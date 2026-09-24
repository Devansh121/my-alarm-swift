import SwiftUI

/// Add / Edit Alarm sheet, replicating Clock's screen: a wheel time picker over
/// an inset-grouped list of Repeat / Label / Sound / Snooze, plus Delete when editing.
struct AlarmEditView: View {
    @ObservedObject var store: AlarmStore
    @Environment(\.dismiss) private var dismiss

    /// True when editing an existing alarm (preserves id, shows Delete).
    private let isExisting: Bool
    private let originalId: String

    @State private var time: Date
    @State private var repeatDays: Set<Weekday>
    @State private var label: String
    @State private var tone: ToneSelection
    @State private var snoozeEnabled: Bool
    @State private var snoozeMinutes: Int

    /// - Parameter alarm: nil for a brand-new alarm, otherwise the one to edit.
    init(alarm: Alarm?, store: AlarmStore) {
        self.store = store
        let base = alarm ?? Alarm(hour: 7, minute: 0, label: "Alarm")
        self.isExisting = alarm != nil
        self.originalId = base.id

        var comps = DateComponents()
        comps.hour = base.hour
        comps.minute = base.minute
        let initial = Calendar.current.date(from: comps) ?? Date()
        _time = State(initialValue: initial)
        _repeatDays = State(initialValue: base.repeatDays)
        _label = State(initialValue: base.label)
        _tone = State(initialValue: base.tone)
        _snoozeEnabled = State(initialValue: base.snoozeEnabled)
        _snoozeMinutes = State(initialValue: base.snoozeMinutes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .padding(.top, 8)

                    optionsList
                }
            }
            .navigationTitle(isExisting ? "Edit Alarm" : "Add Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.orange)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .tint(.orange)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var optionsList: some View {
        List {
            Section {
                NavigationLink {
                    RepeatPickerView(selectedDays: $repeatDays)
                } label: {
                    LabeledRow(title: "Repeat", value: repeatValue)
                }

                HStack {
                    Text("Label")
                    Spacer()
                    TextField("Alarm", text: $label)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    SoundPickerView(selection: $tone)
                } label: {
                    LabeledRow(title: "Sound", value: AlarmFormatting.toneDisplayName(tone))
                }

                Toggle("Snooze", isOn: $snoozeEnabled)

                if snoozeEnabled {
                    NavigationLink {
                        SnoozeDurationPickerView(minutes: $snoozeMinutes)
                    } label: {
                        LabeledRow(title: "Snooze Duration", value: "\(snoozeMinutes) min")
                    }
                }
            }

            if isExisting {
                Section {
                    Button(role: .destructive) {
                        store.delete(id: originalId)
                        dismiss()
                    } label: {
                        Text("Delete Alarm")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var repeatValue: String {
        let summary = AlarmFormatting.repeatSummary(repeatDays)
        return summary.isEmpty ? "Never" : summary
    }

    private func save() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        let alarm = Alarm(
            id: originalId,
            hour: comps.hour ?? 0,
            minute: comps.minute ?? 0,
            repeatDays: repeatDays,
            label: trimmed.isEmpty ? "Alarm" : trimmed,
            tone: tone,
            snoozeEnabled: snoozeEnabled,
            snoozeMinutes: snoozeMinutes,
            enabled: true
        )
        store.upsert(alarm)
        dismiss()
    }
}

/// A title on the left, gray value + chevron on the right — the Clock detail row.
private struct LabeledRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Repeat picker

/// Checkmark list "Every Monday…Every Sunday", multi-select like Clock.
struct RepeatPickerView: View {
    @Binding var selectedDays: Set<Weekday>

    var body: some View {
        List {
            ForEach(Weekday.allCases, id: \.self) { day in
                Button {
                    toggle(day)
                } label: {
                    HStack {
                        Text("Every \(day.fullName)")
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedDays.contains(day) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}

// MARK: - Sound picker

/// "Random" plus each bundled tone, single-select checkmark list.
struct SoundPickerView: View {
    @Binding var selection: ToneSelection

    var body: some View {
        List {
            Section {
                row(title: "Random", isSelected: selection == .random) {
                    selection = .random
                }
            }
            Section {
                ForEach(bundledTones) { tone in
                    row(title: tone.displayName, isSelected: selection == .pinned(toneId: tone.id)) {
                        selection = .pinned(toneId: tone.id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Snooze duration picker

/// Checkmark list of the supported snooze durations.
struct SnoozeDurationPickerView: View {
    @Binding var minutes: Int

    private let options = [5, 9, 10, 15, 20, 30]

    var body: some View {
        List {
            ForEach(options, id: \.self) { value in
                Button {
                    minutes = value
                } label: {
                    HStack {
                        Text("\(value) minutes")
                            .foregroundStyle(.primary)
                        Spacer()
                        if minutes == value {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Snooze Duration")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Add") {
    AlarmEditView(alarm: nil, store: AlarmStore(engine: NoopEngine(), ringer: NoopRinger()))
}

#Preview("Edit") {
    AlarmEditView(
        alarm: Alarm(hour: 6, minute: 30, repeatDays: [.monday, .friday], label: "Work"),
        store: AlarmStore(engine: NoopEngine(), ringer: NoopRinger())
    )
}
