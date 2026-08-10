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

printf '\n%d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" = 0 ]
