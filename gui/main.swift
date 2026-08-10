import Cocoa
import ServiceManagement

// ---- 硬编码 (不进用户配置) ----
let APPNAME   = "LiteOC"
let VPNCTL    = "/usr/local/sbin/vpnctl"
let ConfDir   = NSHomeDirectory() + "/Library/Application Support/LiteOC"
let ConfPath  = ConfDir + "/config"
let ACCOUNT   = "pin"

// 默认配置模板 (占位符, 首次启动写入)
let defaultConf = #"""
# LiteOC 配置 — PIN 不在此文件 (在 macOS 钥匙串)
# 改完保存, 下次连接即生效

HOST="vpn.example.com:443"
USER="your-username"
GROUP="your-group"
SERVERCERT=""                    # 留空 = 首次连接自动获取 (TOFU)
KEYCHAIN_SERVICE="LiteOC"
KEYCHAIN_ACCOUNT="pin"
"""#

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
    var d = [String: String]()
    guard let txt = try? String(contentsOfFile: ConfPath, encoding: .utf8) else { return d }
    for raw in txt.split(separator: "\n") {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s.hasPrefix("#") { continue }
        guard let eq = s.firstIndex(of: "=") else { continue }
        let k = s[..<eq].trimmingCharacters(in: .whitespaces)
        var v = String(s[s.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 { v = String(v.dropFirst().dropLast()) }
        d[String(k)] = v
    }
    return d
}
let CONF_ORDER = ["HOST", "USER", "GROUP", "SERVERCERT", "KEYCHAIN_SERVICE", "KEYCHAIN_ACCOUNT"]
func writeConfig(_ c: [String: String]) {
    var lines = ["# LiteOC 配置 — PIN 在 macOS 钥匙串", "# 保存即生效", ""]
    for k in CONF_ORDER {
        let v = c[k] ?? (k == "KEYCHAIN_SERVICE" ? "LiteOC" : k == "KEYCHAIN_ACCOUNT" ? "pin" : "")
        lines.append("\(k)=\"\(v)\"")
    }
    try? (lines.joined(separator: "\n") + "\n").write(toFile: ConfPath, atomically: true, encoding: .utf8)
}
func setConfigValue(_ key: String, _ value: String) { var c = loadConfig(); c[key] = value; writeConfig(c) }

func ensureConfig() {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: ConfDir, withIntermediateDirectories: true)
    if !fm.fileExists(atPath: ConfPath) { try? defaultConf.write(toFile: ConfPath, atomically: true, encoding: .utf8) }
}

// ---- 钥匙串 ----
func rawPin(_ service: String) -> String? {
    let s = run("/usr/bin/security", ["find-generic-password", "-s", service, "-a", ACCOUNT, "-w"])
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}
func pinGet(_ target: String) -> String? { rawPin(target) }
func pinSet(_ service: String, _ v: String) {
    run("/usr/bin/security", ["add-generic-password", "-s", service, "-a", ACCOUNT, "-w", v, "-T", "/usr/bin/security", "-U"])
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
        pinState = pinGet(service) == nil ? .empty : .managed
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
        let managed = pinGet(service) != nil
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
    @objc func cancelEditPin() { pinState = pinGet(service) == nil ? .empty : .managed; rebuildPinRow() }
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
        pinState = pinGet(service) == nil ? .empty : .managed
        win.close()
    }
    func show(focusPin: Bool = false) {
        load(); rebuildPinRow(); win.center(); win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if focusPin { self.focusPin() }
    }
}

struct NetworkFingerprint: Equatable { let rawValue: String }

class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var primaryMenuView: PrimaryMenuItemView!
    var autostartItem: NSMenuItem!
    var colorImg: NSImage!
    var grayImg: NSImage!
    var redImg: NSImage!
    var spinnerFrames: [NSImage] = []
    var spinStep = 0
    var spinTimer: Timer?
    var state: TunnelState = .disconnected
    var connectedIP = ""
    var downStreak = 0
    var timer: Timer?
    var connectStart: Date?
    var connectionNetworkFingerprint: NetworkFingerprint?
    let vpnQueue = DispatchQueue(label: "local.liteoc.control")
    var service = "LiteOC"
    var configWin: ConfigWindow?

    func loadImg(_ name: String, template: Bool = false) -> NSImage {
        let p = Bundle.main.path(forResource: name, ofType: "png") ?? ""
        let i = NSImage(contentsOfFile: p) ?? NSImage(); i.isTemplate = template; i.size = NSSize(width: 18, height: 18)
        return i
    }
    func reloadConfig() { service = loadConfig()["KEYCHAIN_SERVICE"] ?? "LiteOC" }
    func currentMenuPresentation() -> MenuPresentation {
        menuPresentation(for: state, isConfigured: profileIsConfigured(loadConfig()), connectedIP: connectedIP)
    }
    func updatePrimaryMenu() { primaryMenuView?.update(currentMenuPresentation()) }

    // 连接中旋转 spinner: 预生成 12 帧 (每 30°), template 随菜单栏明暗自适应; 旋转由独立 spinTimer 驱动
    func loadSpinnerFrames() {
        let p = Bundle.main.path(forResource: "menubar_spinner", ofType: "png") ?? ""
        guard let base = NSImage(contentsOfFile: p) else { return }
        base.isTemplate = true; base.size = NSSize(width: 18, height: 18)
        spinnerFrames = (0..<12).map { rotateImg(base, CGFloat($0) * 30) }
    }
    func rotateImg(_ img: NSImage, _ deg: CGFloat) -> NSImage {
        let S: CGFloat = 18
        let r = NSImage(size: NSSize(width: S, height: S)); r.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: S/2, y: S/2); ctx.rotate(by: -deg * .pi / 180); ctx.translateBy(x: -S/2, y: -S/2)
        img.draw(in: NSRect(x: 0, y: 0, width: S, height: S), from: .zero, operation: .sourceOver, fraction: 1)
        r.unlockFocus(); r.isTemplate = true; r.size = NSSize(width: 18, height: 18)
        return r
    }
    @objc func spinTick() {
        guard !spinnerFrames.isEmpty else { return }
        spinStep = (spinStep + 1) % spinnerFrames.count
        item.button?.image = spinnerFrames[spinStep]
    }
    func startSpin() {
        guard !spinnerFrames.isEmpty else { return }
        item.button?.image = spinnerFrames[0]
        guard spinTimer == nil else { return }
        let t = Timer(timeInterval: 0.08, target: self, selector: #selector(spinTick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common); spinTimer = t
    }
    func stopSpin() { spinTimer?.invalidate(); spinTimer = nil }

    func applicationDidFinishLaunching(_ n: Notification) {
        ensureConfig(); reloadConfig()
        colorImg = loadImg("menubar_color"); grayImg = loadImg("menubar_gray", template: true); redImg = loadImg("menubar_red"); loadSpinnerFrames()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly; item.button?.image = grayImg

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

    func runStatus() -> String {
        run("/usr/bin/sudo", [VPNCTL, "status", ConfPath]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func runNetwork() -> NetworkFingerprint? {
        let value = run("/usr/bin/sudo", [VPNCTL, "network", ConfPath]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("network ") ? NetworkFingerprint(rawValue: value) : nil
    }
    func controlToken(_ output: String, _ allowed: [String]) -> String {
        let lines = output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        for line in lines.reversed() {
            if let token = allowed.first(where: { line == $0 || line.hasPrefix($0 + " ") }) { return token }
        }
        return lines.last ?? ""
    }
    func repairAtLaunch() {
        let host = loadConfig()["HOST"] ?? ""
        if host.isEmpty || host.hasPrefix("vpn.example") { enter(.disconnected); return }
        enter(.repairing)
        vpnQueue.async {
            let token = self.controlToken(run("/usr/bin/sudo", [VPNCTL, "repair", ConfPath]),
                                          ["route-clean", "route-repaired", "already-running",
                                           "route-check-failed", "route-cleanup-failed"])
            DispatchQueue.main.async {
                switch token {
                case "route-clean", "route-repaired", "already-running": self.enter(.disconnected); self.tick()
                default: self.enter(.errRoute)
                }
            }
        }
    }

    // 单一计时器回调: 消费 vpnctl 状态快照,叠加时间/意图维度派生 UI 状态机
    @objc func tick() {
        reloadConfig()
        if state == .connecting || state == .connected, let baseline = connectionNetworkFingerprint {
            guard let current = runNetwork() else { beginDisconnect(after: .errNetworkChanged); return }
            if current != baseline { beginDisconnect(after: .errNetworkChanged); return }
        }
        let parts = runStatus().split(separator: " ")
        let st = String(parts.first ?? "")
        let ip = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
        if st == "route-check-failed", state == .disconnected || state == .connecting || state == .connected {
            enter(.errRoute)
            return
        }
        switch state {
        case .disconnected:
            if st == "connected" { enter(.connected, ip: ip) }
            else if st == "connecting" { enter(.connecting) }   // 外部启动的连接, 跟进
            else if st == "route-stale" { beginDisconnect(after: .disconnected); return }
        case .connecting:
            if st == "connected" { enter(.connected, ip: ip) }
            else if st == "route-stale" { beginDisconnect(after: .errNetworkChanged); return }
            else if st == "down" {
                // openconnect 启动后退出 (>3s) → 连接失败;刚启动短暂 down 容忍
                if let s = connectStart, Date().timeIntervalSince(s) > 3 { beginDisconnect(after: .errTimeout); return }
            }
            else if let s = connectStart, Date().timeIntervalSince(s) > 30 { beginDisconnect(after: .errTimeout); return }
        case .connected:
            if st == "connected" { connectedIP = ip; updatePrimaryMenu(); downStreak = 0 }
            else if st == "route-stale" { beginDisconnect(after: .errNetworkChanged); return }
            else if st == "down" {                 // 防抖: 连续 2 次 down 才判掉线 (openconnect 内置重连瞬断不误触)
                downStreak += 1
                if downStreak >= 2 { beginDisconnect(after: .errDropped); return }
            } else { downStreak = 0 }              // connecting: openconnect 内置重连中, 维持 connected
        case .repairing, .disconnecting, .errTimeout, .errAuth, .errCert, .errDropped,
             .errRoute, .errStop, .errNetworkChanged:
            break                                   // 保持当前状态,等后台操作或用户动作
        }
        updatePrimaryMenu()
        reschedule()
    }

    // 状态驱动单一计时器频率: connecting 0.5s (状态检测), 其余 4s; 连接中的旋转由独立 spinTimer 驱动
    func reschedule() {
        let want: TimeInterval = (state == .connecting) ? 0.5 : 4.0
        if let t = timer, t.timeInterval == want { return }
        timer?.invalidate()
        let t = Timer(timeInterval: want, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common); timer = t
    }

    func enter(_ s: TunnelState, ip: String = "") {
        state = s; downStreak = 0
        connectedIP = (s == .connected) ? ip : ""
        if s != .connecting { stopSpin() }
        switch s {
        case .repairing:
            item.button?.image = grayImg
        case .disconnected:
            item.button?.image = grayImg
        case .connecting:
            connectStart = Date(); spinStep = 0; startSpin()
        case .disconnecting:
            item.button?.image = grayImg
        case .connected:
            guard let current = runNetwork() else { beginDisconnect(after: .errNetworkChanged); return }
            connectionNetworkFingerprint = current
            item.button?.image = colorImg
        case .errTimeout, .errAuth, .errCert, .errDropped, .errRoute, .errStop, .errNetworkChanged:
            item.button?.image = redImg
        }
        updatePrimaryMenu()
        reschedule()
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
        if case .connecting = state { return }      // 已在连接, 忽略重复点击
        guard profileIsConfigured(loadConfig()) else { enter(.disconnected); showConfig(); return }
        guard let pin = pinGet(service) else { enter(.disconnected); showConfig(focusPin: true); return }
        guard let current = runNetwork() else { enter(.errRoute); return }
        connectionNetworkFingerprint = current
        enter(.connecting)
        vpnQueue.async {
            let out = run("/usr/bin/sudo", [VPNCTL, "start", ConfPath], stdin: pin)
            let lines = out.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            if let dc = lines.first(where: { $0.hasPrefix("discovered-cert:") }) {
                setConfigValue("SERVERCERT", String(dc.dropFirst("discovered-cert:".count)))   // TOFU 回写
            }
            let r = self.controlToken(out, ["started", "auth-failed", "no-pin", "already-running",
                                            "cert-discover-failed", "openconnect-not-found",
                                            "route-check-failed", "route-cleanup-failed"])
            DispatchQueue.main.async {
                if self.state != .connecting { return }   // 已离开 connecting (用户已断开等), 丢弃迟到的结果
                switch r {
                case "auth-failed": self.enter(.errAuth)
                case "cert-discover-failed": self.enter(.errCert)
                case "openconnect-not-found": self.enter(.disconnected); self.alert("缺少依赖", "重新运行 LiteOC 安装器(.pkg)以补齐内置 openconnect。")
                case "no-pin": self.enter(.disconnected)
                case "route-check-failed", "route-cleanup-failed": self.enter(.errRoute)
                default: break   // started / already-running: 等 tick 检测 connected
                }
            }
        }
    }
    @objc func doDisconnect() {
        beginDisconnect(after: .disconnected)
    }
    func beginDisconnect(after successState: TunnelState) {
        if state == .disconnecting { return }
        enter(.disconnecting)
        vpnQueue.async {
            let token = self.controlToken(run("/usr/bin/sudo", [VPNCTL, "stop", ConfPath]),
                                          ["stopped", "not-running", "stop-timeout",
                                           "route-check-failed", "route-cleanup-failed"])
            DispatchQueue.main.async {
                self.connectionNetworkFingerprint = nil
                switch token {
                case "stopped", "not-running": self.enter(successState)
                case "stop-timeout": self.enter(.errStop)
                default: self.enter(.errRoute)
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
                self?.reloadConfig(); self?.updatePrimaryMenu()
            }
        }
        configWin?.service = service; configWin?.show(focusPin: focusPin)
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
