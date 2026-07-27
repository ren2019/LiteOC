#!/bin/sh
# 一次性安装 root 部分 (sudo 运行): 装 openconnect(缺则 brew) + vpnctl + 免密 sudoers + 装 App
# 用法:  sudo sh setup-root.sh
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "❌ 请用 sudo 运行: sudo sh setup-root.sh"; exit 1; }
USER_="${SUDO_USER:-$(stat -f%Su /dev/console)}"
[ -n "$USER_" ] || { echo "❌ 无法确定用户名"; exit 1; }

# openconnect: 缺则用 brew 以【用户身份】装 (brew 不能以 root 跑)
if ! [ -x /opt/homebrew/bin/openconnect ] && ! [ -x /usr/local/bin/openconnect ]; then
  BREW=""
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && BREW="$b" && break; done
  [ -n "$BREW" ] || { echo "❌ 未找到 Homebrew, 请先安装: https://brew.sh"; exit 1; }
  echo "→ 未找到 openconnect, 以 $USER_ 身份 brew install…"
  sudo -H -u "$USER_" "$BREW" install openconnect
  if ! [ -x /opt/homebrew/bin/openconnect ] && ! [ -x /usr/local/bin/openconnect ]; then
    echo "❌ brew install openconnect 失败"; exit 1
  fi
fi

echo "→ 安装 vpnctl 到 /usr/local/sbin (root 拥有)…"
mkdir -p /usr/local/sbin
install -m 755 -o root -g wheel "$DIR/vpnctl" /usr/local/sbin/vpnctl

echo "→ 写免密 sudoers (仅限 vpnctl 路径)…"
echo "$USER_ ALL=(root) NOPASSWD: /usr/local/sbin/vpnctl" > /etc/sudoers.d/vpnctl
chmod 0440 /etc/sudoers.d/vpnctl
visudo -cf /etc/sudoers.d/vpnctl >/dev/null

# App: 兼容开发目录 (build/) 与发布包 (与脚本相邻)
APP=""
for a in "$DIR/build/LiteOC.app" "$DIR/LiteOC.app"; do [ -d "$a" ] && APP="$a" && break; done
[ -n "$APP" ] || { echo "❌ 找不到 LiteOC.app (期望 $DIR/build/LiteOC.app 或 $DIR/LiteOC.app)"; exit 1; }
echo "→ 安装 App 到 /Applications…"
rm -rf "/Applications/LiteOC.app"
cp -R "$APP" "/Applications/"

echo ""
echo "✅ 完成! 启动台运行 LiteOC, 或: open '/Applications/LiteOC.app'"
echo "   首次: 菜单「配置…」填网关信息 + 「设置 PIN…」存 PIN, 再点连接。"
