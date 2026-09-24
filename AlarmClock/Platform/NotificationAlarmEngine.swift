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

    func schedule(_ request: FireRequest) {
        let content = UNMutableNotificationContent()
        content.title = request.label
        content.body = request.isSnooze ? "Snoozed alarm" : "Alarm"
        content.sound = UNNotificationSound(
            named: UNNotificationSoundName(request.toneFileName)
        )
        content.categoryIdentifier = Self.alarmCategoryId

        let interval = max(request.fireAt.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: request.alarmId,
                content: content,
                trigger: trigger
            )
        ) { error in
            if let error { NSLog("alarm: schedule failed \(error)") }
        }
    }

    func cancel(alarmId: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [alarmId])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
