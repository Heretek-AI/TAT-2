#!/usr/bin/env python3
"""Tests for tools/parse_cubemap.py (stdlib only).

Run with: ``python3 tools/test_parse_cubemap.py``

The cases pin the Phase 3A.4 HDR contract:
  * an HDR cube keeps ``transfer=linear`` and exposes the unclamped linear
    ``face_mean`` + ``face_energy`` (the 8-bit clamp is never forwarded as the
    energy);
  * an HDR manifest that labels the faces sRGB is rejected (double-gamma
    guard), as is a manifest that disagrees with the face extensions or mixes
    HDR and LDR faces;
  * an 8-bit sRGB cube keeps its old behaviour and is labelled ``encoded8``.

Every fixture is built in a temporary directory; the producer never runs
against the shared ``extracted/`` or ``game/data/generated`` trees here.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRODUCER = ROOT / "tools" / "parse_cubemap.py"

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


def load_producer():
    spec = importlib.util.spec_from_file_location("parse_cubemap_test", PRODUCER)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def make_cube(
    base: Path,
    cube_id: str,
    *,
    ext: str,
    transfer: str,
    hdr: bool | None = None,
    encoding: str | None = None,
    face_mean_linear: dict | None = None,
    face_mean_8bit: dict | None = None,
) -> Path:
    path = base / cube_id
    path.mkdir(parents=True)
    faces = {}
    for name in ("px", "nx", "py", "ny", "pz", "nz"):
        file = f"face_{name}.{ext}"
        (path / file).write_bytes(b"fixture")
        faces[name] = file
    rec = {
        "schema": "tat2.cubemap/1",
        "id": cube_id,
        "ue_path": "/Game/MaterialLibrary/Utility/" + cube_id,
        "source_package": "TAT/Content/x/" + cube_id + ".uasset",
        "width": 4,
        "height": 4,
        "pixel_format": "PF_FloatRGBA" if hdr else "PF_B8G8R8A8",
        "srgb": transfer == "srgb",
        "transfer": transfer,
        "slices": 6,
        "faces": faces,
    }
    if hdr is not None:
        rec["hdr"] = hdr
    if encoding is not None:
        rec["encoding"] = encoding
    if face_mean_linear is not None:
        rec["face_mean_linear"] = face_mean_linear
    if face_mean_8bit is not None:
        rec["face_mean_8bit"] = face_mean_8bit
    (path / "cubemap.json").write_text(json.dumps(rec))
    return path


def expect_error(fn, needle: str, name: str) -> None:
    try:
        fn()
    except ValueError as exc:
        check(needle in str(exc), name, str(exc))
    else:
        check(False, name, "no ValueError raised")


def main() -> None:
    mod = load_producer()
    linear = {n: [0.0002, 0.0003, 0.0004] for n in mod.FACE_ORDER}
    zeros = {n: [0.0, 0.0, 0.0] for n in mod.FACE_ORDER}
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)

        # 1. HDR cube: linear transfer preserved, real linear mean/energy.
        hdr_dir = make_cube(
            base,
            "cubemap_ground_floor_01",
            ext="hdr",
            transfer="linear",
            hdr=True,
            encoding="hdr",
            face_mean_linear=linear,
            face_mean_8bit=zeros,
        )
        rec = mod.parse_cube_dir(hdr_dir)
        check(
            rec["transfer"] == "linear",
            "HDR cube keeps transfer=linear",
            rec["transfer"],
        )
        check(
            rec["hdr"] is True and rec["encoding"] == "hdr",
            "HDR cube records hdr/encoding",
        )
        check(
            rec["face_mean"] == {n: [0.0002, 0.0003, 0.0004] for n in mod.FACE_ORDER},
            "HDR face_mean is the linear mean, not the 8-bit clamp",
        )
        check(rec["face_mean_space"] == "linear", "HDR face_mean_space is linear")
        want_lum = 0.2126 * 0.0002 + 0.7152 * 0.0003 + 0.0722 * 0.0004
        check(
            abs(rec["face_energy"]["py"] - want_lum) < 1e-6,
            "HDR face_energy is the linear luminance",
            str(rec["face_energy"]["py"]),
        )
        check(
            rec["face_energy"]["nz"] > 0.0,
            "HDR energy is above the 8-bit quantization floor",
        )
        check(
            all(str(p).endswith(".hdr") for p in rec["faces"].values()),
            "HDR face paths keep the .hdr extension",
        )

        # 2. Negative: HDR faces labelled sRGB would double-gamma.
        bad_gamma = make_cube(
            base,
            "bad_gamma",
            ext="hdr",
            transfer="srgb",
            hdr=True,
            encoding="hdr",
            face_mean_linear=linear,
        )
        expect_error(
            lambda: mod.parse_cube_dir(bad_gamma),
            "double-gamma",
            "HDR + transfer=srgb is rejected",
        )

        # 3. Negative: manifest says HDR but the faces are PNG.
        liar = make_cube(
            base,
            "liar",
            ext="png",
            transfer="linear",
            hdr=True,
            encoding="hdr",
            face_mean_linear=linear,
        )
        expect_error(
            lambda: mod.parse_cube_dir(liar),
            "does not match the face files",
            "hdr flag vs PNG faces is rejected",
        )

        # 4. Negative: mixed HDR/LDR face set.
        mixed = make_cube(
            base,
            "mixed",
            ext="hdr",
            transfer="linear",
            hdr=True,
            encoding="hdr",
            face_mean_linear=linear,
        )
        (mixed / "face_nz.png").write_bytes(b"fixture")
        mc = json.loads((mixed / "cubemap.json").read_text())
        mc["faces"]["nz"] = "face_nz.png"
        (mixed / "cubemap.json").write_text(json.dumps(mc))
        expect_error(
            lambda: mod.parse_cube_dir(mixed),
            "mixed HDR/LDR",
            "mixed face extensions are rejected",
        )

        # 5. 8-bit sRGB cube keeps the old transfer and is labelled encoded8.
        ldr = make_cube(
            base,
            "daylight",
            ext="png",
            transfer="srgb",
            hdr=False,
            encoding="png",
            face_mean_8bit={n: [0.5, 0.25, 0.125] for n in mod.FACE_ORDER},
        )
        rec = mod.parse_cube_dir(ldr)
        check(rec["transfer"] == "srgb", "8-bit sRGB cube keeps transfer=srgb")
        check(rec["hdr"] is False, "8-bit cube is not labelled HDR")
        check(
            rec["face_mean_space"] == "encoded8",
            "8-bit face mean is labelled encoded8, never linear",
        )
        check(
            rec["face_mean"]["py"] == [0.5, 0.25, 0.125],
            "8-bit face mean keeps the historical values",
        )

        # 6. Negative: HDR without a linear mean must not forward the clamped
        #    8-bit zeros as the energy.
        no_linear = make_cube(
            base,
            "no_linear",
            ext="hdr",
            transfer="linear",
            hdr=True,
            encoding="hdr",
            face_mean_8bit=zeros,
        )
        rec = mod.parse_cube_dir(no_linear)
        check(
            "face_mean" not in rec and "face_energy" not in rec,
            "HDR without a linear mean exposes no invented energy",
        )

        # 7. Negative: missing face file still fails closed.
        missing = make_cube(
            base,
            "missing",
            ext="hdr",
            transfer="linear",
            hdr=True,
            encoding="hdr",
            face_mean_linear=linear,
        )
        (missing / "face_px.hdr").unlink()
        expect_error(
            lambda: mod.parse_cube_dir(missing),
            "file is missing",
            "a missing face file is rejected",
        )

        # 8. Negative: non-finite linear mean is rejected.
        nan_dir = make_cube(
            base,
            "nan",
            ext="hdr",
            transfer="linear",
            hdr=True,
            encoding="hdr",
            face_mean_linear={n: [float("nan")] * 3 for n in mod.FACE_ORDER},
        )
        expect_error(
            lambda: mod.parse_cube_dir(nan_dir),
            "not finite",
            "a non-finite face mean is rejected",
        )

        # 9. End-to-end main() against a clean temp SRC/OUT (happy path only).
        clean = base / "clean"
        clean.mkdir()
        shutil.copytree(hdr_dir, clean / hdr_dir.name)
        shutil.copytree(ldr, clean / ldr.name)
        mod.SRC_DIR = clean
        mod.OUT_PATH = base / "out" / "cubemaps.json"
        mod.main()
        doc = json.loads(mod.OUT_PATH.read_text())
        check(
            doc["schema"] == "tat2.cubemaps/1", "main writes the cubemap index schema"
        )
        check(
            "cubemap_ground_floor_01" in doc["cubemaps"],
            "main keeps the valid HDR cube",
        )
        check("daylight" in doc["cubemaps"], "main keeps the valid 8-bit cube")
        check(
            doc["by_ue_path"]["/Game/MaterialLibrary/Utility/cubemap_ground_floor_01"]
            == "cubemap_ground_floor_01",
            "main indexes the cube by UE path",
        )

    print(f"PARSE_CUBEMAP_TEST: PASS checks={PASSED}")


if __name__ == "__main__":
    main()
