import XCTest
@testable import AlarmClock

final class SleepMathTests: XCTestCase {

    private func calendar(_ zone: String = "Asia/Kolkata") -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int = 0,
                      zone: String = "Asia/Kolkata") -> Date {
        calendar(zone).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    // MARK: minutesUntil

    func testMinutesUntilExact() {
        let now = date(2026, 9, 20, 22, 0)
        XCTAssertEqual(SleepMath.minutesUntil(date(2026, 9, 21, 5, 30), from: now), 450)
    }

    func testMinutesUntilRoundsPartialMinuteUp() {
        let now = date(2026, 9, 20, 22, 0, 30)
        XCTAssertEqual(SleepMath.minutesUntil(date(2026, 9, 20, 22, 1), from: now), 1)
        XCTAssertEqual(SleepMath.minutesUntil(date(2026, 9, 21, 4, 0), from: now), 360)
    }

    func testMinutesUntilNeverNegative() {
        let now = date(2026, 9, 20, 22, 0)
        XCTAssertEqual(SleepMath.minutesUntil(date(2026, 9, 20, 21, 0), from: now), 0)
        XCTAssertEqual(SleepMath.minutesUntil(now, from: now), 0)
    }

    func testMinutesUntilAcrossSpringForwardIsRealElapsedTime() {
        // NY 2026-03-08: 02:00 -> 03:00. 23:00 -> 07:00 wall clock is only 7h real.
        let ny = "America/New_York"
        let now = date(2026, 3, 7, 23, 0, zone: ny)
        XCTAssertEqual(SleepMath.minutesUntil(date(2026, 3, 8, 7, 0, zone: ny), from: now), 7 * 60)
    }

    func testMinutesUntilAcrossFallBackIsRealElapsedTime() {
        // NY 2026-11-01: 02:00 -> 01:00. 23:00 -> 07:00 wall clock is 9h real.
        let ny = "America/New_York"
        let now = date(2026, 10, 31, 23, 0, zone: ny)
        XCTAssertEqual(SleepMath.minutesUntil(date(2026, 11, 1, 7, 0, zone: ny), from: now), 9 * 60)
    }

    // MARK: Text

    func testDurationText() {
        XCTAssertEqual(SleepMath.durationText(minutes: 0), "0m")
        XCTAssertEqual(SleepMath.durationText(minutes: 45), "45m")
        XCTAssertEqual(SleepMath.durationText(minutes: 360), "6h")
        XCTAssertEqual(SleepMath.durationText(minutes: 450), "7h 30m")
        XCTAssertEqual(SleepMath.durationText(minutes: 23 * 60 + 59), "23h 59m")
        XCTAssertEqual(SleepMath.durationText(minutes: -5), "0m")
    }

    func testRingsInText() {
        XCTAssertEqual(SleepMath.ringsInText(minutes: 450), "Rings in 7h 30m")
    }

    func testShortSleepWarningThreshold() {
        XCTAssertEqual(SleepMath.shortSleepWarning(minutes: 340), "Only 5h 40m of sleep if you go to bed now")
        XCTAssertEqual(SleepMath.shortSleepWarning(minutes: 359), "Only 5h 59m of sleep if you go to bed now")
        XCTAssertNil(SleepMath.shortSleepWarning(minutes: 360))
        XCTAssertNil(SleepMath.shortSleepWarning(minutes: 600))
        XCTAssertTrue(SleepMath.isShortSleep(minutes: 1))
    }

    // MARK: wakeTime

    func testWakeTimeAddsDuration() {
        let now = date(2026, 9, 20, 22, 15)
        XCTAssertEqual(SleepMath.wakeTime(from: now, adding: 7.5 * 3600, calendar: calendar()),
                       ClockTime(hour: 5, minute: 45))
    }

    func testWakeTimeRoundsToNearestMinute() {
        XCTAssertEqual(SleepMath.wakeTime(from: date(2026, 9, 20, 22, 0, 29), adding: 6 * 3600, calendar: calendar()),
                       ClockTime(hour: 4, minute: 0))
        XCTAssertEqual(SleepMath.wakeTime(from: date(2026, 9, 20, 22, 0, 31), adding: 6 * 3600, calendar: calendar()),
                       ClockTime(hour: 4, minute: 1))
    }

    func testWakeTimeWrapsPastMidnight() {
        let now = date(2026, 9, 20, 23, 50)
        XCTAssertEqual(SleepMath.wakeTime(from: now, adding: 9 * 3600, calendar: calendar()),
                       ClockTime(hour: 8, minute: 50))
    }

    func testWakeTimeAcrossSpringForwardIsRealSleep() {
        // 23:00 + 6h real on spring-forward night lands at 06:00 EDT (wall clock jumped).
        let ny = "America/New_York"
        let now = date(2026, 3, 7, 23, 0, zone: ny)
        XCTAssertEqual(SleepMath.wakeTime(from: now, adding: 6 * 3600, calendar: calendar(ny)),
                       ClockTime(hour: 6, minute: 0))
    }

    func testWakeTimeAcrossFallBackIsRealSleep() {
        let ny = "America/New_York"
        let now = date(2026, 10, 31, 23, 0, zone: ny)
        XCTAssertEqual(SleepMath.wakeTime(from: now, adding: 6 * 3600, calendar: calendar(ny)),
                       ClockTime(hour: 4, minute: 0))
    }

    func testShortcutsAreSixSevenThirtyNine() {
        XCTAssertEqual(SleepMath.wakeShortcuts.map(\.title), ["6h", "7h 30m", "9h"])
        XCTAssertEqual(SleepMath.wakeShortcuts.map(\.duration), [21_600, 27_000, 32_400])
    }

    /// A shortcut's wake time, scheduled as a one-shot, rings ~duration later
    /// and so never trips the short-sleep warning for the 6h shortcut.
    func testSixHourShortcutDoesNotWarn() {
        let cal = calendar()
        for second in [0, 20, 29, 31, 59] {
            let now = date(2026, 9, 20, 22, 0, second)
            let wake = SleepMath.wakeTime(from: now, adding: 6 * 3600, calendar: cal)
            let alarm = Alarm(hour: wake.hour, minute: wake.minute)
            let fire = NextFireCalculator.nextFire(alarm: alarm, after: now, calendar: cal)
            XCTAssertNil(SleepMath.shortSleepWarning(minutes: SleepMath.minutesUntil(fire, from: now)),
                         "second \(second)")
        }
    }
}
