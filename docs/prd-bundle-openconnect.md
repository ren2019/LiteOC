# PRD:内置 openconnect,去除 Homebrew 依赖

> 状态:ready-for-agent 草稿。范围 = 仅「内置 openconnect + 去 brew」;双击 `.pkg` 免终端向导为独立后续 feature。

## Problem Statement

当前安装 LiteOC 依赖 Homebrew:安装器在检测到 openconnect 缺失时会 `brew install openconnect`。但目标用户(非开发的同事)的机器上大多**没有** Homebrew,而安装 Homebrew 本身**必须开终端**——这与「不开终端、自助一键安装」的目标直接冲突。

结果:在普通机器上,安装器卡在「未找到 Homebrew」就退出,逼用户进终端去装 brew,流程中断,同事无法自助完成。

## Solution

把**自包含的 openconnect**(二进制 + 其动态库闭包,重定位后可从任意路径运行)打进 LiteOC 的安装产物。安装器把它放到 **root 拥有、用户不可写**的位置(与 Root Helper 同一信任域)。Root Helper 优先解析这个内置二进制,仅在开发机上回退到 Homebrew 路径。安装器里的 brew 安装块被删除。

用户不再需要 Homebrew;安装产物自带运行时,安装器解决一切。

## User Stories

1. 作为非开发同事,我想全程不开终端就装好 LiteOC,以便自助上 VPN。
2. 作为非开发同事,我想安装器自带 openconnect,而不必先装 Homebrew。
3. 作为拿到全新 Mac 的同事,我想在零预装(无 brew、无 openconnect)的机器上安装也能一次成功。
4. 作为维护者,我想让 openconnect 随发布产物下发,使安装结果不依赖用户机器的当前状态。
5. 作为维护者,我想确认内置 openconnect 是真自包含(无 `/opt/homebrew` 库引用),以便它在没有 Homebrew 的机器上能跑。
6. 作为注重安全的用户,我想 Root Helper 执行的二进制是 root 拥有且用户不可写,以防低权进程替换它来提权。(保 ADR-0001)
7. 作为维护者,我想 .app bundle 保持**用户拥有**,以便 LiteOC 像普通 Mac 应用一样可拖拽更新/替换。
8. 作为已装 Homebrew openconnect 的开发者,我想 LiteOC 仍能照常用,以免破坏我现有环境。(回退路径)
9. 作为维护者,我想 CI 校验内置二进制确属自包含,以便在发布前抓住 dylibbundler 出错。
10. 作为维护者,我想内置二进制的进程名仍为 `openconnect`,以便连接/断开/Status Detection(按进程名)完全不受影响。
11. 作为用户,我想连接、PIN 处理、Cert Pin 的 TOFU、Status Detection、Tunnel 状态指示都与从前**完全一致**。
12. 作为维护者,我想内置 openconnect 钉死一个已知版本,使每次发布可复现。
13. 作为维护者,我想安装后若内置二进制缺失或不可执行,安装器**大声报错并退出**,而非静默坏掉、之后才暴露。
14. 作为维护者,我想文档(安装指南、README、ADR、config spec)反映「不再需要 Homebrew」,以免误导用户去装 brew。
15. 作为 Apple Silicon 用户,我想内置二进制被正确签名(ad-hoc),以便能被内核放行运行。(arm64 内核要求二进制必须有签名)
16. 作为在内网/受限网络环境的用户,我想安装不依赖安装时刻联网去拉取额外组件。(内置即装即用)
17. 作为维护者,我想安装器先校验内置二进制存在再继续,以便 payload 残缺时早早失败。
18. 作为用户,我想卸载/重装 LiteOC 时内置运行时被一并清理/重置,不留垃圾。
19. 作为维护者,我想保留对 Homebrew 路径的回退,以便开发机调试时可用我自己编译/升级的 openconnect。
20. 作为维护者,我想此变更**不引入**公司机密(网关 IP/PIN/Cert Pin/内网地址)到任何产物或文档,以维持项目去标识化。

## Implementation Decisions

- **交付方式**:CI 用 `dylibbundler` 收集 openconnect 的动态库闭包(实测 13 个 dylib),并把二进制的库 load 命令重写为相对其自身的 `@executable_path/libs/…`,使整个 bundle **可重定位**(拷到任意目录都能跑)。openconnect 版本钉到构建时 Homebrew 提供的版本(当前 9.21)。
- **体积**:自包含 openconnect ≈ 8.6 MB;加 openconnect 本体与 LiteOC.app,未压缩总 ≈ 9.4 MB,压缩(pkg/zip)≈ 3–4 MB。可接受。
- **安装位置(安全决策)**:内置 openconnect 装到一个 **root 拥有、用户不可写**的系统目录(与 Root Helper 同一信任域),**不**塞进用户可写的 .app bundle。理由:安装器以普通 `cp` 把 .app 装成用户可写;若让 root 去执行用户可写 bundle 内的二进制,会重开 ADR-0001 堵掉的提权后门。装到 root 拥有的目录则保住该不变量。
- **Root Helper 解析**:Root Helper 内写死的二进制搜索清单**前置**内置路径;Homebrew 的两个标准路径**降级为回退**(开发机兼容)。二进制进程名保持 `openconnect`,Status Detection 依据进程名的逻辑不变。
- **App 行为不变**:GUI 程序不引用、也不传递 openconnect 路径——它只调 Root Helper(子命令 + Profile 配置路径,PIN 经 stdin)。本次仅改一处用户可见的错误文案(「缺二进制」不再提 Homebrew)。GUI ↔ Root Helper 契约不变。
- **安装器变更**:删除 brew 安装块;新增内置二进制的安装步(root 拥有 + 校验可执行)。Root Helper 安装、免密 sudoers 规则(仅锁 Root Helper 单一路径)、.app 落 /Applications 三段**保持不变**。
- **签名**:内置二进制与其库做 **ad-hoc 签名**(arm64 必需,且与项目「匿名、无 Developer ID」的签名立场一致)。
- **Cert Pin 不受影响**:App 用 `--servercert=pin-sha256:` 钉网关证书、绕过 CA 校验,故内置 TLS 库的信任库路径非关键。
- **CI 产物**:发布 payload 在现有「.app + Root Helper + 安装器脚本 + 安装指南」基础上,**新增一个自包含 openconnect 目录**。
- **ADR-0001 修订**:补述 openconnect 现为内置、装到 root 拥有的系统路径;重述不变量(root 执行的路径源自 root 拥有/不可写代码,绝不来自用户可写配置);Homebrew 路径降为开发回退。

## Testing Decisions

- **好测试的标准**:只测**外部行为**(装好的系统能否用内置二进制连上 Gateway、通内网),不测实现细节。本仓当前**无任何测试框架**(无 `tests/`),且本 feature 是打包/安装向的,故不为一次「解析清单加一条路径」的改动引入单测框架。
- **接缝 1 — 验收(手动,端到端,最高接缝)**:在既无 Homebrew 也无 openconnect 的机器上跑安装器,再用有效 Profile + PIN 连 Gateway,确认内网可达、且运行进程是内置二进制(其路径在 root 拥有的系统目录下)。这是真正的完成定义。手动是因为需要可达 Gateway + 真实 PIN(机密,不进 CI)。
- **接缝 2 — CI 守卫(自动,产物不变量)**:在 GitHub Action 里断言内置 openconnect 自包含——`otool -L` 只剩相对自身的 `libs/*` + 系统库(**无** `/opt/homebrew` 引用),且 `--version` 退出 0。这是 CI 可达的最高接缝,守护 dylibbundler 不产出「非重定位」二进制。
- **先例**:仓内无既有测试(本 feature 引入首个测试);现有自动化面是 CI workflow,接缝 2 在其上扩展。
- **两条接缝而非一条的理由**:手动端到端(接缝 1)是真正的闸口,但不能跑在 CI;接缝 2 是它在 CI 里的自动代理。为一行 shell 解析改动新建完整测试框架,投入大于 feature 本身。

## Out of Scope

- **双击 `.pkg` 免终端安装向导**:独立、更大的 feature(涉及 Gatekeeper、签名/公证、以及与「匿名立场」的权衡)。本工作是它的**前置**:去掉 Homebrew 这个坑,但安装当前仍需在终端跑安装器脚本。
- **用现代特权助手架构(SMAppService / SMJobBless)替换 sudoers 模型**:需要 Developer ID 且是大重构,超出范围。
- **Intel macOS 支持**:项目本就仅 Apple Silicon;内置运行时保持 arm64。
- **内置 openconnect 的自动更新**:构建时钉版;重打包是发布时的手动动作(上游极少发版,见下)。

## Further Notes

- **上游节奏(已查 changelog)**:openconnect v9.x 在 2024、2025 **全年零发布**;v9.12(2023-05)→ v9.20(2026-06)隔约 **3 年**。钉 9.21 可长期用,仅在出 CVE 或多年一更时重打包——「内置 = 要长期跟进更新」的顾虑基本不成立。
- **去标识化**:本 feature 纯打包;PRD、产物、issue 均不含公司机密(网关 IP/PIN/Cert Pin/内网地址)。那些只留在本地 `~/Library` 配置 + 私有记忆 + 内网 Confluence,绝不进公开仓。
- **决策渊源**:本 PRD 由 bundle 实现计划转写而来;详细到步骤的实现设计见实现计划,本文件是更高层的需求/决策文档。
