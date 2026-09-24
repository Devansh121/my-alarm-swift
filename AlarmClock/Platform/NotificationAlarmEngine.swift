import Foundation
import UserNotifications

/// AlarmEngine backed by UNUserNotificationCenter.
/// Each FireRequest becomes one local notification whose sound is the
/// pre-resolved bundled tone.
final class NotificationAlarmEngine: AlarmEngine {

    static let shared = NotificationAlarmEngine()

    static let alarmCategoryId = "ALARM"
    static let snoozeActionId = "SNOOZE"
    static let stopActionId = "STOP"

    /// Number of chimes fired per alarm. A single constant so schedule and
    /// cancel stay in sync (cancel must remove every burst identifier).
    static let burstChimes = 8

    private var categoriesRegistered = false

    func requestAuthorization() {
        registerCategories()
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            NSLog("alarm: notification permission granted=\(granted)")
        }
    }

    /// Registers the ALARM category once so alarm notifications get
    /// Snooze/Stop buttons on the lock screen and in banners.
    private func registerCategories() {
        guard !categoriesRegistered else { return }
        categoriesRegistered = true

        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionId,
            title: "Snooze"
        )
        let stop = UNNotificationAction(
            identifier: Self.stopActionId,
            title: "Stop",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.alarmCategoryId,
            actions: [snooze, stop],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Schedules the alarm as a burst of identical chimes. If the user presses
    /// volume/power to silence one chime, the next lands `interval` later —
    /// until Snooze/Stop cancels the whole burst.
    func schedule(_ request: FireRequest) {
        let center = UNUserNotificationCenter.current()
        for chime in BurstPlan.plan(for: request, chimes: Self.burstChimes) {
            let content = UNMutableNotificationContent()
            content.title = request.label
            content.body = request.isSnooze ? "Snoozed alarm" : "Alarm"
            content.sound = UNNotificationSound(
                named: UNNotificationSoundName(request.toneFileName)
            )
            content.categoryIdentifier = Self.alarmCategoryId

            let interval = max(chime.fireAt.timeIntervalSinceNow, 1)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)

            center.add(
                UNNotificationRequest(
                    identifier: chime.identifier,
                    content: content,
                    trigger: trigger
                )
            ) { error in
                if let error { NSLog("alarm: schedule failed \(error)") }
            }
        }
    }

    /// Removes every burst identifier for the alarm — both pending chimes and
    /// any already delivered to the lock screen.
    func cancel(alarmId: String) {
        let ids = BurstPlan.allIdentifiers(alarmId: alarmId, chimes: Self.burstChimes)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
