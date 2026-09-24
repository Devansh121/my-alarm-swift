import Foundation

/// Pure planning logic for firing an alarm as a *burst* of notifications.
///
/// iOS silences a playing notification sound when the user presses volume or
/// power on the lock screen — behavior we cannot intercept. To keep waking a
/// sleeper we schedule several identical chimes spaced `interval` apart, so
/// silencing one still lets the next land until the user explicitly snoozes or
/// stops (which cancels the whole burst).
///
/// Identifier scheme:
///   - index 0 uses the bare `<alarmId>` (so existing cancel-by-id still hits
///     the primary chime),
///   - index k (1..chimes-1) uses `<alarmId>#<k>`.
/// alarmIds are UUID strings, so `#` never occurs except as our separator.
struct BurstPlan {

    /// Builds the ordered list of chimes for a fire request.
    static func plan(
        for request: FireRequest,
        chimes: Int = 8,
        interval: TimeInterval = 30
    ) -> [(identifier: String, fireAt: Date)] {
        guard chimes > 0 else { return [] }
        return (0..<chimes).map { k in
            let identifier = k == 0 ? request.alarmId : "\(request.alarmId)#\(k)"
            let fireAt = request.fireAt.addingTimeInterval(TimeInterval(k) * interval)
            return (identifier: identifier, fireAt: fireAt)
        }
    }

    /// Strips the `#<k>` burst suffix, returning the underlying alarmId.
    static func alarmId(fromNotificationIdentifier identifier: String) -> String {
        guard let hashIndex = identifier.firstIndex(of: "#") else { return identifier }
        return String(identifier[..<hashIndex])
    }

    /// Every notification identifier a burst of `chimes` produces for an alarm.
    static func allIdentifiers(alarmId: String, chimes: Int = 8) -> [String] {
        guard chimes > 0 else { return [] }
        return (0..<chimes).map { k in
            k == 0 ? alarmId : "\(alarmId)#\(k)"
        }
    }
}
