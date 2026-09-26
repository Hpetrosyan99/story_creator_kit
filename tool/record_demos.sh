#!/usr/bin/env bash
# Records the pub.dev demo videos: runs example/integration_test/demo on the
# iOS Simulator and turns its REC_START/REC_STOP markers into
# `xcrun simctl io recordVideo` sessions. Output: docs/demo/*.mp4.
#
#   ./tool/record_demos.sh [simulator-udid]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID="${1:-booted}"
OUT="$ROOT/docs/demo"
LOG="$(mktemp)"
mkdir -p "$OUT"
xcrun simctl privacy "$UDID" grant photos com.mabrook.storyCreatorKitExample 2>/dev/null || true

( tail -n0 -F "$LOG" 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      *REC_START*)
        name="${line##*REC_START }"
        xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/$name.mp4" >/dev/null 2>&1 &
        echo $! > "$LOG.pid"
        echo "recording $name"
        ;;
      *REC_STOP*)
        if [ -f "$LOG.pid" ]; then
          kill -INT "$(cat "$LOG.pid")" 2>/dev/null
          rm -f "$LOG.pid"
          echo "stopped"
        fi
        ;;
    esac
  done ) &
WATCHER=$!

cd "$ROOT/example" && flutter test integration_test/demo/demo_recordings_test.dart -d "$UDID" >>"$LOG" 2>&1
STATUS=$?
sleep 3
kill "$WATCHER" 2>/dev/null
pkill -f "tail -n0 -F $LOG" 2>/dev/null
grep -E "All tests|Some tests|\[E\]" "$LOG" | tail -5
ls -la "$OUT"
exit $STATUS
