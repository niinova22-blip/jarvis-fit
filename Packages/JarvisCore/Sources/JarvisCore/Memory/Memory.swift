import Foundation

public enum MemoryKind: String, Codable, CaseIterable, Sendable {
    case achievement, struggle, likes, dislikes, goal, nutrition, note

    public var title: LocalizedText {
        switch self {
        case .achievement: return LocalizedText(tr: "Başarı", en: "Achievement")
        case .struggle: return LocalizedText(tr: "Zorlandığın", en: "Struggles with")
        case .likes: return LocalizedText(tr: "Sevdiğin", en: "Likes")
        case .dislikes: return LocalizedText(tr: "Sevmediğin", en: "Dislikes")
        case .goal: return LocalizedText(tr: "Hedef", en: "Goal")
        case .nutrition: return LocalizedText(tr: "Beslenme", en: "Nutrition")
        case .note: return LocalizedText(tr: "Not", en: "Note")
        }
    }
}

/// A single fact JARVIS remembers. Only short facts are stored — never raw conversations.
public struct MemoryItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: MemoryKind
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), kind: MemoryKind, text: String, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
    }
}

/// Extracts rememberable facts from what the user says, with data minimisation: contact details,
/// long numbers and anything longer than a short phrase are dropped.
public enum MemoryExtractor {
    private static let rules: [(MemoryKind, [String])] = [
        (.likes, ["seviyorum", "en sevdigim", "hosuma gidiyor", "bayiliyorum", "i love", "i like", "i enjoy", "my favorite", "my favourite"]),
        (.dislikes, ["sevmiyorum", "nefret ediyorum", "hoslanmiyorum", "i hate", "i dont like", "i don't like", "i dislike"]),
        (.struggle, ["zorlaniyorum", "zorlandim", "yapamiyorum", "beceremiyorum", "i struggle", "i can't do", "i cant do", "hard for me"]),
        (.goal, ["hedefim", "istiyorum ki", "my goal", "i want to"]),
        (.nutrition, ["vegan oldum", "vejetaryen oldum", "laktoz", "glutensiz", "alerjim", "alerjik", "i'm vegan", "im vegan", "vegetarian now", "lactose", "gluten", "allergic"])
    ]

    public static func extract(from utterance: String, now: Date = Date()) -> MemoryItem? {
        let normalized = TextNormalizer.normalize(utterance)
        guard let (kind, _) = rules.first(where: { _, keys in keys.contains { normalized.contains(TextNormalizer.normalize($0)) } }) else {
            return nil
        }
        let cleaned = sanitize(utterance)
        guard cleaned.count >= 4 && cleaned.count <= 160 else { return nil }
        return MemoryItem(kind: kind, text: cleaned, createdAt: now)
    }

    /// Removes the wake word, e-mail addresses and digit sequences of 7+ (phone/ID numbers).
    public static func sanitize(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        words.removeAll { word in
            let lower = word.lowercased()
            if lower.hasPrefix("jarvis") { return true }
            if lower.contains("@") { return true }
            return lower.filter(\.isNumber).count >= 7
        }
        return words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
    }

    /// Achievement facts derived from a workout (personal bests).
    public static func achievements(from summary: WorkoutSummary, previousBest: [TrackedExercise: Int], language: AppLanguage, date: Date) -> [MemoryItem] {
        var items: [MemoryItem] = []
        var best: [TrackedExercise: Int] = [:]
        for set in summary.sets { best[set.exercise] = max(best[set.exercise] ?? 0, set.achieved) }
        for (exercise, value) in best {
            let previous = previousBest[exercise] ?? 0
            guard previous > 0, value > previous else { continue }
            let unit = exercise.isTimed ? (language == .turkish ? "saniye" : "seconds") : (language == .turkish ? "tekrar" : "reps")
            let text = language == .turkish
                ? "\(exercise.name.tr) rekoru: tek sette \(value) \(unit) (önceki \(previous))"
                : "\(exercise.name.en) record: \(value) \(unit) in one set (previous \(previous))"
            items.append(MemoryItem(kind: .achievement, text: text, createdAt: date))
        }
        return items
    }
}
