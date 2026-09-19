import Foundation

public struct InterfaceTrafficSnapshot: Equatable, Sendable {
    public let interfaceName: String
    public let receivedBytes: UInt64
    public let sentBytes: UInt64

    public init(interfaceName: String, receivedBytes: UInt64, sentBytes: UInt64) {
        self.interfaceName = interfaceName
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }
}

public enum TrafficConnectionMode: String, Codable, Equatable, Sendable {
    case tunneled
    case direct
}

public struct TrafficUsage: Codable, Equatable, Identifiable, Sendable {
    public let month: String
    public let ssid: String
    public var receivedBytes: UInt64
    public var sentBytes: UInt64
    public var tunneledReceivedBytes: UInt64
    public var tunneledSentBytes: UInt64
    public var directReceivedBytes: UInt64
    public var directSentBytes: UInt64

    public var id: String { "\(month)\u{0}\(ssid)" }
    public var totalBytes: UInt64 {
        Self.clampedAdd(receivedBytes, sentBytes)
    }
    public var tunneledBytes: UInt64 {
        Self.clampedAdd(tunneledReceivedBytes, tunneledSentBytes)
    }
    public var directBytes: UInt64 {
        Self.clampedAdd(directReceivedBytes, directSentBytes)
    }
    public var unclassifiedReceivedBytes: UInt64 {
        Self.clampedSubtract(
            receivedBytes,
            Self.clampedAdd(tunneledReceivedBytes, directReceivedBytes)
        )
    }
    public var unclassifiedSentBytes: UInt64 {
        Self.clampedSubtract(
            sentBytes,
            Self.clampedAdd(tunneledSentBytes, directSentBytes)
        )
    }
    public var unclassifiedBytes: UInt64 {
        Self.clampedAdd(unclassifiedReceivedBytes, unclassifiedSentBytes)
    }

    public init(
        month: String,
        ssid: String,
        receivedBytes: UInt64 = 0,
        sentBytes: UInt64 = 0,
        tunneledReceivedBytes: UInt64 = 0,
        tunneledSentBytes: UInt64 = 0,
        directReceivedBytes: UInt64 = 0,
        directSentBytes: UInt64 = 0
    ) {
        self.month = month
        self.ssid = ssid
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.tunneledReceivedBytes = tunneledReceivedBytes
        self.tunneledSentBytes = tunneledSentBytes
        self.directReceivedBytes = directReceivedBytes
        self.directSentBytes = directSentBytes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        month = try values.decode(String.self, forKey: .month)
        ssid = try values.decode(String.self, forKey: .ssid)
        receivedBytes = try values.decode(UInt64.self, forKey: .receivedBytes)
        sentBytes = try values.decode(UInt64.self, forKey: .sentBytes)
        tunneledReceivedBytes = try values.decodeIfPresent(
            UInt64.self,
            forKey: .tunneledReceivedBytes
        ) ?? 0
        tunneledSentBytes = try values.decodeIfPresent(
            UInt64.self,
            forKey: .tunneledSentBytes
        ) ?? 0
        directReceivedBytes = try values.decodeIfPresent(
            UInt64.self,
            forKey: .directReceivedBytes
        ) ?? 0
        directSentBytes = try values.decodeIfPresent(
            UInt64.self,
            forKey: .directSentBytes
        ) ?? 0
    }

    private static func clampedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? UInt64.max : result.partialValue
    }

    private static func clampedSubtract(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs >= rhs ? lhs - rhs : 0
    }
}

public struct TrafficLedger: Codable, Equatable, Sendable {
    public private(set) var usages: [TrafficUsage]

    public init(usages: [TrafficUsage] = []) {
        self.usages = usages
    }

    public mutating func add(
        month: String,
        ssid: String,
        receivedBytes: UInt64,
        sentBytes: UInt64,
        mode: TrafficConnectionMode
    ) {
        guard receivedBytes > 0 || sentBytes > 0 else { return }

        if let index = usages.firstIndex(where: { $0.month == month && $0.ssid == ssid }) {
            usages[index].receivedBytes = Self.clampedAdd(
                usages[index].receivedBytes,
                receivedBytes
            )
            usages[index].sentBytes = Self.clampedAdd(usages[index].sentBytes, sentBytes)
            switch mode {
            case .tunneled:
                usages[index].tunneledReceivedBytes = Self.clampedAdd(
                    usages[index].tunneledReceivedBytes,
                    receivedBytes
                )
                usages[index].tunneledSentBytes = Self.clampedAdd(
                    usages[index].tunneledSentBytes,
                    sentBytes
                )
            case .direct:
                usages[index].directReceivedBytes = Self.clampedAdd(
                    usages[index].directReceivedBytes,
                    receivedBytes
                )
                usages[index].directSentBytes = Self.clampedAdd(
                    usages[index].directSentBytes,
                    sentBytes
                )
            }
        } else {
            let tunneledReceived = mode == .tunneled ? receivedBytes : 0
            let tunneledSent = mode == .tunneled ? sentBytes : 0
            let directReceived = mode == .direct ? receivedBytes : 0
            let directSent = mode == .direct ? sentBytes : 0
            usages.append(TrafficUsage(
                month: month,
                ssid: ssid,
                receivedBytes: receivedBytes,
                sentBytes: sentBytes,
                tunneledReceivedBytes: tunneledReceived,
                tunneledSentBytes: tunneledSent,
                directReceivedBytes: directReceived,
                directSentBytes: directSent
            ))
        }
    }

    public func usages(for month: String) -> [TrafficUsage] {
        usages.filter { $0.month == month }
            .sorted {
                if $0.totalBytes == $1.totalBytes {
                    return $0.ssid.localizedStandardCompare($1.ssid) == .orderedAscending
                }
                return $0.totalBytes > $1.totalBytes
            }
    }

    public var availableMonths: [String] {
        Array(Set(usages.map(\.month)).sorted(by: >))
    }

    private static func clampedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? UInt64.max : result.partialValue
    }
}

public struct TrafficAccumulator: Sendable {
    public private(set) var ledger: TrafficLedger
    private var baseline: Baseline?

    public init(ledger: TrafficLedger = TrafficLedger()) {
        self.ledger = ledger
    }

    @discardableResult
    public mutating func record(
        snapshot: InterfaceTrafficSnapshot?,
        ssid rawSSID: String?,
        month: String,
        mode: TrafficConnectionMode
    ) -> Bool {
        guard let snapshot,
              let ssid = GuardSettings.sanitizeSSID(rawSSID ?? "") else {
            baseline = nil
            return false
        }

        defer {
            baseline = Baseline(
                interfaceName: snapshot.interfaceName,
                ssid: ssid,
                month: month,
                mode: mode,
                receivedBytes: snapshot.receivedBytes,
                sentBytes: snapshot.sentBytes
            )
        }

        guard let baseline,
              baseline.interfaceName == snapshot.interfaceName,
              baseline.ssid == ssid,
              baseline.month == month,
              baseline.mode == mode,
              snapshot.receivedBytes >= baseline.receivedBytes,
              snapshot.sentBytes >= baseline.sentBytes else {
            return false
        }

        let receivedDelta = snapshot.receivedBytes - baseline.receivedBytes
        let sentDelta = snapshot.sentBytes - baseline.sentBytes
        guard receivedDelta > 0 || sentDelta > 0 else { return false }

        ledger.add(
            month: month,
            ssid: ssid,
            receivedBytes: receivedDelta,
            sentBytes: sentDelta,
            mode: mode
        )
        return true
    }

    public mutating func resetBaseline() {
        baseline = nil
    }

    private struct Baseline: Sendable {
        let interfaceName: String
        let ssid: String
        let month: String
        let mode: TrafficConnectionMode
        let receivedBytes: UInt64
        let sentBytes: UInt64
    }
}

public enum TrafficMonth {
    public static func identifier(
        for date: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
}
