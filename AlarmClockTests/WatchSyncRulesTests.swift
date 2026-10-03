import XCTest
@testable import AlarmClock

final class WatchSyncRulesTests: XCTestCase {

    private func at(_ seconds: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }

    private func op(_ kind: WatchWire.Op.Kind?, _ id: String, at seconds: Int,
                    fields: WatchWire.Fields = .init(), enabled: Bool? = nil) -> WatchWire.Op {
        WatchWire.Op(oid: "o", kind: kind, alarmId: id, at: at(seconds), fields: fields, enabled: enabled)
    }

    private func alarm(_ id: String, updatedAt seconds: Int? = nil) -> Alarm {
        var alarm = Alarm(id: id, hour: 7, minute: 0, repeatDays: [.monday], label: "Wake")
        alarm.updatedAt = seconds.map(at)
        alarm.tone = .pinned(toneId: "waves")
        alarm.timeOverrides = [.monday: ClockTime(hour: 6, minute: 30)]
        return alarm
    }

    // MARK: - Last writer wins

    func testWatchEditNewerThanPhoneEditApplies() {
        let decision = WatchSyncRules.decide(
            op(.put, "a1", at: 200, fields: .init(hour: 9)),
            alarms: [alarm("a1", updatedAt: 100)], tombstones: [:]
        )
        guard case .upsert(let patched) = decision else { return XCTFail("\(decision)") }
        XCTAssertEqual(patched.hour, 9)
    }

    func testPhoneEditNewerThanWatchEditWins() {
        XCTAssertEqual(
            WatchSyncRules.decide(op(.put, "a1", at: 100, fields: .init(hour: 9)),
                                  alarms: [alarm("a1", updatedAt: 200)], tombstones: [:]),
            .reject(.staleEdit)
        )
        XCTAssertEqual(
            WatchSyncRules.decide(op(.del, "a1", at: 100), alarms: [alarm("a1", updatedAt: 200)], tombstones: [:]),
            .reject(.staleEdit)
        )
    }

    func testSameSecondGoesToTheWatch() {
        XCTAssertEqual(
            WatchSyncRules.decide(op(.en, "a1", at: 100, enabled: false),
                                  alarms: [alarm("a1", updatedAt: 100)], tombstones: [:]),
            .setEnabled(id: "a1", false)
        )
    }

    func testSubSecondPhoneEditDoesNotBeatSameSecondWatchEdit() {
        var a = alarm("a1")
        a.updatedAt = Date(timeIntervalSince1970: 100.8)
        XCTAssertEqual(
            WatchSyncRules.decide(op(.del, "a1", at: 100), alarms: [a], tombstones: [:]),
            .delete(id: "a1")
        )
    }

    func testAlarmNeverEditedSinceSyncAcceptsAnyWatchEdit() {
        XCTAssertEqual(
            WatchSyncRules.decide(op(.skip, "a1", at: 1), alarms: [alarm("a1")], tombstones: [:]),
            .skip(id: "a1")
        )
    }

    // MARK: - Patching

    func testPutPatchesOnlyGivenFieldsAndKeepsPhoneOnlyOnes() {
        let decision = WatchSyncRules.decide(
            op(.put, "a1", at: 200, fields: .init(minute: 15, repeatDays: [.saturday], label: "  Long run  ",
                                                    snoozeEnabled: false, snoozeMinutes: 20)),
            alarms: [alarm("a1", updatedAt: 100)], tombstones: [:]
        )
        guard case .upsert(let patched) = decision else { return XCTFail("\(decision)") }
        XCTAssertEqual(patched.hour, 7)
        XCTAssertEqual(patched.minute, 15)
        XCTAssertEqual(patched.repeatDays, [.saturday])
        XCTAssertEqual(patched.label, "Long run")
        XCTAssertFalse(patched.snoozeEnabled)
        XCTAssertEqual(patched.snoozeMinutes, 20)
        XCTAssertEqual(patched.tone, .pinned(toneId: "waves"))
        XCTAssertEqual(patched.timeOverrides, [.monday: ClockTime(hour: 6, minute: 30)])
    }

    func testEmptyDaysMakesAOneShot() {
        let decision = WatchSyncRules.decide(op(.put, "a1", at: 200, fields: .init(repeatDays: [])),
                                             alarms: [alarm("a1")], tombstones: [:])
        guard case .upsert(let patched) = decision else { return XCTFail("\(decision)") }
        XCTAssertEqual(patched.repeatDays, [])
    }

    func testInvalidValuesRejectTheWholePut() {
        let bad: [WatchWire.Fields] = [
            .init(hour: 24), .init(hour: -1), .init(minute: 60),
            .init(label: "   "), .init(snoozeMinutes: 0), .init(snoozeMinutes: 31),
            .init(hour: 8, malformed: true),
        ]
        for fields in bad {
            XCTAssertEqual(
                WatchSyncRules.decide(op(.put, "a1", at: 200, fields: fields), alarms: [alarm("a1")], tombstones: [:]),
                .reject(.invalid), "\(fields)"
            )
        }
    }

    func testLongLabelIsCut() {
        let decision = WatchSyncRules.decide(
            op(.put, "a1", at: 200, fields: .init(label: String(repeating: "x", count: 100))),
            alarms: [alarm("a1")], tombstones: [:]
        )
        guard case .upsert(let patched) = decision else { return XCTFail("\(decision)") }
        XCTAssertEqual(patched.label.count, WatchSyncRules.maxLabelLength)
    }

    // MARK: - Creating

    func testPutOnUnknownIdCreatesWithPhoneDefaults() {
        let decision = WatchSyncRules.decide(
            op(.put, "w42", at: 200, fields: .init(hour: 6, minute: 0, repeatDays: [.monday, .friday])),
            alarms: [], tombstones: [:]
        )
        guard case .upsert(let created) = decision else { return XCTFail("\(decision)") }
        let defaults = Alarm(hour: 0, minute: 0)
        XCTAssertEqual(created.id, "w42")
        XCTAssertEqual(created.hour, 6)
        XCTAssertEqual(created.repeatDays, [.monday, .friday])
        XCTAssertEqual(created.label, defaults.label)
        XCTAssertEqual(created.enabled, true)
        XCTAssertEqual(created.tone, defaults.tone)
        XCTAssertEqual(created.snoozeMinutes, defaults.snoozeMinutes)
        XCTAssertEqual(created.gradualVolume, defaults.gradualVolume)
    }

    func testCreateNeedsATime() {
        XCTAssertEqual(
            WatchSyncRules.decide(op(.put, "w42", at: 200, fields: .init(hour: 6)), alarms: [], tombstones: [:]),
            .reject(.invalid)
        )
    }

    func testOtherOpsOnUnknownAlarmDoNothing() {
        for kind in [WatchWire.Op.Kind.del, .en, .skip, .unskip] {
            XCTAssertEqual(
                WatchSyncRules.decide(op(kind, "gone", at: 200, enabled: true), alarms: [], tombstones: [:]),
                .reject(.unknownAlarm), "\(kind)"
            )
        }
    }

    // MARK: - Tombstones

    func testEditMadeBeforePhoneDeleteIsRejected() {
        XCTAssertEqual(
            WatchSyncRules.decide(op(.put, "a1", at: 100, fields: .init(hour: 6, minute: 0)),
                                  alarms: [], tombstones: ["a1": at(150)]),
            .reject(.deletedOnPhone)
        )
    }

    func testPutMadeAfterPhoneDeleteRecreates() {
        let decision = WatchSyncRules.decide(op(.put, "a1", at: 200, fields: .init(hour: 6, minute: 0)),
                                             alarms: [], tombstones: ["a1": at(150)])
        guard case .upsert(let created) = decision else { return XCTFail("\(decision)") }
        XCTAssertEqual(created.id, "a1")
    }

    func testUnknownKindIsRejectedNotDropped() {
        XCTAssertEqual(WatchSyncRules.decide(op(nil, "a1", at: 1), alarms: [alarm("a1")], tombstones: [:]),
                       .reject(.unsupported))
    }

    func testEnWithoutValueIsInvalid() {
        XCTAssertEqual(WatchSyncRules.decide(op(.en, "a1", at: 1), alarms: [alarm("a1")], tombstones: [:]),
                       .reject(.invalid))
    }

    // MARK: - Sync state

    func testRecordDeletionsTracksRemovedIdsAndForgetsReturningOnes() {
        var state = WatchSyncState()
        state.recordDeletions(previous: ["a", "b", "c"], current: ["a"], now: at(100))
        XCTAssertEqual(state.tombstones, ["b": at(100), "c": at(100)])
        state.recordDeletions(previous: ["a"], current: ["a", "b"], now: at(200))
        XCTAssertEqual(state.tombstones, ["c": at(100)])
    }

    func testTombstonesExpire() {
        var state = WatchSyncState(tombstones: ["old": at(0), "new": at(1000)])
        state.recordDeletions(previous: [], current: [], now: at(Int(WatchSyncState.tombstoneLifetime) + 500))
        XCTAssertEqual(state.tombstones.keys.sorted(), ["new"])
    }

    func testSyncStatePersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let state = WatchSyncState(tombstones: ["a": at(5)])
        state.save(to: url)
        XCTAssertEqual(WatchSyncState.load(from: url), state)
        XCTAssertEqual(WatchSyncState.load(from: url.appendingPathExtension("missing")), WatchSyncState())
    }
}
