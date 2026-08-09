#!/bin/sh
# vpnctl 网关路由契约测试 — 只通过公开 CLI 驱动，不触碰真实系统路由。
# 用法: sh gui/test/vpnctl_route_test.sh
set -eu

VPNCTL="$(cd "$(dirname "$0")/.." && pwd)/vpnctl"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CONF="$WORK/conf"
export ROUTE_STATE="$WORK/route-state" ROUTE_LOG="$WORK/route-log" ROUTE_DELETE_FAIL=0
export PGREP_COUNT="$WORK/pgrep-count" PGREP_RUNNING_UNTIL=0 PKILL_LOG="$WORK/pkill-log" PKILL_FAIL=0
export LITEOC_TESTING=1 LITEOC_LOG="$WORK/openconnect.log"
export LITEOC_ROUTE_STATE_FILE="$WORK/owned-routes" LITEOC_OPENCONNECT_BIN="$WORK/openconnect"
export PHYSICAL_IP=192.168.1.17 PHYSICAL_ROUTER=192.168.1.1
printf 'HOST=vpn.example:9443\nUSER=me\nGROUP=g1\nSERVERCERT=pin-sha256:test\n' > "$CONF"
printf 'stale\n' > "$ROUTE_STATE"
: > "$ROUTE_LOG"
/bin/rm -f "$LITEOC_ROUTE_STATE_FILE"

pass=0; fail=0
check() {   # desc expected actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; fi
}

printf '#!/bin/sh\nexit 1\n' > "$WORK/pgrep"
printf '#!/bin/sh\n[ "${1:-}" = en0 ]\n' > "$WORK/ifconfig"
cat > "$WORK/dscacheutil" <<'EOF'
#!/bin/sh
printf 'name: vpn.example\nip_address: 203.0.113.10\n'
EOF
cat > "$WORK/ipconfig" <<'EOF'
#!/bin/sh
case "$1 $2 $3" in
  "getifaddr en0 ") printf '%s\n' "$PHYSICAL_IP" ;;
  "getoption en0 router") printf '%s\n' "$PHYSICAL_ROUTER" ;;
  *) exit 1 ;;
esac
EOF
cat > "$WORK/route" <<'EOF'
#!/bin/sh
if [ "$1 $2 $3" = "-n get default" ]; then
  printf '   route to: default\ndestination: default\n    gateway: 192.168.1.1\n  interface: en0\n      flags: <UP,GATEWAY,STATIC>\n'
elif [ "$1 $2 $3" = "-n get 203.0.113.10" ]; then
  if [ "$(cat "$ROUTE_STATE")" = lookup-fail ]; then
    exit 1
  elif [ "$(cat "$ROUTE_STATE")" = stale ]; then
    printf '   route to: 203.0.113.10\ndestination: 203.0.113.10\n    gateway: 172.20.10.1\n  interface: en0\n      flags: <UP,GATEWAY,HOST,STATIC>\n'
  elif [ "$(cat "$ROUTE_STATE")" = current ]; then
    printf '   route to: 203.0.113.10\ndestination: 203.0.113.10\n    gateway: 192.168.1.1\n  interface: en0\n      flags: <UP,GATEWAY,HOST,STATIC>\n'
  elif [ "$(cat "$ROUTE_STATE")" = dynamic ]; then
    printf '   route to: 203.0.113.10\ndestination: 203.0.113.10\n    gateway: 172.20.10.1\n  interface: en0\n      flags: <UP,GATEWAY,HOST,LLINFO>\n'
  elif [ "$(cat "$ROUTE_STATE")" = uncertain ]; then
    printf '   route to: 203.0.113.10\ndestination: 203.0.113.10\n  interface: en0\n      flags: <UP,GATEWAY,HOST,STATIC>\n'
  else
    printf '   route to: 203.0.113.10\ndestination: default\n    gateway: 192.168.1.1\n  interface: en0\n      flags: <UP,GATEWAY,STATIC>\n'
  fi
elif [ "$1 $2 $3 $4" = "-n delete -host 203.0.113.10" ]; then
  printf '%s\n' "$*" >> "$ROUTE_LOG"
  [ "$ROUTE_DELETE_FAIL" -eq 0 ] || exit 1
  printf 'clean\n' > "$ROUTE_STATE"
else
  exit 1
fi
EOF
chmod +x "$WORK/pgrep" "$WORK/ifconfig" "$WORK/dscacheutil" "$WORK/ipconfig" "$WORK/route"

echo "== vpnctl 网关路由契约 =="

out=$(PATH="$WORK:$PATH" sh "$VPNCTL" repair "$CONF" 2>&1 || true)
check "启动恢复精确清理旧网关主机路由" "route-repaired" "$out"
check "只删除当前配置解析出的精确 IP" "-n delete -host 203.0.113.10" "$(cat "$ROUTE_LOG")"
check "清理后目标走当前默认网关" "clean" "$(cat "$ROUTE_STATE")"

printf 'stale\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" status "$CONF")
check "进程退出但旧网关路由仍在 → 退化状态" "route-stale" "$out"
check "status 只识别、不修改路由" "" "$(cat "$ROUTE_LOG")"

printf 'stale\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" stop "$CONF")
check "进程已退出时 stop 仍自愈过期路由" "not-running" "$out"
check "退化状态恢复后目标走当前默认网关" "clean" "$(cat "$ROUTE_STATE")"

cat > "$WORK/pgrep" <<'EOF'
#!/bin/sh
n=$(cat "$PGREP_COUNT" 2>/dev/null || printf 0); n=$((n+1)); printf '%s\n' "$n" > "$PGREP_COUNT"
[ "$n" -le "$PGREP_RUNNING_UNTIL" ]
EOF
cat > "$WORK/pkill" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$PKILL_LOG"
[ "$PKILL_FAIL" -eq 0 ]
EOF
printf '#!/bin/sh\nexit 0\n' > "$WORK/sleep"
chmod +x "$WORK/pgrep" "$WORK/pkill" "$WORK/sleep"
printf '0\n' > "$PGREP_COUNT"; export PGREP_RUNNING_UNTIL=2
printf 'current\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"; : > "$PKILL_LOG"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" stop "$CONF")
check "stop 等进程退出且路由验证完成才成功" "stopped" "$out"
check "stop 使用优雅退出信号" "-INT -x openconnect" "$(cat "$PKILL_LOG")"
check "stop 等待到进程实际退出" "3" "$(cat "$PGREP_COUNT")"
check "stop 删除本会话网关主机路由" "clean" "$(cat "$ROUTE_STATE")"

printf '0\n' > "$PGREP_COUNT"; export PGREP_RUNNING_UNTIL=0
printf 'stale\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"
PATH="$WORK:$PATH" sh "$VPNCTL" start "$CONF" </dev/null >/dev/null 2>&1 || true
check "start 在调用 openconnect 前修复旧网关路由" "clean" "$(cat "$ROUTE_STATE")"

cat > "$LITEOC_OPENCONNECT_BIN" <<'EOF'
#!/bin/sh
printf 'current\n' > "$ROUTE_STATE"
exit 1
EOF
chmod +x "$LITEOC_OPENCONNECT_BIN"
printf '0\n' > "$PGREP_COUNT"; export PGREP_RUNNING_UNTIL=0
printf 'clean\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"
out=$(printf 'pin\n' | PATH="$WORK:$PATH" sh "$VPNCTL" start "$CONF" 2>&1 || true)
check "连接失败返回认证错误" "auth-failed" "$out"
check "连接失败后立即清理本次新增网关路由" "clean" "$(cat "$ROUTE_STATE")"

cat > "$LITEOC_OPENCONNECT_BIN" <<'EOF'
#!/bin/sh
printf 'current\n' > "$ROUTE_STATE"
exit 0
EOF
chmod +x "$LITEOC_OPENCONNECT_BIN"
printf '0\n' > "$PGREP_COUNT"; export PGREP_RUNNING_UNTIL=0
printf 'clean\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"; /bin/rm -f "$LITEOC_ROUTE_STATE_FILE"
out=$(printf 'pin\n' | PATH="$WORK:$PATH" sh "$VPNCTL" start "$CONF")
check "连接成功记录本次新增的精确网关路由" "started" "$out"
check "会话所有权记录不含认证信息" "203.0.113.10" "$(cat "$LITEOC_ROUTE_STATE_FILE")"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" status "$CONF")
check "进程退出但已记录会话路由仍在 → 退化状态" "route-stale" "$out"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" repair "$CONF")
check "异常退出后启动恢复会清理已记录会话路由" "route-repaired" "$out"
check "异常退出恢复覆盖同一活动网络" "clean" "$(cat "$ROUTE_STATE")"
check "恢复完成后移除会话所有权记录" "no" "$([ -e "$LITEOC_ROUTE_STATE_FILE" ] && printf yes || printf no)"

CONF_TOFU="$WORK/conf-tofu"
printf 'HOST=vpn.example:9443\nUSER=me\nGROUP=g1\nSERVERCERT=\n' > "$CONF_TOFU"
cat > "$LITEOC_OPENCONNECT_BIN" <<'EOF'
#!/bin/sh
case " $* " in
  *" --background "*) printf 'current\n' > "$ROUTE_STATE"; exit 0 ;;
  *) printf 'current\n' > "$ROUTE_STATE"; printf 'server pin is pin-sha256:abcDEF+/==\n' >&2; exit 1 ;;
esac
EOF
chmod +x "$LITEOC_OPENCONNECT_BIN"
printf '0\n' > "$PGREP_COUNT"; export PGREP_RUNNING_UNTIL=0
printf 'clean\n' > "$ROUTE_STATE"; /bin/rm -f "$LITEOC_ROUTE_STATE_FILE"
out=$(printf 'pin\n' | PATH="$WORK:$PATH" sh "$VPNCTL" start "$CONF_TOFU")
check "路由修复不影响 TOFU 证书发现与 started 契约" "discovered-cert:pin-sha256:abcDEF+/==
started" "$out"
PATH="$WORK:$PATH" sh "$VPNCTL" repair "$CONF_TOFU" >/dev/null

cat > "$LITEOC_OPENCONNECT_BIN" <<'EOF'
#!/bin/sh
printf 'current\n' > "$ROUTE_STATE"
exit 1
EOF
chmod +x "$LITEOC_OPENCONNECT_BIN"
printf 'clean\n' > "$ROUTE_STATE"; /bin/rm -f "$LITEOC_ROUTE_STATE_FILE"
out=$(printf 'pin\n' | PATH="$WORK:$PATH" sh "$VPNCTL" start "$CONF_TOFU" 2>&1 || true)
check "TOFU 探测失败返回明确错误" "cert-discover-failed" "$out"
check "TOFU 探测失败也清理新增网关路由" "clean" "$(cat "$ROUTE_STATE")"
/bin/rm -f "$LITEOC_OPENCONNECT_BIN"

printf '0\n' > "$PGREP_COUNT"; export PGREP_RUNNING_UNTIL=0
printf 'current\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" repair "$CONF")
check "无进程但路由仍属于当前活动网络 → 保持原状" "route-clean" "$out"
check "安全边界不删除无法证明过期的路由" "" "$(cat "$ROUTE_LOG")"

printf '0\n' > "$PGREP_COUNT"; export PGREP_RUNNING_UNTIL=0
printf 'dynamic\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" repair "$CONF")
check "不删除非 STATIC 的精确主机路由" "route-clean" "$out"
check "动态主机路由保持原状" "" "$(cat "$ROUTE_LOG")"

printf '0\n' > "$PGREP_COUNT"; export PGREP_RUNNING_UNTIL=0
printf 'uncertain\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" status "$CONF")
check "无法安全判断精确路由时不能报告健康 down" "route-check-failed" "$out"
check "无法证明过期时保持路由原状" "" "$(cat "$ROUTE_LOG")"

printf 'lookup-fail\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" status "$CONF")
check "route get 执行失败不能报告健康 down" "route-check-failed" "$out"
printf '203.0.113.10\n' > "$LITEOC_ROUTE_STATE_FILE"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" repair "$CONF" 2>&1 || true)
check "所有权路由查询失败必须可见" "route-check-failed" "$out"
check "查询失败时保留所有权记录供后续恢复" "203.0.113.10" "$(cat "$LITEOC_ROUTE_STATE_FILE")"
/bin/rm -f "$LITEOC_ROUTE_STATE_FILE"

printf '0\n' > "$PGREP_COUNT"; export PGREP_RUNNING_UNTIL=1 ROUTE_DELETE_FAIL=1
printf 'current\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" stop "$CONF" 2>&1 || true)
check "stop 路由删除失败不能返回 stopped" "route-cleanup-failed" "$out"
check "删除失败时路由状态保持可见" "current" "$(cat "$ROUTE_STATE")"

printf '0\n' > "$PGREP_COUNT"; export PGREP_RUNNING_UNTIL=999 ROUTE_DELETE_FAIL=0
printf 'current\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" stop "$CONF" 2>&1 || true)
check "进程超时未退出不能返回 stopped" "stop-timeout" "$out"
check "进程仍在时不抢先删除网关路由" "current" "$(cat "$ROUTE_STATE")"

printf '0\n' > "$PGREP_COUNT"; export PGREP_RUNNING_UNTIL=1 PKILL_FAIL=1
printf 'current\n' > "$ROUTE_STATE"; : > "$ROUTE_LOG"
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" stop "$CONF" 2>&1 || true)
check "SIGINT 竞态中进程已自行退出仍完成验证" "stopped" "$out"
check "竞态退出后仍清理已捕获的会话路由" "clean" "$(cat "$ROUTE_STATE")"
export PKILL_FAIL=0

out=$(PATH="$WORK:$PATH" sh "$VPNCTL" network "$CONF" 2>&1 || true)
check "network 暴露物理接口/IP/网关指纹供切网检测" "network en0 192.168.1.17 192.168.1.1" "$out"
export PHYSICAL_IP=172.20.10.2 PHYSICAL_ROUTER=172.20.10.1
out=$(PATH="$WORK:$PATH" sh "$VPNCTL" network "$CONF" 2>&1 || true)
check "同一接口切换网络后指纹发生变化" "network en0 172.20.10.2 172.20.10.1" "$out"

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" = 0 ]
