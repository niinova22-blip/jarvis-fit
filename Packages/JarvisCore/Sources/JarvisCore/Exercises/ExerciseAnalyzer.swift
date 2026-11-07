import Foundation

/// Event produced while analysing an exercise.
public enum ExerciseEvent: Sendable, Equatable {
    case repCompleted(RepRecord)
    case partialRep(FormIssue?)
    case holdStarted
    case holdPaused(FormIssue?)
    case formIssue(FormIssue)
}

/// Per-frame result of an analyser.
public struct AnalyzerUpdate: Sendable {
    public var repCount: Int
    public var holdSeconds: TimeInterval
    public var phase: RepPhase
    /// 0 = start position, 1 = full range of motion reached (for the on-screen gauge).
    public var progress: Double
    public var signal: Double?
    public var events: [ExerciseEvent]
}

public protocol ExerciseAnalyzing {
    var exercise: TrackedExercise { get }
    var view: CameraView { get }
    var repCount: Int { get }
    var records: [RepRecord] { get }
    mutating func process(_ frame: PoseFrame) -> AnalyzerUpdate
}

public enum ExerciseAnalyzerFactory {
    /// Creates the analyser for an exercise. `view` is the camera view detected during positioning.
    public static func make(_ exercise: TrackedExercise, view: CameraView) -> any ExerciseAnalyzing {
        if exercise == .plank { return PlankAnalyzer(view: view) }
        return RepExerciseAnalyzer(spec: RepExerciseSpec.spec(for: exercise, view: view), view: view)
    }
}

/// Signal, thresholds and form checks for one counted exercise in one camera view.
public struct RepExerciseSpec {
    public var exercise: TrackedExercise
    public var config: RepSignalConfig
    /// Extracts the movement signal; nil when the user is not in a valid posture for the exercise.
    public var signal: (PoseFeatures) -> Double?
    /// Issues visible in a single frame while a rep is in progress.
    public var frameChecks: (PoseFeatures, RepPhase) -> [FormIssue]
    /// Issue to cue when the user stops short of the turnaround.
    public var partialIssue: FormIssue?
    /// Checks evaluated on the completed rep's extreme value.
    public var extremeCheck: (Double) -> FormIssue?
    /// Minimum share of rep frames that must show a frame issue before it is reported.
    public var issueFrameShare: Double = 0.3
}

/// Counts repetitions and checks form for all non-timed exercises.
///
/// Two counters run side by side:
/// - the *primary* counter on the exercise's joint-angle signal with fixed thresholds (best form
///   feedback, but tuned for one camera view), and
/// - an *adaptive* counter on a view/distance-independent signal (`AdaptiveSignalSpec`).
/// The analyser reports the primary count while it is tracking. It switches to the adaptive counter
/// for the rest of the set when the primary signal could not see a rep the adaptive one counted
/// (unusual angle, close-up with feet out of frame, phone on the floor…) or falls 2 reps behind.
public struct RepExerciseAnalyzer: ExerciseAnalyzing {
    public enum Mode: Sendable { case primary, adaptive }

    public let spec: RepExerciseSpec
    public let view: CameraView
    public private(set) var mode: Mode = .primary
    private var counter: RepCounter
    private var adaptive: AdaptiveRepCounter?
    private let adaptiveSpec: AdaptiveSignalSpec?
    private var scale = BodyScale()
    private var issueFrames: [FormIssue: Int] = [:]
    private var repFrames = 0
    private var primaryPartials = 0
    private var reported: [RepRecord] = []
    /// Frames with an adaptive signal in the current adaptive rep, and how many of them the primary signal also saw.
    private var adaptiveRepFrames = 0
    private var adaptiveRepPrimaryFrames = 0
    /// Range of the adaptive signal during the current primary rep (to veto jitter "reps").
    private var primaryRepLow = Double.infinity
    private var primaryRepHigh = -Double.infinity
    private var lastScale: Double?

    public init(spec: RepExerciseSpec, view: CameraView) {
        self.spec = spec
        self.view = view
        self.counter = RepCounter(config: spec.config)
        self.adaptiveSpec = AdaptiveSignalSpec.spec(for: spec.exercise)
        if let a = adaptiveSpec { adaptive = AdaptiveRepCounter(direction: a.direction, minAmplitude: a.minAmplitude) }
    }

    public var exercise: TrackedExercise { spec.exercise }
    public var repCount: Int { reported.count }
    public var records: [RepRecord] { reported }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerUpdate {
        let features = PoseFeatures(frame)
        let signal = spec.signal(features)
        let bodyScale = scale.update(features, at: frame.timestamp)
        let adaptiveSignal = adaptiveSpec?.extract(features)

        let phaseBefore = activePhase
        let primaryPhaseBefore = counter.phase
        var primaryEvents = counter.update(signal: signal, at: frame.timestamp)
        lastScale = bodyScale ?? lastScale
        if primaryPhaseBefore == .start || primaryPhaseBefore == .unknown {
            primaryRepLow = .infinity
            primaryRepHigh = -.infinity
        }
        if let v = adaptiveSignal {
            primaryRepLow = min(primaryRepLow, v)
            primaryRepHigh = max(primaryRepHigh, v)
        }
        // A primary rep without body travel is joint jitter seen at an unfavourable angle.
        if let adaptiveSpec, let scale = lastScale, primaryRepHigh >= primaryRepLow {
            let travel = primaryRepHigh - primaryRepLow
            primaryEvents.removeAll { event in
                guard case .repCompleted = event else { return false }
                return travel < 0.35 * adaptiveSpec.minAmplitude * scale
            }
        }
        var adaptiveEvents: [RepCounterEvent] = []
        if var a = adaptive {
            let before = a.phase
            adaptiveEvents = a.update(signal: adaptiveSignal, scale: bodyScale, at: frame.timestamp)
            if before == .start || before == .unknown, a.phase == .away {
                adaptiveRepFrames = 0
                adaptiveRepPrimaryFrames = 0
            }
            if adaptiveSignal != nil && a.phase != .start && a.phase != .unknown {
                adaptiveRepFrames += 1
                if signal != nil { adaptiveRepPrimaryFrames += 1 }
            }
            adaptive = a
        }
        for case .partialRep in primaryEvents { primaryPartials += 1 }

        // Decide whether the adaptive counter should take over.
        var catchUp: [RepRecord] = []
        if mode == .primary, let a = adaptive, a.count > 0, adaptiveEvents.contains(where: { if case .repCompleted = $0 { return true }; return false }) {
            let primaryBlind = adaptiveRepFrames > 0 && Double(adaptiveRepPrimaryFrames) / Double(adaptiveRepFrames) < 0.5
            // Primary partials are trusted (real shallow reps) unless the body clearly travelled a
            // full repetition — then the angle signal is foreshortened by the camera angle.
            let recent = a.excursions.suffix(2)
            let fullTravel = !recent.isEmpty && recent.allSatisfy { $0 >= (adaptiveSpec?.fullAmplitude ?? .infinity) }
            let ahead = a.count >= counter.count + 2 && (primaryPartials == 0 || fullTravel)
            if ahead || (primaryBlind && a.count > counter.count) {
                mode = .adaptive
                catchUp = Array(a.records.dropFirst(reported.count).dropLast())
            }
        }

        let phase = activePhase
        if phase == .away || phase == .turn || phase == .returning {
            if phaseBefore == .start || phaseBefore == .unknown {
                issueFrames.removeAll()
                repFrames = 0
            }
            repFrames += 1
            for issue in spec.frameChecks(features, phase) where issue.requiredView == nil || issue.requiredView == view {
                issueFrames[issue, default: 0] += 1
            }
        }

        var events: [ExerciseEvent] = []
        for record in catchUp { events.append(.repCompleted(report(record, issues: []))) }
        for event in mode == .primary ? primaryEvents : adaptiveEvents {
            switch event {
            case .repCompleted(let record):
                var issues: [FormIssue] = []
                if repFrames > 0 {
                    for (issue, frames) in issueFrames.sorted(by: { $0.value > $1.value })
                    where Double(frames) / Double(repFrames + 1) >= spec.issueFrameShare {
                        issues.append(issue)
                    }
                }
                // Angle-based depth checks only make sense on the primary (angle) signal.
                if mode == .primary, let issue = spec.extremeCheck(record.extremeValue) { issues.append(issue) }
                if record.duration < spec.config.controlledRepDuration { issues.append(.tooFast) }
                events.append(.repCompleted(report(record, issues: issues)))
                issueFrames.removeAll()
                repFrames = 0
            case .partialRep:
                events.append(.partialRep(spec.partialIssue))
                issueFrames.removeAll()
                repFrames = 0
            }
        }

        let progress: Double
        if mode == .adaptive, let a = adaptive {
            progress = adaptiveSignal.map { a.progress(of: $0) } ?? 0
        } else {
            progress = signal.map { max(0, min(1, counter.progress(of: $0))) } ?? (adaptiveSignal.flatMap { v in adaptive.map { $0.progress(of: v) } } ?? 0)
        }
        return AnalyzerUpdate(repCount: reported.count, holdSeconds: 0, phase: phase,
                              progress: progress, signal: mode == .primary ? signal : adaptiveSignal, events: events)
    }

    private var activePhase: RepPhase {
        mode == .adaptive ? (adaptive?.phase ?? .unknown) : counter.phase
    }

    /// Re-indexes a record from either counter into the reported sequence.
    private mutating func report(_ record: RepRecord, issues: [FormIssue]) -> RepRecord {
        var r = record
        r.index = reported.count + 1
        r.formIssues = issues
        reported.append(r)
        return r
    }
}

/// Times a plank hold while the body line is straight; pauses when form breaks.
public struct PlankAnalyzer: ExerciseAnalyzing {
    public let exercise = TrackedExercise.plank
    public let view: CameraView
    public private(set) var holdSeconds: TimeInterval = 0
    private var lastTime: TimeInterval?
    private var holding = false
    private var badSince: TimeInterval?
    private var goodSince: TimeInterval?
    private var lastIssue: FormIssue?
    /// Short form breaks are tolerated before the timer pauses.
    public var graceDuration: TimeInterval = 1.0

    public init(view: CameraView) { self.view = view }

    public var repCount: Int { 0 }
    public var records: [RepRecord] { [] }

    /// Classifies the current frame: nil = not in plank posture, issue = in posture with a fault.
    static func evaluate(_ features: PoseFeatures) -> (inPosture: Bool, issue: FormIssue?) {
        guard features.orientation == .horizontal else { return (false, nil) }
        let side = features.bestSide { [.shoulder($0), .hip($0), .ankle($0)] }
        guard let shoulder = features.frame.point(.shoulder(side)),
              let hip = features.frame.point(.hip(side)),
              let foot = features.frame.point(.ankle(side)) ?? features.frame.point(.knee(side)),
              let line = features.angle(.shoulder(side), .hip(side), features.frame.point(.ankle(side)) != nil ? .ankle(side) : .knee(side))
        else { return (false, nil) }
        if line >= 160 { return (true, nil) }
        if line < 130 { return (false, nil) }
        return (true, hipDeviation(shoulder: shoulder, hip: hip, foot: foot))
    }

    /// Whether the hip is below (sag) or above (pike) the shoulder–foot line. y grows downwards.
    static func hipDeviation(shoulder: Point2, hip: Point2, foot: Point2) -> FormIssue {
        let dx = foot.x - shoulder.x
        let t = abs(dx) > 1e-6 ? (hip.x - shoulder.x) / dx : 0.5
        let lineY = shoulder.y + (foot.y - shoulder.y) * t
        return hip.y > lineY ? .plankHipsSag : .plankHipsPike
    }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerUpdate {
        let features = PoseFeatures(frame)
        let (inPosture, issue) = Self.evaluate(features)
        let ok = inPosture && (issue == nil || view != .side)
        var events: [ExerciseEvent] = []
        let now = frame.timestamp
        defer { lastTime = now }

        if ok {
            badSince = nil
            if goodSince == nil { goodSince = now }
            if !holding, let since = goodSince, now - since >= 0.5 {
                holding = true
                events.append(.holdStarted)
            }
        } else {
            goodSince = nil
            if badSince == nil { badSince = now }
            if holding, let since = badSince, now - since >= graceDuration {
                holding = false
                events.append(.holdPaused(inPosture ? issue : nil))
            } else if holding, inPosture, let issue, issue != lastIssue {
                events.append(.formIssue(issue))
            }
        }
        lastIssue = issue
        if holding, let last = lastTime, now > last { holdSeconds += min(now - last, 0.5) }
        return AnalyzerUpdate(repCount: 0, holdSeconds: holdSeconds, phase: holding ? .turn : .start,
                              progress: holding ? 1 : 0, signal: nil, events: events)
    }
}
