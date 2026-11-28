#!/usr/bin/env bash
# FINAL evidence runner — the P2/P3/P5 + data wave gate set at the merged HEAD
# (`5135f53`), replacing `build/qa/run_p0b_gates.sh` as the current full set.
#
# History
# -------
# `run_p0a_gates.sh` (28 gates) and `run_p0b_gates.sh` (35 P0b gates + 5 P1
# route probes) stay committed as prior-wave measurements under
# `docs/reports/logs/p0a/`, `docs/reports/logs/p0b/` and
# `docs/reports/logs/p1/`. This runner is the W10 FINAL set: every P1 gate body
# is unchanged, the W10-P2/P3/P5 suites and probes are spliced in (cream suite
# 119 is now a normal green gate, not the old RED proof), and the evidence is
# written to `docs/reports/logs/final/`.
#
# Phase 0a (2026-11-27) adds one gate — `p0b_route_self_test`: `bash -n` on the
# route and live-capture wrappers, then the staged-route runner's 62-check
# headless self-test — for 45 gates. No other gate body changes.
#
# Phase 1/2 integration (2026-11-27) adds four gates — `probe_landscape_mask`
# (7), `nav_runtime_probe` (70), `producer_tests` (test-producers + parse_nav)
# and `test_capture_p5_filter` (5) — for 49 gates. Existing markers are raised
# to the merged measurements (beams 9, audio 123, P5 54, self-test 23, KF27
# 9/9); no floor is lowered.
#
# Phase 3 §3B.2 (2026-11-27) keeps the gate count: `nav_runtime_probe` grows
# from 70 to 94/97 checks (per-actor door audit, route-critical linked set,
# prison baked-link binding, census_version 2) and its literal marker becomes
# the `checks=[0-9]+ fails=0` regex; the ratchet's checks=70 stays a floor. The
# wrapper also recomputes the link census from the emitted raw pair set once the
# asset is census_version 2 (PENDING on a legacy v1 asset).
#
# Phase 3 §2.5.1 (2026-11-27) restores the three ratchet-pinned suites that no
# earlier runner invoked — `test_vo_director` (53), `probe_auto_exposure` (77)
# and `probe_cubemap` (37) — for 52 gates. Their pinned logs predated the
# 17:06 run; these gates now produce them in-run. No other gate body changes.
#
# Phase 3 test-manifest/errscan lane (2026-11-27) adds six gates — the
# `gate_manifest` orphan check, the `e2e_errscan` engine-error ceiling scan,
# and the four restored orphans `test_roof_collision` (authored + aabb modes),
# `probe_den_window`, `probe_mirror_split` and `probe_statetree_shadow` — for
# 58 gates. Every `game/tests/**/*.gd` is now a gate or an explicit retired
# entry in `build/qa/retired_tests.txt`.
#
# Rules encoded here (same contract as P0a/P0b/P1)
# ------------------------------------------------
#   * Never hold the Godot lock across the runner. Each Godot invocation takes
#     the lock itself (`flock <lock> tools/godot ...`).
#   * `runtime_smoke.sh` and `p0b_capture.sh` take the lock internally, so they
#     are invoked WITHOUT an outer flock (an outer lock deadlocks them).
#   * Start refuses to run if another process already holds the lock.
#   * Every gate's full output goes to `docs/reports/logs/final/<gate>.log`
#     with the exact command line, start time, exit code and finish time.
#   * Any unexpected non-zero stops the run. There is no expected failure any
#     more: suite 119 prints `CREAM_PROOF: GREEN` and exits 0.
#   * Generated data and the extract are read-only for this lane: the runner
#     never calls `make normalize`, `make extract` or a producer.
#   * The headless capture dry-run/self-test record under this wave's directory
#     via `P0B_EVIDENCE_DIR`, so a FINAL run does not rewrite the committed P0b
#     or P1 evidence.
#
# Usage:
#   build/qa/run_final_gates.sh
#
# Exit: 0 only when every gate passed; the failing gate's exit code otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/docs/reports/logs/final"
MASTER="$OUT/final-run.log"
SUMMARY="$OUT/final-summary.txt"
LOCK="/tmp/opencode/tat2-godot.lock"

# Refuse an unsafe output root before any truncation: a symlinked or
# non-directory $OUT would redirect MASTER, SUMMARY and every gate log.
if [ -L "$OUT" ] || { [ -e "$OUT" ] && [ ! -d "$OUT" ]; }; then
	printf 'FINAL_GATES FAIL output root %s is unsafe (symlink or non-directory); refusing\n' "$OUT" >&2
	exit 5
fi
mkdir -p "$OUT" "$(dirname "$LOCK")" || exit 2
if [ -L "$OUT" ] || [ ! -d "$OUT" ]; then
	printf 'FINAL_GATES FAIL output root %s is not a real directory; refusing\n' "$OUT" >&2
	exit 5
fi
cd "$ROOT" || exit 2
# Headless capture dry-run/self-test evidence goes to this wave's directory.
export P0B_EVIDENCE_DIR="$OUT"

# An output file must be absent or a single-link regular file: refuse a
# symlink, hardlink, FIFO, socket or device before truncating/appending.
_safe_output_file() { # <path>
	local p="$1" links
	[ -L "$p" ] && return 1
	[ -e "$p" ] || return 0
	[ -f "$p" ] || return 1
	links="$(stat -c %h -- "$p" 2>/dev/null || echo 1)"
	[ "$links" = "1" ] || return 1
	return 0
}

for unsafe in "$MASTER" "$SUMMARY"; do
	if ! _safe_output_file "$unsafe"; then
		printf 'FINAL_GATES FAIL output file %s is unsafe (symlink/hardlink/non-regular); refusing\n' "$unsafe" >&2
		exit 5
	fi
done

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
	printf 'FINAL_GATE_RUN\n'
	printf 'started: %s\n' "$(date -Is)"
	printf 'root: .\n'
	printf 'head: %s\n' "$HEAD_SHA"
	printf 'branch: %s\n' "$BRANCH"
	printf 'godot: %s\n' "$GODOT_VERSION"
	printf 'godot_bin: %s\n' "tools/godot"
	printf 'lock: %s\n' "$LOCK"
	printf 'uncommitted_entries_at_start: %s\n' "$DIRTY"
	printf 'host: %s\n' "$(uname -srm)"
	printf 'nproc: %s\n' "$(nproc 2>/dev/null || echo '?')"
	printf 'runner: %s\n' "build/qa/run_final_gates.sh"
	printf '\n'
} >"$MASTER"
: >"$SUMMARY"

# Refuse to start inside an outer Godot lock: that is the W10-A2 deadlock.
if ! flock -n "$LOCK" true; then
	say "FINAL_GATES BLOCKED: another process holds $LOCK."
	say "Do NOT wrap this runner in flock; runtime_smoke.sh/p0b_capture.sh take it themselves."
	exit 2
fi

say "FINAL_GATES start head=$HEAD_SHA branch=$BRANCH godot=$GODOT_VERSION"

GATE_COUNT=0
# The committed runner/binding self-check in tools/check_gate_ratchet.py pins
# the same number. A gate moved into an uncalled function still parses there,
# but this executed-count assertion catches it before the PASS line.
EXPECTED_GATES=58

_open_log() { # <name> <log> <command...>
	local name="${1:?gate name}"
	local log="${2:?gate log path}"
	shift 2
	# Refuse a symlink, hardlink, FIFO or any other non-regular target before
	# truncating: a planted link would rewrite a tracked file or hang the run.
	if ! _safe_output_file "$log"; then
		say "FINAL_GATES FAIL gate=$name log=$log is unsafe (symlink/hardlink/non-regular); refusing to open it"
		exit 5
	fi
	local rendered="" arg
	for arg in "$@"; do
		case "$arg" in
		"$ROOT"/*) arg="./${arg#"$ROOT"/}" ;;
		esac
		rendered+="$(printf ' %q' "$arg")"
	done
	{
		printf '== FINAL_GATE %s\n' "$name"
		printf 'COMMAND:%s\n' "$rendered"
		printf 'CWD: .\nSTARTED: %s\n\n' "$(date -Is)"
	} >"$log"
}

_finish_log() { # <log> <code>
	{
		printf '\nEXIT: %d\nFINISHED: %s\n' "${2:?code}" "$(date -Is)"
	} >>"${1:?log}"
}

_gate_body() { # <name> <log> <command...> — sets GATE_CODE
	local name="${1:?gate name}"
	local log="${2:?gate log path}"
	shift 2
	local log_rel
	_open_log "$name" "$log" "$@"
	"$@" >>"$log" 2>&1
	GATE_CODE=$?
	_finish_log "$log" "$GATE_CODE"
	log_rel="${log#"$ROOT"/}"
	GATE_COUNT=$((GATE_COUNT + 1))
	printf '%s\texit=%d\t%s\n' "$name" "$GATE_CODE" "$log_rel" >>"$SUMMARY"
	say "FINAL_GATE name=$name exit=$GATE_CODE log=$log_rel"
}

_fail_gate() { # <name> <log> <reason>
	local log_rel
	log_rel="${2#"$ROOT"/}"
	say "FINAL_GATES FAIL gate=$1 $3 log=$log_rel"
	say "--- last 25 lines of $log_rel ---"
	tail -25 "${2:?log}" | tee -a "$MASTER"
	say "--- end $log_rel ---"
	exit "${4:-1}"
}

gate() { # gate <name> <log> <command...> — exit 0 required
	_gate_body "$@"
	if [ "$GATE_CODE" -ne 0 ]; then
		_fail_gate "$1" "$2" "exit=$GATE_CODE" "$GATE_CODE"
	fi
}

gate_marker() { # gate_marker <name> <log> <literal marker> <command...>
	local name="${1:?gate name}"
	local log="${2:?gate log path}"
	local marker="${3:?marker}"
	shift 3
	_gate_body "$name" "$log" "$@"
	if [ "$GATE_CODE" -ne 0 ]; then
		_fail_gate "$name" "$log" "exit=$GATE_CODE" "$GATE_CODE"
	fi
	if ! grep -Fq -- "$marker" "$log"; then
		_fail_gate "$name" "$log" "missing marker: $marker" 4
	fi
	say "FINAL_MARKER name=$name marker=$marker"
}

gate_marker_re() { # gate_marker_re <name> <log> <extended-regex marker> <command...>
	local name="${1:?gate name}"
	local log="${2:?gate log path}"
	local marker="${3:?marker regex}"
	shift 3
	_gate_body "$name" "$log" "$@"
	if [ "$GATE_CODE" -ne 0 ]; then
		_fail_gate "$name" "$log" "exit=$GATE_CODE" "$GATE_CODE"
	fi
	if ! grep -Eq -- "$marker" "$log"; then
		_fail_gate "$name" "$log" "missing marker regex: $marker" 4
	fi
	say "FINAL_MARKER name=$name marker=$marker"
}

# 0. Static test manifest: every game/tests/**/*.gd is reachable from
#    run_tests.gd, an E2E tier or this runner (or is an explicit retired entry
#    in build/qa/retired_tests.txt). Cheap and lock-free; run it first so an
#    orphan test fails before any Godot work.
gate_marker gate_manifest "$OUT/gate_manifest.log" "GATE_MANIFEST: PASS" \
	python3 build/qa/gate_manifest.py

# 1. Script compile + the two suite runners.
#    The compile marker is a regex because the checked count grows with every
#    wave; the ratchet (`tools/gate_ratchet.json`) pins the floor, this gate
#    only fails on a broken script or a malformed summary.
gate_marker_re compile "$OUT/compile.log" "scripts checked: [0-9]+, broken: 0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script "$ROOT/tools/check_scripts_compile.gd"

gate_marker run_tests "$OUT/run_tests.log" "SUMMARY: fails=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/run_tests.gd

gate_marker m2 "$OUT/m2.log" "M2_SUMMARY: fails=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_m2_player.gd

# 1b. P1 route-content probes (S12, S21, S24, S25-S26, S13-S20/KF15-16-23).
#     Unchanged from the P1 runner: a FINAL run proves the route content still
#     holds. The measured check counts are pinned on purpose (same convention
#     as E2E/p2): a probe that silently loses checks must be re-measured.
gate_marker probe_p1_safe "$OUT/probe_p1_safe.log" \
	"P1_SAFE PASS checks=86 fails=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_p1_safe.gd

gate_marker probe_p1_doors "$OUT/probe_p1_doors.log" "P1_DOORS PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_p1_doors.gd

gate_marker probe_p1_beams "$OUT/probe_p1_beams.log" \
	"P1_BEAMS PASS checks=9 fails=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_p1_beams.gd

# P4.4 landscape mask A/B: the authored `vis > 0.5` discard plus the diagnostic
# `TAT2_LANDSCAPE_MASK=discard|raw|off` switch and the safe-room gap. Headless;
# no pixel claim (the GPU A/B remains the integrator's separate step).
gate_marker probe_landscape_mask "$OUT/probe_landscape_mask.log" \
	"LANDSCAPE_MASK_SUMMARY: PASS fails=0 checks=7" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_landscape_mask.gd

gate_marker probe_p1_ward "$OUT/probe_p1_ward.log" "P1_WARD PASS checks=44" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_p1_ward.gd

gate_marker probe_p1_street "$OUT/probe_p1_street.log" "P1_STREET PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_p1_street.gd

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
#    The collision truth is the W10-P2 element coverage (0.869-0.912, no
#    invented render-trimesh fallback); the probe's own assertions are the gate
#    and the ratchet pins coverage_ppm=868852.
gate_marker probe_collision_authored "$OUT/probe_collision_authored.log" \
	"COL_MAPS PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_collision_authored.gd

gate_marker probe_lock_inventory "$OUT/probe_lock_inventory.log" \
	"state=APPLIED" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_lock_inventory.gd

# N-P1/N-P2 authored navmesh runtime: one NavigationRegion3D per map, the 80
# baked links, the door link state rule and the negative controls. The wrapper
# takes the Godot lock itself (like runtime_smoke), so no outer flock.
# Phase 3 §3B.2 raised the probe from 70 to 94/97 checks (per-actor door
# audit, route-critical set, prison baked-link binding, census v2), so the
# marker is a regex and the ratchet floor (checks=70) stays a floor.
gate_marker_re nav_runtime_probe "$OUT/nav_runtime_probe.log" \
	"NAV_RUNTIME_PROBE checks=[0-9]+ fails=0" \
	"$ROOT/build/qa/nav_runtime_probe.sh"

gate_marker probe_niagara "$OUT/probe_niagara.log" "NIAGARA_PROBE PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_niagara.gd

# W9-P4 S1 shadow trace: the StateTree interpreter must run (shadow mode) and
# the probe must pass. `TAT2_STATETREE` stays `off` for the game; this single
# gate sets it explicitly to prove the shadow path still executes.
gate_marker_re probe_statetree_shadow "$OUT/probe_statetree_shadow.log" \
	'^PROBE PASS fails=0$' \
	env TAT2_STATETREE=shadow flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_statetree_shadow.gd

gate_marker probe_door_walk "$OUT/probe_door_walk.log" "DOORWALK PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_door_walk.gd

gate_marker probe_viewmodel_truth "$OUT/probe_viewmodel_truth.log" "VIEWMODEL_TRUTH PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_viewmodel_truth.gd

gate_marker probe_geometry_placement "$OUT/probe_geometry_placement.log" "GEOM_PROBE PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_geometry_placement.gd

# P4.2 mirror-split data test (default fast Guildhall_Geometry gate; `--full`
# is the integrator's perf-census run). It proves the bake math, the cull-front
# fast path, the authored negative partition and the exact source-count
# apportionment against the real generated payload.
gate_marker_re probe_mirror_split "$OUT/probe_mirror_split.log" \
	'^MIRROR_DATA_SUMMARY: fails=0 checks=39 mode=geometry$' \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_mirror_split.gd

gate_marker probe_blackjack_race "$OUT/probe_blackjack_race.log" "BLACKJACK_PROBE PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_blackjack_race.gd

gate_marker probe_device_meshes "$OUT/probe_device_meshes.log" "TURRET_PROBE PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_device_meshes.gd

gate_marker probe_gc_destruction "$OUT/probe_gc_destruction.log" "GC_PROBE PASS" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_gc_destruction.gd

# 4. Standalone W10-A2 tests.
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

# W5B/W6L roof collision policy. The probe is mode-independent (it asserts the
# authored per-element hull union through AuthoredCollision), so run it under
# BOTH loader modes. Each mode must print its own `fails=0` summary; the marker
# is printed only after both modes pass.
qa_test_roof_collision() {
	local tmp
	tmp="$(mktemp /tmp/opencode/tat2-roof.XXXXXX)" || return 1
	printf '== mode TAT2_COLLISION=authored ==\n'
	if ! env TAT2_COLLISION=authored flock "$LOCK" tools/godot --headless --path game \
		--script res://tests/test_roof_collision.gd >"$tmp" 2>&1; then
		cat "$tmp"; rm -f "$tmp"; return 1
	fi
	cat "$tmp"
	if ! grep -q 'ROOF_COLLISION_SUMMARY: fails=0' "$tmp"; then
		rm -f "$tmp"; return 1
	fi
	printf '== mode TAT2_COLLISION=aabb ==\n'
	if ! env TAT2_COLLISION=aabb flock "$LOCK" tools/godot --headless --path game \
		--script res://tests/test_roof_collision.gd >"$tmp" 2>&1; then
		cat "$tmp"; rm -f "$tmp"; return 1
	fi
	cat "$tmp"
	if ! grep -q 'ROOF_COLLISION_SUMMARY: fails=0' "$tmp"; then
		rm -f "$tmp"; return 1
	fi
	rm -f "$tmp"
	printf 'ROOF_COLLISION_MODES PASS authored=0 aabb=0\n'
}
gate_marker test_roof_collision "$OUT/test_roof_collision.log" \
	"ROOF_COLLISION_MODES PASS authored=0 aabb=0" \
	qa_test_roof_collision

# 5. Leak probe. The correct path is res://probe_leak.gd (not tests/), and the
#    7 teardown texture-RID warnings are silenced by TAT2_NO_DEN_PROBE=1.
gate_marker probe_leak "$OUT/probe_leak.log" "PROBE start" \
	env TAT2_NO_DEN_PROBE=1 flock "$LOCK" tools/godot --headless --path game \
	--script res://probe_leak.gd

# 6. Full E2E (all tiers, a2 included) and the standalone a2 tier.
gate_marker e2e "$OUT/e2e.log" "SUMMARY: fails=0 passed=300 total=300" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/e2e/run_e2e_tests.gd

gate_marker e2e_a2 "$OUT/e2e_a2.log" "SUMMARY: fails=0 passed=22 total=22" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/e2e/run_e2e_tests.gd -- --tier=a2

#    p2 is authored-data parity: the W10-P2 data wave promoted the two pants
#    expectations to hard checks, so there is no recorded expected failure and
#    no recorded delta. The gate is `unexpected_fail=0` on all 14 checks.
gate_marker e2e_p2 "$OUT/e2e_p2.log" \
	"P2_SUMMARY: expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/e2e/run_e2e_tests.gd -- --tier=p2

# Engine-error scan over the three big Godot logs. `build/qa/e2e_errscan.sh`
# pins an explicit allowlist with per-message maxima and per-log ceilings
# (e2e 31 / e2e_a2 1 / run_tests 482). Any new `ERROR:` message fails, and a
# count above a ceiling fails; a lower count is fine.
gate_marker e2e_errscan "$OUT/e2e_errscan.log" "E2E_ERRSCAN PASS" \
	bash build/qa/e2e_errscan.sh --logdir "$OUT"

gate_marker parity_only "$OUT/parity_only.log" \
	"PARITY_ONLY_SUMMARY: fails=0 passed=60" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_parity_only.gd

# 7. W10-P2/P3/P5 suites and probes.
#    Suite 119 is GREEN now (the old RED proof is retired): no invented white
#    emission, the census increments, and an authored EmissiveColor still emits.
gate_marker test_w10a2_cream "$OUT/test_w10a2_cream.log" \
	"CREAM_PROOF: GREEN passes=5 expected_fail=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_w10a2_cream.gd

gate_marker test_audio_control "$OUT/test_audio_control.log" \
	"AUDIO_CONTROL_SUMMARY: fails=0 checks=123" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_audio_control.gd

# Phase 3 §2.5.1: suites 122-124 were ratchet-pinned but invoked by no runner
# gate before Phase 3 (their logs predated the 17:06 run). Restore them here so
# every pinned value is reproduced by this runner. gate_marker greps the exact
# literal summary, so these counts are exact markers, not floors: a suite that
# adds a check must update this line (the ratchet independently treats the same
# numbers as `>=` floors).
gate_marker test_vo_director "$OUT/test_vo_director.log" \
	"VO_DIRECTOR_SUMMARY: fails=0 checks=53" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/test_vo_director.gd

gate_marker probe_auto_exposure "$OUT/probe_auto_exposure.log" \
	"AEM_PROBE: fails=0 passed=77" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_auto_exposure.gd

gate_marker probe_cubemap "$OUT/probe_cubemap.log" \
	"CUBEMAP_PROBE: fails=0 passed=37" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_cubemap.gd

gate_marker probe_p5_ui "$OUT/probe_p5_ui.log" "P5_UI PASS checks=54" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_p5_ui.gd

# U-2: the P5 capture filter is fail-closed (unknown shot exits 2 before the
# mission load); headless only, no render. The script starts Godot itself, so
# the outer lock is held for its duration.
gate_marker test_capture_p5_filter "$OUT/test_capture_p5_filter.log" \
	"CAPTURE_P5_FILTER_TEST PASS checks=5" \
	flock "$LOCK" "$ROOT/build/qa/test_capture_p5_ui_filter.sh"

gate_marker probe_den_spawn "$OUT/probe_den_spawn.log" "DEN_SPAWN PASS checks=9 fails=0" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_den_spawn.gd

# W9-P2 B3: Den telescope ponder is camera-only (never writes the player) and
# the west-window escape is contained, with the blocker as defense in depth.
gate_marker_re probe_den_window "$OUT/probe_den_window.log" \
	'^DEN_WINDOW PASS checks=34$' \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_den_window.gd

# 8. Port capture harness (headless, no GPU): the wrapper takes the lock itself
#    and writes its dry-run/self-test evidence under $OUT via P0B_EVIDENCE_DIR.
gate_marker p0b_capture_dry_run "$OUT/p0b_capture_dry_run.log" \
	"P0B_DRY_RUN" \
	"$ROOT/build/qa/p0b_capture.sh" --dry-run

gate_marker p0b_capture_self_test "$OUT/p0b_capture_self_test.log" \
	"P0B_SELFTEST PASS checks=23 fails=0" \
	"$ROOT/build/qa/p0b_capture.sh" --self-test

gate_marker p0b_manifest_validate "$OUT/p0b_manifest_validate.log" \
	"P0B_MANIFEST_OK" \
	python3 build/qa/p0b_roi_stats.py --validate-manifest \
	"$OUT/dry-run/manifest.json"

#    Reference-only KF27 calibration: proves the tracked reference frame still
#    meets the same criteria the ROI scorer applies. No port image involved.
gate_marker p0b_kf27_reference "$OUT/p0b_kf27_reference.log" \
	"P0B_KF27_REF pose=upper_foyer met=9/9" \
	python3 build/qa/p0b_roi_stats.py \
	--port docs/reference/clip_1795033698901/clean/KF27_03m27s_foyer_security_beam.jpg \
	--pose upper_foyer --reference-only

#    Route-runner self-test (Phase 0a, headless, no GPU): both QA wrappers must
#    parse, then the staged-route table/schema/audio self-test must pass 62/62.
#    The wrapper writes its evidence under $OUT, so a FINAL run does not rewrite
#    the committed Phase 0a log under docs/reports/logs/p0b-route/.
qa_route_self_test() {
	printf 'bash -n build/qa/p0b_route.sh\n'
	bash -n "$ROOT/build/qa/p0b_route.sh" || return $?
	printf 'bash -n build/qa/p0b_live_capture.sh\n'
	bash -n "$ROOT/build/qa/p0b_live_capture.sh" || return $?
	P0B_ROUTE_EVIDENCE_DIR="$OUT" "$ROOT/build/qa/p0b_route.sh" --self-test
}
gate_marker p0b_route_self_test "$OUT/p0b_route_self_test.log" \
	"P0B_ROUTE_SELFTEST PASS checks=62 fails=0" \
	qa_route_self_test

# 9. Runtime smoke: NO outer flock — the script takes the lock itself and
#    expects the inner `timeout` kill (exit 124), then scans the log.
gate runtime_smoke "$OUT/runtime_smoke.log" \
	"$ROOT/build/qa/runtime_smoke.sh" 90

SMOKE_GODOT_LOG="$(awk '/^log: /{p=$2} END{print p}' "$OUT/runtime_smoke.log")"
if [ -z "$SMOKE_GODOT_LOG" ] || [ ! -f "$SMOKE_GODOT_LOG" ]; then
	say "FINAL_GATES FAIL gate=runtime_smoke no Godot log path in runtime_smoke.log"
	exit 3
fi
cp -- "$SMOKE_GODOT_LOG" "$OUT/runtime_smoke_godot.log"
if ! grep -q 'RUNTIME_SMOKE_SCAN PASS exit=124 ' "$OUT/runtime_smoke.log"; then
	say "FINAL_GATES FAIL gate=runtime_smoke scan did not report PASS exit=124"
	tail -5 "$OUT/runtime_smoke.log" | tee -a "$MASTER"
	exit 3
fi
say "FINAL_SMOKE_GODOT_LOG $OUT/runtime_smoke_godot.log (from $SMOKE_GODOT_LOG)"

gate_marker runtime_smoke_scan "$OUT/runtime_smoke_scan.log" \
	"RUNTIME_SMOKE_SCAN_TEST PASS" \
	"$ROOT/build/qa/test_runtime_smoke_scan.sh"

# 10. Producer/unit tests (stdlib + one headless-free parser fixture). This
#     was outside the runner before Phase 1/2; `test-producers` covers every
#     tools/test_*.py (stealthball array 22, ui pixel stats 15) and the separate
#     build/qa/test_parse_nav.py is the 7-case nav merge/area fixture.
qa_producer_tests() {
	make test-producers || return $?
	python3 "$ROOT/build/qa/test_parse_nav.py" || return $?
	printf 'PRODUCER_TESTS PASS\n'
}
gate_marker producer_tests "$OUT/producer_tests.log" "PRODUCER_TESTS PASS" \
	qa_producer_tests

# 11. Static audit family. `make audit` includes texture-cap-check, string-audit
#     and check-greps; the separate runs below own their ratchet evidence logs.
gate string_audit "$OUT/string_audit.log" make string-audit
gate_marker literal_greps "$OUT/literal_greps.log" "LITERAL_GREPS PASS" make check-greps
gate audit "$OUT/audit.log" make audit
gate texture_cap "$OUT/texture_cap.log" make texture-cap-check
gate perf_guard "$OUT/perf_guard.log" build/qa/test_perf_guard.sh
gate gate_ratchet "$OUT/gate_ratchet.log" make gate-ratchet

if [ "$GATE_COUNT" -ne "$EXPECTED_GATES" ]; then
	say "FINAL_GATES FAIL gate_count=$GATE_COUNT expected=$EXPECTED_GATES (a gate was skipped, duplicated or not executed)"
	exit 6
fi

say "FINAL_GATES PASS head=$HEAD_SHA gates=$GATE_COUNT"
say "FINAL_GATES evidence=$OUT summary=$SUMMARY"
exit 0
