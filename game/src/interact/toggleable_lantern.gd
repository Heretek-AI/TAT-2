extends Node3D
## P1-SAFE: authored caged wall lantern station (S12 / KF14 #2; rows G1-05,
## V1-04). Ports `BP_ToggleableLanternA` as an interactable you can switch:
## `[F] TURN ON` -> warm light + glowing glass/flame -> `[F] TURN OFF`.
##
## Authored sources (every number below is read from the shipped dump):
##   * `extracted/json/Art/Environment/Lights/Mobile/BP_ToggleableLanternA.json`
##     (class defaults): LightIntensity 5.0, LightColor #FFC277
##     (1.0, 0.539479, 0.184475), AttenuationRadius 450 cm, OuterConeAngle
##     80 deg, VolumetricFogIntensity 0, EmissiveMaterialStrength 6.0,
##     EmisShapeColor #FFD08E (1.0, 0.626611, 0.270833), LampCastShadow false,
##     EnableLampMesh / EnableEmisShape true.
##   * `Guildhall_PeripheryA` instance records place the blueprint's three
##     meshes at the same transform: `GasLamp_A` (wall bracket),
##     `SM_LanternGuardA` (iron cage + yellow glass) and a hidden
##     `SM_Sphere2Count` emissive shape scaled (0.4, 0.75, 0.4) 0.293 m above
##     the base, plus one 80 deg spot aimed out of the lamp.
##   * `MI_LanternGuardGlass_Yellow` (mesh slot 1): Emissive On? true,
##     EmissiveStrength 5.0, EmissiveTintB (1.0, 0.5117, 0.0) - the warm glass
##     tone the blueprint drives with EmissiveMaterialStrength.
##   * Prompts: `ST_Interactables.PromptTurnOn` "Turn On" /
##     `PromptTurnOff` "Turn Off", rendered in the reference's `[F] TURN ON` /
##     `[F] TURN OFF` form. The `interact` action is the physical F key.
##
## The station keeps the existing interactable contract: group
## `interactables`, `interact()`, `get_interact_prompt()` and
## `get_interact_point()`. The light is deliberately not registered with
## `light_probe`: `light_probe.short_circuit_lights()`/`tick()` flip `visible`
## on registered lights, which would re-light a lamp the player switched off.
## The safe room has no stealth population, so no guard visibility is lost.
##
## Authored/approximated:
##   * 1:1: mesh paths, glass/cage material join, spot colour/intensity/range/
##     cone/shadow, emissive strength and colour, toggle behaviour, prompts.
##   * APPROX: the flame VFX is the authored hidden `SM_Sphere2Count` emissive
##     shape (the shipped emitter is Niagara HL-1); the flicker is not authored
##     and is intentionally absent.

signal toggled(lit: bool)

const LevelLoaderScript: GDScript = preload("res://src/core/level_loader.gd")

const CAGE_UE_MESH: String = "/Game/Art/Environment/Lights/Mobile/SM_LanternGuardA"
const BRACKET_UE_MESH: String = "/Game/Art/Environment/Lights/GasLamps/GasLamp_A"
const FLAME_UE_MESH: String = "/Game/Art/Environment/Lights/LightModules/EmissiveShapes/SM_Sphere2Count"
const BRACKET_UE_MATERIAL: String = "/Game/Art/Environment/Lights/GasLamps/MI_GasLamps"

const LIGHT_COLOR: Color = Color(1.0, 0.539479, 0.184475)
const LIGHT_INTENSITY: float = 5.0
const LIGHT_RANGE_M: float = 4.5
const LIGHT_OUTER_CONE_DEG: float = 80.0
const LIGHT_VOLUMETRIC_INTENSITY: float = 0.0
const LAMP_CAST_SHADOW: bool = false

const EMISSIVE_MATERIAL_STRENGTH: float = 6.0
const EMIS_SHAPE_COLOR: Color = Color(1.0, 0.626611, 0.270833)
## MI_LanternGuardGlass_Yellow EmissiveTintB - the warm lit end of the glass.
const GLASS_EMISSIVE_TINT: Color = Color(1.0, 0.5117, 0.0)
## PeripheryA instance: SM_Sphere2Count scale (0.4, 0.75, 0.4), 0.293 m up.
const FLAME_SCALE: Vector3 = Vector3(0.4, 0.75, 0.4)
const FLAME_OFFSET_M: float = 0.29

const PROMPT_TURN_ON: String = "[F] TURN ON"
const PROMPT_TURN_OFF: String = "[F] TURN OFF"

## Live level loader (mesh/material resolution). Set before add_child; a
## missing loader builds the station without meshes and is counted, never
## silently white.
var level_loader: Node = null
var lit: bool = false

var cage: MeshInstance3D = null
var bracket: MeshInstance3D = null
var flame: MeshInstance3D = null
var flame_light: SpotLight3D = null
## Duplicated glass surface material; its emission is what the toggle drives.
var glass_material: Material = null
## QA counters: any authored mesh/material the build could not resolve.
var missing_meshes: int = 0
var missing_materials: int = 0


func _ready() -> void:
	add_to_group("interactables")
	_build()
	_apply_lit_state(lit)


## Resolve one authored mesh through the live loader (the same
## `_get_mesh_and_shape` path the level build uses, so the GLB material join is
## identical). Returns null and counts a miss when the loader/asset is absent.
func _mesh_for(ue_path: String) -> MeshInstance3D:
	if level_loader == null or not level_loader.has_method("_get_mesh_and_shape"):
		missing_meshes += 1
		return null
	var info: Dictionary = level_loader.call("_get_mesh_and_shape", ue_path) as Dictionary
	var mesh: Mesh = info.get("mesh") as Mesh
	if mesh == null:
		missing_meshes += 1
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _material_for(ue_path: String) -> Material:
	if level_loader == null or not level_loader.has_method("get_material_for_ue"):
		missing_materials += 1
		return null
	var mat: Material = level_loader.call("get_material_for_ue", ue_path) as Material
	if mat == null:
		missing_materials += 1
	return mat


func _build() -> void:
	if cage != null:
		return
	# Authored composite: gas-lamp bracket + guard lantern at one transform.
	bracket = _mesh_for(BRACKET_UE_MESH)
	if bracket != null:
		bracket.name = "LanternBracket"
		var bracket_mat: Material = _material_for(BRACKET_UE_MATERIAL)
		if bracket_mat != null:
			for s: int in range(bracket.mesh.get_surface_count()):
				bracket.set_surface_override_material(s, bracket_mat)
		add_child(bracket)

	cage = _mesh_for(CAGE_UE_MESH)
	if cage != null:
		cage.name = "LanternCage"
		add_child(cage)
		# Slot 1 is the authored yellow glass; duplicate it so this station can
		# drive emission without touching the shared cached material.
		var src: Material = cage.get_active_material(1)
		if src == null:
			missing_materials += 1
			src = _fallback_glass_material()
		glass_material = src.duplicate()
		cage.set_surface_override_material(1, glass_material)

	# Hidden emissive shape: the authored flame stand-in (Niagara HL-1).
	flame = _mesh_for(FLAME_UE_MESH)
	if flame != null:
		flame.name = "LanternFlame"
		flame.scale = FLAME_SCALE
		flame.position = Vector3(0.0, FLAME_OFFSET_M, 0.0)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var flame_mat := StandardMaterial3D.new()
		flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		flame_mat.albedo_color = Color(
			EMIS_SHAPE_COLOR.r * EMISSIVE_MATERIAL_STRENGTH,
			EMIS_SHAPE_COLOR.g * EMISSIVE_MATERIAL_STRENGTH,
			EMIS_SHAPE_COLOR.b * EMISSIVE_MATERIAL_STRENGTH, 1.0)
		flame.material_override = flame_mat
		add_child(flame)

	# Authored spot: 5.0 / #FFC277 / 4.5 m / 80 deg / no shadow / no fog. The
	# station's local -Z is "out of the wall", which is Godot's spot axis, so
	# no extra rotation is needed.
	flame_light = SpotLight3D.new()
	flame_light.name = "LanternLight"
	flame_light.position = Vector3(0.0, FLAME_OFFSET_M, 0.0)
	flame_light.light_color = LIGHT_COLOR
	flame_light.light_energy = LevelLoaderScript.light_energy_for_intensity(LIGHT_INTENSITY)
	flame_light.spot_range = LIGHT_RANGE_M
	flame_light.spot_angle = LIGHT_OUTER_CONE_DEG
	flame_light.spot_attenuation = 1.0
	flame_light.light_volumetric_fog_energy = LIGHT_VOLUMETRIC_INTENSITY
	flame_light.shadow_enabled = LAMP_CAST_SHADOW
	add_child(flame_light)


## Fallback only for a broken material import: the authored glass tone with no
## texture (counted in `missing_materials` so the probe can report it).
func _fallback_glass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0955, 0.1391, 0.1667, 1.0)
	mat.roughness = 0.6
	return mat


## Drive the three visible states of the authored toggle: spot visibility, the
## glass surface emission and the flame shape. Handles the loader's
## StandardMaterial3D path and its HDR ShaderMaterial path.
func _apply_lit_state(on: bool) -> void:
	lit = on
	if flame_light != null:
		flame_light.visible = on
	if flame != null:
		flame.visible = on
	if glass_material != null:
		if glass_material is StandardMaterial3D:
			var smat: StandardMaterial3D = glass_material as StandardMaterial3D
			smat.emission_enabled = on
			if on:
				smat.emission = GLASS_EMISSIVE_TINT
				smat.emission_energy_multiplier = EMISSIVE_MATERIAL_STRENGTH
			else:
				smat.emission_energy_multiplier = 0.0
		elif glass_material is ShaderMaterial:
			var shmat: ShaderMaterial = glass_material as ShaderMaterial
			if shmat.get_shader_parameter("hdr_scale") != null or _shader_has_uniform(shmat, "hdr_scale"):
				shmat.set_shader_parameter("hdr_color", Vector3(GLASS_EMISSIVE_TINT.r, GLASS_EMISSIVE_TINT.g, GLASS_EMISSIVE_TINT.b))
				shmat.set_shader_parameter("hdr_scale", EMISSIVE_MATERIAL_STRENGTH if on else 0.0)
			elif _shader_has_uniform(shmat, "emission_energy"):
				shmat.set_shader_parameter("emission_color", Vector3(GLASS_EMISSIVE_TINT.r, GLASS_EMISSIVE_TINT.g, GLASS_EMISSIVE_TINT.b))
				shmat.set_shader_parameter("emission_energy", EMISSIVE_MATERIAL_STRENGTH if on else 0.0)


func _shader_has_uniform(mat: ShaderMaterial, uniform_name: String) -> bool:
	if mat.shader == null:
		return false
	for u: Dictionary in mat.shader.get_shader_uniform_list():
		if str(u.get("name", "")) == uniform_name:
			return true
	return false


func set_lit(on: bool, announce: bool = true) -> void:
	_apply_lit_state(on)
	if announce:
		toggled.emit(on)


func is_lit() -> bool:
	return lit


func interact(_who: Node = null) -> void:
	set_lit(not lit)


func get_interact_prompt() -> String:
	return PROMPT_TURN_OFF if lit else PROMPT_TURN_ON


## Readable interaction point: the lantern body, not the wall anchor.
func get_interact_point() -> Vector3:
	return global_position + Vector3(0.0, FLAME_OFFSET_M, 0.0)


func get_interact_hold_seconds() -> float:
	return 0.0
