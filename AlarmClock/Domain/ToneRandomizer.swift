import Foundation

/// Resolves an alarm's `ToneSelection` to a concrete `Tone`.
///
/// Random picks avoid repeating `lastToneId` so back-to-back alarms sound
/// different (unless the catalog has a single tone). Unknown pinned ids fall
/// back to the first catalog tone rather than failing at ring time.
struct ToneRandomizer {
    private let tones: [Tone]

    init(tones: [Tone] = bundledTones) {
        precondition(!tones.isEmpty, "tone catalog must not be empty")
        self.tones = tones
    }

    /// Resolve `selection` to a `Tone`, drawing randomness from `generator`
    /// (injected so tests can be deterministic).
    func resolve<G: RandomNumberGenerator>(
        selection: ToneSelection,
        lastToneId: String?,
        using generator: inout G
    ) -> Tone {
        switch selection {
        case .pinned(let toneId):
            return tones.first { $0.id == toneId } ?? tones[0]
        case .random:
            var candidates = tones.filter { $0.id != lastToneId }
            if candidates.isEmpty { candidates = tones }
            let index = Int(generator.next(upperBound: UInt(candidates.count)))
            return candidates[index]
        }
    }

    /// Convenience overload using the system generator.
    func resolve(selection: ToneSelection, lastToneId: String?) -> Tone {
        var generator = SystemRandomNumberGenerator()
        return resolve(selection: selection, lastToneId: lastToneId, using: &generator)
    }
}
