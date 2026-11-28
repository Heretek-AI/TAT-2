#!/usr/bin/env python3
"""Fail-closed tests for tools/parse_nav.py (no Godot, no extracted data).

Each case writes a tiny synthetic `tat2.nav_tiles/1` dump under a temp dir and
runs the producer. The positive case also pins the merge rule: two parallel
copies 100 cm apart plus the reverse direction collapse to one bidirectional
logical link.

`parallel reverse` is the Phase 3 §3B.2 census regression: a reverse copy whose
endpoints were moved by the tile/poly split (so it is not the exact canonical
reverse) made census_version 1 read a bidirectional link as one-way. The case
asserts the cluster-wide census reads bidirectional **and** that the legacy
canonical count is still emitted as 0, so the failure mode cannot come back
silently. The real-data totals (Guildhall 78/2, Old Manor 60/4, FTUE 4/0) are
recomputed independently from the emitted raw pair set by
`build/qa/check_nav_census.py`; this file stays extracted-data-free.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PARSER = ROOT / "tools" / "parse_nav.py"
MAP_JSON = "Maps/Guildhall/Guildhall_P.json"

AREAS = [
    {"id": 0, "class": "NavArea_Null"},
    {"id": 62, "class": "NavArea_LowHeight"},
    {"id": 63, "class": "NavArea_Default"},
    {"id": 1, "class": "NavArea_Obstacle"},
    {"id": 2, "class": "NavArea_PrivateArea_C"},
    {"id": 3, "class": "NavArea_Bushes_C"},
    {"id": 4, "class": "NavArea_Door_C"},
    {"id": 5, "class": "NavArea_BlockPhysical_C"},
]


def base_doc() -> dict:
    return {
        "schema": "tat2.nav_tiles/1",
        "tile_count": 1,
        "poly_count_total": 5,
        "vert_count_total": 4,
        "offmesh_connection_total": 3,
        "supported_areas": AREAS,
        "nav_data_config": {
            "agent_radius_cm": 45.0,
            "agent_height_cm": 240.0,
            "agent_step_height_cm": 45.0,
        },
        "max_poly_verts": 3,
        "tile_width_cm": 988.0,
        "tile_height_cm": 988.0,
        "walkable_height_cm": 240.0,
        "walkable_radius_cm": 45.0,
        "walkable_climb_cm": 45.0,
        "tiles": [
            {
                "tx": 0,
                "ty": 0,
                "verts": [
                    0.0,
                    0.0,
                    0.0,
                    100.0,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    100.0,
                    100.0,
                    0.0,
                    100.0,
                ],
                "polys": [[0, 1, 2], [1, 3, 2]],
                "poly_flags": [1, 1],
                "poly_areas": [63, 4],
                "offmesh": [
                    # one physical link: forward/back copies plus a parallel copy
                    {
                        "a": [0.0, 0.0, 0.0],
                        "b": [0.0, 0.0, 300.0],
                        "radius": 100.0,
                        "height": 100.0,
                        "flags": 64,
                    },
                    {
                        "a": [0.0, 0.0, 300.0],
                        "b": [0.0, 0.0, 0.0],
                        "radius": 100.0,
                        "height": 100.0,
                        "flags": 64,
                    },
                    {
                        "a": [100.0, 0.0, 0.0],
                        "b": [100.0, 0.0, 300.0],
                        "radius": 100.0,
                        "height": 100.0,
                        "flags": 64,
                    },
                ],
            }
        ],
    }


def run_case(name: str, doc: dict, expect_ok: bool, expect: str = "") -> int:
    with tempfile.TemporaryDirectory(prefix="parse-nav-test-") as tmp:
        root = Path(tmp)
        src = root / "in" / MAP_JSON
        src.parent.mkdir(parents=True)
        src.write_text(json.dumps(doc), encoding="utf-8")
        out = root / "out"
        cp = subprocess.run(
            [
                sys.executable,
                str(PARSER),
                "--input",
                str(root / "in"),
                "--out",
                str(out),
                "--maps",
                "guildhall",
            ],
            text=True,
            capture_output=True,
        )
        if expect_ok:
            if cp.returncode != 0:
                print(f"FAIL {name}: expected exit 0, got {cp.returncode}\n{cp.stderr}")
                return 1
            manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
            entry = manifest["maps"]["guildhall"]
            if entry["links"] != 1 or entry["links_bidirectional"] != 1:
                print(
                    f"FAIL {name}: merge expected 1 bidirectional link, got {entry['links']}/{entry['links_bidirectional']}"
                )
                return 1
            if entry["polys"] != 2 or entry["verts"] != 4:
                print(f"FAIL {name}: counts {entry['polys']}/{entry['verts']}")
                return 1
            if entry.get("census_version") != 2:
                print(f"FAIL {name}: census_version {entry.get('census_version')}")
                return 1
            pairs = json.loads(
                (out / "guildhall.pairs.json").read_text(encoding="utf-8")
            )
            if len(pairs.get("pair_set", [])) != 3 or pairs.get("records") != 3:
                print(
                    f"FAIL {name}: raw pair set rows={len(pairs.get('pair_set', []))} "
                    f"records={pairs.get('records')}"
                )
                return 1
            if entry.get("pairs_sha256") != __import__("hashlib").sha256(
                (out / "guildhall.pairs.json").read_bytes()
            ).hexdigest():
                print(f"FAIL {name}: pairs_sha256 does not match the emitted file")
                return 1
            print(f"PASS {name}")
            return 0
        if cp.returncode == 0:
            print(f"FAIL {name}: expected a refusal, got exit 0")
            return 1
        if expect and expect not in cp.stderr:
            print(f"FAIL {name}: expected {expect!r} in stderr, got:\n{cp.stderr}")
            return 1
        print(f"PASS {name}")
        return 0


def run_oneway_case() -> int:
    """A one-way record must keep its authored A->B direction (300 -> 0)."""
    import struct

    doc = base_doc()
    doc["poly_count_total"] = 3
    doc["offmesh_connection_total"] = 1
    doc["tiles"][0]["offmesh"] = [
        {
            "a": [0.0, 0.0, 300.0],
            "b": [0.0, 0.0, 0.0],
            "radius": 100.0,
            "height": 100.0,
            "flags": 64,
        }
    ]
    with tempfile.TemporaryDirectory(prefix="parse-nav-oneway-") as tmp:
        root = Path(tmp)
        src = root / "in" / MAP_JSON
        src.parent.mkdir(parents=True)
        src.write_text(json.dumps(doc), encoding="utf-8")
        out = root / "out"
        cp = subprocess.run(
            [
                sys.executable,
                str(PARSER),
                "--input",
                str(root / "in"),
                "--out",
                str(out),
                "--maps",
                "guildhall",
            ],
            text=True,
            capture_output=True,
        )
        if cp.returncode != 0:
            print(f"FAIL one-way direction: exit {cp.returncode}\n{cp.stderr}")
            return 1
        entry = json.loads((out / "manifest.json").read_text(encoding="utf-8"))["maps"][
            "guildhall"
        ]
        if entry["links"] != 1 or entry["links_one_way"] != 1:
            print(f"FAIL one-way direction: {entry['links']}/{entry['links_one_way']}")
            return 1
        if entry.get("census_version") != 2 or entry.get("links_bidirectional_legacy_canonical") != 0:
            print(
                "FAIL one-way direction: census fields "
                f"{entry.get('census_version')}/{entry.get('links_bidirectional_legacy_canonical')}"
            )
            return 1
        pairs = json.loads((out / "guildhall.pairs.json").read_text(encoding="utf-8"))
        if [r.get("dir") for r in pairs.get("pair_set", [])] != ["forward"]:
            print(f"FAIL one-way direction: pair rows {pairs.get('pair_set')}")
            return 1
        data = (out / "guildhall.nav.bin").read_bytes()
        o = 8
        _ver, vc, pc, lc = struct.unpack_from("<IIII", data, o)
        o += 16 + vc * 12
        for _ in range(pc):
            n = data[o]
            o += 1 + 2 * n
        o += pc
        a = struct.unpack_from("<iii", data, o)
        b = struct.unpack_from("<iii", data, o + 12)
        if a != (0, 0, 300) or b != (0, 0, 0):
            print(f"FAIL one-way direction: got {a}->{b}")
            return 1
        print("PASS one-way direction")
        return 0


def produce(doc: dict):
    """Run the producer on `doc`; return (completed, entry, pairs, bin bytes)."""
    with tempfile.TemporaryDirectory(prefix="parse-nav-test-") as tmp:
        root = Path(tmp)
        src = root / "in" / MAP_JSON
        src.parent.mkdir(parents=True)
        src.write_text(json.dumps(doc), encoding="utf-8")
        out = root / "out"
        cp = subprocess.run(
            [
                sys.executable,
                str(PARSER),
                "--input",
                str(root / "in"),
                "--out",
                str(out),
                "--maps",
                "guildhall",
            ],
            text=True,
            capture_output=True,
        )
        if cp.returncode != 0:
            return cp, None, None, None
        entry = json.loads((out / "manifest.json").read_text(encoding="utf-8"))["maps"][
            "guildhall"
        ]
        pairs = json.loads((out / "guildhall.pairs.json").read_text(encoding="utf-8"))
        return cp, entry, pairs, (out / "guildhall.nav.bin").read_bytes()


def run_parallel_reverse_case() -> int:
    """Cluster-wide census: a reverse copy with different endpoints is counted."""
    doc = base_doc()
    doc["poly_count_total"] = 4
    doc["offmesh_connection_total"] = 2
    doc["tiles"][0]["offmesh"] = [
        # canonical A -> B
        {
            "a": [0.0, 0.0, 0.0],
            "b": [0.0, 0.0, 300.0],
            "radius": 100.0,
            "height": 100.0,
            "flags": 64,
        },
        # the same physical link, reversed and shifted 100 cm by the poly split:
        # census_version 1 saw no exact (b, a) record and called it one-way.
        {
            "a": [100.0, 0.0, 300.0],
            "b": [100.0, 0.0, 0.0],
            "radius": 100.0,
            "height": 100.0,
            "flags": 64,
        },
    ]
    cp, entry, pairs, data = produce(doc)
    if entry is None:
        print(f"FAIL parallel reverse census: exit {cp.returncode}\n{cp.stderr}")
        return 1
    if entry["census_version"] != 2:
        print(f"FAIL parallel reverse census: census_version {entry['census_version']}")
        return 1
    if (entry["links"], entry["links_bidirectional"], entry["links_one_way"]) != (1, 1, 0):
        print(
            "FAIL parallel reverse census: expected 1 link / 1 bidirectional / "
            f"0 one-way, got {entry['links']}/{entry['links_bidirectional']}/"
            f"{entry['links_one_way']}"
        )
        return 1
    if entry["links_bidirectional_legacy_canonical"] != 0:
        print(
            "FAIL parallel reverse census: legacy canonical count must stay 0 "
            f"(got {entry['links_bidirectional_legacy_canonical']})"
        )
        return 1
    if pairs.get("schema") != "tat2.nav_pairs/1" or len(pairs.get("pair_set", [])) != 2:
        print(f"FAIL parallel reverse census: bad raw pair set {pairs.get('schema')}")
        return 1
    rows = pairs["pair_set"]
    if {r["link"] for r in rows} != {0} or {r["dir"] for r in rows} != {
        "forward",
        "reverse",
    }:
        print(f"FAIL parallel reverse census: pair rows {rows}")
        return 1
    if pairs["links_bidirectional"] != 1 or pairs["records"] != 2:
        print(f"FAIL parallel reverse census: pairs totals {pairs['links_bidirectional']}")
        return 1
    # The binary must carry the census result too (link 0, one-way flag == 0).
    import struct

    o = 8
    _ver, vc, pc, lc = struct.unpack_from("<IIII", data, o)
    o += 16 + vc * 12
    for _ in range(pc):
        n = data[o]
        o += 1 + 2 * n
    o += pc
    a = struct.unpack_from("<iii", data, o)
    b = struct.unpack_from("<iii", data, o + 12)
    bidir = data[o + 28]
    if lc != 1 or bidir != 1:
        print(f"FAIL parallel reverse census: binary links={lc} bidir={bidir} {a}->{b}")
        return 1
    print("PASS parallel reverse census (cluster-wide signed directions)")
    return 0


def main() -> int:
    cases = []

    doc = base_doc()
    cases.append(run_case("positive merge + per-map areas", doc, True))

    doc = base_doc()
    doc.pop("supported_areas")
    cases.append(run_case("missing supported_areas", doc, False, "supported_areas"))

    doc = base_doc()
    doc["supported_areas"] = [dict(a) for a in AREAS]
    for a in doc["supported_areas"]:
        if a["id"] == 63:
            a["class"] = "NavArea_Null"
    cases.append(run_case("area 63 is not Default", doc, False, "area 63"))

    doc = base_doc()
    doc["tiles"][0]["polys"][0] = [0, 1, 2, 0, 1, 2, 3]
    cases.append(run_case("7-vertex poly", doc, False, "> 6"))

    doc = base_doc()
    doc["tiles"][0]["poly_areas"][0] = 0
    cases.append(run_case("NavArea_Null poly", doc, False, "area 0"))

    doc = base_doc()
    doc["nav_data_config"].pop("agent_height_cm")
    cases.append(run_case("missing nav_data_config", doc, False, "nav_data_config"))

    cases.append(run_oneway_case())
    cases.append(run_parallel_reverse_case())

    return 0 if all(c == 0 for c in cases) else 1


if __name__ == "__main__":
    sys.exit(main())
