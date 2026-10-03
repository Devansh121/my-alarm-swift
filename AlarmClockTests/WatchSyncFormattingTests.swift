import XCTest
@testable import AlarmClock

final class WatchSyncFormattingTests: XCTestCase {

    private func watch(_ status: GarminConnection.Watch.Status, installed: Bool? = nil) -> GarminConnection.Watch {
        GarminConnection.Watch(id: UUID(), name: "Forerunner 965", status: status, appInstalled: installed)
    }

    func testStatus() {
        XCTAssertEqual(WatchSyncFormatting.status(watch(.ready, installed: true)), "Connected")
        XCTAssertEqual(WatchSyncFormatting.status(watch(.ready, installed: false)),
                       "Connected · Alarm app not installed")
        XCTAssertEqual(WatchSyncFormatting.status(watch(.connecting)), "Connecting…")
        XCTAssertEqual(WatchSyncFormatting.status(watch(.notConnected)), "Not connected")
        XCTAssertEqual(WatchSyncFormatting.status(watch(.bluetoothOff)), "Bluetooth is off")
    }

    func testLastSync() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(WatchSyncFormatting.lastSync(nil, now: now), "The watch syncs when you open Alarm on it.")
        XCTAssertEqual(WatchSyncFormatting.lastSync(now.addingTimeInterval(-10), now: now), "Last watch sync: just now")
        XCTAssertEqual(WatchSyncFormatting.lastSync(now.addingTimeInterval(-300), now: now), "Last watch sync: 5 min ago")
        XCTAssertEqual(WatchSyncFormatting.lastSync(now.addingTimeInterval(-7200), now: now), "Last watch sync: 2 h ago")
        XCTAssertEqual(WatchSyncFormatting.lastSync(now.addingTimeInterval(-3 * 86_400), now: now), "Last watch sync: 3 d ago")
    }
}
