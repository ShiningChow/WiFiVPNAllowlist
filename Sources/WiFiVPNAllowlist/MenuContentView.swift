import AppKit
import SwiftUI
import VPNGuardCore

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                policyCard
                networkCard
                trafficCard
                allowlistCard
                managedApplicationsCard
                settingsCard
                activityCard
                footer
            }
            .padding(16)
        }
        .frame(width: 410, height: 690)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var trafficCard: some View {
        let usages = model.trafficUsages(for: model.selectedTrafficMonth)
        let totalReceived = clampedSum(usages.map(\.receivedBytes))
        let totalSent = clampedSum(usages.map(\.sentBytes))

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                sectionTitle("Wi-Fi 月度流量", systemImage: "chart.bar.xaxis")
                Spacer()
                Picker("月份", selection: $model.selectedTrafficMonth) {
                    ForEach(model.availableTrafficMonths, id: \.self) { month in
                        Text(monthTitle(month)).tag(month)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: 125)
            }

            if usages.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("本月还没有可显示的流量")
                        .font(.subheadline.weight(.medium))
                    Text("连接 Wi-Fi 后会自动开始统计，无需额外操作。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 16) {
                    trafficMetric("总计", bytes: clampedAdd(totalReceived, totalSent), color: .blue)
                    trafficMetric("下载", bytes: totalReceived, color: .cyan)
                    trafficMetric("上传", bytes: totalSent, color: .indigo)
                }

                Divider()

                VStack(spacing: 10) {
                    ForEach(usages) { usage in
                        VStack(spacing: 5) {
                            HStack {
                                Image(systemName: usage.ssid == model.currentSSID ? "wifi.circle.fill" : "wifi")
                                    .foregroundStyle(usage.ssid == model.currentSSID ? Color.blue : Color.secondary)
                                Text(usage.ssid)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                                Spacer()
                                Text(formatBytes(usage.totalBytes))
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                            }
                            HStack(spacing: 14) {
                                Label(formatBytes(usage.receivedBytes), systemImage: "arrow.down")
                                Label(formatBytes(usage.sentBytes), systemImage: "arrow.up")
                                Spacer()
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let note = model.trafficTrackingNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("统计物理 Wi-Fi 网卡的上下行字节，包含互联网和局域网流量；App 未运行期间不追溯估算。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(policyColor.opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: model.menuBarSymbol)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(policyColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("VPN 白名单守卫")
                    .font(.headline)
                Text("只有白名单 Wi-Fi 允许 VPN")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isChecking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var policyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(policyColor)
                    .frame(width: 9, height: 9)
                Text(model.policyTitle)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(model.decision.mode == .allowed ? "ALLOW" : model.decision.mode == .blocked ? "BLOCK" : "PAUSED")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(policyColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(policyColor.opacity(0.1), in: Capsule())
            }

            Text(model.policyDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("当前网络", systemImage: "wifi")

            HStack(alignment: .top, spacing: 0) {
                networkMetric(
                    "Wi-Fi 名称",
                    value: model.currentSSID ?? "无法识别",
                    color: model.currentSSID == nil ? .orange : .primary
                )

                networkMetricDivider

                networkMetric(
                    "默认网络",
                    value: primaryNetworkTitle,
                    color: model.primaryNetworkState == .wifi ? .primary : .orange
                )

                networkMetricDivider

                networkMetric(
                    "定位权限",
                    value: model.locationPermission.title,
                    color: model.locationPermission == .authorized ? .secondary : .orange
                )
            }

            if model.locationPermission == .notDetermined {
                Button("允许读取 Wi-Fi 名称") {
                    model.requestLocationPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if model.locationPermission != .authorized {
                HStack {
                    Text("不授权时将始终按非白名单处理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("打开定位设置") {
                        model.openLocationSettings()
                    }
                    .controlSize(.small)
                }
            }
        }
        .cardStyle()
    }

    private var allowlistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Wi-Fi 白名单", systemImage: "checkmark.circle")
                Spacer()
                Text("精确匹配")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if model.settings.allowedSSIDs.isEmpty {
                Label("白名单为空：所有网络都禁止 VPN", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.settings.allowedSSIDs, id: \.self) { ssid in
                        HStack {
                            Image(systemName: "wifi")
                                .foregroundStyle(.secondary)
                            Text(ssid)
                                .lineLimit(1)
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                model.removeSSID(ssid)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("移出白名单")
                        }
                        .padding(.vertical, 7)

                        if ssid != model.settings.allowedSSIDs.last {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            }

            HStack(spacing: 8) {
                TextField("输入 Wi-Fi 名称", text: $model.newSSIDEntry)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTypedSSID)
                Button("添加") {
                    addTypedSSID()
                }
                .disabled(model.newSSIDEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Button {
                _ = model.addCurrentSSID()
            } label: {
                Label("把当前 Wi-Fi 加入白名单", systemImage: "plus.circle")
            }
            .disabled(model.currentSSID == nil || model.settings.contains(model.currentSSID ?? ""))
            .controlSize(.small)
        }
        .cardStyle()
    }

    private var managedApplicationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("受控 VPN App", systemImage: "app.badge.checkmark")
                Spacer()
                Button("添加 App…") {
                    model.chooseManagedVPNApplication()
                }
                .controlSize(.small)
            }

            if model.settings.managedVPNApplications.isEmpty {
                Text("尚未添加第三方 VPN App。系统 VPN 仍会被自动断开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.settings.managedVPNApplications) { application in
                    HStack(spacing: 9) {
                        Image(systemName: model.isApplicationInstalled(bundleIdentifier: application.bundleIdentifier) ? "app.fill" : "questionmark.app")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(application.displayName)
                                .font(.subheadline.weight(.medium))
                            Text(application.bundleIdentifier)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { application.isEnabled },
                            set: { model.setManagedApplicationEnabled(
                                bundleIdentifier: application.bundleIdentifier,
                                enabled: $0
                            ) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        Button {
                            model.removeManagedApplication(bundleIdentifier: application.bundleIdentifier)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if !model.runningManagedApplicationNames.isEmpty {
                Label(
                    "仍在运行：\(model.runningManagedApplicationNames.joined(separator: "、"))",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .cardStyle()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("运行设置", systemImage: "gearshape")

            Toggle("启用白名单保护", isOn: Binding(
                get: { model.settings.isProtectionEnabled },
                set: { model.setProtectionEnabled($0) }
            ))

            Toggle("登录时自动启动", isOn: Binding(
                get: { model.launchAtLoginToggleIsOn },
                set: { model.setLaunchAtLogin($0) }
            ))

            if model.loginItemState == .requiresApproval {
                HStack {
                    Text("需要在系统设置中批准后台项目。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("打开设置") {
                        model.openLoginItemSettings()
                    }
                    .controlSize(.small)
                }
            }

            DisclosureGroup("高级规则", isExpanded: $model.showAdvancedRules) {
                Toggle("无法识别 Wi-Fi / 使用有线网络时仍阻止 VPN", isOn: Binding(
                    get: { model.settings.blockWhenSSIDUnavailable },
                    set: { model.setBlockWhenSSIDUnavailable($0) }
                ))
                .padding(.top, 7)

                Text("建议保持开启。关闭后，在定位权限失效、未连接 Wi-Fi 或默认网络走网线时会放行 VPN。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("守卫状态", systemImage: "waveform.path.ecg")
                Spacer()
                Button {
                    model.checkNow()
                } label: {
                    Label("立即检测", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(model.isChecking)
            }

            if model.systemVPNConnections.isEmpty {
                Text("未发现 scutil 可管理的系统 VPN 服务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.systemVPNConnections) { connection in
                    HStack {
                        Circle()
                            .fill(connection.state.isActive ? Color.orange : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7)
                        Text(connection.name)
                            .font(.subheadline)
                        Spacer()
                        Text(connection.state.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let event = model.events.first {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: event.isError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(event.isError ? .orange : .secondary)
                    Text(event.message)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text(event.date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let lastCheckedAt = model.lastCheckedAt {
                Text("最近检测：\(lastCheckedAt.formatted(date: .omitted, time: .standard)) · 每 \(Int(model.settings.pollingIntervalSeconds)) 秒检查")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .cardStyle()
    }

    private var footer: some View {
        HStack {
            Text("个人合规助手 · 不会自动重连 VPN")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("退出") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
        }
    }

    private var policyColor: Color {
        if model.lastError != nil, model.decision.mode == .blocked {
            return .orange
        }
        switch model.decision.mode {
        case .allowed: return Color.green
        case .blocked: return Color.red
        case .paused: return Color.secondary
        }
    }

    private var primaryNetworkTitle: String {
        switch model.primaryNetworkState {
        case .wifi: "Wi-Fi"
        case .nonWiFi: "非 Wi-Fi"
        case .unavailable: "不可用"
        case .unknown: "检测中"
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
    }

    private func addTypedSSID() {
        if model.addSSID(model.newSSIDEntry) {
            model.newSSIDEntry = ""
        }
    }

    private func trafficMetric(_ title: String, bytes: UInt64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatBytes(bytes))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func networkMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var networkMetricDivider: some View {
        Divider()
            .frame(height: 38)
            .padding(.horizontal, 10)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(min(bytes, UInt64(Int64.max))),
            countStyle: .file
        )
    }

    private func monthTitle(_ identifier: String) -> String {
        let components = identifier.split(separator: "-")
        guard components.count == 2 else { return identifier }
        return "\(components[0])年\(Int(components[1]) ?? 0)月"
    }

    private func clampedSum(_ values: [UInt64]) -> UInt64 {
        values.reduce(0, clampedAdd)
    }

    private func clampedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? UInt64.max : result.partialValue
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.72),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}
