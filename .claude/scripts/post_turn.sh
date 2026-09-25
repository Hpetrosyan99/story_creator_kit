#!/usr/bin/env bash
# Stop hook, registered in .claude/settings.json.
#
# At the end of a turn, takes the files the agent edited (recorded by
# track_change.sh) and:
#   1. regenerates Pigeon code when pigeons/ changed
#   2. runs `dart fix --apply` and `dart format` on exactly the edited Dart files
#   3. runs `flutter analyze` on the plugin (lib, test) and, when touched, example/
#
# Clean turn: prints nothing, clears the state file, exits 0.
# Something failed: prints {"decision":"block","reason":...} so the agent sees
# the failure and fixes it, and keeps the file list so the next stop checks it
# again. On the stop right after such a block (stop_hook_active=true) it does
# not block a second time: the failure becomes a warning to the user.
#
# Logs: .claude/state/build.log and .claude/state/analyze_result.log
set -u

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"systemMessage": "post_turn.sh: jq is not installed, so post-turn format/analyze is disabled. Install jq (macOS: brew install jq)."}'
  exit 0
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATE_DIR="$PROJECT_ROOT/.claude/state"
BUILD_LOG="$STATE_DIR/build.log"
ANALYZE_LOG="$STATE_DIR/analyze_result.log"

PAYLOAD=$(cat)
SESSION_ID=$(jq -r '.session_id // empty' <<<"$PAYLOAD" 2>/dev/null | tr -cd 'A-Za-z0-9_-')
SESSION_ID=${SESSION_ID:-default}
STOP_HOOK_ACTIVE=$(jq -r '.stop_hook_active // false' <<<"$PAYLOAD" 2>/dev/null)
PENDING="$STATE_DIR/changed_${SESSION_ID}.txt"
SNAPSHOT="$STATE_DIR/processing_${SESSION_ID}.txt"

[ -s "$PENDING" ] || [ -s "$SNAPSHOT" ] || exit 0

# Background subagents may be mid-edit; check after they finish.
IN_FLIGHT=$(jq -r '[.background_tasks[]? | select(.type == "subagent" or .type == "teammate" or .type == "workflow")] | length' <<<"$PAYLOAD" 2>/dev/null)
[ "${IN_FLIGHT:-0}" = "0" ] || exit 0

command -v flutter >/dev/null 2>&1 || exit 0

cd "$PROJECT_ROOT" || exit 0
if [ -f "$PENDING" ]; then
  mv "$PENDING" "$PENDING.taken" &&
    cat "$PENDING.taken" >>"$SNAPSHOT" &&
    rm -f "$PENDING.taken"
fi
CHANGED=$(sort -u "$SNAPSHOT")

is_generated() {
  case "$1" in
    *.g.dart | lib/src/native/*) return 0 ;;
  esac
  return 1
}

need_pigeon=0 touched_root=0 touched_example=0
DART_FILES=()
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  case "$rel" in
    pigeons/*) need_pigeon=1 ;;
  esac
  case "$rel" in
    *.dart) ;;
    *) continue ;;
  esac
  case "$rel" in
    example/*) touched_example=1 ;;
    *) touched_root=1 ;;
  esac
  if [ -f "$rel" ] && ! is_generated "$rel"; then
    DART_FILES+=("$rel")
  fi
done <<<"$CHANGED"

if [ $((need_pigeon + touched_root + touched_example)) -eq 0 ]; then
  rm -f "$SNAPSHOT"
  exit 0
fi

mkdir -p "$STATE_DIR"
: >"$BUILD_LOG"
: >"$ANALYZE_LOG"
FAILED=()
BUILD_ERRORS=""

log_run() {
  printf '\n$ %s\n' "$*" >>"$BUILD_LOG"
  "$@" >>"$BUILD_LOG" 2>&1
}
step() {
  local first_line
  first_line=$(($(wc -l <"$BUILD_LOG") + 2))
  if ! log_run "$@"; then
    FAILED+=("$*")
    BUILD_ERRORS+=$'\n\n'"$(tail -n +"$first_line" "$BUILD_LOG" | tail -n 25)"
  fi
}

if [ "$need_pigeon" -eq 1 ] && [ -f pigeons/story_native_api.dart ]; then
  step dart run pigeon --input pigeons/story_native_api.dart
  touched_root=1
fi

if [ ${#DART_FILES[@]} -gt 0 ]; then
  for f in "${DART_FILES[@]}"; do
    log_run dart fix --apply "$f" || true
  done
  step dart format "${DART_FILES[@]}"
fi

analyze() { # analyze <label> <dir> <args...>
  local label=$1 dir=$2
  shift 2
  printf '\n$ (cd %s) flutter analyze %s\n' "$dir" "$*" >>"$ANALYZE_LOG"
  (cd "$dir" && flutter analyze "$@") >>"$ANALYZE_LOG" 2>&1 || FAILED+=("$label")
}
[ "$touched_root" -eq 1 ] && analyze "flutter analyze" .
[ "$touched_example" -eq 1 ] && analyze "flutter analyze example" example

if [ ${#FAILED[@]} -eq 0 ]; then
  rm -f "$SNAPSHOT"
  exit 0
fi

cat "$SNAPSHOT" >>"$PENDING"
rm -f "$SNAPSHOT"

failed_steps=$(printf '%s; ' "${FAILED[@]}")
failed_steps=${failed_steps%; }
ISSUE_RE='^[[:space:]]*(error|warning|info) [-•]'

reason="Post-turn checks failed for the files edited this turn: ${failed_steps}."
[ -n "$BUILD_ERRORS" ] && reason+="$BUILD_ERRORS"
if grep -qE "$ISSUE_RE" "$ANALYZE_LOG"; then
  reason+=$'\n\n'"First analyzer issues:"$'\n'"$(grep -E "$ISSUE_RE" "$ANALYZE_LOG" | head -n 30)"
fi
reason+=$'\n\n'"Fix these before finishing. Full output: .claude/state/build.log and .claude/state/analyze_result.log."

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  jq -n --arg msg "Post-turn checks still failing after a fix attempt: ${failed_steps}. See .claude/state/analyze_result.log." \
    '{systemMessage: $msg}'
else
  jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
fi
exit 0
