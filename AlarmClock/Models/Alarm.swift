import Foundation

/// Which tone an alarm plays: a surprise from the catalog, or a fixed pick.
enum ToneSelection: Codable, Equatable, Hashable {
    case random
    case pinned(toneId: String)
}

struct Tone: Identifiable, Equatable {
    let id: String
    let displayName: String
    let fileName: String
}

/// Bundled .caf tones shipped in the app bundle.
let bundledTones: [Tone] = [
    Tone(id: "radial", displayName: "Classic Bell", fileName: "tone_radial.caf"),
    Tone(id: "ascent", displayName: "Rise & Shine", fileName: "tone_ascent.caf"),
    Tone(id: "pulse", displayName: "Digital Pulse", fileName: "tone_pulse.caf"),
    Tone(id: "chimes", displayName: "Gentle Chimes", fileName: "tone_chimes.caf"),
    Tone(id: "cosmic", displayName: "Cosmic Drift", fileName: "tone_cosmic.caf"),
    Tone(id: "beacon", displayName: "Marimba", fileName: "tone_beacon.caf"),
    Tone(id: "signal", displayName: "Music Box", fileName: "tone_signal.caf"),
    Tone(id: "waves", displayName: "Morning Birds", fileName: "tone_waves.caf"),
]

/// 1 = Monday ... 7 = Sunday (ISO), matching Locale-independent storage.
enum Weekday: Int, Codable, CaseIterable, Comparable, Hashable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    var shortName: String {
        switch self {
        case .monday: "Mon"; case .tuesday: "Tue"; case .wednesday: "Wed"
        case .thursday: "Thu"; case .friday: "Fri"; case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    var fullName: String {
        switch self {
        case .monday: "Monday"; case .tuesday: "Tuesday"; case .wednesday: "Wednesday"
        case .thursday: "Thursday"; case .friday: "Friday"; case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }
}

struct Alarm: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var hour: Int            // 0..23
    var minute: Int          // 0..59
    var repeatDays: Set<Weekday> = []   // empty = one-shot
    var label: String = "Alarm"
    var tone: ToneSelection = .random
    var snoozeEnabled: Bool = true
    var snoozeMinutes: Int = 9          // 1..30
    var enabled: Bool = true
    /// Last scheduled fire, persisted for missed-alarm reconciliation.
    var nextFireDate: Date? = nil
    /// In-app ringing ramps the player volume up instead of starting at full.
    /// New alarms default ON; alarms saved before this field existed decode
    /// as OFF so their behavior doesn't change underneath the user.
    var gradualVolume: Bool = true
    /// In-app ringing vibrates alone for the first minute, then adds sound.
    var vibrateFirst: Bool = false
}

// MARK: - Tolerant decoding

/// `AlarmStore.load` decodes the whole `[Alarm]` array in one shot, so a single
/// missing key would wipe every saved alarm. Only `hour`/`minute` are required;
/// every other field falls back to its default when absent (or malformed).
extension Alarm {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Alarm(hour: 0, minute: 0)
        self.init(
            id: (try? c.decodeIfPresent(String.self, forKey: .id)) ?? defaults.id,
            hour: try c.decode(Int.self, forKey: .hour),
            minute: try c.decode(Int.self, forKey: .minute),
            repeatDays: (try? c.decodeIfPresent(Set<Weekday>.self, forKey: .repeatDays)) ?? defaults.repeatDays,
            label: (try? c.decodeIfPresent(String.self, forKey: .label)) ?? defaults.label,
            tone: (try? c.decodeIfPresent(ToneSelection.self, forKey: .tone)) ?? defaults.tone,
            snoozeEnabled: (try? c.decodeIfPresent(Bool.self, forKey: .snoozeEnabled)) ?? defaults.snoozeEnabled,
            snoozeMinutes: (try? c.decodeIfPresent(Int.self, forKey: .snoozeMinutes)) ?? defaults.snoozeMinutes,
            enabled: (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? defaults.enabled,
            nextFireDate: (try? c.decodeIfPresent(Date.self, forKey: .nextFireDate)) ?? nil,
            // Legacy alarms predate the ramp: keep them at full volume.
            gradualVolume: (try? c.decodeIfPresent(Bool.self, forKey: .gradualVolume)) ?? false,
            vibrateFirst: (try? c.decodeIfPresent(Bool.self, forKey: .vibrateFirst)) ?? false
        )
    }

    /// How this alarm should ring in-app.
    var ringStyle: RingStyle {
        RingStyle(gradualVolume: gradualVolume, vibrateFirst: vibrateFirst)
    }
}

/// A concrete "ring at this moment" order handed to the notification engine.
struct FireRequest: Equatable {
    let alarmId: String
    let fireAt: Date
    let label: String
    let toneFileName: String
    var isSnooze: Bool = false
}

/// Platform boundary implemented by the UNUserNotificationCenter engine.
/// Kept as a protocol so the store is unit-testable with a fake.
protocol AlarmEngine {
    func schedule(_ request: FireRequest)
    func cancel(alarmId: String)
    func cancelAll()
}

/// Platform boundary for in-app tone playback (implemented over AVAudioPlayer).
protocol RingerControl {
    func start(toneFileName: String)
    /// Start ringing with a per-alarm style. `elapsed` is how long the alarm
    /// has already been ringing (e.g. opening the app mid-burst), so the
    /// vibrate-first / ramp timeline resumes rather than restarting.
    /// Defaulted in RingSchedule.swift to plain `start(toneFileName:)`.
    func start(toneFileName: String, style: RingStyle, elapsed: TimeInterval)
    func stop()
}
