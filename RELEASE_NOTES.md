# LiteOC v1.11

## 中文

LiteOC v1.11 把状态栏与 Dock 图标全面换成九宫格点阵语言：3×3 圆点用虚实两种点表达全部隧道状态，品牌图案是横过来的 T，错误状态按类型分组显示不同红色图案，繁忙过程有对应点阵动画。

### 用户可感知变化

- 状态栏图标改为 3×3 点阵：已连接显示横 T 图案，未连接为全灭点阵，连接中为外圈顺时针追逐动画，断开中为 T 逐点坍缩动画。
- 自动重连时整个 T 图案闪烁，路由修复中为逐行扫描动画，一眼区分于其他状态。
- 错误状态显示红色分组图案：超时为沙漏、认证/证书为锁、连接掉线为断裂双竖、网络变化/重连失败为空心环、路由/断开清理失败为 X。
- Dock 图标换新：深色底板上的白色 C 形点阵（liteOC 的 C)，与状态栏点阵同一视觉语言。

### 验证

- 17 个契约测试脚本全部通过；其中新增菜单栏图标纯函数测试 59 条断言，逐状态锁定帧序列、帧间隔与着色，架构测试确认旧 PNG/spinner 路径无残留。
- 菜单栏点阵与 Dock 图标均经放大渲染目验：图案正确、灭点 22% 透明度可见、点阵在画布居中。
- App 自本版构建打包通过（build.sh 全链路：图标生成、编译、签名）。

## English

LiteOC v1.11 replaces both the status item and the Dock icon with a nine-grid dot-matrix language: a 3×3 grid of dots expresses every tunnel state through lit and dim dots, the brand mark is a sideways T, error states show distinct red glyphs grouped by failure type, and busy transitions get matching dot animations.

### User-visible changes

- The status item is now a 3×3 dot matrix: a sideways T when connected, an all-dim grid when disconnected, a clockwise chase animation around the ring while connecting, and a dot-by-dot T collapse while disconnecting.
- Auto-reconnect blinks the whole T pattern and route repair scans row by row, each busy state visually distinct.
- Error states show grouped red glyphs: an hourglass for timeout, a lock for auth/certificate, broken columns for a dropped connection, a hollow ring for network-changed/reconnect-failed, and an X for route/teardown cleanup failures.
- New Dock icon: a white C-shaped dot matrix (the C of liteOC) on a dark squircle, sharing the same visual language as the status item.

### Verification

- All 17 contract test scripts pass, including a new menu-bar icon pure-function suite with 59 assertions locking every state's frame sequence, frame interval, and tint; architecture tests confirm no leftover PNG/spinner paths.
- Both the status-item matrix and the Dock icon were visually verified from enlarged renders: correct glyphs, dim dots visible at 22% opacity, grid centered on the canvas.
- The app builds and packages cleanly from this version (full build.sh pipeline: icon generation, compile, signing).

## Full Changelog

https://github.com/ren2019/LiteOC/compare/v1.10...v1.11
