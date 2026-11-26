#!/usr/bin/env python3
"""Static reproduction of the Guildhall guard selection + ingest grounding.

Claim under test (H1): `_spawn_guards()` in
`game/src/missions/mission_controller.gd` grounds each chosen marker with one
`intersect_ray` from `marker + (0,8,0)` to `marker + (0,-30,0)` on mask 1 and
returns the FIRST hit.  If an upper slab/ceiling sits in that column the guard
is placed on top of it instead of on the floor under the marker.

What this script does, with no Godot process:

  1. rebuilds the exact loader file list for `guildhall` / Contract 2 from
     `_map_id_to_sublevels()` (hard-coded base list, quoted in the report) plus
     `GameData.get_contract_sublevels(order=2)`, applying the loader's merge
     skip (`_prescan_merged_sublevels`) and always-streamed additions
     (`_resolve_authored_streaming`);
  2. replays the `markers` pass of `_parse_sublevel_file()` in file order with
     the same `elif` branch order (SmartObject before Guard) to rebuild
     `guard_spawns` / `player_spawn_transforms`;
  3. replays `_spawn_player()`'s first-hit choice + `_snap_player_to_ground()`
     to get the mission anchor, then `_spawn_guards()`'s 10 m < d < 120 m filter
     in array order with the Novice limit 4;
  4. decodes `game/data/generated/mesh_collision.json` the way
     `game/src/core/collision/authored_collision.gd` does and casts the same
     vertical ray against every authored collider in the loaded level files.

Coordinate / unit conventions (all copied from the GDScript, not guessed):
  * level `pos` is Godot metres; level `basis` is a row-major 3x3 whose COLUMNS
    are the basis vectors (`_dict_to_transform`, level_loader.gd:6894);
  * `mesh_collision.json` `half_extent` is the FULL UE extent despite its name
    (authored_collision.gd:471 "FULL UE extent", measured with the 1 m
    /Engine/BasicShapes/Cube -> 100 cm and 4 m SM_Floor_4x4 -> 400 cm).  The
    file's own `notes` string says "HALF-extents"; that note is stale and the
    loader's measured interpretation is used here.
  * element-local -> mesh-local is `_rotator_basis(rotation)` + `center`
    (`_decode_element`); UE cm is converted with the (x, z, y) * 0.01 swap
    (`_p3`, `_baked_points`);
  * instance -> world is `pos + basis * scale * local` with `scale` clamped to
    [0.05, 40] per axis (`_dict_to_transform`), and `CollisionShape3D.scale`
    uses `max(abs(scale), 0.05)` (`_add_collider`).

Collision-shape modelling (mirrors `AuthoredCollision.resolve()`):
  * `absent` (no mesh_collision entry) -> the loader uses the GLB AABB/trimesh
    heuristic.  Not modelled here: counted as "no modelled collision".
  * `complex_as_simple` -> render trimesh.  Counted, not modelled.
  * `ECollisionEnabled::NoCollision` -> no shapes.
  * convex element whose baked point AABB is flatter than 1e-4 m -> skipped
    (planar convex skip);
  * primitive-only sets -> per-element primitive tests (identical first hit to
    the loader's single primitive / tessellated trimesh);
  * sets containing convex elements and (elements > 16 and path is not a
    "stair") or (elements-1) * instances > 250 -> coalesced to element AABBs
    (`_coalesce_element_aabbs`), modelled as mesh-space boxes;
  * otherwise per-element: box = OBB slab test in element space, sphere and
    sphyl = analytic in mesh space, convex = exact vertical-ray upper surface
    computed as the max over vertex triples whose XZ projection contains the
    column (the LP optimum of "max y at fixed x,z" is a basic feasible solution
    with at most 3 non-zero barycentric weights).

Usage:
  python3 build/qa/w10/guard_static_pred.py            # full report
  python3 build/qa/w10/guard_static_pred.py --files     # loader order only
  python3 build/qa/w10/guard_static_pred.py --select    # marker selection only
  python3 build/qa/w10/guard_static_pred.py --json out.json
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
from collections import Counter, OrderedDict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
LEVELS = os.path.join(ROOT, "game", "data", "generated", "levels")
MESH_COLLISION = os.path.join(ROOT, "game", "data", "generated", "mesh_collision.json")
CONTRACTS_JSON = os.path.join(
    ROOT, "game", "data", "generated", "gameplay", "contracts.json"
)

LEVEL_PREFIX = "res://data/generated/levels/"
LEVEL_SUFFIX = ".tatlevel.json"

# `_map_id_to_sublevels("guildhall", order)` base list, verbatim and in order
# (mission_controller.gd:999-1015).  The per-contract file is appended below
# from contracts.json, exactly like `GameData.get_contract_sublevels(2)`.
GUILDHALL_BASE = [
    "Buildings/Guildhall/Building_Guildhall_POI",
    "Buildings/Guildhall/Building_Guildhall_POI_3rdFloor",
    "Buildings/Guildhall/Guildhall_Vault_CeremonialChambers",
    "Guildhall/Guildhall_Gameplay",
    "Guildhall/Guildhall_P",
    "Guildhall/Guildhall_Geometry",
    "Guildhall/Guildhall_Landscape",
    "Guildhall/Guildhall_LightingNoGameplay",
    "Guildhall/Guildhall_LocalVolumetric",
    "Guildhall/Guildhall_PeripheryA",
    "Guildhall/Guildhall_Loot",
    "Guildhall/Guildhall_Contracts",
    "Guildhall/Guildhall_SetSpawners",
    "Guildhall/Guildhall_MissionClues",
    "Guildhall/Guildhall_SkyboxGeo",
]

DECORATIVE_SUBLEVEL_TOKENS = ["skyboxgeo"]  # level_loader.gd:438
CLUTTER_TOKENS = [
    "sm_leaf",
    "sm_grass",
    "sm_newgrass",
    "sm_newspaper",
    "sm_pebble",
    "sm_debris",
    "foliage",
    "ivy",
    "vine",
    "moss",
    "cobweb",
    "sm_dust",
]  # CLUTTER_TOKENS, level_loader.gd:430
NAME_SKIP_TOKENS = ["fogsheet", "fogsphere", "volumetric", "skysphere", "blocker"]

MAX_CONVEX_ELEMENTS_PER_MESH = 16
MAX_ELEMENT_SHAPE_COST = 250
PLANAR_EPS_M = 1e-4
MIN_HALF_EXTENT_M = 0.01
CM_TO_M = 0.01
SCALE_MIN, SCALE_MAX = 0.05, 40.0
ASSETS_UE = os.path.join(ROOT, "game", "assets", "ue")

EPS = 1e-6


# --------------------------------------------------------------------------
# small vector / matrix helpers (no numpy in this environment)
# --------------------------------------------------------------------------
def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vmul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def vdot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def vcross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def vlen(a):
    return math.sqrt(vdot(a, a))


def matvec(cols, v):
    """cols = three column vectors."""
    return (
        cols[0][0] * v[0] + cols[1][0] * v[1] + cols[2][0] * v[2],
        cols[0][1] * v[0] + cols[1][1] * v[1] + cols[2][1] * v[2],
        cols[0][2] * v[0] + cols[1][2] * v[1] + cols[2][2] * v[2],
    )


def mat_inv(cols):
    a, b, c = cols[0], cols[1], cols[2]
    det = vdot(a, vcross(b, c))
    if abs(det) < 1e-12:
        return None
    inv_det = 1.0 / det
    # inverse rows are cross products
    r0 = vmul(vcross(b, c), inv_det)
    r1 = vmul(vcross(c, a), inv_det)
    r2 = vmul(vcross(a, b), inv_det)
    # return columns of the inverse
    return [(r0[0], r1[0], r2[0]), (r0[1], r1[1], r2[1]), (r0[2], r1[2], r2[2])]


def inst_cols(basis_flat):
    """`_dict_to_transform`: Basis(Vector3(b0,b3,b6), ...) -> columns."""
    b = basis_flat if len(basis_flat) >= 9 else [1, 0, 0, 0, 1, 0, 0, 0, 1]
    return [
        (float(b[0]), float(b[3]), float(b[6])),
        (float(b[1]), float(b[4]), float(b[7])),
        (float(b[2]), float(b[5]), float(b[8])),
    ]


def rotator_cols(rot):
    """`_rotator_basis` from authored_collision.gd (UE FRotator -> Godot)."""
    rot = rot or {}
    p = math.radians(float(rot.get("pitch", 0.0)))
    y = math.radians(float(rot.get("yaw", 0.0)))
    r = math.radians(float(rot.get("roll", 0.0)))
    cp, sp = math.cos(p), math.sin(p)
    cy, sy = math.cos(y), math.sin(y)
    cr, sr = math.cos(r), math.sin(r)
    m00 = cp * cy
    m01 = sr * sp * cy - cr * sy
    m02 = -(cr * sp * cy + sr * sy)
    m10 = cp * sy
    m11 = sr * sp * sy + cr * cy
    m12 = sr * cy - cr * sp * sy
    m20 = sp
    m21 = -sr * cp
    m22 = cr * cp
    return [(m00, m20, m10), (m02, m22, m12), (m01, m21, m11)]


def p3(v):
    """UE cm array -> Godot metres with the Y/Z swap (`_p3`)."""
    if not isinstance(v, (list, tuple)) or len(v) < 3:
        return (0.0, 0.0, 0.0)
    return (float(v[0]) * CM_TO_M, float(v[2]) * CM_TO_M, float(v[1]) * CM_TO_M)


def quat_rotate(q, v):
    x, y, z, w = q
    qv = (x, y, z)
    t = vmul(vcross(qv, v), 2.0)
    return vadd(vadd(v, vmul(t, w)), vcross(qv, t))


# --------------------------------------------------------------------------
# loader file order
# --------------------------------------------------------------------------
def _key(path):
    return path


def loader_file_order(order=2, verbose=False):
    """Return [(key, abspath, decorative, why)] in actual parse order."""
    notes = []
    supplied = list(GUILDHALL_BASE)
    contracts = json.load(open(CONTRACTS_JSON))
    appended = []
    for c in contracts.get("contracts", []):
        if int(c.get("order", -1)) != order:
            continue
        for rp in c.get("sublevels_res_paths", []) or []:
            rp = str(rp)
            if not rp.startswith(LEVEL_PREFIX) or not rp.endswith(LEVEL_SUFFIX):
                continue
            key = rp[len(LEVEL_PREFIX) : -len(LEVEL_SUFFIX)]
            if key and key not in supplied:
                supplied.append(key)
                appended.append(key)
        break
    notes.append(("contract_sublevels_appended", appended))

    # _prescan_merged_sublevels: any supplied file whose level_instances names
    # another supplied key skips that key.
    merged = {}
    for key in supplied:
        p = os.path.join(LEVELS, key + LEVEL_SUFFIX)
        if not os.path.exists(p):
            continue
        d = json.load(open(p))
        if not d.get("level_instances"):
            continue
        for li in d["level_instances"]:
            merged[str(li)] = key
    skipped = [k for k in supplied if k in merged]
    notes.append(("merged_skip", skipped))
    supplied = [k for k in supplied if k not in merged]

    files = []
    for key in supplied:
        p = os.path.join(LEVELS, key + LEVEL_SUFFIX)
        files.append((key, p, verbose))

    # _resolve_authored_streaming: "always" streaming rows not already parsed
    # and not merged as a LevelInstance are parsed AFTER the supplied list.
    seen = {k for k in supplied}
    always = []
    for key in supplied:
        p = os.path.join(LEVELS, key + LEVEL_SUFFIX)
        if not os.path.exists(p):
            continue
        d = json.load(open(p))
        for rec in d.get("streaming_levels", []) or []:
            if not isinstance(rec, dict) or rec.get("type") != "always":
                continue
            lvl = str(rec.get("level", ""))
            if lvl and lvl not in always:
                always.append(lvl)
    extras = []
    for lvl in always:
        if lvl in seen:
            continue
        if lvl in merged:
            continue
        p = os.path.join(LEVELS, lvl + LEVEL_SUFFIX)
        if not os.path.exists(p):
            notes.append(("graph_missing", lvl))
            continue
        extras.append(lvl)
        seen.add(lvl)
    for key in extras:
        p = os.path.join(LEVELS, key + LEVEL_SUFFIX)
        files.append((key, p, verbose))
    notes.append(("streaming_added", extras))

    out = []
    for key, p, _ in files:
        if not os.path.exists(p):
            notes.append(("missing", p))
            continue
        decorative = any(tok in p.lower() for tok in DECORATIVE_SUBLEVEL_TOKENS)
        out.append((key, p, decorative))
    return out, OrderedDict(notes)


# --------------------------------------------------------------------------
# loader marker replay
# --------------------------------------------------------------------------
def replay_markers(files):
    guard_spawns = []
    player_spawns = []  # transforms, in load order
    player_positions = []
    smart_objects = 0
    skipped = Counter()
    marker_by_file = Counter()
    for key, path, decorative in files:
        d = json.load(open(path))
        marker_by_file[key] = len(d.get("markers", []) or [])
        for mk in d.get("markers", []) or []:
            if not isinstance(mk, dict):
                continue
            cls = str(mk.get("class", ""))
            pos = mk.get("pos", [0, 0, 0])
            p = (float(pos[0]), float(pos[1]), float(pos[2]))
            # exact branch order of _parse_sublevel_file (level_loader.gd:3403)
            if "PlayerStart" in cls:
                player_positions.append(p)
                player_spawns.append(
                    {
                        "pos": p,
                        "basis": list(mk.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])),
                        "name": str(mk.get("name", "")),
                        "class": cls,
                        "file": key,
                    }
                )
            elif "MissionSpawner_Throwable" in cls:
                skipped["throwable"] += 1
            elif "MissionSpawner_AmmoRefill" in cls:
                skipped["ammo"] += 1
            elif "MissionSpawner_Health" in cls:
                skipped["health"] += 1
            elif "MissionSpawner_Civilian" in cls:
                skipped["civilian"] += 1
            elif "SmartObject" in cls:
                smart_objects += 1
            elif "MissionSpawner_Character" in cls or "Guard" in cls:
                guard_spawns.append(
                    {
                        "pos": p,
                        "name": str(mk.get("name", "")),
                        "class": cls,
                        "file": key,
                    }
                )
            elif (
                "MissionSpawner_MajorLoot" in cls
                or "MissionSpawner_MinorLoot" in cls
                or "QuestSpawner" in cls
            ):
                skipped["loot"] += 1
            elif "Escape" in cls:
                skipped["escape"] += 1
            elif "Door" in cls:
                skipped["door"] += 1
            else:
                skipped["other"] += 1
    return {
        "guard_spawns": guard_spawns,
        "player_spawns": player_spawns,
        "player_positions": player_positions,
        "smart_objects": smart_objects,
        "skipped": skipped,
        "marker_by_file": marker_by_file,
    }


# --------------------------------------------------------------------------
# collision decoding (mirrors authored_collision.gd)
# --------------------------------------------------------------------------
class Element:
    __slots__ = (
        "kind",
        "mesh_pts",
        "half",
        "center",
        "rcols",
        "radius",
        "half_len",
        "aabb",
        "src",
    )

    def __init__(self, kind):
        self.kind = kind
        self.mesh_pts = None  # convex: mesh-space points
        self.half = None  # box: half extents (mesh-space size/2)
        self.center = (0.0, 0.0, 0.0)
        self.rcols = None
        self.radius = 0.0
        self.half_len = 0.0
        self.aabb = None  # mesh-space AABB (min, max)
        self.src = ""


def decode_element(el, note):
    t = str(el.get("type", ""))
    if t == "box":
        ext = p3(el.get("half_extent"))
        half = (
            max(abs(ext[0]), 2 * MIN_HALF_EXTENT_M) / 2.0,
            max(abs(ext[1]), 2 * MIN_HALF_EXTENT_M) / 2.0,
            max(abs(ext[2]), 2 * MIN_HALF_EXTENT_M) / 2.0,
        )
        e = Element("box")
        e.half = half
        e.center = p3(el.get("center"))
        e.rcols = rotator_cols(el.get("rotation"))
        e.src = t
        mn = tuple(e.center[i] - half[i] for i in range(3))
        mx = tuple(e.center[i] + half[i] for i in range(3))
        e.aabb = (mn, mx)
        return e
    if t == "sphere":
        e = Element("sphere")
        e.center = p3(el.get("center"))
        e.radius = max(float(el.get("radius", 0.0)) * CM_TO_M, MIN_HALF_EXTENT_M)
        e.src = t
        r = e.radius
        e.aabb = (
            tuple(e.center[i] - r for i in range(3)),
            tuple(e.center[i] + r for i in range(3)),
        )
        return e
    if t == "sphyl":
        e = Element("sphyl")
        e.center = p3(el.get("center"))
        e.radius = max(float(el.get("radius", 0.0)) * CM_TO_M, MIN_HALF_EXTENT_M)
        e.half_len = max(float(el.get("length", 0.0)) * CM_TO_M, 0.0) / 2.0
        e.rcols = rotator_cols(el.get("rotation"))
        e.src = t
        # world-space AABB is approximated by the axis-less extent; the exact
        # test below does not use it beyond the prefilter.
        r = e.radius
        hx = r + 0.0
        hy = e.half_len + r
        hz = r + 0.0
        # use the largest axis bound to stay conservative in the prefilter
        m = max(hx, hy, hz)
        e.aabb = (
            tuple(e.center[i] - m for i in range(3)),
            tuple(e.center[i] + m for i in range(3)),
        )
        return e
    if t == "convex":
        flat = el.get("vertices_flat", []) or []
        if len(flat) < 9:
            return None
        tr = el.get("transform", {}) or {}
        rq = tr.get("rotation", {}) or {}
        q = (
            float(rq.get("X", 0.0)),
            float(rq.get("Y", 0.0)),
            float(rq.get("Z", 0.0)),
            float(rq.get("W", 1.0)),
        )
        qn = math.sqrt(sum(c * c for c in q)) or 1.0
        q = tuple(c / qn for c in q)
        sc = tr.get("scale3d", [1.0, 1.0, 1.0]) or [1.0, 1.0, 1.0]
        tv = tr.get("translation", [0.0, 0.0, 0.0]) or [0.0, 0.0, 0.0]
        pts = []
        n = len(flat) // 3
        for i in range(n):
            v = (float(flat[3 * i]), float(flat[3 * i + 1]), float(flat[3 * i + 2]))
            v = (v[0] * float(sc[0]), v[1] * float(sc[1]), v[2] * float(sc[2]))
            v = quat_rotate(q, v)
            v = (v[0] + float(tv[0]), v[1] + float(tv[1]), v[2] + float(tv[2]))
            # `_baked_points`: Vector3(v.x, v.z, v.y) * 0.01
            pts.append((v[0] * CM_TO_M, v[2] * CM_TO_M, v[1] * CM_TO_M))
        e = Element("convex")
        e.mesh_pts = pts
        e.src = t
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        zs = [p[2] for p in pts]
        e.aabb = ((min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs)))
        ext = (
            e.aabb[1][0] - e.aabb[0][0],
            e.aabb[1][1] - e.aabb[0][1],
            e.aabb[1][2] - e.aabb[0][2],
        )
        if min(ext) < PLANAR_EPS_M:
            note["planar_skipped"] += 1
            return None
        return e
    note["unknown_element"] += 1
    return None


_GLB_AABB_CACHE = {}
_NONBLOCKING_TOKENS = (
    "rug",
    "carpet",
    "placemat",
    "paper",
    "poster",
    "scroll",
    "curtain",
    "cloth",
    "drape",
    "sheet",
    "cable",
    "wire",
    "rope",
    "ivy",
    "vine",
    "foliage",
)


def glb_aabb(ue_path):
    """Render-mesh AABB from the GLB POSITION accessor min/max (glTF Y-up).

    Used only for `absent` paths, where the loader's `_heuristic_shape()`
    builds a BoxShape3D from `Mesh.get_aabb()`.  The shipped GLBs are
    single-node exports (`node 0 = {mesh: 0}`), so the accessor bounds are the
    mesh AABB; multi-node GLBs would need the node transforms baked.
    """
    if ue_path in _GLB_AABB_CACHE:
        return _GLB_AABB_CACHE[ue_path]
    rel = ue_path[6:] if ue_path.startswith("/Game/") else ue_path.lstrip("/")
    p = os.path.join(ASSETS_UE, "Content", rel + ".glb")
    out = None
    if os.path.exists(p):
        try:
            b = open(p, "rb").read()
            off = 12
            doc = None
            while off + 8 <= len(b):
                clen, ctype = struct.unpack_from("<II", b, off)
                chunk = b[off + 8 : off + 8 + clen]
                if ctype == 0x4E4F534A:
                    doc = json.loads(chunk)
                    break
                off += 8 + clen
            if doc:
                lo = [1e30, 1e30, 1e30]
                hi = [-1e30, -1e30, -1e30]
                accessors = doc.get("accessors", [])
                for mesh in doc.get("meshes", []):
                    for prim in mesh.get("primitives", []):
                        ai = (prim.get("attributes", {}) or {}).get("POSITION")
                        if ai is None or ai >= len(accessors):
                            continue
                        a = accessors[ai]
                        mn, mx = a.get("min"), a.get("max")
                        if not mn or not mx or len(mn) < 3:
                            continue
                        for i in range(3):
                            lo[i] = min(lo[i], float(mn[i]))
                            hi[i] = max(hi[i], float(mx[i]))
                if lo[0] < 1e29:
                    out = (tuple(lo), tuple(hi))
        except Exception:
            out = None
    _GLB_AABB_CACHE[ue_path] = out
    return out


def heuristic_elements(ue_path, note):
    """`_heuristic_shape()` for an `absent` mesh, as one AABB box.

    The loader picks box vs convex vs trimesh by name/size; a trimesh's first
    vertical hit is its top surface, which the AABB box reproduces for a flat
    walk surface and upper-bounds for a pitched one.  The distinction is
    recorded in `note` and in the element source tag.
    """
    low = ue_path.lower()
    if any(t in low for t in _NONBLOCKING_TOKENS):
        note["absent_nonblocking"] += 1
        return [], "absent_nonblocking"
    aabb = glb_aabb(ue_path)
    if aabb is None:
        note["absent_no_glb"] += 1
        return [], "absent_no_glb"
    mn, mx = aabb
    size = (mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2])
    slen = math.sqrt(size[0] ** 2 + size[1] ** 2 + size[2] ** 2)
    if slen <= 0.45:
        note["absent_tiny"] += 1
        return [], "absent_tiny"
    e = Element("box")
    e.half = (max(size[0], 0.1) / 2.0, max(size[1], 0.1) / 2.0, max(size[2], 0.1) / 2.0)
    e.center = ((mn[0] + mx[0]) / 2.0, (mn[1] + mx[1]) / 2.0, (mn[2] + mx[2]) / 2.0)
    e.rcols = [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)]
    is_stair = "stair" in low and not any(
        t in low
        for t in ("rail", "boundary", "post", "banister", "balustrade", "upstairs")
    )
    if (
        "door" in low
        or "archway" in low
        or slen >= 12.0
        or "sidewalk" in low
        or is_stair
    ):
        e.src = "absent_trimesh_aabb"
        note["absent_trimesh_aabb"] += 1
    else:
        e.src = "absent_box"
        note["absent_box"] += 1
    e.aabb = (mn, mx)
    return [e], "absent_heuristic"


def decode_mesh(record, path_instances, note, heuristic=False, path=""):
    """Return (kind, [Element], reduced) mirroring AuthoredCollision.resolve."""
    if record is None:
        if heuristic:
            els, kind = heuristic_elements(path, note)
            return kind, els, False
        return "absent", [], False
    if bool(record.get("complex_as_simple")):
        return "complex_default", [], False
    enabled = str(record.get("collision_enabled", ""))
    if enabled.endswith("NoCollision"):
        return "no_collision", [], False
    raw = record.get("elements", []) or []
    kept = []
    for el in raw:
        try:
            e = decode_element(el, note)
        except Exception as exc:  # malformed element: loader would warn
            note["decode_error"] += 1
            e = None
        if e is not None:
            kept.append(e)
    convex = sum(1 for e in kept if e.kind == "convex")
    if not kept:
        return "hull", [], False
    stair = "stair" in os.path.basename(str(record.get("_path", ""))).lower()
    over_cap = convex > MAX_CONVEX_ELEMENTS_PER_MESH and not stair
    cost_cap = (len(kept) - 1) * max(path_instances, 1) > MAX_ELEMENT_SHAPE_COST
    if convex > 0 and (over_cap or cost_cap):
        boxes = []
        for e in kept:
            b = Element("box")
            mn, mx = e.aabb
            b.half = (
                max((mx[0] - mn[0]) / 2.0, MIN_HALF_EXTENT_M),
                max((mx[1] - mn[1]) / 2.0, MIN_HALF_EXTENT_M),
                max((mx[2] - mn[2]) / 2.0, MIN_HALF_EXTENT_M),
            )
            b.center = (
                (mn[0] + mx[0]) / 2.0,
                (mn[1] + mx[1]) / 2.0,
                (mn[2] + mx[2]) / 2.0,
            )
            b.rcols = [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)]
            b.src = "coalesced_aabb"
            b.aabb = e.aabb
            boxes.append(b)
        return "hull", boxes, True
    return ("hull" if convex else "prims"), kept, False


def path_aabb(elements):
    if not elements:
        return None
    mn = [1e30, 1e30, 1e30]
    mx = [-1e30, -1e30, -1e30]
    for e in elements:
        for i in range(3):
            mn[i] = min(mn[i], e.aabb[0][i])
            mx[i] = max(mx[i], e.aabb[1][i])
    return (tuple(mn), tuple(mx))


# --------------------------------------------------------------------------
# level instances
# --------------------------------------------------------------------------
def iter_instances(files):
    """Yield (key, mesh, pos, cols(scaled), raw_scale, override_materials,
    hidden, skip_reason).  Mirrors the per-mesh skips of _parse_sublevel_file."""
    for key, path, decorative in files:
        d = json.load(open(path))
        for m in d.get("meshes", []) or []:
            mp = str(m.get("mesh", ""))
            if not mp:
                continue
            low = mp.lower()
            reason = None
            if (
                "fogsheet" in low
                or "fogsphere" in low
                or "volumetric" in low
                or "skysphere" in low
                or "blocker" in low
            ):
                reason = "name_skipped"
            elif low.endswith("/sm_wardbox"):
                reason = "wardbox"
            elif low.find("/test/art/primitives/") >= 0 and os.path.basename(low).split(
                "."
            )[0].startswith("sm_shape_"):
                reason = "debug_shape"
            elif "moonshape" in low:
                reason = "moonshape"
            ov = m.get("override_materials")
            if not isinstance(ov, list):
                ov = (
                    [m.get("override_material", "")]
                    if m.get("override_material")
                    else []
                )
            ov = [str(x) for x in ov if x]
            if reason is None and any("LocalVolumetricFog" in o for o in ov):
                reason = "fog_volume"
            if reason is None and decorative:
                reason = "decorative"
            hidden = bool(m.get("hidden_in_game", False))
            if reason is None and hidden:
                reason = "hidden_in_game"
            if reason is None and any(tok in low for tok in CLUTTER_TOKENS):
                reason = "clutter"
            pos = m.get("pos", [0, 0, 0])
            pos = (float(pos[0]), float(pos[1]), float(pos[2]))
            b = m.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
            cols = inst_cols(b)
            s = m.get("scale", [1, 1, 1])
            scale = (
                min(max(float(s[0]), SCALE_MIN), SCALE_MAX),
                min(max(float(s[1]), SCALE_MIN), SCALE_MAX),
                min(max(float(s[2]), SCALE_MIN), SCALE_MAX),
            )
            yield key, mp, pos, cols, scale, ov, hidden, reason


def instance_world_aabb(mesh_aabb, pos, cols, scale):
    mn, mx = mesh_aabb
    pts = []
    for x in (mn[0], mx[0]):
        for y in (mn[1], mx[1]):
            for z in (mn[2], mx[2]):
                lv = (x * scale[0], y * scale[1], z * scale[2])
                pts.append(vadd(pos, matvec(cols, lv)))
    lo = (min(p[0] for p in pts), min(p[1] for p in pts), min(p[2] for p in pts))
    hi = (max(p[0] for p in pts), max(p[1] for p in pts), max(p[2] for p in pts))
    return lo, hi


# --------------------------------------------------------------------------
# ray tests -- all in world space, vertical direction only for the ingest ray
# --------------------------------------------------------------------------
def ray_box_element(origin, direction, e, cols, pos, scale):
    """OBB slab test.  Transform the ray into element space exactly."""
    # world -> instance-mesh space
    minv = mat_inv(cols)
    if minv is None:
        return None
    o = matvec(minv, vsub(origin, pos))
    d = matvec(minv, direction)
    # undo instance scale, then element frame
    o = (o[0] / scale[0], o[1] / scale[1], o[2] / scale[2])
    d = (d[0] / scale[0], d[1] / scale[1], d[2] / scale[2])
    rinv = mat_inv(e.rcols)
    if rinv is None:
        return None
    o = matvec(rinv, vsub(o, e.center))
    d = matvec(rinv, d)
    tmin, tmax = -1e30, 1e30
    for i in range(3):
        if abs(d[i]) < 1e-12:
            if o[i] < -e.half[i] or o[i] > e.half[i]:
                return None
            continue
        t1 = (-e.half[i] - o[i]) / d[i]
        t2 = (e.half[i] - o[i]) / d[i]
        if t1 > t2:
            t1, t2 = t2, t1
        tmin = max(tmin, t1)
        tmax = min(tmax, t2)
        if tmin > tmax:
            return None
    if tmax < 0:
        return None
    return tmin if tmin >= 0 else 0.0


def ray_box_mesh(origin, direction, e, cols, pos, scale):
    """Axis-aligned box in mesh space (the coalesced element AABBs)."""
    minv = mat_inv(cols)
    if minv is None:
        return None
    o = matvec(minv, vsub(origin, pos))
    d = matvec(minv, direction)
    o = (o[0] / scale[0], o[1] / scale[1], o[2] / scale[2])
    d = (d[0] / scale[0], d[1] / scale[1], d[2] / scale[2])
    tmin, tmax = -1e30, 1e30
    for i in range(3):
        if abs(d[i]) < 1e-12:
            if o[i] < e.aabb[0][i] or o[i] > e.aabb[1][i]:
                return None
            continue
        t1 = (e.aabb[0][i] - o[i]) / d[i]
        t2 = (e.aabb[1][i] - o[i]) / d[i]
        if t1 > t2:
            t1, t2 = t2, t1
        tmin = max(tmin, t1)
        tmax = min(tmax, t2)
        if tmin > tmax:
            return None
    if tmax < 0:
        return None
    return tmin if tmin >= 0 else 0.0


def ray_sphere_element(origin, direction, e, cols, pos, scale):
    minv = mat_inv(cols)
    if minv is None:
        return None
    o = matvec(minv, vsub(origin, pos))
    d = matvec(minv, direction)
    o = (o[0] / scale[0], o[1] / scale[1], o[2] / scale[2])
    d = (d[0] / scale[0], d[1] / scale[1], d[2] / scale[2])
    oc = vsub(o, e.center)
    a = vdot(d, d)
    if a < 1e-14:
        return None
    b = 2.0 * vdot(oc, d)
    c = vdot(oc, oc) - e.radius * e.radius
    disc = b * b - 4 * a * c
    if disc < 0:
        return None
    sq = math.sqrt(disc)
    t = (-b - sq) / (2 * a)
    if t < 0:
        t = (-b + sq) / (2 * a)
    return t if t >= 0 else None


def ray_capsule_element(origin, direction, e, cols, pos, scale):
    """Capsule whose axis is element-local Y after _rotator_basis."""
    minv = mat_inv(cols)
    if minv is None:
        return None
    o = matvec(minv, vsub(origin, pos))
    d = matvec(minv, direction)
    o = (o[0] / scale[0], o[1] / scale[1], o[2] / scale[2])
    d = (d[0] / scale[0], d[1] / scale[1], d[2] / scale[2])
    rinv = mat_inv(e.rcols)
    if rinv is None:
        return None
    o = matvec(rinv, vsub(o, e.center))
    d = matvec(rinv, d)
    axis = (0.0, 1.0, 0.0)
    a = vdot(d, d)
    if a < 1e-14:
        return None
    best = None
    # cylinder segment
    d_par = vdot(d, axis)
    o_par = vdot(o, axis)
    dp = vsub(d, vmul(axis, d_par))
    op = vsub(o, vmul(axis, o_par))
    A = vdot(dp, dp)
    if A > 1e-14:
        B = 2.0 * vdot(op, dp)
        C = vdot(op, op) - e.radius * e.radius
        disc = B * B - 4 * A * C
        if disc >= 0:
            sq = math.sqrt(disc)
            for t in ((-B - sq) / (2 * A), (-B + sq) / (2 * A)):
                if t >= 0:
                    y = o_par + t * d_par
                    if -e.half_len <= y <= e.half_len:
                        best = t if best is None else min(best, t)
    # caps
    for cap_y in (-e.half_len, e.half_len):
        oc = vsub(o, (0.0, cap_y, 0.0))
        B = 2.0 * vdot(oc, d)
        C = vdot(oc, oc) - e.radius * e.radius
        disc = B * B - 4 * a * C
        if disc < 0:
            continue
        sq = math.sqrt(disc)
        for t in ((-B - sq) / (2 * a), (-B + sq) / (2 * a)):
            if t >= 0:
                best = t if best is None else min(best, t)
    return best


def convex_top_at(pts, x, z):
    """Exact upper surface of conv(pts) on the vertical line through (x, z).

    The LP `max y s.t. sum(l_i p_i) = (x, y, z), sum l = 1, l >= 0` has three
    equality constraints, so its optimum uses at most three non-zero weights;
    enumerating vertex triples is exact.  Branch-and-bound on the descending y
    order makes the common (flat slab) case O(n^2).
    """
    n = len(pts)
    if n == 0:
        return None
    if n == 1:
        p = pts[0]
        return p[1] if abs(p[0] - x) < 1e-7 and abs(p[2] - z) < 1e-7 else None
    order = sorted(range(n), key=lambda i: -pts[i][1])
    best = -1e30
    for ii in range(n):
        i = order[ii]
        pi = pts[i]
        if pi[1] <= best:
            break
        for jj in range(ii + 1, n):
            j = order[jj]
            pj = pts[j]
            if pj[1] <= best:
                break
            for kk in range(jj + 1, n):
                k = order[kk]
                pk = pts[k]
                if pk[1] <= best:
                    break
                # barycentric in XZ
                ax, az = pi[0], pi[2]
                bx, bz = pj[0], pj[2]
                cx, cz = pk[0], pk[2]
                det = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
                if abs(det) < 1e-12:
                    continue
                l1 = ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / det
                l2 = ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / det
                l3 = 1.0 - l1 - l2
                if l1 < -1e-9 or l2 < -1e-9 or l3 < -1e-9:
                    continue
                y = l1 * pi[1] + l2 * pj[1] + l3 * pk[1]
                if y > best:
                    best = y
    return None if best < -1e29 else best


# --------------------------------------------------------------------------
# collision database
# --------------------------------------------------------------------------
def load_collision_db():
    d = json.load(open(MESH_COLLISION))
    return d.get("meshes", {})


def build_collision_cache(db, instances, note, heuristic=False):
    """Per UE path: decoded elements + mesh AABB + source + instance count."""
    counts = Counter()
    for rec in instances:
        if rec["reason"] is None:
            counts[rec["mesh"]] += 1
    cache = {}
    for mp, n in counts.items():
        raw = db.get(mp)
        if raw is not None:
            raw = dict(raw)
            raw["_path"] = mp
        kind, elements, reduced = decode_mesh(raw, n, note, heuristic, mp)
        cache[mp] = {
            "source": kind,
            "elements": elements,
            "reduced": reduced,
            "instances": n,
            "aabb": path_aabb(elements),
            "explicit": mp in db,
        }
    return cache


# --------------------------------------------------------------------------
# ray against all instanced colliders
# --------------------------------------------------------------------------
def cast_vertical(instances, cache, x, z, ytop, ybot, near=40.0, collect=0):
    """Return hits sorted by descending y: (y, mesh, elem_kind, file, source)."""
    hits = []
    unmodelled_near = Counter()
    for rec in instances:
        if rec["reason"] is not None:
            continue
        pos = rec["pos"]
        if abs(pos[0] - x) > near or abs(pos[2] - z) > near:
            continue
        info = cache.get(rec["mesh"])
        if info is None or info["aabb"] is None:
            continue
        lo, hi = instance_world_aabb(info["aabb"], pos, rec["cols"], rec["scale"])
        if x < lo[0] - 0.02 or x > hi[0] + 0.02:
            continue
        if z < lo[2] - 0.02 or z > hi[2] + 0.02:
            continue
        if hi[1] < ybot or lo[1] > ytop:
            continue
        origin = (x, ytop, z)
        direction = (0.0, -1.0, 0.0)
        for e in info["elements"]:
            if e.kind == "convex":
                # exact vertical top in world space
                m = mat_inv(rec["cols"])
                if m is None:
                    continue
                pts = []
                for p in e.mesh_pts:
                    lv = (
                        p[0] * rec["scale"][0],
                        p[1] * rec["scale"][1],
                        p[2] * rec["scale"][2],
                    )
                    pts.append(vadd(pos, matvec(rec["cols"], lv)))
                y = convex_top_at(pts, x, z)
                if y is None:
                    continue
                t = ytop - y
                if t < -1e-6 or y < ybot - 1e-6 or y > ytop + 1e-6:
                    # still allow a top above ytop? no: the ray starts at ytop
                    if y > ytop + 1e-6:
                        continue
                hits.append((y, rec["mesh"], "convex", rec["file"], info["source"]))
            elif e.kind == "box" and e.src in (
                "coalesced_aabb",
                "absent_box",
                "absent_trimesh_aabb",
            ):
                t = ray_box_mesh(origin, direction, e, rec["cols"], pos, rec["scale"])
                if t is not None:
                    y = ytop - t
                    if ybot - 1e-6 <= y <= ytop + 1e-6:
                        hits.append(
                            (
                                y,
                                rec["mesh"],
                                e.src,
                                rec["file"],
                                info["source"],
                            )
                        )
            elif e.kind == "box":
                t = ray_box_element(
                    origin, direction, e, rec["cols"], pos, rec["scale"]
                )
                if t is not None:
                    y = ytop - t
                    if ybot - 1e-6 <= y <= ytop + 1e-6:
                        hits.append(
                            (y, rec["mesh"], "box", rec["file"], info["source"])
                        )
            elif e.kind == "sphere":
                t = ray_sphere_element(
                    origin, direction, e, rec["cols"], pos, rec["scale"]
                )
                if t is not None:
                    y = ytop - t
                    if ybot - 1e-6 <= y <= ytop + 1e-6:
                        hits.append(
                            (y, rec["mesh"], "sphere", rec["file"], info["source"])
                        )
            elif e.kind == "sphyl":
                t = ray_capsule_element(
                    origin, direction, e, rec["cols"], pos, rec["scale"]
                )
                if t is not None:
                    y = ytop - t
                    if ybot - 1e-6 <= y <= ytop + 1e-6:
                        hits.append(
                            (y, rec["mesh"], "sphyl", rec["file"], info["source"])
                        )
    # Collision the model cannot resolve: UE complex-as-simple render trimeshes,
    # or an `absent` path whose GLB could not be decoded.
    for rec in instances:
        if rec["reason"] is not None:
            continue
        info = cache.get(rec["mesh"])
        if info is None or info["aabb"] is not None:
            continue
        if info["source"] not in ("complex_default", "absent_no_glb"):
            continue
        pos = rec["pos"]
        if abs(pos[0] - x) <= 8.0 and abs(pos[2] - z) <= 8.0:
            unmodelled_near[info["source"] + ":" + rec["mesh"]] += 1
    hits.sort(key=lambda h: -h[0])
    return hits, unmodelled_near


# --------------------------------------------------------------------------
# player spawn replay
# --------------------------------------------------------------------------
def spawn_anchor(instances, cache, spawns, verbose=True):
    chosen = None
    chosen_hit = None
    for t in spawns:
        p = t["pos"]
        hits, _ = cast_vertical(
            instances, cache, p[0], p[2], p[1] + 1.0, p[1] - 6.0, near=20.0
        )
        if hits:
            chosen = t
            chosen_hit = hits[0][0]
            if verbose:
                print(
                    "  player-start candidate %-28s %s first hit %.3f  -> chosen"
                    % (t["name"], fmt_v(p), chosen_hit)
                )
            break
        if verbose:
            print(
                "  player-start candidate %-28s %s no hit in +1..-6"
                % (t["name"], fmt_v(p))
            )
    if chosen is None:
        return None, None, None
    p = chosen["pos"]
    # _spawn_player: spawn = pos + (0,1,0); _snap_player_to_ground from +0.5 to -32
    snap_hits, _ = cast_vertical(
        instances, cache, p[0], p[2], p[1] + 1.5, p[1] - 31.0, near=20.0
    )
    snap = snap_hits[0][0] if snap_hits else None
    if snap is None:
        anchor = (p[0], p[1] + 1.0, p[2])
    else:
        anchor = (p[0], snap + 0.15, p[2])
    return chosen, anchor, snap


def fmt_v(p):
    return "(%.4f, %.4f, %.4f)" % p


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--files", action="store_true")
    ap.add_argument("--select", action="store_true")
    ap.add_argument("--json", default="")
    ap.add_argument("--near", type=float, default=40.0)
    ap.add_argument(
        "--heuristic-aabb",
        action="store_true",
        help="model `absent` meshes with the loader's AABB fallback "
        "(requires the extracted GLBs in game/assets/ue)",
    )
    args = ap.parse_args(argv)

    files, notes = loader_file_order(verbose=True)
    print("== loader file order for guildhall order=2 ==")
    for i, (key, path, decorative) in enumerate(files):
        d = json.load(open(path))
        print(
            "%2d %-55s models=%-4d decorative=%s"
            % (i + 1, key, len(d.get("meshes", []) or []), decorative)
        )
    print("notes:", dict(notes))

    replay = replay_markers(files)
    print("\n== marker replay ==")
    print(
        "guard markers:",
        len(replay["guard_spawns"]),
        "  smart objects excluded:",
        replay["smart_objects"],
        "  player starts:",
        len(replay["player_spawns"]),
    )
    print("per-file markers:", dict(replay["marker_by_file"]))
    print("non-guard marker classes:", dict(replay["skipped"]))

    if args.files:
        return 0

    db = load_collision_db()
    note = Counter()
    instances = []
    for key, mp, pos, cols, scale, ov, hidden, reason in iter_instances(files):
        instances.append(
            {
                "file": key,
                "mesh": mp,
                "pos": pos,
                "cols": cols,
                "scale": scale,
                "ov": ov,
                "hidden": hidden,
                "reason": reason,
            }
        )
    print(
        "\nraw instanced meshes:",
        len(instances),
        " skipped:",
        dict(Counter(r["reason"] for r in instances if r["reason"])),
    )
    cache = build_collision_cache(db, instances, note, heuristic=args.heuristic_aabb)
    print(
        "collision cache paths:",
        len(cache),
        " authored:",
        sum(1 for v in cache.values() if v["explicit"]),
        " absent:",
        sum(1 for v in cache.values() if v["source"] == "absent"),
        " absent_heuristic:",
        sum(1 for v in cache.values() if v["source"] == "absent_heuristic"),
        " complex_default:",
        sum(1 for v in cache.values() if v["source"] == "complex_default"),
        " no_collision:",
        sum(1 for v in cache.values() if v["source"] == "no_collision"),
        " reduced:",
        sum(1 for v in cache.values() if v["reduced"]),
    )
    absent_instances = sum(
        1 for r in instances if r["reason"] is None and not cache[r["mesh"]]["explicit"]
    )
    print(
        "instanced meshes with no mesh_collision entry (collide=true):",
        absent_instances,
        "of",
        sum(1 for r in instances if r["reason"] is None),
    )
    print("decode notes:", dict(note))

    chosen, anchor, snap = spawn_anchor(instances, cache, replay["player_spawns"])
    if chosen is None:
        print("!! no player start had a floor hit; cannot reproduce the anchor")
        anchor = (0.0, 2.0, 0.0)
    print(
        "\nanchor: player.global_position = %s (start %s, snap hit %s)"
        % (fmt_v(anchor), chosen["name"] if chosen else "?", snap)
    )

    limit = 4  # GameState.Difficulty.NOVICE
    eligible = []
    for g in replay["guard_spawns"]:
        p = g["pos"]
        d = vlen(vsub(p, anchor))
        if d > 10.0 and d < 120.0:
            eligible.append((len(eligible) + 1, g, d))
    print("eligible (10 < d < 120):", len(eligible))
    print(
        "\nrank  markername                          authored pos                 dist"
    )
    for rank, g, d in eligible[:16]:
        print("%4d  %-38s %-27s %7.2f" % (rank, g["name"], fmt_v(g["pos"]), d))
    picked = [e for e in eligible[:limit]]

    if args.select:
        return 0

    print("\n== ingest prediction (Novice limit %d) ==" % limit)
    rows = []
    for rank, g, d in picked:
        p = g["pos"]
        hits, unmodelled = cast_vertical(
            instances, cache, p[0], p[2], p[1] + 8.0, p[1] - 30.0, near=args.near
        )
        first = hits[0] if hits else None
        below = None
        for h in hits:
            if h[0] <= p[1] + 0.05:
                below = h
                break
        grounded = (first[0] + 0.15) if first else (p[1] + 0.5)
        cls = "CEILING" if first and first[0] > p[1] + 1.0 else "FLOOR"
        rows.append(
            {
                "rank": rank,
                "name": g["name"],
                "pos": p,
                "dist": d,
                "first": first,
                "grounded": grounded,
                "below": below,
                "class": cls,
                "unmodelled": unmodelled,
            }
        )
        print("\n#%d %s  authored %s  d=%.2f" % (rank, g["name"], fmt_v(p), d))
        print(
            "   ray: (%0.4f, %.4f, %.4f) -> (%.4f, %.4f, %.4f)"
            % (p[0], p[1] + 8.0, p[2], p[0], p[1] - 30.0, p[2])
        )
        print(
            "   first hit: %s  y=%.4f  mesh=%s  (%s, %s)"
            % (
                "yes" if first else "NO HIT",
                first[0] if first else float("nan"),
                first[1] if first else "-",
                first[2] if first else "-",
                first[4] if first else "-",
            )
        )
        print(
            "   grounded = hit + 0.15 = %.4f   (%+.3f vs marker)  %s"
            % (grounded, grounded - p[1], cls)
        )
        if below:
            print(
                "   highest hit below marker (y <= %.2f): y=%.4f mesh=%s (%s)"
                % (p[1] + 0.05, below[0], below[1], below[2])
            )
        else:
            print("   no modelled hit below the marker")
        if unmodelled:
            print("   unmodelled collision near column: %s" % dict(unmodelled))
        # a few more hits for context
        for h in hits[1:4]:
            print("     next hit: y=%.4f mesh=%s (%s)" % (h[0], h[1], h[2]))

    print(
        "\n== TABLE (model=%s) =="
        % (
            "authored + absent-AABB fallback"
            if args.heuristic_aabb
            else "authored only"
        )
    )
    print(
        "rank name                                    marker                    "
        "first_hit_y first_hit_mesh                                    grounded  "
        "floor_y   floor_mesh                                     class"
    )
    for r in rows:
        f = r["first"]
        b = r["below"]
        print(
            "%4d %-38s %-25s %10s %-46s %8.3f %8s %-46s %s"
            % (
                r["rank"],
                r["name"],
                fmt_v(r["pos"]),
                ("%.3f" % f[0]) if f else "NO HIT",
                ((f[1].split("/")[-1] + " [" + str(f[2]) + "]") if f else "-"),
                r["grounded"],
                ("%.3f" % b[0]) if b else "-",
                (b[1].split("/")[-1] if b else "-"),
                r["class"],
            )
        )

    if args.json:
        out = []
        for r in rows:
            out.append(
                {
                    "rank": r["rank"],
                    "name": r["name"],
                    "marker": list(r["pos"]),
                    "first_hit_y": r["first"][0] if r["first"] else None,
                    "first_hit_mesh": r["first"][1] if r["first"] else None,
                    "first_hit_kind": r["first"][2] if r["first"] else None,
                    "grounded_y": r["grounded"],
                    "real_floor_y": r["below"][0] if r["below"] else None,
                    "real_floor_mesh": r["below"][1] if r["below"] else None,
                    "class": r["class"],
                }
            )
        json.dump(out, open(args.json, "w"), indent=1)
        print("\nwrote", args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
