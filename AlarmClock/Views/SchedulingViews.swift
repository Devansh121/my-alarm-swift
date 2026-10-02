import SwiftUI

/// "Times" screen for a repeating alarm: one row per selected day with a
/// compact time picker. Days left alone ring at the alarm's main time; a day
/// changed here gets its own time (e.g. 7:00 Mon–Thu, Fri 8:30).
struct DayTimesView: View {
    let days: Set<Weekday>
    let defaultTime: ClockTime
    @Binding var overrides: [Weekday: ClockTime]

    var body: some View {
        List {
            Section {
                ForEach(days.sorted(), id: \.self) { day in
                    DatePicker(selection: binding(for: day), displayedComponents: .hourAndMinute) {
                        HStack {
                            Text(day.fullName)
                            if isOverridden(day) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("Custom time")
                            }
                        }
                    }
                    .swipeActions {
                        if isOverridden(day) {
                            Button("Reset") { overrides[day] = nil }
                                .tint(.orange)
                        }
                    }
                }
            } footer: {
                Text("Other days ring at \(AlarmFormatting.timeString(hour: defaultTime.hour, minute: defaultTime.minute)). Swipe a changed day to reset it.")
            }

            if days.contains(where: isOverridden) {
                Section {
                    Button("Use Same Time Every Day") {
                        overrides = [:]
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Times")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isOverridden(_ day: Weekday) -> Bool {
        guard let override = overrides[day] else { return false }
        return override != defaultTime
    }

    /// Bridges a day's ClockTime to the picker's Date. Picking the default
    /// time again drops the override.
    private func binding(for day: Weekday) -> Binding<Date> {
        Binding(
            get: { Self.date(for: overrides[day] ?? defaultTime) },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                let picked = ClockTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
                overrides[day] = picked == defaultTime ? nil : picked
            }
        )
    }

    static func date(for time: ClockTime) -> Date {
        Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
    }
}

/// Add/Edit screen hint under the time wheel: "Rings in 7h 30m", turning into
/// a gentle amber warning when that leaves under six hours of sleep.
struct SleepHintView: View {
    let alarm: Alarm
    let now: () -> Date
    let calendar: Calendar

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let current = now()
            let fire = NextFireCalculator.nextFire(alarm: alarm, after: current, calendar: calendar)
            let minutes = SleepMath.minutesUntil(fire, from: current)
            if let warning = SleepMath.shortSleepWarning(minutes: minutes) {
                Label(warning, systemImage: "moon.zzz")
                    .foregroundStyle(Color(red: 1.0, green: 0.75, blue: 0.3))
            } else {
                Text(SleepMath.ringsInText(minutes: minutes))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// "Wake me in 6h / 7h 30m / 9h" shortcut buttons shown when adding an alarm.
struct WakeShortcutsView: View {
    let onPick: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Wake me in")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ForEach(SleepMath.wakeShortcuts, id: \.title) { shortcut in
                Button(shortcut.title) { onPick(shortcut.duration) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.orange)
                    .accessibilityLabel("Wake me in \(shortcut.title)")
            }
        }
    }
}
