#!/usr/bin/env python3
"""M2 audit fixes: add AU-code callouts, merge over-limit KFs, fix KF15 bbox.

Loads callout_spec.json, applies surgical fixes, writes back byte-identical
formatting (json dump indent=2, ensure_ascii) — verified by round-trip test.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SPEC_PATH = ROOT / "callout_spec.json"


def C(cid, cat, code, label, target, anchor, placement, detail, bbox=None):
    return {
        "id": cid,
        "category": cat,
        "code": code,
        "label": label,
        "target": target,
        "anchor": anchor,
        "placement": placement,
        "bbox": bbox,
        "observed_ue5_detail": detail,
    }


ADDS = {
    # kf: (code, label, target, anchor, placement, detail)
    "KF02": (
        "AU1",
        "Quiet Den Room Tone",
        [770, 980],
        [250, 850],
        "pill_right",
        "Thieves' Den indoor room tone (`-76.3 to -73.1 dBFS` RMS) under the opening pan across floorboards and newspapers; Explicit BGM Absence.",
    ),
    "KF06": (
        "AU3",
        "Quiet Den Footsteps",
        [550, 1020],
        [120, 1010],
        "pill_right",
        "Wooden-plank footfalls (`00:23.1-00:23.9`, `pk=-27.1 dBFS`) settling to quiet Den room tone; Ledger click follows (`00:25.2`); Explicit BGM Absence.",
    ),
    "KF10": (
        "AU4",
        "Map Toggle Clicks",
        [450, 650],
        [90, 70],
        "pill_right",
        "Map Table selection and mode-toggle clicks (`00:52.2-00:55.1`, `pk=-38.3 dBFS`) plus confirm chime (`00:55.4`); Explicit BGM Absence.",
    ),
    "KF15": (
        "AU3",
        "Wet Cobble Footsteps",
        [1010, 640],
        [700, 150],
        "pill_right",
        "Steady rain ambience (`-49 dBFS` RMS) at the alley drop; wet-cobble footfalls and puddle splashes follow (`01:24.4-01:27.4`, `pk=-25.2 dBFS`); Explicit BGM Absence.",
    ),
    "KF16": (
        "AU6",
        "Guard Alert VO",
        [855, 395],
        [420, 840],
        "pill_right",
        "Alerted constable VO: `I know someone's here!` (`01:39.3-01:40.6`, `pk=-25.9 dBFS`) overlapping the ZipWire equip clank; Explicit BGM Absence.",
    ),
    "KF18": (
        "AU5",
        "Cable Ratchet Clicks",
        [900, 480],
        [450, 750],
        "pill_right",
        "ZipWire cable-traversal ratchet clicks (`02:13.4-02:15.1`, `pk=-31.3 dBFS`) mid-crossing; Explicit BGM Absence.",
    ),
    "KF19": (
        "AU6",
        "Guard Shout VO",
        [1080, 480],
        [900, 150],
        "pill_right",
        "Guard VO `Hey! Show yourself!` (`02:24.8-02:26.0`, `pk=-33.3 dBFS`) as the player walks past the crates; Explicit BGM Absence.",
    ),
    "KF21": (
        "AU5",
        "Diamond Scan Shimmer",
        [1430, 720],
        [1100, 880],
        "pill_right",
        "Vistara Diamond scan shimmer/chime pulse (`02:32.8-02:33.6`, `pk=-28.0 dBFS`) as the guard flips RED; Explicit BGM Absence.",
    ),
    "KF22": (
        "AU5",
        "Re-Equip Click (No BGM)",
        [1560, 480],
        [1100, 880],
        "pill_right",
        "Vistara shimmer decay plus ZipWire [1] re-equip click (`02:34.0`, `pk=-28.2 dBFS`) under steady rain; Explicit BGM Absence.",
    ),
    "KF24": (
        "AU5",
        "Door Latch & Creak",
        [540, 600],
        [1300, 150],
        "pill_left",
        "Door handle latch click plus wooden door creak open (`03:01.0-03:02.2`, `pk=-29.8 dBFS`) as rain gives way to sheltered interior tone; Explicit BGM Absence.",
    ),
    "KF25": (
        "AU1",
        "Hearth Crackle (No BGM)",
        [350, 960],
        [400, 1010],
        "pill_right",
        "Roaring-hearth crackle bed (`-67.5 to -54.0 dBFS`) under the quiet crouched parquet approach; key jingle and acquisition chime follow at `03:17.1`; Explicit BGM Absence.",
    ),
    "KF29": (
        "AU5",
        "Shatter Sting & Climb",
        [800, 700],
        [250, 600],
        "pill_right",
        "Barrier shatter plus alert sting (`03:37.7-03:38.2`, `pk=-23.5 dBFS`), then rapid slate-stair footfalls and ZipWire clack (`03:39.8`, `pk=-24.5 dBFS`); Explicit BGM Absence.",
    ),
}


def apply_fixes(spec):
    kf = spec["keyframes"]

    # --- plain additions (ids continue 1..N) ---
    for k, (code, label, tgt, anc, place, detail) in ADDS.items():
        cos = kf[k]["callouts"]
        cos.append(
            C(len(cos) + 1, "Gameplay/Audio", code, label, tgt, anc, place, detail)
        )

    # --- KF15 bbox: stop enclosing the top-left HUD loot text ---
    c1 = kf["KF15"]["callouts"][0]
    assert c1["label"] == "BARRON'S DEMOLITION Banner", c1["label"]
    assert c1["bbox"] == [8, 100, 845, 610], c1["bbox"]
    c1["bbox"] = [8, 210, 845, 610]

    # --- KF27: merge emitter+beam, merge case+plate, renumber, add AU ---
    cos = kf["KF27"]["callouts"]
    assert [c["id"] for c in cos] == list(range(1, 10)), "KF27 ids"
    e1 = cos[0]
    assert e1["label"] == "Left-Wall Beam Emitter", e1["label"]
    e1["label"] = "Wall Emitter & Beam"
    e1["observed_ue5_detail"] = (
        "Mid-height circular glowing white beam emitter on the left marble "
        "foyer wall (~40% height) projecting the crisp horizontal white "
        "volumetric beam spanning wall-to-wall; crossing it triggers the "
        "ward lockdown (`03:29.00`)."
    )
    old_beam, old_case = cos[1], cos[2]
    assert old_beam["label"] == "Horizontal Volumetric Beam", old_beam["label"]
    assert old_case["label"] == "Glass Statue Display Case", old_case["label"]
    old_case["label"] = "Case & Floor Plate"
    old_case["observed_ue5_detail"] = (
        "Tall internally lit glass display vitrine housing a bust/statue "
        "beside a velvet armchair and ottoman; flush square metallic "
        "pressure/junction plate embedded in the checkered marble floor "
        "ahead of the carpet runner (`x~910, y~608`)."
    )
    plate = cos[5]
    assert plate["label"] == "Square Metal Floor Plate", plate["label"]
    # remove old beam (#2) and old plate (#6); keep order otherwise
    kept = [cos[0], cos[2], cos[3], cos[4], cos[6], cos[7], cos[8]]
    for i, c in enumerate(kept, 1):
        c["id"] = i
    kept.append(
        C(
            8,
            "Gameplay/Audio",
            "AU3",
            "Marble Footstep Sequence",
            [850, 700],
            [700, 780],
            "pill_right",
            "Crisp hard-sole footfalls on checkered marble "
            "(`03:23.8-03:28.9`, `pk=-28.9 dBFS`) crossing the foyer; "
            "Explicit BGM Absence.",
        )
    )
    kf["KF27"]["callouts"] = kept

    # --- KF28: merge the two status icons, renumber, add AU ---
    cos = kf["KF28"]["callouts"]
    assert [c["id"] for c in cos] == list(range(1, 9)), "KF28 ids"
    jaw, unc = cos[5], cos[6]
    assert jaw["label"] == "Jaw-Trap Status Icon", jaw["label"]
    assert unc["label"] == "Unconscious Guard Icon", unc["label"]
    jaw["label"] = "Status Icons Above Gem"
    jaw["target"] = [965, 806]
    jaw["observed_ue5_detail"] = (
        "White circular mechanical jaw/bear-trap icon with active countdown "
        "ring (`03:29.00+`) plus orange-arc unconscious-head (`xx` eyes + "
        "`zz`) circular icon (`03:31.20+`) stacked above the Light Gem."
    )
    kept = [cos[0], cos[1], cos[2], cos[3], cos[4], jaw, cos[7]]
    for i, c in enumerate(kept, 1):
        c["id"] = i
    kept.append(
        C(
            8,
            "Gameplay/Audio",
            "AU5",
            "Ward Tripwire Chime",
            [1000, 600],
            [560, 880],
            "pill_right",
            "Two-note metallic tripwire chime (`03:29.1-03:29.6`, "
            "`pk=-30.4 dBFS`) plus shimmer whoosh settling into the "
            "sustained low ward hum (`-59 dBFS`); Explicit BGM Absence.",
        )
    )
    kf["KF28"]["callouts"] = kept

    # --- KF27/KF28 AU for KF27 done above; KF27 in ADDS? no. KF28 in ADDS? no. ---
    return spec


def main() -> int:
    raw = SPEC_PATH.read_text(encoding="utf-8")
    spec = json.loads(raw)
    # round-trip fidelity: dump must reproduce the file byte-for-byte
    rt = json.dumps(spec, indent=2, ensure_ascii=True)
    if raw.endswith("\n"):
        rt += "\n"
    if rt != raw:
        print("ROUND-TRIP MISMATCH: refusing to edit (formatting differs).")
        for i, (a, b) in enumerate(zip(raw.splitlines(), rt.splitlines())):
            if a != b:
                print(f"first diff at line {i + 1}:\n  file: {a!r}\n  dump: {b!r}")
                break
        print(f"len file={len(raw)} len dump={len(rt)}")
        return 1
    print("round-trip: byte-identical, proceeding")
    spec = apply_fixes(spec)
    out = json.dumps(spec, indent=2, ensure_ascii=True)
    if raw.endswith("\n"):
        out += "\n"
    SPEC_PATH.write_text(out, encoding="utf-8")
    total = sum(len(f["callouts"]) for f in spec["keyframes"].values())
    print(f"wrote {SPEC_PATH}: 30 KFs, {total} callouts")
    for k in sorted(spec["keyframes"]):
        print(f"  {k}: {len(spec['keyframes'][k]['callouts'])} callouts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
