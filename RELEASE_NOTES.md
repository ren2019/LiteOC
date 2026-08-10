# LiteOC v1.5

## 中文

LiteOC v1.5 修复了网络切换或 OpenConnect 异常退出后遗留 VPN 网关路由的问题，并让连接生命周期的退化状态可见、可恢复。

### 用户可感知变化

- 启动、重新连接和应用恢复时，会精确识别并修复当前 VPN 网关的过期主机路由，不影响其他静态路由。
- 断开连接会等待 OpenConnect 退出并验证路由清理；超时或清理失败会显示明确错误，不再提前报告“未连接”。
- 网络变化会停止旧连接并完成清理，同时更新了应用与菜单栏图标，补充了网络代理排错文档。

### 验证

- 46 项 vpnctl 状态与路由契约断言通过，Swift 应用编译通过。
- 已安装 v1.5 包并核验 App、安装回执、helper 与自包含 OpenConnect；过期路由修复返回 `route-clean`。
- VPN 网关及共享同一公网 IP 的三个入口现场访问均恢复为 HTTP 200。

## English

LiteOC v1.5 fixes stale VPN gateway routes left after network changes or abnormal OpenConnect exits, while making degraded connection states visible and recoverable.

### User-visible changes

- Startup, reconnection, and app recovery now identify and repair only the stale host route for the configured VPN gateway, leaving unrelated static routes untouched.
- Disconnect now waits for OpenConnect to exit and verifies route cleanup; timeout or cleanup failures surface a clear error instead of reporting a healthy disconnected state early.
- Network changes stop and clean up the old connection, while refreshed app/menu-bar icons and new proxy troubleshooting guidance improve day-to-day operation.

### Verification

- Passed 46 vpnctl status and route contract assertions, plus Swift application compilation.
- Installed the v1.5 package and verified the App, installation receipt, helper, bundled OpenConnect, and a `route-clean` recovery result.
- Confirmed HTTP 200 access to the VPN gateway and all three affected endpoints sharing the same public IP.

## Full Changelog

https://github.com/ren2019/LiteOC/compare/v1.4...v1.5
