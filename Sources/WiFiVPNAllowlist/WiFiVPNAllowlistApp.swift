import Darwin
import SwiftUI
import VPNGuardCore

@main
@MainActor
struct WiFiVPNAllowlistApp: App {
    @ObservedObject private var model: AppModel

    init() {
        if CommandLine.arguments.contains("--traffic-self-test") {
            var accumulator = TrafficAccumulator()
            let baselineOnly = accumulator.record(
                snapshot: .init(interfaceName: "en0", receivedBytes: 1_000, sentBytes: 500),
                ssid: "Home WiFi",
                month: "2026-09"
            )
            let recorded = accumulator.record(
                snapshot: .init(interfaceName: "en0", receivedBytes: 1_900, sentBytes: 800),
                ssid: "Home WiFi",
                month: "2026-09"
            )
            let usage = accumulator.ledger.usages(for: "2026-09").first
            guard !baselineOnly,
                  recorded,
                  usage?.ssid == "Home WiFi",
                  usage?.receivedBytes == 900,
                  usage?.sentBytes == 300 else {
                fputs("TRAFFIC_SELF_TEST=failed\n", stderr)
                exit(EXIT_FAILURE)
            }
            print("TRAFFIC_SELF_TEST=passed")
            exit(EXIT_SUCCESS)
        }

        if let optionIndex = CommandLine.arguments.firstIndex(of: "--interface-traffic"),
           CommandLine.arguments.indices.contains(optionIndex + 1) {
            let interfaceName = CommandLine.arguments[optionIndex + 1]
            guard let snapshot = InterfaceTrafficReader.snapshot(interfaceName: interfaceName) else {
                fputs("INTERFACE_TRAFFIC_ERROR=unavailable\n", stderr)
                exit(EXIT_FAILURE)
            }
            print("INTERFACE_TRAFFIC=\(snapshot.interfaceName),\(snapshot.receivedBytes),\(snapshot.sentBytes)")
            exit(EXIT_SUCCESS)
        }

        if CommandLine.arguments.contains("--register-login-item") {
            do {
                try LoginItemManager.setEnabled(true)
                print("LOGIN_ITEM_STATUS=\(LoginItemManager.state.rawValue)")
                exit(EXIT_SUCCESS)
            } catch {
                fputs("LOGIN_ITEM_ERROR=\(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }

        if CommandLine.arguments.contains("--login-item-status") {
            print("LOGIN_ITEM_STATUS=\(LoginItemManager.state.rawValue)")
            exit(EXIT_SUCCESS)
        }

        let appModel = AppModel()
        _model = ObservedObject(wrappedValue: appModel)
        appModel.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Label("VPN 白名单守卫", systemImage: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
