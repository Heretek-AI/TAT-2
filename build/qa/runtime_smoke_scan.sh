#!/usr/bin/env bash
# Runtime-smoke decision (W10-A D9).
#
# Factor the whole pass/fail decision out of `runtime_smoke.sh` so it can be
# self-tested without Godot: one log + the runner's exit code in, one machine
# line out, exit 0 (PASS) or 1 (FAIL).
#
# Policy:
#   * exit code 124 is the ONLY accepted termination — that is the `timeout`
#     kill, i.e. the game stayed up for the whole window. Exit 0 means the
#     mission ended early (it did not stay up) and fails like any other code.
#   * `SCRIPT ERROR`, `SHADER ERROR` and `ERROR:` lines are errors. Godot 4
#     renders `push_error()` as `USER ERROR: <msg>` + an `at:` follow-up, so the
#     `ERROR:` match covers script, shader, push_error and engine errors in one
#     count; each matching LINE is counted once.
#   * lines matched by the embedded teardown allowlist (plus an optional local
#     `runtime_smoke_allowlist.txt`) are subtracted. The embedded list is
#     teardown/exit noise only and documented per entry; it lives in the script
#     because `.gitignore` ignores `build/qa/*.txt`.
#   * the mission must report `TAT-2 mission_ready` at least once.
#
# The log is never moved or deleted here; the caller commits it.
#
# Usage: build/qa/runtime_smoke_scan.sh <log> <exit_code>

set -uo pipefail

LOG="${1:-}"
CODE="${2:-}"
ALLOW="$(cd "$(dirname "$0")" && pwd)/runtime_smoke_allowlist.txt"

emit() { # verdict errors raw allowed script shader ready reason
	printf 'RUNTIME_SMOKE_SCAN %s exit=%s errors=%s raw=%s allowed=%s script_errors=%s shader_errors=%s mission_ready=%s reason=%s path=%s\n' \
		"$1" "${CODE:-?}" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "${LOG:-?}"
}

if [ -z "$LOG" ] || [ -z "$CODE" ]; then
	echo "usage: runtime_smoke_scan.sh <log> <exit_code>" >&2
	emit FAIL 0 0 0 0 0 0 usage
	exit 2
fi

if [ ! -f "$LOG" ]; then
	echo "runtime_smoke_scan: no such log: $LOG" >&2
	emit FAIL 0 0 0 0 0 0 missing_log
	exit 1
fi

# Counted once per matching line. `grep -c` already returns 0 lines on no match;
# the `|| true` suppresses its exit 1 under `set -o pipefail`.
SCRIPT=$(grep -c 'SCRIPT ERROR' "$LOG" || true)
SHADER=$(grep -c 'SHADER ERROR' "$LOG" || true)
RAW=$(grep -cE 'SCRIPT ERROR|SHADER ERROR|ERROR:' "$LOG" || true)
READY=$(grep -c 'TAT-2 mission_ready' "$LOG" || true)
SCRIPT=${SCRIPT:-0}; SHADER=${SHADER:-0}; RAW=${RAW:-0}; READY=${READY:-0}

PATTERNS="$(mktemp -t tat2-smoke-allow-XXXXXX)" || exit 2
trap 'rm -f "$PATTERNS"' EXIT
# Embedded defaults, because `.gitignore:25` ignores `build/qa/*` except
# `.gd/.sh/.py`: a sibling `runtime_smoke_allowlist.txt` would never be
# committed, and the teardown families below are known-good. The external file
# (when a local run creates one) appends site-specific patterns.
cat >"$PATTERNS" <<'ALLOW'
^ERROR: [0-9]+ resources? still in use at exit
^ERROR: [0-9]+ RID allocations of type
^ERROR: Pages in use exist at exit in PagedAllocator
^ERROR: Parameter "fd" is null
ALLOW
if [ -f "$ALLOW" ]; then
	grep -vE '^[[:space:]]*(#|$)' "$ALLOW" >>"$PATTERNS" 2>/dev/null || true
fi
ALLOWED=0
if [ -s "$PATTERNS" ]; then
	# Only error lines can be allowlisted, and each is subtracted once.
	ALLOWED=$(grep -E 'ERROR:' "$LOG" | grep -cE -f "$PATTERNS" || true)
fi
ALLOWED=${ALLOWED:-0}
ERRORS=$((RAW - ALLOWED))
if [ "$ERRORS" -lt 0 ]; then
	# An allowlist pattern that matches non-error lines can over-subtract; the
	# error count is a floor, never negative.
	ERRORS=0
fi

# Print the offending lines, not the allowlisted ones (a teardown line in the
# failure dump would read like a game defect).
show_errors() {
	if [ -s "$PATTERNS" ]; then
		grep -nE 'SCRIPT ERROR|SHADER ERROR|ERROR:' "$LOG" | grep -vE -f "$PATTERNS" | head -20 >&2 || true
	else
		grep -nE 'SCRIPT ERROR|SHADER ERROR|ERROR:' "$LOG" | head -20 >&2 || true
	fi
}

if [ "$CODE" -ne 124 ]; then
	echo "runtime_smoke_scan: exit $CODE is not the accepted timeout kill (124)" >&2
	if [ "$CODE" -eq 0 ]; then
		echo "runtime_smoke_scan: exit 0 means the mission exited on its own (it did not stay up)" >&2
	fi
	show_errors
	emit FAIL "$ERRORS" "$RAW" "$ALLOWED" "$SCRIPT" "$SHADER" "$READY" "unexpected_exit_${CODE}"
	exit 1
fi

if [ "$READY" -lt 1 ]; then
	echo "runtime_smoke_scan: the mission never reached mission_ready" >&2
	show_errors
	emit FAIL "$ERRORS" "$RAW" "$ALLOWED" "$SCRIPT" "$SHADER" "$READY" no_mission_ready
	exit 1
fi

if [ "$ERRORS" -gt 0 ]; then
	echo "runtime_smoke_scan: $ERRORS runtime error line(s) (${RAW} matched, ${ALLOWED} allowlisted)" >&2
	show_errors
	emit FAIL "$ERRORS" "$RAW" "$ALLOWED" "$SCRIPT" "$SHADER" "$READY" runtime_errors
	exit 1
fi

emit PASS "$ERRORS" "$RAW" "$ALLOWED" "$SCRIPT" "$SHADER" "$READY" ok
exit 0
