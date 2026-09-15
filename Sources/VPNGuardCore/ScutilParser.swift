import Foundation

public enum VPNConnectionState: String, Codable, Equatable, Sendable {
    case connected
    case connecting
    case disconnecting
    case disconnected
    case invalid
    case unknown

    public init(scutilValue: String) {
        switch scutilValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "connected": self = .connected
        case "connecting": self = .connecting
        case "disconnecting": self = .disconnecting
        case "disconnected": self = .disconnected
        case "invalid": self = .invalid
        default: self = .unknown
        }
    }

    public var isActive: Bool {
        switch self {
        case .connected, .connecting, .disconnecting:
            true
        case .disconnected, .invalid, .unknown:
            false
        }
    }

    public var shouldIssueStop: Bool {
        self == .connected || self == .connecting
    }
}

public struct VPNConnection: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let state: VPNConnectionState
    public let kind: String
    public let isEnabled: Bool

    public init(
        id: String,
        name: String,
        state: VPNConnectionState,
        kind: String,
        isEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.kind = kind
        self.isEnabled = isEnabled
    }
}

public enum ScutilOutputParser {
    public static func parseConnectionList(_ output: String) -> [VPNConnection] {
        output.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    public static func parseLine(_ line: String) -> VPNConnection? {
        guard let openParenthesis = line.firstIndex(of: "("),
              let closeParenthesis = line[openParenthesis...].firstIndex(of: ")") else {
            return nil
        }

        let prefix = line[..<openParenthesis]
        let isEnabled = prefix.contains("*")
        let stateStart = line.index(after: openParenthesis)
        let stateValue = String(line[stateStart..<closeParenthesis])

        let remainderStart = line.index(after: closeParenthesis)
        let remainder = line[remainderStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let identifier = remainder.split(whereSeparator: \.isWhitespace).first.map(String.init),
              !identifier.isEmpty else {
            return nil
        }

        let quoteIndexes = line.indices.filter { line[$0] == "\"" }
        guard quoteIndexes.count >= 2,
              let firstQuote = quoteIndexes.first,
              let lastQuote = quoteIndexes.last,
              firstQuote < lastQuote else {
            return nil
        }

        let nameStart = line.index(after: firstQuote)
        let name = String(line[nameStart..<lastQuote])

        var kind = "VPN"
        if let openBracket = line.lastIndex(of: "["),
           let closeBracket = line.lastIndex(of: "]"),
           openBracket < closeBracket {
            let kindStart = line.index(after: openBracket)
            kind = String(line[kindStart..<closeBracket])
        }

        return VPNConnection(
            id: identifier,
            name: name,
            state: VPNConnectionState(scutilValue: stateValue),
            kind: kind,
            isEnabled: isEnabled
        )
    }
}
