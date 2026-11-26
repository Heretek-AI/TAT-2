#!/usr/bin/env bash
# P0b evidence runner — the full P0a 28-gate set at merged HEAD plus the P0b
# instruments (E2E a2 standalone + p2, parity-only governance, cream RED proof,
# capture dry-run/self-test + manifest validation + KF27 reference calibration).
#
# Why a separate file instead of editing run_p0a_gates.sh
# --------------------------------------------------------
# `run_p0a_gates.sh` is the committed P0a evidence artifact and its log
# directory (`docs/reports/logs/p0a/`) is still the ratchet evidence for the
# floors measured at 84912ee. P0b re-measures the same set at the merged HEAD
# into its own directory so a later wave can tell the two runs apart.
#
# Rules encoded here (same contract as P0a)
# -----------------------------------------
#   * Never hold the Godot lock across the runner. Each Godot invocation takes
#     the lock itself (`flock <lock> tools/godot ...`).
#   * `runtime_smoke.sh` and `p0b_capture.sh` take the lock internally, so they
#     are invoked WITHOUT an outer flock (an outer lock deadlocks them).
#   * Start refuses to run if another process already holds the lock.
#   * Every gate's full output goes to `docs/reports/logs/p0b/full/<gate>.log`
#     with the exact command line, start time, exit code and finish time.
#   * Any unexpected non-zero exit stops the run. The cream RED proof is the
#     only expected failure: exit 1 with
#     `CREAM_PROOF: RED passes=2 expected_fail=2` is recorded and does not fail
#     the run.
#   * Generated data and the extract are read-only for this lane: the runner
#     never calls `make normalize` or a producer.
#
# Usage:
#   build/qa/run_p0b_gates.sh
#
# Exit: 0 only when every gate passed (with cream RED as designed); the failing
# gate's exit code otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/docs/reports/logs/p0b/full"
MASTER="$OUT/p0b-run.log"
SUMMARY="$OUT/p0b-summary.txt"
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
	printf 'P0B_GATE_RUN\n'
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
	printf 'runner: %s\n' "build/qa/run_p0b_gates.sh"
	printf '\n'
} >"$MASTER"
: >"$SUMMARY"

# Refuse to start inside an outer Godot lock: that is the W10-A2 deadlock.
if ! flock -n "$LOCK" true; then
	say "P0B_GATES BLOCKED: another process holds $LOCK."
	say "Do NOT wrap this runner in flock; runtime_smoke.sh/p0b_capture.sh take it themselves."
	exit 2
fi

say "P0B_GATES start head=$HEAD_SHA branch=$BRANCH godot=$GODOT_VERSION"

GATE_COUNT=0
EXPECTED_COUNT=0

_open_log() { # <name> <log> <command...>
	local name="${1:?gate name}"
	local log="${2:?gate log path}"
	shift 2
	{
		printf '== P0B_GATE %s\n' "$name"
		printf 'COMMAND:'
		printf ' %q' "$@"
		printf '\nCWD: %s\nSTARTED: %s\n\n' "$ROOT" "$(date -Is)"
	} >"$log"
}

_finish_log() { # <log> <code>
	{
		printf '\nEXIT: %d\nFINISHED: %s\n' "${2:?code}" "$(date -Is)"
	} >>"${1:?log}"
}

gate() { # gate <name> <log> <command...> — exit 0 required
	local name="${1:?gate name}"
	local log="${2:?gate log path}"
	shift 2
	local code log_rel
	_open_log "$name" "$log" "$@"
	"$@" >>"$log" 2>&1
	code=$?
	_finish_log "$log" "$code"
	log_rel="${log#"$ROOT"/}"
	GATE_COUNT=$((GATE_COUNT + 1))
	printf '%s\texit=%d\t%s\n' "$name" "$code" "$log_rel" >>"$SUMMARY"
	say "P0B_GATE name=$name exit=$code log=$log_rel"
	if [ "$code" -ne 0 ]; then
		say "P0B_GATES FAIL gate=$name exit=$code log=$log_rel"
		say "--- last 25 lines of $log_rel ---"
		tail -25 "$log" | tee -a "$MASTER"
		say "--- end $log_rel ---"
		exit "$code"
	fi
}

gate_marker() { # gate_marker <name> <log> <literal marker> <command...>
	local name="${1:?gate name}"
	local log="${2:?gate log path}"
	local marker="${3:?marker}"
	shift 3
	local code log_rel
	_open_log "$name" "$log" "$@"
	"$@" >>"$log" 2>&1
	code=$?
	_finish_log "$log" "$code"
	log_rel="${log#"$ROOT"/}"
	GATE_COUNT=$((GATE_COUNT + 1))
	printf '%s\texit=%d\t%s\n' "$name" "$code" "$log_rel" >>"$SUMMARY"
	say "P0B_GATE name=$name exit=$code log=$log_rel"
	if [ "$code" -ne 0 ]; then
		say "P0B_GATES FAIL gate=$name exit=$code log=$log_rel"
		say "--- last 25 lines of $log_rel ---"
		tail -25 "$log" | tee -a "$MASTER"
		say "--- end $log_rel ---"
		exit "$code"
	fi
	if ! grep -Fq -- "$marker" "$log"; then
		say "P0B_GATES FAIL gate=$name missing marker: $marker log=$log_rel"
		tail -25 "$log" | tee -a "$MASTER"
		exit 4
	fi
	say "P0B_MARKER name=$name marker=$marker"
}

expected_gate() { # expected_gate <name> <log> <expected exit> <marker> <command...>
	local name="${1:?gate name}"
	local log="${2:?gate log path}"
	local want="${3:?expected exit}"
	local marker="${4:?marker}"
	shift 4
	local code log_rel
	_open_log "$name" "$log" "$@"
	"$@" >>"$log" 2>&1
	code=$?
	_finish_log "$log" "$code"
	log_rel="${log#"$ROOT"/}"
	EXPECTED_COUNT=$((EXPECTED_COUNT + 1))
	printf '%s\texit=%d(expected=%d)\t%s\n' "$name" "$code" "$want" "$log_rel" >>"$SUMMARY"
	say "P0B_EXPECTED_GATE name=$name exit=$code expected=$want log=$log_rel"
	if [ "$code" -ne "$want" ]; then
		say "P0B_GATES FAIL gate=$name exit=$code expected=$want log=$log_rel"
		tail -25 "$log" | tee -a "$MASTER"
		exit 5
	fi
	if ! grep -Fq -- "$marker" "$log"; then
		say "P0B_GATES FAIL gate=$name missing marker: $marker log=$log_rel"
		tail -25 "$log" | tee -a "$MASTER"
		exit 6
	fi
	say "P0B_EXPECTED_MARKER name=$name marker=$marker"
}

# 1. Script compile + the two suite runners.
gate_marker compile "$OUT/compile.log" ", broken: 0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script "$ROOT/tools/check_scripts_compile.gd"

gate_marker run_tests "$OUT/run_tests.log" "SUMMARY: fails=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/run_tests.gd

gate_marker m2 "$OUT/m2.log" "M2_SUMMARY: fails=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_m2_player.gd

# 2. Guard selection (PARITY_APPROX bucket/layer rule): Guildhall Contract 2
#    must select the authored Lounge C_20 (StandardGuards_Bouncers), never the
#    Hauntstable C_16; Old Manor day-1 is the same Novice-labelled rule.
gate_marker probe_guard_positions_guildhall "$OUT/probe_guard_positions_guildhall.log" \
	"GUARD_CHECK PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_guard_positions.gd

gate_marker probe_guard_positions_old_manor "$OUT/probe_guard_positions_old_manor.log" \
	"GUARD_CHECK PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_guard_positions.gd -- --map=old_manor --order=3

# 3. Authored-collision / lock / VFX / traversal / geometry / device probes.
gate_marker probe_collision_authored "$OUT/probe_collision_authored.log" \
	"COL_MAPS PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_collision_authored.gd

gate_marker probe_lock_inventory "$OUT/probe_lock_inventory.log" \
	"state=APPLIED" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_lock_inventory.gd

gate_marker probe_niagara "$OUT/probe_niagara.log" "NIAGARA_PROBE PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_niagara.gd

gate_marker probe_door_walk "$OUT/probe_door_walk.log" "DOORWALK PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_door_walk.gd

gate_marker probe_viewmodel_truth "$OUT/probe_viewmodel_truth.log" "VIEWMODEL_TRUTH PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_viewmodel_truth.gd

gate_marker probe_geometry_placement "$OUT/probe_geometry_placement.log" "GEOM_PROBE PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_geometry_placement.gd

gate_marker probe_blackjack_race "$OUT/probe_blackjack_race.log" "BLACKJACK_PROBE PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_blackjack_race.gd

gate_marker probe_device_meshes "$OUT/probe_device_meshes.log" "TURRET_PROBE PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_device_meshes.gd

gate_marker probe_gc_destruction "$OUT/probe_gc_destruction.log" "GC_PROBE PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_gc_destruction.gd

# 4. Standalone P0a/W10-A2 tests.
gate_marker test_gc_break_trigger "$OUT/test_gc_break_trigger.log" "GC_TRIGGER PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_gc_break_trigger.gd

gate_marker test_w10a2_civilian "$OUT/test_w10a2_civilian.log" "W10A2_CIV_SUMMARY: fails=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_w10a2_civilian.gd

gate_marker test_w10a2_guard_placement "$OUT/test_w10a2_guard_placement.log" \
	"GUARD_PLACEMENT_SUMMARY: fails=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_w10a2_guard_placement.gd

gate_marker test_beam_geometry "$OUT/test_beam_geometry.log" "BEAM_GEOMETRY_SUMMARY: fails=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_beam_geometry.gd

# 5. Leak probe. The correct path is res://probe_leak.gd (not tests/), and the
#    7 teardown texture-RID warnings are silenced by TAT2_NO_DEN_PROBE=1.
gate_marker probe_leak "$OUT/probe_leak.log" "PROBE start" \
	env TAT2_NO_DEN_PROBE=1 flock "$LOCK" tools/godot --headless --path game \
	--script res://probe_leak.gd

# 6. Full E2E (all tiers, a2 included since P0b).
gate_marker e2e "$OUT/e2e.log" "SUMMARY: fails=0 passed=300 total=300" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/e2e/run_e2e_tests.gd

# 7. P0b harness gates.
#    a2 standalone stays in the set so its own ratchet log is measured at the
#    same HEAD as the full run (the tier also runs inside `all`).
gate_marker e2e_a2 "$OUT/e2e_a2.log" "SUMMARY: fails=0 passed=22 total=22" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/e2e/run_e2e_tests.gd -- --tier=a2

#    p2 is authored-data parity: 1 recorded FAIL (pants albedo) and 1 recorded
#    DELTA (beam) are the honest baseline; `unexpected_fail=0` is the gate.
gate_marker e2e_p2 "$OUT/e2e_p2.log" \
	"P2_SUMMARY: expected_fail=1 expected_delta=1 fixed=0 unexpected_fail=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/e2e/run_e2e_tests.gd -- --tier=p2

gate_marker parity_only "$OUT/parity_only.log" \
	"PARITY_ONLY_SUMMARY: fails=0 passed=60" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_parity_only.gd

#    Cream proof: RED by design until the data wave fixes `_apply_ue_emissive`.
#    Exit 1 + the marker is the expected result, not a gate failure.
expected_gate cream_red_proof "$OUT/cream_red_proof.log" 1 \
	"CREAM_PROOF: RED passes=2 expected_fail=2" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_w10a2_cream.gd

# 8. Port capture harness (headless, no GPU): the wrapper takes the lock itself.
gate_marker p0b_capture_dry_run "$OUT/p0b_capture_dry_run.log" \
	"P0B_DRY_RUN" \
	"$ROOT/build/qa/p0b_capture.sh" --dry-run

gate_marker p0b_capture_self_test "$OUT/p0b_capture_self_test.log" \
	"P0B_SELFTEST PASS checks=21 fails=0" \
	"$ROOT/build/qa/p0b_capture.sh" --self-test

gate_marker p0b_manifest_validate "$OUT/p0b_manifest_validate.log" \
	"P0B_MANIFEST_OK" \
	python3 build/qa/p0b_roi_stats.py --validate-manifest \
	docs/reports/logs/p0b/dry-run/manifest.json

#    Reference-only KF27 calibration: proves the tracked reference frame still
#    meets the same criteria the ROI scorer applies. No port image involved.
gate_marker p0b_kf27_reference "$OUT/p0b_kf27_reference.log" \
	"P0B_KF27_REF pose=upper_foyer met=7/7" \
	python3 build/qa/p0b_roi_stats.py \
	--port docs/reference/clip_1795033698901/clean/KF27_03m27s_foyer_security_beam.jpg \
	--pose upper_foyer --reference-only

# 9. Runtime smoke: NO outer flock — the script takes the lock itself and
#    expects the inner `timeout` kill (exit 124), then scans the log.
gate runtime_smoke "$OUT/runtime_smoke.log" \
	"$ROOT/build/qa/runtime_smoke.sh" 90

SMOKE_GODOT_LOG="$(awk '/^log: /{p=$2} END{print p}' "$OUT/runtime_smoke.log")"
if [ -z "$SMOKE_GODOT_LOG" ] || [ ! -f "$SMOKE_GODOT_LOG" ]; then
	say "P0B_GATES FAIL gate=runtime_smoke no Godot log path in runtime_smoke.log"
	exit 3
fi
cp -- "$SMOKE_GODOT_LOG" "$OUT/runtime_smoke_godot.log"
if ! grep -q 'RUNTIME_SMOKE_SCAN PASS exit=124 ' "$OUT/runtime_smoke.log"; then
	say "P0B_GATES FAIL gate=runtime_smoke scan did not report PASS exit=124"
	tail -5 "$OUT/runtime_smoke.log" | tee -a "$MASTER"
	exit 3
fi
say "P0B_SMOKE_GODOT_LOG $OUT/runtime_smoke_godot.log (from $SMOKE_GODOT_LOG)"

gate_marker runtime_smoke_scan "$OUT/runtime_smoke_scan.log" \
	"RUNTIME_SMOKE_SCAN_TEST PASS" \
	"$ROOT/build/qa/test_runtime_smoke_scan.sh"

# 10. Static audit family. `make audit` includes texture-cap-check, string-audit
#     and check-greps; the separate runs below own their ratchet evidence logs.
gate string_audit "$OUT/string_audit.log" make string-audit
gate_marker literal_greps "$OUT/literal_greps.log" "LITERAL_GREPS PASS" make check-greps
gate audit "$OUT/audit.log" make audit
gate texture_cap "$OUT/texture_cap.log" make texture-cap-check
gate perf_guard "$OUT/perf_guard.log" build/qa/test_perf_guard.sh
gate gate_ratchet "$OUT/gate_ratchet.log" make gate-ratchet

say "P0B_GATES PASS head=$HEAD_SHA gates=$GATE_COUNT expected_gates=$EXPECTED_COUNT"
say "P0B_GATES evidence=$OUT summary=$SUMMARY"
exit 0
