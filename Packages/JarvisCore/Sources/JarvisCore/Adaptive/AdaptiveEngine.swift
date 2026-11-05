import Foundation

public struct WeightEntry: Codable, Hashable, Sendable {
    public var date: Date
    public var kg: Double

    public init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

/// A completed workout as stored in history.
public struct WorkoutLog: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var summary: WorkoutSummary
    public var plannedWorkoutId: String?

    public init(id: UUID = UUID(), date: Date, summary: WorkoutSummary, plannedWorkoutId: String?) {
        self.id = id
        self.date = date
        self.summary = summary
        self.plannedWorkoutId = plannedWorkoutId
    }
}

public enum RecommendationChange: Codable, Hashable, Sendable {
    case calories(deltaKcal: Int)
    case reduceTrainingDays(to: Int)
    case deloadWeek
    case increaseProtein
    case addRestDay
    case reminderTime(minuteOfDay: Int)
    case progression(exerciseId: String, decision: String)
    case rescheduleWorkout(workoutId: String, toWeekday: Int)
}

public struct Recommendation: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: LocalizedText
    /// Why the system suggests this — always shown to the user.
    public var reason: LocalizedText
    public var change: RecommendationChange
}

/// Combines training, nutrition and body data into explainable suggestions. The user accepts or
/// rejects each one; nothing changes silently.
public struct AdaptiveEngine: Sendable {
    public init() {}

    /// Least-squares slope of weight in kg per week.
    public static func weeklyWeightTrend(_ entries: [WeightEntry]) -> Double? {
        guard entries.count >= 4, let first = entries.map(\.date).min(), let last = entries.map(\.date).max(),
              last.timeIntervalSince(first) >= 10 * 86_400 else { return nil }
        let xs = entries.map { $0.date.timeIntervalSince(first) / (7 * 86_400) }
        let ys = entries.map(\.kg)
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - mx) * (y - my)
            den += (x - mx) * (x - mx)
        }
        return den > 0 ? num / den : nil
    }

    static func isoWeekday(_ date: Date) -> Weekday {
        let weekday = Calendar.current.component(.weekday, from: date)
        return (weekday + 5) % 7 + 1
    }

    static let dayNames = (tr: ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"],
                           en: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])

    /// Desired weekly weight change range as a fraction of body weight.
    static func targetRate(_ goal: FitnessGoal) -> ClosedRange<Double> {
        switch goal {
        case .leanDefined: return -0.0075 ... -0.0025
        case .muscular: return 0.001 ... 0.0035
        case .strong: return 0.0 ... 0.003
        case .athletic, .balanced: return -0.0025 ... 0.0025
        }
    }

    public func recommendations(profile: UserProfile, plan: WeeklyPlan, weights: [WeightEntry], workouts: [WorkoutLog],
                                nutritionDays: [(date: Date, totals: Macros)], targets: NutritionTargets,
                                performances: [ExercisePerformance], now: Date = Date()) -> [Recommendation] {
        var result: [Recommendation] = []
        let day = 86_400.0

        // 1. Weight trend vs goal (needs ≥ 10 days of data).
        if let slope = Self.weeklyWeightTrend(weights.filter { now.timeIntervalSince($0.date) <= 28 * day }) {
            let rate = slope / profile.weightKg
            let range = Self.targetRate(profile.goal)
            let pct = String(format: "%.2f", rate * 100)
            if rate > range.upperBound {
                result.append(Recommendation(
                    id: "kcal-down", title: LocalizedText(tr: "Kaloriyi 150 kcal azalt", en: "Lower calories by 150 kcal"),
                    reason: LocalizedText(tr: "Kilon haftada yaklaşık %\(pct) değişiyor; hedefin için bu biraz hızlı yukarı yönlü.",
                                          en: "Your weight is changing about \(pct)% per week, a bit too fast upwards for your goal."),
                    change: .calories(deltaKcal: -150)))
            } else if rate < range.lowerBound {
                result.append(Recommendation(
                    id: "kcal-up", title: LocalizedText(tr: "Kaloriyi 150 kcal artır", en: "Raise calories by 150 kcal"),
                    reason: LocalizedText(tr: "Kilon haftada yaklaşık %\(pct) değişiyor; hedefin için bu fazla düşüş. Kas kaybını önlemek için biraz artıralım.",
                                          en: "Your weight is changing about \(pct)% per week, too fast downwards for your goal. Let's add a little to protect muscle."),
                    change: .calories(deltaKcal: 150)))
            }
        }

        // 2. Adherence over the last 14 days.
        let recentWorkouts = workouts.filter { now.timeIntervalSince($0.date) <= 14 * day }
        let planned = plan.workouts.count * 2
        // Only judged once the current plan has existed for two full weeks.
        if planned >= 4, Double(recentWorkouts.count) < Double(planned) * 0.5, profile.availableDays.count > 2,
           now.timeIntervalSince(plan.createdAt) >= 14 * day {
            let newDays = max(2, profile.availableDays.count - 1)
            result.append(Recommendation(
                id: "fewer-days", title: LocalizedText(tr: "Haftalık gün sayısını \(newDays)'e düşür", en: "Train \(newDays) days a week"),
                reason: LocalizedText(tr: "Son 2 haftada planlanan \(planned) antrenmanın \(recentWorkouts.count) tanesini yaptın. Daha az ama düzenli antrenman daha çok sonuç verir.",
                                      en: "You completed \(recentWorkouts.count) of \(planned) planned workouts in 2 weeks. Fewer but consistent sessions work better."),
                change: .reduceTrainingDays(to: newDays)))
        }

        // 3. Performance: several exercises trending down → deload.
        let ids = Set(performances.map(\.exerciseId))
        var declining = 0
        for id in ids {
            let series = performances.filter { $0.exerciseId == id }.sorted { $0.date < $1.date }.suffix(3).map(\.totalReps)
            if series.count == 3 && series[0] > series[1] && series[1] > series[2] { declining += 1 }
        }
        if declining >= 2 {
            result.append(Recommendation(
                id: "deload", title: LocalizedText(tr: "Bu hafta hafifletilmiş (deload) hafta", en: "Take a deload week"),
                reason: LocalizedText(tr: "\(declining) harekette son 3 antrenmandır tekrar sayın düşüyor. Bu genelde birikmiş yorgunluk işaretidir.",
                                      en: "Reps have dropped for 3 sessions in a row on \(declining) exercises, usually a sign of accumulated fatigue."),
                change: .deloadWeek))
        }

        // 4. Protein intake vs target over logged days of the last week.
        let lastWeek = nutritionDays.filter { now.timeIntervalSince($0.date) <= 7 * day && $0.totals.kcal > 300 }
        if lastWeek.count >= 3 {
            let average = lastWeek.map(\.totals.protein).reduce(0, +) / Double(lastWeek.count)
            if average < Double(targets.proteinG) * 0.8 {
                result.append(Recommendation(
                    id: "protein", title: LocalizedText(tr: "Protein alımını artır", en: "Increase protein intake"),
                    reason: LocalizedText(tr: "Son günlerde ortalama \(Int(average)) g protein aldın, hedefin \(targets.proteinG) g. Her öğüne bir protein kaynağı eklemek yeterli olabilir.",
                                          en: "You averaged \(Int(average)) g protein recently vs a \(targets.proteinG) g target. Adding a protein source to each meal may be enough."),
                    change: .increaseProtein))
            }
        }

        // 5. Too many sessions in the last 7 days → rest.
        let lastSeven = workouts.filter { now.timeIntervalSince($0.date) <= 7 * day }.count
        if lastSeven > plan.workouts.count + 1 {
            result.append(Recommendation(
                id: "rest", title: LocalizedText(tr: "Bir dinlenme günü ekle", en: "Add a rest day"),
                reason: LocalizedText(tr: "Son 7 günde \(lastSeven) antrenman yaptın, planın \(plan.workouts.count). Kaslar dinlenirken gelişir.",
                                      en: "You trained \(lastSeven) times in 7 days vs \(plan.workouts.count) planned. Muscles grow while resting."),
                change: .addRestDay))
        }

        // 6. Habit learning: actual training time differs from the reminder.
        let calendar = Calendar(identifier: .gregorian)
        let minutes = workouts.suffix(8).map { calendar.component(.hour, from: $0.date) * 60 + calendar.component(.minute, from: $0.date) }.sorted()
        if minutes.count >= 4 {
            let median = minutes[minutes.count / 2]
            if abs(median - profile.preferredTrainingMinute) >= 120 {
                let rounded = (median / 30) * 30
                result.append(Recommendation(
                    id: "reminder", title: LocalizedText(tr: "Hatırlatmayı \(rounded / 60):\(String(format: "%02d", rounded % 60))'a al", en: "Move reminder to \(rounded / 60):\(String(format: "%02d", rounded % 60))"),
                    reason: LocalizedText(tr: "Antrenmanlarını genelde bu saatte yapıyorsun.", en: "You usually train around this time."),
                    change: .reminderTime(minuteOfDay: rounded)))
            }
        }

        // 7. Missed workout earlier this week → move it to a free day that respects recovery.
        let today = Self.isoWeekday(now)
        let weekStart = Calendar.current.startOfDay(for: now).addingTimeInterval(-Double(today - 1) * day)
        if let missed = MissedWorkoutDetector.missed(plan: plan, workouts: workouts, today: today, weekStart: weekStart).last {
            var occupied = plan
            occupied.workouts.removeAll { $0.id == missed.id }
            if let target = ScheduleRules.rescheduleDay(for: missed, plan: occupied, today: today) {
                let dayTR = Self.dayNames.tr[target - 1], dayEN = Self.dayNames.en[target - 1]
                result.append(Recommendation(
                    id: "move-\(missed.id)-\(target)",
                    title: LocalizedText(tr: "Kaçırdığın \(missed.title.tr) antrenmanını \(dayTR) gününe taşı",
                                         en: "Move the missed \(missed.title.en) workout to \(dayEN)"),
                    reason: LocalizedText(tr: "Bu antrenmanı kaçırdın. \(dayTR) boş ve aynı kas gruplarını çalıştıran antrenmanlara 48 saatten yakın değil.",
                                          en: "You missed this workout. \(dayEN) is free and keeps 48 h from sessions training the same muscles."),
                    change: .rescheduleWorkout(workoutId: missed.id, toWeekday: target)))
            }
        }
        return result
    }
}
