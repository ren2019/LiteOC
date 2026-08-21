import Foundation

enum TunnelState: Equatable {
    case repairing, disconnected, connecting, disconnecting, connected
    case errTimeout, errAuth, errCert, errDropped, errRoute, errStop, errNetworkChanged
}

enum PrimaryMenuAction: Equatable {
    case none, connect, disconnect, openSettings
}

enum MenuTone: Equatable {
    case neutral, busy, connected, error
}

enum SpinnerAnimationAction: Equatable {
    case none, start, stop
}

func spinnerAnimationAction(from previous: TunnelState, to current: TunnelState) -> SpinnerAnimationAction {
    if previous != .connecting, current == .connecting { return .start }
    if previous == .connecting, current != .connecting { return .stop }
    return .none
}

enum PrimaryMenuLayout {
    static let width: CGFloat = 272
    static let height: CGFloat = 46
    static let horizontalInset: CGFloat = 10
    static let statusWidth: CGFloat = 14
    static let actionWidth: CGFloat = 40
    static let spacing: CGFloat = 8
}

struct MenuPresentation: Equatable {
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: PrimaryMenuAction
    let tone: MenuTone

    var isEnabled: Bool { action != .none }
}

func profileIsConfigured(_ config: [String: String]) -> Bool {
    func usable(_ key: String, placeholders: Set<String>) -> Bool {
        let value = (config[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && !placeholders.contains(value)
    }

    return usable("HOST", placeholders: ["vpn.example.com:443"])
        && usable("USER", placeholders: ["your-username"])
        && usable("GROUP", placeholders: ["your-group"])
}

func effectiveProfileIsConfigured(
    _ config: [String: String],
    missingConfigFields: [String]
) -> Bool {
    missingConfigFields.isEmpty && profileIsConfigured(config)
}

func menuPresentation(
    for state: TunnelState,
    isConfigured: Bool,
    connectedIP: String = ""
) -> MenuPresentation {
    switch state {
    case .repairing:
        return MenuPresentation(
            title: "正在检查残留路由…", subtitle: "请稍候", actionTitle: "",
            action: .none, tone: .busy
        )
    case .disconnected where !isConfigured:
        return MenuPresentation(
            title: "未配置", subtitle: "完成设置后即可连接", actionTitle: "设置",
            action: .openSettings, tone: .neutral
        )
    case .disconnected:
        return MenuPresentation(
            title: "未连接", subtitle: "", actionTitle: "连接",
            action: .connect, tone: .neutral
        )
    case .connecting:
        return MenuPresentation(
            title: "正在连接…", subtitle: "", actionTitle: "取消",
            action: .disconnect, tone: .busy
        )
    case .disconnecting:
        return MenuPresentation(
            title: "正在断开…", subtitle: "正在清理路由", actionTitle: "",
            action: .none, tone: .busy
        )
    case .connected:
        return MenuPresentation(
            title: "已连接", subtitle: connectedIP, actionTitle: "断开",
            action: .disconnect, tone: .connected
        )
    case .errAuth:
        return MenuPresentation(
            title: "PIN 有误", subtitle: "修改 PIN 后重试", actionTitle: "设置",
            action: .openSettings, tone: .error
        )
    case .errCert:
        return MenuPresentation(
            title: "证书获取失败", subtitle: "检查证书指纹", actionTitle: "设置",
            action: .openSettings, tone: .error
        )
    case .errTimeout:
        return MenuPresentation(
            title: "连接超时", subtitle: "检查网络", actionTitle: "重试",
            action: .connect, tone: .error
        )
    case .errDropped:
        return MenuPresentation(
            title: "连接已断开", subtitle: "", actionTitle: "重试",
            action: .connect, tone: .error
        )
    case .errNetworkChanged:
        return MenuPresentation(
            title: "网络已变化", subtitle: "", actionTitle: "重试",
            action: .connect, tone: .error
        )
    case .errRoute:
        return MenuPresentation(
            title: "路由清理失败", subtitle: "", actionTitle: "清理",
            action: .disconnect, tone: .error
        )
    case .errStop:
        return MenuPresentation(
            title: "断开未完成", subtitle: "", actionTitle: "清理",
            action: .disconnect, tone: .error
        )
    }
}
