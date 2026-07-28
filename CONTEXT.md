# CONTEXT — LiteOC 领域术语表

> 仅领域语言(glossary)。实现细节见 `docs/config-spec.md`,不可逆决策见 `docs/adr/`。

- **Profile**:一套完整的 VPN 连接定义 = {Gateway, User, Group, Cert Pin, Keychain Key}。当前系统只有**一个** Profile。
- **PIN**:Profile 的机密凭据。**只存 macOS 钥匙串,永不进配置文件或代码。** 登录密码 = PIN(当前无 OTP)。
- **Gateway**:VPN 网关地址(host:port),AnyLink 服务端。
- **User / Group**:网关账号与用户组(AnyLink 里 group 经表单选择提交)。
- **Cert Pin**:网关证书指纹锁定(`pin-sha256:…`),防中间人;网关证书过期/自签不影响。**可选**:留空则首次连接自动锁定(TOFU)并回写配置。
- **Keychain Key**:PIN 在钥匙串里的定位对 (service, account)。
- **Status Detection**:由 Root Helper 的 status 命令输出三态:`down`(无 openconnect 进程)/ `connecting`(进程在但未拿到有效 IP)/ `connected <ip>`(进程在且拿到有效 IP)。有效内网 IP 仅取自 openconnect 自身输出(`Configured as <ip>`),不再以 ifconfig 猜网段。
- **Tunnel 状态**:Disconnected(盾,template)/ Connecting(黄灯,脉冲)/ Connected(绿灯)/ Error(红灯;连接超时、已建立后掉线、认证或证书失败)。前三态由 Status Detection 直接驱动,Error 由菜单栏 app 派生。
- **Root Helper**(实现名 vpnctl):提权建立隧道的程序,以 root 经免密 sudo 运行。是**安全边界**。
