import Foundation

/// The onboarding questions JARVIS asks (in order).
public enum OnboardingTopic: Int, CaseIterable, Sendable {
    case language, nameAndCoach, goal, body, experience, equipment, schedule, health, diet, permissions
}

public struct OnboardingVoiceResult: Equatable, Sendable {
    public var profile: UserProfile
    /// Something in the answer was understood and applied.
    public var understood: Bool
    /// The user asked to continue ("devam", "evet", "next").
    public var advance: Bool
    /// The user asked to go back.
    public var goBack: Bool
}

/// Understands spoken onboarding answers in Turkish and English ("otuz yaşındayım, boyum 180,
/// 82 kilo", "pazartesi çarşamba cuma akşam yedide", "dambıl ve barfiks barım var").
public enum OnboardingVoiceParser {
    public static func apply(_ utterance: String, topic: OnboardingTopic, to original: UserProfile) -> OnboardingVoiceResult {
        let tokens = TextNormalizer.tokens(utterance)
        let text = " " + tokens.joined(separator: " ") + " "
        var profile = original
        var understood = false

        func has(_ words: [String]) -> Bool { words.contains { text.contains(" " + $0) } }

        switch topic {
        case .language:
            if has(["turkce", "turkish"]) { profile.language = .turkish; understood = true }
            else if has(["ingilizce", "english", "inglizce"]) { profile.language = .english; understood = true }
        case .nameAndCoach:
            if let name = name(in: utterance) { profile.name = name; understood = true }
            if let p = personality(text) { profile.personality = p; understood = true }
        case .goal:
            if let g = goal(text) { profile.goal = g; understood = true }
        case .body:
            let stats = bodyStats(tokens)
            if let a = stats.age { profile.age = a; understood = true }
            if let h = stats.heightCm { profile.heightCm = h; understood = true }
            if let w = stats.weightKg { profile.weightKg = w; understood = true }
            if has(["erkek", "male", "man "]) { profile.sex = .male; understood = true }
            else if has(["kadin", "female", "woman"]) { profile.sex = .female; understood = true }
        case .experience:
            if let e = experience(text, tokens: tokens) { profile.experience = e; understood = true }
        case .equipment:
            if let e = equipment(text) { profile.equipment = e; understood = true }
        case .schedule:
            let days = weekdays(text)
            if !days.isEmpty { profile.availableDays = days; understood = true }
            if let minute = trainingMinute(tokens) { profile.preferredTrainingMinute = minute; understood = true }
            if let length = sessionLength(tokens) { profile.sessionMinutes = length; understood = true }
        case .health:
            if let l = limitations(text) { profile.limitations = l; understood = true }
        case .diet:
            if let d = diet(text) { profile.diet = d; understood = true }
        case .permissions:
            break
        }

        let advance = has(["devam", "evet", "tamam", "sonraki", "ileri", "gec", "olustur", "next", "continue", "yes", "okay", "ok ", "done", "go on"])
        let back = has(["geri", "onceki", "back", "previous"])
        return OnboardingVoiceResult(profile: profile, understood: understood, advance: advance, goBack: back && !advance)
    }

    // MARK: Pieces

    static func name(in utterance: String) -> String? {
        let words = utterance.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "." }).map(String.init)
        let normalized = words.map(TextNormalizer.normalize)
        let markers: [[String]] = [["adim"], ["ismim"], ["benim", "adim"], ["bana"], ["my", "name", "is"], ["call", "me"], ["i'm"], ["im"]]
        for marker in markers {
            for start in normalized.indices where start + marker.count < normalized.count {
                if Array(normalized[start..<start + marker.count]) == marker {
                    let candidate = words[start + marker.count].trimmingCharacters(in: .punctuationCharacters)
                    let stop: Set<String> = ["de", "diyebilirsin", "the", "a", "and", "ve", "jarvis"]
                    guard !candidate.isEmpty, !stop.contains(TextNormalizer.normalize(candidate)), candidate.count <= 20,
                          Double(candidate) == nil else { continue }
                    return candidate.prefix(1).uppercased() + candidate.dropFirst()
                }
            }
        }
        return nil
    }

    static func personality(_ text: String) -> CoachPersonality? {
        if text.contains("disiplin") || text.contains("sert") || text.contains("disciplined") || text.contains("strict") { return .disciplined }
        if text.contains("enerji") || text.contains("energetic") || text.contains("hype") { return .energetic }
        if text.contains("sakin") || text.contains(" calm") { return .calm }
        if text.contains("arkadas") || text.contains("samimi") || text.contains("friendly") || text.contains("friend") { return .friendly }
        return nil
    }

    static func goal(_ text: String) -> FitnessGoal? {
        if text.contains("yagsiz") || text.contains("belirgin") || text.contains("definasyon") || text.contains("zayifla")
            || text.contains("yag yak") || text.contains("kilo ver") || text.contains(" lean") || text.contains("defined") || text.contains("fat loss") || text.contains(" cut") { return .leanDefined }
        if text.contains("atletik") || text.contains("athletic") || text.contains("athlete") { return .athletic }
        if text.contains("guclu") || text.contains("kuvvet") || text.contains("strong") || text.contains("strength") { return .strong }
        if text.contains("dengeli") || text.contains("saglikli") || text.contains("balanced") || text.contains("healthy") { return .balanced }
        if text.contains("kasli") || text.contains("kas ") || text.contains("hacim") || text.contains("muscular") || text.contains("muscle") || text.contains("bulk") { return .muscular }
        return nil
    }

    static func experience(_ text: String, tokens: [String]) -> ExperienceLevel? {
        // "2 yıldır", "6 aydır", "for three years"
        for index in tokens.indices {
            guard let (value, length) = NumberWords.parse(tokens, at: index), index + length < tokens.count else { continue }
            let unit = tokens[index + length]
            if unit.hasPrefix("yil") || unit.hasPrefix("sene") || unit.hasPrefix("year") { return value >= 2 ? .advanced : value >= 0.5 ? .intermediate : .beginner }
            if unit.hasPrefix("ay") || unit.hasPrefix("month") { return value >= 24 ? .advanced : value >= 6 ? .intermediate : .beginner }
        }
        if text.contains("yeni") || text.contains("basla") || text.contains(" hic") || text.contains("beginner") || text.contains("never") || text.contains(" new") { return .beginner }
        if text.contains("ileri") || text.contains("yillardir") || text.contains("uzun suredir") || text.contains("advanced") { return .advanced }
        if text.contains("orta") || text.contains("biraz") || text.contains("intermediate") || text.contains("some") { return .intermediate }
        return nil
    }

    static func equipment(_ text: String) -> Set<Equipment>? {
        var result: Set<Equipment> = []
        let map: [(Equipment, [String])] = [
            (.dumbbells, ["dambil", "dumbbell", "dumbel", "dambel"]), (.barbell, ["halter", "barbell", "olimpik bar"]),
            (.bench, ["sehpa", "bench", "bank"]), (.pullUpBar, ["barfiks", "pull up", "pullup", "chin up"]),
            (.resistanceBands, ["bant", "band", "lastik"]), (.kettlebell, ["kettlebell", "kettle"]),
            (.gymMachines, ["salon", "gym", "makine", "machine"])
        ]
        for (item, words) in map where words.contains(where: { text.contains($0) }) { result.insert(item) }
        if result.isEmpty && (text.contains(" yok") || text.contains("hicbir") || text.contains("none") || text.contains("nothing") || text.contains("no equipment") || text.contains("vucut agirligi") || text.contains("bodyweight")) {
            return []
        }
        return result.isEmpty ? nil : result
    }

    static func limitations(_ text: String) -> Set<HealthLimitation>? {
        var result: Set<HealthLimitation> = []
        let map: [(HealthLimitation, [String])] = [
            (.knee, ["diz", "knee"]), (.lowerBack, [" bel ", "belim", "bel fitig", "lower back", "back pain", "sirt agri"]),
            (.shoulder, ["omuz", "shoulder"]), (.wrist, ["bilek", "wrist"]),
            (.highBloodPressure, ["tansiyon", "blood pressure", "hypertension"]), (.heartCondition, ["kalp", "heart"]),
            (.pregnancy, ["hamile", "gebe", "pregnan"])
        ]
        for (item, words) in map where words.contains(where: { text.contains($0) }) { result.insert(item) }
        if result.isEmpty && (text.contains(" yok") || text.contains(" hayir") || text.contains(" none") || text.contains(" no ") || text.contains("nothing") || text.contains("saglikliyim")) {
            return []
        }
        return result.isEmpty ? nil : result
    }

    static func diet(_ text: String) -> DietPreference? {
        if text.contains("vegan") { return .vegan }
        if text.contains("vejetaryen") || text.contains("vegetarian") { return .vegetarian }
        if text.contains("pesketaryen") || text.contains("pescatarian") || text.contains("balik") || text.contains("fish") { return .pescatarian }
        if text.contains("her sey") || text.contains("hersey") || text.contains("hepsini") || text.contains("omnivore") || text.contains("everything") || text.contains("anything") { return .omnivore }
        return nil
    }

    static func weekdays(_ text: String) -> Set<Weekday> {
        if text.contains("her gun") || text.contains("every day") || text.contains("everyday") { return Set(1...7) }
        var days: Set<Weekday> = []
        if text.contains("hafta ici") || text.contains("weekdays") { days.formUnion(1...5) }
        if text.contains("hafta sonu") || text.contains("weekend") { days.formUnion([6, 7]) }
        var rest = text
        // Longer names first: "pazartesi" contains "pazar", "cumartesi" contains "cuma".
        let names: [(Weekday, [String])] = [(1, ["pazartesi", "monday"]), (6, ["cumartesi", "saturday"]), (2, ["sali", "tuesday"]),
                                            (3, ["carsamba", "wednesday"]), (4, ["persembe", "thursday"]), (5, ["cuma", "friday"]),
                                            (7, ["pazar", "sunday"])]
        for (day, words) in names {
            for word in words where rest.contains(word) {
                days.insert(day)
                rest = rest.replacingOccurrences(of: word, with: " ")
            }
        }
        return days
    }

    /// "saat yedide", "akşam 7", "19:30", "7 pm", "sabah 8 buçukta".
    static func trainingMinute(_ tokens: [String]) -> Int? {
        let evening = tokens.contains { $0.hasPrefix("aksam") || $0 == "pm" || $0.hasPrefix("evening") || $0.hasPrefix("ogleden") }
        for index in tokens.indices {
            let token = tokens[index]
            // "19:30" survives normalisation as "19 30" or "19.30"
            let isTimeCue = index > 0 && ["saat", "at", "aksam", "sabah", "ogle", "ogleden"].contains(where: { tokens[index - 1].hasPrefix($0) })
            let nextIsCue = index + 1 < tokens.count && ["pm", "am", "o", "oclock"].contains(tokens[index + 1])
            // "19.30" / "19:30" (the normaliser turns ":" into a space, "." is kept).
            let parts = token.split(whereSeparator: { $0 == ":" || $0 == "." })
            let clock = parts.count == 2 && parts[1].count == 2
            guard isTimeCue || nextIsCue || clock else { continue }
            var hour: Double
            var minute = 0.0
            if clock, let h = Double(parts[0]), let m = Double(parts[1]) {
                hour = h; minute = m
            } else if let (value, length) = NumberWords.parse(tokens, at: index) {
                hour = value.rounded(.down)
                minute = (value - hour) * 60
                if minute == 0, index + length < tokens.count, let (m, _) = NumberWords.parse(tokens, at: index + length), m < 60, m >= 5 { minute = m }
            } else { continue }
            if evening && hour < 12 { hour += 12 }
            guard hour >= 0 && hour < 24 else { continue }
            return Int(hour) * 60 + Int(minute)
        }
        return nil
    }

    /// "45 dakika", "an hour", "1 saat".
    static func sessionLength(_ tokens: [String]) -> Int? {
        for index in tokens.indices {
            guard let (value, length) = NumberWords.parse(tokens, at: index), index + length < tokens.count else { continue }
            let unit = tokens[index + length]
            var minutes: Double?
            if unit.hasPrefix("dakika") || unit.hasPrefix("dk") || unit.hasPrefix("min") { minutes = value }
            if (unit == "saat" || unit.hasPrefix("hour")) && !(index > 0 && tokens[index - 1] == "saat") { minutes = value * 60 }
            if let minutes, minutes >= 15, minutes <= 120 {
                let options = [20, 30, 45, 60, 75]
                return options.min { abs(Double($0) - minutes) < abs(Double($1) - minutes) }
            }
        }
        return nil
    }

    static func bodyStats(_ tokens: [String]) -> (age: Int?, heightCm: Double?, weightKg: Double?) {
        var age: Int?, height: Double?, weight: Double?
        var numbers: [(value: Double, start: Int, end: Int)] = []
        var index = 0
        while index < tokens.count {
            if tokens[index] != "a" && tokens[index] != "an", let (value, length) = NumberWords.parse(tokens, at: index) {
                numbers.append((value, index, index + length))
                index += length
            } else {
                index += 1
            }
        }
        // "bir yetmiş sekiz" / "1 78" = 1.78 m
        var merged: [(value: Double, start: Int, end: Int)] = []
        for n in numbers {
            if let last = merged.last, last.end == n.start, (last.value == 1 || last.value == 2), n.value >= 10, n.value < 100 {
                merged[merged.count - 1] = (last.value * 100 + n.value, last.start, n.end)
            } else {
                merged.append(n)
            }
        }
        func keyword(near n: (value: Double, start: Int, end: Int)) -> String? {
            let window = tokens[max(0, n.start - 2)..<min(tokens.count, n.end + 2)]
            if window.contains(where: { $0.hasPrefix("yas") || $0 == "age" || $0.hasPrefix("year") }) { return "age" }
            if window.contains(where: { $0.hasPrefix("boy") || $0 == "cm" || $0.hasPrefix("santim") || $0.hasPrefix("height") || $0 == "tall" || $0.hasPrefix("metre") || $0.hasPrefix("meter") }) { return "height" }
            if window.contains(where: { $0.hasPrefix("kilo") || $0 == "kg" || $0.hasPrefix("weigh") }) { return "weight" }
            return nil
        }
        var unassigned: [Double] = []
        for n in merged {
            var value = n.value
            switch keyword(near: n) ?? "" {
            case "age" where (14...90).contains(value): age = Int(value)
            case "height":
                if value > 1.2 && value < 2.3 { value *= 100 }
                if (120...230).contains(value) { height = value }
            case "weight" where (35...250).contains(value): weight = value
            default: unassigned.append(value)
            }
        }
        // Without keywords: plausible ranges in the order asked (age, height, weight).
        for value in unassigned {
            if height == nil, (120...230).contains(value) { height = value }
            else if height == nil, value > 1.2 && value < 2.3 { height = value * 100 }
            else if age == nil, (14...90).contains(value), weight == nil || value < 35 { age = Int(value) }
            else if weight == nil, (35...250).contains(value) { weight = value }
        }
        return (age, height, weight)
    }
}
