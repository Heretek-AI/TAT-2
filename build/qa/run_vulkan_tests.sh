#!/usr/bin/env bash
# Real-renderer test run: proves the modified GLSL compiles under Vulkan.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QA="$ROOT/build/qa"
LOG="$QA/make_test_vulkan_landscape.log"
XVFBLOG="$QA/xvfb_test_vulkan.log"
cd "$ROOT" || exit 1

pkill -f "Xvfb :99" 2>/dev/null
sleep 1
rm -f /tmp/.X99-lock
Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp -ac > "$XVFBLOG" 2>&1 &
XPID=$!
sleep 1

cleanup() {
  set +e
  kill -TERM "$XPID" 2>/dev/null
  wait "$XPID" 2>/dev/null
  rm -f /tmp/.X99-lock
}
trap cleanup EXIT

env -u WAYLAND_DISPLAY -u XAUTHORITY DISPLAY=:99 \
  flatpak run org.godotengine.Godot --path game --rendering-driver vulkan \
  --script res://tests/run_tests.gd > "$LOG" 2>&1
STATUS=$?

echo "exit status: $STATUS"
echo "--- renderer ---"
grep -E "Godot Engine|Vulkan|OpenGL|Forward" "$LOG" | head -5
echo "--- shader/script errors ---"
grep -c "SHADER ERROR" "$LOG" || true
grep -c "SCRIPT ERROR" "$LOG" || true
echo "--- landscape assertions ---"
grep -E "landscape second weightmap|single-weightmap landscape|visibility on second weightmap" "$LOG" || true
echo "--- summary ---"
grep -E "SUMMARY: fails=" "$LOG" || true
exit "$STATUS"
