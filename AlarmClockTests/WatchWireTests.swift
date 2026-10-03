import XCTest
@testable import AlarmClock

final class WatchWireTests: XCTestCase {

    private func at(_ seconds: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }

    // MARK: - Encoding

    func testEncodesEveryWatchVisibleField() {
        var alarm = Alarm(id: "a1", hour: 7, minute: 5, repeatDays: [.friday, .monday],
                          label: "Gym", snoozeEnabled: false, snoozeMinutes: 12, enabled: true)
        alarm.updatedAt = at(1_790_000_000)
        alarm.nextFireDate = at(1_790_100_000)
        alarm.skippedFireDate = at(1_790_050_000)
        alarm.snoozedUntil = at(1_790_000_600)
        alarm.timeOverrides = [.friday: ClockTime(hour: 8, minute: 30)]

        let out = WatchWire.encode(alarm)

        XCTAssertEqual(out["id"] as? String, "a1")
        XCTAssertEqual(out["h"] as? Int, 7)
        XCTAssertEqual(out["m"] as? Int, 5)
        XCTAssertEqual(out["d"] as? [Int], [1, 5])
        XCTAssertEqual(out["l"] as? String, "Gym")
        XCTAssertEqual(out["e"] as? Bool, true)
        XCTAssertEqual(out["sn"] as? Bool, false)
        XCTAssertEqual(out["sm"] as? Int, 12)
        XCTAssertEqual(out["u"] as? Int, 1_790_000_000)
        XCTAssertEqual(out["nf"] as? Int, 1_790_100_000)
        XCTAssertEqual(out["sk"] as? Int, 1_790_050_000)
        XCTAssertEqual(out["sz"] as? Int, 1_790_000_600)
        XCTAssertEqual(out["ov"] as? [String: [Int]], ["5": [8, 30]])
    }

    func testOptionalFieldsAreLeftOutNotNull() {
        let out = WatchWire.encode(Alarm(id: "a1", hour: 7, minute: 0))
        for key in ["nf", "sk", "sz", "ov"] {
            XCTAssertNil(out[key], key)
        }
        XCTAssertEqual(out["u"] as? Int, 0)
        XCTAssertEqual(out["d"] as? [Int], [])
    }

    func testSnapshotEnvelope() {
        let snap = WatchWire.snapshot(
            alarms: [Alarm(id: "a1", hour: 7, minute: 0), Alarm(id: "a2", hour: 8, minute: 0)],
            acked: ["w1-1"], now: at(1_790_000_000)
        )
        XCTAssertEqual(snap["t"] as? String, "snap")
        XCTAssertEqual(snap["v"] as? Int, 1)
        XCTAssertEqual(snap["ts"] as? Int, 1_790_000_000)
        XCTAssertEqual(snap["ack"] as? [String], ["w1-1"])
        XCTAssertEqual((snap["alarms"] as? [[String: Any]])?.compactMap { $0["id"] as? String }, ["a1", "a2"])
    }

    func testSnapshotSurvivesJSONRoundTrip() throws {
        // The SDK needs property-list-like values; JSON serialisability is a
        // good proxy for "no Swift-only types slipped in".
        var alarm = Alarm(id: "a1", hour: 7, minute: 0, repeatDays: [.monday])
        alarm.timeOverrides = [.monday: ClockTime(hour: 6, minute: 0)]
        let snap = WatchWire.snapshot(alarms: [alarm], acked: [], now: at(1))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(snap))
    }

    // MARK: - Decoding

    func testDecodesSyncOps() throws {
        let message: [String: Any] = [
            "t": "sync", "v": 1,
            "ops": [
                ["oid": "w1-1", "op": "put", "id": "w9", "at": 1_790_000_000,
                 "f": ["h": 6, "m": 45, "d": [1, 2, 3], "l": "Run", "sn": true, "sm": 5]],
                ["oid": "w1-2", "op": "en", "id": "a1", "at": 1_790_000_010, "e": false],
                ["oid": "w1-3", "op": "del", "id": "a2", "at": 1_790_000_020],
            ],
        ]
        let ops = try XCTUnwrap(WatchWire.decodeSync(message))
        XCTAssertEqual(ops.count, 3)

        XCTAssertEqual(ops[0].kind, .put)
        XCTAssertEqual(ops[0].alarmId, "w9")
        XCTAssertEqual(ops[0].at, at(1_790_000_000))
        XCTAssertEqual(ops[0].fields.hour, 6)
        XCTAssertEqual(ops[0].fields.minute, 45)
        XCTAssertEqual(ops[0].fields.repeatDays, [.monday, .tuesday, .wednesday])
        XCTAssertEqual(ops[0].fields.label, "Run")
        XCTAssertEqual(ops[0].fields.snoozeEnabled, true)
        XCTAssertEqual(ops[0].fields.snoozeMinutes, 5)
        XCTAssertFalse(ops[0].fields.malformed)

        XCTAssertEqual(ops[1].kind, .en)
        XCTAssertEqual(ops[1].enabled, false)
        XCTAssertEqual(ops[2].kind, .del)
    }

    func testEmptySyncIsAHello() {
        XCTAssertEqual(WatchWire.decodeSync(["t": "sync", "v": 1])?.count, 0)
    }

    func testIgnoresOtherMessagesAndNewerVersions() {
        XCTAssertNil(WatchWire.decodeSync(["t": "snap", "v": 1]))
        XCTAssertNil(WatchWire.decodeSync(["t": "sync", "v": 2, "ops": []]))
        XCTAssertNil(WatchWire.decodeSync(["t": "sync"]))
        XCTAssertNil(WatchWire.decodeSync("hello"))
    }

    func testOpsWithoutIdsAreDroppedUnknownKindsKept() throws {
        let ops = try XCTUnwrap(WatchWire.decodeSync([
            "t": "sync", "v": 1,
            "ops": [
                ["op": "del", "id": "a1", "at": 1],
                ["oid": "w1-2", "op": "del", "at": 1],
                ["oid": "w1-3", "op": "rename", "id": "a1", "at": 1],
                "garbage",
            ],
        ]))
        XCTAssertEqual(ops.map(\.oid), ["w1-3"])
        XCTAssertNil(ops[0].kind)
    }

    func testMalformedFieldsAreFlagged() {
        XCTAssertTrue(WatchWire.decodeFields(["h": "seven"]).malformed)
        XCTAssertTrue(WatchWire.decodeFields(["d": [1, 9]]).malformed)
        XCTAssertTrue(WatchWire.decodeFields(["d": "Mon"]).malformed)
        XCTAssertTrue(WatchWire.decodeFields(["l": 5]).malformed)
        XCTAssertTrue(WatchWire.decodeFields(["sn": "yes"]).malformed)
        XCTAssertTrue(WatchWire.decodeFields(["m": 7.5]).malformed)
        XCTAssertFalse(WatchWire.decodeFields(["h": 7.0, "sn": 1]).malformed)
    }

    func testNumbersArriveAsNSNumberOrFloat() {
        XCTAssertEqual(WatchWire.int(NSNumber(value: 42)), 42)
        XCTAssertEqual(WatchWire.int(42.0), 42)
        XCTAssertEqual(WatchWire.int(Int64(1_790_000_000)), 1_790_000_000)
        XCTAssertNil(WatchWire.int(4.2))
        XCTAssertNil(WatchWire.int("4"))
        XCTAssertEqual(WatchWire.bool(true), true)
        XCTAssertEqual(WatchWire.bool(0), false)
        XCTAssertNil(WatchWire.bool(2))
    }

    func testEpochRoundsDown() {
        XCTAssertEqual(WatchWire.epoch(Date(timeIntervalSince1970: 99.9)), 99)
    }
}
