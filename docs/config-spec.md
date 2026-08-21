# Spec — 配置抽取(把 PIN 之外的项变成可编辑配置)

> 实现状态:✅ 已实现(D1–D7、D9)/ ❌ D8 未实现(schema 稳定,暂不需要)。详见文末。

## D1 — 配置单位:单 Profile ✅
只有一个 VPN。配置描述这一个 Profile;按单 profile 写,将来可扩 `profiles[]`。

## D2 — 范围:配置 vs 写死 ✅

| 项 | 归属 |
|---|---|
| Gateway / User / Group | **配置** |
| Cert Pin (SERVERCERT) | **配置,可选**(空则首次自动锁定,见 D9) |
| Keychain Key service | **配置**(account 固定 `"pin"`,写死在代码) |
| openconnect 二进制路径 | **写死**(安全边界,见 ADR-0001) |
| App 名 / vpnctl 路径 / PIDFILE / 路由所有权记录 / 旧迁移名 | **写死** |

> Cert Pin 的值含 `/` 和末尾 `=`(如 `pin-sha256:…==`),解析按"第一个 `=` 之后全部"取值,不截断。

## D3 — 状态 / IP 探测:自动 ✅
- **是否连上**:`pgrep openconnect`。
- **分到的内网 IP**:从 openconnect 日志(`/tmp/liteoc-openconnect.log`)的 `Configured as <ip>` 取。
- **退化状态**:OpenConnect 不在运行、但当前 Profile 的网关 IP 仍有指向非当前默认网关/接口的 `HOST,STATIC` 路由时,`status` 返回 `route-stale`。
- **路由自愈**:App 启动和 `start` 前执行精确检查;`stop` 等待进程退出后验证并清理本次会话的网关主机路由。成功连接只把本次新增的网关 IP 记入 root 所有的 `/var/run/liteoc-openconnect.routes`,供异常退出恢复;不记录认证信息。只处理当前 Profile 解析出的 IPv4,不做广泛路由表清理。
- 网段换 / 动态分配都不用改代码(主路径靠 openconnect 自身输出)。

## D4 — openconnect 路径:写死 + 安装器内置 ✅
vpnctl 用写死的固定清单:**内置 `/usr/local/libexec/liteoc/openconnect` 优先** → Homebrew 路径(`/opt/homebrew/bin` → `/usr/local/bin`)回退。发布安装器(.pkg)把自包含 openconnect 装到 root 拥有的 libexec;源码/开发路径仍可用 brew。见 ADR-0001。

## D5 — 配置文件格式与位置 ✅
KEY=VALUE(带 `#` 注释),`~/Library/Application Support/LiteOC/config`。App 首次启动写默认模板;vpnctl 用 `grep+cut` 安全解析(不 `eval`);菜单「配置…」打开**图形配置窗口**(非文本编辑器)。

## D6 — OTP:不加 ✅
纯 PIN。服务器实测只校验 PIN。

## D7 — 校验与失败:fail loudly ◑(基本实现)
- 缺必填项(HOST/USER/GROUP)→ vpnctl 返回 `config-error:缺<字段>`,App 弹窗指名道姓。✅
- 非空 SERVERCERT 格式不对 → 交 openconnect 校验失败报错(未单独做格式提示)。◑
- 不静默兜底真实值。✅

## D8 — 跨版本升级:自动合并缺失项 ❌(未实现)
当前 schema 稳定,未做"老配置补新键"的合并;App 仅在**配置文件整个不存在**时写默认模板。将来加键时再实现。

## D9 — 证书指纹:可选 + 首次自动锁定(TOFU)✅
开通邮件从不带证书指纹。`SERVERCERT` 为空时,vpnctl 首次连接**不带 servercert 跑一次 openconnect**,从其输出抓 `pin-sha256`,用它连接并**回传给 App 写入配置**(TOFU)。之后严格校验;证书被换 → 连接失败提示重新锁定。见 ADR-0002。

---

## 配置文件(`~/Library/Application Support/LiteOC/config`)
```ini
# LiteOC 配置 — PIN 不在此文件(在 macOS 钥匙串)
# 改完保存, 下次连接即生效

HOST="vpn.example.com:443"
USER="your-username"
GROUP="your-group"
SERVERCERT=""                    # 留空 = 首次连接自动获取(TOFU)
KEYCHAIN_SERVICE="LiteOC"
```
> 不含:PIN(钥匙串)、openconnect 路径(写死)、OTP(不要)。此文件无机密,无需 chmod 600。

## 数据流
1. 用户在「配置…」窗口(或直接编辑 config 文件)填**非机密**参数。
2. App 读配置 → 取 KEYCHAIN 键 → 钥匙串取 PIN;点「连接」时校验,有错 fail loudly。把配置路径传 vpnctl。
3. vpnctl(root)用 `grep+cut` 安全解析;SERVERCERT 空则自动探测并回传(D9);用**写死的** openconnect 后台连接,输出记 `/tmp/liteoc-openconnect.log`。
4. App 显示状态:`pgrep` 判连/断;IP 从日志 `Configured as <ip>` 取;过期网关主机路由进入可见错误状态。

## 实现状态
- ✅ D1 D2 D3 D4 D5 D6 D7(基本) D9 — 已实现并实测通过(纯 PIN 连接、TOFU 证书自动获取+回写、IP 自动显示、缺项 fail-loudly、配置窗口)。
- ❌ D8(跨版本合并)— 未实现,当前 schema 稳定不需要。
