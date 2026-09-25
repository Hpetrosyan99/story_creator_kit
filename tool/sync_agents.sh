#!/usr/bin/env bash
# Regenerate every tool-specific agent-instruction file from AGENTS.md.
#
# AGENTS.md is the single source. Codex, Zed, Amp and Jules read it
# natively; the files below exist because their tools look somewhere else.
#
#   ./tool/sync_agents.sh            regenerate
#   ./tool/sync_agents.sh --check    fail if any generated file is stale (CI)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SOURCE="AGENTS.md"
[ -f "$SOURCE" ] || { echo "error: $SOURCE not found"; exit 1; }

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

BANNER_MD='<!-- GENERATED FILE — DO NOT EDIT. Source: AGENTS.md. Regenerate: ./tool/sync_agents.sh -->'

OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

# --- CLAUDE.md -------------------------------------------------------------
# Claude Code resolves `@path` as an import, so the body stays in one file.
mkdir -p "$OUT_DIR"
cat > "$OUT_DIR/CLAUDE.md" <<EOF
# CLAUDE.md

$BANNER_MD

@AGENTS.md

## Claude Code specifics

The rules above are the whole contract — this section only covers Claude-only wiring.

- **Commands** in \`.claude/commands/\`: \`/sync-agents\`, \`/review-pr\`, \`/review-codequality\`, \`/review-functional-logic\`, \`/review-security-performance\`, \`/context-prime\`.
- **Agents** in \`.claude/agents/\`: \`flutter-team\`, \`ios-team\`, \`android-team\`, \`mobile-orchestrator\`. Agent teams are enabled through \`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1\` in \`.claude/settings.json\`.
- **Hooks** (\`.claude/settings.json\`): after each edit, \`track_change.sh\` records the file. When you finish a turn, \`post_turn.sh\` regenerates Pigeon code if \`pigeons/\` changed, runs \`dart fix\` and \`dart format\` on the edited Dart files and \`flutter analyze\`. It is silent when clean and blocks your stop with the errors when something fails — fix them. Needs \`jq\`.
- **Editing rules:** change \`AGENTS.md\`, never this file — it is overwritten by \`./tool/sync_agents.sh\`.
EOF

# --- GEMINI.md -------------------------------------------------------------
{ echo "$BANNER_MD"; echo; cat "$SOURCE"; } > "$OUT_DIR/GEMINI.md"

# --- .github/copilot-instructions.md ---------------------------------------
# One directory deep: rewrite root-relative links so they still resolve.
mkdir -p "$OUT_DIR/.github"
{
  echo "$BANNER_MD"
  echo
  sed -E 's#\]\((AGENTS\.md|docs/|\.claude/|lib/|pigeons/|ios/|android/|example/|test/|tool/)#](../\1#g' "$SOURCE"
} > "$OUT_DIR/.github/copilot-instructions.md"

# --- .cursor/rules/000-agents.mdc ------------------------------------------
# Cursor reads AGENTS.md natively in recent versions; this always-applied rule
# is the fallback for older ones and pins the read order for the other .mdc rules.
mkdir -p "$OUT_DIR/.cursor/rules"
cat > "$OUT_DIR/.cursor/rules/000-agents.mdc" <<'EOF'
---
description: Entry point — repo-wide agent rules live in AGENTS.md
alwaysApply: true
---

<!-- GENERATED FILE — DO NOT EDIT. Source: AGENTS.md. Regenerate: ./tool/sync_agents.sh -->

# Read `AGENTS.md` first

`/AGENTS.md` at the repo root is the single source of truth for architecture rules,
layout, rules and the testing contract. Read it
before any change and follow it over anything in this rules directory.

The other `.cursor/rules/*.mdc` files add language- and library-level detail
only (effective_dart, clean-code, dart_3_updates, mocktail, code review).

Never edit this file; edit `AGENTS.md` and run `./tool/sync_agents.sh`.
EOF

# --- write or check --------------------------------------------------------
TARGETS=(
  "CLAUDE.md"
  "GEMINI.md"
  ".github/copilot-instructions.md"
  ".cursor/rules/000-agents.mdc"
)

STALE=0
for f in "${TARGETS[@]}"; do
  if [ "$CHECK" = "1" ]; then
    if ! diff -q "$OUT_DIR/$f" "$f" >/dev/null 2>&1; then
      echo "stale: $f"
      STALE=1
    fi
  else
    mkdir -p "$(dirname "$f")"
    cp "$OUT_DIR/$f" "$f"
    echo "  wrote $f"
  fi
done

if [ "$CHECK" = "1" ]; then
  if [ "$STALE" = "1" ]; then
    echo
    echo "Generated agent files are out of date. Run: ./tool/sync_agents.sh"
    exit 1
  fi
  echo "Generated agent files are in sync with AGENTS.md."
else
  echo "Done. Source: AGENTS.md"
fi
