#!/bin/sh
# connect.sh Root Helper contract — exercise the public CLI without touching a real VPN.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONNECT="$ROOT/connect.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export CALLS="$WORK/calls" PIN_INPUT="$WORK/pin-input" START_ENTERED="$WORK/start-entered"
: > "$CALLS"
: > "$PIN_INPUT"

cat > "$WORK/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
cat > "$WORK/vpnctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
if [ "${1:-}" = start ]; then
  cat > "$PIN_INPUT"
  if [ "${BLOCK_START:-0}" = 1 ]; then
    : > "$START_ENTERED"
    while :; do sleep 1; done
  fi
  if [ "${START_RC:-0}" -ne 0 ]; then
    printf 'start-failed\n'
    exit "$START_RC"
  fi
  printf 'started\n'
elif [ "${1:-}" = stop ]; then
  printf 'stopped\n'
  exit "${STOP_RC:-0}"
elif [ "${1:-}" = status ]; then
  printf 'down\n'
  exit "${STATUS_RC:-0}"
fi
EOF
chmod +x "$WORK/sudo" "$WORK/vpnctl"

pass=0
fail=0
check() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

check_contains() {
  case "$3" in
    *"$2"*)
      pass=$((pass + 1)); printf '  ok   %s\n' "$1"
      ;;
    *)
      fail=$((fail + 1)); printf '  FAIL %s\n       missing: %s\n       actual:  %s\n' "$1" "$2" "$3"
      ;;
  esac
}

check_absent() {
  if grep -Eq -- "$2" "$CONNECT"; then
    fail=$((fail + 1)); printf '  FAIL %s\n       forbidden pattern: %s\n' "$1" "$2"
  else
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  fi
}

wait_for_lines() {
  target="$1"
  expected="$2"
  waited=0
  while [ "$(wc -l < "$target" | tr -d ' ')" -lt "$expected" ]; do
    [ "$waited" -ge 300 ] && return 1
    sleep 0.1
    waited=$((waited + 1))
  done
}

run_connect() {
  HOME="$WORK/home" PATH="$WORK:$PATH" LITEOC_TESTING=1 LITEOC_VPNCTL="$WORK/vpnctl" \
    bash "$CONNECT" "$@"
}

echo "== connect.sh Root Helper contract =="

printf 'secret-pin\n' | run_connect >/dev/null 2>&1 || true
check "无参数连接委托 Root Helper start" "start $WORK/home/Library/Application Support/LiteOC/config" "$(sed -n '1p' "$CALLS")"
check "PIN 只以一行 stdin 交给 Root Helper" "secret-pin" "$(cat "$PIN_INPUT")"
check "Root Helper 只收到一行 PIN" "1" "$(wc -l < "$PIN_INPUT" | tr -d ' ')"
check "连接后 Ctrl-D 委托 Root Helper stop" "stop $WORK/home/Library/Application Support/LiteOC/config" "$(sed -n '2p' "$CALLS")"

: > "$CALLS"
/bin/rm -f "$START_ENTERED"
BLOCKED_START_CALLS="$WORK/blocked-start-calls"
: > "$BLOCKED_START_CALLS"
set +e
CONNECT="$CONNECT" TEST_HOME="$WORK/home" TEST_PATH="$WORK:$PATH" TEST_VPNCTL="$WORK/vpnctl" \
  TEST_CALLS="$BLOCKED_START_CALLS" START_ENTERED="$START_ENTERED" BLOCK_START=1 \
  expect <<'EOF' >"$WORK/blocked-start-output"
set timeout 60
set env(HOME) $env(TEST_HOME)
set env(PATH) $env(TEST_PATH)
set env(LITEOC_TESTING) 1
set env(LITEOC_VPNCTL) $env(TEST_VPNCTL)
set env(CALLS) $env(TEST_CALLS)
set env(START_ENTERED) $env(START_ENTERED)
set env(BLOCK_START) 1
spawn -noecho bash $env(CONNECT)
expect "PIN"
send "blocked-start-pin\r"
for {set i 0} {$i < 600 && ![file exists $env(START_ENTERED)]} {incr i} {
  after 100
}
if {![file exists $env(START_ENTERED)]} {
  exit 1
}
send "\003"
expect eof
exit 0
EOF
blocked_start_rc=$?
set -e
[ "$blocked_start_rc" -eq 0 ] || sed 's/^/       /' "$WORK/blocked-start-output"
wait_for_lines "$BLOCKED_START_CALLS" 2 || true
check "start 执行期间 Ctrl-C 仍委托 Root Helper stop" "start $WORK/home/Library/Application Support/LiteOC/config
stop $WORK/home/Library/Application Support/LiteOC/config" "$(cat "$BLOCKED_START_CALLS")"
check "start 执行期间 Ctrl-C 后 CLI 及时退出" "0" "$blocked_start_rc"

: > "$CALLS"
export START_RC=23
set +e
start_failure_out="$(printf 'bad-pin\n' | run_connect 2>/dev/null)"
start_failure_rc=$?
set -e
unset START_RC
check "start 普通失败保持 Root Helper 输出" "start-failed" "$start_failure_out"
check "start 普通失败保持 Root Helper exit 码" "23" "$start_failure_rc"
check "start 普通失败不额外调用 stop" "start $WORK/home/Library/Application Support/LiteOC/config" "$(cat "$CALLS")"

: > "$CALLS"
export STOP_RC=24
set +e
eof_failure_out="$(printf 'eof-failure-pin\n' | run_connect 2>/dev/null)"
eof_failure_rc=$?
set -e
unset STOP_RC
check "Ctrl-D 保持 Root Helper stop 输出" "started
stopped" "$eof_failure_out"
check "Ctrl-D 保持 Root Helper stop exit 码" "24" "$eof_failure_rc"

: > "$CALLS"
export STOP_RC=25
set +e
out="$(run_connect disconnect </dev/null 2>/dev/null)"
disconnect_rc=$?
set -e
unset STOP_RC
check "disconnect 委托 Root Helper stop" "stop $WORK/home/Library/Application Support/LiteOC/config" "$(cat "$CALLS")"
check "disconnect 返回 Root Helper 输出" "stopped" "$out"
check "disconnect 返回 Root Helper exit 码" "25" "$disconnect_rc"

: > "$CALLS"
export STATUS_RC=26
set +e
out="$(run_connect status </dev/null 2>/dev/null)"
status_rc=$?
set -e
unset STATUS_RC
check "status 委托 Root Helper status" "status $WORK/home/Library/Application Support/LiteOC/config" "$(cat "$CALLS")"
check "status 返回 Root Helper 输出" "down" "$out"
check "status 返回 Root Helper exit 码" "26" "$status_rc"

set +e
missing_out="$(HOME="$WORK/home" PATH="$WORK:$PATH" LITEOC_TESTING=1 LITEOC_VPNCTL="$WORK/missing-vpnctl" \
  bash "$CONNECT" status 2>&1)"
missing_rc=$?
set -e
check "Root Helper 缺失时返回明确错误" "3" "$missing_rc"
check_contains "Root Helper 缺失时给出安装器指引" "LiteOC 安装器" "$missing_out"
check_contains "Root Helper 缺失时给出 setup-root 指引" "setup-root.sh" "$missing_out"

check_absent "不再 source Profile 配置" '(^|[;&|[:space:]])source[[:space:]]'
check_absent "不再读取钥匙串" 'security[[:space:]]+find-generic-password|KEYCHAIN_'
check_absent "不再定位或直接调用 openconnect" 'openconnect|/usr/local/libexec/liteoc|/opt/homebrew/bin'
check_absent "不再拼 openconnect stdin 协议" 'passwd-on-stdin|servercert|--user='
cleanup_contract="$(sed -n '/^cleanup()/,/^}/p' "$CONNECT")"
trap_line="$(printf '%s\n' "$cleanup_contract" | grep -n "trap '' INT HUP TERM" | cut -d: -f1)"
stop_line="$(printf '%s\n' "$cleanup_contract" | grep -n 'sudo .* stop ' | cut -d: -f1)"
check "cleanup 在 stop 前屏蔽中断信号" "yes" "$([ -n "$trap_line" ] && [ -n "$stop_line" ] && [ "$trap_line" -lt "$stop_line" ] && printf yes || printf no)"
check_contains "cleanup 状态防止 stop 重入" "cleaning|done" "$cleanup_contract"

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" = 0 ]
