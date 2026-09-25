---
description: Regenerate the tool-specific agent instruction files from AGENTS.md
allowed-tools: Bash(./tool/sync_agents.sh:*), Bash(git status:*), Bash(git diff:*)
---

`AGENTS.md` is the single source of agent instructions. Every other instruction file is generated from it.

Run:

```
./tool/sync_agents.sh
```

This regenerates:

- `CLAUDE.md`: the `@AGENTS.md` import plus the Claude-only section (commands, agents, hooks)
- `GEMINI.md`
- `.github/copilot-instructions.md`, with root-relative links rewritten one level up
- `.cursor/rules/000-agents.mdc`: the always-applied pointer rule

Then show `git diff --stat` for those files.

If anyone edited one of them by hand, the diff will show that edit being reverted. When that happens, tell me what was lost, so it can be re-applied to the source, `AGENTS.md`, instead.

CI runs `./tool/sync_agents.sh --check`, which fails on drift.
