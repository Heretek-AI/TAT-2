#!/usr/bin/env bash
# N-P1/N-P2 headless navmesh runtime probe. Reads the generated nav asset
# (game/data/generated/nav by default); the integrator must run the extractor
# `nav` command and tools/parse_nav.py first. Writes nothing.
#
#   build/qa/nav_runtime_probe.sh
#   TAT2_NAV_DIR=/tmp/opencode/nav-gen build/qa/nav_runtime_probe.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAV_DIR="${TAT2_NAV_DIR:-$ROOT/game/data/generated/nav}"
LOCK="/tmp/opencode/tat2-godot.lock"

if [[ ! -f "$NAV_DIR/manifest.json" ]]; then
	echo "nav_runtime_probe: missing $NAV_DIR/manifest.json" >&2
	echo "nav_runtime_probe: run the extractor 'nav' command and tools/parse_nav.py first" >&2
	exit 2
fi

# Phase 3 §3B.2: once the integrator has re-baked with census_version 2, the
# gate also recomputes the link census from the emitted raw pair set. A legacy
# census_version 1 asset is printed as PENDING (the Godot probe below still
# pins its 35/45 numbers) so a lane that cannot write shared generated data is
# not failed for a data bake it must not run.
CENSUS_VERSION="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(int(d.get("census", {}).get("version", 1)))' "$NAV_DIR/manifest.json")"
if [[ "$CENSUS_VERSION" -ge 2 ]]; then
	python3 "$ROOT/build/qa/check_nav_census.py" --nav-dir "$NAV_DIR"
else
	echo "NAV_CENSUS: PENDING legacy census_version=$CENSUS_VERSION; run tools/parse_nav.py at the merged HEAD"
fi

flock "$LOCK" -c \
	"timeout 600 '$ROOT/tools/godot' --headless --path '$ROOT/game' \
	 --script '$ROOT/build/qa/nav_runtime_probe.gd' -- --nav-dir='$NAV_DIR'"
