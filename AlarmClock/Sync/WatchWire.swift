import Foundation

/// Wire format of the Garmin watch sync protocol (docs/garmin-sync-protocol.md).
/// Messages are plain dictionaries so the Connect IQ SDK can convert them to
/// Monkey C values; nil values are left out rather than sent as null.
enum WatchWire {
    static let version = 1

    /// Fields a watch `put` may set. Everything else (tone, per-day times,
    /// ramp, vibrate-first) is phone-only and survives watch edits untouched.
    struct Fields: Equatable {
        var hour: Int?
        var minute: Int?
        var repeatDays: Set<Weekday>?
        var label: String?
        var snoozeEnabled: Bool?
        var snoozeMinutes: Int?
        /// True when a field was present but unusable (wrong type, day 9, …),
        /// which rejects the whole `put`.
        var malformed = false
    }

    /// One watch edit, as sent in a `sync` message.
    struct Op: Equatable {
        enum Kind: String {
            case put, del, en, skip, unskip
        }

        let oid: String
        /// Nil for an op kind this build doesn't know; it is acked and ignored.
        let kind: Kind?
        let alarmId: String
        /// When the user made the edit on the watch.
        let at: Date
        var fields = Fields()
        /// `en` only.
        var enabled: Bool?
    }

    // MARK: - Phone → watch

    static func snapshot(alarms: [Alarm], acked: [String], now: Date) -> [String: Any] {
        [
            "t": "snap",
            "v": version,
            "ts": epoch(now),
            "ack": acked,
            "alarms": alarms.map(encode),
        ]
    }

    static func encode(_ alarm: Alarm) -> [String: Any] {
        var out: [String: Any] = [
            "id": alarm.id,
            "h": alarm.hour,
            "m": alarm.minute,
            "d": alarm.repeatDays.map(\.rawValue).sorted(),
            "l": alarm.label,
            "e": alarm.enabled,
            "sn": alarm.snoozeEnabled,
            "sm": alarm.snoozeMinutes,
            "u": alarm.updatedAt.map(epoch) ?? 0,
        ]
        if let next = alarm.nextFireDate { out["nf"] = epoch(next) }
        if let skipped = alarm.skippedFireDate { out["sk"] = epoch(skipped) }
        if let snoozed = alarm.snoozedUntil { out["sz"] = epoch(snoozed) }
        if !alarm.timeOverrides.isEmpty {
            var overrides: [String: [Int]] = [:]
            for (day, time) in alarm.timeOverrides {
                overrides[String(day.rawValue)] = [time.hour, time.minute]
            }
            out["ov"] = overrides
        }
        return out
    }

    // MARK: - Watch → phone

    /// The ops of a `sync` message, or nil when the message isn't a `sync`
    /// this build understands. Ops without an `oid` or alarm id can't be
    /// acked or applied and are dropped.
    static func decodeSync(_ message: Any) -> [Op]? {
        guard let dict = message as? [String: Any],
              dict["t"] as? String == "sync",
              let v = int(dict["v"]), v <= version
        else { return nil }
        let rawOps = dict["ops"] as? [Any] ?? []
        return rawOps.compactMap(decodeOp)
    }

    static func decodeOp(_ raw: Any) -> Op? {
        guard let dict = raw as? [String: Any],
              let oid = dict["oid"] as? String, !oid.isEmpty,
              let alarmId = dict["id"] as? String, !alarmId.isEmpty
        else { return nil }
        let at = int(dict["at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .distantPast
        var op = Op(
            oid: oid,
            kind: (dict["op"] as? String).flatMap(Op.Kind.init(rawValue:)),
            alarmId: alarmId,
            at: at
        )
        if let f = dict["f"] as? [String: Any] {
            op.fields = decodeFields(f)
        }
        op.enabled = bool(dict["e"])
        return op
    }

    static func decodeFields(_ f: [String: Any]) -> Fields {
        var fields = Fields()
        func number(_ key: String) -> Int? {
            guard let value = f[key] else { return nil }
            guard let n = int(value) else { fields.malformed = true; return nil }
            return n
        }
        fields.hour = number("h")
        fields.minute = number("m")
        fields.snoozeMinutes = number("sm")
        if let value = f["d"] {
            let days = (value as? [Any])?.map { int($0).flatMap(Weekday.init(rawValue:)) }
            if let days, !days.contains(where: { $0 == nil }) {
                fields.repeatDays = Set(days.compactMap { $0 })
            } else {
                fields.malformed = true
            }
        }
        if let value = f["l"] {
            if let label = value as? String { fields.label = label } else { fields.malformed = true }
        }
        if let value = f["sn"] {
            if let flag = bool(value) { fields.snoozeEnabled = flag } else { fields.malformed = true }
        }
        return fields
    }

    // MARK: - Value coercion

    /// Whole seconds since 1970; the watch's clock has no finer resolution.
    static func epoch(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }

    /// Monkey C sends Number, Long or Float; the SDK hands them over as
    /// NSNumber. Fractions aren't valid for any integer field.
    static func int(_ value: Any?) -> Int? {
        switch value {
        case let i as Int:
            return i
        case let i as Int64:
            return Int(exactly: i)
        case let i as Int32:
            return Int(i)
        case let d as Double:
            return d.rounded() == d && abs(d) < 1e15 ? Int(d) : nil
        case let n as NSNumber:
            let d = n.doubleValue
            return d.rounded() == d ? n.intValue : nil
        default:
            return nil
        }
    }

    /// Monkey C Booleans may arrive as NSNumber 0/1.
    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool: return b
        case let i as Int where i == 0 || i == 1: return i == 1
        default: return nil
        }
    }
}
