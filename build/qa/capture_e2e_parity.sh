#!/usr/bin/env bash
set -u

ROOT="/home/john/Projects/TAT-2"
QA="$ROOT/build/qa"
OUT_DIR="$QA/e2e_parity"
LOG="$OUT_DIR/capture_e2e_parity.log"
XVFBLOG="$OUT_DIR/xvfb_e2e_parity.log"

STRICT=0
for arg in "$@"; do
  if [ "$arg" = "--strict" ]; then
    STRICT=1
  fi
done

cd "$ROOT" || exit 1
mkdir -p "$OUT_DIR"

pkill -f "Xvfb :99" 2>/dev/null || true
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
  --script ../build/qa/capture_e2e_parity.gd > "$LOG" 2>&1
ST=$?

SHADER_ERR=$(grep -c "SHADER ERROR" "$LOG" || true)
SCRIPT_ERR=$(grep -c "SCRIPT ERROR" "$LOG" || true)

EXPECTED_SHOTS=(
  "parity_startscreen.png"
  "parity_thieves_den_wide.png"
  "parity_thieves_den_map_table.png"
  "parity_wardrobe.png"
  "parity_ledger_journal.png"
  "parity_ledger_market.png"
  "parity_mission_prep_manor.png"
  "parity_mission_prep_guildhall.png"
  "parity_loading_screen.png"
  "parity_start_letter.png"
  "parity_guildhall_spawn_hud.png"
  "parity_guildhall_macneish_ssr.png"
  "parity_1p_zipwire_crank.png"
  "parity_1p_smokebomb_arc.png"
  "parity_1p_vistara_diamond.png"
  "parity_guard_lantern_alert.png"
  "parity_1p_slithersap.png"
  "parity_lockpick_ui.png"
  "parity_map_overlay.png"
  "parity_ping_radial.png"
  "parity_old_manor_exterior.png"
)

MISSING_OR_EMPTY=0
for f in "${EXPECTED_SHOTS[@]}"; do
  if [ ! -s "$OUT_DIR/$f" ]; then
    echo "MISSING_OR_EMPTY_PNG: $OUT_DIR/$f"
    MISSING_OR_EMPTY=$((MISSING_OR_EMPTY + 1))
  fi
done

PARITY_PASSES=$(grep -c '^PARITY_CHECK: .* PASS' "$LOG" || true)
PARITY_FAILS=$(grep -c '^PARITY_CHECK: .* FAIL' "$LOG" || true)
TOTAL_SHOTS=${#EXPECTED_SHOTS[@]}

grep -E "Godot Engine|Vulkan|Forward|PARITY_CAPTURE:|PARITY_CHECK:|PARITY_IMAGE_FAIL:|PARITY_FATAL:|PARITY_GD_DONE:|SHADER ERROR|SCRIPT ERROR" "$LOG" || true
echo "EXIT=$ST SHADER_ERRORS=$SHADER_ERR SCRIPT_ERRORS=$SCRIPT_ERR MISSING_OR_EMPTY=$MISSING_OR_EMPTY"
echo "PARITY_SUMMARY: shots=$TOTAL_SHOTS parity_passes=$PARITY_PASSES parity_fails=$PARITY_FAILS shader_errors=$SHADER_ERR script_errors=$SCRIPT_ERR"

if [ "$ST" -ne 0 ] || [ "$SHADER_ERR" -ne 0 ] || [ "$SCRIPT_ERR" -ne 0 ] || [ "$MISSING_OR_EMPTY" -ne 0 ]; then
  exit 1
fi

if [ "$STRICT" -eq 1 ] && [ "$PARITY_FAILS" -ne 0 ]; then
  echo "STRICT_GATE_FAILED: parity_fails=$PARITY_FAILS"
  exit 1
fi

exit 0
