# Spec — 配置抽取(把 PIN 之外的项变成可编辑配置)

> 状态:grilling 中。✅ 已定 / 🔵 推荐待定 / ❓ 未定。

## D1 — 配置单位:单 Profile ✅
只有一个公司 VPN。配置描述这一个 Profile;结构按单 profile 段写,将来可扩 `profiles[]`。

## D2 — 范围:配置 vs 写死 ✅

| 项 | 当前在 | 归属 |
|---|---|---|
| Gateway / User / Group | vpnctl | **配置** |
| Cert Pin (SERVERCERT) | vpnctl | **配置,可选**(空则首次自动锁定,见 D9) |
| Keychain Key (service/account) | main.swift | **配置** |
| openconnect 二进制路径 | vpnctl | **写死**(安全边界,见 ADR-0001) |
| App 名 / vpnctl 路径 / PIDFILE / 旧迁移名 | 两者 | **写死** |

> Cert Pin 的值含 `/` 和末尾 `=`(如 `pin-sha256:…==`),解析按"第一个 `=` 之后全部"取值,不会被截断。

## D3 — 状态 / IP 探测:自动 ✅
- **是否连上**:`pgrep openconnect`,无配置。
- **分到的内网 IP**:从 openconnect 自身输出取。vpnctl 把 openconnect 的 stdout 记到固定日志(如 `/tmp/liteoc-openconnect.log`),app grep 最近的 `Configured as <ip>`。
- **结果:VPN_IP_PATTERN 从配置移除**。网段换 / 动态分配都不用改代码。
- 依赖:openconnect 的 `Configured as` 消息格式(长期稳定)。

## D4 — openconnect 路径:写死 + 安装器统一装 ✅
vpnctl 用写死的固定路径清单(`/opt/homebrew/bin` → `/usr/local/bin`);**安装器负责 `brew install openconnect`**(用户级),setup-root 启动前校验存在。见 ADR-0001。

## D5 — 配置文件格式与位置 ✅
KEY=VALUE(带 `#` 注释),`~/Library/Application Support/LiteOC/liteoc.conf`。App 首次启动写默认模板;vpnctl 用 `grep+cut` 安全解析(不 `eval`);菜单"编辑配置…"用 TextEdit 打开。

## D6 — OTP:不加 ✅
纯 PIN。服务器实测只校验 PIN;无 OTP 密钥。将来若服务器要 OTP 再加。

## D7 — 校验与失败:fail loudly ✅
- **不再静默兜底默认值**(会掩盖写错的值)。
- 连接前校验:`HOST/USER/GROUP/KEYCHAIN_SERVICE/KEYCHAIN_ACCOUNT` 非空;`SERVERCERT` **可选**(空则走 D9),非空时须 `pin-sha256:` 开头。
- 违规 → 弹窗指名道姓 + "打开配置"按钮。
- openconnect 连接失败 → 弹窗显示日志里的真实原因。
- vpnctl 缺项/格式错时返回 `config-error: <字段>`。
- 校验时机:点"连接"时。

## D8 — 跨版本升级:自动合并缺失项 ✅
启动时 App 读用户配置,缺失的键 → 追加默认值 + 注释,**保留用户已改值**。配置永远完整,D7 不误报。

## D9 — 证书指纹:可选 + 首次自动锁定(TOFU)✅
开通邮件从不带证书指纹,而 openconnect 非交互连接又需要它。
- `SERVERCERT` 可选。**为空时**,vpnctl 首次连接主动获取网关证书的 `pin-sha256`(openconnect 报出 / openssl TLS 探测),用它连接,并把 pin **回写给 App 写入配置**。
- 之后严格按此 pin 校验;证书被换(中间人 / 正常轮换)→ fail loudly 提示重新锁定。
- 详见 ADR-0002。回写由 **App(用户态)**执行,vpnctl 只返回 pin,避免 root 改用户文件造成属主错乱。

---

## 最终配置文件预览(`~/Library/Application Support/LiteOC/liteoc.conf`)
```ini
# LiteOC 配置 — PIN 不在此文件(在 macOS 钥匙串)
# 改完保存, 下次连接即生效

# ---- VPN 网关 ----
HOST="vpn.example.com:443"
USER="your-username"
GROUP="your-group"
# 证书指纹; 留空则首次连接自动锁定并回写 (TOFU)
SERVERCERT="pin-sha256:..."   # 或留空走 TOFU(待实现)

# ---- 钥匙串(PIN 存这里) ----
KEYCHAIN_SERVICE="LiteOC"
KEYCHAIN_ACCOUNT="pin"
```
> 不含:PIN(钥匙串)、openconnect 路径(写死)、IP 段(自动)、OTP(不要)。
> 此文件无机密(无 PIN),无需 chmod 600。

## 数据流
1. 用户编辑 `liteoc.conf`(仅非机密参数)。
2. App 读配置 → 取 KEYCHAIN 键 → 钥匙串取 PIN;点"连接"时**校验**(D7),有错 **fail loudly**。把配置路径传给 vpnctl。
3. vpnctl(root)用 `grep+cut` **安全解析**取 HOST/USER/GROUP/SERVERCERT;`SERVERCERT` 空则首次自动取并回传(D9);用**写死的** openconnect 后台连接;输出记固定日志。
4. App 显示状态:`pgrep` 判连/断;IP 从 openconnect 日志 `Configured as <ip>` 取。

## 状态
✅ D1–D9 全部决策已定,**待用户确认达成共识后开始实现**。
实现期附带修:UI 状态行去灰;安装器统一 `brew install openconnect`。
