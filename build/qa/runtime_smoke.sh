#!/usr/bin/env bash
# Runtime smoke gate.
#
# Boot a real free-play mission headless for N seconds and fail on any
# SCRIPT ERROR / SHADER ERROR. This catches the class the unit suites and E2E
# cannot: a runtime error that only fires in gameplay. The 2026-11-25 footstep
# occlusion bug threw "Array[PhysicsBody3D] -> Array[RID]" on every step and
# silently disabled occlusion, while E2E still reported 278/278.
#
# Usage: build/qa/runtime_smoke.sh [seconds]     (default 90)
# Exit 0 only when the mission reached mission_ready and the log is clean.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SECS="${1:-90}"
LOG="$(mktemp -t tat2-smoke-XXXXXX.log)"
LOCK="/tmp/opencode/tat2-godot.lock"

mkdir -p "$(dirname "$LOCK")" 2>/dev/null || true
cd "$ROOT" || exit 2

# Exit 124 is the expected timeout kill: the game runs until stopped.
flock "$LOCK" -c "timeout ${SECS} tools/godot --headless --path game -- --qa-free-play" >"$LOG" 2>&1
CODE=$?

SCRIPT=$(grep -c "SCRIPT ERROR" "$LOG" 2>/dev/null || true)
SHADER=$(grep -c "SHADER ERROR" "$LOG" 2>/dev/null || true)
READY=$(grep -c "TAT-2 mission_ready" "$LOG" 2>/dev/null || true)
SCRIPT=${SCRIPT:-0}; SHADER=${SHADER:-0}; READY=${READY:-0}

echo "RUNTIME_SMOKE seconds=${SECS} exit=${CODE} script_errors=${SCRIPT} shader_errors=${SHADER} mission_ready=${READY}"

if [ "$READY" -lt 1 ]; then
  echo "RUNTIME_SMOKE FAIL: the mission never reached mission_ready" >&2
  grep -E "SCRIPT ERROR|SHADER ERROR|ERROR:" "$LOG" | head -10 >&2 || true
  echo "log: $LOG" >&2
  exit 1
fi

if [ "$SCRIPT" -gt 0 ] || [ "$SHADER" -gt 0 ]; then
  echo "RUNTIME_SMOKE FAIL: runtime errors during a real boot" >&2
  grep -nE "SCRIPT ERROR|SHADER ERROR" "$LOG" | head -20 >&2 || true
  echo "log: $LOG" >&2
  exit 1
fi

echo "RUNTIME_SMOKE PASS"
rm -f "$LOG"
exit 0
