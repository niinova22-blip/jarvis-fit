import Foundation

/// Short motivation lines in the coach's personality. Deterministic per day so the message is
/// stable during the day; data-driven lines (streaks, records) take priority over generic ones.
public enum Motivation {
    public static func message(personality: CoachPersonality, dayIndex: Int, streakWeeks: Int = 0,
                               recentPersonalBest: TrackedExercise? = nil, workoutsThisWeek: Int = 0) -> LocalizedText {
        if let best = recentPersonalBest {
            return LocalizedText(tr: "\(best.name.tr) rekorunu geçen sefer kırdın. Bugün aynı enerjiyle devam.",
                                 en: "You set a \(best.name.en) record last time. Bring the same energy today.")
        }
        if streakWeeks >= 3 {
            return LocalizedText(tr: "\(streakWeeks) haftadır aralıksız çalışıyorsun. Bu seriyi bozmayalım.",
                                 en: "\(streakWeeks) weeks in a row. Let's keep the streak alive.")
        }
        let lines = generic[personality] ?? []
        guard !lines.isEmpty else { return LocalizedText(tr: "", en: "") }
        return lines[((dayIndex % lines.count) + lines.count) % lines.count]
    }

    static let generic: [CoachPersonality: [LocalizedText]] = [
        .disciplined: [
            LocalizedText(tr: "Motivasyon gelir gider, disiplin kalır. Plan belli, uygula.", en: "Motivation comes and goes; discipline stays. The plan is set, execute it."),
            LocalizedText(tr: "Bugünkü set, yarınki güçtür. Bahane yok.", en: "Today's sets are tomorrow's strength. No excuses."),
            LocalizedText(tr: "Küçük ama düzenli adımlar. Bugün de bir adım.", en: "Small, consistent steps. Today is one more."),
        ],
        .friendly: [
            LocalizedText(tr: "Bugün kendine iyi bak; birlikte güzel bir antrenman yapacağız.", en: "Take care of yourself today; we'll have a good session together."),
            LocalizedText(tr: "Her antrenman bir öncekinden biraz daha iyi. Seninle gurur duyuyorum.", en: "Every session is a little better than the last. I'm proud of you."),
            LocalizedText(tr: "Mükemmel olmak zorunda değil, sadece başla.", en: "It doesn't have to be perfect, just start."),
        ],
        .energetic: [
            LocalizedText(tr: "Bugün enerjini sahaya dökme günü! Hadi bakalım!", en: "Today we bring the energy! Let's go!"),
            LocalizedText(tr: "Her tekrar seni hedefine yaklaştırıyor. Gaza bas!", en: "Every rep gets you closer. Full throttle!"),
            LocalizedText(tr: "Bugün rekor günü olabilir, hazır mısın?", en: "Today could be a record day. Ready?"),
        ],
        .calm: [
            LocalizedText(tr: "Nefesine odaklan, acele yok. Kaliteli hareket her şeydir.", en: "Focus on your breath, no rush. Quality movement is everything."),
            LocalizedText(tr: "Bedenini dinle; istikrar, yoğunluktan değerlidir.", en: "Listen to your body; consistency beats intensity."),
            LocalizedText(tr: "Sakin ve kontrollü. Her tekrar bilinçli olsun.", en: "Calm and controlled. Make every rep mindful."),
        ],
    ]
}
