extends Node
## High-performance UE5 -> Godot 4.7 level builder.
## Loads extracted .tatlevel.json sublevels, batches repeated .glb meshes into MultiMeshInstance3D,
## binds real PBR materials (Albedo/Normal/ORM) from materials.json + mesh_materials.json,
## generates StaticBody3D collision, and extracts real spawn/guard/loot/escape markers.

const _VfxManager: GDScript = preload("res://src/core/vfx_manager.gd")
const MobileProfile: GDScript = preload("res://src/core/mobile_profile.gd")
const WeatherProfile: GDScript = preload("res://src/core/weather_profile.gd")
const LANDSCAPE_SHADER: Shader = preload("res://src/core/tat_landscape.gdshader")
const EMISSIVE_CPD_SHADER: Shader = preload("res://src/core/tat_emissive_cpd.gdshader")
const GLASS_SHADER: Shader = preload("res://src/core/tat_glass.gdshader")
const HDR_EMISSIVE_SHADER: Shader = preload("res://src/core/tat_hdr_emissive.gdshader")

## Landscape layer name -> extracted albedo texture. Missing layers are skipped
## (the shader normalizes the remaining weights) instead of binding a guessed
## texture. Puddle/GroundWet have no recovered ground albedo yet.
const LANDSCAPE_LAYER_TEX: Dictionary = {
	"CobbleA": "res://assets/ue/Raw/MaterialLibrary/Environment/Stone/FloorExterior/T_RoadBricksA_D.png",
	"CobbleB": "res://assets/ue/Raw/MaterialLibrary/Environment/Stone/FloorExterior/T_GroundCobbleA_D.png",
	"GroundA": "res://assets/ue/Raw/MaterialLibrary/Environment/Nature/Dirt/T_GroundDirtA_D.png",
	"GrassA": "res://assets/ue/Raw/MaterialLibrary/Environment/Nature/Grass/T_GrassA_DA.png",
	"RockTileA": "res://assets/ue/Raw/MaterialLibrary/Environment/Stone/RockTile/T_RockTile_D.png",
}

signal load_progress(pct: float, status: String)

var _materials_db: Dictionary = {}
var _materials_db_lower: Dictionary = {}
var _mesh_mats_db: Dictionary = {}
var _mesh_mats_db_lower: Dictionary = {}
var _tex_cache: Dictionary = {}
var _std_mat_cache: Dictionary = {}
var _mesh_res_cache: Dictionary = {} # ue_path -> { "mesh": Mesh, "shape": Shape3D }
## L1/L2 sentinels: corrupt imports (resolved path, failed load) are tracked
## separately from missing meshes so a broken GLB never hides in the missing
## list; substring-guess fallback materials are tiered + counted. Export
## gates read these via _finalize (meshes_ok).
var corrupt_meshes: Array[String] = []
var corrupt_mesh_count: int = 0
var fallback_materials: Array[String] = []
var fallback_material_count: int = 0
var _override_mesh_cache: Dictionary = {} # ue_path + "||" + ov_key -> Mesh
var _emissive_cpd_mat: ShaderMaterial = null

## TASK 4.2 tiny-texture mip guard: icon-size sprites (min dimension <32px,
## i.e. below TINY_TEX_MIN_SIZE) skip the mip chain — a full mip chain on a <32px
## wastes memory and can warn/error on some drivers. Landscape/PBR textures
## (>= TINY_TEX_MIN_SIZE) always keep/generate mipmaps; no project-wide import
## default is changed. The FileAccess path skips generate_mipmaps(); the
## ResourceLoader/.ctex path strips the import mip chain (or keeps the tiny
## texture linear) via _guard_tiny_resource_texture. Skips are visibly
## accounted in skipped_tiny_textures (no silent hide); skipped_tiny_count
## mirrors the array size.
const TINY_TEX_MIN_SIZE: int = 32
var skipped_tiny_textures: Array[String] = []
var skipped_tiny_count: int = 0

## PG-1 texture VRAM budget. The generated .ctex library is imported Lossless
## with mipmaps off and no size limit, so a Guildhall load pulls ~8.9 GB of
## RGBA8 textures onto an 8 GB card and the driver thrashes (measured
## 86.7 ms/frame, 7.8 GB GPU use at 1920x1080). Godot 4.7.2 has no texture
## streaming, so the loader caps the long edge of every oversized texture at
## load time instead. 0 disables the cap; the QA/perf harness overrides the
## value with TAT2_TEX_CAP=<px> for A/B runs. Downscales are accounted in
## downscaled_textures/downscaled_count (no silent hide), the same way the
## tiny-texture mip guard is.
##
## 1024 is measured, not guessed: the Guildhall binds 631 unique textures =
## 5.95 GB RGBA8 at a 2048 cap (355 of them 2048^2) and only 2.04 GB at 1024.
## Live Vulkan 1080p frame time fell 125.7 -> 58.2 ms from that change alone.
## The real long-term fix is the import pipeline (VRAM compression + size
## cap, as tools/prepare_mobile_project.py already does for Android).
const TEX_BUDGET_MAX_DIM: int = 1024
var texture_budget_max_dim: int = TEX_BUDGET_MAX_DIM
var downscaled_textures: Array[String] = []
var downscaled_count: int = 0

# --- Spatial chunking & culling tuning (perf P1/P2/P4) ----------------------
## Repeated meshes are partitioned into CHUNK_SIZE x CHUNK_SIZE XZ cells so every
## MultiMeshInstance3D gets a tight AABB that Godot's frustum culler can reject.
const CHUNK_SIZE: float = 32.0
## visibility_range_* is measured from the instance AABB centre; a 32m chunk's
## centre can be half a cell away from the prop being culled, so pad the ranges.
const CHUNK_RADIUS_PAD: float = CHUNK_SIZE * 0.5
const CLUTTER_VIS_RANGE: float = 22.0
const TINY_PROP_VIS_RANGE: float = 45.0
const SMALL_PROP_VIS_RANGE: float = 95.0
const TINY_PROP_LEN: float = 1.2
const SMALL_PROP_LEN: float = 4.0
const OCCLUDER_MIN_LEN: float = 6.0
const OCCLUDER_MAX_LEN: float = 48.0
## F9 wall-flicker guard: occluder candidates thinner than this never qualify.
## Measured across all 143 Guildhall occluder-candidate GLBs (POSITION
## accessor min/max): thin skins (grates 0.08-0.16 m, plates 0.11-0.13 m,
## signs 0.12 m) sit below 0.25 m, while the SM_Urban_Ext_Wall_4x6 workhorse
## (11879 instances) measures 0.30 m and foundations 0.39 m, so 0.25 m keeps
## every load-bearing occluder class and only drops degenerate skins whose
## faces sit coplanar with the masonry behind them.
const OCCLUDER_MIN_THICK_M: float = 0.25
const MAX_OCCLUDERS: int = 768
const MAX_SHAPES_PER_BODY: int = 384
const MAX_TOTAL_SHAPES: int = 32000
## T6 collider-budget partition (AUDIT.md T6 + core P1-L4): the single 32k
## shape budget is split so curb ribbons can never starve building colliders
## (or vice versa). Buildings carry world integrity (walls/floors), so they
## keep 28000; curb ribbons emit 3 boxes per segment across at most
## CURB_MAX_SPLINES (64) splines and are capped at 4000. The partitions sum
## exactly to MAX_TOTAL_SHAPES, so the global cap still holds as a backstop.
const MAX_BUILDING_SHAPES: int = 28000
# FTUE is a whole-city tutorial map: 34,201 authored meshes against the 28,000
# default. Raising the budget for this map (logged, never silent) keeps every
# gameplay collider and the safe-room start instead of dropping 6,201 shapes.
const MAX_BUILDING_SHAPES_FTUE: int = 40000
const MAX_TOTAL_SHAPES_FTUE: int = 44000
const MAX_CURB_SHAPES: int = 4000
const LIGHT_DISTANCE_FADE_BEGIN: float = 28.0
const LIGHT_DISTANCE_FADE_LENGTH: float = 12.0
const PROGRESS_YIELD_EVERY: int = 64
## L6: rect-light quad emission shares constants with its omni. The quad
## used a disconnected 2.0 energy while its omni faded with distance — glow
## without light at range. Energy stays 2.0 (authored look) but the quad now
## fades over LIGHT_DISTANCE_FADE_* like its omni, so the two cannot desync.

## Authored UE light intensity -> Godot light_energy.
## There is no faithful lumen/candela -> Godot `light_energy` conversion for
## these stylized authored values (Guildhall spans 0.01..2500, median 15), so
## this is a documented approximation: a single linear scale preserves the
## authored RATIO inside the band and only compresses at the extremes. The
## scale is anchored so the median authored intensity (15.0) becomes energy
## 1.0.
##
## The old two-branch mapping (raw < 20 -> raw * 0.95, else raw * 0.08,
## clamped to [1.0, 4.2]) pinned 468 of the 682 lights in
## `game/data/generated/levels/Guildhall/` (68.6%) to a constant: 142 at the
## 1.0 floor and 326 at the 4.2 ceiling. Another 159 lights authored 20-52.5
## escaped the clamp through the * 0.08 branch, so an "in band" count that
## includes them overstates how much of the authored ratio the old mapping
## kept. The 682 figure is that directory only; the loaded Guildhall map also
## merges `Buildings/Guildhall/`, for 982 runtime lights. Under the new
## mapping those 982 split into 778 in band, 70 at the ceiling and 134 at the
## floor (the 682 directory alone: 486 in band, 62 ceiling, 134 floor).
const LIGHT_INTENSITY_SCALE: float = 0.0666667 # 1/15: median authored intensity -> energy 1.0
const LIGHT_ENERGY_FLOOR: float = 0.01
const LIGHT_ENERGY_CEIL: float = 4.0
## Defensive guard only: authored AttenuationRadius values are 0.35-30 m, and
## the old 26 m clamp was clipping 24 legitimate 20-30 m lights. This ceiling
## exists so a corrupt authored radius cannot create an unbounded light.
const LIGHT_RANGE_CEIL: float = 200.0

## Level-component runtime (decals / rect lights / volumes / splines) ---------
## UE decals project along their local +X (DecalActor arrow axis); Godot
## Decal nodes project along local -Y, so every decal basis is post-rotated
## +90 deg about Z (maps -Y onto +X). UE's default decal box is 1 m per axis,
## so components with no authored DecalSize derive extents from their
## RelativeScale3D (already converted to metres by the extractor).
const MAX_DECALS_PER_MAP: int = 256
const DECAL_FADE_BEGIN: float = 45.0
const DECAL_FADE_END: float = 60.0
const UE_DEFAULT_DECAL_M: float = 1.0
## RectLight entries at or below this intensity are authored off (their glow
## is animated at runtime) and must not allocate lights.
const RECT_LIGHT_OFF_THRESHOLD: float = 0.01
## RectLight width/height arrive as raw UU centimetres (radius is metres).
const UU_CM_TO_M: float = 0.01
## Tokens too generic to prove a decal texture belongs to its material.
const DECAL_GENERIC_TOKENS: Array[String] = ["m", "mi", "t", "d", "da", "a", "inst", "decal", "decals"]

## Placed loot containers (chests / display cases / secret stashes): meshes are
## level geometry, so only the marker transform is kept for the openable wave.
const LOOT_CONTAINER_CLASSES: Array[String] = [
	"BP_ChestTrunk_MajorLoot_C",
	"BP_DisplayCaseA_MajorLoot_C",
	"BP_LootStashInteractable_Secret_ThinWall_C",
	"BP_Storefront_DisplayCaseB_MinorLoot_C",
	"BP_Storefront_DisplayCaseD_MinorLoot_C",
]

## Foliage/debris/clutter: aggressively culled, never casts shadows or collides.
const CLUTTER_TOKENS: Array[String] = [
	"sm_leaf", "sm_grass", "sm_newgrass", "sm_newspaper", "sm_pebble", "sm_debris",
	"foliage", "ivy", "vine", "moss", "cobweb", "sm_dust",
]
## Sublevels that only dress the horizon: no physics colliders, no occluders.
## PeripheryA is NOT decorative: it contains the packed city blocks (including
## the Guildhall safe-room buildings) and must collide. Only the skybox shell
## is horizon-only.
const DECORATIVE_SUBLEVEL_TOKENS: Array[String] = ["skyboxgeo"]
## F9 wall-flicker guard: structural masonry tokens whose instances never
## take a distance fade. Small Guildhall wall/building segments (aabb < 4 m)
## used to take the 95 m VISIBILITY_RANGE_FADE_SELF dither fade, whose
## screen-door pattern shimmers on coplanar masonry at the fade boundary.
## Clutter/foliage/loose props keep their fades (the Suite 11 culled-node
## budget lives there); e2e-cleared foliage paths (sm_leaf, sm_tree_*)
## match none of these tokens.
const STRUCTURAL_NO_FADE_TOKENS: Array[String] = [
	"wall", "building", "block", "pillar", "column",
]
## Occlusion occluders are opt-in: only obviously solid structural piece names
## (never see-through pieces like windows, doors, rails, frames or light fixtures).
const OCCLUDER_INCLUDE_TOKENS: Array[String] = [
	"wall", "floor", "ceiling", "roof", "building", "pillar", "column", "stair", "block",
]
const OCCLUDER_EXCLUDE_TOKENS: Array[String] = [
	"window", "door", "glass", "gate", "archway", "arch_", "frame", "rail", "beam",
	"hole", "gap", "curtain", "drape", "cloth", "banner", "flag", "foliage", "leaf",
	"sky", "cloud", "fog", "smoke", "water", "carpet", "rug", "paper", "poster",
	"scroll", "cable", "wire", "rope", "ladder", "light", "lamp", "vent", "pipe",
	"trim", "deco", "panel",
]
## Den west attic window wall: the single wall/window collider is split into
## two side boxes leaving DEN_WINDOW_GAP_M for the moonbeam opening, plus a
## low sill under the opening and a lintel above it. The 2 m marker gate
## (escape/marker trigger clearance) is kept unchanged.
const DEN_WINDOW_GAP_M: float = 0.95
const DEN_WINDOW_SILL_TOP_M: float = 0.9
const DEN_WINDOW_LINTEL_BOTTOM_M: float = 2.0


func _ready() -> void:
	texture_budget_max_dim = _resolve_texture_budget()
	_load_material_dbs()


## PG-1: effective per-texture long-edge cap. TAT2_TEX_CAP (pixels, 0 = off)
## lets the perf harness compare capped vs uncapped on one binary.
func _resolve_texture_budget() -> int:
	var env_cap: String = OS.get_environment("TAT2_TEX_CAP")
	if env_cap.is_valid_int():
		return maxi(0, int(env_cap))
	return TEX_BUDGET_MAX_DIM


## PG-1: downscale an image whose long edge exceeds the budget. Returns the
## same image untouched when it already fits, else resizes it in place. The
## mip contract of the source is kept (imported .ctex ships no mip chain).
func _cap_image(img: Image, res_path: String) -> Image:
	var cap: int = texture_budget_max_dim
	if cap <= 0 or img == null or img.is_empty():
		return img
	var w: int = img.get_width()
	var h: int = img.get_height()
	var longest: int = maxi(w, h)
	if longest <= cap:
		return img
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	var scale: float = float(cap) / float(longest)
	var nw: int = maxi(1, int(round(float(w) * scale)))
	var nh: int = maxi(1, int(round(float(h) * scale)))
	img.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
	# Resizing discards mip levels. PBR surfaces need them back or distant
	# geometry aliases/shimmer; tiny UI icons stay mip-free by design.
	if not img.is_compressed() and nw >= 64 and nh >= 64:
		img.generate_mipmaps()
	if not downscaled_textures.has(res_path):
		downscaled_textures.append(res_path)
	downscaled_count = downscaled_textures.size()
	return img


## PG-1: capped ImageTexture copy of a loaded texture, or the original when
## it already fits the budget (or cannot be read back).
func _cap_texture(tex: Texture2D, res_path: String) -> Texture2D:
	var src: Image = tex.get_image()
	if src == null or src.is_empty():
		return tex
	var img: Image = src.duplicate() as Image
	if img == null:
		return tex
	_cap_image(img, res_path)
	var out: ImageTexture = ImageTexture.create_from_image(img)
	if out == null:
		return tex
	# Keep the source resource path on the capped copy: QA and UI code identify
	# textures by path (e.g. the Mission Prep PBR check), and the capped copy is
	# now the texture for that path in this process.
	if res_path.begins_with("res://") and out.resource_path != res_path:
		out.take_over_path(res_path)
	return out


## PG-1 teardown: release cached textures/materials/meshes when the loader
## leaves the tree (scene reload / quit-to-desktop) so their RIDs are freed
## in scene order instead of at global exit (exit-time RID-leak /
## PagedAllocator noise on live Vulkan). All four caches rebuild on demand.
func _exit_tree() -> void:
	_tex_cache.clear()
	_std_mat_cache.clear()
	_mesh_res_cache.clear()
	_override_mesh_cache.clear()


func _load_material_dbs() -> void:
	if FileAccess.file_exists("res://data/generated/materials.json"):
		var f := FileAccess.open("res://data/generated/materials.json", FileAccess.READ)
		var p: Variant = JSON.parse_string(f.get_as_text())
		if p is Dictionary:
			_materials_db = p
			_materials_db_lower.clear()
			for k: Variant in _materials_db.keys():
				_materials_db_lower[str(k).to_lower()] = _materials_db[k]
	if FileAccess.file_exists("res://data/generated/mesh_materials.json"):
		var f2 := FileAccess.open("res://data/generated/mesh_materials.json", FileAccess.READ)
		var p2: Variant = JSON.parse_string(f2.get_as_text())
		if p2 is Dictionary:
			_mesh_mats_db = p2
			_mesh_mats_db_lower.clear()
			for k2: Variant in _mesh_mats_db.keys():
				_mesh_mats_db_lower[str(k2).to_lower()] = _mesh_mats_db[k2]


## TASK 4.2 helper: true when the mip chain must be skipped for an icon-size
## sprite. Landscape/PBR textures return false and keep their mips.
func _is_tiny_texture(w: int, h: int) -> bool:
	return mini(w, h) < TINY_TEX_MIN_SIZE


## TASK 4.2 fallback: ResourceLoader/.ctex path for the tiny-texture mip
## guard. Imported (.ctex) textures arrive with their import mip chain, so
## there is no generate_mipmaps() call to skip here — instead, after load(),
## a tiny ImageTexture whose image still carries mipmaps is re-created
## without them (clear_mipmaps + ImageTexture.create_from_image). A tiny
## texture with no strippable mip chain (already linear, or a
## CompressedTexture2D whose import chain cannot be rebuilt at runtime) is
## returned as-is and sampled linear. Both cases are recorded in the same
## skipped_tiny_textures/skipped_tiny_count accounting as the FileAccess
## path (no silent hide).
func _guard_tiny_resource_texture(tex: Texture2D, res_path: String) -> Texture2D:
	if tex == null:
		return null
	if res_path == "" or not _is_tiny_texture(tex.get_width(), tex.get_height()):
		return tex
	if tex is ImageTexture:
		var src: Image = (tex as ImageTexture).get_image()
		if src != null and not src.is_empty() and src.has_mipmaps():
			if not skipped_tiny_textures.has(res_path):
				skipped_tiny_textures.append(res_path)
			skipped_tiny_count = skipped_tiny_textures.size()
			push_warning("[level_loader] _load_tex stripped mip chain for tiny ResourceLoader texture ", res_path, " size=", tex.get_width(), "x", tex.get_height(), " skipped_tiny_count=", skipped_tiny_count)
			var clean: Image = src.duplicate() as Image
			if clean != null:
				clean.clear_mipmaps()
				var stripped: ImageTexture = ImageTexture.create_from_image(clean)
				if stripped != null:
					return stripped
			return tex
	if not skipped_tiny_textures.has(res_path):
		skipped_tiny_textures.append(res_path)
	skipped_tiny_count = skipped_tiny_textures.size()
	push_warning("[level_loader] _load_tex tiny ResourceLoader texture kept linear (no strippable mip chain) ", res_path, " size=", tex.get_width(), "x", tex.get_height(), " skipped_tiny_count=", skipped_tiny_count)
	return tex


func _load_tex(res_path: String) -> Texture2D:
	if res_path == "":
		return null
	if _tex_cache.has(res_path):
		return _tex_cache[res_path] as Texture2D
	if ResourceLoader.exists(res_path):
		var t: Variant = load(res_path)
		if t is Texture2D:
			var res_tex: Texture2D = t as Texture2D
			if _is_tiny_texture(res_tex.get_width(), res_tex.get_height()):
				var guarded: Texture2D = _guard_tiny_resource_texture(res_tex, res_path)
				_tex_cache[res_path] = guarded
				return guarded
			if texture_budget_max_dim > 0 and maxi(res_tex.get_width(), res_tex.get_height()) > texture_budget_max_dim:
				var capped_res: Texture2D = _cap_texture(res_tex, res_path)
				_tex_cache[res_path] = capped_res
				return capped_res
			_tex_cache[res_path] = res_tex
			return res_tex
	if FileAccess.file_exists(res_path):
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(res_path))
		if img != null and not img.is_empty():
			var tex_w: int = img.get_width()
			var tex_h: int = img.get_height()
			var tex_has_mips: bool = img.has_mipmaps()
			if _is_tiny_texture(tex_w, tex_h):
				if not skipped_tiny_textures.has(res_path):
					skipped_tiny_textures.append(res_path)
				skipped_tiny_count = skipped_tiny_textures.size()
				push_warning("[level_loader] _load_tex skipped mip chain for tiny texture ", res_path, " size=", tex_w, "x", tex_h, " has_mipmaps=", tex_has_mips, " skipped_tiny_count=", skipped_tiny_count)
				var itex_tiny: ImageTexture = ImageTexture.create_from_image(img)
				if itex_tiny != null:
					_tex_cache[res_path] = itex_tiny
					return itex_tiny
				return null
			# PG-1: cap before mip generation so the resized image gets a valid
			# chain (imports ship none; resized mips would be stale).
			img = _cap_image(img, res_path)
			if img == null:
				return null
			if not img.has_mipmaps():
				img.generate_mipmaps()
			var itex: ImageTexture = ImageTexture.create_from_image(img)
			if itex != null:
				_tex_cache[res_path] = itex
				return itex
	return null


## Normalizes a UE parameter dict for case/space/underscore-insensitive lookup.
func _ue_norm_map(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[str(k).to_lower().replace(" ", "").replace("_", "")] = d[k]
	return out


func _ue_lookup(normed: Dictionary, names: Array) -> Variant:
	for n in names:
		var key := str(n).to_lower().replace(" ", "").replace("_", "")
		if normed.has(key):
			return normed[key]
	return null


## Applies real UE scalar PBR params (Roughness/Metallic/Specular families from
## materials.json "params"). Runs before the art-direction overrides in
## get_material_for_ue() so those keep precedence; missing params keep current
## defaults (roughness 0.78, metallic/specular 0).
func _apply_ue_pbr_params(mat: StandardMaterial3D, info: Dictionary) -> void:
	var params: Dictionary = _ue_norm_map(info.get("params", {}))
	var rough: Variant = _ue_lookup(params, ["roughness", "flatroughness"])
	if rough == null:
		var rlo: Variant = _ue_lookup(params, ["roughnesslow", "roughnessmin"])
		var rhi: Variant = _ue_lookup(params, ["roughnesshigh", "roughnessmax"])
		if rlo != null and rhi != null:
			rough = (float(rlo) + float(rhi)) * 0.5
	if rough != null:
		mat.roughness = clampf(float(rough), 0.0, 1.0)
	var metal: Variant = _ue_lookup(params, ["metallic", "metalness", "flatmetallic"])
	if metal == null:
		var mlo: Variant = _ue_lookup(params, ["metallicmin"])
		var mhi: Variant = _ue_lookup(params, ["metallicmax"])
		if mlo != null and mhi != null:
			metal = (float(mlo) + float(mhi)) * 0.5
	if metal != null:
		mat.metallic = clampf(float(metal), 0.0, 1.0)
	var spec: Variant = _ue_lookup(params, ["specular", "spec"])
	if spec != null:
		mat.metallic_specular = clampf(float(spec), 0.0, 1.0)


## Applies real UE render flags from materials.json "render": TwoSided ->
## double-sided, translucent/AlphaComposite blend -> alpha transparency, masked
## blend -> alpha scissor. Glass art overrides below still take precedence.
func _apply_ue_render_flags(mat: StandardMaterial3D, info: Dictionary) -> void:
	var render: Dictionary = info.get("render", {})
	if render.get("two_sided", false) == true:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var blend: String = str(render.get("blend_mode", "")).to_lower()
	var shading: String = str(render.get("shading_model", ""))
	var texs_rf_v: Variant = info.get("texs", {})
	var texs_rf: Dictionary = texs_rf_v as Dictionary if texs_rf_v is Dictionary else {}
	var is_bark: bool = "bark" in str(texs_rf.get("albedo", "")).to_lower()
	var is_foliage_shading: bool = ("TwoSidedFoliage" in shading or ("Subsurface" in shading and not ("SubsurfaceProfile" in shading))) and not is_bark
	if blend.find("translucent") >= 0 or blend.find("alphacomposite") >= 0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	elif blend.find("masked") >= 0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = clampf(float(render.get("opacity_mask_clip", 0.5)), 0.0, 1.0)
	elif blend == "" and render.has("opacity_mask_clip") and is_foliage_shading:
		# Foliage instances (e.g. MI_BirchLeaves*) inherit masked blend from M_FoliageBase
		# while emitting opacity_mask_clip + foliage shading_model in materials.json.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = clampf(float(render.get("opacity_mask_clip", 0.3333)), 0.0, 1.0)
	if is_foliage_shading:
		# R3 APPROXIMATE backlight stand-in for UE MSM_TwoSidedFoliage / foliage MSM_Subsurface.
		mat.backlight_enabled = true
		var rf_vecs: Dictionary = _ue_norm_map(info.get("vectors", {}))
		var ssc: Variant = _ue_lookup(rf_vecs, ["subsurfacecolor", "sscolor"])
		if ssc is Array and (ssc as Array).size() >= 3:
			var sa: Array = ssc as Array
			mat.backlight = Color(float(sa[0]), float(sa[1]), float(sa[2])).clamp(Color(0.18, 0.14, 0.08), Color(0.75, 0.75, 0.75))
		else:
			mat.backlight = Color(0.35, 0.28, 0.16)


## Applies real UE emissive vectors/scalars from materials.json. Merges with an
## emissive texture bound above (the texture keeps its art-tuned energy while
## the UE colour fills in the emission tint); otherwise enables emission from
## the UE colour scaled by the emissive scalar. Skipped when the UE switches
## explicitly gate emissive off.
## True when materials.json carries an authored emissive colour (and a
## non-zero strength when one is present). Emissive-only materials such as
## MI_PowerLight_On have no albedo/tint by design; they are authored, not a
## tier-3 fallback.
func _has_authored_emissive(info: Dictionary) -> bool:
	var switches: Dictionary = _ue_norm_map(info.get("switches", {}))
	if _ue_lookup(switches, ["emissiveon?"]) == false:
		return false
	if _ue_lookup(switches, ["disableemissivecontribution"]) == true:
		return false
	var vectors: Dictionary = _ue_norm_map(info.get("vectors", {}))
	var ecol: Variant = _ue_lookup(vectors, ["emissivecolor", "emissive", "emissivetint", "emiscolor"])
	if not (ecol is Array) or (ecol as Array).size() < 3:
		return false
	var ea: Array = ecol as Array
	var peak: float = maxf(float(ea[0]), maxf(float(ea[1]), float(ea[2])))
	if peak <= 0.005:
		return false
	var params: Dictionary = _ue_norm_map(info.get("params", {}))
	var estr: Variant = _ue_lookup(params, ["emissivestrength", "emissiveintensity", "emissivemultiplier", "emissivemultiply", "emismultiply", "emissivemult", "emissivepower", "emissivebrightness", "emissivebrillance"])
	return estr == null or peak * float(estr) > 0.005


func _apply_ue_emissive(mat: StandardMaterial3D, info: Dictionary) -> void:
	var switches: Dictionary = _ue_norm_map(info.get("switches", {}))
	if _ue_lookup(switches, ["emissiveon?"]) == false:
		return
	if _ue_lookup(switches, ["disableemissivecontribution"]) == true:
		return
	var vectors: Dictionary = _ue_norm_map(info.get("vectors", {}))
	var ecol: Variant = _ue_lookup(vectors, ["emissivecolor", "emissive", "emissivetint", "emiscolor"])
	var params: Dictionary = _ue_norm_map(info.get("params", {}))
	var estr: Variant = _ue_lookup(params, ["emissivestrength", "emissiveintensity", "emissivemultiplier", "emissivemultiply", "emismultiply", "emissivemult", "emissivepower", "emissivebrightness", "emissivebrillance"])
	if ecol == null and estr == null:
		return
	var col := Color(1.0, 1.0, 1.0)
	if ecol is Array and (ecol as Array).size() >= 3:
		var ea: Array = ecol
		col = Color(float(ea[0]), float(ea[1]), float(ea[2]))
		if maxf(col.r, maxf(col.g, col.b)) <= 0.02 and estr == null:
			return
	if mat.emission_enabled:
		mat.emission = col
		if estr != null:
			mat.emission_energy_multiplier = clampf(float(mat.emission_energy_multiplier) * float(estr), 0.0, 16.0)
	else:
		mat.emission_enabled = true
		mat.emission = col
		if estr != null:
			mat.emission_energy_multiplier = clampf(float(estr), 0.0, 8.0)
		else:
			mat.emission_energy_multiplier = 1.0


func _build_glass_material(info: Dictionary, alb: Texture2D, op: Texture2D) -> ShaderMaterial:
	var smat: ShaderMaterial = ShaderMaterial.new()
	smat.shader = GLASS_SHADER
	var texs: Dictionary = info.get("texs", {})
	var params: Dictionary = _ue_norm_map(info.get("params", {}))
	var vectors_raw: Dictionary = info.get("vectors", {})
	var vectors_norm: Dictionary = _ue_norm_map(vectors_raw)
	var switches: Dictionary = _ue_norm_map(info.get("switches", {}))
	smat.set_shader_parameter("use_albedo_tex", alb != null)
	if alb != null:
		smat.set_shader_parameter("albedo_tex", alb)
	smat.set_shader_parameter("use_opacity_tex", op != null)
	if op != null:
		smat.set_shader_parameter("opacity_tex", op)
	var norm: Texture2D = _load_tex(str(texs.get("normal", "")))
	smat.set_shader_parameter("use_normal_tex", norm != null)
	if norm != null:
		smat.set_shader_parameter("normal_tex", norm)
	var orm: Texture2D = _load_tex(str(texs.get("orm", "")))
	smat.set_shader_parameter("use_orm_tex", orm != null)
	if orm != null:
		smat.set_shader_parameter("orm_tex", orm)
	var vc: Color = Color(1.0, 1.0, 1.0, 1.0)
	var tint: Variant = info.get("tint")
	if tint is Array and (tint as Array).size() >= 3:
		var ta: Array = tint as Array
		vc = Color(float(ta[0]), float(ta[1]), float(ta[2]), 1.0)
	if vectors_raw.has("Overlay"):
		var ov: Variant = vectors_raw["Overlay"]
		if ov is Array and (ov as Array).size() >= 3:
			var ova: Array = ov as Array
			vc.r *= float(ova[0])
			vc.g *= float(ova[1])
			vc.b *= float(ova[2])
	if vectors_raw.has("Multiply"):
		var mu: Variant = vectors_raw["Multiply"]
		if mu is Array and (mu as Array).size() >= 3:
			var mua: Array = mu as Array
			vc.r *= float(mua[0])
			vc.g *= float(mua[1])
			vc.b *= float(mua[2])
	smat.set_shader_parameter("albedo_tint", vc)
	var trans_c: Variant = _ue_lookup(vectors_norm, ["translucentcolor"])
	if trans_c is Array and (trans_c as Array).size() >= 3:
		var tca: Array = trans_c as Array
		smat.set_shader_parameter("translucent_color", Vector3(float(tca[0]), float(tca[1]), float(tca[2])))
	var op_val: Variant = _ue_lookup(params, ["opacity", "glassopacity", "opacitymultiply"])
	var op_scale: float = clampf(float(op_val), 0.0, 8.0) if op_val != null else 1.0
	smat.set_shader_parameter("opacity_scale", op_scale)
	var rough_val: Variant = _ue_lookup(params, ["roughness", "glassroughness", "flatroughness"])
	if rough_val != null:
		smat.set_shader_parameter("roughness_val", clampf(float(rough_val), 0.04, 4.0 if orm != null else 1.0))
	else:
		smat.set_shader_parameter("roughness_val", 1.0 if orm != null else 0.25)
	var metal_val: Variant = _ue_lookup(params, ["metallic", "metalness", "flatmetallic"])
	if metal_val != null:
		smat.set_shader_parameter("metallic_val", clampf(float(metal_val), 0.0, 1.0))
	else:
		smat.set_shader_parameter("metallic_val", 1.0 if orm != null else 0.0)
	var spec_val: Variant = _ue_lookup(params, ["specular", "spec"])
	if spec_val != null:
		smat.set_shader_parameter("specular_val", clampf(float(spec_val), 0.0, 1.0))
	var tile_val: Variant = _ue_lookup(params, ["texturesize", "uvtiling", "uvtilinga"])
	if tile_val != null and float(tile_val) > 0.01:
		smat.set_shader_parameter("uv_scale", float(tile_val))
	var em_allowed: bool = _ue_lookup(switches, ["emissiveon?"]) != false and _ue_lookup(switches, ["disableemissivecontribution"]) != true
	if em_allowed:
		var ecol: Variant = _ue_lookup(vectors_norm, ["emissivecolor", "emissive", "emissivetint", "emiscolor"])
		var estr: Variant = _ue_lookup(params, ["emissivestrength", "emissiveintensity", "emissivemultiplier", "emissivemultiply", "emismultiply", "emissivemult", "emissivepower", "emissivebrightness", "emissivebrillance", "emissive"])
		if ecol is Array and (ecol as Array).size() >= 3 and estr != null:
			var ea: Array = ecol as Array
			var e_col: Color = Color(float(ea[0]), float(ea[1]), float(ea[2]))
			var e_str: float = clampf(float(estr), 0.0, 8.0)
			if maxf(e_col.r, maxf(e_col.g, e_col.b)) * e_str > 0.005:
				smat.set_shader_parameter("emission_color", Vector3(e_col.r, e_col.g, e_col.b))
				smat.set_shader_parameter("emission_energy", e_str)
	return smat


func get_material_for_ue(ue_mat_path: String) -> Material:
	if _std_mat_cache.has(ue_mat_path):
		return _std_mat_cache[ue_mat_path] as Material
	var low_mat: String = ue_mat_path.to_lower()
	var info: Dictionary = _materials_db.get(ue_mat_path, _materials_db_lower.get(low_mat, {}))
	var render_early: Dictionary = info.get("render", {})
	var texs_early: Dictionary = info.get("texs", {})
	var shading_early: String = str(render_early.get("shading_model", ""))
	if low_mat.ends_with("blackunlitmaterial") or (shading_early.ends_with("MSM_Unlit") and texs_early.is_empty()):
		var black := StandardMaterial3D.new()
		black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		black.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		black.cull_mode = BaseMaterial3D.CULL_DISABLED
		_std_mat_cache[ue_mat_path] = black
		return black
	var blend_early: String = str(render_early.get("blend_mode", "")).to_lower()
	var is_translucent_early: bool = blend_early.find("translucent") >= 0 or blend_early.find("alphacomposite") >= 0
	if is_translucent_early and ("glass" in low_mat or "window" in low_mat):
		var glass_alb_path: String = str(texs_early.get("albedo", ""))
		var glass_alb: Texture2D = null if (glass_alb_path.to_lower().find("mapbuilding") >= 0 and low_mat.find("mapbuilding") < 0) else _load_tex(glass_alb_path)
		var glass_op: Texture2D = _load_tex(str(texs_early.get("opacity", "")))
		if glass_alb != null or glass_op != null:
			var gmat: ShaderMaterial = _build_glass_material(info, glass_alb, glass_op)
			_std_mat_cache[ue_mat_path] = gmat
			return gmat
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.78
	_apply_ue_pbr_params(mat, info)
	_apply_ue_render_flags(mat, info)
	var texs: Dictionary = info.get("texs", {})
	var alb: Texture2D = _load_tex(str(texs.get("albedo", "")))
	# Hard rule: the UI map textures (T_MapBuilding_*) must never dress non-map 3D geometry,
	# while M_MapBuilding_* token materials themselves bind their authored textures.
	if str(texs.get("albedo", "")).to_lower().find("mapbuilding") >= 0 and low_mat.find("mapbuilding") < 0:
		alb = null
	if "oldmanorpanels" in low_mat:
		var wood_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Wood/Manor/T_ManorWood_D.png")
		if wood_alb != null:
			alb = wood_alb
		mat.albedo_color = Color(0.65, 0.55, 0.48)
	if alb != null:
		mat.albedo_texture = alb
	var norm := _load_tex(str(texs.get("normal", "")))
	if norm != null:
		mat.normal_enabled = true
		mat.normal_texture = norm
	var orm := _load_tex(str(texs.get("orm", "")))
	if orm != null:
		mat.ao_enabled = true
		mat.ao_texture = orm
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.roughness_texture = orm
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic_texture = orm
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	var tint: Variant = info.get("tint")
	if tint is Array and tint.size() >= 3:
		var tint_col: Color = Color(float(tint[0]), float(tint[1]), float(tint[2]), 1.0)
		var tint_hdr: bool = maxf(tint_col.r, maxf(tint_col.g, tint_col.b)) > 1.0
		var tint_vectors: Dictionary = info.get("vectors", {})
		var plain_hdr_tint: bool = tint_hdr and alb == null and texs.is_empty() \
			and render_early.get("two_sided", false) != true \
			and not (tint_vectors.has("Overlay") or tint_vectors.has("Multiply") or tint_vectors.has("Desaturation"))
		if plain_hdr_tint:
			# Authored UE HDR "Color" on an untextured emissive material
			# (MI_Neon): StandardMaterial3D colour parameters are sRGB-
			# converted and diffuse albedo clamps at 1.0, which collapsed the
			# authored orange-gold (50, 4.109, 0.521) into a saturated red
			# blob. Carry the authored linear values through an unshaded HDR
			# pass instead. Scale the brightest channel to 4.0 so the authored
			# hue survives ACES and the tube core stays orange-gold with a
			# modest halo (2.5 measured dimmer than the UE reference); scaling
			# preserves the authored ratio.
			var hdr_peak: float = maxf(tint_col.r, maxf(tint_col.g, tint_col.b))
			var hdr_mat: ShaderMaterial = ShaderMaterial.new()
			hdr_mat.shader = HDR_EMISSIVE_SHADER
			hdr_mat.set_shader_parameter("hdr_color", Vector3(tint_col.r, tint_col.g, tint_col.b))
			hdr_mat.set_shader_parameter("hdr_scale", clampf(4.0 / hdr_peak, 0.02, 1.0))
			# R3 APPROXIMATE ACES core boost + Fresnel/flicker from authored MI_Neon* params
			# (keeps hdr_color and hdr_scale unchanged for Suite 37).
			var neon_params: Dictionary = _ue_norm_map(info.get("params", {}))
			hdr_mat.set_shader_parameter("hdr_boost", clampf(hdr_peak / 10.0, 2.4, 5.0))
			var exp_in: Variant = _ue_lookup(neon_params, ["exponentin"])
			var base_ref_v: Variant = _ue_lookup(neon_params, ["basereflect"])
			if exp_in != null or base_ref_v != null:
				var base_ref: float = float(base_ref_v) if base_ref_v != null else 0.0
				hdr_mat.set_shader_parameter("fresnel_power", 0.85 if base_ref < 0.0 else 0.65)
				hdr_mat.set_shader_parameter("fresnel_min", 0.28 if base_ref < 0.0 else 0.38)
			var fspd: Variant = _ue_lookup(neon_params, ["flickerspeeda"])
			var fint: Variant = _ue_lookup(neon_params, ["flickeringintensitya"])
			if fspd != null and float(fspd) > 0.0 and (fint == null or float(fint) > 0.0):
				hdr_mat.set_shader_parameter("flicker_speed", clampf(float(fspd) * 8.0, 0.4, 4.0))
				hdr_mat.set_shader_parameter("flicker_amp", 0.22)
			_std_mat_cache[ue_mat_path] = hdr_mat
			return hdr_mat
		mat.albedo_color = tint_col
	var vectors_raw: Dictionary = info.get("vectors", {})
	if vectors_raw.has("Overlay") or vectors_raw.has("Multiply") or vectors_raw.has("Desaturation"):
		var vc: Color = mat.albedo_color
		if vectors_raw.has("Overlay"):
			var ov: Variant = vectors_raw["Overlay"]
			if ov is Array and (ov as Array).size() >= 3:
				var ova: Array = ov
				vc.r *= float(ova[0])
				vc.g *= float(ova[1])
				vc.b *= float(ova[2])
		if vectors_raw.has("Multiply"):
			var mu: Variant = vectors_raw["Multiply"]
			if mu is Array and (mu as Array).size() >= 3:
				var mua: Array = mu
				vc.r *= float(mua[0])
				vc.g *= float(mua[1])
				vc.b *= float(mua[2])
		if vectors_raw.has("Desaturation"):
			var ds: Variant = vectors_raw["Desaturation"]
			if ds is Array and (ds as Array).size() >= 3:
				var dsa: Array = ds
				var lum: float = vc.r * 0.299 + vc.g * 0.587 + vc.b * 0.114
				var amt: float = float(dsa[3]) if dsa.size() >= 4 else 1.0
				amt = clampf(amt, 0.0, 1.0)
				vc.r = lerpf(vc.r, lum, amt)
				vc.g = lerpf(vc.g, lum, amt)
				vc.b = lerpf(vc.b, lum, amt)
		mat.albedo_color = vc
	var em := _load_tex(str(texs.get("emissive", "")))
	if em != null:
		mat.emission_enabled = true
		mat.emission_texture = em
		mat.emission_energy_multiplier = 2.2
	_apply_ue_emissive(mat, info)
	if alb == null and tint == null:
		var low: String = ue_mat_path.to_lower()
		if "brick" in low:
			var brick_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Brick/T_OldBricksA_D.png")
			if brick_alb != null:
				mat.albedo_texture = brick_alb
			mat.albedo_color = Color(0.45, 0.36, 0.32)
			mat.roughness = 0.85
		elif "stone" in low or "cobble" in low:
			var stone_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Legacy/T_CobbleStoneA_D.png")
			if stone_alb != null:
				mat.albedo_texture = stone_alb
			mat.albedo_color = Color(0.42, 0.41, 0.40)
			mat.roughness = 0.88
		elif "dirt" in low or "ground" in low or "mud" in low:
			var dirt_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Nature/Dirt/T_GroundDirtA_D.png")
			if dirt_alb != null:
				mat.albedo_texture = dirt_alb
			mat.albedo_color = Color(0.38, 0.30, 0.22)
			mat.roughness = 0.92
		elif "wood" in low or "plank" in low or "floor" in low or "desk" in low or "trim" in low or "door" in low:
			var manor_wood_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Wood/Manor/T_ManorWood_D.png")
			if manor_wood_alb != null:
				mat.albedo_texture = manor_wood_alb
			else:
				var floor_wood_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Wood/Floors/T_WoodFloorA_D.png")
				if floor_wood_alb != null:
					mat.albedo_texture = floor_wood_alb
			mat.albedo_color = Color(0.52, 0.40, 0.30)
			mat.roughness = 0.72
		elif "brass" in low or "gold" in low:
			mat.albedo_color = Color(0.72, 0.56, 0.24)
			mat.metallic = 0.85
			mat.roughness = 0.3
		elif "metal" in low or "iron" in low or "steel" in low:
			mat.albedo_color = Color(0.24, 0.26, 0.29)
			mat.metallic = 0.8
			mat.roughness = 0.42
		elif "wall" in low:
			mat.albedo_color = Color(0.26, 0.25, 0.27)
		else:
			mat.albedo_color = Color(0.32, 0.30, 0.28)
	# Emissive-only materials (MI_PowerLight_On, M_DefaultEmissive_*) carry
	# their authored appearance in the emissive vector, not albedo/tint.
	# Give them a near-black base so the authored emission reads, and never
	# count them as a guessed fallback.
	var authored_emissive: bool = _has_authored_emissive(info)
	if alb == null and tint == null and authored_emissive:
		mat.albedo_color = Color(0.02, 0.02, 0.02, 1.0)
	if alb == null and tint == null and not authored_emissive:
		# L2: the substring-guess chain above bound a plausible-but-wrong
		# texture (tier 2) or a flat color (tier 3) instead of authored data.
		# The tier rides on the material as metadata and the UE path is
		# counted + warned, so coverage holes read as wrong-but-rendered
		# walls no longer pass silently.
		var fallback_tier: int = 2 if mat.albedo_texture != null else 3
		mat.set_meta("tat_fallback_tier", fallback_tier)
		_note_fallback_material(ue_mat_path, fallback_tier)
	var low_wall: String = ue_mat_path.to_lower()
	if "wallpaper" in low_wall or "thievesden" in low_wall:
		if mat.albedo_texture == null:
			mat.albedo_color = mat.albedo_color * Color(0.42, 0.35, 0.35, 1.0)
		if mat.roughness < 0.72:
			mat.roughness = 0.72
	# Thieves' Den neon fix: T_Wallpaper_Floral and T_WallpaperC_D are channel-packed RGB masks.
	var albedo_path_lower: String = str(texs.get("albedo", "")).to_lower()
	if "wallpaper" in low_mat or "t_wallpaper_floral" in albedo_path_lower or "t_wallpaperc_d" in albedo_path_lower:
		var manor_wall_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Wallpaper/ManorWallpaper/T_ManorWallpaper_C_Diffuse.png")
		if manor_wall_alb != null:
			mat.albedo_texture = manor_wall_alb
			alb = manor_wall_alb
		var manor_wall_norm: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Wallpaper/ManorWallpaper/T_ManorWallpaper_Normal.png")
		if manor_wall_norm != null:
			mat.normal_enabled = true
			mat.normal_texture = manor_wall_norm
		mat.albedo_color = Color(0.28, 0.24, 0.21, 1.0)
		mat.roughness = 0.82
	_std_mat_cache[ue_mat_path] = mat
	return mat


func _ue_mesh_to_res(ue_path: String) -> String:
	var clean := ue_path.split(".")[0]
	if clean.begins_with("/Game/"):
		clean = clean.substr(6)
	var candidate := "res://assets/ue/Content/" + clean + ".glb"
	if ResourceLoader.exists(candidate):
		return candidate
	var gltf_candidate := "res://assets/ue/Content/" + clean + ".gltf"
	if ResourceLoader.exists(gltf_candidate):
		return gltf_candidate
	# Engine primitives ship outside TAT/Content (round-2 T1 repair): level JSON
	# cites them short ("/Engine/BasicShapes/Cube") while the export root keeps
	# the full Pak path (Engine/Content/BasicShapes/...glb), reachable through
	# the Raw mirror (game/assets/ue/Raw -> extracted/assets).
	if clean.begins_with("/Engine/"):
		var raw_base := "res://assets/ue/Raw/Engine/Content/" + clean.substr("/Engine/".length())
		if ResourceLoader.exists(raw_base + ".glb"):
			return raw_base + ".glb"
		if ResourceLoader.exists(raw_base + ".gltf"):
			return raw_base + ".gltf"
	return ""


func _get_mesh_and_shape(ue_path: String) -> Dictionary:
	if _mesh_res_cache.has(ue_path):
		return _mesh_res_cache[ue_path]
	var out: Dictionary = {"mesh": null, "shape": null}
	var res_path: String = _ue_mesh_to_res(ue_path)
	if res_path == "":
		_mesh_res_cache[ue_path] = out
		return out
	var packed: Variant = load(res_path)
	if not (packed is PackedScene):
		# L1 corrupt-import path: ResourceLoader.exists() passed but the
		# load failed (corrupt import, non-scene resource). Named + counted
		# apart from genuinely-missing meshes; still cached below since a
		# retry cannot heal a bad import at runtime.
		_note_corrupt_mesh(ue_path, res_path)
	if packed is PackedScene:
		var inst: Node = packed.instantiate()
		var mi := _find_first_mesh(inst)
		if mi != null and mi.mesh != null:
			var m := mi.mesh.duplicate() as Mesh
			var low_u := ue_path.to_lower()
			if "lightshaft" in low_u or "godray" in low_u:
				var beam_mat := StandardMaterial3D.new()
				beam_mat.albedo_color = Color(0.55, 0.78, 0.95, 0.08)
				beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				for s in range(m.get_surface_count()):
					m.surface_set_material(s, beam_mat)
				out["mesh"] = m
				out["shape"] = null
			else:
				# Bind GLB-ordered material slots by surface name, then index.
				# mesh_materials.json is emitted in GLB primitive order and Godot
				# names imported surfaces after the GLB material, so prefer a
				# case-insensitive name-substring match; fall back to primitive
				# index when the surface name is generic or matches nothing.
				var mesh_key: String = ue_path.split(".")[0]
				var mat_slots: Array = _mesh_mats_db.get(mesh_key, _mesh_mats_db_lower.get(mesh_key.to_lower(), []))
				_bind_glb_materials(m, mat_slots)
				out["mesh"] = m
				var is_nonblocking: bool = ("rug" in low_u or "carpet" in low_u or "placemat" in low_u or "paper" in low_u or "poster" in low_u or "scroll" in low_u or "curtain" in low_u or "cloth" in low_u or "drape" in low_u or "sheet" in low_u or "cable" in low_u or "wire" in low_u or "rope" in low_u or "ivy" in low_u or "vine" in low_u or "foliage" in low_u)
				# Fast BoxShape3D for props; trimesh for walkable surfaces and large structural geometry.
				# Stair runs must present tread faces instead of a full-AABB wall (an
				# SM_StairsCity4x2m box is a flat-topped 2 m wall; an open-riser
				# SM_Stairs_Industrial run boxes into a 0.69 m wall at the low end).
				# Lipped sidewalk slabs must collide at the authored walk band
				# instead of floating a flat box top at trim height
				# (SM_SidewalkCityStone_6m: walk band ~0, box top +0.2).
				# Cheek walls / rails / posts / banisters / upstairs masses keep
				# boxes; tiny and non-blocking props keep the old fast path.
				var is_stair_run: bool = "stair" in low_u and not ("rail" in low_u or "boundary" in low_u or "post" in low_u or "banister" in low_u or "balustrade" in low_u or "upstairs" in low_u)
				var is_walk_surface: bool = "sidewalk" in low_u
				var aabb := m.get_aabb()
				var sz := aabb.size
				if not is_nonblocking and sz.length() > 0.45:
					if sz.length() < 12.0 and not is_stair_run and not is_walk_surface:
						var bx := BoxShape3D.new()
						bx.size = Vector3(maxf(sz.x, 0.1), maxf(sz.y, 0.1), maxf(sz.z, 0.1))
						out["shape"] = bx
						out["shape_offset"] = aabb.get_center()
					else:
						out["shape"] = m.create_trimesh_shape()
						out["shape_offset"] = Vector3.ZERO
		inst.free()
	_mesh_res_cache[ue_path] = out
	return out


## L1 accounting: name the UE path + resolved file, count, cap the stored
## list at 128 (count stays exact). push_error, not warning — a corrupt
## import drops geometry AND collision for that mesh.
func _note_corrupt_mesh(ue_path: String, res_path: String) -> void:
	corrupt_mesh_count += 1
	if corrupt_meshes.size() < 128 and not corrupt_meshes.has(ue_path):
		corrupt_meshes.append(ue_path)
	push_error("[level_loader] corrupt mesh import for UE path '", ue_path, "' (resolved ", res_path, "); cached as missing (corrupt=", corrupt_mesh_count, ")")


## L2 accounting: substring-guess fallbacks bind plausible-but-wrong
## textures (tier 2) or flat colors (tier 3). Named + counted per new path.
func _note_fallback_material(ue_mat_path: String, tier: int) -> void:
	fallback_material_count += 1
	if fallback_materials.size() < 128 and not fallback_materials.has(ue_mat_path):
		fallback_materials.append(ue_mat_path)
	push_warning("[level_loader] material fallback tier ", tier, " for '", ue_mat_path, "' (guessed, not authored; fallbacks=", fallback_material_count, ")")


## Binds GLB-ordered material slots to the imported ArrayMesh surfaces.
## mesh_materials.json is emitted in GLB primitive order, and Godot names
## imported GLB surfaces after the GLB material, so prefer a case-insensitive
## name-substring match (GLB material object name in the surface name or vice
## versa). Fall back to primitive index when the surface name is generic
## (e.g. "Surface 0") or matches nothing, preserving the old index behavior.
func _bind_glb_materials(m: Mesh, mat_slots: Array) -> void:
	if m == null or mat_slots.is_empty():
		return
	for s in range(m.get_surface_count()):
		var surf_name := str(m.surface_get_name(s)).to_lower()
		var matched := -1
		if surf_name != "" and surf_name.length() >= 3:
			for i in range(mat_slots.size()):
				var mp := str(mat_slots[i])
				if mp == "":
					continue
				var short := mp.get_file().split(".")[0].to_lower()
				if short == "" or short.length() < 3:
					continue
				if surf_name.find(short) >= 0 or short.find(surf_name) >= 0:
					matched = i
					break
		if matched == -1 and s < mat_slots.size():
			matched = s
		if matched >= 0 and matched < mat_slots.size():
			var mp2 := str(mat_slots[matched])
			if mp2 != "":
				m.surface_set_material(s, get_material_for_ue(mp2))


func _extract_override_materials(entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var raw_arr: Variant = entry.get("override_materials", null)
	if raw_arr is Array:
		for slot_var: Variant in (raw_arr as Array):
			out.append("" if slot_var == null else str(slot_var))
	elif entry.has("override_material"):
		var single: String = str(entry.get("override_material", ""))
		if single != "":
			out.append(single)
	while not out.is_empty() and out[out.size() - 1] == "":
		out.pop_back()
	var has_nonempty: bool = false
	for s: String in out:
		if s != "":
			has_nonempty = true
			break
	if not has_nonempty:
		return []
	return out


func _get_overridden_mesh(ue_path: String, base_mesh: Mesh, ov_arr: Array[String], ov_key: String) -> Mesh:
	if base_mesh == null or ov_arr.is_empty():
		return base_mesh
	var cache_key: String = ue_path + "||" + ov_key
	if _override_mesh_cache.has(cache_key):
		return _override_mesh_cache[cache_key] as Mesh
	var ov_mesh: Mesh = base_mesh.duplicate(false) as Mesh
	if ov_mesh == null:
		return base_mesh
	var surf_count: int = ov_mesh.get_surface_count()
	var limit: int = mini(ov_arr.size(), surf_count)
	for s: int in range(limit):
		var slot_mat_path: String = ov_arr[s]
		if slot_mat_path == "":
			continue
		var mat: Material = get_material_for_ue(slot_mat_path)
		if mat != null:
			ov_mesh.surface_set_material(s, mat)
	_override_mesh_cache[cache_key] = ov_mesh
	return ov_mesh


func _get_emissive_cpd_material() -> ShaderMaterial:
	if _emissive_cpd_mat == null:
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = EMISSIVE_CPD_SHADER
		_emissive_cpd_mat = mat
	return _emissive_cpd_mat


func _is_emissive_cpd_override(ov_arr: Array[String]) -> bool:
	for ov_path: String in ov_arr:
		if ov_path == "":
			continue
		var stem: String = ov_path.get_file().split(".")[0].to_lower()
		if stem == "m_emissivebase" or stem == "mi_emissiveshape" or stem == "mi_emissiveshapeexterior" or stem == "mi_moonshapeemissive":
			return true
	return false


func _find_first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_first_mesh(c)
		if r != null:
			return r
	return null


func _has_token(haystack_low: String, tokens: Array[String]) -> bool:
	for token: String in tokens:
		if haystack_low.find(token) >= 0:
			return true
	return false


## Skybox/periphery sublevels are horizon dressing: never spawn physics or occluders.
func _is_decorative_sublevel(json_path: String) -> bool:
	return _has_token(json_path.to_lower(), DECORATIVE_SUBLEVEL_TOKENS)


func _new_accumulator() -> Dictionary:
	return {
		"batches": {},
		"batches_nocol": {},
		"batches_far": {},
		"lights": [] as Array,
		"landscapes": [] as Array,
		"decals": [] as Array,
		"rect_lights": [] as Array,
		"volumes": [] as Array,
		"sky_lights": [] as Array,
		"fog_volumes": [] as Array,
		"post_process": [] as Array,
		"niagara": [] as Array,
		"splines": [] as Array,
		"seen_lights": {},
		"result": {
			"player_spawns": [] as Array[Vector3],
		"player_spawn_transforms": [] as Array,
			"guard_spawns": [] as Array[Vector3],
			# Authored-tag index for SceneElement overrides (#11). Kept parallel
			# to the legacy Vector3 arrays so no consumer changes shape.
			"scene_element_spawns": [] as Array,
			"smart_objects": [] as Array,
			"loot_spawns": [] as Array[Vector3],
			"minor_loot_spawns": [] as Array,
			"major_loot_spawns": [] as Array,
			"escape_points": [] as Array[Vector3],
			"door_spawns": [] as Array[Vector3],
			"door_spawn_records": [] as Array,
			"loot_containers": [] as Array,
			"swinging_doors": [] as Array,
			"swinging_door_count": 0,
			"throwable_spawns": [] as Array[Vector3],
			"ammo_spawns": [] as Array[Vector3],
			"health_spawns": [] as Array[Vector3],
			"civilian_spawns": [] as Array[Vector3],
			"candelabra_positions": [] as Array[Vector3],
			"wardrobe_positions": [] as Array[Vector3],
			"desk_positions": [] as Array[Vector3],
			"ledger_positions": [] as Array[Vector3],
			"window_positions": [] as Array[Vector3],
			"mesh_instances": 0,
			"light_count": 0,
			"chunk_count": 0,
			"collision_bodies": 0,
			"collision_shapes": 0,
			"occluder_count": 0,
			"decal_count": 0,
			"decal_skipped": 0,
			"decal_unresolved_material": 0,
			"rect_light_count": 0,
			"rect_light_skipped": 0,
			"blocking_volume_count": 0,
			"volume_skipped": 0,
			"niagara_placements": 0,
			"spline_count": 0,
			"moonshape_hidden": 0,
			"sky_light": {},
			"fog_volume": {},
			"post_process": {},
		},
	}


## FTUE is a whole-city tutorial map. Give it the larger budget explicitly so
## the overflow is not silent, and leave every other map on the default.
## Deterministic SceneVariant selection (task B4).
## `scene_variants.json` holds the parsed TATSceneVariantConfig records. The
## runtime picks one record per state group (e.g. *_Open / *_Closed / *_Quest)
## from the run seed, so the same seed always produces the same world. Applying
## the per-record spawner overrides to tagged actors is tracked separately
## (the parsed data names SceneElement tags while actors carry SpawnGroup tags).
static var _scene_variants: Array = []
static var _scene_variants_loaded: bool = false


static func _sv_fnv1a(text: String) -> int:
	var h: int = 0x811C9DC5
	for i: int in text.length():
		h = (h ^ text.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 0x01000193) & 0xFFFFFFFF
	return h


static func _scene_override_kind(tag: String) -> String:
	if tag.contains("Locks.Doors"):
		return "door"
	if tag.contains("Locks.Windows"):
		return "window"
	if tag.contains(".Lights"):
		return "light"
	if tag.contains(".Guards"):
		return "guard"
	if tag.contains(".MajorLoot") or tag.contains(".NoMajorLoot"):
		return "major_loot"
	if tag.contains(".MinorLoot"):
		return "minor_loot"
	if tag.contains(".Quest"):
		return "quest"
	if tag.contains(".Civilian"):
		return "civilian"
	return ""


static func _sv_pos_key(v: Variant) -> String:
	if v is Vector3:
		var p: Vector3 = v as Vector3
		return "%.3f|%.3f|%.3f" % [p.x, p.y, p.z]
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v as Array
		return "%.3f|%.3f|%.3f" % [float(a[0]), float(a[1]), float(a[2])]
	return ""


static func _sv_source_map(source: String) -> String:
	var base: String = source.split("::")[0]
	if base.ends_with(".json") or base.ends_with(".tatlevel"):
		base = base.get_basename()
	return base


static func _sv_override_applies(typ: String, chance: float, seed_value: int, actor_name: String, tag: String) -> bool:
	var low: String = typ.to_lower()
	if low.ends_with("always"):
		return true
	if low.ends_with("never"):
		return false
	if low.ends_with("overridechance"):
		var roll: int = _sv_fnv1a("%d|%s|%s" % [seed_value, actor_name, tag]) % 10000
		return roll < int(clampf(chance, 0.0, 100.0) * 100.0)
	return false


static func load_scene_variants() -> Array:
	if not _scene_variants_loaded:
		_scene_variants_loaded = true
		var txt: String = FileAccess.get_file_as_string("res://data/generated/scene_variants.json")
		var doc: Variant = JSON.parse_string(txt)
		if doc is Dictionary:
			_scene_variants = (doc as Dictionary).get("variants", []) as Array
	return _scene_variants


static func select_scene_variants(map_id: String, seed_value: int, requested: Array[String] = []) -> Array[Dictionary]:
	var map_key: String = map_id.strip_edges().to_lower().replace("_", "").replace("-", "")
	var groups: Dictionary = {}
	for v: Variant in load_scene_variants():
		if not (v is Dictionary):
			continue
		var rec: Dictionary = v as Dictionary
		var vid: String = str(rec.get("id", ""))
		if vid == "":
			continue
		if not requested.is_empty() and not requested.has(vid):
			continue
		if requested.is_empty():
			var vmap: String = str(rec.get("map_id", "")).to_lower().replace("_", "").replace("-", "")
			if map_key != "" and vmap.find(map_key) < 0 and map_key.find(vmap) < 0:
				continue
		var group: String = vid
		for suffix: String in ["_open", "_closed", "_quest", "_damaged", "_locked", "_on", "_off"]:
			if group.to_lower().ends_with(suffix):
				group = group.substr(0, group.length() - suffix.length())
				break
		if not groups.has(group):
			groups[group] = []
		(groups[group] as Array).append(rec)
	var out: Array[Dictionary] = []
	var keys: Array = groups.keys()
	keys.sort()
	for key: Variant in keys:
		var members: Array = groups[key]
		if members.is_empty():
			continue
		var idx: int = _sv_fnv1a("%d|%s" % [seed_value, str(key)]) % members.size()
		out.append(members[idx] as Dictionary)
	return out


## Applies the selected SceneVariantConfig overrides where this port has an
## authored tag. Exact matches only: a spawner must carry
## _sceneRequirement.ElementTag (e.g. MapVariation.SceneElement.Quest) equal to
## the override tag (or a parent/child of it). Untagged spawners are never
## guessed at; the unresolved count is returned for the report.
##
## Locks.Doors maps to a lock state (Always = locked, Never = unlocked,
## OverrideChance = seeded lock roll). Presence categories (Guards,
## MajorLoot/MinorLoot, Quest, Civilian) suppress a matching spawn when the
## override resolves false. Lights/Windows have no per-spawn tag index yet;
## they are counted as unmapped, not silently applied.
func apply_scene_variant_overrides(_map_id: String, seed_value: int, variant_ids: Array[String], stats: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"active": 0,
		"source_variants": 0,
		"applied": 0,
		"suppressed": 0,
		"locked": 0,
		"class_mapped": 0,
		"unmapped": 0,
		"tags": [] as Array,
	}
	if stats.is_empty():
		return out
	var records: Array = stats.get("scene_element_spawns", []) as Array
	var active: Array = []
	for v: Variant in load_scene_variants():
		if v is Dictionary and variant_ids.has(str((v as Dictionary).get("id", ""))):
			active.append(v)
	out["active"] = active.size()
	# Global map variants apply everywhere; building/sublevel variants apply to
	# their own source map (the LevelInstance building that owns the spawner).
	# The latter is where almost all Locks/MajorLoot overrides live.
	var override_sets: Array = []
	if not active.is_empty():
		override_sets.append({"variants": active, "source": ""})
	var sources: Dictionary = {}
	for rec_var: Variant in records:
		if rec_var is Dictionary:
			var sm: String = _sv_source_map(str((rec_var as Dictionary).get("source", "")))
			if sm != "":
				sources[sm] = true
	for d_var: Variant in stats.get("swinging_doors", []) as Array:
		if d_var is Dictionary:
			var sm2: String = _sv_source_map(str((d_var as Dictionary).get("source", "")))
			if sm2 != "":
				sources[sm2] = true
	for smv: Variant in sources.keys():
		var src_map: String = str(smv)
		var svs: Array = select_scene_variants(src_map, seed_value, [] as Array[String])
		var with_ov: Array = []
		for s_var: Variant in svs:
			if s_var is Dictionary and not ((s_var as Dictionary).get("overrides", []) as Array).is_empty():
				with_ov.append(s_var)
		if not with_ov.is_empty():
			override_sets.append({"variants": with_ov, "source": src_map})
			out["source_variants"] = int(out["source_variants"]) + with_ov.size()
	var suppress: Dictionary = {}
	for set_var: Variant in override_sets:
		if not (set_var is Dictionary):
			continue
		var set: Dictionary = set_var as Dictionary
		var source_filter: String = str(set.get("source", ""))
		var variants: Array = set.get("variants", []) as Array
		for v_var: Variant in variants:
			if not (v_var is Dictionary):
				continue
			var overrides: Array = (v_var as Dictionary).get("overrides", []) as Array
			for ov_var: Variant in overrides:
				if not (ov_var is Dictionary):
					continue
				var ov: Dictionary = ov_var as Dictionary
				var tag: String = str(ov.get("tag", ""))
				var kind: String = _scene_override_kind(tag)
				if kind == "":
					out["unmapped"] = int(out["unmapped"]) + 1
					continue
				var typ: String = str(ov.get("type", ""))
				var chance: float = float(ov.get("chance", 100.0))
				var matched: bool = false
				for rec_var2: Variant in records:
					if not (rec_var2 is Dictionary):
						continue
					var rec: Dictionary = rec_var2 as Dictionary
					if str(rec.get("kind", "")) != kind or kind == "door":
						continue
					if source_filter != "" and _sv_source_map(str(rec.get("source", ""))) != source_filter:
						continue
					var rec_tag: String = str(rec.get("element_tag", ""))
					if rec_tag != "" and rec_tag != tag and not rec_tag.begins_with(tag + ".") and not tag.begins_with(rec_tag + "."):
						continue
					matched = true
					var applies: bool = _sv_override_applies(typ, chance, seed_value, str(rec.get("name", "")), tag)
					if not applies:
						suppress[_sv_pos_key(rec.get("pos", [0.0, 0.0, 0.0]))] = true
						out["suppressed"] = int(out["suppressed"]) + 1
					if rec_tag == "":
						out["class_mapped"] = int(out["class_mapped"]) + 1
					out["applied"] = int(out["applied"]) + 1
				if kind == "door":
					var door_arr: Array = stats.get("swinging_doors", []) as Array
					for dv2: Variant in door_arr:
						if not (dv2 is Dictionary):
							continue
						var dd: Dictionary = dv2 as Dictionary
						if source_filter != "" and _sv_source_map(str(dd.get("source", ""))) != source_filter:
							continue
						var dtag: String = str(dd.get("element_tag", ""))
						if dtag != "" and dtag != tag and not dtag.begins_with(tag + ".") and not tag.begins_with(dtag + "."):
							continue
						if dd.has("scene_locked"):
							continue
						var door_key: String = str(dd.get("actor", dd.get("name", "")))
						var door_applies: bool = _sv_override_applies(typ, chance, seed_value, door_key, tag)
						dd["scene_locked"] = door_applies
						if door_applies:
							out["locked"] = int(out["locked"]) + 1
						if dtag == "":
							out["class_mapped"] = int(out["class_mapped"]) + 1
						out["applied"] = int(out["applied"]) + 1
						matched = true
				if not matched:
					out["unmapped"] = int(out["unmapped"]) + 1
				(out["tags"] as Array).append(tag)

	# Presence arrays: filter poses that resolved false. Typed arrays are kept
	# typed so existing consumers never see a shape change.
	var gs_in: Array = stats.get("guard_spawns", []) as Array
	var gs_out: Array[Vector3] = []
	for gv: Variant in gs_in:
		if gv is Vector3 and not suppress.has(_sv_pos_key(gv)):
			gs_out.append(gv as Vector3)
	stats["guard_spawns"] = gs_out
	for arr_key: String in ["loot_spawns", "door_spawns", "civilian_spawns"]:
		var arr_in: Array = stats.get(arr_key, []) as Array
		var arr_out: Array[Vector3] = []
		for av: Variant in arr_in:
			if av is Vector3 and not suppress.has(_sv_pos_key(av)):
				arr_out.append(av as Vector3)
		stats[arr_key] = arr_out
	for rec_key: String in ["major_loot_spawns", "minor_loot_spawns"]:
		var rec_in: Array = stats.get(rec_key, []) as Array
		var rec_out: Array = []
		for rv: Variant in rec_in:
			if rv is Dictionary and suppress.has(_sv_pos_key((rv as Dictionary).get("pos", [0.0, 0.0, 0.0]))):
				continue
			rec_out.append(rv)
		stats[rec_key] = rec_out
	return out


func _apply_collider_budget(ctx: Dictionary, json_paths: Array) -> void:
	for jp: Variant in json_paths:
		if str(jp).find("/FTUE/") >= 0:
			ctx["building_cap"] = MAX_BUILDING_SHAPES_FTUE
			ctx["total_cap"] = MAX_TOTAL_SHAPES_FTUE
			push_warning(
				"[level_loader] FTUE collider budget raised to %d building / %d total (authored city demand exceeds %d/%d; no gameplay colliders dropped)"
				% [MAX_BUILDING_SHAPES_FTUE, MAX_TOTAL_SHAPES_FTUE, MAX_BUILDING_SHAPES, MAX_TOTAL_SHAPES]
			)
			return
	ctx["building_cap"] = MAX_BUILDING_SHAPES
	ctx["total_cap"] = MAX_TOTAL_SHAPES


func _new_build_ctx(parent: Node3D, light_probe: Node, generate_collision: bool) -> Dictionary:
	return {
		"parent": parent,
		"light_probe": light_probe,
		"generate_collision": generate_collision,
		"col_bodies": {},
		"col_counts": {},
		"collision_shapes": 0,
		"collision_bodies": 0,
		"building_shapes": 0,
		"curb_shapes": 0,
		"collision_dropped": 0,
		"building_dropped": 0,
		"curb_dropped": 0,
		"dropped_colliders": [] as Array,
		"occluders": 0,
		"missing_meshes": [] as Array,
		"missing_mesh_count": 0,
		"curb_built": 0,
		"chunk_count": 0,
		"light_count": 0,
		"landscapes_built": 0,
		"landscape_mat": null,
		"decal_count": 0,
		"decal_skipped": 0,
		"decal_unresolved_material": 0,
		"rect_light_count": 0,
		"rect_light_skipped": 0,
		"blocking_volume_count": 0,
		"volume_skipped": 0,
		"niagara_placements": 0,
		"fog_volumes_built": 0,
		"spline_count": 0,
		"sky_light": {},
		"fog_volume": {},
		"post_process": {},
	}


## Records one authored spawner against its SceneElement tag. The legacy
## position arrays stay Vector3; this parallel index is what #11 matches.
func _note_scene_element(result: Dictionary, kind: String, mk: Dictionary, p: Vector3) -> void:
	if kind == "":
		return
	var arr: Array = result["scene_element_spawns"]
	arr.append({
		"kind": kind,
		"name": str(mk.get("name", "")),
		"class": str(mk.get("class", "")),
		"pos": [p.x, p.y, p.z],
		"element_tag": str(mk.get("scene_requirement", "")),
		"spawn_group": str(mk.get("spawn_group", "")),
		"source": str(mk.get("source", "")),
	})


## Parses one .tatlevel.json into the accumulator. Meshes from skybox/periphery
## sublevels go into the non-colliding batch table so they never spawn physics.
func _parse_sublevel_file(json_path: String, acc: Dictionary, parent: Node3D) -> void:
	if not FileAccess.file_exists(json_path):
		return
	var f: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	var data_dict: Dictionary = data
	var result: Dictionary = acc["result"]
	var landscapes: Array = acc["landscapes"]
	for lc in data_dict.get("landscapes", []):
		if lc is Dictionary:
			landscapes.append(lc)

	var decorative_sublevel: bool = _is_decorative_sublevel(json_path)
	var collide_sublevel: bool = not decorative_sublevel
	var batches: Dictionary = acc["batches"] if collide_sublevel else acc["batches_nocol"]
	if decorative_sublevel:
		batches = acc["batches_far"]

	# Collect Thieves' Den exit door markers first so their SM_DoorInaccessibleA leaf
	# is wired into the swinging-door path instead of spawning a static duplicate.
	var den_exit_doors: Array[Dictionary] = []
	for mk_pre in data_dict.get("markers", []):
		if not (mk_pre is Dictionary):
			continue
		var mk_d: Dictionary = mk_pre as Dictionary
		if str(mk_d.get("class", "")) == "BP_ThievesDenExitDoorInteractable_C":
			var dp_arr: Array = mk_d.get("pos", [0.0, 0.0, 0.0])
			var dp: Vector3 = Vector3(float(dp_arr[0]), float(dp_arr[1]), float(dp_arr[2]))
			var rec: Dictionary = {
				"name": str(mk_d.get("name", "")),
				"class": "BP_ThievesDenExitDoorInteractable_C",
				"pos": [dp.x, dp.y, dp.z],
				"basis": (mk_d.get("basis", [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]) as Array).duplicate(),
				"leaf_mesh": "/Game/Art/Environment/Props/Doors/SM_DoorInaccessibleA",
				"leaf_rel_pos": [-1.22, 0.0, 0.0],
				"leaf_rel_basis": [-1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0],
				"leaf_rel_scale": [1.0, 0.8925, 1.0],
				"_pivot_vec": dp,
			}
			den_exit_doors.append(rec)

	for m in data_dict.get("meshes", []):
		if not (m is Dictionary):
			continue
		var m_dict: Dictionary = m
		var mp: String = str(m_dict.get("mesh", ""))
		if mp == "":
			continue
		if not den_exit_doors.is_empty() and mp.ends_with("SM_DoorInaccessibleA"):
			var tr_door: Transform3D = _dict_to_transform(m_dict)
			var matched_exit: bool = false
			for ex_rec: Dictionary in den_exit_doors:
				var piv_v: Vector3 = ex_rec["_pivot_vec"] as Vector3
				if tr_door.origin.distance_to(piv_v) <= 2.0:
					var rel_p: Vector3 = tr_door.origin - piv_v
					ex_rec["leaf_rel_pos"] = [rel_p.x, rel_p.y, rel_p.z]
					var sc_d: Variant = m_dict.get("scale", null)
					if sc_d is Array and (sc_d as Array).size() >= 3:
						var sca: Array = sc_d as Array
						ex_rec["leaf_rel_scale"] = [float(sca[0]), float(sca[1]), float(sca[2])]
					matched_exit = true
					break
			if matched_exit:
				continue
		# Authored moon billboards render as gray quads now that the real sky
		# carries the moon disc (texture stripped by cooking); hide them and
		# count them, never spawning geometry/collision for them.
		if _is_moonshape_mesh(mp):
			result["moonshape_hidden"] = int(result.get("moonshape_hidden", 0)) + 1
			continue
		var low_mp: String = mp.to_lower()
		if "fogsheet" in low_mp or "fogsphere" in low_mp or "volumetric" in low_mp or "skysphere" in low_mp or "blocker" in low_mp:
			continue
		var tr: Transform3D = _dict_to_transform(m_dict)
		# Per-component OverrideMaterials split the batch so each MultiMesh
		# shares an identically overridden duplicated Mesh resource.
		var ov_arr: Array[String] = _extract_override_materials(m_dict)
		var ov_key: String = "" if ov_arr.is_empty() else "|".join(ov_arr)
		var cpd_raw: Variant = m_dict.get("cpd", null)
		var has_cpd: bool = false
		var cpd_color: Color = Color(1.0, 1.0, 1.0, 0.0)
		if cpd_raw is Array and (cpd_raw as Array).size() == 5 and _is_emissive_cpd_override(ov_arr):
			var cpd_arr: Array = cpd_raw as Array
			var cpd_num_ok: bool = true
			for ci: int in range(5):
				var cv: Variant = cpd_arr[ci]
				if not (cv is float or cv is int):
					cpd_num_ok = false
					break
			if cpd_num_ok:
				cpd_color = Color(float(cpd_arr[2]), float(cpd_arr[3]), float(cpd_arr[4]), float(cpd_arr[1]))
				has_cpd = true
		var hidden_raw: Variant = m_dict.get("hidden_in_game", false)
		var hidden_in_game: bool = hidden_raw is bool and (hidden_raw as bool)
		var bkey: String = mp if ov_key == "" else mp + "||" + ov_key
		if has_cpd:
			bkey += "||cpd"
		if hidden_in_game:
			bkey += "||hidden"
		if not batches.has(bkey):
			batches[bkey] = {
				"mp": mp,
				"override_materials": ov_arr,
				"override_key": ov_key,
				"trs": [] as Array[Transform3D],
				"cpds": [] as Array[Color],
				"hidden_in_game": hidden_in_game,
			}
		var batch_rec: Dictionary = batches[bkey] as Dictionary
		var arr: Array[Transform3D] = batch_rec["trs"]
		arr.append(tr)
		if has_cpd:
			var carr: Array[Color] = batch_rec["cpds"]
			carr.append(cpd_color)
		var prop_pos: Vector3 = tr.origin
		if "candelabra" in low_mp or "candle" in low_mp or "brazier" in low_mp or "torch" in low_mp:
			var candle_arr: Array = result["candelabra_positions"]
			candle_arr.append(prop_pos)
			var wick_y: float = 0.16
			if "candelabrafloor" in low_mp:
				wick_y = 1.35
			elif "candelabra" in low_mp:
				wick_y = 0.46
			elif "brazier" in low_mp or "torch" in low_mp:
				wick_y = 0.55
			wick_y *= tr.basis.get_scale().y
			_VfxManager.spawn_candle_flame(parent, prop_pos + Vector3(0.0, wick_y, 0.0))
		if "wardrobe" in low_mp or "bureau" in low_mp or "armoire" in low_mp:
			var ward_arr: Array = result["wardrobe_positions"]
			ward_arr.append(prop_pos)
		if "sm_map_thievesden" in low_mp:
			var desk_arr: Array = result["desk_positions"]
			desk_arr.insert(0, prop_pos)
		elif "maptable" in low_mp or "table_map" in low_mp or "desk" in low_mp:
			var desk_arr2: Array = result["desk_positions"]
			desk_arr2.append(prop_pos)
		if "openedledger" in low_mp:
			var led_arr: Array = result["ledger_positions"]
			led_arr.append(prop_pos)
		if "windowborder" in low_mp or "thievesden_window" in low_mp:
			var win_arr: Array = result["window_positions"]
			win_arr.append(prop_pos)

	for l in data_dict.get("lights", []):
		if not (l is Dictionary):
			continue
		var l_dict: Dictionary = l
		if "TATShadowFade" in str(l_dict.get("type", "")):
			continue
		if _to_float(l_dict.get("intensity"), 10.0) <= 0.0 or l_dict.get("visible") == false:
			continue
		var lpos: Array = l_dict.get("pos", [0, 0, 0])
		var lkey: String = "%d,%d,%d" % [roundi(float(lpos[0])), roundi(float(lpos[1])), roundi(float(lpos[2]))]
		var seen_lights: Dictionary = acc["seen_lights"]
		if seen_lights.has(lkey):
			continue
		seen_lights[lkey] = true
		var pending_lights: Array = acc["lights"]
		pending_lights.append(l_dict)

	for mk in data_dict.get("markers", []):
		if not (mk is Dictionary):
			continue
		var cls: String = str(mk.get("class", ""))
		var pos_arr: Array = mk.get("pos", [0, 0, 0])
		var p: Vector3 = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		if "PlayerStart" in cls:
			var ps: Array = result["player_spawns"]
			ps.append(p)
			# Authored facing: UE PlayerStart yaw is the spawn facing direction.
			# player_spawns above stays position-only for compatibility.
			var pname: String = str(mk.get("name", ""))
			var pbasis: Array = (mk.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1]) as Array).duplicate()
			(result["player_spawn_transforms"] as Array).append({
				"pos": p,
				"basis": pbasis,
				"name": pname,
				"class": cls,
			})
		elif "MissionSpawner_Throwable" in cls:
			var ts: Array = result["throwable_spawns"]
			ts.append(p)
		elif "MissionSpawner_AmmoRefill" in cls:
			var ams: Array = result["ammo_spawns"]
			ams.append(p)
		elif "MissionSpawner_Health" in cls:
			var hs: Array = result["health_spawns"]
			hs.append(p)
		elif "MissionSpawner_Civilian" in cls:
			var cs: Array = result["civilian_spawns"]
			cs.append(p)
			_note_scene_element(result, "civilian", mk, p)
		elif "SmartObject" in cls:
			# 1,707 BP_SmartObject_GuardDefensiveLocation_C markers are posts a
			# guard can occupy, not guard spawns. Keeping them in guard_spawns
			# spawned 1,707 extra guards and starved the real spawn budget.
			var so: Array = result["smart_objects"]
			so.append({
				"pos": p,
				"rotation": _marker_euler_deg(mk),
				"class": cls,
				"name": str(mk.get("name", "")),
				"source_file": json_path,
			})
		elif "MissionSpawner_Character" in cls or "Guard" in cls:
			var gs: Array = result["guard_spawns"]
			gs.append(p)
			_note_scene_element(result, "guard", mk, p)
		elif "MissionSpawner_MajorLoot" in cls or "MissionSpawner_MinorLoot" in cls or "QuestSpawner" in cls:
			var ls: Array = result["loot_spawns"]
			ls.append(p)
			var loot_kind: String = "quest" if "QuestSpawner" in cls else ("major_loot" if "MajorLoot" in cls else "minor_loot")
			_note_scene_element(result, loot_kind, mk, p)
			# Real loot-actor markers: kept as full records (pos in metres,
			# marker rotation as euler degrees, exact spawner class, source
			# file) for the loot wave. loot_spawns above is untouched.
			if "MissionSpawner_MinorLoot" in cls or "MissionSpawner_MajorLoot" in cls:
				var loot_entry := {
					"pos": p,
					"rotation": _marker_euler_deg(mk),
					"class": cls,
					"source_file": json_path,
				}
				if "MissionSpawner_MajorLoot" in cls:
					(result["major_loot_spawns"] as Array).append(loot_entry)
				else:
					(result["minor_loot_spawns"] as Array).append(loot_entry)
		elif "Escape" in cls:
			var es: Array = result["escape_points"]
			es.append(p)
		elif "Door" in cls:
			var ds: Array = result["door_spawns"]
			ds.append(p)
			_note_scene_element(result, "door", mk, p)
		elif cls in LOOT_CONTAINER_CLASSES:
			# Openable loot container marker: meshes already live in the level
			# geometry, so only the marker transform is recorded (existing
			# keys above are untouched).
			var lc_arr: Array = result["loot_containers"]
			var sc_raw: Array = mk.get("scale", [1, 1, 1])
			var sc := Vector3.ONE
			if sc_raw.size() >= 3:
				sc = Vector3(float(sc_raw[0]), float(sc_raw[1]), float(sc_raw[2]))
			lc_arr.append({
				"class": cls,
				"pos": p,
				"basis": (mk.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1]) as Array).duplicate(),
				"scale": sc,
			})
	for ex_rec2: Dictionary in den_exit_doors:
		var clean_rec: Dictionary = ex_rec2.duplicate()
		clean_rec.erase("_pivot_vec")
		var dsr: Array = result["door_spawn_records"]
		dsr.append(clean_rec)

	# Level-component arrays: collected verbatim, validated at build time.
	for d in data_dict.get("decals", []):
		if d is Dictionary:
			(acc["decals"] as Array).append(d)
	for r in data_dict.get("rect_lights", []):
		if r is Dictionary:
			(acc["rect_lights"] as Array).append(r)
	for v in data_dict.get("volumes", []):
		if v is Dictionary:
			(acc["volumes"] as Array).append(v)
	for s in data_dict.get("sky_lights", []):
		if s is Dictionary:
			(acc["sky_lights"] as Array).append(s)
	for fv in data_dict.get("fog_volumes", []):
		if fv is Dictionary:
			(acc["fog_volumes"] as Array).append(fv)
	for pp in data_dict.get("post_process", []):
		if pp is Dictionary:
			(acc["post_process"] as Array).append(pp)
	for n in data_dict.get("niagara", []):
		if n is Dictionary:
			(acc["niagara"] as Array).append(n)
	for sp in data_dict.get("landscape_splines", []):
		if sp is Dictionary:
			(acc["splines"] as Array).append(sp)

	# Swinging-door entries: passed through verbatim for the door wave.
	for sd in data_dict.get("swinging_doors", []):
		if sd is Dictionary:
			(result["swinging_doors"] as Array).append(sd)


## Whether a mesh path is one of the authored moon billboards that the real
## sky disc replaces. Matches (a) any bound material whose path contains
## "Moonshape" or whose materials.json "switches" set IsMoonshape, and
## (b) the exact 1m_Plane_Reverse moon mesh — extracted data shows its bound
## material is MI_EmisLight_Moonlight (unlit, texture stripped by cooking),
## not MI_MoonshapeEmissive, so the material rule alone misses the 100
## authored instances. Clause (b) additionally requires every bound material
## to carry no recoverable albedo texture, so nothing else can match it.
func _is_moonshape_mesh(mp: String) -> bool:
	var mesh_key: String = mp.split(".")[0]
	var slots: Variant = _mesh_mats_db.get(mesh_key, _mesh_mats_db_lower.get(mesh_key.to_lower(), []))
	if slots is Array:
		for slot_var: Variant in slots:
			var slot := str(slot_var)
			if slot.to_lower().find("moonshape") >= 0:
				return true
			var info: Dictionary = _materials_db.get(slot, _materials_db_lower.get(slot.to_lower(), {}))
			var switches: Variant = info.get("switches", {})
			if switches is Dictionary:
				for sk: Variant in (switches as Dictionary).keys():
					if str(sk).to_lower().replace(" ", "").replace("_", "") == "ismoonshape" and bool((switches as Dictionary)[sk]):
						return true
	if mp.split("/")[-1].to_lower() == "1m_plane_reverse" and slots is Array and not (slots as Array).is_empty():
		var textured := false
		for slot_var2: Variant in slots:
			var info2: Dictionary = _materials_db.get(str(slot_var2), _materials_db_lower.get(str(slot_var2).to_lower(), {}))
			if str((info2.get("texs", {}) as Dictionary).get("albedo", "")) != "":
				textured = true
		if not textured:
			return true
	return false


func _cell_of(tr: Transform3D) -> Vector2i:
	return Vector2i(floori(tr.origin.x / CHUNK_SIZE), floori(tr.origin.z / CHUNK_SIZE))


## Splits one mesh-path batch into per-cell draw items. Single instances (or
## batches that fit in one cell) stay as a single tight-AABB node. Decorative
## horizon sublevels pass global_batch=true and keep one node per mesh path:
## a 3km skyline shell has no useful per-cell culling and would otherwise spend
## thousands of draw calls on near-identical wall pieces.
func _make_draw_items(batches: Dictionary, collide: bool, global_batch: bool = false) -> Array:
	var items: Array = []
	for mp_var in batches.keys():
		# Batch keys carry an optional "||ov_key" suffix where ov_key is
		# "|".join(override_materials); UE mesh paths never contain "||".
		var bval: Variant = batches[mp_var]
		var mp: String = ""
		var ov_key: String = ""
		var ov_arr: Array[String] = []
		var trs: Array = []
		var cpds: Array[Color] = []
		var hidden_in_game: bool = false
		if bval is Dictionary:
			var bdict: Dictionary = bval as Dictionary
			mp = str(bdict.get("mp", ""))
			ov_key = str(bdict.get("override_key", ""))
			var bov_raw: Variant = bdict.get("override_materials", [])
			if bov_raw is Array:
				for s_var: Variant in (bov_raw as Array):
					ov_arr.append(str(s_var))
			var trs_raw: Variant = bdict.get("trs", [])
			if trs_raw is Array:
				trs = trs_raw as Array
			var cpds_raw: Variant = bdict.get("cpds", [])
			if cpds_raw is Array:
				for c_var: Variant in (cpds_raw as Array):
					if c_var is Color:
						cpds.append(c_var as Color)
			var hid_raw: Variant = bdict.get("hidden_in_game", false)
			hidden_in_game = hid_raw is bool and (hid_raw as bool)
		elif bval is Array:
			var mp_key: String = str(mp_var)
			mp = mp_key
			var sep: int = mp_key.find("||")
			if sep >= 0:
				ov_key = mp_key.substr(sep + 2)
				mp = mp_key.substr(0, sep)
			if ov_key != "":
				for part: String in ov_key.split("|"):
					ov_arr.append(part)
			trs = bval as Array
		if trs.is_empty():
			continue
		var has_cpds: bool = not cpds.is_empty() and cpds.size() == trs.size()
		if global_batch:
			items.append({
				"mp": mp,
				"override_materials": ov_arr,
				"override_key": ov_key,
				"trs": trs,
				"cpds": cpds if has_cpds else ([] as Array[Color]),
				"hidden_in_game": hidden_in_game,
				"collide": collide,
				"cell": Vector2i.ZERO,
				"far": true,
			})
			continue
		if trs.size() == 1:
			var single_tr: Transform3D = trs[0]
			var single_cpds: Array[Color] = cpds if has_cpds else ([] as Array[Color])
			items.append({
				"mp": mp,
				"override_materials": ov_arr,
				"override_key": ov_key,
				"trs": trs,
				"cpds": single_cpds,
				"hidden_in_game": hidden_in_game,
				"collide": collide,
				"cell": _cell_of(single_tr),
			})
			continue
		var cells: Dictionary = {}
		var cell_cpds_map: Dictionary = {}
		for idx: int in range(trs.size()):
			var tr: Transform3D = trs[idx]
			var ck: String = "%d_%d" % [floori(tr.origin.x / CHUNK_SIZE), floori(tr.origin.z / CHUNK_SIZE)]
			if not cells.has(ck):
				cells[ck] = [] as Array
				if has_cpds:
					cell_cpds_map[ck] = [] as Array[Color]
			var cell_arr: Array = cells[ck]
			cell_arr.append(tr)
			if has_cpds:
				var cell_carr: Array[Color] = cell_cpds_map[ck]
				cell_carr.append(cpds[idx])
		for ck_var in cells.keys():
			var ck_str: String = str(ck_var)
			var parts: PackedStringArray = ck_str.split("_")
			var cell: Vector2i = Vector2i(int(parts[0]), int(parts[1]))
			var item_cpds: Array[Color] = cell_cpds_map[ck_var] if has_cpds else ([] as Array[Color])
			items.append({
				"mp": mp,
				"override_materials": ov_arr,
				"override_key": ov_key,
				"trs": cells[ck_var],
				"cpds": item_cpds,
				"hidden_in_game": hidden_in_game,
				"collide": collide,
				"cell": cell,
			})
	return items


func _collect_draw_items(acc: Dictionary) -> Array:
	var items: Array = []
	items.append_array(_make_draw_items(acc["batches"], true))
	items.append_array(_make_draw_items(acc["batches_nocol"], false))
	items.append_array(_make_draw_items(acc["batches_far"], false, true))
	return items


func _apply_culling_policy(node: GeometryInstance3D, low_mp: String, mesh: Mesh) -> void:
	var aabb_len: float = mesh.get_aabb().size.length()
	if _has_token(low_mp, STRUCTURAL_NO_FADE_TOKENS):
		return
	if _has_token(low_mp, CLUTTER_TOKENS) and aabb_len < 2.0:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = CLUTTER_VIS_RANGE + CHUNK_RADIUS_PAD
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		return
	if aabb_len < TINY_PROP_LEN:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = TINY_PROP_VIS_RANGE + CHUNK_RADIUS_PAD
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	elif aabb_len < SMALL_PROP_LEN:
		node.visibility_range_end = SMALL_PROP_VIS_RANGE + CHUNK_RADIUS_PAD
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _qualifies_as_occluder(low_mp: String, mesh: Mesh) -> bool:
	var aabb_size: Vector3 = mesh.get_aabb().size
	var aabb_len: float = aabb_size.length()
	if aabb_len < OCCLUDER_MIN_LEN or aabb_len > OCCLUDER_MAX_LEN:
		return false
	if minf(aabb_size.x, minf(aabb_size.y, aabb_size.z)) < OCCLUDER_MIN_THICK_M:
		return false
	if not _has_token(low_mp, OCCLUDER_INCLUDE_TOKENS):
		return false
	return not _has_token(low_mp, OCCLUDER_EXCLUDE_TOKENS)


func _add_occluder(ctx: Dictionary, mesh: Mesh, tr: Transform3D) -> void:
	var aabb: AABB = mesh.get_aabb()
	var box: BoxOccluder3D = BoxOccluder3D.new()
	# F9: inset the occluder one centimetre per side so its faces never sit
	# exactly coplanar with the wall faces that spawned them (coplanar
	# occluder/geometry pairs pop as the camera moves). A smaller occluder
	# under-occludes rather than over-occludes, which is the safe direction.
	box.size = Vector3(maxf(aabb.size.x - 0.04, 0.1), maxf(aabb.size.y - 0.04, 0.1), maxf(aabb.size.z - 0.04, 0.1))
	var occ: OccluderInstance3D = OccluderInstance3D.new()
	occ.occluder = box
	occ.transform = Transform3D(tr.basis, tr * aabb.get_center())
	var parent: Node3D = ctx["parent"]
	parent.add_child(occ)
	ctx["occluders"] = int(ctx.get("occluders", 0)) + 1


## Adds one BoxShape3D/trimesh collider to the per-cell StaticBody3D bucket.
## Bodies are capped at MAX_SHAPES_PER_BODY so Jolt never rebuilds a huge compound.
## Den window-wall split gate: only Den window/wall meshes qualify; the wall
## keeps its full-height side boxes plus sill + lintel (no single slab across
## the moonbeam opening). Non-Den and non-window meshes always return false.
func _is_den_window_wall(low_mp: String) -> bool:
	var is_den: bool = low_mp.find("thievesden") >= 0 or low_mp.find("windowborder") >= 0 or low_mp.find("thievesden_window") >= 0
	if not is_den:
		return false
	return low_mp.find("window") >= 0 or low_mp.find("glass") >= 0 or low_mp.find("wall") >= 0


## Test/contract surface for the Den split: gap stays 0.9-1.0 m, sill low,
## lintel clears 2 m, and the 2 m marker gate is kept. The round-1 dead
## vista_* keys are deleted, not consumed: vista geometry is MISSING-UPSTREAM
## (ledger task-0 A8 — no MoonShape/view kit in extracted/filelist.txt, the
## UE moons live only as in-level BP_MoonShape_C_0..C_7 actors), so the
## procedural replica in mission_controller._spawn_den_window_vista stands
## under the F5 precedent and no hand UE path may masquerade as a value.
func den_window_gap_spec() -> Dictionary:
	return {
		"gap_m": DEN_WINDOW_GAP_M,
		"sill_top_m": DEN_WINDOW_SILL_TOP_M,
		"lintel_bottom_m": DEN_WINDOW_LINTEL_BOTTOM_M,
		"marker_gate_kept": true,
		"boxes": 4,
	}


## F1 collider grounding for Den floor props. When a prop-scale Den collider
## base floats above its instance ground plane, the box is grown down to the
## plane so physics rests on the floor the visuals snap to. Fires only for
## thievesden meshes with box height < 2.5 m floating within (0.02, 1.0] m;
## architecture and table-top items (base at/near the instance origin) pass
## through untouched, and shared shapes are duplicated, never mutated.
func _ground_den_prop_shape(low_mp: String, shape: BoxShape3D, tr: Transform3D, soff: Vector3) -> Array:
	if low_mp.find("thievesden") < 0:
		return [shape, soff]
	var sy: float = maxf(absf(tr.basis.get_scale().y), 0.05)
	var h: float = shape.size.y
	if h >= 2.5:
		return [shape, soff]
	var world_bottom: float = (tr * soff).y - h * 0.5 * sy
	var float_m: float = world_bottom - tr.origin.y
	if float_m <= 0.02 or float_m > 1.0:
		return [shape, soff]
	var grown := BoxShape3D.new()
	grown.size = Vector3(shape.size.x, h + float_m / sy, shape.size.z)
	var grown_soff: Vector3 = soff + Vector3(0.0, -float_m / sy * 0.5, 0.0)
	return [grown, grown_soff]


## Splits one Den wall/window box into two side boxes (full height) with a
## DEN_WINDOW_GAP_M opening, a low sill under the opening and a lintel above
## it. Falls back to a single collider when the wall is too narrow to split.
func _add_den_window_split(ctx: Dictionary, cell: Vector2i, tr: Transform3D, box_shape: BoxShape3D, soff: Vector3, kind: String = "building", label: String = "") -> void:
	var sc: Vector3 = tr.basis.get_scale()
	var sx: float = maxf(absf(sc.x), 0.05)
	var sy: float = maxf(absf(sc.y), 0.05)
	var w: float = box_shape.size.x
	var h: float = box_shape.size.y
	var d: float = box_shape.size.z
	if w * sx <= DEN_WINDOW_GAP_M + 0.2:
		ctx["den_window_unsplit"] = int(ctx.get("den_window_unsplit", 0)) + 1
		_add_collider(ctx, cell, box_shape, tr, soff, kind, label)
		return
	var mesh_gap: float = DEN_WINDOW_GAP_M / sx
	var pillar_w: float = (w - mesh_gap) * 0.5
	if pillar_w < 0.1:
		ctx["den_window_unsplit"] = int(ctx.get("den_window_unsplit", 0)) + 1
		_add_collider(ctx, cell, box_shape, tr, soff, kind, label)
		return
	var floor_y: float = soff.y - h * 0.5
	var sill_h_mesh: float = DEN_WINDOW_SILL_TOP_M / sy
	var lintel_bottom_mesh: float = DEN_WINDOW_LINTEL_BOTTOM_M / sy
	sill_h_mesh = clampf(sill_h_mesh, 0.1, h)
	lintel_bottom_mesh = clampf(lintel_bottom_mesh, 0.1, h - 0.1)
	var lintel_h_mesh: float = maxf(h - lintel_bottom_mesh, 0.1)
	var left := BoxShape3D.new()
	left.size = Vector3(pillar_w, h, d)
	_add_collider(ctx, cell, left, tr, soff + Vector3(-(mesh_gap * 0.5 + pillar_w * 0.5), 0.0, 0.0), kind, label + "/pillar_L")
	var right := BoxShape3D.new()
	right.size = Vector3(pillar_w, h, d)
	_add_collider(ctx, cell, right, tr, soff + Vector3(mesh_gap * 0.5 + pillar_w * 0.5, 0.0, 0.0), kind, label + "/pillar_R")
	var sill := BoxShape3D.new()
	sill.size = Vector3(mesh_gap, sill_h_mesh, d)
	_add_collider(ctx, cell, sill, tr, Vector3(soff.x, floor_y + sill_h_mesh * 0.5, soff.z), kind, label + "/sill")
	var lintel := BoxShape3D.new()
	lintel.size = Vector3(mesh_gap, lintel_h_mesh, d)
	_add_collider(ctx, cell, lintel, tr, Vector3(soff.x, floor_y + lintel_bottom_mesh + lintel_h_mesh * 0.5, soff.z), kind, label + "/lintel")
	ctx["den_window_splits"] = int(ctx.get("den_window_splits", 0)) + 1
	_clip_den_window_visual(ctx, tr, soff, mesh_gap, sill_h_mesh, lintel_bottom_mesh, floor_y, d)


## Cuts the visual wall where the collider splits. The converted
## SM_ThievesDen_Glass GLB bakes its two UE material slots opaque (glTF with
## no alpha mode and no images), so the full assembly renders as a gray slab
## across the collider gap. This hides that slab and seats an opening-fitted
## frosted pane plus a wood trim frame in the gap, bound to the authored UE
## materials from mesh_materials.json (MI_GlassPanels ThinTranslucent +
## MI_StoreFrontTrimA, both present with textures on disk). The trim stands
## in for the upstream SM_ThievesDen_WindowBorder mesh, which exists in the
## Pak filelist but has no converted GLB (extractor allowlist
## tools/tat-extract/Exporter.cs:200): sizes reuse the DEN_WINDOW_* split
## constants, so no measurement here is a hand value. No-ops when the
## sibling visual is absent (bare-host test path) and never emits collision.
func _clip_den_window_visual(ctx: Dictionary, tr: Transform3D, soff: Vector3, mesh_gap: float, sill_h_mesh: float, lintel_bottom_mesh: float, floor_y: float, wall_d_mesh: float) -> void:
	var parent: Node = ctx.get("parent") as Node
	if parent == null:
		return
	var visual: MeshInstance3D = null
	var mm_visual: MultiMeshInstance3D = null
	for i in range(parent.get_child_count() - 1, -1, -1):
		var cand: Node = parent.get_child(i)
		if cand is MeshInstance3D and not (cand as MeshInstance3D).has_meta("den_window_clipped"):
			var mi: MeshInstance3D = cand as MeshInstance3D
			if mi.transform.origin.distance_to(tr.origin) < 0.01:
				visual = mi
				break
		elif cand is MultiMeshInstance3D and not (cand as MultiMeshInstance3D).has_meta("den_window_clipped"):
			# Batched window visuals were invisible to this lookup. Only a
			# single-instance batch can be hidden safely (a many-instance batch
			# may contain other windows); the ambiguous case stays counted.
			var mmi: MultiMeshInstance3D = cand as MultiMeshInstance3D
			if mmi.transform.origin.distance_to(tr.origin) < 0.01 \
				and mmi.multimesh != null and mmi.multimesh.instance_count <= 1:
				mm_visual = mmi
				break
	if visual == null and mm_visual == null:
		# L3: the 1 cm sibling-visual lookup no-op'd silently, leaving the
		# baked-opaque gray slab across the collider gap. Counted + warned
		# (capped list) with the collider origin so a renamed mesh that
		# breaks the string-gated split shows up instead of vanishing.
		ctx["den_window_clip_miss"] = int(ctx.get("den_window_clip_miss", 0)) + 1
		var clip_miss: Array = ctx.get("den_window_clip_miss_list", [] as Array) as Array
		if clip_miss.size() < 16:
			clip_miss.append(tr.origin)
			push_warning("[level_loader] Den window visual clip missed: no sibling visual within 1 cm of ", tr.origin, " (misses=", ctx["den_window_clip_miss"], ")")
		ctx["den_window_clip_miss_list"] = clip_miss
		return
	if visual != null:
		visual.visible = false
		visual.set_meta("den_window_clipped", true)
	if mm_visual != null:
		mm_visual.visible = false
		mm_visual.set_meta("den_window_clipped", true)
	var sc: Vector3 = tr.basis.get_scale()
	var sx: float = maxf(absf(sc.x), 0.05)
	var sy: float = maxf(absf(sc.y), 0.05)
	var sz: float = maxf(absf(sc.z), 0.05)
	var pane_mat: Material = get_material_for_ue("/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels")
	var trim_mat: Material = get_material_for_ue("/Game/MaterialLibrary/Environment/Wood/ML/MI_StoreFrontTrimA")
	var opening_h: float = maxf(lintel_bottom_mesh - sill_h_mesh, 0.1)
	var mid_y: float = floor_y + sill_h_mesh + opening_h * 0.5
	var basis_o: Basis = tr.basis.orthonormalized()
	var scl := Vector3(sx, sy, sz)
	var pane := MeshInstance3D.new()
	pane.name = "DenWindowPane"
	var pane_box := BoxMesh.new()
	pane_box.size = Vector3(mesh_gap, opening_h, 0.06 / sz)
	pane.mesh = pane_box
	if pane_mat != null:
		pane.set_surface_override_material(0, pane_mat)
	pane.transform = Transform3D(basis_o, tr * Vector3(soff.x, mid_y, soff.z))
	pane.scale = scl
	parent.add_child(pane)
	var jamb_w: float = 0.12 / sx
	var head_h: float = 0.12 / sy
	var trim_d: float = maxf(wall_d_mesh, 0.1)
	var trim_defs: Array = [
		["DenWindowTrimL", Vector3(jamb_w, opening_h, trim_d), Vector3(soff.x - mesh_gap * 0.5 - jamb_w * 0.5, mid_y, soff.z)],
		["DenWindowTrimR", Vector3(jamb_w, opening_h, trim_d), Vector3(soff.x + mesh_gap * 0.5 + jamb_w * 0.5, mid_y, soff.z)],
		["DenWindowTrimHead", Vector3(mesh_gap + jamb_w * 2.0, head_h, trim_d), Vector3(soff.x, floor_y + lintel_bottom_mesh + head_h * 0.5, soff.z)],
		["DenWindowTrimSill", Vector3(mesh_gap + jamb_w * 2.0, head_h, trim_d), Vector3(soff.x, floor_y + sill_h_mesh - head_h * 0.5, soff.z)],
	]
	for tdef in trim_defs:
		var trim := MeshInstance3D.new()
		trim.name = str(tdef[0])
		var trim_box := BoxMesh.new()
		trim_box.size = tdef[1] as Vector3
		trim.mesh = trim_box
		if trim_mat != null:
			trim.set_surface_override_material(0, trim_mat)
		trim.transform = Transform3D(basis_o, tr * (tdef[2] as Vector3))
		trim.scale = scl
		parent.add_child(trim)


## T6 partitioned collider budget (AUDIT.md T6): `kind` is "building"
## (default: walls/floors, Den window splits, grounded Den props) or "curb"
## (procedural curb ribbons, 3 boxes per segment). Each partition has its own
## cap (MAX_BUILDING_SHAPES / MAX_CURB_SHAPES, summing to MAX_TOTAL_SHAPES)
## plus the global cap as a backstop. Overflow never returns silently: the
## drop is counted per partition and named in a push_warning carrying both
## partition counts. `label` names the dropped item (mesh path for
## buildings, ribbon/segment id for curbs).
func _add_collider(ctx: Dictionary, cell: Vector2i, shape: Shape3D, tr: Transform3D, shape_offset: Vector3, kind: String = "building", label: String = "") -> void:
	var is_curb: bool = kind == "curb"
	var part_cap: int = MAX_CURB_SHAPES if is_curb else int(ctx.get("building_cap", MAX_BUILDING_SHAPES))
	var part_key: String = "curb_shapes" if is_curb else "building_shapes"
	var part_count: int = int(ctx.get(part_key, 0))
	if int(ctx.get("collision_shapes", 0)) >= int(ctx.get("total_cap", MAX_TOTAL_SHAPES)) or part_count >= part_cap:
		ctx["collision_dropped"] = int(ctx.get("collision_dropped", 0)) + 1
		var drop_key: String = "curb_dropped" if is_curb else "building_dropped"
		ctx[drop_key] = int(ctx.get(drop_key, 0)) + 1
		var item_name: String = label if label != "" else "unlabeled collider"
		var drop_log: Array = ctx.get("dropped_colliders", [] as Array) as Array
		if drop_log.size() < 128 and not drop_log.has(item_name):
			drop_log.append(item_name)
		var part_name: String = "curb" if is_curb else "building"
		push_warning("[level_loader] collider budget overflow: dropped ", part_name, " item '", item_name, "' (", part_name, " ", part_count, "/", part_cap, "; total ", int(ctx.get("collision_shapes", 0)), "/", int(ctx.get("total_cap", MAX_TOTAL_SHAPES)), ")")
		return
	var bodies: Dictionary = ctx["col_bodies"]
	var counts: Dictionary = ctx["col_counts"]
	var base_key: String = "%d_%d" % [cell.x, cell.y]
	var used: int = int(counts.get(base_key, 0))
	var bucket: int = used / MAX_SHAPES_PER_BODY
	var body_key: String = "%s_%d" % [base_key, bucket]
	var body: StaticBody3D = bodies.get(body_key) as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "LevelCollision_%s" % body_key
		body.collision_layer = 1
		var parent: Node3D = ctx["parent"]
		parent.add_child(body)
		bodies[body_key] = body
		ctx["collision_bodies"] = int(ctx.get("collision_bodies", 0)) + 1
	counts[base_key] = used + 1
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	var sc: Vector3 = tr.basis.get_scale()
	cs.transform = Transform3D(tr.basis.orthonormalized(), tr * shape_offset)
	cs.scale = Vector3(maxf(absf(sc.x), 0.05), maxf(absf(sc.y), 0.05), maxf(absf(sc.z), 0.05))
	body.add_child(cs)
	ctx["collision_shapes"] = int(ctx.get("collision_shapes", 0)) + 1
	ctx[part_key] = part_count + 1


## T6 fail-loud export-time accounting hook. Call after a level build (or
## from the export pipeline over the _finalize result dict) to fail closed on
## collider overflow: returns true when nothing was dropped and the total is
## within cap, else emits a push_error with the partition counts and returns
## false. Accepts either the build ctx or the finalized result dict (both
## carry the same keys).
static func check_collider_budget(stats: Dictionary) -> bool:
	var dropped: int = int(stats.get("collision_dropped", 0))
	var total: int = int(stats.get("collision_shapes", 0))
	var total_cap: int = int(stats.get("total_cap", MAX_TOTAL_SHAPES))
	var building_cap: int = int(stats.get("building_cap", MAX_BUILDING_SHAPES))
	if dropped <= 0 and total <= total_cap:
		return true
	push_error("[level_loader] COLLIDER BUDGET EXCEEDED: dropped ", dropped, " colliders (building ", int(stats.get("building_dropped", 0)), " dropped, ", int(stats.get("building_shapes", 0)), "/", building_cap, "; curb ", int(stats.get("curb_dropped", 0)), " dropped, ", int(stats.get("curb_shapes", 0)), "/", MAX_CURB_SHAPES, "; total ", total, "/", total_cap, "). World geometry is missing collision — resize the partition, do not raise the cap silently.")
	return false


## Emits one chunked MultiMeshInstance3D (or plain MeshInstance3D) plus its
## colliders and occluders. Returns the number of mesh instances added.
func _is_fog_volume_override(ov_arr: Array) -> bool:
	for ov_var: Variant in ov_arr:
		if str(ov_var).find("LocalVolumetricFog") >= 0:
			return true
	return false


## Authored fog values from MI_LocalVolumetricFog_Outside_Preset_A:
## Color 0.5, Global Multiplier 0.05, EdgeFalloff 0.75, Emissive Color
## (0.4271, 0.3542, 0.5). UE's Global Multiplier is a material multiplier, not
## a per-metre extinction; ×20 is calibrated against the Vulkan capture so the
## authored 0.05 reads as FogMaterial density 1.0 instead of vanishing.
func _build_fog_volumes(trs: Array, ov_arr: Array, parent: Node3D, ctx: Dictionary) -> int:
	var ov_path: String = ""
	for ov_var: Variant in ov_arr:
		var ov: String = str(ov_var)
		if ov.find("LocalVolumetricFog") >= 0:
			ov_path = ov
			break
	var info: Dictionary = _materials_db.get(ov_path, _materials_db_lower.get(ov_path.to_lower(), {}))
	var params: Dictionary = _ue_norm_map(info.get("params", {}))
	var vectors: Dictionary = _ue_norm_map(info.get("vectors", {}))
	var density_v: Variant = _ue_lookup(params, ["globalmultiplier"])
	var density_base: float = float(density_v) if density_v != null else 0.05
	var density: float = clampf(density_base * 20.0, 0.05, 1.5)
	var edge_v: Variant = _ue_lookup(params, ["edgefalloff"])
	var edge: float = clampf(float(edge_v) if edge_v != null else 0.75, 0.0, 1.0)
	var color_v: Variant = _ue_lookup(vectors, ["color"])
	var color := Color(0.5, 0.5, 0.5, 1.0)
	if color_v is Array and (color_v as Array).size() >= 3:
		var ca: Array = color_v as Array
		color = Color(float(ca[0]), float(ca[1]), float(ca[2]), 1.0)
	var emis_v: Variant = _ue_lookup(vectors, ["emissivecolor"])
	var emis := Color(0.0, 0.0, 0.0, 1.0)
	if emis_v is Array and (emis_v as Array).size() >= 3:
		var ea: Array = emis_v as Array
		emis = Color(float(ea[0]), float(ea[1]), float(ea[2]), 1.0) * 0.08
	var built: int = 0
	for tr_var: Variant in trs:
		if not (tr_var is Transform3D):
			continue
		var tr: Transform3D = tr_var as Transform3D
		var sc: Vector3 = tr.basis.get_scale().abs()
		var fog := FogVolume.new()
		fog.name = "LocalVolumetricFog_%d" % built
		fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		fog.size = Vector3(maxf(sc.x, 0.5), maxf(sc.y, 0.5), maxf(sc.z, 0.5))
		fog.transform = Transform3D(tr.basis.orthonormalized(), tr.origin)
		var fm := FogMaterial.new()
		fm.density = density
		fm.albedo = color
		fm.emission = emis
		fm.edge_fade = clampf(1.0 - edge, 0.0, 1.0)
		fog.material = fm
		fog.set_meta("ue_material", ov_path)
		parent.add_child(fog)
		built += 1
	ctx["fog_volumes_built"] = int(ctx.get("fog_volumes_built", 0)) + built
	return built


func _build_one_draw_item(item: Dictionary, parent: Node3D, ctx: Dictionary) -> int:
	var mp: String = str(item.get("mp", ""))
	var trs: Array = item.get("trs", [])
	if trs.is_empty():
		return 0
	var info: Dictionary = _get_mesh_and_shape(mp)
	var mesh: Mesh = info["mesh"]
	if mesh == null:
		# Headless-safe missing-mesh path: log the UE path (the value the
		# fix todos cross-reference against ThievesDen_Geo/Guildhall actors),
		# emit nothing, and never touch null. A missing vista mesh degrades
		# to the procedural replica instead of crashing.
		push_warning("[level_loader] missing mesh for UE path ", mp, "; skipping draw item (no collider/occluder emitted)")
		# F8 evidence: keep the UE path (cross-reference against the T1
		# cooked actors: Guildhall_Geometry 981 actors / ThievesDen_Geo 348
		# exports) plus a headless-safe count, and never touch null. Stored
		# paths are capped at 128; the count is exact.
		ctx["missing_mesh_count"] = int(ctx.get("missing_mesh_count", 0)) + 1
		var miss_arr: Array = ctx.get("missing_meshes", [] as Array) as Array
		if miss_arr.size() < 128 and not miss_arr.has(mp):
			miss_arr.append(mp)
		return 0
	var ov_arr: Array[String] = _extract_override_materials(item)
	# C3 LocalVolumetric: the authored fog boxes are Engine Cubes with a
	# MI_LocalVolumetricFog_* override. Build a FogVolume per instance; do not
	# draw the cube or create collision for it.
	if _is_fog_volume_override(ov_arr):
		return _build_fog_volumes(trs, ov_arr, parent, ctx)
	var cpds_raw: Variant = item.get("cpds", [])
	var cpds: Array[Color] = []
	if cpds_raw is Array:
		for c_var: Variant in (cpds_raw as Array):
			if c_var is Color:
				cpds.append(c_var as Color)
	var count: int = trs.size()
	var use_cpd: bool = not cpds.is_empty() and cpds.size() == count
	var hidden_raw: Variant = item.get("hidden_in_game", false)
	var hidden_in_game: bool = hidden_raw is bool and (hidden_raw as bool)
	var far_raw: Variant = item.get("far", false)
	var far_item: bool = far_raw is bool and (far_raw as bool)
	if not use_cpd and not ov_arr.is_empty():
		var ov_key: String = str(item.get("override_key", ""))
		if ov_key == "":
			ov_key = "|".join(ov_arr)
		mesh = _get_overridden_mesh(mp, mesh, ov_arr, ov_key)
	var low_mp: String = mp.to_lower()
	var node: GeometryInstance3D
	if count >= 2 or use_cpd:
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		if use_cpd:
			mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = count
		# Explicit tight bounds: Godot only frustum-culls a MultiMesh against
		# its AABB, so each 32m chunk gets the real merged instance bounds.
		var mesh_aabb: AABB = mesh.get_aabb()
		var chunk_aabb: AABB = AABB()
		var have_bounds: bool = false
		for i in range(count):
			var tr_i: Transform3D = trs[i]
			mm.set_instance_transform(i, tr_i)
			if use_cpd:
				mm.set_instance_custom_data(i, cpds[i])
			var world_aabb: AABB = tr_i * mesh_aabb
			if not have_bounds:
				chunk_aabb = world_aabb
				have_bounds = true
			else:
				chunk_aabb = chunk_aabb.merge(world_aabb)
		if have_bounds:
			mm.custom_aabb = chunk_aabb
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if use_cpd:
			mmi.material_override = _get_emissive_cpd_material()
		node = mmi
	else:
		var tr_one: Transform3D = trs[0]
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = tr_one
		node = mi
	_apply_culling_policy(node, low_mp, mesh)
	if far_item:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		node.visibility_range_end = 0.0
	if use_cpd or hidden_in_game:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if hidden_in_game:
		node.visible = false
		node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	if MobileProfile.is_mobile():
		node.lod_bias = MobileProfile.lod_bias()
	node.set_meta("ue_mesh", mp)
	node.set_meta("decorative", not bool(item.get("collide", false)))
	if not ov_arr.is_empty():
		node.set_meta("override_materials", ov_arr)
	parent.add_child(node)
	ctx["chunk_count"] = int(ctx.get("chunk_count", 0)) + 1

	var is_clutter: bool = _has_token(low_mp, CLUTTER_TOKENS)
	if not use_cpd and not hidden_in_game and bool(item.get("collide", false)) and bool(ctx.get("generate_collision", false)) and not is_clutter:
		var shape: Shape3D = info["shape"] as Shape3D
		if shape != null:
			var soff: Vector3 = info.get("shape_offset", Vector3.ZERO)
			var cell: Vector2i = item.get("cell", Vector2i.ZERO)
			var den_split: bool = _is_den_window_wall(low_mp) and shape is BoxShape3D
			for i2 in range(count):
				var tr_c: Transform3D = trs[i2]
				if absf(tr_c.basis.determinant()) < 0.0001:
					continue
				if den_split:
					_add_den_window_split(ctx, cell, tr_c, shape as BoxShape3D, soff, "building", mp)
				elif low_mp.find("thievesden") >= 0 and shape is BoxShape3D:
					var grounded: Array = _ground_den_prop_shape(low_mp, shape as BoxShape3D, tr_c, soff)
					_add_collider(ctx, cell, grounded[0] as Shape3D, tr_c, grounded[1] as Vector3, "building", mp)
				else:
					_add_collider(ctx, cell, shape, tr_c, soff, "building", mp)

	if not use_cpd and not hidden_in_game and not is_clutter and not far_item and _qualifies_as_occluder(low_mp, mesh):
		for i3 in range(count):
			if int(ctx.get("occluders", 0)) >= MAX_OCCLUDERS:
				break
			var tr_o: Transform3D = trs[i3]
			_add_occluder(ctx, mesh, tr_o)
	return count


func _build_landscapes_sync(landscapes: Array, parent: Node3D, ctx: Dictionary) -> void:
	for lc_var: Variant in landscapes:
		_build_one_landscape(lc_var, parent, ctx)


## F7 procedural curb replica (Guildhall exterior + any map with splines).
## No SM_*Curb* asset exists in filelist.txt / extracted/json (backlog F7
## stalled: `grep -ri curb|kerb filelist.txt` is empty), so the UE-cooked
## curb profile is unrecoverable from cooked data. This replica extrudes the
## authored landscape-spline ribbon itself (Guildhall_Landscape splines 0-1:
## one continuous sidewalk path, width 3.0, mesh SM_SidewalkCityA_6m, flat
## y 7.8594; OldManor_P: 8 driveway splines, width 6.0, mesh
## SM_OldManor_DrivewayA_x6) with a footage-derived curb lip on both edges
## (KF15 01:21.38 alley wet cobbles / KF16 01:40.20 gate steps-cobbles; the
## street side is not authored, so both edges carry the lip). Ribbon top
## keeps the authored spline y (the UE spline height IS the ground height;
## nothing invented). The 0.15 m lip stays under the 0.3 m stair snap, so
## the restored surface walks like the authored sidewalk. Material prefers
## the spline's authored override material, else the spline mesh path
## through the standard get_material_for_ue() fallback chain (both maps'
## spline meshes are unbound in materials.json, so the deterministic
## stone-grey fallback binds).
const CURB_LIP_H_M: float = 0.15
const CURB_LIP_W_M: float = 0.30
const CURB_SKIRT_M: float = 0.10
const CURB_MAX_SPLINES: int = 64


## Emits one triangle with an explicit flat normal, flipping the winding
## when the authored vertex order faces away from `want`, so procedural
## ribbon faces can never come out inside-out regardless of path direction.
func _curb_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length() < 0.0000001:
		return
	st.set_normal(want)
	if n.dot(want) < 0.0:
		st.set_uv(uva)
		st.add_vertex(a)
		st.set_uv(uvc)
		st.add_vertex(c)
		st.set_uv(uvb)
		st.add_vertex(b)
	else:
		st.set_uv(uva)
		st.add_vertex(a)
		st.set_uv(uvb)
		st.add_vertex(b)
		st.set_uv(uvc)
		st.add_vertex(c)


## Extrudes one spline ribbon (walk band at the authored spline y, curb lips
## on both edges, skirts below) plus matching walk/lip collision boxes.
## The cross-section profile, swept from outer-left-bottom around to
## outer-right-bottom, is clockwise in (offset, height), so each profile
## segment's outward normal is the left of its travel direction.
func _build_one_curb_ribbon(pts: Array[Vector3], width: float, sp_mesh: String, sp_mat: String, parent: Node3D, ctx: Dictionary) -> void:
	var count: int = pts.size()
	var half: float = width * 0.5
	var lip: float = minf(CURB_LIP_W_M, half * 0.5)
	var sides: Array[Vector3] = []
	sides.resize(count)
	for i in range(count):
		var pa: Vector3 = pts[maxi(i - 1, 0)]
		var pb: Vector3 = pts[mini(i + 1, count - 1)]
		var dd: Vector3 = pb - pa
		dd.y = 0.0
		if dd.length() < 0.001:
			dd = Vector3(1, 0, 0)
		dd = dd.normalized()
		sides[i] = Vector3(-dd.z, 0.0, dd.x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arc: Array[float] = []
	arc.resize(count)
	var run: float = 0.0
	for i2 in range(count):
		if i2 > 0:
			run += pts[i2].distance_to(pts[i2 - 1])
		arc[i2] = run
	# Profile loop P0..P7 (offset, height) from outer-left-bottom around.
	var prof_o: Array[float] = [-half, -half, -half + lip, -half + lip, half - lip, half - lip, half, half]
	var prof_h: Array[float] = [-CURB_SKIRT_M, CURB_LIP_H_M, CURB_LIP_H_M, 0.0, 0.0, CURB_LIP_H_M, CURB_LIP_H_M, -CURB_SKIRT_M]
	for seg in range(count - 1):
		var m_avg: Vector3 = (sides[seg] + sides[seg + 1]) * 0.5
		if m_avg.length() < 0.001:
			m_avg = sides[seg]
		m_avg = m_avg.normalized()
		for k in range(8):
			var k2: int = (k + 1) % 8
			if k == 7:
				continue # open bottom: never visible, never emitted
			var do: float = prof_o[k2] - prof_o[k]
			var dh: float = prof_h[k2] - prof_h[k]
			var seg_l: float = sqrt(do * do + dh * dh)
			if seg_l < 0.000001:
				continue
			var want: Vector3 = m_avg * (-dh / seg_l) + Vector3.UP * (do / seg_l)
			var a: Vector3 = pts[seg] + sides[seg] * prof_o[k] + Vector3.UP * prof_h[k]
			var b: Vector3 = pts[seg] + sides[seg] * prof_o[k2] + Vector3.UP * prof_h[k2]
			var c: Vector3 = pts[seg + 1] + sides[seg + 1] * prof_o[k2] + Vector3.UP * prof_h[k2]
			var dpt: Vector3 = pts[seg + 1] + sides[seg + 1] * prof_o[k] + Vector3.UP * prof_h[k]
			var uva := Vector2(prof_o[k], arc[seg])
			var uvb := Vector2(prof_o[k2], arc[seg])
			var uvc := Vector2(prof_o[k2], arc[seg + 1])
			var uvd := Vector2(prof_o[k], arc[seg + 1])
			_curb_tri(st, a, b, c, want, uva, uvb, uvc)
			_curb_tri(st, a, c, dpt, want, uva, uvc, uvd)
	# Rect end caps (bounding rect of the profile; the lip-step notches are
	# solid-capped, which only shows if a ribbon end is left exposed).
	for cap in range(2):
		var ci: int = 0 if cap == 0 else count - 1
		var cdir: Vector3 = pts[0] - pts[1] if cap == 0 else pts[count - 1] - pts[count - 2]
		cdir.y = 0.0
		if cdir.length() < 0.001:
			cdir = Vector3(0, 0, 1 if cap == 1 else -1)
		cdir = cdir.normalized()
		var m: Vector3 = sides[ci]
		var bl: Vector3 = pts[ci] - m * half + Vector3.UP * -CURB_SKIRT_M
		var br: Vector3 = pts[ci] + m * half + Vector3.UP * -CURB_SKIRT_M
		var tr: Vector3 = pts[ci] + m * half + Vector3.UP * CURB_LIP_H_M
		var tl: Vector3 = pts[ci] - m * half + Vector3.UP * CURB_LIP_H_M
		var cv: float = arc[ci]
		_curb_tri(st, bl, br, tr, cdir, Vector2(-half, cv), Vector2(half, cv), Vector2(half, cv))
		_curb_tri(st, bl, tr, tl, cdir, Vector2(-half, cv), Vector2(half, cv), Vector2(-half, cv))
	var arr_mesh: ArrayMesh = st.commit()
	if arr_mesh == null:
		return
	# Authored landscape splines often carry only a mesh, not a material.
	# Resolve the mesh's own slot 0 from mesh_materials.json instead of feeding
	# the mesh path to get_material_for_ue() (which counted it as a fallback).
	var cmat_path: String = sp_mat
	if cmat_path == "" and sp_mesh != "":
		var curb_key: String = sp_mesh.split(".")[0]
		var curb_slots: Variant = _mesh_mats_db.get(curb_key, _mesh_mats_db_lower.get(curb_key.to_lower(), []))
		if curb_slots is Array and not (curb_slots as Array).is_empty():
			cmat_path = str((curb_slots as Array)[0])
	if cmat_path == "":
		return
	arr_mesh.surface_set_material(0, get_material_for_ue(cmat_path))
	var mi := MeshInstance3D.new()
	mi.mesh = arr_mesh
	mi.name = "CurbRibbon"
	# Structural ground surface: never distance-faded, like the masonry in
	# _apply_culling_policy.
	mi.set_meta("ue_mesh", sp_mesh)
	mi.set_meta("decorative", false)
	parent.add_child(mi)
	if not bool(ctx.get("generate_collision", false)):
		return
	# Restored authored surface: walk band flush with the spline y, curb
	# lips above it. One box per band per segment, pitched with the path so
	# sloped driveways keep contact; boxes overlap by one lip width along
	# the path to close curve gaps.
	for seg2 in range(count - 1):
		var p0: Vector3 = pts[seg2]
		var p1: Vector3 = pts[seg2 + 1]
		var seg_len: float = p0.distance_to(p1)
		if seg_len < 0.001:
			continue
		var z_ax: Vector3 = (p1 - p0) / seg_len
		var x_ax: Vector3 = Vector3.UP.cross(z_ax)
		if x_ax.length() < 0.01:
			x_ax = Vector3.RIGHT
		x_ax = x_ax.normalized()
		var y_ax: Vector3 = z_ax.cross(x_ax).normalized()
		var basis := Basis(x_ax, y_ax, z_ax)
		var mid: Vector3 = (p0 + p1) * 0.5
		var cell: Vector2i = _cell_of(Transform3D(basis, mid))
		var tr := Transform3D(basis, mid)
		var ext: float = seg_len + CURB_LIP_W_M
		var walk := BoxShape3D.new()
		walk.size = Vector3(maxf(width - lip * 2.0, 0.1), CURB_SKIRT_M + 0.02, ext)
		_add_collider(ctx, cell, walk, tr, Vector3(0, -CURB_SKIRT_M * 0.5 + 0.01, 0), "curb", "curb walk seg %d (%s)" % [seg2, sp_mesh])
		for side_sign in [-1.0, 1.0]:
			var lip_box := BoxShape3D.new()
			lip_box.size = Vector3(lip, CURB_LIP_H_M + CURB_SKIRT_M, ext)
			_add_collider(ctx, cell, lip_box, tr, Vector3(side_sign * (half - lip * 0.5), (CURB_LIP_H_M - CURB_SKIRT_M) * 0.5, 0), "curb", "curb lip seg %d side %s (%s)" % [seg2, str(int(side_sign)), sp_mesh])


## Builds one procedural curb ribbon per authored landscape spline (F7).
## SplineEditorMesh entries never reach this table (the extractor drops
## them), so every entry names a real authored mesh; entries with fewer
## than 2 points or no width are skipped, never guessed.
func _build_curbs_from_splines(splines: Array, parent: Node3D, ctx: Dictionary) -> void:
	if splines.is_empty() or parent == null:
		return
	var done: int = 0
	for sp_var: Variant in splines:
		if done >= CURB_MAX_SPLINES:
			push_warning("[level_loader] curb build hit CURB_MAX_SPLINES=", CURB_MAX_SPLINES, "; remaining splines skipped")
			break
		if not (sp_var is Dictionary):
			continue
		var sp: Dictionary = sp_var
		var pts_raw: Variant = sp.get("points", [])
		if not (pts_raw is Array) or (pts_raw as Array).size() < 2:
			continue
		var width: float = float(sp.get("width", 0.0))
		if width <= 0.0:
			continue
		var gpts: Array[Vector3] = []
		for p_var: Variant in (pts_raw as Array):
			if p_var is Array and (p_var as Array).size() >= 3:
				var parr: Array = p_var
				gpts.append(Vector3(float(parr[0]), float(parr[1]), float(parr[2])))
		if gpts.size() < 2:
			continue
		_build_one_curb_ribbon(gpts, width, str(sp.get("mesh", "")), str(sp.get("material", "")), parent, ctx)
		done += 1
	ctx["curb_built"] = int(ctx.get("curb_built", 0)) + done


func _add_one_light(linfo: Dictionary, parent: Node3D, light_probe: Node, hero_shadow: bool) -> bool:
	var lnode: Light3D = _build_light(linfo, hero_shadow)
	if lnode == null:
		return false
	lnode.shadow_enabled = hero_shadow
	parent.add_child(lnode)
	if light_probe != null and light_probe.has_method("register_light"):
		light_probe.register_light(lnode)
	return true


func _prioritize_lights(pending_lights: Array, focus_points: Array) -> Array:
	# Spawn-area lights must survive the global budget even when a distant
	# authored light is brighter; otherwise safe rooms render with an emissive
	# lamp mesh but no actual light. Priority is distance to any player spawn.
	if focus_points.is_empty():
		var copy: Array = pending_lights.duplicate()
		copy.sort_custom(_sort_lights_desc)
		return copy
	var priority: Array = []
	var rest: Array = []
	for l_var: Variant in pending_lights:
		if not (l_var is Dictionary):
			continue
		var l: Dictionary = l_var
		var p: Array = l.get("pos", [0, 0, 0])
		var near: bool = false
		for fp_var: Variant in focus_points:
			if not (fp_var is Vector3):
				continue
			var fp: Vector3 = fp_var
			var dx: float = float(p[0]) - fp.x
			var dy: float = float(p[1]) - fp.y
			var dz: float = float(p[2]) - fp.z
			if dx * dx + dy * dy + dz * dz <= 25.0 * 25.0:
				near = true
				break
		if near:
			priority.append(l)
		else:
			rest.append(l)
	priority.sort_custom(_sort_lights_desc)
	rest.sort_custom(_sort_lights_desc)
	var ordered: Array = priority + rest
	return ordered


func _add_lights(pending_lights: Array, parent: Node3D, light_probe: Node, max_lights: int, ctx: Dictionary, focus_points: Array = []) -> void:
	var ordered: Array = _prioritize_lights(pending_lights, focus_points)
	var budget: int = mini(ordered.size(), max_lights)
	var hero_shadows: int = mini(MobileProfile.hero_shadows(), budget)
	var added: int = 0
	for li in range(budget):
		var linfo: Dictionary = ordered[li]
		if _add_one_light(linfo, parent, light_probe, li < hero_shadows):
			added += 1
	ctx["light_count"] = added


func _finalize(result: Dictionary, ctx: Dictionary, mesh_instances: int) -> Dictionary:
	result["mesh_instances"] = mesh_instances
	result["player_spawn_transform_count"] = (result.get("player_spawn_transforms", []) as Array).size()
	result["minor_loot_spawn_count"] = (result.get("minor_loot_spawns", []) as Array).size()
	result["major_loot_spawn_count"] = (result.get("major_loot_spawns", []) as Array).size()
	result["loot_container_count"] = (result.get("loot_containers", []) as Array).size()
	result["throwable_spawn_count"] = (result.get("throwable_spawns", []) as Array).size()
	result["ammo_spawn_count"] = (result.get("ammo_spawns", []) as Array).size()
	result["health_spawn_count"] = (result.get("health_spawns", []) as Array).size()
	result["civilian_spawn_count"] = (result.get("civilian_spawns", []) as Array).size()
	result["light_count"] = int(ctx.get("light_count", 0))
	result["chunk_count"] = int(ctx.get("chunk_count", 0))
	result["collision_bodies"] = int(ctx.get("collision_bodies", 0))
	result["collision_shapes"] = int(ctx.get("collision_shapes", 0))
	result["building_shapes"] = int(ctx.get("building_shapes", 0))
	result["curb_shapes"] = int(ctx.get("curb_shapes", 0))
	result["collision_dropped"] = int(ctx.get("collision_dropped", 0))
	result["building_dropped"] = int(ctx.get("building_dropped", 0))
	result["curb_dropped"] = int(ctx.get("curb_dropped", 0))
	result["building_cap"] = int(ctx.get("building_cap", MAX_BUILDING_SHAPES))
	result["total_cap"] = int(ctx.get("total_cap", MAX_TOTAL_SHAPES))
	result["dropped_colliders"] = (ctx.get("dropped_colliders", [] as Array) as Array).duplicate()
	# T6 fail-loud: any dropped collider (or total over cap) push_errors here
	# so overflow can never pass silently; export gates on this flag.
	result["collider_budget_ok"] = check_collider_budget(result)
	result["occluder_count"] = int(ctx.get("occluders", 0))
	result["decal_count"] = int(ctx.get("decal_count", 0))
	result["decal_skipped"] = int(ctx.get("decal_skipped", 0))
	result["decal_unresolved_material"] = int(ctx.get("decal_unresolved_material", 0))
	result["rect_light_count"] = int(ctx.get("rect_light_count", 0))
	result["rect_light_skipped"] = int(ctx.get("rect_light_skipped", 0))
	result["blocking_volume_count"] = int(ctx.get("blocking_volume_count", 0))
	result["volume_skipped"] = int(ctx.get("volume_skipped", 0))
	result["niagara_placements"] = int(ctx.get("niagara_placements", 0))
	result["fog_volumes_built"] = int(ctx.get("fog_volumes_built", 0))
	result["niagara_spawned"] = int(ctx.get("niagara_spawned", 0))
	result["niagara_systems"] = int(ctx.get("niagara_systems", 0))
	result["spline_count"] = int(ctx.get("spline_count", 0))
	result["curb_built"] = int(ctx.get("curb_built", 0))
	result["missing_mesh_count"] = int(ctx.get("missing_mesh_count", 0))
	result["missing_meshes"] = (ctx.get("missing_meshes", [] as Array) as Array).duplicate()
	result["corrupt_mesh_count"] = corrupt_mesh_count
	result["corrupt_meshes"] = corrupt_meshes.duplicate()
	result["fallback_material_count"] = fallback_material_count
	result["fallback_materials"] = fallback_materials.duplicate()
	result["den_window_splits"] = int(ctx.get("den_window_splits", 0))
	result["den_window_unsplit"] = int(ctx.get("den_window_unsplit", 0))
	result["den_window_clip_miss"] = int(ctx.get("den_window_clip_miss", 0))
	# L1 fail-loud: any geometry hole (missing or corrupt mesh) push_errors
	# at settle so a level with vanished meshes can never pass silently;
	# export gates on meshes_ok, mirroring the collider-budget pattern.
	result["meshes_ok"] = int(ctx.get("missing_mesh_count", 0)) == 0 and corrupt_mesh_count == 0
	if not result["meshes_ok"]:
		push_error("[level_loader] MESH HOLES: missing=", int(ctx.get("missing_mesh_count", 0)), " corrupt=", corrupt_mesh_count, " (see missing_meshes/corrupt_meshes). Geometry, colliders and occluders are absent for these UE paths.")
	result["swinging_doors"] = result.get("swinging_doors", [])
	result["swinging_door_count"] = (result["swinging_doors"] as Array).size()
	result["sky_light"] = ctx.get("sky_light", {})
	result["fog_volume"] = ctx.get("fog_volume", {})
	result["post_process"] = ctx.get("post_process", {})
	return result


## Splits camelCase and non-alphanumeric boundaries into lowercase tokens.
func _decal_tokens(s: String) -> Array[String]:
	var out: Array[String] = []
	var cur := ""
	var prev_lower := false
	for i in range(s.length()):
		var ch := s[i]
		var is_upper := ch >= "A" and ch <= "Z"
		var is_lower := ch >= "a" and ch <= "z"
		var is_digit := ch >= "0" and ch <= "9"
		if not (is_upper or is_lower or is_digit):
			if cur != "":
				out.append(cur.to_lower())
				cur = ""
			prev_lower = false
			continue
		if is_upper and prev_lower:
			if cur != "":
				out.append(cur.to_lower())
				cur = ""
		cur += ch
		prev_lower = is_lower
	if cur != "":
		out.append(cur.to_lower())
	return out


## Strict decal-material validation. Cooked UE Material assets carry no
## expression graph, so a decal texture is trusted only when the bound albedo
## stem shares a meaningful (len>=4, non-generic) token with the material
## name — e.g. MI_SmokeBomb_Decal + T_SmokeBomb_D, MI_DirtDecalA3 +
## T_GroundDirtA_D via "dirt", MI_Decal_Moss + T_MossA_D. The generic
## poster fallback (T_DecalPostersA_DA) never shares such a token with
## unrelated materials (M_Decal_Puddle, M_Decal_Glyph) and is rejected here,
## as are placeholder swaps (MI_DecalPaperA -> T_GroundStoneA_D) and
## texture-less cooked materials (M_Puddle_Inst). The only exception is an
## explicitly authored tint colour (e.g. MagicSlime puddle), which yields a
## texture-less flat-colour decal.
func _is_decal_material_usable(ue_mat_path: String) -> Dictionary:
	var out := {"usable": false, "texture": null, "normal": null, "color": null, "reason": ""}
	if ue_mat_path == "":
		out["reason"] = "empty material path"
		return out
	var info: Dictionary = _materials_db.get(ue_mat_path, _materials_db_lower.get(ue_mat_path.to_lower(), {}))
	if info.is_empty():
		out["reason"] = "material not in materials.json"
		return out
	var texs: Dictionary = info.get("texs", {})
	var alb_path := str(texs.get("albedo", ""))
	var stem := alb_path.split("/")[-1].split(".")[0]
	var mat_tokens := _decal_tokens(ue_mat_path.split("/")[-1])
	var stem_tokens := _decal_tokens(stem)
	var matched := false
	for mt in mat_tokens:
		if mt.length() < 4 or mt in DECAL_GENERIC_TOKENS:
			continue
		for st in stem_tokens:
			if st.length() < 4 or st in DECAL_GENERIC_TOKENS:
				continue
			if st == mt or st.find(mt) >= 0 or mt.find(st) >= 0:
				matched = true
				break
		if matched:
			break
	if matched and alb_path != "":
		var tex := _load_tex(alb_path)
		if tex == null:
			out["reason"] = "albedo file missing: " + alb_path
			return out
		out["usable"] = true
		out["texture"] = tex
		var norm := _load_tex(str(texs.get("normal", "")))
		if norm != null:
			out["normal"] = norm
		var tint: Variant = info.get("tint")
		if tint is Array and (tint as Array).size() >= 3:
			var ta: Array = tint
			out["color"] = Color(float(ta[0]), float(ta[1]), float(ta[2]), 1.0)
		return out
	var tint2: Variant = info.get("tint")
	if tint2 is Array and (tint2 as Array).size() >= 3:
		var tb: Array = tint2
		var c := Color(float(tb[0]), float(tb[1]), float(tb[2]), 1.0)
		if maxf(c.r, maxf(c.g, c.b)) >= 0.05:
			out["usable"] = true
			out["color"] = c
			out["reason"] = "flat colour (explicit tint, no trustworthy texture)"
			return out
	if alb_path != "" and not matched:
		out["reason"] = "albedo stem shares no token with material (cooked graph, not recoverable)"
	else:
		out["reason"] = "no albedo and no explicit tint"
	return out


## Spawns Godot Decal nodes for validated materials only. Unresolvable
## materials are skipped and counted, never given substitute art.
func _build_decals(decals: Array, parent: Node3D, ctx: Dictionary) -> void:
	var spawned: int = 0
	var skipped: int = 0
	var unresolved: int = 0
	for d_var in decals:
		if not (d_var is Dictionary):
			skipped += 1
			continue
		var d: Dictionary = d_var
		var verdict: Dictionary = _is_decal_material_usable(str(d.get("material", "")))
		if not bool(verdict.get("usable", false)):
			skipped += 1
			unresolved += 1
			continue
		if spawned >= MAX_DECALS_PER_MAP:
			skipped += 1
			continue
		var tr := _dict_to_transform(d)
		var decal := Decal.new()
		# UE projects along local +X; Godot projects along local -Y.
		var fix := Basis(Vector3.FORWARD, PI * 0.5)
		decal.transform = Transform3D((tr.basis * fix).orthonormalized(), tr.origin)
		var size_arr: Array = []
		var size_raw: Variant = d.get("size", [])
		if size_raw is Array:
			size_arr = size_raw
		var size_v: Vector3
		if size_arr.size() >= 3:
			# Authored DecalSize is UE-ordered (X=depth, Y=width, Z=height);
			# Godot size is (X=width, Y=depth, Z=height).
			size_v = Vector3(float(size_arr[1]), float(size_arr[0]), float(size_arr[2]))
		else:
			var sc := tr.basis.get_scale()
			size_v = Vector3(absf(sc.y), absf(sc.x), absf(sc.z)) * UE_DEFAULT_DECAL_M
		decal.size = Vector3(clampf(size_v.x, 0.1, 10.0), clampf(size_v.y, 0.1, 10.0), clampf(size_v.z, 0.1, 10.0))
		var alb: Variant = verdict.get("texture")
		if alb is Texture2D:
			decal.texture_albedo = alb
		var nrm: Variant = verdict.get("normal")
		if nrm is Texture2D:
			decal.texture_normal = nrm
		var col: Variant = verdict.get("color")
		if col is Color:
			decal.modulate = col
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = DECAL_FADE_BEGIN
		decal.distance_fade_length = DECAL_FADE_END - DECAL_FADE_BEGIN
		decal.name = "Decal_%d" % spawned
		parent.add_child(decal)
		spawned += 1
	ctx["decal_count"] = spawned
	ctx["decal_skipped"] = skipped
	ctx["decal_unresolved_material"] = unresolved


## Spawns an OmniLight3D approximation plus an emissive quad for each active
## RectLight. Entries at intensity <= 0.01 are authored off and skipped.
## Energy uses the same linear authored-intensity scale as _build_light
## (LIGHT_INTENSITY_SCALE, floored at LIGHT_ENERGY_FLOOR and capped at
## LIGHT_ENERGY_CEIL); colour converts 0-255 -> 0-1.
## The quad is sized from width x height (raw UU centimetres) and is
## double-sided because the UE emission axis is not recorded; the light
## itself is omnidirectional so gameplay lighting does not depend on it.
## Shadows stay off: an omni shadow would shade the wrong hemisphere for an
## area light; the emissive quad carries the visual instead.
func _build_rect_lights(rects: Array, parent: Node3D, light_probe: Node, ctx: Dictionary, budget: int) -> void:
	var spawned: int = 0
	var skipped: int = 0
	for r_var in rects:
		if not (r_var is Dictionary):
			skipped += 1
			continue
		var r: Dictionary = r_var
		var raw := float(r.get("intensity", 0.0))
		if raw <= RECT_LIGHT_OFF_THRESHOLD:
			skipped += 1
			continue
		if spawned >= budget:
			skipped += 1
			continue
		var omni := OmniLight3D.new()
		omni.omni_range = clampf(maxf(float(r.get("radius", 5.0)), 1.0), 1.0, LIGHT_RANGE_CEIL)
		# Godot's default attenuation. 2.0 would be the physically accurate
		# inverse-square choice; the authored UE lights use inverse-squared
		# falloff with lumen units, but 1.0 is kept as the art default. The
		# previous 0.9 -> 1.0 raises the attenuation exponent, so falloff is
		# FASTER, not slower.
		omni.omni_attenuation = 1.0
		omni.light_energy = clampf(raw * LIGHT_INTENSITY_SCALE, LIGHT_ENERGY_FLOOR, LIGHT_ENERGY_CEIL)
		var col_arr: Array = [255.0, 215.0, 150.0]
		var col_raw: Variant = r.get("color", [])
		if col_raw is Array and (col_raw as Array).size() >= 3:
			col_arr = col_raw
		omni.light_color = Color(float(col_arr[0]) / 255.0, float(col_arr[1]) / 255.0, float(col_arr[2]) / 255.0)
		omni.shadow_enabled = false
		omni.distance_fade_enabled = true
		omni.distance_fade_begin = LIGHT_DISTANCE_FADE_BEGIN
		omni.distance_fade_length = LIGHT_DISTANCE_FADE_LENGTH
		omni.distance_fade_shadow = true
		var rtr := _dict_to_transform(r)
		omni.transform = rtr
		omni.name = "RectLight_%d" % spawned
		parent.add_child(omni)
		if light_probe != null and light_probe.has_method("register_light"):
			light_probe.register_light(omni)
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(clampf(float(r.get("width", 1.0)) * UU_CM_TO_M, 0.1, 30.0), clampf(float(r.get("height", 1.0)) * UU_CM_TO_M, 0.1, 30.0))
		var qmat := StandardMaterial3D.new()
		qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qmat.albedo_color = omni.light_color
		qmat.emission_enabled = true
		qmat.emission = omni.light_color
		qmat.emission_energy_multiplier = 2.0 # L6: keep authored energy; range sync is via visibility fade below
		qmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		qm.material = qmat
		quad.mesh = qm
		quad.transform = Transform3D(rtr.basis.orthonormalized(), rtr.origin)
		quad.name = "RectLightQuad_%d" % spawned
		# L6: fade the emissive quad over the same range its omni uses
		# (LIGHT_DISTANCE_FADE_BEGIN/LENGTH) so glow cannot outlive light.
		quad.visibility_range_end = LIGHT_DISTANCE_FADE_BEGIN + LIGHT_DISTANCE_FADE_LENGTH
		quad.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(quad)
		spawned += 1
	ctx["rect_light_count"] = spawned
	ctx["rect_light_skipped"] = skipped


## Turns designer blocking volumes into real collision. UE extent is already
## a half-extent in metres, so the box is extent*2 at pos on layer 1.
## NavMesh / NavModifier / Trigger / Tutorial volumes carry navigation or
## gameplay logic, not collision, and are counted as skipped.
func _build_volumes(volumes: Array, parent: Node3D, ctx: Dictionary) -> void:
	var blocking: int = 0
	var skipped: int = 0
	for v_var in volumes:
		if not (v_var is Dictionary):
			skipped += 1
			continue
		var v: Dictionary = v_var
		var cls := str(v.get("class", "")).to_lower()
		if cls.find("blocking") < 0 and cls.find("block") < 0:
			skipped += 1
			continue
		var ext: Array = [1.0, 1.0, 1.0]
		var ext_raw: Variant = v.get("extent", [])
		if ext_raw is Array and not (ext_raw as Array).is_empty():
			ext = ext_raw
		var ex := float(ext[0]) if ext.size() > 0 else 1.0
		var ey := float(ext[1]) if ext.size() > 1 else 1.0
		var ez := float(ext[2]) if ext.size() > 2 else 1.0
		var p: Array = [0.0, 0.0, 0.0]
		var p_raw: Variant = v.get("pos", [])
		if p_raw is Array and (p_raw as Array).size() >= 3:
			p = p_raw
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		# Authored volume rotation: a rotated blocking volume must block along its
		# own axes, not the world axes (the old code ignored this entirely).
		var vol_basis: Variant = v.get("basis", [])
		if vol_basis is Array and (vol_basis as Array).size() == 9:
			var vb: Array = vol_basis as Array
			body.basis = Basis(
				Vector3(float(vb[0]), float(vb[1]), float(vb[2])),
				Vector3(float(vb[3]), float(vb[4]), float(vb[5])),
				Vector3(float(vb[6]), float(vb[7]), float(vb[8])),
			)
		else:
			var vol_rot: Variant = v.get("rotation", [])
			if vol_rot is Array and (vol_rot as Array).size() >= 3:
				var vr: Array = vol_rot as Array
				body.rotation_degrees = Vector3(float(vr[0]), float(vr[1]), float(vr[2]))
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(ex * 2.0, 0.1), maxf(ey * 2.0, 0.1), maxf(ez * 2.0, 0.1))
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		body.name = "BlockingVolume_%d" % blocking
		parent.add_child(body)
		blocking += 1
	ctx["blocking_volume_count"] = blocking
	ctx["volume_skipped"] = skipped
	# T6 accounting: blocking volumes always emit (no cap check, no silent
	# drop), but they consume world-integrity budget, so they count against
	# the building partition.
	ctx["collision_bodies"] = int(ctx.get("collision_bodies", 0)) + blocking
	ctx["collision_shapes"] = int(ctx.get("collision_shapes", 0)) + blocking
	ctx["building_shapes"] = int(ctx.get("building_shapes", 0)) + blocking


## Records counts and first-present atmosphere entries for the result stats.
## SplineEditorMesh entries never reach the splines table (the extractor
## drops them), so every spline here names a real authored mesh
## (SM_SidewalkCityA_6m / SM_OldManor_DrivewayA_x6) and is rebuilt as a
## procedural curb ribbon by _build_curbs_from_splines (F7 replica);
## spline_count still records the authored count.
## Niagara placements are likewise counted here for the VFX wave.
func _store_level_extras(acc: Dictionary, ctx: Dictionary) -> void:
	ctx["niagara_placements"] = (acc["niagara"] as Array).size()
	_spawn_level_niagara(acc, ctx)
	ctx["spline_count"] = (acc["splines"] as Array).size()
	if not (acc["sky_lights"] as Array).is_empty():
		ctx["sky_light"] = (acc["sky_lights"] as Array)[0]
	if not (acc["fog_volumes"] as Array).is_empty():
		ctx["fog_volume"] = (acc["fog_volumes"] as Array)[0]
	if not (acc["post_process"] as Array).is_empty():
		ctx["post_process"] = (acc["post_process"] as Array)[0]


## Desktop-only R3 APPROXIMATE replacements for UE5 LumenSkylightLeaking and
## LocalExposure* settings carried in level PostProcessVolumes (e.g. ThievesDenTest_P).
## Never registers bounce fills with light_probe (Suite 36/36b) or group
## "den_hand_fills" (Suite 34b), and never mutates ambient_light_energy or
## adjustment_brightness (Suites 17 & 34b).
## Spawn every authored Niagara placement through one MultiMesh per NS_* system.
## 3,695 placements become 37 nodes (37 draw calls) instead of 3,695 emitters.
## The tint/size encode the system family; the shader animates per-instance phase.
func _spawn_level_niagara(acc: Dictionary, ctx: Dictionary) -> void:
	var parent: Node = ctx.get("parent") as Node
	if parent == null:
		return
	var groups: Dictionary = {}
	for r: Variant in (acc.get("niagara", []) as Array):
		if not (r is Dictionary):
			continue
		var asset: String = str((r as Dictionary).get("asset", ""))
		if asset == "":
			continue
		if not groups.has(asset):
			groups[asset] = []
		(groups[asset] as Array).append(r)
	if groups.is_empty():
		ctx["niagara_spawned"] = 0
		ctx["niagara_systems"] = 0
		return
	var shader: Shader = load("res://src/core/level_niagara.gdshader") as Shader
	var total: int = 0
	for asset: Variant in groups.keys():
		var recs: Array = groups[asset]
		if recs.is_empty():
			continue
		var quad := QuadMesh.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = recs.size()
		for i: int in range(recs.size()):
			var rec: Dictionary = recs[i] as Dictionary
			var pos_arr: Array = rec.get("pos", [0, 0, 0]) as Array
			var b_arr: Variant = rec.get("basis", [])
			var basis := Basis()
			if b_arr is Array and (b_arr as Array).size() == 9:
				var b: Array = b_arr as Array
				basis = Basis(
					Vector3(float(b[0]), float(b[1]), float(b[2])),
					Vector3(float(b[3]), float(b[4]), float(b[5])),
					Vector3(float(b[6]), float(b[7]), float(b[8])),
				)
			var p := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
			mm.set_instance_transform(i, Transform3D(basis, p))
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("tint", _niagara_tint(str(asset)))
		mat.set_shader_parameter("base_size", _niagara_size(str(asset)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "LevelNiagara_" + str(asset).get_file().replace(".", "_")
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		total += recs.size()
	ctx["niagara_spawned"] = total
	ctx["niagara_systems"] = groups.size()
	push_warning("[level_loader] level Niagara: %d placements across %d systems spawned" % [total, groups.size()])


func _niagara_tint(asset: String) -> Color:
	var a: String = asset.to_lower()
	if "flame" in a or "candle" in a or "fire" in a:
		return Color(1.0, 0.55, 0.18, 0.9)
	if "lightbeam" in a or "beam" in a:
		return Color(0.55, 0.85, 1.0, 0.7)
	if "eye" in a or "alarm" in a or "turret" in a:
		return Color(1.0, 0.22, 0.18, 0.85)
	if "dust" in a or "break" in a or "debris" in a:
		return Color(0.62, 0.58, 0.52, 0.5)
	if "smoke" in a:
		return Color(0.55, 0.55, 0.58, 0.5)
	if "ward" in a or "magic" in a or "arcane" in a:
		return Color(0.55, 0.35, 1.0, 0.8)
	return Color(0.9, 0.9, 0.95, 0.55)


func _niagara_size(asset: String) -> float:
	var a: String = asset.to_lower()
	if "dust" in a or "break" in a or "smoke" in a:
		return 0.35
	if "beam" in a:
		return 0.08
	return 0.12


func _build_post_process_gi_fills(post_processes: Array, parent: Node3D, _ctx: Dictionary) -> void:
	if MobileProfile.is_mobile() or parent == null:
		return
	var fill_idx: int = 0
	var wenv: WorldEnvironment = null
	for child: Node in parent.get_children():
		if child is WorldEnvironment:
			wenv = child as WorldEnvironment
			break
	for pp_v: Variant in post_processes:
		if not (pp_v is Dictionary):
			continue
		var pp: Dictionary = pp_v as Dictionary
		var settings_v: Variant = pp.get("settings", {})
		if not (settings_v is Dictionary):
			continue
		var settings: Dictionary = settings_v as Dictionary
		var leak: float = float(settings.get("LumenSkylightLeaking", 0.0))
		if leak > 0.0:
			var fill := OmniLight3D.new()
			fill.name = "SkylightLeakingFill_%d" % fill_idx
			fill_idx += 1
			var pos_v: Variant = pp.get("pos", [0.0, 0.0, 0.0])
			if pos_v is Array and (pos_v as Array).size() >= 3:
				var pa: Array = pos_v as Array
				fill.position = Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
			var sc_v: Variant = pp.get("scale", [10.0, 5.0, 10.0])
			var sx: float = 10.0
			var sz: float = 10.0
			if sc_v is Array and (sc_v as Array).size() >= 3:
				var sa: Array = sc_v as Array
				sx = absf(float(sa[0]))
				sz = absf(float(sa[2]))
			fill.shadow_enabled = false
			fill.light_color = Color(0.55, 0.72, 0.95)
			fill.light_energy = clampf(leak * 0.9, 0.1, 0.45)
			fill.omni_range = clampf(maxf(sx, sz) * 1.5, 8.0, 30.0)
			fill.omni_attenuation = 0.4
			parent.add_child(fill)
		if (settings.has("LocalExposureShadowContrastScale") or settings.has("LocalExposureMiddleGreyBias")) and wenv != null and wenv.environment != null:
			var sc: float = float(settings.get("LocalExposureShadowContrastScale", 0.6))
			var mb: float = float(settings.get("LocalExposureMiddleGreyBias", 0.25))
			wenv.environment.adjustment_enabled = true
			wenv.environment.adjustment_color_correction = WeatherProfile.build_shadow_toe_lut(1.2, sc, mb)


## Derives the map hint for L5 from the level JSON paths (directory token).
## Returns "" when no known token matches — the source scan then decides.
static func _map_hint_from_paths(paths: Array) -> String:
	var joined: String = ""
	for p: Variant in paths:
		joined += "|" + str(p).to_lower()
	if "guildhall" in joined:
		return "guildhall"
	if "old_manor" in joined or "oldmanor" in joined:
		return "old_manor"
	if "thieves_den" in joined or "thievesden" in joined:
		return "thieves_den"
	if "jaspering" in joined or "ftue" in joined:
		return "ftue"
	return ""


func load_sublevels(json_paths: Array[String], parent: Node3D, light_probe: Node, max_lights: int = 96, generate_collision: bool = true) -> Dictionary:
	if _materials_db.is_empty():
		_load_material_dbs()
	# V6 companion: bake the footprint alpha mask now (loading screen),
	# not on the first wet footstep. Static cache makes repeats free.
	_VfxManager.prewarm_footstep_mask()
	var acc: Dictionary = _new_accumulator()
	for jp: String in json_paths:
		_parse_sublevel_file(jp, acc, parent)

	var ctx: Dictionary = _new_build_ctx(parent, light_probe, generate_collision)
	ctx["map_hint"] = _map_hint_from_paths(json_paths)
	_apply_collider_budget(ctx, json_paths)
	# Active RectLights are rare (one per mission map at most) and authored as
	# area lights, so they claim budget slots before the generic point lights.
	_build_rect_lights(acc["rect_lights"], parent, light_probe, ctx, max_lights)
	_add_lights(acc["lights"], parent, light_probe, maxi(max_lights - int(ctx.get("rect_light_count", 0)), 0), ctx, acc["result"]["player_spawns"])
	ctx["light_count"] = int(ctx.get("light_count", 0)) + int(ctx.get("rect_light_count", 0))
	_build_decals(acc["decals"], parent, ctx)
	_build_volumes(acc["volumes"], parent, ctx)
	_store_level_extras(acc, ctx)
	_build_post_process_gi_fills(acc["post_process"], parent, ctx)
	_build_landscapes_sync(acc["landscapes"], parent, ctx)
	_build_curbs_from_splines(acc["splines"], parent, ctx)
	_build_guildhall_saferoom_floor(parent, ctx)

	var items: Array = _collect_draw_items(acc)
	var total_inst: int = 0
	for item: Dictionary in items:
		total_inst += _build_one_draw_item(item, parent, ctx)
	return _finalize(acc["result"], ctx, total_inst)


func load_sublevels_async(json_paths: Array, parent: Node3D, light_probe: Node = null, max_lights: int = 96, generate_collision: bool = true) -> Dictionary:
	if _materials_db.is_empty():
		_load_material_dbs()
	var acc: Dictionary = _new_accumulator()
	_VfxManager.prewarm_footstep_mask()
	var total_files: int = maxi(json_paths.size(), 1)
	var file_idx: int = 0
	load_progress.emit(0.0, "Parsing JSON...")
	for jp in json_paths:
		_parse_sublevel_file(str(jp), acc, parent)
		file_idx += 1
		load_progress.emit(0.3 * float(file_idx) / float(total_files), "Parsing JSON %d/%d..." % [file_idx, json_paths.size()])
		if parent.get_tree() != null:
			await parent.get_tree().process_frame

	var ctx: Dictionary = _new_build_ctx(parent, light_probe, generate_collision)
	ctx["map_hint"] = _map_hint_from_paths(json_paths)
	_apply_collider_budget(ctx, json_paths)
	var pending_lights: Array = _prioritize_lights(acc["lights"], acc["result"]["player_spawns"])
	load_progress.emit(0.3, "Sorting lights...")
	# Active RectLights claim budget slots before the generic point lights.
	_build_rect_lights(acc["rect_lights"], parent, light_probe, ctx, max_lights)
	var light_budget: int = mini(pending_lights.size(), maxi(max_lights - int(ctx.get("rect_light_count", 0)), 0))
	var lights_added: int = 0
	var hero_shadows: int = mini(MobileProfile.hero_shadows(), light_budget)
	for li in range(light_budget):
		var linfo: Dictionary = pending_lights[li]
		if _add_one_light(linfo, parent, light_probe, li < hero_shadows):
			lights_added += 1
		if li % 20 == 0 or li == light_budget - 1:
			load_progress.emit(0.3 + 0.2 * float(li + 1) / float(maxi(light_budget, 1)), "Creating lights %d/%d..." % [li + 1, light_budget])
			if parent.get_tree() != null:
				await parent.get_tree().process_frame
	ctx["light_count"] = lights_added + int(ctx.get("rect_light_count", 0))
	_build_decals(acc["decals"], parent, ctx)
	_build_volumes(acc["volumes"], parent, ctx)
	_store_level_extras(acc, ctx)
	_build_post_process_gi_fills(acc["post_process"], parent, ctx)

	var landscapes: Array = acc["landscapes"]
	for lc_i in range(landscapes.size()):
		_build_one_landscape(landscapes[lc_i], parent, ctx)
		load_progress.emit(0.5 + 0.02 * float(lc_i + 1) / float(landscapes.size()), "Building terrain %d/%d..." % [lc_i + 1, landscapes.size()])
		if parent.get_tree() != null:
			await parent.get_tree().process_frame
	_build_curbs_from_splines(acc["splines"], parent, ctx)
	_build_guildhall_saferoom_floor(parent, ctx)
	load_progress.emit(0.52, "Building curbs...")

	var items: Array = _collect_draw_items(acc)
	var built: int = 0
	var total_inst: int = 0
	for item: Dictionary in items:
		total_inst += _build_one_draw_item(item, parent, ctx)
		built += 1
		if built % PROGRESS_YIELD_EVERY == 0 or built == items.size():
			load_progress.emit(0.52 + 0.46 * float(built) / float(maxi(items.size(), 1)), "Batching meshes %d/%d..." % [built, items.size()])
			if parent.get_tree() != null:
				await parent.get_tree().process_frame
	load_progress.emit(1.0, "Done")
	return _finalize(acc["result"], ctx, total_inst)


## Ranks authored lights into the fixed light budget. This score is used ONLY
## for that ordering; it tracks the rendered energy (the same linear scale as
## _build_light / _build_rect_lights) so the budget keeps the brightest lights
## instead of the old non-monotonic heuristic. The type bonuses are expressed
## against LIGHT_ENERGY_CEIL to keep their previous weight (Directional 10.0
## and Spot 2.0 against the old ~4.2 maximum), which is why they are large
## next to an energy term of at most LIGHT_ENERGY_CEIL.
func _light_score(info: Dictionary) -> float:
	var raw: float = _to_float(info.get("intensity"), 15.0)
	var energy: float = clampf(raw * LIGHT_INTENSITY_SCALE, LIGHT_ENERGY_FLOOR, LIGHT_ENERGY_CEIL)
	var ltype: String = str(info.get("type", ""))
	if "Directional" in ltype:
		energy += LIGHT_ENERGY_CEIL * 2.5
	elif "Spot" in ltype:
		energy += LIGHT_ENERGY_CEIL * 0.5
	return energy


func _sort_lights_desc(a: Dictionary, b: Dictionary) -> bool:
	return _light_score(a) > _light_score(b)


func _dict_to_transform(d: Dictionary) -> Transform3D:
	var p: Array = d.get("pos", [0, 0, 0])
	var b: Array = d.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	var s: Array = d.get("scale", [1, 1, 1])
	var basis: Basis = Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	).scaled_local(Vector3(
		clampf(float(s[0]), 0.05, 40.0),
		clampf(float(s[1]), 0.05, 40.0),
		clampf(float(s[2]), 0.05, 40.0)
	))
	return Transform3D(basis, Vector3(float(p[0]), float(p[1]), float(p[2])))


## Marker rotation as euler degrees (rotation only: scale is not part of the
## loot orientation). Identity basis -> Vector3.ZERO.
func _marker_euler_deg(d: Dictionary) -> Vector3:
	var b: Array = d.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	if b.size() < 9:
		return Vector3.ZERO
	var basis := Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	).orthonormalized()
	var e: Vector3 = basis.get_euler()
	return Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))


func _to_float(v: Variant, fallback: float) -> float:
	if v == null:
		return fallback
	return float(v)


func _build_light(info: Dictionary, cast_shadow: bool = false) -> Light3D:
	var ltype: String = str(info.get("type", ""))
	var raw_i := _to_float(info.get("intensity"), 15.0)
	var intensity := clampf(raw_i * LIGHT_INTENSITY_SCALE, LIGHT_ENERGY_FLOOR, LIGHT_ENERGY_CEIL)
	var col_dict: Variant = info.get("color")
	var col := Color(1.0, 0.85, 0.62)
	if col_dict is Dictionary:
		col = Color(
			_to_float(col_dict.get("R"), 255.0) / 255.0,
			_to_float(col_dict.get("G"), 215.0) / 255.0,
			_to_float(col_dict.get("B"), 150.0) / 255.0
		)
	var light: Light3D
	if "Directional" in ltype:
		light = DirectionalLight3D.new()
		light.light_energy = 0.45
	elif "Spot" in ltype:
		var sl := SpotLight3D.new()
		sl.spot_range = clampf(maxf(_to_float(info.get("radius"), 6.0), 1.0), 1.0, LIGHT_RANGE_CEIL)
		sl.spot_angle = clampf(_to_float(info.get("outer_cone"), 50.0), 18.0, 89.0)
		# Godot's default attenuation. 2.0 would be the physically accurate
		# inverse-square choice; the authored UE lights use inverse-squared
		# falloff with lumen units, but 1.0 is kept as the art default. The
		# previous 0.85 -> 1.0 raises the attenuation exponent, so falloff is
		# FASTER, not slower.
		sl.spot_attenuation = 1.0
		sl.light_energy = intensity
		light = sl
	else:
		var ol := OmniLight3D.new()
		ol.omni_range = clampf(maxf(_to_float(info.get("radius"), 5.0), 1.0), 1.0, LIGHT_RANGE_CEIL)
		# Godot's default attenuation. 2.0 would be the physically accurate
		# inverse-square choice; the authored UE lights use inverse-squared
		# falloff with lumen units, but 1.0 is kept as the art default. The
		# previous 0.9 -> 1.0 raises the attenuation exponent, so falloff is
		# FASTER, not slower.
		ol.omni_attenuation = 1.0
		ol.light_energy = intensity
		light = ol
	light.light_color = col
	light.shadow_enabled = cast_shadow
	# P3: non-hero point/spot lights fade out with camera distance so the
	# Forward+ clustered light list only uploads nearby lights.
	if not cast_shadow and (light is OmniLight3D or light is SpotLight3D):
		light.distance_fade_enabled = true
		light.distance_fade_begin = LIGHT_DISTANCE_FADE_BEGIN
		light.distance_fade_length = LIGHT_DISTANCE_FADE_LENGTH
		light.distance_fade_shadow = true
	light.transform = _dict_to_transform(info)
	if light is SpotLight3D or light is DirectionalLight3D:
		# UE5 spotlights/directionals aim along +X; Godot aims along -Z
		light.rotate_object_local(Vector3.UP, -PI * 0.5)
	return light


## Guildhall safe-room lower floor (todo 4 repair). Verdict MISSING-UPSTREAM:
## re-surveyed post-extract (2026-11-21) in Guildhall_PeripheryA around the
## suite gap coordinate (126.0, 18.56, -10.43): no floor-like mesh within 6 m
## at y < 18.5, only SM_Urban_Foundation walls at y=12 (7.1-7.9 m away); the
## closest floor-like meshes are GB_Cube_6m at 10.18 m and GB_Floor_6x6 at
## 10.43 m (y=18.0). The task-2 greybox pieces (GB_Floor_2x2 x3, GB_Floor_3x2
## x1, 1m_Plane_Reverse x3, SM_FloorConcreteB_4x4 x78) live in the
## Guildhall_Geometry sublevel frame (~160 m away) and already bind through
## the generic mesh path where present, so they are not a lower floor for
## this gap. The Heightmap_6.png tile is flat h16=33774 across the gap, i.e.
## world y = 10.7 + (33774-32768)/128 = 18.56: the discard_holes=0 fill
## renders as a flat plane exactly at the gap coordinate, 6 m below the 24.5
## walkway and level with the wall bases (ext walls based 18.5, foundations
## top out at 12+6=18). One authored slab closes the architectural gap; its
## top sits 0.06 proud of the fill so the two surfaces never z-fight. Probe
## safety: suite 10 steps DOWN through non-landscape hits to
## LandscapeCollision_12 at 18.56, so a slab top at 18.62 still lands the
## probes on the landscape (restart at hit.y-0.05=18.57 sees the 18.56
## landscape 0.01 below before the slab exit 0.05 below).
const GUILDHALL_SAFEROOM_FLOOR_POS: Vector3 = Vector3(126.0, 18.52, -10.43)
const GUILDHALL_SAFEROOM_FLOOR_SIZE: Vector3 = Vector3(8.0, 0.2, 8.0)
## Builds the single authored safe-room slab for guildhall loads only (the
## map_hint derives from the level JSON paths, so a renamed source still
## builds it and the source-vs-map mismatch push_error below still fires).
## No-op for every other map; runs once per load via the ctx guard.
func _build_guildhall_saferoom_floor(parent: Node3D, ctx: Dictionary) -> void:
	if str(ctx.get("map_hint", "")) != "guildhall":
		return
	if bool(ctx.get("saferoom_floor_built", false)):
		return
	ctx["saferoom_floor_built"] = true
	var slab := BoxMesh.new()
	slab.size = GUILDHALL_SAFEROOM_FLOOR_SIZE
	slab.material = _landscape_material(ctx, "Guildhall")
	var mi := MeshInstance3D.new()
	mi.name = "GuildhallSafeRoomFloor"
	mi.mesh = slab
	mi.position = GUILDHALL_SAFEROOM_FLOOR_POS
	parent.add_child(mi)
	if not bool(ctx.get("generate_collision", false)):
		return
	var shape := BoxShape3D.new()
	shape.size = GUILDHALL_SAFEROOM_FLOOR_SIZE
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var body := StaticBody3D.new()
	body.name = "GuildhallSafeRoomFloorBody"
	body.collision_layer = 1
	body.position = GUILDHALL_SAFEROOM_FLOOR_POS
	body.add_child(cs)
	parent.add_child(body)
	ctx["collision_bodies"] = int(ctx.get("collision_bodies", 0)) + 1
	ctx["collision_shapes"] = int(ctx.get("collision_shapes", 0)) + 1


## Builds the real layer-blended landscape material from the component's
## WeightmapTextures + WeightmapLayerAllocations. Returns null when the
## component has no weightmap or no resolvable layer, so the caller falls back
## to the single-surface material.
func _landscape_weighted_material(lc: Dictionary, map_hint: String = "") -> ShaderMaterial:
	var wm_paths: Array = []
	var wm_raw: Variant = lc.get("weightmaps", [])
	if wm_raw is Array:
		wm_paths = wm_raw as Array
	var wm_path: String = str(wm_paths[0]) if wm_paths.size() > 0 else ""
	if wm_path == "":
		wm_path = str(lc.get("weightmap", ""))
	if wm_path == "" or not (FileAccess.file_exists(wm_path) or ResourceLoader.exists(wm_path)):
		return null
	var wm: Texture2D = _load_tex(wm_path)
	if wm == null:
		return null
	var wm1: Texture2D = null
	if wm_paths.size() > 1:
		var wm1_path: String = str(wm_paths[1])
		if wm1_path != "" and (FileAccess.file_exists(wm1_path) or ResourceLoader.exists(wm1_path)):
			wm1 = _load_tex(wm1_path)
	# Layers allocated to a weightmap that is not bound cannot be sampled, so
	# they are skipped instead of reading an empty second weightmap.
	var bound_count: int = 2 if wm1 != null else 1
	var source: String = str(lc.get("source", ""))
	# L5: the old rule keyed the safe-room fill on a map-name substring of
	# the source, so a renamed source silently reopened the void. The caller
	# passes map_hint (derived from the level JSON path); an explicit hint
	# wins, the source scan is the fallback, and a disagreement between them
	# is a loud error naming both — the rename detector the old match lacked.
	var source_low_guildhall: bool = source.to_lower().contains("guildhall")
	var hint_guildhall: bool = map_hint == "guildhall"
	if map_hint != "" and hint_guildhall != source_low_guildhall:
		push_error("[level_loader] discard_holes source/map mismatch: source '", source, "' says guildhall=", source_low_guildhall, " but map_hint='", map_hint, "' says ", hint_guildhall, "; trusting the explicit hint")
	var is_guildhall_fill: bool = hint_guildhall or (source_low_guildhall and map_hint == "")
	if wm_paths.size() > 2:
		push_warning("Landscape %s: %d weightmaps extracted but only %d bound; extra weightmaps are not sampled" % [source, wm_paths.size(), bound_count])
	var mat := ShaderMaterial.new()
	mat.shader = LANDSCAPE_SHADER
	# Guildhall's packed floors are incomplete at the safe-room gap; the
	# extracted data has no lower-floor mesh within 6 m of that visibility hole
	# (only foundation walls at y=12). Keep the authored landscape surface
	# visible there instead of discarding to void. Other maps keep hole discard.
	mat.set_shader_parameter("discard_holes", 0.0 if is_guildhall_fill else 1.0)
	mat.set_shader_parameter("weightmap", wm)
	if wm1 != null:
		mat.set_shader_parameter("weightmap_1", wm1)
	var slot: int = 0
	var layer_i: int = -1
	for l_var: Variant in (lc.get("layers", []) as Array):
		layer_i += 1
		if not (l_var is Dictionary):
			continue
		var l: Dictionary = l_var
		var lname: String = str(l.get("layer", ""))
		var channel: int = int(l.get("channel", 0))
		var tex_idx: int = int(l.get("tex", 0))
		if tex_idx < 0 or tex_idx >= bound_count:
			push_warning("Landscape %s: layer '%s' (index %d) skipped, weightmap index %d is unbound (%d bound)" % [source, lname, layer_i, tex_idx, bound_count])
			continue
		if lname == "Puddle":
			mat.set_shader_parameter("puddle_tex_idx", tex_idx)
			mat.set_shader_parameter("puddle_channel", channel)
			var pn: Texture2D = _load_tex("res://assets/ue/Raw/Art/Effects/Puddles/T_Decal_Puddle_1_Normal.png")
			var po: Texture2D = _load_tex("res://assets/ue/Raw/Art/Effects/Puddles/T_Decal_Puddle_1_Opacity.png")
			if pn != null:
				mat.set_shader_parameter("puddle_normal", pn)
			if po != null:
				mat.set_shader_parameter("puddle_opacity", po)
			continue
		if lname == "GroundWet":
			mat.set_shader_parameter("groundwet_tex_idx", tex_idx)
			mat.set_shader_parameter("groundwet_channel", channel)
			continue
		var is_visibility: bool = lname.to_lower().contains("visibility")
		if is_visibility:
			# Visibility is a mask, not an albedo layer, so it must not consume
			# one of the five colour slots.
			mat.set_shader_parameter("visibility_tex_idx", tex_idx)
			mat.set_shader_parameter("visibility_channel", channel)
			continue
		if slot >= 5:
			continue
		var tex_path: String = str(LANDSCAPE_LAYER_TEX.get(lname, ""))
		if tex_path == "":
			continue
		var tex: Texture2D = _load_tex(tex_path)
		if tex == null:
			continue
		mat.set_shader_parameter("layer_tex_%d" % slot, tex)
		mat.set_shader_parameter("layer_channel_%d" % slot, channel)
		mat.set_shader_parameter("layer_tex_idx_%d" % slot, tex_idx)
		slot += 1
	if slot == 0:
		return null
	mat.set_shader_parameter("uv_scale", 12.0)
	return mat


func _landscape_material(ctx: Dictionary, source: String = "") -> StandardMaterial3D:
	var cached: StandardMaterial3D = ctx.get("landscape_mat") as StandardMaterial3D
	if cached != null:
		return cached
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	# Guildhall's MI_Landscape TextureStreamingData names T_RoadBricksA_H, so
	# its street surface uses the matching road-brick D/N maps. Other maps keep
	# the cobble fallback until their own landscape layer textures are resolved.
	var use_road: bool = source.to_lower().contains("guildhall")
	var road_dir: String = "res://assets/ue/Raw/MaterialLibrary/Environment/Stone/FloorExterior/"
	var cobble_dir: String = "res://assets/ue/Raw/MaterialLibrary/Legacy/"
	var ground_alb: Texture2D = null
	var ground_norm: Texture2D = null
	if use_road:
		ground_alb = _load_tex(road_dir + "T_RoadBricksA_D.png")
		ground_norm = _load_tex(road_dir + "T_RoadBricksA_N.png")
	if ground_alb == null:
		ground_alb = _load_tex(cobble_dir + "T_CobbleStoneA_D.png")
	if ground_norm == null:
		ground_norm = _load_tex(cobble_dir + "T_CobbleStoneA_N.png")
	if ground_alb == null:
		ground_alb = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Nature/Dirt/T_GroundDirtA_D.png")
	if ground_alb != null:
		mat.albedo_texture = ground_alb
	if ground_norm != null:
		mat.normal_enabled = true
		mat.normal_texture = ground_norm
		mat.normal_scale = 0.8
	mat.albedo_color = Color(0.72, 0.70, 0.66) if use_road else Color(0.42, 0.42, 0.40)
	mat.roughness = 0.90
	mat.uv1_scale = Vector3(12.0, 12.0, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ctx["landscape_mat"] = mat
	return mat


## Builds one LandscapeComponent heightfield mesh. Each component gets its own
## StaticBody3D so a single landscape never becomes a massive compound body.
func _build_one_landscape(lc_var: Variant, parent: Node3D, ctx: Dictionary) -> void:
	if not (lc_var is Dictionary):
		return
	var lc: Dictionary = lc_var as Dictionary
	var hpath: String = str(lc.get("heightmap", ""))
	if hpath == "":
		return
	if not FileAccess.file_exists(hpath) and not ResourceLoader.exists(hpath):
		return
	var img: Image = null
	var htex: Texture2D = _load_tex(hpath)
	if htex != null:
		img = htex.get_image()
	if img == null or img.is_empty():
		if FileAccess.file_exists(hpath):
			img = Image.load_from_file(hpath)
	if img == null or img.is_empty():
		return
	var weighted: ShaderMaterial = _landscape_weighted_material(lc, str(ctx.get("map_hint", "")))
	var mat: Material = weighted
	if mat == null:
		mat = _landscape_material(ctx, str(lc.get("source", "")))
	var iw: int = img.get_width()
	var ih: int = img.get_height()
	var quads: int = int(lc.get("quads", 63))
	var sb: Array = lc.get("scale_bias", [1.0 / 64.0, 1.0 / 64.0, 0.0, 0.0])
	var sx_b: float = float(sb[0]) if sb.size() > 0 else 1.0 / 64.0
	var sy_b: float = float(sb[1]) if sb.size() > 1 else 1.0 / 64.0
	var ox_b: float = float(sb[2]) if sb.size() > 2 else 0.0
	var oy_b: float = float(sb[3]) if sb.size() > 3 else 0.0

	var tr_raw: Transform3D = _dict_to_transform(lc)
	var sc_raw: Variant = lc.get("scale", [100.0, 100.0, 100.0])
	var sc_arr: Array = sc_raw if sc_raw is Array else [100.0, 100.0, 100.0]
	# UE LandscapeComponent scale is 100.0 (= 1m per quad); read raw scale
	# directly so _dict_to_transform()'s 40.0 clamp does not shrink 63m tiles to 25.2m.
	var sx_raw: float = float(sc_arr[0]) if sc_arr.size() > 0 and sc_arr[0] != null else 100.0
	var sy_raw: float = float(sc_arr[1]) if sc_arr.size() > 1 and sc_arr[1] != null else 100.0
	var sz_raw: float = float(sc_arr[2]) if sc_arr.size() > 2 and sc_arr[2] != null else 100.0
	var step_x: float = absf(sx_raw) * 0.01
	var step_y: float = absf(sy_raw) * 0.01
	var step_z: float = absf(sz_raw) * 0.01
	if step_x < 0.05:
		step_x = 1.0
	if step_y < 0.05:
		step_y = 1.0
	if step_z < 0.05:
		step_z = 1.0

	var heights: Array[float] = []
	var stride: int = quads + 1
	heights.resize(stride * stride)
	# Level-loader per-texel loop: (stride+1)^2 get_pixel calls per landscape
	# component on the load path. Bulk-read the bytes when the layout is known
	# (RG8/RGB8/RGBA8, uncompressed) — byte-identical to get_pixel — with a
	# size guard + get_pixel fallback so an odd format can never corrupt.
	var bulk_stride: int = 0
	var bulk_data: PackedByteArray = PackedByteArray()
	if not img.is_compressed():
		match img.get_format():
			Image.FORMAT_RG8:
				bulk_stride = 2
			Image.FORMAT_RGB8:
				bulk_stride = 3
			Image.FORMAT_RGBA8:
				bulk_stride = 4
		if bulk_stride > 0:
			var raw_bytes: PackedByteArray = img.get_data()
			if raw_bytes.size() >= iw * ih * bulk_stride:
				bulk_data = raw_bytes
			else:
				bulk_stride = 0
	for vy: int in range(stride):
		for vx: int in range(stride):
			var px: int = clampi(int(round((float(vx) * sx_b + ox_b) * float(iw))), 0, iw - 1)
			var py: int = clampi(int(round((float(vy) * sy_b + oy_b) * float(ih))), 0, ih - 1)
			var h16: int
			if bulk_stride > 0:
				var bo: int = (py * iw + px) * bulk_stride
				h16 = (int(bulk_data[bo]) << 8) | int(bulk_data[bo + 1])
			else:
				var c: Color = img.get_pixel(px, py)
				h16 = (c.r8 << 8) | c.g8
			var h_val: float = ((float(h16) - 32768.0) / 128.0) * step_y
			heights[vy * stride + vx] = h_val

	var faces: PackedVector3Array = PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for qy: int in range(quads):
		for qx: int in range(quads):
			var p00 := Vector3(float(qx) * step_x, heights[qy * stride + qx], float(qy) * step_z)
			var p10 := Vector3(float(qx + 1) * step_x, heights[qy * stride + (qx + 1)], float(qy) * step_z)
			var p01 := Vector3(float(qx) * step_x, heights[(qy + 1) * stride + qx], float(qy + 1) * step_z)
			var p11 := Vector3(float(qx + 1) * step_x, heights[(qy + 1) * stride + (qx + 1)], float(qy + 1) * step_z)
			var u00 := Vector2(float(qx) / float(quads), float(qy) / float(quads))
			var u10 := Vector2(float(qx + 1) / float(quads), float(qy) / float(quads))
			var u01 := Vector2(float(qx) / float(quads), float(qy + 1) / float(quads))
			var u11 := Vector2(float(qx + 1) / float(quads), float(qy + 1) / float(quads))
			st.set_uv(u00); st.add_vertex(p00)
			st.set_uv(u11); st.add_vertex(p11)
			st.set_uv(u10); st.add_vertex(p10)
			st.set_uv(u00); st.add_vertex(p00)
			st.set_uv(u01); st.add_vertex(p01)
			st.set_uv(u11); st.add_vertex(p11)
			faces.append(p00); faces.append(p11); faces.append(p10)
			faces.append(p00); faces.append(p01); faces.append(p11)
	st.generate_normals()
	var arr_mesh: ArrayMesh = st.commit()
	if arr_mesh == null:
		return
	arr_mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = arr_mesh
	mi.transform = Transform3D(tr_raw.basis.orthonormalized(), tr_raw.origin)
	parent.add_child(mi)

	if bool(ctx.get("generate_collision", false)) and not faces.is_empty():
		var cshape := ConcavePolygonShape3D.new()
		cshape.backface_collision = true
		cshape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = cshape
		cs.transform = Transform3D(tr_raw.basis.orthonormalized(), tr_raw.origin)
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "LandscapeCollision_%d" % int(ctx.get("landscapes_built", 0))
		body.collision_layer = 1
		body.add_child(cs)
		parent.add_child(body)
		ctx["collision_bodies"] = int(ctx.get("collision_bodies", 0)) + 1
		ctx["collision_shapes"] = int(ctx.get("collision_shapes", 0)) + 1
		# T6 accounting: landscape colliders always emit (no cap check, no
		# silent drop); counted against the building partition like volumes.
		ctx["building_shapes"] = int(ctx.get("building_shapes", 0)) + 1
	ctx["landscapes_built"] = int(ctx.get("landscapes_built", 0)) + 1
