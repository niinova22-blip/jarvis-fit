import XCTest
@testable import JarvisCore

final class RepCountingTests: XCTestCase {
    /// Runs frames through the smoother and analyser like the live pipeline does.
    private func run(_ exercise: TrackedExercise, view: CameraView, frames: [PoseFrame]) -> (count: Int, events: [ExerciseEvent], analyzer: any ExerciseAnalyzing) {
        var analyzer = ExerciseAnalyzerFactory.make(exercise, view: view)
        var smoother = PoseSmoother()
        var events: [ExerciseEvent] = []
        for frame in frames {
            let update = analyzer.process(smoother.smooth(frame))
            events.append(contentsOf: update.events)
        }
        return (analyzer.repCount, events, analyzer)
    }

    private let countedExercises: [(TrackedExercise, CameraView)] = [
        (.squat, .side), (.squat, .front), (.pushUp, .side), (.lunge, .side), (.jumpingJack, .front),
        (.bicepsCurl, .front), (.shoulderPress, .front), (.lateralRaise, .front), (.gluteBridge, .side), (.crunch, .side)
    ]

    func testCountsExactRepsForEveryExercise() {
        for (exercise, view) in countedExercises {
            for reps in [1, 5, 12] {
                let period = exercise == .jumpingJack ? 0.9 : 2.2
                let frames = SyntheticPose.sequence(reps: reps, period: period, seed: UInt64(reps),
                                                    pose: SyntheticPose.generator(for: exercise, view: view))
                let result = run(exercise, view: view, frames: frames)
                XCTAssertEqual(result.count, reps, "\(exercise) \(view) expected \(reps) reps")
            }
        }
    }

    func testCountsWithHeavierNoise() {
        for (exercise, view) in countedExercises {
            let frames = SyntheticPose.sequence(reps: 8, period: 2.0, noise: 0.008, seed: 42,
                                                pose: SyntheticPose.generator(for: exercise, view: view))
            XCTAssertEqual(run(exercise, view: view, frames: frames).count, 8, "\(exercise) with noise")
        }
    }

    func testStandingStillCountsNothing() {
        for (exercise, view) in countedExercises {
            let frames = SyntheticPose.sequence(reps: 0, period: 2, restBefore: 6, restAfter: 0, noise: 0.006,
                                                seed: 7, pose: SyntheticPose.generator(for: exercise, view: view))
            XCTAssertEqual(run(exercise, view: view, frames: frames).count, 0, "\(exercise) idle")
        }
    }

    func testShallowSquatsAreNotCountedAndCueDepth() {
        let frames = SyntheticPose.sequence(reps: 4, period: 2.2, depth: 0.6,
                                            pose: SyntheticPose.generator(for: .squat, view: .side))
        let result = run(.squat, view: .side, frames: frames)
        XCTAssertEqual(result.count, 0)
        let partials = result.events.filter { if case .partialRep(.squatTooShallow) = $0 { return true }; return false }
        XCTAssertEqual(partials.count, 4)
    }

    func testFastRepsGetTempoCue() {
        let frames = SyntheticPose.sequence(reps: 5, period: 0.7, pose: SyntheticPose.generator(for: .squat, view: .side))
        let result = run(.squat, view: .side, frames: frames)
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.analyzer.records.allSatisfy { $0.formIssues.contains(.tooFast) })
    }

    func testControlledRepsHaveNoTempoCue() {
        let frames = SyntheticPose.sequence(reps: 3, period: 2.5, pose: SyntheticPose.generator(for: .squat, view: .side))
        let result = run(.squat, view: .side, frames: frames)
        XCTAssertFalse(result.analyzer.records.contains { $0.formIssues.contains(.tooFast) })
    }

    func testPushUpHipSagDetected() {
        let frames = SyntheticPose.sequence(reps: 3, period: 2.2) { SyntheticPose.pushUp($0, sag: 0.08) }
        let result = run(.pushUp, view: .side, frames: frames)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.analyzer.records.allSatisfy { $0.formIssues.contains(.pushUpHipsSag) })
    }

    func testPushUpPikeDetected() {
        let frames = SyntheticPose.sequence(reps: 3, period: 2.2) { SyntheticPose.pushUp($0, sag: -0.08) }
        let result = run(.pushUp, view: .side, frames: frames)
        XCTAssertTrue(result.analyzer.records.allSatisfy { $0.formIssues.contains(.pushUpHipsPike) })
    }

    func testCleanPushUpsHaveNoHipIssues() {
        let frames = SyntheticPose.sequence(reps: 3, period: 2.2) { SyntheticPose.pushUp($0) }
        let result = run(.pushUp, view: .side, frames: frames)
        XCTAssertFalse(result.analyzer.records.contains { $0.formIssues.contains(.pushUpHipsSag) || $0.formIssues.contains(.pushUpHipsPike) })
    }

    func testCurlElbowSwingDetected() {
        let frames = SyntheticPose.sequence(reps: 4, period: 2.2) { SyntheticPose.curl($0, swing: 50) }
        let result = run(.bicepsCurl, view: .front, frames: frames)
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result.analyzer.records.contains { $0.formIssues.contains(.curlElbowSwing) })
    }

    func testLateralRaiseTooHigh() {
        let frames = SyntheticPose.sequence(reps: 3, period: 2.2) { SyntheticPose.lateralRaise($0, peak: 140) }
        let result = run(.lateralRaise, view: .front, frames: frames)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.analyzer.records.allSatisfy { $0.formIssues.contains(.raiseTooHigh) })
    }

    func testSquatFormChecksOnlyInTheirView() {
        // Knees caving is a front-view check and must never fire from a side view.
        let frames = SyntheticPose.sequence(reps: 3, period: 2.2, pose: SyntheticPose.generator(for: .squat, view: .side))
        let result = run(.squat, view: .side, frames: frames)
        XCTAssertFalse(result.analyzer.records.contains { $0.formIssues.contains(.squatKneesCaveIn) })
    }

    func testOcclusionMidRepDoesNotCreatePhantomRep() {
        var frames = SyntheticPose.sequence(reps: 3, period: 2.2, pose: SyntheticPose.generator(for: .squat, view: .side))
        // Remove all joints for 2 seconds in the middle of the second rep.
        for index in frames.indices where frames[index].timestamp > 3.9 && frames[index].timestamp < 5.9 {
            frames[index].keypoints = [:]
        }
        let result = run(.squat, view: .side, frames: frames)
        XCTAssertLessThanOrEqual(result.count, 3)
        XCTAssertGreaterThanOrEqual(result.count, 2)
    }

    func testPlankHoldTimed() {
        let frames = SyntheticPose.sequence(reps: 0, period: 1, restBefore: 10, restAfter: 0) { _ in SyntheticPose.pushUp(0) }
        var analyzer = PlankAnalyzer(view: .side)
        var smoother = PoseSmoother()
        for frame in frames { _ = analyzer.process(smoother.smooth(frame)) }
        XCTAssertEqual(analyzer.holdSeconds, 9.5, accuracy: 0.3)
    }

    func testPlankPausesWhenHipsSag() {
        var frames = SyntheticPose.sequence(reps: 0, period: 1, restBefore: 5, restAfter: 0) { _ in SyntheticPose.pushUp(0) }
        let sagging = SyntheticPose.sequence(reps: 0, period: 1, restBefore: 5, restAfter: 0) { _ in SyntheticPose.pushUp(0, sag: 0.08) }
        frames += sagging.map { PoseFrame(timestamp: $0.timestamp + 5, keypoints: $0.keypoints, aspectRatio: 1) }
        var analyzer = PlankAnalyzer(view: .side)
        var smoother = PoseSmoother()
        var events: [ExerciseEvent] = []
        for frame in frames { events += analyzer.process(smoother.smooth(frame)).events }
        XCTAssertEqual(analyzer.holdSeconds, 5.5, accuracy: 0.8)
        XCTAssertTrue(events.contains(.holdPaused(.plankHipsSag)))
    }

    func testRepCounterRelaxesStartThresholdForLimitedExtension() {
        // User whose standing knee angle only reaches 152° (perspective) must still be counted.
        var counter = RepCounter(config: RepSignalConfig(startThreshold: 160, turnThreshold: 105))
        var t = 0.0
        var count = 0
        for _ in 0..<60 { _ = counter.update(signal: 152, at: t); t += 1.0 / 30 }
        for _ in 0..<5 {
            for i in 0..<60 {
                let value = 152 - (152 - 95) * (1 - cos(2 * .pi * Double(i) / 60)) / 2
                for event in counter.update(signal: value, at: t) { if case .repCompleted = event { count += 1 } }
                t += 1.0 / 30
            }
        }
        XCTAssertEqual(count, 5)
    }
}
