import Foundation
import JarvisCore

/// Handles one user utterance outside or inside a workout: deterministic intents first, the
/// on-device language model only for open conversation.
@MainActor
final class JarvisAssistant: ObservableObject {
    let llm = LanguageModelService()
    private let parser = IntentParser()
    private let mealParser = MealParser()

    enum Outcome {
        case reply(String)
        case session(SessionCommand)
        case startWorkout
        case stopSpeaking
        case repeatLast
    }

    func handle(_ utterance: String, model: AppModel, session: SessionSnapshot? = nil) async -> Outcome {
        guard let context = model.assistantContext(session: session) else {
            return .reply(model.t("Önce kurulumu tamamlayalım.", "Let's finish setup first."))
        }
        let resting: Bool = { if case .resting = session?.phase { return true }; return false }()
        let intent = parser.parse(utterance, inWorkout: session != nil && session?.phase != .finished, resting: resting)

        // Remember useful facts (likes, struggles…) — never the raw conversation.
        if model.data.memoryEnabled, let memory = MemoryExtractor.extract(from: utterance) {
            model.addMemory(memory)
        }

        switch intent {
        case .symptom(let concern):
            if session != nil { return .session(.symptom(concern)) }
            return .reply(concern.message.resolve(context.language))
        case .session(let command):
            if session != nil { return .session(command) }
            if command == .stop || command == .pause { return .stopSpeaking }
            return .reply(model.t("Şu an aktif bir antrenman yok. 'Antrenmana başla' diyebilirsin.", "There's no active workout. Say 'start workout' to begin."))
        case .query(let query):
            return .reply(ResponseComposer.answer(query, context: context).resolve(context.language))
        case .logMeal(let text):
            return .reply(logMeal(text, model: model))
        case .startWorkout:
            return .startWorkout
        case .repeatLast:
            return .repeatLast
        case .stopSpeaking:
            return .stopSpeaking
        case .chat(let text):
            let clean = IntentParser.stripWakeWord(text, requireWakeWord: false) ?? text
            guard !clean.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .reply(model.t("Buradayım.", "I'm here."))
            }
            // NOVA talks about sport and nutrition only; clear cases are decided without the model.
            let scope = TopicGuard.classify(clean)
            switch scope {
            case .offTopic: return .reply(TopicGuard.refusal.resolve(context.language))
            case .smallTalk: return .reply(TopicGuard.smallTalkReply(clean).resolve(context.language))
            case .sportOrNutrition, .unclear: break
            }
            guard model.isPremium || model.data.chat.filter({ $0.role == .user && $0.date.dayKey == Date().dayKey }).count < 10 else {
                return .reply(model.t("Ücretsiz sürümde günlük sohbet sınırına ulaştın. Premium ile sınırsız konuşabiliriz.",
                                      "You've reached today's free chat limit. Premium unlocks unlimited conversation."))
            }
            switch await llm.reply(to: clean, context: context, maxSentences: session == nil ? 6 : 2) {
            case .answer(let text):
                return .reply(text)
            case .offTopic:
                return .reply(TopicGuard.refusal.resolve(context.language))
            case .unavailable:
                // No on-device model: built-in sport and nutrition knowledge, personalised.
                if let known = FitnessKnowledge.answer(clean, context: context) {
                    return .reply(known.resolve(context.language))
                }
                return .reply(PromptBuilder.fallbackReply(context.language).resolve(context.language))
            }
        }
    }

    /// Parses a spoken meal and logs it. Assumed portions are stated so the user can correct them.
    func logMeal(_ text: String, model: AppModel) -> String {
        let parsed = mealParser.parse(text)
        guard !parsed.items.isEmpty else {
            return model.t("Hangi yiyecekleri yediğini anlayamadım. Beslenme ekranından da ekleyebilirsin.",
                           "I couldn't tell which foods you ate. You can also add them on the Nutrition screen.")
        }
        let meal = parsed.meal ?? MealType.forHour(Calendar.current.component(.hour, from: Date()))
        let entries = parsed.items.map { FoodLogEntry(date: Date(), meal: meal, food: $0.food, quantity: $0.quantity, unit: $0.unit, source: .voice) }
        model.addFoodEntries(entries)
        let kcal = Int(entries.reduce(0) { $0 + $1.macros.kcal }.rounded())
        let protein = Int(entries.reduce(0) { $0 + $1.macros.protein }.rounded())
        let names = entries.map { entry -> String in
            let q = entry.quantity == entry.quantity.rounded() ? String(Int(entry.quantity)) : String(format: "%.1f", entry.quantity)
            return "\(q) \(entry.unit.title.resolve(model.language)) \(entry.name.resolve(model.language).lowercased())"
        }
        let assumed = parsed.items.filter(\.assumedQuantity).map { $0.food.name.resolve(model.language).lowercased() }
        var reply = model.t("\(meal.title.tr) için ekledim: \(names.joined(separator: ", ")). Yaklaşık \(kcal) kalori, \(protein) gram protein.",
                            "Added to \(meal.title.en.lowercased()): \(names.joined(separator: ", ")). About \(kcal) kcal and \(protein) g protein.")
        if !assumed.isEmpty {
            reply += model.t(" \(assumed.joined(separator: ", ")) için standart porsiyon varsaydım; gerekirse Beslenme ekranından düzeltebilirsin.",
                             " I assumed a standard portion for \(assumed.joined(separator: ", ")); you can adjust it on the Nutrition screen.")
        }
        return reply
    }
}
