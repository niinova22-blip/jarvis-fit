import Foundation

public enum AssistantQuery: String, Equatable, Sendable {
    case repsRemaining, currentSet, restRemaining, nextExercise, workoutProgress
    case todayWorkout, tomorrowWorkout, lastWorkout
    case proteinTarget, caloriesToday, macrosToday
    case weeklyProgress
}

public enum VoiceIntent: Equatable, Sendable {
    case session(SessionCommand)
    case symptom(SafetyConcern)
    case query(AssistantQuery)
    case logMeal(String)
    case startWorkout
    case repeatLast
    case stopSpeaking
    /// Anything else: answered by the on-device language model (or a fallback reply).
    case chat(String)
}

/// Deterministic Turkish/English command understanding. Used before the language model so that
/// workout commands are instant and never misinterpreted.
public struct IntentParser: Sendable {
    public init() {}

    /// "Nova" is the assistant's name; common recogniser spellings are accepted. The former name
    /// "Jarvis" is still understood so existing users are not locked out.
    public static let wakeWords = ["nova", "nowa", "noova", "nuva", "jarvis", "carvis", "cervis", "jervis", "harvis"]

    /// Removes the wake word; returns nil if `requireWakeWord` and none was present.
    public static func stripWakeWord(_ utterance: String, requireWakeWord: Bool) -> String? {
        let tokens = TextNormalizer.tokens(utterance)
        if let index = tokens.firstIndex(where: { token in wakeWords.contains { token.hasPrefix($0) } }) {
            var rest = tokens
            rest.remove(at: index)
            return rest.joined(separator: " ")
        }
        return requireWakeWord ? nil : tokens.joined(separator: " ")
    }

    private func has(_ text: String, _ phrases: [String]) -> Bool {
        let padded = " " + text + " "
        return phrases.contains { padded.contains(" " + $0 + " ") || (($0.count > 5) && padded.contains($0)) }
    }

    /// `inWorkout`/`resting` disambiguate short commands such as "ready" or "how many left".
    public func parse(_ utterance: String, inWorkout: Bool = false, resting: Bool = false) -> VoiceIntent {
        let text = TextNormalizer.tokens(utterance).joined(separator: " ")
        guard !text.isEmpty else { return .chat("") }

        if let concern = SafetyDetector.detect(text) { return .symptom(concern) }

        // Meal logging ("kahvaltıda üç yumurta yedim", "I ate two bananas").
        if has(text, ["yedim", "ictim", "yemek ekle", "ogun ekle", "i ate", "i had", "i drank", "log meal", "for breakfast", "for lunch", "for dinner"])
            || (has(text, ["kahvaltida", "ogle yemeginde", "aksam yemeginde", "aksam", "ara ogunde"]) && has(text, ["yedim", "ictim", "vardi"])) {
            return .logMeal(utterance)
        }

        if has(text, ["sus", "sessiz ol", "konusma", "be quiet", "shut up", "stop talking", "quiet"]) { return .stopSpeaking }
        if has(text, ["tekrar et", "tekrarla", "ne dedin", "anlamadim", "repeat", "say again", "say that again", "what did you say"]) { return .repeatLast }

        // Queries
        if has(text, ["yarin", "tomorrow"]) && has(text, ["antrenman", "calis", "kas", "program", "ne yap", "workout", "train", "training", "muscle", "muscles", "plan"]) {
            return .query(.tomorrowWorkout)
        }
        if has(text, ["bugun", "today", "todays"]) && has(text, ["antrenman", "program", "ne calis", "workout", "plan", "train", "training"]) {
            return .query(.todayWorkout)
        }
        if has(text, ["son antrenman", "gecen antrenman", "onceki antrenman", "last workout", "previous workout", "last session"]) {
            return .query(.lastWorkout)
        }
        if has(text, ["haftalik", "bu hafta", "gelisim", "ilerleme", "weekly", "this week", "my progress"]) { return .query(.weeklyProgress) }
        if has(text, ["protein"]) { return .query(.proteinTarget) }
        if has(text, ["kalori", "calorie", "calories"]) { return .query(.caloriesToday) }
        if has(text, ["makro", "karbonhidrat", "yag", "macro", "macros", "carbs"]) { return .query(.macrosToday) }

        if has(text, ["kac tekrar", "kac kaldi", "ne kadar kaldi", "kac tane kaldi", "how many left", "how many more", "how many reps", "reps left"]) {
            return .query(resting ? .restRemaining : .repsRemaining)
        }
        if has(text, ["kacinci set", "hangi set", "kacinci setteyim", "which set", "what set"]) { return .query(.currentSet) }
        if has(text, ["dinlenme ne kadar", "kac saniye kaldi", "dinlenme kac", "rest left", "how long rest", "how much rest"]) { return .query(.restRemaining) }
        if has(text, ["sonraki hareket ne", "siradaki ne", "siradaki hareket", "sonra ne", "what's next", "whats next", "what is next", "next exercise is"]) {
            return .query(.nextExercise)
        }

        // Session commands — most specific first.
        if has(text, ["antrenmani bitir", "antrenmani durdur", "antrenmani kapat", "antrenmani iptal", "bugunluk yeter", "stop workout", "stop the workout", "end workout", "end the workout", "finish workout", "cancel workout"]) {
            return .session(.stop)
        }
        if has(text, ["antrenmana basla", "antrenmani baslat", "antrenman baslat", "start workout", "start the workout", "start training", "lets train"]) {
            return .startWorkout
        }
        if has(text, ["dinlenmeyi atla", "dinlenmeyi gec", "skip rest", "skip the rest"]) || (resting && has(text, ["hazirim", "hazir", "basla", "ready", "im ready", "go"])) {
            return .session(.skipRest)
        }
        if has(text, ["biraz daha dinlen", "dinlenmeyi uzat", "sure ekle", "daha fazla dinlen", "more rest", "extend rest", "add time", "longer rest"])
            || (has(text, ["saniye daha", "seconds more", "more seconds", "dakika daha", "minute more"])) {
            var seconds = Int(NumberWords.firstNumber(in: text) ?? 30)
            if has(text, ["dakika", "minute"]) { seconds *= 60 }
            return .session(.extendRest(seconds: max(10, min(seconds, 300))))
        }
        if has(text, ["hareketi atla", "hareketi gec", "bunu atla", "bunu gec", "sonraki harekete gec", "atla", "skip exercise", "skip this", "next exercise", "skip"]) {
            return .session(.skipExercise)
        }
        if has(text, ["yoruldum", "cok yorgunum", "yorgunum", "zorlaniyorum", "gucum kalmadi", "tukendim", "im tired", "i am tired", "tired", "exhausted", "worn out"]) {
            return .session(.tired)
        }
        if has(text, ["daha kolay", "kolaylastir", "hedefi dusur", "azalt", "easier", "fewer reps", "make it easier", "lower the target"]) { return .session(.easier) }
        if has(text, ["daha zor", "zorlastir", "hedefi artir", "arttir", "artir", "harder", "more reps", "make it harder", "increase"]) { return .session(.harder) }
        if has(text, ["bitti", "bitirdim", "set bitti", "seti bitir", "tamamdir", "yeter", "done", "im done", "finished", "that's it", "thats it", "set done"]) {
            return inWorkout ? .session(.finishSet) : .chat(utterance)
        }
        if has(text, ["devam", "devam et", "devam edelim", "kaldigimiz yerden", "resume", "continue", "go on", "keep going", "lets go", "lets continue"]) {
            return .session(.resume)
        }
        if has(text, ["duraklat", "durdur", "dur", "bekle", "mola", "pause", "wait", "hold on", "stop"]) {
            return .session(.pause)
        }
        return .chat(utterance)
    }
}
