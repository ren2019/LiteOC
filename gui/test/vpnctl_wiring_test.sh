#!/bin/sh
# App / VpnctlClient wiring contract: protocol words stay in the adapter only.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT/gui/main.swift"
BUILD="$ROOT/gui/build.sh"

pass=0
fail=0

check_absent() {
  if grep -Eq -- "$2" "$MAIN"; then
    fail=$((fail + 1)); printf '  FAIL %s\n       forbidden pattern: %s\n' "$1" "$2"
  else
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  fi
}

check_contains() {
  if grep -Fq -- "$2" "$3"; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n       missing: %s\n' "$1" "$2"
  fi
}

check_equal() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

echo "== App / VpnctlClient wiring contract =="

check_absent "main.swift 不复述 Root Helper 输出 token" \
  '"(down|route-stale|route-check-failed|connecting|connected|config-error:缺|started|auth-failed|no-pin|already-running|cert-discover-failed|openconnect-not-found|route-cleanup-failed|stop-timeout|stopped|not-running|route-repaired|route-clean|network-unavailable|network |discovered-cert:)'
check_absent "main.swift 不保留 controlToken 白名单解析" 'controlToken'
check_absent "main.swift 不直接 spawn vpnctl" 'run\("/usr/bin/sudo", \[VPNCTL'
check_contains "App 构建输入包含 VpnctlClient.swift" "VpnctlClient.swift" "$BUILD"

connected_snapshot_exits="$(awk '
  /^        case \.connecting:$/ { inConnecting = 1; next }
  inConnecting && /^        case \.connected:$/ { exit }
  inConnecting && /case let \.connected\(ip: ip\):/ { inConnectedSnapshot = 1 }
  inConnectedSnapshot && !/case let \.connected\(ip: ip\):/ && /^            case / { inConnectedSnapshot = 0 }
  inConnectedSnapshot && /enter\(\.connected, ip: ip\)/ { entered = 1 }
  inConnectedSnapshot && /return/ { returned = 1 }
  END { print entered && returned ? "yes" : "no" }
' "$MAIN")"
check_equal "connected 快照优先于 connecting 超时" "yes" "$connected_snapshot_exits"

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" = 0 ]
