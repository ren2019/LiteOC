# ADR-0001 — openconnect 二进制路径不进用户配置

- 状态:Accepted
- 日期:2026-07-27

## 背景(Context)
Root Helper(vpnctl)以 **root** 经免密 sudo 运行,并 `exec` openconnect 建立隧道。系统支持一个**用户可写**的配置文件(便于改网关/证书等)。问题是:openconnect 的路径能否也放进这个用户可写配置?

## 决策(Decision)
**不能。** openconnect 路径**写死在 vpnctl**(root 拥有、用户不可写)里,不来自用户配置。vpnctl 试一个写死的固定清单:**内置 `/usr/local/libexec/liteoc/openconnect`**(root 拥有,随 `.pkg` 安装,优先)→ `/opt/homebrew/bin` → `/usr/local/bin`(开发机回退)。发布安装器(.pkg)把**自包含** openconnect 装到 root 拥有的 libexec 路径,使路径确定且**不需 Homebrew**;源码/开发路径仍可用 brew。

## 理由 / 后果(Consequences)
- ✅ 堵掉提权后门:若路径来自用户可写配置,任何能改配置的进程都能让 root 执行任意程序。
- ✅ 配置里的其它字段(网关/用户/组/证书)只是 openconnect 的**参数**,不是"要执行的程序",留在配置无此风险——边界清晰。
- ✅ 内置 openconnect 装在 root 拥有、用户不可写的 `/usr/local/libexec/liteoc/`(与 vpnctl 同信任域);**不**塞进用户可写的 .app——否则同样开后门。
- ⚠️ openconnect 必须在标准路径(或由安装器装);用户不能指向自编译/非标准位置的 openconnect。
- ⚠️ 跨架构(Apple Silicon vs Intel)靠固定清单覆盖。

## 备选(Alternatives)
1. 允许配置 `OPENCONNECT` 路径 → **否决**(提权)。
2. 只认单一固定路径 → 太脆(换机/换架构易断),故用清单。
