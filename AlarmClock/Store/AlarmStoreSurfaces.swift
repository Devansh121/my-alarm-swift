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
    /// End the activity for one alarm, if any.
    func end(alarmId: String)
    /// End every activity except those for alarms that still have a pending
    /// snooze. Called after each reschedule so stops, deletes, disables and
    /// edits can never leave a stale activity behind.
    func endAll(except alarmIds: Set<String>)
}

struct NoopWidgetSnapshotPublisher: WidgetSnapshotPublishing {
    func publish(_ snapshot: WidgetSnapshot) {}
}

struct NoopSnoozeActivity: SnoozeActivityControl {
    func start(alarmId: String, label: String, snoozedAt: Date, ringsAt: Date) {}
    func end(alarmId: String) {}
    func endAll(except alarmIds: Set<String>) {}
}
