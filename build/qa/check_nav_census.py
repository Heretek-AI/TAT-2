#!/usr/bin/env python3
"""Independent navmesh link-direction census check (Phase 3 §3B.2).

Reads the producer's emitted *raw pair set* (`<map>.pairs.json`, one row per
authored off-mesh record) plus the manifest from a generated nav tree and
recomputes the cluster-wide signed-direction census **without** calling
`tools/parse_nav.link_census`. A cluster is bidirectional when its merged
records carry both +axis and -axis rows; the axis is any row's own direction,
so the count does not depend on the producer's sign convention.

The check pins, per map:

  * the logical link total, the raw record total and the pair total,
  * the recomputed bidirectional / one-way split (the census_version 2 truth:
    Guildhall 78/2, Old Manor 60/4, FTUE 4/0),
  * that every emitted row's `dir` agrees with its own sign,
  * that every cluster is a genuine authored parallel merge (|dot| >= 0.99,
    perpendicular <= 150 cm, overlapping along the direction),
  * that the `.nav.bin` link count and per-link bidirectional flags match the
    recomputed census, and the pairs-file sha256 matches the manifest,
  * that the legacy census_version 1 count is still recorded (35/15/0), so the
    correction is attributable rather than a silent flag flip.

Run against the shared generated tree (after the integrator's bake):

    python3 build/qa/check_nav_census.py

or against a temp bake (the worker must not write `game/data/generated`):

    python3 build/qa/check_nav_census.py --nav-dir /tmp/opencode/nav-gen
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_NAV_DIR = ROOT / "game" / "data" / "generated" / "nav"
PAIRS_SCHEMA = "tat2.nav_pairs/1"
MAGIC = b"TAT2NAV1"
MERGE_MIN_PARALLEL = 0.99
MERGE_MAX_PERP_CM = 150.0

# Authored totals measured by the N-P0 extractor run and the census_version 2
# producer. links/pairs/records are exact; bidir/one_way are exact too because
# the cluster grouping is deterministic on this authored data.
EXPECT = {
    "guildhall": {
        "links": 80,
        "bidirectional": 78,
        "one_way": 2,
        "pairs": 123,
        "records": 221,
        "legacy_bidirectional": 35,
    },
    "old_manor": {
        "links": 64,
        "bidirectional": 60,
        "one_way": 4,
        "pairs": 113,
        "records": 216,
        "legacy_bidirectional": 15,
    },
    "ftue": {
        "links": 4,
        "bidirectional": 4,
        "one_way": 0,
        "pairs": 8,
        "records": 11,
        "legacy_bidirectional": 0,
    },
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def vec(row: dict, key: str) -> tuple[float, float, float]:
    v = row.get(key)
    if not isinstance(v, list) or len(v) != 3:
        raise ValueError(f"row {key} is not 3 numbers: {v!r}")
    return (float(v[0]), float(v[1]), float(v[2]))


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def norm(a):
    return math.sqrt(dot(a, a))


def unit(a):
    n = norm(a)
    return (a[0] / n, a[1] / n, a[2] / n) if n > 0 else None


def read_bin_links(path: Path) -> tuple[int, list[dict]]:
    """Return (declared link count, per-link {a, b, bidirectional})."""
    data = path.read_bytes()
    if data[:8] != MAGIC:
        raise ValueError(f"{path}: bad magic")
    _ver, verts, polys, links = struct.unpack_from("<IIII", data, 8)
    off = 24 + verts * 12
    for _ in range(polys):
        n = data[off]
        off += 1 + 2 * n
    off += polys  # one area byte per polygon
    out: list[dict] = []
    for _ in range(links):
        a = struct.unpack_from("<iii", data, off)
        b = struct.unpack_from("<iii", data, off + 12)
        off += 24  # a + b
        off += 4  # radius + height
        bidir = data[off]
        off += 4  # bidir, flags, records
        out.append({"a": a, "b": b, "bidirectional": bidir})
    if off != len(data):
        raise ValueError(f"{path}: trailing bytes {off} != {len(data)}")
    return links, out


def check_map(nav_dir: Path, map_id: str, expect: dict) -> list[str]:
    problems: list[str] = []

    def bad(msg: str) -> None:
        problems.append(f"{map_id}: {msg}")

    manifest_path = nav_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("census", {}).get("version") != 2:
        bad(f"manifest census.version != 2 ({manifest.get('census')!r})")
    entry = manifest.get("maps", {}).get(map_id)
    if not isinstance(entry, dict):
        bad("manifest has no map entry")
        return problems
    if int(entry.get("census_version", -1)) != 2:
        bad(f"entry census_version != 2 ({entry.get('census_version')!r})")

    pairs_name = str(entry.get("pairs_file", ""))
    if not pairs_name:
        bad("entry has no pairs_file")
        return problems
    pairs_path = nav_dir / pairs_name
    if not pairs_path.is_file():
        bad(f"missing raw pair set {pairs_path}")
        return problems
    if entry.get("pairs_sha256") and sha256_file(pairs_path) != entry["pairs_sha256"]:
        bad("pairs_sha256 does not match the emitted pair set")

    pairs = json.loads(pairs_path.read_text(encoding="utf-8"))
    if pairs.get("schema") != PAIRS_SCHEMA:
        bad(f"pairs schema {pairs.get('schema')!r} != {PAIRS_SCHEMA}")
    if str(pairs.get("map", "")) != map_id:
        bad(f"pairs map {pairs.get('map')!r} != {map_id}")
    rows = pairs.get("pair_set")
    if not isinstance(rows, list) or not rows:
        bad("pairs pair_set missing/empty")
        return problems

    records = len(rows)
    if records != int(entry.get("raw_offmesh", -1)):
        bad(f"pair rows {records} != manifest raw_offmesh {entry.get('raw_offmesh')}")
    if records != int(pairs.get("records", -1)):
        bad(f"pair rows {records} != pairs.records {pairs.get('records')}")
    if int(entry.get("offmesh_pairs", -1)) != int(pairs.get("pairs", -2)):
        bad("manifest offmesh_pairs and pairs.pairs disagree")

    by_link: dict[int, list[dict]] = {}
    for row in rows:
        try:
            lid = int(row["link"])
            vec(row, "a")
            vec(row, "b")
        except (KeyError, TypeError, ValueError) as e:
            bad(f"malformed pair row: {e}")
            continue
        by_link.setdefault(lid, []).append(row)

    if sorted(by_link) != list(range(int(entry.get("links", 0)))):
        bad(
            f"pair-set link ids are not 0..links-1 "
            f"(got {len(by_link)} ids, entry.links={entry.get('links')})"
        )

    links = int(entry.get("links", -1))
    bin_path = nav_dir / str(entry.get("file", ""))
    declared_links, bin_links = read_bin_links(bin_path)
    if declared_links != links:
        bad(f"binary link count {declared_links} != manifest {links}")
    if len(bin_links) != len(by_link):
        bad(f"pair-set links {len(by_link)} != binary links {len(bin_links)}")

    bidirectional = 0
    for lid, cluster in sorted(by_link.items()):
        if lid >= len(bin_links):
            bad(f"link {lid}: no binary link row")
            continue
        # Orientation reference: the emitted binary link direction (nav cm).
        la = tuple(float(v) for v in bin_links[lid]["a"])
        lb = tuple(float(v) for v in bin_links[lid]["b"])
        axis = unit(sub(lb, la))
        if axis is None:
            bad(f"link {lid}: zero-length binary link")
            continue
        fwd = rev = 0
        for row in cluster:
            a = vec(row, "a")
            b = vec(row, "b")
            d = dot(sub(b, a), axis)
            if abs(d) < 1e-9:
                bad(f"link {lid}: a merged copy is perpendicular to the link axis")
                continue
            fwd += 1 if d > 0 else 0
            rev += 1 if d < 0 else 0
            declared = str(row.get("dir", ""))
            if declared not in ("forward", "reverse"):
                bad(f"link {lid}: row dir {declared!r} is not forward/reverse")
            elif declared != ("forward" if d > 0 else "reverse"):
                bad(
                    f"link {lid}: row dir {declared!r} disagrees with the emitted "
                    "link direction"
                )
            # The merge rule must hold: parallel, <=150 cm apart, overlapping.
            v = unit(sub(b, a))
            if v is None or abs(dot(axis, v)) < MERGE_MIN_PARALLEL:
                bad(f"link {lid}: a merged copy is not parallel to the link axis")
                continue
            if norm(cross(axis, sub(la, a))) > MERGE_MAX_PERP_CM:
                bad(
                    f"link {lid}: a merged copy is >{MERGE_MAX_PERP_CM} cm perpendicular"
                )
            t0 = sorted((dot(la, axis), dot(lb, axis)))
            t1 = sorted((dot(a, axis), dot(b, axis)))
            if max(t0[0], t1[0]) - min(t0[1], t1[1]) > 0.0:
                bad(f"link {lid}: merged copies do not overlap along the direction")
        is_bidirectional = fwd > 0 and rev > 0
        if fwd + rev == 0:
            bad(f"link {lid}: cluster has no directional record")
        if is_bidirectional:
            bidirectional += 1
            if fwd == 0 or rev == 0:
                bad(f"link {lid}: bidirectional without both directions")
        if bool(bin_links[lid]["bidirectional"]) != is_bidirectional:
            bad(
                f"link {lid}: binary bidirectional flag "
                f"{bin_links[lid]['bidirectional']} != recomputed {int(is_bidirectional)}"
            )

    one_way = links - bidirectional
    if links != expect["links"]:
        bad(f"logical links {links} != {expect['links']}")
    if bidirectional != expect["bidirectional"]:
        bad(f"bidirectional {bidirectional} != {expect['bidirectional']}")
    if one_way != expect["one_way"]:
        bad(f"one-way {one_way} != {expect['one_way']}")
    if records != expect["records"]:
        bad(f"raw records {records} != {expect['records']}")
    if int(entry.get("offmesh_pairs", -1)) != expect["pairs"]:
        bad(f"offmesh pairs {entry.get('offmesh_pairs')} != {expect['pairs']}")
    if int(entry.get("links_bidirectional", -1)) != bidirectional:
        bad(
            f"manifest links_bidirectional {entry.get('links_bidirectional')} "
            f"!= recomputed {bidirectional}"
        )
    if int(entry.get("links_one_way", -1)) != one_way:
        bad(
            f"manifest links_one_way {entry.get('links_one_way')} != recomputed {one_way}"
        )
    legacy = int(entry.get("links_bidirectional_legacy_canonical", -1))
    if legacy != expect["legacy_bidirectional"]:
        bad(
            f"legacy canonical census {legacy} != {expect['legacy_bidirectional']} "
            "(the correction must stay recorded)"
        )

    if not problems:
        print(
            f"NAV_CENSUS {map_id}: links={links} bidirectional={bidirectional} "
            f"one_way={one_way} legacy={legacy} records={records} "
            f"pairs={entry.get('offmesh_pairs')} bin_flags_ok=1"
        )
    return problems


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--nav-dir",
        default=str(DEFAULT_NAV_DIR),
        help="generated nav directory holding manifest.json + <map>.pairs.json",
    )
    args = ap.parse_args(argv)
    nav_dir = Path(args.nav_dir)
    if not (nav_dir / "manifest.json").is_file():
        print(
            f"NAV_CENSUS: SKIP: {nav_dir}/manifest.json is missing; run the "
            "extractor 'nav' stage and tools/parse_nav.py first",
            file=sys.stderr,
        )
        return 2

    problems: list[str] = []
    for map_id, expect in EXPECT.items():
        problems.extend(check_map(nav_dir, map_id, expect))
    if problems:
        for p in problems:
            print(f"NAV_CENSUS FAIL: {p}")
        print(f"NAV_CENSUS_SUMMARY: FAIL problems={len(problems)}")
        return 1
    print(
        "NAV_CENSUS_SUMMARY: PASS maps=3 "
        "bidirectional=78/60/4 one_way=2/4/0 legacy=35/15/0"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
