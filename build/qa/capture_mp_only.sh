#!/usr/bin/env bash
set -u
cd /home/john/Projects/TAT-2 || exit 1
LOG="build/qa/capture_mp_only.log"
mkdir -p build/qa
pkill -f "Xvfb :99" 2>/dev/null
sleep 1
rm -f /tmp/.X99-lock
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp -ac > build/qa/xvfb_mp.log 2>&1 &
XPID=$!
sleep 1
trap 'kill -TERM "$XPID" 2>/dev/null; wait "$XPID" 2>/dev/null; rm -f /tmp/.X99-lock' EXIT
env -u WAYLAND_DISPLAY -u XAUTHORITY DISPLAY=:99 \
  flatpak run org.godotengine.Godot --path game --rendering-driver vulkan \
  --script /home/john/Projects/TAT-2/build/qa/capture_mp_only.gd > "$LOG" 2>&1
ST=$?

echo "EXIT=$ST"
grep -E "Godot Engine|Vulkan|Forward|QA CAPTURE|SHADER ERROR|SCRIPT ERROR" "$LOG"
exit "$ST"
