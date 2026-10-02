import SwiftUI

/// Pure text for the "Test my alarm" banner.
enum TestAlarmCountdown {
    /// "0:27" style countdown, rounded up so it never shows 0:00 early.
    static func text(remaining: TimeInterval) -> String {
        let seconds = max(Int(remaining.rounded(.up)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func status(fireAt: Date, now: Date) -> String {
        let remaining = fireAt.timeIntervalSince(now)
        return remaining > 0
            ? "Test alarm in \(text(remaining: remaining)) — lock your phone"
            : "Test alarm ringing"
    }
}

/// Bottom banner shown while a test alarm is pending or ringing, with a
/// live countdown and a Cancel/Stop button.
struct TestAlarmBanner: View {
    let test: TestAlarm
    let onCancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 12) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TestAlarmCountdown.status(fireAt: test.fireAt, now: context.date))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(test.alarm.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(test.fireAt > context.date ? "Cancel" : "Stop", action: onCancel)
                    .buttonStyle(.bordered)
                    .tint(.orange)
            }
            .padding(14)
            .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .contain)
    }
}
