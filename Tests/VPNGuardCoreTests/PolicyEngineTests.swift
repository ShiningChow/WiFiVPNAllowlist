import XCTest
@testable import VPNGuardCore

final class PolicyEngineTests: XCTestCase {
    func testAllowedSSID() {
        let settings = GuardSettings(allowedSSIDs: ["Home WiFi", "手机热点"])
        let decision = PolicyEngine.evaluate(currentSSID: "手机热点", settings: settings)

        XCTAssertEqual(decision.mode, .allowed)
        XCTAssertEqual(decision.reason, .ssidAllowed)
        XCTAssertFalse(decision.shouldDisconnectVPN)
    }

    func testUnknownSSID() {
        let settings = GuardSettings(allowedSSIDs: ["Home WiFi"])
        let decision = PolicyEngine.evaluate(currentSSID: "School WiFi", settings: settings)

        XCTAssertEqual(decision.mode, .blocked)
        XCTAssertEqual(decision.reason, .ssidNotAllowed)
        XCTAssertTrue(decision.shouldDisconnectVPN)
    }

    func testUnavailableSSIDFailsClosed() {
        let decision = PolicyEngine.evaluate(currentSSID: nil, settings: GuardSettings())

        XCTAssertEqual(decision.mode, .blocked)
        XCTAssertEqual(decision.reason, .ssidUnavailable)
    }

    func testNonWiFiPrimaryPathFailsClosed() {
        let settings = GuardSettings(allowedSSIDs: ["Home WiFi"])
        let decision = PolicyEngine.evaluate(
            currentSSID: "Home WiFi",
            primaryNetworkState: .nonWiFi,
            settings: settings
        )

        XCTAssertEqual(decision.mode, .blocked)
        XCTAssertEqual(decision.reason, .primaryNetworkNotWiFi)
    }

    func testUnknownPathFailsClosed() {
        let decision = PolicyEngine.evaluate(
            currentSSID: "Home WiFi",
            primaryNetworkState: .unknown,
            settings: GuardSettings(allowedSSIDs: ["Home WiFi"])
        )

        XCTAssertEqual(decision.mode, .blocked)
        XCTAssertEqual(decision.reason, .networkStateUnknown)
    }

    func testUnavailableSSIDCanBeAllowed() {
        let settings = GuardSettings(blockWhenSSIDUnavailable: false)
        let decision = PolicyEngine.evaluate(currentSSID: nil, settings: settings)

        XCTAssertEqual(decision.mode, .allowed)
        XCTAssertEqual(decision.reason, .ssidUnavailableException)
    }

    func testExactSSIDMatching() {
        let settings = GuardSettings(allowedSSIDs: ["HomeWiFi"])
        let decision = PolicyEngine.evaluate(currentSSID: "homewifi", settings: settings)

        XCTAssertEqual(decision.mode, .blocked)
    }

    func testPausedProtection() {
        let settings = GuardSettings(isProtectionEnabled: false)
        let decision = PolicyEngine.evaluate(currentSSID: "School", settings: settings)

        XCTAssertEqual(decision.mode, .paused)
        XCTAssertEqual(decision.reason, .protectionDisabled)
    }
}
