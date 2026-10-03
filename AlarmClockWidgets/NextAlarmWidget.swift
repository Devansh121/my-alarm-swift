import WidgetKit
import SwiftUI

// MARK: - Timeline

struct NextAlarmEntry: TimelineEntry {
    let date: Date
    let state: NextAlarmState
}

/// Reads only the App Group snapshot the app writes; schedules an entry at
/// every upcoming fire so "next alarm" rolls over without the app running.
struct NextAlarmProvider: TimelineProvider {

    func placeholder(in context: Context) -> NextAlarmEntry {
        NextAlarmEntry(date: .now, state: .upcoming(Self.sample(from: .now)))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        let now = Date()
        if context.isPreview, SharedSnapshotStore.read() == nil {
            completion(NextAlarmEntry(date: now, state: .upcoming(Self.sample(from: now))))
            return
        }
        completion(NextAlarmEntry(date: now, state: NextAlarmTimeline.state(snapshot: SharedSnapshotStore.read(), at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedSnapshotStore.read()
        let dates = NextAlarmTimeline.entryDates(snapshot: snapshot, now: now)
        let entries = dates.map {
            NextAlarmEntry(date: $0, state: NextAlarmTimeline.state(snapshot: snapshot, at: $0))
        }
        // With nothing upcoming there is nothing to roll over to; the app
        // reloads timelines whenever alarms change.
        let policy: TimelineReloadPolicy = dates.count > 1 ? .atEnd : .never
        completion(Timeline(entries: entries, policy: policy))
    }

    private static func sample(from now: Date) -> [WidgetSnapshot.Occurrence] {
        [
            .init(alarmId: "sample-1", label: "Wake up", fireDate: now.addingTimeInterval(7 * 3600 + 23 * 60)),
            .init(alarmId: "sample-2", label: "Gym", fireDate: now.addingTimeInterval(8 * 3600)),
            .init(alarmId: "sample-3", label: "Alarm", fireDate: now.addingTimeInterval(31 * 3600)),
        ]
    }
}

// MARK: - Widget

struct NextAlarmWidget: Widget {
    let kind = "NextAlarmWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextAlarmProvider()) { entry in
            NextAlarmWidgetView(entry: entry)
                .widgetURL(AlarmDeepLink.alarmList)
        }
        .configurationDisplayName("Next Alarm")
        .description("Your next alarm and how long until it rings.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
    }
}

// MARK: - Views

struct NextAlarmWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextAlarmEntry

    private var upcoming: [WidgetSnapshot.Occurrence] {
        if case .upcoming(let list) = entry.state { return list }
        return []
    }

    /// Text for states with no alarm to show.
    private var emptyMessage: String {
        switch entry.state {
        case .unavailable: return "Open Alarm to set up"
        case .stale: return "Open Alarm to refresh"
        case .upcoming: return "No alarms"
        }
    }

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: small
        }
    }

    // MARK: Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            if let next = upcoming.first {
                nextAlarmBlock(next, timeFont: .system(size: 34, weight: .light))
            } else {
                emptyBlock
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(Color.black, for: .widget)
        // The background is always black, so default-colored text must
        // render for dark even when the device is in light mode.
        .environment(\.colorScheme, .dark)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                if let next = upcoming.first {
                    nextAlarmBlock(next, timeFont: .system(size: 38, weight: .light))
                } else {
                    emptyBlock
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            if upcoming.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("LATER")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(upcoming.dropFirst().prefix(2), id: \.self) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            // One static string: a live `Text(_:style: .time)` beside
                            // the weekday collapses to zero width in this column.
                            Text(item.fireDate, format: .dateTime.weekday(.abbreviated).hour().minute())
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(item.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .containerBackground(Color.black, for: .widget)
        // The background is always black, so default-colored text must
        // render for dark even when the device is in light mode.
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        Label("Next alarm", systemImage: "alarm.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
    }

    private func nextAlarmBlock(_ next: WidgetSnapshot.Occurrence, timeFont: Font) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(next.fireDate, style: .time)
                .font(timeFont)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(.white)
            Text(next.label)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            HStack(spacing: 3) {
                Text("in")
                Text(next.fireDate, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "alarm")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: Lock screen

    private var rectangular: some View {
        HStack(spacing: 6) {
            Image(systemName: "alarm.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                if let next = upcoming.first {
                    Text(next.fireDate, style: .time)
                        .font(.headline)
                    Text(next.label)
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Text(emptyMessage)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "alarm.fill")
                    .font(.caption2)
                if let next = upcoming.first {
                    Text(next.fireDate, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.system(size: 14, weight: .semibold))
                        .minimumScaleFactor(0.6)
                } else {
                    Text("--")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var inline: some View {
        Group {
            if let next = upcoming.first {
                Text("⏰ \(next.fireDate, style: .time)")
            } else {
                Text("⏰ \(emptyMessage)")
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

#Preview(as: .systemSmall) {
    NextAlarmWidget()
} timeline: {
    NextAlarmEntry(date: .now, state: .upcoming([
        .init(alarmId: "a", label: "Wake up", fireDate: .now.addingTimeInterval(26_580)),
    ]))
    NextAlarmEntry(date: .now, state: .upcoming([]))
}
