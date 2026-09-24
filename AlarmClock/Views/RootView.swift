import SwiftUI

/// App root: hosts the alarm list and presents the ringing screen full-screen
/// whenever the store reports an alarm firing. Locked to dark mode to match Clock.
struct RootView: View {
    @ObservedObject var store: AlarmStore

    init(store: AlarmStore) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            AlarmListView(store: store)
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
