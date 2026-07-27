# LiteOC

轻量 macOS 菜单栏 VPN 客户端,封装 [openconnect](https://www.infradead.org/openconnect/),面向 **AnyLink** 及兼容的 AnyConnect-SSL 网关。一键连/断,PIN 存 macOS 钥匙串,连接参数走可编辑配置文件。

## 特性
- 菜单栏图标:灰=离线、彩=连上、闪烁=连接中
- PIN 只存 macOS 钥匙串(不落盘、不进配置/代码)
- 连接参数(网关 / 用户 / 组 / 证书)在 `~/Library/Application Support/LiteOC/config` 编辑
- 证书指纹锁定;分到的内网 IP 自动从 openconnect 输出探测
- 后台 openconnect,经免密 sudo 的 root 助手(`vpnctl`)建隧道;**openconnect 路径写死**(root 执行安全边界)

## 安装
```bash
brew install openconnect
cd gui
./build.sh              # 编译打包 LiteOC.app
sudo sh setup-root.sh   # 装 vpnctl(/usr/local/sbin)+ 免密 sudoers + App 到 /Applications
```
首次:菜单 **编辑配置…** 填网关信息 → **设置 PIN…** 存 PIN → **连接**。
CLI 兜底:`./connect.sh`(读同一份配置)。

## 文档
- [CONTEXT.md](CONTEXT.md) — 领域术语表
- [docs/config-spec.md](docs/config-spec.md) — 配置设计决策(D1–D9)
- [docs/prd-config-extraction.md](docs/prd-config-extraction.md) — PRD
- [docs/adr/](docs/adr/) — 架构决策(0001 路径安全边界、0002 证书 TOFU)

## 适用范围
AnyLink 及 openconnect 兼容的 SSL VPN。**不支持**:OpenVPN / WireGuard / IPsec / SangFor EasyConnect 专有协议 / SSO-SAML / 客户端证书 / 非 macOS。
