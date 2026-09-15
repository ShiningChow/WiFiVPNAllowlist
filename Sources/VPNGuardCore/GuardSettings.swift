import Foundation

public struct ManagedVPNApplication: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let bundleIdentifier: String
    public var displayName: String
    public var isEnabled: Bool

    public var id: String { bundleIdentifier }

    public init(bundleIdentifier: String, displayName: String, isEnabled: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.isEnabled = isEnabled
    }
}

public struct GuardSettings: Codable, Equatable, Sendable {
    public var isProtectionEnabled: Bool
    public var allowedSSIDs: [String]
    public var blockWhenSSIDUnavailable: Bool
    public var pollingIntervalSeconds: Double
    public var managedVPNApplications: [ManagedVPNApplication]

    public init(
        isProtectionEnabled: Bool = true,
        allowedSSIDs: [String] = [],
        blockWhenSSIDUnavailable: Bool = true,
        pollingIntervalSeconds: Double = 2,
        managedVPNApplications: [ManagedVPNApplication] = []
    ) {
        self.isProtectionEnabled = isProtectionEnabled
        self.allowedSSIDs = Self.uniqueSSIDs(allowedSSIDs)
        self.blockWhenSSIDUnavailable = blockWhenSSIDUnavailable
        self.pollingIntervalSeconds = max(1, pollingIntervalSeconds)
        self.managedVPNApplications = Self.uniqueApplications(managedVPNApplications)
    }

    @discardableResult
    public mutating func addSSID(_ rawValue: String) -> Bool {
        guard let ssid = Self.sanitizeSSID(rawValue), !contains(ssid) else {
            return false
        }

        allowedSSIDs.append(ssid)
        allowedSSIDs.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        return true
    }

    @discardableResult
    public mutating func removeSSID(_ rawValue: String) -> Bool {
        guard let ssid = Self.sanitizeSSID(rawValue),
              let index = allowedSSIDs.firstIndex(of: ssid) else {
            return false
        }

        allowedSSIDs.remove(at: index)
        return true
    }

    public func contains(_ rawValue: String) -> Bool {
        guard let ssid = Self.sanitizeSSID(rawValue) else {
            return false
        }
        return allowedSSIDs.contains(ssid)
    }

    public static func sanitizeSSID(_ rawValue: String) -> String? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        return value.isEmpty ? nil : value
    }

    @discardableResult
    public mutating func addManagedApplication(_ application: ManagedVPNApplication) -> Bool {
        guard !application.bundleIdentifier.isEmpty,
              !managedVPNApplications.contains(where: { $0.bundleIdentifier == application.bundleIdentifier }) else {
            return false
        }
        managedVPNApplications.append(application)
        managedVPNApplications.sort {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        return true
    }

    @discardableResult
    public mutating func removeManagedApplication(bundleIdentifier: String) -> Bool {
        guard let index = managedVPNApplications.firstIndex(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            return false
        }
        managedVPNApplications.remove(at: index)
        return true
    }

    private static func uniqueSSIDs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap(sanitizeSSID).filter { seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func uniqueApplications(
        _ applications: [ManagedVPNApplication]
    ) -> [ManagedVPNApplication] {
        var seen = Set<String>()
        return applications.filter { application in
            !application.bundleIdentifier.isEmpty && seen.insert(application.bundleIdentifier).inserted
        }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
