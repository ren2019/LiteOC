#!/bin/sh
set -eu

GUI_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SWIFT_SDK="${LITEOC_SWIFT_SDK:-}"
export CLANG_MODULE_CACHE_PATH="$WORK/module-cache" SWIFT_MODULE_CACHE_PATH="$WORK/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
if [ -n "$SWIFT_SDK" ]; then
  swiftc -sdk "$SWIFT_SDK" -target arm64-apple-macosx12.0 -whole-module-optimization \
    "$GUI_DIR/MenuPresentation.swift" "$GUI_DIR/VpnctlClient.swift" "$GUI_DIR/TunnelReducer.swift" \
    "$GUI_DIR/test/tunnel_events/main.swift" -o "$WORK/tunnel-events-test"
else
  swiftc -target arm64-apple-macosx12.0 -whole-module-optimization \
    "$GUI_DIR/MenuPresentation.swift" "$GUI_DIR/VpnctlClient.swift" "$GUI_DIR/TunnelReducer.swift" \
    "$GUI_DIR/test/tunnel_events/main.swift" -o "$WORK/tunnel-events-test"
fi
"$WORK/tunnel-events-test"
