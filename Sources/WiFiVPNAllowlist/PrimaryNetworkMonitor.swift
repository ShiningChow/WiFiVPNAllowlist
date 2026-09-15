@preconcurrency import Network
import VPNGuardCore

@MainActor
final class PrimaryNetworkMonitor {
    var stateDidChange: ((PrimaryNetworkState) -> Void)?

    private let monitor = NWPathMonitor()
    private(set) var state: PrimaryNetworkState = .unknown
    private var hasStarted = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let newState: PrimaryNetworkState
            if path.status != .satisfied {
                newState = .unavailable
            } else if path.usesInterfaceType(.wifi) {
                newState = .wifi
            } else {
                newState = .nonWiFi
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.state != newState else { return }
                self.state = newState
                self.stateDidChange?(newState)
            }
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        monitor.start(queue: DispatchQueue(label: "com.qiming.wifivpnallowlist.network-path"))
    }

    deinit {
        monitor.cancel()
    }
}
