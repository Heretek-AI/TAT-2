#!/usr/bin/env python3
"""M2 audit validator: checks every handoff section 4.1 rule on callout_spec.json.

Usage:
    /usr/bin/python3 docs/reference/clip_1795033698901/_build/m2_audit_validate.py

Exit 0 = all checks pass. Exit 1 = failures listed.
Parses KEYFRAME_INDEX.md section 3 KF table as the timestamp/segment oracle.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SPEC_PATH = ROOT / "callout_spec.json"
INDEX_PATH = ROOT / "KEYFRAME_INDEX.md"
CLEAN_DIR = ROOT / "clean"
LEGENDS_PATH = ROOT / "CALLOUT_LEGENDS.md"

TAXONOMY = {
    "V1": "Visual",
    "V2": "Visual",
    "V3": "Visual",
    "V4": "Visual",
    "V5": "Visual",
    "V6": "Visual",
    "V7": "Visual",
    "UI1": "HUD/UI",
    "UI2": "HUD/UI",
    "UI3": "HUD/UI",
    "UI4": "HUD/UI",
    "UI5": "HUD/UI",
    "G1": "Gameplay/Audio",
    "G2": "Gameplay/Audio",
    "G3": "Gameplay/Audio",
    "G4": "Gameplay/Audio",
    "G5": "Gameplay/Audio",
    "AU1": "Gameplay/Audio",
    "AU2": "Gameplay/Audio",
    "AU3": "Gameplay/Audio",
    "AU4": "Gameplay/Audio",
    "AU5": "Gameplay/Audio",
    "AU6": "Gameplay/Audio",
}

SAFE = [16, 16, 1904, 1064]

AUDIO_STATE_KEYWORDS = [
    "bgm",
    "no bgm",
    "explicit absence",
    "rain",
    "click",
    "silence",
    "silent",
    "wind",
    "footstep",
    "vo:",
    "vo ",
    "guard vo",
    "thiefnisha",
    "music",
    "jazz",
    "gramophone",
    "tick",
    "countdown",
    "chime",
    "hiss",
    "whoosh",
    "rattle",
    "room tone",
    "ambience",
    "sfx",
    "sting",
    "honk",
    "horn",
    "shatter",
    "hum",
    "audio",
    "audible",
    "dbfs",
    "crackle",
    "clank",
    "creak",
    "thud",
    "rustle",
    "ui audio",
    "dialogue",
]

# Round-2 hardening: every KF block must explicitly state the BGM state
# (presence or absence). A KF fails when zero callout details mention any
# of these. The old per-AU AUDIO_STATE_KEYWORDS check above passed KFs
# whose AU details named concrete sounds but never stated BGM absence.
EXPLICIT_BGM_KEYWORDS = [
    "bgm",
    "music",
    "silence",
    "room tone",
    "room-tone",
    "noise bed",
    "noise-bed",
]

# KFs allowed to carry 9 callouts only with a written justification recorded here.
NINE_JUSTIFICATIONS: dict[str, str] = {}


def parse_index_kf_table(text: str) -> dict[str, dict[str, str]]:
    """Parse the section-3 KF table: | `KFnn` | `ts` | `Snn` | `file` | ..."""
    out: dict[str, dict[str, str]] = {}
    row = re.compile(
        r"^\|\s*`(KF\d\d)`\s*\|\s*`([^`]+)`\s*\|\s*`(S\d\d)`\s*\|\s*`([^`]+)`"
    )
    for line in text.splitlines():
        m = row.match(line.strip())
        if m:
            kf, ts, seg, fn = m.groups()
            out[kf] = {"timestamp": ts, "segment": seg, "filename": fn}
    return out


def in_bounds(pt) -> bool:
    return (
        isinstance(pt, list)
        and len(pt) == 2
        and all(isinstance(v, (int, float)) for v in pt)
        and SAFE[0] <= pt[0] <= SAFE[2]
        and SAFE[1] <= pt[1] <= SAFE[3]
    )


def main() -> int:
    failures: list[str] = []
    notes: list[str] = []

    spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    index_text = INDEX_PATH.read_text(encoding="utf-8")
    oracle = parse_index_kf_table(index_text)

    # 1. schema_version
    if spec.get("schema_version") != "1.1":
        failures.append(
            f"schema_version is {spec.get('schema_version')!r}, expected '1.1'"
        )

    palette = spec.get("palette", {})
    for cat in ("Visual", "HUD/UI", "Gameplay/Audio"):
        if cat not in palette:
            failures.append(f"palette missing category {cat!r}")

    kfmap = spec.get("keyframes")
    if not isinstance(kfmap, dict):
        failures.append("keyframes is not a dict (must be dict-keyed KF01..KF30)")
        print("FAIL")
        for f in failures:
            print("  - " + f)
        return 1

    expected_keys = [f"KF{i:02d}" for i in range(1, 31)]
    if sorted(kfmap.keys()) != expected_keys:
        failures.append(f"keyframe keys != KF01..KF30: got {sorted(kfmap.keys())}")
    if len(oracle) != 30:
        failures.append(
            f"KEYFRAME_INDEX section-3 oracle parsed {len(oracle)} rows, expected 30"
        )

    for kf in expected_keys:
        frame = kfmap.get(kf)
        if frame is None:
            failures.append(f"{kf}: missing from spec")
            continue
        # filename exists
        fn = frame.get("filename")
        if not fn or not (CLEAN_DIR / fn).is_file():
            failures.append(f"{kf}: filename {fn!r} missing in clean/")
        # oracle timestamp/segment/filename
        ref = oracle.get(kf)
        if ref is None:
            failures.append(f"{kf}: missing from KEYFRAME_INDEX section-3 table")
        else:
            if frame.get("timestamp") != ref["timestamp"]:
                failures.append(
                    f"{kf}: timestamp {frame.get('timestamp')!r} != index {ref['timestamp']!r}"
                )
            if frame.get("segment") != ref["segment"]:
                failures.append(
                    f"{kf}: segment {frame.get('segment')!r} != index {ref['segment']!r}"
                )
            if fn != ref["filename"]:
                failures.append(
                    f"{kf}: filename {fn!r} != index filename {ref['filename']!r}"
                )

        callouts = frame.get("callouts", [])
        n = len(callouts)
        if n < 4 or n > 9:
            failures.append(f"{kf}: {n} callouts (need 4..8, 9 only if justified)")
        elif n == 9 and kf not in NINE_JUSTIFICATIONS:
            failures.append(f"{kf}: 9 callouts with no written justification")

        ids = [c.get("id") for c in callouts]
        if ids != list(range(1, n + 1)):
            failures.append(f"{kf}: ids {ids} != 1..{n}")

        cats = {c.get("category") for c in callouts}
        if "HUD/UI" not in cats:
            failures.append(f"{kf}: no HUD/UI callout (HUD is visible in all 30 KFs)")
        au = [c for c in callouts if str(c.get("code", "")).startswith("AU")]
        if not au:
            failures.append(
                f"{kf}: no Gameplay/Audio AU-code callout naming audio state"
            )
        else:
            for c in au:
                detail = str(c.get("observed_ue5_detail", "")).lower()
                if not any(k in detail for k in AUDIO_STATE_KEYWORDS):
                    failures.append(
                        f"{kf} #{c.get('id')}: AU callout detail names no audio state"
                    )
        # Round-2 block-level check: the KF block as a whole must state the
        # BGM state explicitly (presence or absence).
        block_text = " ".join(
            str(c.get("observed_ue5_detail", "")) for c in callouts
        ).lower()
        if not any(k in block_text for k in EXPLICIT_BGM_KEYWORDS):
            failures.append(
                f"{kf}: no explicit BGM presence/absence statement in any callout detail"
            )

        for c in callouts:
            cid = c.get("id")
            tag = f"{kf} #{cid}"
            cat = c.get("category")
            if cat not in palette:
                failures.append(f"{tag}: category {cat!r} not in palette")
            code = c.get("code")
            if code not in TAXONOMY:
                failures.append(f"{tag}: code {code!r} not in section-4.2 taxonomy")
            elif TAXONOMY[code] != cat:
                failures.append(
                    f"{tag}: code {code!r} implies {TAXONOMY[code]!r} but category is {cat!r}"
                )
            label = c.get("label", "")
            if not isinstance(label, str) or not label.strip():
                failures.append(f"{tag}: empty label")
            elif len(label.split()) > 4:
                failures.append(
                    f"{tag}: label {label!r} is {len(label.split())} words (>4)"
                )
            if not in_bounds(c.get("target")):
                failures.append(
                    f"{tag}: target {c.get('target')!r} outside safe_bounds"
                )
            if not in_bounds(c.get("anchor")):
                failures.append(
                    f"{tag}: anchor {c.get('anchor')!r} outside safe_bounds"
                )
            if c.get("placement") not in ("pill_left", "pill_right"):
                failures.append(f"{tag}: unexpected placement {c.get('placement')!r}")
            bbox = c.get("bbox")
            if bbox is not None:
                if (
                    not isinstance(bbox, list)
                    or len(bbox) != 4
                    or not all(isinstance(v, (int, float)) for v in bbox)
                ):
                    failures.append(f"{tag}: malformed bbox {bbox!r}")

        for e in frame.get("hud_exclusions", []):
            if (
                not isinstance(e, list)
                or len(e) != 4
                or not all(isinstance(v, (int, float)) for v in e)
            ):
                failures.append(f"{kf}: malformed hud_exclusion {e!r}")

    # Legend parity: 30 sections, row counts == callout counts
    leg = LEGENDS_PATH.read_text(encoding="utf-8")
    sections = re.findall(r"^### (KF\d\d) - ", leg, flags=re.M)
    if sections != expected_keys:
        failures.append(f"CALLOUT_LEGENDS.md sections {sections} != KF01..KF30")
    blocks = re.split(r"^### KF\d\d - .*$", leg, flags=re.M)
    for kf in expected_keys:
        idx = expected_keys.index(kf) + 1
        if idx >= len(blocks):
            failures.append(f"{kf}: no legend block found")
            continue
        rows = [
            ln for ln in blocks[idx].splitlines() if re.match(r"^\| \d+ \|", ln.strip())
        ]
        want = len(kfmap.get(kf, {}).get("callouts", []))
        if len(rows) != want:
            failures.append(
                f"{kf}: legend has {len(rows)} rows but spec has {want} callouts"
            )

    print(f"checked {len(expected_keys)} keyframes")
    if failures:
        print(f"FAILURES: {len(failures)}")
        for f in failures:
            print("  - " + f)
        return 1
    print("ALL CHECKS PASSED")
    for x in notes:
        print("note: " + x)
    return 0


if __name__ == "__main__":
    sys.exit(main())
