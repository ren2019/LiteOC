# LiteOC — 构建/安装(开发者)

LiteOC 菜单栏 App 的构建脚本与源码。用户向说明见[根 README](../README.md)。

## 文件
| 文件 | 作用 |
|---|---|
| `main.swift` | App 源码:菜单栏图标、连接/断开/配置窗口/PIN、4s 轮询、TOFU pin 回写 |
| `vpnctl` | root 助手:`start`(连接前修复过期网关路由)/ `stop`(SIGINT + 等待退出 + 路由验证)/ `repair`(启动恢复)/ `network`(物理接口/IP/网关指纹)/ `status` |
| `build.sh` | 编译 + 生成图标(AppIcon + 菜单栏彩/灰)+ 打包 `LiteOC.app` + 签名(无需 sudo) |
| `setup-root.sh` | 一次性装 root 部分:`vpnctl` → `/usr/local/sbin`、写免密 sudoers、App → `/Applications`、校验 openconnect(需 sudo) |
| `make_icon.swift` | 生成 1024 App 图标(蓝底地球) |
| `make_menubar.swift` | 生成菜单栏彩/灰小图标 |

## 构建
```bash
./build.sh                 # 产物: build/LiteOC.app
```
依赖:Xcode Command Line Tools(`swiftc`)、`sips`、`iconutil`(macOS 自带)。

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
