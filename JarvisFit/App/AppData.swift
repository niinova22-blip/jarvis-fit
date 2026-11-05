import Foundation
import JarvisCore

struct AppSettings: Codable, Equatable {
    var useFrontCamera = true
    var speakDailyBriefing = true
    var workoutReminders = true
    var weeklyReport = true
    var voiceIdentifier: String?
    /// Outside workouts JARVIS only reacts after hearing "Jarvis".
    var requireWakeWord = true
    var savePhotos = true
}

struct UsageCounters: Codable, Equatable {
    var liveWorkoutDates: [Date] = []
    var foodScanDates: [Date] = []
}

struct FitCheckRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var estimates: [MeasurementEstimate]
    var posture: PostureReport
    var weightKg: Double?
    var frontPhotoFile: String?
    var sidePhotoFile: String?
    /// Tape measurements entered by the user at this scan.
    var tapeMeasurements: [String: Double] = [:]
}

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, jarvis }
    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
}

/// Everything the app persists. Stored as one JSON file with complete file protection.
struct AppData: Codable {
    var profile: UserProfile?
    var plan: WeeklyPlan?
    var workoutLogs: [WorkoutLog] = []
    var performances: [ExercisePerformance] = []
    var foodLog: [FoodLogEntry] = []
    var weights: [WeightEntry] = []
    var fitChecks: [FitCheckRecord] = []
    /// MeasurementSite raw value → calibration factor.
    var calibration: [String: Double] = [:]
    var memories: [MemoryItem] = []
    var memoryEnabled = true
    var dismissedRecommendations: [String: Date] = [:]
    var calorieAdjustment = 0
    var usage = UsageCounters()
    var settings = AppSettings()
    var lastBriefingDay: String?
    var chat: [ChatMessage] = []
}

/// JSON file persistence in Application Support.
final class DataStore {
    private let url: URL
    private let queue = DispatchQueue(label: "jarvisfit.datastore", qos: .utility)

    init(filename: String = "jarvisfit-data.json") {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        url = base.appendingPathComponent(filename)
    }

    static var photosDirectory: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("FitCheckPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func load() -> AppData {
        guard let data = try? Data(contentsOf: url) else { return AppData() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AppData.self, from: data)) ?? AppData()
    }

    func save(_ appData: AppData) {
        let url = self.url
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(appData) else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    func deleteEverything() {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: Self.photosDirectory)
    }
}

extension Date {
    /// ISO weekday: 1 = Monday … 7 = Sunday.
    var isoWeekday: Int {
        let weekday = Calendar.current.component(.weekday, from: self)
        return (weekday + 5) % 7 + 1
    }

    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    var startOfWeek: Date {
        let start = startOfDay
        return Calendar.current.date(byAdding: .day, value: -(isoWeekday - 1), to: start) ?? start
    }
}
