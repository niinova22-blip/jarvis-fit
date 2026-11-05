import SwiftUI
import JarvisCore

struct WorkoutPlanView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPaywall = false
    @State private var manualLog: PlannedExercise?
    @State private var freeExercise: TrackedExercise?

    var body: some View {
        NavigationStack {
            List {
                if let notes = model.data.plan?.notes, !notes.isEmpty {
                    Section {
                        ForEach(notes, id: \.self) { note in
                            Label(model.t(note), systemImage: "info.circle").font(Theme.caption).foregroundStyle(Theme.warning)
                        }
                    }
                }
                ForEach(model.data.plan?.workouts.sorted(by: { $0.weekday < $1.weekday }) ?? []) { workout in
                    Section {
                        ForEach(workout.exercises) { planned in
                            exerciseRow(planned, in: workout)
                        }
                        if !workout.livePlan.items.isEmpty {
                            Button {
                                if model.canStartLiveWorkout() { model.startWorkout(workout) } else { showPaywall = true }
                            } label: {
                                Label(model.t("Canlı antrenmanı başlat", "Start live workout"), systemImage: "play.circle.fill")
                                    .font(Theme.headline)
                            }
                        }
                        Menu {
                            ForEach(1...7, id: \.self) { day in
                                Button(dayName(day)) { model.moveWorkout(workout.id, to: day) }
                            }
                        } label: {
                            Label(model.t("Başka güne taşı", "Move to another day"), systemImage: "calendar")
                                .font(Theme.caption)
                        }
                    } header: {
                        HStack {
                            Text("\(dayName(workout.weekday)) · \(model.t(workout.title))")
                            Spacer()
                            if workout.weekday == Date().isoWeekday { Text(model.t("BUGÜN", "TODAY")).foregroundStyle(Theme.accent) }
                        }
                    }
                }
                Section(model.t("Serbest canlı antrenman", "Free live training")) {
                    ForEach(TrackedExercise.allCases, id: \.self) { exercise in
                        Button {
                            guard model.canStartLiveWorkout() else { showPaywall = true; return }
                            let item = LiveWorkoutItem(exercise: exercise, sets: 3, target: exercise.isTimed ? 30 : 10, restSeconds: 60)
                            let workout = PlannedWorkout(id: "free-\(exercise.rawValue)", weekday: Date().isoWeekday, kind: .fullBodyA,
                                                         exercises: [PlannedExercise(exerciseId: Self.definitionId(for: exercise),
                                                                                     prescription: Prescription(sets: item.sets, repRange: item.target...item.target + 4, targetReps: item.target, restSeconds: item.restSeconds))])
                            model.startWorkout(workout)
                        } label: {
                            HStack {
                                Text(model.t(exercise.name)).foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "camera.viewfinder").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(model.t("Programın", "Your plan"))
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(item: $manualLog) { planned in ManualLogSheet(planned: planned) }
        }
    }

    private func exerciseRow(_ planned: PlannedExercise, in workout: PlannedWorkout) -> some View {
        let definition = planned.definition
        let p = planned.prescription
        let unit = definition?.isTimed == true ? model.t("sn", "s") : model.t("tekrar", "reps")
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(definition.map { model.t($0.name) } ?? planned.exerciseId).font(Theme.headline).foregroundStyle(.white)
                    if definition?.tracked != nil {
                        Image(systemName: "camera.viewfinder").font(.caption).foregroundStyle(Theme.accent)
                            .accessibilityLabel(model.t("Kamerayla takip edilir", "Camera tracked"))
                    }
                }
                Text("\(p.sets) × \(p.targetReps) \(unit) · \(model.t("aralık", "range")) \(p.repRange.lowerBound)–\(p.repRange.upperBound) · \(model.t("dinlenme", "rest")) \(p.restSeconds)s")
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Menu {
                if definition?.tracked == nil {
                    Button(model.t("Setleri elle kaydet", "Log sets manually")) { manualLog = planned }
                }
                if let profile = model.profile {
                    let alternatives = ExerciseLibrary.alternatives(to: planned.exerciseId, for: profile).prefix(5)
                    if !alternatives.isEmpty {
                        Section(model.t("Alternatif hareket", "Alternative exercise")) {
                            ForEach(Array(alternatives)) { alt in
                                Button(model.t(alt.name)) { model.swapExercise(workoutId: workout.id, from: planned.exerciseId, to: alt.id) }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.textSecondary)
            }
        }
        .listRowBackground(Theme.surface)
    }

    /// Library exercise for a tracked movement (bodyweight version preferred).
    static func definitionId(for exercise: TrackedExercise) -> String {
        let candidates = ExerciseLibrary.all.filter { $0.tracked == exercise }
        return (candidates.first { $0.equipment.isEmpty } ?? candidates.first)?.id ?? exercise.rawValue
    }

    private func dayName(_ day: Int) -> String {
        let tr = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
        let en = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return (model.language == .turkish ? tr : en)[max(0, min(6, day - 1))]
    }
}

/// Manual logging for exercises the camera cannot track (e.g. rows, bench press).
struct ManualLogSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let planned: PlannedExercise
    @State private var sets: [Int] = []
    @State private var load: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section(model.t("Setler", "Sets")) {
                    ForEach(sets.indices, id: \.self) { index in
                        Stepper(value: $sets[index], in: 0...100) {
                            Text(model.t("Set \(index + 1): \(sets[index]) tekrar", "Set \(index + 1): \(sets[index]) reps"))
                        }
                    }
                }
                if planned.definition?.isLoaded == true {
                    Section(model.t("Ağırlık (kg)", "Load (kg)")) {
                        Stepper(value: $load, in: 0...300, step: 1) { Text(String(format: "%.0f kg", load)) }
                    }
                }
            }
            .navigationTitle(planned.definition.map { model.t($0.name) } ?? "")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.t("Vazgeç", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.t("Kaydet", "Save")) {
                        model.addPerformance(ExercisePerformance(exerciseId: planned.exerciseId, date: Date(), sets: sets,
                                                                 targetReps: planned.prescription.targetReps, loadKg: load > 0 ? load : nil))
                        dismiss()
                    }
                }
            }
            .onAppear { if sets.isEmpty { sets = Array(repeating: planned.prescription.targetReps, count: planned.prescription.sets) } }
        }
    }
}
