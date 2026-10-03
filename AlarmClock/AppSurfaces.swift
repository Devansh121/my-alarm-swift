import Foundation

/// Installs the real widget/Live Activity implementations on the app's store.
/// Tests and previews keep the store's no-op defaults.
enum AppSurfaces {
    static func install(on store: AlarmStore) {
        store.widgetSnapshots = WidgetSnapshotPublisher()
        let snoozeActivity = LiveSnoozeActivityController()
        snoozeActivity.endExpired()
        store.snoozeActivity = snoozeActivity
        // The Live Activity's Stop button takes the same path as the
        // notification's Stop action: cancel the snooze, disable a one-shot.
        SnoozeStopRouter.handler = { [weak store] alarmId in
            store?.stopFromNotification(id: alarmId)
        }
    }
}
