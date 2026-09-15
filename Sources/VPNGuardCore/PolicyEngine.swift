import Foundation

public enum GuardMode: String, Codable, Equatable, Sendable {
    case allowed
    case blocked
    case paused
}

public enum PolicyReason: String, Codable, Equatable, Sendable {
    case ssidAllowed
    case ssidNotAllowed
    case ssidUnavailable
    case ssidUnavailableException
    case primaryNetworkNotWiFi
    case networkUnavailable
    case networkStateUnknown
    case protectionDisabled
}

public enum PrimaryNetworkState: String, Codable, Equatable, Sendable {
    case wifi
    case nonWiFi
    case unavailable
    case unknown
}

public struct PolicyDecision: Equatable, Sendable {
    public let mode: GuardMode
    public let reason: PolicyReason
    public let currentSSID: String?

    public init(mode: GuardMode, reason: PolicyReason, currentSSID: String?) {
        self.mode = mode
        self.reason = reason
        self.currentSSID = currentSSID
    }

    public var shouldDisconnectVPN: Bool {
        mode == .blocked
    }
}

public enum PolicyEngine {
    public static func evaluate(
        currentSSID rawSSID: String?,
        primaryNetworkState: PrimaryNetworkState = .wifi,
        settings: GuardSettings
    ) -> PolicyDecision {
        guard settings.isProtectionEnabled else {
            return PolicyDecision(
                mode: .paused,
                reason: .protectionDisabled,
                currentSSID: GuardSettings.sanitizeSSID(rawSSID ?? "")
            )
        }

        guard primaryNetworkState == .wifi else {
            let reason: PolicyReason = switch primaryNetworkState {
            case .nonWiFi: .primaryNetworkNotWiFi
            case .unavailable: .networkUnavailable
            case .unknown: .networkStateUnknown
            case .wifi: .networkStateUnknown
            }
            return PolicyDecision(
                mode: settings.blockWhenSSIDUnavailable ? .blocked : .allowed,
                reason: settings.blockWhenSSIDUnavailable ? reason : .ssidUnavailableException,
                currentSSID: GuardSettings.sanitizeSSID(rawSSID ?? "")
            )
        }

        guard let currentSSID = GuardSettings.sanitizeSSID(rawSSID ?? "") else {
            return PolicyDecision(
                mode: settings.blockWhenSSIDUnavailable ? .blocked : .allowed,
                reason: settings.blockWhenSSIDUnavailable ? .ssidUnavailable : .ssidUnavailableException,
                currentSSID: nil
            )
        }

        let isAllowed = settings.contains(currentSSID)
        return PolicyDecision(
            mode: isAllowed ? .allowed : .blocked,
            reason: isAllowed ? .ssidAllowed : .ssidNotAllowed,
            currentSSID: currentSSID
        )
    }
}
