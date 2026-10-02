import Foundation

/// System surfaces outside the app UI that mirror the store's state: the
/// next-alarm widgets and the snooze Live Activity. Kept behind protocols with
/// no-op defaults so `AlarmStore` stays unit-testable; the app installs the
/// real implementations at launch (see `AppSurfaces`).

/// Receives a fresh snapshot after every reschedule.
protocol WidgetSnapshotPublishing {
    func publish(_ snapshot: WidgetSnapshot)
}

/// Starts/ends the "snoozed" Live Activity.
protocol SnoozeActivityControl {
    /// Start (or update in place) the activity for a snoozed alarm.
    func start(alarmId: String, label: String, snoozedAt: Date, ringsAt: Date)
    /// End the activity for one alarm, if any. Called when the snoozed alarm
    /// re-fires, is stopped (ringing screen, notification, Live Activity),
    /// deleted or disabled. Deliberately NOT called on every reschedule, so a
    /// snooze that survives `refreshAndReschedule` keeps its activity.
    func end(alarmId: String)
    /// End every activity whose re-ring time has passed. A snooze that
    /// re-fires while the app is backgrounded can't end its own activity, so
    /// this runs on each reschedule (including every return to foreground).
    func endExpired(now: Date)
}

struct NoopWidgetSnapshotPublisher: WidgetSnapshotPublishing {
    func publish(_ snapshot: WidgetSnapshot) {}
}

struct NoopSnoozeActivity: SnoozeActivityControl {
    func start(alarmId: String, label: String, snoozedAt: Date, ringsAt: Date) {}
    func end(alarmId: String) {}
    func endExpired(now: Date) {}
}
