import Foundation

/// Compact, versioned recording of a live workout's raw pose stream, used to validate and tune the
/// rep counters with real data. Recordings stay on the device unless the user exports them.
///
/// Frame format: `t` timestamp, `a` aspect ratio, `k` 19 joints in `Joint.allCases` order as
/// `[x, y, confidence]` (confidence 0 = not detected), rounded to 4 decimals.
public struct PoseRecording: Codable, Sendable {
    public struct Frame: Codable, Sendable {
        public var t: Double
        public var a: Double
        public var k: [[Double]]
    }

    /// One set as the app counted it, plus the user's own count when they label it.
    public struct SetMarker: Codable, Sendable, Identifiable {
        public var id: Int { index }
        public var index: Int
        public var exercise: TrackedExercise
        public var view: CameraView
        public var startedAt: Double
        public var endedAt: Double
        /// Reps (or hold seconds) counted by the app.
        public var counted: Int
        /// Ground truth entered by the user afterwards (nil = not labelled).
        public var actual: Int?

        public init(index: Int, exercise: TrackedExercise, view: CameraView, startedAt: Double, endedAt: Double, counted: Int, actual: Int? = nil) {
            self.index = index
            self.exercise = exercise
            self.view = view
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.counted = counted
            self.actual = actual
        }
    }

    public static let currentVersion = 1
    public var version = PoseRecording.currentVersion
    public var id: UUID
    public var createdAt: Date
    public var device: String
    public var appVersion: String
    public var cameraPosition: String
    public var frames: [Frame]
    public var sets: [SetMarker]
    public var notes: String

    public init(id: UUID = UUID(), createdAt: Date = Date(), device: String, appVersion: String, cameraPosition: String,
                frames: [Frame] = [], sets: [SetMarker] = [], notes: String = "") {
        self.id = id
        self.createdAt = createdAt
        self.device = device
        self.appVersion = appVersion
        self.cameraPosition = cameraPosition
        self.frames = frames
        self.sets = sets
        self.notes = notes
    }

    public static func encodeFrame(_ frame: PoseFrame) -> Frame {
        func r(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
        let k = Joint.allCases.map { joint -> [Double] in
            guard let kp = frame.keypoints[joint] else { return [0, 0, 0] }
            return [r(kp.position.x), r(kp.position.y), r(kp.confidence)]
        }
        return Frame(t: r(frame.timestamp), a: r(frame.aspectRatio), k: k)
    }

    public static func decodeFrame(_ frame: Frame) -> PoseFrame {
        var keypoints: [Joint: Keypoint] = [:]
        for (index, joint) in Joint.allCases.enumerated() where index < frame.k.count {
            let v = frame.k[index]
            guard v.count == 3, v[2] > 0 else { continue }
            keypoints[joint] = Keypoint(Point2(v[0], v[1]), confidence: v[2])
        }
        return PoseFrame(timestamp: frame.t, keypoints: keypoints, aspectRatio: frame.a)
    }

    public var poseFrames: [PoseFrame] { frames.map(Self.decodeFrame) }

    public var durationSeconds: Double {
        guard let first = frames.first?.t, let last = frames.last?.t else { return 0 }
        return last - first
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> PoseRecording {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PoseRecording.self, from: data)
    }
}

/// Bounded in-memory recorder (≈ 30 fps × 45 min max) used by the live workout screen.
public struct PoseRecorder: Sendable {
    public private(set) var recording: PoseRecording
    public let maxFrames: Int

    public init(recording: PoseRecording, maxFrames: Int = 30 * 60 * 45) {
        self.recording = recording
        self.maxFrames = maxFrames
    }

    public var isFull: Bool { recording.frames.count >= maxFrames }

    public mutating func add(_ frame: PoseFrame) {
        guard !isFull else { return }
        recording.frames.append(PoseRecording.encodeFrame(frame))
    }

    public mutating func markSets(_ results: [SetResult], views: [Int: CameraView]) {
        recording.sets = results.enumerated().map { index, result in
            PoseRecording.SetMarker(index: index, exercise: result.exercise, view: views[index] ?? result.exercise.preferredView,
                                    startedAt: result.startedAt, endedAt: result.endedAt, counted: result.achieved)
        }
    }
}

/// Re-runs the analysers over a recording and compares with the app's and the user's counts.
public enum ReplayEvaluator {
    public struct SetOutcome: Sendable, Equatable {
        public var index: Int
        public var exercise: TrackedExercise
        public var view: CameraView
        public var replayed: Int
        public var counted: Int
        public var actual: Int?
        /// |replayed − actual| / actual, when labelled.
        public var relativeError: Double? {
            guard let actual, actual > 0 else { return nil }
            return Double(abs(replayed - actual)) / Double(actual)
        }
    }

    /// Runs the current algorithm for every set. `view` overrides the recorded camera view.
    public static func evaluate(_ recording: PoseRecording, lead: Double = 0.5) -> [SetOutcome] {
        let frames = recording.poseFrames
        return recording.sets.map { marker in
            var smoother = PoseSmoother()
            var analyzer = ExerciseAnalyzerFactory.make(marker.exercise, view: marker.view)
            var hold = 0.0
            for frame in frames where frame.timestamp >= marker.startedAt - lead && frame.timestamp <= marker.endedAt {
                let update = analyzer.process(smoother.smooth(frame))
                hold = update.holdSeconds
            }
            let replayed = marker.exercise.isTimed ? Int(hold.rounded()) : analyzer.repCount
            return SetOutcome(index: marker.index, exercise: marker.exercise, view: marker.view, replayed: replayed,
                              counted: marker.counted, actual: marker.actual)
        }
    }

    /// Share of labelled sets whose replayed count is within `tolerance` reps of the truth.
    public static func accuracy(_ outcomes: [SetOutcome], tolerance: Int = 0) -> Double? {
        let labelled = outcomes.filter { $0.actual != nil }
        guard !labelled.isEmpty else { return nil }
        let hits = labelled.filter { abs($0.replayed - ($0.actual ?? 0)) <= tolerance }.count
        return Double(hits) / Double(labelled.count)
    }
}
