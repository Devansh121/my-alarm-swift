import XCTest
@testable import AlarmClock

final class HistoryAggregatorTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func ev(_ kind: AlarmEvent.Kind, _ minutes: Double, id: String = "a1",
                    label: String = "Wake", test: Bool = false) -> AlarmEvent {
        AlarmEvent(kind: kind, alarmId: id, label: label,
                   date: t0.addingTimeInterval(minutes * 60), isTest: test)
    }

    func testFiredSnoozedStoppedIsOneMorning() {
        let s = HistoryAggregator.sessions(from: [
            ev(.fired, 0), ev(.snoozed, 1), ev(.fired, 10), ev(.snoozed, 11),
            ev(.fired, 20), ev(.stopped, 22),
        ])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].firedAt, t0)
        XCTAssertEqual(s[0].snoozes, 2)
        XCTAssertEqual(s[0].outcome, .stopped)
        XCTAssertEqual(s[0].minutesToGetUp!, 22, accuracy: 0.001)
    }

    func testOutOfOrderInputIsSortedByDate() {
        let s = HistoryAggregator.sessions(from: [ev(.stopped, 5), ev(.fired, 0)])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].minutesToGetUp!, 5, accuracy: 0.001)
    }

    func testStopWithoutFiredStartsSessionAtStop() {
        let s = HistoryAggregator.sessions(from: [ev(.stopped, 3)])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].outcome, .stopped)
        XCTAssertEqual(s[0].minutesToGetUp!, 0, accuracy: 0.001)
    }

    func testMissedMorning() {
        let s = HistoryAggregator.sessions(from: [ev(.missed, 0)])
        XCTAssertEqual(s.map(\.outcome), [.missed])
        XCTAssertNil(s[0].minutesToGetUp)
    }

    func testLateStopReopensRecentMissed() {
        // Cold launch from a lock-screen Stop: "missed" gets logged on
        // launch, then the fire + stop from the notification arrive.
        let s = HistoryAggregator.sessions(from: [ev(.missed, 0), ev(.fired, 0), ev(.stopped, 6)])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].outcome, .stopped)
        XCTAssertEqual(s[0].minutesToGetUp!, 6, accuracy: 0.001)
    }

    func testNextDayFireDoesNotReopenMissed() {
        let s = HistoryAggregator.sessions(from: [ev(.missed, 0), ev(.fired, 24 * 60), ev(.stopped, 24 * 60 + 1)])
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.map(\.outcome), [.stopped, .missed]) // newest first
    }

    func testAbandonedSessionTimesOut() {
        let s = HistoryAggregator.sessions(from: [ev(.fired, 0), ev(.fired, 24 * 60), ev(.stopped, 24 * 60 + 2)])
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].outcome, .stopped)
        XCTAssertEqual(s[0].minutesToGetUp!, 2, accuracy: 0.001)
        XCTAssertEqual(s[1].outcome, .open)
    }

    func testAlarmsAreTrackedIndependently() {
        let s = HistoryAggregator.sessions(from: [
            ev(.fired, 0, id: "a"), ev(.fired, 1, id: "b"),
            ev(.stopped, 2, id: "a"), ev(.snoozed, 3, id: "b"), ev(.stopped, 15, id: "b"),
        ])
        XCTAssertEqual(s.count, 2)
        let b = s.first { $0.alarmId == "b" }!
        XCTAssertEqual(b.snoozes, 1)
        XCTAssertEqual(b.minutesToGetUp!, 14, accuracy: 0.001)
    }

    func testStatsAveragesAndExcludesTests() {
        let day = 24.0 * 60
        let sessions = HistoryAggregator.sessions(from: [
            ev(.fired, 0), ev(.snoozed, 1), ev(.stopped, 10),
            ev(.fired, day), ev(.stopped, day + 2),
            ev(.missed, 2 * day),
            ev(.fired, 3 * day, id: "t", label: "Test", test: true),
            ev(.stopped, 3 * day + 1, id: "t", label: "Test", test: true),
        ])
        XCTAssertEqual(sessions.count, 4)
        XCTAssertTrue(sessions[0].isTest)
        let stats = HistoryAggregator.stats(from: sessions)
        XCTAssertEqual(stats.count, 1)
        let a = stats[0]
        XCTAssertEqual(a.alarmId, "a1")
        XCTAssertEqual(a.mornings, 3)
        XCTAssertEqual(a.missed, 1)
        XCTAssertEqual(a.averageSnoozes!, 0.5, accuracy: 0.001)
        XCTAssertEqual(a.averageMinutesToGetUp!, 6, accuracy: 0.001)
    }

    func testStatsUseNewestLabel() {
        let sessions = HistoryAggregator.sessions(from: [
            ev(.fired, 0, label: "Old"), ev(.stopped, 1, label: "Old"),
            ev(.fired, 24 * 60, label: "New"), ev(.stopped, 24 * 60 + 1, label: "New"),
        ])
        XCTAssertEqual(HistoryAggregator.stats(from: sessions).first?.label, "New")
    }

    func testStatsWithOnlyMissedHaveNoAverages() {
        let stats = HistoryAggregator.stats(from: HistoryAggregator.sessions(from: [ev(.missed, 0)]))
        XCTAssertNil(stats[0].averageSnoozes)
        XCTAssertNil(stats[0].averageMinutesToGetUp)
    }

    func testCappedKeepsNewest() {
        let events = (0..<10).map { ev(.fired, Double(9 - $0)) } // newest first
        let capped = HistoryAggregator.capped(events, limit: 3)
        XCTAssertEqual(capped.map(\.date), [7, 8, 9].map { t0.addingTimeInterval($0 * 60) })
        XCTAssertEqual(HistoryAggregator.capped(events, limit: 20).count, 10)
    }

    func testSummaryText() {
        let stopped = RingSession(alarmId: "a", label: "A", firedAt: t0, snoozes: 1,
                                  endedAt: t0.addingTimeInterval(12 * 60), outcome: .stopped,
                                  lastActivity: t0)
        XCTAssertEqual(HistoryFormatting.summary(stopped), "1 snooze · up in 12 min")
        var missed = stopped
        missed.outcome = .missed
        XCTAssertEqual(HistoryFormatting.summary(missed), "Missed")
        var open = stopped
        open.outcome = .open
        open.snoozes = 0
        XCTAssertEqual(HistoryFormatting.summary(open), "Not stopped")
        XCTAssertEqual(HistoryFormatting.minutes(0.3), "<1 min")
    }
}
