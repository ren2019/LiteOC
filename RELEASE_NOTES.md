# LiteOC v1.6

## 中文

LiteOC v1.6 重新设计了菜单与设置体验，让当前状态、下一步操作和求助入口更直接，同时为发布产物增加了完整的一致性校验。

### 用户可感知变化

- 菜单顶部现在把状态与操作合并为一行：未连接时点击连接、连接中点击取消、已连接时点击断开，并在异常状态下给出对应的恢复动作。
- 新的紧凑设置窗口集中管理网关、用户、组、证书指纹和 PIN 钥匙串状态，修改 PIN 与证书信息更清晰。
- 菜单新增关于 LiteOC、访问 GitHub 和提交反馈入口；反馈页会预填 LiteOC 与 macOS 版本，并提醒避免提交敏感网络信息。
- 发布流程现在强制校验双语说明、main 分支来源，以及 App、安装包和下载文件的版本一致性。

### 验证

- 86 项菜单、vpnctl、Release Gate 与双端 Release Skill 契约检查通过，Swift 类型检查通过。
- LiteOC.app、自包含 OpenConnect 与 PKG 完整构建通过，main CI 与产物身份检查通过。

## English

LiteOC v1.6 redesigns the menu and Settings experience so the current state, next action, and help entry points are easier to understand, while adding end-to-end consistency checks for release artifacts.

### User-visible changes

- The top menu row now combines status and action: click to connect while offline, cancel while connecting, or disconnect when connected, with a matching recovery action for each error state.
- A compact Settings window now brings the gateway, user, group, certificate fingerprint, and Keychain PIN status together, making PIN and certificate updates clearer.
- New About LiteOC, Visit GitHub, and Submit Feedback entries provide version information and a prefilled issue form with a reminder not to share sensitive network details.
- The release pipeline now enforces bilingual notes, main-branch ancestry, and matching versions across the App, installer package, and downloadable asset.

### Verification

- Passed 86 menu, vpnctl, Release Gate, and dual-client Release Skill contract checks, plus Swift type checking.
- Completed full LiteOC.app, self-contained OpenConnect, and PKG builds; main CI and artifact identity checks passed.

## Full Changelog

https://github.com/ren2019/LiteOC/compare/v1.5...v1.6
