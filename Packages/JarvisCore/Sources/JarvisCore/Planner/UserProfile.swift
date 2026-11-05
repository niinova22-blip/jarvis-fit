import Foundation

public enum FitnessGoal: String, Codable, CaseIterable, Sendable {
    case athletic, muscular, leanDefined, strong, balanced

    public var title: LocalizedText {
        switch self {
        case .athletic: return LocalizedText(tr: "Atletik vücut", en: "Athletic body")
        case .muscular: return LocalizedText(tr: "Kaslı vücut", en: "Muscular body")
        case .leanDefined: return LocalizedText(tr: "Yağsız ve belirgin kaslı vücut", en: "Lean, defined body")
        case .strong: return LocalizedText(tr: "Güçlü vücut", en: "Strong body")
        case .balanced: return LocalizedText(tr: "Dengeli ve sağlıklı vücut", en: "Balanced, healthy body")
        }
    }

    public var summary: LocalizedText {
        switch self {
        case .athletic: return LocalizedText(tr: "Kuvvet, kondisyon ve çeviklik dengesi.", en: "A mix of strength, conditioning and agility.")
        case .muscular: return LocalizedText(tr: "Kas kütlesi artışı (hipertrofi) odaklı.", en: "Focused on building muscle (hypertrophy).")
        case .leanDefined: return LocalizedText(tr: "Kası koruyarak yağ kaybı.", en: "Fat loss while keeping muscle.")
        case .strong: return LocalizedText(tr: "Temel hareketlerde maksimum kuvvet.", en: "Maximal strength in the main lifts.")
        case .balanced: return LocalizedText(tr: "Genel sağlık, hareketlilik ve düzenlilik.", en: "General health, mobility and consistency.")
        }
    }
}

public enum ExperienceLevel: String, Codable, CaseIterable, Sendable {
    case beginner, intermediate, advanced

    public var title: LocalizedText {
        switch self {
        case .beginner: return LocalizedText(tr: "Yeni başlıyorum", en: "Beginner")
        case .intermediate: return LocalizedText(tr: "Orta (6+ ay düzenli)", en: "Intermediate (6+ months)")
        case .advanced: return LocalizedText(tr: "İleri (2+ yıl düzenli)", en: "Advanced (2+ years)")
        }
    }

    var rank: Int { self == .beginner ? 1 : self == .intermediate ? 2 : 3 }
}

public enum BiologicalSex: String, Codable, CaseIterable, Sendable {
    case male, female, unspecified

    public var title: LocalizedText {
        switch self {
        case .male: return LocalizedText(tr: "Erkek", en: "Male")
        case .female: return LocalizedText(tr: "Kadın", en: "Female")
        case .unspecified: return LocalizedText(tr: "Belirtmek istemiyorum", en: "Prefer not to say")
        }
    }
}

public enum Equipment: String, Codable, CaseIterable, Sendable {
    case dumbbells, barbell, bench, pullUpBar, resistanceBands, kettlebell, gymMachines

    public var title: LocalizedText {
        switch self {
        case .dumbbells: return LocalizedText(tr: "Dambıl", en: "Dumbbells")
        case .barbell: return LocalizedText(tr: "Halter", en: "Barbell")
        case .bench: return LocalizedText(tr: "Sehpa", en: "Bench")
        case .pullUpBar: return LocalizedText(tr: "Barfiks barı", en: "Pull-up bar")
        case .resistanceBands: return LocalizedText(tr: "Direnç bandı", en: "Resistance bands")
        case .kettlebell: return LocalizedText(tr: "Kettlebell", en: "Kettlebell")
        case .gymMachines: return LocalizedText(tr: "Spor salonu makineleri", en: "Gym machines")
        }
    }
}

public enum HealthLimitation: String, Codable, CaseIterable, Sendable {
    case knee, lowerBack, shoulder, wrist, highBloodPressure, heartCondition, pregnancy

    public var title: LocalizedText {
        switch self {
        case .knee: return LocalizedText(tr: "Diz problemi", en: "Knee issues")
        case .lowerBack: return LocalizedText(tr: "Bel problemi", en: "Lower-back issues")
        case .shoulder: return LocalizedText(tr: "Omuz problemi", en: "Shoulder issues")
        case .wrist: return LocalizedText(tr: "Bilek problemi", en: "Wrist issues")
        case .highBloodPressure: return LocalizedText(tr: "Yüksek tansiyon", en: "High blood pressure")
        case .heartCondition: return LocalizedText(tr: "Kalp rahatsızlığı", en: "Heart condition")
        case .pregnancy: return LocalizedText(tr: "Hamilelik", en: "Pregnancy")
        }
    }

    /// Conditions where the user should get medical clearance before training.
    public var requiresClearance: Bool {
        self == .heartCondition || self == .pregnancy || self == .highBloodPressure
    }
}

public enum DietPreference: String, Codable, CaseIterable, Sendable {
    case omnivore, vegetarian, vegan, pescatarian

    public var title: LocalizedText {
        switch self {
        case .omnivore: return LocalizedText(tr: "Her şeyi yerim", en: "Omnivore")
        case .vegetarian: return LocalizedText(tr: "Vejetaryen", en: "Vegetarian")
        case .vegan: return LocalizedText(tr: "Vegan", en: "Vegan")
        case .pescatarian: return LocalizedText(tr: "Pesketaryen", en: "Pescatarian")
        }
    }
}

public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary, light, moderate, high

    /// Physical activity multiplier on top of BMR (excluding planned training, which is added
    /// separately by the nutrition calculator).
    public var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.35
        case .moderate: return 1.5
        case .high: return 1.65
        }
    }

    public var title: LocalizedText {
        switch self {
        case .sedentary: return LocalizedText(tr: "Çoğunlukla oturarak", en: "Mostly sitting")
        case .light: return LocalizedText(tr: "Hafif hareketli", en: "Lightly active")
        case .moderate: return LocalizedText(tr: "Gün içinde hareketli", en: "Active during the day")
        case .high: return LocalizedText(tr: "Fiziksel işte çalışıyorum", en: "Physical job")
        }
    }
}

/// 1 = Monday … 7 = Sunday (ISO weekday).
public typealias Weekday = Int

public struct UserProfile: Codable, Hashable, Sendable {
    public var name: String
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var sex: BiologicalSex
    public var goal: FitnessGoal
    public var experience: ExperienceLevel
    public var equipment: Set<Equipment>
    public var availableDays: Set<Weekday>
    /// Minutes after midnight.
    public var preferredTrainingMinute: Int
    public var sessionMinutes: Int
    public var limitations: Set<HealthLimitation>
    public var diet: DietPreference
    public var excludedFoods: [String]
    public var activity: ActivityLevel
    public var personality: CoachPersonality
    public var language: AppLanguage

    public init(name: String = "", age: Int = 30, heightCm: Double = 175, weightKg: Double = 75,
                sex: BiologicalSex = .unspecified, goal: FitnessGoal = .balanced, experience: ExperienceLevel = .beginner,
                equipment: Set<Equipment> = [], availableDays: Set<Weekday> = [1, 3, 5], preferredTrainingMinute: Int = 19 * 60,
                sessionMinutes: Int = 45, limitations: Set<HealthLimitation> = [], diet: DietPreference = .omnivore,
                excludedFoods: [String] = [], activity: ActivityLevel = .light, personality: CoachPersonality = .friendly,
                language: AppLanguage = .turkish) {
        self.name = name
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.sex = sex
        self.goal = goal
        self.experience = experience
        self.equipment = equipment
        self.availableDays = availableDays
        self.preferredTrainingMinute = preferredTrainingMinute
        self.sessionMinutes = sessionMinutes
        self.limitations = limitations
        self.diet = diet
        self.excludedFoods = excludedFoods
        self.activity = activity
        self.personality = personality
        self.language = language
    }

    public var bmi: Double { weightKg / pow(heightCm / 100, 2) }

    /// Basic validation used by onboarding; returns problems to show the user.
    public func validationErrors() -> [LocalizedText] {
        var errors: [LocalizedText] = []
        if age < 16 { errors.append(LocalizedText(tr: "JARVIS FIT 16 yaş ve üzeri içindir.", en: "JARVIS FIT is for ages 16 and up.")) }
        if age > 100 { errors.append(LocalizedText(tr: "Yaşı kontrol et.", en: "Please check your age.")) }
        if heightCm < 120 || heightCm > 230 { errors.append(LocalizedText(tr: "Boy 120–230 cm arasında olmalı.", en: "Height must be 120–230 cm.")) }
        if weightKg < 35 || weightKg > 250 { errors.append(LocalizedText(tr: "Kilo 35–250 kg arasında olmalı.", en: "Weight must be 35–250 kg.")) }
        if availableDays.isEmpty { errors.append(LocalizedText(tr: "En az bir antrenman günü seç.", en: "Pick at least one training day.")) }
        return errors
    }
}
