import Foundation
import Vision
import UIKit
import CoreImage
import JarvisCore

/// On-device food photo classification with Apple's built-in image classifier
/// (`VNClassifyImageRequest`). It recognises general categories ("pizza", "salad", "egg"…), not
/// recipes or portion sizes, so the app always asks the user to confirm items and amounts.
enum FoodPhotoAnalyzer {
    struct Result {
        var candidates: [(item: FoodItem, confidence: Double)]
        var rawLabels: [(identifier: String, confidence: Double)]
    }

    static func analyze(_ image: UIImage) async -> Result {
        guard let cgImage = image.cgImage else { return Result(candidates: [], rawLabels: []) }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do { try handler.perform([request]) } catch { return Result(candidates: [], rawLabels: []) }
            let labels = (request.results ?? [])
                .filter { $0.confidence > 0.05 }
                .prefix(40)
                .map { (identifier: $0.identifier, confidence: Double($0.confidence)) }
            let candidates = FoodDatabase.candidates(forVisionLabels: Array(labels))
            return Result(candidates: Array(candidates.prefix(6)), rawLabels: Array(labels))
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Fit Check analysis of a still photo: person segmentation mask + body pose landmarks.
enum BodyScanAnalyzer {
    struct Output {
        var mask: SilhouetteMask
        var landmarks: ScanLandmarks
        var pose: PoseFrame
    }

    enum ScanError: Error { case noPerson, noPose, failed }

    static func analyze(_ image: UIImage, front: Bool) async throws -> Output {
        guard let cgImage = image.cgImage else { throw ScanError.failed }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            let segmentation = VNGeneratePersonSegmentationRequest()
            segmentation.qualityLevel = .accurate
            segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let pose = VNDetectHumanBodyPoseRequest()
            try handler.perform([segmentation, pose])
            guard let maskBuffer = segmentation.results?.first?.pixelBuffer else { throw ScanError.noPerson }
            guard let observation = VisionPoseAdapter.mainObservation(pose.results ?? []) else { throw ScanError.noPose }

            let mask = Self.silhouette(from: maskBuffer)
            // Image size after orientation correction.
            let swapped = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
            let imageSize = swapped ? CGSize(width: cgImage.height, height: cgImage.width) : CGSize(width: cgImage.width, height: cgImage.height)
            let frame = VisionPoseAdapter.frame(from: observation, timestamp: 0, imageSize: imageSize)
            guard let landmarks = Self.landmarks(frame: frame, mask: mask, front: front) else { throw ScanError.noPose }
            return Output(mask: mask, landmarks: landmarks, pose: frame)
        }.value
    }

    /// Converts the segmentation buffer to a binary mask (threshold 50%).
    static func silhouette(from buffer: CVPixelBuffer) -> SilhouetteMask {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var pixels = [UInt8](repeating: 0, count: width * height)
        if let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) {
            for y in 0..<height {
                let row = base + y * rowBytes
                for x in 0..<width { pixels[y * width + x] = row[x] > 127 ? 1 : 0 }
            }
        }
        return SilhouetteMask(width: width, height: height, pixels: pixels)
    }

    static func landmarks(frame: PoseFrame, mask: SilhouetteMask, front: Bool) -> ScanLandmarks? {
        func px(_ joint: JarvisCore.Joint) -> (x: Double, y: Double)? {
            guard let p = frame.imagePoint(joint, minConfidence: 0.2) else { return nil }
            return (p.x * Double(mask.width), p.y * Double(mask.height))
        }
        let shoulders = [px(.leftShoulder), px(.rightShoulder)].compactMap { $0 }
        let hips = [px(.leftHip), px(.rightHip)].compactMap { $0 }
        let knees = [px(.leftKnee), px(.rightKnee)].compactMap { $0 }
        guard !shoulders.isEmpty, !hips.isEmpty, !knees.isEmpty else { return nil }
        let shoulderY = shoulders.map(\.y).reduce(0, +) / Double(shoulders.count)
        let hipY = hips.map(\.y).reduce(0, +) / Double(hips.count)
        let kneeY = knees.map(\.y).reduce(0, +) / Double(knees.count)
        let centerX = (shoulders + hips).map(\.x).reduce(0, +) / Double(shoulders.count + hips.count)
        var thighX: Double?
        var arm: (x: Double, y: Double)?
        if front {
            if let hip = px(.leftHip), let knee = px(.leftKnee) { thighX = hip.x + (knee.x - hip.x) * 0.3 }
            if let s = px(.leftShoulder), let e = px(.leftElbow) { arm = ((s.x + e.x) / 2, (s.y + e.y) / 2) }
        }
        return ScanLandmarks(shoulderY: shoulderY, hipY: hipY, kneeY: kneeY, centerX: centerX, thighX: thighX, upperArmPoint: arm)
    }
}
