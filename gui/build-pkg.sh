#!/bin/sh
# 打包 LiteOC-<ver>.pkg —— 双击安装,全程无需终端。
# postinstall 以 root 完成:写免密 sudoers(仅 vpnctl)+ 校验关键产物。
# 前置: gui/build/LiteOC.app (build.sh) + gui/build/oc-bundle (dylibbundler 自包含 openconnect) 已就绪
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"; cd "$DIR"
VER="$(sh "$DIR/version.sh")"
APP="$DIR/build/LiteOC.app"; OC="$DIR/build/oc-bundle"
[ -d "$APP" ] || { echo "❌ 缺 $APP(先跑 ./build.sh)"; exit 1; }
[ -d "$OC" ]  || { echo "❌ 缺 $OC(先跑 oc-bundle 构建)"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/root"
mkdir -p "$ROOT/Applications" "$ROOT/usr/local/sbin" "$ROOT/usr/local/libexec/liteoc"
cp -R "$APP" "$ROOT/Applications/"
cp "$DIR/vpnctl" "$ROOT/usr/local/sbin/vpnctl"; chmod 755 "$ROOT/usr/local/sbin/vpnctl"
cp -R "$OC/." "$ROOT/usr/local/libexec/liteoc/"; chmod 755 "$ROOT/usr/local/libexec/liteoc/openconnect"

SC="$TMP/scripts"; mkdir -p "$SC"
cat > "$SC/postinstall" <<'EOF'
#!/bin/sh
# LiteOC 安装后(root 运行):写免密 sudoers(仅锁 vpnctl 单一路径)+ 校验关键产物
USER_="$(stat -f%Su /dev/console 2>/dev/null || true)"
[ -n "$USER_" ] || USER_=root
echo "$USER_ ALL=(root) NOPASSWD: /usr/local/sbin/vpnctl" > /etc/sudoers.d/vpnctl
chmod 0440 /etc/sudoers.d/vpnctl
visudo -cf /etc/sudoers.d/vpnctl >/dev/null || { echo "❌ sudoers 语法错"; exit 1; }
[ -x /usr/local/sbin/vpnctl ] || { echo "❌ vpnctl 缺失"; exit 1; }
[ -x /usr/local/libexec/liteoc/openconnect ] || { echo "❌ 内置 openconnect 缺失"; exit 1; }
echo "✅ LiteOC 安装完成:App 在 /Applications;vpnctl + 内置 openconnect 已就位,免密 sudoers 已写。"
exit 0
EOF
chmod 755 "$SC/postinstall"

OUT="$DIR/build/LiteOC-$VER.pkg"
pkgbuild --root "$ROOT" --identifier local.liteoc.pkg --version "$VER" \
  --scripts "$SC" --ownership recommended "$OUT"
echo "✅ 打包完成: $OUT"
