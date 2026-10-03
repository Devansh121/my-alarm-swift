import SwiftUI

/// Pure text helpers for the Garmin Watch screen.
enum WatchSyncFormatting {

    static func status(_ watch: GarminConnection.Watch) -> String {
        switch watch.status {
        case .ready:
            switch watch.appInstalled {
            case .some(true): return "Connected"
            case .some(false): return "Connected · Alarm app not installed"
            case .none: return "Connected"
            }
        case .connecting: return "Connecting…"
        case .notConnected: return "Not connected"
        case .bluetoothOff: return "Bluetooth is off"
        case .unavailable: return "Unavailable"
        }
    }

    /// e.g. "Last watch sync: 5 min ago", or a hint before the first one.
    static func lastSync(_ date: Date?, now: Date) -> String {
        guard let date else { return "The watch syncs when you open Alarm on it." }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "Last watch sync: just now" }
        if seconds < 3600 { return "Last watch sync: \(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "Last watch sync: \(Int(seconds / 3600)) h ago" }
        return "Last watch sync: \(Int(seconds / 86_400)) d ago"
    }
}

/// Connect a Garmin watch running the Alarm Connect IQ app and see its sync state.
struct WatchSyncView: View {
    @ObservedObject var connection: GarminConnection
    @ObservedObject var sync: WatchSyncCoordinator
    @State private var confirmDisconnect = false

    var body: some View {
        List {
            Section {
                if connection.watches.isEmpty {
                    Text("No watch connected. Choose your watch in Garmin Connect, then install Alarm on it from the Connect IQ app.")
                        .foregroundStyle(.secondary)
                }
                ForEach(connection.watches) { watch in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(watch.name).font(.headline)
                        Text(WatchSyncFormatting.status(watch))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Watches")
            } footer: {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(WatchSyncFormatting.lastSync(sync.lastWatchSync, now: context.date))
                }
            }

            Section {
                Button(connection.watches.isEmpty ? "Choose Garmin Watch" : "Change Watches") {
                    connection.chooseWatches()
                }
                Button("Sync Now") {
                    sync.syncNow()
                }
                .disabled(!connection.watches.contains { $0.status == .ready })
                if !connection.watches.isEmpty {
                    Button("Disconnect", role: .destructive) {
                        confirmDisconnect = true
                    }
                }
            } footer: {
                if connection.needsGarminConnect {
                    Text("Garmin Connect is needed to choose a watch. Install it from the App Store.")
                } else if let error = connection.lastSendError {
                    Text("Last send failed: \(error)")
                }
            }
        }
        .navigationTitle("Garmin Watch")
        .tint(.orange)
        .confirmationDialog("Stop syncing alarms with your watch?", isPresented: $confirmDisconnect,
                            titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { connection.disconnectAll() }
        }
    }
}
