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
    /// Per-weekday time overrides for repeating alarms (e.g. Fri 8:30 while
    /// the alarm's default is 7:00). Days without an entry use hour/minute.
    var timeOverrides: [Weekday: ClockTime] = [:]
    /// The exact occurrence the user chose to skip ("Skip next"). Only honored
    /// while it is still the alarm's next occurrence; cleared once it passes.
    var skippedFireDate: Date? = nil
}

/// Saved-data compatibility: every field except hour/minute is optional in the
/// JSON and falls back to its default, so adding fields never wipes alarms
/// saved by an older build. A malformed optional field also falls back rather
/// than failing the whole `[Alarm]` decode.
extension Alarm {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hour = try c.decode(Int.self, forKey: .hour)
        let minute = try c.decode(Int.self, forKey: .minute)
        var alarm = Alarm(hour: hour, minute: minute)
        func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        alarm.id = field(.id, alarm.id)
        alarm.repeatDays = field(.repeatDays, alarm.repeatDays)
        alarm.label = field(.label, alarm.label)
        alarm.tone = field(.tone, alarm.tone)
        alarm.snoozeEnabled = field(.snoozeEnabled, alarm.snoozeEnabled)
        alarm.snoozeMinutes = field(.snoozeMinutes, alarm.snoozeMinutes)
        alarm.enabled = field(.enabled, alarm.enabled)
        alarm.nextFireDate = try? c.decodeIfPresent(Date.self, forKey: .nextFireDate)
        alarm.timeOverrides = field(.timeOverrides, alarm.timeOverrides)
        alarm.skippedFireDate = try? c.decodeIfPresent(Date.self, forKey: .skippedFireDate)
        self = alarm
    }
}

/// A wall-clock hour/minute pair (0..23, 0..59).
struct ClockTime: Codable, Equatable, Hashable {
    var hour: Int
    var minute: Int
}

/// Lets `[Weekday: X]` encode as a JSON object keyed by ISO day number
/// (`{"5": ...}`) instead of an alternating key/value array.
extension Weekday: CodingKeyRepresentable {
    private struct DayKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue; self.intValue = Int(stringValue) }
        init(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    var codingKey: CodingKey { DayKey(intValue: rawValue) }

    init?<T: CodingKey>(codingKey: T) {
        guard let raw = codingKey.intValue ?? Int(codingKey.stringValue) else { return nil }
        self.init(rawValue: raw)
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
    func stop()
}
