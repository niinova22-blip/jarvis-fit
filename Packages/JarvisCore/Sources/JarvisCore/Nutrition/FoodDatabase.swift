import Foundation

public enum PortionUnit: String, Codable, CaseIterable, Sendable {
    case gram, ml, piece, slice, cup, glass, bowl, plate, tablespoon, teaspoon, handful, portion, scoop, can, skewer

    /// Spoken/written forms (normalised, ASCII-folded) for Turkish and English.
    public var words: [String] {
        switch self {
        case .gram: return ["gram", "gr", "g", "grams"]
        case .ml: return ["ml", "mililitre", "milliliter", "milliliters"]
        case .piece: return ["adet", "tane", "piece", "pieces", "whole"]
        case .slice: return ["dilim", "slice", "slices"]
        case .cup: return ["fincan", "kupa", "cup", "cups", "mug"]
        case .glass: return ["bardak", "glass", "glasses"]
        case .bowl: return ["kase", "kasesi", "bowl", "bowls"]
        case .plate: return ["tabak", "tabagi", "plate", "plates"]
        case .tablespoon: return ["kasik", "yemek kasigi", "tablespoon", "tablespoons", "tbsp", "spoon", "spoons"]
        case .teaspoon: return ["cay kasigi", "tatli kasigi", "teaspoon", "teaspoons", "tsp"]
        case .handful: return ["avuc", "handful", "handfuls"]
        case .portion: return ["porsiyon", "portion", "portions", "serving", "servings"]
        case .scoop: return ["olcek", "scoop", "scoops", "top"]
        case .can: return ["kutu", "can", "cans"]
        case .skewer: return ["sis", "skewer", "skewers"]
        }
    }

    public var title: LocalizedText {
        switch self {
        case .gram: return LocalizedText(tr: "g", en: "g")
        case .ml: return LocalizedText(tr: "ml", en: "ml")
        case .piece: return LocalizedText(tr: "adet", en: "piece")
        case .slice: return LocalizedText(tr: "dilim", en: "slice")
        case .cup: return LocalizedText(tr: "fincan", en: "cup")
        case .glass: return LocalizedText(tr: "bardak", en: "glass")
        case .bowl: return LocalizedText(tr: "kase", en: "bowl")
        case .plate: return LocalizedText(tr: "tabak", en: "plate")
        case .tablespoon: return LocalizedText(tr: "yemek kaşığı", en: "tbsp")
        case .teaspoon: return LocalizedText(tr: "çay kaşığı", en: "tsp")
        case .handful: return LocalizedText(tr: "avuç", en: "handful")
        case .portion: return LocalizedText(tr: "porsiyon", en: "portion")
        case .scoop: return LocalizedText(tr: "ölçek", en: "scoop")
        case .can: return LocalizedText(tr: "kutu", en: "can")
        case .skewer: return LocalizedText(tr: "şiş", en: "skewer")
        }
    }
}

public struct Macros: Codable, Hashable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(kcal: Double, protein: Double, carbs: Double, fat: Double) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    public static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
    }

    public func scaled(_ factor: Double) -> Macros {
        Macros(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }
}

public enum DietTag: String, Codable, Sendable { case meat, fish, dairy, egg, plant }

public struct FoodItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: LocalizedText
    /// Additional normalised names (Turkish/English, singular/plural).
    public var synonyms: [String]
    /// Per 100 g (or 100 ml for drinks).
    public var per100: Macros
    public var units: [PortionUnit: Double]
    public var defaultUnit: PortionUnit
    public var tags: [DietTag]
    /// Labels of Apple Vision's image classifier that indicate this food.
    public var visionLabels: [String]

    public func grams(for unit: PortionUnit) -> Double {
        if unit == .gram || unit == .ml { return 1 }
        if let grams = units[unit] { return grams }
        if unit == .portion || unit == .plate, let d = units[defaultUnit] { return d }
        return units[defaultUnit] ?? 100
    }

    public var defaultPortionGrams: Double { grams(for: defaultUnit) }

    public func macros(grams: Double) -> Macros { per100.scaled(grams / 100) }

    public var searchNames: [String] {
        ([name.tr, name.en] + synonyms).map(TextNormalizer.normalize)
    }
}

/// Local food composition table. Values are rounded per-100 g figures based on USDA FoodData
/// Central (public domain) and typical recipes for Turkish dishes; recipes vary, so every logged
/// value is presented as an estimate.
public enum FoodDatabase {
    private static func f(_ id: String, _ tr: String, _ en: String, _ kcal: Double, _ p: Double, _ c: Double, _ fat: Double,
                          units: [PortionUnit: Double], _ unit: PortionUnit, tags: [DietTag], syn: [String] = [], vision: [String] = []) -> FoodItem {
        FoodItem(id: id, name: LocalizedText(tr: tr, en: en), synonyms: syn,
                 per100: Macros(kcal: kcal, protein: p, carbs: c, fat: fat), units: units, defaultUnit: unit,
                 tags: tags, visionLabels: vision)
    }

    public static let all: [FoodItem] = [
        // Eggs, meat, fish
        f("egg", "Yumurta", "Egg", 155, 13, 1.1, 11, units: [.piece: 50], .piece, tags: [.egg], syn: ["yumurta", "haslanmis yumurta", "eggs", "boiled egg", "fried egg", "sahanda yumurta"], vision: ["egg", "eggs", "fried egg", "boiled egg", "omelet", "omelette"]),
        f("egg_white", "Yumurta beyazı", "Egg white", 52, 11, 0.7, 0.2, units: [.piece: 33], .piece, tags: [.egg], syn: ["yumurta aki", "egg whites"]),
        f("omelette", "Omlet", "Omelette", 154, 11, 1.6, 12, units: [.portion: 150, .plate: 150], .portion, tags: [.egg], syn: ["omlet", "omelet"], vision: ["omelet", "omelette"]),
        f("menemen", "Menemen", "Menemen (eggs with tomato & pepper)", 100, 6, 4, 7, units: [.plate: 250, .portion: 250], .plate, tags: [.egg, .plant], syn: ["menemen"]),
        f("chicken_breast", "Tavuk göğsü (ızgara)", "Grilled chicken breast", 165, 31, 0, 3.6, units: [.portion: 150, .piece: 150, .plate: 200], .portion, tags: [.meat], syn: ["tavuk", "tavuk gogsu", "izgara tavuk", "chicken", "chicken breast"], vision: ["chicken", "grilled chicken", "chicken breast", "roast chicken", "fried chicken"]),
        f("chicken_thigh", "Tavuk but", "Chicken thigh", 209, 26, 0, 11, units: [.piece: 100, .portion: 150], .portion, tags: [.meat], syn: ["tavuk but", "pirzola tavuk", "chicken thigh"]),
        f("beef_steak", "Biftek", "Beef steak", 250, 26, 0, 15, units: [.portion: 150, .piece: 200], .portion, tags: [.meat], syn: ["biftek", "et", "kirmizi et", "bonfile", "antrikot", "steak", "beef"], vision: ["steak", "beef", "meat"]),
        f("ground_beef", "Kıyma (pişmiş)", "Ground beef (cooked)", 254, 26, 0, 17, units: [.portion: 120, .tablespoon: 15], .portion, tags: [.meat], syn: ["kiyma", "ground beef", "mince"]),
        f("kofte", "Köfte", "Turkish meatballs (köfte)", 240, 17, 8, 15, units: [.piece: 25, .portion: 175, .plate: 200], .portion, tags: [.meat], syn: ["kofte", "izgara kofte", "meatball", "meatballs"], vision: ["meatball", "meatballs"]),
        f("doner_beef", "Et döner", "Beef döner (meat)", 250, 20, 4, 17, units: [.portion: 150, .plate: 150], .portion, tags: [.meat], syn: ["doner", "et doner", "doner kebab", "kebab"], vision: ["kebab", "doner kebab", "shawarma", "gyro"]),
        f("doner_chicken", "Tavuk döner", "Chicken döner (meat)", 190, 23, 3, 9, units: [.portion: 150, .plate: 150], .portion, tags: [.meat], syn: ["tavuk doner", "chicken doner", "chicken shawarma"]),
        f("durum", "Dürüm (tavuk)", "Chicken wrap (dürüm)", 220, 14, 24, 8, units: [.piece: 250, .portion: 250], .piece, tags: [.meat], syn: ["durum", "tavuk durum", "wrap", "durum doner"], vision: ["burrito", "wrap"]),
        f("adana", "Adana kebap", "Adana kebab", 280, 18, 2, 22, units: [.portion: 200, .skewer: 100], .portion, tags: [.meat], syn: ["adana", "adana kebap", "urfa kebap", "kebap"]),
        f("chicken_skewer", "Tavuk şiş", "Chicken skewer", 160, 25, 2, 6, units: [.skewer: 120, .portion: 200], .portion, tags: [.meat], syn: ["tavuk sis", "chicken skewer", "chicken kebab"], vision: ["skewer", "kebab"]),
        f("iskender", "İskender", "İskender kebab", 190, 11, 10, 12, units: [.portion: 350, .plate: 350], .portion, tags: [.meat, .dairy], syn: ["iskender"]),
        f("salmon", "Somon", "Salmon", 206, 22, 0, 13, units: [.portion: 150, .piece: 150], .portion, tags: [.fish], syn: ["somon", "salmon"], vision: ["salmon", "fish", "sashimi"]),
        f("tuna", "Ton balığı (konserve)", "Canned tuna (in water)", 116, 26, 0, 1, units: [.can: 120, .portion: 100, .tablespoon: 15], .can, tags: [.fish], syn: ["ton baligi", "ton", "tuna"], vision: ["tuna"]),
        f("white_fish", "Beyaz balık (ızgara)", "White fish (grilled)", 105, 23, 0, 1, units: [.portion: 180, .piece: 180], .portion, tags: [.fish], syn: ["balik", "levrek", "cupra", "hamsi", "fish", "cod", "sea bass"], vision: ["fish", "grilled fish"]),
        f("shrimp", "Karides", "Shrimp", 99, 24, 0.2, 0.3, units: [.portion: 120, .piece: 8], .portion, tags: [.fish], syn: ["karides", "shrimp", "prawn", "prawns"], vision: ["shrimp", "prawn"]),
        f("turkey_slice", "Hindi füme", "Turkey slices", 104, 17, 4, 2, units: [.slice: 20], .slice, tags: [.meat], syn: ["hindi", "hindi fume", "turkey", "turkey slices"]),
        f("sucuk", "Sucuk", "Sucuk (spicy sausage)", 450, 18, 2, 40, units: [.slice: 10, .portion: 50], .slice, tags: [.meat], syn: ["sucuk", "sausage", "salam"], vision: ["sausage"]),
        // Dairy
        f("milk", "Süt", "Milk (whole)", 61, 3.2, 4.8, 3.3, units: [.glass: 200, .cup: 240], .glass, tags: [.dairy], syn: ["sut", "milk"], vision: ["milk"]),
        f("yogurt", "Yoğurt", "Plain yogurt", 61, 3.5, 4.7, 3.3, units: [.bowl: 200, .tablespoon: 20, .cup: 200], .bowl, tags: [.dairy], syn: ["yogurt", "yoghurt"], vision: ["yogurt"]),
        f("greek_yogurt", "Süzme yoğurt", "Greek yogurt", 73, 10, 3.9, 2, units: [.bowl: 170, .tablespoon: 20], .bowl, tags: [.dairy], syn: ["suzme yogurt", "greek yogurt"]),
        f("ayran", "Ayran", "Ayran (yogurt drink)", 36, 1.7, 2.6, 2.0, units: [.glass: 200, .can: 250], .glass, tags: [.dairy], syn: ["ayran"]),
        f("white_cheese", "Beyaz peynir", "White cheese (feta-type)", 264, 14, 4, 21, units: [.slice: 30, .portion: 30], .slice, tags: [.dairy], syn: ["peynir", "beyaz peynir", "feta", "cheese"], vision: ["cheese", "feta"]),
        f("kasar", "Kaşar peyniri", "Kashar cheese", 350, 25, 2, 27, units: [.slice: 20], .slice, tags: [.dairy], syn: ["kasar", "kasar peyniri", "cheddar", "yellow cheese"]),
        f("cottage_cheese", "Lor peyniri", "Cottage cheese", 98, 11, 3.4, 4.3, units: [.tablespoon: 25, .bowl: 150], .tablespoon, tags: [.dairy], syn: ["lor", "lor peyniri", "cottage cheese"]),
        f("butter", "Tereyağı", "Butter", 717, 0.9, 0.1, 81, units: [.tablespoon: 14, .teaspoon: 5], .teaspoon, tags: [.dairy], syn: ["tereyagi", "butter"]),
        // Grains & bread
        f("white_bread", "Ekmek", "White bread", 265, 9, 49, 3.2, units: [.slice: 30, .piece: 250], .slice, tags: [.plant], syn: ["ekmek", "beyaz ekmek", "bread", "white bread", "toast bread"], vision: ["bread", "toast", "baguette"]),
        f("wholewheat_bread", "Tam buğday ekmeği", "Whole-wheat bread", 247, 13, 41, 3.4, units: [.slice: 30], .slice, tags: [.plant], syn: ["tam bugday ekmek", "tam bugday ekmegi", "kepekli ekmek", "whole wheat bread", "brown bread"]),
        f("simit", "Simit", "Simit (sesame bagel)", 305, 9.5, 55, 5.5, units: [.piece: 110], .piece, tags: [.plant], syn: ["simit", "bagel"], vision: ["bagel", "pretzel"]),
        f("lavash", "Lavaş", "Lavash flatbread", 275, 9, 56, 1.2, units: [.piece: 60], .piece, tags: [.plant], syn: ["lavas", "tortilla", "flatbread", "yufka"], vision: ["tortilla", "flatbread"]),
        f("rice", "Pirinç pilavı", "Rice (cooked)", 160, 2.9, 28, 4, units: [.plate: 200, .portion: 180, .cup: 160, .tablespoon: 15, .bowl: 200], .plate, tags: [.plant], syn: ["pilav", "pirinc", "pirinc pilavi", "rice", "white rice"], vision: ["rice", "fried rice", "risotto", "paella"]),
        f("bulgur", "Bulgur pilavı", "Bulgur pilaf", 120, 3, 21, 3, units: [.plate: 200, .portion: 180, .tablespoon: 15], .plate, tags: [.plant], syn: ["bulgur", "bulgur pilavi", "bulgur pilaf"]),
        f("pasta", "Makarna", "Pasta (cooked)", 158, 5.8, 31, 0.9, units: [.plate: 220, .portion: 200, .bowl: 220], .plate, tags: [.plant], syn: ["makarna", "spagetti", "eriste", "pasta", "spaghetti", "noodles"], vision: ["pasta", "spaghetti", "macaroni", "lasagna", "noodles", "ramen"]),
        f("oats", "Yulaf", "Oats (dry)", 389, 16.9, 66, 6.9, units: [.cup: 80, .tablespoon: 10, .bowl: 40, .handful: 30], .bowl, tags: [.plant], syn: ["yulaf", "yulaf ezmesi", "oats", "oatmeal", "porridge", "granola"], vision: ["oatmeal", "porridge", "granola", "muesli"]),
        f("cornflakes", "Mısır gevreği", "Corn flakes", 357, 7.5, 84, 0.4, units: [.bowl: 30, .cup: 30], .bowl, tags: [.plant], syn: ["misir gevregi", "corn flakes", "cereal"], vision: ["cereal"]),
        f("potato", "Patates (haşlanmış)", "Potato (boiled)", 87, 1.9, 20, 0.1, units: [.piece: 150, .portion: 200], .piece, tags: [.plant], syn: ["patates", "haslanmis patates", "potato", "potatoes", "mashed potato", "patates puresi"], vision: ["potato", "mashed potatoes", "baked potato"]),
        f("fries", "Patates kızartması", "French fries", 312, 3.4, 41, 15, units: [.portion: 120, .plate: 150, .handful: 40], .portion, tags: [.plant], syn: ["patates kizartmasi", "kizartma", "fries", "french fries", "chips"], vision: ["french fries", "fries", "chips"]),
        f("sweet_potato", "Tatlı patates", "Sweet potato", 90, 2, 21, 0.2, units: [.piece: 150], .piece, tags: [.plant], syn: ["tatli patates", "sweet potato"], vision: ["sweet potato"]),
        // Legumes & soups
        f("lentil_soup", "Mercimek çorbası", "Lentil soup", 60, 3.2, 8.5, 1.6, units: [.bowl: 250, .plate: 250, .portion: 250], .bowl, tags: [.plant], syn: ["mercimek corbasi", "lentil soup"], vision: ["soup", "lentil soup"]),
        f("soup", "Çorba", "Soup", 50, 2, 7, 1.5, units: [.bowl: 250, .plate: 250], .bowl, tags: [.plant], syn: ["corba", "ezogelin", "tarhana", "domates corbasi", "soup"], vision: ["soup", "broth"]),
        f("beans", "Kuru fasulye", "White bean stew", 100, 5.5, 13, 3, units: [.plate: 250, .portion: 250, .bowl: 250], .plate, tags: [.plant], syn: ["kuru fasulye", "fasulye", "beans", "bean stew"], vision: ["beans", "baked beans"]),
        f("chickpeas", "Nohut", "Chickpeas (cooked)", 164, 8.9, 27, 2.6, units: [.plate: 200, .tablespoon: 15, .bowl: 200], .plate, tags: [.plant], syn: ["nohut", "chickpeas", "chickpea", "garbanzo"], vision: ["chickpeas"]),
        f("lentils", "Yeşil mercimek", "Lentils (cooked)", 116, 9, 20, 0.4, units: [.plate: 200, .bowl: 200], .plate, tags: [.plant], syn: ["yesil mercimek", "mercimek", "lentils", "lentil"]),
        f("hummus", "Humus", "Hummus", 166, 7.9, 14, 9.6, units: [.tablespoon: 15, .bowl: 100], .tablespoon, tags: [.plant], syn: ["humus", "hummus"], vision: ["hummus"]),
        // Vegetables & fruit
        f("salad", "Yeşil salata", "Green salad (no dressing)", 20, 1.5, 3.5, 0.2, units: [.bowl: 150, .plate: 150], .bowl, tags: [.plant], syn: ["salata", "yesil salata", "salad", "green salad"], vision: ["salad", "green salad", "caesar salad", "lettuce"]),
        f("shepherd_salad", "Çoban salatası", "Shepherd's salad (with olive oil)", 60, 1, 5, 4.5, units: [.bowl: 200, .plate: 200], .bowl, tags: [.plant], syn: ["coban salatasi", "coban salata", "shepherd salad", "greek salad"], vision: ["greek salad"]),
        f("tomato", "Domates", "Tomato", 18, 0.9, 3.9, 0.2, units: [.piece: 120, .slice: 20], .piece, tags: [.plant], syn: ["domates", "tomato", "tomatoes"], vision: ["tomato"]),
        f("cucumber", "Salatalık", "Cucumber", 15, 0.7, 3.6, 0.1, units: [.piece: 200, .slice: 10], .piece, tags: [.plant], syn: ["salatalik", "hiyar", "cucumber"], vision: ["cucumber"]),
        f("broccoli", "Brokoli", "Broccoli", 35, 2.4, 7, 0.4, units: [.portion: 150, .bowl: 150], .portion, tags: [.plant], syn: ["brokoli", "broccoli"], vision: ["broccoli"]),
        f("vegetables", "Sebze yemeği (zeytinyağlı)", "Cooked vegetables (olive oil)", 80, 2, 8, 5, units: [.plate: 250, .portion: 250], .plate, tags: [.plant], syn: ["sebze", "sebze yemegi", "zeytinyagli", "taze fasulye", "turlu", "vegetables", "veggies"], vision: ["vegetable", "vegetables", "stir fry"]),
        f("banana", "Muz", "Banana", 89, 1.1, 23, 0.3, units: [.piece: 120], .piece, tags: [.plant], syn: ["muz", "banana", "bananas"], vision: ["banana"]),
        f("apple", "Elma", "Apple", 52, 0.3, 14, 0.2, units: [.piece: 180], .piece, tags: [.plant], syn: ["elma", "apple", "apples"], vision: ["apple", "granny smith"]),
        f("orange", "Portakal", "Orange", 47, 0.9, 12, 0.1, units: [.piece: 150], .piece, tags: [.plant], syn: ["portakal", "mandalina", "orange", "oranges", "tangerine"], vision: ["orange", "citrus", "tangerine", "mandarin"]),
        f("strawberry", "Çilek", "Strawberries", 32, 0.7, 7.7, 0.3, units: [.cup: 150, .bowl: 150, .piece: 12, .handful: 80], .bowl, tags: [.plant], syn: ["cilek", "strawberry", "strawberries"], vision: ["strawberry"]),
        f("grapes", "Üzüm", "Grapes", 69, 0.7, 18, 0.2, units: [.cup: 150, .bowl: 150, .handful: 80], .bowl, tags: [.plant], syn: ["uzum", "grapes", "grape"], vision: ["grape", "grapes"]),
        f("watermelon", "Karpuz", "Watermelon", 30, 0.6, 7.6, 0.2, units: [.slice: 280, .bowl: 200], .slice, tags: [.plant], syn: ["karpuz", "watermelon"], vision: ["watermelon"]),
        f("dates", "Hurma", "Dates", 282, 2.5, 75, 0.4, units: [.piece: 8, .handful: 40], .piece, tags: [.plant], syn: ["hurma", "dates", "date"]),
        f("avocado", "Avokado", "Avocado", 160, 2, 8.5, 14.7, units: [.piece: 150, .slice: 25], .piece, tags: [.plant], syn: ["avokado", "avocado"], vision: ["avocado", "guacamole"]),
        f("olives", "Zeytin", "Olives", 115, 0.8, 6, 10.7, units: [.piece: 4, .handful: 40], .piece, tags: [.plant], syn: ["zeytin", "olive", "olives"], vision: ["olive", "olives"]),
        // Fats & nuts
        f("olive_oil", "Zeytinyağı", "Olive oil", 884, 0, 0, 100, units: [.tablespoon: 13.5, .teaspoon: 4.5], .tablespoon, tags: [.plant], syn: ["zeytinyagi", "olive oil", "oil"]),
        f("almonds", "Badem", "Almonds", 579, 21, 22, 50, units: [.handful: 28, .piece: 1.2], .handful, tags: [.plant], syn: ["badem", "almond", "almonds"], vision: ["almond", "nuts"]),
        f("walnuts", "Ceviz", "Walnuts", 654, 15, 14, 65, units: [.handful: 28, .piece: 4], .handful, tags: [.plant], syn: ["ceviz", "walnut", "walnuts"], vision: ["walnut"]),
        f("hazelnuts", "Fındık", "Hazelnuts", 628, 15, 17, 61, units: [.handful: 28, .piece: 1.5], .handful, tags: [.plant], syn: ["findik", "hazelnut", "hazelnuts", "nuts", "kuruyemis"], vision: ["hazelnut", "nut", "nuts"]),
        f("peanut_butter", "Fıstık ezmesi", "Peanut butter", 588, 25, 20, 50, units: [.tablespoon: 16, .teaspoon: 5], .tablespoon, tags: [.plant], syn: ["fistik ezmesi", "peanut butter"], vision: ["peanut butter"]),
        // Turkish dishes
        f("lahmacun", "Lahmacun", "Lahmacun", 235, 11, 31, 7.5, units: [.piece: 110], .piece, tags: [.meat], syn: ["lahmacun"], vision: ["flatbread", "pizza"]),
        f("pide", "Kıymalı pide", "Pide (minced meat)", 260, 12, 33, 9, units: [.piece: 300, .portion: 300, .slice: 60], .portion, tags: [.meat, .dairy], syn: ["pide", "kiymali pide", "kasarli pide"]),
        f("manti", "Mantı", "Mantı (with yogurt)", 170, 8, 20, 6.5, units: [.plate: 300, .portion: 300], .plate, tags: [.meat, .dairy], syn: ["manti"], vision: ["dumpling", "dumplings", "ravioli"]),
        f("karniyarik", "Karnıyarık", "Karnıyarık (stuffed eggplant)", 120, 4, 7, 9, units: [.portion: 250, .piece: 200], .portion, tags: [.meat, .plant], syn: ["karniyarik", "patlican", "eggplant"], vision: ["eggplant"]),
        f("dolma", "Yaprak sarma", "Stuffed vine leaves", 160, 3, 21, 7, units: [.piece: 25, .portion: 150], .piece, tags: [.plant], syn: ["sarma", "dolma", "yaprak sarma", "stuffed grape leaves"]),
        f("borek", "Börek", "Börek (pastry)", 290, 10, 24, 17, units: [.slice: 120, .piece: 120, .portion: 150], .slice, tags: [.dairy], syn: ["borek", "su boregi", "pogaca", "pastry"]),
        f("tost", "Kaşarlı tost", "Cheese toastie", 300, 13, 33, 13, units: [.piece: 120], .piece, tags: [.dairy, .plant], syn: ["tost", "kasarli tost", "toastie", "grilled cheese"], vision: ["grilled cheese", "panini"]),
        f("baklava", "Baklava", "Baklava", 428, 6.7, 52, 23, units: [.piece: 30, .portion: 90], .piece, tags: [.plant, .dairy], syn: ["baklava"], vision: ["baklava"]),
        f("kunefe", "Künefe", "Künefe", 330, 7, 40, 16, units: [.portion: 150], .portion, tags: [.dairy], syn: ["kunefe"]),
        // Fast food
        f("pizza", "Pizza", "Pizza", 266, 11, 33, 10, units: [.slice: 107, .piece: 107], .slice, tags: [.dairy, .meat], syn: ["pizza"], vision: ["pizza"]),
        f("burger", "Hamburger", "Hamburger", 250, 13, 25, 11, units: [.piece: 200], .piece, tags: [.meat], syn: ["hamburger", "burger", "cheeseburger"], vision: ["hamburger", "burger", "cheeseburger"]),
        f("sandwich", "Sandviç", "Sandwich", 250, 11, 28, 10, units: [.piece: 200], .piece, tags: [.meat, .dairy], syn: ["sandvic", "sandwich", "kumru"], vision: ["sandwich", "sub", "submarine sandwich", "club sandwich"]),
        f("hot_dog", "Sosisli sandviç", "Hot dog", 290, 10, 24, 17, units: [.piece: 100], .piece, tags: [.meat], syn: ["sosisli", "hot dog", "hotdog"], vision: ["hot dog", "hotdog"]),
        f("sushi", "Suşi", "Sushi", 145, 6, 28, 1, units: [.piece: 30, .portion: 240], .piece, tags: [.fish], syn: ["susi", "sushi"], vision: ["sushi", "sashimi", "maki"]),
        f("taco", "Taco", "Taco", 226, 9, 20, 12, units: [.piece: 100], .piece, tags: [.meat], syn: ["taco", "tacos"], vision: ["taco"]),
        f("burrito", "Burrito", "Burrito", 206, 8, 25, 8, units: [.piece: 250], .piece, tags: [.meat], syn: ["burrito"], vision: ["burrito"]),
        // Sweets & snacks
        f("chocolate", "Çikolata", "Chocolate", 546, 4.9, 61, 31, units: [.piece: 10, .slice: 10, .portion: 40], .portion, tags: [.dairy], syn: ["cikolata", "chocolate"], vision: ["chocolate", "chocolate bar"]),
        f("cake", "Kek / pasta", "Cake", 370, 5, 53, 15, units: [.slice: 80, .piece: 80], .slice, tags: [.dairy, .egg], syn: ["kek", "pasta dilimi", "cake", "cheesecake"], vision: ["cake", "cupcake", "cheesecake", "muffin"]),
        f("cookie", "Kurabiye / bisküvi", "Cookie", 480, 6, 66, 22, units: [.piece: 15], .piece, tags: [.dairy], syn: ["kurabiye", "biskuvi", "cookie", "cookies", "biscuit"], vision: ["cookie", "biscuit"]),
        f("ice_cream", "Dondurma", "Ice cream", 207, 3.5, 24, 11, units: [.scoop: 65, .portion: 130, .bowl: 130], .scoop, tags: [.dairy], syn: ["dondurma", "ice cream"], vision: ["ice cream", "gelato", "frozen yogurt"]),
        f("donut", "Donut", "Donut", 452, 4.9, 51, 25, units: [.piece: 60], .piece, tags: [.dairy], syn: ["donut", "doughnut", "pisi"], vision: ["donut", "doughnut"]),
        f("croissant", "Kruvasan", "Croissant", 406, 8, 46, 21, units: [.piece: 60], .piece, tags: [.dairy], syn: ["kruvasan", "croissant"], vision: ["croissant"]),
        f("pancake", "Pankek", "Pancake", 227, 6.4, 28, 10, units: [.piece: 75], .piece, tags: [.dairy, .egg], syn: ["pankek", "pancake", "pancakes", "krep", "crepe"], vision: ["pancake", "pancakes", "crepe"]),
        f("waffle", "Waffle", "Waffle", 291, 7.9, 33, 14, units: [.piece: 75], .piece, tags: [.dairy, .egg], syn: ["waffle"], vision: ["waffle"]),
        f("honey", "Bal", "Honey", 304, 0.3, 82, 0, units: [.tablespoon: 21, .teaspoon: 7], .tablespoon, tags: [.plant], syn: ["bal", "honey"], vision: ["honey"]),
        f("jam", "Reçel", "Jam", 278, 0.4, 69, 0.1, units: [.tablespoon: 20, .teaspoon: 7], .tablespoon, tags: [.plant], syn: ["recel", "jam", "marmelat"]),
        f("protein_bar", "Protein bar", "Protein bar", 350, 30, 35, 10, units: [.piece: 60], .piece, tags: [.dairy], syn: ["protein bar", "protein bari"]),
        f("whey", "Whey protein tozu", "Whey protein powder", 400, 80, 8, 6, units: [.scoop: 30], .scoop, tags: [.dairy], syn: ["whey", "protein tozu", "protein shake", "protein powder", "protein"]),
        // Drinks
        f("tea", "Çay (şekersiz)", "Tea (no sugar)", 1, 0, 0.3, 0, units: [.glass: 100, .cup: 200], .glass, tags: [.plant], syn: ["cay", "tea"], vision: ["tea"]),
        f("coffee", "Kahve (sade)", "Black coffee", 2, 0.3, 0, 0, units: [.cup: 240, .glass: 240], .cup, tags: [.plant], syn: ["kahve", "turk kahvesi", "filtre kahve", "americano", "espresso", "coffee"], vision: ["coffee", "espresso"]),
        f("latte", "Latte", "Latte", 56, 3, 4.6, 3, units: [.cup: 350, .glass: 350], .cup, tags: [.dairy], syn: ["latte", "cappuccino", "sutlu kahve", "flat white"], vision: ["latte", "cappuccino"]),
        f("sugar", "Şeker", "Sugar", 387, 0, 100, 0, units: [.teaspoon: 4, .piece: 3, .tablespoon: 12], .teaspoon, tags: [.plant], syn: ["seker", "kup seker", "sugar"]),
        f("orange_juice", "Portakal suyu", "Orange juice", 45, 0.7, 10.4, 0.2, units: [.glass: 200], .glass, tags: [.plant], syn: ["portakal suyu", "meyve suyu", "orange juice", "juice"], vision: ["orange juice", "juice"]),
        f("cola", "Kola", "Cola", 42, 0, 10.6, 0, units: [.can: 330, .glass: 200], .can, tags: [.plant], syn: ["kola", "gazli icecek", "cola", "coke", "soda"], vision: ["soda", "cola"])
    ]

    private static let byId: [String: FoodItem] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func item(_ id: String) -> FoodItem? { byId[id] }

    /// Simple search for the manual food picker.
    public static func search(_ query: String) -> [FoodItem] {
        let q = TextNormalizer.normalize(query)
        guard !q.isEmpty else { return all }
        return all.filter { item in item.searchNames.contains { $0.contains(q) } }
    }

    /// Candidates for Apple Vision classification labels (label → confidence).
    public static func candidates(forVisionLabels labels: [(identifier: String, confidence: Double)]) -> [(item: FoodItem, confidence: Double)] {
        var best: [String: Double] = [:]
        for label in labels {
            let normalized = TextNormalizer.normalize(label.identifier.replacingOccurrences(of: "_", with: " "))
            for item in all {
                // A label listed first is the item's primary label; secondary labels (e.g. "pizza"
                // for lahmacun) rank slightly lower so the canonical food wins ties.
                guard let position = item.visionLabels.firstIndex(where: { TextNormalizer.normalize($0) == normalized }) else { continue }
                let score = label.confidence * (position == 0 ? 1 : 0.85)
                best[item.id] = max(best[item.id] ?? 0, score)
            }
        }
        return best.compactMap { id, confidence in item(id).map { ($0, confidence) } }
            .sorted { $0.confidence > $1.confidence }
    }
}
