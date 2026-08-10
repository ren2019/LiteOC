# LiteOC v1.7

## 中文

LiteOC v1.7 收紧了菜单宽度与状态信息层级，让连接操作更稳定、已分配的 VPN IP 更容易读取。

### 用户可感知变化

- 菜单状态区缩小为更紧凑的 272×46pt，连接、取消、断开、重试和设置始终固定在同一右侧位置。
- 已连接时，VPN IP 改为显示在状态标题下方；未连接和连接中不再重复显示“点击…”提示。

### 验证

- 89 项菜单、vpnctl、Release Gate 与双端 Release Skill 契约检查通过，Swift 类型检查通过。
- LiteOC.app 完整构建与签名检查通过，main CI 和产物身份检查通过。

## English

LiteOC v1.7 tightens the menu width and status hierarchy so connection actions stay stable and the assigned VPN IP is easier to scan.

### User-visible changes

- The status area is now a more compact 272×46pt, with Connect, Cancel, Disconnect, Retry, and Settings anchored to one consistent trailing position.
- Once connected, the VPN IP appears below the status title; disconnected and connecting states no longer repeat “Click…” instructions.

### Verification

- Passed 89 menu, vpnctl, Release Gate, and dual-client Release Skill contract checks, plus Swift type checking.
- Completed the LiteOC.app build and signature verification; main CI and artifact identity checks passed.

## Full Changelog

https://github.com/ren2019/LiteOC/compare/v1.6...v1.7
