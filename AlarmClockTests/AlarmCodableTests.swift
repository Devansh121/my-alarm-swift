import XCTest
@testable import AlarmClock

/// Saved-data compatibility: AlarmStore.load treats any decode failure as
/// "no alarms", so older JSON must always decode.
final class AlarmCodableTests: XCTestCase {

    private func decode(_ json: String) throws -> [Alarm] {
        try JSONDecoder().decode([Alarm].self, from: Data(json.utf8))
    }

    func testLegacyMinimalJSONDecodesWithDefaults() throws {
        let alarms = try decode(#"[{"id":"a1","hour":7,"minute":30}]"#)
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
        XCTAssertEqual(a.timeOverrides, [:])
        XCTAssertNil(a.skippedFireDate)
    }

    func testPreviousBuildFormatDecodes() throws {
        // Exactly what the pre-scheduling-upgrades build wrote.
        let legacy = Alarm(id: "a2", hour: 6, minute: 15, repeatDays: [.monday, .friday],
                           label: "Gym", tone: .pinned(toneId: "waves"),
                           snoozeEnabled: false, snoozeMinutes: 5, enabled: false,
                           nextFireDate: Date(timeIntervalSinceReferenceDate: 800_000_000))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
        )
        object.removeValue(forKey: "timeOverrides")
        object.removeValue(forKey: "skippedFireDate")
        let data = try JSONSerialization.data(withJSONObject: [object])
        let decoded = try JSONDecoder().decode([Alarm].self, from: data)
        XCTAssertEqual(decoded, [legacy])
    }

    func testMissingIdGetsGenerated() throws {
        let alarms = try decode(#"[{"hour":7,"minute":0}]"#)
        XCTAssertFalse(alarms[0].id.isEmpty)
    }

    func testMalformedOptionalFieldFallsBackInsteadOfWipingAll() throws {
        let alarms = try decode(#"[{"id":"a1","hour":7,"minute":0,"tone":"garbage","timeOverrides":42},{"id":"a2","hour":8,"minute":0}]"#)
        XCTAssertEqual(alarms.map(\.id), ["a1", "a2"])
        XCTAssertEqual(alarms[0].tone, .random)
        XCTAssertEqual(alarms[0].timeOverrides, [:])
    }

    func testMissingHourStillFails() {
        XCTAssertThrowsError(try decode(#"[{"id":"a1","minute":0}]"#))
    }

    func testRoundTripIncludingNewFields() throws {
        var alarm = Alarm(id: "a3", hour: 7, minute: 0, repeatDays: [.monday, .friday, .saturday])
        alarm.timeOverrides = [.friday: ClockTime(hour: 8, minute: 30), .saturday: ClockTime(hour: 9, minute: 0)]
        alarm.skippedFireDate = Date(timeIntervalSinceReferenceDate: 812_345_640)
        alarm.nextFireDate = Date(timeIntervalSinceReferenceDate: 812_432_040)
        let data = try JSONEncoder().encode([alarm])
        XCTAssertEqual(try JSONDecoder().decode([Alarm].self, from: data), [alarm])
    }

    func testOverridesEncodeAsObjectKeyedByISODay() throws {
        var alarm = Alarm(id: "a4", hour: 7, minute: 0, repeatDays: [.friday])
        alarm.timeOverrides = [.friday: ClockTime(hour: 8, minute: 30)]
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(alarm)) as? [String: Any]
        )
        let overrides = try XCTUnwrap(object["timeOverrides"] as? [String: Any])
        let friday = try XCTUnwrap(overrides["5"] as? [String: Int])
        XCTAssertEqual(friday, ["hour": 8, "minute": 30])
    }
}
