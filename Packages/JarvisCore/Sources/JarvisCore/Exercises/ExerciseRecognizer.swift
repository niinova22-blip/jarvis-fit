import Foundation

/// Recognises which supported exercise the user is performing from a short window of poses.
///
/// Each exercise's movement signal is evaluated over the window; an exercise scores when the user
/// is in its posture and its signal sweeps a large share of its start→turn range. Rule-based and
/// explainable — no learned model — so results are reproducible and testable.
public struct ExerciseRecognizer: Sendable {
    public var window: TimeInterval = 3.0
    private var frames: [PoseFrame] = []

    public init() {}

    public struct Guess: Equatable, Sendable {
        public var exercise: TrackedExercise
        /// 0...1, share of the exercise's range of motion covered in the window.
        public var score: Double
    }

    public mutating func add(_ frame: PoseFrame) {
        frames.append(frame)
        while let first = frames.first, frame.timestamp - first.timestamp > window { frames.removeFirst() }
    }

    public mutating func reset() { frames.removeAll() }

    /// Scores of all exercises, best first. Empty when there is not enough data.
    public func ranking() -> [Guess] {
        guard frames.count >= 10, let first = frames.first, let last = frames.last,
              last.timestamp - first.timestamp >= window * 0.6 else { return [] }
        let features = frames.map(PoseFeatures.init)
        var guesses: [Guess] = []
        for exercise in TrackedExercise.allCases {
            let score = exercise == .plank ? plankScore(features) : rangeScore(exercise, features)
            guesses.append(Guess(exercise: exercise, score: score))
        }
        return guesses.sorted { $0.score > $1.score }
    }

    /// The recognised exercise when one clearly stands out.
    public func bestGuess(minimumScore: Double = 0.7) -> Guess? {
        let ranked = ranking()
        guard let best = ranked.first, best.score >= minimumScore else { return nil }
        if ranked.count > 1, ranked[1].score > best.score - 0.1 {
            // Ambiguous between related movements (e.g. squat and lunge): prefer the one with more
            // specific evidence only when the gap is clear.
            return nil
        }
        return best
    }

    private func rangeScore(_ exercise: TrackedExercise, _ features: [PoseFeatures]) -> Double {
        // Try both view-specific specs where relevant and keep the better one.
        let views: [CameraView] = exercise == .squat ? [.side, .front] : [exercise.preferredView]
        var best = 0.0
        for view in views {
            let spec = RepExerciseSpec.spec(for: exercise, view: view)
            let values = features.compactMap(spec.signal)
            guard Double(values.count) >= Double(features.count) * 0.6,
                  let low = values.min(), let high = values.max() else { continue }
            let span = abs(spec.config.turnThreshold - spec.config.startThreshold)
            var score = min(1.0, (high - low) / span)
            // Must actually reach near both ends of the movement.
            let startReached = values.contains { abs($0 - spec.config.startThreshold) <= span * 0.6 || isPast(start: $0, spec.config) }
            let turnReached = values.contains { progress($0, spec.config) >= 0.8 }
            if !startReached || !turnReached { score *= 0.5 }
            best = max(best, score)
        }
        return disambiguate(exercise, features, score: best)
    }

    private func isPast(start value: Double, _ config: RepSignalConfig) -> Bool {
        config.turnThreshold < config.startThreshold ? value >= config.startThreshold : value <= config.startThreshold
    }

    private func progress(_ value: Double, _ config: RepSignalConfig) -> Double {
        (value - config.startThreshold) / (config.turnThreshold - config.startThreshold)
    }

    /// Penalises exercises whose distinguishing features are absent.
    private func disambiguate(_ exercise: TrackedExercise, _ features: [PoseFeatures], score: Double) -> Double {
        guard score > 0 else { return 0 }
        switch exercise {
        case .squat, .lunge:
            // Lunge: legs bend asymmetrically and the feet are split front/back.
            let asymmetry = features.compactMap { f -> Double? in
                guard let l = f.kneeAngle(.left), let r = f.kneeAngle(.right) else { return nil }
                return abs(l - r)
            }.max() ?? 0
            let isLunge = asymmetry > 35
            return (exercise == .lunge) == isLunge ? score : score * 0.4
        case .jumpingJack, .lateralRaise, .shoulderPress:
            // Jacks raise straight arms overhead and move the legs; raises stop near shoulder height;
            // presses keep the elbow bent at the start.
            let legMotion = spread(features.compactMap { $0.stanceWidthRatio })
            let maxElevation = features.compactMap { f in f.bilateral({ f.armElevation($0) }) }.max() ?? 0
            switch exercise {
            case .jumpingJack: return legMotion > 0.8 ? score : score * 0.4
            case .lateralRaise: return maxElevation < 125 && legMotion < 0.5 ? score : score * 0.4
            default: return legMotion < 0.5 ? score : score * 0.5
            }
        case .gluteBridge, .crunch:
            // Bridge moves the hip vertically; crunch moves the shoulders.
            let hipMotion = spread(features.compactMap { $0.hipMid?.y })
            let shoulderMotion = spread(features.compactMap { $0.shoulderMid?.y })
            let isBridge = hipMotion > shoulderMotion * 0.8
            return (exercise == .gluteBridge) == isBridge ? score : score * 0.4
        default:
            return score
        }
    }

    private func spread(_ values: [Double]) -> Double {
        guard let low = values.min(), let high = values.max() else { return 0 }
        return high - low
    }

    /// Plank: horizontal, straight body, almost no movement.
    private func plankScore(_ features: [PoseFeatures]) -> Double {
        let inPosture = features.filter { PlankAnalyzer.evaluate($0).inPosture }.count
        let share = Double(inPosture) / Double(features.count)
        let elbowMotion = spread(features.compactMap { f in f.bilateral({ f.elbowAngle($0) }) })
        return elbowMotion < 15 ? share * 0.95 : share * 0.3
    }
}
