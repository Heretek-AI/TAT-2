#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QA="$ROOT/build/qa"
LOG="$QA/capture_track_c.log"
XVFBLOG="$QA/xvfb_capture_track_c.log"
cd "$ROOT" || exit 1
mkdir -p "$QA"
pkill -f "Xvfb :98" 2>/dev/null
sleep 1
rm -f /tmp/.X98-lock
Xvfb :98 -screen 0 1280x720x24 -nolisten tcp -ac > "$XVFBLOG" 2>&1 &
XPID=$!
sleep 1
cleanup() {
  set +e
  kill -TERM "$XPID" 2>/dev/null
  wait "$XPID" 2>/dev/null
  rm -f /tmp/.X98-lock
}
trap cleanup EXIT
env -u WAYLAND_DISPLAY -u XAUTHORITY DISPLAY=:98 \
  flatpak run org.godotengine.Godot --path game --rendering-driver vulkan \
  --script "$QA/capture_track_c.gd" > "$LOG" 2>&1
ST=$?
echo "EXIT=$ST"
grep -E "Godot Engine|Vulkan|Forward|QA CAPTURE|TRACK_C_CAPTURE|SHADER ERROR|SCRIPT ERROR" "$LOG"
exit "$ST"
