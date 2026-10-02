import SwiftUI

@main
struct AlarmClockApp: App {
    @StateObject private var store: AlarmStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Built here rather than lazily by the scene so background launches
        // (notification actions, the Live Activity's Stop intent) have a
        // store even when no window ever appears.
        let store = AlarmStore(
            engine: NotificationAlarmEngine.shared,
            ringer: AlarmRinger.shared
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
                .onAppear { NotificationDelegate.shared.store = store }
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
