import Foundation

/// One Euro filter (Casiez et al., CHI 2012): adaptive low-pass filter that removes jitter at low
/// speeds while keeping latency low during fast movements.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var derivativeCutoff: Double

    private var previousValue: Double?
    private var previousDerivative: Double = 0
    private var previousTime: TimeInterval?

    public init(minCutoff: Double = 1.2, beta: Double = 0.02, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    public mutating func filter(_ value: Double, at time: TimeInterval) -> Double {
        guard let lastValue = previousValue, let lastTime = previousTime, time > lastTime else {
            previousValue = value
            previousTime = time
            return value
        }
        let dt = time - lastTime
        let derivative = (value - lastValue) / dt
        let aD = Self.alpha(cutoff: derivativeCutoff, dt: dt)
        let smoothedDerivative = aD * derivative + (1 - aD) * previousDerivative
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let a = Self.alpha(cutoff: cutoff, dt: dt)
        let result = a * value + (1 - a) * lastValue
        previousValue = result
        previousDerivative = smoothedDerivative
        previousTime = time
        return result
    }

    public mutating func reset() {
        previousValue = nil
        previousTime = nil
        previousDerivative = 0
    }
}

/// Smooths every joint of a pose stream. Joints that drop out keep no stale value for longer than
/// `holdDuration`, so a brief occlusion does not break the angle signals.
public struct PoseSmoother: Sendable {
    private var filtersX: [Joint: OneEuroFilter] = [:]
    private var filtersY: [Joint: OneEuroFilter] = [:]
    private var lastSeen: [Joint: (Keypoint, TimeInterval)] = [:]
    public var holdDuration: TimeInterval = 0.25
    private let minCutoff: Double
    private let beta: Double

    /// `beta` is expressed per normalised-image-unit/second; joints move ~1 unit/s at most.
    public init(minCutoff: Double = 1.5, beta: Double = 4.0) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    public mutating func smooth(_ frame: PoseFrame) -> PoseFrame {
        var output: [Joint: Keypoint] = [:]
        for joint in Joint.allCases {
            if let keypoint = frame.keypoints[joint], keypoint.confidence >= PoseFrame.minimumConfidence {
                var fx = filtersX[joint] ?? OneEuroFilter(minCutoff: minCutoff, beta: beta)
                var fy = filtersY[joint] ?? OneEuroFilter(minCutoff: minCutoff, beta: beta)
                let x = fx.filter(keypoint.position.x, at: frame.timestamp)
                let y = fy.filter(keypoint.position.y, at: frame.timestamp)
                filtersX[joint] = fx
                filtersY[joint] = fy
                let smoothed = Keypoint(Point2(x, y), confidence: keypoint.confidence)
                output[joint] = smoothed
                lastSeen[joint] = (smoothed, frame.timestamp)
            } else if let (held, time) = lastSeen[joint], frame.timestamp - time <= holdDuration {
                // Short dropout: reuse last position with reduced confidence.
                output[joint] = Keypoint(held.position, confidence: max(PoseFrame.minimumConfidence, held.confidence * 0.8))
            } else {
                filtersX[joint]?.reset()
                filtersY[joint]?.reset()
                lastSeen[joint] = nil
                if let keypoint = frame.keypoints[joint] { output[joint] = keypoint }
            }
        }
        return PoseFrame(timestamp: frame.timestamp, keypoints: output, aspectRatio: frame.aspectRatio)
    }

    public mutating func reset() {
        filtersX.removeAll()
        filtersY.removeAll()
        lastSeen.removeAll()
    }
}
