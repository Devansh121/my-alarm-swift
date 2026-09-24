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
    Tone(id: "radial", displayName: "Radial", fileName: "tone_radial.caf"),
    Tone(id: "ascent", displayName: "Ascent", fileName: "tone_ascent.caf"),
    Tone(id: "pulse", displayName: "Pulse", fileName: "tone_pulse.caf"),
    Tone(id: "chimes", displayName: "Chimes", fileName: "tone_chimes.caf"),
    Tone(id: "cosmic", displayName: "Cosmic", fileName: "tone_cosmic.caf"),
    Tone(id: "beacon", displayName: "Beacon", fileName: "tone_beacon.caf"),
    Tone(id: "signal", displayName: "Signal", fileName: "tone_signal.caf"),
    Tone(id: "waves", displayName: "Waves", fileName: "tone_waves.caf"),
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
