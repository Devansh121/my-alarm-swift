import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen banner + Dynamic Island for a snoozed alarm.
struct SnoozeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SnoozeActivityAttributes.self) { context in
            SnoozeLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.orange)
                .widgetURL(AlarmDeepLink.alarmList)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SnoozeCountdown(context: context)
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(.orange)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.label)
                            .font(.headline)
                            .lineLimit(1)
                        RingsAgainText(context: context)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    StopButton(alarmId: context.attributes.alarmId)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                SnoozeCountdown(context: context)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            }
            .widgetURL(AlarmDeepLink.alarmList)
            .keylineTint(.orange)
        }
    }
}

private struct SnoozeLockScreenView: View {
    let context: ActivityViewContext<SnoozeActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.title)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.label)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                RingsAgainText(context: context)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                SnoozeCountdown(context: context)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90, alignment: .trailing)
                StopButton(alarmId: context.attributes.alarmId)
            }
        }
        .padding(16)
    }
}

/// "Ringing again at 7:09", or a static line once the snooze has elapsed.
private struct RingsAgainText: View {
    let context: ActivityViewContext<SnoozeActivityAttributes>

    var body: some View {
        if context.isStale {
            Text("Snooze over")
        } else {
            Text("Ringing again at \(context.state.ringsAt, style: .time)")
        }
    }
}

/// Live mm:ss countdown to the re-ring; never counts below zero.
private struct SnoozeCountdown: View {
    let context: ActivityViewContext<SnoozeActivityAttributes>

    var body: some View {
        let state = context.state
        if context.isStale || state.ringsAt <= state.snoozedAt {
            Text("0:00")
        } else {
            Text(timerInterval: state.snoozedAt...state.ringsAt, countsDown: true)
        }
    }
}

private struct StopButton: View {
    let alarmId: String

    var body: some View {
        Button(intent: StopSnoozeIntent(alarmId: alarmId)) {
            Label("Stop", systemImage: "stop.fill")
                .font(.subheadline.weight(.semibold))
        }
        .tint(.orange)
    }
}
