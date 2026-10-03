import XCTest
@testable import AlarmClock

private final class FakeTransport: WatchTransport {
    var onMessage: ((Any) -> Void)?
    var onWatchReady: (() -> Void)?
    var sent: [[String: Any]] = []

    func send(_ message: [String: Any]) { sent.append(message) }

    var lastAlarms: [[String: Any]] { sent.last?["alarms"] as? [[String: Any]] ?? [] }
    var lastAck: [String] { sent.last?["ack"] as? [String] ?? [] }
}

private final class NullEngine: AlarmEngine {
    func schedule(_ request: FireRequest) {}
    func cancel(alarmId: String) {}
    func cancelAll() {}
}

final class WatchSyncCoordinatorTests: XCTestCase {

    private var calendar: Calendar!
    private var alarmsURL: URL!
    private var stateURL: URL!
    private var transport: FakeTransport!
    private var store: AlarmStore!
    private var coordinator: WatchSyncCoordinator!
    /// Sunday 2026-09-20 10:00 IST.
    private let now = WatchSyncCoordinatorTests.date(2026, 9, 20, 10, 0)

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        let tmp = FileManager.default.temporaryDirectory
        alarmsURL = tmp.appendingPathComponent("alarms-\(UUID().uuidString).json")
        stateURL = tmp.appendingPathComponent("watch-sync-\(UUID().uuidString).json")
        makeStack()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: alarmsURL)
        try? FileManager.default.removeItem(at: stateURL)
        super.tearDown()
    }

    private func makeStack() {
        let fixedNow = now
        transport = FakeTransport()
        store = AlarmStore(engine: NullEngine(), ringer: NoopRinger(), persistenceURL: alarmsURL,
                           now: { fixedNow }, calendar: calendar)
        coordinator = WatchSyncCoordinator(store: store, transport: transport, stateURL: stateURL,
                                           now: { fixedNow })
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func epoch(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }

    private func sync(_ ops: [[String: Any]]) {
        transport.onMessage?(["t": "sync", "v": 1, "ops": ops])
    }

    private func alarm(_ id: String, hour: Int = 7, days: Set<Weekday> = []) -> Alarm {
        Alarm(id: id, hour: hour, minute: 0, repeatDays: days, label: "Wake")
    }

    // MARK: - Phone → watch

    func testPhoneEditPushesSnapshot() {
        store.upsert(alarm("a1"))
        XCTAssertEqual(transport.sent.last?["t"] as? String, "snap")
        XCTAssertEqual(transport.lastAlarms.map { $0["id"] as? String }, ["a1"])
        XCTAssertEqual(transport.lastAlarms.first?["nf"] as? Int,
                       epoch(Self.date(2026, 9, 21, 7, 0)))
    }

    func testUnchangedRescheduleDoesNotResend() {
        store.upsert(alarm("a1"))
        let count = transport.sent.count
        store.refreshAndReschedule()
        store.refreshAndReschedule()
        XCTAssertEqual(transport.sent.count, count)
    }

    func testWatchReadyAlwaysGetsASnapshot() {
        store.upsert(alarm("a1"))
        let count = transport.sent.count
        transport.onWatchReady?()
        XCTAssertEqual(transport.sent.count, count + 1)
        coordinator.syncNow()
        XCTAssertEqual(transport.sent.count, count + 2)
    }

    // MARK: - Watch → phone

    func testHelloGetsSnapshotWithoutChanges() {
        store.upsert(alarm("a1"))
        let before = store.alarms
        sync([])
        XCTAssertEqual(store.alarms, before)
        XCTAssertEqual(transport.lastAlarms.count, 1)
        XCTAssertEqual(transport.lastAck, [])
        XCTAssertEqual(coordinator.lastWatchSync, now)
    }

    func testWatchCreatesAlarmAndGetsOneAckedReply() {
        let count = transport.sent.count
        let at = epoch(now) - 60
        sync([
            ["oid": "w1-1", "op": "put", "id": "w42", "at": at,
             "f": ["h": 6, "m": 30, "d": [1, 2, 3, 4, 5], "l": "Work"]],
            ["oid": "w1-2", "op": "put", "id": "w42", "at": at + 5, "f": ["sm": 5]],
        ])
        XCTAssertEqual(transport.sent.count, count + 1, "one reply for the whole batch")
        XCTAssertEqual(transport.lastAck, ["w1-1", "w1-2"])

        let created = store.alarms.first { $0.id == "w42" }
        XCTAssertEqual(created?.hour, 6)
        XCTAssertEqual(created?.minute, 30)
        XCTAssertEqual(created?.label, "Work")
        XCTAssertEqual(created?.snoozeMinutes, 5)
        XCTAssertEqual(created?.repeatDays.count, 5)
        XCTAssertEqual(created?.updatedAt, Date(timeIntervalSince1970: TimeInterval(at + 5)))
        XCTAssertEqual(created?.nextFireDate, Self.date(2026, 9, 21, 6, 30))
        XCTAssertEqual(transport.lastAlarms.first?["id"] as? String, "w42")
    }

    func testWatchToggleUsesStoreSemantics() {
        store.upsert(alarm("a1"))
        sync([["oid": "w1-1", "op": "en", "id": "a1", "at": epoch(now) + 1, "e": false]])
        XCTAssertEqual(store.alarms.first?.enabled, false)
        XCTAssertNil(store.alarms.first?.nextFireDate)
        XCTAssertEqual(transport.lastAlarms.first?["e"] as? Bool, false)
    }

    func testStaleWatchEditIsAckedButNotApplied() {
        store.upsert(alarm("a1", hour: 7))   // edited "now" on the phone
        sync([["oid": "w1-1", "op": "put", "id": "a1", "at": epoch(now) - 600, "f": ["h": 9]]])
        XCTAssertEqual(store.alarms.first?.hour, 7)
        XCTAssertEqual(transport.lastAck, ["w1-1"])
        XCTAssertEqual(transport.lastAlarms.first?["h"] as? Int, 7)
    }

    func testWatchDeleteAndSkip() {
        store.upsert(alarm("a1"))
        store.upsert(alarm("a2", days: [.monday, .tuesday]))
        sync([
            ["oid": "w1-1", "op": "del", "id": "a1", "at": epoch(now) + 1],
            ["oid": "w1-2", "op": "skip", "id": "a2", "at": epoch(now) + 2],
        ])
        XCTAssertEqual(store.alarms.map(\.id), ["a2"])
        XCTAssertEqual(store.alarms.first?.skippedFireDate, Self.date(2026, 9, 21, 7, 0))
        XCTAssertEqual(store.alarms.first?.nextFireDate, Self.date(2026, 9, 22, 7, 0))

        sync([["oid": "w1-3", "op": "unskip", "id": "a2", "at": epoch(now) + 3]])
        XCTAssertNil(store.alarms.first?.skippedFireDate)
    }

    func testEditOfAlarmDeletedOnPhoneIsRejectedEvenAfterRelaunch() {
        store.upsert(alarm("a1"))
        store.delete(id: "a1")
        XCTAssertNotNil(coordinator.state.tombstones["a1"])

        makeStack()   // relaunch: tombstones come back from disk
        XCTAssertNotNil(coordinator.state.tombstones["a1"])
        sync([["oid": "w1-1", "op": "put", "id": "a1", "at": epoch(now) - 60, "f": ["h": 6, "m": 0]]])
        XCTAssertTrue(store.alarms.isEmpty)
        XCTAssertEqual(transport.lastAck, ["w1-1"])
    }

    func testUnknownMessagesAreIgnored() {
        let count = transport.sent.count
        transport.onMessage?(["t": "snap", "v": 1])
        transport.onMessage?("status")
        XCTAssertEqual(transport.sent.count, count)
        XCTAssertNil(coordinator.lastWatchSync)
    }

    // MARK: - updatedAt stamping

    func testPhoneEditsStampUpdatedAt() {
        let later = Self.date(2026, 9, 20, 11, 0)
        var current = now
        store = AlarmStore(engine: NullEngine(), ringer: NoopRinger(), persistenceURL: alarmsURL,
                           now: { current }, calendar: calendar)
        store.upsert(alarm("a1", days: [.monday]))
        XCTAssertEqual(store.alarms.first?.updatedAt, now)

        current = later
        store.setEnabled(id: "a1", enabled: false)
        XCTAssertEqual(store.alarms.first?.updatedAt, later)

        current = later.addingTimeInterval(60)
        store.setEnabled(id: "a1", enabled: true)
        store.skipNext(id: "a1")
        XCTAssertEqual(store.alarms.first?.updatedAt, current)

        current = later.addingTimeInterval(120)
        store.cancelSkip(id: "a1")
        XCTAssertEqual(store.alarms.first?.updatedAt, current)

        let watchTime = Date(timeIntervalSince1970: 1_000)
        store.upsert(store.alarms[0], editedAt: watchTime)
        XCTAssertEqual(store.alarms.first?.updatedAt, watchTime)
    }

    func testUpdatedAtPersists() {
        store.upsert(alarm("a1"))
        makeStack()
        XCTAssertEqual(store.alarms.first?.updatedAt, now)
    }
}
