import Foundation
import JarvisCore
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// Structured answer: the model states whether the message is within NOVA's scope (sport and
/// nutrition) before answering, so off-topic questions get the fixed refusal instead of an answer.
@available(iOS 26.0, *)
@Generable
struct NovaReply {
    @Guide(description: "true if the user's message is about sport, exercise, training, fitness, a sport, recovery, sleep or injury prevention for training, motivation to train, nutrition, diet, food, recipes, supplements or body composition, or is a greeting/thanks. false for anything else (coding, politics, films, music, maths, trivia, news, relationships, money…).")
    var onTopic: Bool
    @Guide(description: "The reply to the user, in the user's language. Empty if onTopic is false.")
    var answer: String
}
#endif

/// Free-form conversation with an on-device language model.
///
/// Uses Apple's on-device Foundation Model (iOS 26+, Apple Intelligence devices such as iPhone
/// 15 Pro and newer). It runs entirely on device, needs no download and is covered by Apple's
/// developer terms. When it is unavailable (older device/OS, Apple Intelligence off, unsupported
/// language) NOVA answers with deterministic replies only.
@MainActor
final class LanguageModelService: ObservableObject {
    enum Availability: Equatable {
        case available
        case unavailable(reason: String)
    }

    @Published private(set) var availability: Availability = .unavailable(reason: "checking")

    #if canImport(FoundationModels)
    private var sessionStorage: Any?
    #endif

    init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                availability = .available
            case .unavailable(let reason):
                availability = .unavailable(reason: String(describing: reason))
            @unknown default:
                availability = .unavailable(reason: "unknown")
            }
            return
        }
        #endif
        availability = .unavailable(reason: "requires iOS 26 and Apple Intelligence")
    }

    var isAvailable: Bool { availability == .available }

    /// Starts a fresh conversation with up-to-date context (called when context changes a lot).
    func resetSession() {
        #if canImport(FoundationModels)
        sessionStorage = nil
        #endif
    }

    enum Reply: Equatable {
        case answer(String)
        /// The model judged the message to be outside sport and nutrition.
        case offTopic
        /// No model on this device, or it failed (guardrail, context window…).
        case unavailable
    }

    func reply(to message: String, context: AssistantContext, maxSentences: Int = 3) async -> Reply {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session: LanguageModelSession
            if let existing = sessionStorage as? LanguageModelSession {
                session = existing
            } else {
                session = LanguageModelSession(instructions: PromptBuilder.instructions(context: context))
                sessionStorage = session
            }
            do {
                let options = GenerationOptions(temperature: 0.6, maximumResponseTokens: maxSentences * 60 + 40)
                let response = try await session.respond(to: message, generating: NovaReply.self, options: options)
                guard response.content.onTopic else { return .offTopic }
                let text = response.content.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return .answer(text) }
            } catch {
                // Context window exceeded or guardrail: start over next time.
                sessionStorage = nil
            }
        }
        #endif
        return .unavailable
    }
}
