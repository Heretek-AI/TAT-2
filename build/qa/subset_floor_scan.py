#!/usr/bin/env python3
"""W2P: static floor-owner scan for the Spider personal-chain pins (no Godot).

Answers one question without loading the map: which of a map's generated
`.tatlevel.json` sublevels owns a static surface under each authored pin?

Method: for every mesh record, resolve the UE mesh to its GLB, read the union
POSITION min/max from the glTF accessors (engine units, metres after export),
apply the record's basis/scale/pos exactly like `level_loader._dict_to_transform`
(basis columns = (b0,b1,b2),(b3,b4,b5),(b6,b7,b8); local scale clamped
0.05..40), and keep meshes whose world AABB spans the pin XZ. The nearest
AABB tops to the pin Y are printed with their owning sublevel.

This is corroboration only: the runtime probe is the authority for collision
and grounding (the loader decides which meshes get collision).

    python3 build/qa/subset_floor_scan.py
"""

import glob
import json
import os
import struct

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "game/assets/ue/Content")

PINS = {
    "letter": (-26.8541, 28.0021, -9.4431),
    "owl": (-31.6286, 36.4655, -43.9759),
    "courier": (35.9, 27.0019, -22.728),
    "informant": (1.5, 10.1096, 13.0),
}

MAP_GLOBS = [
    "game/data/generated/levels/Guildhall/*.json",
    "game/data/generated/levels/Buildings/Guildhall/*.json",
    "game/data/generated/levels/OldManor/*.json",
]

_cache = {}


def ue_to_glb(ue):
    clean = ue.split(".")[0]
    if clean.startswith("/Game/"):
        clean = clean[6:]
    path = os.path.join(ASSETS, clean + ".glb")
    return path if os.path.exists(path) else None


def local_bounds(path):
    """Union POSITION accessor min/max for every primitive in the GLB."""
    if path in _cache:
        return _cache[path]
    out = None
    try:
        with open(path, "rb") as f:
            magic, _ver, _length = struct.unpack("<III", f.read(12))
            if magic != 0x46546C67:
                _cache[path] = None
                return None
            clen, _ctype = struct.unpack("<II", f.read(8))
            doc = json.loads(f.read(clen))
        for mesh in doc.get("meshes", []):
            for prim in mesh.get("primitives", []):
                ai = prim.get("attributes", {}).get("POSITION")
                if ai is None:
                    continue
                acc = doc["accessors"][ai]
                if "min" not in acc or "max" not in acc:
                    continue
                lo, hi = acc["min"], acc["max"]
                if out is None:
                    out = [list(lo), list(hi)]
                else:
                    out[0] = [min(out[0][i], lo[i]) for i in range(3)]
                    out[1] = [max(out[1][i], hi[i]) for i in range(3)]
    except Exception:
        out = None
    _cache[path] = out
    return out


def world_aabb(rec, lb):
    b = rec.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
    s = [min(max(float(x), 0.05), 40.0) for x in rec.get("scale", [1, 1, 1])]
    cols = [[b[0], b[1], b[2]], [b[3], b[4], b[5]], [b[6], b[7], b[8]]]
    m = [[cols[c][r] * s[c] for c in range(3)] for r in range(3)]
    lmin, lmax = lb
    lc = [(lmin[i] + lmax[i]) * 0.5 for i in range(3)]
    le = [(lmax[i] - lmin[i]) * 0.5 for i in range(3)]
    p = rec.get("pos", [0, 0, 0])
    c = [p[r] + sum(m[r][k] * lc[k] for k in range(3)) for r in range(3)]
    e = [sum(abs(m[r][k]) * le[k] for k in range(3)) for r in range(3)]
    return c, e


def main():
    layers = []
    for pat in MAP_GLOBS:
        for rel in sorted(glob.glob(os.path.join(ROOT, pat))):
            try:
                doc = json.load(open(rel))
            except Exception:
                continue
            layers.append((os.path.relpath(rel, ROOT), doc))
    for name, (x, y, z) in PINS.items():
        print("### pin %s (%.4f, %.4f, %.4f)" % (name, x, y, z))
        found = False
        for rel, doc in layers:
            rows = []
            for rec in doc.get("meshes", []) or []:
                glb = ue_to_glb(rec["mesh"])
                lb = local_bounds(glb) if glb else None
                if not lb:
                    continue
                c, e = world_aabb(rec, lb)
                if abs(c[0] - x) <= e[0] and abs(c[2] - z) <= e[2]:
                    rows.append(
                        (abs(c[1] + e[1] - y), c[1] + e[1], rec["mesh"].split("/")[-1])
                    )
            if not rows:
                continue
            rows.sort()
            found = True
            dy, top, mesh = rows[0]
            print(
                "  %-58s n=%3d nearest top=%.3f (dy=%+.3f) %s"
                % (rel.split("levels/")[-1], len(rows), top, top - y, mesh)
            )
        if not found:
            print("  no static mesh spans this pin XZ")


if __name__ == "__main__":
    main()
