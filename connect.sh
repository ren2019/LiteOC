#!/usr/bin/env bash
# LiteOC CLI 连接 (GUI 的命令行兜底)
# 连接参数从本地配置读: ~/Library/Application Support/LiteOC/config
# PIN 从钥匙串或终端隐藏输入; 密码 = 纯 PIN
set -euo pipefail

CONF="$HOME/Library/Application Support/LiteOC/config"
[ -f "$CONF" ] || { echo "❌ 配置不存在: $CONF"; echo "   先跑菜单栏 App(会生成模板)或 GUI 的 setup-root.sh"; exit 1; }
# shellcheck disable=SC1090
source "$CONF"

: "${HOST:?配置缺 HOST}"
: "${USER:?配置缺 USER}"
: "${GROUP:?配置缺 GROUP}"
: "${SERVERCERT:?配置缺 SERVERCERT}"

# PIN: 优先钥匙串 (service=KEYCHAIN_SERVICE), 否则终端隐藏输入
SVC="${KEYCHAIN_SERVICE:-LiteOC}"
PIN="$(security find-generic-password -s "$SVC" -a "${KEYCHAIN_ACCOUNT:-pin}" -w 2>/dev/null || true)"
if [ -z "$PIN" ]; then
  IFS= read -s -p "PIN 码 (隐藏输入, 不回显): " PIN; echo
fi
[ -n "$PIN" ] || { echo "❌ PIN 为空"; exit 2; }

BIN=""
for p in /opt/homebrew/bin/openconnect /usr/local/bin/openconnect; do [ -x "$p" ] && BIN="$p" && break; done
[ -n "$BIN" ] || { echo "❌ 未找到 openconnect (brew install openconnect)"; exit 3; }

echo "→ 连接 https://$HOST (user=$USER, group=$GROUP) …  Ctrl-C 断开"
# stdin 顺序: 密码(第1行) + group(第2行)
printf '%s\n%s\n' "$PIN" "$GROUP" | sudo "$BIN" \
  --user="$USER" --passwd-on-stdin --servercert="$SERVERCERT" "https://$HOST"
