import XCTest
@testable import AlarmClock

final class HistoryLogTests: XCTestCase {

    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func event(_ i: Int) -> AlarmEvent {
        AlarmEvent(kind: .fired, alarmId: "a", label: "A",
                   date: Date(timeIntervalSince1970: TimeInterval(1_000 + i)))
    }

    func testMissingFileIsEmpty() {
        XCTAssertEqual(HistoryLog(url: url).events, [])
    }

    func testCorruptFileIsEmptyAndRecoverable() throws {
        try Data("not json{".utf8).write(to: url)
        let log = HistoryLog(url: url)
        XCTAssertEqual(log.events, [])
        log.record(event(1))
        XCTAssertEqual(HistoryLog(url: url).events, [event(1)])
    }

    func testRecordPersistsAndReloads() {
        let log = HistoryLog(url: url)
        log.record(event(1))
        log.record(AlarmEvent(kind: .stopped, alarmId: "t", label: "Test", date: .distantPast, isTest: true))
        let reloaded = HistoryLog(url: url)
        XCTAssertEqual(reloaded.events, log.events)
        XCTAssertEqual(reloaded.events.count, 2)
    }

    func testCapsToLimit() {
        let log = HistoryLog(url: url, limit: 5)
        for i in 0..<12 { log.record(event(i)) }
        XCTAssertEqual(log.events, (7..<12).map(event))
        XCTAssertEqual(HistoryLog(url: url, limit: 5).events.count, 5)
    }

    func testBadEntriesAreSkippedNotFatal() throws {
        let json = """
        [{"kind":"fired","alarmId":"a","label":"A","date":10},
         {"kind":"exploded","alarmId":"a","date":11},
         {"alarmId":"a"},
         {"kind":"stopped","alarmId":"a","date":12}]
        """
        try Data(json.utf8).write(to: url)
        let events = HistoryLog(url: url).events
        XCTAssertEqual(events.map(\.kind), [.fired, .stopped])
        XCTAssertEqual(events[1].label, "Alarm") // defaulted
        XCTAssertFalse(events[1].isTest)
    }

    func testHasEventSince() {
        let log = HistoryLog(url: url)
        log.record(event(5))
        XCTAssertTrue(log.hasEvent(alarmId: "a", since: Date(timeIntervalSince1970: 1_005)))
        XCTAssertFalse(log.hasEvent(alarmId: "a", since: Date(timeIntervalSince1970: 1_006)))
        XCTAssertFalse(log.hasEvent(alarmId: "b", since: .distantPast))
    }

    func testClear() {
        let log = HistoryLog(url: url)
        log.record(event(1))
        log.clear()
        XCTAssertEqual(HistoryLog(url: url).events, [])
    }
}
