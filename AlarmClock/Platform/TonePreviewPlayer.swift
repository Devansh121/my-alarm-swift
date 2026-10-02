import AVFoundation
import Foundation

/// Lightweight tone auditioning for the Sound picker.
///
/// Unlike `AlarmRinger`, this is deliberately minimal: it uses the `.ambient`
/// audio session category so previews respect the hardware mute switch and mix
/// politely with other audio (no volume guard, no full-effect ringing). A
/// preview auto-stops after a few seconds, and starting a new one cancels the
/// previous playback and its timer.
final class TonePreviewPlayer: ObservableObject {

    /// File name of the tone currently previewing, or nil when silent — lets
    /// the UI show a speaker indicator on the active row.
    @Published private(set) var playingFileName: String?

    private var player: AVAudioPlayer?
    private var autoStop: DispatchWorkItem?

    /// How long a preview plays before auto-stopping.
    private let previewDuration: TimeInterval = 4

    func play(toneFileName: String) {
        stop()

        let base = (toneFileName as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: "caf") else {
            NSLog("preview: tone \(toneFileName) missing from bundle")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            self.player = player
            playingFileName = toneFileName

            let work = DispatchWorkItem { [weak self] in self?.stop() }
            autoStop = work
            DispatchQueue.main.asyncAfter(deadline: .now() + previewDuration, execute: work)
        } catch {
            NSLog("preview: playback failed \(error)")
        }
    }

    func stop() {
        autoStop?.cancel()
        autoStop = nil
        player?.stop()
        player = nil
        playingFileName = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
