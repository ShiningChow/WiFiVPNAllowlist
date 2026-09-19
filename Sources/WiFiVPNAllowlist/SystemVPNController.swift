import Foundation
import VPNGuardCore

struct SystemVPNEnforcementOutcome: Sendable {
    var connections: [VPNConnection]
    var wasActiveBeforeEnforcement: Bool
    var stoppedNames: [String]
    var failures: [String]
    var inspectionError: String?
}

private struct CommandResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

enum SystemVPNController {
    static func inspectAndEnforce(shouldBlock: Bool) -> SystemVPNEnforcementOutcome {
        let listResult = runScutil(arguments: ["list"])
        guard listResult.exitCode == 0 else {
            let detail = nonempty(listResult.standardError) ?? nonempty(listResult.standardOutput)
            return SystemVPNEnforcementOutcome(
                connections: [],
                wasActiveBeforeEnforcement: false,
                stoppedNames: [],
                failures: [],
                inspectionError: detail ?? "scutil --nc list 执行失败（\(listResult.exitCode)）"
            )
        }

        let initialConnections = ScutilOutputParser.parseConnectionList(listResult.standardOutput)
        let wasActive = initialConnections.contains { $0.state.isActive }
        guard shouldBlock else {
            return SystemVPNEnforcementOutcome(
                connections: initialConnections,
                wasActiveBeforeEnforcement: wasActive,
                stoppedNames: [],
                failures: [],
                inspectionError: nil
            )
        }

        let targets = initialConnections.filter(\.state.shouldIssueStop)
        guard !targets.isEmpty else {
            return SystemVPNEnforcementOutcome(
                connections: initialConnections,
                wasActiveBeforeEnforcement: wasActive,
                stoppedNames: [],
                failures: [],
                inspectionError: nil
            )
        }

        var stoppedNames: [String] = []
        var failures: [String] = []
        for connection in targets {
            let stopResult = runScutil(arguments: ["stop", connection.id])
            if stopResult.exitCode == 0 {
                stoppedNames.append(connection.name)
            } else {
                let detail = nonempty(stopResult.standardError)
                    ?? nonempty(stopResult.standardOutput)
                    ?? "退出码 \(stopResult.exitCode)"
                failures.append("\(connection.name)：\(detail)")
            }
        }

        let refreshed = runScutil(arguments: ["list"])
        let finalConnections = refreshed.exitCode == 0
            ? ScutilOutputParser.parseConnectionList(refreshed.standardOutput)
            : initialConnections

        return SystemVPNEnforcementOutcome(
            connections: finalConnections,
            wasActiveBeforeEnforcement: wasActive,
            stoppedNames: stoppedNames,
            failures: failures,
            inspectionError: nil
        )
    }

    private static func runScutil(arguments: [String]) -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--nc"] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(
                exitCode: -1,
                standardOutput: "",
                standardError: error.localizedDescription
            )
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
