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
        [sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)]
        for i in range(4)
    ]


def ue_quat_to_mat3(q: dict):
    x = float(q.get("X", 0.0))
    y = float(q.get("Y", 0.0))
    z = float(q.get("Z", 0.0))
    w = float(q.get("W", 1.0))
    n = math.sqrt(x * x + y * y + z * z + w * w)
    if n > 1e-8:
        x /= n; y /= n; z /= n; w /= n
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    return [
        [1 - 2 * (yy + zz), 2 * (xy - wz),     2 * (xz + wy)],
        [2 * (xy + wz),     1 - 2 * (xx + zz), 2 * (yz - wx)],
        [2 * (xz - wy),     2 * (yz + wx),     1 - 2 * (xx + yy)],
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
        [sp,      -sr * cp,               cr * cp],
    ]


def ue_trs_to_mat4(loc: dict | None, rot: dict | None, scale: dict | None, is_quat: bool = False):
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
            round(c0[0] / sx, 5), round(c1[0] / sy, 5), round(c2[0] / sz, 5),
            round(c0[1] / sx, 5), round(c1[1] / sy, 5), round(c2[1] / sz, 5),
            round(c0[2] / sx, 5), round(c1[2] / sy, 5), round(c2[2] / sz, 5),
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
                "rows": exp.get("Rows") or (exp.get("StringTable") or {}).get("KeysToMetaData") or {},
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
            if e.get("Type") in ("InstancedStaticMeshComponent", "HierarchicalInstancedStaticMeshComponent", "StaticMeshComponent"):
                name = e.get("Name", "").replace("_GEN_VARIABLE", "")
                props = e.get("Properties") or {}
                sm = (props.get("StaticMesh") or {}).get("ObjectPath")
                if sm:
                    loc = props.get("RelativeLocation")
                    rot = props.get("RelativeRotation")
                    scl = props.get("RelativeScale3D")
                    lmat = ue_trs_to_mat4(loc, rot, scl, is_quat=False) if (loc or rot or scl) else None
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
            wa = ((props.get("WorldAsset") or {}).get("AssetPathName") or "").split(".")[0]
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
            outer_str = outer.get("ObjectName", "") if isinstance(outer, dict) else str(outer or "")
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
            local = ue_trs_to_mat4(props.get("RelativeLocation"), props.get("RelativeRotation"), props.get("RelativeScale3D"), is_quat=False)
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
        game_map_key = ("/Game/Maps/" + str(rel.with_suffix("")).replace("\\", "/")).lower()
        level_mat = level_transforms.get(game_map_key)

        meshes = []
        lights = []
        markers = []
        landscapes = []

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
                        if not (props.get("RelativeLocation") or props.get("RelativeRotation") or props.get("RelativeScale3D")):
                            bp_lmat = tpl.get("local")
                if not sm:
                    cname = e.get("Name", "")
                    base_c = cname.rstrip("0123456789")
                    sm = glb_by_name.get(cname) or glb_by_name.get(base_c)
                    if not sm and "deskvariant" in cname.lower():
                        sm = glb_by_name.get("sm_deskvariant_b") or glb_by_name.get("sm_deskvariant_a")
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
            if et in ("InstancedStaticMeshComponent", "HierarchicalInstancedStaticMeshComponent", "FoliageInstancedStaticMeshComponent"):
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
                    instances = e.get("PerInstanceSMData") or props.get("PerInstanceSMData") or []
                    if instances:
                        for inst in instances:
                            td = inst.get("TransformData") or {}
                            imat = ue_trs_to_mat4(td.get("Translation"), td.get("Rotation"), td.get("Scale3D"), is_quat=True)
                            trs = ue_mat4_to_godot_trs(mat4_mul(wmat, imat))
                            meshes.append({"mesh": sm.split(".")[0], **trs})
                    else:
                        trs = ue_mat4_to_godot_trs(wmat)
                        meshes.append({"mesh": sm.split(".")[0], **trs})
                    continue

            # 3. Lights
            if "PointLightComponent" in et or "SpotLightComponent" in et or "DirectionalLightComponent" in et:
                wmat = get_world_mat(idx)
                if level_mat is not None:
                    wmat = mat4_mul(level_mat, wmat)
                trs = ue_mat4_to_godot_trs(wmat)
                lights.append({
                    "type": et,
                    "intensity": props.get("Intensity", 10.0),
                    "color": props.get("LightColor"),
                    "radius": round(float(props.get("AttenuationRadius", 1000.0)) * 0.01, 2),
                    "outer_cone": props.get("OuterConeAngle"),
                    **trs,
                })
                continue

            # 4. Gameplay markers
            if any(k in et for k in ("MissionSpawner", "PlayerStart", "Door", "Escape", "Guard", "Patrol", "Loot", "Climb")):
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
                    landscapes.append({
                        "heightmap": f"res://assets/ue/Raw/Maps/{h_rel}/{hname}.png",
                        "quads": int(props.get("ComponentSizeQuads", 63)),
                        "scale_bias": [
                            float(bias.get("X", 1.0 / 64.0)),
                            float(bias.get("Y", 1.0 / 64.0)),
                            float(bias.get("Z", 0.0)),
                            float(bias.get("W", 0.0)),
                        ],
                        **trs,
                    })
                continue

        if meshes or lights or markers or landscapes:
            rel = jf.relative_to(EX / "json" / "Maps")
            dst = levels_dir / rel.with_suffix(".tatlevel.json")
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(json.dumps({
                "source": str(rel),
                "meshes": meshes,
                "lights": lights,
                "markers": markers,
                "landscapes": landscapes,
            }))
            count += 1
            total_meshes += len(meshes)
            total_lights += len(lights)

    print(f"Normalized {count} level JSONs -> {total_meshes} mesh instances, {total_lights} lights")


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
