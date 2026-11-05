import Foundation
import UserNotifications
import JarvisCore

/// Local notifications only (no server): workout reminders, morning briefing, weekly report.
enum NotificationScheduler {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    @MainActor
    static func reschedule(model: AppModel) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard let profile = model.profile, let plan = model.data.plan else { return }
        let settings = model.data.settings
        let tr = profile.language == .turkish

        if settings.workoutReminders {
            for workout in plan.workouts {
                let content = UNMutableNotificationContent()
                content.title = tr ? "Antrenman zamanı" : "Time to train"
                let muscles = workout.focus.prefix(2).map { $0.title.resolve(profile.language) }.joined(separator: tr ? " ve " : " and ")
                content.body = tr ? "Bugün \(muscles) çalışıyoruz. Telefonu yerleştir, gerisini JARVIS halleder."
                                  : "Today it's \(muscles). Set up your phone and JARVIS will handle the rest."
                content.sound = .default
                var components = DateComponents()
                // DateComponents weekday: 1 = Sunday.
                components.weekday = workout.weekday % 7 + 1
                components.hour = profile.preferredTrainingMinute / 60
                components.minute = profile.preferredTrainingMinute % 60
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                center.add(UNNotificationRequest(identifier: "workout-\(workout.weekday)", content: content, trigger: trigger))
            }
        }
        if settings.speakDailyBriefing {
            let content = UNMutableNotificationContent()
            content.title = tr ? "Günaydın" : "Good morning"
            content.body = tr ? "Günlük brifingin hazır." : "Your daily briefing is ready."
            var components = DateComponents()
            components.hour = 8
            center.add(UNNotificationRequest(identifier: "briefing", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
        }
        if settings.weeklyReport {
            let content = UNMutableNotificationContent()
            content.title = tr ? "Haftalık rapor" : "Weekly report"
            content.body = tr ? "Bu haftaki gelişimine bir bak." : "See how your week went."
            var components = DateComponents()
            components.weekday = 1
            components.hour = 19
            center.add(UNNotificationRequest(identifier: "weekly", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
        }
    }
}
