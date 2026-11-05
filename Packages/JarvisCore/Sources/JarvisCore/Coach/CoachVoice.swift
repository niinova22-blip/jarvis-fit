import Foundation

/// Turns semantic cues into short spoken sentences for the chosen personality and language.
/// All phrases are prepared in advance, so in-workout speech never waits for a language model.
public struct CoachVoice: Sendable {
    public var personality: CoachPersonality
    public var language: AppLanguage
    public var userName: String?
    private var variantCounter = 0

    public init(personality: CoachPersonality, language: AppLanguage, userName: String? = nil) {
        self.personality = personality
        self.language = language
        self.userName = userName
    }

    private func t(_ tr: String, _ en: String) -> String { language == .turkish ? tr : en }

    /// Rotates between variants so repeated cues don't sound robotic.
    private mutating func pick(_ options: [String]) -> String {
        guard !options.isEmpty else { return "" }
        defer { variantCounter &+= 1 }
        return options[variantCounter % options.count]
    }

    private func exerciseName(_ exercise: TrackedExercise) -> String { exercise.name.resolve(language) }

    public mutating func text(for cue: CoachCue) -> String {
        switch cue {
        case .welcome(let count):
            let name = userName.map { language == .turkish ? " \($0)" : " \($0)" } ?? ""
            switch personality {
            case .disciplined: return t("Hazır ol\(name). Bugün \(count) hareket var. Başlıyoruz.", "Ready up\(name). \(count) exercises today. Let's begin.")
            case .friendly: return t("Selam\(name)! Bugün \(count) hareket yapacağız, birlikte halledeceğiz.", "Hey\(name)! We have \(count) exercises today, we'll get through them together.")
            case .energetic: return t("Hadi bakalım\(name)! \(count) hareket, full enerji!", "Let's go\(name)! \(count) exercises, full energy!")
            case .calm: return t("Hoş geldin\(name). Bugün \(count) hareket var. Önce derin bir nefes al.", "Welcome\(name). \(count) exercises today. Take a deep breath first.")
            }
        case .setup(let exercise):
            return t("Sıradaki hareket \(exerciseName(exercise)). ", "Next up: \(exerciseName(exercise)). ") + exercise.setupInstruction.resolve(language)
        case .framing(let status):
            return status.cue.resolve(language)
        case .countdown(let n):
            if n == 3 { return t("Seni görüyorum. Üç", "I see you. Three") }
            return language == .turkish ? (n == 2 ? "İki" : "Bir") : (n == 2 ? "Two" : "One")
        case .go(let exercise, let set, let total, let target):
            let unit = exercise.isTimed ? t("saniye", "seconds") : t("tekrar", "reps")
            switch personality {
            case .energetic: return t("Başla! Set \(set)/\(total), \(target) \(unit)!", "Go! Set \(set) of \(total), \(target) \(unit)!")
            case .calm: return t("Başlayabilirsin. Set \(set), hedef \(target) \(unit). Acele etme.", "You can begin. Set \(set), target \(target) \(unit). No rush.")
            default: return t("Başla. Set \(set) / \(total), \(target) \(unit).", "Go. Set \(set) of \(total), \(target) \(unit).")
            }
        case .rep(let n):
            return "\(n)"
        case .repsRemaining(let n):
            switch personality {
            case .energetic: return t("Son \(n), bas!", "Last \(n), push!")
            case .calm: return t("Son \(n) tekrar.", "\(n) more.")
            default: return t("Son \(n).", "\(n) more.")
            }
        case .holdProgress(let seconds, let target):
            let left = max(0, target - seconds)
            return t("\(seconds) saniye. \(left) saniye kaldı.", "\(seconds) seconds. \(left) to go.")
        case .holdStarted:
            return t("Süre başladı, pozisyonu koru.", "Timer started, hold it.")
        case .holdPaused(let issue):
            let base = t("Süreyi durdurdum.", "Timer paused.")
            return issue.map { base + " " + $0.cue.resolve(language) } ?? base + t(" Pozisyona dön.", " Get back into position.")
        case .formCue(let issue):
            return issue.cue.resolve(language)
        case .partialRep(let issue):
            let base = t("Bu tekrar sayılmadı.", "That one didn't count.")
            return issue.map { base + " " + $0.cue.resolve(language) } ?? base
        case .setComplete(let reps, let set, let total, let timed):
            let what = timed ? t("\(reps) saniye", "\(reps) seconds") : t("\(reps) tekrar", "\(reps) reps")
            switch personality {
            case .disciplined: return t("Set \(set) tamam. \(what).", "Set \(set) done. \(what).")
            case .friendly: return pick([t("Süper! Set \(set) bitti, \(what).", "Nice! Set \(set) done, \(what)."),
                                         t("Çok iyi gidiyorsun. \(what), set \(set) / \(total) tamam.", "You're doing great. \(what), set \(set) of \(total) done.")])
            case .energetic: return pick([t("Bomba! \(what)!", "Boom! \(what)!"), t("İşte bu! Set \(set) tamam!", "That's it! Set \(set) done!")])
            case .calm: return t("Güzel. Set \(set) tamamlandı, \(what). Nefesini düzenle.", "Good. Set \(set) complete, \(what). Steady your breath.")
            }
        case .restStart(let seconds, let next, let isNew):
            let nextText = isNew ? t("Sonra \(exerciseName(next)).", "Then \(exerciseName(next)).") : ""
            return t("\(seconds) saniye dinlen. \(nextText)", "Rest \(seconds) seconds. \(nextText)").trimmingCharacters(in: .whitespaces)
        case .restRemaining(let seconds):
            return t("\(seconds) saniye kaldı, hazırlan.", "\(seconds) seconds left, get ready.")
        case .restExtended(let seconds):
            return t("Tamam, \(seconds) saniye ekledim.", "Okay, I added \(seconds) seconds.")
        case .nextExercise(let exercise):
            return t("Dinlenme bitti. Şimdi \(exerciseName(exercise)).", "Rest is over. Now \(exerciseName(exercise)).")
        case .paused:
            return t("Duraklattım. Hazır olunca devam de.", "Paused. Say continue when you're ready.")
        case .resumed:
            return t("Devam ediyoruz.", "Resuming.")
        case .targetAdjusted(let target, let easier):
            if easier { return t("Hedefi \(target) tekrara indirdim.", "I lowered the target to \(target).") }
            return personality == .energetic ? t("Çok kolay geldi! Hedef \(target)!", "Too easy! Target is now \(target)!")
                                             : t("İyi gidiyorsun, hedefi \(target) yaptım.", "You're doing well, target is now \(target).")
        case .encouragement:
            switch personality {
            case .disciplined: return t("Bitirmeden bırakma. Bitirdiğinde 'bitti' de.", "Don't quit early. Say 'done' when you finish.")
            case .friendly: return t("Zorlandığını biliyorum, harika gidiyorsun. Bitirmek istersen 'bitti' de.", "I know it's tough, you're doing great. Say 'done' if you want to finish.")
            case .energetic: return t("Hadi, sen bunu yaparsın! Biraz daha!", "Come on, you've got this! A bit more!")
            case .calm: return t("Nefesine odaklan. Gerekirse 'bitti' diyerek seti kapatabilirsin.", "Focus on your breath. You can say 'done' to end the set.")
            }
        case .wrongExercise(let detected, let expected):
            return t("Bu \(exerciseName(detected)) gibi görünüyor. Şu an \(exerciseName(expected)) yapıyoruz.",
                     "That looks like \(exerciseName(detected)). We're doing \(exerciseName(expected)) now.")
        case .lostTracking:
            return t("Seni kaybettim, kameranın görüş alanına dön.", "I lost you, step back into view.")
        case .workoutComplete(let reps, let minutes, let sets):
            switch personality {
            case .disciplined: return t("Antrenman tamamlandı. \(sets) set, \(reps) tekrar, \(minutes) dakika.", "Workout complete. \(sets) sets, \(reps) reps, \(minutes) minutes.")
            case .friendly: return t("Tebrikler, bitirdin! \(minutes) dakikada \(reps) tekrar yaptın. Kendinle gurur duy.", "Congrats, you did it! \(reps) reps in \(minutes) minutes. Be proud.")
            case .energetic: return t("Muhteşemdin! \(sets) set, \(reps) tekrar! Yarın daha güçlü!", "Amazing! \(sets) sets, \(reps) reps! Stronger tomorrow!")
            case .calm: return t("Antrenmanı tamamladın. \(reps) tekrar, \(minutes) dakika. Şimdi esneme ve su zamanı.", "You've completed the workout. \(reps) reps, \(minutes) minutes. Time to stretch and hydrate.")
            }
        case .safetyStop(let concern):
            return concern.message.resolve(language)
        case .answer(let text):
            return text.resolve(language)
        case .notUnderstood:
            return t("Anlayamadım, tekrar eder misin?", "Sorry, could you say that again?")
        }
    }
}
