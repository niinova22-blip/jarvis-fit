import Foundation

/// Languages supported by JARVIS (speech recognition, phrases, parsing).
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case turkish = "tr"
    case english = "en"

    /// BCP-47 locale identifier used for speech recognition and synthesis.
    public var localeIdentifier: String {
        switch self {
        case .turkish: return "tr-TR"
        case .english: return "en-US"
        }
    }

    /// Picks the app language from a preferred-language list (e.g. `Locale.preferredLanguages`).
    public static func from(preferred: [String]) -> AppLanguage {
        for identifier in preferred {
            let lower = identifier.lowercased()
            if lower.hasPrefix("tr") { return .turkish }
            if lower.hasPrefix("en") { return .english }
        }
        return .english
    }
}

/// A pair of Turkish/English strings; the app resolves it with the active language.
public struct LocalizedText: Codable, Hashable, Sendable {
    public var tr: String
    public var en: String

    public init(tr: String, en: String) {
        self.tr = tr
        self.en = en
    }

    public func resolve(_ language: AppLanguage) -> String {
        language == .turkish ? tr : en
    }
}

/// Text normalisation shared by the parsers: lower-cases with Turkish rules, folds diacritics
/// for matching and collapses punctuation.
public enum TextNormalizer {
    public static func normalize(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "I": result.append("ı")
            case "İ": result.append("i")
            default: result.append(String(scalar).lowercased())
            }
        }
        // Fold Turkish letters to ASCII so speech-recogniser spelling variations still match.
        let folded = result
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
            .replacingOccurrences(of: "â", with: "a")
            .replacingOccurrences(of: "î", with: "i")
            .replacingOccurrences(of: "û", with: "u")
        var cleaned = ""
        var lastWasSpace = false
        for character in folded {
            if character.isLetter || character.isNumber || character == "." || character == "," {
                cleaned.append(character)
                lastWasSpace = false
            } else if !lastWasSpace {
                cleaned.append(" ")
                lastWasSpace = true
            }
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    public static func tokens(_ text: String) -> [String] {
        // A comma between digits is a Turkish decimal separator ("1,5"); otherwise a separator.
        let chars = Array(normalize(text))
        var joined = ""
        for (index, character) in chars.enumerated() {
            if character == "," {
                let before = index > 0 && chars[index - 1].isNumber
                let after = index + 1 < chars.count && chars[index + 1].isNumber
                joined.append(before && after ? "." : " ")
            } else {
                joined.append(character)
            }
        }
        return joined
            .split(separator: " ")
            .map { token in
                var t = String(token)
                while t.hasSuffix(".") { t.removeLast() }
                return t
            }
            .filter { !$0.isEmpty }
    }
}
