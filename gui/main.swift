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

// ---- 配置窗口 ----
enum PinState { case managed, empty, editing }

class ConfigWindow: NSObject {
    let win: NSWindow
    let host = NSTextField(), user = NSTextField(), group = NSTextField()
    let certSec = NSSecureTextField(), certPlain = NSTextField()
    var certRevealed = false
    let pinBox = NSView()
    var pinState = PinState.empty
    var pinField = NSSecureTextField()
    var service = "LiteOC"
    var onSaved: (() -> Void)?

    init(service: String, onSaved: @escaping () -> Void) {
        self.service = service; self.onSaved = onSaved
        win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 360),
                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        win.title = "LiteOC 配置"; win.isReleasedWhenClosed = false
        let cv = win.contentView!
        func add(_ y: CGFloat, _ label: String, _ f: NSTextField, _ ph: String) {
            let l = NSTextField(labelWithString: label); l.alignment = .right
            l.frame = NSRect(x: 16, y: y, width: 96, height: 22)
            f.placeholderString = ph; f.frame = NSRect(x: 120, y: y, width: 340, height: 22)
            cv.addSubview(l); cv.addSubview(f)
        }
        add(310, "网关 host:port", host, "vpn.example.com:443")
        add(278, "用户名", user, "")
        add(246, "用户组", group, "")
        // 证书: secure(默认) + plain(同位置), 👁 切换
        let certLbl = NSTextField(labelWithString: "证书指纹"); certLbl.alignment = .right
        certLbl.frame = NSRect(x: 16, y: 214, width: 96, height: 22)
        certSec.placeholderString = "留空 = 首次连接自动获取"; certSec.frame = NSRect(x: 120, y: 214, width: 340, height: 22)
        certPlain.placeholderString = "pin-sha256:…"; certPlain.frame = NSRect(x: 120, y: 214, width: 340, height: 22)
        certPlain.isHidden = true
        let eye = NSButton(title: "👁", target: self, action: #selector(toggleCert)); eye.bezelStyle = .rounded
        eye.frame = NSRect(x: 468, y: 213, width: 52, height: 24)
        let certHint = NSTextField(labelWithString: "首次配置留空，自动获取")
        certHint.font = .systemFont(ofSize: 11); certHint.textColor = .secondaryLabelColor
        certHint.frame = NSRect(x: 120, y: 192, width: 400, height: 14)
        cv.addSubview(certLbl); cv.addSubview(certSec); cv.addSubview(certPlain); cv.addSubview(eye); cv.addSubview(certHint)
        // PIN 行
        let pinLbl = NSTextField(labelWithString: "PIN"); pinLbl.alignment = .right
        pinLbl.frame = NSRect(x: 16, y: 158, width: 96, height: 22)
        pinBox.frame = NSRect(x: 120, y: 148, width: 400, height: 34)
        cv.addSubview(pinLbl); cv.addSubview(pinBox)
        // 保存 / 取消
        let save = NSButton(title: "保存", target: self, action: #selector(doSave)); save.keyEquivalent = "\r"; save.bezelStyle = .rounded
        save.frame = NSRect(x: 444, y: 16, width: 80, height: 32); cv.addSubview(save)
        let canc = NSButton(title: "取消", target: self, action: #selector(doClose)); canc.bezelStyle = .rounded
        canc.frame = NSRect(x: 360, y: 16, width: 80, height: 32); cv.addSubview(canc)
        load(); rebuildPinRow()
    }

    func load() {
        let c = loadConfig()
        host.stringValue = c["HOST"] ?? ""; user.stringValue = c["USER"] ?? ""; group.stringValue = c["GROUP"] ?? ""
        let cert = c["SERVERCERT"] ?? ""
        certSec.stringValue = cert; certPlain.stringValue = cert
    }
    var certValue: String { certRevealed ? certPlain.stringValue : certSec.stringValue }

    @objc func toggleCert() {
        certRevealed.toggle()
        let v = certRevealed ? certSec.stringValue : certPlain.stringValue
        certSec.stringValue = v; certPlain.stringValue = v
        certSec.isHidden = certRevealed; certPlain.isHidden = !certRevealed
    }

    func rebuildPinRow() {
        pinBox.subviews.forEach { $0.removeFromSuperview() }
        let managed = pinGet(service) != nil
        if managed && pinState != .editing {
            let ok = NSTextField(labelWithString: "✓ 钥匙串已管理"); ok.textColor = .systemGreen
            ok.frame = NSRect(x: 0, y: 8, width: 140, height: 20); pinBox.addSubview(ok)
            let open = NSButton(title: "打开钥匙串", target: self, action: #selector(openKeychain)); open.bezelStyle = .rounded
            open.frame = NSRect(x: 140, y: 4, width: 110, height: 28); pinBox.addSubview(open)
            let edit = NSButton(title: "修改…", target: self, action: #selector(editPin)); edit.bezelStyle = .rounded
            edit.frame = NSRect(x: 256, y: 4, width: 70, height: 28); pinBox.addSubview(edit)
        } else {
            pinField = NSSecureTextField(); pinField.placeholderString = "输入 PIN"
            pinField.frame = NSRect(x: 0, y: 6, width: 200, height: 22); pinBox.addSubview(pinField)
            let save = NSButton(title: "保存到钥匙串", target: self, action: #selector(savePin)); save.bezelStyle = .rounded
            save.frame = NSRect(x: 206, y: 4, width: 120, height: 28); pinBox.addSubview(save)
            if managed {
                let c = NSButton(title: "取消", target: self, action: #selector(cancelEditPin)); c.bezelStyle = .rounded
                c.frame = NSRect(x: 330, y: 4, width: 60, height: 28); pinBox.addSubview(c)
            }
        }
    }
    @objc func openKeychain() { run("/usr/bin/open", ["-a", "Keychain Access"]) }
    @objc func editPin() { pinState = .editing; rebuildPinRow() }
    @objc func cancelEditPin() { pinState = .managed; rebuildPinRow() }
    @objc func savePin() {
        let v = pinField.stringValue
        guard !v.isEmpty else { return }
        pinSet(service, v); pinState = .managed; rebuildPinRow()
    }

    @objc func doSave() {
        var c = loadConfig()
        c["HOST"] = host.stringValue; c["USER"] = user.stringValue
        c["GROUP"] = group.stringValue; c["SERVERCERT"] = certValue
        writeConfig(c); onSaved?(); doClose()
    }
    @objc func doClose() { win.close() }
    func show() {
        load(); rebuildPinRow(); win.center(); win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum St { case disconnected, connecting, connected, errTimeout, errAuth, errCert, errDropped }

class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var statusLine: NSMenuItem!
    var connectItem: NSMenuItem!
    var disconnectItem: NSMenuItem!
    var autostartItem: NSMenuItem!
    var colorImg: NSImage!
    var grayImg: NSImage!
    var redImg: NSImage!
    var spinnerFrames: [NSImage] = []
    var spinStep = 0
    var spinTimer: Timer?
    var state: St = .disconnected
    var userDisconnecting = false
    var downStreak = 0
    var timer: Timer?
    var connectStart: Date?
    var service = "LiteOC"
    var configWin: ConfigWindow?

    func loadImg(_ name: String, template: Bool = false) -> NSImage {
        let p = Bundle.main.path(forResource: name, ofType: "png") ?? ""
        let i = NSImage(contentsOfFile: p) ?? NSImage(); i.isTemplate = template; i.size = NSSize(width: 18, height: 18)
        return i
    }
    func reloadConfig() { service = loadConfig()["KEYCHAIN_SERVICE"] ?? "LiteOC" }

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
        let title = NSMenuItem(title: APPNAME, action: nil, keyEquivalent: ""); title.isEnabled = false
        menu.addItem(title)
        statusLine = NSMenuItem(title: "○ 未连接", action: nil, keyEquivalent: ""); statusLine.isEnabled = true
        menu.addItem(statusLine); menu.addItem(.separator())
        connectItem = NSMenuItem(title: "连接", action: #selector(doConnect), keyEquivalent: ""); connectItem.target = self
        disconnectItem = NSMenuItem(title: "断开", action: #selector(doDisconnect), keyEquivalent: ""); disconnectItem.target = self
        menu.addItem(connectItem); menu.addItem(disconnectItem); menu.addItem(.separator())
        let setPin = NSMenuItem(title: "设置 PIN…", action: #selector(doSetPin), keyEquivalent: ""); setPin.target = self
        let editConf = NSMenuItem(title: "配置…", action: #selector(doEditConfig), keyEquivalent: ""); editConf.target = self
        menu.addItem(setPin); menu.addItem(editConf); menu.addItem(.separator())
        autostartItem = NSMenuItem(title: "开机自启动", action: #selector(toggleAutostart), keyEquivalent: ""); autostartItem.target = self
        autostartItem.state = autostartEnabled() ? .on : .off
        menu.addItem(autostartItem); menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        enter(.disconnected)
        reschedule()
    }

    func runStatus() -> String {
        run("/usr/bin/sudo", [VPNCTL, "status", ConfPath]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 单一计时器回调: 消费 vpnctl 三态, 叠加时间/意图维度派生四态机
    @objc func tick() {
        reloadConfig()
        let parts = runStatus().split(separator: " ")
        let st = String(parts.first ?? "")
        let ip = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
        switch state {
        case .disconnected:
            if userDisconnecting {                 // 主动断开中: 等 status 真正 down 再清标志, 期间不跟进 connecting
                if st == "down" { userDisconnecting = false }
            } else if st == "connected" { enter(.connected, ip: ip) }
            else if st == "connecting" { enter(.connecting) }   // 外部启动的连接, 跟进
        case .connecting:
            if st == "connected" { enter(.connected, ip: ip) }
            else if st == "down" {
                // openconnect 不在了: 主动断开 → disconnected; 启动后退 (>3s) → 连接失败; 刚启动短暂 down 容忍
                if userDisconnecting { userDisconnecting = false; enter(.disconnected) }
                else if let s = connectStart, Date().timeIntervalSince(s) > 3 { enter(.errTimeout) }
            }
            else if let s = connectStart, Date().timeIntervalSince(s) > 30 { enter(.errTimeout) }
        case .connected:
            if st == "connected" { statusLine.title = "● 已连接  " + ip; downStreak = 0 }
            else if st == "down" {                 // 防抖: 连续 2 次 down 才判掉线 (openconnect 内置重连瞬断不误触)
                downStreak += 1
                if downStreak >= 2 { enter(.errDropped) }
            } else { downStreak = 0 }              // connecting: openconnect 内置重连中, 维持 connected
        case .errTimeout, .errAuth, .errCert, .errDropped:
            break                                   // 保持红灯, 等用户连接/断开
        }
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

    func enter(_ s: St, ip: String = "") {
        state = s; downStreak = 0
        if s != .connecting { stopSpin() }
        switch s {
        case .disconnected:
            item.button?.image = grayImg
            let h = loadConfig()["HOST"] ?? ""
            statusLine.title = (h.isEmpty || h.hasPrefix("vpn.example")) ? "○ 未配置 — 点「配置…」" : "○ 未连接"
            connectItem.isEnabled = true; disconnectItem.isEnabled = false
        case .connecting:
            connectStart = Date(); spinStep = 0; startSpin()
            statusLine.title = "● 连接中…"; connectItem.isEnabled = false; disconnectItem.isEnabled = true
        case .connected:
            item.button?.image = colorImg; statusLine.title = "● 已连接  " + ip
            connectItem.isEnabled = false; disconnectItem.isEnabled = true
        case .errTimeout: showError("连接超时", "检查网络/网关可达性")
        case .errAuth: showError("PIN 有误", "检查 PIN")
        case .errCert: showError("证书获取失败", "「配置…」手动填 pin-sha256")
        case .errDropped: showError("连接已断开", "点「连接」重试")
        }
        reschedule()
    }
    func showError(_ t: String, _ d: String) {
        item.button?.image = redImg; statusLine.title = "● \(t) — \(d)"
        connectItem.isEnabled = true; disconnectItem.isEnabled = true
    }

    @objc func doConnect() {
        reloadConfig()
        if case .connecting = state { return }      // 已在连接, 忽略重复点击
        guard let pin = pinGet(service) else { alert("未设置 PIN", "请先在「配置…」里存 PIN。"); return }
        userDisconnecting = false
        enter(.connecting)
        DispatchQueue.global().async {
            let out = run("/usr/bin/sudo", [VPNCTL, "start", ConfPath], stdin: pin)
            let lines = out.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            if let dc = lines.first(where: { $0.hasPrefix("discovered-cert:") }) {
                setConfigValue("SERVERCERT", String(dc.dropFirst("discovered-cert:".count)))   // TOFU 回写
            }
            let r = lines.last(where: { ["started", "auth-failed", "no-pin", "already-running",
                                         "cert-discover-failed", "openconnect-not-found"].contains($0) }) ?? lines.last ?? ""
            DispatchQueue.main.async {
                if self.state != .connecting { return }   // 已离开 connecting (用户已断开等), 丢弃迟到的结果
                switch r {
                case "auth-failed": self.enter(.errAuth)
                case "cert-discover-failed": self.enter(.errCert)
                case "openconnect-not-found": self.enter(.disconnected); self.alert("缺少依赖", "重新运行 LiteOC 安装器(.pkg)以补齐内置 openconnect。")
                case "no-pin": self.enter(.disconnected)
                default: break   // started / already-running: 等 tick 检测 connected
                }
            }
        }
    }
    @objc func doDisconnect() {
        userDisconnecting = true
        enter(.disconnected)                        // UI 立即回灰盾, 不等 stop 返回
        DispatchQueue.global().async { _ = run("/usr/bin/sudo", [VPNCTL, "stop", ConfPath]) }
    }
    @objc func doSetPin() {
        let a = NSAlert(); a.messageText = "设置 \(APPNAME) PIN"; a.informativeText = "存入 macOS 钥匙串 (服务 \(service))。"
        a.addButton(withTitle: "保存"); a.addButton(withTitle: "取消")
        let f = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); f.placeholderString = "PIN 码"
        a.accessoryView = f; a.window.initialFirstResponder = f
        if a.runModal() == .alertFirstButtonReturn, !f.stringValue.isEmpty { pinSet(service, f.stringValue); tick() }
    }
    @objc func doEditConfig() {
        if configWin == nil { configWin = ConfigWindow(service: service) { self.reloadConfig(); self.tick() } }
        configWin?.service = service; configWin?.show()
    }
    func alert(_ t: String, _ m: String) { let a = NSAlert(); a.messageText = t; a.informativeText = m; a.addButton(withTitle: "好"); a.runModal() }

    func autostartEnabled() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    @objc func toggleAutostart() {
        guard #available(macOS 13.0, *) else { alert("不支持", "开机自启动需 macOS 13 及以上。"); return }
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
