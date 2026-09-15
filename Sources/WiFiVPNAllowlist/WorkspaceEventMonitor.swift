import AppKit

@MainActor
final class WorkspaceEventMonitor: NSObject {
    var applicationDidLaunch: ((String) -> Void)?
    var systemDidWake: (() -> Void)?
    var applicationWillTerminate: (() -> Void)?

    private let notificationCenter = NSWorkspace.shared.notificationCenter

    override init() {
        super.init()
        notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationTermination(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleApplicationLaunch(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              let bundleIdentifier = application.bundleIdentifier else {
            return
        }
        applicationDidLaunch?(bundleIdentifier)
    }

    @objc private func handleSystemWake(_ notification: Notification) {
        systemDidWake?()
    }

    @objc private func handleApplicationTermination(_ notification: Notification) {
        applicationWillTerminate?()
    }
}
