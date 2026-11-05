import Foundation

/// Semantic things the coach wants to say. `CoachVoice` turns them into personality-specific text.
public enum CoachCue: Equatable, Sendable {
    case welcome(exerciseCount: Int)
    case setup(TrackedExercise)
    case framing(FramingStatus)
    case countdown(Int)
    case go(TrackedExercise, set: Int, totalSets: Int, target: Int)
    case rep(Int)
    case repsRemaining(Int)
    case holdProgress(seconds: Int, target: Int)
    case holdStarted
    case holdPaused(FormIssue?)
    case formCue(FormIssue)
    case partialRep(FormIssue?)
    case setComplete(reps: Int, set: Int, totalSets: Int, timed: Bool)
    case restStart(seconds: Int, next: TrackedExercise, nextIsNewExercise: Bool)
    case restRemaining(seconds: Int)
    case restExtended(seconds: Int)
    case nextExercise(TrackedExercise)
    case paused
    case resumed
    case targetAdjusted(newTarget: Int, easier: Bool)
    case encouragement
    case wrongExercise(detected: TrackedExercise, expected: TrackedExercise)
    case lostTracking
    case workoutComplete(totalReps: Int, minutes: Int, sets: Int)
    case safetyStop(SafetyConcern)
    case answer(LocalizedText)
    case notUnderstood

    /// Cues that must be heard even if something else is being said.
    public var priority: CuePriority {
        switch self {
        case .safetyStop: return .critical
        case .rep, .holdProgress: return .immediate
        case .setComplete, .go, .countdown, .workoutComplete, .answer, .paused, .resumed, .restStart: return .high
        case .formCue, .partialRep, .repsRemaining, .holdPaused, .framing, .lostTracking: return .normal
        default: return .low
        }
    }
}

public enum CuePriority: Int, Comparable, Sendable {
    case low = 0, normal = 1, high = 2, immediate = 3, critical = 4
    public static func < (a: CuePriority, b: CuePriority) -> Bool { a.rawValue < b.rawValue }
}

public enum CoachPersonality: String, Codable, CaseIterable, Sendable {
    case disciplined, friendly, energetic, calm

    public var title: LocalizedText {
        switch self {
        case .disciplined: return LocalizedText(tr: "Disiplinli", en: "Disciplined")
        case .friendly: return LocalizedText(tr: "Arkadaş canlısı", en: "Friendly")
        case .energetic: return LocalizedText(tr: "Enerjik", en: "Energetic")
        case .calm: return LocalizedText(tr: "Sakin", en: "Calm")
        }
    }

    public var summary: LocalizedText {
        switch self {
        case .disciplined: return LocalizedText(tr: "Net, kısa ve hedef odaklı komutlar.", en: "Clear, short, goal-driven commands.")
        case .friendly: return LocalizedText(tr: "Sıcak, destekleyici ve samimi.", en: "Warm, supportive and personal.")
        case .energetic: return LocalizedText(tr: "Yüksek tempo, bol motivasyon.", en: "High tempo, lots of hype.")
        case .calm: return LocalizedText(tr: "Sakin, odaklı ve nefes farkındalığı yüksek.", en: "Calm, focused and breath-aware.")
        }
    }

    /// Speech rate multiplier for the synthesiser.
    public var speechRate: Double {
        switch self {
        case .disciplined: return 1.0
        case .friendly: return 0.97
        case .energetic: return 1.08
        case .calm: return 0.9
        }
    }
}
