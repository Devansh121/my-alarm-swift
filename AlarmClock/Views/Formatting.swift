import Foundation

/// Pure formatting helpers shared across the alarm UI.
/// Kept free of any UIKit/SwiftUI dependency so they are trivially unit-testable.
enum AlarmFormatting {

    /// Splits a 24h hour/minute into a 12-hour clock string plus its AM/PM suffix.
    /// Midnight -> "12:00" / "AM", noon -> "12:00" / "PM".
    static func timeComponents(hour: Int, minute: Int) -> (time: String, period: String) {
        let normalizedHour = ((hour % 24) + 24) % 24
        let normalizedMinute = ((minute % 60) + 60) % 60
        let period = normalizedHour < 12 ? "AM" : "PM"
        var twelve = normalizedHour % 12
        if twelve == 0 { twelve = 12 }
        let time = String(format: "%d:%02d", twelve, normalizedMinute)
        return (time, period)
    }

    /// Convenience joined 12-hour string, e.g. "6:05 AM".
    static func timeString(hour: Int, minute: Int) -> String {
        let c = timeComponents(hour: hour, minute: minute)
        return "\(c.time) \(c.period)"
    }

    /// Clock-style repeat summary for a set of weekdays.
    /// - empty -> "" (caller omits the segment, like Clock which shows nothing)
    /// - all 7 -> "Every day"
    /// - Mon...Fri -> "Weekdays"
    /// - Sat+Sun -> "Weekends"
    /// - otherwise -> short names in ISO order, space-joined, e.g. "Mon Fri".
    static func repeatSummary(_ days: Set<Weekday>) -> String {
        if days.isEmpty { return "" }
        if days.count == 7 { return "Every day" }

        let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let weekends: Set<Weekday> = [.saturday, .sunday]
        if days == weekdays { return "Weekdays" }
        if days == weekends { return "Weekends" }

        return days.sorted().map(\.shortName).joined(separator: " ")
    }

    /// Secondary row line: joins a non-empty label with the repeat summary, Clock-style.
    /// "Work" + "Weekdays" -> "Work, Weekdays"; "Work" + "" -> "Work"; "" + "Every day" -> "Every day".
    static func secondaryLine(label: String, days: Set<Weekday>) -> String {
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let summary = repeatSummary(days)
        switch (trimmedLabel.isEmpty, summary.isEmpty) {
        case (false, false): return "\(trimmedLabel), \(summary)"
        case (false, true): return trimmedLabel
        case (true, false): return summary
        case (true, true): return ""
        }
    }

    /// Display name for a tone selection, resolving pinned ids against the catalog.
    static func toneDisplayName(_ selection: ToneSelection) -> String {
        switch selection {
        case .random:
            return "Random"
        case .pinned(let toneId):
            return bundledTones.first { $0.id == toneId }?.displayName ?? "Random"
        }
    }

    // MARK: - Per-day times

    /// Summarizes per-day overrides, grouping days that share a time, in ISO
    /// order of each group's first day: e.g. "Fri 8:30 AM" or
    /// "Sat Sun 9:00 AM, Wed 6:15 AM". "" when there are none.
    static func overridesSummary(_ overrides: [Weekday: ClockTime]) -> String {
        guard !overrides.isEmpty else { return "" }
        var groups: [(time: ClockTime, days: [Weekday])] = []
        for day in overrides.keys.sorted() {
            let time = overrides[day]!
            if let i = groups.firstIndex(where: { $0.time == time }) {
                groups[i].days.append(day)
            } else {
                groups.append((time, [day]))
            }
        }
        return groups.map { group in
            let days = group.days.map(\.shortName).joined(separator: " ")
            return "\(days) \(timeString(hour: group.time.hour, minute: group.time.minute))"
        }.joined(separator: ", ")
    }

    /// Row secondary line including per-day overrides:
    /// "Work, Weekdays · Fri 8:30 AM". Falls back to `secondaryLine(label:days:)`.
    static func secondaryLine(label: String, days: Set<Weekday>, overrides: [Weekday: ClockTime]) -> String {
        let base = secondaryLine(label: label, days: days)
        let extra = overridesSummary(overrides.filter { days.contains($0.key) })
        switch (base.isEmpty, extra.isEmpty) {
        case (_, true): return base
        case (true, false): return extra
        case (false, false): return "\(base) · \(extra)"
        }
    }

    // MARK: - Skip next

    /// "Skipping Tue 7:00 AM" for a skipped occurrence, in `calendar`'s zone.
    static func skipSummary(_ skipped: Date, calendar: Calendar) -> String {
        let day = NextFireCalculator.isoWeekday(of: skipped, calendar: calendar)
        let comps = calendar.dateComponents([.hour, .minute], from: skipped)
        return "Skipping \(day.shortName) \(timeString(hour: comps.hour ?? 0, minute: comps.minute ?? 0))"
    }
}
