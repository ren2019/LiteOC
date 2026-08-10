# CONTEXT — LiteOC 领域术语表

> 仅领域语言(glossary)。实现细节见 `docs/config-spec.md`,不可逆决策见 `docs/adr/`。

- **Profile**:一套完整的 VPN 连接定义 = {Gateway, User, Group, Cert Pin, Keychain Key}。当前系统只有**一个** Profile。
- **PIN**:Profile 的机密凭据。**只存 macOS 钥匙串,永不进配置文件或代码。** 登录密码 = PIN(当前无 OTP)。
- **Gateway**:VPN 网关地址(host:port),AnyLink 服务端。
- **User / Group**:网关账号与用户组(AnyLink 里 group 经表单选择提交)。
- **Cert Pin**:网关证书指纹锁定(`pin-sha256:…`),防中间人;网关证书过期/自签不影响。**可选**:留空则首次连接自动锁定(TOFU)并回写配置。
- **Keychain Key**:PIN 在钥匙串里的定位对 (service, account)。
- **Status Detection**:由 Root Helper 的 status 命令输出:`down`(无 openconnect 进程且无过期网关路由)/ `route-stale`(进程已退出但当前 Profile 的网关仍有可恢复静态主机路由)/ `route-check-failed`(存在无法安全判断的路由状态)/ `connecting`(进程在但未拿到有效 IP)/ `connected <ip>`(进程在且拿到有效 IP)。有效内网 IP 仅取自 openconnect 自身输出(`Configured as <ip>`),不再以 ifconfig 猜网段。
- **Tunnel 状态**:Repairing / Disconnected / Connecting / Disconnecting / Connected / Error。清理完成前保持 Repairing 或 Disconnecting;路由检查/清理失败、网络变化、连接超时、掉线、认证或证书失败均进入可见 Error。
- **Root Helper**(实现名 vpnctl):提权建立隧道的程序,以 root 经免密 sudo 运行。是**安全边界**。
- **Route Ownership Record**:只记录本次成功连接新增的网关 IP,用于 OpenConnect 异常退出后的精确恢复;不含认证信息。
- **Release Run**:由用户显式发起的一次发布操作。发起即授权该次发布所需的远程变更;从与远端同步的干净 main 开始,显式版本优先,否则默认取最新标签的下一 minor;只为 Release Note 产生发布提交。
- **Release Gate**:CI 对发布标签强制执行的发布条件。任何发布路径都必须通过,不能因绕过 Release Run 而绕过。
- **Release Note**:中英文说明本次发布变化的用户正文,包含结果摘要、用户可感知变化、验证结果和完整变更链接。它是 Release Gate 的必需输入,不能退化成只有版本比较链接的自动摘要。
- **CI Artifact**:PR 或主分支构建产生的非发布安装包,只证明构建与打包链路可用,不代表 Release。
- **Post-release Acceptance**:Release 生成后的本机下载安装与启动检查。Release Run 默认包含且默认不建立真实 VPN 连接;用户可用自然语言明确表达跳过或扩大验收的意图;不属于 Release Gate。
