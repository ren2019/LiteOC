#!/bin/sh
# App orchestration contract: the delegate consumes TunnelReducer instead of restating transition rules.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT/gui/main.swift"
BUILD="$ROOT/gui/build.sh"
ICON_MODEL="$ROOT/gui/MenuBarIcon.swift"

pass=0
fail=0

check_contains() {
  if grep -Fq -- "$2" "$3"; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n       missing: %s\n' "$1" "$2"
  fi
}

check_absent() {
  if grep -Eq -- "$2" "$3"; then
    fail=$((fail + 1)); printf '  FAIL %s\n       forbidden pattern: %s\n' "$1" "$2"
  else
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
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

echo "== App reducer orchestration contract =="

check_contains "AppDelegate calls the pure reducer" "TunnelReducer.reduce(" "$MAIN"
check_contains "Effect execution has one named interpreter" \
  "func interpret(_ effects: [TunnelReducer.Effect])" "$MAIN"
check_absent "AppDelegate no longer restates the state/snapshot matrix" \
  'switch snapshot|snapshot ==|downStreak \+=|timeIntervalSince' "$MAIN"
check_absent "All phase changes enter through TunnelReducer" \
  '(^|[^[:alnum:]_])enter\(' "$MAIN"
check_absent "AppDelegate never rebuilds reducer Context by hand" \
  'reducerContext = TunnelReducer\.Context' "$MAIN"
check_count "missing config fields are only written by the Effect interpreter" \
  'helperMissingConfigFields = missingFields' "$MAIN" 1
check_contains "menu configuration uses the helper config-error payload" \
  "missingConfigFields: helperMissingConfigFields" "$MAIN"
check_contains "App build links TunnelReducer" "TunnelReducer.swift" "$BUILD"
check_contains "main.swift declares a formal entry point" "@main" "$MAIN"
check_contains "formal entry point owns main()" "static func main()" "$MAIN"
check_absent "main.swift has no top-level app.run()" '^app\.run\(\)$' "$MAIN"
check_contains "Swift build enables the formal entry point" "-parse-as-library" "$BUILD"

check_contains "status item icon comes from the pure dot-matrix icon model" \
  "iconSpec(for: state, isConfigured:" "$MAIN"
check_contains "icon model module is pure logic over TunnelState" \
  "func iconSpec(for state: TunnelState, isConfigured: Bool) -> IconSpec" "$ICON_MODEL"
check_contains "dots are rendered at runtime with a drawing handler" \
  "renderDotIcon(lit:" "$MAIN"
check_contains "busy-state animation advances frames on its own timer" \
  "#selector(iconFrameTick)" "$MAIN"
check_absent "the native spinner is gone" 'NSProgressIndicator|spinner' "$MAIN"
check_absent "the reconnecting blink timer is gone" 'blinkTimer|blinkTick|blinkVisible' "$MAIN"
check_absent "old menubar PNG loading is gone" 'loadImg|menubar_(gray|color|red|yellow)' "$MAIN"
check_absent "hand-rolled frame spinner machinery is gone" \
  'spinnerFrames|spinStep|spinTimer|loadSpinnerFrames|rotateImg|spinTick|startSpin|stopSpin' "$MAIN"
check_absent "dead Swift APPNAME and pinGet shims are gone" '\bAPPNAME\b|\bpinGet\b' "$MAIN"
check_contains "App build links the icon model module" "MenuBarIcon.swift" "$BUILD"
check_absent "menubar PNG assets are no longer packaged" 'menubar_(gray|color|red|yellow|spinner)' "$BUILD"
check_absent "menubar PNG generator is no longer invoked" 'make_menubar' "$BUILD"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
