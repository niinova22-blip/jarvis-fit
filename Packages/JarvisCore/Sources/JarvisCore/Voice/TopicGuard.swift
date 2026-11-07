import Foundation

/// NOVA only talks about sport and nutrition. This deterministic first pass decides clear cases
/// before (and independently of) the language model, which makes the final call on ambiguous ones.
public enum TopicScope: Equatable, Sendable {
    /// Clearly about training, exercise, nutrition, diet, recovery or the body.
    case sportOrNutrition
    /// Greetings, thanks, "how are you" — answered briefly, never refused.
    case smallTalk
    /// Clearly about something else (coding, politics, films, homework…).
    case offTopic
    /// No clear signal; the language model decides.
    case unclear
}

public enum TopicGuard {
    /// The fixed answer for anything outside sport and nutrition.
    public static let refusal = LocalizedText(
        tr: "Ben yalnızca spor ve beslenme konusunda yardımcı olabilirim. Antrenman, egzersiz, beslenme ya da diyetle ilgili ne sormak istersin?",
        en: "I can only help with sport and nutrition. What would you like to know about training, exercise, food or diet?")

    public static func smallTalkReply(_ text: String) -> LocalizedText {
        let n = TextNormalizer.normalize(text)
        if has(n, ["tesekkur", "sagol", "eyvallah", "thank", "thanks", "cheers"]) {
            return LocalizedText(tr: "Rica ederim! Antrenman ya da beslenmeyle ilgili başka bir şey olursa buradayım.",
                                 en: "You're welcome! I'm here for anything about training or nutrition.")
        }
        if has(n, ["nasilsin", "naber", "ne haber", "how are you", "whats up"]) {
            return LocalizedText(tr: "İyiyim, antrenmana hazırım! Bugün antrenman ya da beslenme için ne yapalım?",
                                 en: "I'm great and ready to train! What shall we do for your training or nutrition today?")
        }
        return LocalizedText(tr: "Merhaba! Antrenman, egzersiz ya da beslenmeyle ilgili ne konuşmak istersin?",
                             en: "Hi! What would you like to talk about — training, exercise or nutrition?")
    }

    // Folded (ASCII, lower-case) word stems; matched at the start of a word so Turkish suffixes work.
    static let sportStems = [
        // Turkish — training
        "spor", "antrenman", "antreman", "idman", "egzersiz", "fitnes", "kondisyon", "kardiyo", "kosu", "kostum", "kosmak",
        "yuruyus", "yuzme", "bisiklet", "esneme", "esnet", "isinma", "soguma", "skuat", "squat", "sinav", "mekik", "plank",
        "lunge", "barfiks", "deadlift", "bench", "dambil", "dumbbell", "halter", "agirlik", "tekrar sayi", "dinlenme",
        "toparlan", "sakatl", "kramp", "nabiz", "hipertrofi", "kuvvet", "dayaniklilik", "esneklik", "mobilite", "postur",
        "durus", "karin kas", "kaslar", "kasim agri", "kas agri", "kas kazan", "kas yap", "kas kutle", "bacak", "gogus", "sirt",
        "omuz", "kalca", "baldir", "biceps", "triceps", "pazu", "cardio", "isinmak", "tempo", "pilates", "yoga", "futbol",
        "basketbol", "voleybol", "tenis", "fitness", "salon", "spor salon", "program",
        // Turkish — nutrition and body
        "beslen", "diyet", "yemek", "yemeg", "yedim", "yiyece", "ogun", "kahvalt", "atistir", "kalori", "protein",
        "karbonhidrat", "seker", "lifli", "vitamin", "mineral", "takviye", "kreatin", "whey", "bcaa", "kafein", "kahve",
        "elektrolit", "sodyum", "makro", "porsiyon", "ekmek", "pirinc", "makarna", "tavuk", "balik", "yumurta", "yogurt",
        "peynir", "meyve", "sebze", "salata", "cikolata", "tatli", "alkol", "oruc", "aralikli", "ketojenik", "keto",
        "vegan", "vejetaryen", "glutensiz", "laktoz", "kilo", "zayifla", "metabolizma", "beden kitle", "yag yak",
        "yag oran", "yag kayb", "yagi", "yagli", "yagsiz", "gobek", "gobeg", "definasyon", "bulk", "hacim", "su ic", "uyku", "uyuyam", "yorgun", "tarif",
        // English
        "workout", "exercis", "training", "gym", "cardio", "running", "jogging", "walking", "swimming", "cycling",
        "stretch", "warm up", "warmup", "cool down", "squat", "pushup", "push up", "pullup", "pull up", "plank", "lunge",
        "deadlift", "bench press", "curl", "dumbbell", "barbell", "kettlebell", "reps", "recovery", "sore", "doms",
        "injur", "cramp", "heart rate", "muscle", "strength", "endurance", "mobility", "flexibility", "posture", "abs",
        "glute", "bicep", "tricep", "hypertrophy", "sets", "chest", "leg day", "shoulders", "arms", "biceps", "nutrition", "diet", "food", "meal", "breakfast", "lunch", "dinner",
        "snack", "calori", "kcal", "protein", "carb", "sugar", "fiber", "fibre", "vitamin", "supplement", "creatine",
        "whey", "caffeine", "coffee", "hydrat", "electrolyte", "macro", "portion", "chicken", "rice", "pasta", "fruit",
        "vegetable", "alcohol", "fasting", "keto", "vegan", "vegetarian", "lactose", "gluten", "lose weight",
        "weight loss", "gain weight", "fat loss", "body fat", "burn fat", "metabolism", "bmi", "bulking", "cutting",
        "sleep", "tired", "fatigue", "yoga", "pilates", "football", "basketball", "tennis", "sport", "recipe", "eat",
    ]

    static let offTopicStems = [
        // Turkish
        "siyaset", "politik", "cumhurbaskan", "milletvekil", "hukumet", "borsa", "bitcoin", "kripto", "dolar kac",
        "doviz", "hisse", "faiz", "yazilim", "kodla", "kod yaz", "python", "javascript", "html", "sql", "matematik",
        "denklem", "integral", "turev", "fizik", "kimya", "cografya", "baskent", "film", "dizi oner", "dizisi", "sarki",
        "muzik", "sanatci", "sarkici", "hava durumu", "yagmur yag", "haber", "sevgili", "iliski", "araba", "telefon al",
        "bilgisayar", "odev", "cevir", "ceviri", "siir", "hikaye", "masal", "fikra", "saka yap", "astroloji", "burc",
        "oyun oner", "tarihte", "savas", "ekonomi", "is basvuru", "ozgecmis",
        // English
        "politic", "election", "president", "government", "stock market", "crypto", "bitcoin", "invest", "coding",
        "code", "programming language", "python", "javascript", "html", "sql", "math", "equation", "integral",
        "physics", "chemistry", "geography", "capital of", "movie", "series", "song", "music", "singer", "celebrity",
        "weather", "news", "girlfriend", "boyfriend", "dating", "relationship", "laptop", "homework", "translate",
        "poem", "story", "joke", "horoscope", "zodiac", "history of", "world war", "economy", "resume", "cover letter",
    ]

    static let smallTalkStems = [
        "merhaba", "selam", "gunaydin", "iyi aksamlar", "iyi geceler", "nasilsin", "naber", "ne haber", "tesekkur",
        "sagol", "eyvallah", "hello", "hi", "hey", "good morning", "good evening", "how are you", "whats up", "thanks",
        "thank you", "cheers",
    ]

    /// True when any stem starts a word (or word sequence) of the normalised text.
    static func has(_ normalized: String, _ stems: [String]) -> Bool {
        let padded = " " + normalized + " "
        return stems.contains { padded.contains(" " + $0) }
    }

    public static func classify(_ text: String) -> TopicScope {
        let n = TextNormalizer.normalize(text).trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return .smallTalk }
        let sport = has(n, sportStems)
        let off = has(n, offTopicStems)
        if sport && !off { return .sportOrNutrition }
        if off && !sport { return .offTopic }
        if sport && off { return .unclear }
        let words = n.split(separator: " ").count
        if has(n, smallTalkStems) && words <= 5 { return .smallTalk }
        return .unclear
    }
}
