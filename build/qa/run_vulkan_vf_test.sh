#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QA="$ROOT/build/qa"
LOG="$QA/make_test_vulkan_vf.log"
XVFBLOG="$QA/xvfb_test_vulkan_vf.log"
cd "$ROOT" || exit 1
mkdir -p "$QA"

pkill -f "Xvfb :99" 2>/dev/null
sleep 1
rm -f /tmp/.X99-lock
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp -ac > "$XVFBLOG" 2>&1 &
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
ST=$?

echo "EXIT=$ST"
grep -E "Godot Engine|Vulkan|Forward" "$LOG" | head -5
echo "SHADER_ERRORS=$(grep -c 'SHADER ERROR' "$LOG" || true)"
echo "SCRIPT_ERRORS=$(grep -c 'SCRIPT ERROR' "$LOG" || true)"
grep -E "PASS: 3[1-5]|FAIL:|SUMMARY:" "$LOG"
exit "$ST"
