import XCTest
@testable import VPNGuardCore

final class ScutilParserTests: XCTestCase {
    func testParsesConnections() {
        let output = """
        Available network connection services in the current set (*=enabled):
        * (Connected)      01234567-89AB-CDEF-0123-456789ABCDEF VPN --> IKEv2       \"工作 VPN\"              [VPN:IKEv2]
        * (Disconnected)   ABCDEF01-2345-6789-ABCD-EF0123456789 VPN --> IPSec       \"备用 VPN\"              [VPN:IPSec]
          (Connecting)     com.example.packet-tunnel          VPN --> Custom      \"第三方 VPN\"            [VPN:com.example]
        """

        let connections = ScutilOutputParser.parseConnectionList(output)

        XCTAssertEqual(connections.count, 3)
        XCTAssertEqual(connections[0].id, "01234567-89AB-CDEF-0123-456789ABCDEF")
        XCTAssertEqual(connections[0].name, "工作 VPN")
        XCTAssertEqual(connections[0].state, .connected)
        XCTAssertTrue(connections[0].isEnabled)
        XCTAssertEqual(connections[1].state, .disconnected)
        XCTAssertEqual(connections[2].state, .connecting)
        XCTAssertFalse(connections[2].isEnabled)
    }

    func testIgnoresInvalidLines() {
        let output = """
        Available network connection services in the current set (*=enabled):
        this is not a VPN line
        """

        XCTAssertTrue(ScutilOutputParser.parseConnectionList(output).isEmpty)
    }
}
