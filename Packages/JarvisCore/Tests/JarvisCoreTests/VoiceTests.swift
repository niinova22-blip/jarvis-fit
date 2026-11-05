import XCTest
@testable import JarvisCore

final class VoiceTests: XCTestCase {
    let parser = IntentParser()

    func testExamplesFromTheBrief() {
        XCTAssertEqual(parser.parse("Jarvis, kaç tekrar kaldı?", inWorkout: true), .query(.repsRemaining))
        XCTAssertEqual(parser.parse("Çok yoruldum.", inWorkout: true), .session(.tired))
        XCTAssertEqual(parser.parse("Yarın hangi kas grubunu çalışacağız?"), .query(.tomorrowWorkout))
        if case .logMeal = parser.parse("Jarvis, kahvaltıda üç yumurta ve iki dilim ekmek yedim.") {} else { XCTFail("meal not detected") }
    }

    func testWorkoutCommandsTurkish() {
        XCTAssertEqual(parser.parse("dur", inWorkout: true), .session(.pause))
        XCTAssertEqual(parser.parse("devam et", inWorkout: true), .session(.resume))
        XCTAssertEqual(parser.parse("bitti", inWorkout: true), .session(.finishSet))
        XCTAssertEqual(parser.parse("bu hareketi atla", inWorkout: true), .session(.skipExercise))
        XCTAssertEqual(parser.parse("30 saniye daha dinlenmek istiyorum", inWorkout: true, resting: true), .session(.extendRest(seconds: 30)))
        XCTAssertEqual(parser.parse("bir dakika daha", inWorkout: true, resting: true), .session(.extendRest(seconds: 60)))
        XCTAssertEqual(parser.parse("hazırım", inWorkout: true, resting: true), .session(.skipRest))
        XCTAssertEqual(parser.parse("antrenmanı bitir", inWorkout: true), .session(.stop))
        XCTAssertEqual(parser.parse("daha kolay olsun", inWorkout: true), .session(.easier))
        XCTAssertEqual(parser.parse("kaç kaldı", inWorkout: true, resting: true), .query(.restRemaining))
        XCTAssertEqual(parser.parse("sıradaki hareket ne", inWorkout: true), .query(.nextExercise))
        XCTAssertEqual(parser.parse("kaçıncı setteyim", inWorkout: true), .query(.currentSet))
    }

    func testWorkoutCommandsEnglish() {
        XCTAssertEqual(parser.parse("Jarvis how many reps left", inWorkout: true), .query(.repsRemaining))
        XCTAssertEqual(parser.parse("pause", inWorkout: true), .session(.pause))
        XCTAssertEqual(parser.parse("let's continue", inWorkout: true), .session(.resume))
        XCTAssertEqual(parser.parse("I'm done", inWorkout: true), .session(.finishSet))
        XCTAssertEqual(parser.parse("skip the rest", inWorkout: true, resting: true), .session(.skipRest))
        XCTAssertEqual(parser.parse("end the workout", inWorkout: true), .session(.stop))
        XCTAssertEqual(parser.parse("I'm so tired", inWorkout: true), .session(.tired))
        XCTAssertEqual(parser.parse("what are we training tomorrow"), .query(.tomorrowWorkout))
        XCTAssertEqual(parser.parse("what's my protein target"), .query(.proteinTarget))
    }

    func testSafetyHasPriority() {
        XCTAssertEqual(parser.parse("göğsüm ağrıyor dur", inWorkout: true), .symptom(.chestPain))
        XCTAssertEqual(parser.parse("başım dönüyor", inWorkout: true), .symptom(.dizziness))
        XCTAssertEqual(parser.parse("I feel dizzy", inWorkout: true), .symptom(.dizziness))
        XCTAssertEqual(parser.parse("I can't breathe", inWorkout: true), .symptom(.breathing))
        XCTAssertEqual(parser.parse("dizim ağrıyor", inWorkout: true), .symptom(.pain))
    }

    func testFreeChatFallsThrough() {
        if case .chat = parser.parse("Bana motivasyon için bir şey söyler misin?") {} else { XCTFail() }
        if case .chat = parser.parse("Should I train when I slept badly?") {} else { XCTFail() }
    }

    func testWakeWord() {
        XCTAssertNil(IntentParser.stripWakeWord("kaç tekrar kaldı", requireWakeWord: true))
        XCTAssertEqual(IntentParser.stripWakeWord("Jarvis kaç tekrar kaldı", requireWakeWord: true), "kac tekrar kaldi")
        XCTAssertEqual(IntentParser.stripWakeWord("hey jarvis, pause", requireWakeWord: true), "hey pause")
    }

    func testNumberWords() {
        XCTAssertEqual(NumberWords.firstNumber(in: "on iki tekrar"), 12)
        XCTAssertEqual(NumberWords.firstNumber(in: "yirmi beş saniye"), 25)
        XCTAssertEqual(NumberWords.firstNumber(in: "iki yüz gram"), 200)
        XCTAssertEqual(NumberWords.firstNumber(in: "twenty five"), 25)
        XCTAssertEqual(NumberWords.firstNumber(in: "1,5 porsiyon"), 1.5)
        XCTAssertEqual(NumberWords.firstNumber(in: "iki buçuk dilim"), 2.5)
        XCTAssertEqual(NumberWords.firstNumber(in: "yarım ekmek"), 0.5)
    }

    func testResponsesAnswerFromData() {
        let profile = UserProfile(name: "Ali", goal: .muscular, availableDays: [1, 3, 5], language: .turkish)
        let plan = WorkoutPlanner().makePlan(for: profile)
        let snapshot = SessionSnapshot(phase: .active, exercise: .pushUp, setNumber: 2, totalSets: 3, reps: 8, target: 12, holdSeconds: 0,
                                       restRemaining: nil, nextExercise: .squat, exerciseIndex: 0, exerciseCount: 4, progress: 0, framing: nil, elapsedSeconds: 300)
        let context = AssistantContext(profile: profile, session: snapshot, plan: plan, todayWeekday: 2)
        XCTAssertEqual(ResponseComposer.answer(.repsRemaining, context: context).tr, "Dört tekrar kaldı.")
        XCTAssertEqual(ResponseComposer.answer(.repsRemaining, context: context).en, "Four reps left.")
        let tomorrow = ResponseComposer.answer(.tomorrowWorkout, context: context).tr
        XCTAssertTrue(tomorrow.hasPrefix("Yarın"), tomorrow)
        XCTAssertTrue(tomorrow.contains("antrenmanın var"), tomorrow)
        // Day 2 → tomorrow is day 3 (a training day).
        XCTAssertFalse(tomorrow.contains("dinlenme"))
    }

    func testPromptContainsSafetyRulesAndContext() {
        let profile = UserProfile(name: "Ayşe", limitations: [.knee], language: .turkish)
        let prompt = PromptBuilder.instructions(context: AssistantContext(profile: profile, todayWeekday: 1,
                                                                          memories: [MemoryItem(kind: .likes, text: "squat seviyorum")]))
        XCTAssertTrue(prompt.contains("teşhis"))
        XCTAssertTrue(prompt.contains("Diz problemi"))
        XCTAssertTrue(prompt.contains("squat seviyorum"))
    }

    func testMemoryExtractionAndMinimisation() {
        XCTAssertEqual(MemoryExtractor.extract(from: "Jarvis en sevdiğim hareket squat")?.kind, .likes)
        XCTAssertEqual(MemoryExtractor.extract(from: "Şınavda çok zorlanıyorum")?.kind, .struggle)
        XCTAssertEqual(MemoryExtractor.extract(from: "I hate burpees")?.kind, .dislikes)
        XCTAssertNil(MemoryExtractor.extract(from: "bugün hava güzel"))
        let item = MemoryExtractor.extract(from: "seviyorum beni 05321234567 numaradan ara ali@example.com")
        XCTAssertFalse(item?.text.contains("0532") ?? true)
        XCTAssertFalse(item?.text.contains("@") ?? true)
    }

    func testBriefingMentionsWorkoutAndProtein() {
        let profile = UserProfile(name: "Ali", goal: .muscular, availableDays: [1, 3, 5], preferredTrainingMinute: 19 * 60, language: .turkish)
        let plan = WorkoutPlanner().makePlan(for: profile)
        let targets = NutritionCalculator.targets(for: profile)
        let context = AssistantContext(profile: profile, plan: plan, todayWeekday: 1, nutrition: NutritionDay(entries: [], targets: targets))
        let text = DailyBriefing.compose(context: context, hour: 8).tr
        XCTAssertTrue(text.hasPrefix("Günaydın Ali."))
        XCTAssertTrue(text.contains("19.00"))
        XCTAssertTrue(text.contains("protein hedefin \(targets.proteinG) gram"))
    }
}
