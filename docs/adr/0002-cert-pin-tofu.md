# ADR-0002 — 证书指纹:可选 + 首次自动锁定(TOFU)

- 状态:Accepted
- 日期:2026-07-27

## 背景(Context)
开通邮件只给 `HOST/USER/GROUP/PIN`,**从不给证书指纹**。而 openconnect 非交互(后台)连接必须锁定证书(网关证书自签/已过期,系统不信任)。若强制 `SERVERCERT` 必填,用户得另外探测指纹,"收到一封邮件即可配置"做不到。

## 决策(Decision)
`SERVERCERT` **可选**。为空时:
1. vpnctl 首次连接主动获取网关证书的 `pin-sha256`(让 openconnect 报出,或用 openssl 做 TLS 探测算 SPKI 哈希);
2. 用该 pin 完成本次连接;
3. 把 pin **回传给 App**,由 **App(用户态)**写入 `~/Library/Application Support/LiteOC/config` 的 `SERVERCERT=`(不让 root 直接改用户文件,避免属主错乱)。

之后每次连接严格按此 pin 校验。

## 后果(Consequences)
- ✅ 收到标准 AnyLink 开通邮件即可零额外信息配齐(HOST/USER/GROUP 填配置、PIN 存钥匙串、证书首次自动锁)。
- ✅ 锁定后,证书被换 → 连接失败报错(中间人检测 / 正常轮换提示)。
- ⚠️ **TOFU 风险**:首次连接若已被中间人,会锁定到攻击者证书。等同 SSH 首次连主机;在"可信邮件 + 可信网络首次配置"前提下可接受。
- ⚠️ 证书正常轮换时,用户需清空 `SERVERCERT` 重新锁定(fail loudly 会提示)。

## 备选(Alternatives)
1. `SERVERCERT` 必填 + 文档教用户探测 → 否决(违背"一封邮件即配",体验差)。
2. 完全不校验证书(`--servercert` 也不传,openconnect 每次交互确认)→ 否决(非交互后台连不上,且无 MITM 防护)。
