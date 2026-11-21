#!/usr/bin/env python3
"""Compare extracted files against Steam Manifest_UFSFiles_Win64.txt.

P1-8: this gate used to check the mount only (resolved-in-CUE4Parse
coverage) while the pipeline behind it was unmeasured: dumped counts were
printed-not-gated, errors.log was never read, Engine deps were outside the
manifest glob, and nothing compared extracted/ against game/data/generated/.
Every one of those is now a failing check (opt-out flags exist for
debugging, but the Makefile wires all gates on).
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

STEAM_MANIFEST = (
    Path.home()
    / ".local/share/Steam/steamapps/common/Thick As Thieves/Manifest_UFSFiles_Win64.txt"
)

# P1-1: Engine carriers referenced by shipped levels must be mounted.
# WorldGridMaterial is the proven dangling bind (VFX_SkySearchLight_Mesh);
# BasicShapes are the round-2 mesh repair set.
REQUIRED_ENGINE_DEPS = [
    "Engine/Content/EngineMaterials/WorldGridMaterial.uasset",
    "Engine/Content/BasicShapes/Cube.uasset",
    "Engine/Content/BasicShapes/Plane.uasset",
    "Engine/Content/BasicShapes/Sphere.uasset",
    "Engine/Content/BasicShapes/Cone.uasset",
    "Engine/Content/BasicShapes/Cylinder.uasset",
]

DUMP_STAGES = ("raw", "json", "assets", "audio", "audio-meta")

# (group, source dirs under extracted/, generated outputs). A group is stale
# when its oldest generated output predates its newest extracted source.
FRESHNESS_GROUPS = (
    ("levels", ["json/Maps"], ["../game/data/generated/levels"]),
    (
        "gameplay",
        ["json/Missions", "json/Gameplay", "json/AI", "json/Character"],
        ["../game/data/generated/gameplay"],
    ),
    (
        "tables",
        [
            "json/Gameplay",
            "json/AI",
            "json/Missions",
            "json/Character",
            "json/Core",
            "json/StringTables",
            "json/UI",
            "json/Audio",
        ],
        ["../game/data/generated/tables"],
    ),
    (
        "materials",
        ["assets"],
        [
            "../game/data/generated/materials.json",
            "../game/data/generated/mesh_materials.json",
            "../game/data/generated/mesh_materials_provenance.json",
        ],
    ),
    (
        "audio",
        ["audio", "audio-meta"],
        [
            "../game/data/generated/audio_events.json",
            "../game/data/generated/audio_library.json",
        ],
    ),
    ("weather", ["json"], ["../game/data/generated/weather"]),
    ("vfx", ["json"], ["../game/data/generated/vfx"]),
)


def _newest_mtime(root: Path) -> float:
    latest = 0.0
    if not root.exists():
        return latest
    # Godot writes .import sidecars next to the extracted sources; they are
    # importer artefacts, not extraction output, and must not make the materials
    # group look stale every time the project is opened.
    ignored_suffixes = {".import", ".uid"}
    for p in root.rglob("*"):
        try:
            if p.is_file() and p.suffix not in ignored_suffixes:
                m = p.stat().st_mtime
                if m > latest:
                    latest = m
        except OSError:
            continue
    return latest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--extracted", default="extracted")
    ap.add_argument("--manifest", default=str(STEAM_MANIFEST))
    ap.add_argument("--min-coverage", type=float, default=0.0)
    ap.add_argument(
        "--min-dumped",
        type=int,
        default=0,
        help="Fail if total dumped files across all stages fall below this.",
    )
    ap.add_argument(
        "--fail-on-errors",
        action="store_true",
        help="Fail if errors.log holds current-run failures (mtime >= filelist).",
    )
    ap.add_argument(
        "--fail-on-stale",
        action="store_true",
        help="Fail if any generated group is older than its extracted sources.",
    )
    ap.add_argument(
        "--write-manifest",
        default="",
        help="Write a freshness manifest JSON (extracted snapshot mtimes + "
        "per-group newest-src/oldest-out) to this path. Default location is "
        "<extracted>/_manifest.json; the file records which extracted/ "
        "snapshot produced the current generated/ tree (P2-7).",
    )
    args = ap.parse_args()

    ex = Path(args.extracted)
    filelist = ex / "filelist.txt"
    if not filelist.exists():
        raise SystemExit(f"missing {filelist}")

    mounted = set()
    for line in filelist.read_text().splitlines():
        if line:
            mounted.add(line.split("\t")[0])

    manifest_tat = []
    for line in Path(args.manifest).read_text(errors="replace").splitlines():
        p = line.split("\t")[0].strip()
        if p.startswith("TAT/") and not p.endswith((".ubulk", ".uexp", ".uptnl")):
            manifest_tat.append(p)

    # Check how many manifest TAT files are in mounted pak/utoc
    resolved = sum(1 for p in manifest_tat if p in mounted)
    # Check how many were actually dumped to extracted/ (per stage, gated).
    stage_counts = {}
    for sub in DUMP_STAGES:
        d = ex / sub
        n = sum(1 for _ in d.rglob("*") if _.is_file()) if d.exists() else 0
        stage_counts[sub] = n
    dumped = sum(stage_counts.values())

    cov = resolved / max(1, len(manifest_tat))
    print(f"Manifest TAT entries: {len(manifest_tat)}")
    print(f"Resolved in CUE4Parse: {resolved} ({cov:.1%})")
    for sub in DUMP_STAGES:
        print(f"Dumped {sub}: {stage_counts[sub]}")
    print(f"Files written to {ex}: {dumped}")
    if cov < args.min_coverage:
        raise SystemExit(f"coverage {cov:.1%} < {args.min_coverage:.1%}")
    # P1-8 gate 1: a stage that exported nothing while the mount is healthy
    # means that pipeline leg silently produced zero output.
    for sub in DUMP_STAGES:
        if stage_counts[sub] == 0:
            raise SystemExit(f"stage {sub} dumped 0 files (pipeline leg dead)")
    if dumped < args.min_dumped:
        raise SystemExit(f"dumped {dumped} < --min-dumped {args.min_dumped}")
    # P1-8 gate 2: Engine deps are outside the TAT manifest glob, so assert
    # them by name. A missing WorldGridMaterial re-creates the dangling bind.
    missing_engine = [p for p in REQUIRED_ENGINE_DEPS if p not in mounted]
    n_engine = sum(1 for p in mounted if p.startswith("Engine/Content/"))
    print(f"Engine/Content files mounted: {n_engine}")
    for p in REQUIRED_ENGINE_DEPS:
        print(f"engine-dep {'OK' if p not in missing_engine else 'MISSING'}: {p}")
    if missing_engine:
        raise SystemExit(f"required Engine deps not mounted: {missing_engine}")
    # P1-8 gate 3: errors.log is the per-run failure signal (truncated on open
    # by Exporter.Report, deleted when the run is clean). A non-empty log
    # from the current snapshot (mtime >= filelist) fails the audit; an older
    # one is a stale warning, never silent.
    errors_log = ex / "errors.log"
    if errors_log.exists() and errors_log.stat().st_size > 0:
        age = time.strftime(
            "%Y-%m-%d %H:%M", time.localtime(errors_log.stat().st_mtime)
        )
        if errors_log.stat().st_mtime >= filelist.stat().st_mtime:
            print(f"errors.log ({age}, {errors_log.stat().st_size} bytes):")
            print(errors_log.read_text()[:2000])
            if args.fail_on_errors:
                raise SystemExit("errors.log holds current-run failures")
        else:
            print(
                f"WARNING: stale errors.log ({age}, "
                f"{errors_log.stat().st_size} bytes) predates filelist.txt; "
                "re-run the extractor to truncate it"
            )
    else:
        print("errors.log: clean (absent or empty)")
    # P1-8 gate 4: generated-vs-extracted freshness per domain group.
    stale_groups = []
    group_rows: dict = {}
    for name, srcs, outs in FRESHNESS_GROUPS:
        src_roots = [ex / s for s in srcs]
        out_roots = [(ex / o) for o in outs]
        newest_src = 0.0
        for s in src_roots:
            m = _newest_mtime(s)
            if m > newest_src:
                newest_src = m
        oldest_out = 0.0
        n_out = 0
        for o in out_roots:
            files = (
                [o]
                if o.is_file()
                else ([p for p in o.rglob("*") if p.is_file()] if o.exists() else [])
            )
            for p in files:
                try:
                    m = p.stat().st_mtime
                except OSError:
                    continue
                n_out += 1
                if oldest_out == 0.0 or m < oldest_out:
                    oldest_out = m
        if n_out == 0:
            print(f"freshness {name}: NO GENERATED OUTPUTS (stale by absence)")
            stale_groups.append(name)
            group_rows[name] = {
                "newest_extracted_src": newest_src,
                "oldest_generated_out": 0.0,
                "n_outputs": 0,
                "stale": True,
            }
            continue
        stale = oldest_out < newest_src
        fmt = lambda t: time.strftime("%Y-%m-%d %H:%M", time.localtime(t)) if t else "-"
        print(
            f"freshness {name}: {'STALE' if stale else 'fresh'} "
            f"(newest src {fmt(newest_src)}, oldest out {fmt(oldest_out)}, {n_out} outputs)"
        )
        if stale:
            stale_groups.append(name)
        group_rows[name] = {
            "newest_extracted_src": newest_src,
            "oldest_generated_out": oldest_out,
            "n_outputs": n_out,
            "stale": stale,
        }
    # P2-7: record which extracted/ snapshot the current generated/ tree was
    # built from, so a partial re-extract + subset re-parse cannot pass
    # silently. Written on every run (pass or fail); gates above still fail.
    manifest_path = (
        Path(args.write_manifest) if args.write_manifest else (ex / "_manifest.json")
    )
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(
            {
                "written_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "extracted": str(ex),
                "filelist_mtime": filelist.stat().st_mtime,
                "manifest_entries": len(manifest_tat),
                "resolved": resolved,
                "coverage": cov,
                "stage_counts": stage_counts,
                "required_engine_deps": REQUIRED_ENGINE_DEPS,
                "missing_engine_deps": missing_engine,
                "groups": group_rows,
            },
            indent=2,
        )
        + "\n"
    )
    print(f"manifest -> {manifest_path}")
    if stale_groups and args.fail_on_stale:
        raise SystemExit(f"stale generated groups: {stale_groups}")


if __name__ == "__main__":
    main()
