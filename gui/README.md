# LiteOC — 构建/安装(开发者)

LiteOC 菜单栏 App 的构建脚本与源码。用户向说明见[根 README](../README.md)。

## 文件
| 文件 | 作用 |
|---|---|
| `main.swift` | App 源码:原生菜单、设置窗口、About/反馈入口、4s 轮询、TOFU pin 回写 |
| `MenuPresentation.swift` | Tunnel 状态到菜单标题、提示、动作和色调的纯映射 |
| `vpnctl` | root 助手:`start`(连接前修复过期网关路由)/ `stop`(SIGINT + 等待退出 + 路由验证)/ `repair`(启动恢复)/ `network`(物理接口/IP/网关指纹)/ `status` |
| `build.sh` | 编译 + 生成图标(AppIcon + 菜单栏彩/灰)+ 写入版本 + 打包 `LiteOC.app` + 签名(无需 sudo) |
| `setup-root.sh` | 一次性装 root 部分:`vpnctl` → `/usr/local/sbin`、写免密 sudoers、App → `/Applications`、校验 openconnect(需 sudo) |
| `make_icon.swift` | 生成 1024 App 图标(绿色盾锁) |
| `make_icns.swift` | 当系统 `iconutil` 拒绝标准 iconset 时,用同一组 PNG 生成 ICNS |
| `make_menubar.swift` | 生成菜单栏彩/灰小图标 |

## 构建
```bash
./build.sh                 # 产物: build/LiteOC.app
```
依赖:Xcode Command Line Tools(`swiftc`)、`sips`、`iconutil`(macOS 自带)。

`LITEOC_VERSION=v1.6 ./build.sh` 可显式指定版本;未指定时读取最新 Git tag。构建会同时写入 `CFBundleShortVersionString` 与 `CFBundleVersion`。

## GUI 行为

- 菜单顶部使用 272×46pt 紧凑状态行:IP 显示在第二行,连接、取消、断开、重试或设置固定在右侧操作列;清理中的不可操作状态会禁用点击。
- **设置…** 集中管理连接参数、证书指纹和 PIN。保存更改只写非机密配置;PIN 必须单独点 **存入钥匙串**。
- 缺少 PIN 时,连接操作会直接打开设置并聚焦 PIN,不再弹出独立 PIN 窗口。
- **关于 LiteOC** 使用系统 About Panel;**访问 GitHub** 与 **提交反馈…** 打开项目页和预填 Issue。
- 已确认的 A/B/C 交互原型保存在 [`../docs/prototype-liteoc-ui.html`](../docs/prototype-liteoc-ui.html),不参与 App 编译。

## 测试

```bash
sh test/app_config_test.sh
sh test/config_fixture_test.sh
sh test/menu_presentation_test.sh
sh test/vpnctl_status_test.sh
sh test/vpnctl_route_test.sh
```

## 安装(把 root 部分装到系统)
```bash
sudo sh setup-root.sh
```
`setup-root.sh` 缺 openconnect 时会自动以你的身份 `brew install`(无需手动)。

## 改代码后重装
```bash
./build.sh && sudo sh setup-root.sh
```

## 排错
- App 没起来 → `open 'build/LiteOC.app'` 直接跑看崩溃信息。
- 连接相关 → `sudo /usr/local/sbin/vpnctl status <配置路径>`、`cat /tmp/liteoc-openconnect.log`。
