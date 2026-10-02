import Foundation

/// Pure time math behind the add/edit screen's sleep hints:
/// "Rings in 7h 30m", the short-sleep warning, and "Wake me in…" shortcuts.
enum SleepMath {

    /// Under this many minutes until the alarm, the edit screen warns gently.
    static let shortSleepThresholdMinutes = 6 * 60

    /// "Wake me in" shortcut durations offered when adding an alarm.
    static let wakeShortcuts: [(title: String, duration: TimeInterval)] = [
        ("6h", 6 * 3600),
        ("7h 30m", 7.5 * 3600),
        ("9h", 9 * 3600),
    ]

    /// Whole minutes from `now` until `fire`, rounded UP so a partial minute
    /// counts (an alarm 59s away is "1m", never "0m"). Never negative.
    static func minutesUntil(_ fire: Date, from now: Date) -> Int {
        let seconds = fire.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds / 60).rounded(.up))
    }

    /// "7h 30m", "6h", "45m", "0m".
    static func durationText(minutes: Int) -> String {
        let total = max(minutes, 0)
        let h = total / 60
        let m = total % 60
        switch (h, m) {
        case (0, _): return "\(m)m"
        case (_, 0): return "\(h)h"
        default: return "\(h)h \(m)m"
        }
    }

    static func isShortSleep(minutes: Int) -> Bool {
        minutes < shortSleepThresholdMinutes
    }

    /// "Rings in 7h 30m".
    static func ringsInText(minutes: Int) -> String {
        "Rings in \(durationText(minutes: minutes))"
    }

    /// "Only 5h 40m of sleep if you go to bed now", or nil when there's enough time.
    static func shortSleepWarning(minutes: Int) -> String? {
        guard isShortSleep(minutes: minutes) else { return nil }
        return "Only \(durationText(minutes: minutes)) of sleep if you go to bed now"
    }

    /// Wall-clock time `duration` of real elapsed time after `now`, rounded to
    /// the nearest minute, in `calendar`'s zone. Uses absolute time, so across
    /// a DST change "in 6h" really is six hours of sleep.
    static func wakeTime(from now: Date, adding duration: TimeInterval, calendar: Calendar) -> ClockTime {
        let target = now.addingTimeInterval(duration)
        let rounded = Date(timeIntervalSinceReferenceDate:
            (target.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        let comps = calendar.dateComponents([.hour, .minute], from: rounded)
        return ClockTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
    }
}
