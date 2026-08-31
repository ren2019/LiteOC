#!/bin/sh
set -eu

if [ "${LITEOC_VERSION+x}" = x ]; then
  # 显式指定 (CI Artifact 固定传 0.0.0); 空值按 0.0.0 处理 (release_gate_test 契约)
  version="${LITEOC_VERSION:-0.0.0}"
else
  # 未指定: 读取最新 Git tag (gui/README.md 约定); 非 git 环境或无 tag 回退 0.0.0
  version="$(git describe --tags --abbrev=0 2>/dev/null || printf '0.0.0')"
fi
version="${version#v}"
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || {
  printf 'invalid LiteOC version: %s\n' "$version" >&2
  exit 1
}
printf '%s\n' "$version"
