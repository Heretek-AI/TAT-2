#!/usr/bin/env bash
## W9-P1 A/B: authored UE `AggGeom` collision vs the pre-W9 AABB heuristic.
##
## Runs `game/tests/probe_collision_authored.gd` twice on the same 15-file
## Guildhall ground set — once with TAT2_COLLISION=authored (the shipped
## default) and once with TAT2_COLLISION=aabb (the control) — prints both
## COL_AUDIT lines plus the delta, and exits non-zero if either run fails.
##
## Godot is single-instance on this host: both runs go through the same flock
## the capture lane uses, serially. No python, no GPU, headless only.
##
##   build/qa/w9_collision_ab.sh
##
## Logs: build/qa/w9/logs/collision_ab_<mode>.log (git-ignored, as usual).

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
ROOT="$PWD"
PROBE="res://tests/probe_collision_authored.gd"
LOG_DIR="$ROOT/build/qa/w9/logs"
LOCK="/tmp/opencode/tat2-godot.lock"
mkdir -p "$LOG_DIR"

run_mode() {
	local mode="$1"
	local log="$LOG_DIR/collision_ab_${mode}.log"
	# Bounded lock wait: a wedged sibling run must never turn this script into
	# the queue blocker (W9-P1 incident: a hung probe held the lock for 25 min).
	flock -w 300 "$LOCK" -c "cd '$ROOT' && TAT2_COLLISION=$mode timeout 300 tools/godot --headless --path game --script $PROBE" >"$log" 2>&1
	local rc=$?
	grep -E '^COL_(AUDIT|DETAIL|WALL)' "$log" || true
	if [ "$rc" -ne 0 ]; then
		echo "COL_AUDIT FAIL $mode run exited $rc (see $log)" >&2
	fi
	return "$rc"
}

field() {
	# field <line> <name> -> value (empty when absent)
	echo "$1" | sed -n "s/.*[[:space:]]$2=\([^[:space:]]*\).*/\1/p"
}

echo "=== W9-P1 collision A/B (15-file Guildhall ground set) ==="

AUTH_OUT="$(run_mode authored)"
AUTH_RC=$?
AUTH_LINE="$(echo "$AUTH_OUT" | grep -m1 '^COL_AUDIT mode=' || true)"
echo "--- authored ---"
echo "$AUTH_OUT" | grep -E '^COL_AUDIT ' || echo "(no COL_AUDIT line)"

AABB_OUT="$(run_mode aabb)"
AABB_RC=$?
AABB_LINE="$(echo "$AABB_OUT" | grep -m1 '^COL_AUDIT mode=' || true)"
echo "--- aabb (control) ---"
echo "$AABB_OUT" | grep -E '^COL_AUDIT ' || echo "(no COL_AUDIT line)"

if [ -z "$AUTH_LINE" ] || [ -z "$AABB_LINE" ]; then
	echo "COL_AUDIT FAIL missing COL_AUDIT line (authored_rc=$AUTH_RC aabb_rc=$AABB_RC)" >&2
	exit 1
fi

STATS="placed_meshes placed_instances authored_hull authored_prims absent no_collision query_only reduced shapes bodies dropped load_ms"
echo "--- delta (authored - aabb) ---"
for name in $STATS; do
	a="$(field "$AUTH_LINE" "$name")"
	b="$(field "$AABB_LINE" "$name")"
	case "$a$b" in
		''|*[!0-9]*) printf '%-18s %s -> %s\n' "$name" "${a:-?}" "${b:-?}" ;;
		*) printf '%-18s %s -> %s (%+d)\n' "$name" "$b" "$a" "$((a - b))" ;;
	esac
done

AUTH_SHAPES="$(field "$AUTH_LINE" shapes)"
AABB_SHAPES="$(field "$AABB_LINE" shapes)"
AUTH_DROPPED="$(field "$AUTH_LINE" dropped)"
AABB_DROPPED="$(field "$AABB_LINE" dropped)"
AUTH_HULL="$(field "$AUTH_LINE" authored_hull)"
AUTH_PRIMS="$(field "$AUTH_LINE" authored_prims)"
AUTH_PLACED="$(field "$AUTH_LINE" placed_meshes)"

echo "--- verdict ---"
echo "authored shapes=${AUTH_SHAPES:-?} aabb shapes=${AABB_SHAPES:-?}"
echo "authored-derived coverage=${AUTH_HULL:-?}+${AUTH_PRIMS:-?} of ${AUTH_PLACED:-?} placed meshes"

RC=0
[ "$AUTH_RC" -ne 0 ] && RC=1
[ "$AABB_RC" -ne 0 ] && RC=1
[ "${AUTH_DROPPED:-1}" != "0" ] && { echo "COL_AUDIT FAIL authored dropped=${AUTH_DROPPED:-?}" >&2; RC=1; }
[ "${AABB_DROPPED:-1}" != "0" ] && { echo "COL_AUDIT FAIL aabb dropped=${AABB_DROPPED:-?}" >&2; RC=1; }
if [ "$RC" -eq 0 ]; then
	echo "COLLISION_AB PASS"
else
	echo "COLLISION_AB FAIL"
fi
exit "$RC"
