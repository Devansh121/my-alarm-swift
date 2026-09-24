import XCTest
@testable import AlarmClock

private final class RecordingEngine: AlarmEngine {
    var pending: [String: FireRequest] = [:]
    func schedule(_ request: FireRequest) { pending[request.alarmId] = request }
    func cancel(alarmId: String) { pending.removeValue(forKey: alarmId) }
    func cancelAll() { pending.removeAll() }
}

private final class RecordingRinger: RingerControl {
    var playing: String?
    var started: [String] = []
    func start(toneFileName: String) { playing = toneFileName; started.append(toneFileName) }
    func stop() { playing = nil }
}

final class AlarmStoreTests: XCTestCase {

    private var calendar: Calendar!
    private var tempURL: URL!
    private let now = { AlarmStoreTests.date(2026, 9, 20, 10, 0) }

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alarms-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int,
                             zone: String = "Asia/Kolkata") -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func makeStore(
        engine: RecordingEngine = RecordingEngine(),
        ringer: RecordingRinger = RecordingRinger(),
        now: @escaping () -> Date = { AlarmStoreTests.date(2026, 9, 20, 10, 0) }
    ) -> AlarmStore {
        AlarmStore(engine: engine, ringer: ringer, persistenceURL: tempURL, now: now, calendar: calendar)
    }

    private func alarm(_ id: String, hour: Int = 7, minute: Int = 0,
                       enabled: Bool = true, days: Set<Weekday> = [],
                       tone: ToneSelection = .random, snoozeEnabled: Bool = true,
                       snoozeMinutes: Int = 9) -> Alarm {
        Alarm(id: id, hour: hour, minute: minute, repeatDays: days,
              label: "Alarm", tone: tone, snoozeEnabled: snoozeEnabled,
              snoozeMinutes: snoozeMinutes, enabled: enabled)
    }

    // MARK: CRUD

    func testStartsEmpty() {
        let engine = RecordingEngine()
        let store = makeStore(engine: engine)
        XCTAssertEqual(store.alarms, [])
        XCTAssertTrue(engine.pending.isEmpty)
    }

    func testUpsertPersistsSchedulesAndRefreshes() {
        let engine = RecordingEngine()
        let store = makeStore(engine: engine)
        store.upsert(alarm("a1", hour: 18))
        XCTAssertEqual(store.alarms.map { $0.id }, ["a1"])
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 20, 18, 0))
    }

    func testUpsertUpdatesNotDuplicates() {
        let store = makeStore()
        store.upsert(alarm("a1", hour: 6))
        store.upsert(alarm("a1", hour: 9))
        XCTAssertEqual(store.alarms.count, 1)
        XCTAssertEqual(store.alarms.first?.hour, 9)
    }

    func testDisablingSkipsScheduling() {
        let engine = RecordingEngine()
        let store = makeStore(engine: engine)
        store.upsert(alarm("a1"))
        store.setEnabled(id: "a1", enabled: false)
        XCTAssertEqual(store.alarms.count, 1)
        XCTAssertTrue(engine.pending.isEmpty)
        XCTAssertNil(store.alarms.first?.nextFireDate)
    }

    func testDeleteRemovesAlarmAndPending() {
        let engine = RecordingEngine()
        let store = makeStore(engine: engine)
        store.upsert(alarm("a1"))
        store.delete(id: "a1")
        XCTAssertEqual(store.alarms, [])
        XCTAssertTrue(engine.pending.isEmpty)
    }

    func testMultipleAlarmsAllScheduled() {
        let engine = RecordingEngine()
        let store = makeStore(engine: engine)
        store.upsert(alarm("a1", hour: 6))
        store.upsert(alarm("a2", hour: 22))
        XCTAssertEqual(Set(engine.pending.keys), ["a1", "a2"])
    }

    func testCRUDRoundTripPersistence() {
        // First store writes; a second store reading the same file sees the data.
        do {
            let store = makeStore()
            store.upsert(alarm("a1", hour: 18, tone: .pinned(toneId: "waves")))
        }
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.alarms.map { $0.id }, ["a1"])
        XCTAssertEqual(reloaded.alarms.first?.tone, .pinned(toneId: "waves"))
    }

    func testNextFireDatePersisted() {
        let store = makeStore()
        store.upsert(alarm("a4", hour: 18))
        XCTAssertEqual(store.alarms.first?.nextFireDate, Self.date(2026, 9, 20, 18, 0))
    }

    // MARK: Ringing lifecycle

    func testFiredAlarmStartsRingerWithScheduledTone() {
        let ringer = RecordingRinger()
        let store = makeStore(ringer: ringer)
        store.upsert(alarm("a1", hour: 18, tone: .pinned(toneId: "waves")))
        store.onAlarmFired(id: "a1")
        XCTAssertEqual(store.ringing?.id, "a1")
        XCTAssertEqual(ringer.playing, "tone_waves.caf")
    }

    func testStopSilencesAndDisablesOneShot() {
        let engine = RecordingEngine()
        let ringer = RecordingRinger()
        let store = makeStore(engine: engine, ringer: ringer)
        store.upsert(alarm("a1", hour: 18, tone: .pinned(toneId: "waves")))
        store.onAlarmFired(id: "a1")
        store.stopRinging()
        XCTAssertNil(store.ringing)
        XCTAssertNil(ringer.playing)
        XCTAssertFalse(store.alarms.first!.enabled)
        XCTAssertTrue(engine.pending.isEmpty)
    }

    func testStopKeepsRepeatingAlarmEnabledAndRescheduled() {
        let engine = RecordingEngine()
        let store = makeStore(engine: engine)
        store.upsert(alarm("a2", hour: 18, days: Set(Weekday.allCases)))
        store.onAlarmFired(id: "a2")
        store.stopRinging()
        XCTAssertTrue(store.alarms.first!.enabled)
        XCTAssertNotNil(engine.pending["a2"])
    }

    func testSnoozeSchedulesSameToneNMinutesOut() {
        let engine = RecordingEngine()
        let store = makeStore(engine: engine)
        store.upsert(alarm("a1", hour: 18, tone: .pinned(toneId: "waves"), snoozeMinutes: 9))
        store.onAlarmFired(id: "a1")
        store.snoozeRinging()
        XCTAssertNil(store.ringing)
        let request = engine.pending["a1"]!
        XCTAssertTrue(request.isSnooze)
        XCTAssertEqual(request.toneFileName, "tone_waves.caf")
        XCTAssertEqual(request.fireAt, Self.date(2026, 9, 20, 10, 9))
    }

    // MARK: Notification actions

    func testSnoozeFromNotificationSchedulesSnoozeWithPendingTone() {
        let engine = RecordingEngine()
        let ringer = RecordingRinger()
        let store = makeStore(engine: engine, ringer: ringer)
        store.upsert(alarm("a1", hour: 18, tone: .pinned(toneId: "waves"), snoozeMinutes: 9))
        store.snoozeFromNotification(id: "a1")
        let request = engine.pending["a1"]!
        XCTAssertTrue(request.isSnooze)
        XCTAssertEqual(request.toneFileName, "tone_waves.caf")
        XCTAssertEqual(request.fireAt, Self.date(2026, 9, 20, 10, 9))
        XCTAssertNil(store.ringing)
        XCTAssertNil(ringer.playing)
    }

    func testSnoozeFromNotificationIgnoredWhenSnoozeDisabled() {
        let engine = RecordingEngine()
        let store = makeStore(engine: engine)
        store.upsert(alarm("a1", hour: 18, snoozeEnabled: false))
        let before = engine.pending["a1"]!
        store.snoozeFromNotification(id: "a1")
        XCTAssertEqual(engine.pending["a1"], before)
        XCTAssertFalse(engine.pending["a1"]!.isSnooze)
    }

    func testStopFromNotificationDisablesOneShotAndClearsPending() {
        let engine = RecordingEngine()
        let store = makeStore(engine: engine)
        store.upsert(alarm("a1", hour: 18))
        store.stopFromNotification(id: "a1")
        XCTAssertFalse(store.alarms.first!.enabled)
        XCTAssertTrue(engine.pending.isEmpty)
    }

    func testStopFromNotificationDoesNotTouchRingingState() {
        let ringer = RecordingRinger()
        let store = makeStore(ringer: ringer)
        store.upsert(alarm("a1", hour: 18, tone: .pinned(toneId: "waves")))
        store.onAlarmFired(id: "a1")
        store.stopFromNotification(id: "a1")
        XCTAssertEqual(store.ringing?.id, "a1")
        XCTAssertEqual(ringer.playing, "tone_waves.caf")
    }

    // MARK: Missed reconciliation

    func testMissedOneShotDisablesOnRelaunch() {
        do {
            let store = makeStore(now: { AlarmStoreTests.date(2026, 9, 20, 10, 0) })
            store.upsert(alarm("a1", hour: 18))
        }
        let relaunched = makeStore(now: { AlarmStoreTests.date(2026, 9, 21, 9, 0) })
        XCTAssertFalse(relaunched.alarms.first!.enabled)
    }

    func testFutureOneShotStaysEnabledOnRelaunch() {
        do {
            let store = makeStore(now: { AlarmStoreTests.date(2026, 9, 20, 10, 0) })
            store.upsert(alarm("a1", hour: 18))
        }
        let relaunched = makeStore(now: { AlarmStoreTests.date(2026, 9, 20, 12, 0) })
        XCTAssertTrue(relaunched.alarms.first!.enabled)
    }

    func testMissedRepeatingAlarmStaysEnabledAndReschedules() {
        do {
            let store = makeStore(now: { AlarmStoreTests.date(2026, 9, 20, 10, 0) })
            store.upsert(alarm("a2", hour: 18, days: Set(Weekday.allCases)))
        }
        let engine = RecordingEngine()
        let relaunched = makeStore(engine: engine, now: { AlarmStoreTests.date(2026, 9, 21, 9, 0) })
        XCTAssertTrue(relaunched.alarms.first!.enabled)
        XCTAssertEqual(engine.pending["a2"]?.fireAt, Self.date(2026, 9, 21, 18, 0))
    }
}
