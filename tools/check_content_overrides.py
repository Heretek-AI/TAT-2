#!/usr/bin/env python3
"""Validate the tracked graybox content-override table and its output.

`game/data/expansion/content_overrides.json` is the W6T replacement for
map/loader special cases: `tools/parse_tables.py` re-materialises graybox kit
meshes from this table before writing each `.tatlevel.json`. This checker is
the independent gate. It exits 0 only when:

* every rule's `expect_count` / `expect_changed` matches both the applied
  report written by the producer and the final `.tatlevel.json` selection;
* no two rules select the same mesh instance in a level (overlap);
* every rewritten instance carries the rule's authored material and no rule is
  a no-op (a rule that matches nothing, or rewrites nothing, fails);
* only graybox kit meshes (`GB_*` under the declared prefixes) are touched;
* every coverage region (MissionLobby roof decks, POI Lounge, Entrance Hall,
  Ceremonial Chambers/Prison vault and the POI 3rd floor) has zero graybox
  `GB_Floor_2x2` instances left without an authored override;
* no `add_cap` touches a W5B roof-census level.

`--table-only` validates the tracked table alone (no private generated data);
it is the mode the hosted tooling job can run.

Generated `.tatlevel.json` and the report are gitignored; this checker and the
producer are the repo's gate for them.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "game" / "data" / "expansion" / "content_overrides.json"
LEVELS = ROOT / "game" / "data" / "generated" / "levels"
REPORT = ROOT / "game" / "data" / "generated" / "content_overrides_applied.json"
MATERIALS = ROOT / "game" / "data" / "generated" / "materials.json"

SCHEMA = "tat2.content_overrides/1"
APPLIED_SCHEMA = "tat2.content_overrides.applied/1"

fails: list[str] = []


def fail(msg: str) -> None:
    fails.append(msg)
    print(f"FAIL: {msg}")


def ok(msg: str) -> None:
    print(f"PASS: {msg}")


def load_json(path: Path):
    return json.loads(path.read_text())


def in_bbox(pos, bbox) -> bool:
    if not bbox:
        return True
    try:
        x, y, z = (float(v) for v in pos[:3])
    except (TypeError, ValueError):
        return False
    return (
        float(bbox[0]) <= x <= float(bbox[3])
        and float(bbox[1]) <= y <= float(bbox[4])
        and float(bbox[2]) <= z <= float(bbox[5])
    )


def rule_matches(entry: dict, rule: dict) -> bool:
    mesh = str(entry.get("mesh") or "")
    if mesh not in (rule.get("meshes") or []):
        return False
    return in_bbox(entry.get("pos") or (0.0, 0.0, 0.0), rule.get("bbox"))


def check_table(table: dict, graybox: tuple[str, ...], materials: dict | None) -> None:
    if table.get("schema") != SCHEMA:
        fail(f"table schema is {table.get('schema')!r}, expected {SCHEMA}")
        return
    if not graybox:
        fail("table declares no graybox_prefixes")
    ids: set[str] = set()
    for rule in table.get("rules") or []:
        rid = str(rule.get("id") or "")
        if not rid:
            fail("a rule has no id")
            continue
        if rid in ids:
            fail(f"duplicate rule id {rid}")
        ids.add(rid)
        if rule.get("op") != "set_material":
            fail(
                f"{rid}: unsupported op {rule.get('op')!r} (only set_material/add_cap)"
            )
        meshes = rule.get("meshes") or []
        if not meshes:
            fail(f"{rid}: no meshes")
        for mesh in meshes:
            if graybox and not str(mesh).startswith(graybox):
                fail(f"{rid}: non-graybox mesh {mesh}")
        material = str(rule.get("material") or "")
        if not material.startswith("/Game/"):
            fail(f"{rid}: malformed material {material!r}")
        elif materials is not None and material not in materials:
            fail(f"{rid}: material {material} is not in materials.json")
        count = rule.get("expect_count")
        changed = rule.get("expect_changed", count)
        if not isinstance(count, int) or count <= 0:
            fail(f"{rid}: expect_count must be a positive int")
        if (
            not isinstance(changed, int)
            or changed < 0
            or (isinstance(count, int) and changed > count)
        ):
            fail(f"{rid}: expect_changed {changed!r} is out of range for {count!r}")
        if changed == 0 and not rule.get("allow_noop"):
            fail(f"{rid}: would be a no-op (expect_changed=0)")
        if not rule.get("levels"):
            fail(f"{rid}: no levels")
        bbox = rule.get("bbox")
        if bbox is not None and (not isinstance(bbox, list) or len(bbox) != 6):
            fail(f"{rid}: bbox must be [x0,y0,z0,x1,y1,z1]")
    if not (table.get("rules") or []):
        fail("table has no rules")

    cap_ids: set[str] = set()
    census = set(table.get("roof_census_levels") or [])
    for cap in table.get("add_caps") or []:
        cid = str(cap.get("id") or "")
        if not cid:
            fail("an add_cap has no id")
            continue
        if cid in ids or cid in cap_ids:
            fail(f"duplicate rule/cap id {cid}")
        cap_ids.add(cid)
        if graybox and not str(cap.get("mesh") or "").startswith(graybox):
            fail(f"{cid}: add_cap targets a non-graybox mesh")
        if len(cap.get("pos") or []) != 3:
            fail(f"{cid}: add_cap needs a 3-component pos")
        if int(cap.get("expect_count", 0)) <= 0:
            fail(f"{cid}: add_cap needs a positive expect_count")
        caps = cap.get("caps") or []
        if len(caps) != int(cap.get("expect_count", -1)):
            fail(
                f"{cid}: declares {len(caps)} caps, expect_count={cap.get('expect_count')}"
            )
        for lvl in cap.get("levels") or []:
            if lvl in census:
                fail(f"{cid}: add_cap may not touch roof-census level {lvl}")
        for spec in caps:
            material = str(spec.get("material") or "")
            if materials is not None and material not in materials:
                fail(f"{cid}: cap material {material} is not in materials.json")

    rule_levels = {
        lvl for rule in table.get("rules") or [] for lvl in rule.get("levels") or []
    }
    for region in table.get("coverage_regions") or []:
        rid = str(region.get("id") or "")
        if not rid:
            fail("a coverage_region has no id")
        if not region.get("meshes"):
            fail(f"coverage region {rid}: no meshes")
        for mesh in region.get("meshes") or []:
            if graybox and not str(mesh).startswith(graybox):
                fail(f"coverage region {rid}: non-graybox mesh {mesh}")
        for lvl in region.get("levels") or []:
            if lvl not in rule_levels:
                fail(f"coverage region {rid}: level {lvl} has no override rule")
        bbox = region.get("bbox")
        if bbox is not None and (not isinstance(bbox, list) or len(bbox) != 6):
            fail(f"coverage region {rid}: bbox must be 6 numbers")


def check_applied(table: dict, materials: dict, mesh_mats: dict) -> None:
    if not LEVELS.exists():
        fail(f"missing generated levels at {LEVELS} (run make normalize)")
        return
    if not REPORT.exists():
        fail(f"missing applied report {REPORT} (run tools/parse_tables.py)")
        return
    report = load_json(REPORT)
    if report.get("schema") != APPLIED_SCHEMA:
        fail(f"applied report schema is {report.get('schema')!r}")
        return
    rows = {str(r.get("id")): r for r in report.get("rules") or []}
    rules = table.get("rules") or []
    rule_ids = {str(r["id"]) for r in rules}
    cap_ids = {str(c["id"]) for c in table.get("add_caps") or []}
    if set(rows) != rule_ids | cap_ids:
        fail(
            "applied report rules differ from the table: "
            f"missing={sorted((rule_ids | cap_ids) - set(rows))} "
            f"extra={sorted(set(rows) - (rule_ids | cap_ids))}"
        )
    payload_cache: dict[str, dict] = {}
    total_matched = total_changed = 0
    for rule in rules:
        rid = str(rule["id"])
        row = rows.get(rid)
        if row is None:
            continue
        count = int(rule["expect_count"])
        changed = int(rule.get("expect_changed", count))
        total_matched += count
        total_changed += changed
        level_key = str(row.get("level"))
        if level_key not in (rule.get("levels") or []):
            fail(f"{rid}: report level {level_key} is not declared by the rule")
            continue
        if int(row.get("matched", -1)) != count:
            fail(f"{rid}: report matched {row.get('matched')}, table says {count}")
        if int(row.get("changed", -1)) != changed:
            fail(f"{rid}: report changed {row.get('changed')}, table says {changed}")
        payload = payload_cache.get(level_key)
        if payload is None:
            path = LEVELS / f"{level_key}.tatlevel.json"
            if not path.exists():
                fail(f"{rid}: missing level payload {path.relative_to(ROOT)}")
                continue
            payload = load_json(path)
            payload_cache[level_key] = payload
        selected = [
            idx
            for idx, entry in enumerate(payload.get("meshes") or [])
            if isinstance(entry, dict) and rule_matches(entry, rule)
        ]
        if len(selected) != count:
            fail(
                f"{rid}: final payload selects {len(selected)} instances, expected {count}"
            )
        tagged = [
            entry
            for entry in payload.get("meshes") or []
            if isinstance(entry, dict) and entry.get("content_rule") == rid
        ]
        if len(tagged) != changed:
            fail(
                f"{rid}: {len(tagged)} instances carry content_rule, expected {changed}"
            )
        material = str(rule["material"])
        slots = len(mesh_mats.get(str(rule["meshes"][0]).split(".")[0], []) or []) or 1
        for entry in tagged:
            if entry.get("override_material") != material:
                fail(
                    f"{rid}: {entry.get('mesh')} at {entry.get('pos')} has "
                    f"{entry.get('override_material')!r}, expected {material}"
                )
                break
            ov = entry.get("override_materials")
            if not isinstance(ov, list) or ov != [material] * max(1, len(ov) or slots):
                fail(f"{rid}: override_materials slots are not all {material}")
                break
        for idx in selected:
            entry = payload["meshes"][idx]
            if not (entry.get("override_material") or ""):
                fail(
                    f"{rid}: selected {entry.get('mesh')} at {entry.get('pos')} "
                    "still has no authored override"
                )
                break
        print(f"  {rid}: matched={count} changed={changed} level={level_key}")

    # Overlap is a producer error, but verify independently from final data.
    for level_key, payload in payload_cache.items():
        claimed: dict[int, str] = {}
        for rule in table.get("rules") or []:
            if level_key not in (rule.get("levels") or []):
                continue
            for idx, entry in enumerate(payload.get("meshes") or []):
                if not isinstance(entry, dict) or not rule_matches(entry, rule):
                    continue
                other = claimed.get(idx)
                if other is not None and other != rule["id"]:
                    fail(
                        f"rules {other} and {rule['id']} overlap in {level_key} "
                        f"at mesh index {idx}"
                    )
                    break
                claimed[idx] = str(rule["id"])

    # Only tagged graybox meshes may be rewritten.
    graybox = tuple(table.get("graybox_prefixes") or ())
    for level_key, payload in payload_cache.items():
        for entry in payload.get("meshes") or []:
            if not isinstance(entry, dict) or not entry.get("content_rule"):
                continue
            if graybox and not str(entry.get("mesh") or "").startswith(graybox):
                fail(
                    f"{level_key}: {entry.get('content_rule')} rewrote non-graybox "
                    f"mesh {entry.get('mesh')}"
                )

    # P0 / 3rd-floor coverage: no graybox floor left un-materialed.
    for region in table.get("coverage_regions") or []:
        rid = str(region["id"])
        left = 0
        scanned = 0
        for level_key in region.get("levels") or []:
            payload = payload_cache.get(level_key)
            if payload is None:
                path = LEVELS / f"{level_key}.tatlevel.json"
                if not path.exists():
                    fail(f"coverage region {rid}: missing level {level_key}")
                    continue
                payload = load_json(path)
                payload_cache[level_key] = payload
            for entry in payload.get("meshes") or []:
                if not isinstance(entry, dict):
                    continue
                if str(entry.get("mesh") or "") not in (region.get("meshes") or []):
                    continue
                if not in_bbox(entry.get("pos") or (0.0, 0.0, 0.0), region.get("bbox")):
                    continue
                scanned += 1
                if not (entry.get("override_material") or ""):
                    left += 1
        if scanned == 0:
            fail(f"coverage region {rid}: no instances found (selector drift)")
        elif left:
            fail(f"coverage region {rid}: {left} graybox floor(s) left un-materialed")
        else:
            ok(f"coverage {rid}: 0 graybox floors left ({scanned} scanned)")

    # add_cap: each declared cap exists with its material.
    for cap in table.get("add_caps") or []:
        cid = str(cap["id"])
        for level_key in cap.get("levels") or []:
            payload = payload_cache.get(level_key)
            if payload is None:
                path = LEVELS / f"{level_key}.tatlevel.json"
                if not path.exists():
                    fail(f"add_cap {cid}: missing level {level_key}")
                    continue
                payload = load_json(path)
                payload_cache[level_key] = payload
            for spec in cap.get("caps") or []:
                found = [
                    e
                    for e in payload.get("meshes") or []
                    if isinstance(e, dict)
                    and e.get("mesh") == spec.get("mesh")
                    and e.get("pos") == [float(v) for v in spec["pos"]]
                    and e.get("content_rule") == cid
                    and e.get("override_material") == spec.get("material")
                ]
                if len(found) != 1:
                    fail(
                        f"add_cap {cid}: {spec.get('mesh')} at {spec.get('pos')} not applied"
                    )
        print(f"  {cid}: add_cap checked")

    print(
        f"Content override totals: {len(rules)} set_material rules, "
        f"{total_matched} matched, {total_changed} re-materialised, "
        f"{len(table.get('add_caps') or [])} add_cap rules"
    )


def plot_counts(table: dict) -> None:
    print("Override rule table:")
    for rule in table.get("rules") or []:
        print(
            f"  {rule['id']:42s} {rule.get('expect_count'):5d} / "
            f"{rule.get('expect_changed', 0):5d}  {rule.get('material', '').rsplit('/', 1)[-1]}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--table-only",
        action="store_true",
        help="validate the tracked table only (no private generated data)",
    )
    args = parser.parse_args()

    if not TABLE.exists():
        print(f"FAIL: missing tracked override table {TABLE.relative_to(ROOT)}")
        return 1
    table = load_json(TABLE)
    graybox = tuple(table.get("graybox_prefixes") or ())
    materials = load_json(MATERIALS) if MATERIALS.exists() else None
    mesh_mats = (
        load_json(ROOT / "game" / "data" / "generated" / "mesh_materials.json")
        if (ROOT / "game" / "data" / "generated" / "mesh_materials.json").exists()
        else {}
    )
    check_table(table, graybox, materials)
    plot_counts(table)
    if not args.table_only:
        check_applied(table, materials or {}, mesh_mats)
    else:
        print("Table-only mode: generated-data checks skipped.")

    if fails:
        print(f"\nCONTENT_OVERRIDES: FAIL ({len(fails)} problem(s))")
        return 1
    print("\nCONTENT_OVERRIDES: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
