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
        if !enabled { alarms[index].snoozedUntil = nil }
        refreshAndReschedule()
    }

    // MARK: - Ringing lifecycle

    func onAlarmFired(id: String) {
        runOnMain {
            guard let alarm = self.alarms.first(where: { $0.id == id }) else { return }
            self.ringing = alarm
            let tone = self.pending[id]?.toneFileName ?? bundledTones[0].fileName
            self.ringer.start(toneFileName: tone)
            if let index = self.alarms.firstIndex(where: { $0.id == id }),
               self.alarms[index].snoozedUntil != nil {
                self.alarms[index].snoozedUntil = nil
                self.persist()
            }
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
            self.silenceIfRinging(id: id)
            self.scheduleSnooze(alarm)
        }
    }

    func stopFromNotification(id: String) {
        runOnMain {
            guard let alarm = self.alarms.first(where: { $0.id == id }) else { return }
            self.silenceIfRinging(id: id)
            self.stopAlarm(alarm)
        }
    }

    /// A lock-screen action can arrive right after a background launch whose
    /// refresh took the alarm over in-app; the action is the user's answer to
    /// that ring, so the in-app ringer must not keep playing.
    private func silenceIfRinging(id: String) {
        guard ringing?.id == id else { return }
        ringer.stop()
        ringing = nil
    }

    // MARK: - Sync

    /// How long after its fire time an alarm still counts as "ringing now"
    /// rather than "missed" — matches the notification burst window (8 × 30s).
    static let ringWindow: TimeInterval = 240

    /// Call on foreground: reconcile missed one-shots, resync notifications.
    func refreshAndReschedule() {
        runOnMain {
            // An alarm that fired within the ring window is ringing RIGHT NOW —
            // opening the app must take over with the in-app ringing screen,
            // not silently disable it as "missed".
            // A snooze is the alarm's most recent (or upcoming) fire, so it
            // takes precedence over the regular fire it replaced.
            if self.ringing == nil,
               let live = self.alarms.first(where: { alarm in
                   (alarm.snoozedUntil ?? (alarm.enabled ? alarm.nextFireDate : nil)).map {
                       $0 <= self.now() && self.now() < $0 + Self.ringWindow
                   } ?? false
               }) {
                self.ringing = live
                let tone = self.pending[live.id]?.toneFileName ?? bundledTones[0].fileName
                self.ringer.start(toneFileName: tone)
            }

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

            // A pending snooze is the user's explicit request, scheduled
            // alongside the regular next fire and independent of `enabled`
            // (a missed one-shot may be snoozed from the lock screen after
            // reconciliation disabled it). Past snoozes are dropped.
            for index in scheduled.indices {
                guard let until = scheduled[index].snoozedUntil else { continue }
                guard until > self.now() else {
                    scheduled[index].snoozedUntil = nil
                    continue
                }
                let alarm = scheduled[index]
                let knownTone = self.pending[alarm.id].flatMap { $0.isSnooze ? $0.toneFileName : nil }
                let snooze = FireRequest(
                    alarmId: alarm.id,
                    fireAt: until,
                    label: alarm.label,
                    toneFileName: knownTone
                        ?? self.toneRandomizer.resolve(selection: alarm.tone, lastToneId: nil).fileName,
                    isSnooze: true
                )
                self.engine.schedule(snooze)
                if newPending[alarm.id].map({ until < $0.fireAt }) ?? true {
                    newPending[alarm.id] = snooze
                }
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
        // Stop ends any snooze, and the fire just handled is done — without
        // clearing it a repeating alarm stopped inside its ring window would
        // be taken over again by the refresh below.
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index].snoozedUntil = nil
            alarms[index].nextFireDate = nil
        }
        refreshAndReschedule()
    }

    /// Re-ring in `snoozeMinutes` using the pending request's tone (or first bundled).
    /// Persisted as `snoozedUntil`; refreshAndReschedule schedules the request.
    private func scheduleSnooze(_ alarm: Alarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        let tone = pending[alarm.id]?.toneFileName ?? bundledTones[0].fileName
        let request = FireRequest(
            alarmId: alarm.id,
            fireAt: now().addingTimeInterval(TimeInterval(alarm.snoozeMinutes * 60)),
            label: alarm.label,
            toneFileName: tone,
            isSnooze: true
        )
        pending[alarm.id] = request
        alarms[index].snoozedUntil = request.fireAt
        refreshAndReschedule()
    }

    /// A one-shot alarm whose persisted fire time passed while the app was dead
    /// already rang as a system notification — disable it instead of silently
    /// rescheduling it for tomorrow. Alarms still inside the ring window are
    /// NOT missed — they're ringing, and the takeover in refreshAndReschedule
    /// (or an explicit stop) owns their fate.
    private func reconcileMissed(_ all: [Alarm]) -> [Alarm] {
        let currentNow = now()
        return all.map { alarm in
            if alarm.enabled,
               alarm.repeatDays.isEmpty,
               alarm.id != ringing?.id,
               let stored = alarm.snoozedUntil ?? alarm.nextFireDate,
               stored + Self.ringWindow <= currentNow {
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
