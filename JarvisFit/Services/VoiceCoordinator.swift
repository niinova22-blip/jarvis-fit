import Foundation
import AVFoundation
import Speech
import JarvisCore

/// On-device speech in and out, sharing one AVAudioEngine.
///
/// Speech synthesis is rendered with `AVSpeechSynthesizer.write` and played through a player node
/// of the same engine whose input has Apple's voice processing (echo cancellation) enabled, so
/// NOVA's own voice is removed from the microphone signal. In addition, while NOVA speaks only
/// barge-in words ("dur", "stop", "Nova", symptoms) are accepted, which guards against residual echo.
@MainActor
final class VoiceCoordinator: NSObject, ObservableObject {
    @Published private(set) var orbState: JarvisOrb.State = .idle
    @Published private(set) var lastHeard = ""
    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var onDeviceRecognitionAvailable = true
    @Published private(set) var permissionDenied = false
    @Published private(set) var lastSpoken = ""
    /// Name and quality of the voice in use (shown in Settings).
    @Published private(set) var activeVoiceDescription = ""
    /// True when a higher-quality voice of the wanted gender could be downloaded in iOS Settings.
    @Published private(set) var suggestVoiceDownload = false

    /// Called with transcripts. Return true when the text was acted upon (recognition restarts).
    var onUtterance: ((String, Bool) -> Bool)?
    /// Utterances heard while NOVA speaks are only passed on when this returns true.
    var isBargeIn: ((String) -> Bool)?

    private(set) var language: AppLanguage = .turkish
    private var personality: CoachPersonality = .friendly
    private var voiceIdentifier: String?
    private var wantedGender: VoiceCandidate.Gender = .female
    private var cachedVoice: AVSpeechSynthesisVoice?
    private var enhancementEnabled = true

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    // Studio-style output chain: EQ -> compressor -> subtle room.
    private let equalizer = AVAudioUnitEQ(numberOfBands: 4)
    private let compressor = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private let reverb = AVAudioUnitReverb()
    // 48 kHz so voices that render above 22 kHz keep their top end (and the 10 kHz "air" shelf has
    // something to work on); lower-rate voices are upsampled, which costs nothing audible.
    private let playerFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    /// "Name · Quality"; the voice's native sample rate is appended once the first buffer arrives.
    private var voiceBaseDescription = ""
    /// NOVA's own voice (bundled Piper model) when it applies; otherwise Apple voices are used.
    private var neuralVoice: NeuralVoice?
    private var neuralEnabled = true
    private var neuralLoadKey: String?
    private let synthesisQueue = DispatchQueue(label: "jarvis.neural-voice", qos: .userInitiated)
    private var synthesisToken: SynthesisToken?
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

    func configure(language: AppLanguage, personality: CoachPersonality, voiceIdentifier: String?,
                   gender: VoiceCandidate.Gender = .female, enhancement: Bool = true, neural: Bool = true) {
        let languageChanged = language != self.language || recognizer == nil
        self.language = language
        self.personality = personality
        self.voiceIdentifier = voiceIdentifier
        self.wantedGender = gender
        self.enhancementEnabled = enhancement
        self.neuralEnabled = neural
        applyEnhancement()
        cachedVoice = nil
        _ = selectedVoice()
        updateNeuralVoice()
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
                engine.attach(equalizer)
                engine.attach(compressor)
                engine.attach(reverb)
                engine.connect(player, to: equalizer, format: playerFormat)
                engine.connect(equalizer, to: compressor, format: playerFormat)
                engine.connect(compressor, to: reverb, format: playerFormat)
                engine.connect(reverb, to: engine.mainMixerNode, format: playerFormat)
                setUpEnhancementChain()
                engineConfigured = true
            }
            engine.prepare()
            try engine.start()
        } catch {
            print("[Voice] engine start failed: \(error)")
        }
    }

    /// EQ: rumble cut, less boxiness, presence and air; gentle compression for an even,
    /// close-mic "broadcast" sound; a barely audible small room so the voice is not synthetic-dry.
    private func setUpEnhancementChain() {
        let bands = equalizer.bands
        bands[0].filterType = .highPass
        bands[0].frequency = 90
        bands[1].filterType = .parametric
        bands[1].frequency = 280
        bands[1].bandwidth = 1.0
        bands[1].gain = -2
        bands[2].filterType = .parametric
        bands[2].frequency = 3_500
        bands[2].bandwidth = 1.2
        bands[2].gain = 2.5
        bands[3].filterType = .highShelf
        bands[3].frequency = 10_000
        bands[3].gain = 1.5
        let unit = compressor.audioUnit
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -20, 0)
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 6, 0)
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.003, 0)
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.08, 0)
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 4, 0)
        reverb.loadFactoryPreset(.smallRoom)
        applyEnhancement()
    }

    private func applyEnhancement() {
        for band in equalizer.bands { band.bypass = !enhancementEnabled }
        compressor.bypass = !enhancementEnabled
        reverb.wetDryMix = enhancementEnabled ? 6 : 0
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
        request.contextualStrings = ["Nova", "NOVA Coach", "squat", "plank", "crunch", "lunge", "jumping jack"]
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
        // Ignore what was heard while NOVA speaks (and shortly after) unless it is a barge-in.
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
        synthesisToken?.cancel()
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

        // Numbers, units, times and English exercise names are turned into words the voice reads correctly.
        let text = SpeechText.prepare(item.text, language: language)
        let prosody = VoiceProsody.for(personality)
        // Rendered to buffers, so the sentence gap is added as silence after the last buffer.
        let gapFrames = AVAudioFrameCount(max(1, prosody.postDelay * playerFormat.sampleRate))
        if !player.isPlaying { player.play() }
        let state = SpeechWriteState()

        if let neural = neuralVoice {
            speakNeural(text, voice: neural, rate: prosody.rateMultiplier, state: state, gapFrames: gapFrames, generation: generation)
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(prosody.rateMultiplier)
        utterance.pitchMultiplier = Float(prosody.pitchMultiplier)
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.write(utterance) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            // DispatchQueue.main keeps buffer order (FIFO).
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.speechGeneration else { return }
                    if pcm.frameLength == 0 {
                        self.finishUtterance(state: state, gapFrames: gapFrames, generation: generation)
                    } else {
                        self.schedule(pcm, state: state)
                    }
                }
            }
        }
    }

    /// Own neural voice: sentence by sentence on a background queue, so playback starts after the first sentence.
    private func speakNeural(_ text: String, voice: NeuralVoice, rate: Double, state: SpeechWriteState,
                             gapFrames: AVAudioFrameCount, generation: Int) {
        let token = SynthesisToken()
        synthesisToken = token
        let sentences = SpeechText.sentences(text)
        synthesisQueue.async { [weak self] in
            for sentence in sentences {
                guard !token.isCancelled else { return }
                let buffer = voice.synthesize(sentence, rate: rate)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, let buffer, generation == self.speechGeneration else { return }
                        self.schedule(buffer, state: state)
                    }
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.speechGeneration else { return }
                    self.finishUtterance(state: state, gapFrames: gapFrames, generation: generation)
                }
            }
        }
    }

    private func schedule(_ pcm: AVAudioPCMBuffer, state: SpeechWriteState) {
        guard let converted = convert(pcm) else { return }
        state.scheduledAny = true
        player.scheduleBuffer(converted, completionHandler: nil)
    }

    /// End of utterance: continue with the queue once the last buffer (plus the sentence gap) has played.
    private func finishUtterance(state: SpeechWriteState, gapFrames: AVAudioFrameCount, generation: Int) {
        guard state.scheduledAny else {
            speakNext()
            return
        }
        guard let marker = AVAudioPCMBuffer(pcmFormat: playerFormat, frameCapacity: gapFrames) else { return }
        marker.frameLength = gapFrames
        player.scheduleBuffer(marker, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.speechGeneration else { return }
                    self.speakNext()
                }
            }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: playerFormat)
            converterInputFormat = buffer.format
            activeVoiceDescription = voiceBaseDescription + String(format: " · %.1f kHz", buffer.format.sampleRate / 1000)
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

    /// Loads NOVA's own voice for the language in the background (the model is tens of MB).
    private func updateNeuralVoice() {
        guard NeuralVoiceCatalog.shouldUse(enabled: neuralEnabled, wantedGender: wantedGender, manualVoicePicked: voiceIdentifier != nil) else {
            neuralVoice = nil
            neuralLoadKey = nil
            return
        }
        let key = language.rawValue
        guard neuralLoadKey != key else {
            if neuralVoice != nil { showNeuralDescription() }
            return
        }
        neuralLoadKey = key
        neuralVoice = nil
        let language = language
        synthesisQueue.async { [weak self] in
            let voice = NeuralVoice.load(language: language)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.neuralLoadKey == key else { return }
                    self.neuralVoice = voice
                    if voice != nil { self.showNeuralDescription() }
                }
            }
        }
    }

    private func showNeuralDescription() {
        voiceBaseDescription = "NOVA · " + (language == .turkish ? "Özel ses" : "Custom voice")
        activeVoiceDescription = voiceBaseDescription
        suggestVoiceDownload = false
        converterInputFormat = nil
    }

    private func selectedVoice() -> AVSpeechSynthesisVoice? {
        if let cachedVoice { return cachedVoice }
        let voice: AVSpeechSynthesisVoice?
        if let id = voiceIdentifier, let manual = AVSpeechSynthesisVoice(identifier: id), manual.language.hasPrefix(language.rawValue) {
            voice = manual
            suggestVoiceDownload = false
        } else {
            let all = AVSpeechSynthesisVoice.speechVoices()
            if let best = VoiceSelector.best(from: all.map(Self.candidate), language: language, gender: wantedGender,
                                             preferredRegion: language.localeIdentifier) {
                voice = all.first { $0.identifier == best.voice.identifier }
                suggestVoiceDownload = VoiceSelector.shouldSuggestDownload(best.voice, wanted: wantedGender)
            } else {
                voice = AVSpeechSynthesisVoice(language: language.localeIdentifier)
                suggestVoiceDownload = true
            }
        }
        cachedVoice = voice
        if let voice {
            let quality = voice.quality == .premium ? "Premium" : voice.quality == .enhanced ? "Enhanced" : "Standard"
            voiceBaseDescription = "\(voice.name) · \(quality)"
            activeVoiceDescription = voiceBaseDescription
            converterInputFormat = nil // re-read the native rate of the new voice
        }
        return voice
    }

    static func candidate(_ voice: AVSpeechSynthesisVoice) -> VoiceCandidate {
        let gender: VoiceCandidate.Gender = voice.gender == .male ? .male : voice.gender == .female ? .female : .unknown
        let quality = voice.quality == .premium ? 2 : voice.quality == .enhanced ? 1 : 0
        return VoiceCandidate(identifier: voice.identifier, name: voice.name, language: voice.language, gender: gender,
                              quality: quality, isNovelty: voice.voiceTraits.contains(.isNoveltyVoice),
                              isPersonalVoice: voice.voiceTraits.contains(.isPersonalVoice))
    }

    static func availableVoices(for language: AppLanguage) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language.rawValue) && !$0.voiceTraits.contains(.isNoveltyVoice) }
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
