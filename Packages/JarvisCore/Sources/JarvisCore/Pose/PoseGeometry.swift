import Foundation

public enum Geometry {
    /// Angle ABC in degrees (at vertex B), 0...180.
    public static func angle(_ a: Point2, _ b: Point2, _ c: Point2) -> Double {
        let ba = a - b
        let bc = c - b
        let denominator = ba.length * bc.length
        guard denominator > 1e-9 else { return 180 }
        let dot: Double = ba.x * bc.x + ba.y * bc.y
        let cosine: Double = max(-1.0, min(1.0, dot / denominator))
        return acos(cosine) * 180.0 / Double.pi
    }

    /// Angle of the vector from `a` to `b` relative to vertical, in degrees (0 = straight up/down).
    public static func angleFromVertical(_ a: Point2, _ b: Point2) -> Double {
        let v = b - a
        guard v.length > 1e-9 else { return 0 }
        return atan2(abs(v.x), abs(v.y)) * 180 / .pi
    }

    /// Angle of the vector from `a` to `b` relative to horizontal, in degrees (0 = level).
    public static func angleFromHorizontal(_ a: Point2, _ b: Point2) -> Double {
        90 - angleFromVertical(a, b)
    }
}

/// How the user is oriented relative to the camera.
public enum CameraView: String, Codable, Sendable {
    case front, side, unknown
}

public enum BodyOrientation: String, Codable, Sendable {
    case standing, horizontal, unknown
}

/// Derived measurements on a pose frame, shared by all exercise analysers.
public struct PoseFeatures: Sendable {
    public let frame: PoseFrame

    public init(_ frame: PoseFrame) { self.frame = frame }

    /// Angle at joint `b` for one body side, nil when any joint is not visible.
    public func angle(_ a: Joint, _ b: Joint, _ c: Joint) -> Double? {
        guard let pa = frame.point(a), let pb = frame.point(b), let pc = frame.point(c) else { return nil }
        return Geometry.angle(pa, pb, pc)
    }

    public func kneeAngle(_ side: Side) -> Double? { angle(.hip(side), .knee(side), .ankle(side)) }
    public func elbowAngle(_ side: Side) -> Double? { angle(.shoulder(side), .elbow(side), .wrist(side)) }
    public func hipAngle(_ side: Side) -> Double? { angle(.shoulder(side), .hip(side), .knee(side)) }
    /// Shoulder abduction: angle between torso (shoulder→hip) and upper arm (shoulder→elbow).
    public func shoulderAbduction(_ side: Side) -> Double? { angle(.hip(side), .shoulder(side), .elbow(side)) }
    /// Arm elevation using the wrist (straight-arm movements like jumping jacks).
    public func armElevation(_ side: Side) -> Double? { angle(.hip(side), .shoulder(side), .wrist(side)) }
    /// Straightness of the body line shoulder–hip–ankle (180 = straight).
    public func bodyLine(_ side: Side) -> Double? { angle(.shoulder(side), .hip(side), .ankle(side)) }

    /// The side with higher landmark confidence for the given joints (for side-view exercises).
    public func bestSide(for joints: (Side) -> [Joint]) -> Side {
        frame.meanConfidence(joints(.left)) >= frame.meanConfidence(joints(.right)) ? .left : .right
    }

    /// Returns the measurement of the more reliable side, or the mean when both are reliable.
    public func bilateral(_ measure: (Side) -> Double?, combine: (Double, Double) -> Double = { ($0 + $1) / 2 }) -> Double? {
        switch (measure(.left), measure(.right)) {
        case let (l?, r?): return combine(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    public var shoulderMid: Point2? {
        guard let l = frame.point(.leftShoulder), let r = frame.point(.rightShoulder) else {
            return frame.point(.leftShoulder) ?? frame.point(.rightShoulder) ?? frame.point(.neck)
        }
        return Point2.midpoint(l, r)
    }

    public var hipMid: Point2? {
        guard let l = frame.point(.leftHip), let r = frame.point(.rightHip) else {
            return frame.point(.leftHip) ?? frame.point(.rightHip) ?? frame.point(.root)
        }
        return Point2.midpoint(l, r)
    }

    public var ankleMid: Point2? {
        guard let l = frame.point(.leftAnkle), let r = frame.point(.rightAnkle) else {
            return frame.point(.leftAnkle) ?? frame.point(.rightAnkle)
        }
        return Point2.midpoint(l, r)
    }

    public var torsoLength: Double? {
        guard let s = shoulderMid, let h = hipMid else { return nil }
        return s.distance(to: h)
    }

    /// Whether the torso is upright or the body is lying/horizontal.
    public var orientation: BodyOrientation {
        guard let s = shoulderMid, let h = hipMid else { return .unknown }
        let torsoTilt = Geometry.angleFromVertical(h, s)
        if torsoTilt < 40 { return .standing }
        if torsoTilt > 55 { return .horizontal }
        return .unknown
    }

    /// Front vs side view, from shoulder width relative to torso length.
    public var view: CameraView {
        guard let torso = torsoLength, torso > 1e-6,
              let l = frame.point(.leftShoulder), let r = frame.point(.rightShoulder) else {
            return .unknown
        }
        // In a horizontal body the shoulders line up along the image vertical in front view.
        let shoulderSpan = l.distance(to: r)
        let ratio = shoulderSpan / torso
        if ratio > 0.45 { return .front }
        if ratio < 0.25 { return .side }
        return .unknown
    }

    /// Torso lean from vertical in degrees (meaningful in side view).
    public var torsoLean: Double? {
        guard let s = shoulderMid, let h = hipMid else { return nil }
        return Geometry.angleFromVertical(h, s)
    }

    /// Distance between knees divided by distance between ankles (front view valgus indicator).
    public var kneeToAnkleWidthRatio: Double? {
        guard let lk = frame.point(.leftKnee), let rk = frame.point(.rightKnee),
              let la = frame.point(.leftAnkle), let ra = frame.point(.rightAnkle) else { return nil }
        let ankleWidth = abs(la.x - ra.x)
        guard ankleWidth > 1e-4 else { return nil }
        return abs(lk.x - rk.x) / ankleWidth
    }

    /// Ankle distance divided by hip width (front view stance width).
    public var stanceWidthRatio: Double? {
        guard let la = frame.point(.leftAnkle), let ra = frame.point(.rightAnkle),
              let lh = frame.point(.leftHip), let rh = frame.point(.rightHip) else { return nil }
        let hipWidth = lh.distance(to: rh)
        guard hipWidth > 1e-4 else { return nil }
        return la.distance(to: ra) / hipWidth
    }
}
