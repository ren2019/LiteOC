#!/bin/sh
set -eu

GUI_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SWIFT_SDK="${LITEOC_SWIFT_SDK:-}"
export CLANG_MODULE_CACHE_PATH="$WORK/module-cache" SWIFT_MODULE_CACHE_PATH="$WORK/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
if [ -n "$SWIFT_SDK" ]; then
  swiftc -sdk "$SWIFT_SDK" -target arm64-apple-macosx12.0 \
    "$GUI_DIR/MenuPresentation.swift" "$GUI_DIR/MenuBarIcon.swift" "$GUI_DIR/test/menu_bar_icon/main.swift" -o "$WORK/menu-bar-icon-test"
else
  swiftc -target arm64-apple-macosx12.0 \
    "$GUI_DIR/MenuPresentation.swift" "$GUI_DIR/MenuBarIcon.swift" "$GUI_DIR/test/menu_bar_icon/main.swift" -o "$WORK/menu-bar-icon-test"
fi
"$WORK/menu-bar-icon-test"
