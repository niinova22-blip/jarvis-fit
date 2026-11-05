import Foundation

public struct Prescription: Codable, Hashable, Sendable {
    public var sets: Int
    public var repRange: ClosedRange<Int>
    /// Current target within the range (double progression).
    public var targetReps: Int
    public var restSeconds: Int

    public init(sets: Int, repRange: ClosedRange<Int>, targetReps: Int, restSeconds: Int) {
        self.sets = sets
        self.repRange = repRange
        self.targetReps = targetReps
        self.restSeconds = restSeconds
    }
}

public struct PlannedExercise: Codable, Hashable, Sendable, Identifiable {
    public var exerciseId: String
    public var prescription: Prescription
    public var id: String { exerciseId }

    public var definition: ExerciseDefinition? { ExerciseLibrary.definition(exerciseId) }
}

public enum SessionKind: String, Codable, Sendable {
    case fullBodyA, fullBodyB, upper, lower, push, pull, legs, conditioning

    public var title: LocalizedText {
        switch self {
        case .fullBodyA: return LocalizedText(tr: "Tüm vücut A", en: "Full body A")
        case .fullBodyB: return LocalizedText(tr: "Tüm vücut B", en: "Full body B")
        case .upper: return LocalizedText(tr: "Üst vücut", en: "Upper body")
        case .lower: return LocalizedText(tr: "Alt vücut", en: "Lower body")
        case .push: return LocalizedText(tr: "İtiş (göğüs, omuz, triceps)", en: "Push (chest, shoulders, triceps)")
        case .pull: return LocalizedText(tr: "Çekiş (sırt, biceps)", en: "Pull (back, biceps)")
        case .legs: return LocalizedText(tr: "Bacak ve kalça", en: "Legs and glutes")
        case .conditioning: return LocalizedText(tr: "Kondisyon ve core", en: "Conditioning and core")
        }
    }

    /// Movement slots of the session, in training order (compound first, core/conditioning last).
    var slots: [MovementPattern] {
        switch self {
        case .fullBodyA: return [.squat, .horizontalPush, .horizontalPull, .glute, .shoulderIsolation, .core]
        case .fullBodyB: return [.lunge, .verticalPush, .verticalPull, .hinge, .armFlexion, .core]
        case .upper: return [.horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .armFlexion, .armExtension]
        case .lower: return [.squat, .hinge, .lunge, .glute, .core]
        case .push: return [.horizontalPush, .verticalPush, .shoulderIsolation, .armExtension, .core]
        case .pull: return [.verticalPull, .horizontalPull, .armFlexion, .shoulderIsolation, .core]
        case .legs: return [.squat, .hinge, .lunge, .glute, .core]
        case .conditioning: return [.conditioning, .squat, .horizontalPush, .glute, .core, .conditioning]
        }
    }
}

public struct PlannedWorkout: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var weekday: Weekday
    public var kind: SessionKind
    public var exercises: [PlannedExercise]

    public var title: LocalizedText { kind.title }

    public var focus: [MuscleGroup] {
        var seen: [MuscleGroup] = []
        for exercise in exercises {
            if let primary = exercise.definition?.primary, !seen.contains(primary) { seen.append(primary) }
        }
        return seen
    }

    /// Exercises the camera can track, as a live workout.
    public var livePlan: LiveWorkoutPlan {
        LiveWorkoutPlan(title: title, items: exercises.compactMap { planned in
            guard let tracked = planned.definition?.tracked else { return nil }
            return LiveWorkoutItem(exercise: tracked, sets: planned.prescription.sets,
                                   target: planned.prescription.targetReps, restSeconds: planned.prescription.restSeconds)
        })
    }

    /// Exercises that must be logged manually (not camera-trackable).
    public var manualExercises: [PlannedExercise] { exercises.filter { $0.definition?.tracked == nil } }

    public var estimatedMinutes: Int {
        let seconds = exercises.reduce(0) { total, planned in
            let p = planned.prescription
            let work = planned.definition?.isTimed == true ? p.targetReps : p.targetReps * 3
            return total + p.sets * (work + p.restSeconds) + 60
        }
        return max(10, seconds / 60)
    }
}

public struct WeeklyPlan: Codable, Hashable, Sendable {
    public var workouts: [PlannedWorkout]
    public var createdAt: Date
    public var notes: [LocalizedText]

    public func workout(on weekday: Weekday) -> PlannedWorkout? { workouts.first { $0.weekday == weekday } }

    /// Next workout after the given weekday (wrapping to next week).
    public func nextWorkout(after weekday: Weekday) -> PlannedWorkout? {
        let sorted = workouts.sorted { $0.weekday < $1.weekday }
        return sorted.first { $0.weekday > weekday } ?? sorted.first
    }
}

/// Rule-based, deterministic program generator built on standard resistance-training guidance
/// (ACSM position stand on progression models; NSCA rep-range recommendations by goal).
public struct WorkoutPlanner: Sendable {
    public init() {}

    public func split(for profile: UserProfile) -> [SessionKind] {
        let days = min(6, max(1, profile.availableDays.count))
        switch days {
        case 1: return [.fullBodyA]
        case 2: return [.fullBodyA, .fullBodyB]
        case 3:
            if profile.goal == .muscular && profile.experience != .beginner { return [.push, .pull, .legs] }
            if profile.goal == .athletic || profile.goal == .leanDefined { return [.fullBodyA, .conditioning, .fullBodyB] }
            return [.fullBodyA, .fullBodyB, .fullBodyA]
        case 4:
            if profile.goal == .athletic || profile.goal == .leanDefined { return [.upper, .lower, .conditioning, .fullBodyB] }
            return [.upper, .lower, .upper, .lower]
        case 5: return [.upper, .lower, .push, .pull, .legs]
        default: return [.push, .pull, .legs, .push, .pull, .legs]
        }
    }

    /// Base prescription per goal; experience adjusts volume.
    public func prescription(for definition: ExerciseDefinition, profile: UserProfile) -> Prescription {
        var sets: Int
        var range: ClosedRange<Int>
        var rest: Int
        switch profile.goal {
        case .strong:
            sets = definition.isCompound ? 4 : 3
            range = definition.isLoaded ? (definition.isCompound ? 4...6 : 6...10) : 6...10
            rest = definition.isCompound ? 150 : 90
        case .muscular:
            sets = definition.isCompound ? 4 : 3
            range = definition.isLoaded ? 8...12 : 10...15
            rest = definition.isCompound ? 90 : 60
        case .leanDefined:
            sets = 3
            range = 12...15
            rest = 45
        case .athletic:
            sets = 3
            range = definition.isCompound ? 8...12 : 10...15
            rest = 60
        case .balanced:
            sets = 3
            range = 10...12
            rest = 60
        }
        switch profile.experience {
        case .beginner: sets = max(2, sets - 1)
        case .intermediate: break
        case .advanced: sets += definition.isCompound ? 1 : 0
        }
        if profile.limitations.contains(.highBloodPressure) || profile.limitations.contains(.heartCondition) {
            // Avoid near-maximal efforts and long breath-holding; keep moderate reps.
            range = max(range.lowerBound, 10)...max(range.upperBound, 15)
            rest = max(rest, 75)
        }
        if definition.isTimed {
            let seconds: ClosedRange<Int> = profile.experience == .beginner ? 20...40 : profile.experience == .intermediate ? 30...60 : 45...90
            return Prescription(sets: sets, repRange: seconds, targetReps: seconds.lowerBound, restSeconds: rest)
        }
        if definition.pattern == .conditioning {
            let reps: ClosedRange<Int> = profile.experience == .beginner ? 20...30 : 30...50
            return Prescription(sets: sets, repRange: reps, targetReps: reps.lowerBound, restSeconds: min(rest, 45))
        }
        return Prescription(sets: sets, repRange: range, targetReps: range.lowerBound, restSeconds: rest)
    }

    /// Picks the best exercise for a movement slot.
    func choose(_ pattern: MovementPattern, profile: UserProfile, pool: [ExerciseDefinition], usedThisWeek: [String: Int], usedToday: Set<String>) -> ExerciseDefinition? {
        let candidates = pool.filter { $0.pattern == pattern && !usedToday.contains($0.id) }
        guard !candidates.isEmpty else { return nil }
        let rank = profile.experience.rank
        return candidates.min { lhs, rhs in
            score(lhs, rank: rank, used: usedThisWeek[lhs.id] ?? 0) < score(rhs, rank: rank, used: usedThisWeek[rhs.id] ?? 0)
        }
    }

    /// Lower is better: matching difficulty, camera-trackable, loaded when equipment exists, variety.
    private func score(_ d: ExerciseDefinition, rank: Int, used: Int) -> Double {
        var s = Double(abs(d.difficulty - rank)) * 1.0
        if d.tracked == nil { s += 0.6 }
        if !d.isLoaded { s += 0.3 }
        s += Double(used) * 0.45
        // Stable tie-break by id so plans are deterministic.
        s += Double(abs(d.id.hashValueStable % 100)) / 10_000
        return s
    }

    public func makePlan(for profile: UserProfile, now: Date = Date()) -> WeeklyPlan {
        let pool = ExerciseLibrary.available(for: profile)
        let days = profile.availableDays.sorted()
        let kinds = split(for: profile)
        var usedThisWeek: [String: Int] = [:]
        var workouts: [PlannedWorkout] = []

        // Max exercises that fit in the session length (≈ 7–9 minutes per exercise).
        let maxExercises = max(3, min(7, profile.sessionMinutes / 8))

        for (index, weekday) in days.prefix(kinds.count).enumerated() {
            let kind = kinds[index]
            var usedToday: Set<String> = []
            var exercises: [PlannedExercise] = []
            for pattern in kind.slots {
                guard exercises.count < maxExercises,
                      let choice = choose(pattern, profile: profile, pool: pool, usedThisWeek: usedThisWeek, usedToday: usedToday)
                else { continue }
                usedToday.insert(choice.id)
                usedThisWeek[choice.id, default: 0] += 1
                exercises.append(PlannedExercise(exerciseId: choice.id, prescription: prescription(for: choice, profile: profile)))
            }
            workouts.append(PlannedWorkout(id: "w\(weekday)-\(kind.rawValue)", weekday: weekday, kind: kind, exercises: exercises))
        }

        var notes: [LocalizedText] = []
        if profile.limitations.contains(where: { $0.requiresClearance }) {
            notes.append(LocalizedText(tr: "Belirttiğin sağlık durumu nedeniyle antrenmana başlamadan önce doktorundan onay almanı öneririm. Program yüksek yoğunluklu hareketleri içermez.",
                                       en: "Because of the health condition you shared, please get clearance from your doctor before training. The plan avoids high-intensity movements."))
        }
        if profile.availableDays.count > kinds.count {
            notes.append(LocalizedText(tr: "Fazladan günlerini yürüyüş ve esneme gibi hafif aktivitelerle değerlendirebilirsin.",
                                       en: "Use extra days for light activity like walking and stretching."))
        }
        return WeeklyPlan(workouts: workouts, createdAt: now, notes: notes)
    }
}

extension String {
    /// Deterministic hash (Swift's `hashValue` is randomised per process).
    var hashValueStable: Int {
        var hash: UInt64 = 5381
        for byte in utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Int(truncatingIfNeeded: hash & 0x7FFF_FFFF)
    }
}
