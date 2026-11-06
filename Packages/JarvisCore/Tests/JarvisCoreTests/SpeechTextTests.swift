import XCTest
@testable import JarvisCore

final class SpeechTextTests: XCTestCase {
    private func tr(_ text: String) -> String { SpeechText.prepare(text, language: .turkish) }
    private func en(_ text: String) -> String { SpeechText.prepare(text, language: .english) }

    // MARK: Number words

    func testTurkishCardinals() {
        let cases: [(Int, String)] = [
            (0, "sıfır"), (7, "yedi"), (10, "on"), (11, "on bir"), (100, "yüz"), (140, "yüz kırk"),
            (1000, "bin"), (1985, "bin dokuz yüz seksen beş"), (2000, "iki bin"), (2500, "iki bin beş yüz"),
            (21_000, "yirmi bir bin"), (1_000_000, "bir milyon")
        ]
        for (n, words) in cases { XCTAssertEqual(SpeechText.spell(n, language: .turkish), words, "\(n)") }
    }

    func testEnglishCardinals() {
        let cases: [(Int, String)] = [
            (0, "zero"), (13, "thirteen"), (40, "forty"), (140, "one hundred forty"), (1000, "one thousand"),
            (2450, "two thousand four hundred fifty"), (1_000_000, "one million")
        ]
        for (n, words) in cases { XCTAssertEqual(SpeechText.spell(n, language: .english), words, "\(n)") }
    }

    func testTurkishOrdinals() {
        XCTAssertEqual(tr("2. set başlıyor."), "ikinci set başlıyor.")
        XCTAssertEqual(tr("4. tur"), "dördüncü tur")
        XCTAssertEqual(tr("6. set"), "altıncı set")
        XCTAssertEqual(tr("30. gün"), "otuzuncu gün")
        XCTAssertEqual(tr("3. hafta"), "üçüncü hafta")
        // A sentence-final number is not an ordinal.
        XCTAssertEqual(tr("Hedef 12. Hadi!"), "Hedef on iki. Hadi!")
    }

    func testEnglishOrdinals() {
        XCTAssertEqual(en("Your 2nd set."), "Your second set.")
        XCTAssertEqual(en("the 21st day"), "the twenty first day")
        XCTAssertEqual(en("the 40th day"), "the fortieth day")
    }

    // MARK: Units, decimals, signs

    func testTurkishUnitsAndDecimals() {
        XCTAssertEqual(tr("Günlük protein hedefin 140 g."), "Günlük protein hedefin yüz kırk gram.")
        XCTAssertEqual(tr("Bugün yaklaşık 2.450 kcal aldın."), "Bugün yaklaşık iki bin dört yüz elli kalori aldın.")
        XCTAssertEqual(tr("Kilon +1.2 kg değişti."), "Kilon artı bir virgül iki kilo değişti.")
        XCTAssertEqual(tr("Kilon -0.5 kg değişti."), "Kilon eksi yarım kilo değişti.")
        XCTAssertEqual(tr("2,5 litre su"), "iki buçuk litre su")
        XCTAssertEqual(tr("Protein 1.6 g/kg."), "Protein kilo başına bir virgül altı gram.")
        XCTAssertEqual(tr("≈ 80 cm"), "yaklaşık seksen santim")
        XCTAssertEqual(tr("45 sn kaldı"), "kırk beş saniye kaldı")
    }

    func testEnglishUnitsAndDecimals() {
        XCTAssertEqual(en("Your protein target is 140 g."), "Your protein target is one hundred forty grams.")
        XCTAssertEqual(en("1 kg"), "one kilogram")
        XCTAssertEqual(en("about 2,450 kcal"), "about two thousand four hundred fifty calories")
        XCTAssertEqual(en("changed by +1.2 kg"), "changed by plus one point two kilograms")
        XCTAssertEqual(en("1.6 g/kg"), "one point six grams per kilogram")
    }

    func testPercentRangesSetsAndTimes() {
        XCTAssertEqual(tr("%20 daha az"), "yüzde yirmi daha az")
        XCTAssertEqual(en("20% less"), "twenty percent less")
        XCTAssertEqual(tr("60–90 sn dinlen."), "altmış ila doksan saniye dinlen.")
        XCTAssertEqual(en("Rest 60-90 s."), "Rest sixty to ninety seconds.")
        XCTAssertEqual(tr("Bugün 3x12 şınav."), "Bugün üç set on iki tekrar şınav.")
        XCTAssertEqual(en("Do 3×12."), "Do three sets of twelve.")
        XCTAssertEqual(tr("Saat 19:00'da bacak antrenmanın var."), "Saat on dokuzda bacak antrenmanın var.")
        XCTAssertEqual(tr("Saat 07:30"), "Saat yedi otuz")
        XCTAssertEqual(en("at 19:00"), "at seven p.m.")
        XCTAssertEqual(en("at 07:05"), "at seven oh five a.m.")
        XCTAssertEqual(en("at 12:30"), "at twelve thirty p.m.")
        XCTAssertEqual(en("at 00:15"), "at twelve fifteen a.m.")
    }

    func testTurkishSuffixAfterNumber() {
        XCTAssertEqual(tr("3'ü kaldı"), "üçü kaldı")
        XCTAssertEqual(tr("Saat 7'de"), "Saat yedide")
    }

    // MARK: Pronunciation and cleanup

    func testPronunciationLexicon() {
        XCTAssertEqual(tr("Merhaba, ben JARVIS."), "Merhaba, ben Carvis.")
        XCTAssertEqual(tr("Squat ve lunge yapalım."), "Skuat ve lanç yapalım.")
        XCTAssertEqual(tr("Sıradaki hareket: Biceps curl"), "Sıradaki hareket: Bayseps körl")
        XCTAssertEqual(tr("10 squat"), "on skuat")
        XCTAssertEqual(en("Hi, I'm JARVIS."), "Hi, I'm Jarvis.")
        XCTAssertEqual(en("Next: squat"), "Next: squat")
    }

    func testMarkdownEmojiAndLines() {
        XCTAssertEqual(tr("**Harika!** 💪"), "Harika!")
        XCTAssertEqual(tr("- Su iç\n- Erken uyu"), "Su iç. Erken uyu.")
        XCTAssertEqual(en("## Tips\n1. Drink water\n2. Sleep"), "Tips. Drink water. Sleep.")
        XCTAssertEqual(en("Great job 👍🏽!"), "Great job!")
    }

    /// Every spoken assistant answer must reach the synthesizer without digits or unit abbreviations.
    func testAssistantAnswersHaveNoDigitsOrAbbreviations() {
        let profile = UserProfile(name: "Ali", goal: .muscular, availableDays: [1, 3, 5], language: .turkish)
        let plan = WorkoutPlanner().makePlan(for: profile)
        let snapshot = SessionSnapshot(phase: .active, exercise: .squat, setNumber: 2, totalSets: 3, reps: 8, target: 12, holdSeconds: 0,
                                       restRemaining: 45, nextExercise: .bicepsCurl, exerciseIndex: 0, exerciseCount: 4, progress: 0.3,
                                       framing: nil, elapsedSeconds: 300)
        let context = AssistantContext(profile: profile, session: snapshot, plan: plan, todayWeekday: 2)
        let queries: [AssistantQuery] = [.repsRemaining, .currentSet, .restRemaining, .nextExercise, .workoutProgress, .todayWorkout,
                                         .tomorrowWorkout, .lastWorkout, .proteinTarget, .caloriesToday, .macrosToday, .weeklyProgress]
        for query in queries {
            let answer = ResponseComposer.answer(query, context: context)
            for (text, language) in [(answer.tr, AppLanguage.turkish), (answer.en, .english)] {
                let spoken = SpeechText.prepare(text, language: language)
                XCTAssertNil(spoken.rangeOfCharacter(from: .decimalDigits), "\(query): \(spoken)")
                XCTAssertNil(spoken.range(of: #"\b(kcal|kg|g)\b"#, options: .regularExpression), "\(query): \(spoken)")
            }
        }
    }

    func testPlainSentencesAreUnchanged() {
        let sentence = "Harika bir set. Şimdi dinlen."
        XCTAssertEqual(tr(sentence), sentence)
        XCTAssertEqual(en("Keep your back straight, I'm watching."), "Keep your back straight, I'm watching.")
    }
}
