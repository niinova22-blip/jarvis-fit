import Foundation

/// Short questions about things a photo cannot show (cooking fat, sugar, dressing). Each answer
/// adds a known amount of an ingredient from the food table, so the estimate stays explainable.
public struct ConfirmationQuestion: Hashable, Sendable, Identifiable {
    public struct Option: Hashable, Sendable {
        public var title: LocalizedText
        /// Grams of `ingredientId` added per portion.
        public var grams: Double
    }

    public var id: String
    public var text: LocalizedText
    public var ingredientId: String
    public var options: [Option]
    /// Index of the option used when the user doesn't answer.
    public var defaultIndex: Int

    /// Extra macros for an answer, scaled by the number of portions.
    public func extraMacros(optionIndex: Int, portions: Double) -> Macros {
        guard options.indices.contains(optionIndex), let ingredient = FoodDatabase.item(ingredientId) else { return .zero }
        return ingredient.macros(grams: options[optionIndex].grams * portions)
    }
}

public enum ConfirmationQuestions {
    static let cookedInFat: Set<String> = ["omelette", "menemen", "chicken_thigh", "beef_steak", "ground_beef", "kofte",
                                            "white_fish", "shrimp", "rice", "bulgur", "pasta", "potato", "vegetables", "broccoli",
                                            "karniyarik", "beans", "lentils", "chickpeas", "manti"]
    static let saladIds: Set<String> = ["salad", "shepherd_salad"]
    static let sweetenable: Set<String> = ["tea", "coffee"]

    public static func questions(for food: FoodItem) -> [ConfirmationQuestion] {
        var result: [ConfirmationQuestion] = []
        if cookedInFat.contains(food.id) {
            result.append(ConfirmationQuestion(
                id: "\(food.id)-fat",
                text: LocalizedText(tr: "Ne kadar yağla pişirildi?", en: "How much oil or butter was it cooked with?"),
                ingredientId: "olive_oil",
                options: [.init(title: LocalizedText(tr: "Yağsız", en: "None"), grams: 0),
                          .init(title: LocalizedText(tr: "Az", en: "A little"), grams: 5),
                          .init(title: LocalizedText(tr: "Normal", en: "Normal"), grams: 10),
                          .init(title: LocalizedText(tr: "Çok", en: "A lot"), grams: 20)],
                defaultIndex: 2))
        }
        if saladIds.contains(food.id) {
            result.append(ConfirmationQuestion(
                id: "\(food.id)-dressing",
                text: LocalizedText(tr: "Salataya zeytinyağı kondu mu?", en: "Was olive oil added to the salad?"),
                ingredientId: "olive_oil",
                options: [.init(title: LocalizedText(tr: "Hayır", en: "No"), grams: 0),
                          .init(title: LocalizedText(tr: "1 tatlı kaşığı", en: "1 teaspoon"), grams: 5),
                          .init(title: LocalizedText(tr: "1 yemek kaşığı", en: "1 tablespoon"), grams: 13)],
                defaultIndex: 1))
        }
        if sweetenable.contains(food.id) {
            result.append(ConfirmationQuestion(
                id: "\(food.id)-sugar",
                text: LocalizedText(tr: "Şeker kattın mı?", en: "Did you add sugar?"),
                ingredientId: "sugar",
                options: [.init(title: LocalizedText(tr: "Hayır", en: "No"), grams: 0),
                          .init(title: LocalizedText(tr: "1 küp", en: "1 cube"), grams: 4),
                          .init(title: LocalizedText(tr: "2 küp", en: "2 cubes"), grams: 8)],
                defaultIndex: 0))
        }
        return result
    }
}
