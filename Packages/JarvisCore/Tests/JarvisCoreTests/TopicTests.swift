import XCTest
@testable import JarvisCore

final class TopicTests: XCTestCase {
    func testSportAndNutritionQuestionsAreInScope() {
        let questions = [
            "Günde ne kadar protein almalıyım?", "Squat yaparken dizim içe kaçıyor mu?", "Kreatin zararlı mı?",
            "Göbek yağı nasıl gider?", "Akşam yemeğinde ne yesem?", "Koşuya yeni başlıyorum, nasıl başlamalıyım?",
            "How many sets should I do for chest?", "Is intermittent fasting good for fat loss?", "What should I eat after a workout?",
            "Futbol maçından önce ne yemeliyim?", "Uykusuzluk kas gelişimini etkiler mi?", "Is coffee before the gym ok?",
        ]
        for q in questions { XCTAssertEqual(TopicGuard.classify(q), .sportOrNutrition, q) }
    }

    func testOffTopicQuestionsAreRefused() {
        let questions = [
            "Python'da liste nasıl sıralanır?", "Cumhurbaşkanı seçimi ne zaman?", "Bana bir film öner",
            "Fransa'nın başkenti neresi?", "Yarın hava durumu nasıl?", "Write me a poem about the sea",
            "Solve this equation: 2x + 3 = 7", "Should I invest in bitcoin?", "Bir fıkra anlat",
            "Translate this sentence into German", "Bana bir şarkı söyle",
        ]
        for q in questions { XCTAssertEqual(TopicGuard.classify(q), .offTopic, q) }
    }

    func testSmallTalkIsNotRefused() {
        for q in ["Merhaba", "Selam Nova", "Nasılsın?", "Teşekkürler", "Hi", "Thank you!", "How are you?"] {
            XCTAssertEqual(TopicGuard.classify(q), .smallTalk, q)
        }
        XCTAssertTrue(TopicGuard.smallTalkReply("teşekkür ederim").tr.hasPrefix("Rica"))
    }

    func testRefusalWording() {
        XCTAssertTrue(TopicGuard.refusal.tr.contains("yalnızca spor ve beslenme"))
        XCTAssertTrue(TopicGuard.refusal.en.contains("only help with sport and nutrition"))
    }

    func testModelInstructionsContainScopeAndRefusal() {
        let context = AssistantContext(profile: UserProfile(name: "Ali"), todayWeekday: 1)
        let text = PromptBuilder.instructions(context: context)
        XCTAssertTrue(text.contains(TopicGuard.refusal.tr))
        XCTAssertTrue(text.contains("HER şeyi"))
    }

    func testKnowledgeBaseAnswersCommonQuestions() {
        let cases: [(String, String)] = [
            ("Günde ne kadar protein almalıyım?", "protein"), ("How much protein do I need?", "protein"),
            ("Kilo vermek için ne yapmalıyım?", "fatLoss"), ("Kas kazanmak istiyorum", "muscleGain"),
            ("Kreatin kullanmalı mıyım?", "creatine"), ("Antrenmandan önce ne yemeliyim?", "preWorkout"),
            ("Antrenman sonrası ne yemeliyim?", "postWorkout"), ("Günde ne kadar su içmeliyim?", "water"),
            ("Kaslarım ağrıyor", "soreness"), ("Göbek yağı nasıl erir?", "spotReduction"),
            ("Kaç set kaç tekrar yapmalıyım?", "setsReps"), ("Alkol kas gelişimini etkiler mi?", "alcohol"),
            ("Aralıklı oruç işe yarar mı?", "fasting"), ("Evde ekipmansız antrenman", "homeWorkout"),
            ("Dizimde ağrı var, sakatlandım mı?", "injury"), ("Hiç motivasyonum yok", "motivation"),
            ("What should I eat for a healthy meal?", "healthyMeal"), ("How do I warm up?", "warmup"),
        ]
        for (q, id) in cases { XCTAssertEqual(FitnessKnowledge.topicId(for: q), id, q) }
        XCTAssertNil(FitnessKnowledge.topicId(for: "Fransa'nın başkenti neresi?"))
    }

    func testKnowledgeIsPersonalised() {
        var profile = UserProfile(name: "Ali")
        profile.weightKg = 80
        let context = AssistantContext(profile: profile, todayWeekday: 1)
        let answer = FitnessKnowledge.answer("Ne kadar protein yemeliyim?", context: context)
        XCTAssertNotNil(answer)
        XCTAssertTrue(answer!.tr.contains("128–176"), answer!.tr)
        XCTAssertTrue(answer!.en.contains("80 kg"))
    }
}
