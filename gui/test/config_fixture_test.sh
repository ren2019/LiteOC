#!/bin/sh
# Shared config fixture contract: exercise AppConfig.load and real vpnctl start.
set -eu

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
GUI_DIR="$(cd "$TEST_DIR/.." && pwd)"
FIXTURE="$TEST_DIR/fixtures/config_parser.conf"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SWIFT_SDK="${LITEOC_SWIFT_SDK:-}"
export CLANG_MODULE_CACHE_PATH="$WORK/module-cache" SWIFT_MODULE_CACHE_PATH="$WORK/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
if [ -n "$SWIFT_SDK" ]; then
  swiftc -sdk "$SWIFT_SDK" -target arm64-apple-macosx12.0 \
    "$GUI_DIR/AppConfig.swift" "$TEST_DIR/config_fixture/main.swift" -o "$WORK/read-app-config"
else
  swiftc -target arm64-apple-macosx12.0 \
    "$GUI_DIR/AppConfig.swift" "$TEST_DIR/config_fixture/main.swift" -o "$WORK/read-app-config"
fi
"$WORK/read-app-config" "$FIXTURE" > "$WORK/app-values"

export ROOT_VALUES="$WORK/root-values" ROOT_STDIN="$WORK/root-stdin"
export LITEOC_OPENCONNECT_BIN="$WORK/openconnect"
export LITEOC_ROUTE_STATE_FILE="$WORK/owned-routes"

cat > "$WORK/pgrep" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$WORK/dscacheutil" <<'EOF'
#!/bin/sh
printf 'name: vpn.fixture.example\nip_address: 203.0.113.16\n'
EOF
cat > "$WORK/route" <<'EOF'
#!/bin/sh
case "$*" in
  "-n get 203.0.113.16")
    printf '   route to: 203.0.113.16\ndestination: default\n    gateway: 192.168.1.1\n  interface: en0\n      flags: <UP,GATEWAY,STATIC>\n'
    ;;
  *) exit 1 ;;
esac
EOF
cat > "$LITEOC_OPENCONNECT_BIN" <<'EOF'
#!/bin/sh
IFS= read -r pin
IFS= read -r group
: "$pin"
host="" user="" cert=""
for arg do
  case "$arg" in
    --user=*) user="${arg#--user=}" ;;
    --servercert=*) cert="${arg#--servercert=}" ;;
    https://*) host="${arg#https://}" ;;
  esac
done
printf 'HOST=%s\nUSER=%s\nGROUP=%s\nSERVERCERT=%s\n' \
  "$host" "$user" "$group" "$cert" > "$ROOT_VALUES"
printf '%s\n%s\n' "$pin" "$group" > "$ROOT_STDIN"
EOF
chmod +x "$WORK/pgrep" "$WORK/dscacheutil" "$WORK/route" "$LITEOC_OPENCONNECT_BIN"

printf 'fixture-pin\n' | PATH="$WORK:$PATH" LITEOC_TESTING=1 \
  LITEOC_LOG="$WORK/openconnect.log" \
  sh "$GUI_DIR/vpnctl" start "$FIXTURE" > "$WORK/vpnctl-output"

pass=0
fail=0
check() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}
value_for() {
  grep "^$1=" "$2" | head -1 | cut -d= -f2-
}
expected_for() {
  case "$1" in
    HOST) printf '%s\n' 'vpn.fixture.example:8443' ;;
    USER) printf '%s\n' 'operator=west' ;;
    GROUP) printf '%s\n' 'engineering' ;;
    SERVERCERT) printf '%s\n' 'pin-sha256:AbCdEf+/0123==' ;;
  esac
}

echo "== App / Root Helper shared config fixture =="
for key in HOST USER GROUP SERVERCERT; do
  expected="$(expected_for "$key")"
  app_value="$(value_for "$key" "$WORK/app-values")"
  root_value="$(value_for "$key" "$ROOT_VALUES")"
  check "AppConfig.load 解析 $key" "$expected" "$app_value"
  check "vpnctl start 解析 $key" "$expected" "$root_value"
  check "双端 $key 口径一致" "$app_value" "$root_value"
done
check "Root Helper start 成功" "started" "$(cat "$WORK/vpnctl-output")"
check "fixture PIN 与 group 经 stdin 分行传递" "fixture-pin
engineering" "$(cat "$ROOT_STDIN")"

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" = 0 ]
