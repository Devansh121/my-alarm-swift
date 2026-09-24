import Foundation
import Combine

/// Single source of truth wiring persistence, scheduling, and UI state.
/// Every mutation must: persist → reschedule engine → refresh published state.
final class AlarmStore: ObservableObject {

    @Published private(set) var alarms: [Alarm] = []
    /// Non-nil while an alarm is ringing in-app; drives the full-screen ringing view.
    @Published var ringing: Alarm? = nil

    let engine: AlarmEngine
    let ringer: RingerControl
    let now: () -> Date
    var calendar: Calendar

    private let persistenceURL: URL
    private let toneRandomizer = ToneRandomizer()

    /// alarmId -> last scheduled request; source of truth for the ringing tone.
    private var pending: [String: FireRequest] = [:]

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
        self.persistenceURL = persistenceURL ?? Self.defaultPersistenceURL()

        self.alarms = Self.load(from: self.persistenceURL)
        refreshAndReschedule()
    }

    // MARK: - CRUD

    func upsert(_ alarm: Alarm) {
        var next = alarms
        if let index = next.firstIndex(where: { $0.id == alarm.id }) {
            next[index] = alarm
        } else {
            next.append(alarm)
        }
        alarms = next
        refreshAndReschedule()
    }

    func delete(id: String) {
        alarms.removeAll { $0.id == id }
        refreshAndReschedule()
    }

    func setEnabled(id: String, enabled: Bool) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].enabled = enabled
        refreshAndReschedule()
    }

    // MARK: - Ringing lifecycle

    func onAlarmFired(id: String) {
        runOnMain {
            guard let alarm = self.alarms.first(where: { $0.id == id }) else { return }
            self.ringing = alarm
            let tone = self.pending[id]?.toneFileName ?? bundledTones[0].fileName
            self.ringer.start(toneFileName: tone)
        }
    }

    func stopRinging() {
        runOnMain {
            guard let alarm = self.ringing else { return }
            self.ringer.stop()
            self.ringing = nil
            self.stopAlarm(alarm)
        }
    }

    func snoozeRinging() {
        runOnMain {
            guard let alarm = self.ringing else { return }
            self.ringer.stop()
            self.ringing = nil
            self.scheduleSnooze(alarm)
        }
    }

    func snoozeFromNotification(id: String) {
        runOnMain {
            guard let alarm = self.alarms.first(where: { $0.id == id }) else { return }
            guard alarm.snoozeEnabled else { return }
            self.scheduleSnooze(alarm)
        }
    }

    func stopFromNotification(id: String) {
        runOnMain {
            guard let alarm = self.alarms.first(where: { $0.id == id }) else { return }
            self.stopAlarm(alarm)
        }
    }

    // MARK: - Sync

    /// Call on foreground: reconcile missed one-shots, resync notifications.
    func refreshAndReschedule() {
        runOnMain {
            let reconciled = self.reconcileMissed(self.alarms)

            self.engine.cancelAll()
            var newPending: [String: FireRequest] = [:]
            var scheduled = reconciled

            for index in scheduled.indices {
                let alarm = scheduled[index]
                guard alarm.enabled else {
                    scheduled[index].nextFireDate = nil
                    continue
                }
                let fireAt = NextFireCalculator.nextFire(
                    alarm: alarm, after: self.now(), calendar: self.calendar
                )
                let tone = self.toneRandomizer.resolve(selection: alarm.tone, lastToneId: nil)
                let request = FireRequest(
                    alarmId: alarm.id,
                    fireAt: fireAt,
                    label: alarm.label,
                    toneFileName: tone.fileName
                )
                self.engine.schedule(request)
                newPending[alarm.id] = request
                scheduled[index].nextFireDate = fireAt
            }

            self.pending = newPending
            self.alarms = scheduled
            self.persist()
        }
    }

    // MARK: - Private helpers

    /// One-shot alarms disable themselves once stopped; then re-sync engine + UI.
    private func stopAlarm(_ alarm: Alarm) {
        if alarm.repeatDays.isEmpty {
            if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
                alarms[index].enabled = false
            }
        }
        refreshAndReschedule()
    }

    /// Re-ring in `snoozeMinutes` using the pending request's tone (or first bundled).
    private func scheduleSnooze(_ alarm: Alarm) {
        let tone = pending[alarm.id]?.toneFileName ?? bundledTones[0].fileName
        let request = FireRequest(
            alarmId: alarm.id,
            fireAt: now().addingTimeInterval(TimeInterval(alarm.snoozeMinutes * 60)),
            label: alarm.label,
            toneFileName: tone,
            isSnooze: true
        )
        engine.schedule(request)
        pending[alarm.id] = request
    }

    /// A one-shot alarm whose persisted fire time passed while the app was dead
    /// already rang as a system notification — disable it instead of silently
    /// rescheduling it for tomorrow.
    private func reconcileMissed(_ all: [Alarm]) -> [Alarm] {
        let currentNow = now()
        return all.map { alarm in
            if alarm.enabled,
               alarm.repeatDays.isEmpty,
               let stored = alarm.nextFireDate,
               stored <= currentNow {
                var disabled = alarm
                disabled.enabled = false
                return disabled
            }
            return alarm
        }
    }

    // MARK: - Threading

    /// Ensure @Published mutations run on the main thread (the store may be
    /// invoked from notification callbacks on arbitrary threads).
    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    // MARK: - Persistence

    private static func defaultPersistenceURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("alarms.json")
    }

    private static func load(from url: URL) -> [Alarm] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Alarm].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }
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
