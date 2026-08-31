# LiteOC — 构建/安装(开发者)

LiteOC 菜单栏 App 的构建脚本与源码。用户向说明见[根 README](../README.md)。

## 文件
| 文件 | 作用 |
|---|---|
| `main.swift` | App 源码:原生菜单、设置窗口、About/反馈入口、4s 轮询、TOFU pin 回写 |
| `MenuPresentation.swift` | Tunnel 状态到菜单标题、提示、动作和色调的纯映射 |
| `MenuBarIcon.swift` | Tunnel 状态到菜单栏九宫格点阵图标(帧序列、帧间隔、着色)的纯映射 |
| `TunnelReducer.swift` | Tunnel 状态迁移、防抖、超时与网络变化规则的纯函数 |
| `TunnelPolling.swift` | 后台读取的单任务/generation 调度,防止重入与迟到结果回灌 |
| `vpnctl` | root 助手:`start`(连接前修复过期网关路由)/ `stop`(SIGINT + 等待退出 + 路由验证)/ `repair`(启动恢复)/ `network`(物理接口/IP/网关指纹)/ `status` |
| `build.sh` | 编译 + 生成 App 图标 + 写入版本 + 打包 `LiteOC.app` + 签名(无需 sudo) |
| `setup-root.sh` | 一次性装 root 部分:`vpnctl` → `/usr/local/sbin`、写免密 sudoers、App → `/Applications`、校验 openconnect(需 sudo) |
| `make_icon.swift` | 生成 1024 App 图标(绿色盾锁) |
| `make_icns.swift` | 当系统 `iconutil` 拒绝标准 iconset 时,用同一组 PNG 生成 ICNS |

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
- 单一 Timer 只在主线程提交轮询、归约与渲染;周期性 `vpnctl status/network` 使用独立 poll queue,连接/capture 的 network effect 使用独立 single-flight queue,旧 generation 的结果不会回灌状态。
- 菜单栏图标为运行时绘制的 3×3 圆点阵(18pt,灭点 22% 不透明度):connected 显示横 T,忙态播放点阵动画(追逐/坍缩/闪烁/行扫描),错误态为红色静态分组图案;图案与节奏由 `MenuBarIcon.swift` 的纯函数决定。
- 已确认的 A/B/C 交互原型保存在 [`../docs/prototype-liteoc-ui.html`](../docs/prototype-liteoc-ui.html),不参与 App 编译。

## 测试

```bash
sh test/app_config_test.sh
sh test/config_fixture_test.sh
sh test/menu_presentation_test.sh
sh test/menu_bar_icon_test.sh
sh test/tunnel_reducer_test.sh
sh test/tunnel_events_test.sh
sh test/main_thread_polling_test.sh
sh test/app_architecture_test.sh
sh test/app_bundle_resources_test.sh
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
