import Foundation
import ActivityKit

/// Live Activity shown while an alarm is snoozed: "Ringing again at 7:09"
/// with a live countdown. Static attributes identify the alarm; the content
/// state carries the snooze window (re-snoozing updates it in place).
struct SnoozeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var snoozedAt: Date
        var ringsAt: Date
    }

    var alarmId: String
    var label: String
}
