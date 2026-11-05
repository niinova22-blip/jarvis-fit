import Foundation

/// Weekly progress report (shown on the Progress screen and used for the weekly notification).
public struct WeeklyReport: Equatable, Sendable {
    public var weekStart: Date
    public var workoutsDone: Int
    public var workoutsPlanned: Int
    public var totalReps: Int
    public var previousWeekReps: Int
    public var activeMinutes: Int
    /// Tracked exercises whose best set beat every earlier week.
    public var personalBests: [TrackedExercise]
    public var averageKcal: Int?
    public var averageProteinG: Int?
    public var targetKcal: Int
    public var targetProteinG: Int
    public var weightChangeKg: Double?
    public var streakWeeks: Int

    public var adherence: Double { workoutsPlanned > 0 ? min(1, Double(workoutsDone) / Double(workoutsPlanned)) : 0 }

    /// Builds the report for the week starting at `weekStart` (inclusive, 7 days).
    public static func make(weekStart: Date, plan: WeeklyPlan?, workouts: [WorkoutLog], nutritionDays: [(date: Date, totals: Macros)],
                            targets: NutritionTargets, weights: [WeightEntry], calendar: Calendar = .current) -> WeeklyReport {
        let weekEnd = weekStart.addingTimeInterval(7 * 86_400)
        let previousStart = weekStart.addingTimeInterval(-7 * 86_400)
        let thisWeek = workouts.filter { $0.date >= weekStart && $0.date < weekEnd }
        let lastWeek = workouts.filter { $0.date >= previousStart && $0.date < weekStart }
        let earlier = workouts.filter { $0.date < weekStart }

        var bestBefore: [TrackedExercise: Int] = [:]
        for log in earlier { for set in log.summary.sets { bestBefore[set.exercise] = max(bestBefore[set.exercise] ?? 0, set.achieved) } }
        var bestNow: [TrackedExercise: Int] = [:]
        for log in thisWeek { for set in log.summary.sets { bestNow[set.exercise] = max(bestNow[set.exercise] ?? 0, set.achieved) } }
        var bests: [TrackedExercise] = []
        for (exercise, value) in bestNow {
            if let before = bestBefore[exercise], value > before { bests.append(exercise) }
        }
        bests.sort { $0.rawValue < $1.rawValue }

        let days = nutritionDays.filter { $0.date >= weekStart && $0.date < weekEnd && $0.totals.kcal > 300 }
        let avgKcal = days.isEmpty ? nil : Int(days.map(\.totals.kcal).reduce(0, +) / Double(days.count))
        let avgProtein = days.isEmpty ? nil : Int(days.map(\.totals.protein).reduce(0, +) / Double(days.count))

        let weekWeights = weights.filter { $0.date >= weekStart && $0.date < weekEnd }.sorted { $0.date < $1.date }
        let baseline = weights.filter { $0.date < weekStart }.max { $0.date < $1.date }
        var weightChange: Double?
        if let last = weekWeights.last, let first = baseline ?? (weekWeights.count >= 2 ? weekWeights.first : nil) {
            weightChange = ((last.kg - first.kg) * 10).rounded() / 10
        }

        return WeeklyReport(weekStart: weekStart, workoutsDone: thisWeek.count, workoutsPlanned: plan?.workouts.count ?? 0,
                            totalReps: thisWeek.reduce(0) { $0 + $1.summary.totalReps },
                            previousWeekReps: lastWeek.reduce(0) { $0 + $1.summary.totalReps },
                            activeMinutes: thisWeek.reduce(0) { $0 + $1.summary.durationMinutes },
                            personalBests: bests, averageKcal: avgKcal, averageProteinG: avgProtein,
                            targetKcal: targets.kcal, targetProteinG: targets.proteinG, weightChangeKg: weightChange,
                            streakWeeks: ProgressAnalytics.weekStreak(workouts: workouts, upTo: weekEnd))
    }

    /// Short spoken/written summary.
    public var text: LocalizedText {
        var tr = "Bu hafta \(workoutsDone)/\(max(workoutsPlanned, workoutsDone)) antrenman, toplam \(totalReps) tekrar yaptın."
        var en = "This week you did \(workoutsDone)/\(max(workoutsPlanned, workoutsDone)) workouts and \(totalReps) reps in total."
        if previousWeekReps > 0 {
            let change = Int((Double(totalReps - previousWeekReps) / Double(previousWeekReps) * 100).rounded())
            if change != 0 {
                tr += " Geçen haftaya göre %\(abs(change)) \(change > 0 ? "daha fazla" : "daha az")."
                en += " That's \(abs(change))% \(change > 0 ? "more" : "less") than last week."
            }
        }
        if !personalBests.isEmpty {
            tr += " Yeni rekorların: \(ResponseComposer.list(personalBests.map(\.name.tr), .turkish))."
            en += " New personal bests: \(ResponseComposer.list(personalBests.map(\.name.en), .english))."
        }
        if let p = averageProteinG {
            tr += " Günlük ortalama protein \(p) g (hedef \(targetProteinG) g)."
            en += " Average protein \(p) g a day (target \(targetProteinG) g)."
        }
        if let w = weightChangeKg, w != 0 {
            tr += " Kilon \(String(format: "%+.1f", w)) kg değişti."
            en += " Your weight changed by \(String(format: "%+.1f", w)) kg."
        }
        if streakWeeks >= 2 {
            tr += " \(streakWeeks) haftadır aralıksız antrenman yapıyorsun."
            en += " That's \(streakWeeks) weeks in a row."
        }
        return LocalizedText(tr: tr, en: en)
    }
}

public enum ProgressAnalytics {
    /// Consecutive weeks (ending with the week before `upTo`) with at least one workout.
    public static func weekStreak(workouts: [WorkoutLog], upTo: Date) -> Int {
        guard !workouts.isEmpty else { return 0 }
        var streak = 0
        var end = upTo
        while true {
            let start = end.addingTimeInterval(-7 * 86_400)
            if workouts.contains(where: { $0.date >= start && $0.date < end }) {
                streak += 1
                end = start
            } else {
                return streak
            }
            if streak > 520 { return streak }
        }
    }

    public struct Point: Equatable, Sendable, Identifiable {
        public var id: Date { date }
        public var date: Date
        public var value: Int
    }

    /// Best set per session for one exercise (reps or seconds), oldest first.
    public static func bestSetSeries(_ exerciseId: String, performances: [ExercisePerformance]) -> [Point] {
        performances.filter { $0.exerciseId == exerciseId }
            .sorted { $0.date < $1.date }
            .map { Point(date: $0.date, value: $0.bestSet) }
    }

    /// Exercise ids with at least `minimumSessions` logged sessions, most trained first.
    public static func trackedExerciseIds(_ performances: [ExercisePerformance], minimumSessions: Int = 2) -> [String] {
        let counts = Dictionary(grouping: performances, by: \.exerciseId).mapValues(\.count)
        return counts.filter { $0.value >= minimumSessions }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    /// Relative change between the first and last third of a series (e.g. +0.25 = 25% better).
    public static func trend(_ series: [Point]) -> Double? {
        guard series.count >= 3 else { return nil }
        let third = max(1, series.count / 3)
        let first = series.prefix(third).map(\.value).reduce(0, +)
        let last = series.suffix(third).map(\.value).reduce(0, +)
        guard first > 0 else { return nil }
        return Double(last - first) / Double(first)
    }
}

/// Detects planned workouts that were missed earlier in the current week.
public enum MissedWorkoutDetector {
    /// Workouts scheduled before `today` this week with no logged workout for them (or on that day).
    public static func missed(plan: WeeklyPlan, workouts: [WorkoutLog], today: Weekday, weekStart: Date) -> [PlannedWorkout] {
        let thisWeek = workouts.filter { $0.date >= weekStart }
        let doneIds = Set(thisWeek.compactMap(\.plannedWorkoutId))
        // Free (unplanned) workouts count towards the earliest open slot.
        let planIds = Set(plan.workouts.map(\.id))
        var freeSessions = thisWeek.filter { log in log.plannedWorkoutId.map { !planIds.contains($0) } ?? true }.count
        var result: [PlannedWorkout] = []
        for workout in plan.workouts.sorted(by: { $0.weekday < $1.weekday }) where workout.weekday < today && !doneIds.contains(workout.id) {
            if freeSessions > 0 { freeSessions -= 1; continue }
            result.append(workout)
        }
        return result
    }
}
