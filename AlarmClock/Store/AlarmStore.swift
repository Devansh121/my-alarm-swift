import Foundation
import Combine

/// Single source of truth wiring persistence, scheduling, and UI state.
/// Every mutation must: persist → reschedule engine → refresh published state.
final class AlarmStore: ObservableObject {

    @Published private(set) var alarms: [Alarm] = []
    /// Non-nil while an alarm is ringing in-app; drives the full-screen ringing view.
    @Published var ringing: Alarm? = nil
    /// A pending or ringing "Test my alarm" run. Never part of `alarms`
    /// and never persisted.
    @Published private(set) var testAlarm: TestAlarm? = nil

    let engine: AlarmEngine
    let ringer: RingerControl
    let now: () -> Date
    var calendar: Calendar
    /// Event log for the History screen; nil disables recording (tests).
    let history: HistoryLog?

    private let persistenceURL: URL
    private let toneRandomizer = ToneRandomizer()

    /// alarmId -> last scheduled request; source of truth for the ringing tone.
    private var pending: [String: FireRequest] = [:]

    init(
        engine: AlarmEngine,
        ringer: RingerControl,
        persistenceURL: URL? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        history: HistoryLog? = nil
    ) {
        self.engine = engine
        self.ringer = ringer
        self.now = now
        self.calendar = calendar
        self.history = history
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
        if let alarm = alarms.first(where: { $0.id == id }), alarm.snoozedUntil != nil {
            record(.stopped, alarm)
        }
        alarms.removeAll { $0.id == id }
        refreshAndReschedule()
    }

    func setEnabled(id: String, enabled: Bool) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].enabled = enabled
        if !enabled, alarms[index].snoozedUntil != nil {
            // Ends the snoozed morning in History rather than leaving it open.
            record(.stopped, alarms[index])
            alarms[index].snoozedUntil = nil
        }
        refreshAndReschedule()
    }

    // MARK: - Skip next

    /// Skips only the next occurrence of a repeating alarm; it resumes on its
    /// own afterwards. For a one-shot there is nothing after the next
    /// occurrence, so skipping it is the same as turning it off.
    func skipNext(id: String) {
        guard let index = alarms.firstIndex(where: { $0.id == id }), alarms[index].enabled else { return }
        if alarms[index].repeatDays.isEmpty {
            alarms[index].enabled = false
        } else {
            var unskipped = alarms[index]
            unskipped.skippedFireDate = nil
            alarms[index].skippedFireDate = NextFireCalculator.nextOccurrence(
                alarm: unskipped, after: now(), calendar: calendar
            )
        }
        refreshAndReschedule()
    }

    /// Undoes a pending "skip next".
    func cancelSkip(id: String) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].skippedFireDate = nil
        refreshAndReschedule()
    }

    // MARK: - Ringing lifecycle

    func onAlarmFired(id: String) {
        runOnMain {
            guard let alarm = self.alarm(withId: id) else { return }
            // Already ringing in-app (e.g. ring-on-open takeover, then the
            // notification tap arrives): don't restart the ring timeline.
            guard self.ringing?.id != id else { return }
            self.ringing = alarm
            let request = self.request(forAlarmId: id)
            let tone = request?.toneFileName ?? bundledTones[0].fileName
            let firedAt = [request?.fireAt, alarm.nextFireDate]
                .compactMap { $0 }
                .filter { $0 <= self.now() }
                .max()
            self.startRinger(for: alarm, tone: tone, firedAt: firedAt)
            self.record(.fired, alarm, at: firedAt)
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
            self.record(.stopped, alarm)
            if self.isTest(alarm.id) {
                self.endTestAlarm()
                return
            }
            self.stopAlarm(alarm)
        }
    }

    func snoozeRinging() {
        runOnMain {
            guard let alarm = self.ringing else { return }
            self.ringer.stop()
            self.ringing = nil
            // Snoozing a test alarm just ends the test: it has proven the
            // Snooze action works, and a 9-minute re-ring isn't a "test".
            if self.isTest(alarm.id) {
                self.record(.stopped, alarm)
                self.endTestAlarm()
                return
            }
            self.record(.snoozed, alarm)
            self.scheduleSnooze(alarm)
        }
    }

    /// - Parameter firedAt: when this ring started (first chime of the
    ///   burst), if the notification tells us; used for history only.
    func snoozeFromNotification(id: String, firedAt: Date? = nil) {
        runOnMain {
            if self.endTestOrStrayFromNotification(id: id, firedAt: firedAt) { return }
            guard let alarm = self.alarms.first(where: { $0.id == id }) else { return }
            guard alarm.snoozeEnabled else { return }
            self.silenceIfRinging(id: id)
            if let firedAt { self.record(.fired, alarm, at: firedAt) }
            self.record(.snoozed, alarm)
            self.scheduleSnooze(alarm)
        }
    }

    func stopFromNotification(id: String, firedAt: Date? = nil) {
        runOnMain {
            if self.endTestOrStrayFromNotification(id: id, firedAt: firedAt) { return }
            guard let alarm = self.alarms.first(where: { $0.id == id }) else { return }
            self.silenceIfRinging(id: id)
            if let firedAt { self.record(.fired, alarm, at: firedAt) }
            self.record(.stopped, alarm)
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

    // MARK: - Test my alarm

    static let testAlarmIdPrefix = "test-"
    /// How far ahead "Test my alarm" schedules its ring.
    static let testAlarmDelay: TimeInterval = 30

    /// Schedules a real alarm `testAlarmDelay` from now through the engine,
    /// using `source`'s settings (or defaults), so the user can lock the
    /// phone and hear/feel exactly what a real alarm does. Replaces any
    /// previous test. The test is never added to `alarms` or persisted, and
    /// is cleaned up when it is stopped, snoozed, cancelled, or its ring
    /// window passes.
    func startTestAlarm(basedOn source: Alarm?) {
        runOnMain {
            self.cancelTestAlarmNow()
            let fireAt = self.now().addingTimeInterval(Self.testAlarmDelay)
            let parts = self.calendar.dateComponents([.hour, .minute], from: fireAt)
            var alarm = source ?? Alarm(hour: 0, minute: 0)
            alarm.id = Self.testAlarmIdPrefix + UUID().uuidString
            alarm.hour = parts.hour ?? 0
            alarm.minute = parts.minute ?? 0
            alarm.repeatDays = []
            alarm.enabled = true
            alarm.nextFireDate = fireAt
            alarm.label = source.map { "Test: \($0.label)" } ?? "Test Alarm"
            let tone = self.toneRandomizer.resolve(selection: alarm.tone, lastToneId: nil)
            let request = FireRequest(
                alarmId: alarm.id, fireAt: fireAt,
                label: alarm.label, toneFileName: tone.fileName
            )
            self.engine.schedule(request)
            self.testAlarm = TestAlarm(alarm: alarm, request: request)
        }
    }

    /// Cancels a pending test, or silences one that is ringing.
    func cancelTestAlarm() {
        runOnMain { self.cancelTestAlarmNow() }
    }

    func isTest(_ alarmId: String) -> Bool {
        alarmId.hasPrefix(Self.testAlarmIdPrefix)
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
                let liveFiredAt = live.snoozedUntil ?? live.nextFireDate
                self.startRinger(for: live, tone: tone, firedAt: liveFiredAt)
                self.record(.fired, live, at: liveFiredAt)
            }
            self.refreshTestAlarm()
            self.recordMissed(self.alarms)

            let reconciled = self.reconcileSkips(self.reconcileMissed(self.alarms))

            self.engine.cancelAll()
            // cancelAll also removed a pending test; put it back.
            if let test = self.testAlarm, test.fireAt > self.now() {
                self.engine.schedule(test.request)
            }
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

    /// A saved alarm, or the current test alarm.
    private func alarm(withId id: String) -> Alarm? {
        alarms.first(where: { $0.id == id })
            ?? testAlarm.flatMap { $0.alarm.id == id ? $0.alarm : nil }
    }

    private func request(forAlarmId id: String) -> FireRequest? {
        if let test = testAlarm, test.alarm.id == id { return test.request }
        return pending[id]
    }

    private func record(_ kind: AlarmEvent.Kind, _ alarm: Alarm, at date: Date? = nil) {
        history?.record(AlarmEvent(
            kind: kind, alarmId: alarm.id, label: alarm.label,
            date: date ?? now(), isTest: isTest(alarm.id)
        ))
    }

    /// An enabled alarm whose stored fire time is past the ring window, with
    /// nothing recorded since, rang with nobody around (the app wasn't
    /// opened, and no Snooze/Stop was pressed): log it as missed. Runs
    /// before the fire time is advanced, so each miss is logged once.
    private func recordMissed(_ all: [Alarm]) {
        guard let history else { return }
        let currentNow = now()
        for alarm in all where alarm.enabled && alarm.id != ringing?.id {
            guard let stored = alarm.nextFireDate,
                  stored + Self.ringWindow <= currentNow,
                  !history.hasEvent(alarmId: alarm.id, since: stored) else { continue }
            record(.missed, alarm, at: stored)
        }
    }

    /// Opening the app while the test rings takes over like a real alarm;
    /// a test whose ring window has passed untouched is cleaned up.
    private func refreshTestAlarm() {
        guard let test = testAlarm, ringing?.id != test.alarm.id else { return }
        let currentNow = now()
        if currentNow >= test.fireAt + Self.ringWindow {
            endTestAlarm()
        } else if ringing == nil, test.fireAt <= currentNow {
            ringing = test.alarm
            startRinger(for: test.alarm, tone: test.request.toneFileName, firedAt: test.fireAt)
            record(.fired, test.alarm, at: test.fireAt)
        }
    }

    private func cancelTestAlarmNow() {
        guard let test = testAlarm else { return }
        if ringing?.id == test.alarm.id {
            ringer.stop()
            ringing = nil
        }
        endTestAlarm()
    }

    /// Cancels the test's notifications (pending and delivered) and forgets it.
    private func endTestAlarm() {
        guard let test = testAlarm else { return }
        engine.cancel(alarmId: test.alarm.id)
        testAlarm = nil
    }

    /// Lock-screen Snooze/Stop on the test alarm ends it. On an id we don't
    /// know (a test from before the app was relaunched, or a deleted alarm)
    /// the remaining burst is cancelled so it stops chiming.
    /// Returns true when the action was fully handled here.
    private func endTestOrStrayFromNotification(id: String, firedAt: Date?) -> Bool {
        if let test = testAlarm, test.alarm.id == id {
            if let firedAt { record(.fired, test.alarm, at: firedAt) }
            record(.stopped, test.alarm)
            cancelTestAlarmNow()
            return true
        }
        if alarms.contains(where: { $0.id == id }) { return false }
        engine.cancel(alarmId: id)
        return true
    }

    /// Starts the in-app ringer with the alarm's style, resuming the
    /// vibrate-first / ramp timeline from `firedAt` when the alarm has
    /// already been ringing (as notifications) for a while.
    private func startRinger(for alarm: Alarm, tone: String, firedAt: Date?) {
        let elapsed = Self.elapsedRinging(since: firedAt, now: now())
        ringer.start(toneFileName: tone, style: alarm.ringStyle, elapsed: elapsed)
    }

    /// Seconds an alarm has been ringing, or 0 if `firedAt` is unknown,
    /// in the future, or outside the ring window.
    static func elapsedRinging(since firedAt: Date?, now: Date) -> TimeInterval {
        guard let firedAt else { return 0 }
        let elapsed = now.timeIntervalSince(firedAt)
        return (0..<ringWindow).contains(elapsed) ? elapsed : 0
    }

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

    /// Drops skips that no longer apply — the skipped occurrence has passed,
    /// the alarm was disabled, or an edit moved it off the schedule — so a
    /// skip never lingers past the one occurrence it was meant for.
    private func reconcileSkips(_ all: [Alarm]) -> [Alarm] {
        let currentNow = now()
        return all.map { alarm in
            guard alarm.skippedFireDate != nil,
                  NextFireCalculator.activeSkip(alarm: alarm, after: currentNow, calendar: calendar) == nil
            else { return alarm }
            var cleared = alarm
            cleared.skippedFireDate = nil
            return cleared
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

/// A scheduled "Test my alarm" run: a throwaway alarm plus its fire request.
struct TestAlarm: Equatable {
    let alarm: Alarm
    let request: FireRequest
    var fireAt: Date { request.fireAt }
}
