# LiteOC v1.12

## 中文

LiteOC v1.12 对标 Tailscale 重设计了菜单栏菜单:首行去掉与图标重复的状态灯,改为"有事才着色";新增连接信息行一键复制 IP;修复与诊断入口常驻菜单;未配置时菜单栏图标变为红色 C 形,引导完成初始设置。

### 用户可感知变化

- 菜单首行不再带状态圆点:未连接/已连接是普通菜单行,连接中与出错时才出现橙/红色块;尚未完成初始设置时首行以红色描边引导。
- 已连接时菜单出现连接信息行:显示隧道 IP 与当前网关,点击即复制 IP,下次打开菜单时该行短暂显示"已复制到剪贴板"(不弹系统通知)。
- 菜单新增常驻的"立即修复"与"复制诊断信息":前者仅在隧道不活跃时可用(避免打断活连接),后者一键收集 Tunnel 状态、Network Fingerprint 基线与现状、最近错误,绝不含 PIN。
- 未配置时菜单栏点阵图标从全灭变为红色 C 形,与"已配置未连接"一眼区分。
- 菜单首行与信息行的文字缩进对齐系统菜单项;退出项不再出现新版 macOS 自动附加的图标。

### 验证

- 全部 17 个契约测试脚本通过;菜单呈现与点阵图标两条纯函数契约测试覆盖 15 态文案、色调、信息行出现条件与图标帧序列(37 + 58 条断言)。
- 三轮本机验收:四段菜单结构、复制 IP 与"已复制"反馈、诊断信息版本号(version.sh 未显式指定时回退读取最新 Git tag)、已连接时"立即修复"置灰、文字缩进对齐均逐项目验通过。
- App 自本版构建打包通过(build.sh 全链路:图标生成、编译、签名)。

## English

LiteOC v1.12 redesigns the menu bar menu, benchmarked against Tailscale: the primary row drops its redundant status dot in favor of "color only when attention is needed"; a new connection info row copies your tunnel IP in one click; repair and diagnostics entries are always visible; and the menu bar icon turns into a red C shape when the profile is not yet configured.

### User-visible changes

- The primary row no longer carries a status dot: disconnected/connected are plain menu rows, while connecting and error states show soft orange/red blocks; before initial setup the row is outlined in red as a guide.
- When connected, a connection info row shows the tunnel IP and current gateway; clicking it copies the IP, and the row briefly reads "Copied to clipboard" the next time the menu opens (no system notification).
- New always-visible menu items: "Repair Now" (enabled only while the tunnel is inactive, so it can't disrupt a live connection) and "Copy Diagnostics" (tunnel state, network fingerprint baseline/current, last error — never the PIN).
- The menu bar dot-matrix icon changes from an all-dim grid to a red C shape when unconfigured, clearly distinct from "configured but disconnected".
- Text insets of the primary and info rows now align with standard menu items; the Quit item no longer shows the icon recent macOS versions attach automatically.

### Verification

- All 17 contract test scripts pass; the two pure-function contract suites (menu presentation, menu bar icon) cover copy, tone, info-row visibility, and icon frame sequences across 15 states (37 + 58 assertions).
- Three rounds of on-device acceptance: four-section menu structure, copy-IP feedback, diagnostics version (version.sh falls back to the latest git tag), "Repair Now" disabled while connected, and text alignment were each visually verified.
- The app builds and packages cleanly from this version (full build.sh pipeline: icon generation, compile, signing).

## Full Changelog

https://github.com/ren2019/LiteOC/compare/v1.11...v1.12
