import SwiftUI

@main
struct AlarmClockApp: App {
    @StateObject private var store: AlarmStore
    @StateObject private var watchSync: WatchSyncCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Wire the store into the delegate here, not in a view's onAppear:
        // a lock-screen Snooze/Stop launches the app in the background with
        // no view appearing, and the delegate would drop the action.
        let store = AlarmStore(
            engine: NotificationAlarmEngine.shared,
            ringer: AlarmRinger.shared,
            history: HistoryLog()
        )
        _store = StateObject(wrappedValue: store)
        AppSurfaces.install(on: store)
        // Created at launch, not on a screen: a Bluetooth background relaunch
        // delivers watch edits with no view on screen.
        _watchSync = StateObject(wrappedValue: WatchSyncCoordinator(
            store: store, transport: GarminConnection.shared
        ))
        GarminConnection.shared.startIfPaired()
        NotificationDelegate.shared.store = store
        NotificationDelegate.shared.install()
        NotificationAlarmEngine.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store, watchSync: watchSync)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refreshAndReschedule()
                    }
                }
                // Garmin Connect returns the chosen watches here. Widget /
                // Live Activity taps also deep-link here; the alarm list is
                // the root screen, so opening the app is all they need.
                .onOpenURL { url in
                    GarminConnection.shared.handle(url: url)
                }
        }
    }
}
