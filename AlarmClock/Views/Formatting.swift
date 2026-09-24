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
}
