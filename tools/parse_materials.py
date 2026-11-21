#!/usr/bin/env python3
"""Build game/data/generated/materials.json from extracted material JSONs and PNGs.

Material assets are discovered by name (``MI_*``/``M_*``, ``*_MI``/``*_MI8``)
and by path (``MaterialLibrary``/``Developers``), then accepted only when the
dump's ``Type`` is ``Material``, ``MaterialInstanceConstant`` or
``MaterialInstance``.

UE -> Godot (StandardMaterial3D) parameter mapping used here and in
``game/src/core/level_loader.gd::get_material_for_ue()``:

- Scalar ``Roughness`` (fallbacks: ``FlatRoughness``, average of
  ``Roughness Low``/``Roughness High``, average of ``RoughnessMin``/
  ``RoughnessMax``) -> ``roughness``, clamped to 0..1.
- Scalar ``Metallic`` (fallbacks: ``Metalness``, ``FlatMetallic``,
  average of ``MetallicMin``/``MetallicMax``) -> ``metallic``, clamped.
- Scalar ``Specular`` (fallback ``Spec``) -> ``metallic_specular``, clamped.
- Vector ``EmissiveColor`` (fallbacks ``Emissive``, ``EmissiveTint``,
  ``EmisColor``) -> ``emission`` colour; multiplied in energy by the first
  present emissive scalar (``EmissiveStrength``, ``EmissiveIntensity``,
  ``EmissiveMultiplier``, ``EmissiveMultiply``, ``EmisMultiply``,
  ``EmissiveMult``, ``EmissivePower``, ``EmissiveBrightness``,
  ``EmissiveBrillance``).
- ``TwoSided`` -> ``cull_mode = CULL_DISABLED``.
- ``BlendMode`` containing ``Translucent`` or ``AlphaComposite`` ->
  ``TRANSPARENCY_ALPHA``; ``BLEND_Masked`` -> ``TRANSPARENCY_ALPHA_SCISSOR``
  with ``alpha_scissor_threshold`` from ``BasePropertyOverrides`` /
  ``OpacityMaskClipValue`` (default 0.5).
- ``PhysMaterial`` name is stored for debugging; Godot has no equivalent.
- NOT mapped (kept in the JSON for future work): shading model
  (``MSM_Unlit`` etc. would map to ``SHADING_MODE_UNSHADED`` but current
  art direction relies on shaded+emission materials), ``Opacity`` scalars
  (layer-paint opacities, not alpha), ``Spec``ular colour vectors,
  ``Refraction``/``RefractionDepthBias`` (Godot screen-space refraction is a
  separate pipeline), rain/puddle/grunge/noise/tiling switches and scalars
  (weathering system, no Godot equivalent), mask/channel selector vectors.
"""

import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX_JSON = ROOT / "extracted" / "json"
EX_ASSETS = ROOT / "extracted" / "assets"
OUT = ROOT / "game" / "data" / "generated" / "materials.json"
OUT_MESH_MATS = ROOT / "game" / "data" / "generated" / "mesh_materials.json"
OUT_PROV = ROOT / "game" / "data" / "generated" / "mesh_materials_provenance.json"

_CHUNK_JSON = 0x4E4F534A
_CHUNK_BIN = 0x004E4942
_GLTF_COMPONENT = {5121: ("<B", 1), 5123: ("<H", 2), 5125: ("<I", 4)}


def _short_mat_name(value: str) -> str:
    return str(value).replace("\\", "/").rsplit("/", 1)[-1].split(".")[0]


def _norm_mat_name(value: str) -> str:
    name = _short_mat_name(value).lower()
    while "." in name and name.rsplit(".", 1)[-1].isdigit():
        name = name.rsplit(".", 1)[0]
    return name


def _find_glb_for_ue_mesh(ue_mesh: str):
    if not ue_mesh.startswith("/Game/"):
        return None
    rel = ue_mesh[len("/Game/") :]
    candidates = [
        ROOT / "game" / "assets" / "ue" / "Content" / (rel + ".glb"),
        ROOT / "game" / "assets" / "ue" / "Raw" / "TAT" / "Content" / (rel + ".glb"),
        ROOT / "extracted" / "assets" / "TAT" / "Content" / (rel + ".glb"),
        # P1-1: Engine carriers (BasicShapes/EngineMaterials) ship outside
        # TAT/Content; the Raw mirror (game/assets/ue/Raw -> extracted/assets)
        # resolves them at runtime, so order by their real GLB here.
        ROOT / "extracted" / "assets" / (rel + ".glb"),
    ]
    for c in candidates:
        if c.is_file():
            return c
    return None


def _glb_primitive_material_names(glb_path):
    """GLB primitive material names in primitive order, degenerate filtered.

    Parses the 12-byte GLB header plus JSON chunk, mapping
    primitives[].material -> materials[].name per mesh. Primitives Godot
    drops (fewer than 3 distinct indices or 0 triangles) are filtered so the
    emitted count matches the imported ArrayMesh surface count. Returns None
    when the GLB is missing or unparseable so the caller falls back to
    sidecar order.

    P1-4: also returns a detail dict so the provenance sidecar can mark
    every entry with its slot_order_source plus how many authored
    primitives were filtered (previously invisible slot loss).
    Returns (names_or_None, detail: dict).
    """
    if glb_path is None:
        return None, {"glb_found": False, "authored_primitives": 0, "degenerate_filtered": 0}
    try:
        raw = glb_path.read_bytes()
    except Exception:
        return None, {"glb_found": False, "authored_primitives": 0, "degenerate_filtered": 0}
    try:
        if len(raw) < 12:
            return None, {"glb_found": True, "authored_primitives": 0, "degenerate_filtered": 0, "glb_parse_error": True}
        magic, _version, _declared = struct.unpack_from("<4sII", raw, 0)
        if magic != b"glTF":
            return None, {"glb_found": True, "authored_primitives": 0, "degenerate_filtered": 0, "glb_parse_error": True}
        off = 12
        json_chunk = None
        bin_chunk = b""
        while off + 8 <= len(raw):
            clen, ctype = struct.unpack_from("<II", raw, off)
            off += 8
            chunk = raw[off : off + clen]
            if len(chunk) != clen:
                return None, {"glb_found": True, "authored_primitives": 0, "degenerate_filtered": 0, "glb_parse_error": True}
            if ctype == _CHUNK_JSON and json_chunk is None:
                json_chunk = chunk
            elif ctype == _CHUNK_BIN and len(bin_chunk) == 0:
                bin_chunk = chunk
            off += clen
        if json_chunk is None:
            return None, {"glb_found": True, "authored_primitives": 0, "degenerate_filtered": 0, "glb_parse_error": True}
        gltf = json.loads(json_chunk.rstrip(b" \t\r\n\0").decode("utf-8"))
        materials = gltf.get("materials") or []
        mat_names = [
            (m.get("name") if isinstance(m, dict) else "") or f"material_{i}"
            for i, m in enumerate(materials)
        ]
        accessors = gltf.get("accessors") or []
        buffer_views = gltf.get("bufferViews") or []

        def _is_degenerate(prim: dict) -> bool:
            try:
                mode = int(prim.get("mode", 4))
                attrs = prim.get("attributes") or {}
                pos_acc = attrs.get("POSITION")
                vert_count = None
                if pos_acc is not None:
                    try:
                        vert_count = int(accessors[int(pos_acc)]["count"])
                    except Exception:
                        vert_count = None
                if "indices" in prim:
                    try:
                        acc = accessors[int(prim["indices"])]
                    except Exception:
                        return False
                    if acc.get("sparse"):
                        return False
                    try:
                        count = int(acc["count"])
                    except Exception:
                        return False
                    if count <= 0:
                        return True
                    bv_index = acc.get("bufferView")
                    if bv_index is None:
                        return True
                    try:
                        ctype = int(acc["componentType"])
                    except Exception:
                        return False
                    if ctype not in _GLTF_COMPONENT:
                        return False
                    fmt, elem = _GLTF_COMPONENT[ctype]
                    try:
                        view = buffer_views[int(bv_index)]
                    except Exception:
                        return False
                    base = int(view.get("byteOffset", 0)) + int(
                        acc.get("byteOffset", 0)
                    )
                    stride = int(view.get("byteStride", elem))
                    end = base + (count - 1) * stride + elem if count else base
                    if end > len(bin_chunk):
                        return False
                    seen = set()
                    for i in range(count):
                        v = struct.unpack_from(fmt, bin_chunk, base + i * stride)[0]
                        seen.add(v)
                        if len(seen) >= 3:
                            break
                    distinct = len(seen)
                    # Full distinct set when fewer than 3 found early is
                    # already complete; otherwise at least 3 exist.
                    if distinct < 3:
                        full = set()
                        for i in range(count):
                            full.add(
                                struct.unpack_from(fmt, bin_chunk, base + i * stride)[0]
                            )
                        distinct = len(full)
                    if mode == 4:
                        triangles = count // 3
                    elif mode in (5, 6):
                        triangles = max(0, count - 2)
                    else:
                        triangles = count
                    return distinct < 3 or triangles == 0
                else:
                    if vert_count is None:
                        return True
                    if mode == 4:
                        triangles = vert_count // 3
                    elif mode in (5, 6):
                        triangles = max(0, vert_count - 2)
                    else:
                        triangles = vert_count
                    return vert_count < 3 or triangles == 0
            except Exception:
                return False

        names: list = []
        degenerate_filtered: int = 0
        authored_primitives: int = 0
        meshes = gltf.get("meshes") or []
        if not meshes:
            return None, {"glb_found": True, "authored_primitives": 0, "degenerate_filtered": 0}
        for mesh in meshes:
            prims = (mesh.get("primitives") if isinstance(mesh, dict) else None) or []
            for prim in prims:
                if not isinstance(prim, dict):
                    continue
                authored_primitives += 1
                if _is_degenerate(prim):
                    degenerate_filtered += 1
                    continue
                mat_idx = prim.get("material")
                if mat_idx is None:
                    continue
                try:
                    idx = int(mat_idx)
                except Exception:
                    continue
                if 0 <= idx < len(mat_names):
                    names.append(mat_names[idx])
                else:
                    names.append("")
        detail = {
            "glb_found": True,
            "authored_primitives": authored_primitives,
            "degenerate_filtered": degenerate_filtered,
        }
        if not names:
            return None, detail
        return names, detail
    except Exception:
        return None, {"glb_found": True, "authored_primitives": 0, "degenerate_filtered": 0, "glb_parse_error": True}


def ue_to_res_png(obj_path: str) -> str:
    if not obj_path or not isinstance(obj_path, str):
        return ""
    clean = obj_path.split(".")[0]
    if clean.startswith("/Game/"):
        clean = clean[6:]
    if (EX_ASSETS / (clean + ".png")).exists():
        return "res://assets/ue/Raw/" + clean + ".png"
    if (EX_ASSETS / "TAT" / "Content" / (clean + ".png")).exists():
        return "res://assets/ue/Content/" + clean + ".png"
    return ""


DIFFUSE_SUFFIXES = ("_d", "_da", "_bc", "_bco", "_c", "_alb", "_basecolor", "_diffuse")

MATERIAL_TYPES = ("Material", "MaterialInstanceConstant", "MaterialInstance")

# Strong family words anchor a candidate even when its stem is named differently
# (e.g. /Glass/WindowPanel_D belongs to the glass family).
STRONG_FAMILIES = (
    "glass",
    "metal",
    "brass",
    "bronze",
    "iron",
    "steel",
    "wood",
    "plank",
    "board",
    "stone",
    "rock",
    "marble",
    "plaster",
    "ceramic",
    "brick",
    "fabric",
    "roof",
)

# Material-package categories used when no strong family word applies.
PATH_CATEGORIES = (
    "Wood",
    "Stone",
    "Metal",
    "Plaster",
    "Brick",
    "Roof",
    "Glass",
    "Fabric",
    "Character",
)


def _is_material_candidate(jf: Path) -> bool:
    """Cheap pre-filter so huge level JSONs are never parsed as materials."""
    name = jf.stem
    if name.startswith(("MI_", "M_")):
        return True
    if name.endswith(("_MI", "_MI8")):
        return True
    return "MaterialLibrary" in str(jf.parent) or "Developers" in str(jf.parent)


def _is_ui_or_map_stem(low: str) -> bool:
    """UI/map art must never dress 3D geometry."""
    return (
        "mapbuilding" in low
        or low.startswith("t_map")
        or "poster" in low
        or "icon" in low
        or "glyph" in low
        or "logo" in low
        or "ui_" in low
        or "hud_" in low
    )


def _is_eye_stem(low: str) -> bool:
    return low.startswith("t_eye")


def _is_character_context(mat_name: str, pkg: str) -> bool:
    return (
        "/character/" in pkg.lower()
        or "eyelibrary" in pkg.lower()
        or "eye" in mat_name.lower()
    )


def _family_words(mat_name: str) -> list:
    low: str = mat_name.lower()
    return [w for w in STRONG_FAMILIES if w in low]


def _path_category(pkg: str) -> str:
    parts = {p.lower() for p in pkg.split("/")}
    for cat in PATH_CATEGORIES:
        if cat.lower() in parts:
            return cat
    return ""


def _candidate_score(
    res_path: str, tokens: list, family_words: list, path_category: str
) -> tuple:
    """Comparable (family_hit, path_hit, token_score, -stem_len).

    ``family_hit`` and ``path_hit`` inspect the full res path so a texture's
    folder (``/Glass/``) anchors it even when its stem has no family word.
    """
    stem: str = Path(res_path).stem.lower()
    hay: str = res_path.lower()
    family_hit: int = 1 if any(w in hay for w in family_words) else 0
    path_hit: int = 1 if path_category and path_category.lower() in hay else 0
    token_score: int = sum(len(tok) for tok in tokens if tok in stem)
    return (family_hit, path_hit, token_score, -len(stem))


def _is_albedo_stem(low: str, allow_ui_map: bool = False) -> bool:
    if not low.endswith(DIFFUSE_SUFFIXES):
        return False
    if not allow_ui_map and _is_ui_or_map_stem(low):
        return False
    if low.endswith(("_ma", "_mask", "_ao", "_e")):
        return False
    return not any(
        k in low
        for k in ("paintstroke", "grunge", "noise", "default", "black", "white")
    )


def _best_albedo_candidate(
    res_paths,
    tokens: list,
    family_words: list,
    path_category: str,
    is_character: bool,
    allow_unsignalled: bool = False,
    allow_ui_map: bool = False,
) -> str:
    needs_anchor: bool = bool(family_words) or (
        path_category != "" and path_category != "Character"
    )
    best: str = ""
    best_score: tuple | None = None
    for res in res_paths:
        low: str = Path(res).stem.lower()
        if not _is_albedo_stem(low, allow_ui_map):
            continue
        if _is_eye_stem(low) and not is_character:
            continue
        score: tuple = _candidate_score(res, tokens, family_words, path_category)
        if not allow_unsignalled:
            if score[0] == 0 and score[1] == 0 and score[2] <= 0:
                continue
            # F2: a categorised material must not borrow a cross-category
            # texture; leave it untextured instead of inventing a binding.
            if needs_anchor and score[0] == 0 and score[1] == 0:
                continue
        if best_score is None or score > best_score:
            best = res
            best_score = score
    return best


def _best_texture_candidate(
    res_paths,
    suffixes: tuple,
    tokens: list,
    family_words: list,
    path_category: str,
    is_character: bool,
    allow_ui_map: bool = False,
) -> str:
    """Best normal/ORM candidate, falling back to the first when unsignalled."""
    first: str = ""
    best: str = ""
    best_score: tuple | None = None
    for res in res_paths:
        low: str = Path(res).stem.lower()
        if not low.endswith(suffixes):
            continue
        if not allow_ui_map and _is_ui_or_map_stem(low):
            continue
        if _is_eye_stem(low) and not is_character:
            continue
        if first == "":
            first = res
        score: tuple = _candidate_score(res, tokens, family_words, path_category)
        if score[0] == 0 and score[1] == 0 and score[2] <= 0:
            continue
        if best_score is None or score > best_score:
            best = res
            best_score = score
    return best if best != "" else first


# Category -> candidate texture stems (lowercase, verified against extracted Raw set).
CATEGORY_FALLBACK_STEMS = {
    "brick": [
        "t_civicbricka_d",
        "t_oldbricksa_d",
        "t_oldbricksb_d",
        "t_brickgrounda_d",
        "t_roadbricksa_d",
    ],
    "stone": [
        "t_wallstonea_d",
        "t_civicstonea_d",
        "t_modularstonea_d",
        "t_stonewalld_da",
        "t_granitefloora_d",
    ],
    "wood": [
        "t_woodfloora_d",
        "t_manorwood_d",
        "t_woodboardsa_d",
        "t_woodvarnisha_d",
        "t_manorpanels_d",
    ],
    "plaster": [
        "t_plaster_d",
        "t_plastera_bco",
        "t_plasterb_d",
        "t_plasterc_d",
        "t_ceilingplaster_da",
    ],
    "roof": [
        "t_roofslatea_d",
        "t_roofslatee_d",
        "t_roofbitumena_da",
        "t_roofslatec_da",
    ],
    "metal": [
        "t_trimmetala_d",
        "t_metalstripsa_bco",
        "t_basicmetalsurfacetrimA_d".lower(),
        "t_metaltilepipes_d",
        "t_grate_d",
    ],
    "dirt": [
        "t_grounddirta_d",
        "t_grounddirta_bco",
        "t_grounddirtb_d",
        "t_dirtmossa_bc",
    ],
}


def _extract_real_params(props: dict) -> tuple:
    """Flatten real UE material data: scalars, vectors, switches, render flags."""
    params: dict = {}
    for sv in props.get("ScalarParameterValues") or []:
        nm = ((sv.get("ParameterInfo") or {}).get("Name")) or ""
        val = sv.get("ParameterValue")
        if nm != "" and isinstance(val, (int, float)):
            params[nm] = round(float(val), 4)
    vectors: dict = {}
    for vv in props.get("VectorParameterValues") or []:
        nm = ((vv.get("ParameterInfo") or {}).get("Name")) or ""
        val = vv.get("ParameterValue") or {}
        if nm != "" and "R" in val:
            vectors[nm] = [
                round(float(val.get("R", 0.0)), 4),
                round(float(val.get("G", 0.0)), 4),
                round(float(val.get("B", 0.0)), 4),
                round(float(val.get("A", 1.0)), 4),
            ]
    switches: dict = {}
    for sw in (props.get("StaticParametersRuntime") or {}).get(
        "StaticSwitchParameters"
    ) or []:
        nm = ((sw.get("ParameterInfo") or {}).get("Name")) or ""
        if nm != "" and isinstance(sw.get("Value"), bool):
            switches[nm] = sw["Value"]
    render: dict = {}
    if "BlendMode" in props and props["BlendMode"]:
        render["blend_mode"] = str(props["BlendMode"])
    if props.get("TwoSided") is True:
        render["two_sided"] = True
    if "ShadingModel" in props and props["ShadingModel"]:
        render["shading_model"] = str(props["ShadingModel"])
    clip = (props.get("BasePropertyOverrides") or {}).get("OpacityMaskClipValue")
    if clip is None:
        clip = props.get("OpacityMaskClipValue")
    if clip is None and isinstance(props.get("bOpacityMaskClipValue"), (int, float)):
        clip = props["bOpacityMaskClipValue"]
    if isinstance(clip, (int, float)):
        render["opacity_mask_clip"] = round(float(clip), 4)
    phys = ""
    pm = props.get("PhysMaterial") or {}
    if isinstance(pm, dict):
        op = pm.get("ObjectPath") or ""
        if op:
            phys = op.split(".")[0].rstrip("/").split("/")[-1]
        if not phys:
            on = pm.get("ObjectName") or ""
            m = re.search(r"'([^']+)'", on)
            phys = m.group(1) if m else on
    return params, vectors, switches, render, phys


def _strip_material_base(mat_name: str) -> str:
    base: str = mat_name.lower()
    base = re.sub(r"^(mi_|m_)", "", base)
    base = re.sub(r"(_inst.*|_instance.*)$", "", base)
    base = base.strip("_")
    return base


TOKEN_DROP = {
    "mi",
    "m",
    "ml",
    "inst",
    "instance",
    "d",
    "da",
    "bc",
    "bco",
    "c",
    "alb",
    "default",
    "base",
    "black",
    "white",
    "blue",
    "red",
    "green",
    "yellow",
    "orange",
    "purple",
    "teal",
    "cream",
    "grey",
    "gray",
    "pink",
    "cyan",
    "magenta",
    "dark",
    "light",
    "bright",
    "old",
    "new",
    "smooth",
    "rough",
    "dirty",
    "clean",
    "worn",
    "alt",
    "variant",
    "var",
}


def _diffuse_tokens(mat_name: str) -> list:
    """Family tokens from the material stem, for scoring diffuse candidates.

    Combines underscore-separated tokens with CamelCase words so
    ``MI_PlasterSmoothD`` yields ``plaster`` while modifier words such as
    ``dark``/``old``/``smooth`` never vote for an unrelated texture family.
    """
    base: str = _strip_material_base(mat_name)
    underscored: list = re.split(r"[^a-z0-9]+", base)
    camel: str = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", mat_name)
    camel = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", " ", camel)
    camel_words: list = re.split(r"[^A-Za-z0-9]+", camel.lower())
    tokens: list = []
    for tok in underscored + camel_words:
        if len(tok) < 4 or tok in TOKEN_DROP or tok in tokens:
            continue
        tokens.append(tok)
    return tokens


def _stem_fallback_albedo(
    mat_name: str, pkg: str, parent: str, tex_by_stem: dict
) -> tuple[str, str]:
    """Tiered albedo guess. Returns (res_path, tier) where tier is one of
    "stem-direct" (Tier 1 exact-stem hit), "ranked" (Tier 2 scored
    candidate), "category" (Tier 3 generic family guess), or "" (no bind).
    P1-3: the tier is recorded per material as albedo_source so a generic
    category bind is never mistaken for authored truth downstream."""
    base: str = _strip_material_base(mat_name)
    if base == "":
        return "", ""
    is_character: bool = _is_character_context(mat_name, pkg)
    tokens: list = _diffuse_tokens(mat_name)
    family_words: list = _family_words(mat_name)
    path_category: str = _path_category(pkg)
    allow_ui_map: bool = "/ui/" in pkg.lower() or "/map/" in pkg.lower()
    # 1) Direct stem match: look for diffuse textures whose stem mentions the base.
    best: str = ""
    best_len: int = 10_000
    for tstem, res in tex_by_stem.items():
        low: str = tstem.lower()
        if not _is_albedo_stem(low, allow_ui_map):
            continue
        if _is_eye_stem(low) and not is_character:
            continue
        if base in low or low in ("t_" + base + "_d", "t_" + base + "_bc"):
            if len(low) < best_len:
                best = res
                best_len = len(low)
    if best != "":
        return best, "stem-direct"
    # 2) Rank every diffuse candidate by family anchor, path category, tokens
    # and stem specificity. Candidates with no signal at all are rejected.
    best_res: str = _best_albedo_candidate(
        tex_by_stem.values(),
        tokens,
        family_words,
        path_category,
        is_character,
        allow_ui_map=allow_ui_map,
    )
    if best_res != "":
        return best_res, "ranked"
    # 3) Category fallback: material/pkg/parent name mentions Brick/Stone/Wood/etc.
    hay: str = (mat_name + " " + pkg + " " + parent).lower()
    for cat, stems in CATEGORY_FALLBACK_STEMS.items():
        if cat in hay:
            for cand in stems:
                if cand in tex_by_stem:
                    found: str = tex_by_stem[cand]
                    return found, "category"
    return "", ""


def main():
    tex_by_stem = {}
    for png in EX_ASSETS.rglob("*.png"):
        rel = png.relative_to(EX_ASSETS)
        s = str(rel)
        res = (
            ("res://assets/ue/Content/" + s[len("TAT/Content/") :])
            if s.startswith("TAT/Content/")
            else ("res://assets/ue/Raw/" + s)
        )
        tex_by_stem.setdefault(png.stem.lower(), res)

    raw_mats = {}
    for jf in EX_JSON.rglob("*.json"):
        if not _is_material_candidate(jf):
            continue
        try:
            exps = json.loads(jf.read_text())
        except Exception:
            continue
        if not isinstance(exps, list) or not exps:
            continue
        exp = exps[0]
        if exp.get("Type") not in MATERIAL_TYPES:
            continue
        name = jf.stem
        props = exp.get("Properties") or {}
        pkg = exp.get("Package") or (
            "/Game/" + str(jf.relative_to(EX_JSON).with_suffix(""))
        )
        parent = ((props.get("Parent") or {}).get("ObjectPath") or "").split(".")[0]
        texs = {}
        for tv in props.get("TextureParameterValues") or []:
            pinfo = tv.get("ParameterInfo") or {}
            pname = (pinfo.get("Name") or "").lower()
            assoc = pinfo.get("Association") or ""
            tpath = ue_to_res_png(
                (tv.get("ParameterValue") or {}).get("ObjectPath") or ""
            )
            if not tpath:
                continue
            stem = Path(tpath).stem.lower()
            is_mask = (
                "blendparameter" in assoc.lower()
                or stem.endswith(("_ma", "_mask", "_m", "_r", "_g", "_b", "_a", "_ao"))
                or any(
                    k in pname
                    for k in (
                        "mask",
                        "blend",
                        "grunge",
                        "noise",
                        "stroke",
                        "pattern",
                        "detail",
                        "cavity",
                        "height",
                    )
                )
            )
            if any(k in pname for k in ("normal", "norm")) or stem.endswith(
                ("_n", "_nm")
            ):
                texs.setdefault("normal", tpath)
            elif (
                "orm" in pname
                or "roughness" in pname
                or "arm" in pname
                or stem.endswith(("_orm", "_ormm", "_arm"))
            ):
                texs.setdefault("orm", tpath)
            elif "emissive" in pname or stem.endswith("_e"):
                if "black" not in stem and not name.startswith("M_Env"):
                    texs.setdefault("emissive", tpath)
            elif "opacity" in pname or stem.endswith(("_o", "_opacity")):
                texs.setdefault("opacity", tpath)
            elif not is_mask and (
                any(
                    k in pname
                    for k in (
                        "albedo",
                        "basecolor",
                        "base_color",
                        "diffuse",
                        "color",
                        "bc",
                        "base texture",
                    )
                )
                or pname == "texture"
                or stem.endswith(("_d", "_da", "_bc", "_bco", "_c", "_alb"))
            ):
                texs.setdefault("albedo", tpath)

        # Fallback: UE5 MaterialLayers store used textures in TextureStreamingData and CachedExpressionData.ReferencedTextures
        stream_paths = []
        for tsd in props.get("TextureStreamingData") or []:
            tn = (tsd.get("TextureName") or "").lower()
            if tn and tn in tex_by_stem:
                stream_paths.append(tex_by_stem[tn])
        ref_paths = []
        for rt in (exp.get("CachedExpressionData") or {}).get(
            "ReferencedTextures"
        ) or []:
            if isinstance(rt, dict):
                tp = ue_to_res_png(rt.get("ObjectPath") or "")
                if tp:
                    ref_paths.append(tp)
        tokens: list = _diffuse_tokens(name)
        family_words: list = _family_words(name)
        path_category: str = _path_category(pkg)
        is_character: bool = _is_character_context(name, pkg)
        allow_ui_map: bool = "/ui/" in pkg.lower() or "/map/" in pkg.lower()
        extra_paths = stream_paths + ref_paths
        if "normal" not in texs:
            normal_pick: str = _best_texture_candidate(
                extra_paths,
                ("_n", "_nm"),
                tokens,
                family_words,
                path_category,
                is_character,
                allow_ui_map,
            )
            if normal_pick != "":
                texs["normal"] = normal_pick
        if "orm" not in texs:
            orm_pick: str = _best_texture_candidate(
                extra_paths,
                ("_orm", "_ormm", "_arm"),
                tokens,
                family_words,
                path_category,
                is_character,
                allow_ui_map,
            )
            if orm_pick != "":
                texs["orm"] = orm_pick
        if "opacity" not in texs:
            opacity_pick: str = _best_texture_candidate(
                extra_paths,
                ("_o", "_opacity"),
                tokens,
                family_words,
                path_category,
                is_character,
                allow_ui_map,
            )
            if opacity_pick != "":
                texs["opacity"] = opacity_pick
        # Albedo: TextureStreamingData is a used-texture list, not array-first.
        # Rank every candidate by family anchor, path category, tokens and stem
        # specificity. A signal-less stream pick is ignored (F4) except for
        # Character materials, whose cooked metal/glass TSDs are authored truth.
        if "albedo" not in texs:
            stream_pick: str = _best_albedo_candidate(
                stream_paths,
                tokens,
                family_words,
                path_category,
                is_character,
                allow_unsignalled=(path_category == "Character"),
                allow_ui_map=allow_ui_map,
            )
            stream_single: bool = False
            if stream_pick == "":
                # A single authored stream diffuse is not an arbitrary pick;
                # trust it even when its name shares no token with the material.
                unique_stream: list = []
                for res in stream_paths:
                    low: str = Path(res).stem.lower()
                    if not _is_albedo_stem(low, allow_ui_map):
                        continue
                    if _is_eye_stem(low) and not is_character:
                        continue
                    if res not in unique_stream:
                        unique_stream.append(res)
                if len(unique_stream) == 1:
                    stream_pick = unique_stream[0]
                    stream_single = True
            fb, fb_tier = _stem_fallback_albedo(name, pkg, parent, tex_by_stem)
            ref_pick: str = _best_albedo_candidate(
                ref_paths,
                tokens,
                family_words,
                path_category,
                is_character,
                allow_ui_map=allow_ui_map,
            )
            pick: str = stream_pick or fb or ref_pick
            if pick != "":
                texs["albedo"] = pick
            # P1-3 sentinel: record HOW the albedo was bound. "authored"
            # (UE parameter) > stream-ranked/single > stem-direct > ranked >
            # reference-ranked > category (generic family guess). Anything
            # reading materials.json must be able to tell a guess from truth.
            if stream_pick != "" and pick == stream_pick:
                albedo_source = "stream-single" if stream_single else "stream-ranked"
            elif fb != "" and pick == fb:
                albedo_source = "fallback-" + fb_tier
            elif ref_pick != "" and pick == ref_pick:
                albedo_source = "reference-ranked"
            else:
                albedo_source = "none"
        else:
            albedo_source = "authored"
        tint = None
        for vv in props.get("VectorParameterValues") or []:
            pinfo = vv.get("ParameterInfo") or {}
            pname = (pinfo.get("Name") or "").lower()
            if (
                "mask" in pname
                or "channel" in pname
                or "blendparameter" in (pinfo.get("Association") or "").lower()
            ):
                continue
            if (
                "tint" in pname
                or "basecolor" in pname
                or "albedo" in pname
                or pname == "color"
            ):
                val = vv.get("ParameterValue") or {}
                if "R" in val:
                    r, g, b, a = (
                        float(val["R"]),
                        float(val["G"]),
                        float(val["B"]),
                        float(val.get("A", 1.0)),
                    )
                    # Skip RGBA channel selector vectors like [0, 1, 0, 0] or [1, 0, 0, 0]
                    if a <= 0.01 or (
                        max(r, g, b) >= 0.99
                        and min(r, g, b) == 0.0
                        and (r + g + b) <= 1.01
                    ):
                        continue
                    tint = [round(r, 3), round(g, 3), round(b, 3), round(a, 3)]
                    break
        p_scalars, p_vectors, p_switches, p_render, p_phys = _extract_real_params(props)
        raw_mats[pkg] = {
            "parent": parent,
            "texs": texs,
            "tint": tint,
            "params": p_scalars,
            "vectors": p_vectors,
            "switches": p_switches,
            "render": p_render,
            "phys_material": p_phys,
            "albedo_source": albedo_source,
        }

    # Resolve parent inheritance
    resolved = {}

    def resolve(pkg, depth=0):
        if pkg in resolved:
            return resolved[pkg]
        if depth > 8 or pkg not in raw_mats:
            return {
                "texs": {},
                "tint": None,
                "params": {},
                "vectors": {},
                "switches": {},
                "render": {},
                "phys_material": "",
                "albedo_source": "none",
            }
        cur = raw_mats[pkg]
        base = (
            resolve(cur["parent"], depth + 1)
            if cur["parent"]
            else {
                "texs": {},
                "tint": None,
                "params": {},
                "vectors": {},
                "switches": {},
                "render": {},
                "phys_material": "",
                "albedo_source": "none",
            }
        )
        texs = dict(base["texs"])
        texs.update(cur["texs"])
        tint = cur["tint"] if cur["tint"] is not None else base["tint"]
        params = dict(base["params"])
        params.update(cur["params"])
        vectors = dict(base["vectors"])
        vectors.update(cur["vectors"])
        switches = dict(base["switches"])
        switches.update(cur["switches"])
        render = dict(base["render"])
        render.update(cur["render"])
        phys = cur["phys_material"] or base["phys_material"]
        # P1-3: an albedo bound on the child wins with the child's source;
        # otherwise the inherited source travels with the inherited bind.
        if "albedo" in cur["texs"]:
            albedo_source = cur["albedo_source"]
        else:
            albedo_source = base["albedo_source"]
        resolved[pkg] = {
            "texs": texs,
            "tint": tint,
            "params": params,
            "vectors": vectors,
            "switches": switches,
            "render": render,
            "phys_material": phys,
            "albedo_source": albedo_source,
        }
        return resolved[pkg]

    for k in raw_mats:
        resolve(k)

    # Keep only entries that have at least one texture, tint, or real parameter.
    out = {}
    for k, v in resolved.items():
        if (
            v["texs"]
            or v["tint"]
            or v["params"]
            or v["vectors"]
            or v["switches"]
            or v["render"]
            or v["phys_material"]
        ):
            entry = {
                "texs": v["texs"],
                "tint": v["tint"],
                "params": v["params"],
                "vectors": v["vectors"],
                "switches": v["switches"],
                # P1-3: HOW the albedo was bound (authored vs guess tier).
                "albedo_source": v.get("albedo_source", "none"),
            }
            if v["render"]:
                entry["render"] = v["render"]
            if v["phys_material"]:
                entry["phys_material"] = v["phys_material"]
            out[k] = entry
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=2))
    n_params = sum(
        1 for v in out.values() if v["params"] or v["vectors"] or v["switches"]
    )
    print(f"Resolved {len(out)} materials ({n_params} with real params) -> {OUT}")
    # P1-3 sentinel: Tier-3 (generic category guess) binds are counted and
    # fail loudly on growth. Baseline pinned 2026-11-20; a re-extract that
    # heals guesses into authored/stream binds LOWERs this number (good),
    # but a number above the cap means new guessing crept in (bad).
    from collections import Counter as _Counter
    src_counts = _Counter(v.get("albedo_source", "none") for v in out.values())
    print(f"albedo_source counts: {dict(sorted(src_counts.items()))}")
    MAX_CATEGORY_FALLBACK_ALBEDOS = 0  # pinned 2026-11-20: no shipped material needs it
    n_category = src_counts.get("fallback-category", 0)
    if n_category > MAX_CATEGORY_FALLBACK_ALBEDOS:
        raise SystemExit(
            f"category-fallback albedos grew to {n_category} "
            f"(cap {MAX_CATEGORY_FALLBACK_ALBEDOS}); new guessing crept in"
        )

    mesh_mats = {}
    mesh_mats_prov: dict = {}
    glb_ordered = 0
    sidecar_fallback = 0
    for mf in EX_ASSETS.rglob("*.materials.json"):
        rel = str(mf.relative_to(EX_ASSETS)).replace(".materials.json", "")
        if rel.startswith("TAT/Content/"):
            rel = rel[len("TAT/Content/") :]
        ue_mesh = "/Game/" + rel
        try:
            slots = json.loads(mf.read_text())
        except Exception:
            continue
        sidecar_list = [s for s in slots if isinstance(s, dict)]
        sidecar_index: dict = {}
        for s in sidecar_list:
            full = (s.get("material") or "").split(".")[0]
            if not full:
                continue
            key = _norm_mat_name(full)
            if key and key not in sidecar_index:
                sidecar_index[key] = full
        glb_names, glb_detail = _glb_primitive_material_names(_find_glb_for_ue_mesh(ue_mesh))
        # P1-4 sentinel: per-entry slot_order_source. mesh_materials.json
        # values stay plain slot lists (level_loader.gd binds them positionally
        # and cannot be touched from here); the HOW lives in the sidecar.
        prov: dict = {
            "slot_order_source": "glb" if glb_names is not None else "sidecar",
            "glb_found": glb_detail.get("glb_found", False),
            "authored_primitives": glb_detail.get("authored_primitives", 0),
            "degenerate_filtered": glb_detail.get("degenerate_filtered", 0),
            "emitted_slots": 0,
        }
        if glb_detail.get("glb_parse_error"):
            prov["glb_parse_error"] = True
        if glb_names is not None:
            resolved: list = []
            for gname in glb_names:
                resolved.append(sidecar_index.get(_norm_mat_name(gname), ""))
            mesh_mats[ue_mesh] = resolved
            prov["emitted_slots"] = len(resolved)
            glb_ordered += 1
        else:
            mesh_mats[ue_mesh] = [
                (s.get("material") or "").split(".")[0] for s in sidecar_list
            ]
            prov["emitted_slots"] = len(mesh_mats[ue_mesh])
            prov["authored_primitives"] = len(sidecar_list)
            sidecar_fallback += 1
        mesh_mats_prov[ue_mesh] = prov
    OUT_MESH_MATS.write_text(json.dumps(mesh_mats, indent=2))
    print(
        f"Mapped {len(mesh_mats)} mesh material slot lists "
        f"({glb_ordered} GLB-ordered, {sidecar_fallback} sidecar-fallback) -> {OUT_MESH_MATS}"
    )
    # P1-4: degenerate primitives Godot drops are invisible slot loss unless
    # counted. Name every sidecar-fallback mesh (no GLB to order by) and
    # every mesh that lost primitives to the degenerate filter.
    n_degen = sum(1 for p in mesh_mats_prov.values() if p["degenerate_filtered"] > 0)
    n_degen_slots = sum(p["degenerate_filtered"] for p in mesh_mats_prov.values())
    print(f"meshes with degenerate-filtered primitives: {n_degen} ({n_degen_slots} primitives)")
    for ue_mesh in sorted(mesh_mats_prov):
        if mesh_mats_prov[ue_mesh]["slot_order_source"] == "sidecar":
            print(f"[slot-order-sidecar] {ue_mesh}")
    OUT_PROV.write_text(json.dumps(mesh_mats_prov, indent=2))
    print(f"wrote slot-order provenance ({len(mesh_mats_prov)} entries) -> {OUT_PROV}")


if __name__ == "__main__":
    main()
