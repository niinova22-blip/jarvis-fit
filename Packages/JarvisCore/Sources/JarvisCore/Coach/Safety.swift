import Foundation

/// Symptoms that stop a workout. NOVA never diagnoses; it stops, gives first-step safety advice
/// and points to professional help.
public enum SafetyConcern: String, Codable, CaseIterable, Sendable {
    /// Chest pain, pressure, or pain spreading to the arm/jaw — possible emergency.
    case chestPain
    /// Shortness of breath beyond normal exertion.
    case breathing
    /// Dizziness, light-headedness, fainting feeling, blurred vision.
    case dizziness
    /// Sharp or sudden pain in a joint/muscle.
    case sharpPain
    /// General pain or discomfort.
    case pain
    /// Nausea.
    case nausea

    public var isEmergency: Bool { self == .chestPain || self == .breathing }

    public var message: LocalizedText {
        switch self {
        case .chestPain:
            return LocalizedText(
                tr: "Antrenmanı hemen durduruyorum. Göğüs ağrısı ciddi olabilir. Otur ve dinlen. Ağrı geçmiyorsa, kola, çeneye yayılıyorsa ya da nefes darlığı varsa hemen 112'yi ara. Ben teşhis koyamam.",
                en: "I'm stopping the workout now. Chest pain can be serious. Sit down and rest. If it doesn't go away, spreads to your arm or jaw, or you are short of breath, call emergency services right away. I can't diagnose this.")
        case .breathing:
            return LocalizedText(
                tr: "Antrenmanı durdurdum. Otur, yavaş ve derin nefes al. Nefes darlığın birkaç dakikada geçmezse ya da kötüleşirse acil yardım çağır.",
                en: "Workout stopped. Sit down and breathe slowly. If your shortness of breath doesn't ease within a few minutes or gets worse, call for emergency help.")
        case .dizziness:
            return LocalizedText(
                tr: "Antrenmanı durdurdum. Hemen otur ya da uzan, su iç. Baş dönmesi geçmezse veya bayılma hissi olursa bir sağlık profesyoneline başvur.",
                en: "Workout stopped. Sit or lie down right away and drink some water. If the dizziness doesn't pass or you feel faint, contact a health professional.")
        case .sharpPain:
            return LocalizedText(
                tr: "Durduruyorum. Keskin ağrıyla devam etme. Bölgeyi dinlendir; ağrı sürerse ya da şişlik olursa doktora görün.",
                en: "Stopping. Don't push through sharp pain. Rest the area; if pain persists or there is swelling, see a doctor.")
        case .pain:
            return LocalizedText(
                tr: "Antrenmanı duraklattım. Ağrı varken zorlamayalım. Ağrı geçmezse bir sağlık profesyoneline danış. Hazır olduğunda devam diyebilirsin.",
                en: "Workout paused. Let's not push through pain. If it doesn't go away, consult a health professional. Say continue when you're ready.")
        case .nausea:
            return LocalizedText(
                tr: "Duraklattım. Otur, yavaş nefes al ve biraz su iç. Kendini iyi hissetmiyorsan bugünlük bırakmak en doğrusu.",
                en: "Paused. Sit down, breathe slowly and sip some water. If you don't feel well, it's best to stop for today.")
        }
    }

    /// Pain and nausea pause (user may resume); the others end the session.
    public var endsWorkout: Bool {
        switch self {
        case .pain, .nausea: return false
        default: return true
        }
    }
}

/// Detects safety concerns in an utterance (Turkish and English).
public enum SafetyDetector {
    private static let patterns: [(SafetyConcern, [String])] = [
        (.chestPain, ["gogsum agri", "gogsumde agri", "gogus agri", "gogsum sikis", "gogsumde baski", "kalbim agri", "kalbim cok hizli", "chest pain", "chest hurts", "chest tight", "pressure in my chest", "heart hurts"]),
        (.breathing, ["nefes alamiyorum", "nefesim daraldi", "nefes darligi", "can't breathe", "cant breathe", "cannot breathe", "short of breath"]),
        (.dizziness, ["basim donuyor", "bas donmesi", "bayilacak", "bayiliyorum", "gozum karardi", "gozlerim karardi", "dizzy", "lightheaded", "light headed", "going to faint", "feel faint", "blacking out"]),
        (.sharpPain, ["keskin agri", "bir sey koptu", "birsey koptu", "kasim koptu", "sakatlandim", "sharp pain", "something popped", "i'm injured", "im injured", "i got injured", "pulled a muscle"]),
        (.nausea, ["midem bulaniyor", "kusacagim", "nauseous", "feel sick", "going to throw up"]),
        (.pain, ["agriyor", "agri var", "acidi", "aciyor", "it hurts", "hurts", "pain in my", "my knee hurts", "my back hurts", "in pain"])
    ]

    public static func detect(_ utterance: String) -> SafetyConcern? {
        let text = " " + TextNormalizer.normalize(utterance) + " "
        for (concern, keys) in patterns where keys.contains(where: { text.contains(TextNormalizer.normalize($0)) }) {
            return concern
        }
        return nil
    }
}
