import Foundation

public enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core, fullBody

    public var title: LocalizedText {
        switch self {
        case .chest: return LocalizedText(tr: "göğüs", en: "chest")
        case .back: return LocalizedText(tr: "sırt", en: "back")
        case .shoulders: return LocalizedText(tr: "omuz", en: "shoulders")
        case .biceps: return LocalizedText(tr: "biceps", en: "biceps")
        case .triceps: return LocalizedText(tr: "triceps", en: "triceps")
        case .quads: return LocalizedText(tr: "ön bacak", en: "quads")
        case .hamstrings: return LocalizedText(tr: "arka bacak", en: "hamstrings")
        case .glutes: return LocalizedText(tr: "kalça", en: "glutes")
        case .calves: return LocalizedText(tr: "baldır", en: "calves")
        case .core: return LocalizedText(tr: "karın", en: "core")
        case .fullBody: return LocalizedText(tr: "tüm vücut", en: "full body")
        }
    }
}

public enum MovementPattern: String, Codable, CaseIterable, Sendable {
    case squat, hinge, lunge, horizontalPush, verticalPush, horizontalPull, verticalPull
    case armFlexion, armExtension, shoulderIsolation, glute, core, conditioning
}

public struct ExerciseDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: LocalizedText
    public var pattern: MovementPattern
    public var primary: MuscleGroup
    public var secondary: [MuscleGroup]
    /// All of these are needed. Empty = bodyweight.
    public var equipment: [Equipment]
    /// 1 = easy … 3 = hard.
    public var difficulty: Int
    public var tracked: TrackedExercise?
    public var avoidWith: [HealthLimitation]
    public var isCompound: Bool
    public var isTimed: Bool
    /// Uses external load that can be increased (dumbbells, barbell, machines, kettlebell).
    public var isLoaded: Bool { !equipment.filter { $0 != .bench && $0 != .pullUpBar }.isEmpty }

    public var muscles: [MuscleGroup] { [primary] + secondary }
}

public enum ExerciseLibrary {
    private static func ex(_ id: String, _ tr: String, _ en: String, _ pattern: MovementPattern, _ primary: MuscleGroup,
                           _ secondary: [MuscleGroup] = [], equipment: [Equipment] = [], difficulty: Int = 1,
                           tracked: TrackedExercise? = nil, avoid: [HealthLimitation] = [], compound: Bool = true,
                           timed: Bool = false) -> ExerciseDefinition {
        ExerciseDefinition(id: id, name: LocalizedText(tr: tr, en: en), pattern: pattern, primary: primary, secondary: secondary,
                           equipment: equipment, difficulty: difficulty, tracked: tracked, avoidWith: avoid,
                           isCompound: compound, isTimed: timed)
    }

    public static let all: [ExerciseDefinition] = [
        // Squat pattern
        ex("squat", "Squat", "Bodyweight squat", .squat, .quads, [.glutes, .hamstrings], tracked: .squat, avoid: []),
        ex("goblet_squat", "Goblet squat", "Goblet squat", .squat, .quads, [.glutes, .core], equipment: [.dumbbells], difficulty: 2, tracked: .squat),
        ex("back_squat", "Halter squat", "Barbell back squat", .squat, .quads, [.glutes, .hamstrings, .core], equipment: [.barbell], difficulty: 3, tracked: .squat, avoid: [.lowerBack]),
        ex("leg_press", "Leg press", "Leg press", .squat, .quads, [.glutes], equipment: [.gymMachines], difficulty: 1),
        // Lunge
        ex("lunge", "Lunge", "Reverse lunge", .lunge, .quads, [.glutes], difficulty: 1, tracked: .lunge, avoid: [.knee]),
        ex("db_lunge", "Dambıl lunge", "Dumbbell lunge", .lunge, .quads, [.glutes, .hamstrings], equipment: [.dumbbells], difficulty: 2, tracked: .lunge, avoid: [.knee]),
        ex("split_squat", "Bulgar split squat", "Bulgarian split squat", .lunge, .quads, [.glutes], equipment: [.bench], difficulty: 3, avoid: [.knee]),
        // Hinge / glutes
        ex("glute_bridge", "Glute bridge", "Glute bridge", .glute, .glutes, [.hamstrings, .core], tracked: .gluteBridge, avoid: [.pregnancy]),
        ex("single_leg_bridge", "Tek bacak glute bridge", "Single-leg glute bridge", .glute, .glutes, [.hamstrings], difficulty: 2, tracked: .gluteBridge, avoid: [.pregnancy]),
        ex("db_rdl", "Dambıl Romanian deadlift", "Dumbbell Romanian deadlift", .hinge, .hamstrings, [.glutes, .back], equipment: [.dumbbells], difficulty: 2, avoid: [.lowerBack]),
        ex("bb_deadlift", "Deadlift", "Barbell deadlift", .hinge, .hamstrings, [.glutes, .back, .core], equipment: [.barbell], difficulty: 3, avoid: [.lowerBack, .highBloodPressure, .heartCondition]),
        ex("kb_swing", "Kettlebell swing", "Kettlebell swing", .hinge, .glutes, [.hamstrings, .core], equipment: [.kettlebell], difficulty: 2, avoid: [.lowerBack]),
        // Horizontal push
        ex("push_up", "Şınav", "Push-up", .horizontalPush, .chest, [.triceps, .shoulders, .core], difficulty: 2, tracked: .pushUp, avoid: [.wrist]),
        ex("incline_push_up", "Eğimli şınav", "Incline push-up", .horizontalPush, .chest, [.triceps, .shoulders], difficulty: 1, tracked: .pushUp, avoid: [.wrist]),
        ex("db_bench", "Dambıl bench press", "Dumbbell bench press", .horizontalPush, .chest, [.triceps, .shoulders], equipment: [.dumbbells, .bench], difficulty: 2),
        ex("bb_bench", "Bench press", "Barbell bench press", .horizontalPush, .chest, [.triceps, .shoulders], equipment: [.barbell, .bench], difficulty: 3, avoid: [.shoulder]),
        ex("chest_press_machine", "Göğüs press makinesi", "Machine chest press", .horizontalPush, .chest, [.triceps], equipment: [.gymMachines], difficulty: 1),
        // Vertical push
        ex("db_shoulder_press", "Dambıl omuz press", "Dumbbell shoulder press", .verticalPush, .shoulders, [.triceps], equipment: [.dumbbells], difficulty: 2, tracked: .shoulderPress, avoid: [.shoulder]),
        ex("band_shoulder_press", "Bantla omuz press", "Band shoulder press", .verticalPush, .shoulders, [.triceps], equipment: [.resistanceBands], difficulty: 1, tracked: .shoulderPress, avoid: [.shoulder]),
        ex("pike_push_up", "Pike şınav", "Pike push-up", .verticalPush, .shoulders, [.triceps], difficulty: 3, avoid: [.shoulder, .wrist, .highBloodPressure]),
        // Horizontal pull
        ex("db_row", "Tek kol dambıl row", "One-arm dumbbell row", .horizontalPull, .back, [.biceps], equipment: [.dumbbells], difficulty: 1),
        ex("band_row", "Bantla row", "Band row", .horizontalPull, .back, [.biceps], equipment: [.resistanceBands], difficulty: 1),
        ex("inverted_row", "Ters row (barda)", "Inverted row", .horizontalPull, .back, [.biceps], equipment: [.pullUpBar], difficulty: 2),
        ex("bb_row", "Halter row", "Barbell row", .horizontalPull, .back, [.biceps], equipment: [.barbell], difficulty: 3, avoid: [.lowerBack]),
        ex("cable_row", "Kablo row", "Seated cable row", .horizontalPull, .back, [.biceps], equipment: [.gymMachines], difficulty: 1),
        ex("towel_row", "Havlu row (kapı)", "Towel door row", .horizontalPull, .back, [.biceps], difficulty: 1),
        // Vertical pull
        ex("pull_up", "Barfiks", "Pull-up", .verticalPull, .back, [.biceps], equipment: [.pullUpBar], difficulty: 3, avoid: [.shoulder]),
        ex("lat_pulldown", "Lat pulldown", "Lat pulldown", .verticalPull, .back, [.biceps], equipment: [.gymMachines], difficulty: 1),
        ex("band_pulldown", "Bantla pulldown", "Band pulldown", .verticalPull, .back, [.biceps], equipment: [.resistanceBands], difficulty: 1),
        ex("superman", "Superman", "Superman hold", .verticalPull, .back, [.glutes], difficulty: 1, compound: false, timed: false),
        // Arms
        ex("db_curl", "Dambıl biceps curl", "Dumbbell biceps curl", .armFlexion, .biceps, [], equipment: [.dumbbells], difficulty: 1, tracked: .bicepsCurl, compound: false),
        ex("band_curl", "Bantla biceps curl", "Band biceps curl", .armFlexion, .biceps, [], equipment: [.resistanceBands], difficulty: 1, tracked: .bicepsCurl, compound: false),
        ex("bench_dip", "Sehpada dip", "Bench dip", .armExtension, .triceps, [.chest], difficulty: 2, avoid: [.shoulder, .wrist], compound: false),
        ex("db_overhead_ext", "Dambıl triceps extension", "Dumbbell overhead triceps extension", .armExtension, .triceps, [], equipment: [.dumbbells], difficulty: 1, avoid: [.shoulder], compound: false),
        ex("diamond_push_up", "Elmas şınav", "Diamond push-up", .armExtension, .triceps, [.chest], difficulty: 3, tracked: .pushUp, avoid: [.wrist], compound: false),
        // Shoulders
        ex("db_lateral_raise", "Dambıl yana açış", "Dumbbell lateral raise", .shoulderIsolation, .shoulders, [], equipment: [.dumbbells], difficulty: 1, tracked: .lateralRaise, compound: false),
        ex("band_lateral_raise", "Bantla yana açış", "Band lateral raise", .shoulderIsolation, .shoulders, [], equipment: [.resistanceBands], difficulty: 1, tracked: .lateralRaise, compound: false),
        ex("band_pull_apart", "Band pull-apart", "Band pull-apart", .shoulderIsolation, .shoulders, [.back], equipment: [.resistanceBands], difficulty: 1, compound: false),
        // Core
        ex("plank", "Plank", "Plank", .core, .core, [.shoulders], difficulty: 1, tracked: .plank, avoid: [.pregnancy], compound: false, timed: true),
        ex("crunch", "Mekik (crunch)", "Crunch", .core, .core, [], difficulty: 1, tracked: .crunch, avoid: [.pregnancy], compound: false),
        ex("dead_bug", "Dead bug", "Dead bug", .core, .core, [], difficulty: 1, avoid: [.pregnancy], compound: false),
        ex("side_plank", "Yan plank", "Side plank", .core, .core, [.shoulders], difficulty: 2, avoid: [.shoulder], compound: false, timed: true),
        // Conditioning
        ex("jumping_jack", "Jumping jack", "Jumping jack", .conditioning, .fullBody, [.calves, .shoulders], difficulty: 1, tracked: .jumpingJack, avoid: [.knee, .pregnancy, .heartCondition], compound: true),
        ex("march_in_place", "Yerinde yüksek diz", "High-knee march", .conditioning, .fullBody, [.core], difficulty: 1, compound: true),
        ex("mountain_climber", "Mountain climber", "Mountain climber", .conditioning, .fullBody, [.core, .shoulders], difficulty: 2, avoid: [.wrist, .highBloodPressure, .heartCondition], compound: true),
        ex("calf_raise", "Baldır kaldırma", "Calf raise", .squat, .calves, [], difficulty: 1, compound: false)
    ]

    public static func definition(_ id: String) -> ExerciseDefinition? { all.first { $0.id == id } }

    /// Exercises the user can do with their equipment and limitations.
    public static func available(for profile: UserProfile) -> [ExerciseDefinition] {
        all.filter { definition in
            definition.equipment.allSatisfy { profile.equipment.contains($0) }
                && !definition.avoidWith.contains { profile.limitations.contains($0) }
                && definition.difficulty <= profile.experience.rank + 1
        }
    }

    /// Alternatives with the same movement pattern (and primary muscle), easiest first.
    public static func alternatives(to id: String, for profile: UserProfile) -> [ExerciseDefinition] {
        guard let original = definition(id) else { return [] }
        return available(for: profile)
            .filter { $0.id != id && ($0.pattern == original.pattern || $0.primary == original.primary) }
            .sorted { lhs, rhs in
                let l = (lhs.pattern == original.pattern ? 0 : 1, abs(lhs.difficulty - original.difficulty))
                let r = (rhs.pattern == original.pattern ? 0 : 1, abs(rhs.difficulty - original.difficulty))
                return l < r
            }
    }
}
