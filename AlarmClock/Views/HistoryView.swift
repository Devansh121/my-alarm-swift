import SwiftUI

/// Pure text helpers for the History screen.
enum HistoryFormatting {

    static func minutes(_ value: Double) -> String {
        value < 1 ? "<1 min" : "\(Int(value.rounded())) min"
    }

    static func snoozes(_ count: Int) -> String {
        count == 1 ? "1 snooze" : "\(count) snoozes"
    }

    /// e.g. "1 snooze · up in 12 min", "Missed", "Not stopped".
    static func summary(_ session: RingSession) -> String {
        switch session.outcome {
        case .missed:
            return "Missed"
        case .open:
            return session.snoozes > 0 ? "\(snoozes(session.snoozes)) · not stopped" : "Not stopped"
        case .stopped:
            let up = session.minutesToGetUp.map { "up in \(minutes($0))" } ?? "stopped"
            return "\(snoozes(session.snoozes)) · \(up)"
        }
    }

    static func averageSnoozes(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
    }
}

/// Recent mornings (each alarm going off until it was stopped) and simple
/// per-alarm stats. Test alarms are listed with a badge but left out of stats.
struct HistoryView: View {
    @ObservedObject var history: HistoryLog
    @State private var confirmClear = false

    private static let maxMornings = 100

    var body: some View {
        let sessions = HistoryAggregator.sessions(from: history.events)
        let stats = HistoryAggregator.stats(from: sessions)

        List {
            if sessions.isEmpty {
                Text("No alarm history yet. Mornings appear here after an alarm rings.")
                    .foregroundStyle(.secondary)
            }

            if !stats.isEmpty {
                Section("Per Alarm") {
                    ForEach(stats, id: \.alarmId) { stat in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stat.label).font(.headline)
                            Text(statLine(stat))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !sessions.isEmpty {
                Section("Recent Mornings") {
                    ForEach(Array(sessions.prefix(Self.maxMornings).enumerated()), id: \.offset) { _, session in
                        MorningRow(session: session)
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !history.events.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { confirmClear = true }
                        .tint(.orange)
                }
            }
        }
        .confirmationDialog("Clear all alarm history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { history.clear() }
        }
        .preferredColorScheme(.dark)
    }

    private func statLine(_ stat: AlarmStats) -> String {
        var parts = ["\(stat.mornings) morning\(stat.mornings == 1 ? "" : "s")"]
        parts.append("avg \(HistoryFormatting.averageSnoozes(stat.averageSnoozes)) snoozes")
        if let minutes = stat.averageMinutesToGetUp {
            parts.append("avg up in \(HistoryFormatting.minutes(minutes))")
        }
        if stat.missed > 0 { parts.append("\(stat.missed) missed") }
        return parts.joined(separator: " · ")
    }
}

private struct MorningRow: View {
    let session: RingSession

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.label).font(.headline)
                    if session.isTest {
                        Text("TEST")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.25), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(session.firedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(HistoryFormatting.summary(session))
                .font(.subheadline)
                .foregroundStyle(session.outcome == .missed ? Color.red : Color.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        HistoryView(history: HistoryLog(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-history.json")))
    }
}
