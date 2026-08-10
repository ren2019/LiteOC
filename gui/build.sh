#!/bin/sh
# 编译 + 生成图标 + 打包 LiteOC.app (无需 sudo)
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"; cd "$DIR"
APPNAME="LiteOC"
VER="${LITEOC_VERSION:-}"
VER="${VER#v}"
if [ -z "$VER" ]; then
  TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  VER="${TAG#v}"; VER="${VER:-0.0.0}"
fi
BINDIR="$DIR/build"; APP="$BINDIR/$APPNAME.app"

# 可用环境变量覆盖 SDK；默认沿用当前 Xcode/Command Line Tools 的匹配 SDK。
SWIFT_SDK="${LITEOC_SWIFT_SDK:-}"
SWIFT_CACHE="${TMPDIR:-/tmp}/liteoc-swift-module-cache"
mkdir -p "$SWIFT_CACHE"
export CLANG_MODULE_CACHE_PATH="$SWIFT_CACHE" SWIFT_MODULE_CACHE_PATH="$SWIFT_CACHE"
run_swift() {
  if [ -n "$SWIFT_SDK" ]; then swift -sdk "$SWIFT_SDK" -target arm64-apple-macosx12.0 "$@"; else swift -target arm64-apple-macosx12.0 "$@"; fi
}
run_swiftc() {
  if [ -n "$SWIFT_SDK" ]; then swiftc -sdk "$SWIFT_SDK" -target arm64-apple-macosx12.0 "$@"; else swiftc -target arm64-apple-macosx12.0 "$@"; fi
}

echo "→ 生成 App 图标…"
run_swift make_icon.swift
mkdir -p AppIcon.iconset
sips -z 16 16   icon_1024.png --out AppIcon.iconset/icon_16x16.png      >/dev/null
sips -z 32 32   icon_1024.png --out AppIcon.iconset/icon_16x16@2x.png   >/dev/null
sips -z 32 32   icon_1024.png --out AppIcon.iconset/icon_32x32.png      >/dev/null
sips -z 64 64   icon_1024.png --out AppIcon.iconset/icon_32x32@2x.png   >/dev/null
sips -z 128 128 icon_1024.png --out AppIcon.iconset/icon_128x128.png    >/dev/null
sips -z 256 256 icon_1024.png --out AppIcon.iconset/icon_128x128@2x.png  >/dev/null
sips -z 256 256 icon_1024.png --out AppIcon.iconset/icon_256x256.png    >/dev/null
sips -z 512 512 icon_1024.png --out AppIcon.iconset/icon_256x256@2x.png  >/dev/null
sips -z 512 512 icon_1024.png --out AppIcon.iconset/icon_512x512.png    >/dev/null
cp icon_1024.png AppIcon.iconset/icon_512x512@2x.png
if ! iconutil -c icns AppIcon.iconset -o AppIcon.icns; then
  echo "  iconutil 无法打包,改用 Swift ICNS 兼容路径…"
  run_swift make_icns.swift
fi

echo "→ 生成菜单栏图标 (彩色/灰色)…"
run_swift make_menubar.swift

echo "→ 编译 Swift…"
mkdir -p "$BINDIR"
run_swiftc main.swift MenuPresentation.swift -o "$BINDIR/$APPNAME" -framework Cocoa -framework ServiceManagement

echo "→ 打包 .app …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINDIR/$APPNAME" "$APP/Contents/MacOS/$APPNAME"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp menubar_color.png "$APP/Contents/Resources/menubar_color.png"
cp menubar_gray.png "$APP/Contents/Resources/menubar_gray.png"
cp menubar_spinner.png "$APP/Contents/Resources/menubar_spinner.png"
cp menubar_red.png "$APP/Contents/Resources/menubar_red.png"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APPNAME</string>
  <key>CFBundleDisplayName</key><string>$APPNAME</string>
  <key>CFBundleIdentifier</key><string>local.liteoc.app</string>
  <key>CFBundleExecutable</key><string>$APPNAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VER</string>
  <key>CFBundleVersion</key><string>$VER</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

echo "→ ad-hoc 签名…"
codesign -s - --force --deep "$APP" >/dev/null 2>&1 || echo "  (签名跳过)"
echo "✅ 打包完成: $APP"
