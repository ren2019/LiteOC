#!/usr/bin/env bash
# LiteOC CLI 兜底: 所有 VPN 操作均委托给 Root Helper(vpnctl)。
set -euo pipefail

CONF="$HOME/Library/Application Support/LiteOC/config"
VPNCTL="/usr/local/sbin/vpnctl"
if [ "${LITEOC_TESTING:-0}" = 1 ] && [ "$(/usr/bin/id -u)" -ne 0 ]; then
  VPNCTL="${LITEOC_VPNCTL:-$VPNCTL}"
fi

[ -x "$VPNCTL" ] || {
  echo "❌ Root Helper 未安装或不可执行: $VPNCTL" >&2
  echo "   请重新运行 LiteOC 安装器(.pkg),或在源码目录运行: cd gui && sudo sh setup-root.sh" >&2
  exit 3
}

case "${1:-connect}" in
  disconnect)
    sudo "$VPNCTL" stop "$CONF"
    exit $?
    ;;
  status)
    sudo "$VPNCTL" status "$CONF"
    exit $?
    ;;
  connect) ;;
  *)
    echo "用法: $0 [connect|disconnect|status]" >&2
    exit 64
    ;;
esac

PIN=""
IFS= read -r -s -p "PIN 码 (隐藏输入, 不回显): " PIN || true
echo >&2
[ -n "$PIN" ] || { echo "❌ PIN 为空" >&2; exit 2; }

CLEANUP_STATE="idle"
cleanup() {
  local stop_rc
  trap '' INT HUP TERM
  case "$CLEANUP_STATE" in
    cleaning|done) return 0 ;;
  esac

  CLEANUP_STATE="cleaning"
  set +e
  sudo "$VPNCTL" stop "$CONF"
  stop_rc=$?
  set -e
  CLEANUP_STATE="done"
  return "$stop_rc"
}

handle_signal() {
  local signal_rc="$1"
  trap '' INT HUP TERM
  cleanup || true
  exit "$signal_rc"
}

trap 'handle_signal 130' INT
trap 'handle_signal 129' HUP
trap 'handle_signal 143' TERM

printf '%s\n' "$PIN" | sudo "$VPNCTL" start "$CONF"

echo "→ 已交给 Root Helper 连接; 按 Ctrl-C 或 Ctrl-D 断开" >&2
while IFS= read -r _; do :; done

cleanup
