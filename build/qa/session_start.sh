#!/usr/bin/env bash
# Start the live QA session: back up project.godot, append the autostart
# setting, launch the game on :99, and wait for Guildhall to load.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QA="$ROOT/build/qa"
cd "$ROOT" || exit 1
mkdir -p "$QA"

if ! git diff --quiet -- game/project.godot; then
  echo "ABORT: game/project.godot already modified" >&2
  exit 1
fi
cp game/project.godot "$QA/project.godot.bak"
printf '\n[tat2]\ndebug_autostart_contract=4\n' >> game/project.godot

if ! DISPLAY=:99 xdpyinfo >/dev/null 2>&1; then
  setsid Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp -nolock -ac > "$QA/xvfb_light.log" 2>&1 &
  sleep 2
fi

setsid env -u WAYLAND_DISPLAY -u XAUTHORITY DISPLAY=:99 \
  flatpak run org.godotengine.Godot --path game > "$QA/run_light.log" 2>&1 &
GPID=$!
echo "game pid=$GPID"

LOADED=0
for i in $(seq 1 150); do
  if grep -q "TAT-2 Loaded guildhall" "$QA/run_light.log" 2>/dev/null; then
    LOADED=1
    echo "loaded at ${i}s"
    break
  fi
  if ! kill -0 "$GPID" 2>/dev/null; then
    echo "ABORT: game exited before load" >&2
    tail -40 "$QA/run_light.log" >&2
    exit 1
  fi
  sleep 1
done
if [ "$LOADED" -ne 1 ]; then
  echo "ABORT: load timeout" >&2
  tail -40 "$QA/run_light.log" >&2
  exit 1
fi

sleep 10
grep -E "TAT-2 environment:|TAT-2 Loaded guildhall|SCRIPT ERROR" "$QA/run_light.log" || true
WID=$(DISPLAY=:99 xdotool search --onlyvisible --name "Thick As Thieves" | tail -1)
echo "window id: ${WID:-none}"
if [ -n "${WID:-}" ]; then
  DISPLAY=:99 xdotool windowfocus "$WID"
  DISPLAY=:99 xdotool windowraise "$WID"
  sleep 1
  echo "focused: $(DISPLAY=:99 xdotool getwindowfocus)"
fi
