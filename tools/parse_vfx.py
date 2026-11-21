#!/usr/bin/env python3
"""
Parse UE5 TAT Niagara systems into Godot-friendly structured VFX data.

Reads every extracted `NS_*.json` under `extracted/json/` and writes:
  - `game/data/generated/vfx/systems.json`: one entry per system with
    emitters, renderers (with sprite textures resolved via materials.json),
    compiled variable names/types, exposed parameter names, curve LUT counts,
    referenced meshes/textures, and a `complexity` classification.
  - `game/data/generated/vfx/catalogue.md`: per-system renderer/material/class
    table for art review.

No numbers are invented: fields absent from the source JSON become null.
Niagara compiled graphs are NOT translated; parameters are recorded only as
names/types observed in `ExposedParameters` (defaults live in raw
`ParameterData` bytes and are not decoded).
"""

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX_ROOT = ROOT / "extracted" / "json"
MATERIALS_JSON = ROOT / "game" / "data" / "generated" / "materials.json"
OUT_DIR = ROOT / "game" / "data" / "generated" / "vfx"

# Heuristic cutoffs for the `graph_heavy` class. Deduped per-system counts
# across the 120 systems: scripts range 2-48 (bulk <= 16), LUTs range 0-586
# (bulk <= 62). Cutoffs sit above the bulk at roughly the top decile.
GRAPH_HEAVY_MIN_SCRIPTS = 18
GRAPH_HEAVY_MIN_LUTS = 72

LUT_TYPES = {
    "NiagaraDataInterfaceCurve": "curve",
    "NiagaraDataInterfaceVectorCurve": "vector",
    "NiagaraDataInterfaceVector2DCurve": "vector2d",
    "NiagaraDataInterfaceColorCurve": "color",
}

NON_SPRITE_RENDERERS = {
    "NiagaraMeshRendererProperties",
    "NiagaraRibbonRendererProperties",
    "NiagaraLightRendererProperties",
    "NiagaraDecalRendererProperties",
    "NiagaraComponentRendererProperties",
}

RENDERER_KIND = {
    "NiagaraSpriteRendererProperties": "sprite",
    "NiagaraMeshRendererProperties": "mesh",
    "NiagaraRibbonRendererProperties": "ribbon",
    "NiagaraLightRendererProperties": "light",
    "NiagaraDecalRendererProperties": "decal",
    "NiagaraComponentRendererProperties": "component",
}

# Preferred materials.json texture slot for a sprite texture, in order.
TEX_PREFERENCE = ("albedo", "emissive", "normal", "orm")


def _ref_path(v):
    """UE object reference dict -> asset path without subobject suffix, or None."""
    if isinstance(v, dict):
        p = v.get("ObjectPath") or v.get("AssetPathName")
        if isinstance(p, str) and p:
            return p.split(".")[0]
    return None


def _type_name(typedef):
    """Niagara TypeDef dict -> short class name (e.g. Class'NiagaraFloat' -> NiagaraFloat)."""
    if not isinstance(typedef, dict):
        return None
    cls = (typedef.get("ClassStructOrEnum") or {}).get("ObjectName")
    if isinstance(cls, str) and "'" in cls:
        return cls.split("'")[1]
    return cls


def _dedupe(exports):
    """The extractor emits some exports twice (identical Type/Name/Outer);
    dedupe those, but keep same-named exports that belong to different
    emitters (distinguished by Outer) — they carry different materials."""
    seen = set()
    out = []
    for e in exports:
        key = (e.get("Type"), e.get("Name"), (e.get("Outer") or {}).get("ObjectName"))
        if key in seen:
            continue
        seen.add(key)
        out.append(e)
    return out


def _resolve_sprite_texture(material_path, materials):
    """UE material path -> (texture, slot, resolved) via materials.json.

    Returns (None, None, False) for engine-default materials and paths with
    no materials.json entry; (None, None, True) when the material resolves
    but carries no texture (procedural/unlit materials).
    """
    if not material_path:
        return None, None, False
    if material_path.startswith("/Niagara/"):
        return None, None, False
    entry = materials.get(material_path)
    if entry is None:
        return None, None, False
    texs = entry.get("texs") or {}
    for slot in TEX_PREFERENCE:
        if texs.get(slot):
            return texs[slot], slot, True
    for slot in sorted(texs):
        if texs[slot]:
            return texs[slot], slot, True
    return None, None, True


def _parse_renderer(export, materials):
    props = export.get("Properties") or {}
    kind = RENDERER_KIND[export.get("Type")]
    rec = {"type": kind, "export": export.get("Name"), "material": None}
    if kind in ("sprite", "ribbon", "decal"):
        mat = _ref_path(props.get("Material"))
        rec["material"] = mat
        tex, slot, resolved = _resolve_sprite_texture(mat, materials)
        rec["sprite_texture"] = tex
        rec["texture_slot"] = slot
        rec["material_resolved"] = resolved
    if kind == "sprite":
        rec["alignment"] = props.get("Alignment")
        rec["facing_mode"] = props.get("FacingMode")
        rec["subimage_blend"] = props.get("bSubImageBlend")
    if kind == "mesh":
        meshes = []
        for m in props.get("Meshes", []) or []:
            meshes.append(
                {
                    "mesh": _ref_path((m or {}).get("Mesh")),
                    "lod_mode": (m or {}).get("LODMode"),
                    "scale": (m or {}).get("Scale"),
                }
            )
        rec["meshes"] = meshes
        rec["override_materials"] = [
            _ref_path((om or {}).get("ExplicitMat"))
            for om in props.get("OverrideMaterials", []) or []
        ]
        rec["facing_mode"] = props.get("FacingMode")
        for om_path in rec["override_materials"]:
            tex, slot, resolved = _resolve_sprite_texture(om_path, materials)
            if tex and not rec.get("sprite_texture"):
                rec["sprite_texture"] = tex
                rec["texture_slot"] = slot
        rec["override_materials_resolved"] = [
            (p in materials) if p else False for p in rec["override_materials"]
        ]
    if kind == "ribbon":
        uv0 = props.get("UV0Settings") or {}
        rec["uv_distribution"] = uv0.get("DistributionMode")
    if kind == "light":
        rec["color_add"] = props.get("ColorAdd")
    return rec


def _parse_system(path, materials):
    exports = _dedupe(json.loads(path.read_text()))
    by_type = {}
    for e in exports:
        by_type.setdefault(e.get("Type"), []).append(e)
    systems = by_type.get("NiagaraSystem", [])
    if not systems:
        return None
    sys_export = systems[0]
    props = sys_export.get("Properties") or {}

    emitters = []
    for h in props.get("EmitterHandles", []) or []:
        vi = h.get("VersionedInstance") or {}
        emitters.append(
            {
                "name": h.get("Name"),
                "id": h.get("ID"),
                "enabled": bool(h.get("bIsEnabled")),
                "mode": h.get("EmitterMode"),
                # Always a same-package subobject (ObjectPath '<pkg>.<N>')
                # or null when the handle is disabled/unresolved.
                "emitter_asset": _ref_path(vi.get("Emitter")),
                "stateless": h.get("StatelessEmitter") is not None,
            }
        )

    renderers = [
        _parse_renderer(e, materials)
        for t, es in by_type.items()
        if t in RENDERER_KIND
        for e in es
    ]

    compiled = (props.get("SystemCompiledData") or {}).get(
        "DataSetCompiledData", {}
    ) or {}
    variables = [
        {"name": v.get("Name"), "type": _type_name(v.get("TypeDef"))}
        for v in compiled.get("Variables", []) or []
    ]

    exposed = props.get("ExposedParameters") or {}
    params = []
    seen_params = set()
    for src in (
        exposed.get("UserParameterRedirects", []) or [],
        exposed.get("SortedParameterOffsets", []) or [],
    ):
        for item in src:
            key = item.get("Key") if "Key" in item else item
            if not isinstance(key, dict):
                continue
            name = key.get("Name")
            if not name or name in seen_params:
                continue
            seen_params.add(name)
            params.append({"name": name, "type": _type_name(key.get("TypeDef"))})
    exposed_refs = []
    for ref in (exposed.get("UObjects", []) or []) + (
        exposed.get("DataInterfaces", []) or []
    ):
        p = _ref_path(ref)
        # Skip nulls and references to the system's own package (subobjects
        # of the system itself, e.g. embedded data-interface instances).
        if p and p != sys_export.get("Package"):
            exposed_refs.append(p)

    lut_counts = {v: 0 for v in LUT_TYPES.values()}
    lut_names = []
    for ue_type, short in LUT_TYPES.items():
        for e in by_type.get(ue_type, []):
            lut_counts[short] += 1
            lut_names.append(e.get("Name"))
    lut_total = sum(lut_counts.values())

    scripts = by_type.get("NiagaraScript", [])

    vector_fields = sorted(
        {
            p
            for e in by_type.get("NiagaraDataInterfaceVectorField", [])
            for p in [_ref_path((e.get("Properties") or {}).get("Field"))]
            if p
        }
    )
    skeletal = by_type.get("NiagaraDataInterfaceSkeletalMesh", [])
    skeletal_modes = sorted(
        {
            (e.get("Properties") or {}).get("SourceMode")
            for e in skeletal
            if (e.get("Properties") or {}).get("SourceMode")
        }
    )
    skeletal_bones = sorted(
        {
            b
            for e in skeletal
            for b in ((e.get("Properties") or {}).get("FilteredBones") or [])
        }
    )
    texture_params = sorted(
        {
            (
                ((e.get("Properties") or {}).get("TextureUserParameter") or {}).get(
                    "Parameter", {}
                )
            ).get("Name")
            for e in by_type.get("NiagaraDataInterfaceTexture", [])
        }
        - {None, ""}
    )
    other_dis = sorted(
        {
            t
            for t in by_type
            if t.startswith("NiagaraDataInterface")
            and t
            not in set(LUT_TYPES)
            | {
                "NiagaraDataInterfaceSkeletalMesh",
                "NiagaraDataInterfaceVectorField",
                "NiagaraDataInterfaceTexture",
            }
        }
    )

    meshes = sorted(
        {
            m["mesh"]
            for r in renderers
            if r["type"] == "mesh"
            for m in r.get("meshes", [])
            if m["mesh"]
        }
    )
    textures = sorted(
        {r["sprite_texture"] for r in renderers if r.get("sprite_texture")}
    )

    # Loop duration is never a plain number in these dumps: SystemStateData
    # carries only a ParameterBinding named "None", so it is not resolvable.
    loop_resolvable = isinstance(
        ((props.get("SystemStateData") or {}).get("LoopDuration")), (int, float)
    )

    enabled = [e for e in emitters if e["enabled"]]
    renderer_kinds = sorted({r["type"] for r in renderers})
    has_non_sprite = any(
        kind in ("mesh", "ribbon", "light", "decal", "component")
        for kind in renderer_kinds
    )
    has_skeletal = len(skeletal) > 0
    has_vectorfield = len(vector_fields) > 0 or any(
        (e.get("Properties") or {}).get("Field")
        for e in by_type.get("NiagaraDataInterfaceVectorField", [])
    )
    empty_shell = not enabled and not renderers

    reasons = []
    if empty_shell:
        complexity = "sprite_only"
        reasons.append("no enabled emitters and no renderer data (placeholder shell)")
    elif has_non_sprite:
        complexity = "mesh_or_ribbon"
        reasons.append("non-sprite renderer present: %s" % ", ".join(renderer_kinds))
    elif (
        len(scripts) >= GRAPH_HEAVY_MIN_SCRIPTS
        or lut_total >= GRAPH_HEAVY_MIN_LUTS
        or has_skeletal
        or has_vectorfield
    ):
        complexity = "graph_heavy"
        if len(scripts) >= GRAPH_HEAVY_MIN_SCRIPTS:
            reasons.append("%d scripts >= %d" % (len(scripts), GRAPH_HEAVY_MIN_SCRIPTS))
        if lut_total >= GRAPH_HEAVY_MIN_LUTS:
            reasons.append("%d curve LUTs >= %d" % (lut_total, GRAPH_HEAVY_MIN_LUTS))
        if has_skeletal:
            reasons.append("skeletal-mesh dependency")
        if has_vectorfield:
            reasons.append("vector-field dependency")
    else:
        complexity = "sprite_only"
        reasons.append(
            "sprite renderer(s) only, no mesh/ribbon, no skeletal/vector-field deps"
        )

    rel = str(path.relative_to(ROOT))
    folder = str(path.parent.relative_to(EX_ROOT))
    return {
        "name": sys_export.get("Name"),
        "source": rel,
        "folder": folder,
        "package": sys_export.get("Package"),
        "loop_duration": None,
        "loop_resolvable": loop_resolvable,
        "determinism": props.get("bDeterminism"),
        "emitters": emitters,
        "enabled_emitter_count": len(enabled),
        "renderers": renderers,
        "renderer_kinds": renderer_kinds,
        "compiled_variables": variables,
        "compiled_variable_count": len(variables),
        "exposed_parameters": params,
        # P2-5: defaults live in raw ParameterData bytes and are NOT
        # decoded — recorded explicitly per system so "no authored look"
        # is a stated boundary, not an assumption a reader must recover
        # from the file notes.
        "parameter_defaults": "unknown (ParameterData bytes not decoded)",
        "exposed_object_refs": sorted(set(exposed_refs)),
        "curve_luts": {**lut_counts, "total": lut_total},
        "curve_lut_names": sorted(set(lut_names)),
        "script_count": len(scripts),
        "dependencies": {
            "skeletal_mesh": has_skeletal,
            "skeletal_modes": skeletal_modes,
            "skeletal_bones": skeletal_bones,
            "vector_field": has_vectorfield,
            "vector_fields": vector_fields,
            "texture_user_parameters": texture_params,
            "other_data_interfaces": other_dis,
        },
        "referenced_meshes": meshes,
        "referenced_textures": textures,
        "complexity": complexity,
        "complexity_reasons": reasons,
        "empty_shell": empty_shell,
    }


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    materials = json.loads(MATERIALS_JSON.read_text())

    files = sorted(EX_ROOT.rglob("NS_*.json"))
    if not files:
        raise SystemExit("no NS_*.json found under %s" % EX_ROOT)

    systems = []
    for path in files:
        rec = _parse_system(path, materials)
        if rec is None:
            print("WARN: no NiagaraSystem export in %s" % path)
            continue
        systems.append(rec)
    systems.sort(key=lambda s: s["name"])
    print("Parsed %d Niagara systems" % len(systems))

    # P2-5 drift review: the GRAPH_HEAVY cutoffs are constants pinned by the
    # suite (21/70/29), so they are NOT recomputed here. Instead each run
    # prints the live p90 of the bulk distribution and warns when the bulk
    # has drifted past the constants (re-extract changed the corpus shape).
    def _p90(vals: list) -> float:
        s = sorted(vals)
        return float(s[min(len(s) - 1, int(len(s) * 0.9))]) if s else 0.0

    p90_scripts = _p90([s["script_count"] for s in systems])
    p90_luts = _p90([s["curve_luts"]["total"] for s in systems])
    print(
        "cutoff review: p90 scripts=%.0f (const %d), p90 LUTs=%.0f (const %d)"
        % (p90_scripts, GRAPH_HEAVY_MIN_SCRIPTS, p90_luts, GRAPH_HEAVY_MIN_LUTS)
    )
    if p90_scripts > GRAPH_HEAVY_MIN_SCRIPTS or p90_luts > GRAPH_HEAVY_MIN_LUTS:
        print(
            "WARN: bulk distribution drifted past GRAPH_HEAVY constants; "
            "review cutoffs (suite pins 21/70/29 — update both together)"
        )

    by_class = Counter(s["complexity"] for s in systems)
    by_folder = Counter(s["folder"] for s in systems)

    mat_paths = set()
    for s in systems:
        for r in s["renderers"]:
            if r.get("material"):
                mat_paths.add(r["material"])
            for p in r.get("override_materials", []) or []:
                if p:
                    mat_paths.add(p)
    resolved = sorted(p for p in mat_paths if p in materials)
    missing = sorted(p for p in mat_paths if p not in materials)
    resolved_no_tex = sorted(
        p for p in resolved if not (materials[p].get("texs") or {})
    )
    with_texture = sum(
        1 for s in systems for r in s["renderers"] if r.get("sprite_texture")
    )

    data = {
        "generated_by": "tools/parse_vfx.py",
        "system_count": len(systems),
        "classes": dict(sorted(by_class.items())),
        "by_folder": dict(sorted(by_folder.items())),
        "material_resolution": {
            "distinct_materials": len(mat_paths),
            "resolved": len(resolved),
            "missing": missing,
            "resolved_without_texture": resolved_no_tex,
            "renderer_entries_with_texture": with_texture,
        },
        "notes": [
            "loop_duration is null for every system: SystemStateData carries "
            "only an unbound ParameterBinding, so no duration is resolvable "
            "from the extracted JSON.",
            "Exposed parameters are names/types only; defaults live in raw "
            "ParameterData bytes and are not decoded.",
            "Niagara compiled graphs are not translated; curve LUTs are counted, "
            "not resampled.",
            "complexity sprite_only means convertible to a plain sprite pipeline; "
            "mesh_or_ribbon means a non-sprite renderer (mesh, ribbon, light, "
            "decal or component) is present; graph_heavy means >= %d scripts or "
            ">= %d curve LUTs or a skeletal-mesh/vector-field dependency."
            % (GRAPH_HEAVY_MIN_SCRIPTS, GRAPH_HEAVY_MIN_LUTS),
            "empty_shell systems have no enabled emitters and no renderer data; "
            "they are classed sprite_only (nothing to convert) and flagged.",
        ],
        "systems": systems,
    }
    (OUT_DIR / "systems.json").write_text(json.dumps(data, indent=2) + "\n")
    print("Wrote %s" % (OUT_DIR / "systems.json"))
    print("classes: %s" % ", ".join("%s=%d" % kv for kv in sorted(by_class.items())))
    print(
        "materials: %d distinct, %d resolved, %d missing"
        % (len(mat_paths), len(resolved), len(missing))
    )

    lines = [
        "# VFX catalogue",
        "",
        "Every extracted Niagara system with its renderers, materials and "
        "auto-conversion class. Generated by `tools/parse_vfx.py` — do not edit.",
        "",
        "| System | Folder | Renderers | Material(s) | Sprite texture | Class |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for s in systems:
        kinds = ", ".join(s["renderer_kinds"]) if s["renderer_kinds"] else "—"
        mats = sorted(
            {
                m
                for r in s["renderers"]
                for m in ([r.get("material")] + (r.get("override_materials") or []))
                if m
            }
        )
        mat_cell = "<br>".join(m.split("/")[-1] for m in mats) if mats else "—"
        texs = sorted(
            {r["sprite_texture"] for r in s["renderers"] if r.get("sprite_texture")}
        )
        tex_cell = "<br>".join(t.split("/")[-1] for t in texs) if texs else "—"
        lines.append(
            "| %s | %s | %s | %s | %s | %s |"
            % (s["name"], s["folder"], kinds, mat_cell, tex_cell, s["complexity"])
        )
    (OUT_DIR / "catalogue.md").write_text("\n".join(lines) + "\n")
    print("Wrote %s" % (OUT_DIR / "catalogue.md"))


if __name__ == "__main__":
    main()
