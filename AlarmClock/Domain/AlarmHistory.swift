import Foundation

/// One thing that happened to an alarm, as recorded in the history log.
struct AlarmEvent: Codable, Equatable {
    enum Kind: String, Codable {
        case fired, snoozed, stopped, missed
    }

    var kind: Kind
    var alarmId: String
    var label: String
    /// For `fired`/`missed`: when the alarm went off. Otherwise when the
    /// user acted.
    var date: Date
    /// Events from "Test my alarm" — kept so the log is honest, but marked
    /// and excluded from stats.
    var isTest: Bool = false
}

extension AlarmEvent {
    /// Tolerant decoding: the history file must never fail to load because a
    /// later version added a field. kind/alarmId/date are required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try c.decode(Kind.self, forKey: .kind),
            alarmId: try c.decode(String.self, forKey: .alarmId),
            label: (try? c.decodeIfPresent(String.self, forKey: .label)) ?? "Alarm",
            date: try c.decode(Date.self, forKey: .date),
            isTest: (try? c.decodeIfPresent(Bool.self, forKey: .isTest)) ?? false
        )
    }
}

/// One "morning": an alarm going off and everything until it was stopped
/// (or missed).
struct RingSession: Equatable {
    enum Outcome: Equatable { case stopped, missed, open }

    var alarmId: String
    var label: String
    var firedAt: Date
    var snoozes: Int = 0
    var endedAt: Date? = nil
    var outcome: Outcome = .open
    var isTest: Bool = false
    /// Last event time, used to abandon sessions nobody ever closed.
    var lastActivity: Date

    /// Minutes from first ring to Stop; nil unless stopped.
    var minutesToGetUp: Double? {
        guard outcome == .stopped, let endedAt else { return nil }
        return max(endedAt.timeIntervalSince(firedAt), 0) / 60
    }
}

/// Per-alarm summary over its (non-test) sessions.
struct AlarmStats: Equatable {
    var alarmId: String
    var label: String
    var mornings: Int
    var missed: Int
    /// Average snoozes per morning (missed mornings excluded).
    var averageSnoozes: Double?
    /// Average minutes from first ring to Stop.
    var averageMinutesToGetUp: Double?
}

/// Pure aggregation of the raw event log into mornings and stats.
enum HistoryAggregator {

    /// A session with no activity for this long is considered abandoned, so
    /// the next `fired` starts a new morning instead of extending it.
    static let sessionTimeout: TimeInterval = 3 * 3600

    /// How long after a "missed" a late Stop/Snooze still belongs to that
    /// morning. The app can record "missed" on a cold launch caused by the
    /// very lock-screen Stop that's about to be recorded.
    static let missedReopenWindow: TimeInterval = 2 * 3600

    /// Groups events into sessions, newest first.
    ///
    /// Rules, per alarm, in time order:
    ///   - `fired` opens a session, or continues an open one (a snooze
    ///     re-ringing, or a duplicate fired record).
    ///   - `snoozed` counts against the open session; `stopped` closes it.
    ///   - `missed` closes the open session as missed (or records a missed
    ///     morning on its own).
    ///   - A snooze/stop/fired with no open session reopens a recent missed
    ///     session, else starts a session at its own time.
    static func sessions(from events: [AlarmEvent]) -> [RingSession] {
        var done: [RingSession] = []
        var open: [String: RingSession] = [:]
        // Stable sort keeps insertion order for identical timestamps.
        let ordered = events.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)

        for event in ordered {
            let key = event.alarmId
            if var current = open[key],
               event.date.timeIntervalSince(current.lastActivity) > sessionTimeout {
                current.outcome = .open
                done.append(current)
                open[key] = nil
            }

            var session: RingSession
            if let current = open[key] {
                session = current
            } else if event.kind != .missed,
                      let index = done.lastIndex(where: {
                          $0.alarmId == key && $0.outcome == .missed &&
                          event.date.timeIntervalSince($0.firedAt) >= 0 &&
                          event.date.timeIntervalSince($0.firedAt) <= missedReopenWindow
                      }) {
                session = done.remove(at: index)
                session.outcome = .open
                session.endedAt = nil
            } else {
                session = RingSession(
                    alarmId: key, label: event.label, firedAt: event.date,
                    isTest: event.isTest, lastActivity: event.date
                )
            }

            session.label = event.label
            session.lastActivity = max(session.lastActivity, event.date)
            switch event.kind {
            case .fired:
                open[key] = session
            case .snoozed:
                session.snoozes += 1
                open[key] = session
            case .stopped:
                session.outcome = .stopped
                session.endedAt = event.date
                open[key] = nil
                done.append(session)
            case .missed:
                session.outcome = .missed
                session.endedAt = nil
                open[key] = nil
                done.append(session)
            }
        }

        done.append(contentsOf: open.values)
        return done.sorted { $0.firedAt > $1.firedAt }
    }

    /// Per-alarm stats, excluding test alarms, sorted by most mornings.
    static func stats(from sessions: [RingSession]) -> [AlarmStats] {
        let real = sessions.filter { !$0.isTest }
        let grouped = Dictionary(grouping: real, by: \.alarmId)
        return grouped.map { alarmId, list in
            let newest = list.max { $0.firedAt < $1.firedAt }
            let attended = list.filter { $0.outcome != .missed }
            let minutes = list.compactMap(\.minutesToGetUp)
            return AlarmStats(
                alarmId: alarmId,
                label: newest?.label ?? "Alarm",
                mornings: list.count,
                missed: list.count - attended.count,
                averageSnoozes: attended.isEmpty ? nil
                    : Double(attended.map(\.snoozes).reduce(0, +)) / Double(attended.count),
                averageMinutesToGetUp: minutes.isEmpty ? nil
                    : minutes.reduce(0, +) / Double(minutes.count)
            )
        }
        .sorted { ($0.mornings, $1.label) > ($1.mornings, $0.label) }
    }

    /// Keeps only the newest `limit` events (by date), preserving order.
    static func capped(_ events: [AlarmEvent], limit: Int) -> [AlarmEvent] {
        guard events.count > limit else { return events }
        let ordered = events.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        return Array(ordered.suffix(max(limit, 0)))
    }
}
