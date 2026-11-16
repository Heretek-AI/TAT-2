extends Area3D
## Extraction gate: completes the contract when the player enters with required loot/quest item.

signal extracted()


func _ready() -> void:
	collision_mask = 2
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
			extracted.emit()
