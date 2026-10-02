import AudioToolbox
import AVFoundation
import Foundation
import MediaPlayer
import UIKit

/// Plays the alarm tone at full effect while the app is foregrounded and
/// guards against a silenced ringer: AVAudioSession .playback ignores the
/// mute switch, and volume below the floor is reported so the UI can warn.
///
/// While ringing in the foreground, a volume guard observes the system
/// output volume and restores it if the user presses the hardware
/// volume-down button. (When the alarm fires as a notification with the
/// app dead, iOS offers no way to do this — the guard is foreground-only.)
///
/// Gradual volume and vibrate-first (see `RingSchedule`) are applied to the
/// *player* volume only; the system volume is still held up by the guard.
/// They likewise only exist in-app: notification chimes are played by iOS.
final class AlarmRinger: RingerControl {

    static let shared = AlarmRinger()
    static let minimumVolume: Float = 0.3

    private var player: AVAudioPlayer?
    private var volumeObservation: NSKeyValueObservation?
    private var volumeView: MPVolumeView?
    private var volumeFloor: Float = AlarmRinger.minimumVolume

    /// Drives the ramp / vibration timeline while ringing.
    private var ticker: Timer?
    private var schedule = RingSchedule(style: .immediate)
    private var ringStartedAt = Date()
    private var lastVibrationAt: Date?

    /// True when the system output volume is below the audible floor.
    var volumeTooLow: Bool {
        AVAudioSession.sharedInstance().outputVolume < Self.minimumVolume
    }

    func start(toneFileName: String) {
        start(toneFileName: toneFileName, style: .immediate, elapsed: 0)
    }

    func start(toneFileName: String, style: RingStyle, elapsed: TimeInterval) {
        // A second start (e.g. takeover then a notification tap) replaces the
        // current ring instead of stacking timers and observers.
        stopTimeline()
        stopVolumeGuard()
        player?.stop()
        player = nil

        let base = (toneFileName as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: "caf") else {
            NSLog("alarm: tone \(toneFileName) missing from bundle")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            schedule = RingSchedule(style: style)
            ringStartedAt = Date().addingTimeInterval(-max(elapsed, 0))
            // During vibrate-first the player runs at volume 0: still
            // "playing", so the background audio mode keeps us alive.
            player.volume = schedule.playerVolume(at: max(elapsed, 0))
            player.play()
            self.player = player
            startVolumeGuard(session: session)
            startTimeline()
        } catch {
            NSLog("alarm: ringer failed \(error)")
        }
    }

    func stop() {
        stopTimeline()
        stopVolumeGuard()
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Ramp / vibration timeline

    private func startTimeline() {
        guard schedule.isTimeVarying else { return }
        tick()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTimeline() {
        ticker?.invalidate()
        ticker = nil
        lastVibrationAt = nil
    }

    private func tick() {
        guard let player else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(ringStartedAt)
        player.volume = schedule.playerVolume(at: elapsed)
        if schedule.vibrates(at: elapsed),
           lastVibrationAt.map({ now.timeIntervalSince($0) >= RingSchedule.vibrationInterval }) ?? true {
            lastVibrationAt = now
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    // MARK: - Volume guard

    /// Observes the system output volume while ringing and restores it if the
    /// user presses the hardware volume-down button.
    private func startVolumeGuard(session: AVAudioSession) {
        volumeFloor = max(Self.minimumVolume, session.outputVolume)

        DispatchQueue.main.async { [weak self] in
            self?.installHiddenVolumeView()
        }

        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self, let newVolume = change.newValue else { return }
            if newVolume < self.volumeFloor {
                self.restoreVolume(to: self.volumeFloor)
            }
        }
    }

    private func stopVolumeGuard() {
        volumeObservation?.invalidate()
        volumeObservation = nil
        DispatchQueue.main.async { [weak self] in
            self?.volumeView?.removeFromSuperview()
            self?.volumeView = nil
        }
    }

    /// iOS has no public API to set the system volume directly; a hidden
    /// MPVolumeView's slider is the standard workaround. The view must live
    /// in a window for its slider to take effect.
    private func installHiddenVolumeView() {
        guard volumeView == nil, let window = Self.keyWindow() else { return }
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        view.clipsToBounds = true
        window.addSubview(view)
        volumeView = view
    }

    private func restoreVolume(to volume: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.installHiddenVolumeView()
            guard let view = self.volumeView,
                  let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
            // A tiny delay lets the slider attach to the system volume
            // service before the value is applied.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                slider.value = volume
            }
        }
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .keyWindow
    }
}
