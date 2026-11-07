import Foundation
import Combine
import QuartzCore
import UIKit
import JarvisCore

/// Runs a hands-free live workout: camera → pose → session engine → spoken cues, with voice
/// commands feeding back into the engine. The camera pipeline never waits for speech or the
/// language model.
@MainActor
final class LiveWorkoutController: ObservableObject {
    @Published private(set) var snapshot: SessionSnapshot
    @Published private(set) var latestFrame: PoseFrame?
    @Published private(set) var caption = ""
    @Published private(set) var heard = ""
    @Published private(set) var summary: WorkoutSummary?
    @Published private(set) var flashRep = false
    @Published private(set) var lastFormCue: FormIssue?

    let camera = CameraPoseService()
    let plan: LiveWorkoutPlan
    let planned: PlannedWorkout?

    private var engine: WorkoutSessionEngine
    private var coachVoice: CoachVoice
    private weak var model: AppModel?
    private let assistant: JarvisAssistant
    private var ticker: Timer?
    private var recorded = false
    private var started = false
    private var cameraChanges: AnyCancellable?
    private var recorder: PoseRecorder?
    private var setViews: [Int: CameraView] = [:]
    private let feedback = CueFeedback()

    init(plan: LiveWorkoutPlan, planned: PlannedWorkout?, model: AppModel, assistant: JarvisAssistant) {
        self.plan = plan
        self.planned = planned
        self.model = model
        self.assistant = assistant
        self.engine = WorkoutSessionEngine(plan: plan)
        self.snapshot = WorkoutSessionEngine(plan: plan).snapshot
        let profile = model.profile ?? UserProfile()
        self.coachVoice = CoachVoice(personality: profile.personality, language: profile.language,
                                     userName: profile.name.isEmpty ? nil : profile.name)
        // Re-render when camera state (permission, size, front/back) changes.
        cameraChanges = camera.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private var voice: VoiceCoordinator? { model?.voice }

    func start() {
        guard !started, let model else { return }
        started = true
        UIApplication.shared.isIdleTimerDisabled = true
        feedback.soundsEnabled = model.data.settings.cueSounds
        feedback.hapticsEnabled = model.data.settings.cueSounds
        camera.onPose = { [weak self] frame in self?.handle(frame) }
        let front = model.data.settings.useFrontCamera
        camera.start(front: front, preference: model.data.settings.performance)
        if model.data.settings.recordPoseData {
            recorder = PoseRecorder(recording: PoseRecording(device: Self.deviceModel, appVersion: Self.appVersion,
                                                             cameraPosition: front ? "front" : "back"))
        }

        let voice = model.voice
        voice.isBargeIn = { text in
            let normalized = TextNormalizer.normalize(text)
            if SafetyDetector.detect(text) != nil { return true }
            let words = ["nova", "jarvis", "dur", "durdur", "bekle", "stop", "pause", "wait", "sus", "quiet", "bitti", "done"]
            let tokens = Set(normalized.split(separator: " ").map(String.init))
            return words.contains { tokens.contains($0) }
        }
        voice.onUtterance = { [weak self] text, isFinal in
            guard let self else { return false }
            // Safety words act immediately, even on partial results.
            if let concern = SafetyDetector.detect(text) {
                self.apply(self.engine.handle(.symptom(concern), at: CACurrentMediaTime()))
                return true
            }
            guard isFinal else { return false }
            self.heard = text
            Task { await self.handleUtterance(text) }
            return true
        }
        Task {
            if !voice.hasPermissions { _ = await voice.requestPermissions() }
            voice.startListening()
        }
        apply(engine.start(at: CACurrentMediaTime()))
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        camera.onPose = nil
        camera.stop()
        voice?.onUtterance = nil
        voice?.isBargeIn = nil
        voice?.stopListening()
        UIApplication.shared.isIdleTimerDisabled = false
        recordIfNeeded()
        savePoseRecording()
    }

    /// Writes the raw pose stream (developer option) for offline validation of the rep counters.
    private func savePoseRecording() {
        guard var recorder, !recorder.recording.frames.isEmpty else { return }
        self.recorder = nil
        recorder.markSets(engine.results, views: setViews)
        var recording = recorder.recording
        recording.notes = plan.title.en
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let exercises = Set(recording.sets.map(\.exercise.rawValue)).sorted().joined(separator: "_")
        let url = DataStore.recordingsDirectory.appendingPathComponent("pose-\(formatter.string(from: recording.createdAt))-\(exercises.isEmpty ? "none" : exercises).json")
        let output = recording
        DispatchQueue.global(qos: .utility).async {
            if let data = try? output.encoded() { try? data.write(to: url, options: [.atomic, .completeFileProtection]) }
        }
    }

    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    private func tick() {
        apply(engine.tick(CACurrentMediaTime()))
        snapshot = engine.snapshot
    }

    private func handle(_ frame: PoseFrame) {
        latestFrame = frame
        recorder?.add(frame)
        apply(engine.process(frame))
        snapshot = engine.snapshot
    }

    private func handleUtterance(_ text: String) async {
        guard let model else { return }
        let inWorkout = engine.phase != .finished && engine.phase != .idle
        // In a workout, free chat needs the wake word so background talk is ignored.
        let parser = IntentParser()
        let resting: Bool = { if case .resting = engine.phase { return true }; return false }()
        if case .chat = parser.parse(text, inWorkout: inWorkout, resting: resting),
           IntentParser.stripWakeWord(text, requireWakeWord: true) == nil {
            return
        }
        voice?.setThinking(true)
        let outcome = await assistant.handle(text, model: model, session: engine.snapshot)
        voice?.setThinking(false)
        switch outcome {
        case .reply(let reply):
            caption = reply
            voice?.say(reply, priority: .high)
        case .session(let command):
            apply(engine.handle(command, at: CACurrentMediaTime()))
        case .startWorkout:
            voice?.say(model.t("Antrenman zaten devam ediyor.", "The workout is already running."), priority: .high)
        case .stopSpeaking:
            voice?.stopSpeaking()
        case .repeatLast:
            if let last = voice?.lastSpoken { voice?.say(last, priority: .high) }
        }
        snapshot = engine.snapshot
    }

    func command(_ command: SessionCommand) {
        apply(engine.handle(command, at: CACurrentMediaTime()))
        snapshot = engine.snapshot
    }

    private func apply(_ cues: [CoachCue]) {
        for cue in cues {
            feedback.play(for: cue)
            let text = coachVoice.text(for: cue)
            switch cue {
            case .rep:
                flashRep.toggle()
                voice?.say(text, priority: .immediate, coalesceKey: "rep")
            case .formCue(let issue):
                lastFormCue = issue
                caption = text
                voice?.say(text, priority: cue.priority, coalesceKey: "form")
            case .holdProgress:
                voice?.say(text, priority: cue.priority, coalesceKey: "hold")
            case .framing:
                caption = text
                voice?.say(text, priority: cue.priority, coalesceKey: "framing")
            case .safetyStop:
                caption = text
                voice?.say(text, priority: .critical)
            default:
                caption = text
                voice?.say(text, priority: cue.priority)
            }
        }
        // Remember which camera view each finished set used (for pose recordings).
        if engine.results.count > setViews.count {
            for index in setViews.count..<engine.results.count { setViews[index] = engine.cameraView }
        }
        if engine.phase == .finished, summary == nil {
            summary = engine.summary
            recordIfNeeded()
        }
    }

    /// Saves the workout once — also when the user leaves mid-workout (sets done so far count).
    private func recordIfNeeded() {
        guard !recorded else { return }
        if engine.summary == nil && !engine.results.isEmpty {
            _ = engine.handle(.stop, at: CACurrentMediaTime())
        }
        guard let summary = engine.summary, !summary.sets.isEmpty else { return }
        recorded = true
        model?.recordWorkout(summary, planned: planned)
    }
}
