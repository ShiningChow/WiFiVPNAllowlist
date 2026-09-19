import Foundation
import SystemConfiguration

enum SystemProxyStatusReader {
    static func isEnabled() -> Bool {
        guard let proxies = SCDynamicStoreCopyProxies(nil) as? [String: Any] else {
            return false
        }

        let enableKeys: [CFString] = [
            kSCPropNetProxiesHTTPEnable,
            kSCPropNetProxiesHTTPSEnable,
            kSCPropNetProxiesSOCKSEnable,
            kSCPropNetProxiesFTPEnable,
            kSCPropNetProxiesProxyAutoConfigEnable,
            kSCPropNetProxiesProxyAutoDiscoveryEnable,
        ]

        return enableKeys.contains { key in
            if let number = proxies[key as String] as? NSNumber {
                return number.boolValue
            }
            if let value = proxies[key as String] as? Bool {
                return value
            }
            return false
        }
    }
}
