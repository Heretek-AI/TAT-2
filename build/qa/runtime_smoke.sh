#!/usr/bin/env bash
# Runtime smoke gate.
#
# Boot a real free-play mission headless for N seconds and fail on any runtime
# error. This catches the class the unit suites and E2E cannot: an error that
# only fires in gameplay. The 2026-11-25 footstep occlusion bug threw
# "Array[PhysicsBody3D] -> Array[RID]" on every step and silently disabled
# occlusion, while E2E still reported 278/278.
#
# W10-A D9: the decision lives in `runtime_smoke_scan.sh` (self-tested by
# `test_runtime_smoke_scan.sh`). It checks, in this order:
#   * exit code — 124 (the `timeout` kill) is the only accepted termination; a
#     clean exit 0 means the mission ended early, so it fails;
#   * `TAT-2 mission_ready` seen at least once;
#   * `SCRIPT ERROR` / `SHADER ERROR` / `ERROR:` lines (which include Godot 4's
#     `USER ERROR:` rendering of `push_error`), minus the documented teardown
#     entries (embedded in the scanner; `runtime_smoke_allowlist.txt` is the
#     record plus an optional local extension — `.gitignore` cannot carry it).
# The log is never deleted: every run prints `log: <path>` on stdout and stderr
# so a wave can commit it as evidence.
#
# Usage: build/qa/runtime_smoke.sh [seconds]     (default 90)
# Exit 0 only when the mission stayed up for the whole window and the log is
# clean; the RUNTIME_SMOKE_SCAN line carries the numbers.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SECS="${1:-90}"
LOG="$(mktemp -t tat2-smoke-XXXXXX.log)"
LOCK="/tmp/opencode/tat2-godot.lock"
SCAN="$ROOT/build/qa/runtime_smoke_scan.sh"

mkdir -p "$(dirname "$LOCK")" 2>/dev/null || true
cd "$ROOT" || exit 2

# Exit 124 is the expected timeout kill: the game runs until stopped.
flock "$LOCK" -c "timeout ${SECS} tools/godot --headless --path game -- --qa-free-play" >"$LOG" 2>&1
CODE=$?

echo "log: $LOG"
"$SCAN" "$LOG" "$CODE"
RESULT=$?
if [ "$RESULT" -eq 0 ]; then
	echo "RUNTIME_SMOKE PASS"
else
	echo "RUNTIME_SMOKE FAIL: see the RUNTIME_SMOKE_SCAN line and the log" >&2
	echo "log: $LOG" >&2
fi
exit "$RESULT"
