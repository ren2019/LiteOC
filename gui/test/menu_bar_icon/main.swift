import Foundation

private var passed = 0

private func check(_ description: String, _ actual: IconSpec, _ expected: IconSpec) {
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

private func spec(_ frames: [[Int]], _ interval: TimeInterval, _ red: Bool = false) -> IconSpec {
    IconSpec(frames: frames, frameInterval: interval, isErrorRed: red)
}

print("== LiteOC menu bar dot-matrix icon ==")

let brandTPattern = [0, 3, 4, 5, 6]

// 静态正常态
check("Disconnected (configured) is a fully dim static template icon",
      iconSpec(for: .disconnected, isConfigured: true),
      spec([[]], 0))
// 2026-08-31: 未配置 = 红色 C 形 (对"disconnected 一律全灭"旧规则的显式例外)
check("Disconnected (unconfigured) is a red C shape",
      iconSpec(for: .disconnected, isConfigured: false),
      spec([[0, 1, 2, 3, 6, 7, 8]], 0, true))
check("Connected is the brand T, static and template",
      iconSpec(for: .connected, isConfigured: true),
      spec([brandTPattern], 0))

// 除 disconnected 外, 配置与否不改变任何图标
for state in [TunnelState.repairing, .connecting, .disconnecting, .connected, .reconnecting,
              .errTimeout, .errAuth, .errCert, .errDropped, .errRoute, .errStop, .errNetworkChanged, .errReconnectFailed] {
    checkValue("isConfigured never changes the icon (\(state))",
               iconSpec(for: state, isConfigured: true),
               iconSpec(for: state, isConfigured: false))
}

// connecting: 外圈顺时针追逐, 环序 [0,1,2,5,8,7,6,3], 头点 + 2 拖尾, 8 帧 300ms
check("Connecting chases the outer ring clockwise with a 2-dot tail",
      iconSpec(for: .connecting, isConfigured: true),
      spec([[0, 3, 6], [0, 1, 3], [0, 1, 2], [1, 2, 5], [2, 5, 8], [5, 7, 8], [6, 7, 8], [3, 6, 7]], 0.3))

// disconnecting: T 按 [5,4,0,6,3] 逐点熄灭, 6 帧含全灭, 400ms
check("Disconnecting collapses the T dot by dot",
      iconSpec(for: .disconnecting, isConfigured: true),
      spec([[0, 3, 4, 5, 6], [0, 3, 4, 6], [0, 3, 6], [3, 6], [3], []], 0.4))

// reconnecting: T 整体闪烁, 2 帧 600ms
check("Reconnecting blinks the whole T",
      iconSpec(for: .reconnecting, isConfigured: true),
      spec([brandTPattern, []], 0.6))

// repairing: 行扫描, 3 帧 350ms
check("Repairing scans rows top to bottom",
      iconSpec(for: .repairing, isConfigured: true),
      spec([[0, 1, 2], [3, 4, 5], [6, 7, 8]], 0.35))

// 错误态: 红色静态单帧, 按错误家族分组
check("timeout error is a red hourglass",
      iconSpec(for: .errTimeout, isConfigured: true),
      spec([[0, 1, 2, 4, 6, 7, 8]], 0, true))
check("dropped error is red broken double bars",
      iconSpec(for: .errDropped, isConfigured: true),
      spec([[0, 2, 3, 5, 6, 8]], 0, true))
check("auth error is a red lock",
      iconSpec(for: .errAuth, isConfigured: true),
      spec([[1, 3, 4, 5, 6, 7, 8]], 0, true))
check("certificate error shares the auth lock",
      iconSpec(for: .errCert, isConfigured: true),
      spec([[1, 3, 4, 5, 6, 7, 8]], 0, true))
check("network-changed error is a red hollow ring",
      iconSpec(for: .errNetworkChanged, isConfigured: true),
      spec([[0, 1, 2, 3, 5, 6, 7, 8]], 0, true))
check("reconnect-failed error shares the hollow ring",
      iconSpec(for: .errReconnectFailed, isConfigured: true),
      spec([[0, 1, 2, 3, 5, 6, 7, 8]], 0, true))
check("route error is a red X",
      iconSpec(for: .errRoute, isConfigured: true),
      spec([[0, 2, 4, 6, 8]], 0, true))
check("stop error shares the X",
      iconSpec(for: .errStop, isConfigured: true),
      spec([[0, 2, 4, 6, 8]], 0, true))

// 同组共用、异组不同
let errorGroups: [[TunnelState]] = [
    [.errTimeout],
    [.errDropped],
    [.errAuth, .errCert],
    [.errNetworkChanged, .errReconnectFailed],
    [.errRoute, .errStop]
]
for group in errorGroups {
    for state in group {
        checkValue("error group members share one spec (\(state))",
                   iconSpec(for: state, isConfigured: true),
                   iconSpec(for: group[0], isConfigured: true))
    }
}
var distinctCount = 0
for (index, group) in errorGroups.enumerated() {
    let groupSpec = iconSpec(for: group[0], isConfigured: true)
    if !errorGroups[..<index].contains(where: { iconSpec(for: $0[0], isConfigured: true) == groupSpec }) {
        distinctCount += 1
    }
}
checkValue("different error groups use different specs", distinctCount, errorGroups.count)

// 忙态为动画、其余为静态;错误态全红、正常态全 template
let animated: [TunnelState] = [.connecting, .disconnecting, .reconnecting, .repairing]
let staticStates: [TunnelState] = [.disconnected, .connected, .errTimeout, .errAuth, .errCert,
                                   .errDropped, .errRoute, .errStop, .errNetworkChanged, .errReconnectFailed]
for state in animated {
    checkValue("busy state is animated (\(state))", iconSpec(for: state, isConfigured: true).isAnimated, true)
    checkValue("busy state is template colored (\(state))", iconSpec(for: state, isConfigured: true).isErrorRed, false)
}
for state in staticStates {
    checkValue("calm state is static (\(state))", iconSpec(for: state, isConfigured: true).isAnimated, false)
}

// 几何与灭点常量: 画布 10r, 灭点 22% 不透明度
checkValue("canvas is 10 dot radii", MenuBarIconGeometry.canvas, MenuBarIconGeometry.dotRadius * 10)
checkValue("menu bar icon canvas is 18pt", MenuBarIconGeometry.canvas, 18)
checkValue("dim dots use 22% opacity", MenuBarIconGeometry.dimAlpha, 0.22)

print("\n\(passed) passed")
