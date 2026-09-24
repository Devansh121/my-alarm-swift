import SwiftUI

@main
struct AlarmClockApp: App {
    @StateObject private var store = AlarmStore(
        engine: NotificationAlarmEngine.shared,
        ringer: AlarmRinger.shared
    )
    @Environment(\.scenePhase) private var scenePhase

    init() {
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
        }
    }
}
