#!/usr/bin/env python3
"""
Emit the compact runtime navmesh asset from the extractor's `nav` dump.

Input:  extracted/nav/<map>.json  (tools/tat-extract `nav`, schema tat2.nav_tiles/1)
Output: game/data/generated/nav/manifest.json
        game/data/generated/nav/<map_id>.nav.bin

The authored `ARecastNavMesh` tile set is the source of truth: its ground
polygons, area ids and off-mesh connections are decoded by CUE4Parse (see
`docs/reports/navmesh-spike.md`). This producer does not bake, does not invent
geometry and does not reclassify areas.

Rules that are deliberately fail-closed:

  * every ground polygon must have 3..6 vertices (Detour's convex limit); a
    7+ vertex polygon is an extractor defect, never silently clamped;
  * `supported_areas` and `nav_data_config` are required from the extractor
    (N-P0); a dump without them is stale and is refused;
  * areas are classified by class name. `NavArea_Default` is authored area 63
    in Guildhall/FTUE and must never be treated as Recast's null area; the
    per-map table (Old Manor uses 4 for Bushes and 3 for Door) is copied from
    the map's own `SupportedAreas`, never hard-coded;
  * an off-mesh record whose endpoints/radius/height cannot be represented is
    an error, not a dropped link.

Off-mesh merge (the 221 -> 80 result for Guildhall):

  1. vertices are deduped in 3D exact centimetres across tile borders;
  2. the raw off-mesh records are directional copies (A->B and B->A) of the
     same physical link; exact duplicate unordered endpoint pairs are
     collapsed and their direction census is kept (221 records -> 123 pairs);
  3. copies that are parallel (|dot| >= 0.99), within 150 cm perpendicular
     separation and overlapping along the link direction are one authored
     link split by poly/tile borders (123 -> 80). The canonical endpoint pair
     is the most duplicated copy; a link is bidirectional only when both
     directions are present in the census, never from the raw flags (all
     observed records carry flag 64).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_INPUT = ROOT / "extracted" / "nav"
DEFAULT_OUT = ROOT / "game" / "data" / "generated" / "nav"

SCHEMA = "tat2.nav/1"
SOURCE_SCHEMA = "tat2.nav_tiles/1"
MAGIC = b"TAT2NAV1"
VERSION = 1

# map_id used by GameData / MissionController -> extractor relative paths.
MAPS = {
    "guildhall": (
        "Maps/Guildhall/Guildhall_P.json",
        "Maps/Guildhall/Guildhall_P.umap",
    ),
    "old_manor": (
        "Maps/OldManor/OldManor_P.json",
        "Maps/OldManor/OldManor_P.umap",
    ),
    "ftue": (
        "Maps/FTUE/FTUE_P.json",
        "Maps/FTUE/FTUE_P.umap",
    ),
}

MAX_POLY_VERTS = 6
MERGE_MAX_PERP_CM = 150.0
MERGE_MAX_GAP_CM = 0.0
MERGE_MIN_PARALLEL = 0.99


class NavError(RuntimeError):
    pass


def fail(msg: str) -> None:
    raise NavError(msg)


def load_json(path: Path) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            doc = json.load(f)
    except FileNotFoundError:
        fail(f"missing input {path}; run the extractor 'nav' command first")
    except json.JSONDecodeError as e:
        fail(f"{path}: invalid JSON: {e}")
    if not isinstance(doc, dict):
        fail(f"{path}: root is not an object")
    return doc


def cm(value, what: str) -> int:
    try:
        f = float(value)
    except (TypeError, ValueError):
        fail(f"{what}: not a number: {value!r}")
    # Godot's roundi() rounds half away from zero; Python's round() is
    # banker's rounding and would move an authored X.5 cm vertex by 1 cm
    # (measured once in OldManor).
    return int(math.floor(f + 0.5)) if f >= 0.0 else int(math.ceil(f - 0.5))


def vec3(values, what: str) -> tuple[int, int, int]:
    if not isinstance(values, list) or len(values) != 3:
        fail(f"{what}: expected 3 numbers, got {values!r}")
    return (cm(values[0], what), cm(values[1], what), cm(values[2], what))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def area_table(doc: dict, source: Path) -> dict[int, str]:
    areas = doc.get("supported_areas")
    if not isinstance(areas, list) or not areas:
        fail(
            f"{source}: supported_areas missing/empty; re-run the N-P0 extractor "
            "(ARecastNavMesh SupportedAreas -> supported_areas)"
        )
    table: dict[int, str] = {}
    for entry in areas:
        if not isinstance(entry, dict):
            fail(f"{source}: supported_areas entry is not an object: {entry!r}")
        area_id = entry.get("id")
        class_name = entry.get("class")
        if (
            not isinstance(area_id, int)
            or not isinstance(class_name, str)
            or not class_name
        ):
            fail(f"{source}: supported_areas entry needs int id + class: {entry!r}")
        if area_id in table and table[area_id] != class_name:
            fail(f"{source}: area {area_id} has two class names")
        table[area_id] = class_name
    if table.get(63) != "NavArea_Default":
        fail(
            f"{source}: area 63 is {table.get(63)!r}, expected NavArea_Default; "
            "63 is an authored walkable id, not Recast null"
        )
    return table


def require_nav_config(doc: dict, source: Path) -> dict:
    cfg = doc.get("nav_data_config")
    required = ("agent_radius_cm", "agent_height_cm", "agent_step_height_cm")
    if not isinstance(cfg, dict) or any(
        not isinstance(cfg.get(k), (int, float)) for k in required
    ):
        fail(f"{source}: nav_data_config missing {required}; re-run the N-P0 extractor")
    out = {k: float(cfg[k]) for k in required}
    if out["agent_radius_cm"] <= 0 or out["agent_height_cm"] <= 0:
        fail(f"{source}: non-positive authored agent config {out}")
    return out


def build_mesh(doc: dict, source: Path, areas: dict[int, str]) -> dict:
    tiles = doc.get("tiles")
    if not isinstance(tiles, list) or not tiles:
        fail(f"{source}: no tiles")
    if int(doc.get("tile_count", -1)) != len(tiles):
        fail(f"{source}: tile_count {doc.get('tile_count')} != {len(tiles)} tiles")

    declared_max = doc.get("max_poly_verts")
    if declared_max is not None and int(declared_max) > MAX_POLY_VERTS:
        fail(
            f"{source}: extractor reports max_poly_verts={declared_max} > {MAX_POLY_VERTS}"
        )

    index: dict[tuple[int, int, int], int] = {}
    verts: list[tuple[int, int, int]] = []
    polygons: list[list[int]] = []
    poly_areas: list[int] = []
    poly_flags: list[int] = []
    area_counts: dict[int, int] = {}
    observed_max = 0

    for tile in tiles:
        if not isinstance(tile, dict):
            fail(f"{source}: tile is not an object")
        raw = tile.get("verts")
        if not isinstance(raw, list) or len(raw) % 3:
            fail(
                f"{source}: tile {tile.get('tx')},{tile.get('ty')} verts not x,y,z triples"
            )
        local: list[int] = []
        for i in range(0, len(raw), 3):
            key = vec3(raw[i : i + 3], f"{source}: tile vertex")
            gi = index.get(key)
            if gi is None:
                gi = len(verts)
                index[key] = gi
                verts.append(key)
            local.append(gi)

        polys = tile.get("polys")
        p_areas = tile.get("poly_areas")
        p_flags = tile.get("poly_flags")
        if (
            not isinstance(polys, list)
            or not isinstance(p_areas, list)
            or not isinstance(p_flags, list)
        ):
            fail(
                f"{source}: tile {tile.get('tx')},{tile.get('ty')} missing polys/poly_areas/poly_flags"
            )
        if not (len(polys) == len(p_areas) == len(p_flags)):
            fail(
                f"{source}: tile {tile.get('tx')},{tile.get('ty')} poly arrays differ in length"
            )
        for pi, poly in enumerate(polys):
            if not isinstance(poly, list):
                fail(f"{source}: tile poly is not an array")
            n = len(poly)
            if n > MAX_POLY_VERTS:
                fail(
                    f"{source}: tile {tile.get('tx')},{tile.get('ty')} poly {pi} has {n} "
                    f"verts > {MAX_POLY_VERTS}; refusing to clamp"
                )
            if n < 3:
                fail(f"{source}: tile poly {pi} has {n} vertices")
            observed_max = max(observed_max, n)
            idx: list[int] = []
            for v in poly:
                if not isinstance(v, int) or v < 0 or v >= len(local):
                    fail(f"{source}: tile poly {pi} has invalid local vertex {v!r}")
                idx.append(local[v])
            area = p_areas[pi]
            if not isinstance(area, int) or area not in areas:
                fail(f"{source}: tile poly {pi} area {area!r} not in SupportedAreas")
            if area == 0:
                fail(
                    f"{source}: tile poly {pi} has area 0 (NavArea_Null); not walkable"
                )
            flag = p_flags[pi]
            if not isinstance(flag, int):
                fail(f"{source}: tile poly {pi} flag {flag!r} is not int")
            if flag & 0x10:
                fail(
                    f"{source}: tile poly {pi} is DT_POLYFLAGS_DISABLED; authored data must not be silently skipped"
                )
            polygons.append(idx)
            poly_areas.append(area)
            poly_flags.append(flag)
            area_counts[area] = area_counts.get(area, 0) + 1

    authored_total = int(doc.get("poly_count_total", -1))
    offmesh_total = int(doc.get("offmesh_connection_total", -1))
    if (
        authored_total >= 0
        and offmesh_total >= 0
        and len(polygons) != authored_total - offmesh_total
    ):
        fail(
            f"{source}: walkable polys {len(polygons)} != poly_count_total {authored_total} "
            f"- offmesh {offmesh_total}"
        )
    if len(verts) >= 65536:
        fail(f"{source}: {len(verts)} vertices exceed the u16 polygon index format")

    return {
        "verts": verts,
        "polygons": polygons,
        "poly_areas": poly_areas,
        "poly_flags": poly_flags,
        "area_counts": area_counts,
        "max_poly_verts": observed_max,
        "authored_vert_count": int(doc.get("vert_count_total", len(verts))),
        "walkable_polys": len(polygons),
    }


def collect_offmesh(doc: dict, source: Path) -> list[dict]:
    out: list[dict] = []
    for tile in doc.get("tiles", []):
        for rec in tile.get("offmesh", []) or []:
            if not isinstance(rec, dict):
                fail(f"{source}: offmesh record is not an object")
            a = vec3(rec.get("a"), f"{source}: offmesh a")
            b = vec3(rec.get("b"), f"{source}: offmesh b")
            if a == b:
                fail(f"{source}: offmesh link with identical endpoints {a}")
            radius = cm(rec.get("radius", 0), f"{source}: offmesh radius")
            height = cm(rec.get("height", 0), f"{source}: offmesh height")
            flags = rec.get("flags")
            if not isinstance(flags, int):
                fail(f"{source}: offmesh flags {flags!r} is not int")
            out.append(
                {"a": a, "b": b, "radius": radius, "height": height, "flags": flags}
            )
    declared = int(doc.get("offmesh_connection_total", -1))
    if declared >= 0 and len(out) != declared:
        fail(f"{source}: offmesh records {len(out)} != declared {declared}")
    return out


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _norm(a):
    return math.sqrt(_dot(a, a))


def _unit(a):
    n = _norm(a)
    if n <= 0:
        fail("zero-length link direction")
    return (a[0] / n, a[1] / n, a[2] / n)


def link_census(doc: dict, source: Path) -> tuple[list[dict], dict]:
    records = collect_offmesh(doc, source)

    # 1. Collapse exact directional copies into unordered endpoint pairs.
    pairs: dict[tuple[tuple[int, int, int], tuple[int, int, int]], list[dict]] = {}
    for rec in records:
        key = tuple(sorted((rec["a"], rec["b"])))
        pairs.setdefault(key, []).append(rec)

    # 2. Merge parallel copies of one physical link (poly/tile split).
    keys = sorted(pairs.keys())
    n = len(keys)
    parent = list(range(n))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(x: int, y: int) -> None:
        rx, ry = find(x), find(y)
        if rx != ry:
            parent[ry] = rx

    for i in range(n):
        a, b = keys[i]
        u = _unit(_sub(b, a))
        for j in range(i + 1, n):
            c, e = keys[j]
            v = _unit(_sub(e, c))
            if abs(_dot(u, v)) < MERGE_MIN_PARALLEL:
                continue
            # Perpendicular distance of the second line from the first.
            if _norm(_cross(u, _sub(a, c))) > MERGE_MAX_PERP_CM:
                continue
            ta = sorted((_dot(a, u), _dot(b, u)))
            tb = sorted((_dot(c, u), _dot(e, u)))
            gap = max(ta[0], tb[0]) - min(ta[1], tb[1])
            if gap > MERGE_MAX_GAP_CM:
                continue
            union(i, j)

    clusters: dict[int, list[int]] = {}
    for i in range(n):
        clusters.setdefault(find(i), []).append(i)

    links: list[dict] = []
    bidirectional = 0
    one_way = 0
    for members in clusters.values():
        # Canonical pair: the most duplicated copy, then longest, then stable.
        def rank(i: int):
            a, b = keys[i]
            return (-len(pairs[keys[i]]), -round(_norm(_sub(b, a)), 3), keys[i])

        canonical = sorted(members, key=rank)[0]
        a, b = keys[canonical]
        # The merged copies carry the other direction; count the whole cluster
        # so a one-way raw record pair cannot become bidirectional by accident.
        dir_ab = sum(
            1 for i in members for r in pairs[keys[i]] if (r["a"], r["b"]) == (a, b)
        )
        dir_ba = sum(
            1 for i in members for r in pairs[keys[i]] if (r["a"], r["b"]) in ((b, a),)
        )
        is_bidirectional = dir_ab > 0 and dir_ba > 0
        if not is_bidirectional and dir_ab == 0 and dir_ba > 0:
            # A one-way authored link must keep its A->B direction; the sorted
            # key is only a canonical grouping id.
            a, b = b, a
        if is_bidirectional:
            bidirectional += 1
        else:
            one_way += 1
        # Authored radius/height: highest count, then smallest, deterministic.
        rep = sorted(
            (r for i in members for r in pairs[keys[i]]),
            key=lambda r: (r["radius"], r["height"], r["flags"]),
        )[0]
        links.append(
            {
                "a": a,
                "b": b,
                "radius": rep["radius"],
                "height": rep["height"],
                "flags": rep["flags"],
                "bidirectional": is_bidirectional,
                "records": sum(len(pairs[keys[i]]) for i in members),
                "copies": len(members),
            }
        )

    links.sort(key=lambda L: (L["a"], L["b"]))
    stats = {
        "raw_offmesh": len(records),
        "offmesh_pairs": len(pairs),
        "links": len(links),
        "links_bidirectional": bidirectional,
        "links_one_way": one_way,
        "merge_max_perp_cm": MERGE_MAX_PERP_CM,
        "merge_max_gap_cm": MERGE_MAX_GAP_CM,
    }
    return links, stats


def write_bin(path: Path, mesh: dict, links: list[dict]) -> None:
    verts = mesh["verts"]
    polygons = mesh["polygons"]
    areas = mesh["poly_areas"]
    if len(areas) != len(polygons):
        fail("area/polygon mismatch")
    with open(path, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<I", VERSION))
        f.write(struct.pack("<I", len(verts)))
        f.write(struct.pack("<I", len(polygons)))
        f.write(struct.pack("<I", len(links)))
        for v in verts:
            f.write(struct.pack("<iii", v[0], v[1], v[2]))
        for poly in polygons:
            f.write(struct.pack("<B", len(poly)))
            for idx in poly:
                f.write(struct.pack("<H", idx))
        for area in areas:
            f.write(struct.pack("<B", area))
        for link in links:
            f.write(struct.pack("<iii", *link["a"]))
            f.write(struct.pack("<iii", *link["b"]))
            f.write(struct.pack("<HH", link["radius"], link["height"]))
            f.write(
                struct.pack(
                    "<BBH",
                    1 if link["bidirectional"] else 0,
                    link["flags"] & 0xFF,
                    min(link["records"], 65535),
                )
            )


def parse_map(
    map_id: str, rel_json: str, rel_umap: str, input_root: Path, out_root: Path
) -> dict:
    source = input_root / rel_json
    doc = load_json(source)
    if str(doc.get("schema", "")) != SOURCE_SCHEMA:
        fail(f"{source}: schema {doc.get('schema')!r} != {SOURCE_SCHEMA}")
    areas = area_table(doc, source)
    nav_cfg = require_nav_config(doc, source)
    mesh = build_mesh(doc, source, areas)
    links, link_stats = link_census(doc, source)

    counts = mesh["area_counts"]
    area_rows = [
        {
            "id": area_id,
            "class": areas[area_id],
            "polys": int(counts.get(area_id, 0)),
        }
        for area_id in sorted(areas)
    ]
    if sum(r["polys"] for r in area_rows) != mesh["walkable_polys"]:
        fail(f"{source}: area histogram does not cover every walkable poly")

    out_bin = out_root / f"{map_id}.nav.bin"
    out_root.mkdir(parents=True, exist_ok=True)
    write_bin(out_bin, mesh, links)

    entry = {
        "file": out_bin.name,
        "source": rel_umap,
        "source_json": rel_json,
        "source_sha256": sha256_file(source),
        "schema": SOURCE_SCHEMA,
        "tiles": int(doc.get("tile_count", 0)),
        "polys": mesh["walkable_polys"],
        "authored_polys_total": int(doc.get("poly_count_total", 0)),
        "verts": len(mesh["verts"]),
        "authored_verts": mesh["authored_vert_count"],
        "max_poly_verts": mesh["max_poly_verts"],
        "areas": area_rows,
        "nav_data_config": nav_cfg,
        "params": {
            "tile_width_cm": float(doc.get("tile_width_cm", 0.0)),
            "tile_height_cm": float(doc.get("tile_height_cm", 0.0)),
            "walkable_height_cm": float(doc.get("walkable_height_cm", 0.0)),
            "walkable_radius_cm": float(doc.get("walkable_radius_cm", 0.0)),
            "walkable_climb_cm": float(doc.get("walkable_climb_cm", 0.0)),
        },
        "links": link_stats["links"],
        "links_bidirectional": link_stats["links_bidirectional"],
        "links_one_way": link_stats["links_one_way"],
        "raw_offmesh": link_stats["raw_offmesh"],
        "offmesh_pairs": link_stats["offmesh_pairs"],
        "bin_bytes": out_bin.stat().st_size,
    }
    print(
        f"NAV_MAP {map_id}: tiles={entry['tiles']} polys={entry['polys']} "
        f"verts={entry['verts']}/{entry['authored_verts']} "
        f"offmesh={entry['raw_offmesh']}->{entry['offmesh_pairs']}pairs->{entry['links']} links "
        f"(bidirectional={entry['links_bidirectional']} one_way={entry['links_one_way']}) "
        f"max_poly_verts={entry['max_poly_verts']} areas={len(area_rows)} "
        f"bin={entry['bin_bytes']}B"
    )
    return entry


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        default=str(DEFAULT_INPUT),
        help="extractor nav root (default extracted/nav)",
    )
    parser.add_argument(
        "--out",
        default=str(DEFAULT_OUT),
        help="generated nav root (default game/data/generated/nav)",
    )
    parser.add_argument(
        "--maps", default=",".join(MAPS), help="comma-separated map ids"
    )
    args = parser.parse_args(argv)

    input_root = Path(args.input)
    out_root = Path(args.out)
    selected = [m.strip() for m in args.maps.split(",") if m.strip()]
    unknown = [m for m in selected if m not in MAPS]
    if unknown:
        fail(f"unknown map id(s) {unknown}; known: {sorted(MAPS)}")

    manifest = {
        "schema": SCHEMA,
        "source_schema": SOURCE_SCHEMA,
        "producer": "tools/parse_nav.py",
        "merge": {
            "rule": "exact-cm vertices; unordered duplicate offmesh pairs; parallel copies <=150 cm perpendicular and overlapping along the link direction",
            "max_perp_cm": MERGE_MAX_PERP_CM,
            "overlap_gap_cm": MERGE_MAX_GAP_CM,
        },
        "maps": {},
    }
    for map_id in selected:
        rel_json, rel_umap = MAPS[map_id]
        manifest["maps"][map_id] = parse_map(
            map_id, rel_json, rel_umap, input_root, out_root
        )

    out_root.mkdir(parents=True, exist_ok=True)
    manifest_path = out_root / "manifest.json"
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"NAV_MANIFEST {manifest_path} maps={len(manifest['maps'])}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except NavError as e:
        print(f"parse_nav: ERROR: {e}", file=sys.stderr)
        sys.exit(1)
