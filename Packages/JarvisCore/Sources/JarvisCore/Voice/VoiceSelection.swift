import Foundation

/// Platform-independent description of an installed speech voice (filled from AVSpeechSynthesisVoice).
public struct VoiceCandidate: Equatable, Sendable {
    public enum Gender: Sendable { case male, female, unknown }
    /// 0 = default/compact, 1 = enhanced, 2 = premium.
    public var identifier: String
    public var name: String
    public var language: String
    public var gender: Gender
    public var quality: Int
    public var isNovelty: Bool
    public var isPersonalVoice: Bool

    public init(identifier: String, name: String, language: String, gender: Gender, quality: Int,
                isNovelty: Bool = false, isPersonalVoice: Bool = false) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.gender = gender
        self.quality = quality
        self.isNovelty = isNovelty
        self.isPersonalVoice = isPersonalVoice
    }
}

/// Which voice gender JARVIS uses.
public enum VoiceGenderPreference: String, Codable, CaseIterable, Sendable {
    /// Male voice for male users, female voice for female users.
    case matchUser, female, male

    public var title: LocalizedText {
        switch self {
        case .matchUser: return LocalizedText(tr: "Otomatik (benim cinsiyetime göre)", en: "Automatic (match me)")
        case .female: return LocalizedText(tr: "Kadın sesi", en: "Female voice")
        case .male: return LocalizedText(tr: "Erkek sesi", en: "Male voice")
        }
    }
}

public enum VoiceSelector {
    public static func desiredGender(_ preference: VoiceGenderPreference, userSex: BiologicalSex) -> VoiceCandidate.Gender {
        switch preference {
        case .female: return .female
        case .male: return .male
        case .matchUser: return userSex == .male ? .male : .female
        }
    }

    /// Best voice for the language: right gender first, then quality (premium > enhanced > default);
    /// novelty voices and the user's Personal Voice are never chosen automatically. When no voice of
    /// the wanted gender exists, the best other voice is used (`genderMatched` = false).
    public static func best(from voices: [VoiceCandidate], language: AppLanguage, gender: VoiceCandidate.Gender,
                            preferredRegion: String? = nil) -> (voice: VoiceCandidate, genderMatched: Bool)? {
        let usable = voices.filter { $0.language.hasPrefix(language.rawValue) && !$0.isNovelty && !$0.isPersonalVoice }
        guard !usable.isEmpty else { return nil }
        func score(_ v: VoiceCandidate) -> Int {
            var s = v.quality * 10
            if v.gender == gender { s += 100 }
            if let region = preferredRegion, v.language == region { s += 3 }
            return s
        }
        let sorted = usable.sorted { score($0) == score($1) ? $0.name < $1.name : score($0) > score($1) }
        let chosen = sorted[0]
        return (chosen, chosen.gender == gender)
    }

    /// True when a better voice could be downloaded (only compact voices of the wanted gender installed).
    public static func shouldSuggestDownload(_ chosen: VoiceCandidate, wanted: VoiceCandidate.Gender) -> Bool {
        chosen.quality < 1 || chosen.gender != wanted
    }
}

/// Delivery per coach personality (applied on top of the system rate).
public struct VoiceProsody: Equatable, Sendable {
    public var rateMultiplier: Double
    public var pitchMultiplier: Double
    /// Seconds of silence before / after a sentence.
    public var preDelay: Double
    public var postDelay: Double

    public static func `for`(_ personality: CoachPersonality) -> VoiceProsody {
        switch personality {
        case .disciplined: return VoiceProsody(rateMultiplier: 1.0, pitchMultiplier: 0.95, preDelay: 0, postDelay: 0.05)
        case .friendly: return VoiceProsody(rateMultiplier: 0.97, pitchMultiplier: 1.03, preDelay: 0, postDelay: 0.08)
        case .energetic: return VoiceProsody(rateMultiplier: 1.07, pitchMultiplier: 1.06, preDelay: 0, postDelay: 0.03)
        case .calm: return VoiceProsody(rateMultiplier: 0.9, pitchMultiplier: 0.97, preDelay: 0.05, postDelay: 0.15)
        }
    }
}
