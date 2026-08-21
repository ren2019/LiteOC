#!/bin/sh
# vpnctl status 契约测试 — 项目首个自动化测试
# 通过 PATH 注入 fake pgrep / ifconfig + LITEOC_LOG 控制日志, 断言 status 与配置错误输出。
# 只验证外部输出,不耦合内部解析实现。
# 用法: sh gui/test/vpnctl_status_test.sh
set -eu

VPNCTL="$(cd "$(dirname "$0")/.." && pwd)/vpnctl"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CONF="$WORK/conf"
CONF_MISSING_HOST="$WORK/conf-missing-host"
CONF_MISSING_HOST_GROUP="$WORK/conf-missing-host-group"
CONF_MISSING_USER="$WORK/conf-missing-user"
LOG="$WORK/oc.log"
printf 'HOST=gw.example\nUSER=me\nGROUP=g1\n' > "$CONF"
printf 'USER=me\nGROUP=g1\n' > "$CONF_MISSING_HOST"
printf 'USER=me\n' > "$CONF_MISSING_HOST_GROUP"
printf 'HOST=gw.example\nGROUP=g1\n' > "$CONF_MISSING_USER"

pass=0; fail=0
check() {   # desc  expected  actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; fi
}

# fake pgrep: 进程"在" exit 0;"不在" exit 1 (忽略参数)
pgrep_hit()  { printf '#!/bin/sh\nexit 0\n' > "$WORK/pgrep"; chmod +x "$WORK/pgrep"; }
pgrep_miss() { printf '#!/bin/sh\nexit 1\n' > "$WORK/pgrep"; chmod +x "$WORK/pgrep"; }
# fake ifconfig: 永远吐一个 LAN IP, 验证 status 不会拿它当 VPN IP
printf '#!/bin/sh\necho "inet 192.168.1.17 netmask 0xffffff00"\n' > "$WORK/ifconfig"
printf '#!/bin/sh\nprintf "name: gw.example\\nip_address: 203.0.113.10\\n"\n' > "$WORK/dscacheutil"
cat > "$WORK/route" <<'EOF'
#!/bin/sh
printf '   route to: 203.0.113.10\ndestination: default\n    gateway: 192.168.1.1\n  interface: en0\n      flags: <UP,GATEWAY,STATIC>\n'
EOF
chmod +x "$WORK/ifconfig" "$WORK/dscacheutil" "$WORK/route"

run_status() { ( PATH="$WORK:$PATH" LITEOC_LOG="$LOG" LITEOC_TESTING=1 sh "$VPNCTL" status "$CONF" ); }
check_config_error() { # desc command config expected
  set +e
  out=$(PATH="$WORK:$PATH" LITEOC_LOG="$LOG" LITEOC_TESTING=1 sh "$VPNCTL" "$2" "$3")
  rc=$?
  set -e
  check "$1 输出" "$4" "$out"
  check "$1 exit code" "3" "$rc"
}

echo "== vpnctl status 契约 =="

check_config_error "status 缺单个必填字段" status "$CONF_MISSING_HOST" "config-error:缺 HOST"
check_config_error "status 缺多个必填字段" status "$CONF_MISSING_HOST_GROUP" "config-error:缺 HOST GROUP"
check_config_error "控制命令缺必填字段" stop "$CONF_MISSING_USER" "config-error:缺 USER"

pgrep_miss
out=$(run_status); check "无进程 → down" "down" "$out"

pgrep_hit; : > "$LOG"
out=$(run_status); check "进程在 + 无 IP → connecting" "connecting" "$out"

printf 'Configured as 192.0.2.42\n' > "$LOG"
out=$(run_status); check "有 Configured as → connected <ip>" "connected 192.0.2.42" "$out"

printf 'Configured as 198.51.100.146\n' > "$LOG"
out=$(run_status); check "VPN IP 落 192.168 段 → connected (不因网段误判)" "connected 198.51.100.146" "$out"

pgrep_hit; : > "$LOG"
out=$(run_status); check "ifconfig 有 LAN IP 但无 VPN IP → 仍 connecting" "connecting" "$out"

printf 'Configured as 10.0.0.1\nConfigured as 192.0.2.99\n' > "$LOG"
out=$(run_status); check "多行 Configured as (重连累积) 取最后一行" "connected 192.0.2.99" "$out"

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" = 0 ]
