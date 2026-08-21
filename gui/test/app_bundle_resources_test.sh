#!/bin/sh
# App bundle resources must be derived from build inputs, not ignored checkout history.
set -eu

GUI_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STALE_SPINNER="$GUI_DIR/menubar_spinner.png"
WORK="$(mktemp -d)"
HAD_STALE=0

if [ -e "$STALE_SPINNER" ]; then
  HAD_STALE=1
  cp "$STALE_SPINNER" "$WORK/original-menubar-spinner.png"
fi

cleanup() {
  if [ "$HAD_STALE" = 1 ]; then
    cp "$WORK/original-menubar-spinner.png" "$STALE_SPINNER"
  else
    rm -f "$STALE_SPINNER"
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# Simulate a worktree that retained the old ignored generator output.
printf 'stale ignored spinner fixture\n' > "$STALE_SPINNER"

sh "$GUI_DIR/build.sh"

test -e "$STALE_SPINNER"
if find "$GUI_DIR/build/LiteOC.app" -name 'menubar_spinner*' | grep -q .; then
  printf 'FAIL stale menubar spinner leaked into the App bundle\n' >&2
  exit 1
fi

printf 'ok stale ignored spinner does not enter the App bundle\n'
