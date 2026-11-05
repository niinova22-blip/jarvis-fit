import SwiftUI
import JarvisCore

@main
struct JarvisFitApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var assistant = JarvisAssistant()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(assistant)
                .environmentObject(model.subscriptions)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var assistant: JarvisAssistant
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.isOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        // Personalised notifications are rebuilt from current data whenever the app becomes active.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && model.isOnboarded { NotificationScheduler.reschedule(model: model) }
        }
        .fullScreenCover(isPresented: $model.showLiveWorkout) {
            if let workout = model.activeWorkout {
                LiveWorkoutView(plan: workout.livePlan, planned: workout, model: model, assistant: assistant)
                    .environmentObject(model)
                    .environmentObject(assistant)
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            DashboardView()
                .tabItem { Label(model.t("Bugün", "Today"), systemImage: "sparkles") }
                .tag(AppTab.dashboard)
            WorkoutPlanView()
                .tabItem { Label(model.t("Antrenman", "Workout"), systemImage: "figure.strengthtraining.traditional") }
                .tag(AppTab.workout)
            NutritionView()
                .tabItem { Label(model.t("Beslenme", "Nutrition"), systemImage: "fork.knife") }
                .tag(AppTab.nutrition)
            ProgressScreen()
                .tabItem { Label(model.t("Gelişim", "Progress"), systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.progress)
            ChatView()
                .tabItem { Label("JARVIS", systemImage: "waveform") }
                .tag(AppTab.chat)
        }
    }
}
