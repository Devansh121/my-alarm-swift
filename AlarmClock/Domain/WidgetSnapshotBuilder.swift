import Foundation

/// Builds the widget snapshot from the app's alarms. Pure: alarms + now in,
/// snapshot out. Fire dates come from `NextFireCalculator`, so per-day
/// overrides and a pending "skip next" are honored exactly as the scheduler
/// honors them.
enum WidgetSnapshotBuilder {

    /// How far ahead repeating alarms are expanded. Covers every weekday, so
    /// the widget keeps rolling over for a week without the app running.
    static let horizon: TimeInterval = 7 * 24 * 3600
    /// Cap on stored occurrences, keeping the file and timelines small.
    static let maxOccurrences = 40

    static func build(
        alarms: [Alarm],
        now: Date,
        calendar: Calendar,
        horizon: TimeInterval = horizon,
        maxOccurrences: Int = maxOccurrences
    ) -> WidgetSnapshot {
        let horizonEnd = now.addingTimeInterval(horizon)
        var occurrences: [WidgetSnapshot.Occurrence] = []
        var hasRepeating = false

        for alarm in alarms where alarm.enabled {
            let label = alarm.label.trimmingCharacters(in: .whitespaces)
            func occurrence(_ date: Date) -> WidgetSnapshot.Occurrence {
                .init(alarmId: alarm.id, label: label.isEmpty ? "Alarm" : label, fireDate: date)
            }

            var fire = NextFireCalculator.nextFire(alarm: alarm, after: now, calendar: calendar)
            if alarm.repeatDays.isEmpty {
                occurrences.append(occurrence(fire))
                continue
            }
            hasRepeating = true
            // Only the immediate next occurrence can be skipped, so later
            // occurrences follow plain `nextFire` from the previous one.
            while fire <= horizonEnd {
                occurrences.append(occurrence(fire))
                fire = NextFireCalculator.nextFire(alarm: alarm, after: fire, calendar: calendar)
            }
        }

        occurrences.sort {
            $0.fireDate != $1.fireDate ? $0.fireDate < $1.fireDate : $0.alarmId < $1.alarmId
        }

        if occurrences.count > maxOccurrences {
            let kept = Array(occurrences.prefix(maxOccurrences))
            // Everything before the first dropped fire is known; past it, not.
            return WidgetSnapshot(occurrences: kept, coversUntil: occurrences[maxOccurrences].fireDate)
        }
        return WidgetSnapshot(occurrences: occurrences, coversUntil: hasRepeating ? horizonEnd : nil)
    }
}
