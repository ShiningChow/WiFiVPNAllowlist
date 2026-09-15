import Darwin
import Foundation
import ServiceManagement

enum LoginItemState: String, Sendable {
    case enabled
    case requiresApproval
    case disabled
    case unavailable

    var title: String {
        switch self {
        case .enabled: "已自动启动"
        case .requiresApproval: "等待系统批准"
        case .disabled: "未自动启动"
        case .unavailable: "当前不可用"
        }
    }
}

private enum LoginItemError: LocalizedError {
    case executableUnavailable
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            "无法确定 App 的可执行文件路径"
        case .launchctlFailed(let detail):
            "登录启动服务配置失败：\(detail)"
        }
    }
}

@MainActor
enum LoginItemManager {
    private static let legacyAgentLabel = "com.qiming.wifivpnallowlist"

    private static var legacyAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(legacyAgentLabel).plist")
    }

    static var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound:
            FileManager.default.fileExists(atPath: legacyAgentURL.path) ? .enabled : .disabled
        @unknown default: .unavailable
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status == .notFound {
                try installLegacyAgent()
            } else if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status != .notRegistered,
               SMAppService.mainApp.status != .notFound {
                try SMAppService.mainApp.unregister()
            }
            if FileManager.default.fileExists(atPath: legacyAgentURL.path) {
                try removeLegacyAgent()
            }
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func installLegacyAgent() throws {
        guard let executableURL = Bundle.main.executableURL else {
            throw LoginItemError.executableUnavailable
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: legacyAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let propertyList: [String: Any] = [
            "Label": legacyAgentLabel,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "ThrottleInterval": 10
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try data.write(to: legacyAgentURL, options: .atomic)

        let domain = "gui/\(getuid())"
        _ = try? runLaunchctl(["bootout", "\(domain)/\(legacyAgentLabel)"])
        try runLaunchctl(["bootstrap", domain, legacyAgentURL.path])
        try runLaunchctl(["enable", "\(domain)/\(legacyAgentLabel)"])
    }

    private static func removeLegacyAgent() throws {
        let domain = "gui/\(getuid())"
        _ = try? runLaunchctl(["bootout", "\(domain)/\(legacyAgentLabel)"])
        try FileManager.default.removeItem(at: legacyAgentURL)
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let output = String(
            decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let error = String(
            decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw LoginItemError.launchctlFailed(
                error.isEmpty ? "launchctl 退出码 \(process.terminationStatus)" : error
            )
        }
        return output
    }
}
