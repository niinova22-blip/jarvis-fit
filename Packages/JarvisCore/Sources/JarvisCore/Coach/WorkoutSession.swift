import Foundation

public struct LiveWorkoutItem: Codable, Hashable, Sendable {
    public var exercise: TrackedExercise
    public var sets: Int
    /// Repetitions, or seconds for timed exercises.
    public var target: Int
    public var restSeconds: Int

    public init(exercise: TrackedExercise, sets: Int, target: Int, restSeconds: Int) {
        self.exercise = exercise
        self.sets = max(1, sets)
        self.target = max(1, target)
        self.restSeconds = max(0, restSeconds)
    }
}

public struct LiveWorkoutPlan: Codable, Hashable, Sendable {
    public var title: LocalizedText
    public var items: [LiveWorkoutItem]

    public init(title: LocalizedText, items: [LiveWorkoutItem]) {
        self.title = title
        self.items = items
    }
}

public enum SetEndReason: String, Codable, Sendable {
    case targetReached, userSaidDone, inactivity, skipped, safety, stopped
}

public struct SetResult: Codable, Hashable, Sendable {
    public var exercise: TrackedExercise
    public var setNumber: Int
    public var target: Int
    public var reps: Int
    public var holdSeconds: Double
    public var formIssues: [FormIssue]
    public var partialReps: Int
    public var averageRepDuration: Double?
    /// Ratio of the last reps' duration to the first reps' duration (>1 = slowing down).
    public var slowdown: Double?
    public var startedAt: TimeInterval
    public var endedAt: TimeInterval
    public var endReason: SetEndReason

    public var achieved: Int { exercise.isTimed ? Int(holdSeconds.rounded()) : reps }
}

public struct WorkoutSummary: Codable, Hashable, Sendable {
    public var title: LocalizedText
    public var sets: [SetResult]
    public var startedAt: TimeInterval
    public var endedAt: TimeInterval
    public var completed: Bool
    public var safetyConcern: SafetyConcern?

    public var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
    public var durationMinutes: Int { max(1, Int(((endedAt - startedAt) / 60).rounded())) }
}

public enum SessionCommand: Equatable, Sendable {
    case pause, resume, finishSet, skipExercise, skipRest, extendRest(seconds: Int), stop, tired, easier, harder
    case symptom(SafetyConcern)
}

public enum SessionPhase: Equatable, Sendable {
    case idle
    case positioning
    case countdown(remaining: Int)
    case active
    case resting(until: TimeInterval)
    case paused
    case finished
}

/// Read-only view of the session for UI and voice answers.
public struct SessionSnapshot: Equatable, Sendable {
    public var phase: SessionPhase
    public var exercise: TrackedExercise?
    public var setNumber: Int
    public var totalSets: Int
    public var reps: Int
    public var target: Int
    public var holdSeconds: Double
    public var restRemaining: Int?
    public var nextExercise: TrackedExercise?
    public var exerciseIndex: Int
    public var exerciseCount: Int
    public var progress: Double
    public var framing: FramingStatus?
    public var elapsedSeconds: Int

    public var remaining: Int { max(0, target - (exercise?.isTimed == true ? Int(holdSeconds) : reps)) }
}

/// Hands-free workout state machine: positioning → countdown → active set → rest → … → finished.
///
/// Inputs are pose frames, clock ticks and commands (from voice or UI); outputs are `CoachCue`s.
/// It has no dependency on camera, audio or UI so every transition is unit-testable.
public struct WorkoutSessionEngine {
    public let plan: LiveWorkoutPlan
    public private(set) var phase: SessionPhase = .idle
    public private(set) var itemIndex = 0
    public private(set) var setIndex = 0
    public private(set) var results: [SetResult] = []
    public private(set) var summary: WorkoutSummary?

    /// Target of the current set (adjusted by performance and requests).
    public private(set) var currentTarget = 0
    private var targetOverrides: [Int: Int] = [:]

    private var analyzer: (any ExerciseAnalyzing)?
    private var framingGuide = FramingGuide()
    private var smoother = PoseSmoother()
    private var recognizer = ExerciseRecognizer()
    private var lockedView: CameraView = .unknown

    private var startedAt: TimeInterval = 0
    private var now: TimeInterval = 0
    private var readySince: TimeInterval?
    private var lastFramingStatus: FramingStatus?
    private var lastFramingCueTime: TimeInterval = -100
    private var countdownNext: TimeInterval = 0
    private var setStartedAt: TimeInterval = 0
    private var lastActivityAt: TimeInterval = 0
    private var lastPersonSeenAt: TimeInterval = 0
    private var lostTrackingAnnounced = false
    private var lastFormCueAt: TimeInterval = -100
    private var lastFormIssue: FormIssue?
    private var formIssueCounts: [FormIssue: Int] = [:]
    private var partialReps = 0
    private var lastHoldAnnounce = 0
    private var restAnnouncedTen = false
    private var pausedFrom: SessionPhase?
    private var pausedRestRemaining: TimeInterval?
    private var wrongExerciseAnnounced = false
    private var lastRecognitionCheck: TimeInterval = 0
    private var lastProgress = 0.0
    private var currentReps = 0
    private var currentHold = 0.0
    private var holdPausedSince: TimeInterval?

    /// Seconds without a new rep (after at least one) that end a set automatically.
    public var inactivityTimeout: TimeInterval = 10
    /// Seconds the framing must stay "ready" before the countdown starts.
    public var readyHold: TimeInterval = 1.0
    public var minimumFormCueInterval: TimeInterval = 5

    public init(plan: LiveWorkoutPlan) {
        self.plan = plan
    }

    public var currentItem: LiveWorkoutItem? { plan.items.indices.contains(itemIndex) ? plan.items[itemIndex] : nil }

    // MARK: Lifecycle

    public mutating func start(at time: TimeInterval) -> [CoachCue] {
        guard phase == .idle, let item = currentItem else { return [] }
        now = time
        startedAt = time
        currentTarget = item.target
        phase = .positioning
        readySince = nil
        return [.welcome(exerciseCount: plan.items.count), .setup(item.exercise)]
    }

    // MARK: Frames

    public mutating func process(_ rawFrame: PoseFrame) -> [CoachCue] {
        now = rawFrame.timestamp
        let frame = smoother.smooth(rawFrame)
        guard let item = currentItem else { return [] }
        var cues: [CoachCue] = []

        let personVisible = Joint.allCases.filter { frame.isVisible($0) }.count >= 6
        if personVisible {
            lastPersonSeenAt = now
            lostTrackingAnnounced = false
        }

        switch phase {
        case .positioning:
            let (status, view) = framingGuide.evaluate(frame, for: item.exercise)
            if status == .ready {
                if readySince == nil { readySince = now }
                if let since = readySince, now - since >= readyHold {
                    lockedView = resolvedView(view, for: item.exercise)
                    phase = .countdown(remaining: 3)
                    countdownNext = now + 1
                    lastFramingStatus = nil
                    cues.append(.countdown(3))
                }
            } else {
                readySince = nil
                let changed = status != lastFramingStatus
                if (changed && now - lastFramingCueTime >= 2.5) || now - lastFramingCueTime >= 8 {
                    cues.append(.framing(status))
                    lastFramingCueTime = now
                    lastFramingStatus = status
                }
            }

        case .active:
            guard var analyzer else { break }
            let update = analyzer.process(frame)
            self.analyzer = analyzer
            lastProgress = update.progress
            recognizer.add(frame)
            if update.phase != .start && update.phase != .unknown { lastActivityAt = now }
            cues += handle(update, item: item)
            cues += checkWrongExercise(item: item)

        default:
            break
        }
        return cues
    }

    private func resolvedView(_ detected: CameraView, for exercise: TrackedExercise) -> CameraView {
        detected == .unknown ? exercise.preferredView : detected
    }

    private mutating func handle(_ update: AnalyzerUpdate, item: LiveWorkoutItem) -> [CoachCue] {
        var cues: [CoachCue] = []
        currentReps = update.repCount
        currentHold = update.holdSeconds

        for event in update.events {
            switch event {
            case .repCompleted(let record):
                lastActivityAt = now
                cues.append(.rep(record.index))
                let remaining = currentTarget - record.index
                if remaining == 3 && currentTarget >= 6 { cues.append(.repsRemaining(3)) }
                for issue in record.formIssues { formIssueCounts[issue, default: 0] += 1 }
                if let issue = record.formIssues.first, shouldCue(issue) {
                    cues.append(.formCue(issue))
                    noteFormCue(issue)
                }
            case .partialRep(let issue):
                partialReps += 1
                lastActivityAt = now
                if shouldCue(issue) {
                    cues.append(.partialRep(issue))
                    noteFormCue(issue)
                }
            case .holdStarted:
                holdPausedSince = nil
                cues.append(.holdStarted)
            case .holdPaused(let issue):
                holdPausedSince = now
                if let issue { formIssueCounts[issue, default: 0] += 1 }
                cues.append(.holdPaused(issue))
            case .formIssue(let issue):
                formIssueCounts[issue, default: 0] += 1
                if shouldCue(issue) {
                    cues.append(.formCue(issue))
                    noteFormCue(issue)
                }
            }
        }

        if item.exercise.isTimed {
            let seconds = Int(update.holdSeconds)
            if seconds >= currentTarget {
                cues += completeSet(.targetReached)
            } else if seconds >= lastHoldAnnounce + 10 {
                lastHoldAnnounce = seconds - seconds % 10
                cues.append(.holdProgress(seconds: lastHoldAnnounce, target: currentTarget))
            }
        } else if update.repCount >= currentTarget {
            cues += completeSet(.targetReached)
        }
        return cues
    }

    private func shouldCue(_ issue: FormIssue?) -> Bool {
        let elapsed = now - lastFormCueAt
        if elapsed < minimumFormCueInterval { return false }
        if issue == lastFormIssue && elapsed < 15 { return false }
        return true
    }

    private mutating func noteFormCue(_ issue: FormIssue?) {
        lastFormCueAt = now
        lastFormIssue = issue
    }

    private mutating func checkWrongExercise(item: LiveWorkoutItem) -> [CoachCue] {
        guard !wrongExerciseAnnounced, now - lastRecognitionCheck >= 1, now - setStartedAt > 5 else { return [] }
        lastRecognitionCheck = now
        // Only when the expected exercise isn't being counted.
        guard now - lastRepTime > 6, let guess = recognizer.bestGuess(minimumScore: 0.8),
              guess.exercise != item.exercise else { return [] }
        wrongExerciseAnnounced = true
        return [.wrongExercise(detected: guess.exercise, expected: item.exercise)]
    }

    private var lastRepTime: TimeInterval {
        analyzer?.records.last?.endTime ?? setStartedAt
    }

    // MARK: Clock

    public mutating func tick(_ time: TimeInterval) -> [CoachCue] {
        now = time
        guard let item = currentItem else { return [] }
        var cues: [CoachCue] = []
        switch phase {
        case .countdown(let remaining):
            if now >= countdownNext {
                if remaining > 1 {
                    phase = .countdown(remaining: remaining - 1)
                    countdownNext = now + 1
                    cues.append(.countdown(remaining - 1))
                } else {
                    beginSet(item)
                    cues.append(.go(item.exercise, set: setIndex + 1, totalSets: item.sets, target: currentTarget))
                }
            }
        case .active:
            if now - lastPersonSeenAt > 4 && !lostTrackingAnnounced {
                lostTrackingAnnounced = true
                cues.append(.lostTracking)
            }
            if item.exercise.isTimed {
                if let since = holdPausedSince, now - since > 8, currentHold >= 5 {
                    cues += completeSet(.inactivity)
                }
            } else if currentReps > 0, now - max(lastActivityAt, lastRepTime) > inactivityTimeout {
                cues += completeSet(.inactivity)
            }
        case .resting(let until):
            let remaining = until - now
            if remaining <= 10 && remaining > 9 && !restAnnouncedTen && until - restStartedAt > 20 {
                restAnnouncedTen = true
                cues.append(.restRemaining(seconds: 10))
            }
            if remaining <= 0 { cues += endRest() }
        default:
            break
        }
        return cues
    }

    private var restStartedAt: TimeInterval = 0

    private mutating func beginSet(_ item: LiveWorkoutItem) {
        phase = .active
        analyzer = ExerciseAnalyzerFactory.make(item.exercise, view: lockedView)
        recognizer.reset()
        setStartedAt = now
        lastActivityAt = now
        lastPersonSeenAt = now
        lastHoldAnnounce = 0
        currentReps = 0
        currentHold = 0
        holdPausedSince = nil
        formIssueCounts = [:]
        partialReps = 0
        wrongExerciseAnnounced = false
        lastFormIssue = nil
    }

    // MARK: Set transitions

    private mutating func completeSet(_ reason: SetEndReason) -> [CoachCue] {
        guard let item = currentItem else { return [] }
        let records = analyzer?.records ?? []
        let durations = records.map(\.duration)
        let average = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        var slowdown: Double?
        if durations.count >= 6 {
            let first = durations.prefix(3).reduce(0, +) / 3
            let last = durations.suffix(3).reduce(0, +) / 3
            slowdown = first > 0 ? last / first : nil
        }
        let result = SetResult(exercise: item.exercise, setNumber: setIndex + 1, target: currentTarget,
                               reps: currentReps, holdSeconds: currentHold,
                               formIssues: formIssueCounts.sorted { $0.value > $1.value }.map(\.key),
                               partialReps: partialReps, averageRepDuration: average, slowdown: slowdown,
                               startedAt: setStartedAt, endedAt: now, endReason: reason)
        results.append(result)
        analyzer = nil

        var cues: [CoachCue] = [.setComplete(reps: result.achieved, set: setIndex + 1, totalSets: item.sets, timed: item.exercise.isTimed)]
        if reason == .skipped || reason == .stopped || reason == .safety { cues = [] }

        // Move to the next set or exercise.
        if setIndex + 1 < item.sets {
            setIndex += 1
            let adjusted = SetAdaptation.nextTarget(after: result, planned: item.target)
            if adjusted != currentTarget && reason != .skipped {
                cues.append(.targetAdjusted(newTarget: adjusted, easier: adjusted < currentTarget))
            }
            currentTarget = adjusted
            cues += startRest(seconds: item.restSeconds, next: item.exercise, isNew: false)
        } else if itemIndex + 1 < plan.items.count {
            itemIndex += 1
            setIndex = 0
            let next = plan.items[itemIndex]
            currentTarget = next.target
            cues += startRest(seconds: max(item.restSeconds, 30), next: next.exercise, isNew: true)
        } else {
            cues += finish(completed: true, concern: nil)
        }
        return cues
    }

    private mutating func startRest(seconds: Int, next: TrackedExercise, isNew: Bool) -> [CoachCue] {
        restStartedAt = now
        restAnnouncedTen = false
        phase = .resting(until: now + Double(seconds))
        return [.restStart(seconds: seconds, next: next, nextIsNewExercise: isNew)]
    }

    private mutating func endRest() -> [CoachCue] {
        guard let item = currentItem else { return [] }
        phase = .positioning
        readySince = nil
        lastFramingStatus = nil
        lastFramingCueTime = now
        return setIndex == 0 ? [.nextExercise(item.exercise), .setup(item.exercise)] : []
    }

    private mutating func finish(completed: Bool, concern: SafetyConcern?) -> [CoachCue] {
        phase = .finished
        analyzer = nil
        let summary = WorkoutSummary(title: plan.title, sets: results, startedAt: startedAt, endedAt: now,
                                     completed: completed, safetyConcern: concern)
        self.summary = summary
        if concern != nil { return [] }
        return [.workoutComplete(totalReps: summary.totalReps, minutes: summary.durationMinutes, sets: results.count)]
    }

    // MARK: Commands

    public mutating func handle(_ command: SessionCommand, at time: TimeInterval) -> [CoachCue] {
        now = time
        switch command {
        case .symptom(let concern):
            var cues: [CoachCue] = [.safetyStop(concern)]
            if phase == .active { _ = recordInterruptedSet(.safety) }
            if concern.endsWorkout || phase == .idle {
                cues += finish(completed: false, concern: concern)
            } else if phase != .finished {
                pause()
            }
            return cues

        case .pause:
            guard phase != .paused && phase != .finished && phase != .idle else { return [] }
            pause()
            return [.paused]

        case .resume:
            guard phase == .paused else { return [] }
            switch pausedFrom {
            case .resting?:
                phase = .resting(until: now + (pausedRestRemaining ?? 0))
            default:
                // Re-check framing before continuing a set.
                phase = .positioning
                readySince = nil
            }
            pausedFrom = nil
            return [.resumed]

        case .finishSet:
            guard phase == .active else { return [] }
            return completeSet(.userSaidDone)

        case .skipExercise:
            guard let item = currentItem, phase != .finished, phase != .idle else { return [] }
            if phase == .active { _ = recordInterruptedSet(.skipped) }
            setIndex = item.sets - 1
            if itemIndex + 1 < plan.items.count {
                itemIndex += 1
                setIndex = 0
                currentTarget = plan.items[itemIndex].target
                return endRest()
            }
            return finish(completed: true, concern: nil)

        case .skipRest:
            guard case .resting = phase else { return [] }
            return endRest()

        case .extendRest(let seconds):
            guard case .resting(let until) = phase else { return [] }
            phase = .resting(until: until + Double(seconds))
            restAnnouncedTen = false
            return [.restExtended(seconds: seconds)]

        case .tired:
            switch phase {
            case .resting:
                return handle(.extendRest(seconds: 30), at: time)
            case .active:
                guard let item = currentItem, !item.exercise.isTimed else { return [.encouragement] }
                let reduced = max(currentReps + 2, Int((Double(currentTarget) * 0.8).rounded(.down)))
                if reduced < currentTarget {
                    currentTarget = reduced
                    return [.targetAdjusted(newTarget: reduced, easier: true)]
                }
                return [.encouragement]
            default:
                return [.encouragement]
            }

        case .easier, .harder:
            guard let item = currentItem, phase != .finished else { return [] }
            let factor = command == .easier ? 0.8 : 1.2
            var newTarget = Int((Double(currentTarget) * factor).rounded())
            if newTarget == currentTarget { newTarget += command == .easier ? -1 : 1 }
            newTarget = max(1, newTarget)
            if phase == .active, !item.exercise.isTimed { newTarget = max(newTarget, currentReps + 1) }
            currentTarget = newTarget
            return [.targetAdjusted(newTarget: newTarget, easier: command == .easier)]

        case .stop:
            guard phase != .finished else { return [] }
            if phase == .active { _ = recordInterruptedSet(.stopped) }
            return finish(completed: false, concern: nil)
        }
    }

    private mutating func pause() {
        if case .resting(let until) = phase { pausedRestRemaining = max(0, until - now) }
        if phase == .active { _ = recordInterruptedSet(.stopped); pausedFrom = .positioning } else { pausedFrom = phase }
        phase = .paused
    }

    /// Saves a set that was interrupted (keeps the reps already done, repeats the set on resume).
    private mutating func recordInterruptedSet(_ reason: SetEndReason) -> SetResult? {
        guard let item = currentItem, currentReps > 0 || currentHold > 0 else { analyzer = nil; return nil }
        let result = SetResult(exercise: item.exercise, setNumber: setIndex + 1, target: currentTarget, reps: currentReps,
                               holdSeconds: currentHold, formIssues: Array(formIssueCounts.keys), partialReps: partialReps,
                               averageRepDuration: nil, slowdown: nil, startedAt: setStartedAt, endedAt: now, endReason: reason)
        results.append(result)
        analyzer = nil
        currentReps = 0
        currentHold = 0
        return result
    }

    // MARK: Snapshot

    public var snapshot: SessionSnapshot {
        let item = currentItem
        var restRemaining: Int?
        if case .resting(let until) = phase { restRemaining = max(0, Int((until - now).rounded(.up))) }
        var next: TrackedExercise?
        if let item, setIndex + 1 < item.sets { next = item.exercise }
        else if itemIndex + 1 < plan.items.count { next = plan.items[itemIndex + 1].exercise }
        return SessionSnapshot(phase: phase, exercise: item?.exercise, setNumber: setIndex + 1, totalSets: item?.sets ?? 0,
                               reps: currentReps, target: currentTarget, holdSeconds: currentHold,
                               restRemaining: restRemaining, nextExercise: next, exerciseIndex: itemIndex,
                               exerciseCount: plan.items.count, progress: lastProgress,
                               framing: phase == .positioning ? lastFramingStatus : nil,
                               elapsedSeconds: phase == .idle ? 0 : Int(now - startedAt))
    }
}

/// Between-set target adaptation, based on how the previous set went.
public enum SetAdaptation {
    public static func nextTarget(after result: SetResult, planned: Int) -> Int {
        let target = result.target
        if result.exercise.isTimed {
            if result.endReason == .targetReached { return target }
            return max(10, min(target, Int(result.holdSeconds.rounded())))
        }
        // Ended clearly short: next set aims at what was achieved (never below 75% of the plan).
        if result.endReason != .targetReached && Double(result.reps) < Double(target) * 0.8 {
            return max(Int((Double(planned) * 0.75).rounded()), max(1, result.reps))
        }
        // Strong slowdown in the last reps = near failure: keep or reduce.
        if let slowdown = result.slowdown, slowdown > 1.6 {
            return max(Int((Double(planned) * 0.85).rounded()), target - 2)
        }
        // Reached easily with steady tempo and clean form: add up to 15% (at least one rep).
        if result.endReason == .targetReached, let slowdown = result.slowdown, slowdown < 1.1,
           result.partialReps == 0, result.formIssues.isEmpty {
            return min(Int((Double(planned) * 1.15).rounded(.up)), target + 2)
        }
        return target
    }
}
