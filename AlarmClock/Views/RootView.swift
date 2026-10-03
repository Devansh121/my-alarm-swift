import SwiftUI

/// App root: hosts the alarm list and presents the ringing screen full-screen
/// whenever the store reports an alarm firing. Locked to dark mode to match Clock.
struct RootView: View {
    @ObservedObject var store: AlarmStore
    var watchSync: WatchSyncCoordinator?

    init(store: AlarmStore, watchSync: WatchSyncCoordinator? = nil) {
        self.store = store
        self.watchSync = watchSync
    }

    var body: some View {
        NavigationStack {
            AlarmListView(store: store, watchSync: watchSync)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: ringingBinding) {
            if let alarm = store.ringing {
                RingingView(alarm: alarm, store: store)
            }
        }
    }

    /// Drives the full-screen cover off the optional `ringing` alarm.
    private var ringingBinding: Binding<Bool> {
        Binding(
            get: { store.ringing != nil },
            set: { newValue in
                if !newValue { store.stopRinging() }
            }
        )
    }
}

#Preview {
    RootView(store: AlarmStore(engine: NoopEngine(), ringer: NoopRinger()))
}
