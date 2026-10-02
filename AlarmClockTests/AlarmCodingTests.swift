import XCTest
@testable import AlarmClock

/// Saved-data compatibility: a decode failure wipes every alarm, so older
/// files (missing newer keys) must keep loading with defaults.
final class AlarmCodingTests: XCTestCase {

    func testLegacyMinimalJSONDecodesWithDefaults() throws {
        let json = #"[{"id":"a1","hour":7,"minute":30}]"#.data(using: .utf8)!
        let alarms = try JSONDecoder().decode([Alarm].self, from: json)
        XCTAssertEqual(alarms.count, 1)
        let a = alarms[0]
        XCTAssertEqual(a.id, "a1")
        XCTAssertEqual(a.hour, 7)
        XCTAssertEqual(a.minute, 30)
        XCTAssertEqual(a.repeatDays, [])
        XCTAssertEqual(a.label, "Alarm")
        XCTAssertEqual(a.tone, .random)
        XCTAssertTrue(a.snoozeEnabled)
        XCTAssertEqual(a.snoozeMinutes, 9)
        XCTAssertTrue(a.enabled)
        XCTAssertNil(a.nextFireDate)
        // Existing alarms keep their old (full-volume, no vibrate) behavior.
        XCTAssertFalse(a.gradualVolume)
        XCTAssertFalse(a.vibrateFirst)
    }

    func testPreFeatureSavedAlarmDecodesAsNoRamp() throws {
        // Shape written by the previous app version (no ramp/vibrate keys).
        let json = """
        [{"id":"a2","hour":6,"minute":15,"repeatDays":[1,5],"label":"Work",
          "tone":{"pinned":{"toneId":"waves"}},"snoozeEnabled":false,
          "snoozeMinutes":5,"enabled":false}]
        """.data(using: .utf8)!
        let a = try JSONDecoder().decode([Alarm].self, from: json)[0]
        XCTAssertEqual(a.repeatDays, [.monday, .friday])
        XCTAssertEqual(a.label, "Work")
        XCTAssertEqual(a.tone, .pinned(toneId: "waves"))
        XCTAssertFalse(a.snoozeEnabled)
        XCTAssertEqual(a.snoozeMinutes, 5)
        XCTAssertFalse(a.enabled)
        XCTAssertFalse(a.gradualVolume)
    }

    func testMissingIdGetsGenerated() throws {
        let json = #"[{"hour":7,"minute":0}]"#.data(using: .utf8)!
        let a = try JSONDecoder().decode([Alarm].self, from: json)[0]
        XCTAssertFalse(a.id.isEmpty)
    }

    func testMissingHourFails() {
        let json = #"[{"id":"a1","minute":0}]"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode([Alarm].self, from: json))
    }

    func testNewAlarmsDefaultToGradualVolumeOn() {
        let a = Alarm(hour: 7, minute: 0)
        XCTAssertTrue(a.gradualVolume)
        XCTAssertFalse(a.vibrateFirst)
    }

    func testRoundTripPreservesAllFields() throws {
        let original = Alarm(
            id: "rt", hour: 5, minute: 45, repeatDays: [.saturday, .sunday],
            label: "Gym", tone: .pinned(toneId: "chimes"), snoozeEnabled: false,
            snoozeMinutes: 15, enabled: false,
            nextFireDate: Date(timeIntervalSince1970: 1_800_000_000),
            gradualVolume: false, vibrateFirst: true
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([Alarm].self, from: data)
        XCTAssertEqual(decoded, [original])

        var flipped = original
        flipped.gradualVolume = true
        flipped.vibrateFirst = false
        let again = try JSONDecoder().decode([Alarm].self, from: JSONEncoder().encode([flipped]))
        XCTAssertEqual(again, [flipped])
    }

    func testStoreLoadsLegacyFileWithoutWipingAlarms() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"[{"id":"a1","hour":7,"minute":30}]"#.data(using: .utf8)!.write(to: url)
        let store = AlarmStore(engine: NoopEngine(), ringer: NoopRinger(), persistenceURL: url)
        XCTAssertEqual(store.alarms.map(\.id), ["a1"])
        XCTAssertFalse(store.alarms[0].gradualVolume)
    }
}
