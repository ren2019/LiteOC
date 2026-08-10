#!/bin/sh
set -eu

version="${LITEOC_VERSION:-0.0.0}"
version="${version#v}"
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || {
  printf 'invalid LiteOC version: %s\n' "$version" >&2
  exit 1
}
printf '%s\n' "$version"
