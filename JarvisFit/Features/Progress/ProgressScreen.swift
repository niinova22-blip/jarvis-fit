import SwiftUI
import Charts
import JarvisCore

struct ProgressScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var showFitCheck = false
    @State private var showPaywall = false
    @State private var newWeight: Double = 0
    @State private var selectedExercise: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.isPremium {
                        weekReportCard
                    } else {
                        premiumTeaser
                    }
                    weightCard
                    volumeCard
                    if model.isPremium { exerciseProgressCard }
                    bestsCard
                    fitCheckCard
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(model.t("Gelişim", "Progress"))
            .sheet(isPresented: $showFitCheck) { FitCheckView() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onAppear { if newWeight == 0 { newWeight = model.data.weights.last?.kg ?? model.profile?.weightKg ?? 75 } }
        }
    }

    private var weightCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: model.t("Kilo", "Weight"))
                if model.data.weights.count >= 2 {
                    Chart(model.data.weights, id: \.date) { entry in
                        LineMark(x: .value("Date", entry.date), y: .value("kg", entry.kg))
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Date", entry.date), y: .value("kg", entry.kg))
                            .foregroundStyle(Theme.accent)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                }
                if let trend = AdaptiveEngine.weeklyWeightTrend(model.data.weights) {
                    Text(model.t("Eğilim: haftada \(String(format: "%+.2f", trend)) kg", "Trend: \(String(format: "%+.2f", trend)) kg per week"))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                HStack {
                    Stepper(value: $newWeight, in: 35...250, step: 0.1) {
                        Text(String(format: "%.1f kg", newWeight)).font(Theme.headline).foregroundStyle(.white)
                    }
                    Button(model.t("Kaydet", "Log")) { model.addWeight(newWeight) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private struct WeekVolume: Identifiable {
        var id: Date { week }
        var week: Date
        var reps: Int
    }

    private var weeklyVolume: [WeekVolume] {
        let grouped = Dictionary(grouping: model.data.workoutLogs) { $0.date.startOfWeek }
        return grouped.map { WeekVolume(week: $0.key, reps: $0.value.reduce(0) { $0 + $1.summary.totalReps }) }
            .sorted { $0.week < $1.week }
            .suffix(12)
    }

    private var volumeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: model.t("Haftalık toplam tekrar", "Weekly total reps"))
                if weeklyVolume.isEmpty {
                    Text(model.t("İlk canlı antrenmanından sonra burada grafik göreceksin.", "Your chart appears after the first live workout."))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                } else {
                    Chart(weeklyVolume) { item in
                        BarMark(x: .value("Week", item.week, unit: .weekOfYear), y: .value("Reps", item.reps))
                            .foregroundStyle(Theme.accent.gradient)
                    }
                    .frame(height: 160)
                }
                Text(model.t("Toplam \(model.data.workoutLogs.count) antrenman", "\(model.data.workoutLogs.count) workouts in total"))
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var premiumTeaser: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionTitle(text: model.t("Gelişim raporları", "Progress reports"))
                    Spacer()
                    Text("PREMIUM").font(Theme.caption).foregroundStyle(Theme.warning)
                }
                Text(model.t("Haftalık rapor, hareket bazlı gelişim grafikleri, rekorlar ve adaptif öneriler Premium'da.",
                             "Weekly reports, per-exercise progress charts, records and adaptive suggestions are in Premium."))
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                Button(model.t("Premium'u incele", "See Premium")) { showPaywall = true }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder private var weekReportCard: some View {
        if let report = model.weeklyReport(weekStart: Date().startOfWeek) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: model.t("Bu haftanın raporu", "This week's report"))
                    HStack(spacing: 18) {
                        stat("\(report.workoutsDone)/\(max(report.workoutsPlanned, report.workoutsDone))", model.t("antrenman", "workouts"))
                        stat("\(report.totalReps)", model.t("tekrar", "reps"))
                        stat("\(report.activeMinutes)", model.t("dakika", "minutes"))
                        stat("\(report.streakWeeks)", model.t("hafta seri", "week streak"))
                    }
                    Text(model.t(report.text)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.headline).foregroundStyle(Theme.accent)
            Text(label).font(Theme.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder private var exerciseProgressCard: some View {
        let ids = ProgressAnalytics.trackedExerciseIds(model.data.performances)
        if !ids.isEmpty {
            let current = selectedExercise.flatMap { ids.contains($0) ? $0 : nil } ?? ids[0]
            let series = ProgressAnalytics.bestSetSeries(current, performances: model.data.performances)
            let definition = ExerciseLibrary.definition(current)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionTitle(text: model.t("Hareket gelişimi", "Exercise progress"))
                        Spacer()
                        Menu {
                            ForEach(ids, id: \.self) { id in
                                Button(ExerciseLibrary.definition(id).map { model.t($0.name) } ?? id) { selectedExercise = id }
                            }
                        } label: {
                            Label(definition.map { model.t($0.name) } ?? current, systemImage: "chevron.down").font(Theme.caption)
                        }
                    }
                    Chart(series) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Best", point.value))
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Date", point.date), y: .value("Best", point.value))
                            .foregroundStyle(Theme.accent)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 150)
                    if let trend = ProgressAnalytics.trend(series) {
                        let pct = Int((trend * 100).rounded())
                        Text(model.t("En iyi set: ilk dönemlere göre %\(pct > 0 ? "+" : "")\(pct)", "Best set vs early sessions: \(pct > 0 ? "+" : "")\(pct)%"))
                            .font(Theme.caption).foregroundStyle(pct >= 0 ? Theme.success : Theme.warning)
                    }
                    Text(definition?.isTimed == true ? model.t("Değer: en uzun tutuş (sn)", "Value: longest hold (s)") : model.t("Değer: setteki en yüksek tekrar", "Value: most reps in a set"))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var bests: [(TrackedExercise, Int)] {
        var best: [TrackedExercise: Int] = [:]
        for log in model.data.workoutLogs { for set in log.summary.sets { best[set.exercise] = max(best[set.exercise] ?? 0, set.achieved) } }
        return best.sorted { $0.key.rawValue < $1.key.rawValue }.map { ($0.key, $0.value) }
    }

    private var bestsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: model.t("En iyi setler", "Best sets"))
                if bests.isEmpty {
                    Text("—").foregroundStyle(Theme.textSecondary)
                }
                ForEach(bests.indices, id: \.self) { index in
                    let (exercise, value) = bests[index]
                    HStack {
                        Text(model.t(exercise.name)).foregroundStyle(.white)
                        Spacer()
                        Text(exercise.isTimed ? "\(value) s" : "\(value)").font(Theme.headline).foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    private var fitCheckCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Fit Check")
                    Spacer()
                    if !model.isPremium { Text("PREMIUM").font(Theme.caption).foregroundStyle(Theme.warning) }
                }
                Button {
                    if model.isPremium { showFitCheck = true } else { showPaywall = true }
                } label: { Label(model.t("Yeni tarama", "New scan"), systemImage: "figure.stand") }
                .buttonStyle(SecondaryButtonStyle())

                let checks = model.data.fitChecks.sorted { $0.date < $1.date }
                if let first = checks.first, let last = checks.last, checks.count >= 2 {
                    SectionTitle(text: model.t("İlk ve son tarama", "First vs latest scan"))
                    ForEach(MeasurementSite.allCases, id: \.self) { site in
                        if let a = first.estimates.first(where: { $0.site == site }), let b = last.estimates.first(where: { $0.site == site }) {
                            let diff = b.valueCm - a.valueCm
                            let significant = abs(diff) > max(a.valueCm, b.valueCm) * site.relativeUncertainty(calibrated: a.calibrated && b.calibrated)
                            HStack {
                                Text(model.t(site.title)).foregroundStyle(.white)
                                Spacer()
                                Text("\(Int(a.valueCm.rounded())) → \(Int(b.valueCm.rounded())) cm")
                                    .foregroundStyle(Theme.textSecondary)
                                Text(significant ? String(format: "%+.0f", diff) : model.t("belirsiz", "within error"))
                                    .font(Theme.caption)
                                    .foregroundStyle(significant ? Theme.accent : Theme.textSecondary)
                            }
                            .font(Theme.body)
                        }
                    }
                    let postureChanges = last.posture.changes(since: first.posture)
                    if !postureChanges.isEmpty {
                        SectionTitle(text: model.t("Duruş değişimi", "Posture change"))
                        ForEach(postureChanges, id: \.self) { note in
                            Text("• " + model.t(note)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    photoComparison(first, last)
                }
                ForEach(checks.reversed()) { record in
                    HStack {
                        Text(record.date, style: .date).foregroundStyle(.white)
                        Spacer()
                        if let waist = record.estimates.first(where: { $0.site == .waist }) {
                            Text(model.t("Bel ", "Waist ") + waist.display()).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Button { model.deleteFitCheck(record.id) } label: { Image(systemName: "trash").foregroundStyle(Theme.danger) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private func photoComparison(_ a: FitCheckRecord, _ b: FitCheckRecord) -> some View {
        if let fa = a.frontPhotoFile, let fb = b.frontPhotoFile,
           let ia = UIImage(contentsOfFile: DataStore.photosDirectory.appendingPathComponent(fa).path),
           let ib = UIImage(contentsOfFile: DataStore.photosDirectory.appendingPathComponent(fb).path) {
            HStack(spacing: 8) {
                VStack {
                    Image(uiImage: ia).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(a.date, style: .date).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                VStack {
                    Image(uiImage: ib).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(b.date, style: .date).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxHeight: 260)
        }
    }
}
