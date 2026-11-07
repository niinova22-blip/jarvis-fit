import XCTest
import Vision
@testable import JarvisFit
import JarvisCore

final class JarvisFitTests: XCTestCase {
    func testIsoWeekday() {
        // 2026-11-02 is a Monday.
        var components = DateComponents()
        components.year = 2026; components.month = 11; components.day = 2; components.hour = 12
        let monday = Calendar.current.date(from: components)!
        XCTAssertEqual(monday.isoWeekday, 1)
        XCTAssertEqual(monday.addingTimeInterval(6 * 86_400).isoWeekday, 7)
    }

    func testAppDataRoundTrip() throws {
        var data = AppData()
        data.profile = UserProfile(name: "Test")
        data.plan = WorkoutPlanner().makePlan(for: data.profile!)
        data.foodLog = [FoodLogEntry(date: Date(), meal: .lunch, food: FoodDatabase.item("rice")!, quantity: 1, unit: .plate, source: .manual)]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppData.self, from: encoder.encode(data))
        XCTAssertEqual(decoded.profile, data.profile)
        XCTAssertEqual(decoded.plan?.workouts, data.plan?.workouts)
        XCTAssertEqual(decoded.plan!.createdAt.timeIntervalSince1970, data.plan!.createdAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(decoded.foodLog.count, 1)
    }

    /// Older data files (missing newer fields) and a broken field must not wipe the user's data.
    func testAppDataDecodingIsTolerant() throws {
        var data = AppData()
        data.profile = UserProfile(name: "Old")
        data.weights = [WeightEntry(date: Date(timeIntervalSince1970: 0), kg: 80)]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var json = try JSONSerialization.jsonObject(with: encoder.encode(data)) as! [String: Any]
        json.removeValue(forKey: "lastWeeklyReportWeek")
        var settings = json["settings"] as! [String: Any]
        settings.removeValue(forKey: "performance")
        settings.removeValue(forKey: "cueSounds")
        json["settings"] = settings
        json["chat"] = "not an array"
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppData.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.profile?.name, "Old")
        XCTAssertEqual(decoded.weights.count, 1)
        XCTAssertTrue(decoded.chat.isEmpty)
        XCTAssertEqual(decoded.settings.performance, .automatic)
        XCTAssertTrue(decoded.settings.cueSounds)
    }

    func testVisionJointMapCoversAllJoints() {
        XCTAssertEqual(Set(VisionPoseAdapter.jointMap.values), Set(JarvisCore.Joint.allCases))
    }

    @MainActor
    func testFreeTierLimits() {
        let model = AppModel(store: DataStore(filename: "test-\(UUID().uuidString).json"))
        XCTAssertEqual(model.liveWorkoutsLeftThisWeek, AppModel.freeLiveWorkoutsPerWeek)
        XCTAssertEqual(model.foodScansLeftToday, AppModel.freeFoodScansPerDay)
        model.recordFoodScan()
        XCTAssertEqual(model.foodScansLeftToday, AppModel.freeFoodScansPerDay - 1)
    }

    @MainActor
    func testOnboardingCreatesPlanAndRecordsWorkout() {
        let model = AppModel(store: DataStore(filename: "test-\(UUID().uuidString).json"))
        model.completeOnboarding(UserProfile(name: "A", availableDays: [1, 3, 5]))
        XCTAssertTrue(model.isOnboarded)
        let workout = model.data.plan!.workouts[0]
        let set = SetResult(exercise: .squat, setNumber: 1, target: 10, reps: 10, holdSeconds: 0, formIssues: [], partialReps: 0,
                            averageRepDuration: 2, slowdown: 1, startedAt: 0, endedAt: 30, endReason: .targetReached)
        model.recordWorkout(WorkoutSummary(title: workout.title, sets: [set], startedAt: 0, endedAt: 60, completed: true), planned: workout)
        XCTAssertEqual(model.data.workoutLogs.count, 1)
        XCTAssertFalse(model.data.performances.isEmpty)
    }
}
