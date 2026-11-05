import Foundation
@testable import JarvisCore

/// Deterministic pseudo-random generator for reproducible noise.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }

    /// Approximately normal noise (sum of uniforms).
    mutating func gaussian(_ sigma: Double) -> Double {
        var sum = 0.0
        for _ in 0..<6 { sum += next() }
        return (sum - 3) * sigma * 1.41
    }
}

/// Generates 2D skeletons for exercises from a movement progress value p (0 = start, 1 = turn).
/// Geometry is simplified but anatomically proportioned (normalised to a ~0.8 tall body).
enum SyntheticPose {
    static let torso = 0.26, thigh = 0.22, shin = 0.22, upperArm = 0.15, forearm = 0.14
    static let shoulderHalf = 0.09, hipHalf = 0.06

    static func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }

    static func keypoints(_ points: [Joint: Point2], farSide: Side? = nil) -> [Joint: Keypoint] {
        var result: [Joint: Keypoint] = [:]
        for (joint, point) in points {
            let isFar: Bool
            if let farSide {
                isFar = joint.rawValue.hasPrefix(farSide.rawValue)
            } else {
                isFar = false
            }
            result[joint] = Keypoint(point, confidence: isFar ? 0.5 : 0.9)
        }
        return result
    }

    /// Side view standing leg chain. Returns ankle, knee, hip for a given knee angle.
    static func legSide(ankle: Point2, kneeAngle: Double, forward: Double = 1) -> (knee: Point2, hip: Point2) {
        let total = 180 - kneeAngle
        // Shin tilts forward up to ~35°; the rest of the flexion comes from the thigh.
        let aS = rad(min(total * 0.4, 35)), aT = rad(total - min(total * 0.4, 35))
        let knee = Point2(ankle.x + forward * shin * sin(aS), ankle.y - shin * cos(aS))
        let hip = Point2(knee.x - forward * thigh * sin(aT), knee.y - thigh * cos(aT))
        return (knee, hip)
    }

    static func squat(_ p: Double, view: CameraView) -> [Joint: Keypoint] {
        let kneeAngle = 175 - p * 100
        let (knee, hip) = legSide(ankle: Point2(0.5, 0.9), kneeAngle: kneeAngle)
        let lean = rad(10 + p * 30)
        let shoulder = Point2(hip.x + torso * sin(lean), hip.y - torso * cos(lean))
        let wrist = Point2(shoulder.x + 0.2, shoulder.y + 0.02)
        let elbow = Point2.midpoint(shoulder, wrist)
        if view == .side {
            let o = 0.004
            return keypoints([
                .nose: Point2(shoulder.x + 0.03, shoulder.y - 0.1), .neck: Point2(shoulder.x, shoulder.y - 0.02),
                .leftShoulder: shoulder, .rightShoulder: Point2(shoulder.x + o, shoulder.y),
                .leftElbow: elbow, .rightElbow: Point2(elbow.x + o, elbow.y),
                .leftWrist: wrist, .rightWrist: Point2(wrist.x + o, wrist.y),
                .leftHip: hip, .rightHip: Point2(hip.x + o, hip.y), .root: hip,
                .leftKnee: knee, .rightKnee: Point2(knee.x + o, knee.y),
                .leftAnkle: Point2(0.5, 0.9), .rightAnkle: Point2(0.5 + o, 0.9)
            ], farSide: .right)
        }
        // Front view: same vertical geometry, joints spread horizontally.
        let cx = 0.5
        func mirror(_ y: Double, _ half: Double) -> (Point2, Point2) { (Point2(cx + half, y), Point2(cx - half, y)) }
        let (ls, rs) = mirror(shoulder.y, shoulderHalf)
        let (lh, rh) = mirror(hip.y, hipHalf)
        let (lk, rk) = mirror(knee.y, hipHalf + 0.02 + p * 0.02)
        let (la, ra) = mirror(0.9, hipHalf + 0.02)
        let (le, re) = mirror(elbow.y, shoulderHalf + 0.02)
        let (lw, rw) = mirror(wrist.y, shoulderHalf - 0.02)
        return keypoints([
            .nose: Point2(cx, shoulder.y - 0.1), .neck: Point2(cx, shoulder.y),
            .leftShoulder: ls, .rightShoulder: rs, .leftElbow: le, .rightElbow: re, .leftWrist: lw, .rightWrist: rw,
            .leftHip: lh, .rightHip: rh, .root: Point2(cx, hip.y), .leftKnee: lk, .rightKnee: rk, .leftAnkle: la, .rightAnkle: ra
        ])
    }

    static func lunge(_ p: Double) -> [Joint: Keypoint] {
        let frontAnkle = Point2(0.62, 0.9)
        let frontKneeAngle = 170 - p * 85
        let (fk, hip) = legSide(ankle: frontAnkle, kneeAngle: frontKneeAngle)
        // Back leg: knee drops behind the hip.
        let backKnee = Point2(hip.x - 0.12, hip.y + thigh * 0.9)
        let backAnkle = Point2(backKnee.x - 0.18, 0.9)
        let shoulder = Point2(hip.x + 0.02, hip.y - torso)
        return keypoints([
            .nose: Point2(shoulder.x + 0.02, shoulder.y - 0.1), .neck: shoulder,
            .leftShoulder: shoulder, .rightShoulder: Point2(shoulder.x + 0.004, shoulder.y),
            .leftElbow: Point2(shoulder.x, shoulder.y + 0.13), .rightElbow: Point2(shoulder.x, shoulder.y + 0.13),
            .leftWrist: Point2(shoulder.x, shoulder.y + 0.26), .rightWrist: Point2(shoulder.x, shoulder.y + 0.26),
            .leftHip: hip, .rightHip: Point2(hip.x + 0.004, hip.y), .root: hip,
            .leftKnee: fk, .leftAnkle: frontAnkle, .rightKnee: backKnee, .rightAnkle: backAnkle
        ])
    }

    /// Side-view push-up / plank. `sag` moves the hips down (+) or up (−) off the straight line.
    static func pushUp(_ p: Double, sag: Double = 0) -> [Joint: Keypoint] {
        let elbowAngle = 170 - p * 90
        let floor = 0.85
        let wrist = Point2(0.3, floor)
        let h = (upperArm * upperArm + forearm * forearm - 2 * upperArm * forearm * cos(rad(elbowAngle))).squareRoot()
        let shoulder = Point2(0.3, floor - h)
        // Elbow from triangle shoulder–elbow–wrist, bent towards the feet.
        let cosAtShoulder = (upperArm * upperArm + h * h - forearm * forearm) / (2 * upperArm * h)
        let angleAtShoulder = acos(max(-1, min(1, cosAtShoulder)))
        let elbow = Point2(shoulder.x + upperArm * sin(angleAtShoulder), shoulder.y + upperArm * cos(angleAtShoulder))
        let ankle = Point2(0.95, floor - 0.02)
        let hipBase = Point2(shoulder.x + (ankle.x - shoulder.x) * 0.45, shoulder.y + (ankle.y - shoulder.y) * 0.45)
        let hip = Point2(hipBase.x, hipBase.y + sag)
        let knee = Point2.midpoint(hip, ankle)
        let o = 0.004
        return keypoints([
            .nose: Point2(shoulder.x - 0.08, shoulder.y + 0.01), .neck: Point2(shoulder.x - 0.02, shoulder.y),
            .leftShoulder: shoulder, .rightShoulder: Point2(shoulder.x, shoulder.y + o),
            .leftElbow: elbow, .rightElbow: Point2(elbow.x, elbow.y + o),
            .leftWrist: wrist, .rightWrist: Point2(wrist.x, wrist.y - o),
            .leftHip: hip, .rightHip: Point2(hip.x, hip.y + o), .root: hip,
            .leftKnee: knee, .rightKnee: Point2(knee.x, knee.y + o),
            .leftAnkle: ankle, .rightAnkle: Point2(ankle.x, ankle.y - o)
        ], farSide: .right)
    }

    static func standingFront(shoulderY: Double = 0.3, armLeft: (elbow: Point2, wrist: Point2)? = nil,
                              armRight: (elbow: Point2, wrist: Point2)? = nil, ankleSpread: Double = hipHalf + 0.01) -> [Joint: Point2] {
        let cx = 0.5
        let hipY = shoulderY + torso
        let kneeY = hipY + thigh, ankleY = kneeY + shin
        var points: [Joint: Point2] = [
            .nose: Point2(cx, shoulderY - 0.1), .neck: Point2(cx, shoulderY),
            .leftShoulder: Point2(cx + shoulderHalf, shoulderY), .rightShoulder: Point2(cx - shoulderHalf, shoulderY),
            .leftHip: Point2(cx + hipHalf, hipY), .rightHip: Point2(cx - hipHalf, hipY), .root: Point2(cx, hipY),
            .leftKnee: Point2(cx + (hipHalf + ankleSpread) / 2, kneeY), .rightKnee: Point2(cx - (hipHalf + ankleSpread) / 2, kneeY),
            .leftAnkle: Point2(cx + ankleSpread, ankleY), .rightAnkle: Point2(cx - ankleSpread, ankleY),
            .leftElbow: Point2(cx + shoulderHalf + 0.01, shoulderY + upperArm),
            .rightElbow: Point2(cx - shoulderHalf - 0.01, shoulderY + upperArm),
            .leftWrist: Point2(cx + shoulderHalf + 0.015, shoulderY + upperArm + forearm),
            .rightWrist: Point2(cx - shoulderHalf - 0.015, shoulderY + upperArm + forearm)
        ]
        if let armLeft { points[.leftElbow] = armLeft.elbow; points[.leftWrist] = armLeft.wrist }
        if let armRight { points[.rightElbow] = armRight.elbow; points[.rightWrist] = armRight.wrist }
        return points
    }

    /// Straight arm raised sideways by `degrees` from hanging (0) to overhead (180).
    static func straightArm(shoulder: Point2, degrees: Double, outward: Double) -> (elbow: Point2, wrist: Point2) {
        let a = rad(degrees)
        let dir = Point2(outward * sin(a), cos(a))
        return (shoulder + dir * upperArm, shoulder + dir * (upperArm + forearm))
    }

    static func jumpingJack(_ p: Double) -> [Joint: Keypoint] {
        let deg = 20 + p * 150
        let ls = Point2(0.5 + shoulderHalf, 0.3), rs = Point2(0.5 - shoulderHalf, 0.3)
        return keypoints(standingFront(armLeft: straightArm(shoulder: ls, degrees: deg, outward: 1),
                                       armRight: straightArm(shoulder: rs, degrees: deg, outward: -1),
                                       ankleSpread: hipHalf + 0.01 + p * 0.12))
    }

    static func lateralRaise(_ p: Double, peak: Double = 90) -> [Joint: Keypoint] {
        let deg = 15 + p * (peak - 15)
        let ls = Point2(0.5 + shoulderHalf, 0.3), rs = Point2(0.5 - shoulderHalf, 0.3)
        return keypoints(standingFront(armLeft: straightArm(shoulder: ls, degrees: deg, outward: 1),
                                       armRight: straightArm(shoulder: rs, degrees: deg, outward: -1)))
    }

    /// Curl in the image plane: upper arm hangs, forearm rotates up. `swing` tilts the upper arm.
    static func curl(_ p: Double, swing: Double = 0) -> [Joint: Keypoint] {
        let elbowAngle = 170 - p * 120
        func arm(_ shoulder: Point2, outward: Double) -> (elbow: Point2, wrist: Point2) {
            let s = rad(swing * p)
            let elbow = Point2(shoulder.x + outward * 0.01 + upperArm * sin(s), shoulder.y + upperArm * cos(s))
            let fore = rad(180 - elbowAngle) + s
            let wrist = Point2(elbow.x + forearm * sin(fore) * 0.6 * outward, elbow.y + forearm * cos(fore))
            return (elbow, wrist)
        }
        let ls = Point2(0.5 + shoulderHalf, 0.3), rs = Point2(0.5 - shoulderHalf, 0.3)
        return keypoints(standingFront(armLeft: arm(ls, outward: 1), armRight: arm(rs, outward: -1)))
    }

    static func shoulderPress(_ p: Double) -> [Joint: Keypoint] {
        // Elbow elevation above horizontal 0°→75°, elbow angle 85°→170°.
        let elevation = rad(p * 75)
        let elbowAngle = 85 + p * 85
        func arm(_ shoulder: Point2, outward: Double) -> (elbow: Point2, wrist: Point2) {
            let elbow = Point2(shoulder.x + outward * upperArm * cos(elevation), shoulder.y - upperArm * sin(elevation))
            // Forearm direction: rotate elbow→shoulder vector so the arm opens upwards.
            let back = Point2(shoulder.x - elbow.x, shoulder.y - elbow.y) * (1 / upperArm)
            let r = rad(elbowAngle) * outward
            let dir = Point2(back.x * cos(r) - back.y * sin(r), back.x * sin(r) + back.y * cos(r))
            let wristA = elbow + dir * forearm
            let r2 = -r
            let dir2 = Point2(back.x * cos(r2) - back.y * sin(r2), back.x * sin(r2) + back.y * cos(r2))
            let wristB = elbow + dir2 * forearm
            return (elbow, wristA.y < wristB.y ? wristA : wristB)
        }
        let ls = Point2(0.5 + shoulderHalf, 0.3), rs = Point2(0.5 - shoulderHalf, 0.3)
        return keypoints(standingFront(armLeft: arm(ls, outward: 1), armRight: arm(rs, outward: -1)))
    }

    /// Supine side view with bent knees. Glute bridge raises the hips; crunch lifts the shoulders.
    static func supine(hipLift: Double, shoulderLift: Double) -> [Joint: Keypoint] {
        let floor = 0.86
        let ankle = Point2(0.78, floor)
        let knee = Point2(0.66, 0.60)
        let hip = Point2(0.46, floor - 0.02 - hipLift)
        let toShoulder = rad(shoulderLift)
        // Shoulders stay on the floor in a bridge; the torso tilts as the hip rises.
        let shoulder: Point2
        if shoulderLift > 0 {
            shoulder = Point2(hip.x - torso * cos(toShoulder), hip.y - torso * sin(toShoulder))
        } else {
            let dy = floor - 0.02 - hip.y
            shoulder = Point2(hip.x - (torso * torso - dy * dy).squareRoot(), floor - 0.02)
        }
        let o = 0.004
        return keypoints([
            .nose: Point2(shoulder.x - 0.08, shoulder.y - 0.02), .neck: Point2(shoulder.x - 0.02, shoulder.y),
            .leftShoulder: shoulder, .rightShoulder: Point2(shoulder.x, shoulder.y + o),
            .leftElbow: Point2(shoulder.x + 0.1, floor - 0.01), .rightElbow: Point2(shoulder.x + 0.1, floor - 0.01 + o),
            .leftWrist: Point2(shoulder.x + 0.22, floor - 0.01), .rightWrist: Point2(shoulder.x + 0.22, floor - 0.01 + o),
            .leftHip: hip, .rightHip: Point2(hip.x, hip.y + o), .root: hip,
            .leftKnee: knee, .rightKnee: Point2(knee.x, knee.y + o),
            .leftAnkle: ankle, .rightAnkle: Point2(ankle.x, ankle.y + o)
        ], farSide: .right)
    }

    static func gluteBridge(_ p: Double) -> [Joint: Keypoint] { supine(hipLift: p * 0.15, shoulderLift: 0) }
    static func crunch(_ p: Double) -> [Joint: Keypoint] { supine(hipLift: 0, shoulderLift: p * 40) }

    static func generator(for exercise: TrackedExercise, view: CameraView) -> (Double) -> [Joint: Keypoint] {
        switch exercise {
        case .squat: return { squat($0, view: view) }
        case .pushUp: return { pushUp($0) }
        case .lunge: return { lunge($0) }
        case .jumpingJack: return { jumpingJack($0) }
        case .plank: return { _ in pushUp(0) }
        case .bicepsCurl: return { curl($0) }
        case .shoulderPress: return { shoulderPress($0) }
        case .lateralRaise: return { lateralRaise($0) }
        case .gluteBridge: return { gluteBridge($0) }
        case .crunch: return { crunch($0) }
        }
    }

    /// A sequence of frames: `reps` cycles of `period` seconds with optional rest before/after.
    static func sequence(reps: Int, period: Double, fps: Double = 30, restBefore: Double = 1.5,
                         restAfter: Double = 1.5, depth: Double = 1, noise: Double = 0.003, seed: UInt64 = 1,
                         pose: (Double) -> [Joint: Keypoint]) -> [PoseFrame] {
        var random = SeededRandom(seed: seed)
        var frames: [PoseFrame] = []
        let total = restBefore + Double(reps) * period + restAfter
        var t = 0.0
        while t < total {
            var p = 0.0
            if t >= restBefore && t < restBefore + Double(reps) * period {
                let phase = (t - restBefore) / period
                p = depth * (1 - cos(2 * .pi * phase)) / 2
            }
            var keypoints = pose(p)
            for (joint, kp) in keypoints {
                keypoints[joint] = Keypoint(Point2(kp.position.x + random.gaussian(noise), kp.position.y + random.gaussian(noise)),
                                            confidence: kp.confidence)
            }
            frames.append(PoseFrame(timestamp: t, keypoints: keypoints, aspectRatio: 1))
            t += 1 / fps
        }
        return frames
    }
}
