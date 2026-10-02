import XCTest
@testable import AlarmClock

private final class TrackingEngine: AlarmEngine {
    var pending: [String: FireRequest] = [:]
    var cancelled: [String] = []
    func schedule(_ request: FireRequest) { pending[request.alarmId] = request }
    func cancel(alarmId: String) { cancelled.append(alarmId); pending.removeValue(forKey: alarmId) }
    func cancelAll() { pending.removeAll() }
}

private final class TrackingRinger: RingerControl {
    var playing: String?
    var stops = 0
    func start(toneFileName: String) { playing = toneFileName }
    func stop() { playing = nil; stops += 1 }
}

/// "Test my alarm" lifecycle and history recording through the store.
final class TestAlarmAndHistoryStoreTests: XCTestCase {

    private var alarmsURL: URL!
    private var historyURL: URL!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var engine: TrackingEngine!
    private var ringer: TrackingRinger!
    private var history: HistoryLog!

    override func setUp() {
        super.setUp()
        let tmp = FileManager.default.temporaryDirectory
        alarmsURL = tmp.appendingPathComponent("alarms-\(UUID().uuidString).json")
        historyURL = tmp.appendingPathComponent("history-\(UUID().uuidString).json")
        engine = TrackingEngine()
        ringer = TrackingRinger()
        history = HistoryLog(url: historyURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: alarmsURL)
        try? FileManager.default.removeItem(at: historyURL)
        super.tearDown()
    }

    private func makeStore() -> AlarmStore {
        AlarmStore(engine: engine, ringer: ringer, persistenceURL: alarmsURL,
                   now: { [unowned self] in self.clock }, history: history)
    }

    private func seed(_ alarms: [Alarm]) {
        try! JSONEncoder().encode(alarms).write(to: alarmsURL)
    }

    private func savedAlarm() -> Alarm {
        Alarm(id: "a1", hour: 7, minute: 0, label: "Work",
              tone: .pinned(toneId: "chimes"), snoozeMinutes: 5,
              gradualVolume: false, vibrateFirst: true)
    }

    // MARK: - Test my alarm

    func testStartSchedulesRealRequestThirtySecondsOutWithoutSavingIt() {
        let store = makeStore()
        store.upsert(savedAlarm())
        store.startTestAlarm(basedOn: store.alarms[0])

        let test = try! XCTUnwrap(store.testAlarm)
        XCTAssertTrue(store.isTest(test.alarm.id))
        XCTAssertEqual(test.fireAt, clock.addingTimeInterval(30))
        XCTAssertEqual(test.alarm.label, "Test: Work")
        XCTAssertTrue(test.alarm.vibrateFirst)
        XCTAssertEqual(engine.pending[test.alarm.id]?.toneFileName, "tone_chimes.caf")
        XCTAssertEqual(engine.pending[test.alarm.id]?.fireAt, test.fireAt)
        XCTAssertEqual(store.alarms.map(\.id), ["a1"])
        // Not persisted.
        XCTAssertEqual(makeStore().alarms.map(\.id), ["a1"])
    }

    func testDefaultsWhenNoSourceAlarm() {
        let store = makeStore()
        store.startTestAlarm(basedOn: nil)
        XCTAssertEqual(store.testAlarm?.alarm.label, "Test Alarm")
        XCTAssertEqual(store.testAlarm?.alarm.gradualVolume, true)
        XCTAssertTrue(store.alarms.isEmpty)
    }

    func testRescheduleKeepsPendingTest() {
        let store = makeStore()
        store.startTestAlarm(basedOn: nil)
        let id = store.testAlarm!.alarm.id
        store.upsert(savedAlarm()) // triggers cancelAll + reschedule
        XCTAssertNotNil(engine.pending[id])
        XCTAssertNotNil(engine.pending["a1"])
    }

    func testCancelRemovesNotifications() {
        let store = makeStore()
        store.startTestAlarm(basedOn: nil)
        let id = store.testAlarm!.alarm.id
        store.cancelTestAlarm()
        XCTAssertNil(store.testAlarm)
        XCTAssertNil(engine.pending[id])
        XCTAssertTrue(engine.cancelled.contains(id))
    }

    func testStartingAnotherTestReplacesTheFirst() {
        let store = makeStore()
        store.startTestAlarm(basedOn: nil)
        let first = store.testAlarm!.alarm.id
        store.startTestAlarm(basedOn: nil)
        XCTAssertNotEqual(store.testAlarm?.alarm.id, first)
        XCTAssertNil(engine.pending[first])
    }

    func testFiredTestRingsAndStopCleansUp() {
        let store = makeStore()
        store.upsert(savedAlarm())
        store.startTestAlarm(basedOn: nil)
        let id = store.testAlarm!.alarm.id
        clock = clock.addingTimeInterval(31)
        store.onAlarmFired(id: id)
        XCTAssertEqual(store.ringing?.id, id)
        XCTAssertNotNil(ringer.playing)

        store.stopRinging()
        XCTAssertNil(store.ringing)
        XCTAssertNil(store.testAlarm)
        XCTAssertNil(ringer.playing)
        XCTAssertTrue(engine.cancelled.contains(id))
        // The real alarm is untouched.
        XCTAssertEqual(store.alarms.map(\.enabled), [true])
        XCTAssertNotNil(engine.pending["a1"])
    }

    func testSnoozingTestEndsItWithoutRescheduling() {
        let store = makeStore()
        store.startTestAlarm(basedOn: nil)
        let id = store.testAlarm!.alarm.id
        clock = clock.addingTimeInterval(30)
        store.onAlarmFired(id: id)
        store.snoozeRinging()
        XCTAssertNil(store.ringing)
        XCTAssertNil(store.testAlarm)
        XCTAssertNil(engine.pending[id])
    }

    func testLockScreenActionsEndTest() {
        let store = makeStore()
        store.startTestAlarm(basedOn: nil)
        var id = store.testAlarm!.alarm.id
        store.snoozeFromNotification(id: id, firedAt: clock.addingTimeInterval(30))
        XCTAssertNil(store.testAlarm)
        XCTAssertNil(engine.pending[id])

        store.startTestAlarm(basedOn: nil)
        id = store.testAlarm!.alarm.id
        store.stopFromNotification(id: id)
        XCTAssertNil(store.testAlarm)
        XCTAssertTrue(engine.cancelled.contains(id))
    }

    func testOpeningAppDuringTestRingTakesOver() {
        let store = makeStore()
        store.startTestAlarm(basedOn: nil)
        let id = store.testAlarm!.alarm.id
        clock = clock.addingTimeInterval(60)
        store.refreshAndReschedule()
        XCTAssertEqual(store.ringing?.id, id)
    }

    func testExpiredTestIsCleanedUpOnRefresh() {
        let store = makeStore()
        store.startTestAlarm(basedOn: nil)
        clock = clock.addingTimeInterval(30 + AlarmStore.ringWindow + 1)
        store.refreshAndReschedule()
        XCTAssertNil(store.testAlarm)
        XCTAssertNil(store.ringing)
    }

    func testStopForUnknownIdCancelsItsBurst() {
        let store = makeStore()
        store.stopFromNotification(id: "test-stale")
        XCTAssertEqual(engine.cancelled, ["test-stale"])
    }

    // MARK: - History recording

    func testInAppMorningIsRecorded() {
        let store = makeStore()
        store.upsert(savedAlarm())
        let fireAt = store.alarms[0].nextFireDate!
        clock = fireAt.addingTimeInterval(2)
        store.onAlarmFired(id: "a1")
        clock = clock.addingTimeInterval(60)
        store.snoozeRinging()
        clock = fireAt.addingTimeInterval(5 * 60 + 62)
        store.onAlarmFired(id: "a1")
        clock = clock.addingTimeInterval(30)
        store.stopRinging()

        XCTAssertEqual(history.events.map(\.kind), [.fired, .snoozed, .fired, .stopped])
        XCTAssertEqual(history.events[0].date, fireAt)
        XCTAssertEqual(history.events[0].label, "Work")
        let morning = HistoryAggregator.sessions(from: history.events)
        XCTAssertEqual(morning.count, 1)
        XCTAssertEqual(morning[0].snoozes, 1)
        XCTAssertEqual(morning[0].outcome, .stopped)
    }

    func testLockScreenStopRecordsFireTimeFromNotification() {
        let store = makeStore()
        store.upsert(savedAlarm())
        let fireAt = store.alarms[0].nextFireDate!
        clock = fireAt.addingTimeInterval(100)
        store.stopFromNotification(id: "a1", firedAt: fireAt)
        let s = HistoryAggregator.sessions(from: history.events)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].minutesToGetUp!, 100.0 / 60, accuracy: 0.001)
    }

    func testIgnoredAlarmIsRecordedAsMissedOnce() {
        var a = savedAlarm()
        a.repeatDays = [.monday]
        a.nextFireDate = clock.addingTimeInterval(-3600)
        seed([a])
        let store = makeStore()
        store.refreshAndReschedule()
        XCTAssertEqual(history.events.map(\.kind), [.missed])
        XCTAssertEqual(history.events[0].date, a.nextFireDate)
    }

    func testTakeoverRecordsFiredNotMissed() {
        var a = savedAlarm()
        a.nextFireDate = clock.addingTimeInterval(-30)
        seed([a])
        let store = makeStore()
        XCTAssertEqual(store.ringing?.id, "a1")
        XCTAssertEqual(history.events.map(\.kind), [.fired])
    }

    func testDisablingSnoozedAlarmRecordsStop() {
        let store = makeStore()
        store.upsert(savedAlarm())
        store.onAlarmFired(id: "a1")
        store.snoozeRinging()
        store.setEnabled(id: "a1", enabled: false)
        XCTAssertEqual(history.events.map(\.kind), [.fired, .snoozed, .stopped])
    }

    func testDeletingSnoozedAlarmRecordsStop() {
        let store = makeStore()
        store.upsert(savedAlarm())
        store.onAlarmFired(id: "a1")
        store.snoozeRinging()
        store.delete(id: "a1")
        XCTAssertEqual(history.events.map(\.kind), [.fired, .snoozed, .stopped])
    }

    func testDisablingUnsnoozedAlarmRecordsNothing() {
        let store = makeStore()
        store.upsert(savedAlarm())
        store.setEnabled(id: "a1", enabled: false)
        XCTAssertTrue(history.events.isEmpty)
    }

    func testSnoozedFromLockScreenThenIgnoredIsNotMissed() {
        var a = savedAlarm()
        a.repeatDays = [.monday]
        a.nextFireDate = clock.addingTimeInterval(-3600)
        seed([a])
        history.record(AlarmEvent(kind: .snoozed, alarmId: "a1", label: "Work",
                                  date: clock.addingTimeInterval(-3500)))
        _ = makeStore()
        XCTAssertEqual(history.events.map(\.kind), [.snoozed])
    }

    func testTestAlarmEventsAreMarked() {
        let store = makeStore()
        store.startTestAlarm(basedOn: nil)
        let id = store.testAlarm!.alarm.id
        clock = clock.addingTimeInterval(30)
        store.onAlarmFired(id: id)
        store.stopRinging()
        XCTAssertEqual(history.events.map(\.kind), [.fired, .stopped])
        XCTAssertTrue(history.events.allSatisfy(\.isTest))
        XCTAssertTrue(HistoryAggregator.stats(from: HistoryAggregator.sessions(from: history.events)).isEmpty)
    }

    // MARK: - Pure helpers

    func testBurstStartFromChimeIdentifier() {
        let delivered = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(BurstPlan.chimeIndex(fromNotificationIdentifier: "abc"), 0)
        XCTAssertEqual(BurstPlan.chimeIndex(fromNotificationIdentifier: "abc#3"), 3)
        XCTAssertEqual(BurstPlan.chimeIndex(fromNotificationIdentifier: "abc#x"), 0)
        XCTAssertEqual(BurstPlan.burstStart(notificationIdentifier: "abc#3", deliveredAt: delivered),
                       delivered.addingTimeInterval(-90))
        XCTAssertEqual(BurstPlan.burstStart(notificationIdentifier: "abc", deliveredAt: delivered), delivered)
    }

    func testCountdownText() {
        XCTAssertEqual(TestAlarmCountdown.text(remaining: 30), "0:30")
        XCTAssertEqual(TestAlarmCountdown.text(remaining: 29.2), "0:30")
        XCTAssertEqual(TestAlarmCountdown.text(remaining: 0.1), "0:01")
        XCTAssertEqual(TestAlarmCountdown.text(remaining: -5), "0:00")
        XCTAssertEqual(TestAlarmCountdown.text(remaining: 75), "1:15")
        let now = Date()
        XCTAssertEqual(TestAlarmCountdown.status(fireAt: now, now: now), "Test alarm ringing")
    }
}
