#!/usr/bin/env bash
# P2-NAV spike: extract one authored Guildhall navmesh tile set, then run the
# headless Detour-consumer probe. Writes only to TAT2_NAV_OUT (default
# /tmp/opencode/nav-spike); the repository and game/data are never touched.
#
#   build/qa/navmesh_spike.sh
#   TAT2_NAV_OUT=/tmp/opencode/nav-spike build/qa/navmesh_spike.sh
#   TAT2_NAV_JSON=/path/to/Guildhall_P.json build/qa/navmesh_spike.sh  # probe only
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAV_OUT="${TAT2_NAV_OUT:-/tmp/opencode/nav-spike}"
NAV_JSON="${TAT2_NAV_JSON:-$NAV_OUT/nav/Maps/Guildhall/Guildhall_P.json}"

if [[ ! -f "$NAV_JSON" ]]; then
	EX="$ROOT/tools/tat-extract/bin/Release/net10.0/tat-extract"
	if [[ ! -x "$EX" ]]; then
		echo "navmesh_spike: missing $EX" >&2
		echo "navmesh_spike: run 'make build-extractor' first (CUE4Parse binaries are gitignored)" >&2
		exit 2
	fi
	GAME="${TAT_GAME:-$HOME/.local/share/Steam/steamapps/common/Thick As Thieves}"
	USMAP="${TAT_USMAP:-}"
	if [[ -z "$USMAP" ]]; then
		# tools/ue4ss is generated and may live only in the main checkout when
		# this script runs from a git worktree.
		COMMON="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
		for d in "$ROOT/tools/ue4ss/output" "$(dirname "${COMMON:-/nonexistent}")/tools/ue4ss/output"; do
			if [[ -z "$USMAP" && -d "$d" ]]; then
				USMAP="$(ls "$d"/*.usmap 2>/dev/null | head -1 || true)"
			fi
		done
	fi
	if [[ -z "$USMAP" ]]; then
		echo "navmesh_spike: no .usmap found; set TAT_USMAP=/path/to/TAT-*.usmap" >&2
		exit 2
	fi
	mkdir -p "$NAV_OUT"
	"$EX" nav --game "$GAME" --usmap "$USMAP" \
		--filter 'Maps/Guildhall/Guildhall_P\.umap$' --out "$NAV_OUT"
	[[ -f "$NAV_JSON" ]] || {
		echo "navmesh_spike: extractor did not write $NAV_JSON" >&2
		exit 2
	}
fi

flock /tmp/opencode/tat2-godot.lock -c \
	"timeout 900 '$ROOT/tools/godot' --headless --path '$ROOT/game' \
	 --script '$ROOT/build/qa/navmesh_spike.gd' -- --nav='$NAV_JSON'"
