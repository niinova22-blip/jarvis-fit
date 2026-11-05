import XCTest
@testable import JarvisCore

final class PoseRecordingTests: XCTestCase {
    func testFrameRoundTripKeepsJointsAndDropsMissing() {
        var keypoints = SyntheticPose.squat(0.5, view: .side)
        keypoints[.nose] = nil
        let frame = PoseFrame(timestamp: 12.3456789, keypoints: keypoints, aspectRatio: 0.5625)
        let decoded = PoseRecording.decodeFrame(PoseRecording.encodeFrame(frame))
        XCTAssertNil(decoded.keypoints[.nose])
        XCTAssertEqual(decoded.timestamp, 12.3457, accuracy: 0.0001)
        for (joint, kp) in keypoints {
            let d = try! XCTUnwrap(decoded.keypoints[joint])
            XCTAssertEqual(d.position.x, kp.position.x, accuracy: 0.0001)
            XCTAssertEqual(d.position.y, kp.position.y, accuracy: 0.0001)
        }
    }

    func testReplayReproducesCountsAndScoresLabels() throws {
        let squats = SyntheticPose.sequence(reps: 8, period: 2.0, pose: SyntheticPose.generator(for: .squat, view: .side))
        var recorder = PoseRecorder(recording: PoseRecording(device: "test", appVersion: "1", cameraPosition: "front"))
        squats.forEach { recorder.add($0) }
        let set = SetResult(exercise: .squat, setNumber: 1, target: 8, reps: 8, holdSeconds: 0, formIssues: [], partialReps: 0,
                            averageRepDuration: 2, slowdown: nil, startedAt: 0, endedAt: squats.last!.timestamp, endReason: .targetReached)
        recorder.markSets([set], views: [0: .side])
        var recording = recorder.recording
        recording.sets[0].actual = 8

        // JSON round trip, as when exported and loaded on the dev machine.
        let loaded = try PoseRecording.decode(try recording.encoded())
        let outcomes = ReplayEvaluator.evaluate(loaded)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].replayed, 8)
        XCTAssertEqual(outcomes[0].relativeError, 0)
        XCTAssertEqual(ReplayEvaluator.accuracy(outcomes), 1)
    }

    func testRecorderIsBounded() {
        var recorder = PoseRecorder(recording: PoseRecording(device: "t", appVersion: "1", cameraPosition: "back"), maxFrames: 5)
        for i in 0..<10 { recorder.add(PoseFrame(timestamp: Double(i), keypoints: [:])) }
        XCTAssertEqual(recorder.recording.frames.count, 5)
        XCTAssertTrue(recorder.isFull)
    }

    /// Real recordings exported from the app (Settings › Developer › Pose recordings) can be dropped
    /// into Tests/JarvisCoreTests/Fixtures. Labelled sets must be counted within ±1 rep.
    func testRealRecordingFixtures() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }), !files.isEmpty else {
            throw XCTSkip("No real pose recordings in Fixtures/ yet")
        }
        var all: [ReplayEvaluator.SetOutcome] = []
        for file in files {
            let recording = try PoseRecording.decode(Data(contentsOf: file))
            let outcomes = ReplayEvaluator.evaluate(recording)
            for o in outcomes {
                print("[replay] \(file.lastPathComponent) set \(o.index) \(o.exercise.rawValue)/\(o.view.rawValue): replay \(o.replayed), app \(o.counted), actual \(o.actual.map(String.init) ?? "-")")
            }
            all += outcomes
        }
        if let accuracy = ReplayEvaluator.accuracy(all, tolerance: 1) {
            print("[replay] accuracy (±1): \(Int(accuracy * 100))% over \(all.filter { $0.actual != nil }.count) labelled sets")
            XCTAssertGreaterThanOrEqual(accuracy, 0.9)
        }
    }
}

final class ReportTests: XCTestCase {
    let day = 86_400.0
    let weekStart = Date(timeIntervalSince1970: 1_700_000_000)

    func log(_ offsetDays: Double, reps: Int, exercise: TrackedExercise = .squat, planned: String? = nil) -> WorkoutLog {
        let set = SetResult(exercise: exercise, setNumber: 1, target: reps, reps: reps, holdSeconds: 0, formIssues: [], partialReps: 0,
                            averageRepDuration: 2, slowdown: nil, startedAt: 0, endedAt: 600, endReason: .targetReached)
        let summary = WorkoutSummary(title: LocalizedText(tr: "A", en: "A"), sets: [set], startedAt: 0, endedAt: 600, completed: true)
        return WorkoutLog(date: weekStart.addingTimeInterval(offsetDays * day), summary: summary, plannedWorkoutId: planned)
    }

    func testWeeklyReportComparesWeeksAndFindsBests() {
        let profile = UserProfile(availableDays: [1, 3, 5])
        let plan = WorkoutPlanner().makePlan(for: profile)
        let logs = [log(-6, reps: 10), log(-4, reps: 10), log(-13, reps: 8), log(1, reps: 12), log(3, reps: 11)]
        let targets = NutritionCalculator.targets(for: profile)
        let food: [(date: Date, totals: Macros)] = [(weekStart.addingTimeInterval(day), Macros(kcal: 2000, protein: 120, carbs: 200, fat: 60)),
                                                     (weekStart.addingTimeInterval(2 * day), Macros(kcal: 2200, protein: 140, carbs: 220, fat: 70))]
        let weights = [WeightEntry(date: weekStart.addingTimeInterval(-2 * day), kg: 80), WeightEntry(date: weekStart.addingTimeInterval(5 * day), kg: 79.4)]
        let report = WeeklyReport.make(weekStart: weekStart, plan: plan, workouts: logs, nutritionDays: food, targets: targets, weights: weights)
        XCTAssertEqual(report.workoutsDone, 2)
        XCTAssertEqual(report.workoutsPlanned, 3)
        XCTAssertEqual(report.totalReps, 23)
        XCTAssertEqual(report.previousWeekReps, 20)
        XCTAssertEqual(report.personalBests, [.squat])
        XCTAssertEqual(report.averageProteinG, 130)
        XCTAssertEqual(report.weightChangeKg!, -0.6, accuracy: 0.001)
        XCTAssertEqual(report.streakWeeks, 3)
        XCTAssertTrue(report.text.tr.contains("2/3 antrenman"))
        XCTAssertTrue(report.text.tr.contains("%15 daha fazla"))
        XCTAssertTrue(report.text.en.contains("Squat"))
    }

    func testAssistantUsesWeeklyReport() {
        let profile = UserProfile()
        let report = WeeklyReport(weekStart: weekStart, workoutsDone: 1, workoutsPlanned: 3, totalReps: 30, previousWeekReps: 0, activeMinutes: 20,
                                  personalBests: [], averageKcal: nil, averageProteinG: nil, targetKcal: 2000, targetProteinG: 120,
                                  weightChangeKg: nil, streakWeeks: 1)
        let context = AssistantContext(profile: profile, todayWeekday: 3, weeklyReport: report)
        XCTAssertEqual(ResponseComposer.answer(.weeklyProgress, context: context).tr, report.text.tr)
    }

    func testBestSetSeriesAndTrend() {
        let perf = (0..<6).map { ExercisePerformance(exerciseId: "push_up", date: Date(timeIntervalSince1970: Double($0) * day), sets: [8 + $0, 7], targetReps: 10) }
        let series = ProgressAnalytics.bestSetSeries("push_up", performances: perf)
        XCTAssertEqual(series.map(\.value), [8, 9, 10, 11, 12, 13])
        XCTAssertEqual(ProgressAnalytics.trend(series)!, (25.0 - 17.0) / 17.0, accuracy: 0.001)
        XCTAssertEqual(ProgressAnalytics.trackedExerciseIds(perf), ["push_up"])
    }

    func testMissedWorkoutDetectionAndRecommendation() {
        let profile = UserProfile(availableDays: [1, 3, 5])
        let plan = WorkoutPlanner().makePlan(for: profile)
        let monday = plan.workouts.first { $0.weekday == 1 }!
        // Today is Wednesday; Monday's workout wasn't done.
        let missed = MissedWorkoutDetector.missed(plan: plan, workouts: [], today: 3, weekStart: weekStart)
        XCTAssertEqual(missed.map(\.id), [monday.id])
        // Done → not missed. A free workout also covers the slot.
        XCTAssertTrue(MissedWorkoutDetector.missed(plan: plan, workouts: [log(0, reps: 10, planned: monday.id)], today: 3, weekStart: weekStart).isEmpty)
        XCTAssertTrue(MissedWorkoutDetector.missed(plan: plan, workouts: [log(1, reps: 10, planned: "free-squat")], today: 3, weekStart: weekStart).isEmpty)
    }

    func testAdaptiveEngineSuggestsMovingMissedWorkout() {
        let profile = UserProfile(availableDays: [1, 3, 5])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        // A Wednesday 10:00 local time.
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!
        var plan = WorkoutPlanner().makePlan(for: profile, now: wednesday.addingTimeInterval(-30 * day))
        plan.createdAt = wednesday.addingTimeInterval(-3 * day)
        let targets = NutritionCalculator.targets(for: profile)
        let recs = AdaptiveEngine().recommendations(profile: profile, plan: plan, weights: [], workouts: [], nutritionDays: [],
                                                    targets: targets, performances: [], now: wednesday)
        let move = recs.first { if case .rescheduleWorkout = $0.change { return true }; return false }
        XCTAssertNotNil(move)
        if case .rescheduleWorkout(_, let day)? = move?.change {
            XCTAssertFalse(plan.workouts.map(\.weekday).contains(day))
            XCTAssertGreaterThanOrEqual(day, 3)
        }
    }
}

final class PerformanceAndPostureTests: XCTestCase {
    func testPerformancePolicy() {
        XCTAssertEqual(PerformancePolicy.budget(preference: .automatic, memoryGB: 8, thermal: .nominal, lowPowerMode: false), .high)
        XCTAssertEqual(PerformancePolicy.budget(preference: .automatic, memoryGB: 4, thermal: .nominal, lowPowerMode: false), .light)
        XCTAssertEqual(PerformancePolicy.budget(preference: .automatic, memoryGB: 8, thermal: .nominal, lowPowerMode: true), .light)
        XCTAssertEqual(PerformancePolicy.budget(preference: .automatic, memoryGB: 8, thermal: .nominal, lowPowerMode: false, measuredFPS: 14), .light)
        XCTAssertEqual(PerformancePolicy.budget(preference: .high, memoryGB: 4, thermal: .serious, lowPowerMode: false), .light)
        XCTAssertEqual(PerformancePolicy.budget(preference: .high, memoryGB: 8, thermal: .critical, lowPowerMode: false), .minimal)
        // Never below the rate needed to count fast jumping jacks.
        for budget in [ProcessingBudget.high, .light, .minimal] { XCTAssertGreaterThanOrEqual(budget.analysedFPS, 15) }
    }

    func testLightBudgetStillCountsJumpingJacks() {
        // Light mode analyses 15 fps: fast jumping jacks (0.9 s each) must still be counted.
        let frames = SyntheticPose.sequence(reps: 10, period: 0.9, fps: 15, pose: SyntheticPose.generator(for: .jumpingJack, view: .front))
        var analyzer = ExerciseAnalyzerFactory.make(.jumpingJack, view: .front)
        var smoother = PoseSmoother()
        for frame in frames { _ = analyzer.process(smoother.smooth(frame)) }
        XCTAssertEqual(analyzer.repCount, 10)
    }

    func testPostureChanges() {
        let before = PostureReport(shoulderTiltDegrees: 6, hipTiltDegrees: 1, forwardHeadRatio: 0.25)
        let after = PostureReport(shoulderTiltDegrees: 2, hipTiltDegrees: 1.5, forwardHeadRatio: 0.32)
        let changes = after.changes(since: before)
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes[0].en.contains("more level"))
        XCTAssertTrue(changes[1].en.contains("further forward"))
    }
}

final class MotivationTests: XCTestCase {
    func testMotivationPrefersDataAndIsStablePerDay() {
        for personality in CoachPersonality.allCases {
            let a = Motivation.message(personality: personality, dayIndex: 100)
            XCTAssertFalse(a.tr.isEmpty)
            XCTAssertFalse(a.en.isEmpty)
            XCTAssertEqual(a, Motivation.message(personality: personality, dayIndex: 100))
        }
        XCTAssertTrue(Motivation.message(personality: .calm, dayIndex: 1, recentPersonalBest: .pushUp).en.contains("Push-up"))
        XCTAssertTrue(Motivation.message(personality: .calm, dayIndex: 1, streakWeeks: 4).tr.contains("4 haftadır"))
    }
}

final class ConfirmationQuestionTests: XCTestCase {
    func testQuestionsAddExplainableExtras() {
        let rice = FoodDatabase.item("rice")!
        let questions = ConfirmationQuestions.questions(for: rice)
        XCTAssertEqual(questions.count, 1)
        let q = questions[0]
        XCTAssertNotNil(FoodDatabase.item(q.ingredientId))
        // 10 g oil ≈ 88 kcal; two portions double it; "none" adds nothing.
        XCTAssertEqual(q.extraMacros(optionIndex: 2, portions: 1).kcal, 88.4, accuracy: 5)
        XCTAssertEqual(q.extraMacros(optionIndex: 2, portions: 2).kcal, 2 * q.extraMacros(optionIndex: 2, portions: 1).kcal, accuracy: 0.01)
        XCTAssertEqual(q.extraMacros(optionIndex: 0, portions: 1), .zero)
        XCTAssertEqual(ConfirmationQuestions.questions(for: FoodDatabase.item("tea")!).first?.ingredientId, "sugar")
        XCTAssertTrue(ConfirmationQuestions.questions(for: FoodDatabase.item("banana")!).isEmpty)
        // Every referenced food id exists.
        for id in ConfirmationQuestions.cookedInFat.union(ConfirmationQuestions.saladIds).union(ConfirmationQuestions.sweetenable) {
            XCTAssertNotNil(FoodDatabase.item(id), id)
        }
    }
}
