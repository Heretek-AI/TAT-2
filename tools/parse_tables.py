#!/usr/bin/env python3
"""
Normalize extracted UE5 JSON tables, string tables, curves, and level actors
into clean Godot-friendly JSON under game/data/generated/.
Full support for World Partition sublevels (OldManor_Geo, Guildhall_Geometry, ThievesDen_Geo),
PackedLevelActors (BPP_*_PLA), InstancedStaticMeshComponent (PerInstanceSMData), and AttachParent hierarchies.
"""

import json
import math
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX = ROOT / "extracted"
OUT_DATA = ROOT / "game" / "data" / "generated"
OUT_FONTS = ROOT / "game" / "assets" / "ue" / "fonts"


# ---------------------------------------------------------------------------
# UE5 -> Godot 4x4 Transform Math (pure Python, zero dependencies)
# ---------------------------------------------------------------------------
def mat4_identity():
    return [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]


def mat4_mul(a, b):
    return [
        [sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)
    ]


def ue_quat_to_mat3(q: dict):
    x = float(q.get("X", 0.0))
    y = float(q.get("Y", 0.0))
    z = float(q.get("Z", 0.0))
    w = float(q.get("W", 1.0))
    n = math.sqrt(x * x + y * y + z * z + w * w)
    if n > 1e-8:
        x /= n
        y /= n
        z /= n
        w /= n
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    return [
        [1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy)],
        [2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx)],
        [2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy)],
    ]


def ue_rotator_to_mat3(r: dict):
    # UE FRotator: Pitch (Y), Yaw (Z), Roll (X) in degrees
    p = math.radians(float(r.get("Pitch", 0.0)))
    y = math.radians(float(r.get("Yaw", 0.0)))
    ro = math.radians(float(r.get("Roll", 0.0)))
    cp, sp = math.cos(p), math.sin(p)
    cy, sy = math.cos(y), math.sin(y)
    cr, sr = math.cos(ro), math.sin(ro)
    # UE FRotationMatrix::MakeFromEuler
    return [
        [cp * cy, sr * sp * cy - cr * sy, -(cr * sp * cy + sr * sy)],
        [cp * sy, sr * sp * sy + cr * cy, cr * sp * sy - sr * cy],
        [sp, -sr * cp, cr * cp],
    ]


def ue_trs_to_mat4(
    loc: dict | None, rot: dict | None, scale: dict | None, is_quat: bool = False
):
    if rot:
        r3 = ue_quat_to_mat3(rot) if is_quat else ue_rotator_to_mat3(rot)
    else:
        r3 = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    sx = float((scale or {}).get("X", 1.0))
    sy = float((scale or {}).get("Y", 1.0))
    sz = float((scale or {}).get("Z", 1.0))
    tx = float((loc or {}).get("X", 0.0))
    ty = float((loc or {}).get("Y", 0.0))
    tz = float((loc or {}).get("Z", 0.0))
    return [
        [r3[0][0] * sx, r3[0][1] * sy, r3[0][2] * sz, tx],
        [r3[1][0] * sx, r3[1][1] * sy, r3[1][2] * sz, ty],
        [r3[2][0] * sx, r3[2][1] * sy, r3[2][2] * sz, tz],
        [0.0, 0.0, 0.0, 1.0],
    ]


def ue_mat4_to_godot_trs(m):
    # Swap Y and Z in both rows and cols: P * M * P where P swaps index 1 and 2
    p = [m[0][3] * 0.01, m[2][3] * 0.01, m[1][3] * 0.01]
    # Basis columns in Godot space (before normalizing)
    c0 = [m[0][0], m[2][0], m[1][0]]
    c1 = [m[0][2], m[2][2], m[1][2]]
    c2 = [m[0][1], m[2][1], m[1][1]]
    sx = math.sqrt(sum(v * v for v in c0)) or 1.0
    sy = math.sqrt(sum(v * v for v in c1)) or 1.0
    sz = math.sqrt(sum(v * v for v in c2)) or 1.0
    return {
        "pos": [round(p[0], 4), round(p[1], 4), round(p[2], 4)],
        "basis": [
            round(c0[0] / sx, 5),
            round(c1[0] / sy, 5),
            round(c2[0] / sz, 5),
            round(c0[1] / sx, 5),
            round(c1[1] / sy, 5),
            round(c2[1] / sz, 5),
            round(c0[2] / sx, 5),
            round(c1[2] / sy, 5),
            round(c2[2] / sz, 5),
        ],
        "scale": [round(sx, 4), round(sy, 4), round(sz, 4)],
    }


def extract_datatables():
    tables_dir = OUT_DATA / "tables"
    tables_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    for jf in (EX / "json").rglob("*.json"):
        try:
            data = json.loads(jf.read_text())
        except Exception:
            continue
        if not isinstance(data, list) or not data:
            continue
        exp = data[0]
        t = exp.get("Type")
        if t in ("DataTable", "CurveTable", "CompositeDataTable", "StringTable"):
            rel = jf.relative_to(EX / "json")
            dst = tables_dir / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            out = {
                "type": t,
                "name": exp.get("Name"),
                "rows": exp.get("Rows")
                or (exp.get("StringTable") or {}).get("KeysToMetaData")
                or {},
            }
            if t == "StringTable":
                st = exp.get("StringTable") or {}
                out["entries"] = st.get("KeysToEntries", {})
            dst.write_text(json.dumps(out, indent=2))
            count += 1
    print(f"Normalized {count} DataTable/CurveTable/StringTable JSONs -> {tables_dir}")


def build_bp_mesh_templates():
    """Index Blueprint CDO/SCS component -> StaticMesh mappings from all Blueprints & BPP_*_PLA."""
    templates = {}
    scan_files = list((EX / "json" / "Maps").rglob("BPP_*.json"))
    for jf in (EX / "json").rglob("*.json"):
        if "/Maps/" in str(jf) or "\\Maps\\" in str(jf):
            continue
        scan_files.append(jf)
    for jf in scan_files:
        try:
            exps = json.loads(jf.read_text())
        except Exception:
            continue
        if not isinstance(exps, list):
            continue
        bp_name = jf.stem + "_C"
        comp_meshes = templates.setdefault(bp_name, {})
        for e in exps:
            if e.get("Type") in (
                "InstancedStaticMeshComponent",
                "HierarchicalInstancedStaticMeshComponent",
                "StaticMeshComponent",
            ):
                name = e.get("Name", "").replace("_GEN_VARIABLE", "")
                props = e.get("Properties") or {}
                sm = (props.get("StaticMesh") or {}).get("ObjectPath")
                if sm:
                    loc = props.get("RelativeLocation")
                    rot = props.get("RelativeRotation")
                    scl = props.get("RelativeScale3D")
                    lmat = (
                        ue_trs_to_mat4(loc, rot, scl, is_quat=False)
                        if (loc or rot or scl)
                        else None
                    )
                    comp_meshes[name] = {"sm": sm.split(".")[0], "local": lmat}
    templates = {k: v for k, v in templates.items() if v}
    print(f"Indexed {len(templates)} Blueprint/PLA mesh templates")
    return templates


def build_level_transforms():
    """Extract LevelStreamingAlwaysLoaded LevelTransform matrices keyed by normalized sublevel path."""
    lmap = {}
    for jf in (EX / "json" / "Maps").rglob("*_P.json"):
        try:
            exps = json.loads(jf.read_text())
        except Exception:
            continue
        if not isinstance(exps, list):
            continue
        for e in exps:
            if e.get("Type") != "LevelStreamingAlwaysLoaded":
                continue
            props = e.get("Properties") or {}
            wa = ((props.get("WorldAsset") or {}).get("AssetPathName") or "").split(
                "."
            )[0]
            lt = props.get("LevelTransform")
            if not wa or not isinstance(lt, dict):
                continue
            t = lt.get("Translation")
            r = lt.get("Rotation")
            s = lt.get("Scale3D")
            if t or r or s:
                lmap[wa.lower()] = ue_trs_to_mat4(t, r, s, is_quat=True)
    print(f"Indexed {len(lmap)} sublevel LevelTransforms")
    return lmap


def build_glb_stem_index():
    """Index all extracted .glb files under game/assets/ue/Content by stem -> /Game/... path."""
    content_dir = ROOT / "game" / "assets" / "ue" / "Content"
    by_name = {}
    if content_dir.exists():
        for glb in content_dir.rglob("*.glb"):
            rel = glb.relative_to(content_dir).with_suffix("")
            game_path = "/Game/" + str(rel).replace("\\", "/")
            by_name[glb.stem] = game_path
            by_name[glb.stem.lower()] = game_path
    print(f"Indexed {len(by_name) // 2} extracted .glb stems for component fallback")
    return by_name


# ---------------------------------------------------------------------------
# BP SCS template resolver for ignored level components (Niagara, Decal,
# RectLight, SkyLight, HeightFog, PostProcess, SkyAtmosphere, VolumetricCloud)
# ---------------------------------------------------------------------------
# Level actor exports for BP actors list components by InternalVariableName,
# but the component exports in the level are stubs (AttachParent +
# CreationMethod only). The authored payload (Asset/Material/transforms) lives
# in the BP class JSON (SimpleConstructionScript AllNodes -> ComponentTemplate
# exports), possibly inherited through parent BP Template refs.
BP_COMPONENT_TYPES = {
    "NiagaraComponent",
    "DecalComponent",
    "RectLightComponent",
    "SkyLightComponent",
    "ExponentialHeightFogComponent",
    "PostProcessComponent",
    "SkyAtmosphereComponent",
    "VolumetricCloudComponent",
}

_bp_file_index = None
_bp_exports_cache = {}


def build_bp_file_index():
    """Map BP basename (stem) -> JSON path for all non-Maps extracted JSONs."""
    global _bp_file_index
    if _bp_file_index is not None:
        return _bp_file_index
    idx = {}
    for jf in (EX / "json").rglob("*.json"):
        s = str(jf)
        if "/Maps/" in s or "\\Maps\\" in s:
            continue
        idx.setdefault(jf.stem, jf)
    _bp_file_index = idx
    print(f"Indexed {len(idx)} Blueprint JSON files for SCS template resolution")
    return idx


def load_bp_exports(bp_class):
    """Load cached exports list for a BP class name like 'BP_EscapePoint_C'."""
    stem = bp_class.removesuffix("_C") if bp_class else bp_class
    if stem in _bp_exports_cache:
        return _bp_exports_cache[stem]
    idx = build_bp_file_index()
    jf = idx.get(stem)
    if jf is None:
        _bp_exports_cache[stem] = None
        return None
    try:
        exps = json.loads(jf.read_text())
    except Exception:
        _bp_exports_cache[stem] = None
        return None
    if not isinstance(exps, list):
        _bp_exports_cache[stem] = None
        return None
    rel = str(jf.relative_to(EX / "json"))
    _bp_exports_cache[stem] = (exps, rel)
    return _bp_exports_cache[stem]


def _parse_template_ref(objname):
    """'DecalComponent'BP_X_C:Decal_GEN_VARIABLE'' -> ('DecalComponent', 'BP_X_C', 'Decal_GEN_VARIABLE')."""
    try:
        t, rest = objname.split("'", 1)
        rest = rest.rstrip("'")
        outer, name = rest.split(":", 1)
        return t, outer, name
    except Exception:
        return None, None, None


def _resolve_template_in_bp(bp_class, tname, ttype=None, stub_name=None, depth=0):
    """Look up a ComponentTemplate export by name inside one BP file.

    Follows Template inheritance; builds the SCS ancestor chain for the SCS
    node whose ComponentTemplate (or InternalVariableName) matches.
    """
    if depth > 6 or not bp_class or not tname:
        return None
    loaded = load_bp_exports(bp_class)
    if not loaded:
        return None
    exps, rel = loaded
    by_type_name = {}
    scs_nodes = []
    for e in exps:
        by_type_name.setdefault((e.get("Type", ""), e.get("Name", "")), e)
        if e.get("Type") == "SCS_Node":
            scs_nodes.append(e)
    tpl = by_type_name.get((ttype or "", tname))
    if tpl is None:
        for (t, n_), e in by_type_name.items():
            if n_ == tname:
                tpl = e
                break
    if tpl is None:
        return None
    props = dict(tpl.get("Properties") or {})
    props = _merge_template_parent(props, tpl, depth)
    node = None
    for n in scs_nodes:
        nprops = n.get("Properties") or {}
        cref = (nprops.get("ComponentTemplate") or {}).get("ObjectName", "")
        if cref.split(":")[-1].rstrip("'") == tname or (
            stub_name and nprops.get("InternalVariableName") == stub_name
        ):
            node = n
            break
    chain = []
    if node is not None:
        child2parent = {}
        for n in scs_nodes:
            for c in (n.get("Properties") or {}).get("ChildNodes", []):
                cobj = c.get("ObjectName", "") if isinstance(c, dict) else ""
                cname = cobj.split(".")[-1].rstrip("'")
                child2parent[cname] = n.get("Name", "")
        lineage = []
        cur = node.get("Name", "")
        seen = set()
        while cur in child2parent and cur not in seen:
            seen.add(cur)
            cur = child2parent[cur]
            lineage.append(cur)
        for anc_name in reversed(lineage[:-1] if lineage else []):
            anc = next((n for n in scs_nodes if n.get("Name") == anc_name), None)
            if anc is None:
                continue
            aref = (anc.get("Properties") or {}).get("ComponentTemplate") or {}
            at, _, an = _parse_template_ref(aref.get("ObjectName", ""))
            aexp = by_type_name.get((at or "", an)) if an else None
            if aexp is None and an:
                for (t, n_), e in by_type_name.items():
                    if n_ == an:
                        aexp = e
                        break
            if aexp is not None:
                ap = aexp.get("Properties") or {}
                if (
                    ap.get("RelativeLocation")
                    or ap.get("RelativeRotation")
                    or ap.get("RelativeScale3D")
                ):
                    chain.append(
                        ue_trs_to_mat4(
                            ap.get("RelativeLocation"),
                            ap.get("RelativeRotation"),
                            ap.get("RelativeScale3D"),
                            is_quat=False,
                        )
                    )
    return {"props": props, "source": rel, "chain": chain}


def resolve_bp_component(
    bp_class, stub_name, stub_type=None, stub_template_ref=None, depth=0
):
    """Resolve a level component stub to its authored BP template.

    Returns dict(props=<merged Properties>, source=<bp rel path>,
    chain=[ancestor template-local mat4s top-down, root excluded]>) or None.
    Prefers the stub's own Template archetype ref, then SCS InternalVariableName
    matching, then CDO fallback. Follows Template inheritance refs up to 6
    levels; never invents values.
    """
    if depth > 6 or not bp_class:
        return None
    if stub_template_ref:
        ttype, touter, tname = _parse_template_ref(stub_template_ref)
        if touter and tname and touter.endswith("_C"):
            hit = _resolve_template_in_bp(
                touter, tname, ttype or stub_type, stub_name, depth
            )
            if hit is not None:
                return hit
    loaded = load_bp_exports(bp_class)
    if not loaded:
        return None
    exps, rel = loaded
    by_type_name = {}
    scs_nodes = []
    for e in exps:
        by_type_name.setdefault((e.get("Type", ""), e.get("Name", "")), e)
        if e.get("Type") == "SCS_Node":
            scs_nodes.append(e)
    node = None
    for n in scs_nodes:
        if (n.get("Properties") or {}).get("InternalVariableName") == stub_name:
            node = n
            break
    if node is not None:
        nprops = node.get("Properties") or {}
        tpl_ref = nprops.get("ComponentTemplate") or {}
        ttype, touter, tname = _parse_template_ref(tpl_ref.get("ObjectName", ""))
        if not tname:
            return None
        tpl = by_type_name.get((ttype or stub_type or "", tname))
        if tpl is None and stub_type:
            tpl = by_type_name.get((stub_type, tname))
        if tpl is None:
            # Fall back: any export with this template name
            for (t, n_), e in by_type_name.items():
                if n_ == tname:
                    tpl = e
                    break
        if tpl is None:
            return None
        props = dict(tpl.get("Properties") or {})
        # Inherit missing keys from parent BP archetype via Template ref.
        props = _merge_template_parent(props, tpl, depth)
        # SCS ancestor chain (root node excluded: level root instance carries placement).
        chain = []
        child2parent = {}
        for n in scs_nodes:
            for c in (n.get("Properties") or {}).get("ChildNodes", []):
                cobj = c.get("ObjectName", "") if isinstance(c, dict) else ""
                cname = cobj.split(".")[-1].rstrip("'")
                child2parent[cname] = n.get("Name", "")
        lineage = []
        cur = node.get("Name", "")
        seen = set()
        while cur in child2parent and cur not in seen:
            seen.add(cur)
            cur = child2parent[cur]
            lineage.append(cur)
        for anc_name in reversed(lineage[:-1] if lineage else []):
            anc = next((n for n in scs_nodes if n.get("Name") == anc_name), None)
            if anc is None:
                continue
            aref = (anc.get("Properties") or {}).get("ComponentTemplate") or {}
            at, _, an = _parse_template_ref(aref.get("ObjectName", ""))
            aexp = by_type_name.get((at or "", an)) if an else None
            if aexp is None and an:
                for (t, n_), e in by_type_name.items():
                    if n_ == an:
                        aexp = e
                        break
            if aexp is not None:
                ap = aexp.get("Properties") or {}
                if (
                    ap.get("RelativeLocation")
                    or ap.get("RelativeRotation")
                    or ap.get("RelativeScale3D")
                ):
                    chain.append(
                        ue_trs_to_mat4(
                            ap.get("RelativeLocation"),
                            ap.get("RelativeRotation"),
                            ap.get("RelativeScale3D"),
                            is_quat=False,
                        )
                    )
        return {"props": props, "source": rel, "chain": chain}
    # CDO/Default__ fallback: component authored directly on the class default object.
    for (t, n_), e in by_type_name.items():
        if t == (stub_type or "") and n_ in (stub_name, stub_name + "_GEN_VARIABLE"):
            cprops = dict(e.get("Properties") or {})
            cprops = _merge_template_parent(cprops, e, depth)
            return {"props": cprops, "source": rel, "chain": []}
    return None


def _merge_template_parent(props, tpl_export, depth):
    """Merge missing keys from parent BP archetype via Template ref (up to 6 levels)."""
    parent_ref = (
        (tpl_export.get("Template") or {}) if isinstance(tpl_export, dict) else {}
    )
    if not parent_ref or depth > 6:
        return props
    pt, pouter, pname = _parse_template_ref(parent_ref.get("ObjectName", ""))
    if not (pouter and pname):
        return props
    if pouter == tpl_export.get("_bp_class") and pname == tpl_export.get("Name"):
        return props
    parent = resolve_bp_component(pouter, pname, stub_type=pt or None, depth=depth + 1)
    if parent is not None:
        merged = dict(parent["props"])
        merged.update(props)
        return merged
    ploaded = load_bp_exports(pouter)
    if ploaded:
        for pe in ploaded[0]:
            if pe.get("Name") == pname and (not pt or pe.get("Type") == pt):
                merged = dict(pe.get("Properties") or {})
                merged.update(props)
                return merged
    return props


def _color_to_rgb(c):
    if not isinstance(c, dict):
        return None
    out = []
    for k in ("R", "G", "B"):
        try:
            out.append(round(float(c.get(k, 0.0)), 5))
        except Exception:
            out.append(0.0)
    return out


def _godot_euler_from_basis(basis):
    """Row-major 9-float basis -> YXZ euler degrees [pitch, yaw, roll]."""
    try:
        r00, r02 = basis[0], basis[2]
        r10, r11, r12 = basis[3], basis[4], basis[5]
        r22 = basis[8]
        v = max(-1.0, min(1.0, -r12))
        pitch = math.degrees(math.asin(v))
        if abs(abs(r12) - 1.0) > 1e-4:
            yaw = math.degrees(math.atan2(r02, r22))
            roll = math.degrees(math.atan2(r10, r11))
        else:
            yaw = math.degrees(math.atan2(-basis[6], r00))
            roll = 0.0
        return [round(pitch, 2), round(yaw, 2), round(roll, 2)]
    except Exception:
        return [0.0, 0.0, 0.0]


def _compact_pp_settings(settings):
    """Compact PostProcess Settings: scalars + blendable material paths only."""
    if not isinstance(settings, dict):
        return {}
    out = {}
    for k, v in settings.items():
        if k.startswith("bOverride_"):
            continue
        if isinstance(v, (int, float, bool, str)):
            out[k] = v
        elif isinstance(v, dict) and k == "WeightedBlendables":
            mats = []
            arr = v.get("Array") if isinstance(v.get("Array"), list) else []
            for item in arr:
                if isinstance(item, dict):
                    obj = item.get("Object") or {}
                    op = obj.get("ObjectPath", "") if isinstance(obj, dict) else ""
                    if op:
                        mats.append(op.split(".")[0])
            if mats:
                out["blendables"] = [m for m in mats if isinstance(m, str)]
        elif isinstance(v, dict) and set(v.keys()) <= {
            "X",
            "Y",
            "Z",
            "W",
            "R",
            "G",
            "B",
            "A",
            "Hex",
        }:
            out[k] = {kk: vv for kk, vv in v.items() if kk != "Hex"}
    return out


def _uu_vec_to_godot_m(v):
    """UE UU vector -> Godot meters with Y/Z swap (None-safe)."""
    if not isinstance(v, dict):
        return None
    try:
        return [
            round(float(v.get("X", 0.0)) * 0.01, 4),
            round(float(v.get("Z", 0.0)) * 0.01, 4),
            round(float(v.get("Y", 0.0)) * 0.01, 4),
        ]
    except Exception:
        return None


def _stub_actor(exps, idx):
    """(bp_class_or_None, actor_name_or_None) from a component's Outer."""
    outer = exps[idx].get("Outer") or {}
    on = outer.get("ObjectName", "") if isinstance(outer, dict) else ""
    if on.startswith("Level'"):
        return None, None
    if "'" not in on:
        return None, None
    bp_class = on.split("'", 1)[0]
    actor = on.split(".")[-1].rstrip("'")
    return bp_class, actor


def _trs_with_rotation(wmat):
    trs = ue_mat4_to_godot_trs(wmat)
    trs["rotation"] = _godot_euler_from_basis(trs["basis"])
    return trs


def _compose_bp_world(
    exps,
    actor_by_name,
    comp_by_full_objname,
    get_world_mat,
    level_mat,
    actor_name,
    idx,
    resolved,
):
    """actor root world x SCS ancestor chain x component local."""
    wmat = mat4_identity()
    aidx = actor_by_name.get(actor_name or "")
    if aidx is not None:
        rc = (exps[aidx].get("Properties") or {}).get("RootComponent") or {}
        ridx = None
        if isinstance(rc, dict):
            ridx = comp_by_full_objname.get(rc.get("ObjectName", ""))
            if ridx is None and "PersistentLevel." in rc.get("ObjectName", ""):
                ridx = comp_by_full_objname.get(
                    rc["ObjectName"].split("PersistentLevel.")[-1].rstrip("'")
                )
        if ridx is not None:
            wmat = get_world_mat(ridx)
    if resolved:
        for link in resolved.get("chain") or []:
            wmat = mat4_mul(wmat, link)
        lp = resolved.get("props") or {}
        iprops = exps[idx].get("Properties") or {}
        if (
            iprops.get("RelativeLocation")
            or iprops.get("RelativeRotation")
            or iprops.get("RelativeScale3D")
        ):
            wmat = mat4_mul(
                wmat,
                ue_trs_to_mat4(
                    iprops.get("RelativeLocation"),
                    iprops.get("RelativeRotation"),
                    iprops.get("RelativeScale3D"),
                    is_quat=False,
                ),
            )
        elif (
            lp.get("RelativeLocation")
            or lp.get("RelativeRotation")
            or lp.get("RelativeScale3D")
        ):
            wmat = mat4_mul(
                wmat,
                ue_trs_to_mat4(
                    lp.get("RelativeLocation"),
                    lp.get("RelativeRotation"),
                    lp.get("RelativeScale3D"),
                    is_quat=False,
                ),
            )
    else:
        wmat = get_world_mat(idx)
    if level_mat is not None:
        wmat = mat4_mul(level_mat, wmat)
    return wmat


def extract_levels():
    levels_dir = OUT_DATA / "levels"
    levels_dir.mkdir(parents=True, exist_ok=True)
    bp_templates = build_bp_mesh_templates()
    level_transforms = build_level_transforms()
    glb_by_name = build_glb_stem_index()
    count = 0
    total_meshes = 0
    total_lights = 0

    for jf in sorted((EX / "json" / "Maps").rglob("*.json")):
        if jf.name.startswith("BPP_"):
            continue
        try:
            exps = json.loads(jf.read_text())
        except Exception:
            continue
        if not isinstance(exps, list) or not exps:
            continue

        # Map export index (1-based in UE ObjectPath: "/Game/.../Map.123" -> exps[122] or exps[123]?)
        # Check CUE4Parse ObjectPath index: let's match by Name+Type or index!
        by_obj_name = {}
        for idx, e in enumerate(exps):
            t = e.get("Type", "")
            n = e.get("Name", "")
            outer = e.get("Outer")
            outer_str = (
                outer.get("ObjectName", "")
                if isinstance(outer, dict)
                else str(outer or "")
            )
            # Construct key matching ObjectName e.g. StaticMeshComponent'Map:PersistentLevel.Actor.Comp'
            by_obj_name[(t, n, outer_str)] = idx
            # Also map by ObjectPath suffix if Outer is PersistentLevel.Actor
            if "PersistentLevel." in outer_str:
                actor_part = outer_str.split("PersistentLevel.")[-1].rstrip("'")
                by_obj_name[(n, actor_part)] = idx

        # Build parent pointer map via AttachParent (using ObjectName!)
        # Actually in CUE4Parse JSON, ObjectPath ends with .N (1-based index into exps? Let's verify safely via ObjectName!)
        comp_by_full_objname = {}
        for idx, e in enumerate(exps):
            props = e.get("Properties") or {}
            # Store index by (Type, Name) and full PersistentLevel path if available
            outer = e.get("Outer")
            outer_name = outer.get("ObjectName", "") if isinstance(outer, dict) else ""
            if "PersistentLevel." in outer_name:
                actor_name = outer_name.split("PersistentLevel.")[-1].rstrip("'")
                full = f"{e.get('Type')}'{jf.stem}:PersistentLevel.{actor_name}.{e.get('Name')}'"
                comp_by_full_objname[full] = idx
                comp_by_full_objname[f"{actor_name}.{e.get('Name')}"] = idx

        world_cache = {}

        def get_world_mat(idx: int, depth: int = 0):
            if idx in world_cache:
                return world_cache[idx]
            if depth > 12 or idx < 0 or idx >= len(exps):
                return mat4_identity()
            e = exps[idx]
            props = e.get("Properties") or {}
            local = ue_trs_to_mat4(
                props.get("RelativeLocation"),
                props.get("RelativeRotation"),
                props.get("RelativeScale3D"),
                is_quat=False,
            )
            ap = props.get("AttachParent")
            if isinstance(ap, dict):
                ap_name = ap.get("ObjectName", "")
                pidx = comp_by_full_objname.get(ap_name)
                if pidx is None and "PersistentLevel." in ap_name:
                    tail = ap_name.split("PersistentLevel.")[-1].rstrip("'")
                    pidx = comp_by_full_objname.get(tail)
                if pidx is not None and pidx != idx:
                    local = mat4_mul(get_world_mat(pidx, depth + 1), local)
            world_cache[idx] = local
            return local

        rel = jf.relative_to(EX / "json" / "Maps")
        game_map_key = (
            "/Game/Maps/" + str(rel.with_suffix("")).replace("\\", "/")
        ).lower()
        level_mat = level_transforms.get(game_map_key)

        meshes = []
        lights = []
        markers = []
        landscapes = []
        rect_lights = []
        sky_lights = []
        fog_volumes = []
        post_process = []
        sky_atmospheres = []
        decals = []
        niagara = []
        volumes = []
        landscape_splines = []
        seen_components = set()
        niagara_unresolved = 0
        niagara_resolved = 0
        decals_unresolved = 0
        splines_skipped = 0

        actor_by_name = {}
        for aidx, ae in enumerate(exps):
            an = ae.get("Name", "")
            if an and an not in actor_by_name:
                actor_by_name[an] = aidx

        for idx, e in enumerate(exps):
            et = e.get("Type", "")
            props = e.get("Properties") or {}
            outer = e.get("Outer")
            outer_name = outer.get("ObjectName", "") if isinstance(outer, dict) else ""

            # 1. StaticMeshComponent / SplineMeshComponent (including Blueprint CDO/SCS template fallback)
            if et in ("StaticMeshComponent", "SplineMeshComponent"):
                sm = (props.get("StaticMesh") or {}).get("ObjectPath")
                bp_lmat = None
                if not sm and outer_name:
                    bp_cls = outer_name.split("'")[0]
                    cname = e.get("Name", "")
                    bp_map = bp_templates.get(bp_cls, {})
                    tpl = bp_map.get(cname) or bp_map.get(cname.rstrip("0123456789"))
                    if isinstance(tpl, dict):
                        sm = tpl.get("sm")
                        if not (
                            props.get("RelativeLocation")
                            or props.get("RelativeRotation")
                            or props.get("RelativeScale3D")
                        ):
                            bp_lmat = tpl.get("local")
                if not sm:
                    cname = e.get("Name", "")
                    base_c = cname.rstrip("0123456789")
                    sm = glb_by_name.get(cname) or glb_by_name.get(base_c)
                    if not sm and "deskvariant" in cname.lower():
                        sm = glb_by_name.get("sm_deskvariant_b") or glb_by_name.get(
                            "sm_deskvariant_a"
                        )
                if sm:
                    wmat = get_world_mat(idx)
                    if bp_lmat is not None:
                        wmat = mat4_mul(wmat, bp_lmat)
                    if level_mat is not None:
                        wmat = mat4_mul(level_mat, wmat)
                    trs = ue_mat4_to_godot_trs(wmat)
                    meshes.append({"mesh": sm.split(".")[0], **trs})
                    continue

            # 2. InstancedStaticMeshComponent / HierarchicalInstancedStaticMeshComponent / Foliage
            if et in (
                "InstancedStaticMeshComponent",
                "HierarchicalInstancedStaticMeshComponent",
                "FoliageInstancedStaticMeshComponent",
            ):
                sm = (props.get("StaticMesh") or {}).get("ObjectPath")
                if not sm and outer_name:
                    # Lookup from BPP_*_PLA template
                    bp_cls = outer_name.split("'")[0]
                    cname = e.get("Name", "")
                    tpl2 = bp_templates.get(bp_cls, {}).get(cname)
                    sm = tpl2.get("sm") if isinstance(tpl2, dict) else tpl2
                if sm:
                    wmat = get_world_mat(idx)
                    if level_mat is not None:
                        wmat = mat4_mul(level_mat, wmat)
                    instances = (
                        e.get("PerInstanceSMData")
                        or props.get("PerInstanceSMData")
                        or []
                    )
                    if instances:
                        for inst in instances:
                            td = inst.get("TransformData") or {}
                            imat = ue_trs_to_mat4(
                                td.get("Translation"),
                                td.get("Rotation"),
                                td.get("Scale3D"),
                                is_quat=True,
                            )
                            trs = ue_mat4_to_godot_trs(mat4_mul(wmat, imat))
                            meshes.append({"mesh": sm.split(".")[0], **trs})
                    else:
                        trs = ue_mat4_to_godot_trs(wmat)
                        meshes.append({"mesh": sm.split(".")[0], **trs})
                    continue

            # 3. Lights
            if (
                "PointLightComponent" in et
                or "SpotLightComponent" in et
                or "DirectionalLightComponent" in et
            ):
                wmat = get_world_mat(idx)
                if level_mat is not None:
                    wmat = mat4_mul(level_mat, wmat)
                trs = ue_mat4_to_godot_trs(wmat)
                lights.append(
                    {
                        "type": et,
                        "intensity": props.get("Intensity", 10.0),
                        "color": props.get("LightColor"),
                        "radius": round(
                            float(props.get("AttenuationRadius", 1000.0)) * 0.01, 2
                        ),
                        "outer_cone": props.get("OuterConeAngle"),
                        **trs,
                    }
                )
                continue

            # 4. Gameplay markers
            if any(
                k in et
                for k in (
                    "MissionSpawner",
                    "PlayerStart",
                    "Door",
                    "Escape",
                    "Guard",
                    "Patrol",
                    "Loot",
                    "Climb",
                )
            ):
                rc = props.get("RootComponent")
                wmat = mat4_identity()
                if isinstance(rc, dict):
                    rc_name = rc.get("ObjectName", "")
                    ridx = comp_by_full_objname.get(rc_name)
                    if ridx is not None:
                        wmat = get_world_mat(ridx)
                if level_mat is not None:
                    wmat = mat4_mul(level_mat, wmat)
                trs = ue_mat4_to_godot_trs(wmat)
                markers.append({"name": e.get("Name", ""), "class": et, **trs})

            # 5. LandscapeComponent heightfield terrain
            if et == "LandscapeComponent":
                htex = (props.get("HeightmapTexture") or {}).get("ObjectName", "")
                hname = htex.split(".")[-1].rstrip("'") if htex else ""
                if hname:
                    wmat = get_world_mat(idx)
                    if level_mat is not None:
                        wmat = mat4_mul(level_mat, wmat)
                    trs = ue_mat4_to_godot_trs(wmat)
                    bias = props.get("HeightmapScaleBias") or {}
                    h_rel = str(rel.parent / jf.stem).replace("\\", "/")
                    landscapes.append(
                        {
                            "heightmap": f"res://assets/ue/Raw/Maps/{h_rel}/{hname}.png",
                            "quads": int(props.get("ComponentSizeQuads", 63)),
                            "scale_bias": [
                                float(bias.get("X", 1.0 / 64.0)),
                                float(bias.get("Y", 1.0 / 64.0)),
                                float(bias.get("Z", 0.0)),
                                float(bias.get("W", 0.0)),
                            ],
                            **trs,
                        }
                    )
                continue

            # 6. BP-authored components ignored until now: resolve via SCS templates.
            if et in BP_COMPONENT_TYPES:
                bp_class, actor_name = _stub_actor(exps, idx)
                dedup_key = ((actor_name or ""), e.get("Name", ""), et)
                if dedup_key in seen_components:
                    continue
                seen_components.add(dedup_key)
                direct_payload = (
                    "Asset" in props
                    or "DecalMaterial" in props
                    or "SourceWidth" in props
                    or "SourceType" in props
                    or "Cubemap" in props
                    or "FogDensity" in props
                    or "Settings" in props
                    or "Material" in props
                    or "DecalSize" in props
                )
                resolved = None
                src = f"{rel}::{actor_name or e.get('Name', '')}"
                if not direct_payload and bp_class and bp_class.endswith("_C"):
                    tmpl = e.get("Template") or {}
                    tobj = tmpl.get("ObjectName", "") if isinstance(tmpl, dict) else ""
                    resolved = resolve_bp_component(
                        bp_class,
                        e.get("Name", ""),
                        stub_type=et,
                        stub_template_ref=tobj,
                    )
                    if resolved:
                        src = f"{resolved['source']}::{actor_name}"
                payload = dict(resolved["props"]) if resolved else {}
                if direct_payload:
                    for k, v in props.items():
                        payload.setdefault(k, v)
                if et == "NiagaraComponent":
                    asset = payload.get("Asset") or {}
                    op = asset.get("ObjectPath", "") if isinstance(asset, dict) else ""
                    if not op:
                        niagara_unresolved += 1
                        continue
                    if direct_payload:
                        wmat = get_world_mat(idx)
                        if level_mat is not None:
                            wmat = mat4_mul(level_mat, wmat)
                    else:
                        wmat = _compose_bp_world(
                            exps,
                            actor_by_name,
                            comp_by_full_objname,
                            get_world_mat,
                            level_mat,
                            actor_name,
                            idx,
                            resolved,
                        )
                    trs = _trs_with_rotation(wmat)
                    niagara.append(
                        {
                            "asset": op.split(".")[0],
                            "source_actor": actor_name or e.get("Name", ""),
                            "source": src,
                            **trs,
                        }
                    )
                    niagara_resolved += 1
                    continue
                if et == "DecalComponent":
                    mat = payload.get("DecalMaterial") or {}
                    mop = mat.get("ObjectPath", "") if isinstance(mat, dict) else ""
                    if not mop:
                        decals_unresolved += 1
                    if direct_payload:
                        wmat = get_world_mat(idx)
                        if level_mat is not None:
                            wmat = mat4_mul(level_mat, wmat)
                    else:
                        wmat = _compose_bp_world(
                            exps,
                            actor_by_name,
                            comp_by_full_objname,
                            get_world_mat,
                            level_mat,
                            actor_name,
                            idx,
                            resolved,
                        )
                    trs = _trs_with_rotation(wmat)
                    decals.append(
                        {
                            "material": mop.split(".")[0] if mop else None,
                            "size": _uu_vec_to_godot_m(payload.get("DecalSize")),
                            "source_actor": actor_name or e.get("Name", ""),
                            "source": src,
                            **trs,
                        }
                    )
                    continue
                if et == "RectLightComponent":
                    intensity = payload.get("Intensity", e.get("IntensityNits", 0.0))
                    try:
                        intensity = float(intensity)
                    except Exception:
                        intensity = 0.0
                    if direct_payload:
                        wmat = get_world_mat(idx)
                        if level_mat is not None:
                            wmat = mat4_mul(level_mat, wmat)
                    else:
                        wmat = _compose_bp_world(
                            exps,
                            actor_by_name,
                            comp_by_full_objname,
                            get_world_mat,
                            level_mat,
                            actor_name,
                            idx,
                            resolved,
                        )
                    trs = _trs_with_rotation(wmat)
                    rect_lights.append(
                        {
                            "intensity": intensity,
                            "color": _color_to_rgb(payload.get("LightColor")),
                            "width": round(float(payload.get("SourceWidth", 0.0)), 3),
                            "height": round(float(payload.get("SourceHeight", 0.0)), 3),
                            "radius": round(
                                float(payload.get("AttenuationRadius", 1000.0)) * 0.01,
                                2,
                            ),
                            "cast_shadows": bool(payload.get("CastShadows", True)),
                            "source_actor": actor_name or e.get("Name", ""),
                            "source": src,
                            **trs,
                        }
                    )
                    continue
                if et == "SkyLightComponent":
                    cub = payload.get("Cubemap") or {}
                    cop = cub.get("ObjectPath", "") if isinstance(cub, dict) else ""
                    if direct_payload:
                        wmat = get_world_mat(idx)
                        if level_mat is not None:
                            wmat = mat4_mul(level_mat, wmat)
                    else:
                        wmat = _compose_bp_world(
                            exps,
                            actor_by_name,
                            comp_by_full_objname,
                            get_world_mat,
                            level_mat,
                            actor_name,
                            idx,
                            resolved,
                        )
                    trs = _trs_with_rotation(wmat)
                    sky_lights.append(
                        {
                            "intensity": float(payload.get("Intensity", 1.0) or 0.0),
                            "color": _color_to_rgb(payload.get("LightColor")),
                            "cubemap": cop.split(".")[0] if cop else None,
                            "source_type": str(payload.get("SourceType", "")),
                            "source_actor": actor_name or e.get("Name", ""),
                            "source": src,
                            **trs,
                        }
                    )
                    continue
                if et == "ExponentialHeightFogComponent":
                    if direct_payload:
                        wmat = get_world_mat(idx)
                        if level_mat is not None:
                            wmat = mat4_mul(level_mat, wmat)
                    else:
                        wmat = _compose_bp_world(
                            exps,
                            actor_by_name,
                            comp_by_full_objname,
                            get_world_mat,
                            level_mat,
                            actor_name,
                            idx,
                            resolved,
                        )
                    trs = _trs_with_rotation(wmat)
                    fog_volumes.append(
                        {
                            "density": float(payload.get("FogDensity", 0.0) or 0.0),
                            "height_falloff": float(
                                payload.get("FogHeightFalloff", 0.0) or 0.0
                            ),
                            "inscattering": _color_to_rgb(
                                payload.get("FogInscatteringLuminance")
                            ),
                            "directional_inscattering": float(
                                payload.get("DirectionalInscatteringExponent", 0.0)
                                or 0.0
                            ),
                            "volumetric": bool(
                                payload.get("bEnableVolumetricFog", False)
                            ),
                            "source_actor": actor_name or e.get("Name", ""),
                            "source": src,
                            **trs,
                        }
                    )
                    continue
                if et == "PostProcessComponent":
                    if direct_payload:
                        wmat = get_world_mat(idx)
                        if level_mat is not None:
                            wmat = mat4_mul(level_mat, wmat)
                    else:
                        wmat = _compose_bp_world(
                            exps,
                            actor_by_name,
                            comp_by_full_objname,
                            get_world_mat,
                            level_mat,
                            actor_name,
                            idx,
                            resolved,
                        )
                    trs = _trs_with_rotation(wmat)
                    post_process.append(
                        {
                            "settings": _compact_pp_settings(payload.get("Settings")),
                            "source_actor": actor_name or e.get("Name", ""),
                            "source": src,
                            **trs,
                        }
                    )
                    continue
                if et == "SkyAtmosphereComponent":
                    if direct_payload:
                        wmat = get_world_mat(idx)
                        if level_mat is not None:
                            wmat = mat4_mul(level_mat, wmat)
                    else:
                        wmat = _compose_bp_world(
                            exps,
                            actor_by_name,
                            comp_by_full_objname,
                            get_world_mat,
                            level_mat,
                            actor_name,
                            idx,
                            resolved,
                        )
                    trs = _trs_with_rotation(wmat)
                    sky_atmospheres.append(
                        {
                            "source_actor": actor_name or e.get("Name", ""),
                            "source": src,
                            **trs,
                        }
                    )
                    continue
                if et == "VolumetricCloudComponent":
                    mat = payload.get("Material") or {}
                    mop = mat.get("ObjectPath", "") if isinstance(mat, dict) else ""
                    if direct_payload:
                        wmat = get_world_mat(idx)
                        if level_mat is not None:
                            wmat = mat4_mul(level_mat, wmat)
                    else:
                        wmat = _compose_bp_world(
                            exps,
                            actor_by_name,
                            comp_by_full_objname,
                            get_world_mat,
                            level_mat,
                            actor_name,
                            idx,
                            resolved,
                        )
                    trs = _trs_with_rotation(wmat)
                    post_process.append(
                        {
                            "settings": {
                                "volumetric_cloud_material": mop.split(".")[0]
                                if mop
                                else None
                            },
                            "source_actor": actor_name or e.get("Name", ""),
                            "source": src,
                            **trs,
                        }
                    )
                    continue

        # 7. Actor-level volumes (brush- or box-rooted): Blocking/Trigger/Physics/Nav.
        for idx, e in enumerate(exps):
            et = e.get("Type", "")
            if et == "PostProcessVolume":
                outer = e.get("Outer") or {}
                on = outer.get("ObjectName", "") if isinstance(outer, dict) else ""
                if not on.startswith("Level'"):
                    continue
                dedup_key = ("ppv", e.get("Name", ""), et)
                if dedup_key in seen_components:
                    continue
                seen_components.add(dedup_key)
                eprops = e.get("Properties") or {}
                comp_ref = eprops.get("RootComponent") or {}
                cidx = None
                if isinstance(comp_ref, dict):
                    cidx = comp_by_full_objname.get(comp_ref.get("ObjectName", ""))
                    if cidx is None and "PersistentLevel." in comp_ref.get(
                        "ObjectName", ""
                    ):
                        cidx = comp_by_full_objname.get(
                            comp_ref["ObjectName"]
                            .split("PersistentLevel.")[-1]
                            .rstrip("'")
                        )
                wmat = get_world_mat(cidx) if cidx is not None else mat4_identity()
                if level_mat is not None:
                    wmat = mat4_mul(level_mat, wmat)
                trs = _trs_with_rotation(wmat)
                settings = _compact_pp_settings(eprops.get("Settings"))
                settings["unbound"] = bool(eprops.get("bUnbound", False))
                post_process.append(
                    {
                        "settings": settings,
                        "source_actor": e.get("Name", ""),
                        "source": f"{rel}::{e.get('Name', '')}",
                        **trs,
                    }
                )
                continue
            if not any(
                k in et
                for k in (
                    "BlockingVolume",
                    "TriggerVolume",
                    "TriggerBox",
                    "PhysicsVolume",
                    "NavModifierVolume",
                    "NavMeshBoundsVolume",
                )
            ):
                continue
            outer = e.get("Outer") or {}
            on = outer.get("ObjectName", "") if isinstance(outer, dict) else ""
            if not on.startswith("Level'"):
                continue
            dedup_key = ("volume", e.get("Name", ""), et)
            if dedup_key in seen_components:
                continue
            seen_components.add(dedup_key)
            eprops = e.get("Properties") or {}
            comp_ref = (
                eprops.get("RootComponent") or eprops.get("CollisionComponent") or {}
            )
            cidx = None
            if isinstance(comp_ref, dict):
                cidx = comp_by_full_objname.get(comp_ref.get("ObjectName", ""))
                if cidx is None and "PersistentLevel." in comp_ref.get(
                    "ObjectName", ""
                ):
                    cidx = comp_by_full_objname.get(
                        comp_ref["ObjectName"].split("PersistentLevel.")[-1].rstrip("'")
                    )
            if cidx is None:
                continue
            ce = exps[cidx]
            cprops = ce.get("Properties") or {}
            wmat = get_world_mat(cidx)
            if level_mat is not None:
                wmat = mat4_mul(level_mat, wmat)
            trs = ue_mat4_to_godot_trs(wmat)
            extent = None
            if ce.get("Type") == "BoxComponent" and isinstance(
                cprops.get("BoxExtent"), dict
            ):
                be = cprops["BoxExtent"]
                try:
                    extent = [
                        round(float(be.get("X", 0.0)) * 0.01, 3),
                        round(float(be.get("Z", 0.0)) * 0.01, 3),
                        round(float(be.get("Y", 0.0)) * 0.01, 3),
                    ]
                except Exception:
                    extent = None
            elif ce.get("Type") == "BrushComponent":
                sc = cprops.get("RelativeScale3D") or {}
                try:
                    # Default brush cube is 200^3 UU; half-extent in meters == scale.
                    extent = [
                        round(abs(float(sc.get("X", 1.0))), 4),
                        round(abs(float(sc.get("Z", 1.0))), 4),
                        round(abs(float(sc.get("Y", 1.0))), 4),
                    ]
                except Exception:
                    extent = None
            if extent is None:
                continue
            volumes.append(
                {
                    "class": et,
                    "actor": e.get("Name", ""),
                    "pos": trs["pos"],
                    "extent": extent,
                }
            )

        # 8. Landscape spline segments (road/river splines with mesh refs).
        for idx, e in enumerate(exps):
            if e.get("Type") != "LandscapeSplineSegment":
                continue
            sprops = e.get("Properties") or {}
            pts = sprops.get("Points") or []
            if not pts:
                continue
            mesh_path = ""
            mat_path = ""
            for ref in sprops.get("LocalMeshComponents") or []:
                if not isinstance(ref, dict):
                    continue
                midx = comp_by_full_objname.get(ref.get("ObjectName", ""))
                if midx is None and "PersistentLevel." in ref.get("ObjectName", ""):
                    midx = comp_by_full_objname.get(
                        ref["ObjectName"].split("PersistentLevel.")[-1].rstrip("'")
                    )
                if midx is None:
                    continue
                me = exps[midx]
                sm = (me.get("Properties") or {}).get("StaticMesh") or {}
                sop = sm.get("ObjectPath", "") if isinstance(sm, dict) else ""
                if sop:
                    mesh_path = sop.split(".")[0]
                    mprops = me.get("Properties") or {}
                    for mk in ("OverrideMaterials", "Materials"):
                        mv = mprops.get(mk)
                        if isinstance(mv, list) and mv and isinstance(mv[0], dict):
                            first = mv[0]
                            obj = (
                                first.get("Object")
                                if isinstance(first.get("Object"), dict)
                                else first
                            )
                            mop = (
                                obj.get("ObjectPath", "")
                                if isinstance(obj, dict)
                                else ""
                            )
                            if mop:
                                mat_path = mop.split(".")[0]
                                break
                    break
            if not mesh_path:
                splines_skipped += 1
                continue
            out_pts = []
            widths = []
            for p in pts:
                c = _uu_vec_to_godot_m(p.get("Center")) if isinstance(p, dict) else None
                if c is None:
                    continue
                if level_mat is not None:
                    uu = [c[0] * 100.0, c[2] * 100.0, c[1] * 100.0, 1.0]
                    t = [
                        sum(level_mat[r][cc] * uu[cc] for cc in range(4))
                        for r in range(4)
                    ]
                    c = [
                        round(t[0] * 0.01, 4),
                        round(t[2] * 0.01, 4),
                        round(t[1] * 0.01, 4),
                    ]
                out_pts.append(c)
                left = p.get("Left") if isinstance(p, dict) else None
                right = p.get("Right") if isinstance(p, dict) else None
                if isinstance(left, dict) and isinstance(right, dict):
                    deltas = []
                    for _key in ("X", "Y", "Z"):
                        _a, _b = left.get(_key), right.get(_key)
                        if isinstance(_a, bool) or isinstance(_b, bool):
                            break
                        if not isinstance(_a, (int, float)) or not isinstance(
                            _b, (int, float)
                        ):
                            break
                        deltas.append(_a - _b)
                    if len(deltas) == 3:
                        widths.append(
                            math.sqrt(
                                deltas[0] * deltas[0]
                                + deltas[1] * deltas[1]
                                + deltas[2] * deltas[2]
                            )
                            * 0.01
                        )
            if not out_pts:
                splines_skipped += 1
                continue
            landscape_splines.append(
                {
                    "points": out_pts,
                    "width": round(sum(widths) / len(widths), 3) if widths else 0.0,
                    "mesh": mesh_path,
                    "material": mat_path,
                }
            )

        if (
            meshes
            or lights
            or markers
            or landscapes
            or rect_lights
            or sky_lights
            or fog_volumes
            or post_process
            or sky_atmospheres
            or decals
            or niagara
            or volumes
            or landscape_splines
        ):
            rel = jf.relative_to(EX / "json" / "Maps")
            dst = levels_dir / rel.with_suffix(".tatlevel.json")
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(
                json.dumps(
                    {
                        "source": str(rel),
                        "meshes": meshes,
                        "lights": lights,
                        "markers": markers,
                        "landscapes": landscapes,
                        "rect_lights": rect_lights,
                        "sky_lights": sky_lights,
                        "fog_volumes": fog_volumes,
                        "post_process": post_process,
                        "sky_atmospheres": sky_atmospheres,
                        "decals": decals,
                        "niagara": niagara,
                        "volumes": volumes,
                        "landscape_splines": landscape_splines,
                    }
                )
            )
            count += 1
            total_meshes += len(meshes)
            total_lights += len(lights)
            if (
                rect_lights
                or sky_lights
                or fog_volumes
                or post_process
                or sky_atmospheres
                or decals
                or niagara
                or volumes
                or landscape_splines
            ):
                print(
                    f"  {rel}: rect={len(rect_lights)} sky={len(sky_lights)} fog={len(fog_volumes)} "
                    f"pp={len(post_process)} atmo={len(sky_atmospheres)} decals={len(decals)} "
                    f"niagara={len(niagara)} (+{niagara_unresolved} unresolved) "
                    f"volumes={len(volumes)} splines={len(landscape_splines)} "
                    f"(+{decals_unresolved} decal-no-material, +{splines_skipped} spline-no-mesh)"
                )

    print(
        f"Normalized {count} level JSONs -> {total_meshes} mesh instances, {total_lights} lights"
    )


def copy_fonts():
    src = EX / "raw" / "TAT" / "Content" / "Art" / "UI" / "Fonts"
    if not src.exists():
        return
    OUT_FONTS.mkdir(parents=True, exist_ok=True)
    n = 0
    for uf in src.rglob("*.ufont"):
        rel = uf.relative_to(src).with_suffix(".ttf")
        dst = OUT_FONTS / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(uf, dst)
        n += 1
    print(f"Copied {n} .ufont -> .ttf in {OUT_FONTS}")


def main():
    extract_datatables()
    extract_levels()
    copy_fonts()


if __name__ == "__main__":
    main()
