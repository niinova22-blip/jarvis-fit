import Foundation

/// Text -> IPA phonemes for JARVIS's own neural voices (Piper/VITS models trained with
/// `phoneme_type text`). Port of `tools/voice/phonemes.py`; both are checked against the same
/// golden file, because the model only works with exactly the phonemes it was trained on.
/// No espeak-ng (GPL) is involved.
public enum Phonemizer {
    static let punctuation: Set<Character> = [",", ".", "?", "!", ";", ":"]

    // MARK: Turkish (spelling is close to phonemic)

    private static let turkishMap: [Character: String] = [
        "a": "a", "â": "a", "b": "b", "c": "dʒ", "ç": "tʃ", "d": "d", "e": "e", "f": "f", "g": "ɡ", "h": "h",
        "ı": "ɯ", "i": "i", "î": "i", "j": "ʒ", "k": "k", "l": "l", "m": "m", "n": "n", "o": "o", "ö": "œ",
        "p": "p", "r": "ɾ", "s": "s", "ş": "ʃ", "t": "t", "u": "u", "û": "u", "ü": "y", "v": "v", "y": "j",
        "z": "z", "q": "k", "w": "v", "x": "ks"
    ]
    private static let turkishVowels: Set<Character> = ["a", "â", "e", "ı", "i", "î", "o", "ö", "u", "û", "ü"]

    public static func turkish(_ text: String) -> String {
        let lowered = text.replacingOccurrences(of: "I", with: "ı").replacingOccurrences(of: "İ", with: "i")
            .lowercased().precomposedStringWithCanonicalMapping
        let joined = replace(lowered, #"(\w)['’](\w)"#) { "\($0[1])\($0[2])" }
        let chars = Array(joined)
        var out = ""
        for (i, ch) in chars.enumerated() {
            if ch == "ğ" {
                let prev: Character? = i > 0 ? chars[i - 1] : nil
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                // Silent between vowels; lengthens the vowel before a consonant or the end.
                if let prev, turkishVowels.contains(prev), !(next.map(turkishVowels.contains) ?? false) { out += "ː" }
            } else if let ipa = turkishMap[ch] {
                out += ipa
            } else if punctuation.contains(ch) {
                out.append(ch)
            } else if ch.isWhitespace || ch == "-" || ch == "–" || ch == "—" {
                out += " "
            }
        }
        return tidy(out)
    }

    // MARK: English (dictionary + letter rules)

    private static let letterNames: [Character: String] = [
        "a": "eɪ", "b": "biː", "c": "siː", "d": "diː", "e": "iː", "f": "ɛf", "g": "dʒiː", "h": "eɪtʃ", "i": "aɪ",
        "j": "dʒeɪ", "k": "keɪ", "l": "ɛl", "m": "ɛm", "n": "ɛn", "o": "oʊ", "p": "piː", "q": "kjuː", "r": "ɑːɹ",
        "s": "ɛs", "t": "tiː", "u": "juː", "v": "viː", "w": "dʌbəljuː", "x": "ɛks", "y": "waɪ", "z": "ziː"
    ]
    private static let letterRules: [(String, String)] = [
        ("tion", "ʃən"), ("sion", "ʒən"), ("ough", "oʊ"), ("igh", "aɪ"), ("tch", "tʃ"), ("sch", "sk"),
        ("ch", "tʃ"), ("sh", "ʃ"), ("th", "θ"), ("ph", "f"), ("wh", "w"), ("ck", "k"), ("ng", "ŋ"), ("qu", "kw"),
        ("ee", "iː"), ("ea", "iː"), ("oo", "uː"), ("ou", "aʊ"), ("ow", "aʊ"), ("oi", "ɔɪ"), ("oy", "ɔɪ"),
        ("ai", "eɪ"), ("ay", "eɪ"), ("au", "ɔː"), ("aw", "ɔː"), ("er", "ɚ"), ("ir", "ɜː"), ("ur", "ɜː"),
        ("ar", "ɑːɹ"), ("or", "ɔːɹ"),
        ("a", "æ"), ("b", "b"), ("c", "k"), ("d", "d"), ("e", "ɛ"), ("f", "f"), ("g", "ɡ"), ("h", "h"), ("i", "ɪ"),
        ("j", "dʒ"), ("k", "k"), ("l", "l"), ("m", "m"), ("n", "n"), ("o", "ɑː"), ("p", "p"), ("q", "k"), ("r", "ɹ"),
        ("s", "s"), ("t", "t"), ("u", "ʌ"), ("v", "v"), ("w", "w"), ("x", "ks"), ("y", "j"), ("z", "z")
    ]

    /// Lexicon file format: one `word<TAB>ipa` per line (generated from CMUdict by `tools/voice/export_lexicon.py`).
    public static func loadLexicon(_ contents: String) -> [String: String] {
        var lexicon: [String: String] = [:]
        lexicon.reserveCapacity(140_000)
        for line in contents.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            lexicon[String(line[..<tab])] = String(line[line.index(after: tab)...])
        }
        return lexicon
    }

    public static func english(_ text: String, lexicon: [String: String]) -> String {
        var s = text.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "’", with: "'")
        // "a.m." / "p.m." and other dotted initialisms: spell the letters.
        s = replace(s, #"\b((?:[A-Za-z]\.){2,})"#) { m in
            m[1].replacingOccurrences(of: ".", with: "").map { "#\($0)" }.joined(separator: " ") + " "
        }
        var out = ""
        for token in matches(s, #"#[A-Za-z]|[A-Za-z']+|[,.?!;:]"#) {
            if token.hasPrefix("#") {
                out += " ˈ" + (letterNames[Character(token.dropFirst().lowercased())] ?? "") + " "
            } else if token.count == 1, let ch = token.first, punctuation.contains(ch) {
                out += token
            } else {
                out += " " + englishWord(token.lowercased(), lexicon: lexicon) + " "
            }
        }
        return tidy(out)
    }

    static func englishWord(_ word: String, lexicon: [String: String]) -> String {
        if let ipa = lexicon[word] { return ipa }
        if word.hasSuffix("'s"), let base = lexicon[String(word.dropLast(2))] {
            let last = base.unicodeScalars.last.map(Character.init) ?? " "
            return base + ("szʃʒ".contains(last) ? "ɪz" : "ptkfθ".contains(last) ? "s" : "z")
        }
        let stripped = word.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        if stripped != word { return englishWord(stripped, lexicon: lexicon) }
        return applyLetterRules(word)
    }

    private static func applyLetterRules(_ word: String) -> String {
        var out: [String] = []
        var rest = Substring(word)
        while !rest.isEmpty {
            if let (graph, ipa) = letterRules.first(where: { rest.hasPrefix($0.0) }) {
                out.append(ipa)
                rest = rest.dropFirst(graph.count)
            } else {
                rest = rest.dropFirst()
            }
        }
        if word.hasSuffix("e") && word.count > 2 && out.last == "ɛ" { out.removeLast() } // silent final e
        return out.isEmpty ? "" : "ˈ" + out.joined()
    }

    // MARK: Phoneme ids (Piper)

    /// Piper's id sequence: BOS, PAD, then each phoneme codepoint (NFD) followed by PAD, then EOS.
    /// Codepoints missing from the map are skipped, as in Piper.
    public static func phonemeIds(_ phonemes: String, idMap: [String: Int]) -> [Int] {
        guard let bos = idMap["^"], let eos = idMap["$"], let pad = idMap["_"] else { return [] }
        var ids = [bos, pad]
        for scalar in phonemes.decomposedStringWithCanonicalMapping.unicodeScalars {
            guard let id = idMap[String(scalar)] else { continue }
            ids += [id, pad]
        }
        ids.append(eos)
        return ids
    }

    // MARK: Helpers

    static func tidy(_ phonemes: String) -> String {
        var s = replace(phonemes, #"\s+([,.?!;:])"#) { $0[1] }
        s = replace(s, #"([,.?!;:])(?=[^\s,.?!;:])"#) { $0[1] + " " }
        s = replace(s, #"\s+"#) { _ in " " }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func replace(_ text: String, _ pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? Regex(pattern) else { return text }
        return text.replacing(regex) { match in
            transform((0..<match.output.count).map { match.output[$0].substring.map(String.init) ?? "" })
        }
    }

    private static func matches(_ text: String, _ pattern: String) -> [String] {
        guard let regex = try? Regex(pattern) else { return [] }
        return text.matches(of: regex).map { String(text[$0.range]) }
    }
}
