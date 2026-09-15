import Foundation
import XCTest
@testable import VPNGuardCore

final class TrafficUsageTests: XCTestCase {
    func recordsDeltaAfterBaseline() {
        var accumulator = TrafficAccumulator()

        let establishedBaseline = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 1_000, sentBytes: 500),
            ssid: "Home WiFi",
            month: "2026-09"
        )
        let recordedDelta = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 1_900, sentBytes: 800),
            ssid: "Home WiFi",
            month: "2026-09"
        )
        XCTAssertFalse(establishedBaseline)
        XCTAssertTrue(recordedDelta)

        let usage = accumulator.ledger.usages(for: "2026-09").first
        XCTAssertEqual(usage?.receivedBytes, 900)
        XCTAssertEqual(usage?.sentBytes, 300)
        XCTAssertEqual(usage?.totalBytes, 1_200)
    }

    func networkSwitchResetsBaseline() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 1_000, sentBytes: 500),
            ssid: "Home WiFi",
            month: "2026-09"
        )
        let switchedNetwork = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 2_000, sentBytes: 1_000),
            ssid: "School",
            month: "2026-09"
        )
        let recordedAfterSwitch = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 2_500, sentBytes: 1_200),
            ssid: "School",
            month: "2026-09"
        )
        XCTAssertFalse(switchedNetwork)
        XCTAssertTrue(recordedAfterSwitch)

        XCTAssertEqual(accumulator.ledger.usages(for: "2026-09").count, 1)
        XCTAssertEqual(accumulator.ledger.usages(for: "2026-09").first?.ssid, "School")
        XCTAssertEqual(accumulator.ledger.usages(for: "2026-09").first?.totalBytes, 700)
    }

    func boundariesResetBaseline() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 1_000, sentBytes: 500),
            ssid: "Home WiFi",
            month: "2026-08"
        )
        let crossedMonth = accumulator.record(
            snapshot: .init(interfaceName: "en0", receivedBytes: 2_000, sentBytes: 900),
            ssid: "Home WiFi",
            month: "2026-09"
        )
        let switchedInterface = accumulator.record(
            snapshot: .init(interfaceName: "en1", receivedBytes: 50, sentBytes: 20),
            ssid: "Home WiFi",
            month: "2026-09"
        )
        let countersWentBackwards = accumulator.record(
            snapshot: .init(interfaceName: "en1", receivedBytes: 10, sentBytes: 5),
            ssid: "Home WiFi",
            month: "2026-09"
        )
        XCTAssertFalse(crossedMonth)
        XCTAssertFalse(switchedInterface)
        XCTAssertFalse(countersWentBackwards)
        XCTAssertTrue(accumulator.ledger.usages.isEmpty)
    }

    func groupsAndSortsUsage() {
        var ledger = TrafficLedger()
        ledger.add(month: "2026-09", ssid: "Home WiFi", receivedBytes: 500, sentBytes: 500)
        ledger.add(month: "2026-09", ssid: "Phone", receivedBytes: 2_000, sentBytes: 200)
        ledger.add(month: "2026-08", ssid: "Home WiFi", receivedBytes: 9_000, sentBytes: 0)

        XCTAssertEqual(ledger.availableMonths, ["2026-09", "2026-08"])
        XCTAssertEqual(ledger.usages(for: "2026-09").map(\.ssid), ["Phone", "Home WiFi"])
    }
}
