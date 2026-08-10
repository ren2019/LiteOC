# LiteOC

[中文](README.md) | [English](README.en.md)

轻量 macOS 菜单栏 VPN 客户端,封装 [openconnect](https://www.infradead.org/openconnect/),面向 **AnyLink** 及兼容的 AnyConnect-SSL 网关。

[AnyLink](https://github.com/bjdgyc/anylink) 是国内常见的开源 SSL VPN;LiteOC 让你用菜单栏一键连/断,PIN 存 macOS 钥匙串,连接参数走可编辑配置。

## 特性
- 🌐 **菜单栏图标**:灰=离线、彩=连上、彩灰闪烁=连接中
- 🔐 **PIN 只存 macOS 钥匙串**——不落盘、不进配置/代码、不进 git
- 🪟 **图形配置窗口**:网关 / 用户 / 组;**证书指纹 mask + 👁**(留空首次自动获取);**PIN 行**(已存→「打开钥匙串」按钮,未存→输入)
- 🔒 **证书 TOFU**:开通邮件不带证书指纹?留空即可,首次连接自动探测 `pin-sha256` 并回写
- 🎯 **分到的内网 IP 自动探测**(从 openconnect 输出,不靠写死网段)
- 🛡️ **安全边界**:openconnect 路径写死、配置只解析不执行(防注入/防提权),详见 [ADR-0001](docs/adr/0001-openconnect-path-not-user-configurable.md)

## 下载与安装

**双击安装(无需终端)**:<https://github.com/ren2019/LiteOC/releases/latest> → 下载 `LiteOC-*.pkg` → 双击,按向导输入本机登录密码即可。安装器以 root 完成:装 vpnctl 到 `/usr/local/sbin`、把**内置的**自包含 openconnect 装到 `/usr/local/libexec/liteoc`(均 root 拥有)、写免密 sudoers(仅限 vpnctl 路径)、把 LiteOC.app 放到 /Applications。**无需 Homebrew。**

> 首次打开若被 Gatekeeper 挡(因 .pkg 为 ad-hoc 匿名签名、未公证):系统设置 → 隐私与安全性 → 「仍要打开」。全程图形界面,不开终端。

**或从源码构建(需终端 + Homebrew)**:
```bash
cd gui && ./build.sh && sudo sh setup-root.sh
```
> 仅 Apple Silicon / macOS 12+。

## 使用
1. 启动台打开 **LiteOC**(菜单栏出现地球图标)
2. 点 **配置…** → 填网关 / 用户 / 组(证书留空即可);**PIN 行**存一下 PIN
3. 点 **连接** → 🟢 已连接,显示内网 IP
4. 点 **断开** → 离线

CLI 兜底:`./connect.sh`(读同一份 `~/Library/Application Support/LiteOC/config`)。

## 配置文件
`~/Library/Application Support/LiteOC/config`(KEY=VALUE,带注释)。图形窗口改 = 改这个文件;也可直接编辑。**不含 PIN**。

## 文档
- [CONTEXT.md](CONTEXT.md) — 领域术语表
- [docs/config-spec.md](docs/config-spec.md) — 配置设计决策(D1–D9)+ 实现状态
- [docs/prd-config-extraction.md](docs/prd-config-extraction.md) — PRD
- [docs/adr/](docs/adr/) — 0001 路径安全边界、0002 证书 TOFU

## 与 openconnect-gui 的关系
[openconnect-gui](https://gitlab.com/openconnect/openconnect-gui) 是上游**通用、跨平台、功能完整**的重量级客户端(Windows/macOS/Linux,支持 OTP / 客户端证书 / PKCS#11 硬件令牌 / 多 profile)。LiteOC **不替代它**,而是用广度换单一场景的零摩擦:

| | openconnect-gui | LiteOC |
|---|---|---|
| 定位 | 通用全功能 GUI | AnyLink / 纯 PIN 的薄封装 |
| 平台 | Windows / macOS / Linux | 仅 macOS |
| 凭证 | Qt 自有存储 | **PIN 只进钥匙串**(不落盘) |
| 证书 | 自行提供指纹 | **TOFU**:留空自动获取并回写 |
| 提权 | macOS 每次启动弹管理员密码 | **NOPASSWD 只锁单一二进制** |
| 体量 | Qt,1000+ commits | ~300 行 Swift + 一个 shell |

**选 LiteOC**:macOS 用户、AnyLink/纯 PIN 网关、想要菜单栏一键免密连断、把 PIN 放进钥匙串。
**选 openconnect-gui**:需要 OTP / 客户端证书 / 硬件令牌 / 跨平台 / 多 profile。

## 适用范围
**支持**:AnyLink 及 openconnect 兼容的 SSL VPN(改 4 个网关字段 + PIN 即可指向不同部署;同公司可给同事共用,各自 PIN 钥匙串隔离)。
**不支持**:OpenVPN / WireGuard / IPsec / SangFor EasyConnect 专有协议 / SSO-SAML / 客户端证书 / 非 macOS。

## 排错
- 连接失败「用户名或密码错误」→ PIN 不对,在「配置…」的 PIN 行重新存。
- 「证书获取失败」→ 自动探测没成功,在「配置…」证书栏手动填 `pin-sha256:…`。
- 看实际状态:`sudo /usr/local/sbin/vpnctl status ~/Library/Application\ Support/LiteOC/config`
- openconnect 日志:`cat /tmp/liteoc-openconnect.log` 或 `log show --predicate 'process == "openconnect"' --last 5m`
