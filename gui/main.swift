import Cocoa
import ServiceManagement

// ---- 硬编码 (不进用户配置) ----
let VPNCTL    = "/usr/local/sbin/vpnctl"
let ConfDir   = NSHomeDirectory() + "/Library/Application Support/LiteOC"
let ConfPath  = ConfDir + "/config"

// ---- 跑命令 ----
@discardableResult
func run(_ exe: String, _ args: [String], stdin: String? = nil) -> String {
    let p = Process(); p.launchPath = exe; p.arguments = args
    let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
    if let s = stdin {
        let inp = Pipe(); p.standardInput = inp
        do { try p.run() } catch { return "" }
        inp.fileHandleForWriting.write(s.data(using: .utf8)!); inp.fileHandleForWriting.closeFile()
    } else {
        p.standardInput = Pipe()
        do { try p.run() } catch { return "" }
    }
    p.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

// ---- 配置: 读 / 写 ----
func loadConfig() -> [String: String] {
    AppConfig.load(fromPath: ConfPath)
}
func writeConfig(_ c: [String: String]) {
    try? AppConfig.write(c, toPath: ConfPath)
}
func setConfigValue(_ key: String, _ value: String) { var c = loadConfig(); c[key] = value; writeConfig(c) }

func ensureConfig() {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: ConfDir, withIntermediateDirectories: true)
    try? AppConfig.ensureExists(atPath: ConfPath)
}

// ---- 钥匙串 ----
func rawPin(_ service: String) -> String? {
    let s = run("/usr/bin/security", ["find-generic-password", "-s", service, "-a", AppConfig.keychainAccount, "-w"])
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}
func pinSet(_ service: String, _ v: String) {
    run("/usr/bin/security", ["add-generic-password", "-s", service, "-a", AppConfig.keychainAccount, "-w", v, "-T", "/usr/bin/security", "-U"])
}

// ---- 菜单主状态项 ----
final class PrimaryMenuItemView: NSView {
    private let dot = NSTextField(labelWithString: "○")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let actionLabel = NSTextField(labelWithString: "")
    private var presentation = menuPresentation(for: .disconnected, isConfigured: false)
    private var tracking: NSTrackingArea?
    private var hovered = false
    var onActivate: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        dot.font = .systemFont(ofSize: 16, weight: .medium)
        dot.alignment = .center
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 11)
        actionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        actionLabel.alignment = .right
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actionLabel.setContentHuggingPriority(.required, for: .horizontal)
        actionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let copy = NSStackView(views: [titleLabel, subtitleLabel])
        copy.orientation = .vertical; copy.alignment = .leading; copy.spacing = 2
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [dot, copy, actionLabel])
        row.orientation = .horizontal; row.alignment = .centerY; row.distribution = .fill
        row.spacing = PrimaryMenuLayout.spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: PrimaryMenuLayout.width),
            heightAnchor.constraint(equalToConstant: PrimaryMenuLayout.height),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PrimaryMenuLayout.horizontalInset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PrimaryMenuLayout.horizontalInset),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: PrimaryMenuLayout.statusWidth),
            actionLabel.widthAnchor.constraint(equalToConstant: PrimaryMenuLayout.actionWidth)
        ])
        setAccessibilityRole(.button)
        update(presentation)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }

    override func mouseEntered(with event: NSEvent) { if presentation.isEnabled { hovered = true; updateColors() } }
    override func mouseExited(with event: NSEvent) { hovered = false; updateColors() }
    override func mouseUp(with event: NSEvent) {
        guard presentation.isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        onActivate?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 4, dy: 3)
        let fill: NSColor
        if hovered && presentation.isEnabled {
            fill = .selectedContentBackgroundColor
        } else {
            switch presentation.tone {
            case .neutral, .connected: fill = NSColor.systemGreen.withAlphaComponent(0.11)
            case .busy: fill = NSColor.systemOrange.withAlphaComponent(0.11)
            case .error: fill = NSColor.systemRed.withAlphaComponent(0.11)
            }
        }
        fill.setFill(); NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
    }

    func update(_ value: MenuPresentation) {
        presentation = value
        titleLabel.stringValue = value.title
        subtitleLabel.stringValue = value.subtitle
        subtitleLabel.isHidden = value.subtitle.isEmpty
        actionLabel.stringValue = value.actionTitle
        setAccessibilityLabel(value.title)
        setAccessibilityHelp(value.subtitle)
        updateColors()
    }

    private func updateColors() {
        if hovered && presentation.isEnabled {
            dot.textColor = .white; titleLabel.textColor = .white
            subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.78); actionLabel.textColor = .white
        } else {
            titleLabel.textColor = .labelColor; subtitleLabel.textColor = .secondaryLabelColor
            switch presentation.tone {
            case .neutral: dot.stringValue = "○"; dot.textColor = .secondaryLabelColor; actionLabel.textColor = .systemGreen
            case .busy: dot.stringValue = "●"; dot.textColor = .systemOrange; actionLabel.textColor = .systemOrange
            case .connected: dot.stringValue = "●"; dot.textColor = .systemGreen; actionLabel.textColor = .systemGreen
            case .error: dot.stringValue = "●"; dot.textColor = .systemRed; actionLabel.textColor = .systemRed
            }
        }
        needsDisplay = true
    }
}

// ---- 配置窗口 ----
enum PinState { case managed, empty, editing }

final class ConfigWindow: NSObject {
    let win: NSWindow
    let host = NSTextField(), user = NSTextField(), group = NSTextField()
    let certSec = NSSecureTextField(), certPlain = NSTextField()
    let certToggle = NSButton(title: "显示", target: nil, action: nil)
    let validation = NSTextField(labelWithString: "")
    let pinBox = NSBox()
    var certRevealed = false
    var pinState = PinState.empty
    var pinField = NSSecureTextField()
    var service = "LiteOC"
    var onSaved: (() -> Void)?

    init(service: String, onSaved: @escaping () -> Void) {
        self.service = service; self.onSaved = onSaved
        win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        win.title = "LiteOC 设置"; win.isReleasedWhenClosed = false
        win.contentMinSize = NSSize(width: 560, height: 430)

        let cv = win.contentView!
        func label(_ text: String) -> NSTextField {
            let value = NSTextField(labelWithString: text)
            value.alignment = .right; value.textColor = .secondaryLabelColor; value.font = .systemFont(ofSize: 12)
            return value
        }
        func configureField(_ field: NSTextField, placeholder: String = "") {
            field.placeholderString = placeholder; field.font = .systemFont(ofSize: 13)
            field.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }
        func sectionTitle(_ text: String) -> NSTextField {
            let value = NSTextField(labelWithString: text)
            value.font = .systemFont(ofSize: 11, weight: .semibold); value.textColor = .secondaryLabelColor
            return value
        }
        func separator() -> NSBox {
            let box = NSBox(); box.boxType = .separator
            return box
        }

        configureField(host, placeholder: "vpn.example.com:443")
        configureField(user); configureField(group)
        configureField(certSec, placeholder: "留空 = 首次连接自动获取")
        configureField(certPlain, placeholder: "pin-sha256:…")
        certPlain.isHidden = true
        certToggle.target = self; certToggle.action = #selector(toggleCert); certToggle.bezelStyle = .rounded
        certToggle.widthAnchor.constraint(equalToConstant: 54).isActive = true

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 42), icon.heightAnchor.constraint(equalToConstant: 42)])
        let heading = NSTextField(labelWithString: "连接设置")
        heading.font = .systemFont(ofSize: 20, weight: .bold)
        let intro = NSTextField(labelWithString: "连接参数与凭证都在这里管理。")
        intro.font = .systemFont(ofSize: 12); intro.textColor = .secondaryLabelColor
        let headerCopy = NSStackView(views: [heading, intro])
        headerCopy.orientation = .vertical; headerCopy.alignment = .leading; headerCopy.spacing = 3
        let header = NSStackView(views: [icon, headerCopy])
        header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 13

        validation.font = .systemFont(ofSize: 11, weight: .medium)
        validation.textColor = .systemRed; validation.isHidden = true

        let connectionGrid = NSGridView(views: [
            [label("VPN 网关"), host], [label("用户名"), user], [label("用户组"), group]
        ])
        connectionGrid.columnSpacing = 14; connectionGrid.rowSpacing = 10
        connectionGrid.column(at: 0).width = 88; connectionGrid.column(at: 0).xPlacement = .trailing
        connectionGrid.column(at: 1).width = 390; connectionGrid.column(at: 1).xPlacement = .fill
        let connectionSection = NSStackView(views: [sectionTitle("连接"), connectionGrid])
        connectionSection.orientation = .vertical; connectionSection.alignment = .leading; connectionSection.spacing = 10

        let certFields = NSView(); certFields.translatesAutoresizingMaskIntoConstraints = false
        [certSec, certPlain, certToggle].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; certFields.addSubview($0) }
        NSLayoutConstraint.activate([
            certFields.heightAnchor.constraint(equalToConstant: 32),
            certSec.leadingAnchor.constraint(equalTo: certFields.leadingAnchor), certSec.topAnchor.constraint(equalTo: certFields.topAnchor),
            certSec.bottomAnchor.constraint(equalTo: certFields.bottomAnchor), certSec.trailingAnchor.constraint(equalTo: certToggle.leadingAnchor, constant: -8),
            certPlain.leadingAnchor.constraint(equalTo: certSec.leadingAnchor), certPlain.trailingAnchor.constraint(equalTo: certSec.trailingAnchor),
            certPlain.topAnchor.constraint(equalTo: certSec.topAnchor), certPlain.bottomAnchor.constraint(equalTo: certSec.bottomAnchor),
            certToggle.trailingAnchor.constraint(equalTo: certFields.trailingAnchor), certToggle.centerYAnchor.constraint(equalTo: certFields.centerYAnchor)
        ])
        let certHint = NSTextField(labelWithString: "首次配置可留空，连接时自动获取。")
        certHint.font = .systemFont(ofSize: 11); certHint.textColor = .tertiaryLabelColor
        let certStack = NSStackView(views: [certFields, certHint])
        certStack.orientation = .vertical; certStack.alignment = .leading; certStack.spacing = 5
        certStack.widthAnchor.constraint(equalToConstant: 390).isActive = true

        pinBox.boxType = .custom; pinBox.borderWidth = 0; pinBox.cornerRadius = 8
        pinBox.contentViewMargins = NSSize(width: 10, height: 6)
        pinBox.heightAnchor.constraint(equalToConstant: 42).isActive = true
        pinBox.widthAnchor.constraint(equalToConstant: 390).isActive = true

        let securityGrid = NSGridView(views: [
            [label("证书指纹"), certStack], [label("PIN"), pinBox]
        ])
        securityGrid.columnSpacing = 14; securityGrid.rowSpacing = 12
        securityGrid.column(at: 0).width = 88; securityGrid.column(at: 0).xPlacement = .trailing
        securityGrid.column(at: 1).width = 390; securityGrid.column(at: 1).xPlacement = .fill
        let securitySection = NSStackView(views: [sectionTitle("安全"), securityGrid])
        securitySection.orientation = .vertical; securitySection.alignment = .leading; securitySection.spacing = 10

        let body = NSStackView(views: [header, validation, connectionSection, separator(), securitySection])
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 12
        body.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(body)

        let save = NSButton(title: "保存更改", target: self, action: #selector(doSave))
        save.keyEquivalent = "\r"; save.bezelStyle = .rounded
        let cancel = NSButton(title: "取消", target: self, action: #selector(doClose))
        cancel.keyEquivalent = "\u{1b}"; cancel.bezelStyle = .rounded
        let footer = NSStackView(views: [cancel, save])
        footer.orientation = .horizontal; footer.alignment = .centerY; footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false
        let footerSeparator = separator(); footerSeparator.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(footerSeparator); cv.addSubview(footer)

        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: cv.topAnchor, constant: 22),
            body.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -24),
            connectionSection.widthAnchor.constraint(equalTo: body.widthAnchor),
            securitySection.widthAnchor.constraint(equalTo: body.widthAnchor),
            footerSeparator.leadingAnchor.constraint(equalTo: cv.leadingAnchor), footerSeparator.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            footerSeparator.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            body.bottomAnchor.constraint(lessThanOrEqualTo: footerSeparator.topAnchor, constant: -16),
            footer.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -24), footer.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14),
            save.widthAnchor.constraint(equalToConstant: 90), cancel.widthAnchor.constraint(equalToConstant: 72)
        ])

        load(); rebuildPinRow()
    }

    var certValue: String { certRevealed ? certPlain.stringValue : certSec.stringValue }

    func load() {
        let c = loadConfig()
        host.stringValue = c["HOST"] ?? ""; user.stringValue = c["USER"] ?? ""; group.stringValue = c["GROUP"] ?? ""
        let cert = c["SERVERCERT"] ?? ""
        certSec.stringValue = cert; certPlain.stringValue = cert
        certRevealed = false; certSec.isHidden = false; certPlain.isHidden = true; certToggle.title = "显示"
        validation.isHidden = true
        pinState = rawPin(service) == nil ? .empty : .managed
    }

    @objc func toggleCert() {
        certRevealed.toggle()
        let value = certRevealed ? certSec.stringValue : certPlain.stringValue
        certSec.stringValue = value; certPlain.stringValue = value
        certSec.isHidden = certRevealed; certPlain.isHidden = !certRevealed
        certToggle.title = certRevealed ? "隐藏" : "显示"
    }

    func rebuildPinRow(focus: Bool = false) {
        let content = pinBox.contentView ?? pinBox
        content.subviews.forEach { $0.removeFromSuperview() }
        let managed = rawPin(service) != nil
        pinBox.fillColor = (managed && pinState != .editing)
            ? NSColor.systemGreen.withAlphaComponent(0.12) : .controlBackgroundColor

        let row: NSStackView
        if managed && pinState != .editing {
            let ok = NSTextField(labelWithString: "✓  PIN 已安全存储在钥匙串")
            ok.font = .systemFont(ofSize: 12, weight: .semibold); ok.textColor = .systemGreen
            let edit = NSButton(title: "修改…", target: self, action: #selector(editPin)); edit.bezelStyle = .rounded
            row = NSStackView(views: [ok, edit])
        } else {
            pinField = NSSecureTextField(); pinField.placeholderString = "输入 PIN"; pinField.font = .systemFont(ofSize: 13)
            let save = NSButton(title: "存入钥匙串", target: self, action: #selector(savePin)); save.bezelStyle = .rounded
            var views: [NSView] = [pinField, save]
            if managed {
                let cancel = NSButton(title: "取消", target: self, action: #selector(cancelEditPin)); cancel.bezelStyle = .rounded
                views.append(cancel)
            }
            row = NSStackView(views: views)
            pinField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        }
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor), row.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
        if focus { win.makeFirstResponder(pinField) }
    }

    func focusPin() {
        pinState = .editing; rebuildPinRow(focus: true)
        showValidation("连接前请先存入 PIN。")
    }

    @objc func editPin() { pinState = .editing; rebuildPinRow(focus: true) }
    @objc func cancelEditPin() { pinState = rawPin(service) == nil ? .empty : .managed; rebuildPinRow() }
    @objc func savePin() {
        let value = pinField.stringValue
        guard !value.isEmpty else { showValidation("请输入 PIN 后再存入钥匙串。"); win.makeFirstResponder(pinField); return }
        pinSet(service, value); pinField.stringValue = ""; pinState = .managed; validation.isHidden = true; rebuildPinRow()
        onSaved?()
    }

    private func showValidation(_ message: String) { validation.stringValue = message; validation.isHidden = false }

    @objc func doSave() {
        let fields: [(NSTextField, String)] = [(host, "vpn.example.com:443"), (user, "your-username"), (group, "your-group")]
        if let invalid = fields.first(where: {
            let value = $0.0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty || value == $0.1
        }) {
            showValidation("请填写 VPN 网关、用户名和用户组。")
            win.makeFirstResponder(invalid.0); return
        }
        var c = loadConfig()
        c["HOST"] = host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        c["USER"] = user.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        c["GROUP"] = group.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        c["SERVERCERT"] = certValue.trimmingCharacters(in: .whitespacesAndNewlines)
        writeConfig(c); onSaved?(); doClose()
    }

    @objc func doClose() {
        pinField.stringValue = ""
        pinState = rawPin(service) == nil ? .empty : .managed
        win.close()
    }
    func show(focusPin: Bool = false) {
        load(); rebuildPinRow(); win.center(); win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if focusPin { self.focusPin() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var primaryMenuView: PrimaryMenuItemView!
    var autostartItem: NSMenuItem!
    var colorImg: NSImage!
    var grayImg: NSImage!
    var redImg: NSImage!
    var spinner: NSProgressIndicator!
    var reducerContext: TunnelReducer.Context = .init(
        phase: .disconnected,
        downStreak: 0,
        connectStart: nil,
        connectionNetworkFingerprint: nil
    )
    var state: TunnelState { reducerContext.phase }
    var connectedIP = ""
    var timer: Timer?
    var helperMissingConfigFields: [String] = []
    let reducerThresholds = TunnelReducer.Thresholds(
        connectingDownGrace: 3,
        connectingTimeout: 30,
        connectedDownLimit: 2
    )
    let vpnQueue = DispatchQueue(label: "local.liteoc.control")
    let pollQueue = DispatchQueue(label: "local.liteoc.poll")
    let networkReadQueue = DispatchQueue(label: "local.liteoc.network-read")
    lazy var poller = TunnelPoller(workerQueue: pollQueue)
    lazy var networkReader = BackgroundReadCoordinator<TunnelReducer.NetworkRead>(
        workerQueue: networkReadQueue
    )
    let vpnctl = VpnctlClient(vpnctlPath: VPNCTL, configPath: ConfPath)
    var service = "LiteOC"
    var configWin: ConfigWindow?

    func loadImg(_ name: String, template: Bool = false) -> NSImage {
        let p = Bundle.main.path(forResource: name, ofType: "png") ?? ""
        let i = NSImage(contentsOfFile: p) ?? NSImage(); i.isTemplate = template; i.size = NSSize(width: 18, height: 18)
        return i
    }
    func reloadConfig() { service = loadConfig()["KEYCHAIN_SERVICE"] ?? "LiteOC" }
    func currentMenuPresentation() -> MenuPresentation {
        let isConfigured = effectiveProfileIsConfigured(
            loadConfig(),
            missingConfigFields: helperMissingConfigFields
        )
        return menuPresentation(for: state, isConfigured: isConfigured, connectedIP: connectedIP)
    }
    func updatePrimaryMenu() { primaryMenuView?.update(currentMenuPresentation()) }
    func applicationDidFinishLaunching(_ n: Notification) {
        ensureConfig(); reloadConfig()
        colorImg = loadImg("menubar_color"); grayImg = loadImg("menubar_gray", template: true); redImg = loadImg("menubar_red")
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly; item.button?.image = grayImg
        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        if let button = item.button {
            button.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                spinner.widthAnchor.constraint(equalToConstant: 16),
                spinner.heightAnchor.constraint(equalToConstant: 16)
            ])
        }

        let menu = NSMenu(); menu.autoenablesItems = false
        primaryMenuView = PrimaryMenuItemView(
            frame: NSRect(x: 0, y: 0, width: PrimaryMenuLayout.width, height: PrimaryMenuLayout.height)
        )
        primaryMenuView.onActivate = { [weak self] in self?.performPrimaryMenuAction() }
        let primaryItem = NSMenuItem(); primaryItem.view = primaryMenuView
        menu.addItem(primaryItem); menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(doEditConfig), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        autostartItem = NSMenuItem(title: "登录时自动启动", action: #selector(toggleAutostart), keyEquivalent: ""); autostartItem.target = self
        autostartItem.state = autostartEnabled() ? .on : .off
        menu.addItem(autostartItem); menu.addItem(.separator())

        let about = NSMenuItem(title: "关于 LiteOC", action: #selector(showAbout), keyEquivalent: ""); about.target = self
        let github = NSMenuItem(title: "访问 GitHub", action: #selector(openGitHub), keyEquivalent: ""); github.target = self
        let feedback = NSMenuItem(title: "提交反馈…", action: #selector(openFeedback), keyEquivalent: ""); feedback.target = self
        menu.addItem(about); menu.addItem(github); menu.addItem(feedback); menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "退出 LiteOC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        updatePrimaryMenu()

        repairAtLaunch()
    }

    func repairAtLaunch() {
        let host = loadConfig()["HOST"] ?? ""
        reduce(.launch(profileConfigured: !host.isEmpty && !host.hasPrefix("vpn.example")))
    }

    func repairTunnelEffect() {
        vpnQueue.async {
            let result: Result<RepairResult, VpnctlClientFailure>
            do {
                result = .success(try self.vpnctl.repair())
            } catch let failure as VpnctlClientFailure {
                result = .failure(failure)
            } catch {
                result = .failure(.spawnFailed)
            }
            DispatchQueue.main.async {
                switch result {
                case let .success(value):
                    self.reduce(.repairCompleted(value))
                case .failure:
                    self.reduce(.repairFailed)
                }
            }
        }
    }

    // 单一计时器回调: 主线程只提交快照请求；读取完成后归约并渲染。
    @objc func tick() {
        let phase = state
        let baseline = reducerContext.connectionNetworkFingerprint
        poller.request(
            read: { [weak self] in
                self?.readPollSample(phase: phase, baseline: baseline)
                    ?? TunnelPollSample(snapshot: nil, network: nil, clearsMissingConfigFields: false)
            },
            deliver: { [weak self] sample in
                guard let self else { return }
                if let keychainService = sample.keychainService {
                    self.service = keychainService
                }
                if sample.clearsMissingConfigFields {
                    self.interpret([.clearMissingConfigFields])
                }
                self.reduce(sample.snapshot, network: sample.network)
            }
        )
    }

    func readPollSample(phase: TunnelState, baseline: Fingerprint?) -> TunnelPollSample {
        let keychainService = loadConfig()["KEYCHAIN_SERVICE"] ?? "LiteOC"
        var network = baseline
        var networkReadSucceeded = false
        if (phase == .connecting || phase == .connected), baseline != nil {
            do {
                network = try vpnctl.network()
                networkReadSucceeded = true
            } catch let failure as VpnctlClientFailure {
                if case let .configError(missingFields: missingFields) = failure {
                    return TunnelPollSample(
                        snapshot: .configError(missingFields: missingFields),
                        network: network,
                        clearsMissingConfigFields: false,
                        keychainService: keychainService
                    )
                }
                return TunnelPollSample(
                    snapshot: nil,
                    network: nil,
                    clearsMissingConfigFields: false,
                    keychainService: keychainService
                )
            } catch {
                return TunnelPollSample(
                    snapshot: nil,
                    network: nil,
                    clearsMissingConfigFields: false,
                    keychainService: keychainService
                )
            }
        }

        let snapshot: StatusSnapshot?
        do {
            snapshot = try vpnctl.status()
        } catch {
            snapshot = nil
        }
        let clearsMissingConfigFields: Bool
        if let snapshot, case .configError = snapshot {
            clearsMissingConfigFields = networkReadSucceeded
        } else {
            clearsMissingConfigFields = networkReadSucceeded || snapshot != nil
        }
        return TunnelPollSample(
            snapshot: snapshot,
            network: network,
            clearsMissingConfigFields: clearsMissingConfigFields,
            keychainService: keychainService
        )
    }

    func reduce(_ snapshot: StatusSnapshot?, network: Fingerprint?) {
        let result = TunnelReducer.reduce(
            state: reducerContext,
            snapshot: snapshot,
            network: network,
            now: Date(),
            thresholds: reducerThresholds
        )
        apply(result, snapshot: snapshot)
    }

    func reduce(_ event: TunnelReducer.Event) {
        poller.invalidate()
        apply(TunnelReducer.reduce(state: reducerContext, event: event, now: Date()))
    }

    func apply(_ result: TunnelReducer.Result, snapshot: StatusSnapshot? = nil) {
        let previousState = state
        if result.state != reducerContext {
            networkReader.invalidate()
        }
        reducerContext = result.state
        if case let .connected(ip: ip)? = snapshot, state == .connected {
            connectedIP = ip
        } else if state != .connected {
            connectedIP = ""
        }
        updateStatePresentation(from: previousState)
        interpret(result.effects)
    }

    // 状态驱动单一计时器频率: connecting 0.5s (状态检测),其余 4s。
    func reschedule() {
        let want: TimeInterval = (state == .connecting) ? 0.5 : 4.0
        if let t = timer, t.timeInterval == want { return }
        timer?.invalidate()
        let t = Timer(timeInterval: want, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common); timer = t
    }

    func updateStatePresentation(from previousState: TunnelState) {
        switch spinnerAnimationAction(from: previousState, to: state) {
        case .start:
            spinner.startAnimation(nil)
        case .stop:
            spinner.stopAnimation(nil)
        case .none:
            break
        }
        switch state {
        case .repairing:
            item.button?.image = grayImg
        case .disconnected:
            item.button?.image = grayImg
        case .connecting:
            item.button?.image = nil
        case .disconnecting:
            item.button?.image = grayImg
        case .connected:
            item.button?.image = colorImg
        case .errTimeout, .errAuth, .errCert, .errDropped, .errRoute, .errStop, .errNetworkChanged:
            item.button?.image = redImg
        }
        updatePrimaryMenu()
        reschedule()
    }

    func interpret(_ effects: [TunnelReducer.Effect]) {
        for effect in effects {
            switch effect {
            case .repairTunnel:
                repairTunnelEffect()
            case .readConnectionNetwork:
                readConnectionNetworkEffect()
            case .startConnect:
                startConnectionEffect()
            case let .stopTunnel(after: successState):
                stopTunnelEffect(after: successState)
            case .captureFingerprint:
                captureFingerprintEffect()
            case let .persistCertificate(certificate):
                setConfigValue("SERVERCERT", certificate)
            case .refreshStatus:
                tick()
            case let .showSettings(focusPin):
                showConfig(focusPin: focusPin)
            case let .recordMissingConfigFields(missingFields):
                helperMissingConfigFields = missingFields
                updatePrimaryMenu()
            case .clearMissingConfigFields:
                helperMissingConfigFields = []
                updatePrimaryMenu()
            case .alert(.openconnectMissing):
                alert("缺少依赖", "重新运行 LiteOC 安装器(.pkg)以补齐内置 openconnect。")
            }
        }
    }

    func readNetwork() -> TunnelReducer.NetworkRead {
        do {
            guard let current = try vpnctl.network() else { return .unavailable }
            return .available(current)
        } catch let failure as VpnctlClientFailure {
            if case let .configError(missingFields: missingFields) = failure {
                return .configError(missingFields: missingFields)
            }
            return .failed
        } catch {
            return .failed
        }
    }

    func readNetworkEffect(_ makeEvent: @escaping (TunnelReducer.NetworkRead) -> TunnelReducer.Event) {
        let expectedContext = reducerContext
        networkReader.request(
            read: { [weak self] in self?.readNetwork() ?? .failed },
            deliver: { [weak self] result in
                guard let self, self.reducerContext == expectedContext else { return }
                self.reduce(makeEvent(result))
            }
        )
    }

    func readConnectionNetworkEffect() {
        readNetworkEffect { .connectionNetworkRead($0) }
    }

    func captureFingerprintEffect() {
        readNetworkEffect { .fingerprintRead($0) }
    }

    func performPrimaryMenuAction() {
        switch currentMenuPresentation().action {
        case .none: break
        case .connect: doConnect()
        case .disconnect: doDisconnect()
        case .openSettings: showConfig(focusPin: state == .errAuth)
        }
    }

    @objc func doConnect() {
        reloadConfig()
        let configured = profileIsConfigured(loadConfig())
        let pinAvailable = configured && rawPin(service) != nil
        reduce(.connectRequested(profileConfigured: configured, pinAvailable: pinAvailable))
    }

    func startConnectionEffect() {
        guard let pin = rawPin(service) else {
            reduce(.startCompleted(.noPin))
            return
        }
        vpnQueue.async {
            let result: Result<StartResult, VpnctlClientFailure>
            do {
                result = .success(try self.vpnctl.start(pin: pin))
            } catch let failure as VpnctlClientFailure {
                result = .failure(failure)
            } catch {
                result = .failure(.spawnFailed)
            }
            DispatchQueue.main.async {
                switch result {
                case let .success(value):
                    self.reduce(.startCompleted(value))
                case .failure:
                    self.reduce(.startFailed)
                }
            }
        }
    }
    @objc func doDisconnect() {
        beginDisconnect(after: .disconnected)
    }
    func beginDisconnect(after successState: TunnelState) {
        reduce(.disconnectRequested(after: successState))
    }

    func stopTunnelEffect(after successState: TunnelState) {
        vpnQueue.async {
            let result: Result<StopResult, VpnctlClientFailure>
            do {
                result = .success(try self.vpnctl.stop())
            } catch let failure as VpnctlClientFailure {
                result = .failure(failure)
            } catch {
                result = .failure(.spawnFailed)
            }
            DispatchQueue.main.async {
                switch result {
                case let .success(value):
                    self.reduce(.stopCompleted(value, after: successState))
                case .failure:
                    self.reduce(.stopFailed)
                }
            }
        }
    }
    @objc func doEditConfig() {
        showConfig()
    }
    func showConfig(focusPin: Bool = false) {
        if configWin == nil {
            configWin = ConfigWindow(service: service) { [weak self] in
                self?.invalidateBackgroundReads()
                self?.helperMissingConfigFields = []
                self?.reloadConfig(); self?.updatePrimaryMenu()
            }
        }
        configWin?.service = service; configWin?.show(focusPin: focusPin)
    }

    func invalidateBackgroundReads() {
        poller.invalidate()
        networkReader.invalidate()
    }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    @objc func openGitHub() {
        if let url = URL(string: "https://github.com/ren2019/LiteOC") { NSWorkspace.shared.open(url) }
    }
    @objc func openFeedback() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let body = """
        ## 问题或建议

        请描述你遇到的问题或希望改进的地方。

        ## 环境
        - LiteOC: \(version)
        - macOS: \(os)

        > 请勿粘贴 PIN、证书指纹、网关地址或公司内网信息。
        """
        var components = URLComponents(string: "https://github.com/ren2019/LiteOC/issues/new")!
        components.queryItems = [URLQueryItem(name: "title", value: "[反馈] "), URLQueryItem(name: "body", value: body)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
    func alert(_ t: String, _ m: String) { let a = NSAlert(); a.messageText = t; a.informativeText = m; a.addButton(withTitle: "好"); a.runModal() }

    func autostartEnabled() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    @objc func toggleAutostart() {
        guard #available(macOS 13.0, *) else { alert("不支持", "登录时自动启动需 macOS 13 及以上。"); return }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { alert("设置失败", error.localizedDescription) }
        autostartItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }
}

@main
enum LiteOCApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
