import Foundation
import Combine
import SwiftUI
import JarvisCore

/// Central app state. All mutations go through here and are persisted.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var data: AppData
    @Published var selectedTab: AppTab = .dashboard
    @Published var activeWorkout: PlannedWorkout?
    @Published var showLiveWorkout = false

    private let store: DataStore
    private var subscriptionChanges: AnyCancellable?
    let subscriptions: SubscriptionManager
    let voice: VoiceCoordinator

    init(store: DataStore = DataStore()) {
        self.store = store
        self.data = store.load()
        self.subscriptions = SubscriptionManager()
        self.voice = VoiceCoordinator()
        configureVoice()
        // Premium status lives in SubscriptionManager; refresh views that read `isPremium`.
        subscriptionChanges = subscriptions.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    // MARK: Derived

    var profile: UserProfile? { data.profile }
    var language: AppLanguage { data.profile?.language ?? AppLanguage.from(preferred: Locale.preferredLanguages) }
    var isOnboarded: Bool { data.profile != nil && data.plan != nil }

    func t(_ tr: String, _ en: String) -> String { language == .turkish ? tr : en }
    func t(_ text: LocalizedText) -> String { text.resolve(language) }

    var targets: NutritionTargets? {
        guard let profile = data.profile else { return nil }
        return NutritionCalculator.targets(for: profile, adjustmentKcal: data.calorieAdjustment)
    }

    var todayWorkout: PlannedWorkout? { data.plan?.workout(on: Date().isoWeekday) }

    var completedToday: Bool {
        let today = Date().dayKey
        return data.workoutLogs.contains { $0.date.dayKey == today }
    }

    func entries(on day: Date) -> [FoodLogEntry] {
        let key = day.dayKey
        return data.foodLog.filter { $0.date.dayKey == key }
    }

    var nutritionToday: NutritionDay? {
        guard let targets else { return nil }
        return NutritionDay(entries: entries(on: Date()), targets: targets)
    }

    var workoutsThisWeek: Int {
        let start = Date().startOfWeek
        return data.workoutLogs.filter { $0.date >= start }.count
    }

    func assistantContext(session: SessionSnapshot? = nil) -> AssistantContext? {
        guard let profile = data.profile else { return nil }
        return AssistantContext(profile: profile, session: session, plan: data.plan, todayWeekday: Date().isoWeekday,
                                nutrition: nutritionToday, lastWorkout: data.workoutLogs.last, workoutsThisWeek: workoutsThisWeek,
                                memories: data.memoryEnabled && isPremium ? data.memories : [],
                                weeklyReport: isPremium ? weeklyReport(weekStart: Date().startOfWeek) : nil)
    }

    private var nutritionDays: [(date: Date, totals: Macros)] {
        Dictionary(grouping: data.foodLog, by: { $0.date.dayKey }).map { _, entries in
            (date: entries[0].date, totals: entries.reduce(Macros.zero) { $0 + $1.macros })
        }
    }

    func weeklyReport(weekStart: Date) -> WeeklyReport? {
        guard let targets else { return nil }
        return WeeklyReport.make(weekStart: weekStart, plan: data.plan, workouts: data.workoutLogs, nutritionDays: nutritionDays,
                                 targets: targets, weights: data.weights)
    }

    /// Last week's report, shown once at the start of a new week (if the user trained before).
    var pendingWeeklyReport: WeeklyReport? {
        let thisWeek = Date().startOfWeek
        guard isPremium, data.settings.weeklyReport, data.lastWeeklyReportWeek != thisWeek.dayKey,
              data.workoutLogs.contains(where: { $0.date < thisWeek }),
              let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: thisWeek) else { return nil }
        return weeklyReport(weekStart: lastWeek)
    }

    func markWeeklyReportSeen() { mutate { $0.lastWeeklyReportWeek = Date().startOfWeek.dayKey } }

    var motivation: LocalizedText? {
        guard let profile = data.profile else { return nil }
        let recentBest = data.workoutLogs.last.flatMap { last -> TrackedExercise? in
            let earlier = data.workoutLogs.dropLast()
            return last.summary.sets.first { set in
                let previous = earlier.flatMap(\.summary.sets).filter { $0.exercise == set.exercise }.map(\.achieved).max()
                return previous.map { set.achieved > $0 } ?? false
            }?.exercise
        }
        let dayIndex = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let text = Motivation.message(personality: profile.personality, dayIndex: dayIndex,
                                      streakWeeks: ProgressAnalytics.weekStreak(workouts: data.workoutLogs, upTo: Date()),
                                      recentPersonalBest: recentBest, workoutsThisWeek: workoutsThisWeek)
        return text.tr.isEmpty ? nil : text
    }

    var recommendations: [Recommendation] {
        // Adaptive suggestions are a premium feature.
        guard isPremium, let profile = data.profile, let plan = data.plan, let targets else { return [] }
        let all = AdaptiveEngine().recommendations(profile: profile, plan: plan, weights: data.weights, workouts: data.workoutLogs,
                                                   nutritionDays: nutritionDays, targets: targets, performances: data.performances)
        // A dismissed suggestion stays hidden for 7 days.
        return all.filter { rec in
            guard let dismissed = data.dismissedRecommendations[rec.id] else { return true }
            return Date().timeIntervalSince(dismissed) > 7 * 86_400
        }
    }

    /// Applies language, personality and the gender-matched voice to the speech engine.
    func configureVoice() {
        guard let profile = data.profile else { return }
        let gender = VoiceSelector.desiredGender(data.settings.voiceGender, userSex: profile.sex)
        voice.configure(language: profile.language, personality: profile.personality, voiceIdentifier: data.settings.voiceIdentifier,
                        gender: gender, enhancement: data.settings.voiceEnhancement)
    }

    // MARK: Mutations

    private func mutate(_ change: (inout AppData) -> Void) {
        change(&data)
        store.save(data)
    }

    func completeOnboarding(_ profile: UserProfile) {
        mutate { data in
            data.profile = profile
            data.plan = WorkoutPlanner().makePlan(for: profile)
            data.weights.append(WeightEntry(date: Date(), kg: profile.weightKg))
        }
        configureVoice()
        NotificationScheduler.reschedule(model: self)
    }

    func updateProfile(_ profile: UserProfile, regeneratePlan: Bool) {
        mutate { data in
            data.profile = profile
            if regeneratePlan { data.plan = WorkoutPlanner().makePlan(for: profile) }
        }
        configureVoice()
        NotificationScheduler.reschedule(model: self)
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        mutate { change(&$0.settings) }
        configureVoice()
        NotificationScheduler.reschedule(model: self)
    }

    /// Stores a finished live workout and applies progression to the plan.
    func recordWorkout(_ summary: WorkoutSummary, planned: PlannedWorkout?) {
        guard !summary.sets.isEmpty else { return }
        let now = Date()
        var previousBest: [TrackedExercise: Int] = [:]
        for log in data.workoutLogs {
            for set in log.summary.sets { previousBest[set.exercise] = max(previousBest[set.exercise] ?? 0, set.achieved) }
        }
        let language = self.language
        let premium = isPremium
        mutate { data in
            data.workoutLogs.append(WorkoutLog(date: now, summary: summary, plannedWorkoutId: planned?.id))
            data.usage.liveWorkoutDates.append(now)
            // Per-exercise performance (mapped back to the planned exercise id).
            let grouped = Dictionary(grouping: summary.sets, by: \.exercise)
            for (exercise, sets) in grouped {
                let exerciseId = planned?.exercises.first { $0.definition?.tracked == exercise }?.exerciseId
                    ?? WorkoutPlanView.definitionId(for: exercise)
                let target = sets.first?.target ?? 0
                data.performances.append(ExercisePerformance(exerciseId: exerciseId, date: now, sets: sets.map(\.achieved),
                                                             targetReps: target, formIssueCount: sets.reduce(0) { $0 + $1.formIssues.count }))
            }
            if data.memoryEnabled && premium {
                data.memories += MemoryExtractor.achievements(from: summary, previousBest: previousBest, language: language, date: now)
                // Remember exercises with repeated form issues as struggles (once).
                for set in summary.sets where set.formIssues.count >= 2 {
                    let text = language == .turkish ? "\(set.exercise.name.tr) hareketinde form zorlanması" : "Form difficulties in \(set.exercise.name.en)"
                    if !data.memories.contains(where: { $0.text == text }) {
                        data.memories.append(MemoryItem(kind: .struggle, text: text, createdAt: now))
                    }
                }
            }
            // Progression for the next time this workout comes up (adaptive planning is premium;
            // free users keep their basic plan and can still edit it).
            if premium, let planned, let profile = data.profile, var plan = data.plan,
               let index = plan.workouts.firstIndex(where: { $0.id == planned.id }) {
                for (i, exercise) in plan.workouts[index].exercises.enumerated() {
                    let decision = ProgressionEngine.decide(exerciseId: exercise.exerciseId, prescription: exercise.prescription,
                                                            history: data.performances, profile: profile)
                    plan.workouts[index].exercises[i].prescription = ProgressionEngine.apply(decision, to: exercise.prescription)
                }
                data.plan = plan
            }
        }
    }

    func addPerformance(_ performance: ExercisePerformance) {
        mutate { $0.performances.append(performance) }
    }

    func addFoodEntries(_ entries: [FoodLogEntry]) {
        guard !entries.isEmpty else { return }
        mutate { $0.foodLog.append(contentsOf: entries) }
    }

    func deleteFoodEntry(_ id: UUID) { mutate { $0.foodLog.removeAll { $0.id == id } } }

    func recordFoodScan() { mutate { $0.usage.foodScanDates.append(Date()) } }

    func addWeight(_ kg: Double) {
        mutate { data in
            data.weights.append(WeightEntry(date: Date(), kg: kg))
            data.profile?.weightKg = kg
        }
    }

    func addFitCheck(_ record: FitCheckRecord, calibration: [MeasurementSite: Double]) {
        mutate { data in
            data.fitChecks.append(record)
            for (site, factor) in calibration { data.calibration[site.rawValue] = factor }
            if let w = record.weightKg { data.weights.append(WeightEntry(date: record.date, kg: w)) }
        }
    }

    func deleteFitCheck(_ id: UUID) {
        if let record = data.fitChecks.first(where: { $0.id == id }) {
            for file in [record.frontPhotoFile, record.sidePhotoFile].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: DataStore.photosDirectory.appendingPathComponent(file))
            }
        }
        mutate { $0.fitChecks.removeAll { $0.id == id } }
    }

    var calibrationFactors: [MeasurementSite: Double] {
        var result: [MeasurementSite: Double] = [:]
        for (key, value) in data.calibration { if let site = MeasurementSite(rawValue: key) { result[site] = value } }
        return result
    }

    func accept(_ rec: Recommendation) {
        mutate { data in
            switch rec.change {
            case .calories(let delta): data.calorieAdjustment += delta
            case .reduceTrainingDays(let days):
                if var profile = data.profile {
                    profile.availableDays = Set(profile.availableDays.sorted().prefix(days))
                    data.profile = profile
                    data.plan = WorkoutPlanner().makePlan(for: profile)
                }
            case .deloadWeek:
                if var plan = data.plan {
                    for w in plan.workouts.indices {
                        for e in plan.workouts[w].exercises.indices {
                            plan.workouts[w].exercises[e].prescription = ProgressionEngine.apply(.deload, to: plan.workouts[w].exercises[e].prescription)
                        }
                    }
                    data.plan = plan
                }
            case .reminderTime(let minute): data.profile?.preferredTrainingMinute = minute
            case .rescheduleWorkout(let workoutId, let weekday):
                if var plan = data.plan, let w = plan.workouts.firstIndex(where: { $0.id == workoutId }),
                   !plan.workouts.contains(where: { $0.weekday == weekday }) {
                    plan.workouts[w].weekday = weekday
                    data.plan = plan
                }
            case .increaseProtein, .addRestDay, .progression: break
            }
            data.dismissedRecommendations[rec.id] = Date()
        }
        NotificationScheduler.reschedule(model: self)
    }

    func dismiss(_ rec: Recommendation) { mutate { $0.dismissedRecommendations[rec.id] = Date() } }

    func swapExercise(workoutId: String, from oldId: String, to newId: String) {
        guard let profile = data.profile, let definition = ExerciseLibrary.definition(newId) else { return }
        mutate { data in
            guard var plan = data.plan, let w = plan.workouts.firstIndex(where: { $0.id == workoutId }),
                  let e = plan.workouts[w].exercises.firstIndex(where: { $0.exerciseId == oldId }) else { return }
            plan.workouts[w].exercises[e] = PlannedExercise(exerciseId: newId, prescription: WorkoutPlanner().prescription(for: definition, profile: profile))
            data.plan = plan
        }
    }

    func moveWorkout(_ workoutId: String, to weekday: Int) {
        mutate { data in
            guard var plan = data.plan, let w = plan.workouts.firstIndex(where: { $0.id == workoutId }) else { return }
            plan.workouts[w].weekday = weekday
            data.plan = plan
        }
    }

    // Memory
    func addMemory(_ item: MemoryItem) {
        guard data.memoryEnabled, isPremium else { return }
        mutate { data in
            if !data.memories.contains(where: { $0.text.lowercased() == item.text.lowercased() }) { data.memories.append(item) }
        }
    }
    func deleteMemory(_ id: UUID) { mutate { $0.memories.removeAll { $0.id == id } } }
    func clearMemories() { mutate { $0.memories.removeAll() } }
    func setMemoryEnabled(_ enabled: Bool) { mutate { $0.memoryEnabled = enabled } }

    // Chat
    func appendChat(_ message: ChatMessage) {
        mutate { data in
            data.chat.append(message)
            if data.chat.count > 200 { data.chat.removeFirst(data.chat.count - 200) }
        }
    }
    func clearChat() { mutate { $0.chat.removeAll() } }

    func markBriefingSpoken() { mutate { $0.lastBriefingDay = Date().dayKey } }
    var briefingSpokenToday: Bool { data.lastBriefingDay == Date().dayKey }

    func deleteAllData() {
        store.deleteEverything()
        data = AppData()
        NotificationScheduler.cancelAll()
    }

    // MARK: Free tier

    /// Test phase: every premium feature is unlocked for TestFlight testers. Set to false before
    /// the App Store release (the paywall and free-tier limits then apply again).
    static let testPhaseUnlocked = true

    var isPremium: Bool { Self.testPhaseUnlocked || subscriptions.isPremium }

    static let freeLiveWorkoutsPerWeek = 3
    static let freeFoodScansPerDay = 3

    var liveWorkoutsLeftThisWeek: Int {
        let start = Date().startOfWeek
        return max(0, Self.freeLiveWorkoutsPerWeek - data.usage.liveWorkoutDates.filter { $0 >= start }.count)
    }

    var foodScansLeftToday: Int {
        let key = Date().dayKey
        return max(0, Self.freeFoodScansPerDay - data.usage.foodScanDates.filter { $0.dayKey == key }.count)
    }

    func canStartLiveWorkout() -> Bool { isPremium || liveWorkoutsLeftThisWeek > 0 }
    func canScanFood() -> Bool { isPremium || foodScansLeftToday > 0 }

    func startWorkout(_ workout: PlannedWorkout?) {
        activeWorkout = workout ?? todayWorkout ?? data.plan?.workouts.first
        showLiveWorkout = true
    }
}

enum AppTab: Hashable { case dashboard, workout, nutrition, progress, chat }
