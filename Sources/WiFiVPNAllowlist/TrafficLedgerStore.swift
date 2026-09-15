import Foundation
import VPNGuardCore

enum TrafficLedgerStore {
    private static var fileURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("com.qiming.wifivpnallowlist", isDirectory: true)
            .appendingPathComponent("TrafficLedger.json")
    }

    static func load() -> TrafficLedger {
        guard let data = try? Data(contentsOf: fileURL),
              let ledger = try? JSONDecoder().decode(TrafficLedger.self, from: data) else {
            return TrafficLedger()
        }
        return ledger
    }

    static func save(_ ledger: TrafficLedger) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ledger).write(to: fileURL, options: .atomic)
    }
}
