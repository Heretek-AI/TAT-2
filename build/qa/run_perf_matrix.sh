#!/usr/bin/env bash
# One performance-matrix configuration per invocation (W0b, provenance W0p).
#
# Serializes GPU work (flock + live-process check), isolates user:// via
# XDG_DATA_HOME, runs one Godot with the Dummy audio driver and vsync disabled,
# captures a log, and fails if the run did not print PERF_CONFIG/PERF_SUMMARY/
# PERF_DONE (a truncated run cannot pass).
#
# Lens provenance: the runner measures the SHIPPED lens by default — 54.54
# vertical (UE 85 horizontal at 16:9) and a 4000 m far plane. Both are passed
# explicitly so the log can never inherit a different default. Override with
# --fov= / --far= for a deliberate A/B; published numbers are then labelled by
# the PERF_CONFIG/PERF_RUN fov+far fields, never assumed.
#
# Other levers (all optional, applied by perf_profile / mission_controller):
#   --occlusion=on|off          Viewport.use_occlusion_culling (shipped: on)
#   --mesh-lod=<float>          Viewport.mesh_lod_threshold (0 disables)
#   --dir-shadow=on|off         DirectionalLight3D.shadow_enabled
#   --shadow-splits=1|2|4       PSSM splits (shipped: 4)
#   --shadow-max-distance=<m>   PSSM range (shipped: 80)
#
# Clock provenance: a real pre-warm run (same binary, same scene, 120 frames)
# runs before PERF_GPU_BEFORE, and GPU clocks/temperature/throttle reasons plus
# /proc/loadavg are recorded before and after the measured run. Without the
# pre-warm the "before" sample is an idle clock and any before/after delta is
# GPU boost, not throttling.
#
# Thermal/memory guard (fail closed; see docs/reports/w4p-thermal-guard.md):
#   --start-temp=<C>   refuse to start when the package is above this (78)
#   --max-temp=<C>     kill the launch at or above this (95)
#   --max-rss-mb=<MB>  fail the run when VmHWM exceeds this (8192, 1024..262144)
#   --sample-sec=<s>   independent sampler cadence in seconds (1)
# MemoryMax is derived from MemTotal at 75 % (2 GiB floor) instead of a fixed
# 12G, so an 8 GB host gets a real cap and a 64 GB host is not killed early;
# PERF_SCOPE_MEMORY_MAX overrides it. The RSS ceiling must fit inside that scope
# and below total RAM, otherwise the wrapper refuses: a cap the cgroup or the
# machine kills first can never be observed.
# Both the pre-warm and the measured run are covered by their own 1 s sampler
# process, not by the wait loop: PERF_THERMAL_SAMPLE is logged every tick, the
# peak is reported as PERF_THERMAL_PREWARM_PEAK / peak_cpu_c, and the sampled
# PID is killed at >= --max-temp. A `?` (unknown) temperature is never treated
# as safe: the wrapper aborts before launch and mid-run. Each launch runs in a
# user systemd scope with MemoryMax=12G / MemorySwapMax=0 when systemd-run
# works; otherwise the direct launch is used and PERF_WARNING says so.
# --guard-check=<C> runs only the temperature decision on a synthetic reading
# (no game, no lock) and exits 0/8; build/qa/test_perf_guard.sh uses it.
# --rss-check=<MB> runs only the RSS decision on a synthetic reading and exits
# 0/9; --provenance-check=<bin> verifies an export stamp and exits 0/3/4/5.
#
# Export provenance (W7G): `make linux-build` writes <binary>.stamp.json
# (HEAD + UTC time + PCK/binary SHA-256 and sizes). An exported measurement
# without a matching, current stamp fails closed, and PERF_PROVENANCE records
# publishable=1 only for a clean stamped build. --publishable-only aborts when
# the run would not be publishable.
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
#   build/qa/run_perf_matrix.sh --quality=high --occlusion=off --tag=no_occlusion
#   build/qa/run_perf_matrix.sh --quality=high --dir-shadow=off --shadow-splits=1 --tag=no_moon_shadow
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
MAX_TEMP="${PERF_MAX_TEMP:-95}"
START_TEMP="${PERF_START_TEMP:-78}"
MAX_RSS_MB="${PERF_MAX_RSS_MB:-8192}"
MAX_RSS_EXPLICIT=0
[ -n "${PERF_MAX_RSS_MB:-}" ] && MAX_RSS_EXPLICIT=1
SAMPLE_SEC="${PERF_THERMAL_SAMPLE_SEC:-1}"
MEM_MAX_OVERRIDE="${PERF_SCOPE_MEMORY_MAX:-}"
MEM_MAX=""
MEM_MAX_MB=0
RAM_TOTAL_MB=0
GUARD_CHECK=0
GUARD_CHECK_TEMP=""
RSS_CHECK=0
RSS_CHECK_MB=""
PROV_CHECK=0
PROV_CHECK_BIN=""
PUBLISHABLE_ONLY=0
HOST_DISPLAY="${PERF_HOST_DISPLAY:-1}"
FOV="54.54"
FAR="4000"
OCCLUSION="on"
MESH_LOD=""
DIR_SHADOW=""
SHADOW_SPLITS=""
SHADOW_MAX_DISTANCE=""
PREWARM="${PERF_PREWARM:-1}"
PREWARM_TIMEOUT="${PERF_PREWARM_TIMEOUT:-600}"

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
    --max-temp=*) MAX_TEMP="${arg#*=}" ;;
    --start-temp=*) START_TEMP="${arg#*=}" ;;
    --max-rss-mb=*) MAX_RSS_MB="${arg#*=}"; MAX_RSS_EXPLICIT=1 ;;
    --sample-sec=*) SAMPLE_SEC="${arg#*=}" ;;
    --guard-check=*) GUARD_CHECK=1; GUARD_CHECK_TEMP="${arg#*=}" ;;
    --rss-check=*) RSS_CHECK=1; RSS_CHECK_MB="${arg#*=}" ;;
    --provenance-check=*) PROV_CHECK=1; PROV_CHECK_BIN="${arg#*=}" ;;
    --publishable-only) PUBLISHABLE_ONLY=1 ;;
    --fov=*)      FOV="${arg#*=}" ;;
    --far=*)      FAR="${arg#*=}" ;;
    --occlusion=*) OCCLUSION="${arg#*=}" ;;
    --mesh-lod=*) MESH_LOD="${arg#*=}" ;;
    --dir-shadow=*) DIR_SHADOW="${arg#*=}" ;;
    --shadow-splits=*) SHADOW_SPLITS="${arg#*=}" ;;
    --shadow-max-distance=*) SHADOW_MAX_DISTANCE="${arg#*=}" ;;
    --prewarm=*) PREWARM="${arg#*=}" ;;
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
if ! [[ "$FOV" =~ ^[0-9]+([.][0-9]+)?$ ]] || [ "$(awk -v v="$FOV" 'BEGIN { print (v > 0 && v < 180) ? 1 : 0 }')" != "1" ]; then
  echo "ABORT: --fov must be a vertical FOV in (0, 180), got '$FOV'" >&2
  exit 2
fi
if ! [[ "$FAR" =~ ^[0-9]+([.][0-9]+)?$ ]] || [ "$(awk -v v="$FAR" 'BEGIN { print (v > 0) ? 1 : 0 }')" != "1" ]; then
  echo "ABORT: --far must be a positive distance in metres, got '$FAR'" >&2
  exit 2
fi
case "$OCCLUSION" in on|off) ;; *) echo "ABORT: --occlusion must be on|off" >&2; exit 2 ;; esac
if [ -n "$MESH_LOD" ] && { ! [[ "$MESH_LOD" =~ ^[0-9]+([.][0-9]+)?$ ]] || [ "$(awk -v v="$MESH_LOD" 'BEGIN { print (v >= 0 && v <= 64) ? 1 : 0 }')" != "1" ]; }; then
  echo "ABORT: --mesh-lod must be a number 0..64, got '$MESH_LOD'" >&2
  exit 2
fi
case "$DIR_SHADOW" in ""|on|off) ;; *) echo "ABORT: --dir-shadow must be on|off" >&2; exit 2 ;; esac
case "$SHADOW_SPLITS" in ""|1|2|4) ;; *) echo "ABORT: --shadow-splits must be 1|2|4" >&2; exit 2 ;; esac
if [ -n "$SHADOW_MAX_DISTANCE" ] && { ! [[ "$SHADOW_MAX_DISTANCE" =~ ^[0-9]+$ ]] || [ "$SHADOW_MAX_DISTANCE" -lt 1 ] || [ "$SHADOW_MAX_DISTANCE" -gt 10000 ]; }; then
  echo "ABORT: --shadow-max-distance must be an integer 1..10000, got '$SHADOW_MAX_DISTANCE'" >&2
  exit 2
fi
case "$PREWARM" in 0|1) ;; *) echo "ABORT: --prewarm must be 0|1" >&2; exit 2 ;; esac
if ! [[ "$MAX_TEMP" =~ ^[0-9]+$ ]] || [ "$MAX_TEMP" -lt 60 ] || [ "$MAX_TEMP" -gt 105 ]; then
  echo "ABORT: --max-temp must be an integer 60..105, got '$MAX_TEMP'" >&2
  exit 2
fi
if ! [[ "$START_TEMP" =~ ^[0-9]+$ ]] || [ "$START_TEMP" -lt 60 ] || [ "$START_TEMP" -gt 105 ]; then
  echo "ABORT: --start-temp must be an integer 60..105, got '$START_TEMP'" >&2
  exit 2
fi
if [ "$START_TEMP" -ge "$MAX_TEMP" ]; then
  echo "ABORT: --start-temp ($START_TEMP) must be lower than --max-temp ($MAX_TEMP); a start headroom of 0 C lets a 91 C machine start with max 92 C" >&2
  exit 2
fi
# --- RAM-derived memory scope and RSS ceiling (W7G) ------------------------
# MemoryMax used to be a hard-coded 12G: on an 8 GB host the cgroup cap was
# larger than RAM (so it never bounded anything), and on a 64 GB host it could
# kill a legitimate load. Derive it from MemTotal at 75 % (headroom for the
# kernel, the sampler and the compositor) and keep PERF_SCOPE_MEMORY_MAX as an
# explicit override. The RSS gate must fit inside the scope, otherwise the
# cgroup kills the run before the gate can report it.
ram_total_mb() { awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null; }
mem_max_to_mb() {
  case "$1" in
    *[Gg]) [[ "${1%?}" =~ ^[0-9]+$ ]] || return 1; printf '%d' $(( ${1%?} * 1024 )) ;;
    *[Mm]) [[ "${1%?}" =~ ^[0-9]+$ ]] || return 1; printf '%d' "${1%?}" ;;
    *) return 1 ;;
  esac
}
RAM_TOTAL_MB="$(ram_total_mb)"
case "$RAM_TOTAL_MB" in ''|*[!0-9]*|0) RAM_TOTAL_MB=0 ;; esac
if [ -n "$MEM_MAX_OVERRIDE" ]; then
  MEM_MAX="$MEM_MAX_OVERRIDE"
elif [ "$RAM_TOTAL_MB" -ge 1024 ]; then
  MEM_SCOPE_MB=$(( RAM_TOTAL_MB * 75 / 100 ))
  MEM_SCOPE_GB=$(( MEM_SCOPE_MB / 1024 ))
  [ "$MEM_SCOPE_GB" -lt 2 ] && MEM_SCOPE_GB=2
  MEM_MAX="${MEM_SCOPE_GB}G"
else
  MEM_MAX="2G"
fi
if ! MEM_MAX_MB="$(mem_max_to_mb "$MEM_MAX")"; then
  echo "ABORT: PERF_SCOPE_MEMORY_MAX must look like 12G or 12288M, got '$MEM_MAX'" >&2
  exit 2
fi
if [ "$MAX_RSS_EXPLICIT" = "0" ] && [ "$MAX_RSS_MB" -gt "$MEM_MAX_MB" ]; then
  MAX_RSS_MB="$MEM_MAX_MB"
fi
if ! [[ "$MAX_RSS_MB" =~ ^[0-9]+$ ]] || [ "$MAX_RSS_MB" -lt 1024 ] || [ "$MAX_RSS_MB" -gt 262144 ]; then
  echo "ABORT: --max-rss-mb must be an integer 1024..262144, got '$MAX_RSS_MB'" >&2
  exit 2
fi
if [ "$RAM_TOTAL_MB" -gt 0 ] && [ "$MAX_RSS_MB" -gt "$RAM_TOTAL_MB" ]; then
  echo "ABORT: --max-rss-mb $MAX_RSS_MB is above total RAM (${RAM_TOTAL_MB} MB); a cap above RAM can never fire" >&2
  exit 2
fi
if [ "$MAX_RSS_MB" -gt "$MEM_MAX_MB" ]; then
  echo "ABORT: --max-rss-mb $MAX_RSS_MB exceeds the memory scope MemoryMax=${MEM_MAX} (${MEM_MAX_MB} MB); the cgroup would kill the run first" >&2
  exit 2
fi
if ! [[ "$SAMPLE_SEC" =~ ^[0-9]+$ ]] || [ "$SAMPLE_SEC" -lt 1 ] || [ "$SAMPLE_SEC" -gt 60 ]; then
  echo "ABORT: --sample-sec must be an integer 1..60, got '$SAMPLE_SEC'" >&2
  exit 2
fi

# Single source of truth for the thermal decision. `?` (or any non-numeric
# reading) is `unknown`, never `ok`: this is the fail-closed path. A reading
# exactly at --start-temp is allowed; only a strictly hotter idle refuses.
thermal_decision() {
  local t="$1" start_max="$2" max="$3"
  case "$t" in
    ''|*[!0-9]*) printf 'unknown'; return 0 ;;
  esac
  if [ "$t" -ge "$max" ]; then printf 'refuse_max'; return 0; fi
  if [ "$t" -gt "$start_max" ]; then printf 'refuse_start'; return 0; fi
  printf 'ok'
}

# Synthetic self-check: exercise the exact runtime decision with a supplied
# temperature, before any lock, log, display or game process is touched.
if [ "$GUARD_CHECK" = "1" ]; then
  DECISION="$(thermal_decision "$GUARD_CHECK_TEMP" "$START_TEMP" "$MAX_TEMP")"
  echo "GUARD_CHECK temp=${GUARD_CHECK_TEMP:-?} start_max=$START_TEMP max=$MAX_TEMP decision=$DECISION"
  case "$DECISION" in
    ok) exit 0 ;;
    *) exit 8 ;;
  esac
fi

# Synthetic self-check for the RSS ceiling, mirroring --guard-check: exits 0
# (would pass) / 9 (would fail the run) without touching the lock or a launch.
if [ "$RSS_CHECK" = "1" ]; then
  case "$RSS_CHECK_MB" in
    ''|*[!0-9]*) DECISION="unknown" ;;
    *) if [ "$RSS_CHECK_MB" -gt "$MAX_RSS_MB" ]; then DECISION="refuse"; else DECISION="ok"; fi ;;
  esac
  echo "RSS_CHECK mb=${RSS_CHECK_MB:-?} max_rss_mb=$MAX_RSS_MB memory_max=$MEM_MAX ram_total_mb=$RAM_TOTAL_MB decision=$DECISION"
  case "$DECISION" in
    ok) exit 0 ;;
    *) exit 9 ;;
  esac
fi

# --- export provenance (W7G) -----------------------------------------------
# A measured export must come from the tree it claims. The stamp is written by
# `make linux-build` (HEAD + UTC time + PCK/binary SHA-256 and sizes); a stale
# stamp, a missing stamp or a hash mismatch is fail-closed, so a publishable
# number can never be attributed to a different HEAD. An explicit PERF_BINARY
# override without a stamp still runs but is labelled non-publishable.
json_field() {
  python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
v=d.get(sys.argv[2],"")
print("true" if v is True else "false" if v is False else v)' "$1" "$2" 2>/dev/null
}
PROV_STATUS="unverified"
PROV_REASON=""
PROV_PUBLISHABLE=0
PROV_STAMP=""
PROV_DETAIL=""
PROV_LINE=""
PCK_LINE=""
verify_export_stamp() { # binary
  local bin="$1" stamp="${1}.stamp.json" out rc
  PROV_STAMP="$stamp"
  PROV_STATUS="unverified"; PROV_REASON=""; PROV_PUBLISHABLE=0; PROV_DETAIL=""
  if [ ! -f "$stamp" ]; then
    PROV_STATUS="fail"; PROV_REASON="missing_stamp"
    return 5
  fi
  out="$(bash "$ROOT/build/qa/export_stamp.sh" verify --root "$ROOT" --binary "$bin" --stamp "$stamp" 2>&1)"
  rc=$?
  PROV_DETAIL="$(printf '%s\n' "$out" | tail -1)"
  case "$rc" in
    0) PROV_STATUS="ok" ;;
    3) PROV_STATUS="fail"; PROV_REASON="stale_stamp" ;;
    4) PROV_STATUS="fail"; PROV_REASON="artifact_mismatch" ;;
    *) PROV_STATUS="fail"; PROV_REASON="missing_artifact"; rc=5 ;;
  esac
  if [ "$rc" = "0" ]; then
    PROV_PUBLISHABLE=1
    if [ "$(json_field "$stamp" git_dirty)" = "true" ]; then
      PROV_PUBLISHABLE=0
      PROV_REASON="dirty_build"
    fi
    local stamp_git stamp_godot bin_sha bin_bytes pck_path pck_sha pck_bytes
    stamp_git="$(json_field "$stamp" git_sha)"
    stamp_godot="$(json_field "$stamp" godot)"
    bin_sha="$(json_field "$stamp" binary_sha256)"
    bin_bytes="$(json_field "$stamp" binary_bytes)"
    pck_path="$(json_field "$stamp" pck)"
    pck_sha="$(json_field "$stamp" pck_sha256)"
    pck_bytes="$(json_field "$stamp" pck_bytes)"
    PROV_LINE="PERF_PROVENANCE mode=export publishable=${PROV_PUBLISHABLE} reason=${PROV_REASON:-none} stamp_git=${stamp_git} godot=${stamp_godot} stamp=$stamp"
    if [ -n "$pck_path" ]; then
      PCK_LINE="PERF_PCK path=$(dirname "$bin")/$pck_path sha=$pck_sha bytes=$pck_bytes binary_sha=$bin_sha binary_bytes=$bin_bytes embedded=0"
    else
      PCK_LINE="PERF_PCK path=embedded sha=none bytes=$bin_bytes binary_sha=$bin_sha embedded=1"
    fi
  fi
  return "$rc"
}

if [ "$PROV_CHECK" = "1" ]; then
  if [ ! -f "$PROV_CHECK_BIN" ]; then
    echo "PROVENANCE_CHECK FAIL result=missing_binary bin=$PROV_CHECK_BIN" >&2
    exit 5
  fi
  verify_export_stamp "$PROV_CHECK_BIN"; PROV_RC=$?
  if [ "$PROV_RC" = "0" ]; then
    echo "PROVENANCE_CHECK OK publishable=$PROV_PUBLISHABLE reason=${PROV_REASON:-none} $PROV_DETAIL"
    [ -n "$PCK_LINE" ] && echo "$PCK_LINE"
    exit 0
  fi
  echo "PROVENANCE_CHECK FAIL reason=$PROV_REASON $PROV_DETAIL" >&2
  exit "$PROV_RC"
fi

if [ -z "$TAG" ]; then
  TAG="q${QUALITY}_s${SCALE}_${SCALING}_l${LIGHTS}_sh${SHADOWS}_${RES}_f${FOV}_far${FAR}"
fi
SAFE_TAG="$(printf '%s' "$TAG" | tr -c 'A-Za-z0-9_.-' '_')"
LOG="$OUT/perf_${SAFE_TAG}.log"
PREWARM_LOG="$OUT/prewarm_${SAFE_TAG}.log"
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
PERF_OVERRIDE=0
BIN="$ROOT/tools/godot"
if [ -n "${PERF_BINARY:-}" ]; then
  if [ ! -x "$PERF_BINARY" ]; then
    echo "ABORT: PERF_BINARY=$PERF_BINARY is not executable" >&2
    exit 2
  fi
  BINARY_MODE="export"
  PERF_OVERRIDE=1
  BIN="$PERF_BINARY"
elif [ -x "$ROOT/build/tat2-linux-x86_64" ]; then
  BINARY_MODE="export"
  BIN="$ROOT/build/tat2-linux-x86_64"
fi
BIN_SHA="$(stat -c '%y %s' "$BIN" 2>/dev/null || echo unknown)"

# W7G: verify the export stamp before any measurement. The default export path
# fails closed when the stamp is missing, stale (stamp HEAD != current HEAD) or
# its artifact hashes do not match. An explicit PERF_BINARY override without a
# stamp is allowed for stubs/A-B runs but is never publishable; a stale stamp
# on an override still fails closed.
if [ "$BINARY_MODE" = "export" ]; then
  if [ "$PERF_OVERRIDE" = "1" ] && [ ! -f "$BIN.stamp.json" ]; then
    PROV_STATUS="unverified"
    PROV_REASON="unverified_override"
    PROV_PUBLISHABLE=0
    PROV_LINE="PERF_PROVENANCE mode=export publishable=0 reason=unverified_override bin=$BIN"
    PCK_LINE="PERF_PCK path=unverified sha=none bytes=0 binary_sha=unknown embedded=0"
  else
    verify_export_stamp "$BIN"; PROV_RC=$?
    case "$PROV_RC" in
      0) ;;
      3)
        echo "ABORT: export stamp is stale (stamp HEAD != current HEAD); run make linux-build before measuring (see $BIN.stamp.json)" >&2
        exit 2
        ;;
      4)
        echo "ABORT: export artifact does not match its stamp (PCK/binary SHA or size changed); rerun make linux-build" >&2
        exit 2
        ;;
      *)
        echo "ABORT: export provenance missing or unreadable ($PROV_REASON); run make linux-build before measuring" >&2
        exit 2
        ;;
    esac
  fi
else
  PROV_LINE="PERF_PROVENANCE mode=editor publishable=0 reason=editor_binary"
  PCK_LINE="PERF_PCK path=none sha=none bytes=0 binary_sha=$(sha256sum "$BIN" 2>/dev/null | awk '{print $1}') embedded=0"
fi
if [ "$PUBLISHABLE_ONLY" = "1" ] && [ "$PROV_PUBLISHABLE" != "1" ]; then
  echo "ABORT: --publishable-only but this run is not publishable (${PROV_REASON:-unknown}); build a clean stamped export" >&2
  exit 2
fi

BIN_ARGS=(
  --rendering-driver vulkan
  --audio-driver Dummy
  --script res://tests/perf/perf_matrix.gd
)
if [ "$BINARY_MODE" = "editor" ]; then
  BIN_ARGS=(--path "$ROOT/game" "${BIN_ARGS[@]}")
fi

# Rebuilt from the current FRAMES/POSE/WARMUP/DEADLINE globals so the pre-warm
# can reuse the exact same binary/display/config with a short frame count.
GAME_ARGS=()
build_game_args() {
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
    "--perf-fov=$FOV"
    "--perf-far=$FAR"
    "--perf-occlusion=$OCCLUSION"
    "--res=$RES"
    "--contract=$CONTRACT"
    "--warmup=$WARMUP"
    "--settle=$SETTLE"
    "--frames=$FRAMES"
    "--deadline=$DEADLINE"
  )
  if [ -n "$MESH_LOD" ]; then
    GAME_ARGS+=("--perf-mesh-lod=$MESH_LOD")
  fi
  if [ -n "$DIR_SHADOW" ]; then
    GAME_ARGS+=("--perf-dir-shadow=$DIR_SHADOW")
  fi
  if [ -n "$SHADOW_SPLITS" ]; then
    GAME_ARGS+=("--perf-shadow-splits=$SHADOW_SPLITS")
  fi
  if [ -n "$SHADOW_MAX_DISTANCE" ]; then
    GAME_ARGS+=("--perf-shadow-max-distance=$SHADOW_MAX_DISTANCE")
  fi
  if [ -n "$POSE" ]; then
    GAME_ARGS+=("--poses=$POSE")
  fi
  if [ -n "${TAT2_PERF_EXTRA_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    GAME_ARGS+=(${TAT2_PERF_EXTRA_ARGS})
  fi
}
build_game_args

# GPU/CPU provenance. nvidia-smi is queried in two calls so a driver that does
# not expose clock throttle reasons still yields clocks/temperature/power.
smi_gpu_sample() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    printf 'unavailable'
    return
  fi
  local base throttle
  base="$(nvidia-smi --query-gpu=name,driver_version,temperature.gpu,clocks.current.graphics,clocks.current.memory,power.draw,power.limit,utilization.gpu --format=csv,noheader 2>/dev/null | head -1)"
  if [ -z "$base" ]; then
    printf 'unavailable'
    return
  fi
  throttle="$(nvidia-smi --query-gpu=clocks_throttle_reasons.active --format=csv,noheader 2>/dev/null | head -1)"
  [ -n "$throttle" ] || throttle="unknown"
  printf '%s throttle=%s' "$base" "$throttle"
}

loadavg_sample() {
  # runnable/total and last pid keep a busy machine visible in the report.
  awk '{ printf "%s %s %s %s\n", $1, $2, $3, $4 }' /proc/loadavg 2>/dev/null || printf 'unavailable\n'
}

# CPU package temperature for the thermal guard. Prefer the kernel thermal
# zones (millidegrees) and fall back to `sensors -u`. `?` means unknown and is
# a hard failure: the wrapper refuses to run without a readable package sensor
# (the guard cannot protect a machine it cannot see).
cpu_package_temp() {
  local z t best=""
  for z in /sys/class/thermal/thermal_zone*; do
    [ -r "$z/type" ] || continue
    case "$(cat "$z/type" 2>/dev/null || true)" in
      x86_pkg_temp|TCPU|TCPU_PCI) ;;
      *) continue ;;
    esac
    t="$(cat "$z/temp" 2>/dev/null || true)"
    [ -n "$t" ] || continue
    t=$((t / 1000))
    if [ -z "$best" ] || [ "$t" -gt "$best" ]; then best="$t"; fi
  done
  if [ -z "$best" ] && command -v sensors >/dev/null 2>&1; then
    best="$(sensors -u 2>/dev/null | awk '/Package id 0:/{f=1;next} f&&/temp1_input/{printf "%d",$2;exit}')"
  fi
  printf '%s' "${best:-?}"
}

game_rss_mb() {
  local pid="$1" v
  [ -r "/proc/${pid}/status" ] || { printf '0'; return; }
  v="$(awk '/^VmRSS:/{printf "%d",$2/1024}' "/proc/${pid}/status" 2>/dev/null)"
  printf '%s' "${v:-0}"
}

# Kernel high-water mark: the peak resident set the process ever reached. It is
# cumulative and therefore survives a later drop in VmRSS, which is why the
# --max-rss-mb gate uses it (VmRSS samples are kept for the curve only).
game_vmhwm_mb() {
  local pid="$1" v
  [ -r "/proc/${pid}/status" ] || { printf '0'; return; }
  v="$(awk '/^VmHWM:/{printf "%d",$2/1024}' "/proc/${pid}/status" 2>/dev/null)"
  printf '%s' "${v:-0}"
}

# Read the key=value summary a stopped sampler wrote. Sets TH_PEAK/TH_RSS/
# TH_HWM/TH_ABORT (0 when absent, so a failed write fails closed on "abort").
read_thermal_out() {
  local f="$1"
  TH_PEAK=0; TH_RSS=0; TH_HWM=0; TH_ABORT="none"
  [ -r "$f" ] || { TH_ABORT="missing_summary"; return; }
  TH_PEAK="$(awk -F= '/^peak_temp=/{print $2}' "$f" 2>/dev/null)"
  TH_RSS="$(awk -F= '/^rss_peak_mb=/{print $2}' "$f" 2>/dev/null)"
  TH_HWM="$(awk -F= '/^vmhwm_mb=/{print $2}' "$f" 2>/dev/null)"
  TH_ABORT="$(awk -F= '/^abort=/{print $2}' "$f" 2>/dev/null)"
  TH_PEAK="${TH_PEAK:-0}"; TH_RSS="${TH_RSS:-0}"; TH_HWM="${TH_HWM:-0}"; TH_ABORT="${TH_ABORT:-none}"
}

# Kill a launch through its scope when one exists (the scope owns the whole
# process group), then the sampled PID directly. TERM first, KILL after 2 s.
kill_guarded() {
  local pid="$1" unit="$2" why="$3"
  echo "PERF_THERMAL_KILL reason=${why:-manual} pid=$pid unit=${unit:-none} ts=$(date -Is)" >> "$LOG"
  if [ -n "$unit" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop "$unit" >/dev/null 2>&1 || true
  fi
  [ -n "$pid" ] || return 0
  kill -TERM "$pid" 2>/dev/null
  sleep 2
  kill -KILL "$pid" 2>/dev/null
}

# A process is alive only if it is not a zombie: `kill -0` still succeeds for
# an unreaped child, which would keep the wait loop spinning until the timeout.
process_alive() {
  local pid="$1" st
  [ -n "$pid" ] || return 1
  [ -r "/proc/${pid}/stat" ] || return 1
  st="$(sed -n 's/^[0-9]* (.*) \(.\).*/\1/p' "/proc/${pid}/stat" 2>/dev/null | head -1)"
  [ -n "$st" ] && [ "$st" != "Z" ]
}

# --- memory scope ----------------------------------------------------------
# MemoryMax is a hard cgroup cap the kernel enforces even if the sampler is
# starved; MemorySwapMax=0 stops the run from silently paging instead of
# failing. systemd-run --scope runs the command as a child of systemd-run and
# waits synchronously, so stdio redirection is inherited unchanged.
SCOPE_MODE="direct"
detect_scope() {
  if ! command -v systemd-run >/dev/null 2>&1; then
    SCOPE_MODE="direct"
    echo "PERF_WARNING systemd-run unavailable; launching directly (no MemoryMax, no MemorySwapMax=0)" >> "$LOG"
    return
  fi
  if timeout 5 systemd-run --user --scope --quiet --collect \
      --property="MemoryMax=$MEM_MAX" --property=MemorySwapMax=0 true >/dev/null 2>&1; then
    SCOPE_MODE="systemd"
  else
    SCOPE_MODE="direct"
    echo "PERF_WARNING systemd-run --user --scope failed; launching directly (no MemoryMax, no MemorySwapMax=0)" >> "$LOG"
  fi
}

# Start one guarded launch in the background. In scope mode the game is a child
# of systemd-run, so its real PID is written by `bash -c '... exec "$@"'` into
# a pidfile before exec — that PID is what the sampler watches and kills.
LAUNCH_PID=""
GAME_PID=""
LAUNCH_UNIT=""
start_launch() { # phase logfile
  local phase="$1" logfile="$2" unit_suffix pidfile prefix=() i=0
  LAUNCH_UNIT=""
  GAME_PID=""
  [ "$logfile" = "$LOG" ] || : > "$logfile"
  if [ "$SCOPE_MODE" = "systemd" ]; then
    unit_suffix="$(printf '%s' "$SAFE_TAG" | cut -c1-48)"
    LAUNCH_UNIT="tat2-perf-${unit_suffix}-${phase}"
    pidfile="$OUT/.launch_${phase}_${SAFE_TAG}.pid"
    rm -f "$pidfile"
    prefix=(systemd-run --user --scope --quiet --collect
      --expand-environment=no
      --unit="$LAUNCH_UNIT"
      --property="MemoryMax=$MEM_MAX"
      --property=MemorySwapMax=0)
    "${prefix[@]}" "${STDBUF_CMD[@]}" "${RUN_ENV[@]}" \
      bash -c 'printf "%s\n" "$$" > "$1"; shift; exec "$@"' _ \
      "$pidfile" "$BIN" "${GAME_ARGS[@]}" >> "$logfile" 2>&1 &
    LAUNCH_PID=$!
    while [ ! -s "$pidfile" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    if [ ! -s "$pidfile" ]; then
      echo "ABORT: $phase launch did not report its PID; refusing to run unsampled" >&2
      echo "PERF_THERMAL_FAIL reason=pid_unknown phase=$phase" >> "$LOG"
      kill_guarded "$LAUNCH_PID" "$LAUNCH_UNIT" pid_unknown
      exit 8
    fi
    GAME_PID="$(cat "$pidfile")"
  else
    "${STDBUF_CMD[@]}" "${RUN_ENV[@]}" "$BIN" "${GAME_ARGS[@]}" >> "$logfile" 2>&1 &
    LAUNCH_PID=$!
    GAME_PID=$LAUNCH_PID
  fi
}

# Independent thermal sampler: its own process, its own 1 s cadence, no
# dependency on the wait loop. It writes PERF_THERMAL_SAMPLE every tick,
# rewrites the peak summary each tick (so a kill cannot lose it), and kills the
# sampled PID at >= --max-temp or on an unknown (`?`) reading. Fail closed: if
# it never starts, the caller aborts instead of running unguarded.
THERMAL_SAMPLER_PID=""
start_thermal_sampler() { # pid phase summary_file
  local pid="$1" phase="$2" out="$3" i=0
  rm -f "$out" "$out.ready"
  (
    peak=0; rss_peak=0; hwm=0; elapsed=0; reason=""
    printf 'peak_temp=0\nrss_peak_mb=0\nvmhwm_mb=0\nabort=none\n' > "$out"
    printf 'ready\n' > "$out.ready"
    while process_alive "$pid"; do
      t="$(cpu_package_temp)"
      rss="$(game_rss_mb "$pid")"
      hwm_now="$(game_vmhwm_mb "$pid")"
      [ "$hwm_now" -gt "$hwm" ] && hwm="$hwm_now"
      [ "$rss" -gt "$rss_peak" ] && rss_peak="$rss"
      if [ "$t" = "?" ] || ! [[ "$t" =~ ^[0-9]+$ ]]; then
        reason="unknown_temp"
      else
        [ "$t" -gt "$peak" ] && peak="$t"
        if [ "$t" -ge "$MAX_TEMP" ]; then reason="temp"; fi
      fi
      printf 'peak_temp=%s\nrss_peak_mb=%s\nvmhwm_mb=%s\nabort=%s\n' \
        "$peak" "$rss_peak" "$hwm" "${reason:-none}" > "$out"
      echo "PERF_THERMAL_SAMPLE phase=$phase pid=$pid t=$t rss_mb=$rss vmhwm_mb=$hwm_now elapsed=${elapsed}s max_c=$MAX_TEMP ts=$(date -Is)" >> "$LOG"
      [ -z "$reason" ] || break
      sleep "$SAMPLE_SEC"
      elapsed=$((elapsed + SAMPLE_SEC))
    done
    if [ -n "$reason" ]; then
      echo "PERF_THERMAL_ABORT phase=$phase reason=$reason peak_c=$peak max_c=$MAX_TEMP" >> "$LOG"
      kill_guarded "$pid" "$LAUNCH_UNIT" "$reason"
    fi
  ) &
  THERMAL_SAMPLER_PID=$!
  while [ ! -f "$out.ready" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  if [ ! -f "$out.ready" ]; then
    echo "ABORT: thermal sampler did not start; refusing to run unguarded" >&2
    echo "PERF_THERMAL_FAIL reason=sampler_missing phase=$phase" >> "$LOG"
    kill_guarded "$GAME_PID" "$LAUNCH_UNIT" sampler_missing
    exit 8
  fi
}

stop_thermal_sampler() {
  local pid="$THERMAL_SAMPLER_PID" i=0
  THERMAL_SAMPLER_PID=""
  [ -n "$pid" ] || return 0
  while process_alive "$pid" && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  return 0
}

# Wait for one launch without sampling (the sampler is independent). `PERF_DONE`
# is the completion marker; a windowed export may linger 10 s in teardown after
# it. A missing marker before the wall clock is a truncation/timeout.
LAUNCH_ST=0
WAIT_FORCED_KILL=0
VMHWM_MB=0
wait_launch() { # phase logfile timeout expect_done
  local phase="$1" logfile="$2" timeout_s="$3" expect_done="$4"
  local started now grace_start done_seen
  started=$(date +%s); done_seen=0; grace_start=0
  WAIT_FORCED_KILL=0; VMHWM_MB=0
  while process_alive "$GAME_PID"; do
    now=$(date +%s)
    if [ "$expect_done" = "1" ] && [ "$done_seen" -eq 0 ] && grep -q "^PERF_DONE " "$logfile" 2>/dev/null; then
      done_seen=1
      grace_start=$now
    fi
    if [ "$done_seen" -eq 1 ] && [ $((now - grace_start)) -ge 10 ]; then
      echo "PERF_TEARDOWN phase=$phase forced_kill=1 after PERF_DONE" >> "$LOG"
      kill_guarded "$GAME_PID" "$LAUNCH_UNIT" teardown
      WAIT_FORCED_KILL=1
      break
    fi
    if [ $((now - started)) -ge "$timeout_s" ]; then
      echo "PERF_TIMEOUT phase=$phase wall=${timeout_s}s no PERF_DONE" >> "$LOG"
      kill_guarded "$GAME_PID" "$LAUNCH_UNIT" timeout
      break
    fi
    sleep 1
  done
  # VmHWM at exit, before the process is reaped and /proc disappears.
  VMHWM_MB="$(game_vmhwm_mb "$GAME_PID")"
  wait "$LAUNCH_PID" 2>/dev/null
  LAUNCH_ST=$?
  if [ "$WAIT_FORCED_KILL" -eq 1 ] && grep -q "^PERF_DONE " "$logfile"; then
    LAUNCH_ST=0
  fi
}

XVFB_PID=""
DISPLAY_NUM=""
RUN_ENV=()
cleanup() {
  set +e
  if [ -n "${THERMAL_SAMPLER_PID:-}" ]; then
    kill -TERM "$THERMAL_SAMPLER_PID" 2>/dev/null
    wait "$THERMAL_SAMPLER_PID" 2>/dev/null
  fi
  if [ -n "${GAME_PID:-}" ] && process_alive "$GAME_PID"; then
    if [ -n "${LAUNCH_UNIT:-}" ] && command -v systemctl >/dev/null 2>&1; then
      systemctl --user stop "$LAUNCH_UNIT" >/dev/null 2>&1
    fi
    kill -TERM "$GAME_PID" 2>/dev/null
  fi
  if [ -n "$XVFB_PID" ]; then
    kill -TERM "$XVFB_PID" 2>/dev/null
    wait "$XVFB_PID" 2>/dev/null
  fi
  if [ -n "$DISPLAY_NUM" ]; then
    rm -f "/tmp/.X${DISPLAY_NUM}-lock" 2>/dev/null
  fi
}
trap cleanup EXIT

# Display first: the pre-warm must exercise the same presentation path as the
# measured run (host compositor or Xvfb), otherwise the clocks differ.
start_display() {
  if [ "$HOST_DISPLAY" = "1" ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    echo "PERF_DISPLAY host display=${DISPLAY:-} wayland=${WAYLAND_DISPLAY:-}" >> "$LOG"
    RUN_ENV=(env -u XAUTHORITY XDG_DATA_HOME="$DATA_HOME" TAT_GIT_SHA="$GIT_SHA")
  else
    if ! command -v Xvfb >/dev/null 2>&1; then
      echo "ABORT: no DISPLAY and Xvfb is unavailable" >&2
      exit 2
    fi
    local w="${RES%x*}"
    local h="${RES#*x}"
    local n
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
    Xvfb ":${DISPLAY_NUM}" -screen 0 "${w}x${h}x24" -nolisten tcp -ac > "$XVFBLOG" 2>&1 &
    XVFB_PID=$!
    for _i in $(seq 1 50); do
      [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] && break
      sleep 0.1
    done
    echo "PERF_DISPLAY xvfb=:${DISPLAY_NUM} pid=$XVFB_PID" >> "$LOG"
    echo "PERF_WARNING xvfb presentation adds a copy/sync path; its frame times are NOT comparable to a host compositor" >> "$LOG"
    RUN_ENV=(env -u WAYLAND_DISPLAY -u XAUTHORITY DISPLAY=":${DISPLAY_NUM}" XDG_DATA_HOME="$DATA_HOME" TAT_GIT_SHA="$GIT_SHA")
  fi
}

{
  echo "PERF_HOST tag=$SAFE_TAG git=$GIT_SHA binary_mode=$BINARY_MODE binary=$BIN binary_stat=$BIN_SHA xdg_data_home=$DATA_HOME res=$RES contract=$CONTRACT"
  echo "PERF_ARGS quality=$QUALITY scale=$SCALE scaling=$SCALING lights=$LIGHTS shadows=$SHADOWS vsync=$VSYNC fov=$FOV far=$FAR occlusion=$OCCLUSION mesh_lod=${MESH_LOD:-unset} dir_shadow=${DIR_SHADOW:-unset} shadow_splits=${SHADOW_SPLITS:-unset} shadow_max_distance=${SHADOW_MAX_DISTANCE:-unset} pose=${POSE:-all} frames=$FRAMES warmup=$WARMUP timeout=$TIMEOUT deadline=$DEADLINE prewarm=$PREWARM"
} > "$LOG"
[ -n "$PROV_LINE" ] && echo "$PROV_LINE" >> "$LOG"
[ -n "$PCK_LINE" ] && echo "$PCK_LINE" >> "$LOG"
if [ -n "$OTHER_GODOT" ]; then
  echo "PERF_WARNING other headless Godot processes are running; frame times may be CPU-contended:" >> "$LOG"
  printf '%s\n' "$OTHER_GODOT" >> "$LOG"
fi

start_display
STDBUF_CMD=()
if command -v stdbuf >/dev/null 2>&1; then STDBUF_CMD=(stdbuf -oL -eL); fi
detect_scope
echo "PERF_MEM_SCOPE mode=${SCOPE_MODE} memory_max=${MEM_MAX} memory_max_mb=${MEM_MAX_MB} swap_max=0 ram_total_mb=${RAM_TOTAL_MB:-unknown} max_rss_mb=${MAX_RSS_MB} pid=${BASHPID}" >> "$LOG"

# Pre-warm: a real run of the same scene raises clocks and temperature to the
# steady state the measured run will see. Without it "GPU before" is an idle
# clock and the before/after delta looks like throttling when it is boost.
# Like the measured run it is wrapped in a memory scope and covered by its own
# 1 s sampler; it is never launched unguarded.
TEMP_PEAK=0
TEMP_START="$(cpu_package_temp)"
PREWARM_PEAK=0
PREWARM_HWM=0
THERMAL_ABORT="none"
echo "PERF_THERMAL start=${TEMP_START} start_max=${START_TEMP} max=${MAX_TEMP} rss_max_mb=${MAX_RSS_MB} sample_sec=${SAMPLE_SEC} scope=${SCOPE_MODE} memory_max=${MEM_MAX} swap_max=0" >> "$LOG"
echo "PERF_THERMAL before=${TEMP_START}C start_c=${START_TEMP}C max_c=${MAX_TEMP}C" >> "$LOG"
DECISION="$(thermal_decision "$TEMP_START" "$START_TEMP" "$MAX_TEMP")"
case "$DECISION" in
  unknown)
    echo "ABORT: CPU package temperature is unknown (?); refusing to run unguarded (fail closed)" >&2
    echo "PERF_THERMAL_FAIL reason=unknown_temp phase=precheck" >> "$LOG"
    exit 8
    ;;
  refuse_max)
    echo "ABORT: CPU package ${TEMP_START}C >= --max-temp ${MAX_TEMP}C; cool the machine before measuring" >&2
    exit 8
    ;;
  refuse_start)
    echo "ABORT: CPU package ${TEMP_START}C > --start-temp ${START_TEMP}C (max ${MAX_TEMP}C); refusing to start a sustained run, let the machine idle down first" >&2
    exit 8
    ;;
esac

PREWARM_STATUS="skipped"
if [ "$PREWARM" = "1" ]; then
  SAVED_FRAMES="$FRAMES"; SAVED_POSE="$POSE"; SAVED_WARMUP="$WARMUP"; SAVED_DEADLINE="$DEADLINE"
  FRAMES="120"
  POSE="spawn_overlook"
  WARMUP="30"
  DEADLINE="$PREWARM_TIMEOUT"
  build_game_args
  PW_OUT="$OUT/.thermal_prewarm_${SAFE_TAG}.summary"
  start_launch prewarm "$PREWARM_LOG"
  start_thermal_sampler "$GAME_PID" prewarm "$PW_OUT"
  wait_launch prewarm "$PREWARM_LOG" "$PREWARM_TIMEOUT" 1
  PW_ST=$LAUNCH_ST
  stop_thermal_sampler
  read_thermal_out "$PW_OUT"
  PREWARM_PEAK=$TH_PEAK
  PREWARM_HWM=$TH_HWM
  [ "$TH_RSS" -gt "$PREWARM_HWM" ] && PREWARM_HWM=$TH_RSS
  echo "PERF_THERMAL_PREWARM_PEAK peak_c=${PREWARM_PEAK} peak_rss_mb=${TH_RSS} vmhwm_mb=${PREWARM_HWM} max_c=${MAX_TEMP} abort=${TH_ABORT}" >> "$LOG"
  if grep -q "^PERF_DONE " "$PREWARM_LOG"; then
    PREWARM_STATUS="ok exit=$PW_ST"
  else
    PREWARM_STATUS="incomplete exit=$PW_ST"
    echo "PERF_WARNING pre-warm did not reach PERF_DONE (see $PREWARM_LOG); clocks may still be rising" >> "$LOG"
  fi
  FRAMES="$SAVED_FRAMES"; POSE="$SAVED_POSE"; WARMUP="$SAVED_WARMUP"; DEADLINE="$SAVED_DEADLINE"
  build_game_args
  case "$TH_ABORT" in
    none) ;;
    *)
      THERMAL_ABORT="$TH_ABORT"
      echo "PERF_THERMAL_FAIL reason=${TH_ABORT} phase=prewarm peak_c=${PREWARM_PEAK}" >> "$LOG"
      echo "FAIL: pre-warm thermal abort (${TH_ABORT} at ${PREWARM_PEAK}C, max ${MAX_TEMP}C); measured run not started (see $PREWARM_LOG)" >&2
      exit 8
      ;;
  esac
  if [ "$PREWARM_HWM" -gt "$MAX_RSS_MB" ]; then
    echo "PERF_RSS_FAIL phase=prewarm vmhwm_mb=${PREWARM_HWM} max_rss_mb=${MAX_RSS_MB}" >> "$LOG"
    echo "FAIL: pre-warm VmHWM ${PREWARM_HWM} MB > --max-rss-mb ${MAX_RSS_MB} MB (see $PREWARM_LOG)" >&2
    exit 9
  fi
fi
echo "PERF_THERMAL prewarm_after=$(cpu_package_temp)C" >> "$LOG"
echo "PERF_PREWARM status=$PREWARM_STATUS frames=120 pose=spawn_overlook peak_c=${PREWARM_PEAK} vmhwm_mb=${PREWARM_HWM} log=$PREWARM_LOG" >> "$LOG"

echo "PERF_GPU_BEFORE $(smi_gpu_sample) ts=$(date -Is)" >> "$LOG"
echo "PERF_LOAD_BEFORE $(loadavg_sample) ts=$(date -Is)" >> "$LOG"

# Measured run. The sampler owns the temperature and RSS cadence; this block
# only starts the launch, waits on process liveness/timeout, and enforces the
# recorded peak afterwards.
MEASURE_START=$(date +%s)
RUN_OUT="$OUT/.thermal_run_${SAFE_TAG}.summary"
start_launch run "$LOG"
start_thermal_sampler "$GAME_PID" run "$RUN_OUT"
wait_launch run "$LOG" "$TIMEOUT" 1
ST=$LAUNCH_ST
stop_thermal_sampler
read_thermal_out "$RUN_OUT"
TEMP_PEAK=$TH_PEAK
RSS_SAMPLES=$TH_RSS
RSS_HWM=$TH_HWM
THERMAL_ABORT=$TH_ABORT
[ "$VMHWM_MB" -gt "$RSS_HWM" ] && RSS_HWM=$VMHWM_MB
MEASURE_SEC=$(( $(date +%s) - MEASURE_START ))

echo "PERF_GPU_AFTER $(smi_gpu_sample) ts=$(date -Is) measure_sec=$MEASURE_SEC" >> "$LOG"
echo "PERF_LOAD_AFTER $(loadavg_sample) ts=$(date -Is)" >> "$LOG"
echo "PERF_THERMAL peak_cpu_c=$TEMP_PEAK prewarm_peak_c=$PREWARM_PEAK peak_rss_mb=$RSS_SAMPLES vmhwm_mb=$RSS_HWM max_c=$MAX_TEMP start_max_c=$START_TEMP rss_max_mb=$MAX_RSS_MB sample_sec=$SAMPLE_SEC scope=$SCOPE_MODE abort=$THERMAL_ABORT" >> "$LOG"

echo "EXIT=$ST LOG=$LOG"
grep -E "^PERF_|^[{]|SCRIPT ERROR|SHADER ERROR|Too many mipmaps|double free" "$LOG" | tail -100

if [ "$THERMAL_ABORT" != "none" ]; then
  echo "FAIL: thermal guard (${THERMAL_ABORT}) at peak ${TEMP_PEAK}C (max ${MAX_TEMP}C); let the machine cool and rerun (see $LOG)" >&2
  exit 8
fi
if [ "$RSS_HWM" -gt "$MAX_RSS_MB" ]; then
  echo "PERF_RSS_FAIL phase=run vmhwm_mb=${RSS_HWM} max_rss_mb=${MAX_RSS_MB}" >> "$LOG"
  echo "FAIL: VmHWM ${RSS_HWM} MB > --max-rss-mb ${MAX_RSS_MB} MB (see $LOG)" >&2
  exit 9
fi

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
