import XCTest
@testable import AlarmClock

final class FormattingTests: XCTestCase {

    // MARK: - 12-hour time strings

    func testMidnightIsTwelveAM() {
        XCTAssertEqual(AlarmFormatting.timeString(hour: 0, minute: 0), "12:00 AM")
    }

    func testNoonIsTwelvePM() {
        XCTAssertEqual(AlarmFormatting.timeString(hour: 12, minute: 0), "12:00 PM")
    }

    func testMorningTime() {
        XCTAssertEqual(AlarmFormatting.timeString(hour: 6, minute: 5), "6:05 AM")
    }

    func testAfternoonTime() {
        XCTAssertEqual(AlarmFormatting.timeString(hour: 13, minute: 30), "1:30 PM")
    }

    func testLateEvening() {
        XCTAssertEqual(AlarmFormatting.timeString(hour: 23, minute: 59), "11:59 PM")
    }

    func testJustBeforeNoon() {
        XCTAssertEqual(AlarmFormatting.timeString(hour: 11, minute: 45), "11:45 AM")
    }

    func testComponentsSplitPeriod() {
        let c = AlarmFormatting.timeComponents(hour: 0, minute: 0)
        XCTAssertEqual(c.time, "12:00")
        XCTAssertEqual(c.period, "AM")
    }

    func testOutOfRangeIsNormalized() {
        XCTAssertEqual(AlarmFormatting.timeString(hour: 25, minute: 61), "1:01 AM")
    }

    // MARK: - Repeat summaries

    func testEmptyRepeatIsBlank() {
        XCTAssertEqual(AlarmFormatting.repeatSummary([]), "")
    }

    func testEveryDay() {
        XCTAssertEqual(AlarmFormatting.repeatSummary(Set(Weekday.allCases)), "Every day")
    }

    func testWeekdays() {
        XCTAssertEqual(
            AlarmFormatting.repeatSummary([.monday, .tuesday, .wednesday, .thursday, .friday]),
            "Weekdays"
        )
    }

    func testWeekends() {
        XCTAssertEqual(AlarmFormatting.repeatSummary([.saturday, .sunday]), "Weekends")
    }

    func testArbitraryDaysAreShortNamesInOrder() {
        XCTAssertEqual(AlarmFormatting.repeatSummary([.friday, .monday]), "Mon Fri")
    }

    func testArbitraryDaysThree() {
        XCTAssertEqual(
            AlarmFormatting.repeatSummary([.sunday, .wednesday, .monday]),
            "Mon Wed Sun"
        )
    }

    // MARK: - Secondary line

    func testSecondaryLineLabelAndSummary() {
        XCTAssertEqual(
            AlarmFormatting.secondaryLine(label: "Work", days: [.monday, .tuesday, .wednesday, .thursday, .friday]),
            "Work, Weekdays"
        )
    }

    func testSecondaryLineLabelOnly() {
        XCTAssertEqual(AlarmFormatting.secondaryLine(label: "Work", days: []), "Work")
    }

    func testSecondaryLineSummaryOnly() {
        XCTAssertEqual(
            AlarmFormatting.secondaryLine(label: "  ", days: Set(Weekday.allCases)),
            "Every day"
        )
    }

    func testSecondaryLineEmpty() {
        XCTAssertEqual(AlarmFormatting.secondaryLine(label: "", days: []), "")
    }

    // MARK: - Tone display names

    func testToneRandom() {
        XCTAssertEqual(AlarmFormatting.toneDisplayName(.random), "Random")
    }

    func testTonePinned() {
        XCTAssertEqual(AlarmFormatting.toneDisplayName(.pinned(toneId: "chimes")), "Chimes")
    }

    func testTonePinnedUnknownFallsBackToRandom() {
        XCTAssertEqual(AlarmFormatting.toneDisplayName(.pinned(toneId: "nope")), "Random")
    }
}
