import Foundation

/// Computes the next instant an alarm should fire.
///
/// One-shot alarms (empty `repeatDays`) fire at the next occurrence of their
/// wall-clock time strictly after `after`. Repeating alarms fire on the nearest
/// enabled weekday. Wall-clock times that fall in a DST gap resolve to a shifted
/// valid instant (via `Calendar.date(bySettingHour:...)` which never lands on an
/// invalid local time).
enum NextFireCalculator {

    /// The next `Date` strictly after `after` at which `alarm` should fire in `calendar`'s timezone.
    static func nextFire(alarm: Alarm, after: Date, calendar: Calendar) -> Date {
        let startOfAfterDay = calendar.startOfDay(for: after)

        // offset 0..8 covers "today is the only repeat day but the time already passed"
        for offset in 0...8 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: startOfAfterDay) else {
                continue
            }
            if !alarm.repeatDays.isEmpty {
                let weekday = isoWeekday(of: dayStart, calendar: calendar)
                if !alarm.repeatDays.contains(weekday) { continue }
            }
            // Match the wall-clock time on this specific date. Searching from just
            // before the day's start with `.nextTimePreservingSmallerComponents`
            // resolves DST gaps by shifting forward to a valid instant (e.g. a
            // 02:30 alarm on a spring-forward night lands at 03:30).
            var match = calendar.dateComponents([.year, .month, .day], from: dayStart)
            match.hour = alarm.hour
            match.minute = alarm.minute
            match.second = 0
            guard let candidate = calendar.nextDate(
                after: dayStart.addingTimeInterval(-1),
                matching: match,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                repeatedTimePolicy: .first,
                direction: .forward
            ) else {
                continue
            }
            if candidate > after {
                return candidate
            }
        }
        // Unreachable in practice: a valid fire exists within 8 days.
        fatalError("no fire time within 8 days for alarm \(alarm.id)")
    }

    /// Maps a date to the app's ISO `Weekday` (Monday = 1 ... Sunday = 7),
    /// independent of `Calendar`'s Sunday-based `.weekday` component.
    private static func isoWeekday(of date: Date, calendar: Calendar) -> Weekday {
        let component = calendar.component(.weekday, from: date) // 1 = Sunday ... 7 = Saturday
        // Convert: Sunday(1) -> 7, Monday(2) -> 1, ... Saturday(7) -> 6
        let iso = (component + 5) % 7 + 1
        return Weekday(rawValue: iso)!
    }
}
