import SwiftUI

@main
struct AlarmClockApp: App {
    @StateObject private var store: AlarmStore
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
        NotificationDelegate.shared.store = store
        NotificationDelegate.shared.install()
        NotificationAlarmEngine.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refreshAndReschedule()
                    }
                }
                // Widget / Live Activity taps deep-link here. The alarm list
                // is the root screen, so opening the app is all they need.
                .onOpenURL { _ in }
        }
    }
}
