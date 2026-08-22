# LiteOC v1.9

## 中文

LiteOC v1.9 深化了 App 侧的协议适配、状态归约与后台轮询结构，同时保持既有连接控制行为；本批唯一用户可感知变化是连接中的状态栏动画改为 macOS 系统原生样式。

### 用户可感知变化

- 连接过程中，状态栏现在使用 macOS 原生小型进度指示器，采用系统默认颜色并连续旋转。
- 除 spinner 样式外，本版不改变菜单文案、连接与断开动作或错误状态呈现。

### 验证

- 16 组 GUI、配置、Reducer、VpnctlClient、轮询、vpnctl 与 Release 契约脚本全部通过；其中覆盖 Reducer 72 格状态矩阵与 21 个边界、40 个事件用例，以及 30 个后台轮询动态断言与 16 个静态门禁。
- 真机完成连接、断开、错误 PIN、网络变化和掉线双次采样验收；连接期间连续 12 次高频菜单交互均保持响应，最慢 0.572 秒。
- 真机目视确认系统原生 spinner 的默认色与连续旋转；LiteOC.app 本地构建、严格签名检查及 App bundle 无旧 spinner 资源检查均通过。

## English

LiteOC v1.9 deepens the app-side protocol adapter, state reducer, and background polling architecture while preserving existing connection-control behavior. The only user-visible change in this batch is the native macOS status-item animation shown while connecting.

### User-visible changes

- While connecting, the status item now uses the native macOS small progress indicator with the system-default color and continuous animation.
- Apart from the spinner style, this release does not change menu wording, connect or disconnect actions, or error-state presentation.

### Verification

- Passed all 16 GUI, configuration, Reducer, VpnctlClient, polling, vpnctl, and Release contract scripts, including the 72-cell Reducer state matrix plus 21 boundaries, 40 event cases, and 30 dynamic background-polling assertions plus 16 static gates.
- Completed real-device connect, disconnect, invalid-PIN, network-change, and two-sample drop-debounce acceptance; all 12 rapid menu interactions remained responsive while connecting, with a maximum observed latency of 0.572 seconds.
- Visually confirmed the native spinner's default color and continuous animation; also completed the local LiteOC.app build, strict signature verification, and App-bundle check excluding the legacy spinner resource.

## Full Changelog

https://github.com/ren2019/LiteOC/compare/v1.8...v1.9
