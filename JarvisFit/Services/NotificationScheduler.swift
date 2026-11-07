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
                content.body = tr ? "Bugün \(muscles) çalışıyoruz. Telefonu yerleştir, gerisini NOVA halleder."
                                  : "Today it's \(muscles). Set up your phone and NOVA will handle the rest."
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
            // One personalised briefing per day for the next 7 days (rebuilt each time the app opens).
            let calendar = Calendar.current
            let targets = model.targets
            for offset in 1...7 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: Date().startOfDay) else { continue }
                let content = UNMutableNotificationContent()
                let name = profile.name.isEmpty ? "" : ", \(profile.name)"
                content.title = tr ? "Günaydın\(name)" : "Good morning\(name)"
                var body: String
                if let workout = plan.workout(on: date.isoWeekday) {
                    let muscles = workout.focus.prefix(2).map { $0.title.resolve(profile.language) }.joined(separator: tr ? " ve " : " and ")
                    let time = ResponseComposer.timeString(profile.preferredTrainingMinute)
                    body = tr ? "Bugün \(time)'da \(muscles) antrenmanın var." : "Today at \(time): \(muscles) training."
                } else {
                    body = tr ? "Bugün dinlenme günü; toparlanmaya odaklan." : "Rest day today; focus on recovery."
                }
                if let targets {
                    body += tr ? " Protein hedefin \(targets.proteinG) g." : " Protein target: \(targets.proteinG) g."
                }
                content.body = body
                var components = calendar.dateComponents([.year, .month, .day], from: date)
                components.hour = 8
                center.add(UNNotificationRequest(identifier: "briefing-\(offset)", content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            }
        }
        if settings.weeklyReport {
            let content = UNMutableNotificationContent()
            content.title = tr ? "Haftalık rapor" : "Weekly report"
            let report = model.weeklyReport(weekStart: Date().startOfWeek)
            if let report, report.workoutsDone > 0 {
                content.body = tr ? "Bu hafta \(report.workoutsDone) antrenman yaptın. Raporun hazır."
                                  : "You trained \(report.workoutsDone) times this week. Your report is ready."
            } else {
                content.body = tr ? "Bu haftaki gelişimine bir bak." : "See how your week went."
            }
            var components = DateComponents()
            components.weekday = 1
            components.hour = 19
            center.add(UNNotificationRequest(identifier: "weekly", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }
}
