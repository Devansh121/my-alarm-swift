import XCTest
@testable import AlarmClock

private final class StyleRecordingRinger: RingerControl {
    var starts: [(tone: String, style: RingStyle?, elapsed: TimeInterval)] = []
    var stopped = 0
    func start(toneFileName: String) { starts.append((toneFileName, nil, 0)) }
    func start(toneFileName: String, style: RingStyle, elapsed: TimeInterval) {
        starts.append((toneFileName, style, elapsed))
    }
    func stop() { stopped += 1 }
}

/// The store hands each alarm's ring style (and how long it has already been
/// ringing) to the ringer, and stop/snooze silence it immediately.
final class RingStyleStoreTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ring-style-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    private func seed(_ alarm: Alarm) {
        try! JSONEncoder().encode([alarm]).write(to: tempURL)
    }

    func testFiredAlarmPassesItsStyle() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let ringer = StyleRecordingRinger()
        let store = AlarmStore(engine: NoopEngine(), ringer: ringer,
                               persistenceURL: tempURL, now: { clock })
        var a = Alarm(hour: 7, minute: 0)
        a.id = "a1"
        a.gradualVolume = true
        a.vibrateFirst = true
        store.upsert(a)
        clock = store.alarms[0].nextFireDate!
        store.onAlarmFired(id: "a1")
        XCTAssertEqual(ringer.starts.count, 1)
        XCTAssertEqual(ringer.starts[0].style, RingStyle(gradualVolume: true, vibrateFirst: true))
        XCTAssertEqual(ringer.starts[0].elapsed, 0)
    }

    func testTakeoverResumesTimelineFromFireTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var a = Alarm(hour: 7, minute: 0)
        a.id = "a1"
        a.vibrateFirst = true
        a.nextFireDate = now.addingTimeInterval(-90)
        seed(a)
        let ringer = StyleRecordingRinger()
        let store = AlarmStore(engine: NoopEngine(), ringer: ringer,
                               persistenceURL: tempURL, now: { now })
        XCTAssertEqual(store.ringing?.id, "a1")
        XCTAssertEqual(ringer.starts.count, 1)
        XCTAssertEqual(ringer.starts[0].elapsed, 90, accuracy: 0.001)
        XCTAssertEqual(ringer.starts[0].style?.vibrateFirst, true)
    }

    func testRepeatedFireWhileRingingDoesNotRestartRinger() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var a = Alarm(hour: 7, minute: 0)
        a.id = "a1"
        a.nextFireDate = now.addingTimeInterval(-30)
        seed(a)
        let ringer = StyleRecordingRinger()
        let store = AlarmStore(engine: NoopEngine(), ringer: ringer,
                               persistenceURL: tempURL, now: { now })
        XCTAssertEqual(ringer.starts.count, 1)
        store.onAlarmFired(id: "a1") // notification tap after takeover
        XCTAssertEqual(ringer.starts.count, 1)
    }

    func testStopAndSnoozeSilenceRinger() {
        let ringer = StyleRecordingRinger()
        let store = AlarmStore(engine: NoopEngine(), ringer: ringer, persistenceURL: tempURL)
        var a = Alarm(hour: 7, minute: 0)
        a.id = "a1"
        a.vibrateFirst = true
        store.upsert(a)
        store.onAlarmFired(id: "a1")
        store.snoozeRinging()
        XCTAssertEqual(ringer.stopped, 1)
        XCTAssertNil(store.ringing)
        store.onAlarmFired(id: "a1")
        store.stopRinging()
        XCTAssertEqual(ringer.stopped, 2)
        XCTAssertNil(store.ringing)
    }

    func testElapsedRingingClampsToRingWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(AlarmStore.elapsedRinging(since: nil, now: now), 0)
        XCTAssertEqual(AlarmStore.elapsedRinging(since: now.addingTimeInterval(10), now: now), 0)
        XCTAssertEqual(AlarmStore.elapsedRinging(since: now.addingTimeInterval(-45), now: now), 45)
        XCTAssertEqual(AlarmStore.elapsedRinging(since: now.addingTimeInterval(-600), now: now), 0)
    }
}
