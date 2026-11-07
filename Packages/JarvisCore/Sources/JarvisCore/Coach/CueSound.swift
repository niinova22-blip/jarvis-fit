import Foundation

/// Short non-verbal sounds that accompany coach cues in a live workout: a rep is heard as a blip
/// even while NOVA is still speaking, and the countdown/"go"/set-done moments get a clear
/// audio signature that works from across the room. Tones are synthesised (no audio assets).
public enum CueSound: String, CaseIterable, Sendable {
    case rep, countdown, go, setComplete, workoutComplete

    /// The sound for a cue, or nil when the cue is speech only.
    public static func sound(for cue: CoachCue) -> CueSound? {
        switch cue {
        case .rep: return .rep
        case .countdown: return .countdown
        case .go: return .go
        case .setComplete: return .setComplete
        case .workoutComplete: return .workoutComplete
        default: return nil
        }
    }

    /// (frequency in Hz, duration in seconds); 0 Hz is a short gap.
    public var notes: [(frequency: Double, duration: Double)] {
        switch self {
        case .rep: return [(1318.5, 0.06)]                                   // E6 blip
        case .countdown: return [(880, 0.09)]                                 // A5 tick
        case .go: return [(1760, 0.22)]                                       // A6, longer
        case .setComplete: return [(1046.5, 0.09), (0, 0.03), (1568, 0.16)]   // C6 → G6
        case .workoutComplete: return [(1046.5, 0.12), (1318.5, 0.12), (1568, 0.12), (2093, 0.32)] // C major arpeggio
        }
    }

    public var duration: Double { notes.reduce(0) { $0 + $1.duration } }

    /// Mono 16-bit PCM. Each note has a 5 ms attack and an exponential decay, so there are no clicks.
    public func samples(sampleRate: Double = 44_100, amplitude: Double = 0.5) -> [Int16] {
        var out: [Int16] = []
        out.reserveCapacity(Int(duration * sampleRate) + 1)
        for note in notes {
            let count = Int(note.duration * sampleRate)
            let attack = max(1, Int(0.005 * sampleRate))
            for i in 0..<count {
                guard note.frequency > 0 else { out.append(0); continue }
                let t = Double(i) / sampleRate
                let env = min(1, Double(i) / Double(attack)) * exp(-4.0 * Double(i) / Double(count))
                // A touch of the octave gives the tone a brighter, less "test signal" timbre.
                let wave = sin(2 * .pi * note.frequency * t) * 0.85 + sin(4 * .pi * note.frequency * t) * 0.15
                out.append(Int16(max(-1, min(1, wave * env * amplitude)) * Double(Int16.max)))
            }
        }
        return out
    }

    /// A complete RIFF/WAVE file (mono, 16-bit) ready for AVAudioPlayer(data:).
    public func wavData(sampleRate: Int = 44_100, amplitude: Double = 0.5) -> Data {
        let pcm = samples(sampleRate: Double(sampleRate), amplitude: amplitude)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(pcm.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        for sample in pcm { append(sample) }
        return data
    }
}
