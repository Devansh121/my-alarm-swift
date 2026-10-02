import XCTest
@testable import AlarmClock

private final class FakeEngine: AlarmEngine {
    var pending: [String: FireRequest] = [:]
    func schedule(_ request: FireRequest) { pending[request.alarmId] = request }
    func cancel(alarmId: String) { pending.removeValue(forKey: alarmId) }
    func cancelAll() { pending.removeAll() }
}

private struct SilentRinger: RingerControl {
    func start(toneFileName: String) {}
    func stop() {}
}

/// Records start/end calls and tracks which activities would be live.
private final class RecordingSnoozeActivity: SnoozeActivityControl {
    struct Started: Equatable { let alarmId: String; let label: String; let snoozedAt: Date; let ringsAt: Date }
    var started: [Started] = []
    var ended: [String] = []
    var active: [String: Date] = [:]

    func start(alarmId: String, label: String, snoozedAt: Date, ringsAt: Date) {
        started.append(.init(alarmId: alarmId, label: label, snoozedAt: snoozedAt, ringsAt: ringsAt))
        active[alarmId] = ringsAt
    }

    func end(alarmId: String) {
        ended.append(alarmId)
        active.removeValue(forKey: alarmId)
    }
}

/// The store drives the snooze Live Activity: start on snooze, end on re-fire,
/// stop, delete and disable. 2026-09-20 is a Sunday.
final class SnoozeActivityStoreTests: XCTestCase {

    private var tempURL: URL!
    private var clock = SnoozeActivityStoreTests.date(2026, 9, 20, 10, 0)
    private var engine: FakeEngine!
    private var activity: RecordingSnoozeActivity!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alarms-\(UUID().uuidString).json")
        clock = Self.date(2026, 9, 20, 10, 0)
        engine = FakeEngine()
        activity = RecordingSnoozeActivity()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// A store whose alarm "a1" (18:00, snooze 9 min) is ringing at 18:00.
    private func makeRingingStore(days: Set<Weekday> = [], snoozeEnabled: Bool = true) -> AlarmStore {
        let store = AlarmStore(engine: engine, ringer: SilentRinger(), persistenceURL: tempURL,
                               now: { [unowned self] in self.clock }, calendar: Self.calendar)
        store.snoozeActivity = activity
        store.upsert(Alarm(id: "a1", hour: 18, minute: 0, repeatDays: days, label: "Wake",
                           snoozeEnabled: snoozeEnabled, snoozeMinutes: 9))
        clock = Self.date(2026, 9, 20, 18, 0)
        store.onAlarmFired(id: "a1")
        activity.ended.removeAll()
        return store
    }

    func testSnoozeFromRingingScreenStartsActivity() {
        let store = makeRingingStore()
        store.snoozeRinging()
        XCTAssertEqual(activity.started, [.init(alarmId: "a1", label: "Wake",
                                                snoozedAt: Self.date(2026, 9, 20, 18, 0),
                                                ringsAt: Self.date(2026, 9, 20, 18, 9))])
        XCTAssertEqual(activity.active["a1"], engine.pending["a1"]?.fireAt)
    }

    func testSnoozeFromNotificationStartsActivity() {
        let store = makeRingingStore()
        store.snoozeFromNotification(id: "a1")
        XCTAssertEqual(activity.started.map(\.ringsAt), [Self.date(2026, 9, 20, 18, 9)])
    }

    func testSnoozeDisabledStartsNothing() {
        let store = makeRingingStore(snoozeEnabled: false)
        store.snoozeFromNotification(id: "a1")
        XCTAssertTrue(activity.started.isEmpty)
    }

    func testReFireEndsActivity() {
        let store = makeRingingStore()
        store.snoozeRinging()
        clock = Self.date(2026, 9, 20, 18, 9)
        store.onAlarmFired(id: "a1")
        XCTAssertEqual(activity.ended, ["a1"])
        XCTAssertTrue(activity.active.isEmpty)
    }

    func testStopFromNotificationEndsActivityAndCancelsSnooze() {
        let store = makeRingingStore()
        store.snoozeRinging()
        store.stopFromNotification(id: "a1")
        XCTAssertEqual(activity.ended, ["a1"])
        XCTAssertTrue(activity.active.isEmpty)
        XCTAssertNil(engine.pending["a1"], "stopped one-shot must not ring again")
    }

    func testStopRingingEndsActivity() {
        let store = makeRingingStore(days: [.sunday])
        store.snoozeRinging()
        clock = Self.date(2026, 9, 20, 18, 9)
        store.onAlarmFired(id: "a1")
        activity.ended.removeAll()
        store.stopRinging()
        XCTAssertEqual(activity.ended, ["a1"])
    }

    func testStopThroughLiveActivityRouterEndsActivity() {
        let store = makeRingingStore()
        store.snoozeRinging()
        SnoozeStopRouter.handler = { [weak store] id in store?.stopFromNotification(id: id) }
        defer { SnoozeStopRouter.handler = nil }
        SnoozeStopRouter.handler?("a1")
        XCTAssertEqual(activity.ended, ["a1"])
        XCTAssertFalse(store.alarms[0].enabled)
    }

    func testDeleteEndsActivity() {
        let store = makeRingingStore()
        store.snoozeRinging()
        store.delete(id: "a1")
        XCTAssertEqual(activity.ended, ["a1"])
        XCTAssertTrue(activity.active.isEmpty)
    }

    func testDisableEndsActivityButEnableDoesNot() {
        let store = makeRingingStore(days: [.sunday])
        store.snoozeRinging()
        store.setEnabled(id: "a1", enabled: false)
        XCTAssertEqual(activity.ended, ["a1"])
        activity.ended.removeAll()
        store.setEnabled(id: "a1", enabled: true)
        XCTAssertTrue(activity.ended.isEmpty)
    }

    func testRescheduleAloneDoesNotEndActivity() {
        let store = makeRingingStore(days: [.sunday])
        store.snoozeRinging()
        // Past the 4-minute ring window, so reopening the app is a plain resync.
        clock = Self.date(2026, 9, 20, 18, 5)
        store.refreshAndReschedule()
        store.upsert(Alarm(id: "other", hour: 6, minute: 0))
        XCTAssertTrue(activity.ended.isEmpty)
        XCTAssertNotNil(activity.active["a1"])
    }
}
