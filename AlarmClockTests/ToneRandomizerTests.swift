import XCTest
@testable import AlarmClock

/// Deterministic SplitMix64 generator so tone-random tests are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class ToneRandomizerTests: XCTestCase {

    private let tones = bundledTones

    func testPinnedReturnsThePinnedTone() {
        let r = ToneRandomizer(tones: tones)
        var g = SeededGenerator(seed: 42)
        let tone = r.resolve(selection: .pinned(toneId: "cosmic"), lastToneId: nil, using: &g)
        XCTAssertEqual(tone.id, "cosmic")
    }

    func testPinnedUnknownIdFallsBackToFirstTone() {
        let r = ToneRandomizer(tones: tones)
        var g = SeededGenerator(seed: 42)
        let tone = r.resolve(selection: .pinned(toneId: "does-not-exist"), lastToneId: nil, using: &g)
        XCTAssertEqual(tone.id, tones.first!.id)
    }

    func testRandomReturnsAToneFromCatalog() {
        let r = ToneRandomizer(tones: tones)
        var g = SeededGenerator(seed: 42)
        let tone = r.resolve(selection: .random, lastToneId: nil, using: &g)
        XCTAssertTrue(tones.contains { $0.id == tone.id })
    }

    func testRandomNeverRepeatsLastTone() {
        let r = ToneRandomizer(tones: tones)
        var g = SeededGenerator(seed: 7)
        for last in tones.map({ $0.id }) {
            for _ in 0..<50 {
                let tone = r.resolve(selection: .random, lastToneId: last, using: &g)
                XCTAssertNotEqual(tone.id, last, "picked \(last) twice in a row")
            }
        }
    }

    func testRandomEventuallyCoversAllOtherTones() {
        let r = ToneRandomizer(tones: tones)
        var g = SeededGenerator(seed: 1)
        var seen = Set<String>()
        for _ in 0..<500 {
            seen.insert(r.resolve(selection: .random, lastToneId: "radial", using: &g).id)
        }
        let expected = Set(tones.map { $0.id }).subtracting(["radial"])
        XCTAssertEqual(seen, expected)
    }

    func testRandomDeterministicForSameSeed() {
        let r = ToneRandomizer(tones: tones)
        var a = SeededGenerator(seed: 99)
        var b = SeededGenerator(seed: 99)
        for _ in 0..<20 {
            XCTAssertEqual(
                r.resolve(selection: .random, lastToneId: nil, using: &a).id,
                r.resolve(selection: .random, lastToneId: nil, using: &b).id
            )
        }
    }

    func testSingleToneCatalogRandomAlwaysReturnsItEvenIfLast() {
        let single = [tones.first!]
        let r = ToneRandomizer(tones: single)
        var g = SeededGenerator(seed: 3)
        let tone = r.resolve(selection: .random, lastToneId: tones.first!.id, using: &g)
        XCTAssertEqual(tone.id, tones.first!.id)
    }

    func testResolveWithSystemGeneratorOverload() {
        let r = ToneRandomizer(tones: tones)
        let tone = r.resolve(selection: .pinned(toneId: "beacon"), lastToneId: nil)
        XCTAssertEqual(tone.id, "beacon")
    }
}
