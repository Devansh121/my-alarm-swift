import XCTest
@testable import AlarmClock

final class NextFireCalculatorTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
                      zone: String = "Asia/Kolkata") -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        let comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return cal.date(from: comps)!
    }

    private func alarm(_ hour: Int, _ minute: Int, days: Set<Weekday> = []) -> Alarm {
        Alarm(id: "a1", hour: hour, minute: minute, repeatDays: days)
    }

    // MARK: One-shot

    func testOneShotLaterTodayFiresToday() {
        let now = date(2026, 9, 20, 10, 0)
        let fire = NextFireCalculator.nextFire(alarm: alarm(18, 30), after: now, calendar: calendar)
        XCTAssertEqual(fire, date(2026, 9, 20, 18, 30))
    }

    func testOneShotEarlierTodayFiresTomorrow() {
        let now = date(2026, 9, 20, 10, 0)
        let fire = NextFireCalculator.nextFire(alarm: alarm(7, 0), after: now, calendar: calendar)
        XCTAssertEqual(fire, date(2026, 9, 21, 7, 0))
    }

    func testOneShotExactlyNowFiresTomorrow() {
        let now = date(2026, 9, 20, 10, 0)
        let fire = NextFireCalculator.nextFire(alarm: alarm(10, 0), after: now, calendar: calendar)
        XCTAssertEqual(fire, date(2026, 9, 21, 10, 0))
    }

    func testOneShotOneMinuteAheadFiresToday() {
        let now = date(2026, 9, 20, 9, 59)
        let fire = NextFireCalculator.nextFire(alarm: alarm(10, 0), after: now, calendar: calendar)
        XCTAssertEqual(fire, date(2026, 9, 20, 10, 0))
    }

    func testOneShotMidnightFiresNextMidnight() {
        let now = date(2026, 9, 20, 0, 1)
        let fire = NextFireCalculator.nextFire(alarm: alarm(0, 0), after: now, calendar: calendar)
        XCTAssertEqual(fire, date(2026, 9, 21, 0, 0))
    }

    // MARK: Repeating

    func testRepeatingTodayIsRepeatDayTimeAheadFiresToday() {
        // 2026-09-20 is a Sunday
        let now = date(2026, 9, 20, 6, 0)
        let a = alarm(8, 0, days: [.sunday])
        XCTAssertEqual(NextFireCalculator.nextFire(alarm: a, after: now, calendar: calendar),
                       date(2026, 9, 20, 8, 0))
    }

    func testRepeatingTodayIsRepeatDayTimePassedFiresNextWeek() {
        let now = date(2026, 9, 20, 9, 0)
        let a = alarm(8, 0, days: [.sunday])
        XCTAssertEqual(NextFireCalculator.nextFire(alarm: a, after: now, calendar: calendar),
                       date(2026, 9, 27, 8, 0))
    }

    func testRepeatingPicksNearestOfMultipleDays() {
        let now = date(2026, 9, 20, 12, 0)
        let a = alarm(7, 0, days: [.monday, .friday])
        XCTAssertEqual(NextFireCalculator.nextFire(alarm: a, after: now, calendar: calendar),
                       date(2026, 9, 21, 7, 0))
    }

    func testRepeatingWeekWrapsAround() {
        let now = date(2026, 9, 20, 12, 0)
        let a = alarm(7, 0, days: [.saturday])
        XCTAssertEqual(NextFireCalculator.nextFire(alarm: a, after: now, calendar: calendar),
                       date(2026, 9, 26, 7, 0))
    }

    func testRepeatingEveryDayBehavesLikeDaily() {
        let now = date(2026, 9, 20, 23, 30)
        let a = alarm(23, 0, days: Set(Weekday.allCases))
        XCTAssertEqual(NextFireCalculator.nextFire(alarm: a, after: now, calendar: calendar),
                       date(2026, 9, 21, 23, 0))
    }

    // MARK: Timezone

    func testResultIsZoneAware() {
        var nyCal = Calendar(identifier: .gregorian)
        nyCal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 9, 20, 10, 0, zone: "America/New_York")
        let fire = NextFireCalculator.nextFire(alarm: alarm(18, 30), after: now, calendar: nyCal)
        XCTAssertEqual(fire, date(2026, 9, 20, 18, 30, zone: "America/New_York"))
        XCTAssertEqual(nyCal.component(.hour, from: fire), 18)
    }

    func testDSTSpringForwardGapResolvesToValidInstant() {
        // US DST 2026: clocks jump 02:00 -> 03:00 on Sun 2026-03-08 in New_York.
        var nyCal = Calendar(identifier: .gregorian)
        nyCal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 3, 8, 1, 0, zone: "America/New_York")
        let fire = NextFireCalculator.nextFire(alarm: alarm(2, 30), after: now, calendar: nyCal)
        let comps = nyCal.dateComponents([.year, .month, .day, .minute], from: fire)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 8)
        XCTAssertEqual(comps.minute, 30)
        // The fire must be a real instant strictly after `now`.
        XCTAssertGreaterThan(fire, now)
    }
}
