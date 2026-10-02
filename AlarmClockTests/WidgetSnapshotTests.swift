import XCTest
@testable import AlarmClock

private struct SilentEngine: AlarmEngine {
    func schedule(_ request: FireRequest) {}
    func cancel(alarmId: String) {}
    func cancelAll() {}
}

private struct SilentRinger: RingerControl {
    func start(toneFileName: String) {}
    func stop() {}
}

private final class RecordingPublisher: WidgetSnapshotPublishing {
    var published: [WidgetSnapshot] = []
    func publish(_ snapshot: WidgetSnapshot) { published.append(snapshot) }
}

/// Snapshot building and widget timeline planning. 2026-09-20 is a Sunday.
final class WidgetSnapshotTests: XCTestCase {

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private let now = WidgetSnapshotTests.date(2026, 9, 20, 10, 0)
    private let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    private func build(_ alarms: [Alarm], maxOccurrences: Int = WidgetSnapshotBuilder.maxOccurrences) -> WidgetSnapshot {
        WidgetSnapshotBuilder.build(alarms: alarms, now: now, calendar: Self.calendar,
                                    maxOccurrences: maxOccurrences)
    }

    // MARK: Builder

    func testEmptyAlarmsGiveEmptyCompleteSnapshot() {
        let snapshot = build([])
        XCTAssertEqual(snapshot.occurrences, [])
        XCTAssertNil(snapshot.coversUntil)
    }

    func testDisabledAlarmsExcluded() {
        let snapshot = build([
            Alarm(id: "off", hour: 18, minute: 0, enabled: false),
            Alarm(id: "off-rep", hour: 7, minute: 0, repeatDays: weekdays, enabled: false),
        ])
        XCTAssertEqual(snapshot.occurrences, [])
        XCTAssertNil(snapshot.coversUntil)
    }

    func testOneShotHasSingleOccurrenceAndNoHorizon() {
        let snapshot = build([Alarm(id: "a", hour: 7, minute: 30, label: "Wake")])
        XCTAssertEqual(snapshot.occurrences, [
            .init(alarmId: "a", label: "Wake", fireDate: Self.date(2026, 9, 21, 7, 30)),
        ])
        XCTAssertNil(snapshot.coversUntil)
    }

    func testRepeatingExpandsAcrossHorizon() {
        let snapshot = build([Alarm(id: "w", hour: 7, minute: 0, repeatDays: weekdays)])
        XCTAssertEqual(snapshot.occurrences.map(\.fireDate), [21, 22, 23, 24, 25].map {
            Self.date(2026, 9, $0, 7, 0)
        })
        XCTAssertEqual(snapshot.coversUntil, now.addingTimeInterval(WidgetSnapshotBuilder.horizon))
    }

    func testPerDayOverrideRespected() {
        var alarm = Alarm(id: "w", hour: 7, minute: 0, repeatDays: weekdays)
        alarm.timeOverrides = [.friday: ClockTime(hour: 8, minute: 30)]
        let fires = build([alarm]).occurrences.map(\.fireDate)
        XCTAssertTrue(fires.contains(Self.date(2026, 9, 25, 8, 30)))
        XCTAssertFalse(fires.contains(Self.date(2026, 9, 25, 7, 0)))
        XCTAssertTrue(fires.contains(Self.date(2026, 9, 24, 7, 0)))
    }

    func testSkippedOccurrenceExcludedButLaterOnesKept() {
        var alarm = Alarm(id: "w", hour: 7, minute: 0, repeatDays: weekdays)
        alarm.skippedFireDate = Self.date(2026, 9, 21, 7, 0)
        let fires = build([alarm]).occurrences.map(\.fireDate)
        XCTAssertEqual(fires, [22, 23, 24, 25].map { Self.date(2026, 9, $0, 7, 0) })
    }

    func testSortedAcrossAlarmsWithTiesByAlarmId() {
        let snapshot = build([
            Alarm(id: "b", hour: 7, minute: 0),
            Alarm(id: "late", hour: 22, minute: 0),
            Alarm(id: "a", hour: 7, minute: 0),
            Alarm(id: "soon", hour: 11, minute: 15),
        ])
        XCTAssertEqual(snapshot.occurrences.map(\.alarmId), ["soon", "late", "a", "b"])
    }

    func testBlankLabelFallsBackToAlarm() {
        let snapshot = build([Alarm(id: "a", hour: 7, minute: 0, label: "  ")])
        XCTAssertEqual(snapshot.occurrences.first?.label, "Alarm")
    }

    func testTruncationSetsHorizonAtFirstDroppedFire() {
        let snapshot = build([Alarm(id: "w", hour: 7, minute: 0, repeatDays: weekdays)], maxOccurrences: 3)
        XCTAssertEqual(snapshot.occurrences.count, 3)
        XCTAssertEqual(snapshot.coversUntil, Self.date(2026, 9, 24, 7, 0))
    }

    // MARK: Timeline

    func testTimelineHasEntryAtEachFireAndHorizon() {
        let snapshot = build([
            Alarm(id: "a", hour: 18, minute: 0),
            Alarm(id: "b", hour: 18, minute: 0),
            Alarm(id: "w", hour: 7, minute: 0, repeatDays: [.monday]),
        ])
        let dates = NextAlarmTimeline.entryDates(snapshot: snapshot, now: now)
        XCTAssertEqual(dates, [
            now,
            Self.date(2026, 9, 20, 18, 0),
            Self.date(2026, 9, 21, 7, 0),
            now.addingTimeInterval(WidgetSnapshotBuilder.horizon),
        ])
    }

    func testStateRollsOverAfterAFirePasses() {
        let snapshot = build([
            Alarm(id: "evening", hour: 18, minute: 0),
            Alarm(id: "w", hour: 7, minute: 0, repeatDays: weekdays),
        ])
        guard case .upcoming(let before) = NextAlarmTimeline.state(snapshot: snapshot, at: now) else {
            return XCTFail("expected upcoming")
        }
        XCTAssertEqual(before.first?.alarmId, "evening")

        let atFire = Self.date(2026, 9, 20, 18, 0)
        guard case .upcoming(let after) = NextAlarmTimeline.state(snapshot: snapshot, at: atFire) else {
            return XCTFail("expected upcoming")
        }
        XCTAssertEqual(after.first?.alarmId, "w")
        XCTAssertEqual(after.first?.fireDate, Self.date(2026, 9, 21, 7, 0))
    }

    func testStateIsStalePastHorizonAndUnavailableWithoutSnapshot() {
        let snapshot = build([Alarm(id: "w", hour: 7, minute: 0, repeatDays: weekdays)])
        XCTAssertEqual(NextAlarmTimeline.state(snapshot: snapshot, at: snapshot.coversUntil!), .stale)
        XCTAssertEqual(NextAlarmTimeline.state(snapshot: nil, at: now), .unavailable)
        XCTAssertEqual(NextAlarmTimeline.entryDates(snapshot: nil, now: now), [now])
    }

    func testEmptySnapshotIsNoAlarmsForever() {
        let snapshot = build([])
        XCTAssertEqual(NextAlarmTimeline.state(snapshot: snapshot, at: now.addingTimeInterval(30 * 86_400)),
                       .upcoming([]))
        XCTAssertEqual(NextAlarmTimeline.entryDates(snapshot: snapshot, now: now), [now])
    }

    // MARK: Persistence

    func testSnapshotFileRoundTripsAndDecodesTolerantly() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = build([Alarm(id: "w", hour: 7, minute: 0, repeatDays: weekdays)])
        XCTAssertTrue(SharedSnapshotStore.write(snapshot, to: url))
        XCTAssertEqual(SharedSnapshotStore.read(from: url), snapshot)

        try Data("{}".utf8).write(to: url)
        XCTAssertEqual(SharedSnapshotStore.read(from: url), WidgetSnapshot())
        try Data("garbage".utf8).write(to: url)
        XCTAssertNil(SharedSnapshotStore.read(from: url))
        XCTAssertNil(SharedSnapshotStore.read(from: nil))
        XCTAssertFalse(SharedSnapshotStore.write(snapshot, to: nil))
    }

    // MARK: Store integration

    func testStorePublishesSnapshotOnEveryChange() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alarms-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let publisher = RecordingPublisher()
        let store = AlarmStore(engine: SilentEngine(), ringer: SilentRinger(), persistenceURL: url,
                               now: { [now] in now }, calendar: Self.calendar)
        store.widgetSnapshots = publisher

        store.upsert(Alarm(id: "w", hour: 7, minute: 0, repeatDays: weekdays))
        XCTAssertEqual(publisher.published.last?.occurrences.first?.fireDate, Self.date(2026, 9, 21, 7, 0))

        store.skipNext(id: "w")
        XCTAssertEqual(publisher.published.last?.occurrences.first?.fireDate, Self.date(2026, 9, 22, 7, 0))

        store.setEnabled(id: "w", enabled: false)
        XCTAssertEqual(publisher.published.last?.occurrences, [])

        store.delete(id: "w")
        XCTAssertEqual(publisher.published.last, WidgetSnapshot())
    }
}
