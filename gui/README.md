# LiteOC 菜单栏 App

轻量 macOS 菜单栏 GUI,封装 openconnect,一键连/断企业 VPN。
- PIN 存在 **macOS 钥匙串**(不明文落盘)
- 经 `vpnctl`(root 助手)+ 免密 sudo 后台起 openconnect
- 仅菜单栏图标,无 dock 图标(LSUIElement)

## 文件
- `main.swift` — App 源码(状态图标、连接/断开/设置PIN、4s 轮询状态)
- `vpnctl` — root 助手: `start`(读 stdin 的 PIN → 后台 openconnect)/ `stop`(SIGINT 优雅断开)/ `status`
- `build.sh` — 编译 + 打包 .app + 签名(无需 sudo)
- `setup-root.sh` — 一次性安装 root 部分(需 sudo)

## 安装(一次)
```bash
cd ~/projects/envs/use-ind-vpn/gui
./build.sh                 # 编译打包
sudo sh setup-root.sh      # 装 vpnctl + 免密 sudoers + App 到 /Applications
```
`setup-root.sh` 做的安全相关事:
- vpnctl 装到 `/usr/local/sbin`(root:wheel,用户不可写 → 防提权)
- `/etc/sudoers.d/vpnctl`:`<user> ALL=(root) NOPASSWD: /usr/local/sbin/vpnctl`(仅此路径免密)

## 使用
1. 启动台打开“LiteOC”(或 `open '/Applications/LiteOC.app'`)
2. 菜单栏图标 🔒 → 点 **设置 PIN…** 存 PIN(首次钥匙串可能弹“允许”,点 Always Allow)
3. 点 **连接** → 🟢 已连接,显示内网 IP
4. 点 **断开** → 🔒

## 重新编译(改了 main.swift 后)
```bash
./build.sh && sudo cp -R 'build/LiteOC.app' /Applications/
```

## 排错
- 连接失败“用户名或密码错误” → PIN 不对,重新“设置 PIN…”
- `sudo vpnctl status` 看实际状态;openconnect 日志:`log show --predicate 'process == "openconnect"' --last 5m`
