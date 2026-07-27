#!/bin/sh
# 一次性安装 root 部分 (sudo 运行): vpnctl + 免密 sudoers + 装 App + 校验 openconnect
# 用法:  sudo sh setup-root.sh
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "❌ 请用 sudo 运行: sudo sh setup-root.sh"; exit 1; }
USER_="${SUDO_USER:-$(stat -f%Su /dev/console)}"
[ -n "$USER_" ] || { echo "❌ 无法确定用户名"; exit 1; }

# 校验 openconnect (安装器应已 brew install; 此处只校验)
if ! [ -x /opt/homebrew/bin/openconnect ] && ! [ -x /usr/local/bin/openconnect ]; then
  echo "❌ 未找到 openconnect。请先(以 $USER_ 身份)运行: brew install openconnect"
  exit 1
fi

echo "→ 安装 vpnctl 到 /usr/local/sbin (root 拥有)…"
mkdir -p /usr/local/sbin
install -m 755 -o root -g wheel "$DIR/vpnctl" /usr/local/sbin/vpnctl

echo "→ 写免密 sudoers (仅限 vpnctl 路径)…"
echo "$USER_ ALL=(root) NOPASSWD: /usr/local/sbin/vpnctl" > /etc/sudoers.d/vpnctl
chmod 0440 /etc/sudoers.d/vpnctl
visudo -cf /etc/sudoers.d/vpnctl >/dev/null

echo "→ 安装 App 到 /Applications, 清理旧名…"
pkill -x LiteOC 2>/dev/null || true
pkill -x LiteOC 2>/dev/null || true
rm -rf "/Applications/LiteOC.app" "/Applications/LiteOC.app" "/Applications/LiteOC.app"
cp -R "$DIR/build/LiteOC.app" "/Applications/"

echo ""
echo "✅ 完成! 启动台运行 LiteOC, 或: open '/Applications/LiteOC.app'"
echo "   首次: 菜单“编辑配置…”填网关信息 + “设置 PIN…”存 PIN, 再点连接。"
