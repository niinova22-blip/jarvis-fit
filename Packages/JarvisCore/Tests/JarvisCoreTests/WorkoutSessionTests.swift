import XCTest
@testable import JarvisCore

final class WorkoutSessionTests: XCTestCase {
    /// Drives the engine with frames and 10 Hz ticks, like the app does.
    private struct Driver {
        var engine: WorkoutSessionEngine
        var time: Double = 0
        var cues: [CoachCue] = []
        var lastTick: Double = 0

        mutating func feed(_ frames: [PoseFrame]) {
            for frame in frames {
                let shifted = PoseFrame(timestamp: time + frame.timestamp, keypoints: frame.keypoints, aspectRatio: frame.aspectRatio)
                cues += engine.process(shifted)
                if shifted.timestamp - lastTick >= 0.1 {
                    cues += engine.tick(shifted.timestamp)
                    lastTick = shifted.timestamp
                }
            }
            time += (frames.last?.timestamp ?? 0) + 1.0 / 30
        }

        mutating func wait(_ seconds: Double, pose: [Joint: Keypoint]? = nil) {
            let end = time + seconds
            while time < end {
                if let pose { cues += engine.process(PoseFrame(timestamp: time, keypoints: pose, aspectRatio: 1)) }
                cues += engine.tick(time)
                time += pose == nil ? 0.1 : 1.0 / 30
            }
        }

        mutating func say(_ command: SessionCommand) { cues += engine.handle(command, at: time) }
    }

    private func standingSquatPose() -> [Joint: Keypoint] { SyntheticPose.squat(0, view: .side) }

    func testHandsFreeWorkoutFromStartToFinish() {
        let plan = LiveWorkoutPlan(title: LocalizedText(tr: "Test", en: "Test"), items: [
            LiveWorkoutItem(exercise: .squat, sets: 2, target: 5, restSeconds: 20),
            LiveWorkoutItem(exercise: .pushUp, sets: 1, target: 4, restSeconds: 30)
        ])
        var d = Driver(engine: WorkoutSessionEngine(plan: plan))
        d.cues += d.engine.start(at: 0)
        XCTAssertEqual(d.engine.phase, .positioning)

        // User walks into frame and stands still → countdown → go.
        d.wait(5, pose: standingSquatPose())
        XCTAssertEqual(d.engine.phase, .active)
        XCTAssertTrue(d.cues.contains(.countdown(3)))
        XCTAssertTrue(d.cues.contains(.go(.squat, set: 1, totalSets: 2, target: 5)))

        // Set 1: five squats → set completes automatically → rest.
        d.feed(SyntheticPose.sequence(reps: 5, period: 2.2, restBefore: 0.5, restAfter: 0.5, pose: SyntheticPose.generator(for: .squat, view: .side)))
        XCTAssertTrue(d.cues.contains(.rep(5)))
        XCTAssertEqual(d.engine.results.count, 1)
        XCTAssertEqual(d.engine.results.first?.reps, 5)
        guard case .resting = d.engine.phase else { return XCTFail("expected rest, got \(d.engine.phase)") }

        // Rest passes by itself; user stays in view → set 2 starts with no touch.
        d.wait(22, pose: standingSquatPose())
        d.wait(5, pose: standingSquatPose())
        XCTAssertEqual(d.engine.phase, .active)
        d.feed(SyntheticPose.sequence(reps: d.engine.currentTarget, period: 2.2, restBefore: 0.5, restAfter: 0.5, pose: SyntheticPose.generator(for: .squat, view: .side)))
        XCTAssertEqual(d.engine.results.count, 2)

        // Rest, then the push-up exercise is introduced, user gets down → set runs.
        d.wait(31)
        XCTAssertTrue(d.cues.contains(.nextExercise(.pushUp)))
        XCTAssertEqual(d.engine.phase, .positioning)
        d.wait(5, pose: SyntheticPose.pushUp(0))
        XCTAssertEqual(d.engine.phase, .active)
        d.feed(SyntheticPose.sequence(reps: 4, period: 2.2, restBefore: 0.5, restAfter: 0.5) { SyntheticPose.pushUp($0) })

        XCTAssertEqual(d.engine.phase, .finished)
        XCTAssertEqual(d.engine.summary?.completed, true)
        XCTAssertEqual(d.engine.results.count, 3)
        XCTAssertTrue(d.cues.contains { if case .workoutComplete = $0 { return true }; return false })
    }

    func testFramingCuesWhenUserNotVisible() {
        let plan = LiveWorkoutPlan(title: LocalizedText(tr: "T", en: "T"), items: [LiveWorkoutItem(exercise: .squat, sets: 1, target: 5, restSeconds: 10)])
        var d = Driver(engine: WorkoutSessionEngine(plan: plan))
        d.cues += d.engine.start(at: 0)
        d.wait(3, pose: [:])
        XCTAssertTrue(d.cues.contains(.framing(.noPerson)))
        XCTAssertEqual(d.engine.phase, .positioning)
    }

    func testVoiceDoneEndsSetEarlyAndAdaptsNextTarget() {
        let plan = LiveWorkoutPlan(title: LocalizedText(tr: "T", en: "T"), items: [LiveWorkoutItem(exercise: .squat, sets: 2, target: 10, restSeconds: 30)])
        var d = Driver(engine: WorkoutSessionEngine(plan: plan))
        d.cues += d.engine.start(at: 0)
        d.wait(5, pose: standingSquatPose())
        d.feed(SyntheticPose.sequence(reps: 6, period: 2.2, restBefore: 0.5, restAfter: 0.3, pose: SyntheticPose.generator(for: .squat, view: .side)))
        d.say(.finishSet)
        XCTAssertEqual(d.engine.results.last?.reps, 6)
        XCTAssertEqual(d.engine.results.last?.endReason, .userSaidDone)
        // 6 of 10 is well below target → next set aims lower (but not under 75% of plan).
        XCTAssertEqual(d.engine.currentTarget, 8)
        XCTAssertTrue(d.cues.contains(.targetAdjusted(newTarget: 8, easier: true)))
    }

    func testInactivityEndsSet() {
        let plan = LiveWorkoutPlan(title: LocalizedText(tr: "T", en: "T"), items: [LiveWorkoutItem(exercise: .squat, sets: 1, target: 10, restSeconds: 30)])
        var d = Driver(engine: WorkoutSessionEngine(plan: plan))
        d.cues += d.engine.start(at: 0)
        d.wait(5, pose: standingSquatPose())
        d.feed(SyntheticPose.sequence(reps: 3, period: 2.2, restBefore: 0.5, restAfter: 0.3, pose: SyntheticPose.generator(for: .squat, view: .side)))
        d.wait(12, pose: standingSquatPose())
        XCTAssertEqual(d.engine.results.first?.endReason, .inactivity)
        XCTAssertEqual(d.engine.phase, .finished)
    }

    func testPauseResumeAndExtendRest() {
        let plan = LiveWorkoutPlan(title: LocalizedText(tr: "T", en: "T"), items: [LiveWorkoutItem(exercise: .squat, sets: 2, target: 3, restSeconds: 30)])
        var d = Driver(engine: WorkoutSessionEngine(plan: plan))
        d.cues += d.engine.start(at: 0)
        d.wait(5, pose: standingSquatPose())
        d.feed(SyntheticPose.sequence(reps: 3, period: 2.2, restBefore: 0.5, restAfter: 0.3, pose: SyntheticPose.generator(for: .squat, view: .side)))
        guard case .resting(let until) = d.engine.phase else { return XCTFail("expected rest") }
        d.say(.tired)
        guard case .resting(let extended) = d.engine.phase else { return XCTFail("expected rest") }
        XCTAssertEqual(extended - until, 30, accuracy: 0.01)
        d.say(.pause)
        XCTAssertEqual(d.engine.phase, .paused)
        d.wait(100)
        XCTAssertEqual(d.engine.phase, .paused, "paused rest must not run out")
        d.say(.resume)
        guard case .resting = d.engine.phase else { return XCTFail("expected rest after resume") }
    }

    func testChestPainStopsWorkoutImmediately() {
        let plan = LiveWorkoutPlan(title: LocalizedText(tr: "T", en: "T"), items: [LiveWorkoutItem(exercise: .squat, sets: 3, target: 10, restSeconds: 30)])
        var d = Driver(engine: WorkoutSessionEngine(plan: plan))
        d.cues += d.engine.start(at: 0)
        d.wait(5, pose: standingSquatPose())
        d.feed(SyntheticPose.sequence(reps: 2, period: 2.2, restBefore: 0.5, restAfter: 0.3, pose: SyntheticPose.generator(for: .squat, view: .side)))
        d.say(.symptom(.chestPain))
        XCTAssertEqual(d.engine.phase, .finished)
        XCTAssertEqual(d.engine.summary?.safetyConcern, .chestPain)
        XCTAssertEqual(d.cues.last, .safetyStop(.chestPain))
    }

    func testPainPausesInsteadOfEnding() {
        let plan = LiveWorkoutPlan(title: LocalizedText(tr: "T", en: "T"), items: [LiveWorkoutItem(exercise: .squat, sets: 3, target: 10, restSeconds: 30)])
        var d = Driver(engine: WorkoutSessionEngine(plan: plan))
        d.cues += d.engine.start(at: 0)
        d.wait(5, pose: standingSquatPose())
        d.say(.symptom(.pain))
        XCTAssertEqual(d.engine.phase, .paused)
    }

    func testPlankSetCompletesAtTargetSeconds() {
        let plan = LiveWorkoutPlan(title: LocalizedText(tr: "T", en: "T"), items: [LiveWorkoutItem(exercise: .plank, sets: 1, target: 20, restSeconds: 30)])
        var d = Driver(engine: WorkoutSessionEngine(plan: plan))
        d.cues += d.engine.start(at: 0)
        d.wait(30, pose: SyntheticPose.pushUp(0))
        XCTAssertEqual(d.engine.phase, .finished)
        XCTAssertEqual(d.engine.results.first?.endReason, .targetReached)
        XCTAssertTrue(d.cues.contains(.holdProgress(seconds: 10, target: 20)))
    }

    func testSkipExerciseMovesOn() {
        let plan = LiveWorkoutPlan(title: LocalizedText(tr: "T", en: "T"), items: [
            LiveWorkoutItem(exercise: .squat, sets: 3, target: 10, restSeconds: 30),
            LiveWorkoutItem(exercise: .jumpingJack, sets: 1, target: 20, restSeconds: 30)])
        var d = Driver(engine: WorkoutSessionEngine(plan: plan))
        d.cues += d.engine.start(at: 0)
        d.say(.skipExercise)
        XCTAssertEqual(d.engine.currentItem?.exercise, .jumpingJack)
        XCTAssertEqual(d.engine.phase, .positioning)
    }

    func testSetAdaptationIncreasesWhenEasy() {
        let result = SetResult(exercise: .squat, setNumber: 1, target: 10, reps: 10, holdSeconds: 0, formIssues: [], partialReps: 0,
                               averageRepDuration: 2, slowdown: 1.0, startedAt: 0, endedAt: 20, endReason: .targetReached)
        XCTAssertEqual(SetAdaptation.nextTarget(after: result, planned: 10), 12)
    }

    func testSetAdaptationKeepsWhenFormIssues() {
        let result = SetResult(exercise: .squat, setNumber: 1, target: 10, reps: 10, holdSeconds: 0, formIssues: [.squatTorsoLean], partialReps: 0,
                               averageRepDuration: 2, slowdown: 1.0, startedAt: 0, endedAt: 20, endReason: .targetReached)
        XCTAssertEqual(SetAdaptation.nextTarget(after: result, planned: 10), 10)
    }

    func testCoachVoiceRendersEveryCueInBothLanguages() {
        let cues: [CoachCue] = [.welcome(exerciseCount: 3), .setup(.squat), .framing(.stepBack), .countdown(3), .countdown(1),
                                .go(.plank, set: 1, totalSets: 2, target: 30), .rep(4), .repsRemaining(3), .holdProgress(seconds: 10, target: 30),
                                .formCue(.squatKneesCaveIn), .partialRep(nil), .setComplete(reps: 10, set: 1, totalSets: 3, timed: false),
                                .restStart(seconds: 60, next: .lunge, nextIsNewExercise: true), .workoutComplete(totalReps: 50, minutes: 20, sets: 6),
                                .safetyStop(.dizziness), .encouragement, .wrongExercise(detected: .lunge, expected: .squat)]
        for language in AppLanguage.allCases {
            for personality in CoachPersonality.allCases {
                var voice = CoachVoice(personality: personality, language: language, userName: "Ali")
                for cue in cues { XCTAssertFalse(voice.text(for: cue).isEmpty, "\(cue) \(language) \(personality)") }
            }
        }
        var tr = CoachVoice(personality: .friendly, language: .turkish)
        XCTAssertTrue(tr.text(for: .safetyStop(.chestPain)).contains("112"))
    }
}
