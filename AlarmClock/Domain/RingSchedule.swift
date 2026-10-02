import Foundation

/// Per-alarm in-app ringing options.
struct RingStyle: Equatable {
    var gradualVolume: Bool
    var vibrateFirst: Bool

    /// The pre-feature behavior: full volume immediately, no vibration.
    static let immediate = RingStyle(gradualVolume: false, vibrateFirst: false)
}

/// Pure timeline for an in-app ring: what the player volume should be and
/// whether to vibrate, `elapsed` seconds after the alarm started ringing.
///
/// Timeline:
///   - vibrate-first: player volume 0 (still playing, so the audio session
///     keeps the app alive in the background) for `vibrateOnlyDuration`,
///     vibrating every `vibrationInterval`; vibration continues once sound starts.
///   - then sound: ramps via `VolumeRamp` when gradual, otherwise full volume.
///
/// Only the in-app ringer follows this. Notification-delivered chimes are
/// played by iOS at the system volume and can neither ramp nor vibrate-first.
struct RingSchedule: Equatable {
    static let vibrateOnlyDuration: TimeInterval = 60
    static let vibrationInterval: TimeInterval = 1.5

    let style: RingStyle

    /// Seconds after ring start at which the tone becomes audible.
    var soundStartsAt: TimeInterval {
        style.vibrateFirst ? Self.vibrateOnlyDuration : 0
    }

    func playerVolume(at elapsed: TimeInterval) -> Float {
        let sinceSound = elapsed - soundStartsAt
        if sinceSound < 0 { return 0 }
        return style.gradualVolume ? VolumeRamp.volume(at: sinceSound) : 1
    }

    func vibrates(at elapsed: TimeInterval) -> Bool {
        style.vibrateFirst
    }

    /// Whether anything changes over time (otherwise no ticker is needed).
    var isTimeVarying: Bool { style.gradualVolume || style.vibrateFirst }
}

/// Gradual-wake volume curve for the in-app player.
///
/// Quadratic ease-in from `from` to `to` over `duration`: perceived loudness
/// is roughly logarithmic in amplitude, so a linear amplitude ramp sounds
/// like it jumps early and then stalls; easing in keeps the rise gentle at
/// first and steady toward full volume.
enum VolumeRamp {
    static let duration: TimeInterval = 30
    static let startVolume: Float = 0.1

    static func volume(
        at elapsed: TimeInterval,
        duration: TimeInterval = VolumeRamp.duration,
        from: Float = VolumeRamp.startVolume,
        to: Float = 1.0
    ) -> Float {
        guard duration > 0 else { return to }
        let t = Float(min(max(elapsed / duration, 0), 1))
        return from + (to - from) * t * t
    }
}

extension RingerControl {
    /// Fakes and simple ringers that don't support styles just ring plainly.
    func start(toneFileName: String, style: RingStyle, elapsed: TimeInterval) {
        start(toneFileName: toneFileName)
    }
}
