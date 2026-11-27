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

flock "$LOCK" -c \
	"timeout 600 '$ROOT/tools/godot' --headless --path '$ROOT/game' \
	 --script '$ROOT/build/qa/nav_runtime_probe.gd' -- --nav-dir='$NAV_DIR'"
