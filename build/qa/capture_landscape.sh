#!/usr/bin/env bash
# QA capture helper for the landscape weightmap change. Temporary only:
# modifies game/project.godot (QA autostart) and restores it on exit.
set -u

MODE="${1:?usage: capture_landscape.sh safe|sky [tag]}"
TAG="${2:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QA="$ROOT/build/qa"
case "$MODE" in
  sky) VIEW=courtyard ;;
  safe) VIEW=safe ;;
  *) echo "unknown mode: $MODE" >&2; exit 2 ;;
esac
OUT="$QA/landscape_after_${VIEW}${TAG}.png"
RUNLOG="$QA/run_ls_${MODE}${TAG}.log"
XVFBLOG="$QA/xvfb_ls_${MODE}${TAG}.log"
BAK="$QA/project.godot.bak"

cd "$ROOT" || exit 1
mkdir -p "$QA"

if ! git diff --quiet -- game/project.godot; then
  echo "ABORT: game/project.godot already modified" >&2
  exit 1
fi
cp game/project.godot "$BAK"
printf '\n[tat2]\ndebug_autostart_contract=4\n' >> game/project.godot

cleanup() {
  set +e
  if [ -n "${GPID:-}" ]; then
    kill -TERM -"$GPID" 2>/dev/null
    sleep 2
    kill -KILL -"$GPID" 2>/dev/null
  fi
  if [ -n "${XPID:-}" ]; then
    kill -TERM "$XPID" 2>/dev/null
    wait "$XPID" 2>/dev/null
  fi
  cp "$BAK" game/project.godot
  rm -f /tmp/.X99-lock
  echo "restored project.godot; git diff:"
  git diff --stat -- game/project.godot
}
trap cleanup EXIT

# Clear any stale display from an earlier attempt.
pkill -f "Xvfb :99" 2>/dev/null
sleep 1
rm -f /tmp/.X99-lock

Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp -ac > "$XVFBLOG" 2>&1 &
XPID=$!
sleep 1

setsid env -u WAYLAND_DISPLAY -u XAUTHORITY DISPLAY=:99 \
  flatpak run org.godotengine.Godot --path game > "$RUNLOG" 2>&1 &
GPID=$!

LOADED=0
for _ in $(seq 1 150); do
  if grep -q "TAT-2 Loaded guildhall" "$RUNLOG"; then
    LOADED=1
    break
  fi
  if ! kill -0 "$GPID" 2>/dev/null; then
    echo "ABORT: game exited before load" >&2
    tail -40 "$RUNLOG" >&2
    exit 1
  fi
  sleep 1
done
if [ "$LOADED" -ne 1 ]; then
  echo "ABORT: timed out waiting for guildhall load" >&2
  tail -40 "$RUNLOG" >&2
  exit 1
fi
sleep 10

WID=$(DISPLAY=:99 xdotool search --onlyvisible --name "Thick As Thieves" | tail -1)
echo "window id: ${WID:-none}"
if [ -z "${WID:-}" ]; then
  DISPLAY=:99 xdotool search --name "" getwindowname %@ 2>/dev/null | head -20
  echo "ABORT: no game window" >&2
  exit 1
fi
DISPLAY=:99 xdotool windowfocus "$WID"
DISPLAY=:99 xdotool windowraise "$WID"
sleep 1
echo "focused window: $(DISPLAY=:99 xdotool getwindowfocus)"

if [ "$MODE" = "sky" ]; then
  # Same viewpoint recipe as lighting_after_sky.png:
  # 1890 px left at 0.0024 rad/px = 260 deg -> compass W.
  DISPLAY=:99 xdotool mousemove_relative -- -1890 0
  sleep 1
  DISPLAY=:99 xdotool keydown w
  sleep 4
  DISPLAY=:99 xdotool keyup w
  sleep 2
fi

sleep 1
DISPLAY=:99 import -window root "$OUT"
echo "saved $OUT"
identify "$OUT"

echo "--- run summary ---"
grep -E "TAT-2 environment:|TAT-2 Loaded guildhall|SCRIPT ERROR|SHADER ERROR" "$RUNLOG" || true
