import Foundation

/// Turns display text into text a speech synthesizer reads correctly: numbers, units, times, ranges,
/// percentages and ordinals become words; markdown, list markers and emoji are removed; English
/// exercise names are respelled so a Turkish voice pronounces them the way Turkish speakers do.
///
/// Used before every utterance (Apple voices) and required by an own neural voice later, which
/// cannot read digits or abbreviations at all.
public enum SpeechText {
    public static func prepare(_ text: String, language: AppLanguage) -> String {
        let tr = language == .turkish
        let num = numberPattern(language)
        var s = cleanUp(text, language: language)
        s = applyLexicon(s, language: language)

        // Times: 19:00, 07:30
        s = sub(s, #"\b([01]?\d|2[0-3]):([0-5]\d)(?!\d)"#) { m in
            spellTime(hour: Int(group(m, 1)) ?? 0, minute: Int(group(m, 2)) ?? 0, language: language)
        }
        // Sets x reps: 3x12
        s = sub(s, #"\b(\d{1,2})\s?[x×X]\s?(\d{1,3})(?!\d)"#) { m in
            let sets = Int(group(m, 1)) ?? 0, reps = Int(group(m, 2)) ?? 0
            return tr ? "\(spell(sets, language: language)) set \(spell(reps, language: language)) tekrar"
                : "\(spell(sets, language: language)) \(sets == 1 ? "set" : "sets") of \(spell(reps, language: language))"
        }
        // Percentages: %20 (Turkish) or 20%
        s = sub(s, "%\\s?(\(num))") { m in percent(group(m, 1), language: language) }
        s = sub(s, "(\(num))\\s?%") { m in percent(group(m, 1), language: language) }
        // Ranges: 60–90
        s = sub(s, #"(\d)\s?[–—-]\s?(\d)"#) { m in "\(group(m, 1)) \(tr ? "ila" : "to") \(group(m, 2))" }
        // Signs: +1.2, -0.5
        s = sub(s, #"(^|[\s(])([+−-])(?=\d)"#) { m in
            let plus = group(m, 2) == "+"
            return group(m, 1) + (tr ? (plus ? "artı " : "eksi ") : (plus ? "plus " : "minus "))
        }
        // Ordinals: "2. set" (Turkish), "2nd" (English)
        if tr {
            s = sub(s, #"(\d+)\.(?=\s+\p{Ll})"#) { m in ordinal(Int(group(m, 1)) ?? 0, language: language) }
        } else {
            s = sub(s, #"(\d+)(?:st|nd|rd|th)\b"#) { m in ordinal(Int(group(m, 1)) ?? 0, language: language) }
        }
        // Number + unit: 140 g, 1.6 g/kg, 45 sn
        s = sub(s, "(\(num))\\s?(g/kg|kcal|kg|km|cm|ml|gr|g|sn|sec|dk|min|s)(?![\\p{L}\\d/])") { m in
            unit(group(m, 2), number: group(m, 1), language: language)
        }
        // Remaining numbers
        s = sub(s, num) { m in spellNumber(String(m.output[0].substring ?? ""), language: language) }
        // Turkish suffixes written after an apostrophe belong to the word: "yedi'de" -> "yedide".
        if tr { s = sub(s, #"(\p{L})['’](\p{L})"#) { m in group(m, 1) + group(m, 2) } }
        s = sub(s, #"\s+([.,!?;:…])"#) { m in group(m, 1) }
        s = sub(s, #"\s{2,}"#) { _ in " " }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits prepared text into sentences so a neural voice can start speaking after the first one.
    /// "a.m." / "p.m." do not end a sentence.
    public static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            guard ".!?…;".contains(ch), i + 1 == chars.count || chars[i + 1] == " " else { continue }
            if ch == ".", current.hasSuffix("a.m.") || current.hasSuffix("p.m."),
               i + 2 < chars.count, chars[i + 2].isLowercase { continue }
            let sentence = current.trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty { result.append(sentence) }
            current = ""
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    // MARK: Numbers

    public static func spell(_ n: Int, language: AppLanguage) -> String {
        if n < 0 { return (language == .turkish ? "eksi " : "minus ") + spell(-n, language: language) }
        if n == 0 { return language == .turkish ? "sıfır" : "zero" }
        var rest = n
        var words: [String] = []
        let scales: [(Int, String, String)] = [(1_000_000_000, "milyar", "billion"), (1_000_000, "milyon", "million"), (1000, "bin", "thousand")]
        for (scale, trName, enName) in scales where rest >= scale {
            let count = rest / scale
            rest %= scale
            if language == .turkish {
                if !(scale == 1000 && count == 1) { words += below1000(count, language: language) }
                words.append(trName)
            } else {
                words += below1000(count, language: language) + [enName]
            }
        }
        words += below1000(rest, language: language)
        return words.joined(separator: " ")
    }

    private static let trOnes = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
    private static let trTens = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]
    private static let enOnes = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
                                 "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let enTens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    private static func below1000(_ n: Int, language: AppLanguage) -> [String] {
        var words: [String] = []
        let hundreds = n / 100, rest = n % 100
        if language == .turkish {
            if hundreds > 0 { words += (hundreds > 1 ? [trOnes[hundreds]] : []) + ["yüz"] }
            if rest / 10 > 0 { words.append(trTens[rest / 10]) }
            if rest % 10 > 0 { words.append(trOnes[rest % 10]) }
        } else {
            if hundreds > 0 { words += [enOnes[hundreds], "hundred"] }
            if rest >= 20 {
                words.append(enTens[rest / 10])
                if rest % 10 > 0 { words.append(enOnes[rest % 10]) }
            } else if rest > 0 {
                words.append(enOnes[rest])
            }
        }
        return words
    }

    public static func ordinal(_ n: Int, language: AppLanguage) -> String {
        var words = spell(n, language: language).split(separator: " ").map(String.init)
        guard var last = words.popLast() else { return "" }
        if language == .turkish {
            if last == "dört" {
                last = "dördüncü"
            } else {
                let vowels: Set<Character> = ["a", "ı", "o", "u", "e", "i", "ö", "ü"]
                let suffix: String
                switch last.last(where: { vowels.contains($0) }) ?? "i" {
                case "a", "ı": suffix = "ıncı"
                case "e", "i": suffix = "inci"
                case "o", "u": suffix = "uncu"
                default: suffix = "üncü"
                }
                last += vowels.contains(last.last ?? " ") ? String(suffix.dropFirst()) : suffix
            }
        } else {
            let irregular = ["one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth",
                             "nine": "ninth", "twelve": "twelfth"]
            if let word = irregular[last] { last = word } else if last.hasSuffix("y") { last = last.dropLast() + "ieth" } else { last += "th" }
        }
        return (words + [last]).joined(separator: " ")
    }

    private static func numberPattern(_ language: AppLanguage) -> String {
        language == .turkish
            ? #"(?:\d{1,3}(?:\.\d{3})+(?:,\d+)?(?!\d)|\d+(?:[.,]\d+)?)"#
            : #"(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?(?!\d)|\d+(?:\.\d+)?)"#
    }

    /// Integer and fraction digits of a written number ("2.450" is 2450 in Turkish, "1,5" is 1.5).
    private static func parts(_ raw: String, language: AppLanguage) -> (integer: String, fraction: String?) {
        if language == .turkish {
            if let comma = raw.lastIndex(of: ",") {
                return (raw[..<comma].replacingOccurrences(of: ".", with: ""), String(raw[raw.index(after: comma)...]))
            }
            let groups = raw.split(separator: ".").map(String.init)
            if groups.count > 1 && groups.dropFirst().allSatisfy({ $0.count == 3 }) { return (groups.joined(), nil) }
            return (groups.first ?? raw, groups.count > 1 ? groups[1] : nil)
        }
        let plain = raw.replacingOccurrences(of: ",", with: "")
        let groups = plain.split(separator: ".").map(String.init)
        return (groups.first ?? plain, groups.count > 1 ? groups[1] : nil)
    }

    private static func spellDigits(_ digits: String, language: AppLanguage) -> String {
        digits.compactMap { $0.wholeNumberValue }.map { spell($0, language: language) }.joined(separator: " ")
    }

    static func spellNumber(_ raw: String, language: AppLanguage) -> String {
        let (integerDigits, fraction) = parts(raw, language: language)
        guard integerDigits.count <= 15, let integer = Int(integerDigits) else { return spellDigits(raw, language: language) }
        let whole = spell(integer, language: language)
        guard let fraction, !fraction.isEmpty else { return whole }
        if language == .english { return "\(whole) point \(spellDigits(fraction, language: language))" }
        if fraction == "5" { return integer == 0 ? "yarım" : "\(whole) buçuk" }
        let zeros = fraction.prefix { $0 == "0" }
        let rest = fraction.dropFirst(zeros.count)
        var words = zeros.map { _ in "sıfır" }
        if !rest.isEmpty, rest.count <= 15, let value = Int(rest) { words.append(spell(value, language: language)) }
        return "\(whole) virgül \(words.joined(separator: " "))"
    }

    private static func percent(_ raw: String, language: AppLanguage) -> String {
        let words = spellNumber(raw, language: language)
        return language == .turkish ? "yüzde \(words)" : "\(words) percent"
    }

    private static func spellTime(hour: Int, minute: Int, language: AppLanguage) -> String {
        if language == .turkish {
            var s = spell(hour, language: language)
            if minute > 0 { s += (minute < 10 ? " sıfır " : " ") + spell(minute, language: language) }
            return s
        }
        var s = spell(hour % 12 == 0 ? 12 : hour % 12, language: language)
        if minute > 0 { s += (minute < 10 ? " oh " : " ") + spell(minute, language: language) }
        return s + (hour < 12 ? " a.m." : " p.m.")
    }

    // MARK: Units

    private static let units: [String: (tr: String, en: String, enPlural: String)] = [
        "g": ("gram", "gram", "grams"), "gr": ("gram", "gram", "grams"),
        "kg": ("kilo", "kilogram", "kilograms"), "kcal": ("kalori", "calorie", "calories"),
        "km": ("kilometre", "kilometer", "kilometers"), "cm": ("santim", "centimeter", "centimeters"),
        "ml": ("mililitre", "milliliter", "milliliters"),
        "sn": ("saniye", "second", "seconds"), "s": ("saniye", "second", "seconds"), "sec": ("saniye", "second", "seconds"),
        "dk": ("dakika", "minute", "minutes"), "min": ("dakika", "minute", "minutes")
    ]

    private static func unit(_ symbol: String, number raw: String, language: AppLanguage) -> String {
        let words = spellNumber(raw, language: language)
        let (integer, fraction) = parts(raw, language: language)
        let isOne = integer == "1" && (fraction ?? "").isEmpty
        if symbol == "g/kg" {
            return language == .turkish ? "kilo başına \(words) gram" : "\(words) \(isOne ? "gram" : "grams") per kilogram"
        }
        guard let names = units[symbol] else { return "\(words) \(symbol)" }
        return "\(words) \(language == .turkish ? names.tr : isOne ? names.en : names.enPlural)"
    }

    // MARK: Pronunciation

    /// Turkish respellings of English fitness words (matched at word start, so suffixes are kept:
    /// "squatlar" -> "skuatlar"). Longer phrases first.
    private static let turkishLexicon: [(String, String)] = [
        ("nova coach", "Nova Koç"), ("nova", "Nova"), ("jarvis fit", "Carvis Fit"), ("jarvis", "Carvis"),
        ("push-up", "puşap"), ("push up", "puşap"), ("pushup", "puşap"),
        ("jumping jack", "camping cek"), ("biceps curl", "bayseps körl"), ("biceps", "bayseps"),
        ("glute bridge", "glut briç"), ("shoulder press", "şoldır pres"), ("lateral raise", "laterıl reyz"),
        ("squat", "skuat"), ("lunge", "lanç"), ("plank", "plenk"), ("press", "pres"), ("crunch", "kranç"),
        ("deadlift", "dedlift"), ("burpee", "börpi"), ("cardio", "kardiyo"), ("fit check", "fit çek"), ("iphone", "ayfon")
    ]
    /// All-caps names are spelled letter by letter by English voices.
    private static let englishLexicon: [(String, String)] = [("nova coach", "Nova Coach"), ("nova", "Nova"), ("jarvis fit", "Jarvis Fit"), ("jarvis", "Jarvis")]

    private static func applyLexicon(_ text: String, language: AppLanguage) -> String {
        let tr = language == .turkish
        var s = text
        for (word, spoken) in tr ? turkishLexicon : englishLexicon {
            let escaped = NSRegularExpression.escapedPattern(for: word)
            s = sub(s, "(?i)\\b" + escaped + (tr ? "" : "\\b")) { m in
                let original = String(m.output[0].substring ?? "")
                guard original.first?.isUppercase == true else { return spoken }
                return spoken.prefix(1).uppercased() + spoken.dropFirst()
            }
        }
        return s
    }

    // MARK: Cleanup

    private static func cleanUp(_ text: String, language: AppLanguage) -> String {
        var s = text
        for marker in ["**", "__", "*", "`"] { s = s.replacingOccurrences(of: marker, with: "") }
        let tr = language == .turkish
        s = s.replacingOccurrences(of: "≈", with: tr ? " yaklaşık " : " about ")
        s = s.replacingOccurrences(of: "→", with: ", ")
        s = s.replacingOccurrences(of: " & ", with: tr ? " ve " : " and ")
        s = sub(s, #"~\s?(?=\d)"#) { _ in tr ? "yaklaşık " : "about " }
        s = String(String.UnicodeScalarView(s.unicodeScalars.filter { !isEmoji($0) }))

        var lines = s.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let marker = lines.count > 1 ? #"^(?:#+\s*|[-•]\s+|\d+[.)]\s+)"# : #"^(?:#+\s*|[-•]\s+)"#
        lines = lines.map { sub($0, marker) { _ in "" }.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.count > 1 {
            lines = lines.map { line in
                guard let last = line.last, !".!?…:;,".contains(last) else { return line }
                return line + "."
            }
        }
        return lines.joined(separator: " ")
    }

    private static func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
        let p = scalar.properties
        if [0xFE0F, 0x200D, 0x20E3].contains(scalar.value) { return true }
        return p.isEmojiPresentation || p.isEmojiModifier || (p.isEmoji && scalar.value >= 0x2190)
    }

    // MARK: Regex helpers

    private static func sub(_ text: String, _ pattern: String, _ transform: (Regex<AnyRegexOutput>.Match) -> String) -> String {
        guard let regex = try? Regex(pattern) else {
            assertionFailure("Invalid pattern: \(pattern)")
            return text
        }
        return text.replacing(regex) { transform($0) }
    }

    private static func group(_ match: Regex<AnyRegexOutput>.Match, _ index: Int) -> String {
        match.output[index].substring.map(String.init) ?? ""
    }
}
