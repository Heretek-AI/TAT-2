#!/usr/bin/env python3
"""27-beat -> 120-row route scorer scaffold (Phase 3C instrument).

What this is
------------
`docs/reference/clip_1795033698901/row_route_matrix.md` defines 120 scorecard
rows and says which official beat situation each row needs. This tool:

  1. binds every one of the 120 rows to the official S01..S27 beat(s) where its
     subject appears,
  2. validates that binding against the tracked matrix (ids, pillars, the
     matrix's own YES/PARTIAL/NO tally), and
  3. refuses to emit any `PASS` / `DELTA` / `MISSING` / `HARD_LIMIT` /
     `N/A-route` token until a **played** route manifest exists.

The P0b staged capture and the short `route_driver.gd` segment are not played
routes (`route_claim` is `none`), so this version always reports
`tokens_emitted=0`. A later played-route task must supply real machine scores;
this tool will not invent them.

Usage
-----
  python3 build/qa/p0b_route_stats.py --self-test
  python3 build/qa/p0b_route_stats.py                     # mapping summary only
  python3 build/qa/p0b_route_stats.py \
      --manifest docs/reports/logs/p0b-route-driver/den_telescope/manifest.json \
      --out build/qa/p0b_route_stats/den_telescope.json

Exit codes: 0 = mapping/self-test valid, 1 = a check failed.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / "docs/reference/clip_1795033698901/row_route_matrix.md"

BEAT_IDS = [f"S{i:02d}" for i in range(1, 28)]
PILLAR_PREFIX = {"V": "visual", "AU": "audio", "UI": "hud_ui", "G": "gameplay"}
PILLAR_COUNTS = {"visual": 37, "audio": 31, "hud_ui": 27, "gameplay": 25}

TOKEN_VOCAB = ["PASS", "DELTA", "MISSING", "HARD_LIMIT", "N/A-route"]

# ---------------------------------------------------------------------------
# Beat -> row binding. Every value is the official beat(s) whose reference
# situation shows the row's subject. A row with several beats is visible in any
# of them (the scorer must require the played manifest to cover at least one).
# ---------------------------------------------------------------------------
ROW_BEATS: dict[str, list[str]] = {
    # Visual (37)
    "V1-01": ["S01"],
    "V1-02": ["S03"],
    "V1-03": ["S08"],
    "V1-04": ["S12", "S13"],
    "V1-05": ["S13", "S14"],
    "V1-06": ["S22"],
    "V1-07": ["S26"],
    "V2-01": ["S01", "S13"],
    "V2-02": ["S05"],
    "V2-03": ["S02", "S10"],
    "V2-04": ["S13", "S20"],
    "V2-05": ["S10", "S11", "S13"],
    "V3-01": ["S13"],
    "V3-02": ["S03", "S04", "S07"],
    "V3-03": ["S21"],
    "V3-04": ["S01"],
    "V4-01": ["S01"],
    "V4-02": ["S03"],
    "V4-03": ["S03", "S05"],
    "V4-04": ["S13"],
    "V4-05": ["S14", "S17"],
    "V4-06": ["S20"],
    "V4-07": ["S24"],
    "V5-01": ["S01"],
    "V5-02": ["S04"],
    "V5-03": ["S13", "S14", "S15"],
    "V5-04": ["S22"],
    "V5-05": ["S23"],
    "V6-01": ["S12"],
    "V6-02": ["S18"],
    "V6-03": ["S24"],
    "V6-04": ["S25"],
    "V7-01": ["S01"],
    "V7-02": ["S05"],
    "V7-03": ["S11"],
    "V7-04": ["S23"],
    "V7-05": ["S27"],
    # Audio (31)
    "AU1-01": ["S01"],
    "AU1-02": ["S03"],
    "AU1-03": ["S02", "S10"],
    "AU1-04": ["S05"],
    "AU1-05": ["S13", "S14", "S15", "S16", "S17", "S20"],
    "AU1-06": ["S22"],
    "AU2-01": ["S07"],
    "AU3-01": ["S03"],
    "AU3-02": ["S13"],
    "AU3-03": ["S16", "S17"],
    "AU3-04": ["S24", "S25", "S26"],
    "AU3-05": ["S26"],
    "AU4-01": ["S01", "S02"],
    "AU4-02": ["S04"],
    "AU4-03": ["S06"],
    "AU4-04": ["S09"],
    "AU4-05": ["S27"],
    "AU5-01": ["S13"],
    "AU5-02": ["S14", "S15", "S16"],
    "AU5-03": ["S18"],
    "AU5-04": ["S19"],
    "AU5-05": ["S25"],
    "AU5-06": ["S26"],
    "AU5-07": ["S22"],
    "AU5-08": ["S23"],
    "AU6-01": ["S12"],
    "AU6-02": ["S13"],
    "AU6-03": ["S14", "S15", "S16"],
    "AU6-04": ["S18"],
    "AU6-05": ["S24"],
    "AU6-06": ["S17", "S20"],
    # HUD/UI (27)
    "UI1-01": ["S01"],
    "UI1-02": ["S27"],
    "UI2-01": ["S03", "S05", "S08"],
    "UI2-02": ["S04"],
    "UI2-03": ["S13", "S14", "S15"],
    "UI2-04": ["S15"],
    "UI2-05": ["S21"],
    "UI2-06": ["S22", "S23"],
    "UI2-07": ["S07"],
    "UI3-01": ["S03"],
    "UI3-02": ["S12", "S13", "S14"],
    "UI3-03": ["S17"],
    "UI3-04": ["S22"],
    "UI3-05": ["S12", "S24"],
    "UI3-06": ["S08"],
    "UI4-01": ["S06"],
    "UI4-02": ["S06"],
    "UI4-03": ["S09"],
    "UI4-04": ["S11"],
    "UI4-05": ["S02", "S10"],
    "UI5-01": ["S13", "S19"],
    "UI5-02": ["S15"],
    "UI5-03": ["S14"],
    "UI5-04": ["S19"],
    "UI5-05": ["S09"],
    "UI5-06": ["S25", "S26"],
    "UI5-07": ["S20"],
    # Gameplay (25)
    "G1-01": ["S05"],
    "G1-02": ["S07"],
    "G1-03": ["S08", "S09"],
    "G1-04": ["S13"],
    "G1-05": ["S12"],
    "G1-06": ["S22"],
    "G2-01": ["S03"],
    "G2-02": ["S13"],
    "G2-03": ["S14", "S15", "S16"],
    "G2-04": ["S17"],
    "G2-05": ["S26"],
    "G3-01": ["S14"],
    "G3-02": ["S18"],
    "G3-03": ["S19"],
    "G3-04": ["S19"],
    "G4-01": ["S13", "S14"],
    "G4-02": ["S16"],
    "G4-03": ["S17", "S20"],
    "G4-04": ["S23"],
    "G4-05": ["S17"],
    "G5-01": ["S08", "S09", "S10"],
    "G5-02": ["S17"],
    "G5-03": ["S25"],
    "G5-04": ["S26"],
    "G5-05": ["S27"],
}

# Rows whose staged/prep form is the free-play substitute, not the official
# contract selection. Kept on the row so a later played score cannot silently
# treat the substitute as official.
FREE_PLAY_SUBSTITUTE_ROWS = {"UI3-02", "UI4-03", "G5-01"}

# Measured by game/tests/probe_route_npcs.gd at this HEAD: 4 guards + 3
# civilians at 85.4-150.7 m from the route anchor (the old "48-151 m" note's
# nearest was 48.1 m; the current authored spawn is farther). These beats'
# subjects are not on the route, so any played manifest that does not move an
# NPC into reach must record them unreachable.
NPC_UNREACHABLE_BEATS = {"S19", "S20", "S22", "S23"}
NPC_MEASUREMENT = {
    "source": "res://tests/probe_route_npcs.gd",
    "guards": 4,
    "civilians": 3,
    "nearest_m": 85.4,
    "max_m": 150.7,
    "anchor": "authored Guildhall Contract 2 safe-room spawn",
    "unreachable_beats": sorted(NPC_UNREACHABLE_BEATS),
}

BAD_MATRIX_REASON = (
    "row_route_matrix marks this row NO: the reference situation never occurs "
    "on this route, so the listed beat is where the subject would have to appear"
)


def _pillar(row_id: str) -> str:
    if row_id.startswith("AU"):
        return "audio"
    if row_id.startswith("UI"):
        return "hud_ui"
    return "visual" if row_id.startswith("V") else "gameplay"


def parse_matrix(path: Path = MATRIX) -> dict[str, dict]:
    """Parse the tracked matrix's four tables. Returns id -> row metadata."""
    rows: dict[str, dict] = {}
    text = path.read_text(encoding="utf-8")
    for line in text.splitlines():
        if not line.startswith("| "):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 5:
            continue
        row_id = cells[0]
        if not re.fullmatch(r"(?:AU[1-6]|UI[1-5]|V[1-7]|G[1-5])-\d{2}", row_id):
            continue
        scorable = cells[3]
        if scorable not in {"YES", "PARTIAL", "NO"}:
            continue
        rows[row_id] = {
            "criterion": cells[1],
            "lane": cells[2],
            "scorable": scorable,
            "anchor": cells[4],
            "absence": cells[5] if len(cells) > 5 else "",
            "pillar": _pillar(row_id),
        }
    return rows


def emit_tokens(manifest: dict | None, row_report: list[dict]) -> dict:
    """Tokens are gated on a *played* run. No played run exists in this lane, so
    the answer is always zero here; even a future played manifest may only be
    scored from explicit per-row machine scores (not implemented)."""
    if not manifest or str(manifest.get("route_claim", "none")) != "played":
        return {
            "tokens": {},
            "tokens_emitted": 0,
            "reason": "route_claim is not 'played' (staged capture / short driver segment): no row token may be emitted",
        }
    return {
        "tokens": {},
        "tokens_emitted": 0,
        "reason": "played manifest present but this instrument has no per-row machine score input; refusing to invent tokens",
    }


def build_report(manifest: dict | None) -> dict:
    matrix = parse_matrix()
    rows: list[dict] = []
    for row_id, meta in matrix.items():
        beats = ROW_BEATS[row_id]
        reasons: list[str] = []
        if meta["scorable"] == "NO":
            reasons.append(BAD_MATRIX_REASON)
        if row_id in FREE_PLAY_SUBSTITUTE_ROWS:
            reasons.append(
                "staged/prep form is the free-play substitute, not the official mission selection"
            )
        npc = [b for b in beats if b in NPC_UNREACHABLE_BEATS]
        if npc:
            reasons.append(
                "NPC-dependent: %s; measured nearest NPC %.1f m (probe_route_npcs.gd)"
                % (",".join(npc), NPC_MEASUREMENT["nearest_m"])
            )
        rows.append(
            {
                "row_id": row_id,
                "pillar": meta["pillar"],
                "lane": meta["lane"],
                "criterion": meta["criterion"],
                "scorable": meta["scorable"],
                "beats": beats,
                "npc_dependent": bool(npc),
                "mission_binding": "free_play_substitute"
                if row_id in FREE_PLAY_SUBSTITUTE_ROWS
                else "official",
                "explicit_reason": " | ".join(reasons),
                "token": None,
            }
        )
    tokens = emit_tokens(manifest, rows)
    return {
        "schema": "tat2.route_row_map/1",
        "route_claim": "none"
        if not manifest
        else str(manifest.get("route_claim", "none")),
        "manifest": str(manifest.get("_source", "")) if manifest else "",
        "rows": rows,
        "row_count": len(rows),
        "beat_count": len(BEAT_IDS),
        "rows_with_beats": sum(1 for r in rows if r["beats"]),
        "rows_without_beats": sum(1 for r in rows if not r["beats"]),
        "npc_measurement": NPC_MEASUREMENT,
        "tokens_emitted": tokens["tokens_emitted"],
        "token_policy": tokens["reason"],
        "tokens": tokens["tokens"],
    }


def self_test() -> int:
    checks = 0
    fails = 0

    def check(cond: bool, what: str, detail: str = "") -> None:
        nonlocal checks, fails
        checks += 1
        if cond:
            print("PASS: [stats] " + what)
        else:
            fails += 1
            print("FAIL: [stats] %s %s" % (what, detail), file=sys.stderr)

    matrix = parse_matrix()
    check(len(matrix) == 120, "matrix parses 120 rows", "got %d" % len(matrix))
    by_pillar = {p: 0 for p in PILLAR_COUNTS}
    by_scorable = {"YES": 0, "PARTIAL": 0, "NO": 0}
    for meta in matrix.values():
        by_pillar[meta["pillar"]] += 1
        by_scorable[meta["scorable"]] += 1
    check(
        by_pillar == PILLAR_COUNTS,
        "pillar counts match the template (37/31/27/25)",
        str(by_pillar),
    )
    check(
        by_scorable == {"YES": 43, "PARTIAL": 21, "NO": 56},
        "scorable tally matches the matrix (43/21/56)",
        str(by_scorable),
    )

    mapped = set(ROW_BEATS)
    check(
        mapped == set(matrix),
        "mapping ids exactly equal the matrix ids",
        "missing=%s extra=%s"
        % (sorted(set(matrix) - mapped), sorted(mapped - set(matrix))),
    )
    check(len(ROW_BEATS) == 120, "mapping has 120 rows", "got %d" % len(ROW_BEATS))
    check(
        all(len(v) > 0 for v in ROW_BEATS.values()), "every row has at least one beat"
    )
    bad_beats = sorted({b for v in ROW_BEATS.values() for b in v if b not in BEAT_IDS})
    check(not bad_beats, "every mapped beat is an official S01..S27 id", str(bad_beats))
    used = {b for v in ROW_BEATS.values() for b in v}
    check(
        used == set(BEAT_IDS),
        "all 27 beats are referenced by at least one row",
        "unused=%s" % sorted(set(BEAT_IDS) - used),
    )
    # No duplicate row ids inside a binding.
    dup = [r for r, v in ROW_BEATS.items() if len(v) != len(set(v))]
    check(not dup, "no duplicate beat inside one row binding", str(dup))

    # Explicit reason coverage: every NO row carries one; every NPC row carries one.
    no_rows = [r for r, m in matrix.items() if m["scorable"] == "NO"]
    check(
        all(
            BAD_MATRIX_REASON in build_report(None)["rows"][i]["explicit_reason"]
            for i, row in enumerate(build_report(None)["rows"])
            if row["row_id"] in no_rows
        ),
        "every matrix NO row carries an explicit no-route reason",
    )
    report = build_report(None)
    npc_rows = [r for r in report["rows"] if r["npc_dependent"]]
    check(
        bool(npc_rows) and all(r["explicit_reason"] for r in npc_rows),
        "every NPC-dependent row carries the measured unreachable reason",
    )
    check(
        {b for r in report["rows"] for b in r["beats"]} == set(BEAT_IDS),
        "report preserves the full 27-beat coverage",
    )

    # Token gate: nothing may be emitted without a played run.
    none_tokens = emit_tokens({"route_claim": "none"}, [])
    check(
        none_tokens["tokens_emitted"] == 0 and none_tokens["tokens"] == {},
        "staged/driver run emits zero tokens",
    )
    played_tokens = emit_tokens({"route_claim": "played"}, [])
    check(
        played_tokens["tokens_emitted"] == 0 and played_tokens["tokens"] == {},
        "played claim alone still emits no invented tokens",
    )
    check(
        all(t not in TOKEN_VOCAB for r in report["rows"] for t in [r["token"]] if t),
        "no row carries a PASS/DELTA/MISSING/HARD_LIMIT/N/A-route token",
    )

    ok = fails == 0
    print(
        "P0B_ROUTE_STATS_SELFTEST %s checks=%d fails=%d rows=%d beats=%d"
        % ("PASS" if ok else "FAIL", checks, fails, len(ROW_BEATS), len(BEAT_IDS))
    )
    return 0 if ok else 1


def summary(manifest: dict | None) -> int:
    report = build_report(manifest)
    print(
        "P0B_ROUTE_STATS rows=%d beats=%d rows_with_beats=%d rows_without=%d tokens_emitted=%d route_claim=%s"
        % (
            report["row_count"],
            report["beat_count"],
            report["rows_with_beats"],
            report["rows_without_beats"],
            report["tokens_emitted"],
            report["route_claim"],
        )
    )
    print(
        "P0B_ROUTE_STATS npc_measurement guards=%d civilians=%d nearest_m=%.1f unreachable=%s"
        % (
            NPC_MEASUREMENT["guards"],
            NPC_MEASUREMENT["civilians"],
            NPC_MEASUREMENT["nearest_m"],
            ",".join(NPC_MEASUREMENT["unreachable_beats"]),
        )
    )
    print("P0B_ROUTE_STATS token_policy %s" % report["token_policy"])
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        description="27-beat -> 120-row route scorer scaffold (emits no tokens without a played run)"
    )
    ap.add_argument(
        "--self-test",
        action="store_true",
        help="validate the mapping and the zero-token gate",
    )
    ap.add_argument(
        "--manifest", help="route driver/capture manifest to read (optional)"
    )
    ap.add_argument("--out", help="write the mapping report JSON here")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()

    manifest = None
    if args.manifest:
        p = Path(args.manifest)
        if not p.is_file():
            print("P0B_ROUTE_STATS FAIL: manifest not found: %s" % p, file=sys.stderr)
            return 1
        manifest = json.loads(p.read_text(encoding="utf-8"))
        manifest["_source"] = str(p)
    if args.out:
        report = build_report(manifest)
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(
            "P0B_ROUTE_STATS wrote %s rows=%d tokens_emitted=0"
            % (out, report["row_count"])
        )
    return summary(manifest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
