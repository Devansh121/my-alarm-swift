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
            ToolbarItem(placement: .topBarTrailing) {
                testAlarmMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let history = store.history {
                    NavigationLink {
                        HistoryView(history: history)
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    .tint(.orange)
                    .accessibilityLabel("History")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let test = store.testAlarm {
                TestAlarmBanner(test: test) { store.cancelTestAlarm() }
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
                    onToggle: { enabled in
                        store.setEnabled(id: alarm.id, enabled: enabled)
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    editingAlarm = alarm
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

    /// "Test my alarm": rings a real alarm in 30s with a chosen alarm's
    /// settings (or defaults) so the user can lock the phone and check it.
    private var testAlarmMenu: some View {
        Menu {
            Section("Ring a test alarm in 30 seconds") {
                ForEach(store.alarms) { alarm in
                    Button {
                        store.startTestAlarm(basedOn: alarm)
                    } label: {
                        Text("\(AlarmFormatting.timeString(hour: alarm.hour, minute: alarm.minute)) · \(alarm.label)")
                    }
                }
                Button("Default Settings") {
                    store.startTestAlarm(basedOn: nil)
                }
            }
        } label: {
            Image(systemName: "bell.badge")
        }
        .tint(.orange)
        .accessibilityLabel("Test My Alarm")
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
    let onToggle: (Bool) -> Void

    private var time: (time: String, period: String) {
        AlarmFormatting.timeComponents(hour: alarm.hour, minute: alarm.minute)
    }

    private var secondary: String {
        AlarmFormatting.secondaryLine(label: alarm.label, days: alarm.repeatDays)
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
