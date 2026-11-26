#!/usr/bin/env bash
# P0a evidence runner (wave P0a, Lane E) — the complete, reproducible gate set.
#
# Why this file exists
# --------------------
# The W10-A2 batch deadlocked: the orchestrator wrapped the whole batch in
# `flock /tmp/opencode/tat2-godot.lock`, then `build/qa/runtime_smoke.sh` took
# the same lock for itself and waited on its own parent forever. It also used
# the wrong leak-probe path (`res://probe_leak.gd` is the real one) and never
# ran runtime smoke / audit / texture cap / perf guard / gate ratchet.
#
# Rules encoded here:
#   * Never hold the Godot lock across the runner. Each Godot invocation takes
#     the lock itself (`flock <lock> tools/godot ...`). `runtime_smoke.sh`
#     takes the lock internally, so it is invoked WITHOUT an outer flock.
#   * Start refuses to run if another process already holds the lock (that is
#     the deadlock shape: an outer lock around this script).
#   * Every gate's full output goes to `docs/reports/logs/p0a/<gate>.log` with
#     the exact command line, start time, exit code and finish time.
#   * Any non-zero exit stops the run (runtime smoke is expected to pass the
#     scan with the inner `timeout` exit 124; `runtime_smoke.sh` itself returns
#     0 only when that scan passed).
#   * `normalize.log` is produced by the integrator (`make normalize` at the
#     merged HEAD) and is kept, never overwritten here: this lane does not
#     regenerate shared data.
#
# Usage:
#   build/qa/run_p0a_gates.sh
#
# Exit: 0 only when every gate passed; the failing gate's exit code otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/docs/reports/logs/p0a"
MASTER="$OUT/p0a-run.log"
SUMMARY="$OUT/p0a-summary.txt"
LOCK="/tmp/opencode/tat2-godot.lock"

mkdir -p "$OUT" "$(dirname "$LOCK")" || exit 2
cd "$ROOT" || exit 2

say() {
	printf '%s\n' "$*"
	printf '%s\n' "$*" >>"$MASTER"
}

# --- provenance -------------------------------------------------------------
HEAD_SHA="$(git rev-parse HEAD)"
BRANCH="$(git symbolic-ref --short -q HEAD || echo detached)"
GODOT_VERSION="$(tools/godot --version 2>&1)"
DIRTY="$(git status --porcelain | wc -l)"

{
	printf 'P0A_GATE_RUN\n'
	printf 'started: %s\n' "$(date -Is)"
	printf 'root: %s\n' "$ROOT"
	printf 'head: %s\n' "$HEAD_SHA"
	printf 'branch: %s\n' "$BRANCH"
	printf 'godot: %s\n' "$GODOT_VERSION"
	printf 'godot_bin: %s\n' "$ROOT/tools/godot"
	printf 'lock: %s\n' "$LOCK"
	printf 'uncommitted_entries_at_start: %s\n' "$DIRTY"
	printf 'host: %s\n' "$(uname -srm)"
	printf 'nproc: %s\n' "$(nproc 2>/dev/null || echo '?')"
	printf 'runner: %s\n' "build/qa/run_p0a_gates.sh"
	printf '\n'
} >"$MASTER"
: >"$SUMMARY"

# Refuse to start inside an outer Godot lock: that is the W10-A2 deadlock.
if ! flock -n "$LOCK" true; then
	say "P0A_GATES BLOCKED: another process holds $LOCK."
	say "Do NOT wrap this runner in flock; runtime_smoke.sh takes the lock itself."
	exit 2
fi

say "P0A_GATES start head=$HEAD_SHA branch=$BRANCH godot=$GODOT_VERSION"

GATE_COUNT=0

gate() { # gate <name> <log> <command...>
	local name="${1:?gate name}"
	local log="${2:?gate log path}"
	shift 2
	local start end code log_rel
	start="$(date -Is)"
	{
		printf '== P0A_GATE %s\n' "$name"
		printf 'COMMAND:'
		printf ' %q' "$@"
		printf '\nCWD: %s\nSTARTED: %s\n\n' "$ROOT" "$start"
	} >"$log"
	"$@" >>"$log" 2>&1
	code=$?
	end="$(date -Is)"
	{
		printf '\nEXIT: %d\nFINISHED: %s\n' "$code" "$end"
	} >>"$log"
	log_rel="${log#"$ROOT"/}"
	printf '%s\texit=%d\t%s\t%s\n' "$name" "$code" "$start" "$log_rel" >>"$SUMMARY"
	say "P0A_GATE name=$name exit=$code log=$log_rel"
	GATE_COUNT=$((GATE_COUNT + 1))
	if [ "$code" -ne 0 ]; then
		say "P0A_GATES FAIL gate=$name exit=$code log=$log_rel"
		say "--- last 25 lines of $log_rel ---"
		tail -25 "$log" | tee -a "$MASTER"
		say "--- end $log_rel ---"
		exit "$code"
	fi
}

# 1. Script compile + the two suite runners.
gate compile "$OUT/compile.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script "$ROOT/tools/check_scripts_compile.gd"

gate run_tests "$OUT/run_tests.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/run_tests.gd

gate m2 "$OUT/m2.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_m2_player.gd

# 2. Guard selection (PARITY_APPROX bucket/layer rule): Guildhall Contract 2
#    must select the authored Lounge C_20 (StandardGuards_Bouncers), never the
#    Hauntstable C_16; Old Manor day-1 is the same Novice-labelled rule.
gate probe_guard_positions_guildhall "$OUT/probe_guard_positions_guildhall.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_guard_positions.gd

gate probe_guard_positions_old_manor "$OUT/probe_guard_positions_old_manor.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_guard_positions.gd -- --map=old_manor --order=3

# 3. Authored-collision / lock / VFX / traversal / geometry / device probes.
gate probe_collision_authored "$OUT/probe_collision_authored.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_collision_authored.gd

gate probe_lock_inventory "$OUT/probe_lock_inventory.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_lock_inventory.gd

gate probe_niagara "$OUT/probe_niagara.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_niagara.gd

gate probe_door_walk "$OUT/probe_door_walk.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_door_walk.gd

gate probe_viewmodel_truth "$OUT/probe_viewmodel_truth.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_viewmodel_truth.gd

gate probe_geometry_placement "$OUT/probe_geometry_placement.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_geometry_placement.gd

gate probe_blackjack_race "$OUT/probe_blackjack_race.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_blackjack_race.gd

gate probe_device_meshes "$OUT/probe_device_meshes.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_device_meshes.gd

gate probe_gc_destruction "$OUT/probe_gc_destruction.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_gc_destruction.gd

# 4. Standalone P0a/W10-A2 tests.
gate test_gc_break_trigger "$OUT/test_gc_break_trigger.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_gc_break_trigger.gd

gate test_w10a2_civilian "$OUT/test_w10a2_civilian.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_w10a2_civilian.gd

gate test_w10a2_guard_placement "$OUT/test_w10a2_guard_placement.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_w10a2_guard_placement.gd

gate test_beam_geometry "$OUT/test_beam_geometry.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_beam_geometry.gd

# 5. Leak probe. The correct path is res://probe_leak.gd (not tests/), and the
#    7 teardown texture-RID warnings are silenced by TAT2_NO_DEN_PROBE=1.
gate probe_leak "$OUT/probe_leak.log" \
	env TAT2_NO_DEN_PROBE=1 flock "$LOCK" tools/godot --headless --path game \
	--script res://probe_leak.gd

# 6. Full E2E (all tiers).
gate e2e "$OUT/e2e.log" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/e2e/run_e2e_tests.gd

# 7. Runtime smoke: NO outer flock — the script takes the lock itself and
#    expects the inner `timeout` kill (exit 124), then scans the log.
gate runtime_smoke "$OUT/runtime_smoke.log" \
	"$ROOT/build/qa/runtime_smoke.sh" 90

SMOKE_GODOT_LOG="$(awk '/^log: /{p=$2} END{print p}' "$OUT/runtime_smoke.log")"
if [ -z "$SMOKE_GODOT_LOG" ] || [ ! -f "$SMOKE_GODOT_LOG" ]; then
	say "P0A_GATES FAIL gate=runtime_smoke no Godot log path in runtime_smoke.log"
	exit 3
fi
cp -- "$SMOKE_GODOT_LOG" "$OUT/runtime_smoke_godot.log"
if ! grep -q 'RUNTIME_SMOKE_SCAN PASS exit=124 ' "$OUT/runtime_smoke.log"; then
	say "P0A_GATES FAIL gate=runtime_smoke scan did not report PASS exit=124"
	tail -5 "$OUT/runtime_smoke.log" | tee -a "$MASTER"
	exit 3
fi
say "P0A_SMOKE_GODOT_LOG $OUT/runtime_smoke_godot.log (from $SMOKE_GODOT_LOG)"

gate runtime_smoke_scan "$OUT/runtime_smoke_scan.log" \
	"$ROOT/build/qa/test_runtime_smoke_scan.sh"

# 8. Static audit family. `make audit` includes texture-cap-check, string-audit
#    and check-greps; the separate runs below own their ratchet evidence logs.
gate string_audit "$OUT/string_audit.log" make string-audit
gate literal_greps "$OUT/literal_greps.log" make check-greps
gate audit "$OUT/audit.log" make audit
gate texture_cap "$OUT/texture_cap.log" make texture-cap-check
gate perf_guard "$OUT/perf_guard.log" build/qa/test_perf_guard.sh
gate gate_ratchet "$OUT/gate_ratchet.log" make gate-ratchet

say "P0A_GATES PASS head=$HEAD_SHA gates=$GATE_COUNT"
say "P0A_GATES evidence=$OUT summary=$SUMMARY"
exit 0
