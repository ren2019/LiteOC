#!/bin/sh
# Read-only CI gate for release notes and built artifacts.
set -eu

die() {
  printf 'release-gate: %s\n' "$1" >&2
  exit 1
}

validate_tag() {
  printf '%s\n' "$1" | grep -Eq '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' || die "invalid release tag: $1"
}

version_is_greater() {
  awk -v current="$1" -v previous="$2" '
    function part(version, position, values) {
      split(version, values, ".")
      return values[position] + 0
    }
    BEGIN {
      for (i = 1; i <= 3; i++) {
        left = part(current, i)
        right = part(previous, i)
        if (left > right) exit 0
        if (left < right) exit 1
      }
      exit 1
    }
  '
}

check_notes() {
  tag="$1"
  previous_tag="$2"
  notes="$3"
  validate_tag "$tag"
  validate_tag "$previous_tag"
  [ -f "$notes" ] || die "release notes not found: $notes"
  version_is_greater "${tag#v}" "${previous_tag#v}" || die "$tag must be newer than $previous_tag"

  LC_ALL=C awk -v tag="$tag" -v previous_tag="$previous_tag" '
    function problem(message) {
      print "release-gate: " message > "/dev/stderr"
      failed = 1
    }
    NR == 1 && $0 != "# LiteOC " tag { problem("first heading must be # LiteOC " tag) }
    $0 == "## 中文" {
      zh_heading++
      zh_line = NR
      section = "zh"
      stage = "summary"
      next
    }
    $0 == "### 用户可感知变化" && section == "zh" {
      zh_changes_heading++
      stage = "changes"
      next
    }
    $0 == "### 验证" && section == "zh" {
      zh_verification_heading++
      stage = "verification"
      next
    }
    $0 == "## English" {
      en_heading++
      en_line = NR
      section = "en"
      stage = "summary"
      next
    }
    $0 == "### User-visible changes" && section == "en" {
      en_changes_heading++
      stage = "changes"
      next
    }
    $0 == "### Verification" && section == "en" {
      en_verification_heading++
      stage = "verification"
      next
    }
    $0 == "## Full Changelog" {
      changelog_heading++
      changelog_line = NR
      section = "changelog"
      stage = ""
      next
    }
    /^## / {
      section = ""
      stage = ""
      next
    }
    section == "zh" && stage == "summary" && NF { zh_summary++ }
    section == "en" && stage == "summary" && NF { en_summary++ }
    section == "zh" && stage == "changes" && /^- / { zh_changes++ }
    section == "en" && stage == "changes" && /^- / { en_changes++ }
    section == "zh" && stage == "verification" && /^- / { zh_verification++ }
    section == "en" && stage == "verification" && /^- / { en_verification++ }
    section == "changelog" && $0 == "https://github.com/ren2019/LiteOC/compare/" previous_tag "..." tag { changelog_url++ }
    END {
      if (zh_heading != 1 || en_heading != 1 || changelog_heading != 1) problem("require one Chinese, English, and Full Changelog section")
      if (!(zh_line < en_line && en_line < changelog_line)) problem("sections must be ordered Chinese, English, Full Changelog")
      if (zh_summary < 1 || en_summary < 1) problem("both language sections require a summary")
      if (zh_changes_heading != 1 || zh_changes < 2 || zh_changes > 5) problem("Chinese user-visible changes must contain 2-5 bullets")
      if (en_changes_heading != 1 || en_changes < 2 || en_changes > 5) problem("English user-visible changes must contain 2-5 bullets")
      if (zh_verification_heading != 1 || zh_verification < 1) problem("Chinese verification requires at least one bullet")
      if (en_verification_heading != 1 || en_verification < 1) problem("English verification requires at least one bullet")
      if (changelog_url != 1) problem("Full Changelog URL must compare " previous_tag "..." tag)
      exit failed
    }
  ' "$notes"
}

check_artifacts() {
  identity="$1"
  app="$2"
  pkg="$3"
  if [ "$identity" = "0.0.0" ]; then
    expected="$identity"
  else
    validate_tag "$identity"
    expected="${identity#v}"
  fi
  [ -f "$app/Contents/Info.plist" ] || die "App Info.plist not found: $app"
  [ -f "$pkg" ] || die "package not found: $pkg"
  [ "$(basename "$pkg")" = "LiteOC-$expected.pkg" ] || die "asset name must be LiteOC-$expected.pkg"

  app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null) || die "cannot read App version"
  [ "$app_version" = "$expected" ] || die "App version $app_version does not match $expected"

  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT HUP INT TERM
  pkgutil --expand "$pkg" "$work/expanded" >/dev/null || die "cannot expand package"
  [ -f "$work/expanded/PackageInfo" ] || die "PackageInfo not found"
  pkg_version=$(awk '
    /<pkg-info / && match($0, / version="[^"]*"/) {
      value = substr($0, RSTART + 10, RLENGTH - 11)
      print value
      exit
    }
  ' "$work/expanded/PackageInfo")
  [ -n "$pkg_version" ] || die "cannot read package version"
  [ "$pkg_version" = "$expected" ] || die "package version $pkg_version does not match $expected"
}

check_ancestry() {
  commit="$1"
  main_ref="$2"
  git rev-parse --verify "$commit^{commit}" >/dev/null 2>&1 || die "release commit not found: $commit"
  git rev-parse --verify "$main_ref^{commit}" >/dev/null 2>&1 || die "main ref not found: $main_ref"
  git merge-base --is-ancestor "$commit" "$main_ref" || die "release commit is outside $main_ref history"
}

case "${1:-}" in
  notes)
    [ "$#" -eq 4 ] || die "usage: release-gate.sh notes TAG PREVIOUS_TAG NOTES"
    check_notes "$2" "$3" "$4"
    ;;
  artifacts)
    [ "$#" -eq 4 ] || die "usage: release-gate.sh artifacts TAG APP PKG"
    check_artifacts "$2" "$3" "$4"
    ;;
  ancestry)
    [ "$#" -eq 3 ] || die "usage: release-gate.sh ancestry COMMIT MAIN_REF"
    check_ancestry "$2" "$3"
    ;;
  *)
    die "usage: release-gate.sh {notes|artifacts|ancestry} ..."
    ;;
esac
