import Foundation

private var passed = 0

private func check(_ description: String, _ actual: MenuPresentation, _ expected: MenuPresentation) {
    guard actual == expected else {
        fputs("FAIL \(description)\n  expected: \(expected)\n  actual:   \(actual)\n", stderr)
        exit(1)
    }
    passed += 1
    print("  ok   \(description)")
}

private func checkValue<T: Equatable>(_ description: String, _ actual: T, _ expected: T) {
    guard actual == expected else {
        fputs("FAIL \(description)\n  expected: \(expected)\n  actual:   \(actual)\n", stderr)
        exit(1)
    }
    passed += 1
    print("  ok   \(description)")
}

private func expected(
    _ title: String,
    _ subtitle: String,
    _ actionTitle: String,
    _ action: PrimaryMenuAction,
    _ tone: MenuTone,
    guide: Bool = false
) -> MenuPresentation {
    MenuPresentation(title: title, subtitle: subtitle, actionTitle: actionTitle, action: action, tone: tone, configurationGuide: guide)
}

print("== LiteOC primary menu presentation ==")

check("Repairing is disabled",
      menuPresentation(for: .repairing, isConfigured: true),
      expected("正在检查残留路由…", "请稍候", "", .none, .busy))
check("unconfigured opens settings with configuration guide",
      menuPresentation(for: .disconnected, isConfigured: false),
      expected("未配置", "完成设置后即可连接", "设置", .openSettings, .neutral, guide: true))
check("Disconnected connects",
      menuPresentation(for: .disconnected, isConfigured: true),
      expected("未连接", "", "连接", .connect, .neutral))
check("Connecting cancels",
      menuPresentation(for: .connecting, isConfigured: true),
      expected("正在连接…", "", "取消", .disconnect, .busy))
check("Reconnecting waits on the network and cancels",
      menuPresentation(for: .reconnecting, isConfigured: true),
      expected("正在重新连接…", "网络已变化", "取消", .disconnect, .busy))
check("Disconnecting is disabled",
      menuPresentation(for: .disconnecting, isConfigured: true),
      expected("正在断开…", "正在清理路由", "", .none, .busy))
check("Connected keeps the primary subtitle empty (IP moves to the info row)",
      menuPresentation(for: .connected, isConfigured: true, connectedIP: "198.51.100.146"),
      expected("已连接", "", "断开", .disconnect, .connected))
check("Connected without an IP keeps the detail line empty",
      menuPresentation(for: .connected, isConfigured: true),
      expected("已连接", "", "断开", .disconnect, .connected))
check("auth error opens settings",
      menuPresentation(for: .errAuth, isConfigured: true),
      expected("PIN 有误", "修改 PIN 后重试", "设置", .openSettings, .error))
check("certificate error opens settings",
      menuPresentation(for: .errCert, isConfigured: true),
      expected("证书获取失败", "检查证书指纹", "设置", .openSettings, .error))
check("timeout retries",
      menuPresentation(for: .errTimeout, isConfigured: true),
      expected("连接超时", "检查网络", "重试", .connect, .error))
check("drop retries",
      menuPresentation(for: .errDropped, isConfigured: true),
      expected("连接已断开", "", "重试", .connect, .error))
check("network change retries",
      menuPresentation(for: .errNetworkChanged, isConfigured: true),
      expected("网络已变化", "", "重试", .connect, .error))
check("reconnect exhaustion retries",
      menuPresentation(for: .errReconnectFailed, isConfigured: true),
      expected("重连失败", "", "重试", .connect, .error))
check("route error retries cleanup",
      menuPresentation(for: .errRoute, isConfigured: true),
      expected("路由清理失败", "", "清理", .disconnect, .error))
check("stop error retries cleanup",
      menuPresentation(for: .errStop, isConfigured: true),
      expected("断开未完成", "", "清理", .disconnect, .error))

let presentations = [
    TunnelState.repairing, .disconnected, .connecting, .reconnecting, .disconnecting, .connected,
    .errTimeout, .errAuth, .errCert, .errDropped, .errRoute, .errStop, .errNetworkChanged,
    .errReconnectFailed
].map {
    menuPresentation(for: $0, isConfigured: true, connectedIP: "198.51.100.146")
}
guard presentations.allSatisfy({ !$0.subtitle.contains("点击") }) else {
    fputs("FAIL primary menu subtitles must not repeat click instructions\n", stderr)
    exit(1)
}
passed += 1
print("  ok   subtitles do not repeat click instructions")

guard PrimaryMenuLayout.height == 46,
      PrimaryMenuLayout.actionWidth == 40 else {
    fputs("FAIL compact primary menu layout constants\n", stderr)
    exit(1)
}
passed += 1
print("  ok   compact primary menu layout constants (宽度由菜单内容决定, 不再固定)")

guard ConnectionInfoLayout.height == 44 else {
    fputs("FAIL connection info row layout constants\n", stderr)
    exit(1)
}
passed += 1
print("  ok   connection info row layout constants")

print("== LiteOC connection info row ==")

checkValue("info row appears when connected with an IP",
           connectionInfoPresentation(
               for: .connected, connectedIP: "198.51.100.146", gateway: "vpn.example.net:443"),
           ConnectionInfoPresentation(title: "198.51.100.146", subtitle: "网关 vpn.example.net:443"))
checkValue("copied flag maps to the one-shot transient subtitle",
           connectionInfoPresentation(
               for: .connected, connectedIP: "198.51.100.146", gateway: "vpn.example.net:443",
               showsCopiedConfirmation: true),
           ConnectionInfoPresentation(title: "198.51.100.146", subtitle: "已复制到剪贴板"))
checkValue("connected without an IP has no info row",
           connectionInfoPresentation(for: .connected, connectedIP: "", gateway: "vpn.example.net:443") == nil,
           true)
for state in [TunnelState.repairing, .disconnected, .connecting, .reconnecting, .disconnecting,
              .errTimeout, .errAuth, .errCert, .errDropped, .errRoute, .errStop, .errNetworkChanged,
              .errReconnectFailed] {
    checkValue("no info row outside connected (\(state))",
               connectionInfoPresentation(
                   for: state, connectedIP: "198.51.100.146", gateway: "vpn.example.net:443") == nil,
               true)
}

let configured = ["HOST": "vpn.example.net:443", "USER": "alex", "GROUP": "employees"]
let placeholderHost = ["HOST": "vpn.example.com:443", "USER": "alex", "GROUP": "employees"]
let missingUser = ["HOST": "vpn.example.net:443", "USER": "", "GROUP": "employees"]
guard profileIsConfigured(configured), !profileIsConfigured(placeholderHost), !profileIsConfigured(missingUser) else {
    fputs("FAIL profile configuration detection\n", stderr)
    exit(1)
}
passed += 1
print("  ok   profile configuration detection")

checkValue(
    "helper config-error overrides a locally complete profile",
    effectiveProfileIsConfigured(configured, missingConfigFields: ["GROUP"]),
    false
)

print("\n\(passed) passed")
