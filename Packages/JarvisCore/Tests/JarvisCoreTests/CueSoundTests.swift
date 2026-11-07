import XCTest
@testable import JarvisCore

final class CueSoundTests: XCTestCase {
    func testCueMapping() {
        XCTAssertEqual(CueSound.sound(for: .rep(3)), .rep)
        XCTAssertEqual(CueSound.sound(for: .countdown(2)), .countdown)
        XCTAssertEqual(CueSound.sound(for: .go(.squat, set: 1, totalSets: 3, target: 10)), .go)
        XCTAssertEqual(CueSound.sound(for: .setComplete(reps: 10, set: 1, totalSets: 3, timed: false)), .setComplete)
        XCTAssertEqual(CueSound.sound(for: .workoutComplete(totalReps: 30, minutes: 12, sets: 3)), .workoutComplete)
        XCTAssertNil(CueSound.sound(for: .encouragement))
        XCTAssertNil(CueSound.sound(for: .paused))
    }

    func testRepBlipIsShortSoItNeverDelaysCounting() {
        XCTAssertLessThanOrEqual(CueSound.rep.duration, 0.1)
        for sound in CueSound.allCases { XCTAssertLessThan(sound.duration, 1.0, sound.rawValue) }
    }

    func testSamplesAreClickFreeAndWithinRange() {
        for sound in CueSound.allCases {
            let pcm = sound.samples(sampleRate: 44_100, amplitude: 0.5)
            XCTAssertEqual(pcm.count, sound.notes.reduce(0) { $0 + Int($1.duration * 44_100) })
            XCTAssertEqual(pcm.first, 0, "starts silent (attack ramp)")
            let peak = pcm.map { abs(Int($0)) }.max() ?? 0
            XCTAssertGreaterThan(peak, 5_000)
            XCTAssertLessThanOrEqual(peak, Int(Double(Int16.max) * 0.5) + 1)
            XCTAssertLessThan(abs(Int(pcm.last ?? 0)), 2_000, "\(sound) ends near zero (decay)")
        }
    }

    func testWavHeader() {
        let wav = CueSound.setComplete.wavData(sampleRate: 22_050)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        let samples = CueSound.setComplete.samples(sampleRate: 22_050).count
        XCTAssertEqual(wav.count, 44 + samples * 2)
        let rate = wav[24..<28].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        XCTAssertEqual(rate, 22_050)
    }
}
