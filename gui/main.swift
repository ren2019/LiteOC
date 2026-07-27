import Cocoa

// ---- 硬编码 (不进用户配置) ----
let APPNAME   = "LiteOC"
let VPNCTL    = "/usr/local/sbin/vpnctl"
let ConfDir   = NSHomeDirectory() + "/Library/Application Support/LiteOC"
let ConfPath  = ConfDir + "/config"
// 钥匙串服务名迁移链: 当前 LiteOC ← LiteOC ← LiteOC
let SVC_CHAIN = ["LiteOC", "LiteOC", "LiteOC"]
let ACCOUNT   = "pin"

// 默认配置模板 (占位符, 首次启动写入; 真实值由用户填写, 不进代码/仓库)
let defaultConf = #"""
# LiteOC 配置 — PIN 不在此文件 (在 macOS 钥匙串)
# 改完保存, 下次连接即生效

# ---- VPN 网关 ----
HOST="vpn.example.com:443"
USER="your-username"
GROUP="your-group"
SERVERCERT="pin-sha256:..."        # 证书指纹; 留空暂不支持 (TOFU 待实现)

# ---- 钥匙串 (PIN 存这里) ----
KEYCHAIN_SERVICE="LiteOC"
KEYCHAIN_ACCOUNT="pin"

# ---- 状态探测 (可选; 留空走默认宽匹配) ----
VPN_IP_PATTERN=""
"""#

// ---- 跑命令 ----
@discardableResult
func run(_ exe: String, _ args: [String], stdin: String? = nil) -> String {
    let p = Process()
    p.launchPath = exe; p.arguments = args
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

// ---- 配置: 读 KEY=VALUE ----
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

func ensureConfig() {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: ConfDir, withIntermediateDirectories: true)
    if !fm.fileExists(atPath: ConfPath) {
        try? defaultConf.write(toFile: ConfPath, atomically: true, encoding: .utf8)
    }
}

// ---- 钥匙串 (经 /usr/bin/security); 迁移到链首服务名 ----
func rawPin(_ service: String) -> String? {
    let s = run("/usr/bin/security", ["find-generic-password", "-s", service, "-a", ACCOUNT, "-w"])
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}
func pinGet(_ target: String) -> String? {
    if let p = rawPin(target) { return p }
    for svc in SVC_CHAIN where svc != target {
        if let p = rawPin(svc) {   // 迁移旧服务名 → target
            run("/usr/bin/security", ["add-generic-password", "-s", target, "-a", ACCOUNT,
                                      "-w", p, "-T", "/usr/bin/security", "-U"])
            run("/usr/bin/security", ["delete-generic-password", "-s", svc, "-a", ACCOUNT])
            return p
        }
    }
    return nil
}
func pinSet(_ service: String, _ v: String) {
    run("/usr/bin/security", ["add-generic-password", "-s", service, "-a", ACCOUNT,
                              "-w", v, "-T", "/usr/bin/security", "-U"])
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
    var ipPattern = ""

    func loadImg(_ name: String) -> NSImage {
        let p = Bundle.main.path(forResource: name, ofType: "png") ?? ""
        let i = NSImage(contentsOfFile: p) ?? NSImage()
        i.isTemplate = false; i.size = NSSize(width: 18, height: 18)
        return i
    }

    func reloadConfig() {
        let c = loadConfig()
        service   = c["KEYCHAIN_SERVICE"] ?? "LiteOC"
        ipPattern = c["VPN_IP_PATTERN"] ?? ""
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        ensureConfig()
        reloadConfig()
        colorImg = loadImg("menubar_color"); grayImg = loadImg("menubar_gray")

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly
        item.button?.image = grayImg

        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: APPNAME, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        statusLine = NSMenuItem(title: "○ 未连接", action: nil, keyEquivalent: "")  // 不置灰: enabled + 无 action
        statusLine.isEnabled = true
        menu.addItem(statusLine)
        menu.addItem(.separator())

        connectItem = NSMenuItem(title: "连接", action: #selector(doConnect), keyEquivalent: ""); connectItem.target = self
        disconnectItem = NSMenuItem(title: "断开", action: #selector(doDisconnect), keyEquivalent: ""); disconnectItem.target = self
        menu.addItem(connectItem); menu.addItem(disconnectItem)
        menu.addItem(.separator())

        let setPin = NSMenuItem(title: "设置 PIN…", action: #selector(doSetPin), keyEquivalent: ""); setPin.target = self
        let editConf = NSMenuItem(title: "编辑配置…", action: #selector(doEditConfig), keyEquivalent: ""); editConf.target = self
        menu.addItem(setPin); menu.addItem(editConf)
        menu.addItem(.separator())
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
            statusLine.title = "○ 未连接"
            connectItem.isEnabled = true; disconnectItem.isEnabled = false
        }
    }

    func setBusy(_ on: Bool) {
        busy = on
        if on {
            connectItem.isEnabled = false; disconnectItem.isEnabled = false
            statusLine.title = "… 连接中"
            pulseOn = false; connectStart = Date()
            timer?.invalidate()
            let t = Timer(timeInterval: 0.35, target: self, selector: #selector(busyTick), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common); timer = t
        } else {
            timer?.invalidate(); timer = nil; refresh()
        }
    }

    @objc func busyTick() {
        pulseOn.toggle()
        item.button?.image = pulseOn ? colorImg : grayImg
        if let s = connectStart, Date().timeIntervalSince(s) > 30 {
            setBusy(false); alert("连接超时", "30 秒仍未连上, 请检查网络/配置。"); return
        }
        let r = run("/usr/bin/sudo", [VPNCTL, "status", ConfPath]).trimmingCharacters(in: .whitespacesAndNewlines)
        if r.hasPrefix("up") { setBusy(false) }
    }

    @objc func doConnect() {
        reloadConfig()
        guard let pin = pinGet(service) else { alert("未设置 PIN", "请先点 “设置 PIN…” 存入钥匙串。"); return }
        setBusy(true)
        DispatchQueue.global().async {
            let r = run("/usr/bin/sudo", [VPNCTL, "start", ConfPath], stdin: pin).trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                if r == "auth-failed" { self.setBusy(false); self.alert("连接失败", "用户名或密码错误 —— 检查 PIN。") }
                else if r.hasPrefix("config-error") { self.setBusy(false); self.alert("配置错误", r + "\n点 “编辑配置…” 修正。") }
                else if r == "openconnect-not-found" { self.setBusy(false); self.alert("缺少依赖", "先 brew install openconnect") }
                else if r == "no-pin" { self.setBusy(false); self.alert("连接失败", "未收到 PIN。") }
                // started/already-running: 不立即清 busy, 等 busyTick 检测到 up
            }
        }
    }

    @objc func doDisconnect() {
        DispatchQueue.global().async {
            _ = run("/usr/bin/sudo", [VPNCTL, "stop", ConfPath])
            DispatchQueue.main.async { self.refresh() }
        }
    }

    @objc func doSetPin() {
        let a = NSAlert()
        a.messageText = "设置 \(APPNAME) PIN"; a.informativeText = "存入 macOS 钥匙串 (服务 \(service))。即开通邮件里的 PIN 码。"
        a.addButton(withTitle: "保存"); a.addButton(withTitle: "取消")
        let f = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); f.placeholderString = "PIN 码"
        a.accessoryView = f; a.window.initialFirstResponder = f
        if a.runModal() == .alertFirstButtonReturn, !f.stringValue.isEmpty { pinSet(service, f.stringValue); refresh() }
    }

    @objc func doEditConfig() { run("/usr/bin/open", ["-e", ConfPath]) }

    func alert(_ t: String, _ m: String) {
        let a = NSAlert(); a.messageText = t; a.informativeText = m; a.addButton(withTitle: "好"); a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
