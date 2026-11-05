import SwiftUI
import JarvisCore

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var assistant: JarvisAssistant
    @State private var input = ""
    @State private var handsFree = false
    @State private var thinking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if model.data.chat.isEmpty { emptyState }
                            ForEach(model.data.chat) { message in bubble(message).id(message.id) }
                            if thinking {
                                HStack { ProgressView().tint(Theme.accent); Text(model.t("Düşünüyorum…", "Thinking…")).foregroundStyle(Theme.textSecondary) }
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: model.data.chat.count) { _, _ in
                        if let last = model.data.chat.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                inputBar
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("JARVIS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { LiveOrb(voice: model.voice, size: 30) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(model.t("Sohbeti temizle", "Clear chat"), role: .destructive) { model.clearChat(); assistant.llm.resetSession() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onDisappear { if handsFree { toggleHandsFree() } }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.t("Bana antrenmanın, beslenmen veya programın hakkında her şeyi sorabilirsin.",
                         "Ask me anything about your training, nutrition or plan."))
                .foregroundStyle(.white)
            ForEach(suggestions, id: \.self) { suggestion in
                Button(suggestion) { send(suggestion) }
                    .font(Theme.caption)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.surface))
            }
            if !assistant.llm.isAvailable {
                Text(model.t("Serbest sohbet için cihaz üstü Apple dil modeli gerekir (iOS 26 ve Apple Intelligence açık). Komutlar ve sorular yine de çalışır.",
                             "Free conversation needs Apple's on-device language model (iOS 26 with Apple Intelligence on). Commands and questions still work."))
                    .font(Theme.caption).foregroundStyle(Theme.warning)
            }
        }
    }

    private var suggestions: [String] {
        model.language == .turkish
            ? ["Yarın hangi kas grubunu çalışacağız?", "Bugün kaç kalori aldım?", "Kahvaltıda iki yumurta ve bir dilim ekmek yedim", "Protein hedefim ne?"]
            : ["What are we training tomorrow?", "How many calories have I had today?", "For breakfast I had two eggs and a slice of bread", "What's my protein target?"]
    }

    private func bubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(Theme.body)
                .foregroundStyle(message.role == .user ? Color.black : .white)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(message.role == .user ? Theme.accent : Theme.surface))
            if message.role == .jarvis { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button(action: toggleHandsFree) {
                Image(systemName: handsFree ? "mic.fill" : "mic")
                    .font(.title3)
                    .foregroundStyle(handsFree ? .black : Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(handsFree ? Theme.accent : Theme.accentSoft))
            }
            .accessibilityLabel(handsFree ? model.t("Dinlemeyi durdur", "Stop listening") : model.t("Sesli konuş", "Talk"))
            TextField(model.t("JARVIS'e yaz…", "Message JARVIS…"), text: $input)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                .onSubmit { send(input) }
            Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(Theme.background)
    }

    private func toggleHandsFree() {
        handsFree.toggle()
        let voice = model.voice
        if handsFree {
            let requireWake = model.data.settings.requireWakeWord
            voice.isBargeIn = { text in IntentParser.stripWakeWord(text, requireWakeWord: true) != nil || SafetyDetector.detect(text) != nil }
            voice.onUtterance = { text, isFinal in
                guard isFinal else { return false }
                if requireWake && IntentParser.stripWakeWord(text, requireWakeWord: true) == nil { return true }
                send(text)
                return true
            }
            Task {
                if !voice.hasPermissions { _ = await voice.requestPermissions() }
                voice.startListening()
            }
        } else {
            voice.onUtterance = nil
            voice.isBargeIn = nil
            voice.stopListening()
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        input = ""
        model.appendChat(ChatMessage(role: .user, text: trimmed))
        thinking = true
        model.voice.setThinking(true)
        Task {
            let outcome = await assistant.handle(trimmed, model: model)
            thinking = false
            model.voice.setThinking(false)
            let reply: String
            switch outcome {
            case .reply(let text): reply = text
            case .startWorkout:
                if model.canStartLiveWorkout() {
                    reply = model.t("Canlı antrenmanı başlatıyorum.", "Starting your live workout.")
                    model.startWorkout(nil)
                } else {
                    reply = model.t("Bu haftaki ücretsiz canlı antrenman hakkın doldu. Premium ile sınırsız antrenman yapabilirsin.",
                                    "You've used this week's free live workouts. Premium unlocks unlimited workouts.")
                }
            case .stopSpeaking:
                model.voice.stopSpeaking()
                return
            case .repeatLast:
                reply = model.data.chat.last { $0.role == .jarvis }?.text ?? ""
            case .session:
                reply = model.t("Bu komut canlı antrenman sırasında çalışır.", "That command works during a live workout.")
            }
            guard !reply.isEmpty else { return }
            model.appendChat(ChatMessage(role: .jarvis, text: reply))
            if handsFree || model.voice.isListening { model.voice.say(reply, priority: .high) }
        }
    }
}

