import XCTest
@testable import AlarmClock

final class RingScheduleTests: XCTestCase {

    // MARK: - VolumeRamp

    func testRampStartsAtTenPercent() {
        XCTAssertEqual(VolumeRamp.volume(at: 0), 0.1, accuracy: 0.0001)
    }

    func testRampReachesFullAtThirtySeconds() {
        XCTAssertEqual(VolumeRamp.volume(at: 30), 1.0, accuracy: 0.0001)
    }

    func testRampClampsOutsideRange() {
        XCTAssertEqual(VolumeRamp.volume(at: -5), 0.1, accuracy: 0.0001)
        XCTAssertEqual(VolumeRamp.volume(at: 120), 1.0, accuracy: 0.0001)
    }

    func testRampIsMonotonicAndSmooth() {
        var previous = VolumeRamp.volume(at: 0)
        for step in 1...300 {
            let v = VolumeRamp.volume(at: Double(step) * 0.1)
            XCTAssertGreaterThanOrEqual(v, previous)
            // 0.1s steps never jump by more than ~1% of full scale.
            XCTAssertLessThan(v - previous, 0.01)
            previous = v
        }
    }

    func testRampEasesIn() {
        // Halfway through, still well below the linear midpoint (0.55).
        let mid = VolumeRamp.volume(at: 15)
        XCTAssertGreaterThan(mid, 0.1)
        XCTAssertLessThan(mid, 0.55)
    }

    func testRampZeroDurationIsFull() {
        XCTAssertEqual(VolumeRamp.volume(at: 0, duration: 0), 1.0)
    }

    // MARK: - RingSchedule

    func testImmediateStyleIsFullVolumeAndStatic() {
        let s = RingSchedule(style: .immediate)
        XCTAssertEqual(s.playerVolume(at: 0), 1)
        XCTAssertEqual(s.playerVolume(at: 100), 1)
        XCTAssertFalse(s.vibrates(at: 0))
        XCTAssertFalse(s.isTimeVarying)
    }

    func testGradualStyleRampsFromStart() {
        let s = RingSchedule(style: RingStyle(gradualVolume: true, vibrateFirst: false))
        XCTAssertEqual(s.soundStartsAt, 0)
        XCTAssertEqual(s.playerVolume(at: 0), 0.1, accuracy: 0.0001)
        XCTAssertEqual(s.playerVolume(at: 30), 1, accuracy: 0.0001)
        XCTAssertTrue(s.isTimeVarying)
    }

    func testVibrateFirstIsSilentForSixtySecondsThenFull() {
        let s = RingSchedule(style: RingStyle(gradualVolume: false, vibrateFirst: true))
        XCTAssertEqual(s.soundStartsAt, 60)
        XCTAssertEqual(s.playerVolume(at: 0), 0)
        XCTAssertEqual(s.playerVolume(at: 59.9), 0)
        XCTAssertEqual(s.playerVolume(at: 60), 1)
        XCTAssertTrue(s.vibrates(at: 0))
        XCTAssertTrue(s.vibrates(at: 90))
    }

    func testVibrateFirstThenRamp() {
        let s = RingSchedule(style: RingStyle(gradualVolume: true, vibrateFirst: true))
        XCTAssertEqual(s.playerVolume(at: 30), 0)
        XCTAssertEqual(s.playerVolume(at: 60), 0.1, accuracy: 0.0001)
        XCTAssertEqual(s.playerVolume(at: 75), VolumeRamp.volume(at: 15), accuracy: 0.0001)
        XCTAssertEqual(s.playerVolume(at: 90), 1, accuracy: 0.0001)
    }
}
