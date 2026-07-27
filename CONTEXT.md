# CONTEXT — LiteOC 领域术语表

> 仅领域语言(glossary)。实现细节见 `docs/config-spec.md`,不可逆决策见 `docs/adr/`。

- **Profile**:一套完整的 VPN 连接定义 = {Gateway, User, Group, Cert Pin, Keychain Key}。当前系统只有**一个** Profile。
- **PIN**:Profile 的机密凭据。**只存 macOS 钥匙串,永不进配置文件或代码。** 登录密码 = PIN(当前无 OTP)。
- **Gateway**:VPN 网关地址(host:port),AnyLink 服务端。
- **User / Group**:网关账号与用户组(AnyLink 里 group 经表单选择提交)。
- **Cert Pin**:网关证书指纹锁定(`pin-sha256:…`),防中间人;网关证书过期/自签不影响。**可选**:留空则首次连接自动锁定(TOFU)并回写配置。
- **Keychain Key**:PIN 在钥匙串里的定位对 (service, account)。
- **Status Detection**:判断"已连接"(`pgrep openconnect`)与读取分到的内网 IP(取自 openconnect 自身输出,非猜网段;动态分配也能拿到)。
- **Tunnel 状态**:Disconnected(灰) / Connecting(彩灰闪烁) / Connected(彩)。
- **Root Helper**(实现名 vpnctl):提权建立隧道的程序,以 root 经免密 sudo 运行。是**安全边界**。
