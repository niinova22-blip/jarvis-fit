import Foundation
import AVFoundation
import Vision
import UIKit
import JarvisCore

/// Converts Vision body-pose observations into JarvisCore pose frames.
enum VisionPoseAdapter {
    static let jointMap: [VNHumanBodyPoseObservation.JointName: Joint] = [
        .nose: .nose, .leftEye: .leftEye, .rightEye: .rightEye, .leftEar: .leftEar, .rightEar: .rightEar, .neck: .neck,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder, .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist, .root: .root, .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee, .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle
    ]

    /// Vision uses a bottom-left origin; JarvisCore uses top-left.
    static func frame(from observation: VNHumanBodyPoseObservation, timestamp: TimeInterval, imageSize: CGSize) -> PoseFrame {
        var keypoints: [Joint: Keypoint] = [:]
        if let points = try? observation.recognizedPoints(.all) {
            for (name, point) in points {
                guard let joint = jointMap[name] else { continue }
                keypoints[joint] = Keypoint(Point2(Double(point.location.x), 1 - Double(point.location.y)), confidence: Double(point.confidence))
            }
        }
        let aspect = imageSize.height > 0 ? Double(imageSize.width / imageSize.height) : 9.0 / 16.0
        return PoseFrame(timestamp: timestamp, keypoints: keypoints, aspectRatio: aspect)
    }

    /// Picks the largest detected person (closest to the camera).
    static func mainObservation(_ observations: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        observations.max { area($0) < area($1) }
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

    var onPose: ((PoseFrame) -> Void)?

    private let sessionQueue = DispatchQueue(label: "jarvisfit.camera.session")
    private let videoQueue = DispatchQueue(label: "jarvisfit.camera.video", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var busy = false
    private var frameCount = 0
    private var fpsWindowStart = CACurrentMediaTime()
    private var configured = false
    private var thermalThrottle = false
    private var skip = false

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

    func start(front: Bool) {
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
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        for input in session.inputs { session.removeInput(input) }
        let position: AVCaptureDevice.Position = front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        // 30 fps is enough for exercise tracking and saves battery.
        try? device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        device.unlockForConfiguration()

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

    @objc private func thermalChanged() {
        let state = ProcessInfo.processInfo.thermalState
        thermalThrottle = state == .serious || state == .critical
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Under thermal pressure analyse every other frame (15 fps).
        if thermalThrottle {
            skip.toggle()
            if skip { return }
        }
        guard !busy, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busy = true
        defer { busy = false }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([poseRequest])
        } catch {
            return
        }
        let observations = poseRequest.results ?? []
        let frame: PoseFrame
        if let main = VisionPoseAdapter.mainObservation(observations) {
            frame = VisionPoseAdapter.frame(from: main, timestamp: timestamp, imageSize: size)
        } else {
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
        DispatchQueue.main.async {
            if self.imageSize != size { self.imageSize = size }
            if let fps { self.processingFPS = fps }
            self.onPose?(frame)
        }
    }
}
