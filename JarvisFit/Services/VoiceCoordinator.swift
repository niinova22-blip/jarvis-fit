import Foundation
import AVFoundation
import Speech
import JarvisCore

/// On-device speech in and out, sharing one AVAudioEngine.
///
/// Speech synthesis is rendered with `AVSpeechSynthesizer.write` and played through a player node
/// of the same engine whose input has Apple's voice processing (echo cancellation) enabled, so
/// JARVIS's own voice is removed from the microphone signal. In addition, while JARVIS speaks only
/// barge-in words ("dur", "stop", "Jarvis", symptoms) are accepted, which guards against residual echo.
@MainActor
final class VoiceCoordinator: NSObject, ObservableObject {
    @Published private(set) var orbState: JarvisOrb.State = .idle
    @Published private(set) var lastHeard = ""
    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var onDeviceRecognitionAvailable = true
    @Published private(set) var permissionDenied = false
    @Published private(set) var lastSpoken = ""

    /// Called with transcripts. Return true when the text was acted upon (recognition restarts).
    var onUtterance: ((String, Bool) -> Bool)?
    /// Utterances heard while JARVIS speaks are only passed on when this returns true.
    var isBargeIn: ((String) -> Bool)?

    private(set) var language: AppLanguage = .turkish
    private var personality: CoachPersonality = .friendly
    private var voiceIdentifier: String?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playerFormat = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
    private let synthesizer = AVSpeechSynthesizer()
    private var engineConfigured = false
    private var inputEnabled = false

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var taskStartedAt = Date()
    private var silenceTimer: Timer?
    private var restartTimer: Timer?
    private var lastPartial = ""
    private var speechEndedAt = Date.distantPast
    private var wantsListening = false
    private var recognitionGeneration = UUID()

    private struct QueuedSpeech {
        var text: String
        var priority: CuePriority
        var coalesceKey: String?
    }
    private var queue: [QueuedSpeech] = []
    private var currentPriority: CuePriority = .low
    private var speechGeneration = 0
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }

    func configure(language: AppLanguage, personality: CoachPersonality, voiceIdentifier: String?) {
        let languageChanged = language != self.language || recognizer == nil
        self.language = language
        self.personality = personality
        self.voiceIdentifier = voiceIdentifier
        if languageChanged {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier))
            onDeviceRecognitionAvailable = recognizer?.supportsOnDeviceRecognition ?? false
            if isListening { restartRecognition() }
        }
    }

    // MARK: Permissions

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        let granted = speech == .authorized && mic
        permissionDenied = !granted
        return granted
    }

    var hasPermissions: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVAudioApplication.shared.recordPermission == .granted
    }

    // MARK: Engine

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try session.setActive(true, options: [])
    }

    private func ensureEngine(withInput: Bool) {
        if engineConfigured && (inputEnabled || !withInput) {
            if !engine.isRunning { try? engine.start() }
            return
        }
        do {
            try configureSession()
            if engine.isRunning { engine.stop() }
            if withInput {
                // Echo cancellation for the speaker output; must be set while the engine is stopped.
                try? engine.inputNode.setVoiceProcessingEnabled(true)
                engine.inputNode.removeTap(onBus: 0)
                let format = engine.inputNode.outputFormat(forBus: 0)
                engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                    // Called on the audio thread; the request is thread-safe for appending.
                    self?.appendAudio(buffer)
                }
                inputEnabled = true
            }
            if !engineConfigured {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: playerFormat)
                engineConfigured = true
            }
            engine.prepare()
            try engine.start()
        } catch {
            print("[Voice] engine start failed: \(error)")
        }
    }

    private nonisolated func appendAudio(_ buffer: AVAudioPCMBuffer) {
        RequestBox.shared.append(buffer)
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo, let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        Task { @MainActor in
            if type == .began {
                self.stopSpeaking()
            } else if self.wantsListening {
                self.engineConfigured = false
                self.inputEnabled = false
                self.startListening()
            }
        }
    }

    // MARK: Listening

    func startListening() {
        wantsListening = true
        guard hasPermissions, let recognizer, recognizer.isAvailable else {
            isListening = false
            return
        }
        ensureEngine(withInput: true)
        startRecognitionTask()
        isListening = true
        updateOrb()
    }

    func stopListening() {
        wantsListening = false
        endRecognitionTask()
        isListening = false
        updateOrb()
    }

    private func startRecognitionTask() {
        guard let recognizer else { return }
        endRecognitionTask()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.taskHint = .dictation
        request.contextualStrings = ["Jarvis", "squat", "plank", "crunch", "lunge", "jumping jack"]
        self.request = request
        RequestBox.shared.request = request
        lastPartial = ""
        taskStartedAt = Date()
        let generation = UUID()
        recognitionGeneration = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.recognitionGeneration == generation else { return }
                    if let text { self.handleTranscript(text, isFinal: isFinal) }
                    if failed || isFinal { self.scheduleRestart(after: 0.3) }
                }
            }
        }
        // Recognition requests are limited to about a minute; restart periodically.
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.restartRecognition() }
        }
    }

    private func endRecognitionTask() {
        recognitionGeneration = UUID()
        silenceTimer?.invalidate()
        restartTimer?.invalidate()
        RequestBox.shared.request = nil
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func scheduleRestart(after delay: TimeInterval) {
        guard wantsListening else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.wantsListening else { return }
            self.startRecognitionTask()
        }
    }

    func restartRecognition() {
        guard wantsListening else { return }
        startRecognitionTask()
    }

    private func handleTranscript(_ text: String, isFinal: Bool) {
        guard text != lastPartial || isFinal else { return }
        lastPartial = text
        // Ignore what was heard while JARVIS speaks (and shortly after) unless it is a barge-in.
        let echoWindow = isSpeaking || Date().timeIntervalSince(speechEndedAt) < 0.35
        if echoWindow {
            guard isBargeIn?(text) ?? false else { return }
            stopSpeaking()
        }
        lastHeard = text
        if onUtterance?(text, false) == true {
            restartRecognition()
            return
        }
        // End of utterance = 1.1 s without new words.
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: isFinal ? 0.05 : 1.1, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let finalText = self.lastPartial
                guard !finalText.isEmpty else { return }
                _ = self.onUtterance?(finalText, true)
                self.restartRecognition()
            }
        }
    }

    // MARK: Speaking

    /// Speaks a sentence. Higher-priority speech interrupts lower-priority speech; queued speech
    /// with the same `coalesceKey` (e.g. rep counts) is replaced by the newer one.
    func say(_ text: String, priority: CuePriority = .normal, coalesceKey: String? = nil) {
        guard !text.isEmpty else { return }
        let item = QueuedSpeech(text: text, priority: priority, coalesceKey: coalesceKey)
        if isSpeaking {
            if priority >= .critical || (priority > currentPriority && currentPriority <= .normal) {
                queue.removeAll { $0.priority < priority }
                queue.insert(item, at: 0)
                interruptCurrent()
                return
            }
            if let key = coalesceKey { queue.removeAll { $0.coalesceKey == key } }
            if priority == .low && queue.count >= 1 { return }
            queue.append(item)
            queue.sort { $0.priority > $1.priority }
            if queue.count > 4 { queue.removeLast(queue.count - 4) }
        } else {
            queue.append(item)
            speakNext()
        }
    }

    func stopSpeaking() {
        queue.removeAll()
        interruptCurrent()
    }

    private func interruptCurrent() {
        speechGeneration += 1
        synthesizer.stopSpeaking(at: .immediate)
        player.stop()
        isSpeaking = false
        speechEndedAt = Date()
        updateOrb()
        if !queue.isEmpty { speakNext() }
    }

    private func speakNext() {
        guard !queue.isEmpty else {
            isSpeaking = false
            speechEndedAt = Date()
            updateOrb()
            return
        }
        let item = queue.removeFirst()
        ensureEngine(withInput: inputEnabled || wantsListening && hasPermissions)
        currentPriority = item.priority
        isSpeaking = true
        lastSpoken = item.text
        updateOrb()
        speechGeneration += 1
        let generation = speechGeneration

        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = selectedVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(personality.speechRate)
        utterance.prefersAssistiveTechnologySettings = false
        if !player.isPlaying { player.play() }

        let state = SpeechWriteState()
        synthesizer.write(utterance) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            // DispatchQueue.main keeps buffer order (FIFO).
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.speechGeneration else { return }
                    if pcm.frameLength == 0 {
                        guard state.scheduledAny else {
                            self.speakNext()
                            return
                        }
                        // End of utterance: continue when the last buffer has been played.
                        guard let marker = AVAudioPCMBuffer(pcmFormat: self.playerFormat, frameCapacity: 1) else { return }
                        marker.frameLength = 1
                        self.player.scheduleBuffer(marker, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                            DispatchQueue.main.async {
                                MainActor.assumeIsolated {
                                    guard let self, generation == self.speechGeneration else { return }
                                    self.speakNext()
                                }
                            }
                        }
                        return
                    }
                    if let converted = self.convert(pcm) {
                        state.scheduledAny = true
                        self.player.scheduleBuffer(converted, completionHandler: nil)
                    }
                }
            }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: playerFormat)
            converterInputFormat = buffer.format
        }
        guard let converter else { return nil }
        let ratio = playerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let output = AVAudioPCMBuffer(pcmFormat: playerFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    private func selectedVoice() -> AVSpeechSynthesisVoice? {
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id), voice.language.hasPrefix(language.rawValue) {
            return voice
        }
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language.rawValue) }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language.localeIdentifier)
    }

    static func availableVoices(for language: AppLanguage) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language.rawValue) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    func setThinking(_ thinking: Bool) {
        orbState = thinking ? .thinking : (isSpeaking ? .speaking : isListening ? .listening : .idle)
    }

    private func updateOrb() {
        orbState = isSpeaking ? .speaking : isListening ? .listening : .idle
    }
}

/// Mutable flag shared with the synthesiser callback.
final class SpeechWriteState: @unchecked Sendable {
    var scheduledAny = false
}

/// Thread-safe holder for the active recognition request (the audio tap runs off the main thread).
final class RequestBox: @unchecked Sendable {
    static let shared = RequestBox()
    private let lock = NSLock()
    private var _request: SFSpeechAudioBufferRecognitionRequest?

    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.lock(); defer { lock.unlock() }; return _request }
        set { lock.lock(); _request = newValue; lock.unlock() }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let r = _request
        lock.unlock()
        r?.append(buffer)
    }
}
