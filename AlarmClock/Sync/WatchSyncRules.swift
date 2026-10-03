import Foundation

/// What a watch op does to the phone's alarms, decided by `WatchSyncRules`.
enum WatchOpDecision: Equatable {
    /// Insert or replace the alarm (a `put`, after patching).
    case upsert(Alarm)
    case delete(id: String)
    case setEnabled(id: String, Bool)
    case skip(id: String)
    case unskip(id: String)
    case reject(Rejection)

    enum Rejection: Equatable {
        /// The phone has a newer edit of this alarm.
        case staleEdit
        /// The phone deleted this alarm after the watch edit was made.
        case deletedOnPhone
        /// `en`/`skip`/`unskip`/`del` on an alarm the phone doesn't have.
        case unknownAlarm
        /// A field out of range, or a new alarm without a time.
        case invalid
        /// An op kind this build doesn't know.
        case unsupported
    }
}

/// Conflict rules of the sync protocol (docs/garmin-sync-protocol.md):
/// per-alarm last writer wins, compared in whole seconds.
enum WatchSyncRules {
    static let maxLabelLength = 40

    /// - Parameter tombstones: alarm id -> when the phone deleted it.
    static func decide(_ op: WatchWire.Op, alarms: [Alarm], tombstones: [String: Date]) -> WatchOpDecision {
        guard let kind = op.kind else { return .reject(.unsupported) }
        let at = WatchWire.epoch(op.at)

        guard let existing = alarms.first(where: { $0.id == op.alarmId }) else {
            if let deletedAt = tombstones[op.alarmId], WatchWire.epoch(deletedAt) > at {
                return .reject(.deletedOnPhone)
            }
            guard kind == .put else { return .reject(.unknownAlarm) }
            return create(op)
        }

        if let updatedAt = existing.updatedAt, WatchWire.epoch(updatedAt) > at {
            return .reject(.staleEdit)
        }

        switch kind {
        case .put:
            guard let patched = patch(existing, with: op.fields) else { return .reject(.invalid) }
            return .upsert(patched)
        case .del:
            return .delete(id: existing.id)
        case .en:
            guard let enabled = op.enabled else { return .reject(.invalid) }
            return .setEnabled(id: existing.id, enabled)
        case .skip:
            return .skip(id: existing.id)
        case .unskip:
            return .unskip(id: existing.id)
        }
    }

    private static func create(_ op: WatchWire.Op) -> WatchOpDecision {
        guard let hour = op.fields.hour, let minute = op.fields.minute else { return .reject(.invalid) }
        let fresh = Alarm(id: op.alarmId, hour: hour, minute: minute)
        guard let alarm = patch(fresh, with: op.fields) else { return .reject(.invalid) }
        return .upsert(alarm)
    }

    /// The alarm with `fields` applied, or nil if any field is invalid.
    static func patch(_ alarm: Alarm, with fields: WatchWire.Fields) -> Alarm? {
        guard !fields.malformed else { return nil }
        var out = alarm
        if let hour = fields.hour {
            guard (0...23).contains(hour) else { return nil }
            out.hour = hour
        }
        if let minute = fields.minute {
            guard (0...59).contains(minute) else { return nil }
            out.minute = minute
        }
        if let days = fields.repeatDays {
            out.repeatDays = days
        }
        if let label = fields.label {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            out.label = String(trimmed.prefix(maxLabelLength))
        }
        if let snoozeEnabled = fields.snoozeEnabled {
            out.snoozeEnabled = snoozeEnabled
        }
        if let minutes = fields.snoozeMinutes {
            guard (1...30).contains(minutes) else { return nil }
            out.snoozeMinutes = minutes
        }
        return out
    }
}

/// Phone-side sync bookkeeping, persisted next to alarms.json.
struct WatchSyncState: Codable, Equatable {
    /// Alarm id -> when it disappeared from the phone's list.
    var tombstones: [String: Date] = [:]

    static let tombstoneLifetime: TimeInterval = 30 * 24 * 3600

    /// Records ids that were in `previous` but not in `current` as deleted
    /// at `now`, forgets ids that came back, and drops expired tombstones.
    mutating func recordDeletions(previous: [String], current: [String], now: Date) {
        let currentSet = Set(current)
        for id in previous where !currentSet.contains(id) {
            tombstones[id] = now
        }
        for id in currentSet {
            tombstones.removeValue(forKey: id)
        }
        tombstones = tombstones.filter { now.timeIntervalSince($0.value) < Self.tombstoneLifetime }
    }

    static func load(from url: URL) -> WatchSyncState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(WatchSyncState.self, from: data)
        else { return WatchSyncState() }
        return state
    }

    func save(to url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
