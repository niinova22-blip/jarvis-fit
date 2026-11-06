import XCTest
@testable import JarvisCore

final class PhonemizerTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private static let lexicon: [String: String] = {
        let url = repo.appendingPathComponent("JarvisFit/Resources/Voices/en_lexicon.tsv")
        return Phonemizer.loadLexicon((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }()

    /// The voice models were trained on phonemes from tools/voice/phonemes.py; the app must produce
    /// exactly the same phonemes for the same text.
    func testMatchesTrainingPhonemizer() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/phonemes_golden.tsv")
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertGreaterThan(lines.count, 1000)
        XCTAssertGreaterThan(Self.lexicon.count, 100_000)
        var mismatches = 0
        for line in lines {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { continue }
            let got = parts[0] == "tr" ? Phonemizer.turkish(parts[1]) : Phonemizer.english(parts[1], lexicon: Self.lexicon)
            if got != parts[2] {
                mismatches += 1
                if mismatches <= 10 { XCTFail("\(parts[0]) \(parts[1])\n  want \(parts[2])\n  got  \(got)") }
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

    func testTurkishBasics() {
        XCTAssertEqual(Phonemizer.turkish("Günaydın Mert."), "ɡynajdɯn meɾt.")
        XCTAssertEqual(Phonemizer.turkish("Dağ, değil, öğle"), "daː, deil, œːle")
        XCTAssertEqual(Phonemizer.turkish("Carvis'e"), "dʒaɾvise")
    }

    func testEnglishBasics() {
        XCTAssertEqual(Phonemizer.english("Keep going!", lexicon: Self.lexicon), "kˈiːp ɡˈoʊɪŋ!")
        XCTAssertEqual(Phonemizer.english("at seven p.m.", lexicon: Self.lexicon), "ˈæt sˈɛvən ˈpiː ˈɛm")
    }

    func testSentenceSplitting() {
        XCTAssertEqual(SpeechText.sentences("Harika bir set! Şimdi dinlen. Hazır mısın?"),
                       ["Harika bir set!", "Şimdi dinlen.", "Hazır mısın?"])
        XCTAssertEqual(SpeechText.sentences("Your workout is at seven p.m. today. Ready?"),
                       ["Your workout is at seven p.m. today.", "Ready?"])
        XCTAssertEqual(SpeechText.sentences("Saat yedi otuz"), ["Saat yedi otuz"])
        XCTAssertEqual(SpeechText.prepare("iPhone'da işlenir.", language: .turkish), "ayfonda işlenir.")
    }

    func testVoiceConfigParsing() throws {
        let json = #"{"audio":{"sample_rate":22050,"quality":"medium"},"inference":{"noise_scale":0.6,"length_scale":1.1,"noise_w":0.7},"phoneme_id_map":{"_":[0],"^":[1],"$":[2],"a":[14]},"num_symbols":256}"#
        let config = try NeuralVoiceConfig(json: Data(json.utf8))
        XCTAssertEqual(config.sampleRate, 22050)
        XCTAssertEqual(config.phonemeIdMap["a"], 14)
        XCTAssertEqual(config.lengthScale, 1.1)
        XCTAssertEqual(config.lengthScale(rate: 1.1), 1.0, accuracy: 0.001)
        XCTAssertTrue(NeuralVoiceCatalog.shouldUse(enabled: true, wantedGender: .male, manualVoicePicked: false))
        XCTAssertFalse(NeuralVoiceCatalog.shouldUse(enabled: true, wantedGender: .female, manualVoicePicked: false))
        XCTAssertFalse(NeuralVoiceCatalog.shouldUse(enabled: true, wantedGender: .male, manualVoicePicked: true))
    }

    func testPhonemeIdsFollowPiperLayout() {
        let map = ["_": 0, "^": 1, "$": 2, "a": 14, "ː": 122]
        XCTAssertEqual(Phonemizer.phonemeIds("aː", idMap: map), [1, 0, 14, 0, 122, 0, 2])
        XCTAssertEqual(Phonemizer.phonemeIds("a?", idMap: map), [1, 0, 14, 0, 2]) // unknown symbols skipped
    }
}
