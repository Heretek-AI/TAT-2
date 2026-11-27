#!/usr/bin/env python3
"""Derive the authored T_stealthball_Array slice mapping (U-4).

The extractor (`tools/tat-extract/Exporter.cs`, `ExportTextureArray`) writes the
21 authored slices next to the array package:

    extracted/assets/Art/UI/HUD/Stealth_Ball/T_stealthball_Array/
        manifest.json
        slice_00.png ... slice_20.png

The Blueprint (`BPUI_UniversalStealthBall`) samples one slice of the array
(`NumTexturesInArray = 21`) through `M_TextureArray`'s `TexArray` + `Index`
parameters, but the native `TATUnifiedStealthWidget` code that chooses `Index`
is not in the extracted data. So the slice->direction mapping is **derived from
the pixels**, never invented:

1. the disc is the alpha>16 region of a slice (DXT5 carries the mask);
2. luma is Rec. 709 (0.2126R + 0.7152G + 0.0722B) on the RGB (0..255);
3. the lit cap is `luma >= p10 + 0.50 * (p99.9 - p10)` inside the disc
   (the cap is a bright plateau with a wide margin over the concealed face, so
   a range midpoint is stable for caps from ~1 % to ~100 % of the disc; a
   near-flat slice has no distinguishable cap and is recorded as `flat`);
4. the lit centroid's offset from the disc centre, normalised to the disc
   bbox, is the cap direction in the HUD's canvas frame (+x right, +y down);
5. the lit fraction is the cap's share of the disc.

If the centroids barely move (pairwise angular spread < 15 deg) the array is an
exposure ramp and the mapping is by lit fraction; otherwise it is directional
and the runtime uses angle + fraction. `mapping.kind` records the measurement.

Outputs `game/data/generated/ui/stealthball_array.json`. `status` is
`payload_present`, `payload_absent` (the extractor has not run yet — the HUD
keeps its labelled PORT_APPROX shader) or `payload_incomplete` (manifest exists
but a slice is missing; the producer exits 1 rather than emitting a partial map).

Usage::

    python3 tools/parse_stealthball_array.py
    python3 tools/parse_stealthball_array.py --extracted extracted --out /tmp/x.json
    python3 tools/parse_stealthball_array.py --require-payload   # gate mode
    python3 tools/parse_stealthball_array.py --print             # no write

The producer is deterministic: same PNG bytes -> same JSON bytes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from png_rgba import PngError, read_rgba  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
ASSET = "T_stealthball_Array"
REL_DIR = Path("assets") / "Art" / "UI" / "HUD" / "Stealth_Ball" / ASSET
DEFAULT_EXTRACTED = ROOT / "extracted"
DEFAULT_OUT = ROOT / "game" / "data" / "generated" / "ui" / "stealthball_array.json"

AUTHORED_SLICES = 21
AUTHORED_SIZE = 256
ALPHA_MIN = 16
LIT_P10 = 0.10
LIT_P_HIGH = 0.999
LIT_SPAN = 0.50
FLAT_SPAN = 8.0
CENTRED_OFFSET = 0.08
DIRECTIONAL_MIN_SPREAD_DEG = 15.0
## Port decision, recorded in `mapping.selection` so the runtime reads the same
## weight the mapping was produced with (game/src/ui/hud.gd defaults to it).
ANGLE_WEIGHT = 0.35
SCHEMA = "tat2.stealthball_array/1"


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _percentile(sorted_values: list[int], p: float) -> float:
    if not sorted_values:
        return 0.0
    idx = int(round(p * (len(sorted_values) - 1)))
    idx = max(0, min(len(sorted_values) - 1, idx))
    return float(sorted_values[idx])


def _luma(r: int, g: int, b: int) -> float:
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _slice_stats(
    width: int, height: int, rgba: bytes, index: int, name: str, sha: str
) -> dict:
    disc: list[int] = []
    x0, y0, x1, y1 = width, height, -1, -1
    for y in range(height):
        row = y * width * 4
        for x in range(width):
            if rgba[row + x * 4 + 3] >= ALPHA_MIN:
                disc.append(y * width + x)
                if x < x0:
                    x0 = x
                if x > x1:
                    x1 = x
                if y < y0:
                    y0 = y
                if y > y1:
                    y1 = y
    entry: dict = {
        "index": index,
        "file": name,
        "sha256": sha,
        "width": width,
        "height": height,
        "alpha_coverage": round(len(disc) / float(width * height), 6),
        "disc_bbox": [x0, y0, x1, y1] if disc else [0, 0, -1, -1],
    }
    if not disc:
        entry.update(
            {
                "degenerate": True,
                "disc_pixels": 0,
                "lit_fraction": 0.0,
                "lit_area_of_slice": 0.0,
                "centroid_offset": [0.0, 0.0],
                "angle_deg": 0.0,
                "direction": [0.0, 0.0, 1.0],
                "centred": True,
            }
        )
        return entry

    lumas: list[int] = []
    for p in disc:
        o = p * 4
        lumas.append(int(round(_luma(rgba[o], rgba[o + 1], rgba[o + 2]))))
    ordered = sorted(lumas)
    p10 = _percentile(ordered, LIT_P10)
    high = _percentile(ordered, LIT_P_HIGH)
    flat = (high - p10) < FLAT_SPAN
    threshold = p10 + LIT_SPAN * (high - p10)
    lit: list[int] = []
    lit_rgb = [0, 0, 0]
    dark_rgb = [0, 0, 0]
    dark_n = 0
    for p, lv in zip(disc, lumas):
        if (not flat) and lv >= threshold:
            lit.append(p)
            o = p * 4
            lit_rgb[0] += rgba[o]
            lit_rgb[1] += rgba[o + 1]
            lit_rgb[2] += rgba[o + 2]
        else:
            dark_n += 1
            o = p * 4
            dark_rgb[0] += rgba[o]
            dark_rgb[1] += rgba[o + 1]
            dark_rgb[2] += rgba[o + 2]

    lit_n = len(lit)
    mid_x = (x0 + x1) * 0.5
    mid_y = (y0 + y1) * 0.5
    half_w = max(1.0, (x1 - x0) * 0.5)
    half_h = max(1.0, (y1 - y0) * 0.5)
    if lit_n == 0:
        cx = mid_x
        cy = mid_y
        nx = 0.0
        ny = 0.0
        n2 = 0.0
    else:
        cx = sum(p % width for p in lit) / float(lit_n)
        cy = sum(p // width for p in lit) / float(lit_n)
        nx = max(-1.0, min(1.0, (cx - mid_x) / half_w))
        ny = max(-1.0, min(1.0, (cy - mid_y) / half_h))
        n2 = nx * nx + ny * ny
        if n2 > 1.0:
            scale = 1.0 / math.sqrt(n2)
            nx *= scale
            ny *= scale
            n2 = 1.0
    nz = math.sqrt(max(0.0, 1.0 - n2))
    lit_mean = [int(round(v / float(max(lit_n, 1)))) for v in lit_rgb]
    dark_mean = [int(round(v / float(max(dark_n, 1)))) for v in dark_rgb]
    entry.update(
        {
            "degenerate": False,
            "disc_pixels": len(disc),
            "luma_p10": round(p10, 2),
            "luma_p999": round(high, 2),
            "flat": flat,
            "lit_threshold": round(threshold, 2),
            "lit_fraction": round(lit_n / float(len(disc)), 6),
            "lit_area_of_slice": round(lit_n / float(width * height), 6),
            "lit_centroid": [round(cx, 3), round(cy, 3)],
            "centroid_offset": [round(nx, 6), round(ny, 6)],
            "angle_deg": round(math.degrees(math.atan2(ny, nx)), 3),
            "direction": [round(nx, 6), round(ny, 6), round(nz, 6)],
            "centred": math.hypot(nx, ny) < CENTRED_OFFSET,
            "mean_lit_rgb": lit_mean,
            "mean_dark_rgb": dark_mean,
        }
    )
    return entry


def _angle_spread(slices: list[dict]) -> float:
    dirs = [
        (s["centroid_offset"][0], s["centroid_offset"][1])
        for s in slices
        if not s.get("degenerate") and not s.get("centred")
    ]
    best = 0.0
    for i in range(len(dirs)):
        for j in range(i + 1, len(dirs)):
            ax, ay = dirs[i]
            bx, by = dirs[j]
            na = math.hypot(ax, ay)
            nb = math.hypot(bx, by)
            if na < 1e-9 or nb < 1e-9:
                continue
            dot = max(-1.0, min(1.0, (ax * bx + ay * by) / (na * nb)))
            best = max(best, math.degrees(math.acos(dot)))
    return round(best, 3)


def _empty(status: str, reason: str, source: dict | None = None) -> dict:
    return {
        "schema": SCHEMA,
        "status": status,
        "reason": reason,
        "source": source,
        "derivation": _derivation(),
        "authored": {
            "asset": ASSET,
            "slices": AUTHORED_SLICES,
            "size": [AUTHORED_SIZE, AUTHORED_SIZE],
            "pixel_format": "PF_DXT5",
            "material": "/Game/MaterialLibrary/Widget/M_TextureArray (TexArray + Index)",
        },
        "mapping": {
            "kind": None,
            "order": [],
            "angle_spread_deg": 0.0,
            "selection": _selection(),
        },
        "slices": [],
    }


def _derivation() -> dict:
    return {
        "frame": "canvas (+x right, +y down, +z toward the camera)",
        "disc": "alpha >= %d" % ALPHA_MIN,
        "luma": "Rec. 709 0.2126R + 0.7152G + 0.0722B (0..255)",
        "lit_threshold": "p10 + %.2f * (p99.9 - p10) inside the disc; flat if the span < %.1f"
        % (LIT_SPAN, FLAT_SPAN),
        "centroid": "mean lit pixel - disc bbox centre, normalised by the bbox half extents",
        "centred_offset": CENTRED_OFFSET,
        "directional_min_spread_deg": DIRECTIONAL_MIN_SPREAD_DEG,
        "selection": "derived-approx: nearest measured fraction (area ramp) or angle+fraction (directional)",
        "z": "front-hemisphere assumption: sqrt(1 - x^2 - y^2)",
    }


## The one port decision in the mapping: the angle term weight. Written to the
## JSON so the runtime consumes the producer's value instead of duplicating a
## magic number; `source=port_decision` keeps it out of the authored columns.
def _selection() -> dict:
    return {
        "kind": "derived-approx",
        "angle_weight": ANGLE_WEIGHT,
        "source": "port_decision",
        "note": "fraction error dominates; the angle term only breaks ties on a measured directional payload",
    }


def _find_manifest(extracted: Path) -> Path | None:
    direct = extracted / REL_DIR / "manifest.json"
    if direct.is_file():
        return direct
    matches = sorted(extracted.glob("assets/**/%s/manifest.json" % ASSET))
    return matches[0] if matches else None


def _build(manifest_path: Path, extracted: Path) -> tuple[dict, int]:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        return _empty("payload_incomplete", "manifest unreadable: %s" % exc), 1
    entries = manifest.get("slice_files") or []
    declared = int(manifest.get("slices") or 0)
    by_index: dict[int, dict] = {}
    for e in entries:
        try:
            by_index[int(e["index"])] = e
        except (KeyError, TypeError, ValueError):
            continue
    src = {
        "manifest": str(manifest_path.relative_to(extracted)),
        "manifest_sha256": _sha256(manifest_path.read_bytes()),
        "package": manifest.get("source_package", ""),
        "size": [int(manifest.get("width") or 0), int(manifest.get("height") or 0)],
        "slices": declared,
        "pixel_format": manifest.get("pixel_format", ""),
        "packed_data": manifest.get("packed_data", 0),
    }
    expected = AUTHORED_SLICES
    missing = [i for i in range(expected) if i not in by_index]
    if declared != expected:
        missing.extend(range(expected, max(expected, declared)))
    if missing:
        out = _empty(
            "payload_incomplete",
            "manifest declares %d slices and %d files; missing indices %s"
            % (declared, len(by_index), missing),
            src,
        )
        return out, 1
    slices: list[dict] = []
    for i in range(expected):
        entry = by_index[i]
        name = str(entry.get("file") or "")
        path = manifest_path.parent / name
        if not name or not path.is_file():
            out = _empty(
                "payload_incomplete",
                "slice %02d file missing: %r" % (i, name),
                src,
            )
            return out, 1
        data = path.read_bytes()
        try:
            w, h, rgba = read_rgba(path)
        except PngError as exc:
            out = _empty("payload_incomplete", "slice %02d: %s" % (i, exc), src)
            return out, 1
        if [w, h] != src["size"]:
            out = _empty(
                "payload_incomplete",
                "slice %02d is %dx%d, manifest says %s" % (i, w, h, src["size"]),
                src,
            )
            return out, 1
        slices.append(_slice_stats(w, h, rgba, i, name, _sha256(data)))

    spread = _angle_spread(slices)
    directional = spread >= DIRECTIONAL_MIN_SPREAD_DEG
    order = sorted(range(len(slices)), key=lambda k: (slices[k]["lit_fraction"], k))
    fractions = [slices[k]["lit_fraction"] for k in order]
    out = {
        "schema": SCHEMA,
        "status": "payload_present",
        "reason": "derived from %d authored slices" % len(slices),
        "source": src,
        "derivation": _derivation(),
        "authored": {
            "asset": ASSET,
            "slices": declared,
            "size": src["size"],
            "pixel_format": src["pixel_format"],
            "material": "/Game/MaterialLibrary/Widget/M_TextureArray (TexArray + Index)",
        },
        "mapping": {
            "kind": "directional" if directional else "area_ramp",
            "angle_spread_deg": spread,
            "order": order,
            "selection": _selection(),
            "lit_fraction_range": [fractions[0], fractions[-1]]
            if fractions
            else [0.0, 0.0],
        },
        "slices": slices,
    }
    return out, 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--extracted", default=str(DEFAULT_EXTRACTED))
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--require-payload", action="store_true")
    ap.add_argument("--print", dest="print_only", action="store_true")
    args = ap.parse_args(argv)

    extracted = Path(args.extracted)
    manifest_path = _find_manifest(extracted)
    if manifest_path is None:
        out = _empty(
            "payload_absent",
            "no %s/manifest.json under %s; run the extractor `textures` command"
            % (ASSET, extracted),
        )
        code = 2 if args.require_payload else 0
    else:
        out, code = _build(manifest_path, extracted)
        if args.require_payload and out["status"] != "payload_present":
            code = code or 2
    text = json.dumps(out, indent=1, sort_keys=True, ensure_ascii=True) + "\n"
    if args.print_only:
        sys.stdout.write(text)
        stream = sys.stderr
    else:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(text, encoding="utf-8")
        stream = sys.stdout
    kind = out["mapping"]["kind"] or "-"
    print(
        "STEALTHBALL_ARRAY status=%s slices=%d mapping_kind=%s out=%s"
        % (
            out["status"],
            len(out["slices"]),
            kind,
            "-" if args.print_only else args.out,
        ),
        file=stream,
    )
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
