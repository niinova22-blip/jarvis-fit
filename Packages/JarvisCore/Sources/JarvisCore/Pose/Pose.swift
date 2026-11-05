import Foundation

/// The 19 body joints produced by Apple Vision's 2D human body pose request.
public enum Joint: String, CaseIterable, Codable, Sendable {
    case nose, leftEye, rightEye, leftEar, rightEar, neck
    case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
}

/// A 2D point in normalised image coordinates: x to the right, y downwards, both 0...1.
public struct Point2: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static func + (a: Point2, b: Point2) -> Point2 { Point2(a.x + b.x, a.y + b.y) }
    public static func - (a: Point2, b: Point2) -> Point2 { Point2(a.x - b.x, a.y - b.y) }
    public static func * (a: Point2, s: Double) -> Point2 { Point2(a.x * s, a.y * s) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public func distance(to other: Point2) -> Double { (self - other).length }

    public static func midpoint(_ a: Point2, _ b: Point2) -> Point2 { Point2((a.x + b.x) / 2, (a.y + b.y) / 2) }
}

public struct Keypoint: Codable, Hashable, Sendable {
    public var position: Point2
    public var confidence: Double

    public init(_ position: Point2, confidence: Double) {
        self.position = position
        self.confidence = confidence
    }
}

/// One frame of detected body pose.
public struct PoseFrame: Codable, Sendable {
    public var timestamp: TimeInterval
    public var keypoints: [Joint: Keypoint]
    /// Width / height of the source image; used to correct angles for non-square frames.
    public var aspectRatio: Double

    public init(timestamp: TimeInterval, keypoints: [Joint: Keypoint], aspectRatio: Double = 9.0 / 16.0) {
        self.timestamp = timestamp
        self.keypoints = keypoints
        self.aspectRatio = aspectRatio
    }

    public static let minimumConfidence = 0.3

    /// Position in an isotropic space (x scaled by aspect ratio) so angles are geometrically correct.
    public func point(_ joint: Joint, minConfidence: Double = PoseFrame.minimumConfidence) -> Point2? {
        guard let keypoint = keypoints[joint], keypoint.confidence >= minConfidence else { return nil }
        return Point2(keypoint.position.x * aspectRatio, keypoint.position.y)
    }

    /// Raw normalised image position (for overlays and framing checks).
    public func imagePoint(_ joint: Joint, minConfidence: Double = PoseFrame.minimumConfidence) -> Point2? {
        guard let keypoint = keypoints[joint], keypoint.confidence >= minConfidence else { return nil }
        return keypoint.position
    }

    public func confidence(_ joint: Joint) -> Double { keypoints[joint]?.confidence ?? 0 }

    public func isVisible(_ joint: Joint) -> Bool { confidence(joint) >= PoseFrame.minimumConfidence }

    /// Mean confidence over a set of joints.
    public func meanConfidence(_ joints: [Joint]) -> Double {
        guard !joints.isEmpty else { return 0 }
        return joints.reduce(0) { $0 + confidence($1) } / Double(joints.count)
    }
}

public enum Side: String, Codable, Sendable { case left, right }

public extension Joint {
    static func shoulder(_ side: Side) -> Joint { side == .left ? .leftShoulder : .rightShoulder }
    static func elbow(_ side: Side) -> Joint { side == .left ? .leftElbow : .rightElbow }
    static func wrist(_ side: Side) -> Joint { side == .left ? .leftWrist : .rightWrist }
    static func hip(_ side: Side) -> Joint { side == .left ? .leftHip : .rightHip }
    static func knee(_ side: Side) -> Joint { side == .left ? .leftKnee : .rightKnee }
    static func ankle(_ side: Side) -> Joint { side == .left ? .leftAnkle : .rightAnkle }
    static func ear(_ side: Side) -> Joint { side == .left ? .leftEar : .rightEar }
}
