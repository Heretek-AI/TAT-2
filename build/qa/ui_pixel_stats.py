#!/usr/bin/env python3
"""P5 UI pixel metrics (U-1/U-2): gem, compass, prompts, pause, briefing, text.

Reads the frames + `.txt` sidecars written by `build/qa/capture_p5_ui.gd` and
reports **measurements**, not verdicts. Every number is derived from the PNG
and cross-checked against the HUD state recorded in the sidecar (gem path /
slice / angle, prompt strings, compass letter), so a pixel change can be tied
to the state that produced it.

What is measured
----------------
* **gem**      inside `roi.gem`: cream lit-cap fraction, centroid, direction
               (canvas +x right / +y down), angle vs the sidecar's
               `hud.gem ... angle:` and the violet frame ring thickness.
* **compass**  inside `roi.compass`: the horizontal rule's row, thickness and
               span, plus the heading ink bbox above the rule.
* **prompt**   inside `roi.prompt`/`roi.prompt_secondary`: text ink count,
               contrast ratio (text p98 vs background median, 0..255 luma),
               and clipping at the ROI edge. Luma is Rec. 709
               (0.2126R + 0.7152G + 0.0722B) everywhere in this tool and in the
               gem producer — not ITU-R 601.
* **pause**    `pause` vs `pause_backdrop` (same pose, no modal): world luma
               ratio (dim) and edge-energy ratio (blur); modal ink bbox.
* **briefing** `roi.paper_text` line runs: line count, first/last ink row,
               paper bottom margin, overflow.
* **text**     every named text ROI: ink bbox, clipped edges, contrast.

`--strict` turns the documented thresholds into a non-zero exit; the default
run only reports numbers (a GPU frame is never judged by a guess). The tool is
stdlib-only: it reuses `tools/png_rgba.py`, the same decoder the gem producer
uses, so there is a single pixel convention in the lane.

Usage::

    build/qa/ui_pixel_stats.py --dir /tmp/opencode/p5-ui-captures/<run>
    build/qa/ui_pixel_stats.py --dir ... --json p5_ui_stats.json --strict
    build/qa/ui_pixel_stats.py --dir ... --size 1080 --shots gem
    build/qa/ui_pixel_stats.py --dir ... --require startscreen,pause,pause_backdrop,briefing
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from png_rgba import PngError, read_rgba, read_size  # noqa: E402

SAMPLE = 2  # every 2nd pixel, the capture sidecar convention
GEM_SHOTS = {"safe_room", "crank", "pause_backdrop", "pause"}
TEXT_ROIS = (
    "prompt",
    "prompt_secondary",
    "legend",
    "key_row",
    "footer",
    "tabs",
    "modal",
    "cards",
)
STRICT_PROMPT_CONTRAST = 4.5
STRICT_PAUSE_BLUR_RATIO = 0.60
STRICT_PAUSE_DIM_RATIO = 0.90


def luma(r: int, g: int, b: int) -> float:
    """Rec. 709 relative luma on 0..255 channels (not ITU-R 601)."""
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _median(values: list[float]) -> float:
    if not values:
        return 0.0
    values = sorted(values)
    return values[len(values) // 2]


def _pct(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    values = sorted(values)
    i = int(round(p * (len(values) - 1)))
    return values[max(0, min(len(values) - 1, i))]


def _decode_rgba(path: Path, width: int, height: int) -> bytes:
    """ffmpeg fast path (a 1920x1080 PNG in ~50 ms); stdlib fallback.

    The repo already depends on ffmpeg for `make convert_videos`, so it is the
    fast path on every integration host; `tools/png_rgba.py` keeps the tool
    runnable without it. Both paths return the same RGBA8 bytes.
    """
    if shutil.which("ffmpeg"):
        proc = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
            capture_output=True,
            check=False,
        )
        if proc.returncode == 0 and len(proc.stdout) == width * height * 4:
            return proc.stdout
    return read_rgba(path)[2]


class Frame:
    def __init__(self, png: Path, side: Path) -> None:
        self.png = png
        self.meta: dict[str, object] = {}
        self.rois: dict[str, tuple[float, float, float, float]] = {}
        for line in side.read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            if key.startswith("roi."):
                head = value.split(" mean=")[0]
                parts = head.split(",")
                if len(parts) == 4:
                    try:
                        self.rois[key[4:]] = tuple(float(x) for x in parts)  # type: ignore[assignment]
                    except ValueError:
                        pass
            else:
                self.meta[key] = value
        self._w, self._h = read_size(png)
        self._rgba = _decode_rgba(png, self._w, self._h)

    @property
    def shot(self) -> str:
        return str(self.meta.get("shot", self.png.name.split("_")[0]))

    @property
    def size(self) -> tuple[int, int]:
        return self._w, self._h

    def pixel(self, x: int, y: int) -> tuple[int, int, int, int]:
        o = (y * self._w + x) * 4
        return self._rgba[o], self._rgba[o + 1], self._rgba[o + 2], self._rgba[o + 3]

    def rect(self, name: str, default: tuple[float, float, float, float] | None = None):
        r = self.rois.get(name)
        if r is None:
            if default is None:
                return None
            r = default
        x0 = max(0, min(self._w - 1, int(r[0] * self._w)))
        y0 = max(0, min(self._h - 1, int(r[1] * self._h)))
        x1 = max(x0 + 1, min(self._w, int((r[0] + r[2]) * self._w)))
        y1 = max(y0 + 1, min(self._h, int((r[1] + r[3]) * self._h)))
        return x0, y0, x1, y1


def _gem(frame: Frame) -> dict:
    box = frame.rect("gem")
    if box is None:
        return {"present": False}
    x0, y0, x1, y1 = box
    cream = 0
    violet = 0
    total = 0
    cx = cy = 0.0
    cream_lumas: list[float] = []
    for y in range(y0, y1, SAMPLE):
        for x in range(x0, x1, SAMPLE):
            r, g, b, a = frame.pixel(x, y)
            if a < 16:
                continue
            total += 1
            L = luma(r, g, b)
            # Cream face: the authored lit cap is (217,200,161)..(237,222,195);
            # keep a wide margin so a dim exposure still counts as lit.
            if r > 120 and g > 100 and b > 60 and r >= b:
                cream += 1
                cream_lumas.append(L)
                cx += x
                cy += y
            # Violet: the frame tint (21,28,175) and the concealed royal blue.
            elif b > 60 and b > r * 1.35 and b > g * 1.15:
                violet += 1
    if total == 0:
        return {"present": True, "pixels": 0}
    direction = None
    angle = None
    if cream:
        cx /= cream
        cy /= cream
        mx = (x0 + x1) * 0.5
        my = (y0 + y1) * 0.5
        hw = max(1.0, (x1 - x0) * 0.5)
        hh = max(1.0, (y1 - y0) * 0.5)
        dx = max(-1.0, min(1.0, (cx - mx) / hw))
        dy = max(-1.0, min(1.0, (cy - my) / hh))
        n = math.hypot(dx, dy)
        if n > 1e-6:
            dx /= n
            dy /= n
        direction = [round(dx, 4), round(dy, 4)]
        angle = round(math.degrees(math.atan2(dy, dx)), 2)
    # Frame ring thickness on the horizontal centre row: median violet run.
    row = (y0 + y1) // 2
    runs: list[int] = []
    run = 0
    for x in range(x0, x1):
        r, g, b, a = frame.pixel(x, row)
        is_violet = a >= 16 and b > 60 and b > r * 1.35 and b > g * 1.15
        if is_violet:
            run += 1
        elif run:
            runs.append(run)
            run = 0
    if run:
        runs.append(run)
    side_angle = None
    state: dict[str, float] = {}
    for part in str(frame.meta.get("hud.gem", "")).replace(",", " ").split():
        if ":" not in part:
            continue
        key, value = part.split(":", 1)
        try:
            state[key] = float(value)
        except ValueError:
            state[key] = value  # type: ignore[assignment]
    if "angle" in state and isinstance(state["angle"], float):
        side_angle = state["angle"]
    angle_err = None
    if angle is not None and side_angle is not None:
        angle_err = round(abs((angle - side_angle + 180.0) % 360.0 - 180.0), 2)
    return {
        "present": True,
        "pixels": total,
        "lit_fraction": round(cream / float(total), 4),
        "cream_px": cream,
        "violet_px": violet,
        "ring_thickness_px": int(_median([float(v) for v in runs])) if runs else 0,
        "centroid": [round(cx, 1), round(cy, 1)] if cream else None,
        "direction": direction,
        "angle_deg": angle,
        "state_angle_deg": side_angle,
        "angle_err_deg": angle_err,
        "state_amount": state.get("amount"),
        "state_lit_area": state.get("lit_area"),
        "state_slice": state.get("slice"),
        "lit_rgb_p95": int(_pct(cream_lumas, 0.95)),
    }


def _compass(frame: Frame) -> dict:
    box = frame.rect("compass")
    if box is None:
        return {"present": False}
    x0, y0, x1, y1 = box
    rows: list[tuple[int, int]] = []
    for y in range(y0, y1):
        count = 0
        for x in range(x0, x1):
            r, g, b, a = frame.pixel(x, y)
            if a >= 16 and luma(r, g, b) > 120:
                count += 1
        rows.append((y, count))
    peak = max((c for _, c in rows), default=0)
    rule_rows = [y for y, c in rows if peak > 0 and c >= peak * 0.5]
    result: dict = {
        "present": True,
        "rule_rows": rule_rows[:1] + rule_rows[-1:],
        "rule_peak_px": peak,
    }
    if rule_rows:
        rule_y = rule_rows[len(rule_rows) // 2]
        result["rule_row"] = rule_y
        result["rule_thickness_px"] = len(rule_rows)
        # Span of the rule on the rule row.
        first = last = None
        for x in range(x0, x1):
            r, g, b, a = frame.pixel(x, rule_y)
            if a >= 16 and luma(r, g, b) > 120:
                if first is None:
                    first = x
                last = x
        result["rule_span_px"] = 0 if first is None else (last - first + 1)
        # Heading ink: bright pixels above the rule, merged into a bbox.
        hx0 = hy0 = 10**9
        hx1 = hy1 = -1
        ink = 0
        for y in range(y0, max(y0, rule_rows[0] - 1)):
            for x in range(x0, x1):
                r, g, b, a = frame.pixel(x, y)
                if a >= 16 and luma(r, g, b) > 120:
                    ink += 1
                    hx0 = min(hx0, x)
                    hy0 = min(hy0, y)
                    hx1 = max(hx1, x)
                    hy1 = max(hy1, y)
        result["heading_ink_px"] = ink
        result["heading_bbox"] = [hx0, hy0, hx1, hy1] if ink else None
        result["heading_above_rule"] = bool(ink and hy1 < rule_rows[0])
        result["heading_letter"] = str(frame.meta.get("hud.compass", ""))
    return result


def _ink_stats(frame: Frame, box, threshold: float = 0.45) -> dict:
    x0, y0, x1, y1 = box
    values: list[float] = []
    ix0 = iy0 = 10**9
    ix1 = iy1 = -1
    ink = 0
    for y in range(y0, y1, SAMPLE):
        for x in range(x0, x1, SAMPLE):
            r, g, b, a = frame.pixel(x, y)
            if a < 16:
                continue
            L = luma(r, g, b) / 255.0
            values.append(L)
            if L >= threshold:
                ink += 1
                ix0 = min(ix0, x)
                iy0 = min(iy0, y)
                ix1 = max(ix1, x)
                iy1 = max(iy1, y)
    if not values:
        return {"present": True, "px": 0}
    bg = _median(values)
    text = _pct(values, 0.98)
    contrast = (text + 0.05) / (bg + 0.05)
    clipped: list[str] = []
    # A panel/background fill is not "clipped text": only flag a bbox that is
    # materially smaller than the ROI (a text run), never a solid block.
    bbox_area = (ix1 - ix0 + 1) * (iy1 - iy0 + 1) if ink else 0
    roi_area = max(1, (x1 - x0) * (y1 - y0))
    solid = bool(ink and bbox_area >= roi_area * 0.90)
    if ink and not solid:
        pad = 2
        if ix0 <= x0 + pad:
            clipped.append("left")
        if iy0 <= y0 + pad:
            clipped.append("top")
        if ix1 >= x1 - 1 - pad:
            clipped.append("right")
        if iy1 >= y1 - 1 - pad:
            clipped.append("bottom")
    return {
        "present": True,
        "px": len(values),
        "ink_px": ink,
        "ink_bbox": [ix0, iy0, ix1, iy1] if ink else None,
        "bg_luma": round(bg, 4),
        "text_luma_p98": round(text, 4),
        "contrast": round(contrast, 2),
        "clipped_edges": clipped,
        "solid": solid,
    }


def _briefing(frame: Frame) -> dict:
    box = frame.rect("paper_text")
    paper = frame.rect("paper")
    if box is None:
        return {"present": False}
    x0, y0, x1, y1 = box
    # Luma is Rec. 709 (0.2126R + 0.7152G + 0.0722B) for the whole tool.
    # The authored letter is dark ink on parchment, so the line detector keys
    # on deviation from the *page* background, not on a bright threshold.
    bg_values: list[float] = []
    for y in range(y0, y1, SAMPLE):
        for x in range(x0, x1, SAMPLE):
            r, g, b, a = frame.pixel(x, y)
            if a >= 16:
                bg_values.append(luma(r, g, b) / 255.0)
    bg = _median(bg_values)
    row_counts: list[tuple[int, int]] = []
    for y in range(y0, y1):
        count = 0
        for x in range(x0, x1, SAMPLE):
            r, g, b, a = frame.pixel(x, y)
            if a >= 16 and abs(luma(r, g, b) / 255.0 - bg) > 0.18:
                count += 1
        row_counts.append((y, count))
    lines: list[tuple[int, int]] = []
    start = None
    for y, count in row_counts:
        if count >= 3 and start is None:
            start = y
        elif count < 3 and start is not None:
            lines.append((start, y - 1))
            start = None
    if start is not None:
        lines.append((start, row_counts[-1][0]))
    paper_bottom = paper[3] if paper is not None else y1
    last = lines[-1][1] if lines else y0
    return {
        "present": True,
        "line_count": len(lines),
        "line_rows": [list(v) for v in lines],
        "first_ink_y": lines[0][0] if lines else None,
        "last_ink_y": last if lines else None,
        "paper_bottom_px": paper_bottom,
        "bottom_margin_px": paper_bottom - last,
        "overflow": bool(lines and last > paper_bottom - 4),
    }


def _edge_energy(frame: Frame, box) -> float:
    x0, y0, x1, y1 = box
    total = 0.0
    n = 0
    for y in range(y0, y1 - SAMPLE, SAMPLE):
        for x in range(x0, x1 - SAMPLE, SAMPLE):
            r0, g0, b0, _ = frame.pixel(x, y)
            r1, g1, b1, _ = frame.pixel(x + SAMPLE, y)
            r2, g2, b2, _ = frame.pixel(x, y + SAMPLE)
            l0 = luma(r0, g0, b0)
            total += abs(l0 - luma(r1, g1, b1)) + abs(l0 - luma(r2, g2, b2))
            n += 1
    return total / max(1.0, float(n))


def _pause_pair(backdrop: Frame, paused: Frame) -> dict:
    box = paused.rect("world")
    if box is None:
        return {"present": False}
    # The modal sits over the world; comparing its pixels against the
    # backdrop would report dimming that is really the menu's own panel.
    modal = paused.rect("modal")
    b_lumas: list[float] = []
    p_lumas: list[float] = []
    x0, y0, x1, y1 = box
    for y in range(y0, y1, SAMPLE):
        for x in range(x0, x1, SAMPLE):
            if modal is not None and modal[0] <= x < modal[2] and modal[1] <= y < modal[3]:
                continue
            rb, gb, bb, _ = backdrop.pixel(x, y)
            rp, gp, bp, _ = paused.pixel(x, y)
            b_lumas.append(luma(rb, gb, bb))
            p_lumas.append(luma(rp, gp, bp))
    b_mean = sum(b_lumas) / max(1, len(b_lumas))
    p_mean = sum(p_lumas) / max(1, len(p_lumas))
    b_edge = _edge_energy(backdrop, box)
    p_edge = _edge_energy(paused, box)
    # Dimming scales edge amplitude with luma, so the blur term must be
    # *relative* contrast: a dim-only overlay keeps ~1.0 and is not a blur.
    b_rel = b_edge / max(1.0, b_mean)
    p_rel = p_edge / max(1.0, p_mean)
    return {
        "present": True,
        "backdrop_mean_luma": round(b_mean, 2),
        "paused_mean_luma": round(p_mean, 2),
        "dim_ratio": round(p_mean / b_mean, 4) if b_mean else None,
        "backdrop_edge_energy": round(b_edge, 3),
        "paused_edge_energy": round(p_edge, 3),
        "blur_ratio": round(p_rel / b_rel, 4) if b_rel else None,
        "modal_ink": _ink_stats(paused, modal, 0.35) if modal is not None else None,
    }


def analyse(frames: list[Frame]) -> dict:
    by_shot: dict[str, dict[tuple[int, int], Frame]] = {}
    for f in frames:
        by_shot.setdefault(f.shot, {})[f.size] = f
    out: dict[str, dict] = {}
    for shot in sorted(by_shot):
        for size, frame in sorted(by_shot[shot].items()):
            key = "%s@%dx%d" % (shot, size[0], size[1])
            row: dict = {
                "png": str(frame.png),
                "shot": shot,
                "size": list(size),
                "capture": frame.meta.get("capture", ""),
                "tag": frame.meta.get("tag", ""),
                "hud.gem": frame.meta.get("hud.gem", ""),
                "hud.prompt": frame.meta.get("hud.prompt", ""),
                "staged": frame.meta.get("staged", ""),
            }
            if shot in GEM_SHOTS:
                row["gem"] = _gem(frame)
            if "compass" in frame.rois:
                row["compass"] = _compass(frame)
            if shot == "briefing":
                row["briefing"] = _briefing(frame)
            text: dict[str, dict] = {}
            for roi in TEXT_ROIS:
                if roi in frame.rois:
                    text[roi] = _ink_stats(frame, frame.rect(roi))
            if text:
                row["text"] = text
            out[key] = row
    # Pause pair: dim/blur need the same pose at the same size.
    for size, paused in by_shot.get("pause", {}).items():
        backdrop = by_shot.get("pause_backdrop", {}).get(size)
        if backdrop is not None:
            out["pause@%dx%d" % size]["pause_pair"] = _pause_pair(backdrop, paused)
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", required=True)
    ap.add_argument("--json", default="")
    ap.add_argument("--size", default="", help="720 | 1080 (default all)")
    ap.add_argument("--shots", default="", help="comma list of shot names")
    ap.add_argument("--require", default="", help="comma list that must be present")
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args(argv)

    root = Path(args.dir)
    if not root.is_dir():
        print("UI_PIXEL_STATS FAIL missing_dir=%s" % root)
        return 2
    want_shots = {s for s in args.shots.split(",") if s}
    want_size = args.size
    frames: list[Frame] = []
    errors: list[str] = []
    for png in sorted(root.glob("*.png")):
        side = png.with_suffix(".txt")
        if not side.is_file():
            errors.append("missing sidecar: %s" % png.name)
            continue
        try:
            frame = Frame(png, side)
        except (PngError, OSError) as exc:
            errors.append("%s: %s" % (png.name, exc))
            continue
        if want_shots and frame.shot not in want_shots:
            continue
        if want_size and str(frame.size[1]) != want_size:
            continue
        frames.append(frame)
    if not frames:
        print("UI_PIXEL_STATS FAIL no_frames dir=%s" % root)
        return 2
    result = {
        "schema": "tat2.ui_pixel_stats/1",
        "dir": str(root),
        "frames": len(frames),
        "rows": analyse(frames),
        "errors": errors,
    }
    if args.json:
        Path(args.json).write_text(
            json.dumps(result, indent=1, sort_keys=True) + "\n", encoding="utf-8"
        )

    fails: list[str] = []
    print("UI_PIXEL_STATS dir=%s frames=%d" % (root, len(frames)))
    for key in sorted(result["rows"]):
        row = result["rows"][key]
        bits = [key]
        if "gem" in row and row["gem"].get("present"):
            g = row["gem"]
            bits.append(
                "gem lit=%.3f ang=%s dir=%s ring=%dpx"
                % (
                    float(g.get("lit_fraction", 0.0)),
                    str(g.get("angle_deg")),
                    str(g.get("direction")),
                    int(g.get("ring_thickness_px", 0)),
                )
            )
            if g.get("angle_err_deg") is not None and float(g["angle_err_deg"]) > 45.0:
                bits.append("GEM_ANGLE_ERR=%.1f" % float(g["angle_err_deg"]))
        if "compass" in row and row["compass"].get("present"):
            c = row["compass"]
            bits.append(
                "compass rule_row=%s thick=%s span=%s heading=%s"
                % (
                    str(c.get("rule_row")),
                    str(c.get("rule_thickness_px")),
                    str(c.get("rule_span_px")),
                    str(c.get("heading_letter")),
                )
            )
        if "briefing" in row and row["briefing"].get("present"):
            b = row["briefing"]
            bits.append(
                "briefing lines=%s last_y=%s margin=%s overflow=%s"
                % (
                    str(b.get("line_count")),
                    str(b.get("last_ink_y")),
                    str(b.get("bottom_margin_px")),
                    str(b.get("overflow")),
                )
            )
            if b.get("overflow"):
                fails.append("%s briefing overflow" % key)
        for roi, st in (row.get("text") or {}).items():
            if not st.get("present"):
                continue
            bits.append(
                "%s contrast=%.2f ink=%d clip=%s"
                % (
                    roi,
                    float(st.get("contrast", 0.0)),
                    int(st.get("ink_px", 0)),
                    ",".join(st.get("clipped_edges") or []) or "-",
                )
            )
            if (
                args.strict
                and roi == "prompt"
                and float(st.get("contrast", 0.0)) < STRICT_PROMPT_CONTRAST
            ):
                fails.append(
                    "%s prompt contrast %.2f < %.1f"
                    % (key, float(st.get("contrast", 0.0)), STRICT_PROMPT_CONTRAST)
                )
            if args.strict and st.get("clipped_edges"):
                fails.append(
                    "%s %s text clipped at %s"
                    % (key, roi, ",".join(st["clipped_edges"]))
                )
        if "pause_pair" in row and row["pause_pair"].get("present"):
            p = row["pause_pair"]
            bits.append(
                "pause dim=%s blur=%s"
                % (str(p.get("dim_ratio")), str(p.get("blur_ratio")))
            )
            if (
                args.strict
                and p.get("dim_ratio") is not None
                and float(p["dim_ratio"]) > STRICT_PAUSE_DIM_RATIO
            ):
                fails.append(
                    "%s dim_ratio %.2f > %.2f"
                    % (key, float(p["dim_ratio"]), STRICT_PAUSE_DIM_RATIO)
                )
            if (
                args.strict
                and p.get("blur_ratio") is not None
                and float(p["blur_ratio"]) > STRICT_PAUSE_BLUR_RATIO
            ):
                fails.append(
                    "%s blur_ratio %.2f > %.2f"
                    % (key, float(p["blur_ratio"]), STRICT_PAUSE_BLUR_RATIO)
                )
        print("  " + "  ".join(bits))
    for note in errors:
        print("  ERROR " + note)
    if args.strict:
        # A paused frame without its same-size backdrop silently skips the
        # dim/blur check; fail closed instead of reporting a clean pause.
        for key, row in result["rows"].items():
            if row["shot"] != "pause":
                continue
            size = row["size"]
            if not any(r["shot"] == "pause_backdrop" and r["size"] == size for r in result["rows"].values()):
                fails.append("%s pause has no pause_backdrop at %dx%d" % (key, size[0], size[1]))
    required = [s for s in args.require.split(",") if s]
    missing = [
        s for s in required if not any(r["shot"] == s for r in result["rows"].values())
    ]
    if missing:
        fails.append("missing required shots: %s" % ",".join(missing))
    if fails:
        for f in fails:
            print("UI_PIXEL_STATS FAIL " + f)
        print(
            "UI_PIXEL_STATS SUMMARY rows=%d fails=%d"
            % (len(result["rows"]), len(fails))
        )
        return 1
    print("UI_PIXEL_STATS PASS rows=%d" % len(result["rows"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
