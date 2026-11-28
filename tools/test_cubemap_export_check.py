#!/usr/bin/env python3
"""Fixture tests for ``tools/check_cubemap_export.py``.

Run with: ``python3 tools/test_cubemap_export_check.py``

The checker is the post-condition of the ``cubemaps`` extract stage: it must
refuse the exact defect the stage produced before P3-3A.4 (8-bit PNG faces,
which clamp a ~1.5e-3 linear sky to 0 / 1/255) and it must not skip silently on
an empty output tree.
"""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

import check_cubemap_export as checker

FACE_NAMES = checker.FACE_NAMES
PASSED = 0


def check(condition: bool, name: str, detail: str = "") -> None:
    global PASSED
    if not condition:
        message = f"FAIL: {name}"
        if detail:
            message += f" ({detail})"
        print(message)
        raise SystemExit(1)
    PASSED += 1
    print(f"PASS: {name}")


def write_cube(
    root: Path,
    cid: str,
    *,
    ext: str = ".hdr",
    hdr: bool = True,
    transfer: str = "linear",
    stale_png: bool = False,
    omit_face: str | None = None,
) -> None:
    cube_dir = root / cid
    cube_dir.mkdir(parents=True)
    faces = {}
    for name in FACE_NAMES:
        faces[name] = f"face_{name}{ext}"
        if name != omit_face:
            (cube_dir / faces[name]).write_bytes(b"fixture")
    if stale_png:
        (cube_dir / "face_px.png").write_bytes(b"stale")
    manifest = {
        "schema": "tat2.cubemap/1",
        "id": cid,
        "hdr": hdr,
        "encoding": "hdr" if hdr else "png",
        "transfer": transfer,
        "face_order": FACE_NAMES,
        "faces": faces,
    }
    (cube_dir / "cubemap.json").write_text(json.dumps(manifest))


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)

        # 1. A complete HDR cube passes.
        hdr_root = base / "hdr"
        write_cube(hdr_root, "cubemap_ground_floor_01")
        cubes, problems = checker.check(hdr_root)
        check(cubes == 1 and not problems, "a complete HDR cube passes", str(problems))
        check(
            checker.main(["--root", str(hdr_root)]) == 0,
            "the CLI exits 0 on a good tree",
        )

        # 2. The measured defect: 8-bit PNG faces are refused.
        png_root = base / "png"
        write_cube(png_root, "cubemap_ground_floor_01", ext=".png", hdr=False)
        cubes, problems = checker.check(png_root)
        check(cubes == 1, "the PNG cube is still counted", str(cubes))
        check(
            any("not HDR" in p or "8-bit" in p for p in problems),
            "PNG faces are refused",
            str(problems),
        )
        check(
            any("hdr=" in p for p in problems),
            "a manifest hdr=false is refused",
            str(problems),
        )
        check(
            checker.main(["--root", str(png_root)]) == 2,
            "the CLI exits 2 on a PNG cube",
        )

        # 3. A stale PNG beside an HDR manifest is refused.
        stale_root = base / "stale"
        write_cube(stale_root, "cubemap_ground_floor_01", stale_png=True)
        _, problems = checker.check(stale_root)
        check(
            any("stale 8-bit face" in p for p in problems),
            "a stale PNG beside an HDR manifest is refused",
            str(problems),
        )

        # 4. A missing face file is refused.
        missing_root = base / "missing"
        write_cube(missing_root, "daylight", omit_face="nz")
        _, problems = checker.check(missing_root)
        check(
            any("file missing" in p for p in problems),
            "a missing face file is refused",
            str(problems),
        )

        # 5. An HDR manifest must stay linear (no double gamma).
        srgb_root = base / "srgb"
        write_cube(srgb_root, "daylight", transfer="srgb")
        _, problems = checker.check(srgb_root)
        check(
            any("transfer" in p for p in problems),
            "an HDR cube with srgb transfer is refused",
            str(problems),
        )

        # 6. An empty tree is a failure, never a skip.
        empty_root = base / "empty"
        empty_root.mkdir()
        _, problems = checker.check(empty_root)
        check(bool(problems), "an empty Cubemaps directory fails closed", str(problems))
        _, problems = checker.check(base / "absent")
        check(
            bool(problems), "a missing Cubemaps directory fails closed", str(problems)
        )

        # 7. A mixed tree fails on the offending cube only.
        mixed_root = base / "mixed"
        write_cube(mixed_root, "cubemap_ground_floor_01")
        write_cube(mixed_root, "daylight", ext=".png", hdr=False)
        cubes, problems = checker.check(mixed_root)
        check(
            cubes == 2 and problems and all("daylight" in p for p in problems),
            "a mixed tree reports only the offending cube",
            str(problems),
        )

    print(f"CUBEMAP_EXPORT_CHECK_TEST: PASS checks={PASSED}")


if __name__ == "__main__":
    main()
