import Foundation

/// Parses spoken numbers in Turkish and English ("üç", "on iki", "twenty five", "1.5", "yarım").
public enum NumberWords {
    private static let turkishUnits: [String: Double] = [
        "sifir": 0, "bir": 1, "iki": 2, "uc": 3, "dort": 4, "bes": 5, "alti": 6, "yedi": 7,
        "sekiz": 8, "dokuz": 9
    ]
    private static let turkishTens: [String: Double] = [
        "on": 10, "yirmi": 20, "otuz": 30, "kirk": 40, "elli": 50, "altmis": 60, "yetmis": 70,
        "seksen": 80, "doksan": 90
    ]
    private static let englishUnits: [String: Double] = [
        "zero": 0, "one": 1, "a": 1, "an": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    private static let englishTens: [String: Double] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90
    ]
    private static let fractions: [String: Double] = [
        "yarim": 0.5, "half": 0.5, "ceyrek": 0.25, "quarter": 0.25
    ]

    /// Tries to read a number starting at `index`. Returns the value and the number of tokens used.
    public static func parse(_ tokens: [String], at index: Int) -> (value: Double, length: Int)? {
        guard index < tokens.count else { return nil }
        let first = tokens[index]
        if let numeric = Double(first) {
            // "2 buçuk" / "2.5"
            if index + 1 < tokens.count, tokens[index + 1] == "bucuk" { return (numeric + 0.5, 2) }
            return (numeric, 1)
        }
        if let fraction = fractions[first] { return (fraction, 1) }

        var total: Double = 0
        var used = 0
        var cursor = index
        var sawHundred = false
        while cursor < tokens.count {
            let token = tokens[cursor]
            if token == "yuz" || token == "hundred" {
                total = (total == 0 ? 1 : total) * 100
                sawHundred = true
            } else if let tens = turkishTens[token] ?? englishTens[token] {
                if used > 0 && !sawHundred && total.truncatingRemainder(dividingBy: 100) != 0 { break }
                total += tens
            } else if let unit = turkishUnits[token] ?? englishUnits[token] {
                // "a"/"an" only count as one when followed by a non-number word.
                if (token == "a" || token == "an") && used > 0 { break }
                if used > 0 && total.truncatingRemainder(dividingBy: 10) != 0 { break }
                total += unit
            } else if token == "bucuk" && used > 0 {
                total += 0.5
                used += 1
                cursor += 1
                break
            } else if token == "and" && used > 0 && sawHundred {
                // "one hundred and five"
            } else {
                break
            }
            used += 1
            cursor += 1
        }
        return used > 0 ? (total, used) : nil
    }

    /// Returns the first number found anywhere in the text.
    public static func firstNumber(in text: String) -> Double? {
        let tokens = TextNormalizer.tokens(text)
        for index in tokens.indices {
            if tokens[index] == "a" || tokens[index] == "an" { continue }
            if let parsed = parse(tokens, at: index) { return parsed.value }
        }
        return nil
    }
}
