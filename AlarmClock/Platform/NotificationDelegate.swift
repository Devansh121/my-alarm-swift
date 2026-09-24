import Foundation
import UserNotifications

/// Routes alarm notifications into the store: foreground arrivals start the
/// in-app ringing screen (suppressing the system banner+sound since the
/// ringer takes over); taps and action buttons from background do the same
/// on open. Store calls are dispatched to the main thread.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationDelegate()

    /// Wired up by the app at launch. Held as a plain var so the app owns
    /// the store's lifetime.
    var store: AlarmStore?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let alarmId = notification.request.identifier
        DispatchQueue.main.async { [weak self] in
            self?.store?.onAlarmFired(id: alarmId)
        }
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let alarmId = response.notification.request.identifier
        let action = response.actionIdentifier
        DispatchQueue.main.async { [weak self] in
            guard let store = self?.store else { return }
            switch action {
            case NotificationAlarmEngine.snoozeActionId:
                store.snoozeFromNotification(id: alarmId)
            case NotificationAlarmEngine.stopActionId:
                store.stopFromNotification(id: alarmId)
            default:
                // Tap on the notification body: open the in-app ringing screen.
                store.onAlarmFired(id: alarmId)
            }
        }
        completionHandler()
    }
}
