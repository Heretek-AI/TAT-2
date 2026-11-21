#!/usr/bin/env bash
# P2-7: reimport step for extracted GLBs. Re-exporting a GLB with different
# CUE4Parse conversion settings without reimport leaves Godot rendering the
# stale imported mesh (995 .glb.import files under game/assets/ue/ carry
# source mtimes + import params). Run this after `make extract` (or any
# subset re-parse) and before `make test` so .godot/imported/ matches disk.
#
# Usage: tools/reimport_assets.sh [--check]
#   --check: fail without importing if any .glb under game/assets/ue/ is
#            newer than its .glb.import sidecar (staleness probe for CI).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-flatpak run org.godotengine.Godot}"

if [[ "${1:-}" == "--check" ]]; then
    stale=0
    while IFS= read -r glb; do
        if [[ "$glb" -nt "$glb.import" ]]; then
            echo "STALE: $glb newer than $glb.import"
            stale=1
        fi
    done < <(find "$ROOT/game/assets/ue" -name '*.glb')
    if [[ "$stale" == 1 ]]; then
        echo "reimport needed: run tools/reimport_assets.sh" >&2
        exit 1
    fi
    echo "reimport check: all .glb.import sidecars fresh"
    exit 0
fi

# Full headless import: re-runs the Godot import pipeline over game/.
$GODOT --headless --path "$ROOT/game" --import
echo "reimport done"
