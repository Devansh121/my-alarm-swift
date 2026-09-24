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
            AppRootPlaceholder(store: store)
                .onAppear { NotificationDelegate.shared.store = store }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refreshAndReschedule()
                    }
                }
        }
    }
}

/// integration PR swaps this for RootView(store:)
private struct AppRootPlaceholder: View {
    let store: AlarmStore

    var body: some View {
        Text("Alarm")
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
    }
}
