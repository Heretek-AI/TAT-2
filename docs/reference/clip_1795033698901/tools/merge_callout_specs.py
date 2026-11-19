#!/usr/bin/env python3
"""Merge the three M2 draft callout specs into one normalized file.

Usage (paths are relative to this script location):
    /usr/bin/python3 merge_callout_specs.py --dump
    /usr/bin/python3 merge_callout_specs.py --check
    /usr/bin/python3 merge_callout_specs.py --write

Draft schemas handled:
  kf01_10: keyframes dict; callout id/target/anchor/placement/bbox/
           observed_ue5_detail; hud_exclusions = [[x0,y0,x1,y1], ...]
  kf11_20: keyframes dict; callout num/target/anchor/placement/bbox/detail;
           protected_hud = [[x0,y0,x1,y1], ...]
  kf21_30: keyframes list; callout id/target/label_anchor/placement/bbox/
           observed_detail (+estimated_pill_bbox, +color, dropped);
           hud_exclusion_zones = [[name, [x0,y0,x1,y1]], ...]

Output: callout_spec.json, schema_version 1.1, dict-keyed KF01..KF30.
Code overrides and coordinate/detail fixes below come from clean-keyframe
visual verification and 4K source-frame crops (see CALLOUT_LEGENDS.md).

HUD-SEMANTICS GUARD (2026-11-19, run 20261118-185627-d692): callout_spec.json
has been hand-corrected to the user-confirmed HUD semantics (Light Gem =
light exposure + direction; red arcs = player noise, NOT threat/detection).
The CODE_OVERRIDES / detail strings below still carry the OLD wording and
the OLD per-keyframe numbering, so --write MUST refuse to overwrite a
corrected v1.1 spec. To rebuild from drafts, delete callout_spec.json first
(and re-apply the hud-semantics corrections afterwards).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CLEAN = ROOT / "clean"
INDEX = ROOT / "KEYFRAME_INDEX.md"
OUT = ROOT / "callout_spec.json"
DRAFTS = [
    ROOT / "_carryover" / "callout_spec_kf01_10.json",
    ROOT / "_carryover" / "callout_spec_kf11_20.json",
    ROOT / "_carryover" / "callout_spec_kf21_30.json",
]
SAFE_BOUNDS = [16, 16, 1904, 1064]
PALETTE = {"Visual": "#FFB300", "HUD/UI": "#00E5FF", "Gameplay/Audio": "#FF4081"}
CATEGORY_FOR_PREFIX = {
    "V": "Visual",
    "UI": "HUD/UI",
    "G": "Gameplay/Audio",
    "AU": "Gameplay/Audio",
}
VALID_CODES = {
    "V1",
    "V2",
    "V3",
    "V4",
    "V5",
    "V6",
    "V7",
    "UI1",
    "UI2",
    "UI3",
    "UI4",
    "UI5",
    "G1",
    "G2",
    "G3",
    "G4",
    "G5",
    "AU1",
    "AU2",
    "AU3",
    "AU4",
    "AU5",
    "AU6",
}
VALID_PLACEMENTS = {"pill_left", "pill_right"}
AUDIO_KEYWORDS = [
    "dbfs",
    "bgm",
    "silence",
    "room tone",
    "chime",
    "click",
    "rustle",
    "footstep",
    "rain",
    "wind",
    "hiss",
    "thud",
    "grunt",
    "tick",
    "whoosh",
    "shimmer",
    "jingle",
    "creak",
    "sting",
    "hum",
    "clank",
    "bark",
    "cough",
    "vo",
    "nisha",
    "guard",
    "music",
    "ambience",
]
MEASURE_WORDS = ("dbfs", "bgm", "silence", "room tone")
CODE_OVERRIDES = {
    "KF01#4": "G4",
    "KF01#5": "V2",
    "KF02#2": "UI3",
    "KF02#3": "UI3",
    "KF02#6": "G1",
    "KF03#1": "UI4",
    "KF03#2": "UI4",
    "KF03#3": "UI4",
    "KF03#4": "V5",
    "KF03#5": "V4",
    "KF04#2": "AU4",
    "KF04#3": "UI4",
    "KF04#4": "V5",
    "KF05#1": "V2",
    "KF05#3": "V4",
    "KF05#4": "UI2",
    "KF05#5": "AU1",
    "KF06#3": "V4",
    "KF06#5": "V4",
    "KF06#6": "UI3",
    "KF07#1": "UI4",
    "KF07#2": "UI4",
    "KF07#3": "UI4",
    "KF07#5": "UI4",
    "KF07#6": "AU4",
    "KF08#1": "UI4",
    "KF08#2": "UI4",
    "KF08#3": "UI4",
    "KF08#6": "AU4",
    "KF09#1": "AU2",
    "KF09#2": "UI2",
    "KF10#1": "UI4",
    "KF11#1": "UI5",
    "KF11#2": "UI4",
    "KF11#3": "UI4",
    "KF11#5": "V5",
    "KF11#6": "AU4",
    "KF12#2": "V2",
    "KF12#3": "UI4",
    "KF12#4": "UI4",
    "KF12#5": "AU1",
    "KF13#1": "V7",
    "KF13#2": "UI4",
    "KF13#3": "UI4",
    "KF13#4": "UI4",
    "KF14#1": "V6",
    "KF14#3": "UI3",
    "KF14#4": "UI3",
    "KF14#6": "UI5",
    "KF14#7": "AU6",
    "KF15#1": "V4",
    "KF15#3": "V4",
    "KF15#4": "UI3",
    "KF15#5": "G2",
    "KF16#1": "V4",
    "KF16#2": "G4",
    "KF16#4": "G3",
    "KF16#5": "UI3",
    "KF16#6": "UI2",
    "KF17#1": "G3",
    "KF17#3": "UI2",
    "KF17#4": "UI5",
    "KF17#5": "AU5",
    "KF18#1": "G2",
    "KF18#2": "V4",
    "KF18#3": "G4",
    "KF18#4": "V4",
    "KF18#5": "V4",
    "KF18#6": "UI5",
}
CODE_OVERRIDES.update(
    {
        "KF19#1": "UI3",
        "KF19#2": "V4",
        "KF19#3": "V4",
        "KF19#4": "G3",
        "KF19#5": "UI2",
        "KF19#6": "UI3",
        "KF20#1": "V6",
        "KF20#2": "AU5",
        "KF20#3": "UI3",
        "KF20#4": "UI5",
        "KF20#5": "UI2",
        "KF21#1": "UI3",
        "KF21#2": "V4",
        "KF21#3": "G4",
        "KF21#5": "UI3",
        "KF22#1": "V5",
        "KF22#2": "V1",
        "KF22#4": "UI3",
        "KF23#1": "UI3",
        "KF23#2": "V4",
        "KF23#3": "V4",
        "KF24#1": "V4",
        "KF24#5": "UI5",
        "KF25#1": "V1",
        "KF25#2": "G4",
        "KF25#3": "G4",
        "KF26#1": "V1",
        "KF26#2": "G4",
        "KF26#3": "UI5",
        "KF26#4": "AU5",
        "KF27#1": "G5",
        "KF27#2": "V6",
        "KF27#3": "V4",
        "KF27#5": "G5",
        "KF27#6": "G1",
        "KF27#7": "UI3",
        "KF27#8": "UI5",
        "KF28#1": "V6",
        "KF28#2": "V6",
        "KF28#3": "G1",
        "KF28#4": "G5",
        "KF28#5": "V6",
        "KF28#6": "UI5",
        "KF28#7": "UI5",
        "KF29#1": "V4",
        "KF29#2": "V1",
        "KF29#4": "UI5",
        "KF30#1": "V7",
        "KF30#4": "AU4",
    }
)
COORD_FIXES = {
    "KF01#3": {"anchor": [1240, 770], "placement": "pill_left"},
    "KF13#2": {"anchor": [135, 560], "placement": "pill_right"},
    "KF13#5": {"target": [960, 898]},
    "KF15#2": {"target": [985, 172]},
    "KF16#2": {"target": [871, 422]},
    "KF17#3": {"target": [890, 535]},
    "KF18#3": {"target": [1128, 268]},
    "KF21#3": {"target": [885, 657]},
    "KF22#1": {"target": [848, 612]},
    "KF25#2": {"target": [626, 633]},
    "KF27#1": {"target": [305, 432]},
    "KF28#1": {"target": [420, 547]},
    "KF28#6": {"anchor": [600, 760]},
    "KF28#7": {"anchor": [600, 880]},
}
EXTRA_CALLOUTS = {
    "KF03": [
        {
            "id": 7,
            "category": "Gameplay/Audio",
            "code": "AU4",
            "label": "Wardrobe Browse Ticks",
            "target": [200, 505],
            "anchor": [80, 392],
            "placement": "pill_right",
            "bbox": None,
            "observed_ue5_detail": "Wardrobe open chime decay after 00:06.7 latch; crisp metallic browse ticks from 00:08.9 (pk -34.6 to -39.4 dBFS); no BGM.",
        }
    ],
    "KF23": [
        {
            "id": 6,
            "category": "Gameplay/Audio",
            "code": "AU1",
            "label": "Rain and Footsteps",
            "target": [700, 900],
            "anchor": [420, 980],
            "placement": "pill_right",
            "bbox": None,
            "observed_ue5_detail": "Steady rain on wet stone balcony plus rapid wet footstep bed and ZipWire re-equip click (02:34.0, pk -28.2 dBFS); distant guard throat-clear follows at 02:41.5; no BGM.",
        }
    ],
}
DETAIL_APPENDS = {
    "KF19#4": " Guard VO: Hey! Show yourself! (02:24.8-02:26.0, pk -33.3 dBFS); no BGM.",
    "KF22#3": " Vistara shimmer decay plus ZipWire re-equip click (02:34.0, pk -28.2 dBFS); no BGM.",
}


def parse_index():
    text = INDEX.read_text(encoding="utf-8")
    rows = {}
    for line in text.splitlines():
        line = line.strip()
        if not (line.startswith("| `KF") and line.endswith("|")):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 4:
            continue
        kf = cells[0].strip("` ")
        rows[kf] = {
            "timestamp": cells[1].strip("` "),
            "segment": cells[2].strip("` "),
            "filename": cells[3].strip("` "),
        }
    if len(rows) != 30:
        raise SystemExit("FATAL: parsed " + str(len(rows)) + " rows, expected 30")
    return rows


def norm_bbox(value):
    return None if value is None else [int(v) for v in value]


def norm_hud(value):
    boxes = []
    for item in value or []:
        if isinstance(item, dict):
            item = item.get("bbox")
        if (
            isinstance(item, (list, tuple))
            and len(item) == 2
            and isinstance(item[1], (list, tuple))
        ):
            item = item[1]
        boxes.append([int(v) for v in item])
    return boxes


def load_drafts():
    frames = {}
    for path in DRAFTS:
        doc = json.loads(path.read_text(encoding="utf-8"))
        raw = doc["keyframes"]
        if isinstance(raw, dict):
            items = []
            for kf, body in raw.items():
                body = dict(body)
                body.setdefault("kf_id", kf)
                items.append(body)
        else:
            items = raw
        for body in items:
            kf = body.get("kf_id") or body.get("id")
            if kf in frames:
                raise SystemExit("FATAL: duplicate " + str(kf))
            callouts = []
            for pos, c in enumerate(body.get("callouts", []), start=1):
                cid = c.get("id", c.get("num", pos))
                det = (
                    c.get("observed_ue5_detail")
                    or c.get("observed_detail")
                    or c.get("detail")
                    or ""
                ).strip()
                callouts.append(
                    {
                        "id": int(cid),
                        "category": c["category"],
                        "code": c["code"],
                        "label": c["label"].strip(),
                        "target": [int(v) for v in c["target"]],
                        "anchor": [
                            int(v) for v in (c.get("anchor") or c.get("label_anchor"))
                        ],
                        "placement": c["placement"],
                        "bbox": norm_bbox(c.get("bbox")),
                        "observed_ue5_detail": det,
                    }
                )
            frames[kf] = {
                "filename": body["filename"],
                "segment": body["segment"],
                "timestamp": body["timestamp"],
                "hud_exclusions": norm_hud(
                    body.get("hud_exclusions")
                    or body.get("protected_hud")
                    or body.get("hud_exclusion_zones")
                ),
                "callouts": sorted(callouts, key=lambda c: c["id"]),
            }
    for kf, extra in EXTRA_CALLOUTS.items():
        frames[kf]["callouts"].extend(extra)
        frames[kf]["callouts"].sort(key=lambda c: c["id"])
    for kf, frame in frames.items():
        for c in frame["callouts"]:
            key = kf + "#" + str(c["id"])
            if key in CODE_OVERRIDES:
                c["code"] = CODE_OVERRIDES[key]
            if key in COORD_FIXES:
                c.update(COORD_FIXES[key])
            if key in DETAIL_APPENDS:
                c["observed_ue5_detail"] = (
                    c["observed_ue5_detail"] + DETAIL_APPENDS[key]
                )
    return frames


def names_audio(c):
    if c["code"].startswith("AU"):
        return True
    detail = c["observed_ue5_detail"].lower()
    if c["category"] == "Gameplay/Audio" and any(k in detail for k in AUDIO_KEYWORDS):
        return True
    return any(k in detail for k in MEASURE_WORDS)


def validate(frames, index):
    errors = []
    if sorted(frames) != ["KF%02d" % i for i in range(1, 31)]:
        errors.append("keyframe set is not exactly KF01..KF30")
    clean_files = set(p.name for p in CLEAN.glob("*.jpg"))
    if len(clean_files) != 30:
        errors.append("clean/ holds " + str(len(clean_files)) + " jpgs")
    for kf in sorted(frames):
        frame = frames[kf]
        truth = index.get(kf)
        if truth is None:
            errors.append(kf + ": missing from KEYFRAME_INDEX.md")
            continue
        for field in ("timestamp", "segment", "filename"):
            if frame[field] != truth[field]:
                errors.append(
                    kf + ": " + field + " " + frame[field] + " != index " + truth[field]
                )
        if frame["filename"] not in clean_files:
            errors.append(kf + ": file missing from clean/")
        n = len(frame["callouts"])
        if not 4 <= n <= 8:
            errors.append(kf + ": " + str(n) + " callouts, need 4..8")
        ids = [c["id"] for c in frame["callouts"]]
        if ids != list(range(1, n + 1)):
            errors.append(kf + ": ids " + repr(ids))
        if not any(c["category"] == "HUD/UI" for c in frame["callouts"]):
            errors.append(kf + ": no HUD/UI callout")
        if not any(names_audio(c) for c in frame["callouts"]):
            errors.append(kf + ": no audio-state callout")
        for c in frame["callouts"]:
            tag = kf + "#" + str(c["id"])
            if c["code"] not in VALID_CODES:
                errors.append(tag + ": bad code " + repr(c["code"]))
            if c["category"] not in PALETTE:
                errors.append(tag + ": bad category")
            prefix = (
                "AU"
                if c["code"].startswith("AU")
                else ("UI" if c["code"].startswith("UI") else c["code"][0])
            )
            if CATEGORY_FOR_PREFIX.get(prefix) != c["category"]:
                errors.append(tag + ": category/code mismatch")
            if c["placement"] not in VALID_PLACEMENTS:
                errors.append(tag + ": bad placement")
            if len(c["label"].split()) > 4:
                errors.append(tag + ": label too long")
            x0, y0, x1, y1 = SAFE_BOUNDS
            for field in ("target", "anchor"):
                x, y = c[field]
                if not (x0 <= x <= x1 and y0 <= y <= y1):
                    errors.append(tag + ": " + field + " out of bounds")
            if not c["observed_ue5_detail"]:
                errors.append(tag + ": empty detail")
            if c["bbox"] is not None:
                bx = c["bbox"]
                if not (0 <= bx[0] < bx[2] <= 1920 and 0 <= bx[1] < bx[3] <= 1080):
                    errors.append(tag + ": bbox out of frame")
    return errors


def build(frames, index):
    ordered = {}
    for kf in sorted(frames):
        f = frames[kf]
        keep = (
            "id",
            "category",
            "code",
            "label",
            "target",
            "anchor",
            "placement",
            "bbox",
            "observed_ue5_detail",
        )
        ordered[kf] = {
            "filename": index[kf]["filename"],
            "segment": index[kf]["segment"],
            "timestamp": index[kf]["timestamp"],
            "hud_exclusions": f["hud_exclusions"],
            "callouts": [{k: c[k] for k in keep} for c in f["callouts"]],
        }
    return {
        "schema_version": "1.1",
        "resolution": [1920, 1080],
        "fonts": {
            "badge_numeral": "/usr/share/fonts/google-noto/NotoSans-Bold.ttf",
            "label_text": "/usr/share/fonts/google-noto/NotoSans-SemiBold.ttf",
            "fallback_regular": "/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
        },
        "palette": PALETTE,
        "geometry": {
            "badge_diameter_px": 28,
            "badge_stroke_px": 2,
            "leader_width_px": 2.5,
            "leader_casing_px": 1,
            "target_dot_diameter_px": 6,
            "pill_height_px": 32,
            "pill_pad_x_px": 12,
            "badge_pill_gap_px": 6,
            "label_font_size_px": 17,
            "badge_font_size_px": 16,
            "legend_font_size_px": 14,
            "safe_bounds": SAFE_BOUNDS,
        },
        "keyframes": ordered,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    index = parse_index()
    frames = load_drafts()
    if args.dump:
        for kf in sorted(frames):
            f = frames[kf]
            print(
                "== "
                + kf
                + " "
                + f["filename"]
                + " "
                + f["segment"]
                + " "
                + f["timestamp"]
            )
            for c in f["callouts"]:
                print(
                    "   #"
                    + str(c["id"])
                    + " ["
                    + c["category"]
                    + "/"
                    + c["code"]
                    + "] "
                    + c["label"]
                )
        print("TOTAL", len(frames), sum(len(f["callouts"]) for f in frames.values()))
        return 0
    errors = validate(frames, index)
    if errors:
        print("VALIDATION FAILED:")
        for e in errors:
            print("  -", e)
        return 1
    total = sum(len(f["callouts"]) for f in frames.values())
    print("VALID: " + str(len(frames)) + " keyframes, " + str(total) + " callouts")
    if args.write:
        if OUT.exists():
            try:
                existing = json.loads(OUT.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                existing = {}
            if isinstance(existing, dict) and existing.get("schema_version") == "1.1":
                print(
                    "REFUSED: "
                    + str(OUT)
                    + " is an existing schema 1.1 spec (it carries the corrected HUD semantics)."
                    + " --write would clobber it with stale draft wording/numbering."
                )
                return 2
        OUT.write_text(
            json.dumps(build(frames, index), indent=2) + chr(10), encoding="utf-8"
        )
        print("WROTE " + str(OUT) + " " + str(OUT.stat().st_size) + " bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
