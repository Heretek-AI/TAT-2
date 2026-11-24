extends Area3D
## Extraction gate: completes the contract when the player enters with required loot/quest item.

signal extracted()


const INTERACTABLES_PATH := "res://data/generated/gameplay/interactables.json"
const PORTAL_SHADER_PATH := "res://src/core/tat_escape_portal.gdshader"
## Fallbacks mirror BP_EscapePoint (_escapeOpenDuration 240,
## _canBeUsedMultipleTimes true); the JSON above is authoritative.
const FALLBACK_OPEN_DURATION_SEC := 240.0

## Visual portal slot (wall outline). Kept as a named child so QA/tests can
## identify the marker without a floating Label3D.
const PORTAL_NODE_NAME := "EscapePortalVisual"
const PORTAL_SIZE: Vector2 = Vector2(2.6, 3.0)

var portal_visual: MeshInstance3D = null

## Seconds the escape stays usable once opened (BP_EscapePoint).
var open_duration_sec: float = FALLBACK_OPEN_DURATION_SEC
## BP_EscapePoint._canBeUsedMultipleTimes: the gate keeps working after a use.
var can_be_used_multiple_times: bool = true
var use_count: int = 0


static func escape_config() -> Dictionary:
	if FileAccess.file_exists(INTERACTABLES_PATH):
		var f: FileAccess = FileAccess.open(INTERACTABLES_PATH, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary and (data as Dictionary).has("escape"):
				var esc: Variant = (data as Dictionary)["escape"]
				if esc is Dictionary:
					return (esc as Dictionary).duplicate()
	return {}


func apply_escape_config(cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	open_duration_sec = float(cfg.get("open_duration_s", open_duration_sec))
	can_be_used_multiple_times = bool(cfg.get("can_be_used_multiple_times", can_be_used_multiple_times))


func _ready() -> void:
	add_to_group("escape_points")
	collision_mask = 2
	apply_escape_config(escape_config())
	body_entered.connect(_on_body_entered)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 3.0)
	col.shape = box
	col.position = Vector3(0, 1.5, 0)
	add_child(col)

	# Wall-outline portal: a thin vertical ring on a QuadMesh in the gate's
	# local XY plane (green core + violet rim shader), so the marker reads as a
	# doorway on the wall instead of the flat green floor cylinder + floating
	# "ESCAPE GATE" label the first port shipped.
	var mi := MeshInstance3D.new()
	mi.name = PORTAL_NODE_NAME
	var quad := QuadMesh.new()
	quad.size = PORTAL_SIZE
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(PORTAL_SHADER_PATH):
		mat.shader = ResourceLoader.load(PORTAL_SHADER_PATH) as Shader
	mi.material_override = mat
	mi.position = Vector3(0, 1.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	portal_visual = mi


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and GameState.state == "playing":
		if GameState.are_all_objectives_complete():
			if can_be_used_multiple_times or use_count == 0:
				use_count += 1
				extracted.emit()
