#!/usr/bin/env python3
"""P0b Lane I ROI statistics: reference vs port luma/percentiles, beam rows,
16x9 unexplained-cream cell map, and the KF27 beam criteria.

The headline mean/p50/p95/%<8 numbers are computed with the *same* method as the
P0a/W9 baseline (`w9_frame_stats.py`: ImageMagick gray, ITU-R 601, 480 px
resize), so a port frame can be compared with L1's published numbers without a
second convention. Per-cell/row analysis uses full-resolution RGB sampled every
2nd pixel (documented in every line).

What is measured (and what is not)
----------------------------------
* Reference frames are the tracked clean keyframes under
  docs/reference/clip_1795033698901/clean/. Port frames come from
  build/qa/p0b_capture.gd. The camera poses are *approximate* alignments, not a
  pixel registration: the script reports numbers and a cell map; it does not
  claim a per-pixel parity score.
* "Cream" is a near-white, low-saturation pixel: luma >= 170 and max-min <= 46.
  The reference KF27 measures ~0.10 % cream, so a port cell with >= 5 % cream
  whose reference cell has < 1 % is reported as `cream_unexplained` (no
  corresponding reference cream). Authored white emitters are not inferred from
  pixels; pass `--allow-cells` for a documented exception.
* KF27 criteria are the cream/beam RE values: the wall emitter's max-bright
  cluster sits at x~17.8 %, y~40.0 % in clean/KF27; the beam is **one** band at
  40.0-40.5 % of frame height; the core is neutral (top-5 % saturation p95
  ~35); the glow falls off within ~1 % of frame height; the viewport outside
  the beam band has ~0.1 % cream. The port is scored against those *reported*
  numbers, never against a guessed threshold. The numbers live in
  `build/qa/kf27_beam_reference.json` so the headless beam probe asserts the
  same contract.
* `beam_close` is the Lounge C_57 extra pose, not KF27. It gets luma stats but
  no KF27 criteria; `foyer_beam` is the KF27-framed cue at
  (27,29.67,-55) -> (23.27,29.76,-57.4).

Usage
-----
  # one pose (reference chosen by pose id)
  build/qa/p0b_roi_stats.py --port build/qa/p0b/captures/<run>/lounge_beam.png \
      --pose lounge_beam

  # every fresh capture recorded in a manifest
  build/qa/p0b_roi_stats.py --all build/qa/p0b/captures/<run> \
      --manifest docs/reports/logs/p0b/<run>/manifest.json --json

  # schema proof / CI check (no image needed)
  build/qa/p0b_roi_stats.py --validate-manifest \
      docs/reports/logs/p0b/dry-run/manifest.json

  # reference-only calibration
  build/qa/p0b_roi_stats.py --port docs/reference/.../clean/KF27_*.jpg \
      --pose upper_foyer --reference-only

Exit codes: 0 measured/valid, 2 bad input or invalid manifest.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
from w9_frame_stats import stats as w9_stats  # noqa: E402  (same-method baseline)

W, H = 1920, 1080
COLS, ROWS = 16, 9
CELL_W, CELL_H = W // COLS, H // ROWS
CREAM_LUMA = 170
CREAM_SAT = 46
CELL_SAMPLE = 2
REF_DIR = REPO / "docs/reference/clip_1795033698901/clean"
SCHEMA = "tat2.p0b_capture/1"
KF27_REF_PATH = HERE / "kf27_beam_reference.json"


def _load_kf27_reference() -> dict:
    """The measured KF27 contract; fails closed if the tracked file is absent."""
    with KF27_REF_PATH.open(encoding="utf-8") as fh:
        data = json.load(fh)
    if data.get("schema") != "tat2.kf27_beam_reference/1":
        raise ValueError(f"{KF27_REF_PATH}: unexpected schema {data.get('schema')!r}")
    return data


KF27_REF = _load_kf27_reference()
KF27_MEASURED = KF27_REF["measured"]
KF27_TOL = KF27_REF["tolerance"]
POSE_IDS = [
    "gate",
    "upper_foyer",
    "yaw180",
    "foyer_beam",
    "foyer_beam_wide",
    "lounge",
    "lounge_beam",
    "beam_close",
    "gap_view",
]
# Lounge C_57 / landscape gap are extras, not KF27/S24 frames: luma stats only,
# no KF27 criteria.
POSE_EXTRAS = {"beam_close", "gap_view"}
POSE_REFS = {
    "gate": "KF16_01m40s_zipwire_gate_headlights.jpg",
    "upper_foyer": "KF27_03m27s_foyer_security_beam.jpg",
    "yaw180": "KF27_03m27s_foyer_security_beam.jpg",
    "foyer_beam": "KF27_03m27s_foyer_security_beam.jpg",
    "foyer_beam_wide": "KF27_03m27s_foyer_security_beam.jpg",
    "lounge": "KF27_03m27s_foyer_security_beam.jpg",
    "lounge_beam": "KF27_03m27s_foyer_security_beam.jpg",
    "beam_close": "KF27_03m27s_foyer_security_beam.jpg",
}
REF_FILES = {
    "KF16": "KF16_01m40s_zipwire_gate_headlights.jpg",
    "KF27": "KF27_03m27s_foyer_security_beam.jpg",
    "KF18": "KF18_02m14s_guildhall_arch_overlook.jpg",
}
MAGICK = shutil.which("magick") or shutil.which("convert")


def _fail(msg: str) -> int:
    print(f"P0B_ROI_FAIL {msg}", file=sys.stderr)
    return 2


def load_rgb(path: Path) -> tuple[bytes, tuple[int, int]]:
    """Full-resolution RGB bytes, resized to 1920x1080 when needed."""
    if not path.is_file():
        raise FileNotFoundError(path)
    if MAGICK:
        size = subprocess.run(
            [MAGICK, "identify", "-format", "%wx%h", str(path)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        native = tuple(int(v) for v in size.split("x")) if "x" in size else (0, 0)
        cmd = [MAGICK, str(path)]
        if native != (W, H):
            cmd += ["-resize", f"{W}x{H}!"]
        cmd += ["-depth", "8", "rgb:-"]
        raw = subprocess.run(cmd, check=True, capture_output=True).stdout
        if len(raw) != W * H * 3:
            raise ValueError(f"{path}: got {len(raw)} bytes, want {W * H * 3}")
        return raw, native
    try:
        from PIL import Image  # noqa: PLC0415 - optional fallback only
    except ImportError as exc:  # pragma: no cover - host without magick/Pillow
        raise RuntimeError("need ImageMagick (magick) or Pillow") from exc
    im = Image.open(path).convert("RGB")
    native = im.size
    if native != (W, H):
        im = im.resize((W, H), Image.LANCZOS)
    return im.tobytes(), native


def luma(r: int, g: int, b: int) -> int:
    return (299 * r + 587 * g + 114 * b) // 1000


def sat(r: int, g: int, b: int) -> int:
    return max(r, g, b) - min(r, g, b)


def px(raw: bytes, x: int, y: int) -> tuple[int, int, int]:
    o = (y * W + x) * 3
    return raw[o], raw[o + 1], raw[o + 2]


def region_stats(
    raw: bytes,
    x0: int = 0,
    y0: int = 0,
    x1: int = W,
    y1: int = H,
    step: int = CELL_SAMPLE,
) -> dict:
    hist = [0] * 256
    cream = 0
    total = 0
    for y in range(max(0, y0), min(H, y1), step):
        base = y * W
        for x in range(max(0, x0), min(W, x1), step):
            o = (base + x) * 3
            r, g, b = raw[o], raw[o + 1], raw[o + 2]
            lv = luma(r, g, b)
            hist[lv] += 1
            total += 1
            if lv >= CREAM_LUMA and sat(r, g, b) <= CREAM_SAT:
                cream += 1
    if total == 0:
        return {"samples": 0}

    def pct(frac: float) -> int:
        target = total * frac
        acc = 0
        for level, count in enumerate(hist):
            acc += count
            if acc >= target:
                return level
        return 255

    return {
        "samples": total,
        "mean": sum(i * c for i, c in enumerate(hist)) / total,
        "p50": pct(0.50),
        "p95": pct(0.95),
        "p99": pct(0.99),
        "pct_lt8": sum(hist[:8]) / total * 100.0,
        "pct_lt16": sum(hist[:16]) / total * 100.0,
        "pct_gt200": sum(hist[201:]) / total * 100.0,
        "cream_pct": cream / total * 100.0,
    }


def cell_map(raw: bytes) -> list[list[dict]]:
    out: list[list[dict]] = []
    for cy in range(ROWS):
        row: list[dict] = []
        for cx in range(COLS):
            row.append(
                region_stats(
                    raw,
                    cx * CELL_W,
                    cy * CELL_H,
                    (cx + 1) * CELL_W,
                    (cy + 1) * CELL_H,
                    CELL_SAMPLE,
                )
            )
        out.append(row)
    return out


def emitter_centroid(raw: bytes) -> dict:
    """Max-bright cluster in the left-wall box, the measured KF27 method.

    Box x 0..35 %, y 25..55 %; a pixel is a candidate at luma >= 90 with
    max-min <= 40; the cluster is every candidate within 10 luma of the max.
    clean/KF27 reproduces the RE's (17.8 %, 40.0 %) as ~(17.7 %, 40.2 %).
    """
    x0, x1 = 0, int(W * 0.35)
    y0, y1 = int(H * 0.25), int(H * 0.55)
    pts: list[tuple[int, int, int]] = []
    for y in range(y0, y1, CELL_SAMPLE):
        base = y * W
        for x in range(x0, x1, CELL_SAMPLE):
            o = (base + x) * 3
            r, g, b = raw[o], raw[o + 1], raw[o + 2]
            lv = luma(r, g, b)
            if lv >= 90 and sat(r, g, b) <= 40:
                pts.append((x, y, lv))
    if not pts:
        return {"found": False, "n": 0, "x_pct": 0.0, "y_pct": 0.0, "max_luma": 0}
    peak = max(p[2] for p in pts)
    top = [p for p in pts if p[2] >= peak - 10]
    return {
        "found": True,
        "n": len(top),
        "x_pct": 100.0 * sum(p[0] for p in top) / len(top) / W,
        "y_pct": 100.0 * sum(p[1] for p in top) / len(top) / H,
        "max_luma": peak,
    }


def beam_rows(raw: bytes) -> dict:
    """Row luma profile in the 28..52 % band, x 10..90 %, stride 2.

    The beam is the row with the largest mean luma over a median baseline; its
    glow is the excess at ±0.5/1/2/4 % of frame height. The core neutrality is
    the saturation of the top-5 % luma pixels in the peak row.
    """
    y0, y1 = int(H * 0.28), int(H * 0.52)
    x0, x1 = int(W * 0.10), int(W * 0.90)
    profile: dict[int, float] = {}
    for y in range(y0, y1):
        total = 0
        acc = 0
        base = y * W
        for x in range(x0, x1, CELL_SAMPLE):
            o = (base + x) * 3
            acc += luma(raw[o], raw[o + 1], raw[o + 2])
            total += 1
        profile[y] = acc / total if total else 0.0
    values = sorted(profile.values())
    baseline = values[len(values) // 2] if values else 0.0
    peak_y = max(profile, key=profile.get) if profile else y0
    peak = profile.get(peak_y, 0.0)
    excess = peak - baseline

    def at(frac: float) -> float:
        y = min(y1 - 1, max(y0, peak_y + int(round(frac * H))))
        return profile.get(y, baseline) - baseline

    offsets = {
        "-4%": at(-0.04),
        "-2%": at(-0.02),
        "-1%": at(-0.01),
        "-0.5%": at(-0.005),
        "0": 0.0,
        "+0.5%": at(0.005),
        "+1%": at(0.01),
        "+2%": at(0.02),
        "+4%": at(0.04),
    }
    # Core rows: contiguous rows around the peak whose excess is at least a
    # quarter of the peak excess (or 0.5 luma, whichever is larger).
    core_floor = max(0.5, 0.25 * excess)
    core_rows = 1
    y = peak_y - 1
    while y >= y0 and profile.get(y, baseline) - baseline >= core_floor:
        core_rows += 1
        y -= 1
    y = peak_y + 1
    while y < y1 and profile.get(y, baseline) - baseline >= core_floor:
        core_rows += 1
        y += 1
    # Distinct beam lines: local maxima over a +/-3 px window, merged when
    # adjacent, reported by excess. KF27 is one crisp horizontal band (40.0-
    # 40.5 %); secondary ripple under a quarter of the peak is not a band.
    candidates: list[tuple[int, float]] = []
    for yy in range(y0 + 3, y1 - 3):
        val = profile.get(yy, baseline) - baseline
        if val < 1.0:
            continue
        if all(
            profile.get(yy + d, baseline) <= profile.get(yy, baseline)
            for d in (-3, -2, -1, 1, 2, 3)
        ):
            candidates.append((yy, val))
    candidates.sort(key=lambda t: t[1], reverse=True)
    merged: list[tuple[int, float]] = []
    for yy, val in candidates:
        if all(abs(yy - m[0]) > 4 for m in merged):
            merged.append((yy, val))
    band_floor = max(4.0, 0.25 * excess)
    band_count = sum(1 for _, val in merged if val >= band_floor)
    peaks = [
        {"row": yy, "y_pct": 100.0 * yy / H, "excess": val} for yy, val in merged[:3]
    ]
    # Core neutrality: top 5 % luma pixels of the peak row, x 10..90 %.
    core: list[tuple[int, int]] = []
    base = peak_y * W
    for x in range(x0, x1):
        o = (base + x) * 3
        r, g, b = raw[o], raw[o + 1], raw[o + 2]
        core.append((luma(r, g, b), sat(r, g, b)))
    core.sort(key=lambda t: t[0], reverse=True)
    top_n = max(1, len(core) // 20)
    top = core[:top_n]
    sat_sorted = sorted(s for _, s in top)
    luma_sorted = sorted(lv for lv, _ in top)
    return {
        "band_y_pct": [28.0, 52.0],
        "baseline": baseline,
        "peak_row": peak_y,
        "peak_y_pct": 100.0 * peak_y / H,
        "peak_mean": peak,
        "excess": excess,
        "core_rows": core_rows,
        "bands": band_count,
        "band_floor": round(band_floor, 3),
        "peaks": peaks,
        "glow": offsets,
        "core_top5_luma_p50": luma_sorted[len(luma_sorted) // 2],
        "core_top5_sat_p50": sat_sorted[len(sat_sorted) // 2],
        "core_top5_sat_p95": sat_sorted[int(len(sat_sorted) * 0.95)],
    }


def cream_outside_beam(raw: bytes) -> dict:
    """Cream fraction outside the beam band (rows 30..50 %) — the slab test."""
    y0, y1 = int(H * 0.30), int(H * 0.50)
    cream = 0
    total = 0
    for y in range(0, H, CELL_SAMPLE):
        if y0 <= y < y1:
            continue
        base = y * W
        for x in range(0, W, CELL_SAMPLE):
            o = (base + x) * 3
            r, g, b = raw[o], raw[o + 1], raw[o + 2]
            total += 1
            if luma(r, g, b) >= CREAM_LUMA and sat(r, g, b) <= CREAM_SAT:
                cream += 1
    return {
        "cream_pct_outside_band": 100.0 * cream / total if total else 0.0,
        "samples": total,
        "band_y_pct": [30.0, 50.0],
    }


def cyan_node(raw: bytes) -> dict:
    """Cyan-ish cluster in the top-centre third (KF27's ceiling diamond)."""
    x0, x1 = int(W * 0.30), int(W * 0.70)
    y0, y1 = 0, int(H * 0.30)
    n = 0
    total = 0
    sx = 0
    sy = 0
    for y in range(y0, y1, CELL_SAMPLE):
        base = y * W
        for x in range(x0, x1, CELL_SAMPLE):
            o = (base + x) * 3
            r, g, b = raw[o], raw[o + 1], raw[o + 2]
            total += 1
            if b >= 100 and g >= 70 and b >= r + 40 and g >= r + 20:
                n += 1
                sx += x
                sy += y
    return {
        "found": n > 0,
        "fraction_pct": 100.0 * n / total if total else 0.0,
        "x_pct": 100.0 * sx / n / W if n else 0.0,
        "y_pct": 100.0 * sy / n / H if n else 0.0,
        "box": [30.0, 0.0, 70.0, 30.0],
    }


def kf27_criteria(
    raw: bytes,
    allow_cells: set[tuple[int, int]],
    cells: list[list[dict]] | None = None,
) -> dict:
    em = emitter_centroid(raw)
    br = beam_rows(raw)
    cream = cream_outside_beam(raw)
    cyan = cyan_node(raw)
    glow_l = max(0.0, float(br["glow"]["-1%"]))
    glow_r = max(0.0, float(br["glow"]["+1%"]))
    emitter_x = float(KF27_MEASURED["emitter_pct"]["x"])
    emitter_y = float(KF27_MEASURED["emitter_pct"]["y"])
    emitter_tol = float(KF27_TOL["emitter_pct"])
    row_lo, row_hi = (float(v) for v in KF27_MEASURED["beam_band_row_pct"])
    criteria = {
        "emitter_box": bool(em["found"])
        and 10.0 <= em["x_pct"] <= 26.0
        and 33.0 <= em["y_pct"] <= 47.0,
        "emitter_at_kf27": bool(em["found"])
        and abs(em["x_pct"] - emitter_x) <= emitter_tol
        and abs(em["y_pct"] - emitter_y) <= emitter_tol,
        "beam_row_band": row_lo <= br["peak_y_pct"] <= row_hi,
        "one_band": br["bands"] == int(KF27_MEASURED["beam_bands"]),
        "row_excess_ge_2": br["excess"] >= 2.0,
        "glow_falloff": br["excess"] > 0
        and glow_l <= 0.60 * br["excess"]
        and glow_r <= 0.60 * br["excess"],
        "core_neutral": br["core_top5_sat_p95"] <= float(KF27_TOL["core_sat_p95"]),
        "no_cream_slab_10pct": cream["cream_pct_outside_band"] <= 10.0,
        "cream_reference_like_2pct": cream["cream_pct_outside_band"]
        <= float(KF27_TOL["cream_outside_band_pct"]),
    }
    return {
        "emitter": em,
        "beam": br,
        "cream": cream,
        "cyan_node": cyan,
        "cells_measured": bool(cells),
        "allow_cells": sorted([list(a) for a in allow_cells]),
        "criteria": criteria,
        "criteria_met": sum(1 for v in criteria.values() if v),
        "criteria_total": len(criteria),
    }


def cell_codes(
    port: list[list[dict]], ref: list[list[dict]], allow: set[tuple[int, int]]
) -> tuple[list[list[str]], list[dict]]:
    codes: list[list[str]] = []
    rows: list[dict] = []
    for cy in range(ROWS):
        row: list[str] = []
        for cx in range(COLS):
            p = port[cy][cx]
            r = ref[cy][cx]
            pc = float(p.get("cream_pct", 0.0))
            rc = float(r.get("cream_pct", 0.0))
            pm = float(p.get("mean", 0.0))
            rm = float(r.get("mean", 0.0))
            if (cx, cy) in allow:
                code = "A"
                cls = "allowed"
            elif pc >= 5.0 and rc < 1.0:
                code = "C"
                cls = "cream_unexplained"
            elif pc >= 5.0 and rc >= 1.0:
                code = "c"
                cls = "cream_match"
            elif pm - rm >= 12.0:
                code = "B"
                cls = "brighter"
            elif rm - pm >= 12.0:
                code = "D"
                cls = "darker"
            else:
                code = "."
                cls = "ok"
            row.append(code)
            rows.append(
                {
                    "col": cx,
                    "row": cy,
                    "class": cls,
                    "port_mean": round(pm, 2),
                    "ref_mean": round(rm, 2),
                    "delta_mean": round(pm - rm, 2),
                    "port_cream_pct": round(pc, 2),
                    "ref_cream_pct": round(rc, 2),
                    "port_p95": p.get("p95", 0),
                    "ref_p95": r.get("p95", 0),
                }
            )
        codes.append(row)
    return codes, rows


def _resolve_reference(pose: str, explicit: str | None) -> Path:
    if explicit:
        return Path(explicit)
    name = POSE_REFS.get(pose)
    if not name:
        raise ValueError(f"no reference for pose {pose}; pass --ref")
    return REF_DIR / name


def measure(port: Path, pose: str, ref_path: Path, allow: set[tuple[int, int]]) -> dict:
    port_raw, port_native = load_rgb(port)
    ref_raw, ref_native = load_rgb(ref_path)
    port_w9 = w9_stats(port)
    ref_w9 = w9_stats(ref_path)
    port_cells = cell_map(port_raw)
    ref_cells = cell_map(ref_raw)
    codes, rows = cell_codes(port_cells, ref_cells, allow)
    beam = kf27_criteria(port_raw, allow, port_cells)
    ref_beam = kf27_criteria(ref_raw, set(), ref_cells)
    unexplained = [c for c in rows if c["class"] == "cream_unexplained"]
    counts: dict[str, int] = {}
    for c in rows:
        counts[c["class"]] = counts.get(c["class"], 0) + 1
    return {
        "pose": pose,
        "port": str(port),
        "reference": str(ref_path),
        "port_native": list(port_native),
        "reference_native": list(ref_native),
        "kf27_applies": ref_path.name.startswith("KF27") and pose not in POSE_EXTRAS,
        "pose_extra": pose in POSE_EXTRAS,
        "luma": {
            "port": {
                k: round(v, 3) if isinstance(v, float) else v
                for k, v in port_w9.items()
                if k != "file"
            },
            "reference": {
                k: round(v, 3) if isinstance(v, float) else v
                for k, v in ref_w9.items()
                if k != "file"
            },
            "delta": {
                key: round(float(port_w9[key]) - float(ref_w9[key]), 3)
                for key in ("mean", "p50", "p95", "pct_lt8", "pct_lt16", "pct_gt200")
            },
        },
        "cells": {
            "codes": codes,
            "rows": rows,
            "counts": counts,
            "allow": sorted([list(a) for a in allow]),
        },
        "beam": beam,
        "reference_beam": ref_beam,
        "unexplained_cells": unexplained,
    }


def print_report(m: dict) -> None:
    luma_p = m["luma"]["port"]
    luma_r = m["luma"]["reference"]
    d = m["luma"]["delta"]
    print(
        f"P0B_STATS kind=reference pose={m['pose']} file={m['reference']} "
        f"mean={luma_r['mean']:.1f} p50={luma_r['p50']:.0f} p95={luma_r['p95']:.0f} "
        f"lt8={luma_r['pct_lt8']:.1f} lt16={luma_r['pct_lt16']:.1f} gt200={luma_r['pct_gt200']:.2f}"
    )
    print(
        f"P0B_STATS kind=port pose={m['pose']} file={m['port']} "
        f"mean={luma_p['mean']:.1f} p50={luma_p['p50']:.0f} p95={luma_p['p95']:.0f} "
        f"lt8={luma_p['pct_lt8']:.1f} lt16={luma_p['pct_lt16']:.1f} gt200={luma_p['pct_gt200']:.2f}"
    )
    print(
        f"P0B_DELTA pose={m['pose']} d_mean={d['mean']:+.1f} d_p50={d['p50']:+.0f} "
        f"d_p95={d['p95']:+.0f} d_lt8={d['pct_lt8']:+.1f} d_gt200={d['pct_gt200']:+.2f}"
    )
    b = m["beam"]
    rb = m["reference_beam"]
    if m.get("kf27_applies"):
        peaks_txt = (
            ",".join(f"{p['y_pct']:.1f}@{p['excess']:.1f}" for p in b["beam"]["peaks"])
            or "none"
        )
        rpeaks_txt = (
            ",".join(f"{p['y_pct']:.1f}@{p['excess']:.1f}" for p in rb["beam"]["peaks"])
            or "none"
        )
        print(
            f"P0B_BEAM pose={m['pose']} emitter_pct=({b['emitter']['x_pct']:.1f},{b['emitter']['y_pct']:.1f}) "
            f"peak_row={b['beam']['peak_y_pct']:.2f}% excess={b['beam']['excess']:.2f} "
            f"bands={b['beam']['bands']} peaks=({peaks_txt}) core_px={b['beam']['core_rows']} "
            f"glow_1pct=({b['beam']['glow']['-1%']:+.2f},{b['beam']['glow']['+1%']:+.2f}) "
            f"core_sat_p95={b['beam']['core_top5_sat_p95']} "
            f"cream_outside_band={b['cream']['cream_pct_outside_band']:.2f}% "
            f"cyan=(found={b['cyan_node']['found']},pct={b['cyan_node']['fraction_pct']:.3f})"
        )
        print(
            f"P0B_BEAM_REF pose={m['pose']} emitter_pct=({rb['emitter']['x_pct']:.1f},{rb['emitter']['y_pct']:.1f}) "
            f"peak_row={rb['beam']['peak_y_pct']:.2f}% excess={rb['beam']['excess']:.2f} "
            f"bands={rb['beam']['bands']} peaks=({rpeaks_txt}) core_px={rb['beam']['core_rows']} "
            f"glow_1pct=({rb['beam']['glow']['-1%']:+.2f},{rb['beam']['glow']['+1%']:+.2f}) "
            f"core_sat_p95={rb['beam']['core_top5_sat_p95']} "
            f"cream_outside_band={rb['cream']['cream_pct_outside_band']:.2f}%"
        )
        print(
            f"P0B_KF27 pose={m['pose']} met={b['criteria_met']}/{b['criteria_total']} "
            + " ".join(f"{k}={str(v).lower()}" for k, v in b["criteria"].items())
        )
    elif m.get("pose_extra"):
        print(
            f"P0B_EXTRA pose={m['pose']} extra=true kf27_applies=false "
            "reason=lounge_c_57_not_kf27"
        )
    print(
        f"P0B_CELLMAP pose={m['pose']} grid={COLS}x{ROWS} "
        f"cream=luma>={CREAM_LUMA},sat<={CREAM_SAT} stride={CELL_SAMPLE} "
        f"unexplained={len(m['unexplained_cells'])}"
    )
    legend = (
        ". ok  B brighter  D darker  c cream-in-both  C cream-unexplained  A allowed"
    )
    print(f"P0B_CELLMAP_LEGEND {legend}")
    for cy, row in enumerate(m["cells"]["codes"]):
        print(f"P0B_CELLMAP_ROW row={cy} " + " ".join(row))
    counts = m["cells"]["counts"]
    print(
        "P0B_CELLMAP_COUNTS "
        + " ".join(f"{k}={v}" for k, v in sorted(counts.items()))
        + " unexplained_cells="
        + (",".join(f"{c['col']},{c['row']}" for c in m["unexplained_cells"]) or "none")
    )


def validate_manifest(m: dict) -> list[str]:
    errs: list[str] = []
    required = [
        "schema",
        "run_id",
        "dry_run",
        "self_test",
        "repo_root",
        "out_dir",
        "git",
        "host",
        "gpu",
        "engine",
        "lens",
        "settle",
        "seed",
        "env",
        "beam_card",
        "poses",
        "audio",
    ]
    for key in required:
        if key not in m:
            errs.append(f"missing top-level key {key}")
    if str(m.get("schema", "")) != SCHEMA:
        errs.append(f"schema != {SCHEMA}")
    if not isinstance(m.get("dry_run"), bool):
        errs.append("dry_run is not a bool")
    if not isinstance(m.get("self_test"), bool):
        errs.append("self_test is not a bool")
    lens = m.get("lens", {})
    if not isinstance(lens, dict):
        errs.append("lens is not a dict")
        lens = {}
    if abs(float(lens.get("fov_vertical_deg", 0.0)) - 54.54) > 0.001:
        errs.append("lens.fov_vertical_deg != 54.54")
    if lens.get("resolution") != [W, H]:
        errs.append("lens.resolution != [1920,1080]")
    if str(lens.get("keep_aspect", "")) != "height":
        errs.append("lens.keep_aspect != height")
    settle = m.get("settle", {})
    if not isinstance(settle, dict):
        errs.append("settle is not a dict")
        settle = {}
    if int(settle.get("frames", 0)) != 60:
        errs.append("settle.frames != 60")
    if int(settle.get("capture_frames", 0)) != 5:
        errs.append("settle.capture_frames != 5")
    if str(settle.get("selector", "")) != "median-mean":
        errs.append("settle.selector != median-mean")
    seed = m.get("seed", {})
    if not isinstance(seed, dict):
        errs.append("seed is not a dict")
        seed = {}
    if int(seed.get("official_clip_seed", 0)) != 1025051536:
        errs.append("seed.official_clip_seed != 1025051536")
    if "requested" not in seed or "active_map_seed" not in seed:
        errs.append("seed missing requested/active_map_seed")
    beam = m.get("beam_card", {})
    if not isinstance(beam, dict) or beam.get("mode") not in ("on", "off"):
        errs.append("beam_card.mode not on/off")
    elif not str(beam.get("mechanism", "")):
        errs.append("beam_card.mechanism empty")
    git = m.get("git", {})
    if (
        not isinstance(git, dict)
        or not str(git.get("sha", ""))
        or str(git.get("sha")) == "unknown"
    ):
        errs.append("git.sha missing")
    gpu = m.get("gpu", {})
    if not isinstance(gpu, dict) or "used_by_capture" not in gpu:
        errs.append("gpu.used_by_capture missing")
    elif bool(gpu.get("used_by_capture")) == bool(m.get("dry_run")):
        errs.append("gpu.used_by_capture disagrees with dry_run")
    poses = m.get("poses", [])
    if not isinstance(poses, list) or not poses:
        errs.append("poses is not a non-empty list")
        poses = []
    seen: set[str] = set()
    for p in poses:
        if not isinstance(p, dict):
            errs.append("pose entry is not a dict")
            continue
        pid = str(p.get("id", ""))
        if pid not in POSE_IDS:
            errs.append(f"unknown pose id {pid}")
        if pid in seen:
            errs.append(f"duplicate pose id {pid}")
        seen.add(pid)
        if not (isinstance(p.get("eye"), list) and len(p["eye"]) == 3):
            errs.append(f"{pid} eye is not 3 numbers")
        if not (isinstance(p.get("target"), list) and len(p["target"]) == 3):
            errs.append(f"{pid} target is not 3 numbers")
        status = str(p.get("status", ""))
        if status not in ("dry_run", "captured", "failed", "skipped"):
            errs.append(f"{pid} status {status}")
        if m.get("dry_run"):
            if status != "dry_run":
                errs.append(f"{pid} dry-run manifest has status {status}")
            if p.get("png"):
                errs.append(f"{pid} dry-run manifest has a png")
        elif status == "captured":
            if len(p.get("frames_mean", [])) != 5:
                errs.append(f"{pid} frames_mean size != 5")
            if not p.get("png"):
                errs.append(f"{pid} captured without png")
            if p.get("png_size") != [W, H]:
                errs.append(f"{pid} png_size != [1920,1080]")
            if not 0 <= int(p.get("median_index", -1)) < 5:
                errs.append(f"{pid} median_index out of range")
    audio = m.get("audio", {})
    if not isinstance(audio, dict) or "enabled" not in audio or "reason" not in audio:
        errs.append("audio block missing enabled/reason")
    elif not isinstance(audio.get("enabled"), bool):
        errs.append("audio.enabled is not a bool")
    elif not audio.get("enabled") and not str(audio.get("reason", "")):
        errs.append("disabled audio has no reason")
    return errs


def _allow_set(raw: str) -> set[tuple[int, int]]:
    out: set[tuple[int, int]] = set()
    for part in raw.split(";"):
        part = part.strip()
        if not part:
            continue
        bits = part.split(",")
        if len(bits) != 2:
            raise ValueError(f"bad --allow-cells entry {part!r} (want col,row;col,row)")
        out.add((int(bits[0]), int(bits[1])))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--port", type=Path, help="port PNG (1920x1080; resized if not)")
    ap.add_argument(
        "--pose", choices=POSE_IDS, help="pose id (selects the reference keyframe)"
    )
    ap.add_argument(
        "--ref", help="reference image override (default: the pose's clean keyframe)"
    )
    ap.add_argument(
        "--all", type=Path, help="capture directory or manifest for every captured pose"
    )
    ap.add_argument("--manifest", type=Path, help="manifest path (with --all)")
    ap.add_argument(
        "--validate-manifest", type=Path, help="validate a capture manifest and exit"
    )
    ap.add_argument(
        "--allow-cells",
        default="",
        help="documented cell exceptions: 'col,row;col,row'",
    )
    ap.add_argument(
        "--reference-only", action="store_true", help="measure the reference side only"
    )
    ap.add_argument(
        "--json", action="store_true", help="print the JSON summary at the end"
    )
    ap.add_argument("--json-out", type=Path, help="write the JSON summary to this file")
    args = ap.parse_args()

    if args.validate_manifest:
        path = args.validate_manifest
        if not path.is_file():
            return _fail(f"manifest missing: {path}")
        try:
            m = json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            return _fail(f"manifest is not JSON: {exc}")
        errs = validate_manifest(m)
        if errs:
            for e in errs:
                print(f"P0B_MANIFEST_INVALID {path}: {e}", file=sys.stderr)
            return 2
        print(
            f"P0B_MANIFEST_OK path={path} poses={len(m.get('poses', []))} "
            f"dry_run={str(m.get('dry_run')).lower()} run_id={m.get('run_id')}"
        )
        return 0

    allow = _allow_set(args.allow_cells)

    if args.all:
        manifest = args.manifest
        if manifest is None:
            cand = args.all / "manifest.json" if args.all.is_dir() else args.all
            manifest = cand
        if manifest is None or not manifest.is_file():
            return _fail(f"manifest not found for --all {args.all}")
        m = json.loads(manifest.read_text())
        errs = validate_manifest(m)
        if errs:
            for e in errs:
                print(f"P0B_MANIFEST_INVALID {manifest}: {e}", file=sys.stderr)
            return 2
        if m.get("dry_run"):
            print(
                f"P0B_ALL manifest={manifest} dry_run=true poses={len(m.get('poses', []))} (no images)"
            )
            return 0
        repo = Path(m.get("repo_root", REPO))
        results = []
        for p in m.get("poses", []):
            if p.get("status") != "captured":
                print(f"P0B_ALL_SKIP pose={p.get('id')} status={p.get('status')}")
                continue
            pid = str(p.get("id"))
            port = Path(p.get("png", ""))
            if not port.is_absolute():
                port = repo / port
            if not port.is_file():
                cand = args.all / (pid + ".png")
                if cand.is_file():
                    port = cand
                else:
                    print(f"P0B_ALL_MISSING pose={pid} png={port}", file=sys.stderr)
                    continue
            ref_name = REF_FILES.get(str(p.get("ref_keyframe", ""))) or POSE_REFS.get(
                pid
            )
            if not ref_name:
                print(
                    f"P0B_ALL_MISSING_REF pose={pid} ref={p.get('ref_keyframe')}",
                    file=sys.stderr,
                )
                continue
            one = measure(port, pid, REF_DIR / ref_name, allow)
            print_report(one)
            results.append(one)
        payload = {"manifest": str(manifest), "results": results}
        if args.json_out:
            args.json_out.parent.mkdir(parents=True, exist_ok=True)
            args.json_out.write_text(json.dumps(payload, indent=2) + "\n")
        if args.json:
            print(json.dumps(payload, indent=2))
        return 0

    if not args.port or not args.pose:
        return _fail("need --port and --pose (or --all/--validate-manifest)")
    if args.pose not in POSE_REFS and not args.ref:
        return _fail(f"no reference for pose {args.pose} (A/B-only extra); pass --ref")
    ref_path = _resolve_reference(args.pose, args.ref)
    if not ref_path.is_file():
        return _fail(f"reference missing: {ref_path}")
    if args.reference_only:
        raw, native = load_rgb(ref_path)
        w9 = w9_stats(ref_path)
        print(
            f"P0B_STATS kind=reference pose={args.pose} file={ref_path} "
            f"mean={w9['mean']:.1f} p50={w9['p50']:.0f} p95={w9['p95']:.0f} "
            f"lt8={w9['pct_lt8']:.1f} lt16={w9['pct_lt16']:.1f} gt200={w9['pct_gt200']:.2f}"
        )
        m = kf27_criteria(raw, allow)
        if args.pose in POSE_EXTRAS:
            print(
                f"P0B_EXTRA pose={args.pose} extra=true kf27_applies=false "
                "reason=lounge_c_57_not_kf27"
            )
        elif ref_path.name.startswith("KF27"):
            print(
                f"P0B_KF27_REF pose={args.pose} met={m['criteria_met']}/{m['criteria_total']} "
                + " ".join(f"{k}={str(v).lower()}" for k, v in m["criteria"].items())
            )
        if args.json:
            print(
                json.dumps(
                    {
                        "pose": args.pose,
                        "reference": str(ref_path),
                        "native": native,
                        "beam": m,
                    },
                    indent=2,
                )
            )
        return 0
    result = measure(args.port, args.pose, ref_path, allow)
    print_report(result)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2) + "\n")
    if args.json:
        print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
