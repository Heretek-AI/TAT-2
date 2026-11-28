#!/usr/bin/env python3
"""Fail-closed post-check for the extractor's `cubemaps` stage.

Run with: ``python3 tools/check_cubemap_export.py [--root DIR]``

Why this exists (P3-3A.4, measured 2026-11-27): the shipped sky cubes are
``PF_FloatRGBA`` and their linear radiance is ~1e-3. Exporting them as 8-bit
PNG clamps that to 0 or 1/255, and the cooked ``Cubemap_GroundFloor_01`` loses
~87 % of its energy (manifest: ``face_mean_8bit`` ~2e-4 vs ``face_mean_linear``
~1.5e-3). The extractor now writes Radiance ``.hdr`` faces for this pass only
(``CubemapOpts()``; every other texture command keeps PNG).

``make cubemaps`` runs a real extractor, and without a resolved ``--usmap`` an
unversioned package fails to load: ``cubemaps`` reports ``ok=0 fail=3`` and,
without ``--fail-on-error``, exits 0 — the previous 8-bit ``face_*.png`` files
then simply stay on disk and the IBL path silently keeps the quantized cube.
This checker is the second half of that guard: it reads the manifests the pass
actually wrote and refuses anything that is not a complete, linear, HDR cube.

Pinned (fail closed, never a silent skip):
  * the Cubemaps directory exists and holds at least one ``cubemap.json``;
  * every manifest names the six faces in the explicit ``px/nx/py/ny/pz/nz``
    order and each named file exists beside it;
  * every face is ``.hdr``/``.exr`` and the manifest declares ``hdr: true``,
    ``encoding: hdr`` and ``transfer: linear`` (an 8-bit face is the defect
    this exists to catch — all three authored cubes are float sources);
  * no stale ``face_*.png`` survives beside an HDR manifest.

Exit 0 with ``CUBEMAP_EXPORT_CHECK PASS cubes=N``; exit 2 with one
``CUBEMAP_EXPORT_CHECK FAIL`` line per problem.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ROOT = ROOT / "extracted" / "assets" / "TAT" / "Content" / "Cubemaps"
FACE_NAMES = ["px", "nx", "py", "ny", "pz", "nz"]
HDR_EXTS = {".hdr", ".exr"}


def check(root: Path) -> tuple[int, list[str]]:
    problems: list[str] = []
    if not root.is_dir():
        return 0, [f"{root}: no Cubemaps directory — the pass wrote nothing"]
    manifests = sorted(root.glob("*/cubemap.json"))
    if not manifests:
        return 0, [f"{root}: no */cubemap.json — the pass wrote nothing"]

    for manifest in manifests:
        cid = manifest.parent.name
        try:
            rec = json.loads(manifest.read_text())
        except (OSError, ValueError) as exc:
            problems.append(f"{cid}: unreadable manifest ({exc})")
            continue
        faces = rec.get("faces")
        if not isinstance(faces, dict) or sorted(faces) != sorted(FACE_NAMES):
            problems.append(f"{cid}: manifest faces are not the six px/nx/py/ny/pz/nz")
            faces = faces if isinstance(faces, dict) else {}
        if rec.get("hdr") is not True:
            problems.append(f"{cid}: manifest hdr={rec.get('hdr')!r} (expected true)")
        if rec.get("encoding") != "hdr":
            problems.append(
                f"{cid}: manifest encoding={rec.get('encoding')!r} (expected 'hdr')"
            )
        if rec.get("transfer") != "linear":
            problems.append(
                f"{cid}: manifest transfer={rec.get('transfer')!r} (HDR faces must be linear)"
            )
        for name in FACE_NAMES:
            rel = faces.get(name)
            if not rel:
                problems.append(f"{cid}: face '{name}' has no path")
                continue
            face = manifest.parent / rel
            ext = Path(rel).suffix.lower()
            if ext not in HDR_EXTS:
                problems.append(
                    f"{cid}: face '{name}' is '{rel}' — an 8-bit/PNG face is the quantized "
                    f"cube this check exists to catch"
                )
            if not face.is_file():
                problems.append(f"{cid}: face '{name}' file missing ({rel})")
        # A PNG face is only "stale" when the manifest claims HDR: an
        # all-PNG manifest is already reported above as a non-HDR cube.
        if rec.get("hdr") is True:
            for stale in sorted(manifest.parent.glob("face_*.png")):
                problems.append(
                    f"{cid}: stale 8-bit face survived the HDR pass ({stale.name})"
                )

    return len(manifests), problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--root",
        type=Path,
        default=DEFAULT_ROOT,
        help=f"cubemaps output directory (default {DEFAULT_ROOT})",
    )
    args = parser.parse_args(argv)

    cubes, problems = check(args.root)
    if problems:
        for problem in problems:
            print(f"CUBEMAP_EXPORT_CHECK FAIL: {problem}")
        return 2
    print(f"CUBEMAP_EXPORT_CHECK PASS cubes={cubes}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
