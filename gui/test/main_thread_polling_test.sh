#!/bin/sh
# Polling must never run the privileged helper on the AppKit main thread.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT/gui/main.swift"
POLLING="$ROOT/gui/TunnelPolling.swift"
BUILD="$ROOT/gui/build.sh"
TEST_MAIN="$ROOT/gui/test/main_thread_polling/main.swift"
SDK="${LITEOC_SWIFT_SDK:-}"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/liteoc-main-thread-polling.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM
BIN="$TEST_TMP/main-thread-polling-test"
export LITEOC_TEST_TMP="$TEST_TMP"
export CLANG_MODULE_CACHE_PATH="$TEST_TMP/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="$TEST_TMP/swift-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULE_CACHE_PATH"
pass=0
fail=0

check_contains() {
  if grep -Eq -- "$2" "$3"; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n       missing: %s\n' "$1" "$2"
  fi
}

check_absent_text() {
  if printf '%s\n' "$3" | grep -Eq -- "$2"; then
    fail=$((fail + 1)); printf '  FAIL %s\n       forbidden pattern: %s\n' "$1" "$2"
  else
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  fi
}

check_contains_text() {
  if printf '%s\n' "$3" | grep -Eq -- "$2"; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n       missing: %s\n' "$1" "$2"
  fi
}

check_count() {
  actual="$(grep -Ec -- "$2" "$3" || true)"
  if [ "$actual" = "$4" ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n       expected count: %s\n       actual count:   %s\n' "$1" "$4" "$actual"
  fi
}

echo "== App polling architecture contract =="

tick_body="$(sed -n '/@objc func tick()/,/^    func readPollSample/p' "$MAIN")"
interpreter_body="$(sed -n '/func interpret(_ effects:/,/^    func readNetwork()/p' "$MAIN")"
network_effect_body="$(sed -n '/func readNetworkEffect(/,/^    func performPrimaryMenuAction()/p' "$MAIN")"
reschedule_body="$(sed -n '/func reschedule()/,/^    func updateStatePresentation/p' "$MAIN")"
config_saved_body="$(sed -n '/configWin = ConfigWindow(service: service)/,/^            }/p' "$MAIN")"
invalidation_body="$(sed -n '/func invalidateBackgroundReads()/,/^    }/p' "$MAIN")"

check_absent_text "tick never calls status synchronously" 'vpnctl\.status\(' "$tick_body"
check_absent_text "tick never calls network synchronously" 'vpnctl\.network\(|readNetwork\(' "$tick_body"
check_contains_text "tick delegates one background poll" 'poller\.request' "$tick_body"
check_contains "periodic polls have a queue independent from control effects" \
  'let pollQueue = DispatchQueue' "$MAIN"
check_contains "poller uses the independent poll queue" \
  'TunnelPoller\(workerQueue: pollQueue\)' "$MAIN"
check_absent_text "captureFingerprint never reads the helper synchronously" \
  'fingerprintRead\(readNetwork\(\)\)' "$interpreter_body"
check_absent_text "readConnectionNetwork never reads the helper synchronously" \
  'connectionNetworkRead\(readNetwork\(\)\)' "$interpreter_body"
check_contains "network effects ignore results for a replaced reducer context" \
  'reducerContext == expectedContext' /dev/stdin <<EOF
$network_effect_body
EOF
check_contains "network effects use a single-flight coordinator" \
  'networkReader\.request' "$MAIN"
check_contains_text "config and PIN saves call the background-read invalidator" \
  'self\?\.invalidateBackgroundReads\(\)' "$config_saved_body"
check_contains_text "save invalidation advances the poll generation" \
  'poller\.invalidate\(\)' "$invalidation_body"
check_contains_text "save invalidation advances the network-read generation" \
  'networkReader\.invalidate\(\)' "$invalidation_body"
check_contains "App build links the polling module" 'TunnelPolling.swift' "$BUILD"
check_count "App keeps a single polling timer" '#selector\(tick\)' "$MAIN" 1
check_count "menu bar icon animation runs on its own timer" '#selector\(iconFrameTick\)' "$MAIN" 1
check_contains_text "connecting keeps the 0.5s polling interval" \
  'state == \.connecting.*\? 0\.5 : 4\.0' "$reschedule_body"

echo
if [ ! -f "$POLLING" ]; then
  fail=$((fail + 1))
  printf '  FAIL slow fake helper contract\n       missing polling seam: %s\n' "$POLLING"
else
  if [ -n "$SDK" ]; then
    swiftc -parse-as-library -sdk "$SDK" -target arm64-apple-macosx12.0 \
      "$ROOT/gui/VpnctlClient.swift" "$POLLING" "$TEST_MAIN" -o "$BIN"
  else
    swiftc -parse-as-library -target arm64-apple-macosx12.0 \
      "$ROOT/gui/VpnctlClient.swift" "$POLLING" "$TEST_MAIN" -o "$BIN"
  fi
  compile_status=$?
  if [ "$compile_status" -ne 0 ]; then
    fail=$((fail + 1)); printf '  FAIL polling contract compilation\n'
  elif "$BIN"; then
    pass=$((pass + 1)); printf '  ok   polling contract executable\n'
  else
    fail=$((fail + 1)); printf '  FAIL polling contract executable\n'
  fi
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
