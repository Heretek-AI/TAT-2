#!/usr/bin/env python3
"""Deterministic annotation renderer for the M2 callout spec.

Usage (paths are relative to this script location):
    /usr/bin/python3 render_annotations.py [--only KF07] [--check] [--emit-legends]

Reads callout_spec.json + clean/, writes annotated/<same filename>.
Byte-identical output for identical input (no timestamps, no randomness).
"""

from __future__ import annotations

import argparse
import io
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SPEC_PATH = ROOT / "callout_spec.json"
CLEAN_DIR = ROOT / "clean"
OUT_DIR = ROOT / "annotated"
LEGENDS_PATH = ROOT / "CALLOUT_LEGENDS.md"

TEXT_ON = {"Visual": (0, 0, 0), "HUD/UI": (0, 0, 0), "Gameplay/Audio": (255, 255, 255)}


def load_spec():
    return json.loads(SPEC_PATH.read_text(encoding="utf-8"))


def hex_rgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


class Ctx:
    def __init__(self, spec):
        geo = spec["geometry"]
        self.safe = tuple(geo["safe_bounds"])
        fonts = spec["fonts"]
        self.badge_font = ImageFont.truetype(
            fonts["badge_numeral"], geo["badge_font_size_px"]
        )
        self.label_font = ImageFont.truetype(
            fonts["label_text"], geo["label_font_size_px"]
        )
        self.legend_font = ImageFont.truetype(
            fonts["fallback_regular"], geo["legend_font_size_px"]
        )
        self.badge_r = geo["badge_diameter_px"] // 2
        self.pill_h = geo["pill_height_px"]
        self.pill_pad = geo["pill_pad_x_px"]
        self.gap = geo["badge_pill_gap_px"]
        self.palette = {k: hex_rgb(v) for k, v in spec["palette"].items()}


def pill_rect(ctx, anchor, placement, label):
    ax, ay = anchor
    bb = ctx.label_font.getbbox(label)
    tw = bb[2] - bb[0]
    pw = tw + 2 * ctx.pill_pad
    ph = ctx.pill_h
    top = ay - ph // 2
    if placement == "pill_right":
        x0 = ax + ctx.badge_r + ctx.gap
        return [x0, top, x0 + pw, top + ph]
    x1 = ax - ctx.badge_r - ctx.gap
    return [x1 - pw, top, x1, top + ph]


def badge_rect(ctx, anchor):
    ax, ay = anchor
    r = ctx.badge_r
    return [ax - r, ay - r, ax + r, ay + r]


def rects_overlap(a, b):
    return not (a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1])


def rect_in(bounds_outer, r):
    return (
        bounds_outer[0] <= r[0]
        and bounds_outer[1] <= r[1]
        and r[2] <= bounds_outer[2]
        and r[3] <= bounds_outer[3]
    )


def draw_dashed_rect(d, box, fill, width=2, dash=9, gap=6):
    x0, y0, x1, y1 = [int(v) for v in box]
    for x in range(x0, x1, dash + gap):
        d.line([(x, y0), (min(x + dash, x1), y0)], fill=fill, width=width)
        d.line([(x, y1), (min(x + dash, x1), y1)], fill=fill, width=width)
    for y in range(y0, y1, dash + gap):
        d.line([(x0, y), (x0, min(y + dash, y1))], fill=fill, width=width)
        d.line([(x1, y), (x1, min(y + dash, y1))], fill=fill, width=width)


def draw_leader(d, anchor, target, color):
    ax, ay = anchor
    tx, ty = target
    dx, dy = tx - ax, ty - ay
    dist = math.hypot(dx, dy) or 1.0
    sx = ax + dx / dist * 14.0
    sy = ay + dy / dist * 14.0
    d.line([(sx, sy), (tx, ty)], fill=(0, 0, 0), width=5)
    d.line([(sx, sy), (tx, ty)], fill=color, width=2)


def layout_frame(ctx, kf, frame):
    items = []
    for c in frame["callouts"]:
        color = ctx.palette[c["category"]]
        items.append(
            {
                "c": c,
                "color": color,
                "badge": badge_rect(ctx, c["anchor"]),
                "pill": pill_rect(ctx, c["anchor"], c["placement"], c["label"]),
            }
        )
    return items


def legend_text_for(kf, frame):
    return (
        kf
        + "  "
        + frame["timestamp"]
        + "  "
        + frame["segment"]
        + "  Amber=Visual Cyan=UI Magenta=GameplayAudio"
    )


def legend_rect_for(ctx, d_tmp, text, corner):
    bb = ctx.legend_font.getbbox(text)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    w, h = tw + 20, th + 14
    m = 20
    if corner == "BR":
        return [1920 - m - w, 1080 - m - h, 1920 - m, 1080 - m]
    if corner == "BL":
        return [m, 1080 - m - h, m + w, 1080 - m]
    if corner == "TR":
        return [1920 - m - w, m, 1920 - m, m + h]
    return [m, m, m + w, m + h]


def pick_legend(ctx, items, exclusions, text):
    solids = [it["badge"] for it in items] + [it["pill"] for it in items]
    for corner in ("BR", "BL", "TR", "TL"):
        r = legend_rect_for(ctx, None, text, corner)
        if not rect_in(ctx.safe, r):
            continue
        if any(rects_overlap(r, e) for e in exclusions):
            continue
        if any(rects_overlap(r, s) for s in solids):
            continue
        return corner, r
    return None, None


def check_frame(ctx, kf, frame):
    problems = []
    items = layout_frame(ctx, kf, frame)
    excl = frame["hud_exclusions"]
    solids = []
    for it in items:
        solids.append((it["c"]["id"], "badge", it["badge"]))
        solids.append((it["c"]["id"], "pill", it["pill"]))
    for i in range(len(solids)):
        for j in range(i + 1, len(solids)):
            if rects_overlap(solids[i][2], solids[j][2]):
                problems.append(
                    "overlap badge/pill #"
                    + str(solids[i][0])
                    + solids[i][1]
                    + " vs #"
                    + str(solids[j][0])
                    + solids[j][1]
                )
    for cid, kind, r in solids:
        if not rect_in(ctx.safe, r):
            problems.append("#" + str(cid) + " " + kind + " outside safe_bounds")
        for e in excl:
            if rects_overlap(r, e):
                problems.append(
                    "#" + str(cid) + " " + kind + " overlaps hud_exclusion " + repr(e)
                )
    corner, lrect = pick_legend(ctx, items, excl, legend_text_for(kf, frame))
    if lrect is None:  # omission allowed: strip left out rather than cover HUD
        pass  # omission allowed per spec
    return problems, items, corner, lrect


def render_frame(ctx, kf, frame):
    problems, items, corner, lrect = check_frame(ctx, kf, frame)
    img = Image.open(CLEAN_DIR / frame["filename"]).convert("RGB")
    if img.size != (1920, 1080):
        raise SystemExit("FATAL: " + frame["filename"] + " size " + repr(img.size))
    base = img.convert("RGBA")
    ov = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for it in items:
        c, color = it["c"], it["color"]
        tx, ty = c["target"]
        if c["bbox"] is not None:
            bx = [int(v) for v in c["bbox"]]
            d.rectangle(bx, outline=(0, 0, 0, 255), width=4)
            draw_dashed_rect(d, bx, color + (255,), width=2)
    for it in items:
        c, color = it["c"], it["color"]
        draw_leader(d, tuple(c["anchor"]), tuple(c["target"]), color)
        tx, ty = c["target"]
        d.ellipse([tx - 5, ty - 5, tx + 5, ty + 5], fill=(0, 0, 0, 255))
        d.ellipse([tx - 3, ty - 3, tx + 3, ty + 3], fill=color + (255,))
    for it in items:
        c, color = it["c"], it["color"]
        ax, ay = c["anchor"]
        r = ctx.badge_r
        d.ellipse([ax - r - 2, ay - r - 2, ax + r + 2, ay + r + 2], fill=(0, 0, 0, 255))
        d.ellipse([ax - r, ay - r, ax + r, ay + r], fill=color + (255,))
        d.text(
            (ax, ay),
            str(c["id"]),
            font=ctx.badge_font,
            anchor="mm",
            fill=TEXT_ON[c["category"]] + (255,),
        )
        pr = [int(v) for v in it["pill"]]
        d.rounded_rectangle(pr, radius=16, fill=(0, 0, 0, 179))
        d.text(
            ((pr[0] + pr[2]) // 2, (pr[1] + pr[3]) // 2),
            c["label"],
            font=ctx.label_font,
            anchor="mm",
            fill=(255, 255, 255, 255),
        )
    if lrect is not None:
        lr = [int(v) for v in lrect]
        d.rounded_rectangle(lr, radius=8, fill=(0, 0, 0, 179))
        d.text(
            ((lr[0] + lr[2]) // 2, (lr[1] + lr[3]) // 2),
            legend_text_for(kf, frame),
            font=ctx.legend_font,
            anchor="mm",
            fill=(255, 255, 255, 255),
        )
    out = Image.alpha_composite(base, ov).convert("RGB")
    return out, problems, corner


def encode_jpeg(img):
    for quality, sampling in ((90, 0), (90, 2), (88, 2)):
        buf = io.BytesIO()
        img.save(
            buf, format="JPEG", quality=quality, optimize=True, subsampling=sampling
        )
        data = buf.getvalue()
        if len(data) < 750 * 1024:
            return data, quality, sampling
    return data, quality, sampling


TAXONOMY = [
    ("V1", "Visual", "Lighting: key/fill, practicals, neon, volumetrics, shadows"),
    ("V2", "Visual", "Sky, atmosphere, fog, weather (rain, wetness, puddles)"),
    ("V3", "Visual", "Materials and shaders: albedo, roughness, glass, emissive"),
    ("V4", "Visual", "Geometry and level dressing: architecture, props, layout"),
    ("V5", "Visual", "Characters and animation: 1P hands/tools, NPCs, takedowns"),
    ("V6", "Visual", "VFX and particles: smoke, sparks, barriers, beams"),
    ("V7", "Visual", "Camera and post: FOV, framing, motion, exposure, grade"),
    ("UI1", "HUD/UI", "Front-end menus (Startscreen, Pause, Settings)"),
    ("UI2", "HUD/UI", "In-world interaction prompts"),
    ("UI3", "HUD/UI", "Persistent HUD: player card, compass, tools, health, light gem"),
    ("UI4", "HUD/UI", "Full-screen panels: Wardrobe, Journal, Market, Map, Briefing"),
    (
        "UI5",
        "HUD/UI",
        "Alerts and feedback: guard-alert pips, player-noise arcs, status icons, alarms, countdowns",
    ),
    ("G1", "Gameplay", "Interactables and stations (den, doors, loot, scope)"),
    ("G2", "Gameplay", "Traversal and movement (zipwire, climb, stairs)"),
    ("G3", "Gameplay", "Tools and abilities (smoke bomb, zipwire gun)"),
    ("G4", "Gameplay", "AI and guards: patrol, perception, alert, takedowns"),
    ("G5", "Gameplay", "Hazards and mission flow: beams, barriers, traps"),
    ("AU1", "Audio", "Ambience and room tone, plus explicit BGM absence"),
    ("AU2", "Audio", "Music (gramophone jazz around 00:44-00:50)"),
    ("AU3", "Audio", "Footsteps and foley (surface-specific)"),
    ("AU4", "Audio", "UI audio (clicks, hovers, countdown ticks, confirms)"),
    ("AU5", "Audio", "Gameplay SFX (tools, smoke, diamond, alarm, horn)"),
    ("AU6", "Audio", "Voice: VO, barks, dialogue (verbatim quotes)"),
]


def slug_of(filename):
    parts = filename.split("_", 2)
    if len(parts) == 3:
        return parts[2].rsplit(".", 1)[0]
    return filename.rsplit(".", 1)[0]


def emit_legends(spec):
    lines = []
    lines.append("# Callout Legends")
    lines.append("")
    lines.append("Numbered legend tables for every annotated keyframe.")
    lines.append("Badge IDs [1]..[N] match the badges rendered on")
    lines.append("annotated/<same filename as clean/> exactly.")
    lines.append("")
    lines.append("Badge colour key: Amber #FFB300 = Visual (V*);")
    lines.append("Cyan #00E5FF = HUD/UI (UI*); Magenta #FF4081 = Gameplay/Audio.")
    lines.append("")
    lines.append("## HUD semantics glossary (user-confirmed)")
    lines.append("")
    lines.append(
        "- **Light Gem** (bottom-centre ornate gem, UI3): shows how much light is on the player **and from which direction**."
    )
    lines.append(
        "  The warm cream/white lit sector's size = light amount; its position within the gem = the direction the light comes from."
    )
    lines.append("  Bright = exposed, dark = concealed. It is NOT a detection meter.")
    lines.append(
        "- **Red arcs** flanking the gem (UI5): show how much sound the player is making (player noise level)."
    )
    lines.append(
        "  Large/bright = loud; absent = quiet. They are NOT enemy threat/detection arcs and do not track guard proximity."
    )
    lines.append(
        "- **Guard-alert direction pip** (KF17 only): three-dash crimson indicator away from the gem showing the direction of an alerted guard."
    )
    lines.append(
        "  A guard-perception alert element, different from the player-noise arcs."
    )
    lines.append("")
    lines.append("Regenerate images and this file with:")
    lines.append(
        "`/usr/bin/python3 docs/reference/clip_1795033698901/tools/render_annotations.py`"
    )
    lines.append(
        "`/usr/bin/python3 docs/reference/clip_1795033698901/tools/render_annotations.py --emit-legends`"
    )
    lines.append("")
    lines.append("## Code taxonomy")
    lines.append("")
    lines.append("| Code | Category | Meaning |")
    lines.append("|---|---|---|")
    for code, cat, meaning in TAXONOMY:
        lines.append("| " + code + " | " + cat + " | " + meaning + " |")
    lines.append("")
    for kf in sorted(spec["keyframes"]):
        frame = spec["keyframes"][kf]
        lines.append("### " + kf + " - " + slug_of(frame["filename"]))
        lines.append("(" + frame["timestamp"] + ", " + frame["segment"] + ")")
        lines.append("")
        lines.append("![clean](clean/" + frame["filename"] + ")")
        lines.append("")
        lines.append("![annotated](annotated/" + frame["filename"] + ")")
        lines.append("")
        lines.append(
            "| # | Category | Code | Label | Target (x, y) | Observed UE5 Detail | TAT-2 Ref |"
        )
        lines.append("|---|---|---|---|---|---|---|")
        for c in frame["callouts"]:
            tx, ty = c["target"]
            lines.append(
                "| "
                + str(c["id"])
                + " | "
                + c["category"]
                + " | "
                + c["code"]
                + " | "
                + c["label"]
                + " | ("
                + str(tx)
                + ", "
                + str(ty)
                + ") | "
                + c["observed_ue5_detail"]
                + " | -- |"
            )
        lines.append("")
    LEGENDS_PATH.write_text(chr(10).join(lines), encoding="utf-8")
    print("WROTE " + str(LEGENDS_PATH))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--emit-legends", action="store_true")
    args = ap.parse_args()
    spec = load_spec()
    ctx = Ctx(spec)
    frames = spec["keyframes"]
    if args.emit_legends:
        emit_legends(spec)
        return 0
    wanted = [args.only] if args.only else sorted(frames)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    failed = 0
    for kf in wanted:
        frame = frames[kf]
        img, problems, corner = render_frame(ctx, kf, frame)
        if args.check:
            status = "OK" if not problems else "FAIL " + str(len(problems))
            print(
                kf + " " + frame["filename"] + " legend=" + str(corner) + " " + status
            )
        else:
            data, q, ss = encode_jpeg(img)
            (OUT_DIR / frame["filename"]).write_bytes(data)
            status = "OK" if not problems else "FAIL " + str(len(problems))
            print(
                kf
                + " "
                + str(len(data) // 1024)
                + "KB q="
                + str(q)
                + " ss="
                + str(ss)
                + " legend="
                + str(corner)
                + " "
                + status
            )
        for p in problems:
            print("   - " + p)
            failed += 1
    if failed:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
