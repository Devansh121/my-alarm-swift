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
///   - snooze bursts use `<alarmId>#snooze<k>` for every index, so a pending
///     snooze and the alarm's regular next fire never replace each other.
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
            let identifier = Self.identifier(alarmId: request.alarmId, index: k, snooze: request.isSnooze)
            let fireAt = request.fireAt.addingTimeInterval(TimeInterval(k) * interval)
            return (identifier: identifier, fireAt: fireAt)
        }
    }

    /// Strips the `#<k>` burst suffix, returning the underlying alarmId.
    static func alarmId(fromNotificationIdentifier identifier: String) -> String {
        guard let hashIndex = identifier.firstIndex(of: "#") else { return identifier }
        return String(identifier[..<hashIndex])
    }

    /// The burst position encoded in a notification identifier (0 for the
    /// bare primary id, k for `<alarmId>#<k>`).
    static func chimeIndex(fromNotificationIdentifier identifier: String) -> Int {
        guard let hashIndex = identifier.firstIndex(of: "#") else { return 0 }
        return max(Int(identifier[identifier.index(after: hashIndex)...]) ?? 0, 0)
    }

    /// When the burst started, given one chime's identifier and delivery
    /// time — i.e. when the alarm actually went off.
    static func burstStart(
        notificationIdentifier identifier: String,
        deliveredAt: Date,
        interval: TimeInterval = 30
    ) -> Date {
        let k = chimeIndex(fromNotificationIdentifier: identifier)
        return deliveredAt.addingTimeInterval(-TimeInterval(k) * interval)
    }

    /// Every notification identifier a burst of `chimes` produces for an alarm.
    static func allIdentifiers(alarmId: String, chimes: Int = 8, snooze: Bool = false) -> [String] {
        guard chimes > 0 else { return [] }
        return (0..<chimes).map { k in
            identifier(alarmId: alarmId, index: k, snooze: snooze)
        }
    }

    private static func identifier(alarmId: String, index k: Int, snooze: Bool) -> String {
        if snooze { return "\(alarmId)#snooze\(k)" }
        return k == 0 ? alarmId : "\(alarmId)#\(k)"
    }
}
