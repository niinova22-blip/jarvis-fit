import SwiftUI
import JarvisCore

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var assistant: JarvisAssistant
    @State private var showSettings = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    briefingCard
                    todayCard
                    nutritionCard
                    if !model.recommendations.isEmpty { recommendationsSection }
                    weekCard
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("JARVIS FIT")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(model.t("Ayarlar", "Settings"))
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onAppear(perform: speakBriefingIfNeeded)
        }
    }

    private var briefing: String {
        guard let context = model.assistantContext() else { return "" }
        let hour = Calendar.current.component(.hour, from: Date())
        let last = model.todayWorkout?.exercises.lazy.compactMap { planned in
            model.data.performances.last { $0.exerciseId == planned.exerciseId }
        }.first
        return model.t(DailyBriefing.compose(context: context, hour: hour, lastPerformance: last))
    }

    private func speakBriefingIfNeeded() {
        guard model.data.settings.speakDailyBriefing, !model.briefingSpokenToday, !briefing.isEmpty else { return }
        model.markBriefingSpoken()
        model.voice.say(briefing, priority: .normal)
    }

    private var briefingCard: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                LiveOrb(voice: model.voice, size: 54)
                VStack(alignment: .leading, spacing: 8) {
                    Text(briefing).font(Theme.body).foregroundStyle(.white)
                    Button {
                        model.voice.stopSpeaking()
                        model.voice.say(briefing, priority: .high)
                    } label: {
                        Label(model.t("Dinle", "Listen"), systemImage: "speaker.wave.2.fill").font(Theme.caption)
                    }
                }
            }
        }
    }

    private var todayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: model.t("Bugünkü antrenman", "Today's workout"))
                if let workout = model.todayWorkout {
                    Text(model.t(workout.title)).font(Theme.title).foregroundStyle(.white)
                    Text(model.t("\(workout.exercises.count) hareket · ~\(workout.estimatedMinutes) dk · \(workout.livePlan.items.count) tanesi kamerayla takip edilir",
                                 "\(workout.exercises.count) exercises · ~\(workout.estimatedMinutes) min · \(workout.livePlan.items.count) camera-tracked"))
                        .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    if model.completedToday {
                        Label(model.t("Bugünkü antrenman tamamlandı", "Today's workout is done"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.success)
                    }
                    startButton(workout)
                } else {
                    Text(model.t("Bugün dinlenme günü. İstersen yine de kısa bir antrenman yapabilirsin.", "Rest day. You can still do a short session if you like."))
                        .font(Theme.body).foregroundStyle(Theme.textSecondary)
                    if let any = model.data.plan?.nextWorkout(after: Date().isoWeekday) {
                        startButton(any)
                    }
                }
            }
        }
    }

    @ViewBuilder private func startButton(_ workout: PlannedWorkout) -> some View {
        if workout.livePlan.items.isEmpty {
            Text(model.t("Bu antrenmandaki hareketler kamerayla takip edilemiyor; Antrenman sekmesinden elle kaydedebilirsin.",
                         "This workout has no camera-trackable moves; log it from the Workout tab."))
                .font(Theme.caption).foregroundStyle(Theme.textSecondary)
        } else {
            Button {
                if model.canStartLiveWorkout() { model.startWorkout(workout) } else { showPaywall = true }
            } label: {
                Label(model.t("Canlı antrenmanı başlat", "Start live workout"), systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            if !model.isPremium {
                Text(model.t("Ücretsiz: bu hafta \(model.liveWorkoutsLeftThisWeek) canlı antrenman hakkın kaldı.",
                             "Free: \(model.liveWorkoutsLeftThisWeek) live workouts left this week."))
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var nutritionCard: some View {
        Card {
            if let day = model.nutritionToday {
                HStack(spacing: 18) {
                    ZStack {
                        ProgressRing(progress: day.totals.kcal / Double(max(1, day.targets.kcal)), lineWidth: 9)
                        VStack(spacing: 0) {
                            Text("\(Int(day.totals.kcal))").font(Theme.headline).foregroundStyle(.white)
                            Text("/ \(day.targets.kcal)").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: model.t("Beslenme (tahmini)", "Nutrition (estimated)"))
                        macroBar(model.t("Protein", "Protein"), day.totals.protein, Double(day.targets.proteinG), Theme.accent)
                        macroBar(model.t("Karbonhidrat", "Carbs"), day.totals.carbs, Double(day.targets.carbsG), Theme.warning)
                        macroBar(model.t("Yağ", "Fat"), day.totals.fat, Double(day.targets.fatG), Theme.success)
                    }
                }
            }
        }
        .onTapGesture { model.selectedTab = .nutrition }
    }

    private func macroBar(_ title: String, _ value: Double, _ target: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Int(value))/\(Int(target)) g").font(Theme.caption).foregroundStyle(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color).frame(width: geo.size.width * min(1, value / max(1, target)))
                }
            }
            .frame(height: 6)
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: model.t("JARVIS önerileri", "JARVIS suggestions"))
            ForEach(model.recommendations) { rec in
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.t(rec.title)).font(Theme.headline).foregroundStyle(.white)
                        Text(model.t(rec.reason)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        HStack {
                            Button(model.t("Uygula", "Apply")) { model.accept(rec) }.buttonStyle(SecondaryButtonStyle())
                            Button(model.t("Şimdi değil", "Not now")) { model.dismiss(rec) }
                                .font(Theme.headline).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var weekCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: model.t("Bu hafta", "This week"))
                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { day in
                        let planned = model.data.plan?.workout(on: day) != nil
                        let done = model.data.workoutLogs.contains { $0.date >= Date().startOfWeek && $0.date.isoWeekday == day }
                        VStack(spacing: 6) {
                            Circle()
                                .fill(done ? Theme.success : planned ? Theme.accentSoft : Theme.surfaceRaised)
                                .overlay(Circle().stroke(day == Date().isoWeekday ? Theme.accent : .clear, lineWidth: 2))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black) }
                                }
                            Text(shortDay(day)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func shortDay(_ day: Int) -> String {
        (model.language == .turkish ? ["Pt", "Sa", "Ça", "Pe", "Cu", "Ct", "Pz"] : ["M", "T", "W", "T", "F", "S", "S"])[day - 1]
    }
}

