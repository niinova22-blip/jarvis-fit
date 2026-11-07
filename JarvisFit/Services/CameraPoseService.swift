import Foundation
import AVFoundation
import Vision
import UIKit
import JarvisCore

/// Converts Vision body-pose observations into JarvisCore pose frames.
enum VisionPoseAdapter {
    static let jointMap: [VNHumanBodyPoseObservation.JointName: JarvisCore.Joint] = [
        .nose: .nose, .leftEye: .leftEye, .rightEye: .rightEye, .leftEar: .leftEar, .rightEar: .rightEar, .neck: .neck,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder, .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist, .root: .root, .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee, .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle
    ]

    /// Vision uses a bottom-left origin; JarvisCore uses top-left. `roi` maps points found inside a
    /// zoomed region of interest back to full-image coordinates.
    static func frame(from observation: VNHumanBodyPoseObservation, timestamp: TimeInterval, imageSize: CGSize,
                      roi: CGRect? = nil) -> PoseFrame {
        var keypoints: [JarvisCore.Joint: Keypoint] = [:]
        if let points = try? observation.recognizedPoints(.all) {
            for (name, point) in points {
                guard let joint = jointMap[name] else { continue }
                var location = point.location
                if let roi { location = CGPoint(x: roi.minX + location.x * roi.width, y: roi.minY + location.y * roi.height) }
                keypoints[joint] = Keypoint(Point2(Double(location.x), 1 - Double(location.y)), confidence: Double(point.confidence))
            }
        }
        let aspect = imageSize.height > 0 ? Double(imageSize.width / imageSize.height) : 9.0 / 16.0
        return PoseFrame(timestamp: timestamp, keypoints: keypoints, aspectRatio: aspect)
    }

    /// Picks the largest detected person (closest to the camera).
    static func mainObservation(_ observations: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        observations.max { area($0) < area($1) }
    }

    /// Bounding box of the confident joints (Vision coordinates, bottom-left origin).
    static func bounds(_ observation: VNHumanBodyPoseObservation) -> CGRect? {
        guard let points = try? observation.recognizedPoints(.all).values.filter({ $0.confidence > 0.3 }), points.count >= 4 else { return nil }
        let xs = points.map(\.location.x), ys = points.map(\.location.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func area(_ observation: VNHumanBodyPoseObservation) -> CGFloat {
        guard let points = try? observation.recognizedPoints(.all).values.filter({ $0.confidence > 0.3 }), !points.isEmpty else { return 0 }
        let xs = points.map(\.location.x), ys = points.map(\.location.y)
        return ((xs.max() ?? 0) - (xs.min() ?? 0)) * ((ys.max() ?? 0) - (ys.min() ?? 0))
    }
}

/// Camera capture + on-device body pose detection. Frames are processed off the main thread; the
/// latest pose is delivered to `onPose` on the main thread. Frames that arrive while the previous one
/// is still being analysed are dropped (keeps latency low instead of building a backlog).
final class CameraPoseService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published private(set) var isRunning = false
    @Published private(set) var authorizationDenied = false
    @Published private(set) var imageSize = CGSize(width: 720, height: 1280)
    @Published private(set) var processingFPS: Double = 0
    @Published private(set) var usingFrontCamera = true
    /// Current processing budget (light mode on older devices / heat / Low Power Mode).
    @Published private(set) var budget: ProcessingBudget = .high

    var onPose: ((PoseFrame) -> Void)?

    private let sessionQueue = DispatchQueue(label: "jarvisfit.camera.session")
    private let videoQueue = DispatchQueue(label: "jarvisfit.camera.video", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var busy = false
    private var frameCount = 0
    private var fpsWindowStart = CACurrentMediaTime()
    private let startedMeasuringAt = CACurrentMediaTime()
    private var configured = false
    private var frameIndex = 0
    private var preference: PerformancePreference = .automatic
    private var analyseEvery = 1
    private var measuredFPS: Double?
    /// Zoomed region of interest while the user is far away (small in the image); nil = full frame.
    private var roi: CGRect?
    /// Last person bounds in full-image Vision coordinates.
    private var lastBounds: CGRect?
    /// Whether Vision reports ROI results relative to the ROI (documented behaviour); verified at
    /// runtime against the previous frame before it is trusted, see `resolveROIMapping`.
    private var roiRelative: Bool?
    private var roiVotes = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(thermalChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start(front: Bool, preference: PerformancePreference = .automatic) {
        self.preference = preference
        updateBudget()
        Task {
            let granted = await Self.requestAccess()
            await MainActor.run { self.authorizationDenied = !granted }
            guard granted else { return }
            sessionQueue.async {
                self.configure(front: front)
                if !self.session.isRunning { self.session.startRunning() }
                let running = self.session.isRunning
                DispatchQueue.main.async { self.isRunning = running }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    func switchCamera() {
        let front = !usingFrontCamera
        sessionQueue.async {
            self.configured = false
            self.configure(front: front)
        }
    }

    private func configure(front: Bool) {
        if configured && front == usingFrontCamera { return }
        let budget = currentBudget
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let preset: AVCaptureSession.Preset = budget.resolution >= 1280 ? .hd1280x720 : .vga640x480
        session.sessionPreset = session.canSetSessionPreset(preset) ? preset : .high
        for input in session.inputs { session.removeInput(input) }
        let position: AVCaptureDevice.Position = front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        // ≤ 30 fps is enough for exercise tracking and saves battery.
        applyFrameRate(budget.cameraFPS, to: device)

        if !session.outputs.contains(output) {
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        if let connection = output.connection(with: .video) {
            // Upright portrait buffers; not mirrored so left/right match the user's real body.
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
        }
        configured = true
        DispatchQueue.main.async { self.usingFrontCamera = front }
    }

    private func applyFrameRate(_ fps: Int, to device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains { Double(fps) >= $0.minFrameRate && Double(fps) <= $0.maxFrameRate }
        if supported {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        }
        device.unlockForConfiguration()
    }

    // Accessed from the session/video queues; written on main before (re)configuration.
    private var currentBudget: ProcessingBudget = .high

    private static var thermalLevel: ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .fair
        }
    }

    /// Re-evaluates the budget (start, heat changes, measured throughput).
    private func updateBudget() {
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let newBudget = PerformancePolicy.budget(preference: preference, memoryGB: memoryGB, thermal: Self.thermalLevel,
                                                 lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, measuredFPS: measuredFPS)
        let previous = currentBudget
        currentBudget = newBudget
        analyseEvery = newBudget.analyseEvery
        DispatchQueue.main.async { self.budget = newBudget }
        // Frame rate / resolution changes need a reconfiguration of a running session.
        if configured && (previous.cameraFPS != newBudget.cameraFPS || previous.resolution != newBudget.resolution) {
            let front = usingFrontCamera
            sessionQueue.async {
                self.configured = false
                self.configure(front: front)
            }
        }
    }

    @objc private func thermalChanged() {
        updateBudget()
    }

    /// Region (same aspect as the image) around a person who fills less than ~45% of the image (far away), so
    /// Vision analyses them at a higher effective resolution. nil when the person is close enough.
    static func zoomRegion(for bounds: CGRect) -> CGRect? {
        let size = max(bounds.width, bounds.height) * 1.7
        guard size < 0.75 else { return nil }
        let k = max(size, 0.35)
        let x = min(max(bounds.midX - k / 2, 0), 1 - k)
        let y = min(max(bounds.midY - k / 2, 0), 1 - k)
        return CGRect(x: x, y: y, width: k, height: k)
    }

    /// Decides once (by 3 agreeing frames) whether ROI results are relative to the ROI, by comparing
    /// both interpretations with the person's previous full-frame bounds. Returns the ROI to map with,
    /// or nil to use the points as they are.
    private func resolveROIMapping(_ observation: VNHumanBodyPoseObservation, roi: CGRect) -> CGRect? {
        if let relative = roiRelative, roiVotes >= 3 { return relative ? roi : nil }
        guard let raw = VisionPoseAdapter.bounds(observation), let previous = lastBounds else { return roi }
        let mapped = CGRect(x: roi.minX + raw.minX * roi.width, y: roi.minY + raw.minY * roi.height,
                            width: raw.width * roi.width, height: raw.height * roi.height)
        func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
            hypot(a.midX - b.midX, a.midY - b.midY) + abs(a.height - b.height) + abs(a.width - b.width)
        }
        let relative = distance(mapped, previous) <= distance(raw, previous)
        if relative == roiRelative { roiVotes += 1 } else { roiRelative = relative; roiVotes = 1 }
        return relative ? roi : nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameIndex &+= 1
        if analyseEvery > 1 && frameIndex % analyseEvery != 0 { return }
        guard !busy, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busy = true
        defer { busy = false }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let usedROI = roi
        poseRequest.regionOfInterest = usedROI ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        do {
            try handler.perform([poseRequest])
        } catch {
            roi = nil
            return
        }
        let observations = poseRequest.results ?? []
        let frame: PoseFrame
        if let main = VisionPoseAdapter.mainObservation(observations) {
            let mapping = usedROI.flatMap { resolveROIMapping(main, roi: $0) }
            frame = VisionPoseAdapter.frame(from: main, timestamp: timestamp, imageSize: size, roi: mapping)
            if let raw = VisionPoseAdapter.bounds(main) {
                let full = mapping.map { m in CGRect(x: m.minX + raw.minX * m.width, y: m.minY + raw.minY * m.height,
                                                    width: raw.width * m.width, height: raw.height * m.height) } ?? raw
                lastBounds = full
                roi = Self.zoomRegion(for: full)
            } else {
                roi = nil
            }
        } else {
            // Lost the person inside the zoomed region: search the full frame again.
            roi = nil
            lastBounds = nil
            frame = PoseFrame(timestamp: timestamp, keypoints: [:], aspectRatio: Double(size.width / max(size.height, 1)))
        }
        frameCount += 1
        let now = CACurrentMediaTime()
        var fps: Double?
        if now - fpsWindowStart >= 1 {
            fps = Double(frameCount) / (now - fpsWindowStart)
            frameCount = 0
            fpsWindowStart = now
        }
        // After a few seconds, step down automatically if the device can't keep up.
        if let fps, preference == .automatic, !currentBudget.isLight, measuredFPS == nil, now - startedMeasuringAt > 5 {
            measuredFPS = fps
            if fps < 20 { DispatchQueue.main.async { self.updateBudget() } }
        }
        DispatchQueue.main.async {
            if self.imageSize != size { self.imageSize = size }
            if let fps { self.processingFPS = fps }
            self.onPose?(frame)
        }
    }
}
