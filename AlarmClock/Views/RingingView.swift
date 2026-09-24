import SwiftUI

/// Full-screen alarm firing UI: live current time, the alarm's label, and
/// Snooze (when enabled) / Stop pill buttons wired to the store.
struct RingingView: View {
    let alarm: Alarm
    @ObservedObject var store: AlarmStore

    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                Spacer()

                Text(alarm.label)
                    .font(.title2)
                    .foregroundStyle(Color(white: 0.75))

                Text(currentTime.time)
                    .font(.system(size: 84, weight: .thin))
                    .foregroundStyle(.white)
                + Text(" \(currentTime.period)")
                    .font(.system(size: 34, weight: .thin))
                    .foregroundStyle(.white)

                Spacer()

                VStack(spacing: 20) {
                    if alarm.snoozeEnabled {
                        Button {
                            store.snoozeRinging()
                        } label: {
                            Text("Snooze \(alarm.snoozeMinutes) min")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color.orange, in: Capsule())
                        }
                    }

                    Button {
                        store.stopRinging()
                    } label: {
                        Text("Stop")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color(white: 0.18), in: Capsule())
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onReceive(ticker) { now = $0 }
    }

    private var currentTime: (time: String, period: String) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        return AlarmFormatting.timeComponents(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
    }
}

#Preview {
    RingingView(
        alarm: Alarm(hour: 7, minute: 0, label: "Wake Up", snoozeEnabled: true, snoozeMinutes: 9),
        store: AlarmStore(engine: NoopEngine(), ringer: NoopRinger())
    )
}
