import Foundation

/// Identifiers shared by the app and the widget extension.
enum AppGroup {
    static let identifier = "group.com.devansh.alarmclock"
}

/// Deep links the widgets and Live Activity open the app with.
enum AlarmDeepLink {
    static let scheme = "alarmclock"
    static let alarmList = URL(string: "alarmclock://alarms")!
}

/// Compact, precomputed view of upcoming alarm fires that the app writes into
/// the App Group container for the widgets. The widget never sees `Alarm` or
/// re-derives schedules: skips and per-day overrides are already applied by the
/// app's `NextFireCalculator`, so the widget only filters by "still upcoming".
struct WidgetSnapshot: Codable, Equatable {

    struct Occurrence: Codable, Equatable, Hashable {
        var alarmId: String
        var label: String
        var fireDate: Date
    }

    /// Upcoming fires, sorted ascending by `fireDate` (ties by alarmId).
    var occurrences: [Occurrence] = []
    /// The list is known to be complete only up to this instant (it holds a
    /// bounded horizon of repeating alarms). nil means it is complete forever:
    /// no repeating alarms are enabled and nothing was truncated.
    var coversUntil: Date? = nil

    init(occurrences: [Occurrence] = [], coversUntil: Date? = nil) {
        self.occurrences = occurrences
        self.coversUntil = coversUntil
    }

    /// Tolerant decode: a snapshot written by another build never fails the
    /// widget outright; missing fields fall back to empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        occurrences = (try? c.decodeIfPresent([Occurrence].self, forKey: .occurrences)) ?? []
        coversUntil = try? c.decodeIfPresent(Date.self, forKey: .coversUntil)
    }

    /// Fires strictly after `date`, in order — what the widget shows at `date`.
    func upcoming(after date: Date) -> [Occurrence] {
        occurrences.filter { $0.fireDate > date }
    }
}

/// What a widget entry renders at a given instant.
enum NextAlarmState: Equatable {
    /// No snapshot (App Group unavailable or app never launched).
    case unavailable
    /// The snapshot's horizon has passed; the app must run to extend it.
    case stale
    /// Upcoming fires (possibly empty = "No alarms").
    case upcoming([WidgetSnapshot.Occurrence])
}

/// Pure timeline planning for the next-alarm widgets.
enum NextAlarmTimeline {

    /// Entry instants: `now`, then every distinct upcoming fire (so the widget
    /// rolls over to the following alarm the moment one passes), then the
    /// horizon end if the snapshot has one. Capped to keep timelines small.
    static func entryDates(snapshot: WidgetSnapshot?, now: Date, limit: Int = 40) -> [Date] {
        guard let snapshot else { return [now] }
        var dates = [now]
        for fire in Set(snapshot.upcoming(after: now).map(\.fireDate)).sorted() {
            guard dates.count < limit else { break }
            if let end = snapshot.coversUntil, fire >= end { break }
            dates.append(fire)
        }
        if let end = snapshot.coversUntil, end > now, dates.count < limit {
            dates.append(end)
        }
        return dates
    }

    /// The state to render at `date`.
    static func state(snapshot: WidgetSnapshot?, at date: Date) -> NextAlarmState {
        guard let snapshot else { return .unavailable }
        if let end = snapshot.coversUntil, date >= end { return .stale }
        return .upcoming(snapshot.upcoming(after: date))
    }
}

/// Reads/writes the snapshot file in the App Group container. Every failure
/// (no entitlement, no container, bad JSON) degrades to nil/false — never a crash.
enum SharedSnapshotStore {
    static let fileName = "widget-snapshot.json"

    static func fileURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent(fileName)
    }

    static func read(from url: URL? = fileURL()) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    static func write(_ snapshot: WidgetSnapshot, to url: URL? = fileURL()) -> Bool {
        guard let url, let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("alarm: widget snapshot write failed \(error)")
            return false
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
