#!/bin/sh
# Release Gate 契约测试：只通过公开脚本接口验证发布说明与产物版本。
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/scripts/release-gate.sh"
VERSION="$ROOT/gui/version.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

check_equal() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

check_ok() {
  desc="$1"; shift
  if "$@" >"$WORK/output" 2>&1; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$desc"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n' "$desc"; sed 's/^/       /' "$WORK/output"
  fi
}

check_fails() {
  desc="$1"; shift
  if "$@" >"$WORK/output" 2>&1; then
    fail=$((fail + 1)); printf '  FAIL %s\n       command unexpectedly succeeded\n' "$desc"
  else
    pass=$((pass + 1)); printf '  ok   %s\n' "$desc"
  fi
}

write_valid_notes() {
  target="$1"
  sed "s/__TAG__/$2/g; s/__PREVIOUS__/$3/g" >"$target" <<'EOF'
# LiteOC __TAG__

## 中文

本版本让网络切换后的 VPN 恢复更加可靠。

### 用户可感知变化

- 自动修复过期的 VPN 网关路由。
- 断开失败时显示明确错误。

### 验证

- 通过 vpnctl 契约测试与安装包版本检查。

## English

This release makes VPN recovery after network changes more reliable.

### User-visible changes

- Automatically repairs stale VPN gateway routes.
- Shows a clear error when disconnect cleanup fails.

### Verification

- Passed the vpnctl contracts and package-version checks.

## Full Changelog

https://github.com/ren2019/LiteOC/compare/__PREVIOUS__...__TAG__
EOF
}

echo "== Release Gate 契约 =="

NOTES="$WORK/RELEASE_NOTES.md"
write_valid_notes "$NOTES" v1.6 v1.5
check_ok "完整双语发布说明通过 gate" sh "$GATE" notes v1.6 v1.5 "$NOTES"
check_fails "缺少发布说明文件时拒绝发布" sh "$GATE" notes v1.6 v1.5 "$WORK/missing.md"

sed 's/# LiteOC v1.6/# LiteOC v1.7/' "$NOTES" >"$WORK/wrong-version.md"
check_fails "说明版本与 tag 不一致时拒绝发布" sh "$GATE" notes v1.6 v1.5 "$WORK/wrong-version.md"

sed '/^## English$/,/^## Full Changelog$/d' "$NOTES" >"$WORK/no-english.md"
check_fails "缺少英文正文时拒绝发布" sh "$GATE" notes v1.6 v1.5 "$WORK/no-english.md"

awk '
  $0 == "## 中文" { print; skip = 1; next }
  $0 == "## English" { skip = 0 }
  !skip { print }
' "$NOTES" >"$WORK/empty-chinese.md"
check_fails "中文正文为空时拒绝发布" sh "$GATE" notes v1.6 v1.5 "$WORK/empty-chinese.md"

printf '# LiteOC v1.6\n\n## Full Changelog\n\nhttps://github.com/ren2019/LiteOC/compare/v1.5...v1.6\n' >"$WORK/link-only.md"
check_fails "只有 Full Changelog 时拒绝发布" sh "$GATE" notes v1.6 v1.5 "$WORK/link-only.md"

check_fails "版本没有向前推进时拒绝发布" sh "$GATE" notes v1.5 v1.5 "$NOTES"
check_fails "非版本 tag 不能触发发布" sh "$GATE" notes latest v1.5 "$NOTES"

REPO="$WORK/repo"
git init -q "$REPO"
git -C "$REPO" -c user.name=Test -c user.email=test@example.com commit --allow-empty -q -m main
git -C "$REPO" branch -M main
main_commit=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" switch -q -c release-candidate
git -C "$REPO" -c user.name=Test -c user.email=test@example.com commit --allow-empty -q -m candidate
candidate_commit=$(git -C "$REPO" rev-parse HEAD)
check_ok "main 历史内的 tag commit 通过 gate" sh -c 'cd "$1" && sh "$2" ancestry "$3" main' sh "$REPO" "$GATE" "$main_commit"
check_fails "main 历史外的 tag commit 被拒绝" sh -c 'cd "$1" && sh "$2" ancestry "$3" main' sh "$REPO" "$GATE" "$candidate_commit"

check_equal "无显式版本的 CI Artifact 固定为 0.0.0" "0.0.0" "$(LITEOC_VERSION= sh "$VERSION")"
check_equal "release tag 规范化为 App/PKG 版本" "1.6" "$(LITEOC_VERSION=v1.6 sh "$VERSION")"
check_fails "非法构建版本被拒绝" env LITEOC_VERSION=next sh "$VERSION"

APP="$WORK/LiteOC.app"
mkdir -p "$APP/Contents"
sed 's/__VERSION__/1.6/' >"$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>__VERSION__</string>
</dict></plist>
EOF
PKG="$WORK/LiteOC-1.6.pkg"
pkgbuild --nopayload --identifier local.liteoc.test --version 1.6 "$PKG" >/dev/null
check_ok "tag、App、PKG 与 asset 名版本一致时通过" sh "$GATE" artifacts v1.6 "$APP" "$PKG"

sed 's/<string>1.6<\//<string>1.5<\//' "$APP/Contents/Info.plist" >"$WORK/Info.plist"
mv "$WORK/Info.plist" "$APP/Contents/Info.plist"
check_fails "App 版本漂移时拒绝发布" sh "$GATE" artifacts v1.6 "$APP" "$PKG"

sed 's/<string>1.5<\//<string>1.6<\//' "$APP/Contents/Info.plist" >"$WORK/Info.plist"
mv "$WORK/Info.plist" "$APP/Contents/Info.plist"
pkgbuild --nopayload --identifier local.liteoc.test --version 1.5 "$PKG" >/dev/null
check_fails "PKG 版本漂移时拒绝发布" sh "$GATE" artifacts v1.6 "$APP" "$PKG"

sed 's/<string>1.6<\//<string>0.0.0<\//' "$APP/Contents/Info.plist" >"$WORK/Info.plist"
mv "$WORK/Info.plist" "$APP/Contents/Info.plist"
PKG="$WORK/LiteOC-0.0.0.pkg"
pkgbuild --nopayload --identifier local.liteoc.test --version 0.0.0 "$PKG" >/dev/null
check_ok "PR/main 的 App 与 PKG 以 0.0.0 通过身份检查" sh "$GATE" artifacts 0.0.0 "$APP" "$PKG"

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" = 0 ]
