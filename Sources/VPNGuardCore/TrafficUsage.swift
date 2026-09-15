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

public struct TrafficUsage: Codable, Equatable, Identifiable, Sendable {
    public let month: String
    public let ssid: String
    public var receivedBytes: UInt64
    public var sentBytes: UInt64

    public var id: String { "\(month)\u{0}\(ssid)" }
    public var totalBytes: UInt64 {
        let result = receivedBytes.addingReportingOverflow(sentBytes)
        return result.overflow ? UInt64.max : result.partialValue
    }

    public init(
        month: String,
        ssid: String,
        receivedBytes: UInt64 = 0,
        sentBytes: UInt64 = 0
    ) {
        self.month = month
        self.ssid = ssid
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
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
        sentBytes: UInt64
    ) {
        guard receivedBytes > 0 || sentBytes > 0 else { return }

        if let index = usages.firstIndex(where: { $0.month == month && $0.ssid == ssid }) {
            usages[index].receivedBytes = usages[index].receivedBytes.addingReportingOverflow(receivedBytes).overflow
                ? UInt64.max
                : usages[index].receivedBytes + receivedBytes
            usages[index].sentBytes = usages[index].sentBytes.addingReportingOverflow(sentBytes).overflow
                ? UInt64.max
                : usages[index].sentBytes + sentBytes
        } else {
            usages.append(TrafficUsage(
                month: month,
                ssid: ssid,
                receivedBytes: receivedBytes,
                sentBytes: sentBytes
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
        month: String
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
                receivedBytes: snapshot.receivedBytes,
                sentBytes: snapshot.sentBytes
            )
        }

        guard let baseline,
              baseline.interfaceName == snapshot.interfaceName,
              baseline.ssid == ssid,
              baseline.month == month,
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
            sentBytes: sentDelta
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
