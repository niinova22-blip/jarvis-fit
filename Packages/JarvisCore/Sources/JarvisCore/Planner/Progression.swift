import Foundation

/// Logged performance of one exercise in one session (live-tracked or manual).
public struct ExercisePerformance: Codable, Hashable, Sendable {
    public var exerciseId: String
    public var date: Date
    /// Achieved reps (or seconds) per set.
    public var sets: [Int]
    public var targetReps: Int
    public var formIssueCount: Int
    /// Optional external load in kg.
    public var loadKg: Double?

    public init(exerciseId: String, date: Date, sets: [Int], targetReps: Int, formIssueCount: Int = 0, loadKg: Double? = nil) {
        self.exerciseId = exerciseId
        self.date = date
        self.sets = sets
        self.targetReps = targetReps
        self.formIssueCount = formIssueCount
        self.loadKg = loadKg
    }

    public var totalReps: Int { sets.reduce(0, +) }
    public var bestSet: Int { sets.max() ?? 0 }
    public var allSetsHitTarget: Bool { !sets.isEmpty && sets.allSatisfy { $0 >= targetReps } }
}

public enum ProgressionDecision: Equatable, Sendable {
    case keep(target: Int)
    case addReps(newTarget: Int)
    /// Top of the range reached: add load or move to a harder variation.
    case increaseDifficulty(suggestedExerciseId: String?, loadIncreasePercent: Double?)
    case reduce(newTarget: Int)
    case deload

    public func explanation(_ language: AppLanguage) -> String {
        let tr = language == .turkish
        switch self {
        case .keep(let t): return tr ? "Hedef \(t) tekrarda kalıyor; önce formu oturtalım." : "Target stays at \(t); let's consolidate form first."
        case .addReps(let t): return tr ? "Son antrenmanda tüm setleri tamamladın, hedef \(t) tekrara çıktı." : "You hit every set last time, so the target is now \(t)."
        case .increaseDifficulty(let id, let load):
            if let load { return tr ? "Tekrar aralığının üstüne ulaştın: ağırlığı yaklaşık %\(Int(load)) artır ve aralığın altından başla." : "You reached the top of the range: add about \(Int(load))% load and restart at the bottom of the range." }
            if let id, let name = ExerciseLibrary.definition(id)?.name.resolve(language) { return tr ? "Bu hareket artık kolay geliyor; \(name) varyasyonuna geçiyoruz." : "This is getting easy; moving to \(name)." }
            return tr ? "Hareketi yavaş tempoyla (3 sn iniş) yaparak zorlaştır." : "Make it harder with a slow 3-second lowering phase."
        case .reduce(let t): return tr ? "İki antrenmandır hedefin altında kaldın, hedefi \(t) yaptım." : "You've been below target twice, so the target is now \(t)."
        case .deload: return tr ? "Performansın düşüyor; bu hafta hacmi azaltıp toparlanmaya odaklanalım." : "Performance is dropping; let's reduce volume this week and recover."
        }
    }
}

/// Double progression: add reps until the top of the range, then add load / harder variation.
public enum ProgressionEngine {
    public static func decide(exerciseId: String, prescription: Prescription, history: [ExercisePerformance], profile: UserProfile) -> ProgressionDecision {
        let recent = history.filter { $0.exerciseId == exerciseId }.sorted { $0.date < $1.date }
        guard let last = recent.last else { return .keep(target: prescription.targetReps) }
        let range = prescription.repRange

        // Three consecutive sessions with falling total reps → deload.
        if recent.count >= 3 {
            let lastThree = recent.suffix(3).map(\.totalReps)
            if lastThree[0] > lastThree[1] && lastThree[1] > lastThree[2] && Double(lastThree[2]) < Double(lastThree[0]) * 0.85 {
                return .deload
            }
        }
        // Two sessions in a row clearly below target → reduce.
        if recent.count >= 2 {
            let lastTwo = recent.suffix(2)
            if lastTwo.allSatisfy({ Double($0.bestSet) < Double($0.targetReps) * 0.8 }) {
                return .reduce(newTarget: max(range.lowerBound, last.targetReps - 2))
            }
        }
        guard last.allSetsHitTarget && last.formIssueCount <= last.sets.count else {
            return .keep(target: last.targetReps)
        }
        let step = range.upperBound - range.lowerBound >= 6 ? 2 : 1
        if last.targetReps + step <= range.upperBound {
            return .addReps(newTarget: last.targetReps + step)
        }
        guard let definition = ExerciseLibrary.definition(exerciseId) else { return .keep(target: last.targetReps) }
        if definition.isLoaded {
            return .increaseDifficulty(suggestedExerciseId: nil, loadIncreasePercent: definition.isCompound ? 5 : 10)
        }
        let harder = ExerciseLibrary.available(for: profile)
            .filter { $0.pattern == definition.pattern && $0.difficulty > definition.difficulty && $0.id != definition.id }
            .min { $0.difficulty < $1.difficulty }
        return .increaseDifficulty(suggestedExerciseId: harder?.id, loadIncreasePercent: nil)
    }

    /// Applies a decision to a prescription (used when generating the next session).
    public static func apply(_ decision: ProgressionDecision, to prescription: Prescription) -> Prescription {
        var p = prescription
        switch decision {
        case .keep(let t): p.targetReps = min(max(t, p.repRange.lowerBound), p.repRange.upperBound)
        case .addReps(let t): p.targetReps = min(t, p.repRange.upperBound)
        case .increaseDifficulty: p.targetReps = p.repRange.lowerBound
        case .reduce(let t): p.targetReps = max(1, t)
        case .deload:
            p.sets = max(1, p.sets - 1)
            p.targetReps = p.repRange.lowerBound
        }
        return p
    }
}

/// Recovery and rescheduling rules.
public enum ScheduleRules {
    /// Minimum hours between sessions that train the same primary muscle groups hard.
    public static let recoveryHours: Double = 48

    /// Muscles still recovering at `date`, given completed sessions (date + muscles).
    public static func recoveringMuscles(at date: Date, completed: [(date: Date, muscles: [MuscleGroup])]) -> Set<MuscleGroup> {
        var result: Set<MuscleGroup> = []
        for session in completed where date.timeIntervalSince(session.date) < recoveryHours * 3600 && date >= session.date {
            result.formUnion(session.muscles.filter { $0 != .core && $0 != .fullBody })
        }
        return result
    }

    /// Chooses the day to move a missed workout to: the first upcoming weekday (within the
    /// remaining week) that is free and keeps 48 h from sessions using the same main muscles.
    /// Returns nil when the workout should be skipped this week instead of cramming.
    public static func rescheduleDay(for missed: PlannedWorkout, plan: WeeklyPlan, today: Weekday) -> Weekday? {
        let occupied = Set(plan.workouts.map(\.weekday))
        let missedMain = Set(missed.focus.prefix(3))
        guard today >= 1 && today <= 7 else { return nil }
        for day in today...7 where !occupied.contains(day) {
            let neighbours = plan.workouts.filter { abs($0.weekday - day) == 1 && $0.id != missed.id }
            let conflicts = neighbours.contains { !Set($0.focus.prefix(3)).isDisjoint(with: missedMain) }
            if !conflicts { return day }
        }
        return nil
    }
}
