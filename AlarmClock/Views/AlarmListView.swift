import SwiftUI

/// The Alarm tab. Faithful to Apple's Clock: large "Alarms" title, black
/// background, Edit / + toolbar, and big thin time rows over hairline separators.
struct AlarmListView: View {
    @ObservedObject var store: AlarmStore

    @State private var editingAlarm: Alarm?
    @State private var isPresentingNew = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        Group {
            if store.alarms.isEmpty {
                emptyState
            } else {
                alarmList
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Alarms")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !store.alarms.isEmpty {
                    EditButton()
                        .tint(.orange)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingNew = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                }
                .tint(.orange)
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(item: $editingAlarm) { alarm in
            AlarmEditView(alarm: alarm, store: store)
        }
        .sheet(isPresented: $isPresentingNew) {
            AlarmEditView(alarm: nil, store: store)
        }
    }

    private var alarmList: some View {
        List {
            ForEach(store.alarms) { alarm in
                AlarmRow(
                    alarm: alarm,
                    isEditing: editMode.isEditing,
                    skipText: skipText(for: alarm),
                    onToggle: { enabled in
                        store.setEnabled(id: alarm.id, enabled: enabled)
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    editingAlarm = alarm
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    skipButton(for: alarm)
                }
                .contextMenu {
                    skipButton(for: alarm)
                }
                .listRowBackground(Color.black)
                .listRowSeparatorTint(Color(white: 0.22))
            }
            .onDelete { indexSet in
                for index in indexSet {
                    store.delete(id: store.alarms[index].id)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
    }

    // MARK: Skip next

    /// "Skipping Tue 7:00 AM" while a skip is in effect. Evaluated against the
    /// current time so a skip whose occurrence already passed never shows.
    private func skipText(for alarm: Alarm) -> String? {
        NextFireCalculator.activeSkip(alarm: alarm, after: store.now(), calendar: store.calendar)
            .map { AlarmFormatting.skipSummary($0, calendar: store.calendar) }
    }

    /// "Skip Next" / "Undo Skip" for enabled repeating alarms. Hidden for
    /// one-shots (their toggle already covers "don't ring next time").
    @ViewBuilder
    private func skipButton(for alarm: Alarm) -> some View {
        if alarm.enabled, !alarm.repeatDays.isEmpty {
            if skipText(for: alarm) != nil {
                Button {
                    store.cancelSkip(id: alarm.id)
                } label: {
                    Label("Undo Skip", systemImage: "arrow.uturn.backward")
                }
                .tint(.gray)
            } else {
                Button {
                    store.skipNext(id: alarm.id)
                } label: {
                    Label("Skip Next", systemImage: "forward.end")
                }
                .tint(.orange)
            }
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No Alarms")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single alarm row: huge thin time with a smaller AM/PM suffix, a secondary
/// "Label, repeat" line, and a trailing toggle. Dims to gray when disabled.
private struct AlarmRow: View {
    let alarm: Alarm
    let isEditing: Bool
    var skipText: String? = nil
    let onToggle: (Bool) -> Void

    private var time: (time: String, period: String) {
        AlarmFormatting.timeComponents(hour: alarm.hour, minute: alarm.minute)
    }

    private var secondary: String {
        AlarmFormatting.secondaryLine(
            label: alarm.label, days: alarm.repeatDays, overrides: alarm.effectiveTimeOverrides
        )
    }

    private var foreground: Color {
        alarm.enabled ? .white : Color(white: 0.55)
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(time.time)
                        .font(.system(size: 58, weight: .light))
                    Text(time.period)
                        .font(.system(size: 26, weight: .light))
                }
                .foregroundStyle(foreground)

                if !secondary.isEmpty {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(alarm.enabled ? Color(white: 0.7) : Color(white: 0.45))
                }

                if let skipText {
                    Label(skipText, systemImage: "forward.end")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if !isEditing {
                Toggle("", isOn: Binding(
                    get: { alarm.enabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    let store = AlarmStore(engine: NoopEngine(), ringer: NoopRinger())
    return NavigationStack {
        AlarmListView(store: store)
    }
    .preferredColorScheme(.dark)
}
