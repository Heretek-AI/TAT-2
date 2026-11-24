#!/usr/bin/env bash
# One performance-matrix configuration per invocation (W0b).
#
# Serializes GPU work (flock + live-process check), isolates user:// via
# XDG_DATA_HOME, runs one Godot with the Dummy audio driver and vsync disabled,
# captures a log, and fails if the run did not print PERF_CONFIG/PERF_SUMMARY/
# PERF_DONE (a truncated run cannot pass).
#
# Display: the host compositor by default. Xvfb is only a fallback for a
# headless machine; its presentation path adds ~25 ms/frame at 720p on the
# reference RTX 4070, so Xvfb numbers are labelled and are not comparable to a
# host run. Set PERF_HOST_DISPLAY=0 to force Xvfb.
#
# Prefer a release export (`build/tat2-linux-x86_64`) when present; the editor
# binary is a fallback for a tree that has not been exported.
#
# Examples:
#   build/qa/run_perf_matrix.sh --quality=high --scale=1.0 --scaling=bilinear
#   build/qa/run_perf_matrix.sh --quality=medium --scale=0.85 --scaling=fsr1 --lights=80 --shadows=3
#   build/qa/run_perf_matrix.sh --quality=high --scale=1.0 --scaling=bilinear \
#       --pose=spawn_overlook --frames=300 --warmup=180 --tag=validate
#
# Full matrix (serialized, one config at a time):
#   for q in high medium low; do
#     build/qa/run_perf_matrix.sh --quality=$q --scale=1.0 --scaling=bilinear --tag="ladder_$q"
#   done
#   build/qa/run_perf_matrix.sh --quality=high --scale=0.85 --scaling=fsr1 --tag=fsr1_085
#   build/qa/run_perf_matrix.sh --quality=high --scale=0.75 --scaling=fsr2 --tag=fsr2_075
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/qa/perf"
mkdir -p "$OUT"

QUALITY="high"
SCALE="1.0"
SCALING="bilinear"
LIGHTS="160"
SHADOWS="6"
VSYNC="off"
RES="1920x1080"
CONTRACT="4"
TAG=""
POSE=""
FRAMES="0"
WARMUP="180"
SETTLE="30"
TIMEOUT="1800"
DEADLINE=""
HOST_DISPLAY="${PERF_HOST_DISPLAY:-1}"

for arg in "$@"; do
  case "$arg" in
    --quality=*)  QUALITY="${arg#*=}" ;;
    --scale=*)    SCALE="${arg#*=}" ;;
    --scaling=*)  SCALING="${arg#*=}" ;;
    --lights=*)   LIGHTS="${arg#*=}" ;;
    --shadows=*)  SHADOWS="${arg#*=}" ;;
    --vsync=*)    VSYNC="${arg#*=}" ;;
    --res=*)      RES="${arg#*=}" ;;
    --contract=*) CONTRACT="${arg#*=}" ;;
    --tag=*)      TAG="${arg#*=}" ;;
    --pose=*)     POSE="${arg#*=}" ;;
    --poses=*)    POSE="${arg#*=}" ;;
    --frames=*)   FRAMES="${arg#*=}" ;;
    --warmup=*)   WARMUP="${arg#*=}" ;;
    --settle=*)   SETTLE="${arg#*=}" ;;
    --timeout=*)  TIMEOUT="${arg#*=}" ;;
    --deadline=*) DEADLINE="${arg#*=}" ;;
    --host-display) HOST_DISPLAY=1 ;;
    *)
      echo "ABORT: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

case "$QUALITY" in low|medium|high) ;; *) echo "ABORT: --quality must be low|medium|high" >&2; exit 2 ;; esac
case "$SCALE" in 1.0|0.85|0.75) ;; *) echo "ABORT: --scale must be 1.0|0.85|0.75" >&2; exit 2 ;; esac
case "$SCALING" in bilinear|fsr1|fsr2) ;; *) echo "ABORT: --scaling must be bilinear|fsr1|fsr2" >&2; exit 2 ;; esac
case "$VSYNC" in off|on) ;; *) echo "ABORT: --vsync must be off|on" >&2; exit 2 ;; esac
if [ "$VSYNC" != "off" ]; then
  echo "ABORT: the perf matrix requires --vsync=off" >&2
  exit 2
fi
if ! [[ "$RES" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "ABORT: --res must be WxH" >&2
  exit 2
fi
if [ -z "$TAG" ]; then
  TAG="q${QUALITY}_s${SCALE}_${SCALING}_l${LIGHTS}_sh${SHADOWS}_${RES}"
fi
SAFE_TAG="$(printf '%s' "$TAG" | tr -c 'A-Za-z0-9_.-' '_')"
LOG="$OUT/perf_${SAFE_TAG}.log"
XVFBLOG="$OUT/xvfb_${SAFE_TAG}.log"
if [ -z "$DEADLINE" ]; then
  DEADLINE=$(( TIMEOUT > 120 ? TIMEOUT - 60 : TIMEOUT ))
fi

# Serialize GPU work: a second matrix run waits/fails instead of sharing the
# GPU with the first. The lock is per output directory, not per tag.
exec 9>"$OUT/.perf_matrix.lock"
if ! flock -n 9; then
  echo "ABORT: another perf matrix run holds $OUT/.perf_matrix.lock" >&2
  exit 2
fi
if pgrep -f "[t]at2-linux-x86_64" >/dev/null 2>&1; then
  echo "ABORT: an exported TAT-2 client is already running" >&2
  exit 2
fi
OTHER_GODOT="$(pgrep -af "[Gg]odot.*--path .*game" 2>/dev/null || true)"
GPU_GODOT="$(printf '%s\n' "$OTHER_GODOT" | grep -v -- "--headless" || true)"
if [ -n "$GPU_GODOT" ]; then
  echo "ABORT: another windowed/Vulkan Godot game instance is already running:" >&2
  printf '%s\n' "$GPU_GODOT" >&2
  exit 2
fi

DATA_HOME="${XDG_DATA_HOME:-/tmp/tat2-perf-data/$SAFE_TAG}"
mkdir -p "$DATA_HOME"
GIT_SHA="$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"

# Prefer a release export when one exists: the editor binary runs scripts in
# debug mode and is not comparable to the shipped frame times. `PERF_BINARY`
# forces a specific executable (fail closed if it does not exist).
BINARY_MODE="editor"
BIN="$ROOT/tools/godot"
if [ -n "${PERF_BINARY:-}" ]; then
  if [ ! -x "$PERF_BINARY" ]; then
    echo "ABORT: PERF_BINARY=$PERF_BINARY is not executable" >&2
    exit 2
  fi
  BINARY_MODE="export"
  BIN="$PERF_BINARY"
elif [ -x "$ROOT/build/tat2-linux-x86_64" ]; then
  BINARY_MODE="export"
  BIN="$ROOT/build/tat2-linux-x86_64"
fi
BIN_SHA="$(stat -c '%y %s' "$BIN" 2>/dev/null || echo unknown)"

SMI_BEFORE="unavailable"
if command -v nvidia-smi >/dev/null 2>&1; then
  SMI_BEFORE="$(nvidia-smi --query-gpu=name,driver_version,temperature.gpu,clocks.current.graphics,power.draw --format=csv,noheader 2>/dev/null | head -1)"
  [ -n "$SMI_BEFORE" ] || SMI_BEFORE="unavailable"
fi

{
  echo "PERF_HOST tag=$SAFE_TAG git=$GIT_SHA binary_mode=$BINARY_MODE binary=$BIN binary_stat=$BIN_SHA xdg_data_home=$DATA_HOME res=$RES contract=$CONTRACT"
  echo "PERF_ARGS quality=$QUALITY scale=$SCALE scaling=$SCALING lights=$LIGHTS shadows=$SHADOWS vsync=$VSYNC pose=${POSE:-all} frames=$FRAMES warmup=$WARMUP timeout=$TIMEOUT deadline=$DEADLINE"
  echo "PERF_GPU_BEFORE $SMI_BEFORE"
} > "$LOG"
if [ -n "$OTHER_GODOT" ]; then
  echo "PERF_WARNING other headless Godot processes are running; frame times may be CPU-contended:" >> "$LOG"
  printf '%s\n' "$OTHER_GODOT" >> "$LOG"
fi

XVFB_PID=""
DISPLAY_NUM=""
cleanup() {
  set +e
  if [ -n "$XVFB_PID" ]; then
    kill -TERM "$XVFB_PID" 2>/dev/null
    wait "$XVFB_PID" 2>/dev/null
  fi
  if [ -n "$DISPLAY_NUM" ]; then
    rm -f "/tmp/.X${DISPLAY_NUM}-lock" 2>/dev/null
  fi
}
trap cleanup EXIT

BIN_ARGS=(
  --rendering-driver vulkan
  --audio-driver Dummy
  --script res://tests/perf/perf_matrix.gd
)
if [ "$BINARY_MODE" = "editor" ]; then
  BIN_ARGS=(--path "$ROOT/game" "${BIN_ARGS[@]}")
fi
GAME_ARGS=(
  "${BIN_ARGS[@]}"
  --
  "--perf-matrix"
  "--perf-quality=$QUALITY"
  "--perf-scale=$SCALE"
  "--perf-scaling=$SCALING"
  "--perf-lights=$LIGHTS"
  "--perf-shadows=$SHADOWS"
  "--perf-vsync=$VSYNC"
  "--res=$RES"
  "--contract=$CONTRACT"
  "--warmup=$WARMUP"
  "--settle=$SETTLE"
  "--frames=$FRAMES"
  "--deadline=$DEADLINE"
)
if [ -n "$POSE" ]; then
  GAME_ARGS+=("--poses=$POSE")
fi
if [ -n "${TAT2_PERF_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  GAME_ARGS+=(${TAT2_PERF_EXTRA_ARGS})
fi

GAME_PID=""
TEARDOWN_KILLED=0
STDBUF_CMD=()
if command -v stdbuf >/dev/null 2>&1; then STDBUF_CMD=(stdbuf -oL -eL); fi

# Wait for the run to finish. `PERF_DONE` is the completion marker; a windowed
# export can linger in teardown on some compositors, so after the marker the
# wrapper gives 10 s and then terminates it. A missing marker is a truncation.
wait_game() {
  local started now grace_start done_seen
  started=$(date +%s)
  done_seen=0
  while kill -0 "$GAME_PID" 2>/dev/null; do
    if [ "$done_seen" -eq 0 ] && grep -q "^PERF_DONE " "$LOG"; then
      done_seen=1
      grace_start=$(date +%s)
    fi
    now=$(date +%s)
    if [ "$done_seen" -eq 1 ]; then
      if [ $((now - grace_start)) -ge 10 ]; then
        echo "PERF_TEARDOWN forced_kill=1 after PERF_DONE" >> "$LOG"
        kill -TERM "$GAME_PID" 2>/dev/null
        sleep 1
        kill -KILL "$GAME_PID" 2>/dev/null
        TEARDOWN_KILLED=1
        break
      fi
    elif [ $((now - started)) -ge "$TIMEOUT" ]; then
      echo "PERF_TIMEOUT wall=${TIMEOUT}s no PERF_DONE" >> "$LOG"
      kill -TERM "$GAME_PID" 2>/dev/null
      sleep 1
      kill -KILL "$GAME_PID" 2>/dev/null
      TEARDOWN_KILLED=1
      break
    fi
    sleep 0.5
  done
  wait "$GAME_PID" 2>/dev/null
  ST=$?
  if [ "$TEARDOWN_KILLED" -eq 1 ] && grep -q "^PERF_DONE " "$LOG"; then
    ST=0
  fi
}

if [ "$HOST_DISPLAY" = "1" ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
  echo "PERF_DISPLAY host display=${DISPLAY:-} wayland=${WAYLAND_DISPLAY:-}" >> "$LOG"
  "${STDBUF_CMD[@]}" env -u XAUTHORITY XDG_DATA_HOME="$DATA_HOME" TAT_GIT_SHA="$GIT_SHA" \
    "$BIN" "${GAME_ARGS[@]}" >> "$LOG" 2>&1 &
  GAME_PID=$!
  wait_game
else
  if ! command -v Xvfb >/dev/null 2>&1; then
    echo "ABORT: no DISPLAY and Xvfb is unavailable" >&2
    exit 2
  fi
  W="${RES%x*}"
  H="${RES#*x}"
  for n in 98 99 97 96 95 94 93 92 91 90; do
    if [ ! -e "/tmp/.X${n}-lock" ]; then
      DISPLAY_NUM="$n"
      break
    fi
  done
  if [ -z "$DISPLAY_NUM" ]; then
    echo "ABORT: no free Xvfb display number" >&2
    exit 2
  fi
  Xvfb ":${DISPLAY_NUM}" -screen 0 "${W}x${H}x24" -nolisten tcp -ac > "$XVFBLOG" 2>&1 &
  XVFB_PID=$!
  for _i in $(seq 1 50); do
    [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] && break
    sleep 0.1
  done
  echo "PERF_DISPLAY xvfb=:${DISPLAY_NUM} pid=$XVFB_PID" >> "$LOG"
  echo "PERF_WARNING xvfb presentation adds a copy/sync path; its frame times are NOT comparable to a host compositor" >> "$LOG"
  "${STDBUF_CMD[@]}" env -u WAYLAND_DISPLAY -u XAUTHORITY DISPLAY=":${DISPLAY_NUM}" \
    XDG_DATA_HOME="$DATA_HOME" TAT_GIT_SHA="$GIT_SHA" \
    "$BIN" "${GAME_ARGS[@]}" >> "$LOG" 2>&1 &
  GAME_PID=$!
  wait_game
fi

SMI_AFTER="unavailable"
if command -v nvidia-smi >/dev/null 2>&1; then
  SMI_AFTER="$(nvidia-smi --query-gpu=name,driver_version,temperature.gpu,clocks.current.graphics,power.draw --format=csv,noheader 2>/dev/null | head -1)"
  [ -n "$SMI_AFTER" ] || SMI_AFTER="unavailable"
fi
echo "PERF_GPU_AFTER $SMI_AFTER" >> "$LOG"

echo "EXIT=$ST LOG=$LOG"
grep -E "^PERF_|^[{]|SCRIPT ERROR|SHADER ERROR|Too many mipmaps|double free" "$LOG" | tail -100

for marker in "PERF_CONFIG " "PERF_SUMMARY " "PERF_DONE "; do
  if ! grep -q "^${marker}" "$LOG"; then
    echo "FAIL: truncated run, missing ${marker}(see $LOG)" >&2
    exit 7
  fi
done
if [ "$ST" -ne 0 ]; then
  echo "FAIL: Godot exited $ST after PERF_DONE (see $LOG)" >&2
  exit "$ST"
fi
exit 0
