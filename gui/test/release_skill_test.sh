#!/bin/sh
# Cross-client skill contract: one canonical, Git-tracked, explicit-only skill.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLAUDE_SKILL="$ROOT/.claude/skills/release"
CODEX_SKILL="$ROOT/.agents/skills/release"

pass=0
fail=0

check() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
  fi
}

echo "== Release Skill 双端契约 =="

check "Claude canonical skill 存在" yes "$([ -f "$CLAUDE_SKILL/SKILL.md" ] && printf yes || printf no)"
check "Codex alias 是符号链接" yes "$([ -L "$CODEX_SKILL" ] && printf yes || printf no)"
check "两个客户端解析到同一 canonical skill" "$(cd "$CLAUDE_SKILL" && pwd -P)" "$(cd "$CODEX_SKILL" && pwd -P)"
check "Claude 禁止模型隐式调用" yes "$(grep -Eq '^disable-model-invocation:[[:space:]]*true$' "$CLAUDE_SKILL/SKILL.md" && printf yes || printf no)"
check "Codex 禁止隐式调用" yes "$(grep -Eq '^  allow_implicit_invocation:[[:space:]]*false$' "$CLAUDE_SKILL/agents/openai.yaml" && printf yes || printf no)"
check "Codex 默认提示显式引用 release" yes "$(grep -Fq '$release' "$CLAUDE_SKILL/agents/openai.yaml" && printf yes || printf no)"
check "Skill 保持 instruction-only" no "$([ -d "$CLAUDE_SKILL/scripts" ] && printf yes || printf no)"
check "Skill 脚手架无 TODO 残留" no "$(grep -Rq 'TODO' "$CLAUDE_SKILL" && printf yes || printf no)"

accept_line="$(grep -n '^## 4\. Accept$' "$CLAUDE_SKILL/SKILL.md" | cut -d: -f1 || true)"
close_line="$(grep -n '^## 5\. Close released issues$' "$CLAUDE_SKILL/SKILL.md" | cut -d: -f1 || true)"
preflight_section="$(sed -n '/^## 1\. Preflight$/,/^## 2\. Prepare$/p' "$CLAUDE_SKILL/SKILL.md")"
close_section="$(sed -n '/^## 5\. Close released issues$/,$p' "$CLAUDE_SKILL/SKILL.md")"
check "Issue 目标在发布前证明" yes "$(printf '%s\n' "$preflight_section" | grep -Fq 'issue closure set' && printf yes || printf no)"
check "Issue 只在发布验收后关闭" yes "$([ -n "$accept_line" ] && [ -n "$close_line" ] && [ "$close_line" -gt "$accept_line" ] && printf yes || printf no)"
check "Issue 以 completed 原因关闭" yes "$(printf '%s\n' "$close_section" | grep -Fq -- '--reason completed' && printf yes || printf no)"
check "Issue 关闭评论引用 Release URL" yes "$(printf '%s\n' "$close_section" | grep -Fq 'Release URL' && printf yes || printf no)"
check "Issue 关闭后回读状态" yes "$(printf '%s\n' "$close_section" | grep -Fq 'stateReason' && printf '%s\n' "$close_section" | grep -Fq 'COMPLETED' && printf yes || printf no)"
check "未证明属于本次发布的 Issue 保持原状" yes "$(printf '%s\n' "$preflight_section" | grep -Fq 'unproven issue' && printf '%s\n' "$preflight_section" | grep -Fq 'unchanged' && printf yes || printf no)"

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" = 0 ]
