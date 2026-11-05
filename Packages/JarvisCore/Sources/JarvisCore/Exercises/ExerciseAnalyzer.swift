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
public struct RepExerciseAnalyzer: ExerciseAnalyzing {
    public let spec: RepExerciseSpec
    public let view: CameraView
    private var counter: RepCounter
    private var issueFrames: [FormIssue: Int] = [:]
    private var repFrames = 0

    public init(spec: RepExerciseSpec, view: CameraView) {
        self.spec = spec
        self.view = view
        self.counter = RepCounter(config: spec.config)
    }

    public var exercise: TrackedExercise { spec.exercise }
    public var repCount: Int { counter.count }
    public var records: [RepRecord] { counter.records }

    public mutating func process(_ frame: PoseFrame) -> AnalyzerUpdate {
        let features = PoseFeatures(frame)
        let signal = spec.signal(features)
        let phaseBefore = counter.phase
        let counterEvents = counter.update(signal: signal, at: frame.timestamp)

        if counter.phase == .away || counter.phase == .turn || counter.phase == .returning {
            if phaseBefore == .start || phaseBefore == .unknown {
                issueFrames.removeAll()
                repFrames = 0
            }
            repFrames += 1
            for issue in spec.frameChecks(features, counter.phase) where issue.requiredView == nil || issue.requiredView == view {
                issueFrames[issue, default: 0] += 1
            }
        }

        var events: [ExerciseEvent] = []
        for event in counterEvents {
            switch event {
            case .repCompleted(let record):
                var issues: [FormIssue] = []
                if repFrames > 0 {
                    for (issue, frames) in issueFrames.sorted(by: { $0.value > $1.value })
                    where Double(frames) / Double(repFrames + 1) >= spec.issueFrameShare {
                        issues.append(issue)
                    }
                }
                if let issue = spec.extremeCheck(record.extremeValue) { issues.append(issue) }
                if record.duration < spec.config.controlledRepDuration { issues.append(.tooFast) }
                counter.annotateLastRecord(with: issues)
                events.append(.repCompleted(counter.records.last ?? record))
                issueFrames.removeAll()
                repFrames = 0
            case .partialRep:
                events.append(.partialRep(spec.partialIssue))
                issueFrames.removeAll()
                repFrames = 0
            }
        }

        let progress = signal.map { max(0, min(1, counter.progress(of: $0))) } ?? 0
        return AnalyzerUpdate(repCount: counter.count, holdSeconds: 0, phase: counter.phase,
                              progress: progress, signal: signal, events: events)
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
