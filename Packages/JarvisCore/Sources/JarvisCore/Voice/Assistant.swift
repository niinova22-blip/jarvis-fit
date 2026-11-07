import Foundation

/// Everything NOVA knows about "now" when answering.
public struct AssistantContext: Sendable {
    public var profile: UserProfile
    public var language: AppLanguage { profile.language }
    public var session: SessionSnapshot?
    public var plan: WeeklyPlan?
    public var todayWeekday: Weekday
    public var nutrition: NutritionDay?
    public var lastWorkout: WorkoutLog?
    public var workoutsThisWeek: Int
    public var memories: [MemoryItem]
    public var weeklyReport: WeeklyReport?

    public init(profile: UserProfile, session: SessionSnapshot? = nil, plan: WeeklyPlan? = nil, todayWeekday: Weekday,
                nutrition: NutritionDay? = nil, lastWorkout: WorkoutLog? = nil, workoutsThisWeek: Int = 0, memories: [MemoryItem] = [],
                weeklyReport: WeeklyReport? = nil) {
        self.weeklyReport = weeklyReport
        self.profile = profile
        self.session = session
        self.plan = plan
        self.todayWeekday = todayWeekday
        self.nutrition = nutrition
        self.lastWorkout = lastWorkout
        self.workoutsThisWeek = workoutsThisWeek
        self.memories = memories
    }
}

/// Answers factual questions from app data — deterministic, instant and always correct, unlike a
/// language model. Only open-ended chat goes to the model.
public enum ResponseComposer {
    static func list(_ items: [String], _ language: AppLanguage) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        let joiner = language == .turkish ? " ve " : " and "
        return items.dropLast().joined(separator: ", ") + joiner + items.last!
    }

    static func describe(_ workout: PlannedWorkout, _ language: AppLanguage) -> String {
        let muscles = workout.focus.prefix(3).map { $0.title.resolve(language) }
        return language == .turkish
            ? "\(workout.title.tr): \(list(muscles, language)) çalışacağız, \(workout.exercises.count) hareket"
            : "\(workout.title.en): \(list(muscles, language)), \(workout.exercises.count) exercises"
    }

    public static func answer(_ query: AssistantQuery, context c: AssistantContext) -> LocalizedText {
        func say(_ t: String, _ e: String) -> LocalizedText { LocalizedText(tr: t, en: e) }

        switch query {
        case .repsRemaining:
            guard let s = c.session, let exercise = s.exercise, s.phase == .active else {
                if let s = c.session, case .resting = s.phase, let r = s.restRemaining { return say("Dinlenmenin bitmesine \(r) saniye var.", "\(r) seconds of rest left.") }
                return say("Şu an aktif bir set yok.", "There's no active set right now.")
            }
            if exercise.isTimed { return say("\(s.remaining) saniye kaldı.", "\(s.remaining) seconds left.") }
            let n = s.remaining
            if n == 0 { return say("Hedefe ulaştın!", "You've hit the target!") }
            return say("\(numberWord(n, .turkish).capitalizedFirst) tekrar kaldı.", "\(numberWord(n, .english).capitalizedFirst) reps left.")
        case .currentSet:
            guard let s = c.session, let e = s.exercise else { return say("Şu an antrenmanda değiliz.", "We're not in a workout right now.") }
            return say("\(e.name.tr), \(s.setNumber). set, toplam \(s.totalSets) set.", "\(e.name.en), set \(s.setNumber) of \(s.totalSets).")
        case .restRemaining:
            guard let r = c.session?.restRemaining else { return say("Şu an dinlenmiyoruz.", "We're not resting right now.") }
            return say("\(r) saniye dinlenme kaldı.", "\(r) seconds of rest left.")
        case .nextExercise:
            guard let next = c.session?.nextExercise else { return say("Bu son hareketti.", "That was the last exercise.") }
            return say("Sırada \(next.name.tr) var.", "Next is \(next.name.en).")
        case .workoutProgress:
            guard let s = c.session else { return say("Şu an antrenmanda değiliz.", "We're not in a workout right now.") }
            return say("\(s.exerciseCount) hareketin \(s.exerciseIndex + 1). hareketindesin.", "You're on exercise \(s.exerciseIndex + 1) of \(s.exerciseCount).")
        case .todayWorkout:
            guard let w = c.plan?.workout(on: c.todayWeekday) else {
                return say("Bugün dinlenme günün. Hafif bir yürüyüş iyi gelir.", "Today is a rest day. A light walk would be good.")
            }
            let time = timeString(c.profile.preferredTrainingMinute)
            return say("Bugün saat \(time)'da " + describe(w, .turkish) + ".", "Today at \(time): " + describe(w, .english) + ".")
        case .tomorrowWorkout:
            let tomorrow = c.todayWeekday % 7 + 1
            guard let w = c.plan?.workout(on: tomorrow) else {
                return say("Yarın dinlenme günün.", "Tomorrow is a rest day.")
            }
            let muscles = w.focus.prefix(3)
            return say("Yarın \(list(muscles.map { $0.title.tr }, .turkish)) antrenmanın var.",
                       "Tomorrow you have \(list(muscles.map { $0.title.en }, .english)) training.")
        case .lastWorkout:
            guard let last = c.lastWorkout else { return say("Henüz kayıtlı bir antrenmanın yok.", "You don't have a logged workout yet.") }
            let s = last.summary
            let best = s.sets.max { $0.achieved < $1.achieved }
            var t = "Son antrenmanında \(s.sets.count) set ve toplam \(s.totalReps) tekrar yaptın."
            var e = "In your last workout you did \(s.sets.count) sets and \(s.totalReps) reps in total."
            if let best, !best.exercise.isTimed {
                t += " En iyi setin \(best.reps) \(best.exercise.name.tr)."
                e += " Your best set was \(best.reps) \(best.exercise.name.en)."
            }
            return say(t, e)
        case .proteinTarget:
            guard let n = c.nutrition else { return say("Beslenme hedeflerin henüz oluşturulmadı.", "Your nutrition targets aren't set yet.") }
            let eaten = Int(n.totals.protein.rounded())
            return say("Günlük protein hedefin \(n.targets.proteinG) gram. Bugün yaklaşık \(eaten) gram aldın.",
                       "Your daily protein target is \(n.targets.proteinG) g. You've had about \(eaten) g today.")
        case .caloriesToday:
            guard let n = c.nutrition else { return say("Bugün henüz yemek kaydı yok.", "No meals logged today yet.") }
            let eaten = Int(n.totals.kcal.rounded())
            let remaining = n.remainingKcal
            return say("Bugün yaklaşık \(eaten) kalori aldın. Hedefine \(max(0, remaining)) kalori var.",
                       "You've had about \(eaten) kcal today, \(max(0, remaining)) left to your target.")
        case .macrosToday:
            guard let n = c.nutrition else { return say("Bugün henüz yemek kaydı yok.", "No meals logged today yet.") }
            let t = n.totals
            return say("Bugün yaklaşık \(Int(t.protein)) g protein, \(Int(t.carbs)) g karbonhidrat ve \(Int(t.fat)) g yağ aldın.",
                       "Today: about \(Int(t.protein)) g protein, \(Int(t.carbs)) g carbs and \(Int(t.fat)) g fat.")
        case .weeklyProgress:
            if let report = c.weeklyReport { return report.text }
            let planned = c.plan?.workouts.count ?? 0
            return say("Bu hafta \(planned) antrenmanın \(c.workoutsThisWeek) tanesini tamamladın.",
                       "This week you've completed \(c.workoutsThisWeek) of \(planned) workouts.")
        }
    }

    public static func timeString(_ minuteOfDay: Int) -> String {
        String(format: "%02d.%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    /// Small numbers as words so the synthesiser reads them naturally.
    public static func numberWord(_ n: Int, _ language: AppLanguage) -> String {
        let tr = ["sıfır", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz", "on"]
        let en = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        guard n >= 0 && n <= 10 else { return "\(n)" }
        return language == .turkish ? tr[n] : en[n]
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Builds the daily briefing shown and spoken when the app opens.
public enum DailyBriefing {
    public static func compose(context c: AssistantContext, hour: Int, lastPerformance: ExercisePerformance? = nil) -> LocalizedText {
        let greetingTR = hour < 12 ? "Günaydın" : hour < 18 ? "İyi günler" : "İyi akşamlar"
        let greetingEN = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let name = c.profile.name.isEmpty ? "" : " \(c.profile.name)"
        var tr = "\(greetingTR)\(name)."
        var en = "\(greetingEN)\(name)."

        if let w = c.plan?.workout(on: c.todayWeekday) {
            let time = ResponseComposer.timeString(c.profile.preferredTrainingMinute)
            let musclesTR = ResponseComposer.list(w.focus.prefix(2).map { $0.title.tr }, .turkish)
            let musclesEN = ResponseComposer.list(w.focus.prefix(2).map { $0.title.en }, .english)
            tr += " Bugün saat \(time)'da \(musclesTR) antrenmanın var."
            en += " Today at \(time) you have \(musclesEN) training."
            if let perf = lastPerformance, let def = ExerciseLibrary.definition(perf.exerciseId),
               let planned = w.exercises.first(where: { $0.exerciseId == perf.exerciseId }) {
                tr += " Son antrenmanda en iyi setin \(perf.bestSet) \(def.name.tr) oldu. Bugün \(planned.prescription.targetReps) tekrar hedefliyoruz."
                en += " Last time your best set was \(perf.bestSet) \(def.name.en). Today we're aiming for \(planned.prescription.targetReps)."
            }
        } else {
            tr += " Bugün dinlenme günün; toparlanmaya odaklan."
            en += " Today is a rest day; focus on recovery."
        }
        if let n = c.nutrition {
            tr += " Günlük protein hedefin \(n.targets.proteinG) gram, kalori hedefin \(n.targets.kcal)."
            en += " Your protein target is \(n.targets.proteinG) g and calories \(n.targets.kcal)."
        }
        return LocalizedText(tr: tr, en: en)
    }
}

/// Builds instructions for the on-device language model.
public enum PromptBuilder {
    public static func instructions(context c: AssistantContext) -> String {
        let p = c.profile
        let tr = c.language == .turkish
        var lines: [String] = []
        lines.append(tr
            ? "Sen NOVA'sın: kullanıcının cihazında çalışan kişisel spor mentorusun. Her zaman Türkçe, kısa ve doğal konuş (en fazla 3 cümle)."
            : "You are NOVA, a personal fitness mentor running on the user's device. Always answer in English, short and natural (max 3 sentences).")
        lines.append(personalityLine(p.personality, tr: tr))
        lines.append(tr
            ? "Kurallar: Tıbbi teşhis koyma, ilaç veya tedavi önerme. Ağrı, baş dönmesi, göğüs ağrısı gibi belirtilerde antrenmanı bırakmasını ve bir sağlık profesyoneline başvurmasını söyle. Bilmediğin bir şeyi uydurma. Kalori ve ölçüm değerlerini kesin değil tahmini olarak belirt."
            : "Rules: Never diagnose or recommend medication or treatment. For pain, dizziness, chest pain or similar symptoms tell the user to stop and contact a health professional. Don't make things up. Present calories and measurements as estimates.")
        lines.append(tr ? "Kullanıcı bilgileri:" : "User facts:")
        if !p.name.isEmpty { lines.append("- \(tr ? "İsim" : "Name"): \(p.name)") }
        lines.append("- \(tr ? "Hedef" : "Goal"): \(p.goal.title.resolve(c.language)); \(tr ? "seviye" : "level"): \(p.experience.title.resolve(c.language))")
        lines.append("- \(tr ? "Yaş/boy/kilo" : "Age/height/weight"): \(p.age), \(Int(p.heightCm)) cm, \(Int(p.weightKg)) kg")
        if !p.limitations.isEmpty {
            lines.append("- \(tr ? "Sağlık kısıtları" : "Health limitations"): \(p.limitations.map { $0.title.resolve(c.language) }.sorted().joined(separator: ", "))")
        }
        lines.append("- \(tr ? "Beslenme" : "Diet"): \(p.diet.title.resolve(c.language))")
        if let w = c.plan?.workout(on: c.todayWeekday) {
            lines.append("- \(tr ? "Bugünkü antrenman" : "Today's workout"): \(ResponseComposer.describe(w, c.language))")
        }
        if let n = c.nutrition {
            lines.append("- \(tr ? "Bugün beslenme" : "Nutrition today"): \(Int(n.totals.kcal))/\(n.targets.kcal) kcal, \(Int(n.totals.protein))/\(n.targets.proteinG) g protein")
        }
        if let s = c.session, let e = s.exercise {
            lines.append("- \(tr ? "Şu an antrenmanda" : "Currently training"): \(e.name.resolve(c.language)), set \(s.setNumber)/\(s.totalSets), \(s.reps)/\(s.target)")
        }
        let memories = c.memories.suffix(12)
        if !memories.isEmpty {
            lines.append(tr ? "Hatırladıkların:" : "Things you remember:")
            for m in memories { lines.append("- [\(m.kind.title.resolve(c.language))] \(m.text)") }
        }
        return lines.joined(separator: "\n")
    }

    static func personalityLine(_ personality: CoachPersonality, tr: Bool) -> String {
        switch personality {
        case .disciplined: return tr ? "Üslubun: disiplinli, net ve kararlı bir antrenör." : "Style: a disciplined, clear and firm coach."
        case .friendly: return tr ? "Üslubun: sıcak, samimi ve destekleyici bir arkadaş." : "Style: a warm, friendly and supportive buddy."
        case .energetic: return tr ? "Üslubun: enerjik, coşkulu ve motive edici." : "Style: energetic, upbeat and motivating."
        case .calm: return tr ? "Üslubun: sakin, dingin ve nefes odaklı." : "Style: calm, composed and breath-focused."
        }
    }

    /// Reply used when no on-device model is available.
    public static func fallbackReply(_ language: AppLanguage) -> LocalizedText {
        LocalizedText(tr: "Bu cihazda serbest sohbet modeli şu an kullanılamıyor. Antrenman, beslenme ve programınla ilgili komutları yine de anlayabilirim; örneğin 'yarın ne çalışacağız' diyebilirsin.",
                      en: "The free-chat model isn't available on this device right now. I can still handle workout, nutrition and plan commands — try 'what are we training tomorrow'.")
    }
}
