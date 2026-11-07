import XCTest
@testable import JarvisCore

/// Counting must not depend on a fixed phone placement (≈2.5 m, waist height, exact side/front view).
/// Camera changes are simulated on the synthetic skeletons: distance (scale), close-ups that cut
/// joints off, diagonal views (horizontal foreshortening) and low/high phones (vertical squeeze).
final class AnyAngleTests: XCTestCase {
    struct Placement {
        var name: String
        var scale = 1.0
        var squeezeX = 1.0
        var squeezeY = 1.0
        var center = Point2(0.5, 0.5)
    }

    static let placements: [Placement] = [
        Placement(name: "far (~6 m)", scale: 0.3),
        Placement(name: "far, off-centre", scale: 0.35, center: Point2(0.25, 0.6)),
        Placement(name: "close-up, limbs cut off", scale: 1.7),
        Placement(name: "diagonal ~65°", squeezeX: 0.42),
        Placement(name: "phone on the floor / tilted", squeezeY: 0.62),
        Placement(name: "far + diagonal + low", scale: 0.45, squeezeX: 0.5, squeezeY: 0.7),
    ]

    /// Applies a placement; joints that leave the image are dropped like Vision would.
    static func place(_ keypoints: [Joint: Keypoint], _ p: Placement) -> [Joint: Keypoint] {
        var out: [Joint: Keypoint] = [:]
        for (joint, kp) in keypoints {
            let x = p.center.x + (kp.position.x - 0.5) * p.scale * p.squeezeX
            let y = p.center.y + (kp.position.y - 0.5) * p.scale * p.squeezeY
            guard (0...1).contains(x), (0...1).contains(y) else { continue }
            out[joint] = Keypoint(Point2(x, y), confidence: kp.confidence)
        }
        return out
    }

    private func count(_ exercise: TrackedExercise, view: CameraView, frames: [PoseFrame]) -> Int {
        var analyzer = ExerciseAnalyzerFactory.make(exercise, view: view)
        var smoother = PoseSmoother()
        for frame in frames { _ = analyzer.process(smoother.smooth(frame)) }
        return analyzer.repCount
    }

    private let exercises: [(TrackedExercise, CameraView)] = [
        (.squat, .side), (.squat, .front), (.pushUp, .side), (.lunge, .side), (.jumpingJack, .front),
        (.bicepsCurl, .front), (.shoulderPress, .front), (.lateralRaise, .front), (.gluteBridge, .side), (.crunch, .side)
    ]

    func testCountsFromAnyPlacement() {
        for placement in Self.placements {
            for (exercise, view) in exercises {
                let period = exercise == .jumpingJack ? 0.9 : 2.2
                let generator = SyntheticPose.generator(for: exercise, view: view)
                // Noise scales with the person's size in the image (pixel noise on a smaller body).
                let frames = SyntheticPose.sequence(reps: 6, period: period, noise: 0.003 * max(placement.scale, 0.5), seed: 7) {
                    Self.place(generator($0), placement)
                }
                XCTAssertEqual(count(exercise, view: view, frames: frames), 6, "\(exercise) \(view) — \(placement.name)")
            }
        }
    }

    /// Head-on push-ups (phone on the floor in front of the hands): the elbow angle is hidden by
    /// foreshortening and the feet are occluded, so only the shoulder drop is visible.
    func testHeadOnPushUps() {
        func headOn(_ p: Double) -> [Joint: Keypoint] {
            let shoulderY = 0.55 + p * 0.12
            let elbowOut = 0.04 + p * 0.07
            var points: [Joint: Point2] = [
                .nose: Point2(0.5, shoulderY - 0.06), .neck: Point2(0.5, shoulderY - 0.01),
                .leftShoulder: Point2(0.59, shoulderY), .rightShoulder: Point2(0.41, shoulderY),
                .leftWrist: Point2(0.62, 0.8), .rightWrist: Point2(0.38, 0.8),
                .leftHip: Point2(0.55, shoulderY - 0.03), .rightHip: Point2(0.45, shoulderY - 0.03),
            ]
            points[.leftElbow] = Point2(0.6 + elbowOut, (shoulderY + 0.8) / 2)
            points[.rightElbow] = Point2(0.4 - elbowOut, (shoulderY + 0.8) / 2)
            return SyntheticPose.keypoints(points)
        }
        let frames = SyntheticPose.sequence(reps: 8, period: 1.8, pose: headOn)
        XCTAssertEqual(count(.pushUp, view: .front, frames: frames), 8)
    }

    func testStandingStillIsNotCountedAnywhere() {
        for placement in Self.placements {
            for (exercise, view) in exercises {
                let generator = SyntheticPose.generator(for: exercise, view: view)
                let frames = SyntheticPose.sequence(reps: 0, period: 2, restBefore: 6, restAfter: 6, noise: 0.006, seed: 3) {
                    Self.place(generator($0), placement)
                }
                XCTAssertEqual(count(exercise, view: view, frames: frames), 0, "\(exercise) — \(placement.name)")
            }
        }
    }

    /// Standing up, getting down into the push-up position and then doing push-ups must count only
    /// the push-ups, not the transition.
    func testGettingIntoPositionIsNotARep() {
        var frames: [PoseFrame] = []
        var t = 0.0
        // Standing (shoulders high), then 1.2 s transition down to the plank, then push-ups.
        let standing = SyntheticPose.squat(0, view: .front)
        for _ in 0..<45 { frames.append(PoseFrame(timestamp: t, keypoints: standing, aspectRatio: 1)); t += 1 / 30.0 }
        let plank = SyntheticPose.pushUp(0)
        for i in 0..<36 {
            let k = Double(i) / 35
            var mixed: [Joint: Keypoint] = [:]
            for (joint, a) in standing {
                guard let b = plank[joint] else { continue }
                mixed[joint] = Keypoint(Point2(a.position.x + (b.position.x - a.position.x) * k,
                                               a.position.y + (b.position.y - a.position.y) * k), confidence: 0.9)
            }
            frames.append(PoseFrame(timestamp: t, keypoints: mixed, aspectRatio: 1)); t += 1 / 30.0
        }
        let pushUps = SyntheticPose.sequence(reps: 5, period: 2.0, restBefore: 1, pose: { SyntheticPose.pushUp($0) })
        frames += pushUps.map { PoseFrame(timestamp: $0.timestamp + t, keypoints: $0.keypoints, aspectRatio: 1) }
        XCTAssertEqual(count(.pushUp, view: .side, frames: frames), 5)
    }

    func testAdaptiveCounterLearnsUserRange() {
        var counter = AdaptiveRepCounter(direction: 1, minAmplitude: 0.2)
        var t = 0.0
        func run(depth: Double, reps: Int) -> Int {
            var n = 0
            for _ in 0..<(reps * 60) {
                let phase = (t.truncatingRemainder(dividingBy: 2)) / 2
                let v = 1 + depth * (1 - cos(2 * .pi * phase)) / 2
                for case .repCompleted in counter.update(signal: v, scale: 1, at: t) { n += 1 }
                t += 1 / 30
            }
            return n
        }
        XCTAssertEqual(run(depth: 0.8, reps: 4), 4)
        // After deep reps, quarter-depth movements are partial reps, not full ones.
        XCTAssertEqual(run(depth: 0.25, reps: 3), 0)
        XCTAssertGreaterThan(counter.partials, 0)
    }
}
