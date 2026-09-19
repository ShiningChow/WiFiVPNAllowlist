# 架构与安全边界

## 决策条件

只有以下条件全部满足时返回 `ALLOW`：

1. 白名单保护已开启。
2. `NWPathMonitor` 判断默认可用路径使用 Wi‑Fi。
3. CoreWLAN 成功读取当前 SSID。
4. 当前 SSID 精确匹配本地白名单。

任一条件不满足时返回 `BLOCK`。用户可以在高级设置中明确关闭“SSID 不可用时从严阻止”，但默认始终开启。

## 执行适配器

### 系统 VPN

App 通过 `Process` 直接执行绝对路径 `/usr/sbin/scutil`，不经过 shell：

```text
scutil --nc list
scutil --nc stop <service-id>
```

只对 `Connected` 或 `Connecting` 状态发出停止命令。服务 ID 来自解析后的列表，服务显示名从不参与命令拼接。

### 第三方 VPN App

App 使用 `NSRunningApplication` 按 bundle identifier 查找受控应用，先 `terminate()` 做正常退出；900 毫秒后仍运行才调用 `forceTerminate()`，最后再次验证。处于 `BLOCK` 状态时还会监听应用启动事件，避免 ClashX Pro 等客户端被重新打开。

### 常驻与权限

- SSID：CoreWLAN。
- SSID 隐私授权：CoreLocation。
- 默认网络路径：Network.framework。
- 登录时启动：`SMAppService.mainApp`。
- 本地设置：`UserDefaults`，位于 bundle identifier `com.qiming.wifivpnallowlist` 对应的用户偏好中。

### 流量分类

App 读取物理 Wi-Fi 网卡的 64 位收发字节计数，并按自然月和 SSID 累加。每次采样还检查活动系统 VPN、SystemConfiguration 中启用的系统代理，以及受控 VPN App 的运行状态，将增量归入“梯子开启时”或“未开启时”。Wi-Fi、月份、网卡或连接状态发生切换时只重建基线，不归类跨边界增量。

这是按采样状态分段的统计，不检查数据包内容，也不能判断分流 VPN 中某个数据包是否真正经过隧道。旧版本账本缺少连接状态字段，迁移后保留为“升级前未分类”。

## 不采用的做法

- 不依据 `utun` 接口判断 VPN，避免误伤 Private Relay 等系统服务。
- 不使用不稳定的私有 `airport` 命令读取 SSID。
- 不用切换式 AppleScript 关闭 ClashX Pro，避免竞态条件下反而打开代理。
- 不直接清空所有系统代理，避免覆盖学校或其他合法网络配置。
- 不使用 PF 作为产品接口。

## 强制力边界

`NEVPNManager` 与 `NETunnelProviderManager` 只能管理调用 App 自己创建的 VPN 配置，无法作为全局“关闭所有 VPN”接口。当前实现属于持续检测、快速断开模型，因此在 App 启动前、网络切换瞬间或用户退出 App 后没有强制力。

学校级不可绕过方案需要由学校部署 MDM 和系统扩展策略，并在网络出口侧执行相应限制。
