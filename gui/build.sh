#!/bin/sh
# 编译 + 生成图标 + 打包 LiteOC.app (无需 sudo)
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"; cd "$DIR"
APPNAME="LiteOC"
VER="${LITEOC_VERSION#v}"; VER="${VER:-1.2}"   # CI 传 tag; 本地默认 1.2
BINDIR="$DIR/build"; APP="$BINDIR/$APPNAME.app"

echo "→ 生成 App 图标…"
swift make_icon.swift
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
iconutil -c icns AppIcon.iconset -o AppIcon.icns

echo "→ 生成菜单栏图标 (彩色/灰色)…"
swift make_menubar.swift

echo "→ 编译 Swift…"
mkdir -p "$BINDIR"
swiftc main.swift -o "$BINDIR/$APPNAME" -framework Cocoa

echo "→ 打包 .app …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINDIR/$APPNAME" "$APP/Contents/MacOS/$APPNAME"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp menubar_color.png "$APP/Contents/Resources/menubar_color.png"
cp menubar_gray.png "$APP/Contents/Resources/menubar_gray.png"
cp menubar_yellow.png "$APP/Contents/Resources/menubar_yellow.png"
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
