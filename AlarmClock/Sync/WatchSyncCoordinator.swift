import Foundation
import Combine

/// Carries sync messages to and from watches (Connect IQ in the app, a fake
/// in tests). Callbacks are delivered on the main thread.
protocol WatchTransport: AnyObject {
    /// Every message a watch app sends.
    var onMessage: ((Any) -> Void)? { get set }
    /// A watch became reachable; it should get a fresh snapshot.
    var onWatchReady: (() -> Void)? { get set }
    /// Sends to every reachable watch.
    func send(_ message: [String: Any])
}

/// Keeps the watch's copy of the alarms in step with the store
/// (docs/garmin-sync-protocol.md): pushes a snapshot whenever the alarms
/// change, and applies the watch's ops through the store's own methods so
/// watch edits schedule, record history and update widgets exactly like
/// phone edits.
final class WatchSyncCoordinator: ObservableObject {

    /// When the last `sync` arrived from a watch.
    @Published private(set) var lastWatchSync: Date?

    private let store: AlarmStore
    private let transport: WatchTransport
    private let now: () -> Date
    private let stateURL: URL
    private(set) var state: WatchSyncState

    /// Ids in the store as of the last change, to spot deletions.
    private var knownIds: [String]
    /// The alarms part of the last snapshot sent, to skip no-op pushes
    /// (the store republishes on every reschedule).
    private var lastSentAlarms: NSArray?
    /// Set while a watch's ops are applied; the reply snapshot goes out once
    /// at the end instead of once per op.
    private var applyingWatchOps = false
    private var cancellable: AnyCancellable?

    init(store: AlarmStore, transport: WatchTransport, stateURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.transport = transport
        self.now = now
        self.stateURL = stateURL ?? Self.defaultStateURL()
        self.state = WatchSyncState.load(from: self.stateURL)
        self.knownIds = store.alarms.map(\.id)

        transport.onMessage = { [weak self] message in self?.receive(message) }
        transport.onWatchReady = { [weak self] in self?.pushSnapshot(force: true) }
        // @Published emits the new value before the property changes, so
        // the value passed in is the one to use.
        cancellable = store.$alarms.dropFirst().sink { [weak self] alarms in
            self?.alarmsChanged(alarms)
        }
    }

    /// Sends the current alarms even if they haven't changed ("Sync now").
    func syncNow() {
        pushSnapshot(force: true)
    }

    // MARK: - Watch → phone

    func receive(_ message: Any) {
        guard let ops = WatchWire.decodeSync(message) else { return }
        lastWatchSync = now()
        applyingWatchOps = true
        var acked: [String] = []
        for op in ops {
            apply(WatchSyncRules.decide(op, alarms: store.alarms, tombstones: state.tombstones), editedAt: op.at)
            acked.append(op.oid)
        }
        applyingWatchOps = false
        pushSnapshot(alarms: store.alarms, acked: acked, force: true)
    }

    private func apply(_ decision: WatchOpDecision, editedAt: Date) {
        switch decision {
        case .upsert(let alarm):
            store.upsert(alarm, editedAt: editedAt)
        case .delete(let id):
            store.delete(id: id)
        case .setEnabled(let id, let enabled):
            store.setEnabled(id: id, enabled: enabled, editedAt: editedAt)
        case .skip(let id):
            store.skipNext(id: id, editedAt: editedAt)
        case .unskip(let id):
            store.cancelSkip(id: id, editedAt: editedAt)
        case .reject:
            // Acked anyway; the reply snapshot shows the watch the phone's state.
            break
        }
    }

    // MARK: - Phone → watch

    private func alarmsChanged(_ alarms: [Alarm]) {
        let ids = alarms.map(\.id)
        if ids != knownIds {
            state.recordDeletions(previous: knownIds, current: ids, now: now())
            state.save(to: stateURL)
            knownIds = ids
        }
        guard !applyingWatchOps else { return }
        pushSnapshot(alarms: alarms, acked: [], force: false)
    }

    private func pushSnapshot(force: Bool) {
        pushSnapshot(alarms: store.alarms, acked: [], force: force)
    }

    private func pushSnapshot(alarms: [Alarm], acked: [String], force: Bool) {
        let snapshot = WatchWire.snapshot(alarms: alarms, acked: acked, now: now())
        let encoded = (snapshot["alarms"] as? [Any]).map { $0 as NSArray }
        if !force, let encoded, let lastSentAlarms, encoded.isEqual(lastSentAlarms) { return }
        lastSentAlarms = encoded
        transport.send(snapshot)
    }

    private static func defaultStateURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("watch-sync.json")
    }
}
