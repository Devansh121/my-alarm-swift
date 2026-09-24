import Foundation
import Combine

/// Single source of truth wiring persistence, scheduling, and UI state.
/// Contract only for now — implementation lands in feature/domain-and-store.
/// Every mutation must: persist → reschedule engine → refresh published state.
final class AlarmStore: ObservableObject {

    @Published private(set) var alarms: [Alarm] = []
    /// Non-nil while an alarm is ringing in-app; drives the full-screen ringing view.
    @Published var ringing: Alarm? = nil

    let engine: AlarmEngine
    let ringer: RingerControl
    let now: () -> Date
    var calendar: Calendar

    init(
        engine: AlarmEngine,
        ringer: RingerControl,
        persistenceURL: URL? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.engine = engine
        self.ringer = ringer
        self.now = now
        self.calendar = calendar
    }

    // MARK: - CRUD

    func upsert(_ alarm: Alarm) {}
    func delete(id: String) {}
    func setEnabled(id: String, enabled: Bool) {}

    // MARK: - Ringing lifecycle

    func onAlarmFired(id: String) {}
    func stopRinging() {}
    func snoozeRinging() {}
    func snoozeFromNotification(id: String) {}
    func stopFromNotification(id: String) {}

    // MARK: - Sync

    /// Call on foreground: reconcile missed one-shots, resync notifications.
    func refreshAndReschedule() {}
}

/// No-op stand-ins so previews and the placeholder app run without platform services.
struct NoopEngine: AlarmEngine {
    func schedule(_ request: FireRequest) {}
    func cancel(alarmId: String) {}
    func cancelAll() {}
}

struct NoopRinger: RingerControl {
    func start(toneFileName: String) {}
    func stop() {}
}
