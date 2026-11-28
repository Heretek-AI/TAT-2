#!/usr/bin/env bash
# Played-route input driver wrapper (Phase 3C instrument).
#
#   build/qa/route_driver.sh --tag=den_telescope
#   build/qa/route_driver.sh --tag=den_telescope --seed=1025051536
#
# Headless only: no Xvfb, no Vulkan, no screenshot. The driver executes a short
# input-driven segment (Den S03 arrival + S05 telescope enter/exit) and writes
# docs/reports/logs/p0b-route-driver/<tag>/manifest.json. It is NOT the full
# 27-beat played route; route_claim stays "none".
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="/tmp/opencode/tat2-godot.lock"
TAG="den_telescope"
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
case "$SEED" in
'' | *[!0-9]*)
  echo "ABORT: --seed must be an integer" >&2
  exit 2
  ;;
esac

mkdir -p "$(dirname "$LOCK")" || exit 2
export TAT2_PARITY_ONLY=1

T0=$(date +%s)
flock "$LOCK" -c "timeout 1200 \"$ROOT/tools/godot\" --headless --path \"$ROOT/game\" --script \"$ROOT/build/qa/route_driver.gd\" -- --segment=den_telescope --tag=$TAG --seed=$SEED"
CODE=$?
T1=$(date +%s)
echo "ROUTE_DRIVER_WALL tag=$TAG seed=$SEED exit=$CODE wall=$((T1 - T0))s (headless, no GPU render)"
exit "$CODE"
