import Foundation

private var passed = 0

private func check(_ description: String, _ condition: @autoclosure () -> Bool) {
    guard condition() else {
        fputs("FAIL \(description)\n", stderr)
        exit(1)
    }
    passed += 1
    print("  ok   \(description)")
}

private let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("liteoc-app-config-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: work) }
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

print("== LiteOC App config contract ==")

let freshPath = work.appendingPathComponent("fresh-config").path
try AppConfig.ensureExists(atPath: freshPath)
let freshContents = try String(contentsOfFile: freshPath, encoding: .utf8)
check("默认模板不生成 KEYCHAIN_ACCOUNT", !freshContents.contains("KEYCHAIN_ACCOUNT"))
check("默认模板保留 KEYCHAIN_SERVICE", freshContents.contains("KEYCHAIN_SERVICE=\"LiteOC\""))

let savedPath = work.appendingPathComponent("saved-config").path
let savedConfig: [String: String] = [
    "KEYCHAIN_SERVICE": "CustomService",
    "SERVERCERT": "pin-sha256:abc+/==",
    "KEYCHAIN_ACCOUNT": "legacy-account",
    "GROUP": "employees",
    "HOST": "vpn.example.net:443",
    "USER": "alex"
]
try AppConfig.write(savedConfig, toPath: savedPath)
let savedContents = try String(contentsOfFile: savedPath, encoding: .utf8)
let expectedSavedContents = #"""
# LiteOC 配置 — PIN 在 macOS 钥匙串
# 保存即生效

HOST="vpn.example.net:443"
USER="alex"
GROUP="employees"
SERVERCERT="pin-sha256:abc+/=="
KEYCHAIN_SERVICE="CustomService"

"""#
check("配置写入只保留受支持键及固定顺序", savedContents == expectedSavedContents)

let legacyPath = work.appendingPathComponent("legacy-config").path
let legacyContents = #"""
HOST="vpn.legacy.example:443"
USER="ren"
GROUP="engineering"
SERVERCERT="pin-sha256:legacy+/=="
KEYCHAIN_SERVICE="LegacyService"
KEYCHAIN_ACCOUNT="old-account"
UNKNOWN_KEY="ignored"
"""#
try legacyContents.write(toFile: legacyPath, atomically: true, encoding: .utf8)
let loadedLegacy = AppConfig.load(fromPath: legacyPath)
let expectedLegacy = [
    "HOST": "vpn.legacy.example:443",
    "USER": "ren",
    "GROUP": "engineering",
    "SERVERCERT": "pin-sha256:legacy+/==",
    "KEYCHAIN_SERVICE": "LegacyService"
]
check("读取旧配置时忽略 KEYCHAIN_ACCOUNT 与其他未知键", loadedLegacy == expectedLegacy)
check("钥匙串 account 固定为 pin", AppConfig.keychainAccount == "pin")

print("\n\(passed) passed")
