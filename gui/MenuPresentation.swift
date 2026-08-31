import Foundation

enum TunnelState: Equatable {
    case repairing, disconnected, connecting, disconnecting, connected, reconnecting
    case errTimeout, errAuth, errCert, errDropped, errRoute, errStop, errNetworkChanged, errReconnectFailed
}

enum PrimaryMenuAction: Equatable {
    case none, connect, disconnect, openSettings
}

enum MenuTone: Equatable {
    case neutral, busy, connected, error
}

enum PrimaryMenuLayout {
    // 宽度由菜单内容决定(自定义 view 不设固定宽, NSMenu 会拉伸到菜单宽); 仅保留纵向与内边距几何。
    static let height: CGFloat = 46
    /// 自定义 view 初始宽: 仅作菜单内容最小宽参考, NSMenu 展开时拉伸到菜单宽 (menu.minimumWidth 兜底)。
    static let initialViewWidth: CGFloat = 160
    /// 与标准 NSMenuItem 文字缩进对齐 (实测系统菜单文字距菜单边缘约 15pt)。
    static let horizontalInset: CGFloat = 15
    static let actionWidth: CGFloat = 40
    static let spacing: CGFloat = 8
}

enum ConnectionInfoLayout {
    static let height: CGFloat = 44
}

struct MenuPresentation: Equatable {
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: PrimaryMenuAction
    let tone: MenuTone
    /// 未配置引导: 首行以红色描边提示完成初始设置 (2026-08-31 首行样式定稿"有事才着色")。
    let configurationGuide: Bool

    init(title: String, subtitle: String, actionTitle: String, action: PrimaryMenuAction, tone: MenuTone, configurationGuide: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
        self.tone = tone
        self.configurationGuide = configurationGuide
    }

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
            action: .openSettings, tone: .neutral, configurationGuide: true
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
    case .reconnecting:
        return MenuPresentation(
            title: "正在重新连接…", subtitle: "网络已变化", actionTitle: "取消",
            action: .disconnect, tone: .busy
        )
    case .disconnecting:
        return MenuPresentation(
            title: "正在断开…", subtitle: "正在清理路由", actionTitle: "",
            action: .none, tone: .busy
        )
    case .connected:
        // 2026-08-31: IP 移入 Connection Info Row, 首行副标题留空。
        return MenuPresentation(
            title: "已连接", subtitle: "", actionTitle: "断开",
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
    case .errReconnectFailed:
        return MenuPresentation(
            title: "重连失败", subtitle: "", actionTitle: "重试",
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

struct ConnectionInfoPresentation: Equatable {
    /// 隧道 IP (等宽字体展示)。
    let title: String
    /// 默认 "网关 <host:port>"; 复制后为一次性 "已复制到剪贴板"。
    let subtitle: String
}

// Connection Info Row: 仅 connected 且有有效 IP 时出现 (CONTEXT.md 术语)。
// "已复制"瞬态由 App 层注入一次性标志, 呈现层只做映射。
func connectionInfoPresentation(
    for state: TunnelState,
    connectedIP: String = "",
    gateway: String = "",
    showsCopiedConfirmation: Bool = false
) -> ConnectionInfoPresentation? {
    guard state == .connected, !connectedIP.isEmpty else { return nil }
    return ConnectionInfoPresentation(
        title: connectedIP,
        subtitle: showsCopiedConfirmation ? "已复制到剪贴板" : "网关 \(gateway)"
    )
}
