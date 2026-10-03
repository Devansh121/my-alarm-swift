import Foundation
import ActivityKit

/// ActivityKit-backed `SnoozeActivityControl`. Activities are looked up from
/// `Activity.activities` rather than tracked in memory, so ones left over from
/// a previous process (app killed while snoozed) are found and ended too.
///
/// Each activity's `staleDate` is the re-ring time: if the app is not running
/// when the snooze elapses, the system marks it stale and the view switches to
/// a static "Snooze over" state instead of a countdown stuck at zero, and the
/// next launch or return to foreground ends it (`endExpired`).
final class LiveSnoozeActivityController: SnoozeActivityControl {

    func start(alarmId: String, label: String, snoozedAt: Date, ringsAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(
            state: SnoozeActivityAttributes.ContentState(snoozedAt: snoozedAt, ringsAt: ringsAt),
            staleDate: ringsAt
        )

        let existing = activities(for: alarmId)
        if let current = existing.first {
            // Re-snoozed: update in place rather than stacking a second activity.
            Task { await current.update(content) }
            for extra in existing.dropFirst() { endNow(extra) }
            return
        }

        let trimmed = label.trimmingCharacters(in: .whitespaces)
        let attributes = SnoozeActivityAttributes(alarmId: alarmId, label: trimmed.isEmpty ? "Alarm" : trimmed)
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            // e.g. the app is in the background (iOS only lets apps start
            // Live Activities from the foreground) or the user disabled them.
            NSLog("alarm: snooze live activity not started \(error)")
        }
    }

    func end(alarmId: String) {
        activities(for: alarmId).forEach(endNow)
    }

    /// Ends activities whose snooze already elapsed — leftovers from a process
    /// that was killed before the re-ring could end them. Run at launch.
    func endExpired(now: Date = Date()) {
        Activity<SnoozeActivityAttributes>.activities
            .filter { $0.content.state.ringsAt <= now }
            .forEach(endNow)
    }

    private func activities(for alarmId: String) -> [Activity<SnoozeActivityAttributes>] {
        Activity<SnoozeActivityAttributes>.activities.filter { $0.attributes.alarmId == alarmId }
    }

    private func endNow(_ activity: Activity<SnoozeActivityAttributes>) {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
