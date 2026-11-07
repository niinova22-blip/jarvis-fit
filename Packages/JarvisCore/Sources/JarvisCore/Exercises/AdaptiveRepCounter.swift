import Foundation

/// View- and distance-independent movement signal for an exercise.
///
/// The fixed-threshold signals in `ExerciseSpecs` are joint angles, which are only reliable from the
/// camera view they were designed for (an elbow angle seen head-on is foreshortened). These signals
/// instead follow the *vertical travel* of a key point (hips in a squat, shoulders in a push-up,
/// wrists in a curl), divided by the body's own size, so they work from the front, the side, a
/// diagonal, from close or far, and with the phone on the floor or on a table. Thresholds are not
/// fixed angles but are learned from the user's own range of motion (`AdaptiveRepCounter`).
public struct AdaptiveSignalSpec: Sendable {
    /// +1 when the value grows while moving away from the start position, -1 otherwise.
    public var direction: Double
    /// Typical travel of a full repetition, in body-scale units (≈ torso lengths).
    public var fullAmplitude: Double
    /// Smallest travel (body-scale units) that counts as a repetition. Starting values; to be tuned
    /// with recorded real sessions (docs/DEVICE_TESTING.md).
    public var minAmplitude: Double
    /// Raw signal in image units (y is top-down, so "down" movements increase it).
    public var extract: @Sendable (PoseFeatures) -> Double?

    public static func spec(for exercise: TrackedExercise) -> AdaptiveSignalSpec? {
        /// Wrist height below the shoulder of one side; falls back to twice the elbow height when the
        /// wrist is out of frame (close-ups: hands overhead leave the image first).
        @Sendable func armBelowShoulder(_ f: PoseFeatures, _ side: Side) -> Double? {
            guard let s = f.frame.point(.shoulder(side)) else { return nil }
            if let w = f.frame.point(.wrist(side)) { return w.y - s.y }
            if let e = f.frame.point(.elbow(side)) { return 2 * (e.y - s.y) }
            return nil
        }
        switch exercise {
        case .squat:
            return AdaptiveSignalSpec(direction: 1, fullAmplitude: 0.5, minAmplitude: 0.25) { $0.hipMid?.y }
        case .lunge:
            return AdaptiveSignalSpec(direction: 1, fullAmplitude: 0.4, minAmplitude: 0.2) { $0.hipMid?.y }
        case .pushUp:
            return AdaptiveSignalSpec(direction: 1, fullAmplitude: 0.3, minAmplitude: 0.15) { $0.shoulderMid?.y }
        case .crunch:
            return AdaptiveSignalSpec(direction: -1, fullAmplitude: 0.3, minAmplitude: 0.15) { $0.shoulderMid?.y }
        case .gluteBridge:
            return AdaptiveSignalSpec(direction: -1, fullAmplitude: 0.22, minAmplitude: 0.12) { $0.hipMid?.y }
        case .jumpingJack:
            return AdaptiveSignalSpec(direction: -1, fullAmplitude: 1.4, minAmplitude: 0.7) { f in
                f.bilateral({ armBelowShoulder(f, $0) })
            }
        case .bicepsCurl:
            // The more curled arm, so alternating curls are counted too.
            return AdaptiveSignalSpec(direction: -1, fullAmplitude: 0.6, minAmplitude: 0.3) { f in
                f.bilateral({ armBelowShoulder(f, $0) }, combine: min)
            }
        case .shoulderPress:
            return AdaptiveSignalSpec(direction: -1, fullAmplitude: 0.4, minAmplitude: 0.25) { f in
                f.bilateral({ armBelowShoulder(f, $0) })
            }
        case .lateralRaise:
            return AdaptiveSignalSpec(direction: -1, fullAmplitude: 0.7, minAmplitude: 0.35) { f in
                f.bilateral({ armBelowShoulder(f, $0) })
            }
        case .plank:
            return nil
        }
    }
}

/// Body size in the image (≈ torso length), from whichever body parts are visible. Slowly decaying
/// maximum so it stays stable while the torso is foreshortened during a movement.
public struct BodyScale: Sendable {
    public private(set) var value: Double?
    private var lastTime: TimeInterval?
    /// Seconds for a stale maximum to decay by ~63% (the user moved further away).
    public var decay: TimeInterval = 6

    public init() {}

    public static func estimate(_ f: PoseFeatures) -> Double? {
        var candidates: [Double] = []
        if let torso = f.torsoLength { candidates.append(torso) }
        if let l = f.frame.point(.leftShoulder), let r = f.frame.point(.rightShoulder) {
            candidates.append(l.distance(to: r) * 1.5)
        }
        for side in [Side.left, .right] {
            if let s = f.frame.point(.shoulder(side)), let e = f.frame.point(.elbow(side)) {
                candidates.append(s.distance(to: e) * 1.7)
            }
            if let h = f.frame.point(.hip(side)), let k = f.frame.point(.knee(side)) {
                candidates.append(h.distance(to: k) * 1.15)
            }
        }
        return candidates.max().flatMap { $0 > 1e-4 ? $0 : nil }
    }

    public mutating func update(_ f: PoseFeatures, at time: TimeInterval) -> Double? {
        let current = Self.estimate(f)
        if let previous = value, let last = lastTime {
            let decayed = previous * exp(-max(0, time - last) / decay)
            value = max(decayed, current ?? 0)
        } else {
            value = current
        }
        lastTime = time
        return value
    }
}

/// Counts repetitions on a signal without fixed thresholds: the start level is the recent resting
/// extreme, a rep needs at least `minAmplitude × body scale` of travel (and ≈55% of the user's typical
/// travel once a few reps are known, and clearly more than the measured joint jitter), and it is
/// counted when the user comes back to within 30% of the start.
public struct AdaptiveRepCounter: Sendable {
    public let direction: Double
    /// In body-scale units.
    public let minAmplitude: Double
    public var window: TimeInterval = 3
    public var minRepDuration: TimeInterval = 0.3
    /// A turnaround held longer than this abandons the rep (e.g. the user got down into position).
    public var maxTurnHold: TimeInterval = 4
    public var maxRepDuration: TimeInterval = 10
    public var maxSignalGap: TimeInterval = 1
    /// Required travel in multiples of the estimated per-frame jitter.
    public var noiseMultiple = 9.0

    public private(set) var phase: RepPhase = .unknown
    public private(set) var count = 0
    public private(set) var partials = 0
    public private(set) var records: [RepRecord] = []
    /// Travel of each counted rep, in body-scale units.
    public private(set) var excursions: [Double] = []

    private var samples: [(t: TimeInterval, s: Double)] = []
    private var secondDiffs: [Double] = []
    private var smoothed: Double?
    private var previous: Double?
    private var previousDelta: Double?
    private var startLevel = 0.0
    private var extreme = 0.0
    private var repStart: TimeInterval = 0
    private var turnTime: TimeInterval = 0
    private var turnReachedAt: TimeInterval = 0
    private var lastTime: TimeInterval?
    private var scale = 1.0

    public init(direction: Double, minAmplitude: Double) {
        self.direction = direction
        self.minAmplitude = minAmplitude
    }

    /// Robust per-frame jitter (σ) from second differences, which ignore smooth movement.
    public var noise: Double {
        guard secondDiffs.count >= 10 else { return 0 }
        let sorted = secondDiffs.sorted()
        return sorted[sorted.count / 2] / 1.65
    }

    /// Full-repetition travel required now, in image units.
    public var reference: Double {
        var ref = max(minAmplitude * scale, noiseMultiple * noise)
        if !excursions.isEmpty {
            let recent = excursions.suffix(3)
            ref = max(ref, 0.55 * recent.reduce(0, +) / Double(recent.count) * scale)
        }
        return ref
    }

    /// 0 at the start position, 1 at a full repetition.
    public func progress(of value: Double) -> Double {
        let s = direction * value
        let inRep = phase == .away || phase == .turn || phase == .returning
        let base = inRep ? startLevel : (samples.map(\.s).min() ?? s)
        return max(0, min(1, (s - base) / reference))
    }

    public mutating func update(signal: Double?, scale bodyScale: Double?, at time: TimeInterval) -> [RepCounterEvent] {
        guard let value = signal, let bodyScale, bodyScale > 1e-4 else {
            if let last = lastTime, time - last > maxSignalGap {
                phase = .unknown
                samples.removeAll()
                smoothed = nil
                previous = nil
                previousDelta = nil
            }
            return []
        }
        lastTime = time
        scale = bodyScale
        let raw = direction * value
        if let p = previous {
            let delta = raw - p
            if let pd = previousDelta {
                secondDiffs.append(abs(delta - pd))
                if secondDiffs.count > 90 { secondDiffs.removeFirst() }
            }
            previousDelta = delta
        }
        previous = raw
        // Light smoothing on top of the pose smoother (≈ 50 ms at 30 fps).
        let s = smoothed.map { $0 + 0.6 * (raw - $0) } ?? raw
        smoothed = s
        samples.append((time, s))
        samples.removeAll { time - $0.t > window }
        let low = samples.map(\.s).min() ?? s
        let reference = self.reference

        var events: [RepCounterEvent] = []
        switch phase {
        case .unknown, .start:
            phase = .start
            if s - low > 0.3 * reference {
                phase = .away
                startLevel = low
                extreme = s
                repStart = time
            }
        case .away:
            extreme = max(extreme, s)
            if extreme - startLevel >= reference {
                phase = .turn
                turnTime = time
                turnReachedAt = time
            } else if s - startLevel <= 0.15 * reference {
                if extreme - startLevel >= 0.5 * reference {
                    partials += 1
                    events.append(.partialRep(extremeValue: direction * extreme))
                }
                phase = .start
            } else if time - repStart > maxRepDuration {
                phase = .unknown
            }
        case .turn, .returning:
            if s > extreme {
                extreme = s
                turnTime = time
            }
            let travel = extreme - startLevel
            if phase == .turn && s - startLevel < 0.85 * travel { phase = .returning }
            if s - startLevel <= 0.3 * travel {
                let duration = time - repStart
                if duration >= minRepDuration && duration <= maxRepDuration {
                    count += 1
                    excursions.append(travel / scale)
                    let record = RepRecord(index: count, startTime: repStart, turnTime: turnTime, endTime: time,
                                           extremeValue: direction * extreme, formIssues: [])
                    records.append(record)
                    events.append(.repCompleted(record))
                }
                phase = .start
            } else if time - turnReachedAt > maxTurnHold || time - repStart > maxRepDuration {
                // Held far from the start (changed position): this level becomes the new start.
                phase = .start
                samples.removeAll { time - $0.t > 0.5 }
            }
        }
        return events
    }
}
