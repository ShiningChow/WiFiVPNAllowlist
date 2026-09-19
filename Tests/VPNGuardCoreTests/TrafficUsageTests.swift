import Foundation
import XCTest
@testable import VPNGuardCore

final class TrafficUsageTests: XCTestCase {
    func testRecordsDeltaAfterBaseline() {
        var accumulator = TrafficAccumulator()

        let establishedBaseline = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 1_000, sentBytes: 500),
            ssid: "Home WiFi",
            month: "2026-09",
            mode: .direct
        )
        let recordedDelta = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 1_900, sentBytes: 800),
            ssid: "Home WiFi",
            month: "2026-09",
            mode: .direct
        )
        XCTAssertFalse(establishedBaseline)
        XCTAssertTrue(recordedDelta)

        let usage = accumulator.ledger.usages(for: "2026-09").first
        XCTAssertEqual(usage?.receivedBytes, 900)
        XCTAssertEqual(usage?.sentBytes, 300)
        XCTAssertEqual(usage?.totalBytes, 1_200)
        XCTAssertEqual(usage?.directBytes, 1_200)
        XCTAssertEqual(usage?.tunneledBytes, 0)
    }

    func testNetworkSwitchResetsBaseline() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 1_000, sentBytes: 500),
            ssid: "Home WiFi",
            month: "2026-09",
            mode: .direct
        )
        let switchedNetwork = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 2_000, sentBytes: 1_000),
            ssid: "School",
            month: "2026-09",
            mode: .direct
        )
        let recordedAfterSwitch = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 2_500, sentBytes: 1_200),
            ssid: "School",
            month: "2026-09",
            mode: .direct
        )
        XCTAssertFalse(switchedNetwork)
        XCTAssertTrue(recordedAfterSwitch)

        XCTAssertEqual(accumulator.ledger.usages(for: "2026-09").count, 1)
        XCTAssertEqual(accumulator.ledger.usages(for: "2026-09").first?.ssid, "School")
        XCTAssertEqual(accumulator.ledger.usages(for: "2026-09").first?.directBytes, 700)
    }

    func testBoundariesResetBaseline() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 1_000, sentBytes: 500),
            ssid: "Home WiFi",
            month: "2026-08",
            mode: .direct
        )
        let crossedMonth = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 2_000, sentBytes: 900),
            ssid: "Home WiFi",
            month: "2026-09",
            mode: .direct
        )
        let switchedInterface = accumulator.record(
            snapshot: .init(interfaceName: "en1", receivedBytes: 50, sentBytes: 20),
            ssid: "Home WiFi",
            month: "2026-09",
            mode: .direct
        )
        let countersWentBackwards = accumulator.record(
            snapshot: .init(interfaceName: "en1", receivedBytes: 10, sentBytes: 5),
            ssid: "Home WiFi",
            month: "2026-09",
            mode: .direct
        )
        XCTAssertFalse(crossedMonth)
        XCTAssertFalse(switchedInterface)
        XCTAssertFalse(countersWentBackwards)
        XCTAssertTrue(accumulator.ledger.usages.isEmpty)
    }

    func testConnectionModeSwitchResetsBaseline() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 1_000, sentBytes: 500),
            ssid: "Home WiFi",
            month: "2026-09",
            mode: .direct
        )

        let switchedMode = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 1_500, sentBytes: 700),
            ssid: "Home WiFi",
            month: "2026-09",
            mode: .tunneled
        )
        let tunneledDelta = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 2_100, sentBytes: 900),
            ssid: "Home WiFi",
            month: "2026-09",
            mode: .tunneled
        )

        XCTAssertFalse(switchedMode)
        XCTAssertTrue(tunneledDelta)
        let usage = accumulator.ledger.usages(for: "2026-09").first
        XCTAssertEqual(usage?.tunneledReceivedBytes, 600)
        XCTAssertEqual(usage?.tunneledSentBytes, 200)
        XCTAssertEqual(usage?.directBytes, 0)
    }

    func testLegacyUsageBecomesUnclassified() throws {
        let data = Data(
            #"{"month":"2026-09","ssid":"Home WiFi","receivedBytes":900,"sentBytes":300}"#.utf8
        )
        let usage = try JSONDecoder().decode(TrafficUsage.self, from: data)

        XCTAssertEqual(usage.totalBytes, 1_200)
        XCTAssertEqual(usage.unclassifiedBytes, 1_200)
        XCTAssertEqual(usage.directBytes, 0)
        XCTAssertEqual(usage.tunneledBytes, 0)
    }

    func testGroupsAndSortsUsage() {
        var ledger = TrafficLedger()
        ledger.add(
            month: "2026-09",
            ssid: "Home WiFi",
            receivedBytes: 500,
            sentBytes: 500,
            mode: .direct
        )
        ledger.add(
            month: "2026-09",
            ssid: "Phone",
            receivedBytes: 2_000,
            sentBytes: 200,
            mode: .tunneled
        )
        ledger.add(
            month: "2026-08",
            ssid: "Home WiFi",
            receivedBytes: 9_000,
            sentBytes: 0,
            mode: .direct
        )

        XCTAssertEqual(ledger.availableMonths, ["2026-09", "2026-08"])
        XCTAssertEqual(ledger.usages(for: "2026-09").map(\.ssid), ["Phone", "Home WiFi"])
    }
}
