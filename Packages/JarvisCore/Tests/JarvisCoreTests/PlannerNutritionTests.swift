import XCTest
@testable import JarvisCore

final class PlannerTests: XCTestCase {
    let planner = WorkoutPlanner()

    func testPlanUsesAvailableDaysAndEquipment() {
        let profile = UserProfile(goal: .muscular, experience: .intermediate, equipment: [], availableDays: [1, 3, 5])
        let plan = planner.makePlan(for: profile)
        XCTAssertEqual(plan.workouts.map(\.weekday), [1, 3, 5])
        for workout in plan.workouts {
            XCTAssertFalse(workout.exercises.isEmpty)
            for planned in workout.exercises {
                XCTAssertEqual(planned.definition?.equipment, [], "bodyweight only: \(planned.exerciseId)")
            }
        }
    }

    func testLimitationsExcludeRiskyExercises() {
        let profile = UserProfile(experience: .advanced, equipment: Set(Equipment.allCases), availableDays: [1, 2, 4, 5], limitations: [.knee, .lowerBack, .shoulder])
        let plan = planner.makePlan(for: profile)
        let ids = plan.workouts.flatMap { $0.exercises.map(\.exerciseId) }
        for id in ids {
            let definition = ExerciseLibrary.definition(id)!
            XCTAssertTrue(Set(definition.avoidWith).isDisjoint(with: profile.limitations), id)
        }
        XCTAssertFalse(ids.contains("lunge"))
        XCTAssertFalse(ids.contains("bb_deadlift"))
    }

    func testClearanceNoteForHeartCondition() {
        let profile = UserProfile(availableDays: [1, 4], limitations: [.heartCondition])
        let plan = planner.makePlan(for: profile)
        XCTAssertFalse(plan.notes.isEmpty)
        XCTAssertFalse(plan.workouts.flatMap { $0.exercises.map(\.exerciseId) }.contains("jumping_jack"))
    }

    func testPrescriptionMatchesGoal() {
        let squat = ExerciseLibrary.definition("goblet_squat")!
        let strong = planner.prescription(for: squat, profile: UserProfile(goal: .strong, experience: .intermediate, equipment: [.dumbbells]))
        let lean = planner.prescription(for: squat, profile: UserProfile(goal: .leanDefined, experience: .intermediate, equipment: [.dumbbells]))
        XCTAssertLessThan(strong.repRange.upperBound, lean.repRange.lowerBound)
        XCTAssertGreaterThan(strong.restSeconds, lean.restSeconds)
    }

    func testSplitByDays() {
        XCTAssertEqual(planner.split(for: UserProfile(availableDays: [1, 4])), [.fullBodyA, .fullBodyB])
        XCTAssertEqual(planner.split(for: UserProfile(availableDays: [1, 2, 4, 5])), [.upper, .lower, .upper, .lower])
        XCTAssertEqual(planner.split(for: UserProfile(goal: .muscular, experience: .intermediate, availableDays: [1, 3, 5])), [.push, .pull, .legs])
    }

    func testPlanIsDeterministic() {
        let profile = UserProfile(goal: .athletic, equipment: [.dumbbells], availableDays: [2, 4, 6])
        XCTAssertEqual(planner.makePlan(for: profile, now: Date(timeIntervalSince1970: 0)), planner.makePlan(for: profile, now: Date(timeIntervalSince1970: 0)))
    }

    func testLivePlanContainsOnlyTrackedExercises() {
        let profile = UserProfile(equipment: [.dumbbells], availableDays: [1, 3, 5])
        for workout in planner.makePlan(for: profile).workouts {
            XCTAssertEqual(workout.livePlan.items.count + workout.manualExercises.count, workout.exercises.count)
        }
    }

    func testProgressionAddsRepsThenDifficulty() {
        let profile = UserProfile(experience: .beginner)
        let p = Prescription(sets: 3, repRange: 10...12, targetReps: 10, restSeconds: 60)
        let day = 86_400.0
        let hit = [ExercisePerformance(exerciseId: "squat", date: Date(timeIntervalSince1970: day), sets: [10, 10, 10], targetReps: 10)]
        XCTAssertEqual(ProgressionEngine.decide(exerciseId: "squat", prescription: p, history: hit, profile: profile), .addReps(newTarget: 11))
        let top = [ExercisePerformance(exerciseId: "squat", date: Date(timeIntervalSince1970: day), sets: [12, 12, 12], targetReps: 12)]
        if case .increaseDifficulty = ProgressionEngine.decide(exerciseId: "squat", prescription: p, history: top, profile: profile) {} else { XCTFail() }
        let missed = [
            ExercisePerformance(exerciseId: "squat", date: Date(timeIntervalSince1970: day), sets: [6, 5, 5], targetReps: 10),
            ExercisePerformance(exerciseId: "squat", date: Date(timeIntervalSince1970: 3 * day), sets: [7, 6, 5], targetReps: 10)]
        XCTAssertEqual(ProgressionEngine.decide(exerciseId: "squat", prescription: p, history: missed, profile: profile), .reduce(newTarget: 10))
    }

    func testRescheduleKeepsRecovery() {
        let profile = UserProfile(availableDays: [1, 3, 5])
        let plan = planner.makePlan(for: profile)
        let missed = plan.workouts[0]
        let day = ScheduleRules.rescheduleDay(for: missed, plan: plan, today: 2)
        XCTAssertNotNil(day)
        XCTAssertFalse(plan.workouts.map(\.weekday).contains(day!))
    }
}

final class NutritionTests: XCTestCase {
    func testMifflinStJeor() {
        let p = UserProfile(age: 30, heightCm: 180, weightKg: 80, sex: .male)
        XCTAssertEqual(NutritionCalculator.bmr(p), 1780, accuracy: 0.1)
        let f = UserProfile(age: 30, heightCm: 165, weightKg: 60, sex: .female)
        XCTAssertEqual(NutritionCalculator.bmr(f), 1320.25, accuracy: 0.1)
    }

    func testTargetsDependOnGoal() {
        let lean = NutritionCalculator.targets(for: UserProfile(weightKg: 80, sex: .male, goal: .leanDefined))
        let bulk = NutritionCalculator.targets(for: UserProfile(weightKg: 80, sex: .male, goal: .muscular))
        XCTAssertLessThan(lean.kcal, bulk.kcal)
        XCTAssertEqual(lean.proteinG, 160)
        let sum = lean.proteinG * 4 + lean.carbsG * 4 + lean.fatG * 9
        XCTAssertEqual(Double(sum), Double(lean.kcal), accuracy: 40)
    }

    func testParsesBriefExample() {
        let meal = MealParser().parse("Jarvis, kahvaltıda üç yumurta ve iki dilim ekmek yedim.")
        XCTAssertEqual(meal.meal, .breakfast)
        XCTAssertEqual(meal.items.count, 2)
        XCTAssertEqual(meal.items[0].food.id, "egg")
        XCTAssertEqual(meal.items[0].quantity, 3)
        XCTAssertEqual(meal.items[1].food.id, "white_bread")
        XCTAssertEqual(meal.items[1].quantity, 2)
        XCTAssertEqual(meal.items[1].unit, .slice)
    }

    func testParsesTurkishSuffixesAndUnits() {
        let meal = MealParser().parse("öğlen bir tabak pilav, 200 gram tavuk göğsü ve bir kase yoğurt yedim")
        XCTAssertEqual(meal.meal, .lunch)
        let ids = meal.items.map(\.food.id)
        XCTAssertEqual(ids, ["rice", "chicken_breast", "yogurt"])
        XCTAssertEqual(meal.items[1].quantity, 200)
        XCTAssertEqual(meal.items[1].unit, .gram)
        XCTAssertEqual(meal.items[2].unit, .bowl)
        let fish = MealParser().parse("akşam balık yedim")
        XCTAssertEqual(fish.items.first?.food.id, "white_fish", "balık must not match bal (honey)")
    }

    func testParsesEnglish() {
        let meal = MealParser().parse("For dinner I had a bowl of yogurt, two bananas and 150 g salmon")
        XCTAssertEqual(meal.meal, .dinner)
        XCTAssertEqual(meal.items.map(\.food.id), ["yogurt", "banana", "salmon"])
        XCTAssertEqual(meal.items[1].quantity, 2)
        XCTAssertEqual(meal.items[2].quantity, 150)
    }

    func testAssumedQuantityIsFlagged() {
        let meal = MealParser().parse("menemen yedim")
        XCTAssertEqual(meal.items.first?.assumedQuantity, true)
    }

    func testLogEntryMacros() {
        let egg = FoodDatabase.item("egg")!
        let entry = FoodLogEntry(date: Date(), meal: .breakfast, food: egg, quantity: 3, unit: .piece, source: .voice)
        XCTAssertEqual(entry.grams, 150)
        XCTAssertEqual(entry.macros.kcal, 232.5, accuracy: 0.1)
        XCTAssertTrue(entry.isEstimate)
    }

    func testVisionLabelMapping() {
        let candidates = FoodDatabase.candidates(forVisionLabels: [("pizza", 0.9), ("salad", 0.4), ("table", 0.8)])
        XCTAssertEqual(candidates.first?.item.id, "pizza")
        XCTAssertTrue(candidates.contains { $0.item.id == "salad" })
    }

    func testDatabaseIsConsistent() {
        for item in FoodDatabase.all {
            let m = item.per100
            let computed = m.protein * 4 + m.carbs * 4 + m.fat * 9
            // Atwater check: within 20% or 25 kcal (fibre, alcohol and rounding cause small gaps).
            XCTAssertLessThanOrEqual(abs(computed - m.kcal), max(25, m.kcal * 0.2), item.id)
            XCTAssertNotNil(item.units[item.defaultUnit], item.id)
        }
        XCTAssertEqual(Set(FoodDatabase.all.map(\.id)).count, FoodDatabase.all.count)
    }
}

final class FitCheckTests: XCTestCase {
    /// Draws an ellipse-section "person": a rectangle body with given widths per band.
    private func mask(width: Int, height: Int, bands: [(ClosedRange<Int>, Int)], center: Int) -> SilhouetteMask {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for (rows, w) in bands {
            for y in rows { for x in (center - w / 2)..<(center + w / 2) { pixels[y * width + x] = 1 } }
        }
        return SilhouetteMask(width: width, height: height, pixels: pixels)
    }

    func testEllipsePerimeter() {
        XCTAssertEqual(BodyMeasurementEstimator.ellipsePerimeter(width: 10, depth: 10), .pi * 10, accuracy: 1e-9)
        XCTAssertEqual(BodyMeasurementEstimator.ellipsePerimeter(width: 30, depth: 20), 79.33, accuracy: 0.05)
    }

    func testWaistEstimateFromSyntheticSilhouettes() {
        // 180 px tall person = 180 cm → 1 px = 1 cm. Waist band 30 px wide (front), 20 px deep (side).
        let bands: [(ClosedRange<Int>, Int)] = [(0...29, 16), (30...69, 40), (70...99, 30), (100...119, 36), (120...179, 30)]
        let sideBands: [(ClosedRange<Int>, Int)] = [(0...29, 18), (30...69, 26), (70...99, 20), (100...119, 26), (120...179, 20)]
        let front = mask(width: 100, height: 180, bands: bands, center: 50)
        let side = mask(width: 100, height: 180, bands: sideBands, center: 50)
        let landmarks = ScanLandmarks(shoulderY: 30, hipY: 100, kneeY: 150, centerX: 50)
        let results = BodyMeasurementEstimator().estimate(front: front, frontLandmarks: landmarks, side: side, sideLandmarks: landmarks, heightCm: 180)
        let waist = results.first { $0.site == .waist }!
        XCTAssertEqual(waist.valueCm, BodyMeasurementEstimator.ellipsePerimeter(width: 30, depth: 20), accuracy: 0.5)
        XCTAssertFalse(waist.calibrated)
        XCTAssertLessThan(waist.lowCm, waist.valueCm)
        XCTAssertTrue(waist.display().hasPrefix("≈"))
    }

    func testCalibrationNarrowsRangeAndRejectsOutliers() {
        XCTAssertEqual(BodyMeasurementEstimator.calibrationFactor(tapeCm: 84, rawEstimateCm: 80)!, 1.05, accuracy: 1e-9)
        XCTAssertNil(BodyMeasurementEstimator.calibrationFactor(tapeCm: 120, rawEstimateCm: 80))
        XCTAssertLessThan(MeasurementSite.waist.relativeUncertainty(calibrated: true), MeasurementSite.waist.relativeUncertainty(calibrated: false))
    }
}

final class AdaptiveTests: XCTestCase {
    func testWeightTrend() {
        let day = 86_400.0
        let entries = (0..<15).map { WeightEntry(date: Date(timeIntervalSince1970: Double($0) * day), kg: 80 - Double($0) * 0.1) }
        XCTAssertEqual(AdaptiveEngine.weeklyWeightTrend(entries)!, -0.7, accuracy: 0.01)
    }

    func testRecommendsMoreCaloriesWhenLosingTooFastOnBulk() {
        let day = 86_400.0
        let now = Date(timeIntervalSince1970: 30 * day)
        let profile = UserProfile(weightKg: 80, goal: .muscular)
        let plan = WorkoutPlanner().makePlan(for: profile, now: now)
        let weights = (0..<15).map { WeightEntry(date: now.addingTimeInterval(-Double(14 - $0) * day), kg: 80 - Double($0) * 0.05) }
        let recs = AdaptiveEngine().recommendations(profile: profile, plan: plan, weights: weights, workouts: [], nutritionDays: [],
                                                    targets: NutritionCalculator.targets(for: profile), performances: [], now: now)
        XCTAssertTrue(recs.contains { $0.change == .calories(deltaKcal: 150) })
        XCTAssertTrue(recs.allSatisfy { !$0.reason.tr.isEmpty && !$0.reason.en.isEmpty })
    }

    func testDeloadWhenSeveralExercisesDecline() {
        let day = 86_400.0
        let now = Date(timeIntervalSince1970: 30 * day)
        let profile = UserProfile()
        let plan = WorkoutPlanner().makePlan(for: profile, now: now)
        var perf: [ExercisePerformance] = []
        for id in ["squat", "push_up"] {
            for (i, reps) in [30, 26, 22].enumerated() {
                perf.append(ExercisePerformance(exerciseId: id, date: now.addingTimeInterval(Double(i - 3) * 2 * day), sets: [reps], targetReps: 10))
            }
        }
        let recs = AdaptiveEngine().recommendations(profile: profile, plan: plan, weights: [], workouts: [], nutritionDays: [],
                                                    targets: NutritionCalculator.targets(for: profile), performances: perf, now: now)
        XCTAssertTrue(recs.contains { $0.change == .deloadWeek })
    }
}

final class RecognizerTests: XCTestCase {
    private func recognize(_ frames: [PoseFrame]) -> TrackedExercise? {
        var recognizer = ExerciseRecognizer()
        var smoother = PoseSmoother()
        var guess: TrackedExercise?
        for frame in frames {
            recognizer.add(smoother.smooth(frame))
            if let g = recognizer.bestGuess(minimumScore: 0.7) { guess = g.exercise }
        }
        return guess
    }

    func testRecognisesDistinctExercises() {
        let cases: [(TrackedExercise, CameraView)] = [(.squat, .side), (.pushUp, .side), (.jumpingJack, .front), (.gluteBridge, .side),
                                                       (.lateralRaise, .front), (.bicepsCurl, .front)]
        for (exercise, view) in cases {
            let frames = SyntheticPose.sequence(reps: 3, period: 2.0, restBefore: 0, restAfter: 0, pose: SyntheticPose.generator(for: exercise, view: view))
            XCTAssertEqual(recognize(frames), exercise, "\(exercise)")
        }
    }

    func testFramingGuide() {
        let guide = FramingGuide()
        let standing = PoseFrame(timestamp: 0, keypoints: SyntheticPose.squat(0, view: .side), aspectRatio: 1)
        XCTAssertEqual(guide.evaluate(standing, for: .squat).status, .ready)
        XCTAssertEqual(guide.evaluate(PoseFrame(timestamp: 0, keypoints: [:]), for: .squat).status, .noPerson)
        // No fixed placement: standing in view is enough to start (the user gets down afterwards).
        XCTAssertEqual(guide.evaluate(standing, for: .pushUp).status, .ready)
        // Close-up for an arm exercise: only the upper body is visible.
        var upper = SyntheticPose.curl(0)
        for joint: Joint in [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle] { upper[joint] = nil }
        XCTAssertEqual(guide.evaluate(PoseFrame(timestamp: 0, keypoints: upper, aspectRatio: 1), for: .bicepsCurl).status, .ready)
        // Very far away: tiny in the image.
        let tiny = AnyAngleTests.place(SyntheticPose.squat(0, view: .front), AnyAngleTests.Placement(name: "tiny", scale: 0.1))
        XCTAssertEqual(guide.evaluate(PoseFrame(timestamp: 0, keypoints: tiny, aspectRatio: 1), for: .squat).status, .stepCloser)
        // Feet cut off.
        var noFeet = SyntheticPose.squat(0, view: .front)
        for joint: Joint in [.leftAnkle, .rightAnkle, .leftKnee, .rightKnee] { noFeet[joint] = nil }
        XCTAssertEqual(guide.evaluate(PoseFrame(timestamp: 0, keypoints: noFeet, aspectRatio: 1), for: .squat).status, .showFeet)
    }
}
