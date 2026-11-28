#!/usr/bin/env python3
"""
Build the P4.1 IBL cubemap index from the extractor's TextureCube faces.

`tools/tat-extract cubemaps` writes, for each authored sky cubemap:

    extracted/assets/TAT/Content/Cubemaps/<id>/cubemap.json
    extracted/assets/TAT/Content/Cubemaps/<id>/face_px.png ... face_nz.png

and this producer validates the six faces and writes:

    game/data/generated/ibl/cubemaps.json

The index is deliberately explicit about the face order and the colour
transfer:
  - `faces_order` is px/nx/py/ny/pz/nz and `ue_face_order` is UE's ECubeFace
    (PosX, NegX, PosY, NegY, PosZ, NegZ) — the order of the six slices in the
    cooked TextureCube. The extractor writes the names, so the runtime never
    guesses a face index;
  - `transfer` is "linear" for the HDR (`.hdr`) faces and for TC_HDR/float
    cubemaps that were exported as 8-bit PNG, and "srgb" only for an authored
    sRGB 8-bit cube. An HDR face is linear by construction: a manifest that
    calls it "srgb" is rejected instead of applying a second gamma transform;
  - `face_mean` is the linear RGB face mean when the extractor recorded
    `face_mean_linear`; the 8-bit clamped mean (`face_mean_8bit`) is only used
    for non-HDR cubes and is labelled `face_mean_space: "encoded8"`. The
    per-face `face_energy` (luminance of that mean) is what the IBL path can
    compare with the authored SkyLight energy — it is never invented when the
    HDR mean is absent.

A clean extraction without the `cubemaps` pass is not an error: the index is
written with zero cubemaps and `available=false` consumers (today's look).
Malformed sidecars or missing face files fail the producer, because a partially
written cube must never be used as ambient light.
"""

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "extracted" / "assets" / "TAT" / "Content" / "Cubemaps"
OUT_PATH = ROOT / "game" / "data" / "generated" / "ibl" / "cubemaps.json"

FACE_ORDER = ["px", "nx", "py", "ny", "pz", "nz"]
UE_FACE_ORDER = ["PosX", "NegX", "PosY", "NegY", "PosZ", "NegZ"]
RES_PREFIX = "res://assets/ue/Content/Cubemaps"


def _require(rec: dict, key: str, path: Path):
    if key not in rec:
        raise ValueError("%s: missing '%s'" % (path, key))
    return rec[key]


def _face_means(rec: dict, hdr: bool, manifest_path: Path) -> tuple[dict | None, str]:
    """Pick the face-mean set the loader may trust.

    HDR faces carry the real linear energy (`face_mean_linear`); the 8-bit
    clamped mean is near zero for the authored sky cube and must never be
    presented as the energy. Non-HDR cubes keep the historical `face_mean_8bit`
    value, labelled as encoded 8-bit so a consumer cannot mistake it for linear.
    """
    linear = rec.get("face_mean_linear")
    encoded = rec.get("face_mean_8bit") or rec.get("face_mean")
    source = linear if isinstance(linear, dict) else (None if hdr else encoded)
    space = "linear" if isinstance(linear, dict) else "encoded8"
    if source is None:
        return None, space
    out: dict = {}
    for name in FACE_ORDER:
        m = source.get(name)
        if not isinstance(m, list) or len(m) != 3:
            continue
        try:
            rgb = [float(c) for c in m]
        except (TypeError, ValueError):
            raise ValueError(
                "%s: face mean '%s' is not three numbers (%r)"
                % (manifest_path, name, m)
            )
        if not all(math.isfinite(c) for c in rgb):
            raise ValueError(
                "%s: face mean '%s' is not finite (%r)" % (manifest_path, name, m)
            )
        out[name] = [round(c, 6) for c in rgb]
    return (out or None), space


def parse_cube_dir(path: Path) -> dict:
    manifest_path = path / "cubemap.json"
    rec = json.loads(manifest_path.read_text())
    if not isinstance(rec, dict):
        raise ValueError("%s: cubemap.json is not an object" % manifest_path)
    cube_id = str(_require(rec, "id", manifest_path))
    if path.name != cube_id:
        raise ValueError(
            "%s: id '%s' does not match the directory" % (manifest_path, cube_id)
        )
    ue_path = str(_require(rec, "ue_path", manifest_path))
    if not ue_path.startswith("/Game/") and not ue_path.startswith("/Engine/"):
        raise ValueError(
            "%s: ue_path '%s' is not a UE mount path" % (manifest_path, ue_path)
        )
    width = int(_require(rec, "width", manifest_path))
    height = int(_require(rec, "height", manifest_path))
    if width <= 0 or height <= 0:
        raise ValueError("%s: invalid size %dx%d" % (manifest_path, width, height))
    transfer = str(rec.get("transfer", "linear"))
    if transfer not in ("linear", "srgb"):
        raise ValueError(
            "%s: transfer '%s' is not linear|srgb" % (manifest_path, transfer)
        )
    faces = _require(rec, "faces", manifest_path)
    if not isinstance(faces, dict):
        raise ValueError("%s: faces is not an object" % manifest_path)
    out_faces = {}
    face_exts = set()
    for name in FACE_ORDER:
        rel = faces.get(name)
        if not isinstance(rel, str) or not rel:
            raise ValueError("%s: face '%s' has no file" % (manifest_path, name))
        disk = path / rel
        if not disk.is_file():
            raise ValueError(
                "%s: face '%s' file is missing (%s)" % (manifest_path, name, disk)
            )
        out_faces[name] = "%s/%s/%s" % (RES_PREFIX, cube_id, rel)
        face_exts.add(Path(rel).suffix.lower())
    # An HDR cube is six .hdr faces or six PNGs — never a mixed set, and the
    # physical extension wins over a stale manifest flag.
    hdr_exts = {".hdr", ".exr"}
    if face_exts & hdr_exts and face_exts - hdr_exts:
        raise ValueError(
            "%s: mixed HDR/LDR face extensions %s" % (manifest_path, sorted(face_exts))
        )
    hdr = bool(face_exts & hdr_exts)
    declared_hdr = bool(rec.get("hdr", False)) or rec.get("encoding") == "hdr"
    if declared_hdr != hdr:
        raise ValueError(
            "%s: manifest hdr=%r does not match the face files %s"
            % (manifest_path, declared_hdr, sorted(face_exts))
        )
    if hdr and transfer != "linear":
        # HDR is already linear; an sRGB label would make the loader apply a
        # second gamma transform. Fail closed instead of inventing a transfer.
        raise ValueError(
            "%s: HDR faces are linear but transfer='%s' (double-gamma guard)"
            % (manifest_path, transfer)
        )
    out_means, mean_space = _face_means(rec, hdr, manifest_path)
    out_energy = None
    if out_means:
        out_energy = {
            name: round(0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2], 6)
            for name, rgb in out_means.items()
        }
    return {
        "id": cube_id,
        "ue_path": ue_path,
        "source_package": rec.get("source_package"),
        "width": width,
        "height": height,
        "pixel_format": rec.get("pixel_format"),
        "hdr": hdr,
        "encoding": "hdr" if hdr else "png",
        "transfer": transfer,
        "faces": out_faces,
        **(
            {"face_mean": out_means, "face_mean_space": mean_space} if out_means else {}
        ),
        **({"face_energy": out_energy} if out_energy else {}),
    }


def _rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def main() -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    cubes = {}
    by_ue_path = {}
    rejected = 0
    if SRC_DIR.is_dir():
        for path in sorted(p for p in SRC_DIR.iterdir() if p.is_dir()):
            try:
                rec = parse_cube_dir(path)
            except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
                print("ERROR: %s" % exc, file=sys.stderr)
                rejected += 1
                continue
            if rec["id"] in cubes:
                print("ERROR: duplicate cubemap id '%s'" % rec["id"], file=sys.stderr)
                rejected += 1
                continue
            if rec["ue_path"] in by_ue_path:
                print(
                    "ERROR: duplicate ue_path '%s' (%s and %s)"
                    % (rec["ue_path"], by_ue_path[rec["ue_path"]], rec["id"]),
                    file=sys.stderr,
                )
                rejected += 1
                continue
            cubes[rec["id"]] = rec
            by_ue_path[rec["ue_path"]] = rec["id"]
    else:
        print(
            "note: %s absent; writing an empty IBL index (run `tat-extract cubemaps` first)"
            % _rel(SRC_DIR)
        )

    doc = {
        "schema": "tat2.cubemaps/1",
        "generated_by": "tools/parse_cubemap.py",
        "source": _rel(SRC_DIR),
        "faces_order": FACE_ORDER,
        "ue_face_order": UE_FACE_ORDER,
        "cubemaps": cubes,
        "by_ue_path": dict(sorted(by_ue_path.items())),
        "counts": {
            "cubemaps": len(cubes),
            "faces": 6 * len(cubes),
            "rejected": rejected,
        },
    }
    OUT_PATH.write_text(json.dumps(doc, indent=2) + "\n")
    print(
        "cubemaps: %d converged, %d rejected -> %s"
        % (len(cubes), rejected, _rel(OUT_PATH))
    )
    for cube_id, rec in cubes.items():
        means = rec.get("face_mean") or {}
        energies = rec.get("face_energy") or {}
        gauge = ""
        if "py" in energies and "ny" in energies:
            gauge = " py_lum=%.6f ny_lum=%.6f" % (
                energies["py"],
                energies["ny"],
            )
        elif "py" in means and "ny" in means:
            gauge = " py_lum=%.4f ny_lum=%.4f" % (
                0.2126 * means["py"][0]
                + 0.7152 * means["py"][1]
                + 0.0722 * means["py"][2],
                0.2126 * means["ny"][0]
                + 0.7152 * means["ny"][1]
                + 0.0722 * means["ny"][2],
            )
        print(
            "  %-28s %s %dx%d %s%s%s"
            % (
                cube_id,
                rec["ue_path"],
                rec["width"],
                rec["height"],
                rec["encoding"],
                rec["transfer"],
                gauge,
            )
        )
    if rejected:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
