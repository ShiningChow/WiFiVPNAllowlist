import Darwin
import Foundation
import VPNGuardCore

enum InterfaceTrafficReader {
    static func snapshot(interfaceName: String) -> InterfaceTrafficSnapshot? {
        let interfaceIndex = if_nametoindex(interfaceName)
        guard interfaceIndex != 0 else {
            return nil
        }

        var mib: [Int32] = [
            CTL_NET,
            PF_LINK,
            NETLINK_GENERIC,
            IFMIB_IFDATA,
            Int32(interfaceIndex),
            IFDATA_GENERAL,
        ]
        var interfaceData = ifmibdata()
        var byteCount = MemoryLayout<ifmibdata>.size
        let readSucceeded = withUnsafeMutablePointer(to: &interfaceData) { pointer in
            sysctl(&mib, UInt32(mib.count), pointer, &byteCount, nil, 0) == 0
        }
        guard readSucceeded, byteCount >= MemoryLayout<ifmibdata>.size else {
            return nil
        }

        return InterfaceTrafficSnapshot(
            interfaceName: interfaceName,
            receivedBytes: interfaceData.ifmd_data.ifi_ibytes,
            sentBytes: interfaceData.ifmd_data.ifi_obytes
        )
    }
}
