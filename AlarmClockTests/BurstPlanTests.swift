import XCTest
@testable import AlarmClock

final class BurstPlanTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func request(id: String = "550e8400-e29b-41d4-a716-446655440000") -> FireRequest {
        FireRequest(alarmId: id, fireAt: base, label: "Wake", toneFileName: "tone_radial.caf")
    }

    // MARK: - plan

    func testPlanProducesRequestedChimeCount() {
        XCTAssertEqual(BurstPlan.plan(for: request(), chimes: 8).count, 8)
        XCTAssertEqual(BurstPlan.plan(for: request(), chimes: 1).count, 1)
    }

    func testPlanEmptyForNonPositiveChimes() {
        XCTAssertTrue(BurstPlan.plan(for: request(), chimes: 0).isEmpty)
        XCTAssertTrue(BurstPlan.plan(for: request(), chimes: -3).isEmpty)
    }

    func testPlanSpacesChimesByInterval() {
        let plan = BurstPlan.plan(for: request(), chimes: 4, interval: 30)
        XCTAssertEqual(plan[0].fireAt, base)
        XCTAssertEqual(plan[1].fireAt, base.addingTimeInterval(30))
        XCTAssertEqual(plan[2].fireAt, base.addingTimeInterval(60))
        XCTAssertEqual(plan[3].fireAt, base.addingTimeInterval(90))
    }

    func testPlanHonorsCustomInterval() {
        let plan = BurstPlan.plan(for: request(), chimes: 3, interval: 45)
        XCTAssertEqual(plan[2].fireAt, base.addingTimeInterval(90))
    }

    func testFirstIdentifierIsBareAlarmId() {
        let id = "550e8400-e29b-41d4-a716-446655440000"
        let plan = BurstPlan.plan(for: request(id: id), chimes: 8)
        XCTAssertEqual(plan[0].identifier, id)
    }

    func testSubsequentIdentifiersUseHashSuffix() {
        let id = "550e8400-e29b-41d4-a716-446655440000"
        let plan = BurstPlan.plan(for: request(id: id), chimes: 3)
        XCTAssertEqual(plan[1].identifier, "\(id)#1")
        XCTAssertEqual(plan[2].identifier, "\(id)#2")
    }

    // MARK: - alarmId(fromNotificationIdentifier:)

    func testStripsSuffixFromBurstIdentifier() {
        let id = "550e8400-e29b-41d4-a716-446655440000"
        XCTAssertEqual(BurstPlan.alarmId(fromNotificationIdentifier: id), id)
        XCTAssertEqual(BurstPlan.alarmId(fromNotificationIdentifier: "\(id)#1"), id)
        XCTAssertEqual(BurstPlan.alarmId(fromNotificationIdentifier: "\(id)#7"), id)
    }

    /// alarmIds are UUIDs, so `#` only ever appears as our suffix separator —
    /// stripping every plan identifier round-trips back to the original id.
    func testSuffixStrippingRoundTripsForEveryPlanIdentifier() {
        let id = "550e8400-e29b-41d4-a716-446655440000"
        XCTAssertFalse(id.contains("#"), "UUID alarmIds must never contain '#'")
        for chime in BurstPlan.plan(for: request(id: id), chimes: 8) {
            XCTAssertEqual(BurstPlan.alarmId(fromNotificationIdentifier: chime.identifier), id)
        }
    }

    // MARK: - allIdentifiers

    func testAllIdentifiersMatchesPlanIdentifiers() {
        let id = "550e8400-e29b-41d4-a716-446655440000"
        let planIds = BurstPlan.plan(for: request(id: id), chimes: 8).map(\.identifier)
        XCTAssertEqual(BurstPlan.allIdentifiers(alarmId: id, chimes: 8), planIds)
    }

    func testAllIdentifiersEmptyForNonPositiveChimes() {
        XCTAssertTrue(BurstPlan.allIdentifiers(alarmId: "x", chimes: 0).isEmpty)
    }
}
