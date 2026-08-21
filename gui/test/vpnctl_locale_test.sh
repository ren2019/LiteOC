#!/bin/sh
# vpnctl OpenConnect locale contract — exercise the public start -> status path.
# 用法: sh gui/test/vpnctl_locale_test.sh
set -eu

VPNCTL="$(cd "$(dirname "$0")/.." && pwd)/vpnctl"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CONF="$WORK/conf"
LOG="$WORK/openconnect.log"
RUNNING="$WORK/openconnect-running"
ROUTE_STATE="$WORK/route-state"
LOCALE_TRACE="$WORK/locale-trace"

export LITEOC_TESTING=1 LITEOC_LOG="$LOG"
export LITEOC_ROUTE_STATE_FILE="$WORK/owned-routes"
export LITEOC_OPENCONNECT_BIN="$WORK/openconnect"
export RUNNING ROUTE_STATE LOCALE_TRACE

printf 'HOST=vpn.example:9443\nUSER=me\nGROUP=g1\nSERVERCERT=\n' > "$CONF"
printf 'clean\n' > "$ROUTE_STATE"
: > "$LOCALE_TRACE"

pass=0
fail=0
check() {
  if [ "$2" = "$3" ]; then
    pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail+1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

cat > "$WORK/pgrep" <<'EOF'
#!/bin/sh
[ -f "$RUNNING" ]
EOF
cat > "$WORK/ifconfig" <<'EOF'
#!/bin/sh
[ "${1:-}" = en0 ]
EOF
cat > "$WORK/dscacheutil" <<'EOF'
#!/bin/sh
printf 'name: vpn.example\nip_address: 203.0.113.10\n'
EOF
cat > "$WORK/route" <<'EOF'
#!/bin/sh
if [ "$1 $2 $3" = "-n get default" ]; then
  printf '   route to: default\ndestination: default\n    gateway: 192.168.1.1\n  interface: en0\n      flags: <UP,GATEWAY,STATIC>\n'
elif [ "$1 $2 $3" = "-n get 203.0.113.10" ]; then
  if [ "$(cat "$ROUTE_STATE")" = current ]; then
    printf '   route to: 203.0.113.10\ndestination: 203.0.113.10\n    gateway: 192.168.1.1\n  interface: en0\n      flags: <UP,GATEWAY,HOST,STATIC>\n'
  else
    printf '   route to: 203.0.113.10\ndestination: default\n    gateway: 192.168.1.1\n  interface: en0\n      flags: <UP,GATEWAY,STATIC>\n'
  fi
else
  exit 1
fi
EOF
cat > "$LITEOC_OPENCONNECT_BIN" <<'EOF'
#!/bin/sh
locale="${LC_ALL:-<unset>}"
case " $* " in
  *" --background "*)
    printf 'start=%s\n' "$locale" >> "$LOCALE_TRACE"
    : > "$RUNNING"
    printf 'current\n' > "$ROUTE_STATE"
    if [ "$locale" = C ]; then
      printf 'Configured as 192.0.2.42\n'
    else
      printf '已配置为 192.0.2.42\n'
    fi
    exit 0
    ;;
  *)
    printf 'discover=%s\n' "$locale" >> "$LOCALE_TRACE"
    printf '服务器证书指纹 pin-sha256:abcDEF+/==\n' >&2
    exit 1
    ;;
esac
EOF
chmod +x "$WORK/pgrep" "$WORK/ifconfig" "$WORK/dscacheutil" "$WORK/route" "$LITEOC_OPENCONNECT_BIN"

run_vpnctl() {
  PATH="$WORK:$PATH" LC_ALL=zh_CN.UTF-8 LANG=zh_CN.UTF-8 sh "$VPNCTL" "$@" "$CONF"
}

echo "== vpnctl OpenConnect locale contract =="

out=$(printf 'pin\n' | run_vpnctl start)
check "非英文父环境仍可启动并完成 TOFU" "discovered-cert:pin-sha256:abcDEF+/==
started" "$out"

out=$(run_vpnctl status)
check "start 产生的日志可由 status 识别为 connected" "connected 192.0.2.42" "$out"

check "证书探测和正式连接都固定使用 C locale" "discover=C
start=C" "$(cat "$LOCALE_TRACE")"

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" = 0 ]
