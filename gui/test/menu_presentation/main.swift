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

private func expected(
    _ title: String,
    _ subtitle: String,
    _ actionTitle: String,
    _ action: PrimaryMenuAction,
    _ tone: MenuTone
) -> MenuPresentation {
    MenuPresentation(title: title, subtitle: subtitle, actionTitle: actionTitle, action: action, tone: tone)
}

print("== LiteOC primary menu presentation ==")

check("Repairing is disabled",
      menuPresentation(for: .repairing, isConfigured: true),
      expected("正在检查残留路由…", "请稍候", "", .none, .busy))
check("unconfigured opens settings",
      menuPresentation(for: .disconnected, isConfigured: false),
      expected("未配置", "完成设置后即可连接", "设置", .openSettings, .neutral))
check("Disconnected connects",
      menuPresentation(for: .disconnected, isConfigured: true),
      expected("未连接", "点击连接", "连接", .connect, .neutral))
check("Connecting cancels",
      menuPresentation(for: .connecting, isConfigured: true),
      expected("正在连接…", "点击取消", "取消", .disconnect, .busy))
check("Disconnecting is disabled",
      menuPresentation(for: .disconnecting, isConfigured: true),
      expected("正在断开…", "正在清理路由", "", .none, .busy))
check("Connected displays the VPN IP and disconnects",
      menuPresentation(for: .connected, isConfigured: true, connectedIP: "192.0.2.42"),
      expected("已连接 · 192.0.2.42", "点击断开", "断开", .disconnect, .connected))
check("auth error opens settings",
      menuPresentation(for: .errAuth, isConfigured: true),
      expected("PIN 有误", "修改 PIN 后重试", "设置", .openSettings, .error))
check("certificate error opens settings",
      menuPresentation(for: .errCert, isConfigured: true),
      expected("证书获取失败", "检查证书指纹", "设置", .openSettings, .error))
check("timeout retries",
      menuPresentation(for: .errTimeout, isConfigured: true),
      expected("连接超时", "检查网络后重试", "重试", .connect, .error))
check("drop retries",
      menuPresentation(for: .errDropped, isConfigured: true),
      expected("连接已断开", "点击重试", "重试", .connect, .error))
check("network change retries",
      menuPresentation(for: .errNetworkChanged, isConfigured: true),
      expected("网络已变化", "点击重新连接", "重试", .connect, .error))
check("route error retries cleanup",
      menuPresentation(for: .errRoute, isConfigured: true),
      expected("路由清理失败", "点击重试清理", "清理", .disconnect, .error))
check("stop error retries cleanup",
      menuPresentation(for: .errStop, isConfigured: true),
      expected("断开未完成", "点击重试清理", "清理", .disconnect, .error))

let configured = ["HOST": "vpn.example.net:443", "USER": "alex", "GROUP": "employees"]
let placeholderHost = ["HOST": "vpn.example.com:443", "USER": "alex", "GROUP": "employees"]
let missingUser = ["HOST": "vpn.example.net:443", "USER": "", "GROUP": "employees"]
guard profileIsConfigured(configured), !profileIsConfigured(placeholderHost), !profileIsConfigured(missingUser) else {
    fputs("FAIL profile configuration detection\n", stderr)
    exit(1)
}
passed += 1
print("  ok   profile configuration detection")

print("\n\(passed) passed")
