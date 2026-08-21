# LiteOC v1.8

## 中文

LiteOC v1.8 修复了中文及其他非英文 macOS 环境下，VPN 实际已连接却被误判为连接超时的问题。

### 用户可感知变化

- OpenConnect 取得内网 IP 后，LiteOC 现在能稳定进入“已连接”，不会再因本地化日志无法识别而停留在“连接中”。
- 证书探测与正式连接使用稳定的控制面语言，不影响 App 的界面语言，并避免连接在 30 秒后被错误断开。

### 验证

- 98 项菜单、vpnctl、Release Gate 与双端 Release Skill 契约检查通过，新增非英文父环境下完整 `start → status` 回归覆盖。
- LiteOC.app 本地构建、严格签名检查与发布说明 Gate 通过。

## English

LiteOC v1.8 fixes a false connection timeout on Chinese and other non-English macOS environments after the VPN tunnel has already connected successfully.

### User-visible changes

- After OpenConnect receives an internal IP, LiteOC now reliably enters Connected instead of remaining stuck in Connecting because of localized log output.
- Certificate discovery and tunnel startup now use a stable control-plane language without changing the app UI language, preventing the connection from being incorrectly stopped after 30 seconds.

### Verification

- Passed 98 menu, vpnctl, Release Gate, and dual-client Release Skill contract checks, including a new full `start → status` regression under a non-English parent environment.
- Completed the local LiteOC.app build, strict signature verification, and release-note gate.

## Full Changelog

https://github.com/ren2019/LiteOC/compare/v1.7...v1.8
