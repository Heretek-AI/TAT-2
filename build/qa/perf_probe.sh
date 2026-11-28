#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RES="${1:-1920x1080}"
OUT="$ROOT/build/qa/perf"
LOG="$OUT/probe_${RES}.log"
XVFBLOG="$OUT/xvfb_${RES}.log"

mkdir -p "$OUT"
if pgrep -f "[t]at2-linux-x86_64" >/dev/null || pgrep -f "[g]odot.*perf_probe" >/dev/null; then
  echo "ABORT: concurrent game/perf process detected"
  exit 2
fi
rm -f /tmp/.X98-lock
Xvfb :98 -screen 0 1920x1080x24 -nolisten tcp -ac > "$XVFBLOG" 2>&1 &
XPID=$!
sleep 1

cleanup() {
  set +e
  kill -TERM "$XPID" 2>/dev/null
  wait "$XPID" 2>/dev/null
  rm -f /tmp/.X98-lock
}
trap cleanup EXIT

cd "$ROOT" || exit 1
env -u WAYLAND_DISPLAY -u XAUTHORITY DISPLAY=:98 \
  /usr/bin/timeout -s TERM 1500s \
  flatpak run org.godotengine.Godot --path game --rendering-driver vulkan \
  --script ../build/qa/perf_probe.gd -- "--res=${RES}" > "$LOG" 2>&1
ST=$?

echo "EXIT=$ST LOG=$LOG"
grep -E "PERF_|SCRIPT ERROR|SHADER ERROR|Too many mipmaps|double free" "$LOG" | tail -80
exit $ST
