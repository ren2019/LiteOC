# LiteOC v1.10

## 中文

LiteOC v1.10 让网络变化后的隧道恢复从"手动重连"变为"App 自动编排"：瞬断不再误杀隧道，真实换网转入黄灯自动重连并在配额内升级为明确错误，全程可取消。

### 用户可感知变化

- 网络瞬断（如 Wi-Fi 短暂丢包几秒再恢复）不再拆掉已连接的隧道，绿灯保持不变。
- 换网（切换 Wi-Fi/热点、携机移动到新网络）时状态栏转为黄灯闪烁，显示"正在重新连接…/网络已变化"，连上后自动回到绿灯并显示新 IP，无需手动操作。
- 黄灯期间可随时点"取消"回到灰灯断开态；持续无网时黄灯持续闪烁，不误报错误。
- 自动重连设 3 次配额：配额内每次尝试失败会继续重试，3 次耗尽才升红灯显示"重连失败/重试"；若重连中发现 PIN 有误则立即升红灯提示"PIN 有误"，不再空耗配额。
- 连接进行途中（30 秒窗口内）发生网络变化，同样转入黄灯自动重连，不会中途落红。

### 验证

- 16 组 GUI、配置、Reducer、VpnctlClient、轮询、vpnctl 与 Release 契约脚本全部通过；其中 Reducer 84 格状态矩阵 + 43 个边界断言、60 个事件用例、30 个后台轮询动态断言与 16 个静态门禁。
- 真机完成三票验证门：关 Wi-Fi 约 5 秒再开绿灯不掉；携机换网黄灯闪烁后自动回绿显示新 IP，途中持续断网不升红；黄灯时点"取消"回到灰灯；connecting 途中换网转黄灯自动重连不落红。
- App 重装自本版构建（/Applications 与 /usr/local/sbin/vpnctl 同源同时间戳），确认无部署漂移后验收。

## English

LiteOC v1.10 turns post-network-change tunnel recovery from manual reconnect into app-orchestrated recovery: transient drops no longer tear down the tunnel, real network changes enter an amber auto-reconnect flow with a bounded quota that escalates to an explicit error, and the whole flow is cancellable.

### User-visible changes

- Transient network blips (a few seconds of Wi-Fi loss that recovers) no longer tear down a connected tunnel; the green light stays on.
- On a real network change (switching Wi-Fi/hotspot, moving to a new network) the status item switches to a flashing amber light with "Reconnecting… / Network changed", then returns to green with the new IP once connected — no manual action needed.
- The amber state is cancellable at any time via "Cancel" back to the disconnected gray state; sustained loss of network keeps flashing amber instead of reporting an error.
- Auto-reconnect runs with a 3-attempt quota: within quota each failed attempt retries, only exhaustion after 3 escalates to red with "Reconnect failed / Retry"; a wrong PIN discovered mid-reconnect escalates immediately to red with "Invalid PIN" instead of burning the quota.
- A network change during the connecting window (within 30 seconds) likewise transitions to amber auto-reconnect rather than dropping to red mid-connect.

### Verification

- Passed all 16 GUI, configuration, Reducer, VpnctlClient, polling, vpnctl, and Release contract scripts, including the 84-cell Reducer state matrix plus 43 boundary assertions, 60 event cases, and 30 dynamic background-polling assertions plus 16 static gates.
- Completed the three-issue real-device acceptance on site: turning Wi-Fi off for ~5 seconds and back on kept the green light; walking to another network produced the flashing amber light, automatic return to green with the new IP, and no false red during the offline stretch; "Cancel" during amber returned to gray; a network change inside the connecting window transitioned to amber auto-reconnect without dropping to red.
- The app was reinstalled from this build (/Applications and /usr/local/sbin/vpnctl from the same source and timestamp), verifying no deployment drift before acceptance.

## Full Changelog

https://github.com/ren2019/LiteOC/compare/v1.9...v1.10
