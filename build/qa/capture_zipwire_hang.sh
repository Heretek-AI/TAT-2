#!/usr/bin/env bash
# KF16/KF17 zipwire capture wrapper: native Godot Vulkan Forward+ on own :95.
#   bash build/qa/capture_zipwire_hang.sh
# Output: /tmp/opencode/zip_hang_final/kf16_*.png / kf17_*.png
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QA="$ROOT/build/qa"
OUT_DIR="/tmp/opencode/zip_hang_final"
LOG="$OUT_DIR/capture_zipwire_hang.log"
XVFBLOG="$OUT_DIR/xvfb_zipwire_hang.log"
GODOT_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tools/godot"

cd "$ROOT" || exit 1
mkdir -p "$OUT_DIR"

# Own :95 only. Never touch another display.
pkill -f "^Xvfb :95" 2>/dev/null || true
sleep 1
rm -f /tmp/.X95-lock
Xvfb :95 -screen 0 1920x1080x24 -nolisten tcp -ac > "$XVFBLOG" 2>&1 &
XPID=$!
sleep 1

cleanup() {
  set +e
  kill -TERM "$XPID" 2>/dev/null
  wait "$XPID" 2>/dev/null
  rm -f /tmp/.X95-lock
}
trap cleanup EXIT

DISPLAY=:95 TAT2_TEX_CAP=1024 \
  "$GODOT_BIN" --path "$ROOT/game" --rendering-driver vulkan \
  --resolution 1920x1080 --position 0,0 \
  --script "$QA/capture_zipwire_hang.gd" > "$LOG" 2>&1
ST=$?

SHADER_ERR=$(grep -c "SHADER ERROR" "$LOG" || true)
SCRIPT_ERR=$(grep -c "SCRIPT ERROR" "$LOG" || true)

MISSING=0
for f in "kf16_zipwire_travel.png" "kf17_zipwire_hang_crank.png" "kf17_zipwire_hang_idle.png"; do
  if [ ! -s "$OUT_DIR/$f" ]; then
    echo "MISSING_OR_EMPTY_PNG: $OUT_DIR/$f"
    MISSING=$((MISSING + 1))
  fi
done

grep -E "CAPTURE_BOOT|CAPTURE_SPAWN|SWEEP_RESULT|GRAPPLE_CHOICE|STATE_TRIPLE|CAPTURE:|CAPTURE_DONE|CAPTURE_FAIL|CAPTURE_FATAL|ASSERT_FAIL|Vulkan|SHADER ERROR|SCRIPT ERROR" "$LOG" || true
echo "EXIT=$ST SHADER_ERRORS=$SHADER_ERR SCRIPT_ERRORS=$SCRIPT_ERR MISSING_OR_EMPTY=$MISSING"

if [ "$ST" -ne 0 ] || [ "$SHADER_ERR" -ne 0 ] || [ "$SCRIPT_ERR" -ne 0 ] || [ "$MISSING" -ne 0 ]; then
  exit 1
fi
exit 0
