import XCTest
@testable import AlarmClock

/// Per-day time overrides and "skip next" in NextFireCalculator.
/// Reference week: 2026-09-20 is a Sunday (Mon 21 ... Sat 26, Sun 27).
final class ScheduleRulesTests: XCTestCase {

    private func calendar(_ zone: String = "Asia/Kolkata") -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int,
                      zone: String = "Asia/Kolkata") -> Date {
        calendar(zone).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    private func alarm(_ h: Int, _ m: Int, days: Set<Weekday>,
                       overrides: [Weekday: ClockTime] = [:], skip: Date? = nil) -> Alarm {
        var a = Alarm(id: "a1", hour: h, minute: m, repeatDays: days)
        a.timeOverrides = overrides
        a.skippedFireDate = skip
        return a
    }

    private func next(_ a: Alarm, _ now: Date, zone: String = "Asia/Kolkata") -> Date {
        NextFireCalculator.nextFire(alarm: a, after: now, calendar: calendar(zone))
    }

    // MARK: Overrides

    func testOverrideUsedOnItsDay() {
        let a = alarm(7, 0, days: weekdays, overrides: [.friday: ClockTime(hour: 8, minute: 30)])
        XCTAssertEqual(next(a, date(2026, 9, 24, 10, 0)), date(2026, 9, 25, 8, 30))
    }

    func testDefaultTimeUsedOnOtherDays() {
        let a = alarm(7, 0, days: weekdays, overrides: [.friday: ClockTime(hour: 8, minute: 30)])
        XCTAssertEqual(next(a, date(2026, 9, 20, 12, 0)), date(2026, 9, 21, 7, 0))
    }

    func testOverrideLaterThanDefaultStillFiresTodayAfterDefaultPassed() {
        let a = alarm(7, 0, days: Set(Weekday.allCases), overrides: [.sunday: ClockTime(hour: 10, minute: 0)])
        XCTAssertEqual(next(a, date(2026, 9, 20, 8, 0)), date(2026, 9, 20, 10, 0))
    }

    func testOverrideEarlierThanDefaultAlreadyPassedMovesToNextDay() {
        let a = alarm(9, 0, days: Set(Weekday.allCases), overrides: [.sunday: ClockTime(hour: 6, minute: 0)])
        XCTAssertEqual(next(a, date(2026, 9, 20, 7, 0)), date(2026, 9, 21, 9, 0))
        XCTAssertEqual(next(a, date(2026, 9, 20, 5, 0)), date(2026, 9, 20, 6, 0))
    }

    func testOverrideForNonRepeatDayIsIgnored() {
        let a = alarm(7, 0, days: [.monday], overrides: [.tuesday: ClockTime(hour: 5, minute: 0)])
        XCTAssertEqual(next(a, date(2026, 9, 20, 12, 0)), date(2026, 9, 21, 7, 0))
    }

    func testOneShotIgnoresOverrides() {
        let a = alarm(7, 0, days: [], overrides: [.monday: ClockTime(hour: 5, minute: 0)])
        XCTAssertEqual(next(a, date(2026, 9, 20, 12, 0)), date(2026, 9, 21, 7, 0))
    }

    func testOverrideWeekWraparound() {
        let a = alarm(7, 0, days: [.saturday], overrides: [.saturday: ClockTime(hour: 9, minute: 0)])
        XCTAssertEqual(next(a, date(2026, 9, 26, 10, 0)), date(2026, 10, 3, 9, 0))
    }

    func testEffectiveOverridesDropDefaultsAndUnselectedDays() {
        let a = alarm(7, 0, days: [.monday, .friday], overrides: [
            .monday: ClockTime(hour: 7, minute: 0),
            .friday: ClockTime(hour: 8, minute: 30),
            .sunday: ClockTime(hour: 10, minute: 0),
        ])
        XCTAssertEqual(a.effectiveTimeOverrides, [.friday: ClockTime(hour: 8, minute: 30)])
        XCTAssertEqual(alarm(7, 0, days: [], overrides: [.friday: ClockTime(hour: 8, minute: 30)])
            .effectiveTimeOverrides, [:])
    }

    // MARK: Skip next

    func testSkipJumpsToFollowingOccurrence() {
        let a = alarm(7, 0, days: Set(Weekday.allCases), skip: date(2026, 9, 21, 7, 0))
        let now = date(2026, 9, 20, 10, 0)
        XCTAssertEqual(next(a, now), date(2026, 9, 22, 7, 0))
        XCTAssertEqual(NextFireCalculator.activeSkip(alarm: a, after: now, calendar: calendar()),
                       date(2026, 9, 21, 7, 0))
    }

    func testSkipAutoClearsOnceOccurrencePassed() {
        let a = alarm(7, 0, days: Set(Weekday.allCases), skip: date(2026, 9, 21, 7, 0))
        let now = date(2026, 9, 21, 8, 0)
        XCTAssertEqual(next(a, now), date(2026, 9, 22, 7, 0))
        XCTAssertNil(NextFireCalculator.activeSkip(alarm: a, after: now, calendar: calendar()))
    }

    func testSkipStillActiveJustBeforeSkippedOccurrence() {
        let a = alarm(7, 0, days: Set(Weekday.allCases), skip: date(2026, 9, 21, 7, 0))
        XCTAssertEqual(next(a, date(2026, 9, 21, 6, 59)), date(2026, 9, 22, 7, 0))
    }

    func testSkipOnSingleDayAlarmWrapsToFollowingWeek() {
        let a = alarm(7, 0, days: [.monday], skip: date(2026, 9, 21, 7, 0))
        XCTAssertEqual(next(a, date(2026, 9, 20, 12, 0)), date(2026, 9, 28, 7, 0))
    }

    func testSkipOfOverrideOccurrence() {
        let a = alarm(7, 0, days: weekdays, overrides: [.friday: ClockTime(hour: 8, minute: 30)],
                      skip: date(2026, 9, 25, 8, 30))
        XCTAssertEqual(next(a, date(2026, 9, 24, 10, 0)), date(2026, 9, 28, 7, 0))
    }

    func testSkipFollowedByOverrideOccurrence() {
        let a = alarm(7, 0, days: weekdays, overrides: [.friday: ClockTime(hour: 8, minute: 30)],
                      skip: date(2026, 9, 24, 7, 0))
        XCTAssertEqual(next(a, date(2026, 9, 23, 10, 0)), date(2026, 9, 25, 8, 30))
    }

    func testSkipBecomesStaleWhenOverrideMovesTheOccurrence() {
        // Skipped Fri 7:00, then the user gave Friday its own 8:30 time.
        let a = alarm(7, 0, days: weekdays, overrides: [.friday: ClockTime(hour: 8, minute: 30)],
                      skip: date(2026, 9, 25, 7, 0))
        let now = date(2026, 9, 24, 10, 0)
        XCTAssertEqual(next(a, now), date(2026, 9, 25, 8, 30))
        XCTAssertNil(NextFireCalculator.activeSkip(alarm: a, after: now, calendar: calendar()))
    }

    func testSkipIgnoredForOneShot() {
        let a = alarm(7, 0, days: [], skip: date(2026, 9, 21, 7, 0))
        let now = date(2026, 9, 20, 10, 0)
        XCTAssertEqual(next(a, now), date(2026, 9, 21, 7, 0))
        XCTAssertNil(NextFireCalculator.activeSkip(alarm: a, after: now, calendar: calendar()))
    }

    func testActiveSkipNilWhenDisabled() {
        var a = alarm(7, 0, days: Set(Weekday.allCases), skip: date(2026, 9, 21, 7, 0))
        a.enabled = false
        XCTAssertNil(NextFireCalculator.activeSkip(alarm: a, after: date(2026, 9, 20, 10, 0), calendar: calendar()))
    }

    func testSkipToleratesSubSecondJSONDrift() {
        let a = alarm(7, 0, days: Set(Weekday.allCases), skip: date(2026, 9, 21, 7, 0).addingTimeInterval(0.0004))
        XCTAssertEqual(next(a, date(2026, 9, 20, 10, 0)), date(2026, 9, 22, 7, 0))
    }

    // MARK: DST (America/New_York: spring forward Sun 2026-03-08, fall back Sun 2026-11-01)

    func testOverrideInSpringForwardGapShiftsToValidInstant() {
        let ny = "America/New_York"
        let a = alarm(7, 0, days: [.sunday], overrides: [.sunday: ClockTime(hour: 2, minute: 30)])
        let fire = next(a, date(2026, 3, 7, 12, 0, zone: ny), zone: ny)
        let comps = calendar(ny).dateComponents([.month, .day, .hour, .minute], from: fire)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 8)
        XCTAssertEqual(comps.hour, 3)
        XCTAssertEqual(comps.minute, 30)
    }

    func testOverrideInFallBackRepeatedHourUsesFirstInstance() {
        let ny = "America/New_York"
        let a = alarm(7, 0, days: [.sunday], overrides: [.sunday: ClockTime(hour: 1, minute: 30)])
        let fire = next(a, date(2026, 10, 31, 12, 0, zone: ny), zone: ny)
        // First 1:30 is EDT (UTC-4) -> 05:30 UTC.
        XCTAssertEqual(fire, date(2026, 11, 1, 5, 30, zone: "UTC"))
    }

    func testSkipAcrossSpringForward() {
        let ny = "America/New_York"
        let a = alarm(7, 0, days: Set(Weekday.allCases), skip: date(2026, 3, 8, 7, 0, zone: ny))
        XCTAssertEqual(next(a, date(2026, 3, 7, 10, 0, zone: ny), zone: ny), date(2026, 3, 9, 7, 0, zone: ny))
    }

    func testSkipAcrossFallBackKeepsWallClockTime() {
        let ny = "America/New_York"
        let a = alarm(7, 0, days: Set(Weekday.allCases), skip: date(2026, 10, 31, 7, 0, zone: ny))
        let fire = next(a, date(2026, 10, 30, 10, 0, zone: ny), zone: ny)
        XCTAssertEqual(fire, date(2026, 11, 1, 7, 0, zone: ny))
        XCTAssertEqual(calendar(ny).component(.hour, from: fire), 7)
    }
}
