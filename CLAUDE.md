# CLAUDE.md

<!-- GENERATED FILE — DO NOT EDIT. Source: AGENTS.md. Regenerate: ./tool/sync_agents.sh -->

@AGENTS.md

## Claude Code specifics

The rules above are the whole contract — this section only covers Claude-only wiring.

- **Commands** in `.claude/commands/`: `/sync-agents`, `/review-pr`, `/review-codequality`, `/review-functional-logic`, `/review-security-performance`, `/context-prime`.
- **Agents** in `.claude/agents/`: `flutter-team`, `ios-team`, `android-team`, `mobile-orchestrator`. Agent teams are enabled through `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `.claude/settings.json`.
- **Hooks** (`.claude/settings.json`): after each edit, `track_change.sh` records the file. When you finish a turn, `post_turn.sh` regenerates Pigeon code if `pigeons/` changed, runs `dart fix` and `dart format` on the edited Dart files and `flutter analyze`. It is silent when clean and blocks your stop with the errors when something fails — fix them. Needs `jq`.
- **Editing rules:** change `AGENTS.md`, never this file — it is overwritten by `./tool/sync_agents.sh`.
