import Foundation
import JarvisCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Free-form conversation with an on-device language model.
///
/// Uses Apple's on-device Foundation Model (iOS 26+, Apple Intelligence devices such as iPhone
/// 15 Pro and newer). It runs entirely on device, needs no download and is covered by Apple's
/// developer terms. When it is unavailable (older device/OS, Apple Intelligence off, unsupported
/// language) JARVIS answers with deterministic replies only.
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

    func reply(to message: String, context: AssistantContext, maxSentences: Int = 3) async -> String {
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
                let options = GenerationOptions(temperature: 0.6, maximumResponseTokens: maxSentences * 45)
                let response = try await session.respond(to: message, options: options)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            } catch {
                // Context window exceeded or guardrail: start over next time.
                sessionStorage = nil
                return context.language == .turkish
                    ? "Bunu şu an yanıtlayamıyorum. Başka bir şekilde sorabilir misin?"
                    : "I can't answer that right now. Could you ask another way?"
            }
        }
        #endif
        return PromptBuilder.fallbackReply(context.language).resolve(context.language)
    }
}
