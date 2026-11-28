#!/usr/bin/env bash
# Played-route input driver wrapper (Phase 3C instrument + Phase 3 played-route).
#
#   build/qa/route_driver.sh --tag=den_telescope
#   build/qa/route_driver.sh --segment=cleanout_route --tag=cleanout_route
#   build/qa/route_driver.sh --tag=den_telescope --seed=1025051536
#
# Headless only: no Xvfb, no Vulkan, no screenshot. The driver executes an
# input-driven segment and writes
# docs/reports/logs/p0b-route-driver/<tag>/manifest.json plus driver.log.
# `den_telescope` is the short Phase 3C segment; `cleanout_route` is the
# continuous route front (menu -> Den -> first-class Cleanout -> safe room).
# Neither is the full 27-beat played route: route_claim stays "none".
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="/tmp/opencode/tat2-godot.lock"
TAG="den_telescope"
SEGMENT="den_telescope"
SEED="1025051536"

usage() {
  awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
  --tag=*) TAG="${1#*=}" ;;
  --tag)
    shift
    TAG="${1:-den_telescope}"
    ;;
  --segment=*) SEGMENT="${1#*=}" ;;
  --segment)
    shift
    SEGMENT="${1:-den_telescope}"
    ;;
  --seed=*) SEED="${1#*=}" ;;
  --seed)
    shift
    SEED="${1:-1025051536}"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
  shift
done

if ! printf '%s' "$TAG" | grep -Eq '^[A-Za-z0-9._-]+$'; then
  echo "ABORT: --tag must be [A-Za-z0-9._-]+" >&2
  exit 2
fi
case "$SEGMENT" in
den_telescope | cleanout_route) ;;
*)
  echo "ABORT: --segment must be den_telescope|cleanout_route" >&2
  exit 2
  ;;
esac
case "$SEED" in
'' | *[!0-9]*)
  echo "ABORT: --seed must be an integer" >&2
  exit 2
  ;;
esac

LOG_DIR="$ROOT/docs/reports/logs/p0b-route-driver/$TAG"
mkdir -p "$LOG_DIR" "$(dirname "$LOCK")" || exit 2
LOG="$LOG_DIR/driver.log"
export TAT2_PARITY_ONLY=1

T0=$(date +%s)
# shellcheck disable=SC2086
flock "$LOCK" -c "timeout 1800 \"$ROOT/tools/godot\" --headless --path \"$ROOT/game\" --script \"$ROOT/build/qa/route_driver.gd\" -- --segment=$SEGMENT --tag=$TAG --seed=$SEED" 2>&1 | tee "$LOG"
CODE=${PIPESTATUS[0]}
T1=$(date +%s)
echo "ROUTE_DRIVER_WALL tag=$TAG segment=$SEGMENT seed=$SEED exit=$CODE wall=$((T1 - T0))s (headless, no GPU render) log=$LOG"

# The Cleanout acceptance requires the engine's own run-clock line to name the
# mission row (3300 s, not the 7200 s map row). Fail closed if it is absent.
if [ "$SEGMENT" = "cleanout_route" ]; then
  if grep -Eq 'TAT-2 run clock: map=guildhall mission=Mission\.Guildhall\.LootTheRoom main_s=3300(\.0+)? main_source=mission_row' "$LOG"; then
    echo "ROUTE_DRIVER_CLOCK PASS main_source=mission_row main_s=3300"
  else
    echo "ROUTE_DRIVER_CLOCK FAIL: no 'TAT-2 run clock: map=guildhall ... main_source=mission_row' line in $LOG" >&2
    echo "  measured lines:" >&2
    grep -E 'TAT-2 run clock:' "$LOG" >&2 || true
    exit 3
  fi
fi
exit "$CODE"
