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
    # m12 is the negated UE M[2][1] (M[2][1] = CR*SP*SY - SR*CY); this
    # negated form is what keeps the Godot basis orthonormal (cf.
    # game/src/core/weather_profile.gd moon_basis). The un-negated
    # literal shears meshes.
    return [
        [cp * cy, sr * sp * cy - cr * sy, -(cr * sp * cy + sr * sy)],
        [cp * sy, sr * sp * sy + cr * cy, sr * cy - cr * sp * sy],
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
    # Composed non-uniform scale can leave non-orthogonal columns; this
    # rebuilds a rigid rotation with Gram-Schmidt while preserving the scale
    # magnitudes. 44 baseline instances needed it.
    n0 = [v / sx for v in c0]
    n1_raw = [v / sy for v in c1]
    n1_proj = sum(n1_raw[i] * n0[i] for i in range(3))
    n1 = [n1_raw[i] - n1_proj * n0[i] for i in range(3)]
    n1_len = math.sqrt(sum(v * v for v in n1))
    if n1_len < 1e-8:
        axis = [1.0, 0.0, 0.0] if abs(n0[0]) < 0.9 else [0.0, 1.0, 0.0]
        n1 = [
            n0[1] * axis[2] - n0[2] * axis[1],
            n0[2] * axis[0] - n0[0] * axis[2],
            n0[0] * axis[1] - n0[1] * axis[0],
        ]
        n1_len = math.sqrt(sum(v * v for v in n1))
        if n1_len < 1e-8:
            n1 = [0.0, 1.0, 0.0]
            n1_len = 1.0
    n1 = [v / n1_len for v in n1]
    n2_raw = [v / sz for v in c2]
    n2_proj0 = sum(n2_raw[i] * n0[i] for i in range(3))
    n2_proj1 = sum(n2_raw[i] * n1[i] for i in range(3))
    n2 = [n2_raw[i] - n2_proj0 * n0[i] - n2_proj1 * n1[i] for i in range(3)]
    n2_len = math.sqrt(sum(v * v for v in n2))
    if n2_len < 1e-8:
        n2 = [
            n0[1] * n1[2] - n0[2] * n1[1],
            n0[2] * n1[0] - n0[0] * n1[2],
            n0[0] * n1[1] - n0[1] * n1[0],
        ]
        n2_len = math.sqrt(sum(v * v for v in n2))
        if n2_len < 1e-8:
            n2 = [0.0, 0.0, 1.0]
            n2_len = 1.0
    n2 = [v / n2_len for v in n2]
    return {
        "pos": [round(p[0], 4), round(p[1], 4), round(p[2], 4)],
        "basis": [
            round(n0[0], 5),
            round(n1[0], 5),
            round(n2[0], 5),
            round(n0[1], 5),
            round(n1[1], 5),
            round(n2[1], 5),
            round(n0[2], 5),
            round(n1[2], 5),
            round(n2[2], 5),
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
                    # Packed Level Actor instance transforms live in the
                    # component template export, not in the level stub.
                    instances = e.get("PerInstanceSMData") or props.get(
                        "PerInstanceSMData"
                    )
                    comp_meshes[name] = {
                        "sm": sm.split(".")[0],
                        "local": lmat,
                        "instances": instances if isinstance(instances, list) else [],
                        "type": e.get("Type", ""),
                    }
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
    """Map BP basename (stem) -> JSON path for non-Maps JSONs and Maps BPP_* PLAs."""
    global _bp_file_index
    if _bp_file_index is not None:
        return _bp_file_index
    idx = {}
    for jf in (EX / "json").rglob("*.json"):
        s = str(jf)
        if ("/Maps/" in s or "\\Maps\\" in s) and not jf.name.startswith("BPP_"):
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


_tpl_props_cache = {}
_bp_lookup_cache = {}


def _bp_by_type_name(bp_class):
    """Cached (Type, Name) -> export lookup for one BP JSON class."""
    stem = bp_class.removesuffix("_C") if bp_class else ""
    if stem.startswith("Default__"):
        stem = stem[len("Default__") :]
    if stem in _bp_lookup_cache:
        return _bp_lookup_cache[stem]
    loaded = load_bp_exports(stem + "_C" if stem else bp_class)
    if not loaded:
        _bp_lookup_cache[stem] = None
        return None
    by_tn = {}
    by_n = {}
    for be in loaded[0]:
        bn = be.get("Name", "")
        bt = be.get("Type", "")
        by_tn.setdefault((bt, bn), be)
        by_n.setdefault(bn, be)
    _bp_lookup_cache[stem] = (by_tn, by_n)
    return _bp_lookup_cache[stem]


def _resolve_tpl_chain_props(ttype, touter, tname, depth=0):
    """Merge a component Template's Properties across its Template inheritance chain."""
    key = (ttype or "", touter or "", tname or "")
    if key in _tpl_props_cache:
        return _tpl_props_cache[key]
    if depth > 6 or not touter or not tname:
        return {}
    lookup = _bp_by_type_name(touter)
    if not lookup:
        _tpl_props_cache[key] = {}
        return {}
    by_tn, by_n = lookup
    tpl = by_tn.get((ttype or "", tname))
    if tpl is None:
        tpl = by_n.get(tname)
    if tpl is None:
        _tpl_props_cache[key] = {}
        return {}
    props = dict(tpl.get("Properties") or {})
    ptref = tpl.get("Template")
    if isinstance(ptref, dict) and ptref.get("ObjectName"):
        pt, pouter, pname = _parse_template_ref(ptref.get("ObjectName", ""))
        if pouter and pname and not (pouter == touter and pname == tname):
            base = _resolve_tpl_chain_props(pt, pouter, pname, depth + 1)
            if base:
                merged = dict(base)
                merged.update(props)
                props = merged
    _tpl_props_cache[key] = props
    return props


def _norm_mat_name(value: str) -> str:
    name = str(value).replace("\\", "/").rsplit("/", 1)[-1].split(".")[0].lower()
    while "." in name and name.rsplit(".", 1)[-1].isdigit():
        name = name.rsplit(".", 1)[0]
    return name


def build_ue_to_glb_slot_map():
    """Build UE sidecar slot index -> GLB primitive index remaps for reordered meshes.

    Matches non-empty slot material names in occurrence order against
    game/data/generated/mesh_materials.json (which is in GLB primitive order).
    Meshes whose sidecar order already equals GLB primitive order are omitted so
    they pass through at raw slot indices with zero overhead.
    """
    mm_path = OUT_DATA / "mesh_materials.json"
    if not mm_path.is_file():
        return ({}, {})
    try:
        mesh_mats = json.loads(mm_path.read_text())
    except Exception:
        return ({}, {})
    if not isinstance(mesh_mats, dict):
        return ({}, {})
    mm_lower = {str(k).lower(): v for k, v in mesh_mats.items() if isinstance(v, list)}

    ex_assets = EX / "assets"
    if not ex_assets.exists():
        return ({}, {})

    remap = {}
    remap_lower = {}
    for mf in ex_assets.rglob("*.materials.json"):
        rel = str(mf.relative_to(ex_assets)).replace(".materials.json", "").replace("\\", "/")
        if rel.startswith("TAT/Content/"):
            rel = rel[len("TAT/Content/") :]
        ue_mesh = "/Game/" + rel
        glb_slots = mesh_mats.get(ue_mesh)
        if not isinstance(glb_slots, list):
            glb_slots = mm_lower.get(ue_mesh.lower())
        if not isinstance(glb_slots, list):
            continue
        try:
            raw_slots = json.loads(mf.read_text())
        except Exception:
            continue
        if not isinstance(raw_slots, list):
            continue
        sc_slots = [
            (s.get("material") or "").split(".")[0]
            for s in raw_slots
            if isinstance(s, dict)
        ]
        if [_norm_mat_name(x) for x in sc_slots] == [_norm_mat_name(x) for x in glb_slots]:
            continue
        used_gi = set()
        si_to_gi = {}
        for si, smat in enumerate(sc_slots):
            sn = _norm_mat_name(smat)
            if not sn:
                continue
            for gi, gmat in enumerate(glb_slots):
                if gi not in used_gi and _norm_mat_name(gmat) == sn:
                    si_to_gi[si] = gi
                    used_gi.add(gi)
                    break
        for si, smat in enumerate(sc_slots):
            if (
                not _norm_mat_name(smat)
                and si < len(glb_slots)
                and not _norm_mat_name(glb_slots[si])
                and si not in used_gi
            ):
                si_to_gi[si] = si
                used_gi.add(si)
        val = (si_to_gi, len(glb_slots))
        remap[ue_mesh] = val
        remap_lower[ue_mesh.lower()] = val
    print(f"Indexed {len(remap)} UE-to-GLB material slot remaps")
    return (remap, remap_lower)


def _extract_obj_ref(item) -> tuple:
    if item is None:
        return ("", "")
    op = ""
    on = ""
    if isinstance(item, dict):
        obj = item.get("Object")
        if isinstance(obj, dict):
            raw_op = obj.get("ObjectPath", "")
            raw_on = obj.get("ObjectName", "")
            op = raw_op if isinstance(raw_op, str) else ""
            on = raw_on if isinstance(raw_on, str) else ""
        if not op and isinstance(item.get("ObjectPath"), str):
            op = item["ObjectPath"]
        if not on and isinstance(item.get("ObjectName"), str):
            on = item["ObjectName"]
    elif isinstance(item, str):
        op = item
    return (op, on)


def _is_mid_ref(op: str, on: str, exps, map_ue_path: str | None) -> bool:
    if on.startswith("MaterialInstanceDynamic'"):
        return True
    if not map_ue_path or not exps:
        return False
    base_op, _, suffix = op.rpartition(".")
    if base_op.lower() == map_ue_path.lower() and suffix.isdigit():
        idx = int(suffix)
        if 0 <= idx < len(exps) and exps[idx].get("Type") == "MaterialInstanceDynamic":
            return True
    return False


def _resolve_override_item(item, exps=None, map_ue_path=None, mid_stats=None) -> str:
    op, on = _extract_obj_ref(item)
    if not op:
        return ""
    if not _is_mid_ref(op, on, exps, map_ue_path):
        return op.split(".")[0]
    if not exps:
        if mid_stats is not None:
            mid_stats["unresolved"] += 1
            if len(mid_stats["samples"]) < 10:
                mid_stats["samples"].append((map_ue_path or "", op, on))
        return ""

    cur_op, cur_on = op, on
    for _depth in range(4):
        _, _, suffix = cur_op.rpartition(".")
        target = None
        if suffix.isdigit():
            idx = int(suffix)
            if 0 <= idx < len(exps) and exps[idx].get("Type") == "MaterialInstanceDynamic":
                target = exps[idx]
        if target is None and cur_on:
            inner = cur_on.split("'", 2)[1] if "'" in cur_on else cur_on
            short_name = inner.rsplit(".", 1)[-1].rsplit(":", 1)[-1]
            if short_name:
                for exp in exps:
                    if exp.get("Type") == "MaterialInstanceDynamic" and exp.get("Name") == short_name:
                        target = exp
                        break
        if target is None:
            break
        parent = (target.get("Properties") or {}).get("Parent")
        pop, pon = _extract_obj_ref(parent)
        if not pop:
            break
        if _is_mid_ref(pop, pon, exps, map_ue_path):
            cur_op, cur_on = pop, pon
            continue
        if mid_stats is not None:
            mid_stats["resolved"] += 1
        return pop.split(".")[0]

    if mid_stats is not None:
        mid_stats["unresolved"] += 1
        if len(mid_stats["samples"]) < 10:
            mid_stats["samples"].append((map_ue_path or "", op, on))
    return ""


def _component_override_paths(
    mprops,
    exps=None,
    map_ue_path=None,
    mid_stats=None,
    sm_ue_path=None,
    ue_to_glb=None,
):
    """Slot-indexed /Game/... OverrideMaterials paths in GLB primitive order.

    Preserves "" for None/unresolvable slots, resolves map-local
    MaterialInstanceDynamic refs via Properties.Parent, remaps UE sidecar
    slot indices to GLB primitive indices when mesh_materials.json differs,
    and trims only trailing "". Never invents values.
    """
    mv = (mprops or {}).get("OverrideMaterials")
    if not isinstance(mv, list):
        return []
    raw_out = [
        _resolve_override_item(item, exps=exps, map_ue_path=map_ue_path, mid_stats=mid_stats)
        for item in mv
    ]
    if ue_to_glb and sm_ue_path:
        remap_map, remap_lower = ue_to_glb
        remap = remap_map.get(sm_ue_path) or remap_lower.get(sm_ue_path.lower())
        if remap is not None:
            si_to_gi, glb_len = remap
            out = [""] * glb_len
            for si, val in enumerate(raw_out):
                if val and si in si_to_gi:
                    out[si_to_gi[si]] = val
        else:
            out = raw_out
    else:
        out = raw_out
    while out and not out[-1]:
        out.pop()
    return out


def _merged_comp_props(e):
    """Merge level export Properties on top of its BP Template archetype chain."""
    props = dict(e.get("Properties") or {})
    tref = e.get("Template")
    if isinstance(tref, dict):
        oname = tref.get("ObjectName", "")
        if oname:
            ttype, touter, tname = _parse_template_ref(oname)
            if touter and tname:
                base = _resolve_tpl_chain_props(ttype, touter, tname)
                if base:
                    merged = dict(base)
                    merged.update(props)
                    return merged
    return props


# ---------------------------------------------------------------------------
# Swinging-door resolution (TATSwingingDoorPivotComponent).
# ---------------------------------------------------------------------------
# Level instances of door Blueprint actors carry stub
# TATSwingingDoorPivotComponent exports (real RelativeLocation/Rotation under
# the actor's RootSceneComponent, or identity with the authored transform
# living in the BP template) plus stub leaf StaticMeshComponents attached to
# the pivot. The authored mesh + leaf-relative transform live in the BP class
# JSON (SCS_Node InternalVariableName -> ParentComponentOrVariableName plus
# ComponentTemplate exports). This extends the SCS template path above.
DOOR_LEAF_COMPONENT_TYPES = {
    "StaticMeshComponent",
    "SplineMeshComponent",
    "InstancedStaticMeshComponent",
    "HierarchicalInstancedStaticMeshComponent",
    "FoliageInstancedStaticMeshComponent",
}


def _door_template_props(bp_class, stub_name, stub_type, template_ref):
    """Authored template props for a door pivot/leaf level stub.

    Prefers the stub's own Template archetype ref (exact BP export, Default__
    CDO prefix tolerated), then the actor BP's SCS InternalVariableName match.
    Follows Template inheritance; returns the resolve dict or None and never
    invents values.
    """
    if template_ref:
        ttype, touter, tname = _parse_template_ref(template_ref)
        if touter and tname:
            norm = touter.removesuffix("_C")
            if norm.startswith("Default__"):
                norm = norm[len("Default__") :]
            hit = _resolve_template_in_bp(
                norm + "_C", tname, ttype or stub_type, stub_name
            )
            if hit is not None:
                return hit
    if bp_class and bp_class.endswith("_C"):
        hit = resolve_bp_component(bp_class, stub_name, stub_type=stub_type)
        if hit is not None:
            return hit
    return None


def _door_scs_parent(bp_class, leaf_name):
    """SCS ParentComponentOrVariableName for a leaf component name, or None."""
    loaded = load_bp_exports(bp_class) if bp_class else None
    if not loaded:
        return None
    for e in loaded[0]:
        if e.get("Type") != "SCS_Node":
            continue
        if (e.get("Properties") or {}).get("InternalVariableName") == leaf_name:
            return (e.get("Properties") or {}).get("ParentComponentOrVariableName")
    return None


def _door_glb_exists(ue_path):
    """Existence check for a /Game/... mesh path as an extracted .glb."""
    clean = ue_path.split(".")[0]
    if clean.startswith("/Game/"):
        clean = clean[6:]
    return (ROOT / "game" / "assets" / "ue" / "Content" / (clean + ".glb")).exists()


def _apply_godot_transform(entry, trs):
    """Apply a Godot-space rigid transform to a generated level entry."""
    p = entry.get("pos")
    b = entry.get("basis")
    if not isinstance(p, list) or len(p) < 3:
        return
    ib = trs.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
    r = [
        [float(ib[0]), float(ib[1]), float(ib[2])],
        [float(ib[3]), float(ib[4]), float(ib[5])],
        [float(ib[6]), float(ib[7]), float(ib[8])],
    ]
    v = [float(p[0]), float(p[1]), float(p[2])]
    tp = trs.get("pos", [0.0, 0.0, 0.0])
    np = [sum(r[i][j] * v[j] for j in range(3)) + float(tp[i]) for i in range(3)]
    entry["pos"] = [round(np[0], 4), round(np[1], 4), round(np[2], 4)]
    if isinstance(b, list) and len(b) >= 9:
        bb = [
            [float(b[0]), float(b[1]), float(b[2])],
            [float(b[3]), float(b[4]), float(b[5])],
            [float(b[6]), float(b[7]), float(b[8])],
        ]
        nb = [
            [sum(r[i][k] * bb[k][j] for k in range(3)) for j in range(3)]
            for i in range(3)
        ]
        entry["basis"] = [
            round(nb[0][0], 5),
            round(nb[0][1], 5),
            round(nb[0][2], 5),
            round(nb[1][0], 5),
            round(nb[1][1], 5),
            round(nb[1][2], 5),
            round(nb[2][0], 5),
            round(nb[2][1], 5),
            round(nb[2][2], 5),
        ]


def _apply_godot_point(point, trs):
    ib = trs.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
    r = [
        [float(ib[0]), float(ib[1]), float(ib[2])],
        [float(ib[3]), float(ib[4]), float(ib[5])],
        [float(ib[6]), float(ib[7]), float(ib[8])],
    ]
    v = [float(point[0]), float(point[1]), float(point[2])]
    tp = trs.get("pos", [0.0, 0.0, 0.0])
    return [
        round(sum(r[i][j] * v[j] for j in range(3)) + float(tp[i]), 4) for i in range(3)
    ]


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
    stale_removed = 0
    for old_tat in levels_dir.rglob("*.tatlevel.json"):
        old_tat.unlink()
        stale_removed += 1
    bp_templates = build_bp_mesh_templates()
    level_transforms = build_level_transforms()
    glb_by_name = build_glb_stem_index()
    ue_to_glb = build_ue_to_glb_slot_map()
    count = 0
    total_meshes = 0
    total_lights = 0
    total_level_instances_loaded = 0
    total_level_instance_meshes = 0
    total_level_instances_unresolved = 0
    mid_stats = {"resolved": 0, "unresolved": 0, "samples": []}
    level_payloads = {}

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

        def get_world_mat(idx: int, depth: int = 0, use_templates: bool = False):
            ckey = (idx, use_templates)
            if ckey in world_cache:
                return world_cache[ckey]
            if depth > 12 or idx < 0 or idx >= len(exps):
                return mat4_identity()
            e = exps[idx]
            props = (
                _merged_comp_props(e) if use_templates else (e.get("Properties") or {})
            )
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
                    local = mat4_mul(
                        get_world_mat(pidx, depth + 1, use_templates=use_templates),
                        local,
                    )
            world_cache[ckey] = local
            return local

        rel = jf.relative_to(EX / "json" / "Maps")
        rel_key = str(rel.with_suffix("")).replace("\\", "/")
        raw_map_ue_path = "/Game/Maps/" + rel_key
        game_map_key = raw_map_ue_path.lower()
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

        # 0. Swinging-door pre-pass: resolve each TATSwingingDoorPivotComponent
        # to (actor root world x pivot relative) plus its leaf mesh components
        # (level SMC stubs attached to the pivot, mesh from the BP template).
        # Resolved leaf stub indices are skipped by the mesh branches below so
        # dynamic doors never duplicate the static batches.
        swinging_doors = []
        swinging_unresolved = []
        door_leaf_idx = set()
        door_leaves_excluded = 0
        seen_pivots = set()
        for pidx, pe in enumerate(exps):
            if pe.get("Type") != "TATSwingingDoorPivotComponent":
                continue
            pname = pe.get("Name", "")
            bp_class, actor_name = _stub_actor(exps, pidx)
            dsrc = f"{rel}::{actor_name or pname}"
            if not actor_name or not bp_class:
                swinging_unresolved.append(
                    {
                        "pivot": pname,
                        "actor": actor_name or "",
                        "class": bp_class or "",
                        "reason": "no_parent_actor",
                        "source": dsrc,
                    }
                )
                continue
            dedup = (actor_name, pname)
            if dedup in seen_pivots:
                continue
            seen_pivots.add(dedup)
            aidx = actor_by_name.get(actor_name)
            aroot = None
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
                    aroot = get_world_mat(ridx)
            if aroot is None:
                swinging_unresolved.append(
                    {
                        "pivot": pname,
                        "actor": actor_name,
                        "class": bp_class,
                        "reason": "no_actor_root",
                        "source": dsrc,
                    }
                )
                continue
            pprops = pe.get("Properties") or {}
            ploc = pprops.get("RelativeLocation")
            prot = pprops.get("RelativeRotation")
            pscl = pprops.get("RelativeScale3D")
            # The pivot is itself a StaticMeshComponent subclass in the
            # authored BPs: for doorway Blueprints (no separate leaf stub in
            # the level) the leaf mesh lives directly on the pivot template.
            # Resolve that template once for both transform and mesh.
            tmpl = pe.get("Template") or {}
            tobj = tmpl.get("ObjectName", "") if isinstance(tmpl, dict) else ""
            pivot_hit = None
            if not (ploc or prot or pscl) or not pprops.get("StaticMesh"):
                pivot_hit = _door_template_props(
                    bp_class, pname, "TATSwingingDoorPivotComponent", tobj
                )
            if not (ploc or prot or pscl) and pivot_hit is not None:
                hp = pivot_hit.get("props") or {}
                ploc = hp.get("RelativeLocation")
                prot = hp.get("RelativeRotation")
                pscl = hp.get("RelativeScale3D")
            if not (ploc or prot or pscl):
                swinging_unresolved.append(
                    {
                        "pivot": pname,
                        "actor": actor_name,
                        "class": bp_class,
                        "reason": "no_pivot_transform",
                        "source": dsrc,
                    }
                )
                continue
            pwmat = mat4_mul(aroot, ue_trs_to_mat4(ploc, prot, pscl, is_quat=False))
            if level_mat is not None:
                pwmat = mat4_mul(level_mat, pwmat)
            pgt = ue_mat4_to_godot_trs(pwmat)
            leaves = []
            leaf_bad = []
            pend_idx = []
            for jdx, je in enumerate(exps):
                if je.get("Type") not in DOOR_LEAF_COMPONENT_TYPES:
                    continue
                _, a2 = _stub_actor(exps, jdx)
                if a2 != actor_name:
                    continue
                ap = ((je.get("Properties") or {}).get("AttachParent") or {}).get(
                    "ObjectName", ""
                )
                tail = (
                    ap.split("PersistentLevel.")[-1].rstrip("'").split(".")[-1]
                    if "PersistentLevel." in ap
                    else ""
                )
                if tail != pname:
                    continue
                jname = je.get("Name", "")
                jprops = je.get("Properties") or {}
                jsm = jprops.get("StaticMesh")
                sm = (
                    jsm.get("ObjectPath", "")
                    if isinstance(jsm, dict)
                    else (jsm if isinstance(jsm, str) else "")
                )
                thit = None
                if not sm:
                    tmpl = je.get("Template") or {}
                    tobj = tmpl.get("ObjectName", "") if isinstance(tmpl, dict) else ""
                    thit = _door_template_props(
                        bp_class, jname, je.get("Type", ""), tobj
                    )
                    if thit is not None:
                        tp = thit.get("props") or {}
                        tsm = tp.get("StaticMesh") or {}
                        sm = (
                            tsm.get("ObjectPath", "")
                            if isinstance(tsm, dict)
                            else (tsm if isinstance(tsm, str) else "")
                        )
                if not sm:
                    tpl = bp_templates.get(bp_class, {}).get(jname) or bp_templates.get(
                        bp_class, {}
                    ).get(jname.rstrip("0123456789"))
                    if isinstance(tpl, dict):
                        sm = tpl.get("sm") or ""
                if not sm:
                    base = jname.rstrip("0123456789")
                    sm = glb_by_name.get(jname) or glb_by_name.get(base) or ""
                if not sm:
                    leaf_bad.append(jname)
                    continue
                ue_mesh = sm.split(".")[0]
                if not _door_glb_exists(ue_mesh):
                    leaf_bad.append(jname)
                    continue
                lloc = jprops.get("RelativeLocation")
                lrot = jprops.get("RelativeRotation")
                lscl = jprops.get("RelativeScale3D")
                if not (lloc or lrot or lscl) and thit is not None:
                    tp = thit.get("props") or {}
                    lloc = tp.get("RelativeLocation")
                    lrot = tp.get("RelativeRotation")
                    lscl = tp.get("RelativeScale3D")
                lmat = ue_trs_to_mat4(lloc, lrot, lscl, is_quat=False)
                lgt = ue_mat4_to_godot_trs(lmat)
                game_rel = ue_mesh[6:] if ue_mesh.startswith("/Game/") else ue_mesh
                leaves.append(
                    {
                        "mesh": ue_mesh,
                        "res": f"res://assets/ue/Content/{game_rel}.glb",
                        "rel_loc": lloc,
                        "rel_rot": lrot,
                        "rel_scale": lscl,
                        "rel_pos": lgt["pos"],
                        "rel_basis": lgt["basis"],
                        "rel_scale_v": lgt["scale"],
                        "scs_parent": _door_scs_parent(bp_class, jname),
                    }
                )
                pend_idx.append(jdx)
            if not leaves:
                # Doorway BPs attach the leaf mesh directly to the pivot
                # component instead of instancing a separate SMC stub. The
                # authored StaticMesh + pivot transform is the complete leaf;
                # its local transform is identity because the pivot already
                # carries the hinge position.
                psm = pprops.get("StaticMesh")
                if not psm and pivot_hit is not None:
                    psm = (pivot_hit.get("props") or {}).get("StaticMesh")
                psm_path = (
                    psm.get("ObjectPath", "")
                    if isinstance(psm, dict)
                    else (psm if isinstance(psm, str) else "")
                )
                psm_mesh = psm_path.split(".")[0]
                if psm_mesh and _door_glb_exists(psm_mesh):
                    game_rel = (
                        psm_mesh[6:] if psm_mesh.startswith("/Game/") else psm_mesh
                    )
                    leaves.append(
                        {
                            "mesh": psm_mesh,
                            "res": f"res://assets/ue/Content/{game_rel}.glb",
                            "rel_loc": None,
                            "rel_rot": None,
                            "rel_scale": None,
                            "rel_pos": [0.0, 0.0, 0.0],
                            "rel_basis": [
                                1.0,
                                0.0,
                                0.0,
                                0.0,
                                1.0,
                                0.0,
                                0.0,
                                0.0,
                                1.0,
                            ],
                            "rel_scale_v": [1.0, 1.0, 1.0],
                            "scs_parent": None,
                            "leaf_source": "pivot_static_mesh",
                        }
                    )
                else:
                    swinging_unresolved.append(
                        {
                            "pivot": pname,
                            "actor": actor_name,
                            "class": bp_class,
                            "reason": "no_resolved_leaves"
                            + (":" + ",".join(leaf_bad[:4]) if leaf_bad else ""),
                            "source": dsrc,
                        }
                    )
                    continue
            for q in pend_idx:
                door_leaf_idx.add(q)
            swinging_doors.append(
                {
                    "name": f"{actor_name}.{pname}",
                    "actor": actor_name,
                    "class": bp_class,
                    "pos": pgt["pos"],
                    "basis": pgt["basis"],
                    "leaves": leaves,
                    "source": dsrc,
                }
            )

        for idx, e in enumerate(exps):
            et = e.get("Type", "")
            props = e.get("Properties") or {}
            outer = e.get("Outer")
            outer_name = outer.get("ObjectName", "") if isinstance(outer, dict) else ""

            # 1. StaticMeshComponent / SplineMeshComponent (including Blueprint CDO/SCS template fallback)
            if et in ("StaticMeshComponent", "SplineMeshComponent"):
                if idx in door_leaf_idx:
                    door_leaves_excluded += 1
                    continue
                mprops = _merged_comp_props(e)
                if mprops.get("bVisible") is False:
                    continue
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
                    if "SplineEditorMesh" in sm:
                        continue
                    wmat = get_world_mat(idx)
                    if bp_lmat is not None:
                        wmat = mat4_mul(wmat, bp_lmat)
                    if level_mat is not None:
                        wmat = mat4_mul(level_mat, wmat)
                    trs = ue_mat4_to_godot_trs(wmat)
                    sm_clean = sm.split(".")[0]
                    entry = {"mesh": sm_clean, **trs}
                    ov_paths = _component_override_paths(
                        mprops,
                        exps=exps,
                        map_ue_path=raw_map_ue_path,
                        mid_stats=mid_stats,
                        sm_ue_path=sm_clean,
                        ue_to_glb=ue_to_glb,
                    )
                    if ov_paths:
                        entry["override_materials"] = ov_paths
                        if ov_paths[0]:
                            entry["override_material"] = ov_paths[0]
                    meshes.append(entry)
                    continue

            # 2. InstancedStaticMeshComponent / HierarchicalInstancedStaticMeshComponent / Foliage
            if et in (
                "InstancedStaticMeshComponent",
                "HierarchicalInstancedStaticMeshComponent",
                "FoliageInstancedStaticMeshComponent",
            ):
                if idx in door_leaf_idx:
                    door_leaves_excluded += 1
                    continue
                mprops2 = _merged_comp_props(e)
                if mprops2.get("bVisible") is False:
                    continue
                sm = (props.get("StaticMesh") or {}).get("ObjectPath")
                bp_cls = outer_name.split("'")[0] if outer_name else ""
                cname = e.get("Name", "")
                tpl2 = bp_templates.get(bp_cls, {}).get(cname)
                if not isinstance(tpl2, dict):
                    tpl2 = bp_templates.get(bp_cls, {}).get(cname.rstrip("0123456789"))
                if not sm and isinstance(tpl2, dict):
                    # Packed Level Actor components keep their mesh and
                    # per-instance transforms in the BPP class template.
                    sm = tpl2.get("sm")
                instances = (
                    e.get("PerInstanceSMData") or props.get("PerInstanceSMData") or []
                )
                if not instances and isinstance(tpl2, dict):
                    instances = tpl2.get("instances") or []
                if sm:
                    if "SplineEditorMesh" in sm:
                        continue
                    sm_clean2 = sm.split(".")[0]
                    ov_paths2 = _component_override_paths(
                        mprops2,
                        exps=exps,
                        map_ue_path=raw_map_ue_path,
                        mid_stats=mid_stats,
                        sm_ue_path=sm_clean2,
                        ue_to_glb=ue_to_glb,
                    )
                    wmat = get_world_mat(idx)
                    stub_has_transform = bool(
                        props.get("RelativeLocation")
                        or props.get("RelativeRotation")
                        or props.get("RelativeScale3D")
                    )
                    if (
                        isinstance(tpl2, dict)
                        and tpl2.get("local") is not None
                        and not stub_has_transform
                    ):
                        wmat = mat4_mul(wmat, tpl2["local"])
                    if level_mat is not None:
                        wmat = mat4_mul(level_mat, wmat)
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
                            ientry = {"mesh": sm_clean2, **trs}
                            if ov_paths2:
                                ientry["override_materials"] = ov_paths2
                                if ov_paths2[0]:
                                    ientry["override_material"] = ov_paths2[0]
                            meshes.append(ientry)
                    else:
                        trs = ue_mat4_to_godot_trs(wmat)
                        sentry = {"mesh": sm_clean2, **trs}
                        if ov_paths2:
                            sentry["override_materials"] = ov_paths2
                            if ov_paths2[0]:
                                sentry["override_material"] = ov_paths2[0]
                        meshes.append(sentry)
                    continue

            # 3. Lights
            if (
                "PointLightComponent" in et
                or "SpotLightComponent" in et
                or "DirectionalLightComponent" in et
            ):
                if "TATShadowFade" in et:
                    continue
                lprops = _merged_comp_props(e)
                raw_int = lprops.get("Intensity", 10.0)
                intensity = float(raw_int) if raw_int is not None else 10.0
                if (
                    intensity <= 0.0
                    or lprops.get("bVisible") is False
                    or lprops.get("bHiddenInGame") is True
                ):
                    continue
                wmat = get_world_mat(idx, use_templates=True)
                if level_mat is not None:
                    wmat = mat4_mul(level_mat, wmat)
                trs = ue_mat4_to_godot_trs(wmat)
                raw_rad = lprops.get("AttenuationRadius", 1000.0)
                radius = round(
                    float(raw_rad if raw_rad is not None else 1000.0) * 0.01, 2
                )
                lights.append(
                    {
                        "type": et,
                        "intensity": intensity,
                        "color": lprops.get("LightColor"),
                        "radius": radius,
                        "outer_cone": lprops.get("OuterConeAngle"),
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
                    wbias = props.get("WeightmapScaleBias") or {}
                    h_rel = str(rel.parent / jf.stem).replace("\\", "/")
                    wtextures = props.get("WeightmapTextures") or []
                    weightmaps = []
                    for wt in wtextures:
                        wname = ""
                        if isinstance(wt, dict):
                            wname = (
                                (wt.get("ObjectName") or "").split(".")[-1].rstrip("'")
                            )
                        weightmaps.append(
                            f"res://assets/ue/Raw/Maps/{h_rel}/{wname}.png"
                            if wname
                            else ""
                        )
                    weightmap = weightmaps[0] if weightmaps else ""
                    layers = []
                    for alloc in props.get("WeightmapLayerAllocations") or []:
                        li = (alloc.get("LayerInfo") or {}).get("ObjectName", "")
                        lname = (
                            li.split("'")[1].replace("_LayerInfo", "")
                            if "'" in li
                            else ""
                        )
                        if lname:
                            layers.append(
                                {
                                    "layer": lname,
                                    "tex": int(alloc.get("WeightmapTextureIndex", 0)),
                                    "channel": int(
                                        alloc.get("WeightmapTextureChannel", 0)
                                    ),
                                }
                            )
                    landscapes.append(
                        {
                            "heightmap": f"res://assets/ue/Raw/Maps/{h_rel}/{hname}.png",
                            "source": h_rel,
                            "weightmap": weightmap,
                            "weightmaps": weightmaps,
                            "weightmap_scale_bias": [
                                float(wbias.get("X", 1.0 / 64.0)),
                                float(wbias.get("Y", 1.0 / 64.0)),
                                float(wbias.get("Z", 0.0)),
                                float(wbias.get("W", 0.0)),
                            ],
                            "layers": layers,
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
            if not mesh_path or "SplineEditorMesh" in mesh_path:
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

        # LevelInstance actors reference another map and place it with the
        # LevelInstanceComponent transform. Collect pending refs in Pass 1 and
        # resolve recursively in Pass 2 so alphabetical ordering (e.g.
        # FTUE/FTUE_Geometry -> Guildhall/Facade_Apartment_CarUnderpass) and
        # multi-level LevelInstance chains merge from fresh in-memory payloads.
        pending_li = []
        for e in exps:
            if e.get("Type") != "LevelInstance":
                continue
            props = e.get("Properties") or {}
            asset = (props.get("CookedWorldAsset") or {}).get("AssetPathName", "")
            if not asset:
                continue
            rel_asset = asset.split(".")[0]
            prefix = "/Game/Maps/"
            if not rel_asset.startswith(prefix):
                continue
            rel_asset = rel_asset[len(prefix) :]
            if rel_asset == rel_key:
                continue
            comp_ref = (props.get("LevelInstanceComponent") or {}).get("ObjectName", "")
            ridx = comp_by_full_objname.get(comp_ref)
            if ridx is None and "PersistentLevel." in comp_ref:
                ridx = comp_by_full_objname.get(
                    comp_ref.split("PersistentLevel.")[-1].rstrip("'")
                )
            if ridx is None:
                total_level_instances_unresolved += 1
                continue
            inst_mat = get_world_mat(ridx)
            if level_mat is not None:
                inst_mat = mat4_mul(level_mat, inst_mat)
            inst_trs = ue_mat4_to_godot_trs(inst_mat)
            pending_li.append((rel_asset, inst_trs, e.get("Name")))

        has_base_entities = bool(
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
        )
        if has_base_entities or pending_li:
            level_payloads[rel_key] = {
                "rel": rel,
                "pending_li": pending_li,
                "niagara_unresolved": niagara_unresolved,
                "decals_unresolved": decals_unresolved,
                "splines_skipped": splines_skipped,
                "data": {
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
                    "swinging_doors": swinging_doors,
                    "door_leaves_excluded": door_leaves_excluded,
                    "swinging_doors_unresolved": swinging_unresolved,
                    "level_instances": [],
                },
            }

    # Pass 2: Memoized recursive LevelInstance merge over in-memory payloads.
    resolved_li = set()
    visiting_li = set()
    li_merge_keys = (
        "meshes",
        "lights",
        "markers",
        "landscapes",
        "rect_lights",
        "sky_lights",
        "fog_volumes",
        "post_process",
        "sky_atmospheres",
        "decals",
        "niagara",
        "volumes",
        "landscape_splines",
        "swinging_doors",
    )

    def resolve_li(key: str):
        nonlocal total_level_instances_loaded, total_level_instance_meshes, total_level_instances_unresolved
        if key in resolved_li or key in visiting_li:
            return
        meta = level_payloads.get(key)
        if meta is None:
            return
        visiting_li.add(key)
        pdata = meta["data"]
        prel = meta["rel"]
        for rel_asset, inst_trs, actor_name in meta["pending_li"]:
            sub_meta = level_payloads.get(rel_asset)
            if sub_meta is None:
                total_level_instances_unresolved += 1
                continue
            resolve_li(rel_asset)
            sub_data = sub_meta["data"]
            for mkey in li_merge_keys:
                dest = pdata[mkey]
                for entry in list(sub_data.get(mkey) or []):
                    if not isinstance(entry, dict):
                        continue
                    e2 = dict(entry)
                    if "override_materials" in e2 and isinstance(e2["override_materials"], list):
                        e2["override_materials"] = list(e2["override_materials"])
                    if mkey == "landscape_splines":
                        pts = e2.get("points") or []
                        e2["points"] = [
                            _apply_godot_point(pt, inst_trs)
                            for pt in pts
                            if isinstance(pt, list) and len(pt) >= 3
                        ]
                    else:
                        _apply_godot_transform(e2, inst_trs)
                    e2["level_instance"] = f"{prel}::{actor_name}"
                    dest.append(e2)
            total_level_instances_loaded += 1
            pdata["level_instances"].append(rel_asset)
            total_level_instance_meshes += len(sub_data.get("meshes") or [])
        visiting_li.remove(key)
        resolved_li.add(key)

    for key in list(level_payloads.keys()):
        resolve_li(key)

    # Write Pass: emit non-empty .tatlevel.json payloads.
    for key, meta in level_payloads.items():
        pdata = meta["data"]
        if (
            pdata["meshes"]
            or pdata["lights"]
            or pdata["markers"]
            or pdata["landscapes"]
            or pdata["rect_lights"]
            or pdata["sky_lights"]
            or pdata["fog_volumes"]
            or pdata["post_process"]
            or pdata["sky_atmospheres"]
            or pdata["decals"]
            or pdata["niagara"]
            or pdata["volumes"]
            or pdata["landscape_splines"]
        ):
            prel = meta["rel"]
            dst = levels_dir / prel.with_suffix(".tatlevel.json")
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(json.dumps(pdata))
            count += 1
            total_meshes += len(pdata["meshes"])
            total_lights += len(pdata["lights"])
            if pdata["swinging_doors"] or pdata["swinging_doors_unresolved"]:
                print(
                    f"  {prel}: swinging_doors={len(pdata['swinging_doors'])} "
                    f"door_leaves_excluded={pdata['door_leaves_excluded']} "
                    f"unresolved={len(pdata['swinging_doors_unresolved'])}"
                )
            if (
                pdata["rect_lights"]
                or pdata["sky_lights"]
                or pdata["fog_volumes"]
                or pdata["post_process"]
                or pdata["sky_atmospheres"]
                or pdata["decals"]
                or pdata["niagara"]
                or pdata["volumes"]
                or pdata["landscape_splines"]
            ):
                print(
                    f"  {prel}: rect={len(pdata['rect_lights'])} sky={len(pdata['sky_lights'])} fog={len(pdata['fog_volumes'])} "
                    f"pp={len(pdata['post_process'])} atmo={len(pdata['sky_atmospheres'])} decals={len(pdata['decals'])} "
                    f"niagara={len(pdata['niagara'])} (+{meta['niagara_unresolved']} unresolved) "
                    f"volumes={len(pdata['volumes'])} splines={len(pdata['landscape_splines'])} "
                    f"(+{meta['decals_unresolved']} decal-no-material, +{meta['splines_skipped']} spline-no-mesh)"
                )

    for d in sorted(levels_dir.rglob("*"), reverse=True):
        if d.is_dir() and not any(d.iterdir()):
            d.rmdir()

    print(
        f"Normalized {count} level JSONs -> {total_meshes} mesh instances, {total_lights} lights "
        f"(stale_removed={stale_removed})"
    )
    print(
        f"Level instances: {total_level_instances_loaded} loaded "
        f"({total_level_instance_meshes} meshes), "
        f"{total_level_instances_unresolved} unresolved"
    )
    print(
        f"MID overrides: mid_resolved={mid_stats['resolved']}, "
        f"mid_unresolved={mid_stats['unresolved']}"
    )
    if mid_stats["samples"]:
        print(f"  unresolved MID samples: {mid_stats['samples']}")


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
