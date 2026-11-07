import Foundation
import JarvisCore

struct AppSettings: Codable, Equatable {
    var useFrontCamera = true
    var speakDailyBriefing = true
    var workoutReminders = true
    var weeklyReport = true
    var voiceIdentifier: String?
    /// Outside workouts NOVA only reacts after hearing "Nova".
    var requireWakeWord = true
    var savePhotos = true
    var performance: PerformancePreference = .automatic
    /// Developer option: keep the raw pose stream of live workouts to validate rep counting.
    var recordPoseData = false
    /// Male voice for male users, female voice for female users (unless changed).
    var voiceGender: VoiceGenderPreference = .matchUser
    /// Studio-style processing (EQ, compression, subtle room) on NOVA's voice.
    var voiceEnhancement = true
    /// NOVA's own on-device voice (used for male voice when bundled); off = Apple voices only.
    var neuralVoice = true
    /// Short tones + haptics for reps, countdown, "go" and finished sets in live workouts.
    var cueSounds = true

    init() {}

    // Tolerant decoding: settings added in later versions fall back to defaults instead of
    // making the whole data file unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        useFrontCamera = c.value(.useFrontCamera, d.useFrontCamera)
        speakDailyBriefing = c.value(.speakDailyBriefing, d.speakDailyBriefing)
        workoutReminders = c.value(.workoutReminders, d.workoutReminders)
        weeklyReport = c.value(.weeklyReport, d.weeklyReport)
        voiceIdentifier = c.value(.voiceIdentifier, d.voiceIdentifier)
        requireWakeWord = c.value(.requireWakeWord, d.requireWakeWord)
        savePhotos = c.value(.savePhotos, d.savePhotos)
        performance = c.value(.performance, d.performance)
        recordPoseData = c.value(.recordPoseData, d.recordPoseData)
        voiceGender = c.value(.voiceGender, d.voiceGender)
        voiceEnhancement = c.value(.voiceEnhancement, d.voiceEnhancement)
        neuralVoice = c.value(.neuralVoice, d.neuralVoice)
        cueSounds = c.value(.cueSounds, d.cueSounds)
    }

    private static let defaults = AppSettings()
}

extension KeyedDecodingContainer {
    /// Decodes a value if present and valid, otherwise returns the fallback.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
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
    var lastWeeklyReportWeek: String?

    init() {}

    // Each field decodes independently so one unreadable or new field never wipes the user's data.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = c.value(.profile, nil)
        plan = c.value(.plan, nil)
        workoutLogs = c.value(.workoutLogs, [])
        performances = c.value(.performances, [])
        foodLog = c.value(.foodLog, [])
        weights = c.value(.weights, [])
        fitChecks = c.value(.fitChecks, [])
        calibration = c.value(.calibration, [:])
        memories = c.value(.memories, [])
        memoryEnabled = c.value(.memoryEnabled, true)
        dismissedRecommendations = c.value(.dismissedRecommendations, [:])
        calorieAdjustment = c.value(.calorieAdjustment, 0)
        usage = c.value(.usage, UsageCounters())
        settings = c.value(.settings, AppSettings())
        lastBriefingDay = c.value(.lastBriefingDay, nil)
        chat = c.value(.chat, [])
        lastWeeklyReportWeek = c.value(.lastWeeklyReportWeek, nil)
    }
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
        do {
            return try decoder.decode(AppData.self, from: data)
        } catch {
            // Never silently overwrite unreadable data: keep a copy next to it.
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            return AppData()
        }
    }

    /// Directory for developer pose recordings (excluded from backups).
    static var recordingsDirectory: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        var dir = base.appendingPathComponent("PoseRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
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
        try? FileManager.default.removeItem(at: Self.recordingsDirectory)
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
