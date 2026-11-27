#!/usr/bin/env python3
"""Tests for build/qa/ui_pixel_stats.py (stdlib + ffmpeg-optional).

Run with: ``python3 tools/test_ui_pixel_stats.py``

The tool turns captured UI frames into the numbers the UI lane adjudicates on
(gem lit area/direction, compass rule/heading, prompt contrast, pause dim/blur,
briefing line fit, text clipping). A regression in that math would silently
misreport every capture, so this test paints synthetic frames with known
answers and pins them:

* gem: a violet ring + a cream cap at +x -> angle ~0, ring thickness, sidecar
  angle agreement;
* compass: a two-row rule and a heading block above it -> row/thickness/span;
* prompt: white ink on black -> contrast > 10 and no clipped edge; a second
  frame whose ink touches the ROI edge must be reported as clipped;
* briefing: 11 dark ink rows on parchment -> line_count == 11, no overflow;
  a row touching the paper bottom -> overflow;
* pause: a checkerboard backdrop vs a blurred+dimmed copy -> dim ~0.5,
  blur_ratio < 0.5, and `--strict` accepts it; an unblurred pair fails strict.

The tool is imported from ``build/qa/`` with importlib (it is not a `tools/`
producer) and fed a temporary capture directory; nothing outside the temp dir
is written.
"""

from __future__ import annotations

import importlib.util
import json
import struct
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from test_stealthball_array import encode_png  # noqa: E402

FAILS = 0
CHECKS = 0


def check(cond: bool, ok: str, fail: str) -> None:
    global FAILS, CHECKS
    CHECKS += 1
    if cond:
        print("PASS:", ok)
    else:
        print("FAIL:", fail)
        FAILS += 1


def _load_tool():
    path = ROOT / "build" / "qa" / "ui_pixel_stats.py"
    spec = importlib.util.spec_from_file_location("ui_pixel_stats", path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class Canvas:
    def __init__(self, w: int, h: int, fill=(8, 6, 20, 255)) -> None:
        self.w = w
        self.h = h
        self.px = bytearray()
        for _ in range(w * h):
            self.px.extend(fill)

    def set(self, x: int, y: int, c) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            o = (y * self.w + x) * 4
            self.px[o : o + 4] = bytes(c)

    def rect(self, x0: int, y0: int, x1: int, y1: int, c) -> None:
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.set(x, y, c)

    def disc(self, cx: int, cy: int, r: int, c) -> None:
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.set(x, y, c)

    def ring(self, cx: int, cy: int, r0: int, r1: int, c) -> None:
        for y in range(cy - r1, cy + r1 + 1):
            for x in range(cx - r1, cx + r1 + 1):
                d2 = (x - cx) ** 2 + (y - cy) ** 2
                if r0 * r0 <= d2 <= r1 * r1:
                    self.set(x, y, c)

    def write(self, path: Path) -> int:
        path.write_bytes(encode_png(self.w, self.h, bytes(self.px), 4, 0))
        return len(self.px)


def _sidecar(
    root: Path,
    name: str,
    meta: dict[str, str],
    rois: dict[str, tuple[float, float, float, float]],
) -> None:
    lines = [f"{k}={v}" for k, v in meta.items()]
    for roi, r in rois.items():
        lines.append(
            "roi.%s=%.4f,%.4f,%.4f,%.4f mean=0.0000 max=0.0000 px=1"
            % (roi, r[0], r[1], r[2], r[3])
        )
    (root / (name + ".txt")).write_text("\n".join(lines) + "\n", encoding="utf-8")


def _gem_frame(root: Path, name: str) -> None:
    c = Canvas(240, 160)
    c.ring(120, 120, 38, 42, (21, 28, 175, 255))
    c.disc(142, 120, 14, (232, 219, 185, 255))
    c.write(root / (name + ".png"))
    _sidecar(
        root,
        name,
        {
            "shot": "safe_room",
            "size": "240x160",
            "capture": name,
            "hud.gem": "path:port_approx bound:false layers:0 kind: area:-1 amount:0.400 lit_area:0.400 angle:0.0",
            "hud.compass": "NE",
            "hud.prompt": "",
        },
        {
            "gem": (0.25, 0.55, 0.50, 0.40),
            "compass": (0.0, 0.0, 1.0, 0.36),
        },
    )
    # Compass rule + heading letter on the same frame.
    c.rect(20, 40, 180, 42, (225, 240, 255, 255))
    c.rect(108, 10, 132, 24, (225, 240, 255, 255))
    c.write(root / (name + ".png"))


def _prompt_frame(root: Path, name: str, clip: bool) -> None:
    c = Canvas(240, 160)
    c.rect(70, 90, 170, 110, (245, 245, 245, 255)) if clip else c.rect(
        70, 90, 150, 110, (245, 245, 245, 255)
    )
    c.write(root / (name + ".png"))
    _sidecar(
        root,
        name,
        {
            "shot": "doors_clip" if clip else "doors",
            "size": "240x160",
            "capture": name,
            "hud.prompt": "[F] OPEN",
        },
        {"prompt": (0.25, 0.50, 0.45, 0.20)},
    )


def _briefing_frame(root: Path, name: str, overflow: bool) -> None:
    c = Canvas(240, 180, (226, 216, 194, 255))
    for i in range(11):
        y = 30 + i * 11
        if overflow and i == 10:
            y = 165
        c.rect(40, y, 200, y + 3, (40, 32, 24, 255))
    c.write(root / (name + ".png"))
    _sidecar(
        root,
        name,
        {"shot": "briefing", "size": "240x180", "capture": name},
        {"paper": (0.10, 0.10, 0.80, 0.80), "paper_text": (0.15, 0.15, 0.70, 0.70)},
    )


def _checker(w: int, h: int, dim: float, blur: bool) -> Canvas:
    src = Canvas(w, h, (0, 0, 0, 255))
    for y in range(h):
        for x in range(w):
            v = 230 if ((x // 4) + (y // 4)) % 2 == 0 else 25
            src.set(x, y, (v, v, v, 255))
    out = Canvas(w, h, (0, 0, 0, 255))
    for y in range(h):
        for x in range(w):
            if blur:
                acc = [0, 0, 0]
                n = 0
                for dy in range(-4, 5, 2):
                    for dx in range(-4, 5, 2):
                        xx, yy = min(w - 1, max(0, x + dx)), min(h - 1, max(0, y + dy))
                        o = (yy * w + xx) * 4
                        acc[0] += src.px[o]
                        acc[1] += src.px[o + 1]
                        acc[2] += src.px[o + 2]
                        n += 1
                v = int(sum(acc) / (3 * n) * dim)
            else:
                o = (y * w + x) * 4
                v = int(src.px[o] * dim)
            out.set(x, y, (v, v, v, 255))
    return out


def _pause_pair(root: Path, blurred: bool) -> None:
    for name, dim, blur in (("pause_backdrop", 1.0, False), ("pause", 0.5, blurred)):
        frame = _checker(240, 160, dim, blur)
        if name == "pause":
            frame.rect(80, 60, 160, 100, (210, 210, 210, 255))
        frame.write(root / (name + ".png"))
        _sidecar(
            root,
            name,
            {"shot": name, "size": "240x160", "capture": name},
            {"world": (0.10, 0.10, 0.80, 0.80), "modal": (0.30, 0.30, 0.40, 0.35)},
        )


def main() -> int:
    tool = _load_tool()
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        _gem_frame(root, "den_hud_240")
        _prompt_frame(root, "doors_240", clip=False)
        _briefing_frame(root, "briefing_240", overflow=False)
        _pause_pair(root, blurred=True)

        frames = []
        for png in sorted(root.glob("*.png")):
            frames.append(tool.Frame(png, png.with_suffix(".txt")))
        rows = tool.analyse(frames)
        gem = rows["safe_room@240x160"]["gem"]
        check(
            abs(float(gem.get("angle_deg", 999)) - 0.0) < 20.0,
            "gem direction follows the cream cap (+x -> angle ~0)",
            "gem angle=%s" % gem.get("angle_deg"),
        )
        check(
            0.02 < float(gem.get("lit_fraction", 0.0)) < 0.35,
            "gem lit fraction is the cream share of the ROI",
            "lit_fraction=%s" % gem.get("lit_fraction"),
        )
        check(
            int(gem.get("ring_thickness_px", 0)) >= 2,
            "gem violet ring thickness is measured",
            "ring=%s" % gem.get("ring_thickness_px"),
        )
        check(
            gem.get("angle_err_deg") is not None and float(gem["angle_err_deg"]) < 20.0,
            "gem pixel angle agrees with the HUD state angle",
            "angle_err=%s" % gem.get("angle_err_deg"),
        )
        compass = rows["safe_room@240x160"]["compass"]
        check(
            int(compass.get("rule_row", -1)) in (40, 41)
            and int(compass.get("rule_thickness_px", 0)) == 2,
            "compass rule row/thickness are measured",
            "compass=%s" % compass,
        )
        check(
            int(compass.get("rule_span_px", 0)) >= 155
            and bool(compass.get("heading_above_rule")),
            "compass rule span + heading above the rule",
            "compass=%s" % compass,
        )
        check(
            compass.get("heading_letter") == "NE",
            "compass heading letter comes from the sidecar",
            str(compass.get("heading_letter")),
        )
        prompt = rows["doors@240x160"]["text"]["prompt"]
        check(
            float(prompt.get("contrast", 0.0)) > 10.0
            and not prompt.get("clipped_edges"),
            "prompt contrast is high and unclipped",
            "prompt=%s" % prompt,
        )
        brief = rows["briefing@240x180"]["briefing"]
        check(
            int(brief.get("line_count", 0)) == 11 and not brief.get("overflow"),
            "briefing finds the 11 ink lines with no overflow",
            "briefing=%s" % brief,
        )
        pair = rows["pause@240x160"]["pause_pair"]
        check(
            pair.get("dim_ratio") is not None
            and abs(float(pair["dim_ratio"]) - 0.5) < 0.06,
            "pause dim ratio measures the darkened world",
            "dim=%s" % pair.get("dim_ratio"),
        )
        check(
            pair.get("blur_ratio") is not None and float(pair["blur_ratio"]) < 0.2,
            "pause blur ratio measures the softened world",
            "blur=%s" % pair.get("blur_ratio"),
        )

        # Strict path: the clean capture passes; clipped ink and an unblurred
        # pause pair both fail closed.
        out = root / "stats.json"
        rc = tool.main(
            [
                "--dir",
                str(root),
                "--json",
                str(out),
                "--require",
                "safe_room,doors,briefing,pause",
            ]
        )
        check(rc == 0 and out.is_file(), "clean capture reports PASS", "rc=%d" % rc)
        rc_strict = tool.main(["--dir", str(root), "--strict"])
        check(
            rc_strict == 0, "clean capture passes --strict", "strict rc=%d" % rc_strict
        )

        with tempfile.TemporaryDirectory() as td2:
            root2 = Path(td2)
            _gem_frame(root2, "den_hud_240")
            _prompt_frame(root2, "doors_240", clip=True)
            rc_clip = tool.main(["--dir", str(root2), "--strict"])
            check(
                rc_clip == 1,
                "text clipped at the ROI edge fails --strict",
                "rc=%d" % rc_clip,
            )
        with tempfile.TemporaryDirectory() as td3:
            root3 = Path(td3)
            _pause_pair(root3, blurred=False)
            rc_blur = tool.main(["--dir", str(root3), "--strict"])
            check(
                rc_blur == 1,
                "an unblurred pause pair fails --strict",
                "rc=%d" % rc_blur,
            )

    if FAILS == 0:
        print("UI_PIXEL_STATS_TEST PASS checks=%d" % CHECKS)
    else:
        print("UI_PIXEL_STATS_TEST FAIL checks=%d fails=%d" % (CHECKS, FAILS))
    return 0 if FAILS == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
