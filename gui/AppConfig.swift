import Foundation

enum AppConfig {
    static let keychainAccount = "pin"
    private static let writeOrder = ["HOST", "USER", "GROUP", "SERVERCERT", "KEYCHAIN_SERVICE"]

    static let defaultTemplate = #"""
# LiteOC 配置 — PIN 不在此文件 (在 macOS 钥匙串)
# 改完保存, 下次连接即生效

HOST="vpn.example.com:443"
USER="your-username"
GROUP="your-group"
SERVERCERT=""                    # 留空 = 首次连接自动获取 (TOFU)
KEYCHAIN_SERVICE="LiteOC"
"""#

    static func ensureExists(atPath path: String) throws {
        guard !FileManager.default.fileExists(atPath: path) else { return }
        try defaultTemplate.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func write(_ config: [String: String], toPath path: String) throws {
        var lines = ["# LiteOC 配置 — PIN 在 macOS 钥匙串", "# 保存即生效", ""]
        for key in writeOrder {
            let value = config[key] ?? (key == "KEYCHAIN_SERVICE" ? "LiteOC" : "")
            lines.append("\(key)=\"\(value)\"")
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func load(fromPath path: String) -> [String: String] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var config: [String: String] = [:]
        for rawLine in contents.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals].trimmingCharacters(in: .whitespaces))
            guard writeOrder.contains(key) else { continue }
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            config[key] = value
        }
        return config
    }
}
