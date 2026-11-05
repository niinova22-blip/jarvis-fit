import Foundation

public struct NutritionTargets: Codable, Hashable, Sendable {
    public var kcal: Int
    public var proteinG: Int
    public var carbsG: Int
    public var fatG: Int
    /// Short explanation of how the targets were derived (shown in the UI).
    public var rationale: LocalizedText
}

/// Energy and macro targets from Mifflin–St Jeor BMR, activity, planned training and goal.
public enum NutritionCalculator {
    public static func bmr(_ p: UserProfile) -> Double {
        let base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.age)
        switch p.sex {
        case .male: return base + 5
        case .female: return base - 161
        case .unspecified: return base - 78
        }
    }

    /// Average daily energy spent in planned workouts (≈5 kcal/min of resistance training).
    public static func trainingKcalPerDay(_ p: UserProfile) -> Double {
        Double(p.availableDays.count) * Double(p.sessionMinutes) * 5 / 7
    }

    public static func tdee(_ p: UserProfile) -> Double {
        bmr(p) * p.activity.multiplier + trainingKcalPerDay(p)
    }

    public static func targets(for p: UserProfile, adjustmentKcal: Int = 0) -> NutritionTargets {
        let maintenance = tdee(p)
        var factor: Double
        switch p.goal {
        case .leanDefined: factor = 0.82
        case .muscular: factor = 1.10
        case .strong: factor = 1.05
        case .athletic: factor = p.bmi > 25 ? 0.92 : 1.0
        case .balanced: factor = p.bmi > 27 ? 0.9 : 1.0
        }
        if p.limitations.contains(.pregnancy) { factor = max(factor, 1.0) }
        let floor: Double = p.sex == .female ? 1300 : p.sex == .male ? 1500 : 1400
        let kcal = max(floor, maintenance * factor + Double(adjustmentKcal))

        // Protein per kg; for BMI > 30 use the weight at BMI 27 to avoid overestimating.
        let referenceWeight = p.bmi > 30 ? 27 * pow(p.heightCm / 100, 2) : p.weightKg
        let proteinPerKg: Double
        switch p.goal {
        case .leanDefined: proteinPerKg = 2.0
        case .muscular, .strong: proteinPerKg = 1.8
        case .athletic: proteinPerKg = 1.7
        case .balanced: proteinPerKg = 1.4
        }
        let protein = proteinPerKg * referenceWeight
        let fat = max(0.6 * p.weightKg, kcal * 0.27 / 9)
        let carbs = max(50, (kcal - protein * 4 - fat * 9) / 4)

        let goalText = p.goal.title
        return NutritionTargets(
            kcal: Int((kcal / 10).rounded() * 10), proteinG: Int(protein.rounded()), carbsG: Int(carbs.rounded()), fatG: Int(fat.rounded()),
            rationale: LocalizedText(
                tr: "Bazal metabolizma (Mifflin–St Jeor) \(Int(bmr(p))) kcal, günlük harcama ≈\(Int(maintenance)) kcal. Hedef: \(goalText.tr). Protein \(String(format: "%.1f", proteinPerKg)) g/kg. Bunlar tahmindir; kilo değişimine göre her 2 haftada güncellenir.",
                en: "BMR (Mifflin–St Jeor) \(Int(bmr(p))) kcal, daily expenditure ≈\(Int(maintenance)) kcal. Goal: \(goalText.en). Protein \(String(format: "%.1f", proteinPerKg)) g/kg. These are estimates and are updated every 2 weeks from your weight trend."))
    }
}

public enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack

    public var title: LocalizedText {
        switch self {
        case .breakfast: return LocalizedText(tr: "Kahvaltı", en: "Breakfast")
        case .lunch: return LocalizedText(tr: "Öğle yemeği", en: "Lunch")
        case .dinner: return LocalizedText(tr: "Akşam yemeği", en: "Dinner")
        case .snack: return LocalizedText(tr: "Ara öğün", en: "Snack")
        }
    }

    public static func forHour(_ hour: Int) -> MealType {
        switch hour {
        case 5..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }
}

public enum FoodLogSource: String, Codable, Sendable { case photo, voice, manual }

public struct FoodLogEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var meal: MealType
    public var foodId: String
    public var name: LocalizedText
    public var grams: Double
    public var quantity: Double
    public var unit: PortionUnit
    public var macros: Macros
    public var source: FoodLogSource
    /// Photo/voice entries are estimates; manual gram entries are as precise as the database.
    public var isEstimate: Bool

    public init(id: UUID = UUID(), date: Date, meal: MealType, food: FoodItem, quantity: Double, unit: PortionUnit, source: FoodLogSource) {
        self.id = id
        self.date = date
        self.meal = meal
        self.foodId = food.id
        self.name = food.name
        self.quantity = quantity
        self.unit = unit
        self.grams = quantity * food.grams(for: unit)
        self.macros = food.macros(grams: grams)
        self.source = source
        self.isEstimate = source != .manual || (unit != .gram && unit != .ml)
    }
}

public struct ParsedFood: Equatable, Sendable {
    public var food: FoodItem
    public var quantity: Double
    public var unit: PortionUnit
    /// True when no amount was said and the default portion was assumed.
    public var assumedQuantity: Bool
}

public struct ParsedMeal: Equatable, Sendable {
    public var meal: MealType?
    public var items: [ParsedFood]
    /// Words that looked like food but are not in the database.
    public var unknownWords: [String]
}

/// Extracts foods and amounts from spoken text such as
/// "Jarvis, kahvaltıda üç yumurta ve iki dilim ekmek yedim" or "I had a bowl of yogurt and a banana".
public struct MealParser: Sendable {
    public init() {}

    private static let mealWords: [(MealType, [String])] = [
        (.breakfast, ["kahvalti", "kahvaltida", "breakfast", "sabah"]),
        (.lunch, ["ogle", "oglen", "ogle yemegi", "ogle yemeginde", "lunch"]),
        (.dinner, ["aksam", "aksam yemegi", "aksam yemeginde", "dinner", "supper"]),
        (.snack, ["ara ogun", "ara ogunde", "atistirmalik", "snack"])
    ]

    private struct NameEntry {
        let tokens: [String]
        let food: FoodItem
    }

    private static let names: [NameEntry] = {
        var entries: [NameEntry] = []
        for food in FoodDatabase.all {
            for name in Set(food.searchNames) {
                let tokens = TextNormalizer.tokens(name)
                if !tokens.isEmpty { entries.append(NameEntry(tokens: tokens, food: food)) }
            }
        }
        // Longest names first so "tavuk doner" wins over "tavuk".
        return entries.sorted { $0.tokens.count > $1.tokens.count }
    }()

    /// Turkish is agglutinative ("yumurtayı", "ekmeği", "yoğurdu"): accept suffixed forms when the
    /// stem is long enough, tolerating the final consonant softening (k→ğ, t→d, p→b, ç→c).
    static func tokenMatches(_ token: String, _ name: String) -> Bool {
        if token == name { return true }
        guard name.count >= 3 else { return false }
        if token.hasPrefix(name) && token.count - name.count <= 4 { return true }
        let softened: [Character: Character] = ["k": "g", "t": "d", "p": "b", "c": "c"]
        if let last = name.last, let soft = softened[last] {
            let stem = String(name.dropLast()) + String(soft)
            if token.hasPrefix(stem) && token.count - stem.count <= 4 { return true }
        }
        // English plural
        if token == name + "s" || token == name + "es" { return true }
        return false
    }

    private func unitAt(_ tokens: [String], _ index: Int) -> (PortionUnit, Int)? {
        guard index < tokens.count else { return nil }
        for unit in PortionUnit.allCases {
            for word in unit.words.sorted(by: { $0.count > $1.count }) {
                let parts = word.split(separator: " ").map(String.init)
                guard index + parts.count <= tokens.count else { continue }
                let slice = Array(tokens[index..<(index + parts.count)])
                if zip(slice, parts).allSatisfy({ MealParser.tokenMatches($0, $1) || $0 == $1 }) {
                    return (unit, parts.count)
                }
            }
        }
        return nil
    }

    /// Best food name starting at `index`: more tokens first, then exact matches, then longer names.
    private func bestEntry(_ tokens: [String], at index: Int) -> NameEntry? {
        var best: NameEntry?
        var bestScore = (0, 0, 0)
        for entry in Self.names where index + entry.tokens.count <= tokens.count {
            let slice = tokens[index..<(index + entry.tokens.count)]
            guard zip(slice, entry.tokens).allSatisfy({ Self.tokenMatches($0, $1) }) else { continue }
            let exact = zip(slice, entry.tokens).filter { $0 == $1 }.count
            let score = (entry.tokens.count, exact, entry.tokens.joined().count)
            if score > bestScore {
                bestScore = score
                best = entry
            }
        }
        return best
    }

    public func parse(_ text: String) -> ParsedMeal {
        let tokens = TextNormalizer.tokens(text).filter { !IntentParser.wakeWords.contains($0) }
        var meal: MealType?
        let joined = " " + tokens.joined(separator: " ") + " "
        for (type, words) in Self.mealWords where words.contains(where: { joined.contains(" " + $0) }) {
            meal = type
            break
        }

        var items: [ParsedFood] = []
        var index = 0
        while index < tokens.count {
            guard let entry = bestEntry(tokens, at: index) else {
                index += 1
                continue
            }
            let foodStart = index
            let foodEnd = index + entry.tokens.count
            var quantity: Double?
            var unit: PortionUnit?

            // Look back: "<number> <unit> [of] <food>" or "<number> <food>".
            var cursor = foodStart - 1
            if cursor >= 0 && tokens[cursor] == "of" { cursor -= 1 }
            for length in [3, 2, 1] where cursor - length + 1 >= 0 {
                if let (u, matched) = unitAt(tokens, cursor - length + 1), matched == length {
                    unit = u
                    cursor -= length
                    break
                }
            }
            if cursor >= 0 {
                for start in stride(from: cursor, through: max(0, cursor - 2), by: -1) {
                    if let (value, length) = NumberWords.parse(tokens, at: start), start + length - 1 == cursor {
                        quantity = value
                        break
                    }
                }
            }
            // Amount after the food: "tavuk 200 gram".
            if quantity == nil, let (value, length) = NumberWords.parse(tokens, at: foodEnd),
               let (u, _) = unitAt(tokens, foodEnd + length), u == .gram || u == .ml {
                quantity = value
                unit = u
            }
            items.append(ParsedFood(food: entry.food, quantity: quantity ?? 1, unit: unit ?? entry.food.defaultUnit,
                                    assumedQuantity: quantity == nil))
            index = foodEnd
        }
        return ParsedMeal(meal: meal, items: items, unknownWords: [])
    }
}

/// Daily totals and comparison with targets.
public struct NutritionDay: Sendable {
    public var entries: [FoodLogEntry]
    public var targets: NutritionTargets

    public init(entries: [FoodLogEntry], targets: NutritionTargets) {
        self.entries = entries
        self.targets = targets
    }

    public var totals: Macros { entries.reduce(.zero) { $0 + $1.macros } }
    public var remainingKcal: Int { targets.kcal - Int(totals.kcal.rounded()) }
    public var remainingProtein: Int { targets.proteinG - Int(totals.protein.rounded()) }
    public var hasEstimates: Bool { entries.contains { $0.isEstimate } }

    public func entries(for meal: MealType) -> [FoodLogEntry] { entries.filter { $0.meal == meal } }
}
