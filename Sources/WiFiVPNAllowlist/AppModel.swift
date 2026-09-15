import AppKit
import CoreLocation
import Foundation
import UniformTypeIdentifiers
import VPNGuardCore

struct GuardEvent: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let message: String
    let isError: Bool
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var settings: GuardSettings
    @Published private(set) var currentSSID: String?
    @Published private(set) var primaryNetworkState: PrimaryNetworkState
    @Published private(set) var locationPermission: LocationPermissionState
    @Published private(set) var decision: PolicyDecision
    @Published private(set) var systemVPNConnections: [VPNConnection] = []
    @Published private(set) var runningManagedApplicationNames: [String] = []
    @Published private(set) var loginItemState: LoginItemState
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var events: [GuardEvent] = []
    @Published private(set) var isChecking = false
    @Published private(set) var trafficLedger: TrafficLedger
    @Published private(set) var trafficTrackingNote: String?
    @Published var newSSIDEntry = ""
    @Published var showAdvancedRules = false
    @Published var selectedTrafficMonth = TrafficMonth.identifier()

    private let wifiReader: WiFiReader
    private let primaryNetworkMonitor: PrimaryNetworkMonitor
    private let workspaceEventMonitor: WorkspaceEventMonitor
    private var trafficAccumulator: TrafficAccumulator
    private var lastTrafficSaveAt: Date?
    private var monitorTask: Task<Void, Never>?
    private var hasStarted = false

    init() {
        let reader = WiFiReader()
        let networkMonitor = PrimaryNetworkMonitor()
        let eventMonitor = WorkspaceEventMonitor()
        wifiReader = reader
        primaryNetworkMonitor = networkMonitor
        workspaceEventMonitor = eventMonitor

        let initialSettings: GuardSettings
        if let savedSettings = SettingsStore.load() {
            initialSettings = savedSettings
        } else {
            var seededSettings = GuardSettings()
            if NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.west2online.ClashXPro"
            ) != nil {
                seededSettings.addManagedApplication(
                    ManagedVPNApplication(
                        bundleIdentifier: "com.west2online.ClashXPro",
                        displayName: "ClashX Pro"
                    )
                )
            }
            initialSettings = seededSettings
            SettingsStore.save(seededSettings)
        }

        let initialSSID = reader.currentSSID()
        let initialNetworkState = networkMonitor.state
        let initialPermission = reader.permissionState
        let initialTrafficLedger = TrafficLedgerStore.load()
        settings = initialSettings
        currentSSID = initialSSID
        primaryNetworkState = initialNetworkState
        locationPermission = initialPermission
        decision = PolicyEngine.evaluate(
            currentSSID: initialSSID,
            primaryNetworkState: initialNetworkState,
            settings: initialSettings
        )
        loginItemState = LoginItemManager.state
        trafficLedger = initialTrafficLedger
        trafficAccumulator = TrafficAccumulator(ledger: initialTrafficLedger)
        trafficTrackingNote = nil

        reader.authorizationDidChange = { [weak self] in
            guard let self else { return }
            self.locationPermission = self.wifiReader.permissionState
            self.runCheckSoon()
        }
        networkMonitor.stateDidChange = { [weak self] newState in
            guard let self else { return }
            self.primaryNetworkState = newState
            self.trafficAccumulator.resetBaseline()
            self.runCheckSoon()
        }
        eventMonitor.applicationDidLaunch = { [weak self] bundleIdentifier in
            guard let self,
                  self.decision.shouldDisconnectVPN,
                  self.settings.managedVPNApplications.contains(where: {
                      $0.isEnabled && $0.bundleIdentifier == bundleIdentifier
                  }) else {
                return
            }
            self.runCheckSoon()
        }
        eventMonitor.systemDidWake = { [weak self] in
            self?.trafficAccumulator.resetBaseline()
            self?.runCheckSoon()
        }
        eventMonitor.applicationWillTerminate = { [weak self] in
            self?.saveTrafficLedger(force: true)
        }
    }

    deinit {
        monitorTask?.cancel()
    }

    var menuBarSymbol: String {
        switch decision.mode {
        case .allowed: "shield.checkered"
        case .blocked: "shield.fill"
        case .paused: "shield.slash"
        }
    }

    var policyTitle: String {
        switch decision.mode {
        case .allowed: "VPN 已允许"
        case .blocked: "VPN 已阻止"
        case .paused: "保护已暂停"
        }
    }

    var policyDetail: String {
        switch decision.reason {
        case .ssidAllowed:
            "当前 Wi-Fi 在白名单中"
        case .ssidNotAllowed:
            "当前 Wi-Fi 不在白名单中"
        case .ssidUnavailable:
            locationPermission == .authorized
                ? "未连接 Wi-Fi 或无法识别名称，已按从严规则处理"
                : "没有 Wi-Fi 名称权限，已按从严规则处理"
        case .ssidUnavailableException:
            "未识别到 Wi-Fi，已按例外设置放行"
        case .primaryNetworkNotWiFi:
            "当前默认网络不是 Wi-Fi，已按从严规则处理"
        case .networkUnavailable:
            "当前没有可用网络，已按从严规则处理"
        case .networkStateUnknown:
            "网络正在切换，已按从严规则处理"
        case .protectionDisabled:
            "不会自动断开 VPN"
        }
    }

    var launchAtLoginToggleIsOn: Bool {
        loginItemState == .enabled || loginItemState == .requiresApproval
    }

    var currentTrafficMonth: String {
        TrafficMonth.identifier()
    }

    var availableTrafficMonths: [String] {
        Array(Set([currentTrafficMonth] + trafficLedger.availableMonths)).sorted(by: >)
    }

    func trafficUsages(for month: String) -> [TrafficUsage] {
        trafficLedger.usages(for: month)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        appendEvent("白名单保护已启动", isError: false)

        if wifiReader.permissionState == .notDetermined {
            wifiReader.requestPermission()
        }
        primaryNetworkMonitor.start()

        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.evaluateAndEnforce()
                let interval = self.settings.pollingIntervalSeconds
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func checkNow() {
        runCheckSoon()
    }

    func requestLocationPermission() {
        wifiReader.requestPermission()
        locationPermission = wifiReader.permissionState
    }

    func openLocationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func setProtectionEnabled(_ enabled: Bool) {
        settings.isProtectionEnabled = enabled
        persistAndRecheck()
        appendEvent(enabled ? "白名单保护已开启" : "白名单保护已暂停", isError: false)
    }

    func setBlockWhenSSIDUnavailable(_ shouldBlock: Bool) {
        settings.blockWhenSSIDUnavailable = shouldBlock
        persistAndRecheck()
    }

    @discardableResult
    func addSSID(_ value: String) -> Bool {
        guard settings.addSSID(value) else { return false }
        SettingsStore.save(settings)
        appendEvent("已加入白名单：\(value.trimmingCharacters(in: .whitespacesAndNewlines))", isError: false)
        runCheckSoon()
        return true
    }

    @discardableResult
    func addCurrentSSID() -> Bool {
        guard let currentSSID else { return false }
        return addSSID(currentSSID)
    }

    func removeSSID(_ value: String) {
        guard settings.removeSSID(value) else { return }
        SettingsStore.save(settings)
        appendEvent("已移出白名单：\(value)", isError: false)
        runCheckSoon()
    }

    func chooseManagedVPNApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择需要在非白名单网络中退出的 VPN App"
        panel.prompt = "加入守卫"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else {
            return
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let application = ManagedVPNApplication(
            bundleIdentifier: identifier,
            displayName: displayName
        )
        guard settings.addManagedApplication(application) else { return }
        SettingsStore.save(settings)
        appendEvent("已纳入守卫：\(displayName)", isError: false)
        runCheckSoon()
    }

    func setManagedApplicationEnabled(bundleIdentifier: String, enabled: Bool) {
        guard let index = settings.managedVPNApplications.firstIndex(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else { return }
        settings.managedVPNApplications[index].isEnabled = enabled
        SettingsStore.save(settings)
        runCheckSoon()
    }

    func removeManagedApplication(bundleIdentifier: String) {
        guard let application = settings.managedVPNApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }), settings.removeManagedApplication(bundleIdentifier: bundleIdentifier) else {
            return
        }
        SettingsStore.save(settings)
        appendEvent("已取消守卫：\(application.displayName)", isError: false)
    }

    func isApplicationInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            loginItemState = LoginItemManager.state
            lastError = nil
        } catch {
            loginItemState = LoginItemManager.state
            lastError = "设置登录启动失败：\(error.localizedDescription)"
            appendEvent(lastError ?? "设置登录启动失败", isError: true)
        }
    }

    func openLoginItemSettings() {
        LoginItemManager.openSystemSettings()
    }

    private func persistAndRecheck() {
        SettingsStore.save(settings)
        runCheckSoon()
    }

    private func runCheckSoon() {
        Task { [weak self] in
            await self?.evaluateAndEnforce()
        }
    }

    private func evaluateAndEnforce() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        locationPermission = wifiReader.permissionState
        currentSSID = wifiReader.currentSSID()
        decision = PolicyEngine.evaluate(
            currentSSID: currentSSID,
            primaryNetworkState: primaryNetworkState,
            settings: settings
        )
        recordTrafficSample()

        let shouldBlock = decision.shouldDisconnectVPN
        let systemTask = Task.detached(priority: .utility) {
            SystemVPNController.inspectAndEnforce(shouldBlock: shouldBlock)
        }

        let applicationOutcome: VPNApplicationEnforcementOutcome
        if shouldBlock {
            applicationOutcome = await VPNApplicationController.terminate(
                applications: settings.managedVPNApplications
            )
        } else {
            applicationOutcome = VPNApplicationController.inspect(
                applications: settings.managedVPNApplications
            )
        }

        let systemOutcome = await systemTask.value
        systemVPNConnections = systemOutcome.connections
        runningManagedApplicationNames = applicationOutcome.runningNames
        lastCheckedAt = Date()

        var errors = systemOutcome.failures + applicationOutcome.failedNames.map {
            "无法退出 \($0)"
        }
        if let inspectionError = systemOutcome.inspectionError {
            errors.append(inspectionError)
        }
        lastError = errors.isEmpty ? nil : errors.joined(separator: "；")

        let stoppedSystem = systemOutcome.stoppedNames
        let stoppedApplications = applicationOutcome.terminatedNames
            + applicationOutcome.forceTerminatedNames
        if !stoppedSystem.isEmpty {
            appendEvent("已断开系统 VPN：\(stoppedSystem.joined(separator: "、"))", isError: false)
        }
        if !stoppedApplications.isEmpty {
            appendEvent("已退出 VPN App：\(Array(Set(stoppedApplications)).sorted().joined(separator: "、"))", isError: false)
        }
        if let lastError {
            appendEvent(lastError, isError: true)
        }
    }

    private func appendEvent(_ message: String, isError: Bool) {
        if events.first?.message == message, events.first?.isError == isError {
            return
        }
        events.insert(GuardEvent(date: Date(), message: message, isError: isError), at: 0)
        if events.count > 12 {
            events.removeLast(events.count - 12)
        }
    }

    private func recordTrafficSample() {
        guard primaryNetworkState == .wifi else {
            trafficAccumulator.resetBaseline()
            trafficTrackingNote = "当前默认网络不是 Wi-Fi，未计入 Wi-Fi 流量"
            return
        }
        guard let currentSSID else {
            trafficAccumulator.resetBaseline()
            trafficTrackingNote = locationPermission == .authorized
                ? "暂时无法识别 Wi-Fi 名称，未计入流量"
                : "需要定位权限才能按 Wi-Fi 名称统计流量"
            return
        }
        guard let interfaceName = wifiReader.currentInterfaceName(),
              let snapshot = InterfaceTrafficReader.snapshot(interfaceName: interfaceName) else {
            trafficAccumulator.resetBaseline()
            trafficTrackingNote = "暂时无法读取 Wi-Fi 网卡流量计数"
            return
        }

        trafficTrackingNote = nil
        let changed = trafficAccumulator.record(
            snapshot: snapshot,
            ssid: currentSSID,
            month: currentTrafficMonth
        )
        guard changed else { return }

        trafficLedger = trafficAccumulator.ledger
        saveTrafficLedger(force: false)
    }

    private func saveTrafficLedger(force: Bool) {
        let now = Date()
        if !force,
           let lastTrafficSaveAt,
           now.timeIntervalSince(lastTrafficSaveAt) < 30 {
            return
        }

        do {
            try TrafficLedgerStore.save(trafficAccumulator.ledger)
            lastTrafficSaveAt = now
        } catch {
            trafficTrackingNote = "流量记录暂时无法保存：\(error.localizedDescription)"
        }
    }
}
