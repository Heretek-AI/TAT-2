extends Area3D
## Extraction gate: completes the contract when the player enters with required loot/quest item.

signal extracted()


const INTERACTABLES_PATH := "res://data/generated/gameplay/interactables.json"
## Fallbacks mirror BP_EscapePoint (_escapeOpenDuration 240,
## _canBeUsedMultipleTimes true); the JSON above is authoritative.
const FALLBACK_OPEN_DURATION_SEC := 240.0

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

	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 1.4
	cm.height = 0.15
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.85, 0.35, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.9, 0.4)
	mi.material_override = mat
	add_child(mi)

	var lbl := Label3D.new()
	lbl.position = Vector3(0, 2.3, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.text = "ESCAPE GATE"
	lbl.font_size = 36
	lbl.modulate = Color(0.4, 1.0, 0.5)
	add_child(lbl)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and GameState.state == "playing":
		if GameState.quest_item_acquired or GameState.loot_collected >= GameState.loot_needed:
			if can_be_used_multiple_times or use_count == 0:
				use_count += 1
				extracted.emit()
