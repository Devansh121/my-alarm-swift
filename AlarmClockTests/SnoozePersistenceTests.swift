import XCTest
@testable import AlarmClock

/// Keeps regular and snooze requests apart, mirroring the engine's distinct
/// notification identifiers for the two.
private final class SnoozeAwareEngine: AlarmEngine {
    var regular: [String: FireRequest] = [:]
    var snoozes: [String: FireRequest] = [:]
    func schedule(_ request: FireRequest) {
        if request.isSnooze { snoozes[request.alarmId] = request } else { regular[request.alarmId] = request }
    }
    func cancel(alarmId: String) {
        regular.removeValue(forKey: alarmId)
        snoozes.removeValue(forKey: alarmId)
    }
    func cancelAll() {
        regular.removeAll()
        snoozes.removeAll()
    }
}

private final class SnoozeRinger: RingerControl {
    var playing: String?
    func start(toneFileName: String) { playing = toneFileName }
    func stop() { playing = nil }
}

/// A pending snooze must survive refreshAndReschedule (foregrounding, CRUD)
/// and app relaunch, and be cleared when it fires, is stopped, or the alarm
/// is deleted/disabled.
final class SnoozePersistenceTests: XCTestCase {

    private var calendar: Calendar!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snooze-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    private func date(_ h: Int, _ min: Int, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: h, minute: min))!
    }

    private func makeStore(
        engine: SnoozeAwareEngine = SnoozeAwareEngine(),
        ringer: SnoozeRinger = SnoozeRinger(),
        now: Date
    ) -> AlarmStore {
        AlarmStore(engine: engine, ringer: ringer, persistenceURL: tempURL,
                   now: { now }, calendar: calendar)
    }

    private func alarm(_ id: String = "a1", hour: Int = 18, days: Set<Weekday> = [],
                       tone: ToneSelection = .pinned(toneId: "waves")) -> Alarm {
        Alarm(id: id, hour: hour, minute: 0, repeatDays: days, label: "Wake",
              tone: tone, snoozeEnabled: true, snoozeMinutes: 9)
    }

    /// Seeds the persisted file as if the app had been killed after snoozing.
    private func seed(_ alarm: Alarm) {
        try! JSONEncoder().encode([alarm]).write(to: tempURL)
    }

    // MARK: Survives rescheduling

    func testSnoozeSurvivesRefreshAlongsideRegularFire() {
        let engine = SnoozeAwareEngine()
        let store = makeStore(engine: engine, now: date(10, 0))
        store.upsert(alarm())
        store.snoozeFromNotification(id: "a1")

        store.refreshAndReschedule() // e.g. lock + unlock → scenePhase .active

        XCTAssertEqual(engine.snoozes["a1"]?.fireAt, date(10, 9))
        XCTAssertEqual(engine.snoozes["a1"]?.toneFileName, "tone_waves.caf")
        XCTAssertEqual(engine.regular["a1"]?.fireAt, date(18, 0), "regular next fire still scheduled")
        XCTAssertEqual(store.alarms.first?.snoozedUntil, date(10, 9))
    }

    func testSnoozeSurvivesCRUDOnAnotherAlarm() {
        let engine = SnoozeAwareEngine()
        let store = makeStore(engine: engine, now: date(10, 0))
        store.upsert(alarm())
        store.snoozeFromNotification(id: "a1")
        store.upsert(alarm("a2", hour: 20))
        XCTAssertEqual(engine.snoozes["a1"]?.fireAt, date(10, 9))
        XCTAssertNotNil(engine.regular["a2"])
    }

    func testRandomToneKeptForSnoozeAcrossRefresh() {
        let engine = SnoozeAwareEngine()
        let store = makeStore(engine: engine, now: date(10, 0))
        store.upsert(alarm(tone: .random))
        store.onAlarmFired(id: "a1")
        store.snoozeRinging()
        let tone = engine.snoozes["a1"]!.toneFileName
        for _ in 0..<10 { store.refreshAndReschedule() }
        XCTAssertEqual(engine.snoozes["a1"]?.toneFileName, tone)
    }

    func testSnoozeSurvivesRelaunch() {
        do {
            let store = makeStore(now: date(10, 0))
            store.upsert(alarm())
            store.onAlarmFired(id: "a1")
            store.snoozeRinging()
        }
        let engine = SnoozeAwareEngine()
        let relaunched = makeStore(engine: engine, now: date(10, 5))
        XCTAssertEqual(engine.snoozes["a1"]?.fireAt, date(10, 9))
        XCTAssertTrue(engine.snoozes["a1"]!.isSnooze)
        XCTAssertEqual(engine.snoozes["a1"]?.toneFileName, "tone_waves.caf")
        XCTAssertEqual(engine.regular["a1"]?.fireAt, date(18, 0))
        XCTAssertNil(relaunched.ringing)
    }

    func testPendingSnoozeDoesNotRetakeOverOrDisableSnoozedOneShot() {
        // One-shot fired at 07:00 (now 07:02, inside its ring window), user
        // snoozed from the lock screen until 07:11, app relaunches at 07:06.
        var a = alarm(hour: 7)
        a.nextFireDate = date(7, 0)
        a.snoozedUntil = date(7, 11)
        seed(a)
        let engine = SnoozeAwareEngine()
        let ringer = SnoozeRinger()
        let store = makeStore(engine: engine, ringer: ringer, now: date(7, 2))
        XCTAssertNil(store.ringing, "a snoozed alarm must not ring again before its snooze")
        XCTAssertNil(ringer.playing)
        XCTAssertTrue(store.alarms.first!.enabled)
        XCTAssertEqual(engine.snoozes["a1"]?.fireAt, date(7, 11))

        let later = makeStore(engine: engine, now: date(7, 6)) // past the 07:00 ring window
        XCTAssertTrue(later.alarms.first!.enabled, "pending snooze must not be reconciled as missed")
        XCTAssertEqual(engine.snoozes["a1"]?.fireAt, date(7, 11))
    }

    // MARK: Clearing

    func testPastSnoozeNotRescheduledAndCleared() {
        var a = alarm(days: Set(Weekday.allCases))
        a.snoozedUntil = date(9, 0)
        seed(a)
        let engine = SnoozeAwareEngine()
        let store = makeStore(engine: engine, now: date(10, 0))
        XCTAssertNil(engine.snoozes["a1"])
        XCTAssertNil(store.alarms.first?.snoozedUntil)
        XCTAssertEqual(engine.regular["a1"]?.fireAt, date(18, 0))
    }

    func testFiringClearsSnooze() {
        let store = makeStore(now: date(10, 0))
        store.upsert(alarm())
        store.snoozeFromNotification(id: "a1")
        store.onAlarmFired(id: "a1")
        XCTAssertNil(store.alarms.first?.snoozedUntil)
    }

    func testStopRingingClearsSnooze() {
        let engine = SnoozeAwareEngine()
        let store = makeStore(engine: engine, now: date(10, 0))
        store.upsert(alarm(days: Set(Weekday.allCases)))
        store.snoozeFromNotification(id: "a1")
        store.onAlarmFired(id: "a1")
        store.stopRinging()
        XCTAssertNil(engine.snoozes["a1"])
        XCTAssertNil(store.alarms.first?.snoozedUntil)
        XCTAssertNotNil(engine.regular["a1"])
    }

    func testStopFromNotificationClearsSnooze() {
        let engine = SnoozeAwareEngine()
        let store = makeStore(engine: engine, now: date(10, 0))
        store.upsert(alarm(days: Set(Weekday.allCases)))
        store.snoozeFromNotification(id: "a1")
        store.stopFromNotification(id: "a1")
        XCTAssertNil(engine.snoozes["a1"])
        XCTAssertNil(store.alarms.first?.snoozedUntil)
        XCTAssertNotNil(engine.regular["a1"])
    }

    func testDeleteClearsSnooze() {
        let engine = SnoozeAwareEngine()
        let store = makeStore(engine: engine, now: date(10, 0))
        store.upsert(alarm())
        store.snoozeFromNotification(id: "a1")
        store.delete(id: "a1")
        XCTAssertTrue(engine.snoozes.isEmpty)
        XCTAssertTrue(engine.regular.isEmpty)
    }

    func testDisableClearsSnooze() {
        let engine = SnoozeAwareEngine()
        let store = makeStore(engine: engine, now: date(10, 0))
        store.upsert(alarm())
        store.snoozeFromNotification(id: "a1")
        store.setEnabled(id: "a1", enabled: false)
        XCTAssertTrue(engine.snoozes.isEmpty)
        XCTAssertNil(store.alarms.first?.snoozedUntil)
    }

    // MARK: Ring-on-open / missed with a snooze that fired while closed

    func testSnoozeFiredWhileClosedTakesOverInsideRingWindow() {
        var a = alarm(hour: 7)
        a.nextFireDate = date(7, 0, day: 21) // already advanced past today's fire
        a.snoozedUntil = date(7, 9)
        seed(a)
        let ringer = SnoozeRinger()
        let store = makeStore(ringer: ringer, now: date(7, 10))
        XCTAssertEqual(store.ringing?.id, "a1")
        XCTAssertNotNil(ringer.playing)
        XCTAssertTrue(store.alarms.first!.enabled)
        XCTAssertNil(store.alarms.first?.snoozedUntil)
    }

    func testSnoozeWhoseRingWindowPassedIsMissed() {
        var a = alarm(hour: 7)
        a.nextFireDate = date(7, 0, day: 21)
        a.snoozedUntil = date(7, 9)
        seed(a)
        let engine = SnoozeAwareEngine()
        let ringer = SnoozeRinger()
        let store = makeStore(engine: engine, ringer: ringer, now: date(8, 0))
        XCTAssertNil(store.ringing)
        XCTAssertNil(ringer.playing)
        XCTAssertFalse(store.alarms.first!.enabled, "missed one-shot snooze disables like a missed alarm")
        XCTAssertTrue(engine.snoozes.isEmpty)
        XCTAssertTrue(engine.regular.isEmpty)
    }

    func testMissedRepeatingSnoozeKeepsAlarmScheduled() {
        var a = alarm(hour: 7, days: Set(Weekday.allCases))
        a.nextFireDate = date(7, 0, day: 21)
        a.snoozedUntil = date(7, 9)
        seed(a)
        let engine = SnoozeAwareEngine()
        let store = makeStore(engine: engine, now: date(8, 0))
        XCTAssertNil(store.ringing)
        XCTAssertTrue(store.alarms.first!.enabled)
        XCTAssertEqual(engine.regular["a1"]?.fireAt, date(7, 0, day: 21))
        XCTAssertTrue(engine.snoozes.isEmpty)
    }

    // MARK: Background-launch notification actions

    func testSnoozeActionAfterBackgroundTakeoverSilencesRinger() {
        // Lock-screen Snooze at 07:01 cold-launches the app; init's refresh
        // takes the 07:00 alarm over in-app before the action is delivered.
        var a = alarm(hour: 7)
        a.nextFireDate = date(7, 0)
        seed(a)
        let engine = SnoozeAwareEngine()
        let ringer = SnoozeRinger()
        let store = makeStore(engine: engine, ringer: ringer, now: date(7, 1))
        XCTAssertNotNil(store.ringing)

        store.snoozeFromNotification(id: "a1")
        XCTAssertNil(store.ringing)
        XCTAssertNil(ringer.playing)
        XCTAssertEqual(engine.snoozes["a1"]?.fireAt, date(7, 10))
    }

    func testSnoozeActionOnMissedOneShotStillSchedules() {
        // Lock-screen Snooze tapped after the ring window: relaunch disables
        // the one-shot as missed, but the explicit snooze must still ring.
        var a = alarm(hour: 7)
        a.nextFireDate = date(7, 0)
        seed(a)
        let engine = SnoozeAwareEngine()
        let store = makeStore(engine: engine, now: date(7, 6))
        XCTAssertFalse(store.alarms.first!.enabled)

        store.snoozeFromNotification(id: "a1")
        XCTAssertEqual(engine.snoozes["a1"]?.fireAt, date(7, 15))
        store.refreshAndReschedule()
        XCTAssertEqual(engine.snoozes["a1"]?.fireAt, date(7, 15))
    }

    func testStoppingRepeatingAlarmInsideRingWindowDoesNotRingAgain() {
        final class Clock { var now = Date() }
        let clock = Clock()
        clock.now = date(6, 59)
        let ringer = SnoozeRinger()
        let store = AlarmStore(engine: SnoozeAwareEngine(), ringer: ringer, persistenceURL: tempURL,
                               now: { clock.now }, calendar: calendar)
        store.upsert(alarm(hour: 7, days: Set(Weekday.allCases)))
        XCTAssertEqual(store.alarms.first?.nextFireDate, date(7, 0))

        clock.now = date(7, 0)
        store.onAlarmFired(id: "a1") // fired in the foreground
        clock.now = date(7, 1)
        store.stopRinging()
        XCTAssertNil(store.ringing, "stopping must not be undone by the ring-on-open takeover")
        XCTAssertNil(ringer.playing)
        XCTAssertEqual(store.alarms.first?.nextFireDate, date(7, 0, day: 21))
    }

    // MARK: Legacy persistence

    func testLegacyJSONWithoutSnoozeKeyDecodes() throws {
        let legacy = """
        [{"id":"a1","hour":7,"minute":30,"repeatDays":[1,5],"label":"Work",
          "tone":{"pinned":{"toneId":"waves"}},"snoozeEnabled":true,"snoozeMinutes":9,
          "enabled":true,"nextFireDate":780000000}]
        """
        let decoded = try JSONDecoder().decode([Alarm].self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, "a1")
        XCTAssertEqual(decoded[0].repeatDays, [.monday, .friday])
        XCTAssertEqual(decoded[0].tone, .pinned(toneId: "waves"))
        XCTAssertNil(decoded[0].snoozedUntil)

        try Data(legacy.utf8).write(to: tempURL)
        let store = makeStore(now: date(10, 0))
        XCTAssertEqual(store.alarms.map(\.id), ["a1"], "legacy alarms must not be wiped on load")
    }
}
