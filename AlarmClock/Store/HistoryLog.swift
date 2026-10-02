import Foundation
import Combine

/// Append-only alarm event log persisted as a small JSON file, capped to the
/// newest `limit` events.
///
/// Loading is tolerant: a missing or corrupt file yields an empty log, and a
/// single undecodable entry is skipped rather than discarding the rest.
final class HistoryLog: ObservableObject {

    static let defaultLimit = 500

    @Published private(set) var events: [AlarmEvent] = []

    private let url: URL
    private let limit: Int

    init(url: URL? = nil, limit: Int = HistoryLog.defaultLimit) {
        self.url = url ?? Self.defaultURL()
        self.limit = limit
        self.events = HistoryAggregator.capped(Self.load(from: self.url), limit: limit)
    }

    func record(_ event: AlarmEvent) {
        let work = {
            self.events = HistoryAggregator.capped(self.events + [event], limit: self.limit)
            self.persist()
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
    }

    /// Whether anything was recorded for `alarmId` at or after `date`.
    func hasEvent(alarmId: String, since date: Date) -> Bool {
        events.contains { $0.alarmId == alarmId && $0.date >= date }
    }

    func clear() {
        events = []
        persist()
    }

    // MARK: - Persistence

    private static func defaultURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("alarm-history.json")
    }

    /// Decodes element-by-element so one bad entry can't wipe the history.
    static func load(from url: URL) -> [AlarmEvent] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Lossy].self, from: data) else { return [] }
        return entries.compactMap(\.event)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private struct Lossy: Decodable {
        let event: AlarmEvent?
        init(from decoder: Decoder) throws {
            event = try? AlarmEvent(from: decoder)
        }
    }
}
