#!/usr/bin/env python3
"""Compare extracted files against Steam Manifest_UFSFiles_Win64.txt."""
import argparse
import os
from pathlib import Path

STEAM_MANIFEST = Path.home() / ".local/share/Steam/steamapps/common/Thick As Thieves/Manifest_UFSFiles_Win64.txt"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--extracted", default="extracted")
    ap.add_argument("--manifest", default=str(STEAM_MANIFEST))
    ap.add_argument("--min-coverage", type=float, default=0.0)
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
    # Check how many were actually dumped to extracted/
    dumped = 0
    for sub in ("raw", "json", "assets", "audio", "audio-meta"):
        d = ex / sub
        if d.exists():
            dumped += sum(1 for _ in d.rglob("*") if _.is_file())

    cov = resolved / max(1, len(manifest_tat))
    print(f"Manifest TAT entries: {len(manifest_tat)}")
    print(f"Resolved in CUE4Parse: {resolved} ({cov:.1%})")
    print(f"Files written to {ex}: {dumped}")
    if cov < args.min_coverage:
        raise SystemExit(f"coverage {cov:.1%} < {args.min_coverage:.1%}")

if __name__ == "__main__":
    main()
