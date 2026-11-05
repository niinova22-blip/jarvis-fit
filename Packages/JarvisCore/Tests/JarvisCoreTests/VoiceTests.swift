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

final class OnboardingVoiceTests: XCTestCase {
    let base = UserProfile()

    func apply(_ text: String, _ topic: OnboardingTopic) -> OnboardingVoiceResult {
        OnboardingVoiceParser.apply(text, topic: topic, to: base)
    }

    func testLanguageNameAndCoach() {
        XCTAssertEqual(apply("İngilizce konuşalım", .language).profile.language, .english)
        let r = apply("Adım Mert, disiplinli bir hoca istiyorum", .nameAndCoach)
        XCTAssertEqual(r.profile.name, "Mert")
        XCTAssertEqual(r.profile.personality, .disciplined)
        XCTAssertEqual(apply("Call me Alex, and be calm", .nameAndCoach).profile.name, "Alex")
        XCTAssertEqual(apply("Call me Alex, and be calm", .nameAndCoach).profile.personality, .calm)
    }

    func testGoals() {
        XCTAssertEqual(apply("Yağsız ve belirgin kaslı olmak istiyorum", .goal).profile.goal, .leanDefined)
        XCTAssertEqual(apply("kaslı bir vücut", .goal).profile.goal, .muscular)
        XCTAssertEqual(apply("I want to be strong", .goal).profile.goal, .strong)
        XCTAssertEqual(apply("dengeli ve sağlıklı", .goal).profile.goal, .balanced)
        XCTAssertFalse(apply("bilmiyorum", .goal).understood)
    }

    func testBodyStats() {
        let tr = apply("Otuz iki yaşındayım, boyum bir yetmiş sekiz, kilom seksen iki buçuk", .body).profile
        XCTAssertEqual(tr.age, 32)
        XCTAssertEqual(tr.heightCm, 178)
        XCTAssertEqual(tr.weightKg, 82.5)
        let plain = apply("25 180 75", .body).profile
        XCTAssertEqual(plain.age, 25)
        XCTAssertEqual(plain.heightCm, 180)
        XCTAssertEqual(plain.weightKg, 75)
        let en = apply("I'm 40 years old, 1,72 tall and weigh 68 kg, female", .body).profile
        XCTAssertEqual(en.age, 40)
        XCTAssertEqual(en.heightCm, 172, accuracy: 0.01)
        XCTAssertEqual(en.weightKg, 68)
        XCTAssertEqual(en.sex, .female)
    }

    func testExperienceEquipmentHealthDiet() {
        XCTAssertEqual(apply("iki yıldır düzenli çalışıyorum", .experience).profile.experience, .advanced)
        XCTAssertEqual(apply("about 8 months", .experience).profile.experience, .intermediate)
        XCTAssertEqual(apply("yeni başlıyorum", .experience).profile.experience, .beginner)
        XCTAssertEqual(apply("Dambıl ve barfiks barım var", .equipment).profile.equipment, [.dumbbells, .pullUpBar])
        let none = apply("hiçbir ekipmanım yok", .equipment)
        XCTAssertTrue(none.understood)
        XCTAssertTrue(none.profile.equipment.isEmpty)
        XCTAssertEqual(apply("Dizimde ve belimde sorun var", .health).profile.limitations, [.knee, .lowerBack])
        XCTAssertEqual(apply("hayır yok", .health).profile.limitations, [])
        XCTAssertEqual(apply("vejetaryenim", .diet).profile.diet, .vegetarian)
    }

    func testSchedule() {
        let r = apply("Pazartesi, çarşamba ve cumartesi akşam yedide, 45 dakika", .schedule).profile
        XCTAssertEqual(r.availableDays, [1, 3, 6])
        XCTAssertEqual(r.preferredTrainingMinute, 19 * 60)
        XCTAssertEqual(r.sessionMinutes, 45)
        XCTAssertEqual(apply("hafta içi saat 18.30", .schedule).profile.availableDays, [1, 2, 3, 4, 5])
        XCTAssertEqual(apply("hafta içi saat 18.30", .schedule).profile.preferredTrainingMinute, 18 * 60 + 30)
        XCTAssertEqual(apply("weekends at 9 am for an hour", .schedule).profile.availableDays, [6, 7])
        XCTAssertEqual(apply("weekends at 9 am for an hour", .schedule).profile.preferredTrainingMinute, 9 * 60)
        XCTAssertEqual(apply("weekends at 9 am for an hour", .schedule).profile.sessionMinutes, 60)
        XCTAssertEqual(apply("pazar ve cuma", .schedule).profile.availableDays, [5, 7])
    }

    func testNavigation() {
        XCTAssertTrue(apply("tamam devam", .goal).advance)
        XCTAssertTrue(apply("geri dön", .goal).goBack)
    }
}

final class VoiceSelectionTests: XCTestCase {
    let voices = [
        VoiceCandidate(identifier: "tr.yelda.compact", name: "Yelda", language: "tr-TR", gender: .female, quality: 0),
        VoiceCandidate(identifier: "tr.yelda.enhanced", name: "Yelda", language: "tr-TR", gender: .female, quality: 1),
        VoiceCandidate(identifier: "tr.cem", name: "Cem", language: "tr-TR", gender: .male, quality: 0),
        VoiceCandidate(identifier: "en.ava.premium", name: "Ava", language: "en-US", gender: .female, quality: 2),
        VoiceCandidate(identifier: "en.evan.enhanced", name: "Evan", language: "en-US", gender: .male, quality: 1),
        VoiceCandidate(identifier: "en.bells", name: "Bells", language: "en-US", gender: .unknown, quality: 2, isNovelty: true),
        VoiceCandidate(identifier: "en.me", name: "Me", language: "en-US", gender: .male, quality: 2, isPersonalVoice: true),
    ]

    func testGenderMatchesUser() {
        XCTAssertEqual(VoiceSelector.desiredGender(.matchUser, userSex: .male), .male)
        XCTAssertEqual(VoiceSelector.desiredGender(.matchUser, userSex: .female), .female)
        XCTAssertEqual(VoiceSelector.desiredGender(.matchUser, userSex: .unspecified), .female)
        XCTAssertEqual(VoiceSelector.desiredGender(.male, userSex: .female), .male)
    }

    func testPicksBestVoiceOfWantedGender() {
        XCTAssertEqual(VoiceSelector.best(from: voices, language: .turkish, gender: .female)?.voice.identifier, "tr.yelda.enhanced")
        // Gender beats quality: a compact male voice is preferred over an enhanced female one for a man.
        XCTAssertEqual(VoiceSelector.best(from: voices, language: .turkish, gender: .male)?.voice.identifier, "tr.cem")
        // Novelty and Personal Voice are never auto-selected.
        XCTAssertEqual(VoiceSelector.best(from: voices, language: .english, gender: .male)?.voice.identifier, "en.evan.enhanced")
        XCTAssertEqual(VoiceSelector.best(from: voices, language: .english, gender: .female)?.voice.identifier, "en.ava.premium")
    }

    func testFallsBackAndSuggestsDownload() {
        let onlyFemale = voices.filter { $0.gender != .male }
        let result = VoiceSelector.best(from: onlyFemale, language: .turkish, gender: .male)!
        XCTAssertFalse(result.genderMatched)
        XCTAssertTrue(VoiceSelector.shouldSuggestDownload(result.voice, wanted: .male))
        XCTAssertFalse(VoiceSelector.shouldSuggestDownload(voices[3], wanted: .female))
    }

    func testProsodyPerPersonality() {
        XCTAssertGreaterThan(VoiceProsody.for(.energetic).rateMultiplier, VoiceProsody.for(.calm).rateMultiplier)
        XCTAssertGreaterThan(VoiceProsody.for(.calm).postDelay, VoiceProsody.for(.energetic).postDelay)
    }
}
