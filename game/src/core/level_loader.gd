extends Node
## High-performance UE5 -> Godot 4.7 level builder.
## Loads extracted .tatlevel.json sublevels, batches repeated .glb meshes into MultiMeshInstance3D,
## binds real PBR materials (Albedo/Normal/ORM) from materials.json + mesh_materials.json,
## generates StaticBody3D collision, and extracts real spawn/guard/loot/escape markers.

const _VfxManager: GDScript = preload("res://src/core/vfx_manager.gd")
const MobileProfile: GDScript = preload("res://src/core/mobile_profile.gd")
const WeatherProfile: GDScript = preload("res://src/core/weather_profile.gd")
## W9-P1: authored UE `AggGeom` collision (TAT2_COLLISION=authored, default).
const AuthoredCollision: GDScript = preload("res://src/core/collision/authored_collision.gd")
const NiagaraParams: GDScript = preload("res://src/core/vfx/niagara_params.gd")
const NiagaraLibrary: GDScript = preload("res://src/core/vfx/niagara_library.gd")
const NiagaraCuller: GDScript = preload("res://src/core/vfx/level_niagara_culler.gd")
const LANDSCAPE_SHADER: Shader = preload("res://src/core/tat_landscape.gdshader")
const EMISSIVE_CPD_SHADER: Shader = preload("res://src/core/tat_emissive_cpd.gdshader")
const GLASS_SHADER: Shader = preload("res://src/core/tat_glass.gdshader")
const HDR_EMISSIVE_SHADER: Shader = preload("res://src/core/tat_hdr_emissive.gdshader")
const STOREFRONT_DECAL_SHADER: Shader = preload("res://src/core/tat_storefront_decal.gdshader")
const BEAM_SHADER: Shader = preload("res://src/core/tat_beam.gdshader")

## Authored security beam cards (Guildhall 134 + Old Manor 196 in the *_Gameplay
## sublevels). The UE StaticMesh bounds are X -0.1..10.1 cm (a 10.2 cm long axis
## on the mesh's local X) and Y/Z +-50.04 cm (the 1 m additive cross width).
## The SM_LightBeam component is authored with RelativeRotation.Yaw = 90, so on
## the detector the mesh's local X lies along the actor's local +Z, which is the
## merged record/device basis **column 2**. The blueprint writes the authored
## span as a length scale of 24.5..236.9539 in record scale slot 2.
##
## The old path scaled column 0 (the 1 m cross axis), so all 330 cards rendered
## as a cross-beam bar 90 deg off the authored direction. This exact-path
## transform rotates the card's local X onto col2 and applies slot 2 there.
## There is deliberately no ceiling: the old 40 m clamp clipped 129/134
## Guildhall cards and the later 200 ceiling clipped 5/196 Old Manor cards
## (max authored 236.9539 = 24.169 m). Record path is exact so no other mesh
## changes scale/clamp behaviour.
const BEAM_CARD_MESH: String = "/Game/Art/Effects/LightBeam/SM_LightBeam"
const BEAM_CARD_LEN_M: float = 0.102

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
## W10-A3-GC: owner actor name -> {"leaves": Array[Node3D],
## "broken": Array[Node3D]} for the destructible overlays built by this load.
## Chests/display cases own one emitted leaf; a bookcase owns two doors whose
## intact glass panes are existing static-batch nodes (Phase 2 G-2), so the
## arrays are plural by authored design. Rebuilt per load; the loot containers
## read it once in `_ready` through `gc_visuals_for()`.
var _gc_owner_index: Dictionary = {}
## Phase 2 G-2: intact bookcase glass nodes created by the static batch for this
## load, as {node, source_sublevel, used}. Resolved into the owner index after
## the draw items exist (nearest unused node within the measured radius).
var _gc_static_glass: Array[Dictionary] = []
var _mesh_mats_db: Dictionary = {}
var _mesh_mats_db_lower: Dictionary = {}
## P0b parity-only load state (TAT2_PARITY_ONLY=1, default off). Resolved once
## per build in `_new_build_ctx`; `_content_rule_classes` is the tracked
## rule id -> parity_class map used to classify content-override-tagged meshes
## when the generated payload predates the `content_parity_class` field.
var _parity_only: bool = false
var _content_rule_classes: Dictionary = {}
var _tex_cache: Dictionary = {}
var _std_mat_cache: Dictionary = {}
var _mesh_res_cache: Dictionary = {}
## W9-P1: per-load placement count per UE path (filled by `_build_draw_items`);
## only the authored-collision cost cap reads it, so a dense mesh can choose a
## coalesced encoding without any per-instance work.
var _col_path_counts: Dictionary = {}
## W9-P1 hard guard: a malformed authored payload (or a future regression) must
## never wedge a headless run on the shared Godot lock. A probe sets an absolute
## `Time.get_ticks_msec()` deadline; collider emission stops at it and reports
## `col_deadline_hit` instead of continuing. `_col_progress` prints one line
## every 128 collision paths so a wedge is localised to the last mesh name.
var _col_deadline_ms: int = 0
var _col_progress: bool = false
## SM_Guildhall_Sign split-mesh cache (ue_path -> ArrayMesh).
var _guildhall_sign_split_cache: Dictionary = {}
var _prof_glb_ms: int = 0
var _prof_mat_ms: int = 0
var _prof_shape_ms: int = 0 # ue_path -> { "mesh": Mesh, "shape": Shape3D }
## L1/L2 sentinels: corrupt imports (resolved path, failed load) are tracked
## separately from missing meshes so a broken GLB never hides in the missing
## list; substring-guess fallback materials are tiered + counted. Export
## gates read these via _finalize (meshes_ok).
var corrupt_meshes: Array[String] = []
var corrupt_mesh_count: int = 0
var fallback_materials: Array[String] = []
var fallback_material_count: int = 0
## W10-P2 cream fix: a material that authors EmissiveStrength but neither an
## EmissiveColor nor an emissive map used to receive an invented WHITE emission
## (the cream-slab class). It now gets no emission and is counted here. This is
## the `tat_invented_white` census the cream proof reads.
var invented_white_materials: Array[String] = []
var _invented_white_count: int = 0
## Authored flat-colour binds (tint present, no albedo map). Counted so the
## "untextured but correct" population is visible; near-white ones are named
## and warned separately (L2-03: debug primitives rendered as flat white).
var flat_colour_materials: Array[String] = []
var flat_colour_material_count: int = 0
## Empty-authoring slots rescued by a unique surface-name match (see
## _slot_name_fallback). Zero on the shipped data set; any growth is a warning.
var slot_name_fallback_count: int = 0
var slot_name_fallback_names: Array[String] = []
var _override_mesh_cache: Dictionary = {} # ue_path + "||" + ov_key -> Mesh
var _emissive_cpd_mat: ShaderMaterial = null
## W6L: roof top-coverage measurements, keyed by lower-case UE path. The public
## roof_collision_kind() one-arg form needs the measured geometry, and a mesh
## cannot be measured twice per load for free.
var _roof_geom_cache: Dictionary = {}
## W7G: roughness remap textures are cached process-wide, keyed by
## "orm_path|low|high". W6L keyed the same way per loader instance, so a second
## live loader (or a mission reload while another loader still exists) re-baked
## the same 0.15..1.0 ramp. One L8 texture per authored range, not one per
## material: several MIs bind the same ORM at different ranges. The cache is
## cleared by the teardown path once the last live loader leaves the tree.
static var _roughness_global_cache: Dictionary = {}
## Number of LevelLoader nodes currently in the tree. The process cache is
## released only when this reaches 0, so a concurrent loader never loses a bake.
static var _roughness_live_loaders: int = 0
## One-time TAT2_ROUGH_BAKE resolution, so an invalid value is reported once per
## process instead of once per material.
static var _roughness_mode: String = ""
## W6L/W7G bake accounting (one ROUGHNESS_BAKE line per map load): the exact
## low + g*(high-low) bake is a one-time cost, measured instead of guessed.
## `bytes` counts the L8 texture + its mip chain, `hits` are process-cache
## reuses (no rebake). Full resolution is retained: no half-res path exists.
var _roughness_bake_count: int = 0
var _roughness_bake_px: int = 0
var _roughness_bake_ms: int = 0
var _roughness_bake_bytes: int = 0
var _roughness_cache_hits: int = 0
## SM_LightBeam transform accounting: one BEAM_FIX + one BEAM_AXIS line at
## settle. `_beam_fix_max_axis_err_deg` is the worst angle between the applied
## card long axis and the authored record col2; `_beam_fix_max_len_err` is the
## worst relative rewrite of the authored length scale; `_beam_fix_clamped`
## counts any card whose authored scale was not applied verbatim (must be 0).
var _beam_fix_count: int = 0
var _beam_fix_max_scale: float = 0.0
var _beam_fix_max_axis_err_deg: float = 0.0
var _beam_fix_max_len_err: float = 0.0
var _beam_fix_clamped: int = 0
# RE-P-10/08 accounting: the [0.05, 40] scale clamp and the reflected
# (det < 0) bases used to be silent. Counted, never silently rewritten.
var _scale_clamp_count: int = 0
var _scale_clamp_worst: float = 1.0
# `_mirrored_basis_count` is the placement-transform census: every
# `_dict_to_transform()` call with det < 0, including decals and GC overlays.
# It is kept for the RE-P-08 probes. The draw-item census (`_mirror_draw_bases`)
# is the render-relevant one and is reconciled against the split batches below.
var _mirrored_basis_count: int = 0
## P4.2 mirror split. A UE placement with a reflected basis (determinant < 0)
## is authored art, not a defect. Godot compensates a negative-determinant
## `MeshInstance3D` by flipping its cull face, but a `MultiMesh` has no
## per-instance cull state (and no surface override in 4.7.2), so a mirrored
## MultiMesh batch renders its one-sided faces from the wrong side. Negative
## instances therefore get their own batch drawn from a mesh baked with a
## local-X reflection: vertices x negated, triangle winding reversed, normals
## x negated and tangent x/w negated (the handedness term). The instance basis
## is right-multiplied by the same reflection so det(instance) > 0 and the
## engine adds no second flip:
##   B' = B * S,  M' = S * M,  B' * M' = B * M.
## A single-surface `BaseMaterial3D` mesh uses a cloned `CULL_FRONT` material
## instead (no mesh copy); the shared source material is never mutated. A
## two-sided source already renders mirrored correctly and keeps its material.
## Standalone mirrored `MeshInstance3D` keep Godot's native compensation by
## default; `TAT2_MIRROR_SINGLE=baked` opts into the bake if the synthetic
## `build/qa/mirror_probe.sh --run` readback proves the engine does not
## compensate. `TAT2_MIRROR_FAST=off` disables the cull-front fast path.
const MIRROR_LOCAL_FLIP: Basis = Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
const MIRROR_LOG_LIMIT: int = 64
var _mirror_variant_cache: Dictionary = {}
var _mirror_cull_front_cache: Dictionary = {}
var _mirror_draw_bases: int = 0
var _mirror_batches_split: int = 0
var _mirror_multimesh_instances: int = 0
var _mirror_single_instances: int = 0
var _mirror_cull_front_instances: int = 0
var _mirror_cull_disabled_instances: int = 0
var _mirror_mesh_bytes: int = 0
var _mirror_mesh_count: int = 0
var _mirror_unbaked: int = 0
var _mirror_log_count: int = 0
var _mirror_log_suppressed: int = 0
var _mirror_warned: Dictionary = {}

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
## The only DXT1 texture in the extracted tree with real punch-through alpha
## (7,611 transparent pixels at 4096²). Import/runtime downscaling blends every
## transparent pixel to alpha 1.0, so the storefront glass-decal cutout must
## stay at authored resolution even when TAT2_TEX_CAP requests a smaller cap.
## Mirrors tools/prebake_texture_cap.py ALPHA_CRITICAL_PATHS.
const ALPHA_CRITICAL_TEXTURES: Array[String] = [
	"res://assets/ue/Raw/Art/Environment/Storefront/GlassDecals/T_Storefront_GlassDecalsA.png",
]
## Authored Niagara activation is per component (`NiagaraComponent.bAutoActivate`),
## not a name blacklist: see `game/src/core/vfx/niagara_params.gd`. The old
## one-entry table survives only as documentation of the system it covered.
const NIAGARA_INACTIVE_ASSETS: Array[String] = [
	"ns_candelabras_flame_out",
]
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
## keep the larger share; curb ribbons emit 3 boxes per segment across at most
## CURB_MAX_SPLINES (64) splines. The partitions sum exactly to
## MAX_TOTAL_SHAPES, so the global cap still holds as a backstop.
##
## W9-P1 authored collision (measured on the 15-file Guildhall ground set,
## `build/qa/w9_collision_ab.sh`): the authored AggGeom needs 30,873 building
## shapes (+27 curb, +1 landscape = 30,901 total) against the old 28,000/4,000
## split, so 4,000 curb slots for a partition that peaks at 27 would have
## dropped 2,873 authored colliders. Split moved to 31,400/600: 527 building
## shapes of headroom over the measurement (>= 512) and 22x the measured curb
## peak. MAX_TOTAL_SHAPES stays 32,000 and the `run_tests` invariant
## (`col_shapes < 32000`) is unchanged. The FTUE map keeps its own pair below.
const MAX_BUILDING_SHAPES: int = 31400
# FTUE is a whole-city tutorial map: 34,201 authored meshes against the 31,400
# default. Raising the budget for this map (logged, never silent) keeps every
# gameplay collider and the safe-room start instead of dropping 6,201 shapes.
const MAX_BUILDING_SHAPES_FTUE: int = 40000
const MAX_TOTAL_SHAPES_FTUE: int = 44000
const MAX_CURB_SHAPES: int = 600
const LIGHT_DISTANCE_FADE_BEGIN: float = 28.0
const LIGHT_DISTANCE_FADE_LENGTH: float = 12.0
const PROGRESS_YIELD_EVERY: int = 64

## W1p structural perf prototypes. Every lever is off unless the named
## environment variable asks for it, so the shipped look/behaviour is unchanged.
## The QA harness owns the A/B runs; these are not quality presets.
const ENV_PERIPH_RANGE: String = "TAT2_PERIPH_RANGE"
const ENV_MERGE_CELLS: String = "TAT2_MERGE_CELLS"
const ENV_PERF_CENSUS: String = "TAT2_PERF_CENSUS"
const PERIPH_RANGE_CHOICES: Array[int] = [0, 100, 120, 150]
## Same 32 m cell radius pad used by the prop culling policy: visibility_range
## is measured from the merged chunk AABB centre, so a cell corner may be half
## a cell farther away than the authored range.
const PERIPH_RANGE_PAD: float = CHUNK_SIZE * 0.5
## Merge-cell prototype exclusions. These meshes are addressed individually by
## gameplay/cutscene code (door leaves, loot containers, devices, landmarks and
## the authored mission props below), so folding them into a cell mesh would
## make their MeshInstance3D lookups fail. Plain static masonry/props are the
## only merge candidates.
const MERGE_EXCLUDE_TOKENS: Array[String] = [
	"door", "gate", "loot", "chest", "displaycase", "lockbox", "clue",
	"device", "landmark", "interactable", "spawner", "marker", "portal",
	"switch", "lever", "button", "hatch", "elevator",
	"guildhall_sign", "map_thievesden", "automobile_lights",
	"knockoutgrenade", "sm_truncheon",
]
## ShaderMaterial is only mergeable when its shader is certified opaque here.
## The loader's transparent/additive shaders (tat_glass, tat_beam, decals,
## neon/HDR emission) are intentionally absent; StandardMaterial3D surfaces
## carry the static city. Adding a shader to this list is a visual review.
const MERGE_OPAQUE_SHADERS: Array[String] = []

## L6: rect-light quad emission shares constants with its omni. The quad
## used a disconnected 2.0 energy while its omni faded with distance — glow
## without light at range. Energy stays 2.0 (authored look) but the quad now
## fades over LIGHT_DISTANCE_FADE_* like its omni, so the two cannot desync.

## Authored UE light intensity -> Godot light_energy.
## There is no faithful lumen/candela -> Godot `light_energy` conversion for
## these stylized authored values (Guildhall spans 0.01..2500, median 15).
## The old linear-scale-plus-hard-ceiling mapping flattened every authored
## value above 60 lumens to the same 4.0 energy: 90th percentile (50) still
## read as 3.33, 95th (150) and the 2500-lumen security spots all read 4.0.
## That erased the authored hierarchy exactly where the practicals and
## security lights need to stay distinguishable.
##
## Replacement: a monotonic sqrt response with a smooth (tanh) shoulder,
## anchored so the median authored intensity (15.0) is energy 1.0. The sqrt
## lifts the dark end (3 lumens -> 0.46 instead of 0.20, 0.5 -> 0.185 instead
## of 0.033) while the shoulder compresses the top (150 -> 2.59, 300 -> 3.07,
## 2500 -> 3.56 instead of a flat 4.0). No branch, no hard discontinuity; the
## mapping is strictly increasing across the whole 0.01..2500 range.
const LIGHT_MEDIAN_INTENSITY: float = 15.0
const LIGHT_ENERGY_FLOOR: float = 0.01
## Smooth asymptotic shoulder, not a clamp. 3.5 keeps the top practicals and
## the 2500-lumen train/security spots from stacking into a white blob while
## leaving the 15-lumen median at 1.0.
const LIGHT_ENERGY_SOFT_CEIL: float = 3.5


## Den-only authored practical pass-through (FIX_SPEC P0 #1). The five
## ThievesDen_Geo spots keep their authored 0.75x intensity response,
## inverse-square attenuation and true cones (including the 5 deg moon).
## The global mapping above and the 18 deg floor stay untouched for every
## other map (Suite 23 / T2-02 still exercise the global curve).
const DEN_SPOT_ENERGY_SCALE: float = 0.75
const DEN_SPOT_ATTENUATION: float = 2.0
## Den LumenSkylightLeaking stand-in: 0.10 / 10 m / attenuation 1.5 replaces
## the flat 0.27 / 17.5 m / 0.4 blue wash that veiled the whole attic.
const DEN_GI_FILL_ENERGY: float = 0.10
const DEN_GI_FILL_RANGE: float = 10.0
const DEN_GI_FILL_ATTENUATION: float = 1.5
const DEN_GI_FILL_COLOR: Color = Color(0.55, 0.70, 0.92)
## Authored gold lamp glass (MI_LightSmGlassA_Gold): EmissiveTintB warm value
## and the authored 2.2 multiplier instead of a white 16x clip.
const DEN_GOLD_LAMP_EMISSION: float = 2.2
## W6L two-tone emissive policy. When a material has no EmissiveColor but does
## carry the authored EmissiveTintA/B pair (Two Tone Emissive gradient), the
## old lookup fell through to white and multiplied it by the authored
## EmissiveStrength: a 50x clip for MI_LightSmGlassA_*, 11x for the guard
## lantern, 110x+ for the large lamps. The lit tone is the brighter of the two
## authored ends (B for the warm glass families, A where B is authored off),
## and each family carries an energy ceiling so the lamp reads as a lamp and
## never as a pure-white bloom sheet. No material may emit pure white above 4.
const GLASS_EMISSION_CAP: float = 3.0
const GUARD_LANTERN_EMISSION_CAP: float = 1.6
const LARGE_LAMP_EMISSION_CAP: float = 2.5
const EMISSIVE_ENERGY_CEIL: float = 4.0
## W6L foliage gate. MSM_Subsurface is not proof of foliage: the WANTED
## posters, decals, coins, scrolls, candles and slime bubbles all inherit it
## from a masked/subsurface master, so backlight was standing in for a
## translucent edge and painting those flat cards from behind. Only authored
## foliage (TwoSidedFoliage shading, or a foliage/bark/leaf token in the
## material path or its albedo) may take the backlight stand-in.
const FOLIAGE_TOKENS: Array[String] = [
	"leaves", "leaf", "needle", "foliage", "willow", "ivy", "vine", "moss",
	"fern", "plants", "shrub", "bush", "canopy", "branch", "bark",
]


## Monotonic authored-intensity -> energy mapping. See the constants above.
## Median 15.0 -> 1.0 exactly; the curve is continuous and strictly increasing
## over the whole authored range (the tanh shoulder never reaches the ceiling).
static func light_energy_for_intensity(raw: float) -> float:
	if raw <= 0.0:
		return LIGHT_ENERGY_FLOOR
	var x: float = raw / LIGHT_MEDIAN_INTENSITY
	var shaped: float = LIGHT_ENERGY_SOFT_CEIL * tanh(sqrt(x) / LIGHT_ENERGY_SOFT_CEIL)
	var median: float = LIGHT_ENERGY_SOFT_CEIL * tanh(1.0 / LIGHT_ENERGY_SOFT_CEIL)
	return maxf(shaped / median, LIGHT_ENERGY_FLOOR)
## Defensive guard only: authored AttenuationRadius values are 0.35-30 m, and
## the old 26 m clamp was clipping 24 legitimate 20-30 m lights. This ceiling
## exists so a corrupt authored radius cannot create an unbounded light.
const LIGHT_RANGE_CEIL: float = 200.0

## --- T07 P0: fair per-room light allocation --------------------------------
##
## The desktop budget is a hard node cap (MobileProfile.DESKTOP_MAX_LIGHTS = 160;
## the Guildhall already runs ~37 FPS at 1080p/high per
## docs/reports/w1p-structural-perf-prototype.md, so the cap is NOT raised here).
## What changes is *how* the cap is spent.
##
## The old policy ranked every deduped authored light by authored energy and cut
## at rank 159. On the Guildhall's 15-file load set that is 976 authored records
## -> 914 after the integer-position dedupe, cut at energy 1.2689 (authored
## 25.0 lm): it kept the 137 lights brighter than the median and evicted every
## ordinary room lamp. Result: 94 of 189 16 m room bubbles had NO light at all,
## even though 77 % of those bubbles author a 6-12 m practical that loses only
## because a 50-2500 lm fixture elsewhere on the map outranks it.
##
## The budget is now water-filled per room bubble: every occupied 16 m cell gets
## its own best authored light before any cell gets a second. Cells are served
## densest-first, so a 58-light hall is not starved by a one-candle closet while
## the map is over-subscribed (189 bubbles > 153 generic slots), and a map with
## fewer bubbles than slots (the Den, unit fixtures) simply takes more per cell.
const LIGHT_ROOM_CELL_M: float = 16.0

## Authored lights the budget must never evict, because a runtime contract (or
## the suite that pins it) requires the light node to exist.
##
## - **KF16 gate** (radius 10 m at `HERO_LIGHT_POINT`): the gate approach is lit
##   by six authored lights aimed away from the sign (two 20.0 uplights, two 4.1
##   omnis, two 20.0 Gameplay lights). They rank ~243-702 on authored energy, so
##   the old 160-light cut evicted all of them and the gate rendered dark.
## - **Contract-2 safe room** (radius 2 m): `Guildhall_PeripheryA` authors the
##   room's only fixture, an 88 deg wall spot (intensity 5.0, radius 9 m) at
##   (126.28, 27.14, -2.47). run_tests suite 10 requires that spot to be
##   instantiated, aimed -Z with its authored 88 deg cone; under per-room
##   allocation it lost its 16 m bubble to a brighter neighbour.
##
## Surviving candidates inside any radius are force-included after the hero
## shadow slots and are always shadowless.
const PROTECTED_LIGHT_POINTS: Array[Vector3] = [
	Vector3(10.0, 26.0, 49.8),
	Vector3(126.2758, 27.1426, -2.4736),
]
const PROTECTED_LIGHT_RADII: Array[float] = [10.0, 2.0]
const HERO_LIGHT_POINT: Vector3 = Vector3(10.0, 26.0, 49.8)
const HERO_LIGHT_RADIUS_M: float = 10.0
const HERO_LIGHT_MAP_HINT: String = "guildhall"

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

## Placed loot containers (chests / display cases / bookcases / wall safes /
## secret stashes): meshes are level geometry, so only the marker transform is
## kept for the openable wave. Phase 2 G-1 added the three K-06 classes the old
## 5-class allowlist dropped (8 Guildhall bookcases, 2 POI bookcases, 8 safes).
const LOOT_CONTAINER_CLASSES: Array[String] = [
	"BP_ChestTrunk_MajorLoot_C",
	"BP_DisplayCaseA_MajorLoot_C",
	"BP_LootStashInteractable_Secret_ThinWall_C",
	"BP_Storefront_DisplayCaseB_MinorLoot_C",
	"BP_Storefront_DisplayCaseD_MinorLoot_C",
	"BP_Manor_Bookcase_Cabinet_MinorLoot_C",
	"BP_Manor_Bookcase_Cabinet_MajorLoot_C",
	"BP_SmallSafe_MajorLoot_C",
]

## W10-A3-GC: destructible broken-state overlays (chests, display cases, glass).
## The producer emits one hidden `gc` layer per authored GeometryCollection and,
## for chests/display cases, one visible `gc_leaves` record for the intact lid /
## door. The runtime swaps them on `loot_container.break_container()`. `off`
## builds the same level without the layers so a probe can prove they add no
## collision.
const ENV_GC_LAYERS: String = "TAT2_GC_LAYERS"
const GC_ROOT_NAME: String = "GC_Destruction"
## Phase 2 G-2: the intact bookcase glass door is already in the static level
## batch. The authored broken overlay replaces only the glass pane
## (`SM_BookcaseB_GlassBrokenDoor`), so the loader binds the existing static
## node instead of emitting a duplicate leaf (a duplicate would double the
## transparent pane). The pane is split to one MeshInstance3D per instance so a
## single owner's door can be hidden; measured one-to-one with the broken
## overlay at 0.472 m, second-nearest >= 0.838 m -> 0.60 m is the unique match.
const GC_BOOKCASE_GLASS_MESH: String = "/Game/Art/Environment/Manor/SM_Manor_Bookcase_Cabinet_Door_Glass_2x8"
const GC_STATIC_LEAF_MATCH_M: float = 0.60


static func gc_layers_enabled() -> bool:
	var v: String = OS.get_environment(ENV_GC_LAYERS).to_lower()
	return v == "" or (v != "off" and v != "0" and v != "false")

## W9-P2 B2: authored lock keys carried 1:1 from a marker record into the
## `loot_containers`/`swinging_doors` record. The producer emits them only when
## the source actor authors them (`_locked`, `_lockConfig.MaxLockLevel` /
## `MinLockLevel` / `CanBeLockpicked`, `KeyTag.TagName`); a marker without them
## stays absent so the consumer default (unlocked) applies. No level is
## invented here: `max_lock_level` is the authored cap and the consumers label
## cap-as-level as a port decision.
const MARKER_LOCK_KEYS: Array[String] = [
	"locked", "max_lock_level", "min_lock_level", "can_lockpick", "key_tag",
]


static func marker_lock_fields(mk: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in MARKER_LOCK_KEYS:
		if mk.has(k):
			out[k] = mk[k]
	return out

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
## W5B: "roof" was in this list, and Guildhall_PeripheryA emitted 398 roof
## BoxOccluder3Ds. A pitched roof module's AABB is mostly air: the 44-46 deg
## SM_RoofUrban_Ext_Mid_4x4 covers 12.9 % of its box (measured from the GLB
## triangles), so the occluder culled the city behind a solid volume that does
## not exist and popped geometry in and out as the camera moved. Roof pieces
## are excluded by name now (below); walls/floors/ceilings keep their boxes.
## W6L: "stair" was an occluder candidate. A flight's AABB is a long, mostly
## empty ramp: SM_StairsCity4x2m boxes 4 x 2 m of air over the treads, so its
## occluder culled whatever stood behind the open underside. With roofs already
## excluded (W5B) those mostly-empty stair AABBs were the next class filling
## the freed MAX_OCCLUDERS slots. Stairs are excluded by *removing* the token
## here, so every remaining include token still has to prove a solid piece.
const OCCLUDER_INCLUDE_TOKENS: Array[String] = [
	"wall", "floor", "ceiling", "building", "pillar", "column", "block",
]
const OCCLUDER_EXCLUDE_TOKENS: Array[String] = [
	"window", "door", "glass", "gate", "archway", "arch_", "frame", "rail", "beam",
	"hole", "gap", "curtain", "drape", "cloth", "banner", "flag", "foliage", "leaf",
	"sky", "cloud", "fog", "smoke", "water", "carpet", "rug", "paper", "poster",
	"scroll", "cable", "wire", "rope", "ladder", "light", "lamp", "vent", "pipe",
	"trim", "deco", "panel",
	# W5B: pitched roof shells are 12.9 % filled AABBs (see above) and the
	# flat roof decks (GB_RoofFloor_*) are horizontal slabs a camera never
	# looks past, so no /roofs/ surface is an occluder. Walls still are.
	"roof",
	# Interior wall classes were the 768-occluder set in Guildhall (prison and
	# civic interior walls). Their AABBs span baked doorways, so rooms popped
	# in/out as the camera moved. Exterior walls remain valid occluders.
	"prison", "_int_", "interior",
]
## W5B roof collision policy. Roof modules under /roofs/ are pitched shells, so
## their AABB is not their shape: the box top of SM_RoofUrban_Ext_Mid_4x4
## (4.07 x 4.18 m footprint, 4.22 m rise, ~46 deg, the audit's 44 deg hip)
## stands 4.08 m above the eave, which put an invisible flat platform in the
## air above every roof and let the player stand on nothing.
##
## W6L: the split is measured from the geometry, not from the `end` token. The
## EndA/EndB gable caps are pitched shells too (92 instances in PeripheryA),
## and three of the six End meshes measure 0.0000 top coverage - the name said
## "end", so they kept BoxShape3D and floated a box at the ridge. A flat roof
## surface is the one that presents a real horizontal top: the fraction of
## upward-facing area inside ROOF_TOP_BAND_M of the AABB top, over the AABB
## footprint. Measured on the shipped modules: GB_RoofFloor_6x6 = 1.00,
## Side_* fascia = 1.90, EndA/EndB = 0.000-0.014, Mid_* = 0.07, Corner = 0.03,
## so ROOF_FLAT_TOP_FRAC 0.5 separates decks/fascia from pitched shells with a
## wide margin. Roof props and trim keep their exact box by ROOF_BOX_TOKENS
## (a chimney's hull would only cost more, and its top is a real cap).
const ROOF_PATH_TOKEN: String = "/roofs/"
const ROOF_BOX_TOKENS: Array[String] = [
	"trim", "chimney", "vent", "pipe", "gutter", "rail", "watertower", "tank",
	"roofdetails", "spike",
]
## Upward-facing area is counted only inside this band below the AABB top.
const ROOF_TOP_BAND_M: float = 0.10
## >= this top-area / footprint ratio is a flat, standable roof surface (box);
## below it the module is a pitched shell (convex hull).
const ROOF_FLAT_TOP_FRAC: float = 0.5
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


## W1p: PeripheryA HLOD test range. 0/absent keeps the current draw distance;
## only the authored 100/120/150 choices are accepted so a typo cannot silently
## turn into an arbitrary cull plane.
func _resolve_periph_range() -> int:
	var raw: String = OS.get_environment(ENV_PERIPH_RANGE).strip_edges()
	if raw == "":
		return 0
	if not raw.is_valid_int():
		push_warning("[level_loader] %s=%s is not an integer; PeripheryA range stays off" % [ENV_PERIPH_RANGE, raw])
		return 0
	var value: int = int(raw)
	if not PERIPH_RANGE_CHOICES.has(value):
		push_warning("[level_loader] %s=%d is not one of %s; PeripheryA range stays off" % [ENV_PERIPH_RANGE, value, str(PERIPH_RANGE_CHOICES)])
		return 0
	return value


## W1p: accepts exactly "plain" (case-insensitive). Anything else is off, with a
## warning for unknown non-empty values, so a typo can never enable a merge.
func _resolve_merge_mode() -> String:
	var raw: String = OS.get_environment(ENV_MERGE_CELLS).strip_edges().to_lower()
	if raw == "" or raw == "off" or raw == "0":
		return "off"
	if raw == "plain":
		return "plain"
	push_warning("[level_loader] %s=%s is not a known merge mode; merge stays off" % [ENV_MERGE_CELLS, raw])
	return "off"


## Draw-item provenance: "Guildhall_PeripheryA.tatlevel.json" ->
## "Guildhall_PeripheryA". Used for the census and the PeripheryA range lever.
static func _sublevel_tag(json_path: String) -> String:
	var file_name: String = json_path.get_file()
	var suffix: String = ".tatlevel.json"
	if file_name.to_lower().ends_with(suffix):
		return file_name.substr(0, file_name.length() - suffix.length())
	return file_name.get_basename()


static func _is_periphery_a_source(source: String) -> bool:
	var low: String = source.to_lower()
	return low == "peripherya" or low.ends_with("_peripherya") or low.ends_with("_periphery_a")


## Single source of truth for the loader's applied budget/shadow values. The
## env overrides live in MobileProfile; this helper keeps the two load paths and
## the log line from disagreeing.
func _effective_light_budget(requested: int) -> int:
	var applied: int = MobileProfile.light_budget(requested)
	if applied != requested or MobileProfile.shadow_heroes_override() >= 0:
		print("TAT-2 perf light env: requested=%d applied=%d hero_shadows=%d" % [requested, applied, MobileProfile.hero_shadows()])
	return applied


## True for the authored textures whose 1-bit alpha must survive verbatim.
## The storefront glass decals lose all 7,611 transparent pixels when resized.
func _is_alpha_critical_texture(res_path: String) -> bool:
	return ALPHA_CRITICAL_TEXTURES.has(res_path)


## PG-1: downscale an image whose long edge exceeds the budget. Returns the
## same image untouched when it already fits, else resizes it in place. The
## mip contract of the source is kept (imported .ctex ships no mip chain).
func _cap_image(img: Image, res_path: String) -> Image:
	var cap: int = texture_budget_max_dim
	if cap <= 0 or img == null or img.is_empty():
		return img
	if _is_alpha_critical_texture(res_path):
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
	if _is_alpha_critical_texture(res_path):
		return tex
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


func _enter_tree() -> void:
	_roughness_live_loaders += 1
	# RE-C/C2-01: props instantiated outside the level build (loot, clues,
	# pickups, thrown bottles, locked doors) reuse the live loader's material
	# DB + texture cache through bind_prop_scene_materials() instead of
	# building their own. Group membership is additive: nothing else keys off
	# it, and a loader that is not in a tree (tests) simply is not found.
	add_to_group("level_loader")


## W7G: explicit teardown hook for probes/tests that hold a loader outside the
## tree (they never get `_exit_tree`). Mirrors the other `cleanup_static_caches`.
static func cleanup_roughness_cache() -> void:
	_roughness_global_cache.clear()


## PG-1 teardown: release cached textures/materials/meshes when the loader
## leaves the tree (scene reload / quit-to-desktop) so their RIDs are freed
## in scene order instead of at global exit (exit-time RID-leak /
## PagedAllocator noise on live Vulkan). Every cache rebuilds on demand.
## W7G: the process-global roughness cache is released only when the last live
## loader leaves, so a concurrent load never loses its bakes.
func _exit_tree() -> void:
	_tex_cache.clear()
	_std_mat_cache.clear()
	_mesh_res_cache.clear()
	_guildhall_sign_split_cache.clear()
	_override_mesh_cache.clear()
	_spline_mesh_cache.clear()
	_roof_geom_cache.clear()
	_roughness_live_loaders = maxi(_roughness_live_loaders - 1, 0)
	if _roughness_live_loaders == 0:
		_roughness_global_cache.clear()


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
##
## W6L metallic precedence: the authored `Metallic Map?` / `Use Metallic Map`
## switch is the authority. MI_TrimMetalA_brass and MI_Phonograph carry it true
## next to the master's `FlatMetallic 0.0`, and the old chain read FlatMetallic
## first, so 584 map-driven materials rendered as dielectrics. With the switch
## on and an ORM bound, metallic must be 1.0 so the blue channel drives;
## FlatMetallic is only the fallback for map-off materials (MI_Map_ThievesDen:
## switch false, FlatMetallic 0.0 -> 0.0).
##
## W6L roughness range: UE's M_Env* masters expose `Roughness Low/High` and let
## the map interpolate between them (low + g * (high - low)). Godot multiplies
## `roughness` by the texture's green channel, so the old midpoint collapsed
## the authored range to (low+high)/2 * g (parchment 0.50 * g, brass
## 0.575 * g = mirror metal). The remap is baked once per (ORM, low, high) in
## _roughness_remap_texture() and the scalar stays 1.0 so the map is the value.
func _apply_ue_pbr_params(mat: StandardMaterial3D, info: Dictionary) -> void:
	var params: Dictionary = _ue_norm_map(info.get("params", {}))
	var switches: Dictionary = _ue_norm_map(info.get("switches", {}))
	var texs: Dictionary = {}
	var texs_v: Variant = info.get("texs", {})
	if texs_v is Dictionary:
		texs = texs_v as Dictionary
	var has_orm: bool = str(texs.get("orm", "")) != ""
	var rough_map_switch: Variant = _ue_lookup(switches, ["roughnessmap?"])
	# FlatRoughness is a UE master-material fallback used only when the
	# roughness map is off. It was being applied even when T_*_ORM was bound,
	# multiplying the map by 0 and producing mirror-metal props (MI_Zipwire:
	# FlatRoughness 0.0 + ORM mean 0.665 -> 0.04). Prefer an explicit
	# Roughness scalar, otherwise let the ORM map drive (value 1.0).
	var rough: Variant = _ue_lookup(params, ["roughness", "rougness"])
	if rough == null and not (has_orm and rough_map_switch != false):
		rough = _ue_lookup(params, ["flatroughness"])
	var rlo: Variant = _ue_lookup(params, ["roughnesslow", "roughnessmin"])
	var rhi: Variant = _ue_lookup(params, ["roughnesshigh", "roughnessmax"])
	var rough_low: float = float(rlo) if rlo != null else 0.0
	var rough_high: float = float(rhi) if rhi != null else 1.0
	if rough != null:
		mat.roughness = clampf(float(rough), 0.0, 1.0)
	elif has_orm and rlo != null and rhi != null and not is_equal_approx(rough_low, rough_high):
		if is_zero_approx(rough_low) and is_equal_approx(rough_high, 1.0):
			# low 0 / high 1 is the identity range: the ORM green channel already
			# IS low + g * (high - low), so the authored map binds directly with
			# scalar 1.0 and no baked copy is allocated.
			mat.roughness = 1.0
		elif rough_low < 0.0 or rough_high < 0.0:
			# Negative authored values are data errors: use the safe matte end
			# rather than a negative roughness. An inverted but non-negative
			# range (low > high) is authored and bakes as a decreasing ramp.
			mat.roughness = clampf(maxf(rough_low, rough_high), 0.0, 1.0)
		else:
			# low + g * (high - low) is baked into the roughness texture (see
			# _roughness_remap_texture); the scalar multiplies it by 1.0.
			# TAT2_ROUGH_BAKE=off is the documented fallback: keep the safe
			# authored high end and never bind the ORM green channel, because
			# scalar * g would re-introduce the retired midpoint.
			if _roughness_bake_enabled():
				mat.roughness = 1.0
				mat.set_meta("ue_roughness_remap", Vector2(rough_low, rough_high))
			else:
				mat.roughness = clampf(rough_high, 0.0, 1.0)
				mat.set_meta("ue_roughness_flat", rough_high)
	elif has_orm and rlo != null and rhi != null:
		mat.roughness = clampf(rough_high, 0.0, 1.0)
	elif has_orm:
		mat.roughness = 1.0
	elif rlo != null and rhi != null:
		# No map to interpolate along: the high end is the safe matte value.
		mat.roughness = clampf(rough_high, 0.0, 1.0)
	var metal_map_on: bool = _ue_lookup(switches, ["metallicmap?", "usemetallicmap"]) == true
	var metal: Variant = _ue_lookup(params, ["metallic", "metalness", "flatmetallic"])
	if metal_map_on and has_orm:
		# The map is the value; keep the authored flat value only as the
		# fallback if the ORM texture fails to load at bind time.
		mat.metallic = 1.0
		mat.set_meta("ue_metallic_map", true)
		if metal != null:
			mat.set_meta("ue_flat_metallic", clampf(float(metal), 0.0, 1.0))
	else:
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


## W7G: `TAT2_ROUGH_BAKE=off` is a sanctioned diagnostic fallback, never the
## default. Resolved once per process so an invalid value is logged once.
## Returns true when the L8 range bake should run (the shipped path).
func _roughness_bake_enabled() -> bool:
	if _roughness_mode == "":
		var raw: String = OS.get_environment("TAT2_ROUGH_BAKE").strip_edges().to_lower()
		match raw:
			"", "on", "1", "true", "yes":
				_roughness_mode = "on"
			"off", "0", "false", "no":
				_roughness_mode = "off"
			_:
				_roughness_mode = "on"
				print("ROUGHNESS_BAKE_MODE invalid=", raw, " default=on")
		if _roughness_mode == "off":
			print("ROUGHNESS_BAKE_MODE off=1 fallback=rough_high source=TAT2_ROUGH_BAKE")
		else:
			print("ROUGHNESS_BAKE_MODE on=1 resolution=full cache=process")
	return _roughness_mode != "off"


## W6L/W7G: bakes `low + g * (high - low)` from the authored ORM green channel
## into a single-channel (L8) texture, cached per texture + range. Godot
## multiplies BaseMaterial3D.roughness by the sampled green, so an L8 texture
## whose luminance is the remapped value keeps every texel's authored roughness
## without holding a second RGBA copy of the ORM (78.8 M px would be ~400 MiB
## at RGBA8; L8 is ~100 MiB and samples .g = luminance on 4.7.2, verified with
## a readback render). A null result means "no texture"; the caller falls back
## to the high end so roughness is never left at the old average. Full authored
## resolution is always kept (there is deliberately no half-res path).
func _roughness_remap_texture(orm: Texture2D, low: float, high: float, orm_path: String) -> Texture2D:
	if orm == null:
		return null
	var key: String = "%s|%.4f|%.4f" % [orm_path if orm_path != "" else orm.resource_path, low, high]
	if _roughness_global_cache.has(key):
		_roughness_cache_hits += 1
		return _roughness_global_cache[key] as Texture2D
	var bake_t0: int = Time.get_ticks_msec()
	var img: Image = orm.get_image()
	if img == null:
		_roughness_global_cache[key] = null
		return null
	img = (img.duplicate() as Image)
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		_roughness_global_cache[key] = null
		return null
	var lut := PackedByteArray()
	lut.resize(256)
	for i: int in range(256):
		var v: float = low + (float(i) / 255.0) * (high - low)
		lut[i] = int(roundf(clampf(v, 0.0, 1.0) * 255.0))
	var src: PackedByteArray = img.get_data()
	var dst := PackedByteArray()
	dst.resize(w * h)
	var si: int = 1
	var di: int = 0
	var n: int = src.size()
	while si < n and di < w * h:
		dst[di] = lut[src[si]]
		si += 4
		di += 1
	var out_img: Image = Image.create_from_data(w, h, false, Image.FORMAT_L8, dst)
	if out_img == null:
		_roughness_global_cache[key] = null
		return null
	if not out_img.has_mipmaps():
		out_img.generate_mipmaps()
	var tex: ImageTexture = ImageTexture.create_from_image(out_img)
	_roughness_global_cache[key] = tex
	_roughness_bake_count += 1
	_roughness_bake_px += w * h
	_roughness_bake_ms += Time.get_ticks_msec() - bake_t0
	# L8 + a full mip chain: 4/3 of the base plane.
	_roughness_bake_bytes += (w * h * 4) / 3
	return tex


## W5B/W6L: UE's M_Env* masters multiply the diffuse by `DiffuseMaskTint` only
## when the `DiffuseColorMask?` static switch is on. Every MI inherits the
## master's vector (MI_PosterWanted carries [0.5331,0.5645,0.6979]) but keeps
## the switch off (0 materials in materials.json have it true), so the guard
## stays. W6L correction: this tint path is inert on the shipped data and was
## never the cyan-poster cause - applying the vector unconditionally only
## changes WANTED posters if someone flips the switch. The poster was actually
## lit from behind by the MSM_Subsurface backlight fallback (see
## _is_authored_foliage), while the white emissive fallback is the lamp clip.
## Keep the switch guard, then convert the authored linear vector once for
## albedo_color (Godot treats albedo_color as sRGB).
func _apply_diffuse_mask_tint(mat: StandardMaterial3D, info: Dictionary) -> void:
	var switches: Dictionary = _ue_norm_map(info.get("switches", {}))
	if _ue_lookup(switches, ["diffusecolormask?"]) != true:
		return
	var vectors: Dictionary = _ue_norm_map(info.get("vectors", {}))
	var t: Variant = _ue_lookup(vectors, ["diffusemasktint", "diffusemaskcolor"])
	if not (t is Array) or (t as Array).size() < 3:
		return
	var ta: Array = t as Array
	var lin: Color = Color(float(ta[0]), float(ta[1]), float(ta[2]), 1.0)
	var srgb: Color = lin.linear_to_srgb()
	mat.albedo_color = Color(
		mat.albedo_color.r * srgb.r,
		mat.albedo_color.g * srgb.g,
		mat.albedo_color.b * srgb.b,
		mat.albedo_color.a
	)


## RE-C-08: convert an authored LINEAR base-colour composite into the sRGB space
## Godot's `albedo_color` is declared in. Values above 1.0 are HDR emissive
## carries (additive/unlit loot shine, hotwire glow, the beam card) and keep the
## legacy pass-through; only <=1 authored surface tints are encoded.
static func _srgb_encode_albedo_tint(c: Color) -> Color:
	if maxf(c.r, maxf(c.g, c.b)) > 1.0:
		return c
	var s: Color = c.linear_to_srgb()
	s.a = c.a
	return s


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
	var is_foliage_shading: bool = _is_authored_foliage(info, shading) and not is_bark
	# Authored EBlendMode::BLEND_Additive is a real additive pass, not opaque.
	# M_ParticleAdd_Niagara/MI_ThiefWriting_* and friends sat as opaque cards.
	if blend.find("additive") >= 0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	elif blend.find("translucent") >= 0 or blend.find("alphacomposite") >= 0:
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
	elif shading.ends_with("MSM_Unlit") and str(texs_rf.get("albedo", "")) != "":
		# Authored unlit masters (M_EnvUnlit, M_LF_CandlesFlickerA) must not
		# receive scene lighting. Untextured unlit materials already return an
		# unshaded black material in get_material_for_ue().
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


## W6L: MSM_Subsurface is not a foliage token. M_EnvBasicAlphaDoubleSided is the
## masked double-sided master shared by the WANTED posters, decal posters,
## scrolls, coins, candles and slime bubbles, and they all inherit
## MSM_Subsurface. The old gate read that shading as foliage, so every flat card
## took backlight_enabled and was lit from behind. Only authored foliage
## qualifies: MSM_TwoSidedFoliage, or a leaf/bark/foliage token in the material
## path or its bound albedo. Bark keeps its own no-backlight rule below.
func _is_authored_foliage(info: Dictionary, shading: String) -> bool:
	if shading.find("TwoSidedFoliage") >= 0:
		return true
	if shading.find("Subsurface") < 0 or shading.find("SubsurfaceProfile") >= 0:
		return false
	var texs_v: Variant = info.get("texs", {})
	var texs: Dictionary = texs_v as Dictionary if texs_v is Dictionary else {}
	var haystack: String = str(info.get("path", "")).to_lower() + "|" \
		+ str(info.get("parent", "")).to_lower() + "|" \
		+ str(texs.get("albedo", "")).to_lower() + "|" \
		+ str(texs.get("normal", "")).to_lower()
	return _has_token(haystack, FOLIAGE_TOKENS)


## Applies real UE emissive vectors/scalars from materials.json. Merges with an
## emissive texture bound above (the texture keeps its art-tuned energy while
## the UE colour fills in the emission tint); otherwise enables emission from
## the UE colour scaled by the emissive scalar. Skipped when the UE switches
## explicitly gate emissive off.
## True when materials.json carries an authored emissive colour (and a
## non-zero strength when one is present). Emissive-only materials such as
## MI_PowerLight_On have no albedo/tint by design; they are authored, not a
## tier-3 fallback.
## Whether the authoring switches allow the emissive texture to be bound.
## get_material_for_ue() used to bind texs.emissive and enable emission before
## _apply_ue_emissive() checked `Emissive On?`; MI_Zipwire and
## MI_ThiefNisha_Top therefore glowed with T_LightWallCastleSm_E (the
## white-spotted wall-light map) despite Emissive On? = false. That produced
## the black/white speckles on the 1P hands and launcher.
func _ue_emissive_allowed(info: Dictionary) -> bool:
	var switches: Dictionary = _ue_norm_map(info.get("switches", {}))
	if _ue_lookup(switches, ["emissiveon?"]) == false:
		return false
	# Third-party Stylized_Furniture masters use `Emissive_Switch` instead of
	# `Emissive On?` (MI_TeleScope_Inst: false + black Emissive_Color). The
	# old check missed it and bound T_FloorLamp_Glow to the telescope, making
	# it a white self-lit prop under the Den AGX exposure.
	if _ue_lookup(switches, ["emissiveswitch"]) == false:
		return false
	if _ue_lookup(switches, ["disableemissivecontribution"]) == true:
		return false
	# Do not reject on EmissiveStrength=0: UE window masters leave the scalar
	# at 0 while their E map and Emissive On?=true are the authored light.
	# The switch is the authority; texture presence is handled by the caller.
	return true


func _has_authored_emissive(info: Dictionary) -> bool:
	var switches: Dictionary = _ue_norm_map(info.get("switches", {}))
	if _ue_lookup(switches, ["emissiveon?"]) == false:
		return false
	if _ue_lookup(switches, ["disableemissivecontribution"]) == true:
		return false
	var vectors: Dictionary = _ue_norm_map(info.get("vectors", {}))
	var ecol: Variant = _ue_lookup(vectors, ["emissivecolor", "emissive", "emissivetint", "emiscolor"])
	if ecol == null:
		ecol = _two_tone_emissive_tint(vectors)
	if not (ecol is Array) or (ecol as Array).size() < 3:
		return false
	var ea: Array = ecol as Array
	var peak: float = maxf(float(ea[0]), maxf(float(ea[1]), float(ea[2])))
	if peak <= 0.005:
		return false
	var params: Dictionary = _ue_norm_map(info.get("params", {}))
	var estr: Variant = _ue_lookup(params, ["emissivestrength", "emissiveintensity", "emissivemultiplier", "emissivemultiply", "emismultiply", "emissivemult", "emissivepower", "emissivebrightness", "emissivebrillance"])
	return estr == null or peak * float(estr) > 0.005


## W6L: resolves the authored two-tone emissive gradient to its lit end.
## Two Tone Emissive materials expose EmissiveTintA/B and no EmissiveColor (the
## authored gradient blends between the two), so the generic lookup returned
## null and _apply_ue_emissive() fell back to white. Pick the brighter end by
## luminance: B carries the warm lit tone for the glass lamp families, while
## the angular/blue/red modules and the switched-off variants author that tone
## in A with B dark, and choosing B there would emit nothing.
func _two_tone_emissive_tint(vectors: Dictionary) -> Variant:
	var a: Variant = _ue_lookup(vectors, ["emissivetinta"])
	var b: Variant = _ue_lookup(vectors, ["emissivetintb"])
	var a_ok: bool = a is Array and (a as Array).size() >= 3
	var b_ok: bool = b is Array and (b as Array).size() >= 3
	if not a_ok and not b_ok:
		return null
	if a_ok and not b_ok:
		return a
	if b_ok and not a_ok:
		return b
	var aa: Array = a as Array
	var ba: Array = b as Array
	var a_luma: float = float(aa[0]) * 0.2126 + float(aa[1]) * 0.7152 + float(aa[2]) * 0.0722
	var b_luma: float = float(ba[0]) * 0.2126 + float(ba[1]) * 0.7152 + float(ba[2]) * 0.0722
	return a if a_luma >= b_luma else b


## W6L per-family emissive energy ceilings. The authored EmissiveStrength on
## these authored lamps is calibrated for UE's physical exposure (50x glass,
## 100x large lamps); carried 1:1 into Godot's emission it clips to white and
## seeds a bloom sheet. Glass stays readable at 3.0, the guard's handheld
## lantern at 1.6, large lamps at 2.5; everything else is bounded by the global
## 4.0 so no material emits pure white above 4.
func _emissive_energy_cap(low_path: String) -> float:
	if low_path.find("lanternguard") >= 0 or (low_path.find("lantern") >= 0 and low_path.find("guard") >= 0):
		return GUARD_LANTERN_EMISSION_CAP
	if low_path.find("lightlrg") >= 0 or low_path.find("chandelier") >= 0 \
		or low_path.find("industrialceiling") >= 0 or low_path.find("/lights/ceiling/") >= 0:
		return LARGE_LAMP_EMISSION_CAP
	if low_path.find("glass") >= 0 or low_path.find("window") >= 0:
		return GLASS_EMISSION_CAP
	return EMISSIVE_ENERGY_CEIL


func _apply_ue_emissive(mat: StandardMaterial3D, info: Dictionary) -> void:
	# A flat EmissiveTint with no E map is authored neon/light only. Character
	# masters (M_BasicChar_Tintable) expose EmissiveTint as a green debug value
	# with Emissive On?=true but no emissive texture; applying it turned every
	# guard and Hauntstable bust into a flat green silhouette.
	var texs_em: Dictionary = info.get("texs", {})
	if str(texs_em.get("emissive", "")).strip_edges() == "":
		var path_low: String = str(info.get("path", "")).to_lower()
		var parent_low: String = str(info.get("parent", "")).to_lower()
		var render_em: Dictionary = info.get("render", {})
		var shading_em: String = str(render_em.get("shading_model", "")).to_lower()
		var flat_ok: bool = shading_em.find("unlit") >= 0 \
			or path_low.find("neon") >= 0 or parent_low.find("neon") >= 0 \
			or path_low.find("light") >= 0 or parent_low.find("light") >= 0 \
			or path_low.find("lamp") >= 0 or path_low.find("bulb") >= 0 \
			or path_low.find("emissive") >= 0 or path_low.find("glow") >= 0
		if not flat_ok:
			return
	var switches: Dictionary = _ue_norm_map(info.get("switches", {}))
	if _ue_lookup(switches, ["emissiveon?"]) == false:
		return
	if _ue_lookup(switches, ["disableemissivecontribution"]) == true:
		return
	var vectors: Dictionary = _ue_norm_map(info.get("vectors", {}))
	var params: Dictionary = _ue_norm_map(info.get("params", {}))
	# FIX_SPEC P0 #6: MI_LightSmGlassA_Gold is a Two Tone Emissive glass whose
	# authored warm tint lives in EmissiveTintB (1.0, 0.606, 0.193). The old
	# generic lookup missed the A/B pair, fell back to white and multiplied the
	# authored 50x strength into a clipped 16x white orb. Use the authored B
	# tint with the authored 2.2 emission multiplier. Exact material only;
	# Guildhall's Blue/Gold1 lamp variants keep their previous path.
	var mat_stem: String = str(info.get("path", "")).get_file().split(".")[0].to_lower()
	if mat_stem == "mi_lightsmglassa_gold":
		var gold_tint: Variant = _ue_lookup(vectors, ["emissivetintb"])
		if gold_tint is Array and (gold_tint as Array).size() >= 3:
			var ga: Array = gold_tint as Array
			mat.emission_enabled = true
			mat.emission = Color(float(ga[0]), float(ga[1]), float(ga[2]))
			mat.emission_energy_multiplier = DEN_GOLD_LAMP_EMISSION
			return
	var ecol: Variant = _ue_lookup(vectors, ["emissivecolor", "emissive", "emissivetint", "emiscolor"])
	if ecol == null:
		# W6L two-tone gradient: see _two_tone_emissive_tint().
		ecol = _two_tone_emissive_tint(vectors)
	var estr: Variant = _ue_lookup(params, ["emissivestrength", "emissiveintensity", "emissivemultiplier", "emissivemultiply", "emismultiply", "emissivemult", "emissivepower", "emissivebrightness", "emissivebrillance"])
	if ecol == null and estr == null:
		return
	var col := Color(1.0, 1.0, 1.0)
	var authored_colour: bool = false
	if ecol is Array and (ecol as Array).size() >= 3:
		authored_colour = true
		var ea: Array = ecol
		col = Color(float(ea[0]), float(ea[1]), float(ea[2]))
		if maxf(col.r, maxf(col.g, col.b)) <= 0.02 and estr == null:
			return
	# W10-P2 cream fix: a WHITE tint is only authored when an emissive map
	# supplies the colour (the caller binds `emission_texture` from
	# texs.emissive) or the material authors an EmissiveColor. With neither, the
	# old code left `col` at (1,1,1) and multiplied the authored strength into
	# it — that invented emission is the cream slab on the moon cards'
	# MI_EmisLight_Moonlight class. No colour + no map => no emission, counted.
	var has_emissive_map: bool = str(texs_em.get("emissive", "")).strip_edges() != ""
	if not authored_colour and not has_emissive_map:
		_invented_white_count += 1
		var iw_name: String = str(info.get("path", ""))
		if invented_white_materials.size() < 64 and not invented_white_materials.has(iw_name):
			invented_white_materials.append(iw_name)
		set_meta("tat_invented_white", _invented_white_count)
		return
	var energy_cap: float = _emissive_energy_cap(str(info.get("path", "")).to_lower())
	if mat.emission_enabled:
		mat.emission = col
		if estr != null:
			var e_tex: float = clampf(float(mat.emission_energy_multiplier) * float(estr), 0.0, 16.0)
			mat.emission_energy_multiplier = minf(e_tex, energy_cap)
	else:
		mat.emission_enabled = true
		mat.emission = col
		var e_base: float = clampf(float(estr), 0.0, 8.0) if estr != null else 1.0
		mat.emission_energy_multiplier = minf(e_base, energy_cap)


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
	# W6L Den pane: MI_GlassPanels_oldmanor (ThievesDen glass) authors Opacity 2.0
	# and MI_GlassPanels authors 1.5. With the _O mask at 0.51 those multiplied
	# the mask past 1.0, so the centre of the pane saturated opaque. A mask IS
	# the opacity: cap the multiplier at 1.0 when an opacity map is bound, which
	# puts the centre transmission back at the thin-glass floor
	# (0.51 * 0.42 = 0.21) while the fresnel rim keeps its authored 0.51-0.90
	# band. Glass with no mask keeps its authored scalar (bulbs, display cases).
	var op_scale: float = 1.0
	if op_val != null:
		op_scale = clampf(float(op_val), 0.0, 1.0 if op != null else 8.0)
	elif op != null:
		op_scale = 1.0
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


## W5B masked opacity. A UE masked master can keep the silhouette in a separate
## Opacity map (M_UnlitOpacityMask + T_HorizonA_BCO) while Godot's alpha scissor
## only reads the albedo texture's alpha. MI_HorizonA bound T_TrimMetalB_DA
## (alpha 255 everywhere), so the 558 x 140 m horizon card rendered as a solid
## black wall instead of a skyline cut-out. Two authored packings are handled:
##   * "..._BCO" (BaseColor+Opacity): RGB is the authored base colour and alpha
##     is the mask, so the map is used verbatim - no resample, no pixel copy;
##   * grayscale "_O"/"_OPACITY": the mask lives in the red channel, so it is
##     copied into the albedo alpha at the mask's own resolution.
## Null leaves the previous albedo bound (never silently drops authored colour).
func _masked_opacity_albedo(albedo: Texture2D, opacity: Texture2D, op_res_path: String) -> Texture2D:
	if opacity == null:
		return null
	var key: String = "masked:" + op_res_path + "|" + (albedo.resource_path if albedo != null else "")
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var mask_img: Image = opacity.get_image()
	if mask_img == null:
		return null
	mask_img = (mask_img.duplicate() as Image)
	if mask_img.is_compressed():
		mask_img.decompress()
	mask_img.convert(Image.FORMAT_RGBA8)
	var mask_from_alpha: bool = _mask_uses_alpha(mask_img)
	var out_tex: Texture2D = null
	if mask_from_alpha and op_res_path.to_lower().ends_with("_bco.png"):
		out_tex = opacity
	else:
		var out_img: Image = null
		var alb_img: Image = albedo.get_image() if albedo != null else null
		if alb_img != null:
			alb_img = (alb_img.duplicate() as Image)
			if alb_img.is_compressed():
				alb_img.decompress()
			alb_img.convert(Image.FORMAT_RGBA8)
			# The mask defines the cut-out, so it keeps its own resolution and
			# aspect; only the colour is resampled into it.
			if alb_img.get_size() != mask_img.get_size():
				alb_img.resize(mask_img.get_width(), mask_img.get_height(), Image.INTERPOLATE_BILINEAR)
			out_img = alb_img
		else:
			# No albedo to keep: the mask map's own RGB is the authored base
			# colour (a grayscale _O is neutral, a _BCO is base colour).
			out_img = (mask_img.duplicate() as Image)
		out_img.clear_mipmaps()
		_copy_mask_to_alpha(out_img, mask_img, mask_from_alpha)
		# Both inputs already went through _load_tex/_cap_texture, so the
		# composed image is inside the texture budget; capping it again would
		# double-count the downscale against the opacity path.
		if not out_img.has_mipmaps():
			out_img.generate_mipmaps()
		out_tex = ImageTexture.create_from_image(out_img)
	if out_tex != null:
		_tex_cache[key] = out_tex
	return out_tex


## Authored opacity maps are packed two ways in this project: a genuine alpha
## mask (T_HorizonA_BCO, 22 % of texels below 0.5) or a grayscale map in RGB
## (T_GooBubble01, T_Hauntstable_*_O - alpha 255 everywhere). A 64x64 probe
## decides which without scanning millions of texels per material.
static func _mask_uses_alpha(img: Image) -> bool:
	var probe: Image = (img.duplicate() as Image)
	probe.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	probe.convert(Image.FORMAT_RGBA8)
	var d: PackedByteArray = probe.get_data()
	var i: int = 3
	while i < d.size():
		if d[i] < 250:
			return true
		i += 4
	return false


static func _copy_mask_to_alpha(out_img: Image, mask_img: Image, from_alpha: bool) -> void:
	var md: PackedByteArray = mask_img.get_data()
	var od: PackedByteArray = out_img.get_data()
	var i: int = 3 if from_alpha else 0
	var n: int = mini(md.size(), od.size())
	while i < n:
		od[i] = md[i]
		i += 4
	out_img.set_data(out_img.get_width(), out_img.get_height(), false, Image.FORMAT_RGBA8, od)


## Authored beam material (MI_LightBeam_SM) for the SM_LightBeam cards and the
## security_beam fallback. Every value comes from the generated material row so
## a producer change flows through instead of being hidden in a constant; the
## fallbacks are the authored values measured above. Additive/unlit/two-sided
## is the shader's render_mode, matching the authored render block.
func _build_beam_material(info: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	var vecs: Dictionary = info.get("vectors", {}) as Dictionary if info.get("vectors", {}) is Dictionary else {}
	var base: Array = vecs.get("BaseColor", []) as Array if vecs.get("BaseColor", []) is Array else []
	var beam_col := Color(5.0, 4.3813, 3.5156, 0.5)
	if base.size() >= 4:
		beam_col = Color(float(base[0]), float(base[1]), float(base[2]), float(base[3]))
	var params: Dictionary = info.get("params", {}) as Dictionary if info.get("params", {}) is Dictionary else {}
	mat.set_shader_parameter("beam_color", beam_col)
	mat.set_shader_parameter("emissive_multiplier", float(params.get("EmissiveMultiplier", 3.0)))
	mat.set_shader_parameter("center_line_thickness", float(params.get("Center Line Thickness", 0.015)))
	mat.set_shader_parameter("center_line_opacity", float(params.get("Center Line Opacity", 0.5)))
	mat.set_shader_parameter("center_line_falloff", float(params.get("Center Line Falloff", 0.25)))
	mat.set_shader_parameter("fake_glow_opacity", float(params.get("Fake Glow Opacity", 0.06)))
	mat.set_shader_parameter("fake_glow_center_width", float(params.get("Fake Glow Center Width", 0.085)))
	mat.set_shader_parameter("fake_glow_power", float(params.get("Fake Glow Power", 1.1)))
	# P4.5: the remaining authored beam terms. `Fake Glow Thickness` and
	# `Fake Glow Center Power` drive the tight core; `Fake Glow Side Width`,
	# the sphere-mask trio and `EdgeFadePower` are bound so a future noise-mask
	# / graph recovery can switch them on without touching this loader, but the
	# shader deliberately does not apply them (no authored sphere centre and no
	# noise mask; see tat_beam.gdshader). The fallbacks are the authored values
	# from materials.json / MI_LightBeam_SM.json.
	mat.set_shader_parameter("fake_glow_thickness", float(params.get("Fake Glow Thickness", 0.02)))
	mat.set_shader_parameter("fake_glow_center_power", float(params.get("Fake Glow Center Power", 2.0)))
	mat.set_shader_parameter("fake_glow_side_width", float(params.get("Fake Glow Side Width", 1.0)))
	mat.set_shader_parameter("center_line_sphere_mask_radius", float(params.get("Center Line Sphere Mask Radius", 1.0)))
	mat.set_shader_parameter("sphere_mask_opacity", float(params.get("Sphere Mask Opacity", 0.25)))
	mat.set_shader_parameter("sphere_mask_power", float(params.get("Sphere Mask Power", 2.0)))
	mat.set_shader_parameter("edge_fade_power", float(params.get("EdgeFadePower", 0.5)))
	mat.set_shader_parameter("fade_distance", float(params.get("FadeDistance", 25.0)))
	# The authored card's local X is the length axis (radial = YZ).
	mat.set_shader_parameter("radial_axis", 0)
	return mat


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
	# Exact MI only: MI_LightBeam_SM (134 Guildhall SM_LightBeam meshes) is
	# authored Additive + Unlit + TwoSided with an HDR warm-white alpha 0.5.
	# The StandardMaterial3D path turned it into an opaque white lit slab.
	# The beam shader keeps the authored additive, unshaded, cull-disabled,
	# depth-write-off look and draws the authored 1.5 cm centre line / 6 %
	# fake glow / 25 m fade instead of the old full-tube bar.
	if low_mat.ends_with("mi_lightbeam_sm"):
		var beam_m: ShaderMaterial = _build_beam_material(info)
		_std_mat_cache[ue_mat_path] = beam_m
		return beam_m
	if is_translucent_early and ("glass" in low_mat or "window" in low_mat):
		var glass_alb_path: String = str(texs_early.get("albedo", ""))
		var glass_alb: Texture2D = null if (glass_alb_path.to_lower().find("mapbuilding") >= 0 and low_mat.find("mapbuilding") < 0) else _load_tex(glass_alb_path)
		var glass_op: Texture2D = _load_tex(str(texs_early.get("opacity", "")))
		if glass_alb != null or glass_op != null:
			var gmat: ShaderMaterial = _build_glass_material(info, glass_alb, glass_op)
			_std_mat_cache[ue_mat_path] = gmat
			return gmat
	# Exact MI instance only: the storefront glass decal albedo is ~90% black
	# texels (the magenta neon reads through it), so the StandardMaterial3D
	# tint path turned the whole pane magenta. Recolor the black background to
	# a dark gold and gate emission to the bright scrollwork luma instead.
	if low_mat.ends_with("mi_storefront_decal"):
		var dmat: ShaderMaterial = ShaderMaterial.new()
		dmat.shader = STOREFRONT_DECAL_SHADER
		dmat.set_shader_parameter("albedo_tex", _load_tex(str(texs_early.get("albedo", ""))))
		var decal_tint: Variant = info.get("tint")
		if decal_tint is Array and (decal_tint as Array).size() >= 3:
			var dt: Array = decal_tint as Array
			# Authored UE tint is already linear; do NOT sRGB-convert here.
			dmat.set_shader_parameter("gold_lin", Vector3(float(dt[0]), float(dt[1]), float(dt[2])))
		else:
			dmat.set_shader_parameter("gold_lin", Vector3(1.0, 0.327, 0.106))
		dmat.set_shader_parameter("bg_color", Vector3(1.0, 0.97, 0.94))
		dmat.set_shader_parameter("bg_gold", 0.008)
		dmat.set_shader_parameter("em_floor", 0.0)
		dmat.set_shader_parameter("em_scroll", 0.60)
		dmat.set_shader_parameter("luma_lo", 0.55)
		dmat.set_shader_parameter("luma_hi", 0.85)
		_std_mat_cache[ue_mat_path] = dmat
		return dmat
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
	# W5B: a masked material keeps its silhouette in `texs.opacity` when the
	# albedo has none (MI_HorizonA's skyline). Only the authored masked blend
	# takes this path; stippled/translucent and the foliage stand-in keep the
	# albedo alpha they were tuned against.
	if alb != null and blend_early.find("masked") >= 0:
		var op_path: String = str(texs.get("opacity", ""))
		if op_path != "":
			var op_tex: Texture2D = _load_tex(op_path)
			var masked_alb: Texture2D = _masked_opacity_albedo(alb, op_tex, op_path)
			if masked_alb != null:
				mat.albedo_texture = masked_alb
				mat.set_meta("masked_opacity", op_path)
	var norm := _load_tex(str(texs.get("normal", "")))
	if norm != null:
		mat.normal_enabled = true
		mat.normal_texture = norm
	var orm := _load_tex(str(texs.get("orm", "")))
	if orm != null:
		mat.ao_enabled = true
		mat.ao_texture = orm
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		# W6L: roughness is a baked low + g * (high - low) L8 map when the
		# material authored a Roughness Low/High range; otherwise the ORM's own
		# green channel (scalar 1.0, set in _apply_ue_pbr_params). Guard with
		# has_meta: get_meta(key, null) is "no default" and logs an engine ERROR.
		if mat.has_meta("ue_roughness_remap"):
			var remap: Vector2 = mat.get_meta("ue_roughness_remap") as Vector2
			var rough_tex: Texture2D = _roughness_remap_texture(orm, remap.x, remap.y, str(texs.get("orm", "")))
			if rough_tex != null:
				mat.roughness_texture = rough_tex
				mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			else:
				mat.roughness = clampf(remap.y, 0.0, 1.0)
		elif mat.has_meta("ue_roughness_flat"):
			# TAT2_ROUGH_BAKE=off: the authored high end is the scalar value;
			# do not bind the ORM green channel (scalar * g would be wrong).
			pass
		else:
			mat.roughness_texture = orm
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic_texture = orm
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	elif mat.get_meta("ue_metallic_map", false) == true:
		# The ORM never loaded: a metallic map with no map would read as solid
		# metal, so fall back to the authored flat value (0.0 when absent).
		mat.metallic = float(mat.get_meta("ue_flat_metallic", 0.0))
	if orm == null and mat.has_meta("ue_roughness_remap"):
		# Same for roughness: with no map the safe matte end of the range, never
		# the retired midpoint.
		var remap2: Vector2 = mat.get_meta("ue_roughness_remap") as Vector2
		mat.roughness = clampf(remap2.y, 0.0, 1.0)
	var tint: Variant = info.get("tint")
	var tint_applied: bool = false
	if tint is Array and tint.size() >= 3:
		var tint_col: Color = Color(float(tint[0]), float(tint[1]), float(tint[2]), 1.0)
		tint_applied = true
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
	var parent_low: String = str(info.get("parent", "")).to_lower()
	var skip_albedo_vectors: bool = parent_low.ends_with("m_envprop") or parent_low.ends_with("m_assetmaster") or parent_low.ends_with("m_basicchar_tintable")
	if not skip_albedo_vectors and (vectors_raw.has("Overlay") or vectors_raw.has("Multiply") or vectors_raw.has("Desaturation")):
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
	# Colour space (RE-C-08 / C2-02): UE base-colour vectors are LINEAR and
	# Godot's albedo_color is a source_color uniform that is decoded sRGB ->
	# linear in the shader. Assigning the authored value verbatim therefore
	# multiplies the albedo map by one gamma too little (darker and more
	# saturated). Encode the composite (tint x Overlay x Multiply, after
	# desaturation) to sRGB exactly once, the same convention already used by
	# _apply_diffuse_mask_tint and the storefront-decal shader. Values above
	# 1.0 are HDR emissive carries on additive/unlit paths (loot shine,
	# hotwire glow, the beam card) and are NOT surface albedo: they keep the
	# legacy pass-through so those materials do not lose their glow.
	if tint_applied:
		mat.albedo_color = _srgb_encode_albedo_tint(mat.albedo_color)
	_apply_diffuse_mask_tint(mat, info)
	if _ue_emissive_allowed(info):
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
	# L2-03: a material with an authored colour but no albedo map binds that
	# colour as a flat surface. Legitimate for real flat PBR (M_Solid_*,
	# M_BasicGrey) - and also exactly how untextured debug geometry
	# (MI_Default_White) renders. It used to be completely silent (zero
	# "material fallback" lines exist for it), so a capture could not tell a
	# deliberate flat colour from a missing map. Count every bind and name the
	# near-white class; the census lands in _finalize.
	if alb == null and tint != null:
		flat_colour_material_count += 1
		if flat_colour_materials.size() < 128 and not flat_colour_materials.has(ue_mat_path):
			flat_colour_materials.append(ue_mat_path)
		var flat_col: Color = mat.albedo_color
		if minf(flat_col.r, minf(flat_col.g, flat_col.b)) >= 0.90:
			push_warning("[level_loader] material flat white: '", ue_mat_path,
				"' has a colour but no albedo map (albedo_color=", flat_col,
				", flat=", flat_colour_material_count, ")")
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


## SM_Guildhall_Sign surface 0 (MI_TrimMetalA_brass_dark) mixes the +Z-facing
## letter caps with the trim frame. UE's two-sided flag for that surface is
## dropped on import, so the letters cull from the street and read as a dark
## brass board. Partition surface 0's triangles by local-space centroid into a
## letter band (y 2.30..4.50, z > 0.13) and keep that band on its own surface
## with the authored gold material at CULL_DISABLED. Surfaces 1 (iron board)
## and 2 (gold crest finials) are copied unchanged. Geometry is untouched, so
## the collision shape is identical; the split mesh is cached per UE path.
func _split_guildhall_sign_mesh(ue_path: String, m: Mesh) -> Mesh:
	if _guildhall_sign_split_cache.has(ue_path):
		return _guildhall_sign_split_cache[ue_path] as Mesh
	if m == null or m.get_surface_count() < 1:
		_guildhall_sign_split_cache[ue_path] = m
		return m
	var arr0: Array = m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr0[Mesh.ARRAY_VERTEX]
	var idx0: PackedInt32Array = arr0[Mesh.ARRAY_INDEX]
	if verts.is_empty() or idx0.is_empty():
		_guildhall_sign_split_cache[ue_path] = m
		return m
	var letter_idx := PackedInt32Array()
	var body_idx := PackedInt32Array()
	for t: int in range(idx0.size() / 3):
		var i0: int = idx0[t * 3]
		var i1: int = idx0[t * 3 + 1]
		var i2: int = idx0[t * 3 + 2]
		var centroid: Vector3 = (verts[i0] + verts[i1] + verts[i2]) / 3.0
		if centroid.y >= 2.30 and centroid.y <= 4.50 and centroid.z > 0.13:
			letter_idx.append(i0)
			letter_idx.append(i1)
			letter_idx.append(i2)
		else:
			body_idx.append(i0)
			body_idx.append(i1)
			body_idx.append(i2)
	if letter_idx.is_empty():
		_guildhall_sign_split_cache[ue_path] = m
		return m
	var gold: Material = get_material_for_ue("/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalSurfaceA_Brass")
	if gold is BaseMaterial3D:
		gold = (gold as BaseMaterial3D).duplicate()
		(gold as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	if gold == null:
		var fallback_gold := StandardMaterial3D.new()
		fallback_gold.albedo_texture = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Metal/T_BasicMetalSurfaceTrimA_D.png")
		fallback_gold.albedo_color = Color(1.0, 0.685, 0.273)
		fallback_gold.metallic = 0.85
		fallback_gold.roughness = 0.35
		fallback_gold.cull_mode = BaseMaterial3D.CULL_DISABLED
		gold = fallback_gold
	var body_arrays: Array = arr0.duplicate()
	body_arrays[Mesh.ARRAY_INDEX] = body_idx
	var letter_arrays: Array = arr0.duplicate()
	letter_arrays[Mesh.ARRAY_INDEX] = letter_idx
	# The GLB carries custom float channels; surface_get_arrays() returns them
	# as raw PackedFloat32Array, so add_surface_from_arrays() needs the source
	# format flags to decode them instead of failing the surface.
	var fmt0: int = m.surface_get_format(0)
	var split := ArrayMesh.new()
	split.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, body_arrays, [], {}, fmt0)
	split.surface_set_material(0, m.surface_get_material(0))
	split.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, letter_arrays, [], {}, fmt0)
	split.surface_set_material(1, gold)
	for s: int in range(1, m.get_surface_count()):
		split.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(s), [], {}, m.surface_get_format(s))
		split.surface_set_material(split.get_surface_count() - 1, m.surface_get_material(s))
	_guildhall_sign_split_cache[ue_path] = split
	return split


## W6L: the additive light-shaft path. Authored light shafts / god rays were
## the only names routed here, so VFX_SkySearchLight_Mesh (the authored sky
## searchlight cone under /Lights/Searchlight/) kept the engine placeholder
## WorldGridMaterial and rendered as the grey checkerboard cone. The token is
## scoped: `skysearchlight` by name, or `searchlight` only on a VFX_ / /vfx/
## asset, so the hard-surface fixtures (SM_Searchlight, SM_SearchlightBase,
## ...LensSmall) keep their authored MI_Searchlight materials.
func _is_additive_light_shaft(low_path: String) -> bool:
	if low_path.find("lightshaft") >= 0 or low_path.find("godray") >= 0:
		return true
	if low_path.find("skysearchlight") >= 0:
		return true
	return low_path.find("searchlight") >= 0 and (low_path.find("vfx_") >= 0 or low_path.find("/vfx/") >= 0)


func _get_mesh_and_shape(ue_path: String) -> Dictionary:
	if _mesh_res_cache.has(ue_path):
		return _mesh_res_cache[ue_path]
	var out: Dictionary = {"mesh": null, "shape": null}
	var res_path: String = _ue_mesh_to_res(ue_path)
	if res_path == "":
		_mesh_res_cache[ue_path] = out
		return out
	var _p0: int = Time.get_ticks_msec()
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
		_prof_glb_ms += Time.get_ticks_msec() - _p0
		if mi != null and mi.mesh != null:
			var m := mi.mesh.duplicate() as Mesh
			var low_u := ue_path.to_lower()
			if _is_additive_light_shaft(low_u):
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
				# Bind GLB-ordered material slots by INDEX (the producer emits
				# mesh_materials.json in GLB primitive order, the same order
				# Godot imports); a name match fills an empty slot only.
				var mesh_key: String = ue_path.split(".")[0]
				var mat_slots: Array = _mesh_mats_db.get(mesh_key, _mesh_mats_db_lower.get(mesh_key.to_lower(), []))
				var _m0: int = Time.get_ticks_msec()
				_bind_glb_materials(m, mat_slots)
				_fix_worldgrid_door_surfaces(ue_path, m)
				_fix_worldgrid_mountain_surfaces(ue_path, m)
				_prof_mat_ms += Time.get_ticks_msec() - _m0
				if "sm_guildhall_sign" in low_u:
					m = _split_guildhall_sign_mesh(ue_path, m)
				out["mesh"] = m
				# W9-P1: authored collision (default) reads the UE AggGeom; the
				# AABB/name heuristic is built only in `aabb` mode and for the
				# meshes that have no authored answer at all, so authored mode
				# never pays for trimeshes/hulls it does not use.
				if _collision_mode() == "aabb":
					var heur_a: Dictionary = _heuristic_shape(m, low_u)
					out["shape"] = heur_a["shape"]
					out["shape_offset"] = heur_a["shape_offset"]
				else:
					_fill_authored_shape(out, ue_path, m)
					if not out.has("shapes"):
						var heur_b: Dictionary = _heuristic_shape(m, low_u)
						out["shape"] = heur_b["shape"]
						out["shape_offset"] = heur_b["shape_offset"]
		inst.free()
	if out.get("shape") is Shape3D:
		(out["shape"] as Shape3D).set_meta("ue_mesh", ue_path)
	if out.has("shapes"):
		for s_var: Variant in (out["shapes"] as Array):
			if s_var is Shape3D:
				(s_var as Shape3D).set_meta("ue_mesh", ue_path)
	_mesh_res_cache[ue_path] = out
	return out


## Collision mode for mesh colliders. `authored` (default) consumes the UE
## simple-collision `AggGeom` payload (`mesh_collision.gd`); `aabb` keeps the
## pre-W9 render-mesh heuristic as the A/B control. An unknown value warns once
## (never per mesh) and falls back to `authored`, which is the uploaded default.
static var _collision_mode_warned: bool = false


static func _collision_mode() -> String:
	var raw: String = OS.get_environment("TAT2_COLLISION").strip_edges().to_lower()
	if raw == "" or raw == "authored":
		return "authored"
	if raw == "aabb":
		return "aabb"
	if not _collision_mode_warned:
		_collision_mode_warned = true
		push_warning("[level_loader] unknown TAT2_COLLISION='%s' (expected authored|aabb); using authored" % raw)
	return "authored"


## The pre-W9 shape heuristic, moved verbatim out of `_get_mesh_and_shape`:
## name tokens + AABB size decide box / trimesh / convex for one mesh. Used for
## `TAT2_COLLISION=aabb` and for the meshes that have no authored collision at
## all (10 of the 79 collidable Guildhall paths, all `/Game/Test/` graybox).
func _heuristic_shape(m: Mesh, low_u: String) -> Dictionary:
	var out: Dictionary = {"shape": null, "shape_offset": Vector3.ZERO}
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
	# Door frames/doorways are modelled with an opening, but their
	# AABB is solid. The old box path sealed every open doorway with
	# an invisible wall 0.5-0.9 m in front of the leaf. A trimesh
	# follows the modelled hole and is cheap for ~200 frames.
	var is_door_aperture: bool = "door" in low_u or "archway" in low_u
	# W6L: pitched /roofs/ modules must not box. See ROOF_BOX_TOKENS /
	# _measure_roof_top_coverage; the split is measured from this mesh.
	var is_roof_surface: bool = _is_roof_convex_surface(low_u, m)
	var aabb := m.get_aabb()
	var sz := aabb.size
	if not is_nonblocking and sz.length() > 0.45:
		if is_door_aperture:
			out["shape"] = m.create_trimesh_shape()
			out["shape_offset"] = Vector3.ZERO
		elif is_roof_surface and sz.length() < 12.0:
			# Convex hull: the authored pitch (ridge, hips, dormer
			# cheeks) becomes walkable collision instead of a flat
			# plateau at AABB top. Points are mesh-local, so no
			# centre offset (boxes are centred, hulls are not).
			out["shape"] = m.create_convex_shape()
			out["shape_offset"] = Vector3.ZERO
		elif sz.length() < 12.0 and not is_stair_run and not is_walk_surface:
			var bx := BoxShape3D.new()
			bx.size = Vector3(maxf(sz.x, 0.1), maxf(sz.y, 0.1), maxf(sz.z, 0.1))
			out["shape"] = bx
			out["shape_offset"] = aabb.get_center()
		else:
			out["shape"] = m.create_trimesh_shape()
			out["shape_offset"] = Vector3.ZERO
	return out


## Fills the authored-collision fields for one mesh. `out["shape"]` keeps the
## heuristic value only when the mesh has no authored answer at all; every other
## source replaces it (`shapes`/`shape_offsets` carry the real per-instance set,
## `shape` is the single-shape compatibility field for the tests/probes that
## read `_get_mesh_and_shape` directly).
func _fill_authored_shape(out: Dictionary, ue_path: String, m: Mesh) -> void:
	# The load-total placement count only feeds the per-mesh cost cap; the
	# pre-pass in `_build_draw_items` fills it, direct callers default to 1.
	var n: int = maxi(int(_col_path_counts.get(ue_path, 1)), 1)
	var res: Dictionary = AuthoredCollision.resolve(ue_path, n) as Dictionary
	var source: String = str(res.get("source", "absent"))
	out["col"] = {
		"source": source,
		"class": str(res.get("class", "")),
		"reason": str(res.get("reason", "")),
		"elements": int(res.get("elements", 0)),
		"convex": int(res.get("convex", 0)),
		"reduced": bool(res.get("reduced", false)),
		"enabled": str(res.get("enabled", "QueryAndPhysics")),
	}
	match source:
		"hull", "prims":
			var shapes: Array = res["shapes"] as Array
			var offs: Array = res["offsets"] as Array
			out["shapes"] = shapes
			out["shape_offsets"] = offs
			# Single-shape compatibility field: legacy callers (roof/stair probes,
			# `_get_mesh_and_shape` consumers) get the first authored shape. The
			# draw path itself always uses `shapes`/`shape_offsets`, so a
			# multi-hull mesh is never reduced to this field.
			if not shapes.is_empty():
				out["shape"] = shapes[0]
				out["shape_offset"] = (offs[0] as Transform3D).origin
			else:
				out["shape"] = null
				out["shape_offset"] = Vector3.ZERO
		"complex_default":
			# UE `CTF_UseDefaultCollision` + no simple geometry collides with the
			# render triangles; that trimesh IS the authored answer (re-a1 §B6).
			var ts: Shape3D = m.create_trimesh_shape()
			out["shapes"] = [ts]
			out["shape_offsets"] = [Transform3D.IDENTITY]
			out["shape"] = ts
			out["shape_offset"] = Vector3.ZERO
		"no_collision":
			out["shapes"] = [] as Array
			out["shape_offsets"] = [] as Array
			out["shape"] = null
			out["shape_offset"] = Vector3.ZERO
		_:
			# "absent": no authored data exists; `out` already holds the heuristic.
			pass


## L1 accounting: name the UE path + resolved file, count, cap the stored
## list at 128 (count stays exact). push_error, not warning — a corrupt
## import drops geometry AND collision for that mesh.
func _note_corrupt_mesh(ue_path: String, res_path: String) -> void:
	corrupt_mesh_count += 1
	if corrupt_meshes.size() < 128 and not corrupt_meshes.has(ue_path):
		corrupt_meshes.append(ue_path)
	push_error("[level_loader] corrupt mesh import for UE path '", ue_path, "' (resolved ", res_path, "); cached as missing (corrupt=", corrupt_mesh_count, ")")


## W10-P2 cream census: number of materials where `_apply_ue_emissive()` would
## have invented a white emission (EmissiveStrength with no EmissiveColor and no
## emissive map) and suppressed it instead. Exposed for the cream proof.
func invented_white_count() -> int:
	return _invented_white_count


## L2 accounting: substring-guess fallbacks bind plausible-but-wrong
## textures (tier 2) or flat colors (tier 3). Named + counted per new path.
func _note_fallback_material(ue_mat_path: String, tier: int) -> void:
	fallback_material_count += 1
	if fallback_materials.size() < 128 and not fallback_materials.has(ue_mat_path):
		fallback_materials.append(ue_mat_path)
	push_warning("[level_loader] material fallback tier ", tier, " for '", ue_mat_path, "' (guessed, not authored; fallbacks=", fallback_material_count, ")")


## Binds GLB-ordered material slots to the imported ArrayMesh surfaces.
##
## The SLOT INDEX is the authored mapping: `tools/parse_materials.py` emits
## `mesh_materials.json` in GLB primitive order (`slot_order_source: "glb"` for
## 2,047 of 2,065 meshes, 0 reorderings against the authored StaticMaterials
## array), and Godot imports GLB primitives in that same order. The previous
## implementation let a name-substring match win over the index, which bound the
## wrong variant whenever one slot name contained another: a surface named
## `MI_TrimMetalSurfaceA` matched slot `MI_TrimMetalSurfaceA_Copper`,
## `MI_GlassPanels` matched `MI_GlassPanels_oldmanor`, `MI_RoastedPig` matched
## `MI_RoastedPigDetails`. Repository census (RE-Q-06, reproduced): 53 placed
## meshes / 776 instances took a different material than the authored slot.
##
## The name match survives only for an EMPTY authored slot (24 slots / 14
## meshes, otherwise a white glTF default) and only when exactly one slot name
## is a match; each such rescue is counted in slot_name_fallback_count.
func _bind_glb_materials(m: Mesh, mat_slots: Array) -> void:
	if m == null or mat_slots.is_empty():
		return
	for s in range(m.get_surface_count()):
		if s >= mat_slots.size():
			break
		var mp := str(mat_slots[s])
		if mp == "":
			mp = _slot_name_fallback(m, mat_slots, s)
		if mp != "":
			m.surface_set_material(s, get_material_for_ue(mp))


## Rescues an empty authored slot by surface name. Returns "" when the surface
## name is generic, no slot matches, or more than one does (an ambiguous name
## must never pick a material).
func _slot_name_fallback(m: Mesh, mat_slots: Array, surface: int) -> String:
	var surf_name := str(m.surface_get_name(surface)).to_lower()
	if surf_name.length() < 3:
		return ""
	var hit: String = ""
	var hits: int = 0
	for i in range(mat_slots.size()):
		var mp := str(mat_slots[i])
		if mp == "":
			continue
		var short := mp.get_file().split(".")[0].to_lower()
		if short.length() < 3:
			continue
		if surf_name.find(short) >= 0 or short.find(surf_name) >= 0:
			hit = mp
			hits += 1
	if hits != 1:
		return ""
	slot_name_fallback_count += 1
	if slot_name_fallback_names.size() < 64 and not slot_name_fallback_names.has(hit):
		slot_name_fallback_names.append(hit)
	return hit


## Reverse of _ue_mesh_to_res for the prop call sites: the exported GLB path is
## deterministic (`res://assets/ue/Content/<Game-relative>.glb`, or the Raw/TAT
## mirror for engine carriers), so the authored UE mesh path can be recovered
## without another JSON field.
static func glb_res_to_ue_path(res_path: String) -> String:
	var rel: String = res_path
	var prefixes: Array[String] = [
		"res://assets/ue/Content/",
		"res://assets/ue/Raw/TAT/Content/",
	]
	for prefix: String in prefixes:
		if rel.begins_with(prefix):
			rel = rel.substr(prefix.length())
			if rel.to_lower().ends_with(".glb"):
				rel = rel.substr(0, rel.length() - 4)
			return "/Game/" + rel
	return ""


## One-time warning guard for bind_prop_scene_materials (static).
static var _prop_bind_warned: bool = false


## Bind the authored material slots onto a GLB prop that was instantiated
## outside the level build (loot/quest/clue/pickup/prop/tool views).
##
## The glTF export carries no images and no baseColorFactor, so every surface of
## an un-rebound GLB renders the glTF default - flat white, fully rough - which
## is why the carried props, the cat statue and the clues were blank. The level
## build rebinds through _bind_glb_materials(); this is the equivalent for the
## standalone call sites, using the live loader's already-loaded DB + texture
## cache. It sets per-instance surface OVERRIDES (never mutates the shared
## imported Mesh, which a level instance may bind differently).
##
## Returns the number of surfaces bound (0 when the prop has no authored slot
## list, or when no loader is live - one warning is emitted per process so a
## white prop is never silent).
static func bind_prop_scene_materials(root: Node, glb_res_path: String) -> int:
	if root == null or glb_res_path == "":
		return 0
	var tree: SceneTree = root.get_tree()
	if tree == null:
		return 0
	var loader: Node = null
	for cand: Node in tree.get_nodes_in_group("level_loader"):
		if is_instance_valid(cand):
			loader = cand
			break
	var ue_mesh: String = glb_res_to_ue_path(glb_res_path)
	var slots: Array = []
	if loader != null and ue_mesh != "":
		var db: Variant = loader.get("_mesh_mats_db")
		var slots_v: Variant = (db as Dictionary).get(ue_mesh, null) if db is Dictionary else null
		if not (slots_v is Array):
			var db_low: Variant = loader.get("_mesh_mats_db_lower")
			slots_v = (db_low as Dictionary).get(ue_mesh.to_lower(), null) if db_low is Dictionary else null
		if slots_v is Array:
			slots = slots_v as Array
	if loader == null or slots.is_empty():
		if not _prop_bind_warned:
			_prop_bind_warned = true
			push_warning("[level_loader] prop GLB '", glb_res_path,
				"' has no authored slot list (loader=", loader != null,
				"); its surfaces stay on the white glTF default")
		return 0
	return _bind_scene_overrides(root, loader, slots)


## Walks an instantiated prop and sets a surface override from the authored slot
## list (index order, same contract as _bind_glb_materials).
static func _bind_scene_overrides(node: Node, loader: Node, slots: Array) -> int:
	var bound: int = 0
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			for s: int in range(mi.mesh.get_surface_count()):
				if s >= slots.size():
					break
				var mp: String = str(slots[s])
				if mp == "":
					continue
				var mat: Material = loader.call("get_material_for_ue", mp) as Material
				if mat != null:
					mi.set_surface_override_material(s, mat)
					bound += 1
	for child: Node in node.get_children():
		bound += _bind_scene_overrides(child, loader, slots)
	return bound


## WorldGridMaterial is the UE checkerboard placeholder, not authored art. On
## door/gate/fence meshes it means the shipped asset never assigned that
## surface (SM_OldManor_Gate_FrontDoor is 4/4 grid, SM_OldManor_Gallery_Door_
## Glass 1/1, SM_Manor_Door_Single and SM_Store_Int_WallDoor_Closed_4x6 carry a
## stray grid panel). Substitute a referenced material; never hide WorldGrid
## globally (spheres/emitters use it intentionally).
const WORLDGRID_GATE_MATERIAL: String = "/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalSurfaceA"
const WORLDGRID_GLASS_MATERIAL: String = "/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_Glass_Display"
## W5B: SkyboxGeo's distant mountain cards (SM_Mountain02/07/16/18_Grass) bind
## the engine placeholder WorldGridMaterial, so the horizon rendered as the grey
## checkerboard. The authored grass mountain material already exists and is
## bound by SM_Mountain17_Grass; substitution is scoped to /skybox/mountains/
## and an "sm_mountain" file stem (never global: WorldGrid is intentional for
## spheres/emitters and the gate/door path above keeps its own targets).
const WORLDGRID_MOUNTAIN_MATERIAL: String = "/Game/Art/Environment/Materials/MI_Mountain17"


func _is_worldgrid_material(mat: Material) -> bool:
	if mat == null:
		return false
	if "worldgrid" in mat.resource_path.to_lower():
		return true
	var sm := mat as StandardMaterial3D
	if sm != null and sm.albedo_texture != null:
		return "grid" in sm.albedo_texture.resource_path.to_lower()
	return false


func _fix_worldgrid_door_surfaces(ue_path: String, m: Mesh) -> void:
	if m == null:
		return
	var low: String = ue_path.to_lower()
	if low.find("door") < 0 and low.find("gate") < 0 and low.find("fence") < 0:
		return
	var count: int = m.get_surface_count()
	var grid_slots: Array[int] = []
	for s: int in range(count):
		if _is_worldgrid_material(m.surface_get_material(s)):
			grid_slots.append(s)
	if grid_slots.is_empty():
		return
	var replacement: Material = null
	if grid_slots.size() == count:
		# Fully-gridded asset: substitute a referenced metal (gate/fence) or
		# glass (glass door) material instead of a checkerboard door.
		replacement = get_material_for_ue(
			WORLDGRID_GLASS_MATERIAL if low.find("glass") >= 0 else WORLDGRID_GATE_MATERIAL
		)
	else:
		# Partial grid panel: reuse the mesh's own main door material (slot 0)
		# so the leaf matches its frame and handle.
		replacement = m.surface_get_material(0)
		if replacement == null or _is_worldgrid_material(replacement):
			replacement = get_material_for_ue(WORLDGRID_GATE_MATERIAL)
	if replacement == null:
		return
	for s2: int in grid_slots:
		m.surface_set_material(s2, replacement)


## W5B: skybox mountain substitution. Scoped by name only - the mesh must live
## under /skybox/mountains/ and its stem must start with "sm_mountain" - so the
## placeholder stays untouched for every other WorldGrid surface (spheres,
## emitters, the door/gate path above).
func _is_skybox_mountain_mesh(low_path: String) -> bool:
	if low_path.find("/skybox/mountains/") < 0:
		return false
	return low_path.get_file().split(".")[0].begins_with("sm_mountain")


func _fix_worldgrid_mountain_surfaces(ue_path: String, m: Mesh) -> void:
	if m == null or not _is_skybox_mountain_mesh(ue_path.to_lower()):
		return
	var grid_slots: Array[int] = []
	for s: int in range(m.get_surface_count()):
		if _is_worldgrid_material(m.surface_get_material(s)):
			grid_slots.append(s)
	if grid_slots.is_empty():
		return
	var replacement: Material = get_material_for_ue(WORLDGRID_MOUNTAIN_MATERIAL)
	if replacement == null:
		return
	for s2: int in grid_slots:
		m.surface_set_material(s2, replacement)


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


## ----- P4.2 mirror split ---------------------------------------------------
## Per-load reset. The caches hold baked meshes and cull-front material clones
## for the duration of one load only, so a second map does not retain the
## previous map's geometry.
func _reset_mirror_counters() -> void:
	_mirror_variant_cache.clear()
	_mirror_cull_front_cache.clear()
	_mirror_warned.clear()
	_mirror_draw_bases = 0
	_mirror_batches_split = 0
	_mirror_multimesh_instances = 0
	_mirror_single_instances = 0
	_mirror_cull_front_instances = 0
	_mirror_cull_disabled_instances = 0
	_mirror_mesh_bytes = 0
	_mirror_mesh_count = 0
	_mirror_unbaked = 0
	_mirror_log_count = 0
	_mirror_log_suppressed = 0


static func _mirror_fast_path_enabled() -> bool:
	return OS.get_environment("TAT2_MIRROR_FAST").strip_edges().to_lower() != "off"


static func _mirror_single_baked() -> bool:
	return OS.get_environment("TAT2_MIRROR_SINGLE").strip_edges().to_lower() == "baked"


## Cached mirror variant for one effective mesh (already override-bound):
##   mode "baked"          -> `mesh` is the local-X-mirrored ArrayMesh
##   mode "cull_front"     -> `material` is a CULL_FRONT clone, mesh unchanged
##   mode "cull_disabled"  -> source already two-sided (or single-surface
##                            bake fallback); `material` is set only when the
##                            fallback had to clone a BaseMaterial3D
##   mode "native"         -> no bake possible; caller keeps Godot's own
##                            negative-determinant handling (standalone only)
## `allow_material_clone` is false when the caller applies a material override
## of its own (CPD emissive), because a second override would replace it.
func _get_mirror_variant(source: Mesh, ov_key: String, allow_material_clone: bool) -> Dictionary:
	var fast_on: bool = _mirror_fast_path_enabled()
	# The cull-front/cull-disabled decision depends on both the caller's
	# override policy and the A/B env, so both are part of the cache key.
	var key: String = "%d||%s||%d||%d" % [
		source.get_instance_id(), ov_key, 1 if allow_material_clone else 0, 1 if fast_on else 0]
	var hit: Variant = _mirror_variant_cache.get(key)
	if hit is Dictionary:
		return hit as Dictionary
	var surfaces: int = source.get_surface_count()
	var out: Dictionary = {
		"mode": "baked",
		"mesh": source,
		"material": null,
		"materials": [] as Array,
		"bytes": 0,
		"surfaces": surfaces,
	}
	# Fast path: one surface, BaseMaterial3D, no caller override. A CULL_FRONT
	# clone is enough for a MultiMesh batch (no per-instance engine flip). A
	# source that is already two-sided needs no flip at all.
	if allow_material_clone and fast_on and surfaces == 1:
		var src_mat: Material = source.surface_get_material(0)
		var bm: BaseMaterial3D = src_mat as BaseMaterial3D
		if bm != null:
			if bm.cull_mode == BaseMaterial3D.CULL_DISABLED:
				out["mode"] = "cull_disabled"
				_mirror_variant_cache[key] = out
				return out
			var front: BaseMaterial3D = _get_mirror_cull_front_material(bm)
			if front != null:
				out["mode"] = "cull_front"
				out["material"] = front
				_mirror_variant_cache[key] = out
				return out
	var baked: ArrayMesh = _bake_mirrored_mesh(source)
	if baked != null:
		out["mesh"] = baked
		out["bytes"] = int(baked.get_meta("mirror_bytes", 0))
		_mirror_mesh_bytes += int(out["bytes"])
		_mirror_mesh_count += 1
		_mirror_variant_cache[key] = out
		return out
	# Baked mesh unavailable (non-triangle primitive or unreadable arrays).
	# Single-surface BaseMaterial3D can still be made two-sided; anything else
	# is recorded as unbaked instead of silently rendering inside-out.
	if surfaces == 1:
		var fb_mat: Material = source.surface_get_material(0)
		var fb_bm: BaseMaterial3D = fb_mat as BaseMaterial3D
		if fb_bm != null:
			var disabled: BaseMaterial3D = fb_bm.duplicate() as BaseMaterial3D
			if disabled != null:
				disabled.cull_mode = BaseMaterial3D.CULL_DISABLED
				out["mode"] = "cull_disabled"
				out["material"] = disabled
				_mirror_variant_cache[key] = out
				return out
	out["mode"] = "native"
	_mirror_unbaked += 1
	var warn_key: String = str(source.resource_path)
	if warn_key == "":
		warn_key = "mesh_%d" % source.get_instance_id()
	if not _mirror_warned.has(warn_key) and _mirror_warned.size() < 8:
		_mirror_warned[warn_key] = true
		push_warning("[level_loader] mirrored mesh has no bake/fast path; negative instances keep the authored basis: ", warn_key)
	_mirror_variant_cache[key] = out
	return out


## One CULL_FRONT clone per source material (never mutates the shared source).
func _get_mirror_cull_front_material(src: BaseMaterial3D) -> BaseMaterial3D:
	var key: int = int(src.get_instance_id())
	var hit: Variant = _mirror_cull_front_cache.get(key)
	if hit is BaseMaterial3D:
		return hit as BaseMaterial3D
	var clone: BaseMaterial3D = src.duplicate() as BaseMaterial3D
	if clone == null:
		return null
	clone.cull_mode = BaseMaterial3D.CULL_FRONT
	_mirror_cull_front_cache[key] = clone
	return clone


## Build the local-X mirror of `source`: S = diag(-1, 1, 1). Per surface:
## vertices x negated; triangle winding reversed (0,1,2 -> 0,2,1); normals x
## negated; tangent x and tangent.w negated so the bitangent stays consistent
## (`w' = -w` because cross(S n, S t) = -S cross(n, t) for det S = -1). UVs,
## colours, custom channels, bones and weights are copied unchanged, and every
## surface keeps its authored Material (same resource, not a copy).
func _bake_mirrored_mesh(source: Mesh) -> ArrayMesh:
	if source == null:
		return null
	var surfaces: int = source.get_surface_count()
	if surfaces <= 0:
		return null
	var out: ArrayMesh = ArrayMesh.new()
	out.resource_name = "%s_mirrorX" % source.resource_name
	var total_bytes: int = 0
	for s: int in range(surfaces):
		var prim: int = source.surface_get_primitive_type(s)
		if prim != Mesh.PRIMITIVE_TRIANGLES:
			return null
		var arrays: Array = source.surface_get_arrays(s)
		if arrays.is_empty() or arrays.size() <= Mesh.ARRAY_VERTEX:
			return null
		var verts_v: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (verts_v is PackedVector3Array) or (verts_v as PackedVector3Array).is_empty():
			return null
		var verts: PackedVector3Array = (verts_v as PackedVector3Array).duplicate()
		for i: int in range(verts.size()):
			verts[i] = Vector3(-verts[i].x, verts[i].y, verts[i].z)
		arrays[Mesh.ARRAY_VERTEX] = verts
		var normals_v: Variant = arrays[Mesh.ARRAY_NORMAL]
		if normals_v is PackedVector3Array:
			var normals: PackedVector3Array = (normals_v as PackedVector3Array).duplicate()
			for i: int in range(normals.size()):
				normals[i] = Vector3(-normals[i].x, normals[i].y, normals[i].z)
			arrays[Mesh.ARRAY_NORMAL] = normals
		var tangents_v: Variant = arrays[Mesh.ARRAY_TANGENT]
		if tangents_v is PackedFloat32Array:
			var tangents: PackedFloat32Array = (tangents_v as PackedFloat32Array).duplicate()
			var ti: int = 0
			while ti + 3 < tangents.size():
				tangents[ti] = -tangents[ti]
				tangents[ti + 3] = -tangents[ti + 3]
				ti += 4
			arrays[Mesh.ARRAY_TANGENT] = tangents
		var idx_v: Variant = arrays[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array
		if idx_v is PackedInt32Array and (idx_v as PackedInt32Array).size() >= 3:
			idx = (idx_v as PackedInt32Array).duplicate()
		else:
			# Non-indexed surface: indexing it first lets the winding flip
			# without reordering every per-vertex attribute.
			idx = PackedInt32Array()
			idx.resize(verts.size())
			for i: int in range(verts.size()):
				idx[i] = i
		if idx.size() % 3 != 0:
			return null
		var ti2: int = 0
		while ti2 + 2 < idx.size():
			var tmp: int = idx[ti2 + 1]
			idx[ti2 + 1] = idx[ti2 + 2]
			idx[ti2 + 2] = tmp
			ti2 += 3
		arrays[Mesh.ARRAY_INDEX] = idx
		total_bytes += _mirror_arrays_bytes(arrays)
		# Source format flags preserve compression / attribute packing. The
		# mirror data test drives a real compressed surface through this path.
		out.add_surface_from_arrays(prim, arrays, [], {}, source.surface_get_format(s))
		out.surface_set_material(out.get_surface_count() - 1, source.surface_get_material(s))
	out.set_meta("mirror_baked", true)
	out.set_meta("mirror_source_id", source.get_instance_id())
	out.set_meta("mirror_bytes", total_bytes)
	return out


## Uncompressed byte estimate for the baked array set (the report's memory
## figure; Godot may store less when the source flags compress attributes).
static func _mirror_arrays_bytes(arrays: Array) -> int:
	var total: int = 0
	for a_v: Variant in arrays:
		if a_v == null:
			continue
		if a_v is PackedByteArray:
			total += (a_v as PackedByteArray).size()
		elif a_v is PackedInt32Array:
			total += (a_v as PackedInt32Array).size() * 4
		elif a_v is PackedInt64Array:
			total += (a_v as PackedInt64Array).size() * 8
		elif a_v is PackedFloat32Array:
			total += (a_v as PackedFloat32Array).size() * 4
		elif a_v is PackedFloat64Array:
			total += (a_v as PackedFloat64Array).size() * 8
		elif a_v is PackedVector2Array:
			total += (a_v as PackedVector2Array).size() * 8
		elif a_v is PackedVector3Array:
			total += (a_v as PackedVector3Array).size() * 12
		elif a_v is PackedVector4Array:
			total += (a_v as PackedVector4Array).size() * 16
		elif a_v is PackedColorArray:
			total += (a_v as PackedColorArray).size() * 16
	return total


func _mirror_log_split(mp: String, mode: String, pos_n: int, neg_n: int, bytes: int, surfaces: int) -> void:
	if _mirror_log_count >= MIRROR_LOG_LIMIT:
		_mirror_log_suppressed += 1
		return
	_mirror_log_count += 1
	print("MIRROR_SPLIT mp=%s mode=%s pos=%d neg=%d surfaces=%d bytes=%d" % [
		mp.left(96), mode, pos_n, neg_n, surfaces, bytes])


## ----- SplineMeshComponent deformation (RE-B-04) ---------------------------
## A UE `SplineMeshComponent` lofts its static mesh along an authored cubic
## Hermite spline: the mesh's local X axis is the splice axis (its bounds map
## to t = 0…1), and the cross-section (local Y = height, local Z = width after
## the UE→Godot axis swap) is stamped at each slice with the authored 2D
## scale, 2D offset and roll. tools/parse_tables.py:extract_levels() emits the
## authored params as `spline` on the mesh entry, already converted to
## component-local Godot metres/radians:
##   p0/t0/p1/t1        Vector3 (m)   spline endpoints + tangents
##   scale0/scale1      [a, b]        a = width (local Z), b = height (local Y)
##   offset0/offset1    Vector3 (m)   cross-section offset, local X always 0
##   roll0/roll1        float (rad)   roll about the tangent
## Without this the 469 authored spline pieces collapse onto their parent
## transform (1,080 exact duplicates the dedupe below then drops), so fences,
## railings, chains, driveways and the monorail render as one straight piece.
const SPLINE_AXIS_EPS: float = 1.0e-5

var _spline_mesh_cache: Dictionary = {} # ue_path + "||" + spline key -> Mesh


static func _spline_vec3(raw: Variant, fallback: Vector3) -> Vector3:
	# Already normalised: normalize_spline() is applied at the parse boundary
	# AND again inside spline_deform_mesh(), so it must be idempotent.
	if raw is Vector3:
		return raw as Vector3
	if raw is Array and (raw as Array).size() >= 3:
		var a: Array = raw as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


static func _spline_vec2(raw: Variant, fallback: Vector2) -> Vector2:
	if raw is Vector2:
		return raw as Vector2
	if raw is Array and (raw as Array).size() >= 2:
		var a: Array = raw as Array
		return Vector2(float(a[0]), float(a[1]))
	return fallback


static func _spline_float(raw: Variant, fallback: float) -> float:
	if raw is float or raw is int:
		return float(raw)
	return fallback


## Authored spline record, normalised once per batch. Keeping this in one
## place means the batch key, the cached mesh and the collider all use the
## identical parameter set.
func normalize_spline(sp: Dictionary) -> Dictionary:
	return {
		"p0": _spline_vec3(sp.get("p0"), Vector3.ZERO),
		"t0": _spline_vec3(sp.get("t0"), Vector3.ZERO),
		"p1": _spline_vec3(sp.get("p1"), Vector3.FORWARD),
		"t1": _spline_vec3(sp.get("t1"), Vector3.ZERO),
		"s0": _spline_vec2(sp.get("scale0"), Vector2.ONE),
		"s1": _spline_vec2(sp.get("scale1"), Vector2.ONE),
		"o0": _spline_vec3(sp.get("offset0"), Vector3.ZERO),
		"o1": _spline_vec3(sp.get("offset1"), Vector3.ZERO),
		"r0": _spline_float(sp.get("roll0"), 0.0),
		"r1": _spline_float(sp.get("roll1"), 0.0),
	}


## Cubic Hermite position at t (USplineMeshComponent::BuildSplineMesh).
func spline_point(sp: Dictionary, t: float) -> Vector3:
	var p0: Vector3 = sp["p0"]
	var t0: Vector3 = sp["t0"]
	var p1: Vector3 = sp["p1"]
	var t1: Vector3 = sp["t1"]
	var t2: float = t * t
	var t3: float = t2 * t
	return p0 * (2.0 * t3 - 3.0 * t2 + 1.0) \
		+ t0 * (t3 - 2.0 * t2 + t) \
		+ p1 * (-2.0 * t3 + 3.0 * t2) \
		+ t1 * (t3 - t2)


## d/dt of spline_point().
func spline_tangent(sp: Dictionary, t: float) -> Vector3:
	var p0: Vector3 = sp["p0"]
	var t0: Vector3 = sp["t0"]
	var p1: Vector3 = sp["p1"]
	var t1: Vector3 = sp["t1"]
	var t2: float = t * t
	return p0 * (6.0 * t2 - 6.0 * t) \
		+ t0 * (3.0 * t2 - 4.0 * t + 1.0) \
		+ p1 * (-6.0 * t2 + 6.0 * t) \
		+ t1 * (3.0 * t2 - 2.0 * t)


## Local-space slice frame at t: X = tangent, Y = cross-section height,
## Z = cross-section width, origin shifted by the authored 2D offset.
func spline_frame(sp: Dictionary, t: float) -> Transform3D:
	var origin: Vector3 = spline_point(sp, t)
	var dir: Vector3 = spline_tangent(sp, t)
	var x_axis: Vector3 = dir.normalized()
	if x_axis.length() < 0.5:
		# Degenerate tangents (a zero-length authored segment) fall back to the
		# chord so the piece still has a usable orientation.
		x_axis = ((sp["p1"] as Vector3) - (sp["p0"] as Vector3)).normalized()
	if x_axis.length() < 0.5:
		x_axis = Vector3.RIGHT
	var up: Vector3 = Vector3.UP
	if absf(x_axis.dot(up)) > 0.999:
		up = Vector3.FORWARD
	var z_axis: Vector3 = x_axis.cross(up).normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	var roll: float = lerpf(float(sp["r0"]), float(sp["r1"]), t)
	if absf(roll) > SPLINE_AXIS_EPS:
		var rot := Basis(x_axis, roll)
		y_axis = (rot * y_axis).normalized()
		z_axis = (rot * z_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	var off: Vector3 = (sp["o0"] as Vector3).lerp(sp["o1"] as Vector3, t)
	return Transform3D(basis, origin + basis * off)


## Lofts `base` along the authored spline. Every vertex of every surface is
## re-placed, so multi-surface meshes keep their surfaces, materials and UVs.
##
## Rebuilt through SurfaceTool on purpose: the imported GLB surfaces carry a
## compressed/custom attribute format, and `ArrayMesh.add_surface_from_arrays`
## rejects the arrays `surface_get_arrays` hands back (the custom-channel format
## flags are not part of that array). SurfaceTool re-emits the standard
## attributes (position, normal, tangent, UV, UV2, colour) in a clean format,
## which is exactly what a loft needs.
func spline_deform_mesh(base: Mesh, sp_in: Dictionary) -> ArrayMesh:
	if base == null:
		return null
	var sp: Dictionary = normalize_spline(sp_in)
	var aabb: AABB = base.get_aabb()
	var x_min: float = aabb.position.x
	var span: float = aabb.size.x
	var inv_span: float = 0.0 if absf(span) < SPLINE_AXIS_EPS else 1.0 / span
	var w0: float = (sp["s0"] as Vector2).x
	var h0: float = (sp["s0"] as Vector2).y
	var w1: float = (sp["s1"] as Vector2).x
	var h1: float = (sp["s1"] as Vector2).y
	var out := ArrayMesh.new()
	for s: int in range(base.get_surface_count()):
		var arrays: Array = base.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var verts_v: Variant = arrays[Mesh.ARRAY_VERTEX]
		if not (verts_v is PackedVector3Array):
			continue
		var verts: PackedVector3Array = verts_v as PackedVector3Array
		var count: int = verts.size()
		if count == 0:
			continue
		var new_verts := PackedVector3Array()
		new_verts.resize(count)
		var normals_v: Variant = arrays[Mesh.ARRAY_NORMAL]
		var has_normals: bool = normals_v is PackedVector3Array and (normals_v as PackedVector3Array).size() == count
		var normals: PackedVector3Array = normals_v as PackedVector3Array if has_normals else PackedVector3Array()
		var new_norms := PackedVector3Array()
		if has_normals:
			new_norms.resize(count)
		for i: int in range(count):
			var v: Vector3 = verts[i]
			var t: float = clampf((v.x - x_min) * inv_span, 0.0, 1.0)
			var frame: Transform3D = spline_frame(sp, t)
			new_verts[i] = frame * Vector3(0.0, v.y * lerpf(h0, h1, t), v.z * lerpf(w0, w1, t))
			if has_normals:
				new_norms[i] = (frame.basis * normals[i]).normalized()
		var index_v: Variant = arrays[Mesh.ARRAY_INDEX]
		var indices: PackedInt32Array = index_v as PackedInt32Array if index_v is PackedInt32Array else PackedInt32Array()
		var uv_v: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var uvs: PackedVector2Array = uv_v as PackedVector2Array if uv_v is PackedVector2Array else PackedVector2Array()
		var uv2_v: Variant = arrays[Mesh.ARRAY_TEX_UV2]
		var uvs2: PackedVector2Array = uv2_v as PackedVector2Array if uv2_v is PackedVector2Array else PackedVector2Array()
		var col_v: Variant = arrays[Mesh.ARRAY_COLOR]
		var cols: PackedColorArray = col_v as PackedColorArray if col_v is PackedColorArray else PackedColorArray()
		var tan_v: Variant = arrays[Mesh.ARRAY_TANGENT]
		var tans: PackedFloat32Array = tan_v as PackedFloat32Array if tan_v is PackedFloat32Array else PackedFloat32Array()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var emit: int = indices.size() if indices.size() > 0 else count
		for k: int in range(emit):
			var vi: int = indices[k] if indices.size() > 0 else k
			if vi < 0 or vi >= count:
				continue
			if uvs.size() == count:
				st.set_uv(uvs[vi])
			if uvs2.size() == count:
				st.set_uv2(uvs2[vi])
			if cols.size() == count:
				st.set_color(cols[vi])
			if tans.size() >= (vi + 1) * 4:
				var t3: float = clampf((verts[vi].x - x_min) * inv_span, 0.0, 1.0)
				var tb: Basis = spline_frame(sp, t3).basis
				var tv: Vector3 = tb * Vector3(tans[vi * 4], tans[vi * 4 + 1], tans[vi * 4 + 2])
				if tv.length() > 0.5:
					st.set_tangent(Plane(tv.x, tv.y, tv.z, tans[vi * 4 + 3]))
			if has_normals:
				st.set_normal(new_norms[vi])
			st.add_vertex(new_verts[vi])
		var before: int = out.get_surface_count()
		st.commit(out)
		if out.get_surface_count() > before:
			var src_mat: Material = base.surface_get_material(s)
			if src_mat != null:
				out.surface_set_material(out.get_surface_count() - 1, src_mat)
	return out


## Deformed spline mesh for one authored record, cached per UE path + params.
func _get_spline_mesh(ue_path: String, base_mesh: Mesh, spline_rec: Dictionary, variant_key: String = "") -> Mesh:
	if base_mesh == null:
		return base_mesh
	var key: String = ue_path + "||" + variant_key + "||spline||" + str(normalize_spline(spline_rec))
	if _spline_mesh_cache.has(key):
		return _spline_mesh_cache[key] as Mesh
	var deformed: ArrayMesh = spline_deform_mesh(base_mesh, spline_rec)
	if deformed == null:
		return base_mesh
	_spline_mesh_cache[key] = deformed
	return deformed


## Collider for a deformed spline piece. The authored collision is a swept
## hull, so a trimesh of the deformed surface is the closest authored answer;
## the static-mesh box heuristic would seal the arc the loft describes.
func spline_shape_for(mesh: Mesh) -> Dictionary:
	var out: Dictionary = {"shape": null, "shape_offset": Vector3.ZERO}
	if mesh == null:
		return out
	var aabb: AABB = mesh.get_aabb()
	if aabb.size.length() <= 0.45:
		return out
	out["shape"] = mesh.create_trimesh_shape()
	out["shape_offset"] = Vector3.ZERO
	return out


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
	# Phase 2 G-2: the static bookcase glass candidates are collected while the
	# draw items are built; a new load must not inherit the previous map's nodes.
	_gc_static_glass.clear()
	return {
		"batches": {},
		"batches_nocol": {},
		"batches_far": {},
		# Cross-sublevel exact-duplicate guard. Periphery/POI/Gameplay and
		# baked SplineMeshComponents contained 424 instances / 276 surplus
		# draws at identical transforms (z-fighting / wall flicker).
		"mesh_dedupe": {},
		# Authored sublevel graph (RE-B-01). Keyed by the level key
		# ("OldManor/OldManor_PathBlockers"), not the res:// path.
		"sublevel_keys": {},
		"level_instance_targets": {},
		"streaming_levels": [] as Array,
		"lights": [] as Array,
		"gc": [] as Array,
		"gc_leaves": [] as Array,
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
			"guard_spawns": [] as Array,
			# Authored APatrolPath records (actor/class/loop_type/points[]) in
			# world metres, merged verbatim from each sublevel so the mission
			# controller can assign real patrols instead of the 6x6 m square.
			"patrol_paths": [] as Array,
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
			# P0b parity-only counters (default 0; see ParityGovernance).
			"parity_skipped_expansion_meshes": 0,
			"parity_skipped_expansion_caps": 0,
			"parity_skipped_expansion_nodes": 0,
			"parity_skipped_expansion_rules": {} as Dictionary,
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

	# Presence arrays: filter poses that resolved false. Guard records keep their
	# authored bucket/layers; a record is dropped only when its `pos` is
	# suppressed. (Vector3 entries are still accepted for legacy callers.)
	var gs_in: Array = stats.get("guard_spawns", []) as Array
	var gs_out: Array = []
	for gv: Variant in gs_in:
		if gv is Vector3:
			if not suppress.has(_sv_pos_key(gv)):
				gs_out.append(gv)
		elif gv is Dictionary:
			var gd: Dictionary = gv as Dictionary
			var gp_v: Variant = gd.get("pos", null)
			if gp_v is Vector3 and not suppress.has(_sv_pos_key(gp_v)):
				gs_out.append(gd)
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
	# P0b parity governance: resolve the flag + tracked rule classes once per
	# build. When off (the default) every downstream gate is a no-op and the
	# shipped load path is byte-for-byte unchanged.
	_parity_only = ParityGovernance.enabled()
	_content_rule_classes = ParityGovernance.load_rule_classes() if _parity_only else {}
	# W10-A evidence: per-load planar-convex skip delta. `AuthoredCollision` is
	# process-global (payload parsed once), so a map load takes a snapshot here
	# and `_finalize` reports the difference. One `load_sublevels*` call is one
	# map load, which is what makes the probe's per-map number exact. A load that
	# generates no collision must not force the payload parse; it reports 0.
	var col_base: Dictionary = {}
	if generate_collision or AuthoredCollision.is_loaded():
		col_base = AuthoredCollision.stats() as Dictionary
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
		## W9-P1 authored-collision accounting (distinct paths unless noted).
		"col_paths": {} as Dictionary,
		"col_path_counts": {} as Dictionary,
		"col_authored_hull": 0,
		"col_authored_prims": 0,
		"col_authored_elements": 0,
		"col_authored_complex": 0,
		"col_no_record": 0,
		"col_absent": 0,
		"col_no_collision": 0,
		"col_query_only": 0,
		"col_reduced": 0,
		"col_complex_default": 0,
		"col_elements": 0,
		"col_convex": 0,
		"col_authored_instances": 0,
		"col_authored_shapes": 0,
		"col_heuristic_shapes": 0,
		"col_paths_seen": 0,
		"col_scale_baked": 0,
		## W10-A evidence: named reduced meshes + this load's planar skips.
		"col_reduced_names": [] as Array,
		"col_planar_base_skipped": int(col_base.get("planar_convex_skipped", 0)),
		"col_planar_base_paths": (col_base.get("planar_skipped_paths", []) as Array).duplicate(),
		## W9-P1 probe safety (see `_col_deadline_ms`): 0 = no deadline.
		"col_deadline_ms": _col_deadline_ms,
		"col_deadline_hit": 0,
		"col_progress": _col_progress,
		"occluders": 0,
		"missing_meshes": [] as Array,
		"missing_mesh_count": 0,
		"duplicate_meshes": 0,
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
		# W1p prototypes: resolved once per build so repeated env lookups are not
		# on the hot draw-item path. Both are off by default.
		"periph_range": _resolve_periph_range(),
		"periph_range_applied": 0,
		"periph_range_kept_smaller": 0,
		"periph_range_skipped_mixed": 0,
		"periph_range_skipped_other": 0,
		"merge_mode": _resolve_merge_mode(),
		"merge_candidates": 0,
		"merge_cells": 0,
		"merge_nodes": 0,
		"merge_surfaces_before": 0,
		"merge_surfaces_after": 0,
		"merge_skipped_visuals": 0,
		"merge_skipped": {} as Dictionary,
	}


## RE-P-15: TAT-2 additions that are not shipped art must be machine-identifiable
## (AGENTS rule 7). Tags the most recently added child of `parent` with the
## `expansion` meta + the shared group and counts it, exactly like prep_skyline.
func _note_expansion_placement(parent: Node, kind_name: String, result: Dictionary) -> void:
	if parent == null or parent.get_child_count() == 0:
		return
	var node: Node = parent.get_child(parent.get_child_count() - 1)
	node.set_meta("expansion", true)
	node.set_meta("expansion_kind", kind_name)
	if not node.is_in_group("expansion_placements"):
		node.add_to_group("expansion_placements")
	result["expansion_placements"] = int(result.get("expansion_placements", 0)) + 1


## P0b parity-only mesh gate. Returns true when this `.tatlevel.json` mesh entry
## must be excluded from the load. Only `content_rule`-tagged entries are
## eligible: `parity_restoration` stays, `tat2_expansion` and unknown classes are
## skipped and counted per rule (fail closed, never a crash). This mirrors
## ParityGovernance.filter_level_payload() exactly.
func _parity_skip_mesh(m_dict: Dictionary, result: Dictionary) -> bool:
	var rid: String = str(m_dict.get("content_rule", ""))
	if rid == "":
		return false
	var decision: Dictionary = ParityGovernance.mesh_decision(m_dict, _content_rule_classes, true)
	if not bool(decision.get("skip", false)):
		return false
	var key: String = "parity_skipped_expansion_caps" if bool(m_dict.get("content_cap", false)) else "parity_skipped_expansion_meshes"
	result[key] = int(result.get(key, 0)) + 1
	var by_rule: Dictionary = result["parity_skipped_expansion_rules"] as Dictionary
	by_rule[rid] = int(by_rule.get(rid, 0)) + 1
	return true


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
## Authored-light acceptance rule, shared by the loader and the T07 render probe
## (game/tests/probe_render_t07.gd) so the count can never drift from the build.
## TATShadowFade* components are authored-off shadow proxies (intensity 0.0 in
## the CDO); intensity <= 0 and visible=false are authored-off too.
static func light_record_accepted(l: Dictionary) -> bool:
	if "TATShadowFade" in str(l.get("type", "")):
		return false
	var i_v: Variant = l.get("intensity")
	var intensity: float = 10.0 if i_v == null else float(i_v)
	if intensity <= 0.0:
		return false
	return l.get("visible") != false


## Integer-metre position key for the loader's cross-sublevel light dedupe.
static func light_record_key(l: Dictionary) -> String:
	var p_v: Variant = l.get("pos", null)
	if not (p_v is Array) or (p_v as Array).size() < 3:
		return "0,0,0"
	var p: Array = p_v as Array
	return "%d,%d,%d" % [roundi(float(p[0])), roundi(float(p[1])), roundi(float(p[2]))]


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
	var sublevel_tag: String = _sublevel_tag(json_path)
	var result: Dictionary = acc["result"]
	result["authored_meshes"] = int(result.get("authored_meshes", 0)) + (data_dict.get("meshes", []) as Array).size()
	# Authored sublevel bookkeeping (RE-B-01/03): the key lets the loader
	# reconcile the supplied list against the persistent map's own
	# LevelStreaming graph and against LevelInstance merges.
	var sublevel_key: String = _level_key_from_res(json_path)
	if sublevel_key != "":
		(acc["sublevel_keys"] as Dictionary)[sublevel_key] = true
	for li_var: Variant in (data_dict.get("level_instances", []) as Array):
		(acc["level_instance_targets"] as Dictionary)[str(li_var)] = sublevel_key
	for sl_var: Variant in (data_dict.get("streaming_levels", []) as Array):
		if sl_var is Dictionary:
			(acc["streaming_levels"] as Array).append(sl_var)
	var landscapes: Array = acc["landscapes"]
	for lc in data_dict.get("landscapes", []):
		if lc is Dictionary:
			landscapes.append(lc)

	# W10-A3-GC: destructible broken-state overlays and their intact leaves.
	# Both are per-component records (not batched) because the runtime swaps
	# one owner's leaf/layer pair on break.
	var gc_entries: Array = acc["gc"]
	for gc_var: Variant in (data_dict.get("gc", []) as Array):
		if gc_var is Dictionary:
			var gc_rec: Dictionary = (gc_var as Dictionary).duplicate(true)
			gc_rec["source_sublevel"] = sublevel_tag
			gc_entries.append(gc_rec)
	var gc_leaf_entries: Array = acc["gc_leaves"]
	for gl_var: Variant in (data_dict.get("gc_leaves", []) as Array):
		if gl_var is Dictionary:
			var gl_rec: Dictionary = (gl_var as Dictionary).duplicate(true)
			gl_rec["source_sublevel"] = sublevel_tag
			gc_leaf_entries.append(gl_rec)

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

	# Every map's candelabras carry authored NS_Candelabras_Flame placements, so
	# the loader must not also spawn its procedural candle quad at the same wick
	# (doubled flames, RE-E-09). Collect the authored wick positions and test each
	# candle mesh against them: a per-wick test, not the old Den-only file scope,
	# so Guildhall and OldManor de-duplicate too.
	var authored_flame_positions: Array = []
	for n_v: Variant in data_dict.get("niagara", []):
		if not (n_v is Dictionary):
			continue
		var n_asset: String = str((n_v as Dictionary).get("asset", "")).to_lower()
		if "candelabras_flame" in n_asset and not n_asset.ends_with("_flame_out"):
			var fpos_v: Variant = (n_v as Dictionary).get("pos", null)
			if fpos_v is Array and (fpos_v as Array).size() >= 3:
				var fpos: Array = fpos_v as Array
				authored_flame_positions.append(Vector3(float(fpos[0]), float(fpos[1]), float(fpos[2])))
	for m in data_dict.get("meshes", []):
		if not (m is Dictionary):
			continue
		var m_dict: Dictionary = m
		var mp: String = str(m_dict.get("mesh", ""))
		if mp == "":
			continue
		# P0b parity-only: a content-override-tagged mesh whose rule is not a
		# restoration is excluded whole (expansion content) or fail-closed
		# (unclassified), counted per rule. Default off = no change.
		if _parity_only and _parity_skip_mesh(m_dict, result):
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
		# FIX_SPEC P0 #5: the authored BP_MoonShape_C_5 window backlight is the
		# one moonshape plane that must render. Unhide just this instance, nudge
		# it to the outer face of the glass (x=5.75) and apply the authored
		# 1.6 x 2.0 pane scale. Every other moonshape billboard stays hidden.
		if _is_den_window_backlight(mp, m_dict):
			m_dict = m_dict.duplicate(true)
			m_dict["hidden_in_game"] = false
			var bpos_v: Variant = m_dict.get("pos", [5.75, 41.2624, 266.8386])
			var bpos: Array = (bpos_v as Array).duplicate()
			if bpos.size() >= 3:
				bpos[0] = 5.75
			m_dict["pos"] = bpos
			m_dict["scale"] = [1.6, 1.0, 2.0]
			# Authored CPD EmisMultiply is 1.2 in UE-linear. At the Den AGX
			# exposure 1.9 that clips the pane to a white rectangle and seeds
			# a 4-mip bloom sheet, so cap the port multiplier at 0.25: below
			# the 0.85 glow threshold it still reads as a luminous cool pane
			# (authored colour 0.351, 0.797, 1.0) without the overexposed
			# white slab or room-wide bloom spill.
			var bcpd_v: Variant = m_dict.get("cpd", null)
			if bcpd_v is Array and (bcpd_v as Array).size() >= 5:
				var bcpd: Array = (bcpd_v as Array).duplicate()
				bcpd[1] = minf(float(bcpd[1]), 0.25)
				m_dict["cpd"] = bcpd
			result["den_window_backlight"] = int(result.get("den_window_backlight", 0)) + 1
		# Authored moon billboards render as gray quads now that the real sky
		# carries the moon disc (texture stripped by cooking); hide them and
		# count them, never spawning geometry/collision for them.
		elif _is_moonshape_mesh(mp):
			result["moonshape_hidden"] = int(result.get("moonshape_hidden", 0)) + 1
			continue
		var low_mp: String = mp.to_lower()
		# P1-W (V6-04, KF28): the authored `SM_BlockerWard_*` shard cluster is
		# the shipped ward visual. The old blanket `"blocker" in low_mp` filter
		# dropped all 376 instances and left the flat `tat_ward` BoxMesh as the
		# only thing on screen (the "near-opaque flat violet box" in the
		# comparison). The shards are now spawned per instance into the
		# `ward_shards` group, hidden and collision-free, and the device layer
		# hands each ward its own cluster. Fog/sky blockers stay dropped.
		var is_ward_shard: bool = low_mp.contains("/sm_blockerward_")
		if not is_ward_shard and ("fogsheet" in low_mp or "fogsphere" in low_mp or "volumetric" in low_mp or "skysphere" in low_mp):
			# RE-B-14: 16 authored instances (15 SM_FogSphere, 1 SM_SkySphere)
			# are intentionally invisible, but the drop used to be uncounted.
			result["name_skipped"] = int(result.get("name_skipped", 0)) + 1
			continue
		# SM_WardBox is the authored ward-zone trigger volume (8 instances at
		# the foyer/upper-floor wards). It is not the visible ward VFX: the
		# cooked material is an emissive white debug shell, and a camera inside
		# one renders a fully clipped frame (p50/p95 = 1.0). The visible arcane
		# ward is driven by the ward VFX/shader, so skip the debug shell and
		# count it instead of spawning geometry.
		if low_mp.ends_with("/sm_wardbox"):
			result["ward_box_hidden"] = int(result.get("ward_box_hidden", 0)) + 1
			continue
		# /Game/Test/Art/Primitives/SM_Shape_* are the editor's test
		# primitives (sphere 115, plane 40, narrow capsule 16 campaign-wide =
		# 171 instances, 58 of them in the Guildhall). All 171 slots bind
		# MI_Default_White - an untextured white debug material - so they
		# spawn as flat white geometry in every map and the reference build
		# shows none of them. They are editorial debris, not art: skip and
		# count them, like SM_WardBox above. Scoped to that exact authored
		# folder and stem, so /Engine/BasicShapes volumes (cubes/planes used
		# as gameplay volumes) are never touched.
		if _is_debug_shape_mesh(low_mp, m_dict):
			result["debug_shape_hidden"] = int(result.get("debug_shape_hidden", 0)) + 1
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
		# P1-W: ward shards are spawned hidden and collision-free; the ward
		# device owns their visibility (KF28).
		if is_ward_shard:
			hidden_in_game = true
			m_dict["no_collide"] = true
			result["ward_shard_spawned"] = int(result.get("ward_shard_spawned", 0)) + 1
		# W10-A3: producer-emitted per-entry collision opt-out (authored turret
		# props). Batches split on the flag so a no-collide placement can never
		# share a collider bucket with collidable masonry of the same UE path.
		var no_collide_raw: Variant = m_dict.get("no_collide", false)
		var no_collide: bool = no_collide_raw is bool and (no_collide_raw as bool)
		# Authored SplineMeshComponent params: each distinct spline is its own
		# loft, so it must be its own batch (and its own collider shape).
		var spline_raw: Variant = m_dict.get("spline", null)
		var spline_rec: Dictionary = {}
		var spline_key: String = ""
		if spline_raw is Dictionary:
			spline_rec = normalize_spline(spline_raw as Dictionary)
			spline_key = str(spline_rec)
		var bkey: String = mp if ov_key == "" else mp + "||" + ov_key
		if has_cpd:
			bkey += "||cpd"
		if hidden_in_game:
			bkey += "||hidden"
		if no_collide:
			bkey += "||nocol"
		if spline_key != "":
			bkey += "||spline||" + spline_key
		var dedupe_key: String = bkey + "||" + str(tr)
		var seen_meshes: Dictionary = acc.get("mesh_dedupe", {}) as Dictionary
		if seen_meshes.has(dedupe_key):
			result["duplicate_meshes"] = int(result.get("duplicate_meshes", 0)) + 1
			continue
		seen_meshes[dedupe_key] = true
		if not batches.has(bkey):
			batches[bkey] = {
				"mp": mp,
				"override_materials": ov_arr,
				"override_key": ov_key,
				"trs": [] as Array[Transform3D],
				"cpds": [] as Array[Color],
				"sources": [] as Array[String],
				"source_sublevel": sublevel_tag,
				"source_sublevels": {} as Dictionary,
				"hidden_in_game": hidden_in_game,
				"no_collide": no_collide,
			}
			if spline_key != "":
				(batches[bkey] as Dictionary)["spline"] = spline_rec
		var batch_rec: Dictionary = batches[bkey] as Dictionary
		if mp == BEAM_CARD_MESH or is_ward_shard or mp == GC_BOOKCASE_GLASS_MESH:
			# One MeshInstance3D per authored card/shard so the device layer can
			# drive its powered/active state (a MultiMesh hides instances
			# together). Phase 2 G-2: the bookcase glass pane is also split so
			# one owner's door can be hidden when its authored broken overlay
			# takes over (the intact pane is static-batch geometry).
			batch_rec["per_instance"] = true
		var arr: Array[Transform3D] = batch_rec["trs"]
		arr.append(tr)
		var src_arr: Array[String] = batch_rec["sources"]
		src_arr.append(sublevel_tag)
		var src_counts: Dictionary = batch_rec["source_sublevels"]
		src_counts[sublevel_tag] = int(src_counts.get(sublevel_tag, 0)) + 1
		if has_cpd:
			var carr: Array[Color] = batch_rec["cpds"]
			carr.append(cpd_color)
		var prop_pos: Vector3 = tr.origin
		if "candelabra" in low_mp or "candle" in low_mp or "brazier" in low_mp or "torch" in low_mp:
			var candle_arr: Array = result["candelabra_positions"]
			candle_arr.append(prop_pos)
			# TAT2_CANDLE_FLAMES: the wick heights below are PORT CONSTANTS, not
			# authored data (the cooked candle meshes carry no wick socket). The
			# quad is TAT-2 expansion content and is labelled as such.
			var wick_y: float = 0.16
			if "candelabrafloor" in low_mp:
				wick_y = 1.35
			elif "candelabra" in low_mp:
				wick_y = 0.46
			elif "brazier" in low_mp or "torch" in low_mp:
				wick_y = 0.55
			wick_y *= tr.basis.get_scale().y
			var wick: Vector3 = prop_pos + Vector3(0.0, wick_y, 0.0)
			if _authored_flame_near(authored_flame_positions, wick):
				result["candle_flames_suppressed"] = int(result.get("candle_flames_suppressed", 0)) + 1
			elif not ParityGovernance.expansion_nodes_allowed():
				# P0b parity-only: the procedural wick quad is TAT-2 node
				# content, not shipped art. Count it; spawn nothing.
				result["parity_skipped_expansion_nodes"] = int(result.get("parity_skipped_expansion_nodes", 0)) + 1
			else:
				_VfxManager.spawn_candle_flame(parent, wick)
				_note_expansion_placement(parent, "candle_flame", result)
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
		if not light_record_accepted(l_dict):
			continue
		var lkey: String = light_record_key(l_dict)
		var seen_lights: Dictionary = acc["seen_lights"]
		if seen_lights.has(lkey):
			continue
		seen_lights[lkey] = true
		# Tag the five authored ThievesDen_Geo practicals so the light builder
		# can apply the Den-only energy/attenuation/cone response without
		# touching the global mapping. The moon spot (intensity 0.025) alone
		# stays shadowless; the four warm practicals cast authored shadows.
		if json_path.to_lower().find("thievesden/thievesden_geo") >= 0:
			l_dict = l_dict.duplicate(true)
			l_dict["_den_spot"] = true
			l_dict["_den_shadow"] = _to_float(l_dict.get("intensity"), 0.0) > 1.0
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
		elif ("MissionSpawner_Character" in cls or "Guard" in cls) and not cls.begins_with("BP_AirshipGuard_"):
			# A2: the SkyboxGeo airship actors are set dressing, not mission
			# guards: BP_AirshipGuard_Patrol/Swarm sit at x -1164..341,
			# y 122..394, z -807..679 (≈1 km outside the play space). Catching
			# them with the "Guard" substring made the Guildhall pool 119 when
			# the authored mission pool is 116.
			# P0a: the authored SpawnBucket + Layers travel with the record; the
			# mission selection must never receive a position-only guard.
			var gs: Array = result["guard_spawns"]
			var spawn_layers: Array = []
			var marker_layers_v: Variant = mk.get("spawn_layers", [])
			if marker_layers_v is Array:
				for layer_v: Variant in (marker_layers_v as Array):
					spawn_layers.append(str(layer_v))
			gs.append({
				"pos": p,
				"name": str(mk.get("name", "")),
				"class": cls,
				"spawn_bucket": str(mk.get("spawn_bucket", "")),
				"spawn_layers": spawn_layers,
				"source_file": json_path,
			})
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
			# RE-P-05: 309 authored component markers carried no
			# RelativeLocation, so they arrived at exactly (0, 0, 0). No
			# consumer reads door_spawns today, but the next one would have
			# spawned ~307 doors on the world origin. Refuse the origin and
			# count it; the producer now emits the parent transform instead.
			if p == Vector3.ZERO:
				result["origin_markers_skipped"] = int(result.get("origin_markers_skipped", 0)) + 1
				continue
			var ds: Array = result["door_spawns"]
			ds.append(p)
			_note_scene_element(result, "door", mk, p)
		elif cls in LOOT_CONTAINER_CLASSES:
			# Openable loot container marker: meshes already live in the level
			# geometry, so only the marker transform is recorded (existing
			# keys above are untouched). W9-P2 B2: the authored lock keys (when
			# the marker has them) travel with the record unchanged — this is
			# the only place the loader may drop them.
			var lc_arr: Array = result["loot_containers"]
			var sc_raw: Array = mk.get("scale", [1, 1, 1])
			var sc := Vector3.ONE
			if sc_raw.size() >= 3:
				sc = Vector3(float(sc_raw[0]), float(sc_raw[1]), float(sc_raw[2]))
			var lc_rec := {
				"class": cls,
				"owner": str(mk.get("name", "")),
				"pos": p,
				"basis": (mk.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1]) as Array).duplicate(),
				"scale": sc,
			}
			lc_rec.merge(marker_lock_fields(mk))
			lc_arr.append(lc_rec)
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
			var sp_rec: Dictionary = (sp as Dictionary).duplicate()
			sp_rec["_source_sublevel"] = sublevel_tag
			(acc["splines"] as Array).append(sp_rec)

	# Swinging-door entries: passed through verbatim for the door wave.
	for sd in data_dict.get("swinging_doors", []):
		if sd is Dictionary:
			(result["swinging_doors"] as Array).append(sd)

	# Authored patrol paths: tools/parse_tables.py already converts point
	# positions to Godot metres/axes, so these records are merged verbatim
	# (actor, class, loop_type, points[] with pos/wait/facing/yaw/type).
	for pp in data_dict.get("patrol_paths", []):
		if pp is Dictionary:
			(result["patrol_paths"] as Array).append(pp)


## True for the editor's untextured test primitives only:
## `/Game/Test/Art/Primitives/SM_Shape_{Sphere,Plane,NarrowCapsule}`, no authored
## override material, and an authored slot that still binds MI_Default_White.
## All 171 campaign-wide placements match (58 in the Guildhall) and they render
## as flat white geometry. An override disqualifies the instance because a
## designer deliberately re-purposed the primitive: the Den's window backlight
## is exactly `SM_Shape_Plane` + MI_MoonshapeEmissive.
func _is_debug_shape_mesh(low_path: String, entry: Dictionary) -> bool:
	if low_path.find("/test/art/primitives/") < 0:
		return false
	if not low_path.get_file().split(".")[0].begins_with("sm_shape_"):
		return false
	if not _extract_override_materials(entry).is_empty():
		return false
	var mesh_path: String = str(entry.get("mesh", ""))
	var slots_v: Variant = _mesh_mats_db.get(mesh_path, null)
	if not (slots_v is Array):
		slots_v = _mesh_mats_db_lower.get(mesh_path.to_lower(), null)
	if not (slots_v is Array):
		return false
	for s: Variant in (slots_v as Array):
		if str(s).to_lower().find("mi_default_white") >= 0:
			return true
	return false


## True only for the authored BP_MoonShape_C_5 window backlight plane. The
## other seven moonshape billboards remain subject to _is_moonshape_mesh().
## Exact authored placement: UE cm (571.09, 4126.24, 26683.86) -> port
## (5.7109, 41.2624, 266.8386), SM_Shape_Plane + MI_MoonshapeEmissive.
func _is_den_window_backlight(mp: String, m_dict: Dictionary) -> bool:
	if not mp.to_lower().ends_with("/sm_shape_plane"):
		return false
	var has_moon_mat: bool = false
	for ov: String in _extract_override_materials(m_dict):
		if ov.to_lower().find("mi_moonshapeemissive") >= 0:
			has_moon_mat = true
			break
	if not has_moon_mat:
		return false
	var pos_v: Variant = m_dict.get("pos", [])
	if not (pos_v is Array) or (pos_v as Array).size() < 3:
		return false
	var pa: Array = pos_v as Array
	return absf(float(pa[0]) - 5.7109) < 0.01 \
		and absf(float(pa[1]) - 41.2624) < 0.01 \
		and absf(float(pa[2]) - 266.8386) < 0.01


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


## Provenance summary for one draw item. A batch can combine instances from
## several sublevels (PeripheryA shares mesh paths with the POI), so per-cell
## source tags are kept instead of trusting the first batch contributor.
static func _source_summary(sources: Array) -> Dictionary:
	var counts: Dictionary = {}
	for s_var: Variant in sources:
		var tag: String = str(s_var)
		if tag == "":
			continue
		counts[tag] = int(counts.get(tag, 0)) + 1
	var tags: Array[String] = []
	for k: Variant in counts.keys():
		tags.append(str(k))
	tags.sort()
	var single: String = "unknown"
	if tags.size() == 1:
		single = tags[0]
	elif tags.size() > 1:
		single = "mixed"
	return {
		"source_sublevel": single,
		"source_sublevels": tags,
		"source_counts": counts,
	}


## P4.2: apportion one draw item's per-source counts between its positive and
## negative batches. Every key satisfies pos + neg == item exactly; the negative
## share uses the largest-remainder method with a sorted-key tie-break, so
## there is no rounding loss and the result is deterministic. `neg_instances`
## is the number of negative-determinant instances in the item; the denominator
## is the item's source-count total (which equals the item count on real data).
## This keeps PERF_CENSUS.source_sublevels summing to the pre-split baseline:
## the two nodes together contribute exactly the item's original counts.
static func split_source_counts(source_counts: Dictionary, total_instances: int, neg_instances: int) -> Dictionary:
	var pos: Dictionary = {}
	var neg: Dictionary = {}
	var csum: int = 0
	for k: Variant in source_counts.keys():
		csum += maxi(int(source_counts[k]), 0)
	if csum <= 0 or total_instances <= 0 or neg_instances <= 0:
		for k0: Variant in source_counts.keys():
			pos[str(k0)] = maxi(int(source_counts[k0]), 0)
		return {"pos": pos, "neg": neg}
	if neg_instances >= total_instances:
		for k1: Variant in source_counts.keys():
			neg[str(k1)] = maxi(int(source_counts[k1]), 0)
		return {"pos": pos, "neg": neg}
	var neg_target: int = mini(neg_instances, csum)
	var keys: Array = source_counts.keys()
	keys.sort()
	var remainders: Array = []
	var assigned: int = 0
	for k2: Variant in keys:
		var key: String = str(k2)
		var c: int = maxi(int(source_counts[k2]), 0)
		var numer: int = c * neg_target
		var base: int = numer / csum
		neg[key] = base
		assigned += base
		remainders.append({"key": key, "rem": numer % csum, "cap": c})
	var need: int = neg_target - assigned
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: int = int(a["rem"])
		var rb: int = int(b["rem"])
		if ra != rb:
			return ra > rb
		return str(a["key"]) < str(b["key"]))
	for r: Dictionary in remainders:
		if need <= 0:
			break
		var rkey: String = str(r["key"])
		if int(neg.get(rkey, 0)) < int(r["cap"]):
			neg[rkey] = int(neg.get(rkey, 0)) + 1
			need -= 1
	if need > 0:
		# Defensive only: largest-remainder allocation cannot leave a residual
		# when neg_target <= csum, but a malformed count set must still not lose
		# or invent a record.
		for k3: Variant in keys:
			var k3s: String = str(k3)
			while need > 0 and int(neg.get(k3s, 0)) < maxi(int(source_counts[k3]), 0):
				neg[k3s] = int(neg.get(k3s, 0)) + 1
				need -= 1
			if need <= 0:
				break
	for k4: Variant in keys:
		var k4s: String = str(k4)
		var total_k: int = maxi(int(source_counts[k4]), 0)
		var neg_k: int = int(neg.get(k4s, 0))
		if neg_k <= 0:
			neg.erase(k4s)
		else:
			neg[k4s] = neg_k
		var pos_k: int = total_k - neg_k
		if pos_k > 0:
			pos[k4s] = pos_k
	return {"pos": pos, "neg": neg}


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
		var sources: Array = []
		var hidden_in_game: bool = false
		var no_collide: bool = false
		var per_instance: bool = false
		var spline_rec: Dictionary = {}
		if bval is Dictionary:
			var bdict: Dictionary = bval as Dictionary
			mp = str(bdict.get("mp", ""))
			ov_key = str(bdict.get("override_key", ""))
			per_instance = bool(bdict.get("per_instance", false))
			var bov_raw: Variant = bdict.get("override_materials", [])
			if bov_raw is Array:
				for s_var: Variant in (bov_raw as Array):
					ov_arr.append(str(s_var))
			var trs_raw: Variant = bdict.get("trs", [])
			if trs_raw is Array:
				trs = trs_raw as Array
			var sources_raw: Variant = bdict.get("sources", [])
			if sources_raw is Array:
				sources = sources_raw as Array
			var cpds_raw: Variant = bdict.get("cpds", [])
			if cpds_raw is Array:
				for c_var: Variant in (cpds_raw as Array):
					if c_var is Color:
						cpds.append(c_var as Color)
			var hid_raw: Variant = bdict.get("hidden_in_game", false)
			hidden_in_game = hid_raw is bool and (hid_raw as bool)
			var nocol_raw: Variant = bdict.get("no_collide", false)
			no_collide = nocol_raw is bool and (nocol_raw as bool)
			var spl_raw: Variant = bdict.get("spline", null)
			if spl_raw is Dictionary:
				spline_rec = spl_raw as Dictionary
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
			var far_src: Dictionary = _source_summary(sources)
			items.append({
				"mp": mp,
				"override_materials": ov_arr,
				"override_key": ov_key,
				"trs": trs,
				"cpds": cpds if has_cpds else ([] as Array[Color]),
				"hidden_in_game": hidden_in_game,
				"no_collide": no_collide,
				"collide": collide,
				"cell": Vector2i.ZERO,
				"spline": spline_rec,
				"far": true,
				"source_sublevel": far_src["source_sublevel"],
				"source_sublevels": far_src["source_sublevels"],
				"source_counts": far_src["source_counts"],
			})
			continue
		if per_instance:
			# Authored beam cards: one draw item (and later one MeshInstance3D)
			# per card so powered state can be shown per detector.
			for pi: int in range(trs.size()):
				var tr_pi: Transform3D = trs[pi]
				var pi_cpds: Array[Color] = []
				if has_cpds:
					pi_cpds.append(cpds[pi])
				var pi_src: Dictionary = _source_summary([str(sources[pi])] if pi < sources.size() else [])
				items.append({
					"mp": mp,
					"override_materials": ov_arr,
					"override_key": ov_key,
					"trs": [tr_pi],
					"cpds": pi_cpds,
					"hidden_in_game": hidden_in_game,
					"no_collide": no_collide,
					"collide": collide,
					"cell": _cell_of(tr_pi),
					"spline": spline_rec,
					"per_instance": true,
					"source_sublevel": pi_src["source_sublevel"],
					"source_sublevels": pi_src["source_sublevels"],
					"source_counts": pi_src["source_counts"],
				})
			continue
		if trs.size() == 1:
			var single_tr: Transform3D = trs[0]
			var single_cpds: Array[Color] = cpds if has_cpds else ([] as Array[Color])
			var single_src: Dictionary = _source_summary([sources[0]] if sources.size() == 1 else [])
			items.append({
				"mp": mp,
				"override_materials": ov_arr,
				"override_key": ov_key,
				"trs": trs,
				"cpds": single_cpds,
				"hidden_in_game": hidden_in_game,
				"no_collide": no_collide,
				"collide": collide,
				"cell": _cell_of(single_tr),
				"spline": spline_rec,
				"source_sublevel": single_src["source_sublevel"],
				"source_sublevels": single_src["source_sublevels"],
				"source_counts": single_src["source_counts"],
			})
			continue
		var cells: Dictionary = {}
		var cell_cpds_map: Dictionary = {}
		var cell_sources_map: Dictionary = {}
		for idx: int in range(trs.size()):
			var tr: Transform3D = trs[idx]
			var ck: String = "%d_%d" % [floori(tr.origin.x / CHUNK_SIZE), floori(tr.origin.z / CHUNK_SIZE)]
			if not cells.has(ck):
				cells[ck] = [] as Array
				cell_sources_map[ck] = [] as Array
				if has_cpds:
					cell_cpds_map[ck] = [] as Array[Color]
			var cell_arr: Array = cells[ck]
			cell_arr.append(tr)
			var cell_src_arr: Array = cell_sources_map[ck]
			cell_src_arr.append(str(sources[idx]) if idx < sources.size() else "unknown")
			if has_cpds:
				var cell_carr: Array[Color] = cell_cpds_map[ck]
				cell_carr.append(cpds[idx])
		for ck_var in cells.keys():
			var ck_str: String = str(ck_var)
			var parts: PackedStringArray = ck_str.split("_")
			var cell: Vector2i = Vector2i(int(parts[0]), int(parts[1]))
			var item_cpds: Array[Color] = cell_cpds_map[ck_var] if has_cpds else ([] as Array[Color])
			var cell_src: Dictionary = _source_summary(cell_sources_map[ck_var])
			items.append({
				"mp": mp,
				"override_materials": ov_arr,
				"override_key": ov_key,
				"trs": cells[ck_var],
				"cpds": item_cpds,
				"hidden_in_game": hidden_in_game,
				"no_collide": no_collide,
				"collide": collide,
				"cell": cell,
				"spline": spline_rec,
				"source_sublevel": cell_src["source_sublevel"],
				"source_sublevels": cell_src["source_sublevels"],
				"source_counts": cell_src["source_counts"],
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


## The merge prototype may only fold instances whose culling outcome is the
## same "shadow on, no distance fade" default. Anything the policy would cull,
## dither or shadow-disable keeps its own node (the cell mesh cannot carry
## per-source ranges without changing the authored look).
func _culling_policy_signature(low_mp: String, mesh: Mesh) -> String:
	var aabb_len: float = mesh.get_aabb().size.length()
	if _has_token(low_mp, STRUCTURAL_NO_FADE_TOKENS):
		return "structural"
	if _has_token(low_mp, CLUTTER_TOKENS) and aabb_len < 2.0:
		return "clutter"
	if aabb_len < TINY_PROP_LEN:
		return "tiny"
	if aabb_len < SMALL_PROP_LEN:
		return "small"
	return "default"


## W6L roof collision policy, also the gate/test surface: "convex" for a pitched
## /roofs/ shell, "box" for a flat roof surface and the roof props that keep the
## exact AABB, "none" for anything outside /roofs/. The split is measured from
## the mesh (see ROOF_TOP_BAND_M / ROOF_FLAT_TOP_FRAC), not from the file name:
## the EndA/EndB gable caps are pitched shells whose top coverage measures
## 0.000-0.014, while a deck measures 1.00 and the fascia band 1.90. Passing a
## mesh avoids a second GLB load; without one the geometry is loaded once and
## cached per path.
func roof_collision_kind(ue_path: String, mesh: Mesh = null) -> String:
	var low: String = ue_path.to_lower()
	if low.find(ROOF_PATH_TOKEN) < 0:
		return "none"
	if _has_token(low, ROOF_BOX_TOKENS):
		return "box"
	var top_frac: float = -1.0
	if mesh != null:
		top_frac = _measure_roof_top_coverage(mesh)
		_roof_geom_cache[low] = top_frac
	else:
		top_frac = _roof_geometry_for_path(ue_path, low)
	if top_frac < 0.0:
		# Unreadable mesh: no shape is emitted anyway, and box is the safer
		# answer than inventing a hull from geometry that failed to load.
		return "box"
	return "box" if top_frac >= ROOF_FLAT_TOP_FRAC else "convex"


## Fraction of the AABB footprint covered by upward-facing area inside
## ROOF_TOP_BAND_M of the AABB top. 1.0 (or more) is a flat, standable surface;
## a pitched shell only touches the band along its ridge. A mesh with no
## footprint (a vertical plane) reports 1.0 so a degenerate hull is never
## requested for a flat card.
func _measure_roof_top_coverage(mesh: Mesh) -> float:
	var aabb: AABB = mesh.get_aabb()
	var footprint: float = aabb.size.x * aabb.size.z
	if footprint <= 0.0001:
		return 1.0
	var top_y: float = aabb.position.y + aabb.size.y - ROOF_TOP_BAND_M
	var top_area: float = 0.0
	for s: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var tri_count: int = idx.size() / 3
		var sequential: bool = idx.is_empty()
		if sequential:
			tri_count = verts.size() / 3
		for t: int in range(tri_count):
			var ia: int = t * 3 if sequential else idx[t * 3]
			var ib: int = t * 3 + 1 if sequential else idx[t * 3 + 1]
			var ic: int = t * 3 + 2 if sequential else idx[t * 3 + 2]
			if ia >= verts.size() or ib >= verts.size() or ic >= verts.size():
				continue
			var va: Vector3 = verts[ia]
			var vb: Vector3 = verts[ib]
			var vc: Vector3 = verts[ic]
			var cross: Vector3 = (vb - va).cross(vc - va)
			if cross.length_squared() <= 0.0:
				continue
			var ny: float = absf(cross.normalized().y)
			if ny < 0.5:
				continue
			if (va.y + vb.y + vc.y) / 3.0 < top_y:
				continue
			top_area += 0.5 * cross.length() * ny
	return top_area / footprint


## One-time geometry load for the one-argument roof_collision_kind() form (the
## tests and any caller that only has a path). Never routed through
## _get_mesh_and_shape(): that is the caller of roof_collision_kind().
func _roof_geometry_for_path(ue_path: String, low_key: String) -> float:
	if _roof_geom_cache.has(low_key):
		return float(_roof_geom_cache[low_key])
	var top_frac: float = -1.0
	var res_path: String = _mesh_res_any_case(ue_path)
	if res_path != "":
		var packed: Variant = load(res_path)
		if packed is PackedScene:
			var inst: Node = (packed as PackedScene).instantiate()
			var mi: MeshInstance3D = _find_first_mesh(inst)
			if mi != null and mi.mesh != null:
				top_frac = _measure_roof_top_coverage(mi.mesh)
			inst.free()
	_roof_geom_cache[low_key] = top_frac
	return top_frac


## Case-insensitive mesh resolution for path-only callers (tests pass the
## authored UE path; some call sites already lower-case it). Matched against the
## exact mesh paths in mesh_materials.json, then resolved through the normal
## exact-case resolver.
func _mesh_res_any_case(ue_path: String) -> String:
	var direct: String = _ue_mesh_to_res(ue_path)
	if direct != "":
		return direct
	var low: String = ue_path.to_lower().split(".")[0]
	for k: Variant in _mesh_mats_db.keys():
		var cand: String = str(k)
		if cand.to_lower().split(".")[0] == low:
			var res: String = _ue_mesh_to_res(cand)
			if res != "":
				return res
	return ""


func _is_roof_convex_surface(low_path: String, mesh: Mesh = null) -> bool:
	return roof_collision_kind(low_path, mesh) == "convex"


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
	# F9: inset the occluder 10 cm per side so its faces never sit exactly
	# coplanar with the wall faces that spawned them (coplanar occluder/geometry
	# pairs pop as the camera moves). The old 2 cm inset was still coplanar with
	# the 4 cm wall trim; a smaller occluder under-occludes, which is safe.
	box.size = Vector3(maxf(aabb.size.x - 0.20, 0.1), maxf(aabb.size.y - 0.20, 0.1), maxf(aabb.size.z - 0.20, 0.1))
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
func _add_collider(ctx: Dictionary, cell: Vector2i, shape: Shape3D, tr: Transform3D, shape_offset: Vector3, kind: String = "building", label: String = "", bake_scale: bool = false) -> void:
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
	if label != "":
		cs.set_meta("ue_mesh", label)
	var sc: Vector3 = tr.basis.get_scale()
	cs.transform = Transform3D(tr.basis.orthonormalized(), tr * shape_offset)
	if bake_scale:
		# W9-P1: the authored shape already carries the instance scale (Jolt
		# cannot non-uniformly scale capsule/convex/trimesh shapes and logs an
		# error per shape per tick if asked). `cs.scale` stays identity.
		cs.scale = Vector3.ONE
		ctx["col_scale_baked"] = int(ctx.get("col_scale_baked", 0)) + 1
	else:
		cs.scale = Vector3(maxf(absf(sc.x), 0.05), maxf(absf(sc.y), 0.05), maxf(absf(sc.z), 0.05))
	body.add_child(cs)
	ctx["collision_shapes"] = int(ctx.get("collision_shapes", 0)) + 1
	ctx[part_key] = part_count + 1


## W9-P1: emit N authored shapes for one placed instance. Same per-body bucket,
## same building/total caps and the same `ue_mesh` meta as `_add_collider`,
## which is called once per (instance, shape) so the budget can never be
## bypassed by a multi-element mesh. `offset` is the element-local transform
## (rotation + centre) that `_add_collider` composes with the instance transform.
func _add_collider_shapes(ctx: Dictionary, cell: Vector2i, shapes: Array, offsets: Array, trs: Array, count: int, kind: String = "building", label: String = "") -> void:
	var n: int = mini(count, trs.size())
	ctx["col_authored_shapes"] = int(ctx.get("col_authored_shapes", 0)) + shapes.size() * n
	var deadline: int = int(ctx.get("col_deadline_ms", 0))
	for i: int in range(n):
		if deadline > 0 and Time.get_ticks_msec() > deadline:
			# Named, counted stop: never a silent wedge (see `_col_deadline_ms`).
			ctx["col_deadline_hit"] = int(ctx.get("col_deadline_hit", 0)) + 1
			return
		var tr_c: Transform3D = trs[i]
		if absf(tr_c.basis.determinant()) < 0.0001:
			continue
		# W9-P1 (F2): Jolt rejects a non-uniform `CollisionShape3D.scale` for
		# capsule/convex/trimesh shapes (it logs "Failed to correctly scale shape
		# … not supported by Jolt Physics" every tick and silently uses an
		# averaged uniform scale). Bake such an instance scale into the shape
		# instead — exact for boxes/hulls/trimeshes, mean-radius for capsule and
		# sphere (see `AuthoredCollision.scaled_variant`). Uniform scales keep
		# the cheap shared shape and the CS scale Jolt accepts.
		var sc: Vector3 = tr_c.basis.get_scale()
		var ax: float = maxf(absf(sc.x), 0.05)
		var ay: float = maxf(absf(sc.y), 0.05)
		var az: float = maxf(absf(sc.z), 0.05)
		var uniform: bool = absf(ax - ay) <= 0.0001 * ay and absf(ay - az) <= 0.0001 * az
		var use_shapes: Array = shapes
		if not uniform:
			use_shapes = (AuthoredCollision.scaled_variant(label, {"shapes": shapes}, Vector3(ax, ay, az))["shapes"]) as Array
		for s: int in range(use_shapes.size()):
			var sh: Shape3D = use_shapes[s] as Shape3D
			if sh == null:
				continue
			var off: Transform3D = (offsets[s] as Transform3D) if s < offsets.size() else Transform3D.IDENTITY
			_add_collider(ctx, cell, sh, tr_c * off, Vector3.ZERO, kind, label, not uniform)


## W9-P1: per-load collision-source accounting, once per UE path (the draw item
## loop visits a path many times). Feeds the `AUTHORED_COLLISION` summary, the
## returned stats dict and `probe_collision_authored.gd`.
## `col_authored_hull` counts every path with a non-absent classification (the
## collision accounting identity); `col_authored_elements` is the subset whose
## collider is authored simple geometry, `col_authored_complex` the subset that
## falls back to the render trimesh, `col_no_record` the packages with no
## BodySetup dump at all (no collider), and `col_authored_prims` the subset
## encoded as one primitive/coalesced shape per instance.
func _count_collision_path(ctx: Dictionary, mp: String, info: Dictionary) -> void:
	var seen: Dictionary = ctx.get("col_paths", {}) as Dictionary
	if seen.has(mp):
		return
	seen[mp] = true
	ctx["col_paths"] = seen
	if bool(ctx.get("col_progress", false)) and seen.size() % 128 == 0:
		print("COL_PROGRESS paths=%d shapes=%d bodies=%d last=%s" % [
			seen.size(), int(ctx.get("collision_shapes", 0)),
			int(ctx.get("collision_bodies", 0)), mp])
	var col: Dictionary = info.get("col", {}) as Dictionary
	var source: String = str(col.get("source", "absent"))
	var total: int = int((ctx.get("col_path_counts", {}) as Dictionary).get(mp, 1))
	ctx["col_placed_instances"] = int(ctx.get("col_placed_instances", 0)) + total
	if source == "absent":
		ctx["col_absent"] = int(ctx.get("col_absent", 0)) + 1
		return
	ctx["col_authored_hull"] = int(ctx.get("col_authored_hull", 0)) + 1
	ctx["col_elements"] = int(ctx.get("col_elements", 0)) + int(col.get("elements", 0))
	ctx["col_convex"] = int(ctx.get("col_convex", 0)) + int(col.get("convex", 0))
	ctx["col_authored_instances"] = int(ctx.get("col_authored_instances", 0)) + total
	# W10-P2: the collision class separates authored simple elements from the
	# render-trimesh fallback and from "no record at all". Only `elements`
	# counts as authored-coverage: the trimesh is a fallback to render geometry
	# and a no-record package has no authored collision.
	var cls: String = str(col.get("class", ""))
	if cls == "elements":
		ctx["col_authored_elements"] = int(ctx.get("col_authored_elements", 0)) + 1
	elif cls == "complex":
		ctx["col_authored_complex"] = int(ctx.get("col_authored_complex", 0)) + 1
		ctx["col_complex_default"] = int(ctx.get("col_complex_default", 0)) + 1
	elif cls == "no_record":
		ctx["col_no_record"] = int(ctx.get("col_no_record", 0)) + 1
	if source == "prims" or source == "complex_default":
		ctx["col_authored_prims"] = int(ctx.get("col_authored_prims", 0)) + 1
	if source == "no_collision":
		ctx["col_no_collision"] = int(ctx.get("col_no_collision", 0)) + 1
	if bool(col.get("reduced", false)):
		ctx["col_reduced"] = int(ctx.get("col_reduced", 0)) + 1
		# W10-A evidence: name every reduced mesh, with the per-load placement
		# count the cost cap used and the shape count actually emitted. The
		# per-mesh `elements` is the authored count from `resolve()`.
		(ctx["col_reduced_names"] as Array).append({
			"path": mp,
			"elements": int(col.get("elements", 0)),
			"instances": total,
			"shapes": (info.get("shapes", []) as Array).size(),
		})
	if str(col.get("enabled", "")) == "QueryOnly":
		# Port decision: Godot has no per-shape query-only flag, so the shape is
		# kept on the world layer (a StaticBody3D answers traces and physics).
		# RE-A1 §B5 proposes a dedicated layer for HidingSpot bushes; that is a
		# gameplay-mask change, not an encoding change, and is left as a risk.
		ctx["col_query_only"] = int(ctx.get("col_query_only", 0)) + 1


## W9-P1: heuristic-path shape demand, once per UE path. Only used where the
## per-instance shape count is not known to `_count_collision_path` (the spline
## loft and the `absent` meshes, whose single shape comes from the AABB branch).
func _count_heuristic_shapes(ctx: Dictionary, mp: String, per_instance: int) -> void:
	var seen: Dictionary = ctx.get("col_heur_paths", {}) as Dictionary
	if seen.has(mp):
		return
	seen[mp] = true
	ctx["col_heur_paths"] = seen
	var total: int = int((ctx.get("col_path_counts", {}) as Dictionary).get(mp, 1))
	ctx["col_heuristic_shapes"] = int(ctx.get("col_heuristic_shapes", 0)) + per_instance * total


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


## W1p: the cheapest HLOD test. PeripheryA is the packed city ring around the
## guildhall; fading its chunks at the requested range removes step-in draws
## without touching the interior sublevels. Mixed batches (PeripheryA shares
## mesh paths with the POI) are deliberately skipped because the cell node may
## contain interior instances; the census reports how many.
func _apply_periph_range(node: GeometryInstance3D, item: Dictionary, ctx: Dictionary) -> void:
	var requested: int = int(ctx.get("periph_range", 0))
	if requested <= 0 or node == null:
		return
	var source: String = str(item.get("source_sublevel", "unknown"))
	if not _is_periphery_a_source(source):
		var source_tags: Variant = item.get("source_sublevels", [])
		var has_periph: bool = false
		if source_tags is Array:
			for tag: Variant in (source_tags as Array):
				if _is_periphery_a_source(str(tag)):
					has_periph = true
					break
		if source == "mixed" and has_periph:
			ctx["periph_range_skipped_mixed"] = int(ctx.get("periph_range_skipped_mixed", 0)) + 1
		else:
			ctx["periph_range_skipped_other"] = int(ctx.get("periph_range_skipped_other", 0)) + 1
		return
	if bool(item.get("far", false)):
		ctx["periph_range_skipped_other"] = int(ctx.get("periph_range_skipped_other", 0)) + 1
		return
	var target: float = float(requested) + PERIPH_RANGE_PAD
	if node.visibility_range_end > 0.0 and node.visibility_range_end <= target:
		ctx["periph_range_kept_smaller"] = int(ctx.get("periph_range_kept_smaller", 0)) + 1
		return
	node.visibility_range_end = target
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	node.set_meta("periph_range_end", target)
	ctx["periph_range_applied"] = int(ctx.get("periph_range_applied", 0)) + 1


## One draw node for an already-partitioned batch. The pre-P4.2 path is
## unchanged for a batch without negative determinants; a split item calls
## this twice (positive batch with the authored mesh, negative batch with the
## mirror variant) so all culling/metadata policy stays in one place.
func _make_draw_batch_node(mesh_b: Mesh, trs_b: Array, cpds_b: Array[Color], use_cpd_b: bool) -> GeometryInstance3D:
	var bcount: int = trs_b.size()
	if bcount >= 2 or use_cpd_b:
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		if use_cpd_b:
			mm.use_custom_data = true
		mm.mesh = mesh_b
		mm.instance_count = bcount
		# Explicit tight bounds: Godot only frustum-culls a MultiMesh against
		# its AABB, so each 32m chunk gets the real merged instance bounds.
		var mesh_aabb: AABB = mesh_b.get_aabb()
		var chunk_aabb: AABB = AABB()
		var have_bounds: bool = false
		for i: int in range(bcount):
			var tr_i: Transform3D = trs_b[i]
			mm.set_instance_transform(i, tr_i)
			if use_cpd_b:
				mm.set_instance_custom_data(i, cpds_b[i])
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
		if use_cpd_b:
			mmi.material_override = _get_emissive_cpd_material()
		return mmi
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh_b
	mi.transform = trs_b[0]
	return mi


## Shared node policy/metadata path (extracted verbatim from the pre-P4.2
## single-node build so a split positive and negative node stay identical).
func _finish_draw_node(
		node: GeometryInstance3D,
		item: Dictionary,
		mp: String,
		low_mp: String,
		ov_arr: Array[String],
		mesh_for_policy: Mesh,
		source_sublevel: String,
		source_sublevels: Array[String],
		source_counts: Dictionary,
		far_item: bool,
		use_cpd: bool,
		hidden_in_game: bool,
		no_collide: bool,
		ctx: Dictionary,
		parent: Node3D) -> void:
	_apply_culling_policy(node, low_mp, mesh_for_policy)
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
	_apply_periph_range(node, item, ctx)
	node.set_meta("ue_mesh", mp)
	node.set_meta("decorative", not bool(item.get("collide", false)) or no_collide)
	node.set_meta("source_sublevel", source_sublevel)
	node.set_meta("source_sublevels", source_sublevels)
	node.set_meta("source_counts", source_counts)
	if not ov_arr.is_empty():
		node.set_meta("override_materials", ov_arr)
	if low_mp.contains("/sm_blockerward_"):
		# P1-W: authored ward shard; hidden until the ward device activates.
		node.name = "WardShard"
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		node.add_to_group("ward_shards")
		node.set_meta("ward_shard", true)
	if mp == BEAM_CARD_MESH:
		# Authored beam cards are per-instance so the device layer can bind
		# one card to each detector and drive its powered visibility. They
		# are additive/unlit: never a shadow caster.
		node.name = "BeamCard"
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_to_group("lightbeam_cards")
		node.set_meta("beam_card", true)
	if mp == GC_BOOKCASE_GLASS_MESH:
		# Phase 2 G-2: intact bookcase glass door in the static batch. Keep
		# the node addressable so `_build_gc_layers` can bind it as the
		# owner's leaf instead of emitting a duplicate. It keeps the same
		# culling/shadow outcome the batched instance had (the split is per
		# instance, not a visual change) and never joins the GC groups, so
		# the GC census stays emitted-leaf only. The per-instance split makes
		# the normal case a MeshInstance3D; a split negative pane is also a
		# MeshInstance3D and is registered here.
		var glass_mm: MultiMeshInstance3D = node as MultiMeshInstance3D
		if node is MeshInstance3D:
			node.name = "BookcaseGlass"
			node.set_meta("gc_static_leaf", true)
			node.set_meta("gc_no_collision", true)
			_gc_static_glass.append({
				"node": node,
				"source_sublevel": source_sublevel,
				"used": false,
			})
		else:
			# The per-instance split is required; a batched pane cannot be
			# hidden for one owner. Fail visible instead of silently leaving
			# the bookcase without an intact leaf.
			var glass_n: int = 1
			if glass_mm != null and glass_mm.multimesh != null:
				glass_n = glass_mm.multimesh.instance_count
			ctx["gc_static_leaf_multi"] = int(ctx.get("gc_static_leaf_multi", 0)) + glass_n
	parent.add_child(node)
	ctx["chunk_count"] = int(ctx.get("chunk_count", 0)) + 1


## Pure index partition for the render split: positive-determinant instances
## keep the authored mesh, negative-determinant instances go to a mirrored
## batch. Static so the headless data test drives exactly this code.
static func partition_mirror_indices(trs: Array) -> Dictionary:
	var pos: Array = []
	var neg: Array = []
	for i: int in range(trs.size()):
		var tr: Transform3D = trs[i]
		if tr.basis.determinant() < 0.0:
			neg.append(i)
		else:
			pos.append(i)
	return {"pos": pos, "neg": neg}


func _build_one_draw_item(item: Dictionary, parent: Node3D, ctx: Dictionary) -> int:
	var mp: String = str(item.get("mp", ""))
	var trs: Array = item.get("trs", [])
	if trs.is_empty():
		return 0
	var _pm0: int = Time.get_ticks_msec() if ctx.has("perf_mesh_ms") else 0
	var info: Dictionary = _get_mesh_and_shape(mp)
	if ctx.has("perf_mesh_ms"):
		ctx["perf_mesh_ms"] = int(ctx["perf_mesh_ms"]) + (Time.get_ticks_msec() - _pm0)
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
	# W10-A3: authored turret props opt out of building collision (and occluder
	# proxies) per entry. The producer emits `no_collide: true`; the loader must
	# never count them against the 32,000-shape budget.
	var no_collide_raw: Variant = item.get("no_collide", false)
	var no_collide: bool = no_collide_raw is bool and (no_collide_raw as bool)
	var far_raw: Variant = item.get("far", false)
	var far_item: bool = far_raw is bool and (far_raw as bool)
	var ov_key_eff: String = str(item.get("override_key", ""))
	if ov_key_eff == "":
		ov_key_eff = "|".join(ov_arr)
	if not use_cpd and not ov_arr.is_empty():
		mesh = _get_overridden_mesh(mp, mesh, ov_arr, ov_key_eff)
	# Authored spline deformation: the piece is lofted along its own authored
	# curve, so it cannot share the rigid mesh/collider of the same UE path.
	var spline_item_raw: Variant = item.get("spline", null)
	var spline_item: Dictionary = {}
	if spline_item_raw is Dictionary and not (spline_item_raw as Dictionary).is_empty():
		spline_item = spline_item_raw as Dictionary
		mesh = _get_spline_mesh(mp, mesh, spline_item, ov_key_eff)
		if mesh == null:
			return 0
	var low_mp: String = mp.to_lower()
	var source_sublevel: String = str(item.get("source_sublevel", "unknown"))
	var source_sublevels_raw: Variant = item.get("source_sublevels", [])
	var source_sublevels: Array[String] = []
	if source_sublevels_raw is Array:
		for sv: Variant in (source_sublevels_raw as Array):
			source_sublevels.append(str(sv))
	var source_counts_raw: Variant = item.get("source_counts", {})
	var source_counts: Dictionary = source_counts_raw as Dictionary if source_counts_raw is Dictionary else {}
	if source_counts.is_empty() and source_sublevel != "" and source_sublevel != "unknown" and source_sublevel != "mixed":
		source_counts = {source_sublevel: count}
	var skip_visual: bool = bool(item.get("_merge_skip_visual", false))
	if not skip_visual:
		var split: Dictionary = partition_mirror_indices(trs)
		var pos_indices: Array = split["pos"] as Array
		var neg_indices: Array = split["neg"] as Array
		if neg_indices.is_empty():
			var node: GeometryInstance3D = _make_draw_batch_node(mesh, trs, cpds, use_cpd)
			_finish_draw_node(node, item, mp, low_mp, ov_arr, mesh,
				source_sublevel, source_sublevels, source_counts, far_item,
				use_cpd, hidden_in_game, no_collide, ctx, parent)
		else:
			_mirror_draw_bases += neg_indices.size()
			_mirror_batches_split += 1
			# P4.2 accounting: the two nodes must contribute the item's
			# source_counts exactly once. Apportion by instance count with the
			# deterministic largest-remainder split; see split_source_counts().
			# The sublevel tag list stays the item's authored set (the split is
			# a draw-batch split, not a provenance rewrite); only the counts are
			# apportioned, so PERF_CENSUS.source_sublevels is unchanged.
			var source_split: Dictionary = split_source_counts(source_counts, count, neg_indices.size())
			var pos_source_counts: Dictionary = source_split["pos"] as Dictionary
			var neg_source_counts: Dictionary = source_split["neg"] as Dictionary
			# Split, preserving authored order inside each batch. `cpds` only
			# exists when `use_cpd`, so the parallel arrays stay aligned.
			var pos_trs: Array = []
			var neg_trs: Array = []
			var pos_cpds: Array[Color] = []
			var neg_cpds: Array[Color] = []
			for pi: int in range(pos_indices.size()):
				var ip: int = int(pos_indices[pi])
				pos_trs.append(trs[ip])
				if use_cpd:
					pos_cpds.append(cpds[ip])
			for ni: int in range(neg_indices.size()):
				var ineg: int = int(neg_indices[ni])
				neg_trs.append(trs[ineg])
				if use_cpd:
					neg_cpds.append(cpds[ineg])
			var variant: Dictionary
			if neg_trs.size() >= 2 or use_cpd:
				# MultiMesh: no per-instance cull state (and no surface
				# override), so negative instances get a baked mesh or a
				# whole-batch CULL_FRONT material clone.
				variant = _get_mirror_variant(mesh, ov_key_eff, not use_cpd)
				var mm_mode: String = str(variant.get("mode", "native"))
				if mm_mode == "baked":
					for bi: int in range(neg_trs.size()):
						var tr_b: Transform3D = neg_trs[bi]
						# B' = B * S; the baked mesh is already S * M, so the
						# world geometry is unchanged and det(B') > 0.
						neg_trs[bi] = Transform3D(tr_b.basis * MIRROR_LOCAL_FLIP, tr_b.origin)
				elif mm_mode == "cull_front":
					_mirror_cull_front_instances += neg_trs.size()
				elif mm_mode == "cull_disabled":
					_mirror_cull_disabled_instances += neg_trs.size()
				_mirror_multimesh_instances += neg_trs.size()
			else:
				# A one-instance batch is a MeshInstance3D. Godot already
				# compensates a negative-determinant MeshInstance3D; the bake
				# is opt-in for the synthetic probe's readback verdict.
				if _mirror_single_baked():
					variant = _get_mirror_variant(mesh, ov_key_eff, false)
					if str(variant.get("mode", "native")) == "baked":
						var tr_one: Transform3D = neg_trs[0]
						neg_trs[0] = Transform3D(tr_one.basis * MIRROR_LOCAL_FLIP, tr_one.origin)
					else:
						_mirror_unbaked += 1
				else:
					variant = {
						"mode": "native",
						"mesh": mesh,
						"material": null,
						"materials": [] as Array,
						"bytes": 0,
						"surfaces": mesh.get_surface_count(),
					}
				_mirror_single_instances += 1
			var neg_mesh: Mesh = variant.get("mesh", mesh) as Mesh
			if not pos_trs.is_empty():
				var pos_node: GeometryInstance3D = _make_draw_batch_node(mesh, pos_trs, pos_cpds, use_cpd)
				_finish_draw_node(pos_node, item, mp, low_mp, ov_arr, mesh,
					source_sublevel, source_sublevels, pos_source_counts, far_item,
					use_cpd, hidden_in_game, no_collide, ctx, parent)
			var neg_node: GeometryInstance3D = _make_draw_batch_node(neg_mesh, neg_trs, neg_cpds, use_cpd)
			neg_node.set_meta("mirror_neg", true)
			neg_node.set_meta("mirror_mode", str(variant.get("mode", "native")))
			neg_node.set_meta("mirror_instances", neg_trs.size())
			neg_node.set_meta("mirror_source_mesh", mp)
			# The test-facing apportionment proof: item = pos + neg exactly.
			neg_node.set_meta("mirror_item_source_counts", source_counts)
			neg_node.set_meta("mirror_pos_source_counts", pos_source_counts)
			neg_node.set_meta("mirror_neg_source_counts", neg_source_counts)
			var neg_mat: Variant = variant.get("material")
			if neg_mat is Material:
				neg_node.material_override = neg_mat as Material
			var neg_mats: Array = variant.get("materials", [] as Array) as Array
			if not neg_mats.is_empty():
				var mi_neg: MeshInstance3D = neg_node as MeshInstance3D
				if mi_neg != null:
					for s_neg: int in range(neg_mats.size()):
						if neg_mats[s_neg] is Material:
							mi_neg.set_surface_override_material(s_neg, neg_mats[s_neg] as Material)
			_finish_draw_node(neg_node, item, mp, low_mp, ov_arr, neg_mesh,
				source_sublevel, source_sublevels, neg_source_counts, far_item,
				use_cpd, hidden_in_game, no_collide, ctx, parent)
			_mirror_log_split(mp, str(variant.get("mode", "native")),
				pos_trs.size(), neg_trs.size(), int(variant.get("bytes", 0)),
				mesh.get_surface_count())
	if ctx.has("perf_build_ms"):
		ctx["perf_build_ms"] = int(ctx["perf_build_ms"]) + (Time.get_ticks_msec() - _pm0)

	var is_clutter: bool = _has_token(low_mp, CLUTTER_TOKENS)
	if not use_cpd and not hidden_in_game and not no_collide and bool(item.get("collide", false)) and bool(ctx.get("generate_collision", false)) and not is_clutter:
		var cell: Vector2i = item.get("cell", Vector2i.ZERO)
		if not spline_item.is_empty():
			# A lofted spline piece cannot share the rigid authored hull, so the
			# deformed mesh keeps the spline trimesh in every mode.
			var spline_shape: Dictionary = spline_shape_for(mesh)
			var sshape: Shape3D = spline_shape["shape"] as Shape3D
			_count_collision_path(ctx, mp, info)
			if sshape != null:
				var soff_s: Vector3 = spline_shape.get("shape_offset", Vector3.ZERO)
				_count_heuristic_shapes(ctx, mp, 1)
				for i2: int in range(count):
					var tr_s: Transform3D = trs[i2]
					if absf(tr_s.basis.determinant()) < 0.0001:
						continue
					_add_collider(ctx, cell, sshape, tr_s, soff_s, "building", mp)
		elif info.has("shapes"):
			# W9-P1 authored set: one CollisionShape3D per (shape, offset) on the
			# same StaticBody3D bucket, sharing the per-path Shape3D resources.
			var a_shapes: Array = info["shapes"] as Array
			var a_offsets: Array = info.get("shape_offsets", []) as Array
			_count_collision_path(ctx, mp, info)
			if not a_shapes.is_empty():
				_add_collider_shapes(ctx, cell, a_shapes, a_offsets, trs, count, "building", mp)
		else:
			var shape: Shape3D = info["shape"] as Shape3D
			# Count even when the heuristic produced no shape (0.45 gate /
			# non-blocking name): `absent` means "the heuristic decided this
			# path", so the census identity holds in `aabb` mode too.
			_count_collision_path(ctx, mp, info)
			if shape != null:
				var soff: Vector3 = info.get("shape_offset", Vector3.ZERO)
				var den_split: bool = _is_den_window_wall(low_mp) and shape is BoxShape3D
				_count_heuristic_shapes(ctx, mp, 1)
				for i2b: int in range(count):
					var tr_c: Transform3D = trs[i2b]
					if absf(tr_c.basis.determinant()) < 0.0001:
						continue
					if den_split:
						_add_den_window_split(ctx, cell, tr_c, shape as BoxShape3D, soff, "building", mp)
					elif low_mp.find("thievesden") >= 0 and shape is BoxShape3D:
						var grounded: Array = _ground_den_prop_shape(low_mp, shape as BoxShape3D, tr_c, soff)
						_add_collider(ctx, cell, grounded[0] as Shape3D, tr_c, grounded[1] as Vector3, "building", mp)
					else:
						_add_collider(ctx, cell, shape, tr_c, soff, "building", mp)

	if not use_cpd and not hidden_in_game and not no_collide and not is_clutter and not far_item and _qualifies_as_occluder(low_mp, mesh):
		for i3 in range(count):
			if int(ctx.get("occluders", 0)) >= MAX_OCCLUDERS:
				break
			var tr_o: Transform3D = trs[i3]
			_add_occluder(ctx, mesh, tr_o)
	return 0 if skip_visual else count


## W1p cell-merge prototype ("plain" mode only). Folds single-instance plain
## MeshInstance3D draw items that share a 32 m cell into one ArrayMesh with one
## surface per material. Collision and occluders are emitted per original item
## through the normal draw path (visuals skipped), so physics/occlusion are
## untouched. Every rejection is counted; any surface that cannot be
## reproduced rejects the whole cell and leaves its originals visible.
func _merge_skip_reason(ctx: Dictionary, reason: String) -> void:
	var skipped: Dictionary = ctx.get("merge_skipped", {}) as Dictionary
	skipped[reason] = int(skipped.get(reason, 0)) + 1


func _merge_material_reason(mat: Material) -> String:
	if mat == null:
		return "null_material"
	var std_mat: StandardMaterial3D = mat as StandardMaterial3D
	if std_mat != null:
		if std_mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return "transparent"
		if std_mat.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
			return "blend_mode"
		if std_mat.emission_enabled:
			return "emission"
		return ""
	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	if shader_mat != null:
		if shader_mat.shader == null:
			return "shader_null"
		if not MERGE_OPAQUE_SHADERS.has(shader_mat.shader.resource_path):
			return "shader_not_allowlisted"
		return ""
	return "material_type"


## Returns an empty dictionary when the item is not a candidate. Candidate
## checks are the fail-closed gate: static, single-instance, no CPD, opaque
## materials only, no gameplay-addressed mesh, and a culling outcome the cell
## mesh can reproduce (shadow on, no distance fade).
func _merge_candidate(item: Dictionary, ctx: Dictionary) -> Dictionary:
	var trs: Variant = item.get("trs", [])
	if not (trs is Array) or (trs as Array).size() != 1:
		_merge_skip_reason(ctx, "not_plain")
		return {}
	var cpds: Variant = item.get("cpds", [])
	if cpds is Array and not (cpds as Array).is_empty():
		_merge_skip_reason(ctx, "cpd")
		return {}
	if bool(item.get("hidden_in_game", false)):
		_merge_skip_reason(ctx, "hidden")
		return {}
	if bool(item.get("far", false)):
		_merge_skip_reason(ctx, "far")
		return {}
	var mp: String = str(item.get("mp", ""))
	if mp == "":
		_merge_skip_reason(ctx, "no_mp")
		return {}
	var low_mp: String = mp.to_lower()
	if _has_token(low_mp, MERGE_EXCLUDE_TOKENS):
		_merge_skip_reason(ctx, "gameplay_addressed")
		return {}
	var info: Dictionary = _get_mesh_and_shape(mp)
	var mesh: Mesh = info.get("mesh") as Mesh
	if mesh == null:
		_merge_skip_reason(ctx, "missing_mesh")
		return {}
	var ov_arr: Array[String] = _extract_override_materials(item)
	if not ov_arr.is_empty():
		var ov_key: String = str(item.get("override_key", ""))
		if ov_key == "":
			ov_key = "|".join(ov_arr)
		mesh = _get_overridden_mesh(mp, mesh, ov_arr, ov_key)
		if mesh == null:
			_merge_skip_reason(ctx, "override_mesh")
			return {}
	var tr: Transform3D = (trs as Array)[0]
	if tr.basis.determinant() <= 0.0001:
		_merge_skip_reason(ctx, "degenerate_transform")
		return {}
	var surface_count: int = mesh.get_surface_count()
	if surface_count <= 0:
		_merge_skip_reason(ctx, "no_surfaces")
		return {}
	for s: int in range(surface_count):
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			_merge_skip_reason(ctx, "non_triangles")
			return {}
		var mat: Material = mesh.surface_get_material(s)
		var mat_reason: String = _merge_material_reason(mat)
		if mat_reason != "":
			_merge_skip_reason(ctx, mat_reason)
			return {}
		var arrays: Array = mesh.surface_get_arrays(s)
		if not _merge_arrays_supported(arrays):
			_merge_skip_reason(ctx, "unsupported_arrays")
			return {}
	var cull_sig: String = _culling_policy_signature(low_mp, mesh)
	if cull_sig != "structural" and cull_sig != "default":
		_merge_skip_reason(ctx, "culling_" + cull_sig)
		return {}
	return {
		"item": item,
		"mesh": mesh,
		"mp": mp,
		"tr": tr,
		"surface_count": surface_count,
	}


func _merge_arrays_supported(arrays: Array) -> bool:
	if arrays.size() < Mesh.ARRAY_MAX:
		return false
	var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
	if not (verts is PackedVector3Array) or (verts as PackedVector3Array).is_empty():
		return false
	if arrays[Mesh.ARRAY_NORMAL] != null and not (arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array):
		return false
	if arrays[Mesh.ARRAY_TANGENT] != null and not (arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array):
		return false
	if arrays[Mesh.ARRAY_COLOR] != null and not (arrays[Mesh.ARRAY_COLOR] is PackedColorArray):
		return false
	if arrays[Mesh.ARRAY_TEX_UV] != null and not (arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array):
		return false
	if arrays[Mesh.ARRAY_TEX_UV2] != null and not (arrays[Mesh.ARRAY_TEX_UV2] is PackedVector2Array):
		return false
	if arrays[Mesh.ARRAY_INDEX] != null and not (arrays[Mesh.ARRAY_INDEX] is PackedInt32Array):
		return false
	for attr: int in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM3 + 1):
		if arrays[attr] != null and not (arrays[attr] is PackedFloat32Array):
			return false
	for attr2: int in range(Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS + 1):
		if arrays[attr2] != null:
			return false
	return true


static func _merge_empty_like(src: Variant) -> Variant:
	match typeof(src):
		TYPE_PACKED_VECTOR3_ARRAY:
			return PackedVector3Array()
		TYPE_PACKED_VECTOR2_ARRAY:
			return PackedVector2Array()
		TYPE_PACKED_COLOR_ARRAY:
			return PackedColorArray()
		TYPE_PACKED_FLOAT32_ARRAY:
			return PackedFloat32Array()
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array()
	return null


## Keep the authored custom-channel format (RGBA8/UV etc.) but drop flags that
## describe storage we do not reproduce: compression, 16-bit indices, 8-bone
## weights and dynamic update. The merged index array is int32.
static func _merge_normalize_format(fmt: int) -> int:
	return fmt & ~((1 << 2) | (1 << 3) | (1 << 4) | (1 << 5))


static func _merge_append_packed(existing: Variant, incoming: Variant) -> Variant:
	if existing == null:
		existing = _merge_empty_like(incoming)
	match typeof(incoming):
		TYPE_PACKED_VECTOR3_ARRAY:
			var v3: PackedVector3Array = existing as PackedVector3Array
			v3.append_array(incoming as PackedVector3Array)
			return v3
		TYPE_PACKED_VECTOR2_ARRAY:
			var v2: PackedVector2Array = existing as PackedVector2Array
			v2.append_array(incoming as PackedVector2Array)
			return v2
		TYPE_PACKED_COLOR_ARRAY:
			var col: PackedColorArray = existing as PackedColorArray
			col.append_array(incoming as PackedColorArray)
			return col
		TYPE_PACKED_FLOAT32_ARRAY:
			var f32: PackedFloat32Array = existing as PackedFloat32Array
			f32.append_array(incoming as PackedFloat32Array)
			return f32
		TYPE_PACKED_INT32_ARRAY:
			var i32: PackedInt32Array = existing as PackedInt32Array
			i32.append_array(incoming as PackedInt32Array)
			return i32
	return null


## Combine candidates into one ArrayMesh. Surface order is first-seen material
## order, so a two-material cell produces exactly two surfaces in authored
## order. Returns {ok, ...} or {ok=false, reason}; the caller leaves originals
## visible on failure.
func _build_merge_cell_mesh(candidates: Array, ctx: Dictionary) -> Dictionary:
	var groups: Array = []
	var group_by_mat: Dictionary = {}
	var aabb: AABB = AABB()
	var have_aabb: bool = false
	var ue_paths: Array[String] = []
	var instances: int = 0
	var sources: Array = []
	var collide: bool = false
	for cand_var: Variant in candidates:
		var cand: Dictionary = cand_var as Dictionary
		var item: Dictionary = cand["item"] as Dictionary
		var mesh: Mesh = cand["mesh"] as Mesh
		var tr: Transform3D = cand["tr"] as Transform3D
		var mp: String = str(cand["mp"])
		instances += 1
		collide = collide or bool(item.get("collide", false))
		sources.append(str(item.get("source_sublevel", "unknown")))
		if ue_paths.size() < 64 and not ue_paths.has(mp):
			ue_paths.append(mp)
		var world_aabb: AABB = tr * mesh.get_aabb()
		if not have_aabb:
			aabb = world_aabb
			have_aabb = true
		else:
			aabb = aabb.merge(world_aabb)
		var normal_basis: Basis = tr.basis.inverse().transposed()
		for s: int in range(mesh.get_surface_count()):
			var mat: Material = mesh.surface_get_material(s)
			if mat == null:
				return {"ok": false, "reason": "null_material"}
			var mat_id: int = mat.get_instance_id()
			var group_index: int = int(group_by_mat.get(mat_id, -1))
			var surface_format: int = 0
			if mesh is ArrayMesh:
				surface_format = _merge_normalize_format((mesh as ArrayMesh).surface_get_format(s))
			if group_index < 0:
				var new_arrays: Array = []
				new_arrays.resize(Mesh.ARRAY_MAX)
				groups.append({
					"material": mat,
					"arrays": new_arrays,
					"vertex_count": 0,
					"index": PackedInt32Array(),
					"format": surface_format,
				})
				group_index = groups.size() - 1
				group_by_mat[mat_id] = group_index
			var group: Dictionary = groups[group_index]
			if int(group["format"]) != surface_format:
				return {"ok": false, "reason": "format_mismatch"}
			var group_arrays: Array = group["arrays"] as Array
			var surface_arrays: Array = mesh.surface_get_arrays(s)
			if not _merge_arrays_supported(surface_arrays):
				return {"ok": false, "reason": "unsupported_arrays"}
			var verts: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var vcount: int = verts.size()
			var offset: int = int(group["vertex_count"])
			# Attribute set must match across every surface in the same material
			# bucket; a mismatch would silently drop UVs/normals/custom data from
			# one mesh.
			if offset > 0:
				for attr: int in range(0, Mesh.ARRAY_CUSTOM3 + 1):
					var has_attr: bool = surface_arrays[attr] != null
					var group_has_attr: bool = group_arrays[attr] != null
					if has_attr != group_has_attr:
						return {"ok": false, "reason": "attribute_mismatch"}
			for i: int in range(vcount):
				verts[i] = tr * verts[i]
			group_arrays[Mesh.ARRAY_VERTEX] = _merge_append_packed(group_arrays[Mesh.ARRAY_VERTEX], verts)
			var normals_v: Variant = surface_arrays[Mesh.ARRAY_NORMAL]
			if normals_v is PackedVector3Array:
				var normals: PackedVector3Array = (normals_v as PackedVector3Array).duplicate()
				for i2: int in range(normals.size()):
					var n: Vector3 = normal_basis * normals[i2]
					normals[i2] = n.normalized() if n.length_squared() > 0.0000001 else Vector3.UP
				group_arrays[Mesh.ARRAY_NORMAL] = _merge_append_packed(group_arrays[Mesh.ARRAY_NORMAL], normals)
			var tangents_v: Variant = surface_arrays[Mesh.ARRAY_TANGENT]
			if tangents_v is PackedFloat32Array:
				var tangents: PackedFloat32Array = (tangents_v as PackedFloat32Array).duplicate()
				if tangents.size() % 4 != 0:
					return {"ok": false, "reason": "bad_tangents"}
				for i3: int in range(0, tangents.size(), 4):
					var t: Vector3 = normal_basis * Vector3(tangents[i3], tangents[i3 + 1], tangents[i3 + 2])
					if t.length_squared() > 0.0000001:
						t = t.normalized()
					tangents[i3] = t.x
					tangents[i3 + 1] = t.y
					tangents[i3 + 2] = t.z
				group_arrays[Mesh.ARRAY_TANGENT] = _merge_append_packed(group_arrays[Mesh.ARRAY_TANGENT], tangents)
			var colors_v: Variant = surface_arrays[Mesh.ARRAY_COLOR]
			if colors_v is PackedColorArray:
				group_arrays[Mesh.ARRAY_COLOR] = _merge_append_packed(group_arrays[Mesh.ARRAY_COLOR], colors_v)
			var uv_v: Variant = surface_arrays[Mesh.ARRAY_TEX_UV]
			if uv_v is PackedVector2Array:
				group_arrays[Mesh.ARRAY_TEX_UV] = _merge_append_packed(group_arrays[Mesh.ARRAY_TEX_UV], uv_v)
			var uv2_v: Variant = surface_arrays[Mesh.ARRAY_TEX_UV2]
			if uv2_v is PackedVector2Array:
				group_arrays[Mesh.ARRAY_TEX_UV2] = _merge_append_packed(group_arrays[Mesh.ARRAY_TEX_UV2], uv2_v)
			for custom_attr: int in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM3 + 1):
				var custom_v: Variant = surface_arrays[custom_attr]
				if custom_v is PackedFloat32Array:
					group_arrays[custom_attr] = _merge_append_packed(group_arrays[custom_attr], custom_v)
			var indices: PackedInt32Array = group["index"] as PackedInt32Array
			var src_idx_v: Variant = surface_arrays[Mesh.ARRAY_INDEX]
			if src_idx_v is PackedInt32Array and not (src_idx_v as PackedInt32Array).is_empty():
				var src_idx: PackedInt32Array = src_idx_v as PackedInt32Array
				for idx: int in range(src_idx.size()):
					indices.append(src_idx[idx] + offset)
			else:
				for idx2: int in range(vcount):
					indices.append(offset + idx2)
			group["index"] = indices
			group["vertex_count"] = offset + vcount
	if groups.is_empty():
		return {"ok": false, "reason": "no_surfaces"}
	var merged := ArrayMesh.new()
	for group_var: Variant in groups:
		var group: Dictionary = group_var as Dictionary
		var arrays: Array = group["arrays"] as Array
		arrays[Mesh.ARRAY_INDEX] = group["index"]
		var material: Material = group["material"] as Material
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, int(group["format"]))
		merged.surface_set_material(merged.get_surface_count() - 1, material)
	if merged.get_surface_count() == 0:
		return {"ok": false, "reason": "array_mesh_empty"}
	var src_summary: Dictionary = _source_summary(sources)
	var first_item: Dictionary = ((candidates[0] as Dictionary)["item"] as Dictionary)
	return {
		"ok": true,
		"cell": first_item.get("cell", Vector2i.ZERO),
		"mesh": merged,
		"aabb": aabb,
		"instances": instances,
		"surface_count": merged.get_surface_count(),
		"materials": groups.size(),
		"ue_paths": ue_paths,
		"decorative": not collide,
		"source_sublevel": src_summary["source_sublevel"],
		"source_sublevels": src_summary["source_sublevels"],
		"source_counts": src_summary["source_counts"],
	}


func _prepare_merge_plan(items: Array, ctx: Dictionary) -> Array:
	ctx["merge_skipped"] = {} as Dictionary
	ctx["merge_candidates"] = 0
	ctx["merge_cells"] = 0
	ctx["merge_nodes"] = 0
	ctx["merge_surfaces_before"] = 0
	ctx["merge_surfaces_after"] = 0
	ctx["merge_skipped_visuals"] = 0
	if str(ctx.get("merge_mode", "off")) != "plain":
		return []
	var by_cell: Dictionary = {}
	for item_var: Variant in items:
		if not (item_var is Dictionary):
			continue
		var item: Dictionary = item_var as Dictionary
		var cand: Dictionary = _merge_candidate(item, ctx)
		if cand.is_empty():
			continue
		ctx["merge_candidates"] = int(ctx.get("merge_candidates", 0)) + 1
		var cell: Vector2i = item.get("cell", Vector2i.ZERO)
		var cell_key: String = "%d_%d" % [cell.x, cell.y]
		if not by_cell.has(cell_key):
			by_cell[cell_key] = [] as Array
		(by_cell[cell_key] as Array).append(cand)
	var plan: Array = []
	for cell_key_var: Variant in by_cell.keys():
		var cands: Array = by_cell[cell_key_var] as Array
		if cands.size() < 2:
			_merge_skip_reason(ctx, "single_cell")
			continue
		var built: Dictionary = _build_merge_cell_mesh(cands, ctx)
		if not bool(built.get("ok", false)):
			_merge_skip_reason(ctx, str(built.get("reason", "cell_failed")))
			continue
		var surface_before: int = 0
		for cand_var: Variant in cands:
			surface_before += int((cand_var as Dictionary).get("surface_count", 0))
		built["items"] = cands
		built["surface_before"] = surface_before
		plan.append(built)
		ctx["merge_cells"] = int(ctx.get("merge_cells", 0)) + 1
		ctx["merge_nodes"] = int(ctx.get("merge_nodes", 0)) + 1
		ctx["merge_surfaces_before"] = int(ctx.get("merge_surfaces_before", 0)) + surface_before
		ctx["merge_surfaces_after"] = int(ctx.get("merge_surfaces_after", 0)) + int(built["surface_count"])
		ctx["merge_skipped_visuals"] = int(ctx.get("merge_skipped_visuals", 0)) + cands.size()
		for cand_var2: Variant in cands:
			var cand_item: Dictionary = (cand_var2 as Dictionary)["item"] as Dictionary
			cand_item["_merge_skip_visual"] = true
	if str(ctx.get("merge_mode", "off")) == "plain":
		print("PERF_MERGE mode=plain candidates=%d cells=%d nodes=%d surfaces_before=%d surfaces_after=%d skipped=%d reasons=%s" % [
			int(ctx.get("merge_candidates", 0)),
			int(ctx.get("merge_cells", 0)),
			int(ctx.get("merge_nodes", 0)),
			int(ctx.get("merge_surfaces_before", 0)),
			int(ctx.get("merge_surfaces_after", 0)),
			int(ctx.get("merge_skipped_visuals", 0)),
			str(ctx.get("merge_skipped", {})),
		])
	return plan


func _build_merged_cell_node(entry: Dictionary, parent: Node3D, ctx: Dictionary) -> int:
	var mesh: Mesh = entry.get("mesh") as Mesh
	if mesh == null or parent == null:
		return -1
	var cell: Vector2i = entry.get("cell", Vector2i.ZERO)
	var cell_text: String = "%d_%d" % [cell.x, cell.y]
	var mi := MeshInstance3D.new()
	mi.name = "MergedCell_%s" % cell_text
	mi.mesh = mesh
	var aabb: AABB = entry.get("aabb", AABB())
	if aabb.size.length_squared() > 0.0:
		mi.custom_aabb = aabb
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if MobileProfile.is_mobile():
		mi.lod_bias = MobileProfile.lod_bias()
	mi.set_meta("ue_mesh", "MERGED_CELL_%s" % cell_text)
	mi.set_meta("merged_cell", cell)
	mi.set_meta("merged_source_count", int(entry.get("instances", 0)))
	mi.set_meta("merged_material_count", int(entry.get("materials", 0)))
	mi.set_meta("merged_ue_meshes", entry.get("ue_paths", []))
	mi.set_meta("decorative", bool(entry.get("decorative", false)))
	mi.set_meta("source_sublevel", str(entry.get("source_sublevel", "unknown")))
	mi.set_meta("source_sublevels", entry.get("source_sublevels", []))
	mi.set_meta("source_counts", entry.get("source_counts", {}))
	_apply_periph_range(mi, entry, ctx)
	parent.add_child(mi)
	ctx["chunk_count"] = int(ctx.get("chunk_count", 0)) + 1
	return int(entry.get("instances", 0))


## Shared build path for tests: plan merges first (so a failed cell leaves its
## originals untouched), build merged nodes, then every original item. Items
## folded into a cell only emit collision/occluders here.
## W9-P1: one cheap pre-pass so the authored-collision cost cap sees the real
## placement count per path (draw items are split per 32 m cell, so a single
## item's count is NOT the load total). Runs before ANY `_get_mesh_and_shape`
## call — the sync (`_build_draw_items`) and async (`load_sublevels_async`)
## paths both go through `_prepare_merge_plan`, which resolves meshes. No JSON
## work happens here; it is a pure item census.
func _fill_col_path_counts(items: Array, ctx: Dictionary) -> void:
	if not (ctx.get("col_path_counts", {}) as Dictionary).is_empty():
		return
	var path_counts: Dictionary = {}
	for pc_var: Variant in items:
		if not (pc_var is Dictionary):
			continue
		var pc_item: Dictionary = pc_var as Dictionary
		if not bool(pc_item.get("collide", false)) or bool(pc_item.get("hidden_in_game", false)) or bool(pc_item.get("no_collide", false)):
			continue
		var pc_trs: Variant = pc_item.get("trs", [])
		if not (pc_trs is Array):
			continue
		var pc_cpds: Variant = pc_item.get("cpds", [])
		if pc_cpds is Array and not (pc_cpds as Array).is_empty() and (pc_cpds as Array).size() == (pc_trs as Array).size():
			continue
		var pc_mp: String = str(pc_item.get("mp", ""))
		if _has_token(pc_mp.to_lower(), CLUTTER_TOKENS):
			continue
		path_counts[pc_mp] = int(path_counts.get(pc_mp, 0)) + (pc_trs as Array).size()
	ctx["col_path_counts"] = path_counts
	# F1: the independent census. Every distinct collidable UE path the draw-item
	# census saw; the classification counters must account for exactly this many.
	ctx["col_paths_seen"] = path_counts.size()
	_col_path_counts = path_counts


func _build_draw_items(items: Array, parent: Node3D, ctx: Dictionary) -> int:
	_fill_col_path_counts(items, ctx)
	var plan: Array = _prepare_merge_plan(items, ctx)
	var total: int = 0
	for entry_var: Variant in plan:
		var entry: Dictionary = entry_var as Dictionary
		var merged_instances: int = _build_merged_cell_node(entry, parent, ctx)
		if merged_instances < 0:
			for cand_var: Variant in (entry.get("items", []) as Array):
				var cand_item: Dictionary = (cand_var as Dictionary)["item"] as Dictionary
				cand_item.erase("_merge_skip_visual")
			ctx["merge_nodes"] = maxi(int(ctx.get("merge_nodes", 0)) - 1, 0)
			ctx["merge_cells"] = maxi(int(ctx.get("merge_cells", 0)) - 1, 0)
			_merge_skip_reason(ctx, "merged_node_failed")
		else:
			total += merged_instances
	for item_var: Variant in items:
		if item_var is Dictionary:
			total += _build_one_draw_item(item_var as Dictionary, parent, ctx)
	return total


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
func _build_one_curb_ribbon(pts: Array[Vector3], width: float, sp_mesh: String, sp_mat: String, parent: Node3D, ctx: Dictionary, source_sublevel: String = "unknown") -> void:
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
	mi.set_meta("source_sublevel", source_sublevel)
	mi.set_meta("source_sublevels", [source_sublevel])
	mi.set_meta("source_counts", {source_sublevel: 1} if source_sublevel != "unknown" else {})
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
		_build_one_curb_ribbon(gpts, width, str(sp.get("mesh", "")), str(sp.get("material", "")), parent, ctx, str(sp.get("_source_sublevel", "unknown")))
		done += 1
	ctx["curb_built"] = int(ctx.get("curb_built", 0)) + done


func _add_one_light(linfo: Dictionary, parent: Node3D, light_probe: Node, hero_shadow: bool, map_hint: String = "") -> bool:
	var cast_shadow: bool = hero_shadow
	if map_hint == "thieves_den" and bool(linfo.get("_den_spot", false)):
		cast_shadow = bool(linfo.get("_den_shadow", true))
	var lnode: Light3D = _build_light(linfo, cast_shadow, map_hint)
	if lnode == null:
		return false
	lnode.shadow_enabled = cast_shadow
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
	var map_hint: String = str(ctx.get("map_hint", ""))
	var plan: Dictionary = plan_light_selection(ordered, max_lights, map_hint)
	var selection: Array = plan["selection"] as Array
	var stats: Dictionary = plan["stats"] as Dictionary
	var added: int = 0
	var forced_added: int = 0
	for sel_var: Variant in selection:
		var sel: Dictionary = sel_var as Dictionary
		var linfo: Dictionary = sel["info"] as Dictionary
		if _add_one_light(linfo, parent, light_probe, bool(sel.get("shadow", false)), map_hint):
			added += 1
			if bool(sel.get("forced", false)):
				forced_added += 1
	ctx["light_count"] = added
	ctx["gate_light_count"] = forced_added
	ctx["hero_shadows"] = MobileProfile.hero_shadows()
	ctx["light_allocation"] = stats
	_report_light_allocation(stats, map_hint)
	_report_gate_lights(added, max_lights, forced_added, map_hint, int(ctx.get("rect_light_count", 0)))


## True when a candidate is one of the authored lights the budget must never
## evict (see PROTECTED_LIGHT_POINTS). Only Guildhall is allowlisted so every
## other map keeps its pure per-room ranking.
static func _is_gate_hero_light(info: Dictionary, map_hint: String) -> bool:
	if map_hint != HERO_LIGHT_MAP_HINT:
		return false
	var p_v: Variant = info.get("pos", null)
	if not (p_v is Array) or (p_v as Array).size() < 3:
		return false
	var p: Array = p_v as Array
	for i: int in range(PROTECTED_LIGHT_POINTS.size()):
		var centre: Vector3 = PROTECTED_LIGHT_POINTS[i]
		var radius: float = PROTECTED_LIGHT_RADII[i] if i < PROTECTED_LIGHT_RADII.size() else HERO_LIGHT_RADIUS_M
		var dx: float = float(p[0]) - centre.x
		var dy: float = float(p[1]) - centre.y
		var dz: float = float(p[2]) - centre.z
		if dx * dx + dy * dy + dz * dz <= radius * radius:
			return true
	return false


## Spatial bucket for the fair allocation ("room bubble"). The same floor() grid
## is applied to authored and selected lights, so a bubble is stable per load.
static func light_room_cell(info: Dictionary, cell: float = LIGHT_ROOM_CELL_M) -> Vector3i:
	var p_v: Variant = info.get("pos", null)
	if not (p_v is Array) or (p_v as Array).size() < 3:
		return Vector3i.ZERO
	var p: Array = p_v as Array
	return Vector3i(
		int(floor(float(p[0]) / cell)),
		int(floor(float(p[1]) / cell)),
		int(floor(float(p[2]) / cell))
	)


## Fair allocation plan. `ordered` is the preference order produced by
## _prioritize_lights (spawn-area first, then authored energy desc); it is used
## only *within* a room bubble, never as a global cut. Returns
## {"selection": Array[{info, shadow, forced}], "stats": Dictionary}.
##
## Rule (see the LIGHT_ROOM_CELL_M block above for the measured defect):
##   1. gate hero lights are force-included (shadowless) as before;
##   2. the remaining slots are handed out one round at a time to room bubbles in
##      densest-first order, each bubble taking its next light in preference
##      order. An over-subscribed map therefore gives every served bubble exactly
##      one authored light (instead of zero), and an under-subscribed map keeps
##      filling round by round;
##   3. shadows go to the first N selected lights in global preference order, so
##      the hero-shadow contract (6 desktop) is unchanged.
func plan_light_selection(ordered: Array, max_lights: int, map_hint: String) -> Dictionary:
	var budget: int = mini(ordered.size(), max_lights)
	var forced: Array[int] = []
	var cell_ranks: Dictionary = {}
	var cell_order: Array = []
	for i: int in range(ordered.size()):
		var l_v: Variant = ordered[i]
		if not (l_v is Dictionary):
			continue
		var l: Dictionary = l_v as Dictionary
		if _is_gate_hero_light(l, map_hint):
			forced.append(i)
			continue
		var key: Vector3i = light_room_cell(l)
		if not cell_ranks.has(key):
			cell_ranks[key] = [] as Array[int]
			cell_order.append(key)
		(cell_ranks[key] as Array[int]).append(i)
	# Densest bubble first: it holds the most authored fixtures, so its loss is
	# the most visible. Ties keep the brighter bubble first, then a stable
	# cell-key order so two loads of the same map pick the same lights.
	cell_order.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		var ca: int = (cell_ranks[a] as Array[int]).size()
		var cb: int = (cell_ranks[b] as Array[int]).size()
		if ca != cb:
			return ca > cb
		var ra: int = (cell_ranks[a] as Array[int])[0]
		var rb: int = (cell_ranks[b] as Array[int])[0]
		var sa: float = _light_score(ordered[ra] as Dictionary)
		var sb: float = _light_score(ordered[rb] as Dictionary)
		if not is_equal_approx(sa, sb):
			return sa > sb
		if a.x != b.x:
			return a.x < b.x
		if a.y != b.y:
			return a.y < b.y
		return a.z < b.z
	)
	var keep_target: int = clampi(budget - forced.size(), 0, ordered.size())
	var depth: Dictionary = {}
	var picked: Array[int] = []
	var covered: Dictionary = {}
	while picked.size() < keep_target:
		var progressed: bool = false
		for key: Vector3i in cell_order:
			if picked.size() >= keep_target:
				break
			var ranks: Array[int] = cell_ranks[key] as Array[int]
			var d: int = int(depth.get(key, 0))
			if d >= ranks.size():
				continue
			picked.append(ranks[d])
			depth[key] = d + 1
			covered[key] = true
			progressed = true
		if not progressed:
			break
	picked.sort()
	var selection: Array = []
	var hero_shadows: int = mini(MobileProfile.hero_shadows(), budget)
	for i: int in range(picked.size()):
		selection.append({"info": ordered[picked[i]] as Dictionary, "shadow": i < hero_shadows, "forced": false})
	for fi: int in forced:
		if selection.size() >= budget:
			break
		selection.append({"info": ordered[fi] as Dictionary, "shadow": false, "forced": true})
	var stats: Dictionary = {
		"authored": ordered.size(),
		"budget": budget,
		"kept": selection.size(),
		"forced": mini(forced.size(), budget),
		"cells": cell_order.size(),
		"covered": covered.size(),
		"cell_m": LIGHT_ROOM_CELL_M,
		"hero_shadows": hero_shadows,
	}
	return {"selection": selection, "stats": stats}


## Budget cut used by _add_lights and the perf tests. Thin wrapper over
## plan_light_selection so the policy has exactly one implementation.
func _select_lights(ordered: Array, max_lights: int, map_hint: String) -> Array:
	return plan_light_selection(ordered, max_lights, map_hint)["selection"] as Array


## One line per load, printed only when the cap actually bites (the Guildhall),
## so every other map stays quiet. `rooms=covered/cells` is the room-bubble
## coverage the fair allocation exists to report.
static func _report_light_allocation(stats: Dictionary, map_hint: String) -> void:
	if int(stats.get("authored", 0)) <= int(stats.get("budget", 0)):
		return
	print("TAT-2 light allocation: map=", map_hint, " authored=", stats.get("authored"), " kept=", stats.get("kept"), " budget=", stats.get("budget"), " forced=", stats.get("forced"), " rooms=", stats.get("covered"), "/", stats.get("cells"), " cell_m=", stats.get("cell_m"))


## Verification line for the KF16 gate pass: final selected count (generic +
## rect lights) plus how many lights the allowlist forced in. Printed for
## Guildhall only (the sole allowlisted map) so other loads stay quiet.
static func _report_gate_lights(added: int, budget: int, forced: int, map_hint: String, rect_lights: int = 0) -> void:
	if map_hint != HERO_LIGHT_MAP_HINT:
		return
	print("TAT-2 gate lights: total=%d (generic=%d rect=%d) budget=%d forced=%d hero_shadows=%d" % [added + rect_lights, added, rect_lights, budget, forced, mini(MobileProfile.hero_shadows(), budget)])


## W1p headless census. Counts the real nodes the loader emitted (not the JSON
## input): draw call surfaces, lights, shadows, occluders and collision. The
## PeripheryA columns are what the range lever can affect; source counts show
## which sublevel owns each instance.
func _perf_census(parent: Node3D, ctx: Dictionary, result: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"meshes": 0,
		"mesh_instances": 0,
		"chunk_nodes": int(ctx.get("chunk_count", 0)),
		"plain_mesh_instances": 0,
		"multimesh_instances": 0,
		"surface_draws": 0,
		"lights": 0,
		"shadow_lights": 0,
		"occluders": 0,
		"collision_bodies": int(ctx.get("collision_bodies", 0)),
		"collision_shapes": int(ctx.get("collision_shapes", 0)),
		"periph_nodes": 0,
		"periph_instances": 0,
		"periph_surface_draws": 0,
		"periph_plain": 0,
		"periph_multimesh": 0,
		"source_sublevels": {} as Dictionary,
		"light_budget": int(ctx.get("light_budget", 0)),
		"light_allocation": (ctx.get("light_allocation", {}) as Dictionary).duplicate(),
		"hero_shadows": int(ctx.get("hero_shadows", MobileProfile.hero_shadows())),
		"periph_range": int(ctx.get("periph_range", 0)),
		"merge_mode": str(ctx.get("merge_mode", "off")),
		"merge_candidates": int(ctx.get("merge_candidates", 0)),
		"merge_nodes": int(ctx.get("merge_nodes", 0)),
		"merge_surfaces_before": int(ctx.get("merge_surfaces_before", 0)),
		"merge_surfaces_after": int(ctx.get("merge_surfaces_after", 0)),
	}
	var body_scan: int = 0
	var shape_scan: int = 0
	var source_counts: Dictionary = out["source_sublevels"]
	if parent != null:
		for child: Node in parent.get_children():
			var node_instances: int = 0
			var node_surfaces: int = 0
			var is_plain: bool = false
			var is_multi: bool = false
			if child is MultiMeshInstance3D:
				var mmi: MultiMeshInstance3D = child as MultiMeshInstance3D
				is_multi = true
				out["multimesh_instances"] = int(out["multimesh_instances"]) + 1
				if mmi.multimesh != null:
					node_instances = mmi.multimesh.instance_count
					if mmi.multimesh.mesh != null:
						node_surfaces = mmi.multimesh.mesh.get_surface_count()
			elif child is MeshInstance3D:
				var mi: MeshInstance3D = child as MeshInstance3D
				is_plain = true
				out["plain_mesh_instances"] = int(out["plain_mesh_instances"]) + 1
				node_instances = 1
				if mi.mesh != null:
					node_surfaces = mi.mesh.get_surface_count()
			if is_plain or is_multi:
				out["meshes"] = int(out["meshes"]) + 1
				out["mesh_instances"] = int(out["mesh_instances"]) + node_instances
				out["surface_draws"] = int(out["surface_draws"]) + node_surfaces
				var src_counts_v: Variant = null
				if child.has_meta("source_counts"):
					src_counts_v = child.get_meta("source_counts")
				if src_counts_v is Dictionary and not (src_counts_v as Dictionary).is_empty():
					for k: Variant in (src_counts_v as Dictionary).keys():
						source_counts[str(k)] = int(source_counts.get(str(k), 0)) + int((src_counts_v as Dictionary)[k])
				else:
					var src: String = ""
					if child.has_meta("source_sublevel"):
						src = str(child.get_meta("source_sublevel"))
					if src != "" and src != "unknown" and src != "mixed":
						source_counts[src] = int(source_counts.get(src, 0)) + node_instances
				if _node_is_periphery_a(child):
					out["periph_nodes"] = int(out["periph_nodes"]) + 1
					out["periph_instances"] = int(out["periph_instances"]) + node_instances
					out["periph_surface_draws"] = int(out["periph_surface_draws"]) + node_surfaces
					if is_plain:
						out["periph_plain"] = int(out["periph_plain"]) + 1
					else:
						out["periph_multimesh"] = int(out["periph_multimesh"]) + 1
			elif child is Light3D:
				out["lights"] = int(out["lights"]) + 1
				if (child as Light3D).shadow_enabled:
					out["shadow_lights"] = int(out["shadow_lights"]) + 1
			elif child is OccluderInstance3D:
				out["occluders"] = int(out["occluders"]) + 1
			elif child is StaticBody3D:
				body_scan += 1
				for shape_child: Node in child.get_children():
					if shape_child is CollisionShape3D:
						shape_scan += 1
	out["collision_bodies"] = maxi(int(out["collision_bodies"]), body_scan)
	out["collision_shapes"] = maxi(int(out["collision_shapes"]), shape_scan)
	out["source_sublevels"] = source_counts
	return out


func _node_is_periphery_a(node: Node) -> bool:
	if node.has_meta("source_sublevel") and _is_periphery_a_source(str(node.get_meta("source_sublevel"))):
		return true
	if not node.has_meta("source_sublevels"):
		return false
	var tags_v: Variant = node.get_meta("source_sublevels")
	if tags_v is Array:
		for tag: Variant in (tags_v as Array):
			if _is_periphery_a_source(str(tag)):
				return true
	return false


## Emits PERF_CENSUS once per Guildhall load (or any load when TAT2_PERF_CENSUS
## is set). Headless-safe: no rendering/GPU work is performed.
func _log_perf_census(parent: Node3D, ctx: Dictionary, result: Dictionary, json_paths: Array) -> void:
	var map_hint: String = _map_hint_from_paths(json_paths)
	if map_hint != "guildhall" and not OS.has_environment(ENV_PERF_CENSUS):
		return
	var census: Dictionary = _perf_census(parent, ctx, result)
	result["perf_census"] = census
	print("PERF_CENSUS meshes=%d instances=%d chunk_nodes=%d plain=%d multimesh=%d surface_draws=%d lights=%d shadow_lights=%d occluders=%d collision_bodies=%d collision_shapes=%d periph_nodes=%d periph_instances=%d periph_surface_draws=%d periph_plain=%d periph_multimesh=%d periph_range=%d merge_mode=%s merge_candidates=%d merge_nodes=%d merge_surfaces_before=%d merge_surfaces_after=%d light_budget=%d hero_shadows=%d source_sublevels=%s" % [
		int(census["meshes"]),
		int(census["mesh_instances"]),
		int(census["chunk_nodes"]),
		int(census["plain_mesh_instances"]),
		int(census["multimesh_instances"]),
		int(census["surface_draws"]),
		int(census["lights"]),
		int(census["shadow_lights"]),
		int(census["occluders"]),
		int(census["collision_bodies"]),
		int(census["collision_shapes"]),
		int(census["periph_nodes"]),
		int(census["periph_instances"]),
		int(census["periph_surface_draws"]),
		int(census["periph_plain"]),
		int(census["periph_multimesh"]),
		int(census["periph_range"]),
		str(census["merge_mode"]),
		int(census["merge_candidates"]),
		int(census["merge_nodes"]),
		int(census["merge_surfaces_before"]),
		int(census["merge_surfaces_after"]),
		int(census["light_budget"]),
		int(census["hero_shadows"]),
		str(census["source_sublevels"]),
	])
	var requested: int = int(ctx.get("periph_range", 0))
	if requested > 0:
		print("PERF_PERIPH_RANGE requested=%d applied=%d kept_smaller=%d skipped_mixed=%d skipped_other=%d pad=%.1f" % [
			requested,
			int(ctx.get("periph_range_applied", 0)),
			int(ctx.get("periph_range_kept_smaller", 0)),
			int(ctx.get("periph_range_skipped_mixed", 0)),
			int(ctx.get("periph_range_skipped_other", 0)),
			PERIPH_RANGE_PAD,
		])


func _finalize(result: Dictionary, ctx: Dictionary, mesh_instances: int) -> Dictionary:
	result["mesh_instances"] = mesh_instances
	# W9-P1: authored-collision source accounting for the A/B probe. `hull` is
	# every mesh whose collider came from authored data (hulls, primitive
	# coalescing or UE complex-as-simple); `prims` is the subset encoded as one
	# coalesced/primitive shape per instance. `absent` is the meshes with no
	# authored answer at all (heuristic fallback, counted, never silent).
	for _col_key: String in ["col_authored_hull", "col_authored_prims", "col_absent",
			"col_no_collision", "col_query_only", "col_reduced", "col_complex_default",
			"col_authored_elements", "col_authored_complex", "col_no_record",
			"col_elements", "col_convex", "col_authored_instances", "col_authored_shapes",
			"col_heuristic_shapes", "col_path_counts", "col_placed_instances",
			"col_deadline_hit", "col_paths_seen", "col_scale_baked"]:
		result[_col_key] = ctx.get(_col_key, 0) if _col_key != "col_path_counts" else (ctx.get(_col_key, {}) as Dictionary).size()
	# W10-A evidence: the reduced-mesh roster and the planar-convex skip delta
	# for THIS load (the counters themselves stay in `AuthoredCollision.stats()`
	# as exact process totals; the base snapshot is taken in `_new_build_ctx`).
	result["col_reduced_names"] = (ctx.get("col_reduced_names", []) as Array).duplicate(true)
	var planar_post: Dictionary = {}
	if AuthoredCollision.is_loaded():
		planar_post = AuthoredCollision.stats() as Dictionary
	var planar_paths_now: Array = planar_post.get("planar_skipped_paths", []) as Array
	var planar_paths_base: Array = ctx.get("col_planar_base_paths", []) as Array
	var planar_new: Array[String] = []
	for _planar_var: Variant in planar_paths_now:
		var _planar_path: String = str(_planar_var)
		if not planar_paths_base.has(_planar_var) and not planar_new.has(_planar_path):
			planar_new.append(_planar_path)
	result["col_planar_skipped"] = maxi(
		int(planar_post.get("planar_convex_skipped", 0))
		- int(ctx.get("col_planar_base_skipped", 0)), 0)
	result["col_planar_paths"] = planar_new
	result["collision_mode"] = _collision_mode()
	if int(ctx.get("col_authored_hull", 0)) + int(ctx.get("col_absent", 0)) > 0:
		var ainst: int = maxi(int(ctx.get("col_authored_instances", 0)), 1)
		var ast: Dictionary = AuthoredCollision.stats() as Dictionary
		print("AUTHORED_COLLISION meshes=%d hull=%d authored_elements=%d complex=%d no_record=%d prims=%d convex=%d absent=%d no_collision=%d query_only=%d reduced=%d shapes_per_instance_avg=%.2f elements=%d load_ms=%d" % [
			int(ctx.get("col_authored_hull", 0)) + int(ctx.get("col_absent", 0)),
			int(ctx.get("col_authored_hull", 0)),
			int(ctx.get("col_authored_elements", 0)),
			int(ctx.get("col_authored_complex", 0)),
			int(ctx.get("col_no_record", 0)),
			int(ctx.get("col_authored_prims", 0)),
			int(ctx.get("col_convex", 0)),
			int(ctx.get("col_absent", 0)),
			int(ctx.get("col_no_collision", 0)),
			int(ctx.get("col_query_only", 0)),
			int(ctx.get("col_reduced", 0)),
			float(ctx.get("col_authored_shapes", 0)) / float(ainst),
			int(ctx.get("col_elements", 0)),
			int(ast.get("load_ms", 0)),
		])
	if _roughness_bake_count > 0 or _roughness_cache_hits > 0:
		print("ROUGHNESS_BAKE count=%d pixels=%d ms=%d bytes=%d hits=%d (L8 low+g*(high-low), full-res, process cache)" % [
			_roughness_bake_count, _roughness_bake_px, _roughness_bake_ms,
			_roughness_bake_bytes, _roughness_cache_hits,
		])
	result["beam_cards_fixed"] = _beam_fix_count
	result["beam_scale_max"] = _beam_fix_max_scale
	result["beam_axis_max_err_deg"] = _beam_fix_max_axis_err_deg
	result["beam_len_max_err"] = _beam_fix_max_len_err
	result["beam_clamped"] = _beam_fix_clamped
	if _beam_fix_count > 0:
		# One line per load: applied count, authored axis/length slot and the
		# true applied world span (0.102 m authored card axis * max scale).
		# `clamp=none`: the authored Old Manor maximum is 236.9539 (24.169 m)
		# and the old 200 ceiling clipped 5/196 cards.
		print("BEAM_FIX SM_LightBeam cards=", _beam_fix_count,
			" axis=col2 length_slot=2 clamp=none",
			" max_scale=", snappedf(_beam_fix_max_scale, 0.0001),
			" max_length_m=", snappedf(_beam_fix_max_scale * BEAM_CARD_LEN_M, 0.001))
		print("BEAM_AXIS cards=", _beam_fix_count,
			" max_axis_err_deg=", snappedf(_beam_fix_max_axis_err_deg, 0.0001),
			" max_len_err=", snappedf(_beam_fix_max_len_err, 0.000001),
			" clamped=", _beam_fix_clamped)
	result["player_spawn_transform_count"] = (result.get("player_spawn_transforms", []) as Array).size()
	result["minor_loot_spawn_count"] = (result.get("minor_loot_spawns", []) as Array).size()
	result["major_loot_spawn_count"] = (result.get("major_loot_spawns", []) as Array).size()
	result["loot_container_count"] = (result.get("loot_containers", []) as Array).size()
	result["throwable_spawn_count"] = (result.get("throwable_spawns", []) as Array).size()
	result["ammo_spawn_count"] = (result.get("ammo_spawns", []) as Array).size()
	result["health_spawn_count"] = (result.get("health_spawns", []) as Array).size()
	result["civilian_spawn_count"] = (result.get("civilian_spawns", []) as Array).size()
	result["light_count"] = int(ctx.get("light_count", 0))
	result["light_allocation"] = (ctx.get("light_allocation", {}) as Dictionary).duplicate()
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
	result["niagara_nodes"] = int(ctx.get("niagara_nodes", 0))
	result["niagara_sprites"] = int(ctx.get("niagara_sprites", 0))
	result["niagara_params_applied"] = int(ctx.get("niagara_params_applied", 0))
	result["niagara_inactive_skipped"] = int(ctx.get("niagara_inactive_skipped", 0))
	result["gc_layers_enabled"] = bool(ctx.get("gc_layers_enabled", false))
	result["gc_layers_built"] = int(ctx.get("gc_layers_built", 0))
	result["gc_leaves_built"] = int(ctx.get("gc_leaves_built", 0))
	result["gc_missing_mesh"] = int(ctx.get("gc_missing_mesh", 0))
	result["gc_visible_broken"] = int(ctx.get("gc_visible_broken", 0))
	result["gc_static_leaves_bound"] = int(ctx.get("gc_static_leaves_bound", 0))
	result["gc_static_leaves_unmatched"] = int(ctx.get("gc_static_leaves_unmatched", 0))
	result["gc_static_leaf_multi"] = int(ctx.get("gc_static_leaf_multi", 0))
	result["gc_owner_count"] = _gc_owner_index.size()
	result["spline_count"] = int(ctx.get("spline_count", 0))
	result["curb_built"] = int(ctx.get("curb_built", 0))
	result["missing_mesh_count"] = int(ctx.get("missing_mesh_count", 0))
	result["duplicate_meshes"] = int(result.get("duplicate_meshes", 0))
	result["name_skipped"] = int(result.get("name_skipped", 0))
	result["ward_box_hidden"] = int(result.get("ward_box_hidden", 0))
	result["moonshape_hidden"] = int(result.get("moonshape_hidden", 0))
	result["clamped_scales"] = _scale_clamp_count
	result["scale_clamp_worst_ratio"] = snappedf(_scale_clamp_worst, 0.0001)
	# P4.2: `mirrored_bases` is the draw-item census (the set the split batches
	# and mirrored standalone nodes must account for). The transform-level
	# census (includes decals/GC overlays) stays exported for the RE-P-08 probe.
	result["mirrored_bases"] = _mirror_draw_bases
	result["mirrored_transform_bases"] = _mirrored_basis_count
	result["mirrored_multimesh"] = _mirror_multimesh_instances
	result["mirrored_single"] = _mirror_single_instances
	result["mirrored_batches_split"] = _mirror_batches_split
	result["mirrored_cull_front"] = _mirror_cull_front_instances
	result["mirrored_cull_disabled"] = _mirror_cull_disabled_instances
	result["mirrored_mesh_bytes"] = _mirror_mesh_bytes
	result["mirrored_mesh_count"] = _mirror_mesh_count
	result["mirrored_unbaked"] = _mirror_unbaked
	result["authored_meshes"] = int(result.get("authored_meshes", 0))
	result["sublevels_skipped_merged"] = int(result.get("sublevels_skipped_merged", 0))
	result["sublevels_from_graph"] = int(result.get("sublevels_from_graph", 0))
	result["sublevels_graph_missing"] = int(result.get("sublevels_graph_missing", 0))
	result["expansion_placements"] = int(result.get("expansion_placements", 0))
	result["parity_only"] = _parity_only
	if _parity_only:
		var parity_rules: Dictionary = result.get("parity_skipped_expansion_rules", {}) as Dictionary
		var names: Array = parity_rules.keys()
		names.sort()
		var parts := PackedStringArray()
		for rid_v: Variant in names:
			parts.append("%s=%d" % [str(rid_v), int(parity_rules[rid_v])])
		print("PARITY_ONLY load: skipped_expansion_meshes=%d skipped_expansion_caps=%d skipped_expansion_nodes=%d rules={%s}" % [
			int(result.get("parity_skipped_expansion_meshes", 0)),
			int(result.get("parity_skipped_expansion_caps", 0)),
			int(result.get("parity_skipped_expansion_nodes", 0)),
			", ".join(parts),
		])
	# RE-P-09/RE-P-16: the mesh reconciliation used to live only in `result`,
	# so no run log could prove a filter had not eaten authored geometry. One
	# deterministic line per load, always on.
	print("MESH_RECON authored=%d applied=%d duplicate=%d name_skipped=%d wardbox=%d moonshape=%d clamp=%d clamp_worst=%.2fx mirrored=%d origin_markers_skipped=%d skipped_merged=%d from_graph=%d graph_missing=%d mirrored_bases=%d mirrored_multimesh=%d mirrored_single=%d mirrored_splits=%d mirrored_cull_front=%d mirrored_cull_disabled=%d mirrored_mesh_bytes=%d mirrored_mesh_count=%d mirrored_unbaked=%d" % [
		int(result["authored_meshes"]),
		mesh_instances,
		int(result["duplicate_meshes"]),
		int(result["name_skipped"]),
		int(result["ward_box_hidden"]),
		int(result["moonshape_hidden"]),
		_scale_clamp_count,
		_scale_clamp_worst,
		_mirrored_basis_count,
		int(result.get("origin_markers_skipped", 0)),
		int(result["sublevels_skipped_merged"]),
		int(result["sublevels_from_graph"]),
		int(result["sublevels_graph_missing"]),
		_mirror_draw_bases,
		_mirror_multimesh_instances,
		_mirror_single_instances,
		_mirror_batches_split,
		_mirror_cull_front_instances,
		_mirror_cull_disabled_instances,
		_mirror_mesh_bytes,
		_mirror_mesh_count,
		_mirror_unbaked,
	])
	# P4.2 reconcile: every mirrored draw instance must be in a negative
	# MultiMesh batch or a mirrored standalone node. A mismatch is a split bug,
	# not a data quality number, so it is loud.
	var mirror_total: int = _mirror_multimesh_instances + _mirror_single_instances
	var mirror_ok: bool = mirror_total == _mirror_draw_bases
	print("MIRROR_RECON bases=%d multimesh=%d single=%d split=%d cull_front=%d cull_disabled=%d baked=%d baked_bytes=%d unbaked=%d suppressed=%d ok=%s" % [
		_mirror_draw_bases,
		_mirror_multimesh_instances,
		_mirror_single_instances,
		_mirror_batches_split,
		_mirror_cull_front_instances,
		_mirror_cull_disabled_instances,
		_mirror_mesh_count,
		_mirror_mesh_bytes,
		_mirror_unbaked,
		_mirror_log_suppressed,
		str(mirror_ok),
	])
	if not mirror_ok:
		push_error("[level_loader] MIRROR_RECON mismatch: bases=%d multimesh=%d single=%d" % [
			_mirror_draw_bases, _mirror_multimesh_instances, _mirror_single_instances])
	result["missing_meshes"] = (ctx.get("missing_meshes", [] as Array) as Array).duplicate()
	result["corrupt_mesh_count"] = corrupt_mesh_count
	result["corrupt_meshes"] = corrupt_meshes.duplicate()
	# PG-1 budget accounting. With the pre-baked imports downscaled_count must
	# be 0: any entry means the runtime decoded a full-res PNG this load.
	result["downscaled_count"] = downscaled_count
	result["downscaled_textures"] = downscaled_textures.duplicate()
	result["fallback_material_count"] = fallback_material_count
	result["fallback_materials"] = fallback_materials.duplicate()
	result["invented_white_count"] = _invented_white_count
	result["invented_white_materials"] = invented_white_materials.duplicate()
	if _invented_white_count > 0:
		print("MATERIAL_EMISSIVE invented_white=%d names=%s" % [
			_invented_white_count, ",".join(invented_white_materials)])
	# L2-03: authored flat-colour binds (visible population, near-white named).
	result["flat_colour_material_count"] = flat_colour_material_count
	result["flat_colour_materials"] = flat_colour_materials.duplicate()
	# RE-Q-06: empty slots rescued by a unique surface-name match (0 on the
	# shipped data set; the index is authoritative).
	result["slot_name_fallback_count"] = slot_name_fallback_count
	result["slot_name_fallback_names"] = slot_name_fallback_names.duplicate()
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
	result["patrol_paths"] = result.get("patrol_paths", [])
	result["patrol_path_count"] = (result["patrol_paths"] as Array).size()
	result["sky_light"] = ctx.get("sky_light", {})
	result["fog_volume"] = ctx.get("fog_volume", {})
	result["post_process"] = ctx.get("post_process", {})
	# W1p structural prototype accounting. Defaults are zero/off; the census
	# line is the only always-on artifact.
	result["light_budget"] = int(ctx.get("light_budget", 0))
	result["hero_shadows"] = int(ctx.get("hero_shadows", MobileProfile.hero_shadows()))
	result["periph_range"] = int(ctx.get("periph_range", 0))
	result["periph_range_applied"] = int(ctx.get("periph_range_applied", 0))
	result["periph_range_kept_smaller"] = int(ctx.get("periph_range_kept_smaller", 0))
	result["periph_range_skipped_mixed"] = int(ctx.get("periph_range_skipped_mixed", 0))
	result["periph_range_skipped_other"] = int(ctx.get("periph_range_skipped_other", 0))
	result["merge_mode"] = str(ctx.get("merge_mode", "off"))
	result["merge_candidates"] = int(ctx.get("merge_candidates", 0))
	result["merge_cells"] = int(ctx.get("merge_cells", 0))
	result["merge_nodes"] = int(ctx.get("merge_nodes", 0))
	result["merge_surfaces_before"] = int(ctx.get("merge_surfaces_before", 0))
	result["merge_surfaces_after"] = int(ctx.get("merge_surfaces_after", 0))
	result["merge_skipped_visuals"] = int(ctx.get("merge_skipped_visuals", 0))
	result["merge_skipped"] = (ctx.get("merge_skipped", {}) as Dictionary).duplicate()
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
## Energy uses the same monotonic authored-intensity mapping as _build_light
## (light_energy_for_intensity); colour converts 0-255 -> 0-1.
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
		omni.light_energy = light_energy_for_intensity(raw)
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
		# Shared tag consumed by traversal probes (mantle/wall-climb/zipwire):
		# an invisible designer blocker is solid to walk into, never a wall,
		# ledge or anchor. Tag only; the body stays solid on layer 1.
		body.add_to_group("blocking_volume")
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
## Spawn every authored-active Niagara placement as one instanced billboard per
## placement (T12-VFX; findings RE-E-02/03/04/10/14).
##
## Chain of truth, per placement:
##   1. `bAutoActivate` on the owning component (decoded from the extraction by
##      `niagara_params.gd`); a placement whose own component states a flag wins.
##      Placements whose Blueprint inherits the component fall back to the
##      authored event-gated set (30 systems), so 3,695 authored placements now
##      resolve to 1,048 live instances instead of 3,308.
##   2. Per-instance authoring: the placement `scale` multiplies the billboard,
##      and a decoded `User.Scale` (a UE centimetre size) replaces the class band.
##   3. Colour: the decoded user colour (Color1 / EffectColor / ParticleColor...),
##      then the renderer material's authored vector, then the counted fallback.
##   4. Sprite: `systems.json`'s resolved renderer texture, sampled only when the
##      measured mask table says it is a soft mask (`sprite_masks.gd`).
##   5. Culling: one MultiMesh per (system, 32 m XZ chunk), each registered with
##      `level_niagara_culler.gd`, so instances beyond 60 m stop drawing.
func _spawn_level_niagara(acc: Dictionary, ctx: Dictionary) -> void:
	var parent: Node = ctx.get("parent") as Node
	if parent == null:
		return
	var records: Array = acc.get("niagara", []) as Array
	var ctx_skip: int = 0
	var ctx_params: int = 0
	var ctx_tint_param: int = 0
	var ctx_tint_material: int = 0
	var ctx_tint_fallback: int = 0
	# Decode only the Blueprints this map's placements name, once per process.
	var sources: Array = []
	var seen_src: Dictionary = {}
	for r_v: Variant in records:
		if not (r_v is Dictionary):
			continue
		var src: String = str((r_v as Dictionary).get("source", ""))
		var sep: int = src.find("::")
		var file: String = src.substr(0, sep) if sep >= 0 else src
		if file != "" and not seen_src.has(file):
			seen_src[file] = true
			sources.append(file)
	var params_handle: Dictionary = NiagaraParams.prepare(sources)
	NiagaraLibrary.ensure_loaded()
	# asset -> {"chunks": {Vector2i: {"trs": Array, "cols": Array}}, "abs": bool}
	var groups: Dictionary = {}
	for r_v: Variant in records:
		if not (r_v is Dictionary):
			continue
		var r: Dictionary = r_v as Dictionary
		var asset: String = str(r.get("asset", ""))
		if asset == "":
			continue
		var state: Dictionary = NiagaraParams.resolve(params_handle, r)
		var auto_v: Variant = state.get("auto", null)
		var active: bool
		if auto_v is bool:
			active = bool(auto_v)
		else:
			active = not NiagaraParams.is_event_gated(asset)
		if not active:
			ctx_skip += 1
			continue
		var params: Dictionary = state.get("params", {}) as Dictionary
		if not params.is_empty():
			ctx_params += 1
		var pos_arr: Array = r.get("pos", [0, 0, 0]) as Array
		var b_arr: Variant = r.get("basis", [])
		var basis := Basis()
		if b_arr is Array and (b_arr as Array).size() == 9:
			var b: Array = b_arr as Array
			basis = Basis(
				Vector3(float(b[0]), float(b[1]), float(b[2])),
				Vector3(float(b[3]), float(b[4]), float(b[5])),
				Vector3(float(b[6]), float(b[7]), float(b[8])),
			)
		var pl_scale := Vector3.ONE
		var sc_v: Variant = r.get("scale", null)
		if sc_v is Array and (sc_v as Array).size() >= 3:
			var sc: Array = sc_v as Array
			pl_scale = Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
			if pl_scale.x <= 0.0 or pl_scale.y <= 0.0:
				pl_scale = Vector3.ONE
		# Authored per-instance size. `User.Scale` is a UE centimetre pair in the
		# candle system (5, 10) -> 5 x 10 cm; clamp so a stray value cannot make a
		# kilometre quad. Systems that carry it size absolute and skip the band.
		var user_scale := Vector2.ONE
		var abs_scale: bool = false
		var us_v: Variant = params.get("Scale", null)
		if us_v is Vector2:
			var us: Vector2 = us_v as Vector2
			user_scale = Vector2(maxf(us.x * 0.01, 0.01), maxf(us.y * 0.01, 0.01))
			abs_scale = true
		elif us_v is Vector3:
			var us3: Vector3 = us_v as Vector3
			user_scale = Vector2(maxf(us3.x * 0.01, 0.01), maxf(us3.y * 0.01, 0.01))
			abs_scale = true
		elif us_v is float:
			user_scale = Vector2(maxf(float(us_v), 0.01), maxf(float(us_v), 0.01))
		var tint := Color(1.0, 1.0, 1.0, 1.0)
		var pc: Color = _niagara_param_colour(params)
		if pc.a > 0.0:
			tint = pc
			ctx_tint_param += 1
		else:
			var mc: Color = NiagaraLibrary.material_tint(asset)
			if mc.a > 0.0:
				tint = mc
				ctx_tint_material += 1
			else:
				tint = NiagaraLibrary.fallback_tint(asset)
				ctx_tint_fallback += 1
		tint.a = clampf(tint.a, 0.02, 1.0) * NIAGARA_ADDITIVE_ALPHA
		var p := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var cell := Vector2i(int(floor(p.x / CHUNK_SIZE)), int(floor(p.z / CHUNK_SIZE)))
		var inst_scale := Vector3(pl_scale.x * user_scale.x, pl_scale.y * user_scale.y, 1.0)
		if not groups.has(asset):
			groups[asset] = {"chunks": {}, "abs": abs_scale}
		var grp: Dictionary = groups[asset] as Dictionary
		if abs_scale:
			grp["abs"] = true
		var chunks: Dictionary = grp["chunks"] as Dictionary
		if not chunks.has(cell):
			chunks[cell] = {"trs": [] as Array, "cols": [] as Array}
		var bucket: Dictionary = chunks[cell] as Dictionary
		(bucket["trs"] as Array).append(Transform3D(basis.scaled(inst_scale), p))
		(bucket["cols"] as Array).append(tint)
		if bool(ctx.get("niagara_log", false)):
			var log: Array = ctx.get("niagara_instance_log", []) as Array
			if log.is_empty():
				ctx["niagara_instance_log"] = log
			log.append({"a": str(asset).get_file(), "p": p, "t": tint,
				"s": Vector2(inst_scale.x, inst_scale.y)})
	ctx["niagara_inactive_skipped"] = ctx_skip
	if groups.is_empty():
		ctx["niagara_spawned"] = 0
		ctx["niagara_systems"] = 0
		ctx["niagara_nodes"] = 0
		ctx["niagara_sprites"] = 0
		ctx["niagara_params_applied"] = ctx_params
		return
	var shader: Shader = load("res://src/core/level_niagara.gdshader") as Shader
	var culler: Node3D = NiagaraCuller.new() as Node3D
	culler.name = "LevelNiagaraCuller"
	parent.add_child(culler)
	ctx["niagara_culler"] = culler
	var total: int = 0
	var nodes: int = 0
	var sprites: int = 0
	for asset: Variant in groups.keys():
		var grp2: Dictionary = groups[asset] as Dictionary
		var info: Dictionary = NiagaraLibrary.info(str(asset))
		var sprite_path: String = str(info.get("sprite_path", ""))
		var base_size: float = 1.0 if bool(grp2.get("abs", false)) 			else float(info.get("base_size", 0.12))
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("tint", Color(1.0, 1.0, 1.0, 1.0))
		mat.set_shader_parameter("base_size", base_size)
		mat.set_shader_parameter("use_sprite", false)
		if sprite_path != "":
			var tex: Texture2D = _load_tex(sprite_path)
			if tex != null:
				mat.set_shader_parameter("sprite_tex", tex)
				mat.set_shader_parameter("use_sprite", true)
				sprites += 1
		var sys_name: String = str(asset).get_file().replace(".", "_")
		var chunks2: Dictionary = grp2["chunks"] as Dictionary
		for cell_v: Variant in chunks2.keys():
			var cell: Vector2i = cell_v as Vector2i
			var bucket2: Dictionary = chunks2[cell_v] as Dictionary
			var trs: Array = bucket2["trs"] as Array
			var cols: Array = bucket2["cols"] as Array
			if trs.is_empty():
				continue
			var quad := QuadMesh.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = quad
			mm.instance_count = trs.size()
			# Instance transforms stay relative to the chunk node so the node sits
			# at its chunk centre: that is what the distance culler measures and it
			# keeps world-space precision inside a large map.
			var chunk_origin := Vector3((float(cell.x) + 0.5) * CHUNK_SIZE, 0.0,
				(float(cell.y) + 0.5) * CHUNK_SIZE)
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			for i: int in range(trs.size()):
				var tr: Transform3D = trs[i] as Transform3D
				var local := Transform3D(tr.basis, tr.origin - chunk_origin)
				mm.set_instance_transform(i, local)
				mm.set_instance_custom_data(i, cols[i] as Color)
				lo = lo.min(local.origin)
				hi = hi.max(local.origin)
			var aabb := AABB(lo - Vector3.ONE, (hi - lo) + Vector3(2.0, 2.0, 2.0))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "LevelNiagara_%s_%d_%d" % [sys_name, cell.x, cell.y]
			mmi.position = chunk_origin
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.custom_aabb = aabb
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mmi)
			var radius: float = maxf(aabb.size.x, aabb.size.z) * 0.5
			culler.call("add_chunk", mmi, radius, str(asset).get_file())
			nodes += 1
			total += trs.size()
	ctx["niagara_spawned"] = total
	ctx["niagara_systems"] = groups.size()
	ctx["niagara_nodes"] = nodes
	ctx["niagara_sprites"] = sprites
	ctx["niagara_params_applied"] = ctx_params
	ctx["niagara_tint_param"] = ctx_tint_param
	ctx["niagara_tint_material"] = ctx_tint_material
	ctx["niagara_tint_fallback"] = ctx_tint_fallback
	var st: Dictionary = params_handle.get("stats", {}) as Dictionary
	push_warning("[level_loader] level Niagara: %d placements across %d systems in %d chunk nodes (%d sprite-masked, %d parameter sets, %d activation-skipped; decode root=%s files=%d)" % [
		total, groups.size(), nodes, sprites, ctx_params, ctx_skip, str(st.get("root", "")), int(st.get("files_loaded", 0))])


## The additive HDR band every level-Niagara billboard sits in. Global on purpose:
## the authored colours stay authored, only the overall lift is a port constant.
const NIAGARA_ADDITIVE_ALPHA: float = 0.85

## First authored colour carried by the decoded user parameters, or transparent
## black when the component overrides no colour.
func _niagara_param_colour(params: Dictionary) -> Color:
	for key: String in ["Color1", "EffectColor", "ParticleColor", "EmberColor", "PuddleColor", "BeamColor", "Tint", "Color"]:
		var v: Variant = params.get(key, null)
		if v is Color:
			var c: Color = v as Color
			if c.a <= 0.0:
				c.a = 1.0
			return c
		if v is Vector3:
			var v3: Vector3 = v as Vector3
			return Color(v3.x, v3.y, v3.z, 1.0)
	return Color(0.0, 0.0, 0.0, 0.0)


## True when an authored live-flame placement sits within [param radius] of
## [param wick]. The loader's procedural candle quad must not stack on top of an
## authored NS_Candelabras_Flame billboard (RE-E-09); a per-wick test replaces the
## old Den-only file scope, so Guildhall and OldManor de-duplicate too.
func _authored_flame_near(flames: Array, wick: Vector3, radius: float = 0.75) -> bool:
	var r2: float = radius * radius
	for f_v: Variant in flames:
		if (f_v as Vector3).distance_squared_to(wick) <= r2:
			return true
	return false


func _build_post_process_gi_fills(post_processes: Array, parent: Node3D, ctx: Dictionary) -> void:
	if MobileProfile.is_mobile() or parent == null:
		return
	var is_den: bool = str(ctx.get("map_hint", "")) == "thieves_den"
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
			if is_den:
				# FIX_SPEC P0 #2: the Den LumenSkylightLeaking stand-in was a
				# flat 0.27 / 17.5 m / 0.4 blue omni that veiled the attic.
				# Keep a small local bounce only.
				fill.light_color = DEN_GI_FILL_COLOR
				fill.light_energy = DEN_GI_FILL_ENERGY
				fill.omni_range = DEN_GI_FILL_RANGE
				fill.omni_attenuation = DEN_GI_FILL_ATTENUATION
			else:
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


## ----- Authored sublevel graph (RE-B-01 / RE-B-03) --------------------------
## The shipped persistent maps declare their sublevels as
## `LevelStreamingAlwaysLoaded` / `LevelStreamingDynamic` actors. The port
## never consumed that graph (hardcoded lists in mission_controller.gd), which
## dropped OldManor_PathBlockers (156 meshes of authored route gating),
## ThievesDenTest_Contracts (the Den's contract booth/journal props) and
## ThievesDen_LoadoutCapture, and let FTUE load Building_JewelryStore twice
## (once as the authored LevelInstance inside FTUE_Geometry, once standalone).
const LEVELS_RES_ROOT: String = "res://data/generated/levels/"
const LEVELS_RES_SUFFIX: String = ".tatlevel.json"


## "res://data/generated/levels/A/B.tatlevel.json" -> "A/B". Anything outside
## the generated levels root keeps the pre-graph behaviour (key "").
static func _level_key_from_res(json_path: String) -> String:
	if not json_path.begins_with(LEVELS_RES_ROOT) or not json_path.ends_with(LEVELS_RES_SUFFIX):
		return ""
	var tail: String = json_path.substr(LEVELS_RES_ROOT.length())
	return tail.substr(0, tail.length() - LEVELS_RES_SUFFIX.length())


## Level keys that a supplied sublevel already contributes through the
## LevelInstance merge pass. Those must never also be parsed standalone: the
## merged copies sit at the authored instance transform, the standalone payload
## sits at the level's own origin (~220 m away for the FTUE jewelry store), and
## the mesh dedupe cannot collapse them because the transforms differ.
## The empty case is detected without a JSON parse so ordinary maps pay nothing.
func _prescan_merged_sublevels(json_paths: Array) -> Dictionary:
	var merged: Dictionary = {}
	for jp_var: Variant in json_paths:
		var jp: String = str(jp_var)
		if not FileAccess.file_exists(jp):
			continue
		var txt: String = FileAccess.get_file_as_string(jp)
		if txt == "" or txt.find("\"level_instances\": []") >= 0:
			continue
		var parsed: Variant = JSON.parse_string(txt)
		if not (parsed is Dictionary):
			continue
		for li_var: Variant in ((parsed as Dictionary).get("level_instances", []) as Array):
			merged[str(li_var)] = true
	return merged


## Authoried always-loaded sublevels missing from the supplied set, as res://
## paths. Dynamic levels are deliberately not added (the contract row owns
## those), and a level already merged as a LevelInstance is skipped because its
## geometry is present.
func _resolve_authored_streaming(acc: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = (acc["sublevel_keys"] as Dictionary).duplicate()
	var merged: Dictionary = acc["level_instance_targets"] as Dictionary
	var result: Dictionary = acc["result"]
	var wanted: Array[String] = []
	for sl_var: Variant in (acc["streaming_levels"] as Array):
		if not (sl_var is Dictionary):
			continue
		var rec: Dictionary = sl_var as Dictionary
		if str(rec.get("type", "")) != "always":
			continue
		var key: String = str(rec.get("level", ""))
		if key == "" or seen.has(key):
			continue
		seen[key] = true
		wanted.append(key)
	for key: String in wanted:
		if merged.has(key):
			result["sublevels_skipped_merged"] = int(result.get("sublevels_skipped_merged", 0)) + 1
			continue
		var res_path: String = LEVELS_RES_ROOT + key + LEVELS_RES_SUFFIX
		if not FileAccess.file_exists(res_path):
			result["sublevels_graph_missing"] = int(result.get("sublevels_graph_missing", 0)) + 1
			continue
		result["sublevels_from_graph"] = int(result.get("sublevels_from_graph", 0)) + 1
		out.append(res_path)
	return out


## Parses the supplied sublevels plus the authored always-loaded graph, minus
## sublevels that another supplied payload already merged. Both load paths use
## this so sync and async stay identical.
func _parse_sublevels_with_graph(json_paths: Array, acc: Dictionary, parent: Node3D, on_file: Callable = Callable()) -> void:
	var merged: Dictionary = _prescan_merged_sublevels(json_paths)
	for jp_var: Variant in json_paths:
		var jp: String = str(jp_var)
		var key: String = _level_key_from_res(jp)
		if key != "" and merged.has(key):
			var result: Dictionary = acc["result"]
			result["sublevels_skipped_merged"] = int(result.get("sublevels_skipped_merged", 0)) + 1
			if on_file.is_valid():
				on_file.call(jp, true)
			continue
		_parse_sublevel_file(jp, acc, parent)
		if on_file.is_valid():
			on_file.call(jp, false)
	for extra: String in _resolve_authored_streaming(acc):
		_parse_sublevel_file(extra, acc, parent)
		if on_file.is_valid():
			on_file.call(extra, false)


func load_sublevels(json_paths: Array[String], parent: Node3D, light_probe: Node, max_lights: int = 96, generate_collision: bool = true) -> Dictionary:
	var _timing: bool = OS.has_environment("TAT_LOAD_TIMING")
	var _t0: int = Time.get_ticks_msec()
	if _materials_db.is_empty():
		_load_material_dbs()
	# V6 companion: bake the footprint alpha mask now (loading screen),
	# not on the first wet footstep. Static cache makes repeats free.
	_VfxManager.prewarm_footstep_mask()
	var acc: Dictionary = _new_accumulator()
	_roughness_bake_count = 0
	_roughness_bake_px = 0
	_roughness_bake_ms = 0
	_roughness_bake_bytes = 0
	_roughness_cache_hits = 0
	_beam_fix_count = 0
	_beam_fix_max_scale = 0.0
	_beam_fix_max_axis_err_deg = 0.0
	_beam_fix_max_len_err = 0.0
	_beam_fix_clamped = 0
	_scale_clamp_count = 0
	_scale_clamp_worst = 1.0
	_mirrored_basis_count = 0
	_reset_mirror_counters()
	_parse_sublevels_with_graph(json_paths, acc, parent)

	if _timing:
		print("LoadTiming parse_ms=", Time.get_ticks_msec() - _t0)
	var ctx: Dictionary = _new_build_ctx(parent, light_probe, generate_collision)
	ctx["map_hint"] = _map_hint_from_paths(json_paths)
	var effective_budget: int = _effective_light_budget(max_lights)
	ctx["light_budget"] = effective_budget
	ctx["hero_shadows"] = MobileProfile.hero_shadows()
	_apply_collider_budget(ctx, json_paths)
	# Active RectLights are rare (one per mission map at most) and authored as
	# area lights, so they claim budget slots before the generic point lights.
	_build_rect_lights(acc["rect_lights"], parent, light_probe, ctx, effective_budget)
	_add_lights(acc["lights"], parent, light_probe, maxi(effective_budget - int(ctx.get("rect_light_count", 0)), 0), ctx, acc["result"]["player_spawns"])
	ctx["light_count"] = int(ctx.get("light_count", 0)) + int(ctx.get("rect_light_count", 0))
	_build_decals(acc["decals"], parent, ctx)
	_build_volumes(acc["volumes"], parent, ctx)
	_store_level_extras(acc, ctx)
	_build_post_process_gi_fills(acc["post_process"], parent, ctx)
	_build_landscapes_sync(acc["landscapes"], parent, ctx)
	_build_curbs_from_splines(acc["splines"], parent, ctx)
	_build_guildhall_saferoom_floor(parent, ctx)

	var items: Array = _collect_draw_items(acc)
	var total_inst: int = _build_draw_items(items, parent, ctx)
	_build_gc_layers(acc["gc"], acc["gc_leaves"], parent, ctx)
	_finalize(acc["result"], ctx, total_inst)
	_log_perf_census(parent, ctx, acc["result"], json_paths)
	return acc["result"]


func load_sublevels_async(json_paths: Array, parent: Node3D, light_probe: Node = null, max_lights: int = 96, generate_collision: bool = true) -> Dictionary:
	var _timing: bool = OS.has_environment("TAT_LOAD_TIMING")
	var _t0: int = Time.get_ticks_msec()
	if _materials_db.is_empty():
		_load_material_dbs()
	var acc: Dictionary = _new_accumulator()
	_prof_glb_ms = 0
	_prof_mat_ms = 0
	_prof_shape_ms = 0
	_VfxManager.prewarm_footstep_mask()
	var total_files: int = maxi(json_paths.size(), 1)
	_beam_fix_count = 0
	_beam_fix_max_scale = 0.0
	_beam_fix_max_axis_err_deg = 0.0
	_beam_fix_max_len_err = 0.0
	_beam_fix_clamped = 0
	_scale_clamp_count = 0
	_scale_clamp_worst = 1.0
	_mirrored_basis_count = 0
	_reset_mirror_counters()
	_roughness_bake_count = 0
	_roughness_bake_px = 0
	_roughness_bake_ms = 0
	_roughness_bake_bytes = 0
	_roughness_cache_hits = 0
	load_progress.emit(0.0, "Parsing JSON...")
	# The graph resolver can add always-loaded sublevels, so the progress
	# denominator is the supplied count and the extra files land in the tail
	# of the parse budget instead of overrunning 0.3. The counter lives in a
	# Dictionary because GDScript lambdas capture scalars by value.
	var progress_state: Dictionary = {"idx": 0}
	var parse_tick: Callable = func(_jp: String, _skipped: bool) -> void:
		progress_state["idx"] = int(progress_state["idx"]) + 1
		var frac: float = minf(0.29, 0.3 * float(int(progress_state["idx"])) / float(total_files))
		load_progress.emit(frac, "Parsing JSON %d/%d..." % [int(progress_state["idx"]), json_paths.size()])
	_parse_sublevels_with_graph(json_paths, acc, parent, parse_tick)
	if parent.get_tree() != null:
		await parent.get_tree().process_frame

	if _timing:
		print("LoadTiming parse_ms=", Time.get_ticks_msec() - _t0)
	var ctx: Dictionary = _new_build_ctx(parent, light_probe, generate_collision)
	ctx["map_hint"] = _map_hint_from_paths(json_paths)
	if _timing:
		ctx["perf_mesh_ms"] = 0
		ctx["perf_build_ms"] = 0
	var effective_budget: int = _effective_light_budget(max_lights)
	ctx["light_budget"] = effective_budget
	ctx["hero_shadows"] = MobileProfile.hero_shadows()
	_apply_collider_budget(ctx, json_paths)
	var pending_lights: Array = _prioritize_lights(acc["lights"], acc["result"]["player_spawns"])
	load_progress.emit(0.3, "Sorting lights...")
	# Active RectLights claim budget slots before the generic point lights.
	_build_rect_lights(acc["rect_lights"], parent, light_probe, ctx, effective_budget)
	var light_budget: int = mini(pending_lights.size(), maxi(effective_budget - int(ctx.get("rect_light_count", 0)), 0))
	var plan: Dictionary = plan_light_selection(pending_lights, light_budget, str(ctx.get("map_hint", "")))
	var selection: Array = plan["selection"] as Array
	var lights_added: int = 0
	var forced_lights: int = 0
	for li in range(selection.size()):
		var sel: Dictionary = selection[li] as Dictionary
		var linfo: Dictionary = sel["info"] as Dictionary
		if _add_one_light(linfo, parent, light_probe, bool(sel.get("shadow", false)), str(ctx.get("map_hint", ""))):
			lights_added += 1
			if bool(sel.get("forced", false)):
				forced_lights += 1
		if li % 20 == 0 or li == selection.size() - 1:
			load_progress.emit(0.3 + 0.2 * float(li + 1) / float(maxi(selection.size(), 1)), "Creating lights %d/%d..." % [li + 1, selection.size()])
			if parent.get_tree() != null:
				await parent.get_tree().process_frame
	ctx["light_count"] = lights_added + int(ctx.get("rect_light_count", 0))
	ctx["gate_light_count"] = forced_lights
	ctx["light_allocation"] = plan["stats"] as Dictionary
	_report_light_allocation(plan["stats"] as Dictionary, str(ctx.get("map_hint", "")))
	_report_gate_lights(lights_added, light_budget, forced_lights, str(ctx.get("map_hint", "")), int(ctx.get("rect_light_count", 0)))
	if _timing:
		print("LoadTiming lights_ms=", Time.get_ticks_msec() - _t0)
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
	if _timing:
		print("LoadTiming terrain_ms=", Time.get_ticks_msec() - _t0)
	load_progress.emit(0.52, "Building curbs...")

	var items: Array = _collect_draw_items(acc)
	_fill_col_path_counts(items, ctx)
	var merge_plan: Array = _prepare_merge_plan(items, ctx)
	var total_inst: int = 0
	for entry_var: Variant in merge_plan:
		var merged_instances: int = _build_merged_cell_node(entry_var as Dictionary, parent, ctx)
		if merged_instances > 0:
			total_inst += merged_instances
	var built: int = 0
	for item: Dictionary in items:
		total_inst += _build_one_draw_item(item, parent, ctx)
		built += 1
		if built % PROGRESS_YIELD_EVERY == 0 or built == items.size():
			load_progress.emit(0.52 + 0.46 * float(built) / float(maxi(items.size(), 1)), "Batching meshes %d/%d..." % [built, items.size()])
			if parent.get_tree() != null:
				await parent.get_tree().process_frame
	if _timing:
		print("LoadTiming draw_ms=", Time.get_ticks_msec() - _t0, " items=", items.size(), " instances=", total_inst, " mesh_ms=", int(ctx.get("perf_mesh_ms", 0)), " build_ms=", int(ctx.get("perf_build_ms", 0)), " glb_ms=", _prof_glb_ms, " mat_ms=", _prof_mat_ms, " shape_ms=", _prof_shape_ms, " downscaled=", downscaled_count)
	load_progress.emit(1.0, "Done")
	_build_gc_layers(acc["gc"], acc["gc_leaves"], parent, ctx)
	_finalize(acc["result"], ctx, total_inst)
	_log_perf_census(parent, ctx, acc["result"], json_paths)
	return acc["result"]


## Ranks authored lights into the fixed light budget. This score is used ONLY
## for that ordering; it tracks the rendered energy (the same monotonic
## mapping as _build_light / _build_rect_lights) so the budget keeps the
## brightest lights instead of the old non-monotonic heuristic. The type bonus
## is expressed against LIGHT_ENERGY_SOFT_CEIL to keep its previous weight.
func _light_score(info: Dictionary) -> float:
	var raw: float = _to_float(info.get("intensity"), 15.0)
	var energy: float = light_energy_for_intensity(raw)
	var ltype: String = str(info.get("type", ""))
	if "Directional" in ltype:
		energy += LIGHT_ENERGY_SOFT_CEIL * 2.5
	# A flat +2.0 for every Spot made all 47 Guildhall slots spots and dropped
	# every warm point lamp. Rank on authored energy only; the type tie-break
	# is no longer needed with the 160-light desktop budget.
	return energy


func _sort_lights_desc(a: Dictionary, b: Dictionary) -> bool:
	var sa: float = _light_score(a)
	var sb: float = _light_score(b)
	if not is_equal_approx(sa, sb):
		return sa > sb
	# Stable tie-break on authored position: equal-energy lights used to rank
	# in whichever order the dictionary iteration produced, so the 160-light
	# cut and the gate allowlist evictions were not reproducible between loads.
	var pa_v: Variant = a.get("pos", null)
	var pb_v: Variant = b.get("pos", null)
	if not (pa_v is Array) or not (pb_v is Array):
		return false
	var pa: Array = pa_v as Array
	var pb: Array = pb_v as Array
	for i in range(3):
		var va: float = float(pa[i]) if i < pa.size() else 0.0
		var vb: float = float(pb[i]) if i < pb.size() else 0.0
		if not is_equal_approx(va, vb):
			return va > vb
	return false


## W10-A3-GC: owner -> intact leaves / broken overlays for the current load.
## Shape: {"leaves": Array[Node3D], "broken": Array[Node3D]}. A chest/display
## case owns one leaf; a bookcase owns two (its paired static-batch glass
## doors, Phase 2 G-2). Either array may be empty when a map authors only one
## half (or GC layers are disabled); containers guard with `is_instance_valid`.
func gc_visuals_for(owner: String) -> Dictionary:
	var rec: Variant = _gc_owner_index.get(owner, null)
	if rec is Dictionary:
		return rec as Dictionary
	return {"leaves": [] as Array, "broken": [] as Array}


## Spawns the destructible layers emitted by tools/parse_tables.py:
##  * one visible MeshInstance3D for each intact chest lid / display-case door
##    (emitted as `gc_leaves`), plus the bookcase glass doors resolved from the
##    static batch (Phase 2 G-2: never duplicated);
##  * one hidden MeshInstance3D for each authored broken-state overlay.
## No StaticBody3D, CollisionShape3D or occluder is created here, so the layers
## add no collision by construction (the GC probe also measures the delta).
func _build_gc_layers(gc_entries: Array, leaf_entries: Array, parent: Node3D, ctx: Dictionary) -> void:
	_gc_owner_index.clear()
	var built_broken: int = 0
	var built_leaves: int = 0
	var missing: int = 0
	var visible_broken: int = 0
	if not gc_layers_enabled():
		ctx["gc_layers_enabled"] = false
		ctx["gc_layers_built"] = 0
		ctx["gc_leaves_built"] = 0
		ctx["gc_missing_mesh"] = 0
		ctx["gc_static_leaves_bound"] = 0
		ctx["gc_static_leaves_unmatched"] = 0
		_gc_static_glass.clear()
		return
	var root := Node3D.new()
	root.name = GC_ROOT_NAME
	root.set_meta("gc_no_collision", true)
	parent.add_child(root)
	for rec_var: Variant in gc_entries:
		if not (rec_var is Dictionary):
			continue
		var rec: Dictionary = rec_var as Dictionary
		var node: MeshInstance3D = _make_gc_mesh_node(rec, "broken", false)
		if node == null:
			missing += 1
			if rec.get("hidden") != true:
				push_error("[level_loader] visible GeometryCollection has no mesh: owner=%s component=%s collection=%s" % [
					str(rec.get("owner", "")), str(rec.get("component", "")), str(rec.get("collection", ""))])
			continue
		root.add_child(node)
		built_broken += 1
		if node.visible:
			visible_broken += 1
		var owner: String = str(rec.get("owner", ""))
		if owner != "":
			var slot: Dictionary = _gc_owner_slot(owner)
			(slot["broken"] as Array).append(node)
			# The broken record is the anchor for the static-batch leaf match:
			# it is the same door's authored end state.
			if str(rec.get("kind", "")) == "bookcase":
				slot["_anchor"] = rec
			_gc_owner_index[owner] = slot
	for rec_var2: Variant in leaf_entries:
		if not (rec_var2 is Dictionary):
			continue
		var rec2: Dictionary = rec_var2 as Dictionary
		var node2: MeshInstance3D = _make_gc_mesh_node(rec2, "leaf", true)
		if node2 == null:
			missing += 1
			continue
		root.add_child(node2)
		built_leaves += 1
		var owner2: String = str(rec2.get("owner", ""))
		if owner2 != "":
			var slot2: Dictionary = _gc_owner_slot(owner2)
			(slot2["leaves"] as Array).append(node2)
			_gc_owner_index[owner2] = slot2
	# Phase 2 G-2: bookcase intact glass lives in the static batch. Bind the
	# nearest unused authored pane to each broken record, one-to-one, by
	# position and source sublevel. Measured 0.472 m for the authored pair vs
	# >= 0.838 m for any other pane, so GC_STATIC_LEAF_MATCH_M is a unique
	# match; an unmatched door is counted, never guessed from a further node.
	var static_bound: int = 0
	var static_unmatched: int = 0
	for owner3: String in _gc_owner_index.keys():
		var slot3: Dictionary = _gc_owner_index[owner3] as Dictionary
		if not slot3.has("_anchor"):
			continue
		slot3.erase("_anchor")
		var owner_source: String = ""
		if not (slot3["broken"] as Array).is_empty():
			var anchor: Node3D = (slot3["broken"] as Array)[0] as Node3D
			if anchor != null:
				owner_source = str(anchor.get_meta("source_sublevel", ""))
		for broken_node: Node3D in (slot3["broken"] as Array):
			if not (broken_node is MeshInstance3D):
				continue
			var bp: Vector3 = broken_node.global_position
			var best: Dictionary = {}
			var best_d: float = GC_STATIC_LEAF_MATCH_M
			for cand: Dictionary in _gc_static_glass:
				if bool(cand.get("used", false)):
					continue
				if owner_source != "" and str(cand.get("source_sublevel", "")) != owner_source:
					continue
				var cand_node: Node3D = cand["node"] as Node3D
				if cand_node == null or not is_instance_valid(cand_node):
					continue
				var d: float = bp.distance_to(cand_node.global_position)
				if d <= best_d:
					best_d = d
					best = cand
			if best.is_empty():
				static_unmatched += 1
				continue
			best["used"] = true
			var leaf_node: Node3D = best["node"] as Node3D
			leaf_node.set_meta("gc_owner", owner3)
			leaf_node.set_meta("gc_kind", "bookcase")
			leaf_node.set_meta("gc_static_leaf", true)
			(slot3["leaves"] as Array).append(leaf_node)
			static_bound += 1
		_gc_owner_index[owner3] = slot3
	# Unused panes stay ordinary static geometry; only the candidate list is
	# released, never the nodes themselves.
	_gc_static_glass.clear()
	ctx["gc_layers_enabled"] = true
	ctx["gc_layers_built"] = built_broken
	ctx["gc_leaves_built"] = built_leaves
	ctx["gc_missing_mesh"] = missing
	ctx["gc_visible_broken"] = visible_broken
	ctx["gc_static_leaves_bound"] = static_bound
	ctx["gc_static_leaves_unmatched"] = static_unmatched


## Owner index slot, preserving both arrays (a bookcase has two doors).
func _gc_owner_slot(owner: String) -> Dictionary:
	var rec: Variant = _gc_owner_index.get(owner, null)
	if rec is Dictionary:
		return rec as Dictionary
	return {"leaves": [] as Array, "broken": [] as Array}


func _make_gc_mesh_node(rec: Dictionary, role: String, make_visible: bool) -> MeshInstance3D:
	var mp: String = str(rec.get("mesh", ""))
	if mp == "":
		return null
	var info: Dictionary = _get_mesh_and_shape(mp)
	var mesh: Mesh = info["mesh"] as Mesh
	if mesh == null:
		return null
	var ov_arr: Array[String] = _extract_override_materials(rec)
	if not ov_arr.is_empty():
		mesh = _get_overridden_mesh(mp, mesh, ov_arr, "|".join(ov_arr))
	var node := MeshInstance3D.new()
	node.name = ("GCLeaf_%s" if role == "leaf" else "GCBroken_%s") % str(rec.get("owner", "unknown"))
	node.mesh = mesh
	node.transform = _dict_to_transform(rec)
	node.visible = make_visible
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_STATIC if make_visible else GeometryInstance3D.GI_MODE_DISABLED
	node.set_meta("ue_mesh", mp)
	node.set_meta("gc_owner", str(rec.get("owner", "")))
	node.set_meta("gc_role", role)
	node.set_meta("gc_kind", str(rec.get("kind", "")))
	node.set_meta("gc_source", str(rec.get("source", "")))
	node.set_meta("source_sublevel", str(rec.get("source_sublevel", "")))
	node.set_meta("gc_no_collision", true)
	node.set_meta("decorative", true)
	node.add_to_group("gc_leaves" if role == "leaf" else "gc_broken_layers")
	return node


func _dict_to_transform(d: Dictionary) -> Transform3D:
	# Exact SM_LightBeam path only: the authored beam axis is record basis
	# column 2 and the authored span is scale slot 2. The old path scaled
	# column 0 (the 1 m cross axis), so every card was a cross-beam bar 90 deg
	# off the beam. See beam_card_transform().
	if str(d.get("mesh", "")) == BEAM_CARD_MESH:
		var beam_tr: Transform3D = beam_card_transform(d)
		_beam_fix_count += 1
		var s_arr: Array = d.get("scale", [1, 1, 1])
		var s_auth: float = float(s_arr[2]) if s_arr.size() > 2 else 1.0
		var auth_basis: Basis = _record_basis(
			d.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1]))
		# The record basis is emitted with 5-decimal rounding, so col2 is only
		# ~1e-5 off unit length. Compare the applied *scale factor*, not the
		# raw column length, or the rounding looks like a clamp.
		var axis_len: float = maxf(auth_basis.z.length(), 0.000001)
		var applied_scale: float = beam_tr.basis.x.length() / axis_len
		_beam_fix_max_scale = maxf(_beam_fix_max_scale, maxf(s_auth, 0.0))
		if is_finite(s_auth) and s_auth > 0.0:
			var len_err: float = absf(applied_scale - s_auth) / s_auth
			_beam_fix_max_len_err = maxf(_beam_fix_max_len_err, len_err)
			# 1e-5 absorbs float32 division noise (~2e-7); a real clamp is
			# orders of magnitude larger (the 200 ceiling would rewrite 5/196
			# Old Manor cards by 15%+).
			if len_err > 0.00001:
				_beam_fix_clamped += 1
		else:
			# Degenerate authored scale (not a real card): count it, never
			# hide it. The transform falls back to 1.0.
			_beam_fix_clamped += 1
			_beam_fix_max_len_err = maxf(_beam_fix_max_len_err, 1.0)
		var auth_axis: Vector3 = auth_basis.z / axis_len
		var card_axis: Vector3 = beam_tr.basis.x.normalized()
		var axis_err: float = rad_to_deg(atan2(
			card_axis.cross(auth_axis).length(), card_axis.dot(auth_axis)))
		_beam_fix_max_axis_err_deg = maxf(_beam_fix_max_axis_err_deg, axis_err)
		return beam_tr
	var p: Array = d.get("pos", [0, 0, 0])
	var b: Array = d.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	var s: Array = d.get("scale", [1, 1, 1])
	var basis: Basis = Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	)
	# RE-P-10: the authored [0.05, 40] clamp used to rewrite thin slabs and
	# oversized volumes with no trace. Keep the clamp (it is load-bearing: a
	# 0.0021 m slab degenerates the collider) but count every instance and the
	# worst ratio so a producer regression is visible in every run log.
	var s_raw := Vector3(float(s[0]), float(s[1]), float(s[2]))
	var s_clamped := Vector3(
		clampf(s_raw.x, 0.05, 40.0),
		clampf(s_raw.y, 0.05, 40.0),
		clampf(s_raw.z, 0.05, 40.0)
	)
	if s_clamped != s_raw:
		_scale_clamp_count += 1
		for ax: int in range(3):
			var authored_ax: float = s_raw[ax]
			if authored_ax <= 0.0:
				continue
			var ratio: float = s_clamped[ax] / authored_ax
			if ratio > _scale_clamp_worst:
				_scale_clamp_worst = ratio
	basis = basis.scaled_local(s_clamped)
	# RE-P-08: reflected bases (det < 0) are authored mirrors. This increment
	# is the placement-transform census (the RE-P-08 probe); the render split
	# is counted in _build_one_draw_item() and reconciled by MIRROR_RECON.
	if basis.determinant() < 0.0:
		_mirrored_basis_count += 1
	return Transform3D(basis, Vector3(float(p[0]), float(p[1]), float(p[2])))


## Row-major 9-float record basis -> Godot Basis (same convention as
## _dict_to_transform). Kept static so the pure beam transform and its
## diagnostics share one construction.
static func _record_basis(b: Array) -> Basis:
	return Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	)


## Pure SM_LightBeam record -> world transform (also used by
## tests/test_beam_geometry.gd). The authored record basis is kept as-is: its
## col2 (Basis.z) is the beam direction — the SM_LightBeam component is
## authored with RelativeRotation.Yaw = 90, so the mesh's 10.2 cm local X runs
## along the actor's local +Z — and record scale slot 2 is the authored length
## scale (`BeamLength` / 0.102 m). The card's local X is rotated onto col2 and
## scaled there; local Y stays on col1, preserving the authored cross width and
## side. There is no ceiling: the authored maximum is 236.9539 (Old Manor,
## 24.169 m). Only non-finite/non-positive scales fall back to 1.0, and the
## loader counts those as clamped.
static func beam_card_transform(d: Dictionary) -> Transform3D:
	var p: Array = d.get("pos", [0, 0, 0])
	var b: Array = d.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	var s: Array = d.get("scale", [1, 1, 1])
	var s_authored: float = float(s[2]) if s.size() > 2 else 1.0
	var s_len: float = s_authored if is_finite(s_authored) and s_authored > 0.0 else 1.0
	# Mesh local X -> record col2, mesh local Y -> record col1: -90 deg about
	# the record's local +Y. Pure rotation, so only the length axis changes.
	var basis: Basis = _record_basis(b) * Basis(Vector3.UP, -PI * 0.5)
	basis = basis.scaled_local(Vector3(s_len, 1.0, 1.0))
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


func _build_light(info: Dictionary, cast_shadow: bool = false, map_hint: String = "") -> Light3D:
	var ltype: String = str(info.get("type", ""))
	var raw_i := _to_float(info.get("intensity"), 15.0)
	var intensity := light_energy_for_intensity(raw_i)
	var is_den_spot: bool = map_hint == "thieves_den" and bool(info.get("_den_spot", false))
	if is_den_spot:
		# Authored Den response: 0.75 x intensity (1.50 / 2.25 / 1.50 / 1.50 /
		# 0.019), inverse-square attenuation, true authored cone (5 deg moon).
		intensity = snappedf(maxf(raw_i * DEN_SPOT_ENERGY_SCALE, LIGHT_ENERGY_FLOOR), 0.001)
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
		if is_den_spot:
			sl.spot_angle = clampf(_to_float(info.get("outer_cone"), 50.0), 0.5, 89.0)
			sl.spot_attenuation = DEN_SPOT_ATTENUATION
		else:
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
	# Authored UE intensity before light_energy_for_intensity mapping. UI
	# passes (startscreen headlights) need the authored value because the
	# mapped light_energy compresses everything above 20 into ~3.3-4.0.
	light.set_meta("tat_ue_intensity", raw_i)
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


## P4.4 landscape visibility-mask diagnostic. `discard` is the shipped rule
## (UE LandscapeVisibilityLayerInfo stores 1 = hole); `raw` samples the mask
## and renders it as a debug A/B without discarding; `off` skips the read.
## An unknown value falls back to `discard` so a typo can never turn authored
## holes into solid terrain. The data assertion for the safe-room gap lives in
## `game/tests/probe_landscape_mask.gd`; no flip happens here.
const LANDSCAPE_MASK_ENV: String = "TAT2_LANDSCAPE_MASK"
const LANDSCAPE_MASK_MODES: Array[String] = ["discard", "raw", "off"]


static func landscape_mask_mode(raw: String = "") -> String:
	var v: String = raw.strip_edges().to_lower()
	if v == "":
		v = OS.get_environment(LANDSCAPE_MASK_ENV).strip_edges().to_lower()
	if v == "":
		return "discard"
	if LANDSCAPE_MASK_MODES.has(v):
		return v
	push_warning("LANDSCAPE_MASK unknown mode '%s'; using discard" % v)
	return "discard"


## Shader parameters for a mode. Kept as a pure function so the probe can
## assert all three paths without a renderer.
static func landscape_mask_params(mode: String = "") -> Dictionary:
	var m: String = landscape_mask_mode(mode)
	if m == "raw":
		return {"mode": m, "sample_mask": 1.0, "discard_holes": 0.0, "mask_raw_view": 1.0}
	if m == "off":
		return {"mode": m, "sample_mask": 0.0, "discard_holes": 0.0, "mask_raw_view": 0.0}
	return {"mode": m, "sample_mask": 1.0, "discard_holes": 1.0, "mask_raw_view": 0.0}


## The authored visibility convention: raw weight 1 = hole. Kept in one place
## so the probe's CPU model and the shader's `vis > 0.5` cannot drift.
static func landscape_mask_hole(vis: float) -> bool:
	return vis > 0.5


## Mask coverage of one weightmap image channel, sampled on a stride. Used by
## the probe and by the optional `TAT2_LANDSCAPE_MASK_STATS=1` log; the load
## path itself only logs presence/channel so a 128-component map does not pay
## a per-texel scan.
static func landscape_mask_stats(img: Image, channel: int, stride: int = 8) -> Dictionary:
	if img == null or img.is_empty() or channel < 0 or channel > 3:
		return {"samples": 0, "holes": 0, "hole_frac": 0.0, "min": 0.0, "max": 0.0, "mean": 0.0}
	var work: Image = img
	if work.is_compressed():
		var dec: Image = work.duplicate() as Image
		if dec == null or dec.decompress() != OK:
			return {"samples": 0, "holes": 0, "hole_frac": 0.0, "min": 0.0, "max": 0.0, "mean": 0.0}
		work = dec
	var w: int = work.get_width()
	var h: int = work.get_height()
	var step: int = maxi(stride, 1)
	var samples: int = 0
	var holes: int = 0
	var mn: float = 1.0
	var mx: float = 0.0
	var sum: float = 0.0
	for y: int in range(0, h, step):
		for x: int in range(0, w, step):
			var c: Color = work.get_pixel(x, y)
			var v: float = c.r
			if channel == 1:
				v = c.g
			elif channel == 2:
				v = c.b
			elif channel == 3:
				v = c.a
			samples += 1
			sum += v
			mn = minf(mn, v)
			mx = maxf(mx, v)
			if landscape_mask_hole(v):
				holes += 1
	return {
		"samples": samples,
		"holes": holes,
		"hole_frac": float(holes) / float(samples) if samples > 0 else 0.0,
		"min": mn if samples > 0 else 0.0,
		"max": mx,
		"mean": sum / float(samples) if samples > 0 else 0.0,
	}


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
	if wm_paths.size() > 2:
		push_warning("Landscape %s: %d weightmaps extracted but only %d bound; extra weightmaps are not sampled" % [source, wm_paths.size(), bound_count])
	var mat := ShaderMaterial.new()
	mat.shader = LANDSCAPE_SHADER
	# UE LandscapeVisibilityLayerInfo stores 1 = hole. The shipped mode is
	# `discard` (sample the authored mask, discard vis > 0.5); `TAT2_LANDSCAPE_MASK`
	# exists only for the raw-mask A/B and the off control. See
	# landscape_mask_params() for the three paths.
	var mask_mode: String = landscape_mask_mode()
	var mask_params: Dictionary = landscape_mask_params(mask_mode)
	mat.set_shader_parameter("sample_mask", float(mask_params["sample_mask"]))
	mat.set_shader_parameter("discard_holes", float(mask_params["discard_holes"]))
	mat.set_shader_parameter("mask_raw_view", float(mask_params["mask_raw_view"]))
	mat.set_shader_parameter("weightmap", wm)
	if wm1 != null:
		mat.set_shader_parameter("weightmap_1", wm1)
	var vis_idx: int = -1
	var vis_ch: int = -1
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
			vis_idx = tex_idx
			vis_ch = channel
			mat.set_shader_parameter("visibility_tex_idx", tex_idx)
			mat.set_shader_parameter("visibility_channel", channel)
			continue
		if slot >= 5:
			continue
		var tex_path: String = str(LANDSCAPE_LAYER_TEX.get(lname, ""))
		# The startscreen street is 95-100% GroundA; the authored surface there
		# is road bricks, not the dirt layer used by the other maps.
		if lname == "GroundA" and source.to_lower().contains("startscreen"):
			tex_path = "res://assets/ue/Raw/MaterialLibrary/Environment/Stone/FloorExterior/T_RoadBricksA_D.png"
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
	# Guildhall's gate approach has no colour weight at all (puddle-only), so
	# the shader's total==0 path used to flatten it to grey. Bind the authored
	# road-brick albedo as that fallback; every other map keeps the grey/dirt
	# fallback_color (fallback_tex_on stays 0.0).
	if source.to_lower().contains("guildhall"):
		var fb_tex: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Stone/FloorExterior/T_RoadBricksA_D.png")
		if fb_tex != null:
			mat.set_shader_parameter("fallback_tex", fb_tex)
			mat.set_shader_parameter("fallback_tex_on", 1.0)
		# The same branch samples the fallback road bricks at UV * uv_scale;
		# bind the matching normal so the street is not lit as flat grey.
		var fb_norm: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Stone/FloorExterior/T_RoadBricksA_N.png")
		if fb_norm != null:
			mat.set_shader_parameter("fallback_normal", fb_norm)
			mat.set_shader_parameter("fallback_normal_on", 1.0)
	# Per-component mask provenance (P4.4). This is the load-time half of the
	# data assertion: which components carry a `LandscapeVisibilityLayerInfo`,
	# on which weightmap/channel, and what the active diagnostic mode does.
	# The coverage fraction is computed by probe_landscape_mask.gd (and by
	# `TAT2_LANDSCAPE_MASK_STATS=1` below) because a per-texel scan on every
	# component would tax the 128-component OldManor map.
	var pos_arr: Array = lc.get("pos", []) as Array
	var pos := Vector3.ZERO
	if pos_arr.size() >= 3:
		pos = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var comp_wm: String = wm_path.get_file()
	if vis_idx == 1 and wm_paths.size() > 1:
		comp_wm = str(wm_paths[1]).get_file()
	var mask_line: String = "LANDSCAPE_MASK src=%s comp=(%.2f,%.2f,%.2f) wm=%s mode=%s mask=%s tex=%d ch=%d sample=%.0f discard=%.0f raw=%.0f" % [
		source, pos.x, pos.y, pos.z, comp_wm, mask_mode,
		"present" if vis_idx >= 0 else "absent", vis_idx, vis_ch,
		float(mask_params["sample_mask"]), float(mask_params["discard_holes"]),
		float(mask_params["mask_raw_view"])]
	if vis_idx >= 0 and OS.get_environment("TAT2_LANDSCAPE_MASK_STATS").strip_edges() == "1":
		var mask_tex: Texture2D = wm1 if vis_idx == 1 else wm
		var mask_img: Image = mask_tex.get_image() if mask_tex != null else null
		var st: Dictionary = landscape_mask_stats(mask_img, vis_ch, 16)
		mask_line += " samples=%d hole_frac=%.4f min=%.3f max=%.3f mean=%.3f" % [
			int(st["samples"]), float(st["hole_frac"]), float(st["min"]),
			float(st["max"]), float(st["mean"])]
	print(mask_line)
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
	# Full res:// literals (no concatenation) so tools/prebake_texture_cap.py
	# finds and pre-caps all four ground maps. The road normal is a 2048² map
	# and used to decode/resize at every load because the tool only scans
	# literals.
	var ground_alb: Texture2D = null
	var ground_norm: Texture2D = null
	if use_road:
		ground_alb = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Stone/FloorExterior/T_RoadBricksA_D.png")
		ground_norm = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Stone/FloorExterior/T_RoadBricksA_N.png")
	if ground_alb == null:
		ground_alb = _load_tex("res://assets/ue/Raw/MaterialLibrary/Legacy/T_CobbleStoneA_D.png")
	if ground_norm == null:
		ground_norm = _load_tex("res://assets/ue/Raw/MaterialLibrary/Legacy/T_CobbleStoneA_N.png")
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
	mat.cull_mode = BaseMaterial3D.CULL_BACK
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
			# Godot treats this winding as clockwise-from-above, so the
			# heightfield top was a backface and cull_back hid the whole
			# terrain (the startscreen street showed sky/fog through it).
			# Emit the opposite winding so the top faces +Y and generate_normals
			# produces up-facing normals.
			st.set_uv(u00); st.add_vertex(p00)
			st.set_uv(u10); st.add_vertex(p10)
			st.set_uv(u11); st.add_vertex(p11)
			st.set_uv(u00); st.add_vertex(p00)
			st.set_uv(u11); st.add_vertex(p11)
			st.set_uv(u01); st.add_vertex(p01)
			faces.append(p00); faces.append(p10); faces.append(p11)
			faces.append(p00); faces.append(p11); faces.append(p01)
	st.generate_normals()
	var arrays: Array = st.commit_to_arrays()
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if arr_mesh.get_surface_count() == 0:
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
