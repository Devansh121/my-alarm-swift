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

/// Store-level behavior of "skip next" and per-day times: what actually gets
/// handed to the notification engine. 2026-09-20 is a Sunday.
final class SchedulingStoreTests: XCTestCase {

    private var tempURL: URL!
    private var clock = SchedulingStoreTests.date(2026, 9, 20, 10, 0)

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alarms-\(UUID().uuidString).json")
        clock = Self.date(2026, 9, 20, 10, 0)
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

    private func makeStore(_ engine: FakeEngine) -> AlarmStore {
        AlarmStore(engine: engine, ringer: SilentRinger(), persistenceURL: tempURL,
                   now: { [unowned self] in self.clock }, calendar: Self.calendar)
    }

    private let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    private func alarm(_ id: String = "a1", hour: Int = 7, minute: Int = 0,
                       days: Set<Weekday>, overrides: [Weekday: ClockTime] = [:]) -> Alarm {
        var a = Alarm(id: id, hour: hour, minute: minute, repeatDays: days)
        a.timeOverrides = overrides
        return a
    }

    // MARK: Skip next

    func testSkipNextSchedulesFollowingOccurrence() {
        let engine = FakeEngine()
        let store = makeStore(engine)
        store.upsert(alarm(days: weekdays))
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 21, 7, 0))

        store.skipNext(id: "a1")
        XCTAssertEqual(store.alarms[0].skippedFireDate, Self.date(2026, 9, 21, 7, 0))
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 22, 7, 0))
        XCTAssertEqual(store.alarms[0].nextFireDate, Self.date(2026, 9, 22, 7, 0))
    }

    func testCancelSkipRestoresOccurrence() {
        let engine = FakeEngine()
        let store = makeStore(engine)
        store.upsert(alarm(days: weekdays))
        store.skipNext(id: "a1")
        store.cancelSkip(id: "a1")
        XCTAssertNil(store.alarms[0].skippedFireDate)
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 21, 7, 0))
    }

    func testSkipAutoClearsAfterSkippedOccurrencePasses() {
        let engine = FakeEngine()
        let store = makeStore(engine)
        store.upsert(alarm(days: weekdays))
        store.skipNext(id: "a1")

        clock = Self.date(2026, 9, 21, 7, 30) // skipped Mon 7:00 has passed
        store.refreshAndReschedule()
        XCTAssertNil(store.alarms[0].skippedFireDate)
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 22, 7, 0))

        clock = Self.date(2026, 9, 22, 7, 30)
        store.refreshAndReschedule()
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 23, 7, 0))
    }

    func testSkipSurvivesRelaunchBeforeSkippedOccurrence() {
        do {
            let store = makeStore(FakeEngine())
            store.upsert(alarm(days: weekdays))
            store.skipNext(id: "a1")
        }
        clock = Self.date(2026, 9, 21, 6, 0)
        let engine = FakeEngine()
        let relaunched = makeStore(engine)
        XCTAssertEqual(relaunched.alarms[0].skippedFireDate, Self.date(2026, 9, 21, 7, 0))
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 22, 7, 0))
    }

    func testRelaunchAfterSkippedOccurrenceDoesNotRingOrDisable() {
        do {
            let store = makeStore(FakeEngine())
            store.upsert(alarm(days: weekdays))
            store.skipNext(id: "a1")
        }
        clock = Self.date(2026, 9, 21, 7, 1) // inside what would have been the ring window
        let engine = FakeEngine()
        let relaunched = makeStore(engine)
        XCTAssertNil(relaunched.ringing)
        XCTAssertTrue(relaunched.alarms[0].enabled)
        XCTAssertNil(relaunched.alarms[0].skippedFireDate)
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 22, 7, 0))
    }

    func testSkipNextOnOneShotDisablesIt() {
        let engine = FakeEngine()
        let store = makeStore(engine)
        store.upsert(alarm(days: []))
        store.skipNext(id: "a1")
        XCTAssertFalse(store.alarms[0].enabled)
        XCTAssertNil(store.alarms[0].skippedFireDate)
        XCTAssertTrue(engine.pending.isEmpty)
    }

    func testSkipNextIgnoredWhenDisabled() {
        let store = makeStore(FakeEngine())
        store.upsert(alarm(days: weekdays))
        store.setEnabled(id: "a1", enabled: false)
        store.skipNext(id: "a1")
        XCTAssertNil(store.alarms[0].skippedFireDate)
    }

    func testDisablingDropsSkip() {
        let engine = FakeEngine()
        let store = makeStore(engine)
        store.upsert(alarm(days: weekdays))
        store.skipNext(id: "a1")
        store.setEnabled(id: "a1", enabled: false)
        store.setEnabled(id: "a1", enabled: true)
        XCTAssertNil(store.alarms[0].skippedFireDate)
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 21, 7, 0))
    }

    func testEditThatMovesSkippedOccurrenceDropsSkip() {
        let engine = FakeEngine()
        let store = makeStore(engine)
        store.upsert(alarm(days: weekdays))
        store.skipNext(id: "a1")
        var edited = store.alarms[0]
        edited.hour = 6
        store.upsert(edited)
        XCTAssertNil(store.alarms[0].skippedFireDate)
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 21, 6, 0))
    }

    func testEditKeepingSkippedOccurrenceKeepsSkip() {
        let engine = FakeEngine()
        let store = makeStore(engine)
        store.upsert(alarm(days: weekdays))
        store.skipNext(id: "a1")
        var edited = store.alarms[0]
        edited.label = "Work"
        store.upsert(edited)
        XCTAssertEqual(store.alarms[0].skippedFireDate, Self.date(2026, 9, 21, 7, 0))
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 22, 7, 0))
    }

    // MARK: Per-day times

    func testOverrideScheduledOnItsDay() {
        let engine = FakeEngine()
        clock = Self.date(2026, 9, 24, 10, 0) // Thursday
        let store = makeStore(engine)
        store.upsert(alarm(days: weekdays, overrides: [.friday: ClockTime(hour: 8, minute: 30)]))
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 25, 8, 30))
    }

    func testSkipOverrideOccurrenceThenResume() {
        let engine = FakeEngine()
        clock = Self.date(2026, 9, 24, 10, 0) // Thursday
        let store = makeStore(engine)
        store.upsert(alarm(days: weekdays, overrides: [.friday: ClockTime(hour: 8, minute: 30)]))
        store.skipNext(id: "a1")
        XCTAssertEqual(store.alarms[0].skippedFireDate, Self.date(2026, 9, 25, 8, 30))
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 28, 7, 0))

        clock = Self.date(2026, 10, 1, 10, 0) // following Thursday
        store.refreshAndReschedule()
        XCTAssertNil(store.alarms[0].skippedFireDate)
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 10, 2, 8, 30))
    }

    func testOverridesPersistAcrossRelaunch() {
        do {
            let store = makeStore(FakeEngine())
            store.upsert(alarm(days: weekdays, overrides: [.friday: ClockTime(hour: 8, minute: 30)]))
        }
        let relaunched = makeStore(FakeEngine())
        XCTAssertEqual(relaunched.alarms[0].timeOverrides, [.friday: ClockTime(hour: 8, minute: 30)])
    }

    func testMissedRepeatingAlarmWithOverrideReschedulesToOverride() {
        clock = Self.date(2026, 9, 23, 10, 0) // Wednesday
        do {
            let store = makeStore(FakeEngine())
            store.upsert(alarm(days: weekdays, overrides: [.friday: ClockTime(hour: 8, minute: 30)]))
        }
        clock = Self.date(2026, 9, 25, 7, 0) // app dead through Thu 7:00, reopened Fri morning
        let engine = FakeEngine()
        let relaunched = makeStore(engine)
        XCTAssertTrue(relaunched.alarms[0].enabled)
        XCTAssertNil(relaunched.ringing)
        XCTAssertEqual(engine.pending["a1"]?.fireAt, Self.date(2026, 9, 25, 8, 30))
    }

    func testLegacySavedFileLoadsAndSchedules() throws {
        try Data(#"[{"id":"old","hour":18,"minute":0}]"#.utf8).write(to: tempURL)
        let engine = FakeEngine()
        let store = makeStore(engine)
        XCTAssertEqual(store.alarms.map(\.id), ["old"])
        XCTAssertEqual(engine.pending["old"]?.fireAt, Self.date(2026, 9, 20, 18, 0))
    }
}

final class SchedulingFormattingTests: XCTestCase {

    func testOverridesSummaryEmpty() {
        XCTAssertEqual(AlarmFormatting.overridesSummary([:]), "")
    }

    func testOverridesSummarySingle() {
        XCTAssertEqual(AlarmFormatting.overridesSummary([.friday: ClockTime(hour: 8, minute: 30)]), "Fri 8:30 AM")
    }

    func testOverridesSummaryGroupsSharedTimes() {
        let summary = AlarmFormatting.overridesSummary([
            .sunday: ClockTime(hour: 9, minute: 0),
            .wednesday: ClockTime(hour: 6, minute: 15),
            .saturday: ClockTime(hour: 9, minute: 0),
        ])
        XCTAssertEqual(summary, "Wed 6:15 AM, Sat Sun 9:00 AM")
    }

    func testSecondaryLineWithOverrides() {
        let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        XCTAssertEqual(
            AlarmFormatting.secondaryLine(label: "Work", days: weekdays,
                                          overrides: [.friday: ClockTime(hour: 8, minute: 30)]),
            "Work, Weekdays · Fri 8:30 AM"
        )
        XCTAssertEqual(
            AlarmFormatting.secondaryLine(label: "", days: weekdays,
                                          overrides: [.friday: ClockTime(hour: 8, minute: 30)]),
            "Weekdays · Fri 8:30 AM"
        )
        XCTAssertEqual(AlarmFormatting.secondaryLine(label: "Work", days: weekdays, overrides: [:]),
                       "Work, Weekdays")
    }

    func testSecondaryLineIgnoresOverridesForUnselectedDays() {
        XCTAssertEqual(
            AlarmFormatting.secondaryLine(label: "Work", days: [.monday],
                                          overrides: [.friday: ClockTime(hour: 8, minute: 30)]),
            "Work, Mon"
        )
    }

    func testSkipSummary() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let tue = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 7, minute: 0))!
        XCTAssertEqual(AlarmFormatting.skipSummary(tue, calendar: cal), "Skipping Tue 7:00 AM")
    }
}
