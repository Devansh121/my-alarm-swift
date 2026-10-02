import Foundation

/// Computes the next instant an alarm should fire.
///
/// One-shot alarms (empty `repeatDays`) fire at the next occurrence of their
/// wall-clock time strictly after `after`. Repeating alarms fire on the nearest
/// enabled weekday, at that day's override time if one is set. Wall-clock
/// times that fall in a DST gap resolve to a shifted valid instant (via `Calendar.date(bySettingHour:...)` which never lands on an
/// invalid local time).
enum NextFireCalculator {

    /// The next `Date` strictly after `after` at which `alarm` should fire in
    /// `calendar`'s timezone, honoring a pending "skip next".
    ///
    /// A skip only applies while `skippedFireDate` is still the alarm's very
    /// next occurrence; once that instant passes (or the schedule changes so it
    /// is no longer an occurrence) it is ignored, so the alarm resumes without
    /// any user action.
    static func nextFire(alarm: Alarm, after: Date, calendar: Calendar) -> Date {
        let next = nextOccurrence(alarm: alarm, after: after, calendar: calendar)
        guard let skipped = alarm.skippedFireDate,
              !alarm.repeatDays.isEmpty,
              isSameInstant(skipped, next) else { return next }
        return nextOccurrence(alarm: alarm, after: next, calendar: calendar)
    }

    /// The skip that is still in effect at `after`, or nil if there is none or
    /// it is stale (already passed, alarm disabled/one-shot, or schedule changed).
    static func activeSkip(alarm: Alarm, after: Date, calendar: Calendar) -> Date? {
        guard let skipped = alarm.skippedFireDate,
              alarm.enabled,
              !alarm.repeatDays.isEmpty else { return nil }
        let next = nextOccurrence(alarm: alarm, after: after, calendar: calendar)
        return isSameInstant(skipped, next) ? next : nil
    }

    /// The next scheduled occurrence strictly after `after`, ignoring any skip.
    static func nextOccurrence(alarm: Alarm, after: Date, calendar: Calendar) -> Date {
        let startOfAfterDay = calendar.startOfDay(for: after)

        // offset 0..8 covers "today is the only repeat day but the time already passed"
        for offset in 0...8 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: startOfAfterDay) else {
                continue
            }
            let weekday = isoWeekday(of: dayStart, calendar: calendar)
            if !alarm.repeatDays.isEmpty, !alarm.repeatDays.contains(weekday) {
                continue
            }
            let time = alarm.time(on: weekday)
            // Match the wall-clock time on this specific date. Searching from just
            // before the day's start with `.nextTimePreservingSmallerComponents`
            // resolves DST gaps by shifting forward to a valid instant (e.g. a
            // 02:30 alarm on a spring-forward night lands at 03:30).
            var match = calendar.dateComponents([.year, .month, .day], from: dayStart)
            match.hour = time.hour
            match.minute = time.minute
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

    /// Persisted dates round-trip through JSON as Doubles; compare with a
    /// sub-second tolerance rather than bit-exact equality.
    private static func isSameInstant(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 1
    }

    /// Maps a date to the app's ISO `Weekday` (Monday = 1 ... Sunday = 7),
    /// independent of `Calendar`'s Sunday-based `.weekday` component.
    static func isoWeekday(of date: Date, calendar: Calendar) -> Weekday {
        let component = calendar.component(.weekday, from: date) // 1 = Sunday ... 7 = Saturday
        // Convert: Sunday(1) -> 7, Monday(2) -> 1, ... Saturday(7) -> 6
        let iso = (component + 5) % 7 + 1
        return Weekday(rawValue: iso)!
    }
}

extension Alarm {
    /// The wall-clock time this alarm rings on `weekday`: the per-day override
    /// for repeating alarms when set, otherwise the alarm's default time.
    /// One-shot alarms always use the default time.
    func time(on weekday: Weekday) -> ClockTime {
        if !repeatDays.isEmpty, repeatDays.contains(weekday), let override = timeOverrides[weekday] {
            return override
        }
        return ClockTime(hour: hour, minute: minute)
    }

    /// Overrides restricted to selected repeat days and differing from the
    /// default time — what is worth persisting/showing.
    var effectiveTimeOverrides: [Weekday: ClockTime] {
        guard !repeatDays.isEmpty else { return [:] }
        let base = ClockTime(hour: hour, minute: minute)
        return timeOverrides.filter { repeatDays.contains($0.key) && $0.value != base }
    }
}
