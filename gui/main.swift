import Cocoa

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
VPN_IP_PATTERN=""
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
let CONF_ORDER = ["HOST", "USER", "GROUP", "SERVERCERT", "KEYCHAIN_SERVICE", "KEYCHAIN_ACCOUNT", "VPN_IP_PATTERN"]
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

class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var statusLine: NSMenuItem!
    var connectItem: NSMenuItem!
    var disconnectItem: NSMenuItem!
    var colorImg: NSImage!
    var grayImg: NSImage!
    var busy = false
    var pulseOn = false
    var timer: Timer?
    var connectStart: Date?
    var service = "LiteOC"
    var configWin: ConfigWindow?

    func loadImg(_ name: String) -> NSImage {
        let p = Bundle.main.path(forResource: name, ofType: "png") ?? ""
        let i = NSImage(contentsOfFile: p) ?? NSImage(); i.isTemplate = false; i.size = NSSize(width: 18, height: 18)
        return i
    }
    func reloadConfig() { service = loadConfig()["KEYCHAIN_SERVICE"] ?? "LiteOC" }

    func applicationDidFinishLaunching(_ n: Notification) {
        ensureConfig(); reloadConfig()
        colorImg = loadImg("menubar_color"); grayImg = loadImg("menubar_gray")
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
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        refresh()
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
    }

    @objc func refresh() {
        reloadConfig()
        guard !busy else { return }
        let r = run("/usr/bin/sudo", [VPNCTL, "status", ConfPath]).trimmingCharacters(in: .whitespacesAndNewlines)
        let up = r.hasPrefix("up")
        item.button?.image = up ? colorImg : grayImg
        if up {
            statusLine.title = "● 已连接  " + (r.split(separator: " ").dropFirst().joined(separator: " "))
            connectItem.isEnabled = false; disconnectItem.isEnabled = true
        } else {
            let h = loadConfig()["HOST"] ?? ""
            statusLine.title = (h.isEmpty || h.hasPrefix("vpn.example")) ? "○ 未配置 — 点「配置…」" : "○ 未连接"
            connectItem.isEnabled = true; disconnectItem.isEnabled = false
        }
    }

    func setBusy(_ on: Bool) {
        busy = on
        if on {
            connectItem.isEnabled = false; disconnectItem.isEnabled = false; statusLine.title = "… 连接中"
            pulseOn = false; connectStart = Date(); timer?.invalidate()
            let t = Timer(timeInterval: 0.35, target: self, selector: #selector(busyTick), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common); timer = t
        } else { timer?.invalidate(); timer = nil; refresh() }
    }
    @objc func busyTick() {
        pulseOn.toggle(); item.button?.image = pulseOn ? colorImg : grayImg
        if let s = connectStart, Date().timeIntervalSince(s) > 30 { setBusy(false); alert("连接超时", "30 秒仍未连上, 请检查网络/配置。"); return }
        if run("/usr/bin/sudo", [VPNCTL, "status", ConfPath]).hasPrefix("up") { setBusy(false) }
    }

    @objc func doConnect() {
        reloadConfig()
        guard let pin = pinGet(service) else { alert("未设置 PIN", "请先在「配置…」里存 PIN。"); return }
        setBusy(true)
        DispatchQueue.global().async {
            let out = run("/usr/bin/sudo", [VPNCTL, "start", ConfPath], stdin: pin)
            let lines = out.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            if let dc = lines.first(where: { $0.hasPrefix("discovered-cert:") }) {
                setConfigValue("SERVERCERT", String(dc.dropFirst("discovered-cert:".count)))   // TOFU 回写
            }
            let r = lines.last(where: { ["started", "auth-failed", "no-pin", "already-running",
                                         "cert-discover-failed", "openconnect-not-found"].contains($0) }) ?? lines.last ?? ""
            DispatchQueue.main.async {
                switch r {
                case "auth-failed": self.setBusy(false); self.alert("连接失败", "用户名或密码错误 —— 检查 PIN。")
                case "cert-discover-failed": self.setBusy(false); self.alert("证书获取失败", "无法自动获取网关证书, 请在「配置…」手动填 pin-sha256。")
                case "openconnect-not-found": self.setBusy(false); self.alert("缺少依赖", "brew install openconnect")
                case "no-pin": self.setBusy(false); self.alert("连接失败", "未收到 PIN。")
                default: break   // started / already-running: 等 busyTick 检测 up
                }
            }
        }
    }
    @objc func doDisconnect() {
        DispatchQueue.global().async { _ = run("/usr/bin/sudo", [VPNCTL, "stop", ConfPath]); DispatchQueue.main.async { self.refresh() } }
    }
    @objc func doSetPin() {
        let a = NSAlert(); a.messageText = "设置 \(APPNAME) PIN"; a.informativeText = "存入 macOS 钥匙串 (服务 \(service))。"
        a.addButton(withTitle: "保存"); a.addButton(withTitle: "取消")
        let f = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); f.placeholderString = "PIN 码"
        a.accessoryView = f; a.window.initialFirstResponder = f
        if a.runModal() == .alertFirstButtonReturn, !f.stringValue.isEmpty { pinSet(service, f.stringValue); refresh() }
    }
    @objc func doEditConfig() {
        if configWin == nil { configWin = ConfigWindow(service: service) { self.reloadConfig(); self.refresh() } }
        configWin?.service = service; configWin?.show()
    }
    func alert(_ t: String, _ m: String) { let a = NSAlert(); a.messageText = t; a.informativeText = m; a.addButton(withTitle: "好"); a.runModal() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
