import Foundation

/// Where the user is inside a repetition.
public enum RepPhase: String, Codable, Sendable {
    /// No reliable signal yet (joints missing / not in position).
    case unknown
    /// At the start position (e.g. standing tall in a squat).
    case start
    /// Moving away from the start position (eccentric for most lifts).
    case away
    /// Reached the turnaround position (e.g. bottom of the squat).
    case turn
    /// Returning to the start position.
    case returning
}

/// Thresholds of a scalar movement signal (usually a joint angle in degrees).
public struct RepSignalConfig: Sendable {
    /// Signal value that marks the start position. A rep ends when the signal returns past it.
    public var startThreshold: Double
    /// Signal value that marks the turnaround (full range of motion).
    public var turnThreshold: Double
    /// Movement that reaches this fraction of the start→turn distance but not the turnaround is
    /// reported as a partial rep.
    public var partialFraction: Double = 0.45
    /// Faster reps are treated as noise.
    public var minRepDuration: TimeInterval = 0.35
    /// Slower reps reset the counter (user paused mid-rep).
    public var maxRepDuration: TimeInterval = 12
    /// Reps faster than this are counted but trigger a tempo cue.
    public var controlledRepDuration: TimeInterval = 0.9
    /// If the user's start position never reaches `startThreshold` (camera perspective, mobility),
    /// the threshold is relaxed by up to this amount based on the observed start extreme.
    public var startTolerance: Double = 15
    /// Signal gap after which the current rep is abandoned.
    public var maxSignalGap: TimeInterval = 1.0

    public init(startThreshold: Double, turnThreshold: Double, partialFraction: Double = 0.45,
                minRepDuration: TimeInterval = 0.35, maxRepDuration: TimeInterval = 12,
                controlledRepDuration: TimeInterval = 0.9, startTolerance: Double = 15) {
        self.startThreshold = startThreshold
        self.turnThreshold = turnThreshold
        self.partialFraction = partialFraction
        self.minRepDuration = minRepDuration
        self.maxRepDuration = maxRepDuration
        self.controlledRepDuration = controlledRepDuration
        self.startTolerance = startTolerance
    }

    /// +1 when the signal increases from start to turn, -1 when it decreases.
    var direction: Double { turnThreshold > startThreshold ? 1 : -1 }
}

/// Measurements of one completed repetition.
public struct RepRecord: Codable, Sendable, Equatable {
    public var index: Int
    public var startTime: TimeInterval
    public var turnTime: TimeInterval
    public var endTime: TimeInterval
    /// Most extreme signal value reached (e.g. lowest knee angle).
    public var extremeValue: Double
    public var formIssues: [FormIssue]

    public var duration: TimeInterval { endTime - startTime }
    /// Time from leaving the start position to the turnaround.
    public var awayDuration: TimeInterval { turnTime - startTime }
    /// Time from the turnaround back to the start position.
    public var returnDuration: TimeInterval { endTime - turnTime }
}

public enum RepCounterEvent: Sendable, Equatable {
    case repCompleted(RepRecord)
    /// The user moved part of the way and returned without reaching the turnaround.
    case partialRep(extremeValue: Double)
}

/// Generic hysteresis state machine that turns a noisy scalar signal into repetitions.
///
/// A rep is: start → (cross start threshold) away → (cross turn threshold) turn → returning →
/// (cross start threshold again) start. Hysteresis between the two thresholds removes jitter, the
/// duration limits reject spikes, and gaps in the signal abandon the rep instead of guessing.
public struct RepCounter: Sendable {
    public private(set) var config: RepSignalConfig
    public private(set) var phase: RepPhase = .unknown
    public private(set) var count = 0
    public private(set) var records: [RepRecord] = []

    private var repStartTime: TimeInterval = 0
    private var turnTime: TimeInterval = 0
    private var extreme: Double = 0
    private var lastSignalTime: TimeInterval?
    private var observedStartExtreme: Double?
    private var effectiveStart: Double

    public init(config: RepSignalConfig) {
        self.config = config
        self.effectiveStart = config.startThreshold
    }

    /// Progress from start (0) to turnaround (1) for a signal value.
    public func progress(of value: Double) -> Double {
        let span = config.turnThreshold - effectiveStart
        guard abs(span) > 1e-9 else { return 0 }
        return (value - effectiveStart) / span
    }

    private func isPastStart(_ value: Double) -> Bool {
        config.direction > 0 ? value <= effectiveStart : value >= effectiveStart
    }

    private func isPastTurn(_ value: Double) -> Bool {
        config.direction > 0 ? value >= config.turnThreshold : value <= config.turnThreshold
    }

    private func moreExtreme(_ a: Double, than b: Double) -> Bool {
        config.direction > 0 ? a > b : a < b
    }

    /// Feeds one signal sample. `nil` means the joints needed for the signal were not visible.
    public mutating func update(signal: Double?, at time: TimeInterval) -> [RepCounterEvent] {
        guard let value = signal else {
            if let last = lastSignalTime, time - last > config.maxSignalGap, phase != .unknown {
                phase = .unknown
            }
            return []
        }
        lastSignalTime = time
        adaptStartThreshold(with: value)

        var events: [RepCounterEvent] = []
        switch phase {
        case .unknown:
            if isPastStart(value) { phase = .start }
        case .start:
            if !isPastStart(value) {
                phase = .away
                repStartTime = time
                extreme = value
            }
        case .away:
            if moreExtreme(value, than: extreme) { extreme = value }
            if isPastTurn(value) {
                phase = .turn
                turnTime = time
            } else if isPastStart(value) {
                // Returned without reaching the turnaround.
                if progress(of: extreme) >= config.partialFraction {
                    events.append(.partialRep(extremeValue: extreme))
                }
                phase = .start
            } else if time - repStartTime > config.maxRepDuration {
                phase = .unknown
            }
        case .turn, .returning:
            if moreExtreme(value, than: extreme) {
                extreme = value
                turnTime = time
            }
            if phase == .turn && progress(of: value) < 0.85 { phase = .returning }
            if isPastStart(value) {
                let duration = time - repStartTime
                if duration >= config.minRepDuration && duration <= config.maxRepDuration {
                    count += 1
                    let record = RepRecord(index: count, startTime: repStartTime, turnTime: turnTime,
                                           endTime: time, extremeValue: extreme, formIssues: [])
                    records.append(record)
                    events.append(.repCompleted(record))
                }
                phase = .start
            } else if time - repStartTime > config.maxRepDuration {
                phase = .unknown
            }
        }
        return events
    }

    /// Relaxes the start threshold when the user's actual start position stays just short of it.
    private mutating func adaptStartThreshold(with value: Double) {
        guard phase == .unknown || phase == .start || phase == .away else { return }
        // Track the most start-like value, slowly forgetting old extremes.
        if let observed = observedStartExtreme {
            let isMoreStartLike = config.direction > 0 ? value < observed : value > observed
            observedStartExtreme = isMoreStartLike ? value : observed + (value - observed) * 0.002
        } else {
            observedStartExtreme = value
        }
        guard let observed = observedStartExtreme else { return }
        let margin = 6.0
        if config.direction > 0 {
            let candidate = observed + margin
            effectiveStart = min(config.startThreshold + config.startTolerance, max(config.startThreshold, candidate))
        } else {
            let candidate = observed - margin
            effectiveStart = max(config.startThreshold - config.startTolerance, min(config.startThreshold, candidate))
        }
        // Keep the start threshold clearly away from the turnaround.
        let minimumGap = abs(config.turnThreshold - config.startThreshold) * 0.5
        if abs(config.turnThreshold - effectiveStart) < minimumGap {
            effectiveStart = config.turnThreshold - config.direction * minimumGap
        }
    }

    /// Attaches form issues to the most recent record (analysers call this after checks).
    public mutating func annotateLastRecord(with issues: [FormIssue]) {
        guard !records.isEmpty, !issues.isEmpty else { return }
        records[records.count - 1].formIssues = issues
    }

    public mutating func reset() {
        phase = .unknown
        count = 0
        records = []
        lastSignalTime = nil
        observedStartExtreme = nil
        effectiveStart = config.startThreshold
    }

    public var effectiveStartThreshold: Double { effectiveStart }
}
