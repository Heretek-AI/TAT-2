class_name MissionPrepUI
extends Control
## Mission Preparation screen: full-screen 3D moonlit rooftop stage (SubViewport)
## with a full-body Thief standing on a slanted tiled roof, plus the official
## left-side info stack (Location / Mission / Contract cards) and
## bottom-right [F] READY | [ESC] BACK controls.
## Flow: ContractTableUI confirm dialog -> open_prep(...) -> READY (F/Space)
## emits ready_pressed(map_id, difficulty, mode, contract_order); ESC/BACK
## emits closed().

signal ready_pressed(map_id: String, difficulty: int, mode: String, contract_order: int)
signal closed()

const BODY_CANDIDATES: Array[String] = [
	"res://assets/ue/Content/Art/Character/SK_ThiefNisha__Body.glb",
	"res://assets/ue/Content/Art/Character/Thief/SK_ThiefNisha__Body.glb",
	"res://assets/ue/Raw/Art/Character/SK_ThiefNisha__Body.glb",
	"res://assets/ue/Content/Art/Gameplay/Thief/SK_ThiefNisha__Body.glb",
]
const HEAD_CANDIDATES: Array[String] = [
	"res://assets/ue/Content/Art/Character/SK_ThiefNisha__Head.glb",
	"res://assets/ue/Content/Art/Character/Thief/SK_ThiefNisha__Head.glb",
	"res://assets/ue/Raw/Art/Character/SK_ThiefNisha__Head.glb",
	"res://assets/ue/Content/Art/Gameplay/Thief/SK_ThiefNisha__Head.glb",
]

const LOC_OLD_MANOR_TITLE: String = "ELWAY MANOR"
const LOC_OLD_MANOR_DESC: String = "This is the estate of the three Elway sisters. Although it has fallen into disrepair, both the house and the family that holds it have a very long history in Kilcairn."
const LOC_GUILDHALL_TITLE: String = "CONSTABLES' GUILDHALL"
const LOC_GUILDHALL_DESC: String = "This is the headquarters and operational base for the Constables, Kilcairn's police force."
const CONTRACT_INACTIVE: String = "Contract Inactive"

var map_id: String = "old_manor"
var difficulty: int = 1
var mode: String = "Solo"
var contract_order: int = 1

var _location_body: Label
var _location_title_lbl: Label
var _mission_title_lbl: Label
var _mission_body: Label
var _contract_title_lbl: Label
var _contract_body: Label
var _controls_lbl: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_all()
	_refresh_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Show the prep screen for the given settings and take mouse control.
func open_prep(p_map_id: String, p_difficulty: int, p_mode: String, p_contract_order: int) -> void:
	map_id = p_map_id
	difficulty = clampi(p_difficulty, 1, 3)
	mode = p_mode
	contract_order = p_contract_order
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_all()


## Hide, restore mouse, emit closed and free.
func close_prep() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	visible = false
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo:
			var vp: Viewport = get_viewport()
			if kev.keycode == KEY_F or kev.keycode == KEY_SPACE:
				if vp != null:
					vp.set_input_as_handled()
				_emit_ready()
				return
			if kev.keycode == KEY_ESCAPE:
				if vp != null:
					vp.set_input_as_handled()
				close_prep()
				return


func _emit_ready() -> void:
	ready_pressed.emit(map_id, difficulty, mode, contract_order)
	visible = false
	queue_free()


func _build_all() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var stage_box: SubViewportContainer = SubViewportContainer.new()
	stage_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_box.stretch = true
	stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage_box)
	var viewport: SubViewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage_box.add_child(viewport)
	_build_stage(viewport)

	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.02, 0.25)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var title: Label = Label.new()
	title.text = "MISSION PREPARATION"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-260, 18)
	title.custom_minimum_size = Vector2(520, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var left: VBoxContainer = VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	left.position = Vector2(36, -250)
	left.custom_minimum_size = Vector2(400, 500)
	left.add_theme_constant_override("separation", 14)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	var loc_card: PanelContainer = _make_card("LOCATION", "", "")
	left.add_child(loc_card)
	_location_title_lbl = loc_card.get_meta("title_lbl") as Label
	_location_body = loc_card.get_meta("body_lbl") as Label
	var mis_card: PanelContainer = _make_card("MISSION", "", "")
	left.add_child(mis_card)
	_mission_title_lbl = mis_card.get_meta("title_lbl") as Label
	_mission_body = mis_card.get_meta("body_lbl") as Label
	var con_card: PanelContainer = _make_card("CONTRACT", "", "")
	left.add_child(con_card)
	_contract_title_lbl = con_card.get_meta("title_lbl") as Label
	_contract_body = con_card.get_meta("body_lbl") as Label

	var bottom: VBoxContainer = VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom.position = Vector2(-380, -150)
	bottom.custom_minimum_size = Vector2(344, 114)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	add_child(bottom)
	_controls_lbl = Label.new()
	_controls_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_controls_lbl.add_theme_font_size_override("font_size", 18)
	_controls_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	_controls_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_controls_lbl)
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)
	bottom.add_child(btn_row)
	var ready_btn: Button = Button.new()
	ready_btn.text = "READY [F]"
	ready_btn.custom_minimum_size = Vector2(160, 46)
	ready_btn.pressed.connect(_emit_ready)
	btn_row.add_child(ready_btn)
	var back_btn: Button = Button.new()
	back_btn.text = "BACK [ESC]"
	back_btn.custom_minimum_size = Vector2(160, 46)
	back_btn.pressed.connect(close_prep)
	btn_row.add_child(back_btn)


func _make_card(header: String, title_text: String, body_text: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.035, 0.07, 0.88)
	style.border_color = Color(0.55, 0.45, 0.25, 0.9)
	style.set_border_width_all(2)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	var hdr: Label = Label.new()
	hdr.text = header
	hdr.add_theme_font_size_override("font_size", 15)
	hdr.add_theme_color_override("font_color", Color(0.65, 0.60, 0.42))
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hdr)
	var title_lbl: Label = Label.new()
	title_lbl.text = title_text
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title_lbl)
	var body_lbl: Label = Label.new()
	body_lbl.text = body_text
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.add_theme_font_size_override("font_size", 14)
	body_lbl.add_theme_color_override("font_color", Color(0.86, 0.84, 0.76))
	body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(body_lbl)
	panel.set_meta("title_lbl", title_lbl)
	panel.set_meta("body_lbl", body_lbl)
	return panel


func _build_stage(viewport: SubViewport) -> void:
	var wenv: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.03, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.30, 0.48)
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.08, 0.16)
	env.fog_density = 0.01
	wenv.environment = env
	viewport.add_child(wenv)

	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(0.2, 2.6, 7.2)
	cam.fov = 55.0
	cam.current = true
	viewport.add_child(cam)
	cam.look_at(Vector3(0.4, 1.0, 0.0), Vector3.UP)

	var moonlight: DirectionalLight3D = DirectionalLight3D.new()
	moonlight.rotation_degrees = Vector3(-48, -28, 0)
	moonlight.light_color = Color(0.68, 0.78, 0.98)
	moonlight.light_energy = 0.85
	moonlight.shadow_enabled = true
	viewport.add_child(moonlight)

	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(0.5, 2.4, 5.5)
	fill.light_color = Color(0.45, 0.60, 0.85)
	fill.light_energy = 0.5
	fill.omni_range = 9.0
	viewport.add_child(fill)

	_add_moon(viewport)
	_add_stars(viewport)
	_add_roof(viewport)


func _add_moon(viewport: SubViewport) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.92, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.90, 1.0)
	mat.emission_energy_multiplier = 2.5
	var moon: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.2
	sphere.height = 2.4
	moon.mesh = sphere
	moon.material_override = mat
	moon.position = Vector3(-4.5, 6.5, -20.0)
	viewport.add_child(moon)
	var halo_mat: StandardMaterial3D = StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.albedo_color = Color(0.55, 0.65, 0.95, 0.16)
	halo_mat.emission_enabled = true
	halo_mat.emission = Color(0.55, 0.65, 0.95)
	halo_mat.emission_energy_multiplier = 0.6
	var halo: MeshInstance3D = MeshInstance3D.new()
	var halo_sphere: SphereMesh = SphereMesh.new()
	halo_sphere.radius = 2.1
	halo_sphere.height = 4.2
	halo.mesh = halo_sphere
	halo.material_override = halo_mat
	halo.position = Vector3(-4.5, 6.5, -20.0)
	viewport.add_child(halo)


func _add_stars(viewport: SubViewport) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.93, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.93, 1.0)
	mat.emission_energy_multiplier = 1.2
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	for i: int in range(60):
		var ang: float = rng.randf_range(0.0, TAU)
		var elev: float = rng.randf_range(0.15, 1.2)
		var dist: float = 38.0
		var star: MeshInstance3D = MeshInstance3D.new()
		star.mesh = mesh
		star.material_override = mat
		star.position = Vector3(cos(ang) * cos(elev), sin(elev), sin(ang) * cos(elev)) * dist
		viewport.add_child(star)


func _add_roof(viewport: SubViewport) -> void:
	var roof_root: Node3D = Node3D.new()
	roof_root.rotation_degrees = Vector3(-18, 0, 0)
	viewport.add_child(roof_root)
	var tile_mat: StandardMaterial3D = StandardMaterial3D.new()
	tile_mat.albedo_color = Color(0.09, 0.11, 0.19)
	tile_mat.roughness = 0.9
	var slab: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(30, 16)
	slab.mesh = plane
	slab.material_override = tile_mat
	roof_root.add_child(slab)
	var ridge_mat: StandardMaterial3D = StandardMaterial3D.new()
	ridge_mat.albedo_color = Color(0.13, 0.16, 0.26)
	ridge_mat.roughness = 0.85
	for i: int in range(8):
		var ridge: MeshInstance3D = MeshInstance3D.new()
		var bar: BoxMesh = BoxMesh.new()
		bar.size = Vector3(30, 0.07, 0.35)
		ridge.mesh = bar
		ridge.material_override = ridge_mat
		ridge.position = Vector3(0, 0.05, -7.0 + float(i) * 2.0)
		roof_root.add_child(ridge)
	var chimney: MeshInstance3D = MeshInstance3D.new()
	var ch_box: BoxMesh = BoxMesh.new()
	ch_box.size = Vector3(1.1, 1.6, 1.1)
	chimney.mesh = ch_box
	chimney.material_override = tile_mat
	chimney.position = Vector3(-4.5, 0.8, -3.0)
	roof_root.add_child(chimney)
	var thief_anchor: Node3D = Node3D.new()
	thief_anchor.position = Vector3(0.8, 0.0, 1.0)
	roof_root.add_child(thief_anchor)
	_add_thief(thief_anchor)


func _add_thief(anchor: Node3D) -> void:
	var body_path: String = _first_existing(BODY_CANDIDATES)
	var head_path: String = _first_existing(HEAD_CANDIDATES)
	if body_path != "":
		var body_res: Resource = ResourceLoader.load(body_path) as Resource
		if body_res is PackedScene:
			var body_node: Node = (body_res as PackedScene).instantiate()
			anchor.add_child(body_node)
		else:
			_add_placeholder_body(anchor)
	else:
		_add_placeholder_body(anchor)
	if head_path != "":
		var head_res: Resource = ResourceLoader.load(head_path) as Resource
		if head_res is PackedScene:
			var head_node: Node = (head_res as PackedScene).instantiate()
			head_node.position = Vector3(0, 1.45, 0)
			anchor.add_child(head_node)
		else:
			_add_placeholder_head(anchor)
	else:
		_add_placeholder_head(anchor)


func _add_placeholder_body(anchor: Node3D) -> void:
	var coat_mat: StandardMaterial3D = StandardMaterial3D.new()
	coat_mat.albedo_color = Color(0.07, 0.09, 0.13)
	coat_mat.roughness = 0.8
	var body: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.32
	capsule.height = 1.15
	body.mesh = capsule
	body.material_override = coat_mat
	body.position = Vector3(0, 0.75, 0)
	anchor.add_child(body)
	var trim_mat: StandardMaterial3D = StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.55, 0.38, 0.16)
	trim_mat.roughness = 0.6
	var belt: MeshInstance3D = MeshInstance3D.new()
	var belt_box: BoxMesh = BoxMesh.new()
	belt_box.size = Vector3(0.5, 0.09, 0.4)
	belt.mesh = belt_box
	belt.material_override = trim_mat
	belt.position = Vector3(0, 0.72, 0)
	anchor.add_child(belt)


func _add_placeholder_head(anchor: Node3D) -> void:
	var hood_mat: StandardMaterial3D = StandardMaterial3D.new()
	hood_mat.albedo_color = Color(0.06, 0.07, 0.11)
	hood_mat.roughness = 0.85
	var head: MeshInstance3D = MeshInstance3D.new()
	var skull: SphereMesh = SphereMesh.new()
	skull.radius = 0.22
	skull.height = 0.44
	head.mesh = skull
	head.material_override = hood_mat
	head.position = Vector3(0, 1.5, 0)
	anchor.add_child(head)
	var mask_mat: StandardMaterial3D = StandardMaterial3D.new()
	mask_mat.albedo_color = Color(0.45, 0.08, 0.10)
	mask_mat.roughness = 0.5
	var mask: MeshInstance3D = MeshInstance3D.new()
	var band: BoxMesh = BoxMesh.new()
	band.size = Vector3(0.34, 0.11, 0.10)
	mask.mesh = band
	mask.material_override = mask_mat
	mask.position = Vector3(0, 1.52, 0.16)
	anchor.add_child(mask)


func _first_existing(paths: Array[String]) -> String:
	for p: String in paths:
		if ResourceLoader.exists(p):
			return p
	return ""


func _refresh_all() -> void:
	_refresh_location_card()
	_refresh_mission_card()
	_refresh_contract_card()
	_refresh_controls()


func _refresh_location_card() -> void:
	if _location_title_lbl == null or _location_body == null:
		return
	var info: Array = _location_info()
	_location_title_lbl.text = str(info[0])
	_location_body.text = str(info[1])


func _location_info() -> Array:
	if map_id == "old_manor":
		return [LOC_OLD_MANOR_TITLE, LOC_OLD_MANOR_DESC]
	if map_id == "guildhall":
		return [LOC_GUILDHALL_TITLE, LOC_GUILDHALL_DESC]
	if map_id == "jaspering_hall":
		return ["JASPERING HALL", "A glittering jewelry house and private gallery in Kilcairn's merchant quarter, heavy with private security."]
	return [map_id.to_upper(), "A shadowed mark in Kilcairn, ripe for the taking."]


func _refresh_mission_card() -> void:
	if _mission_title_lbl == null or _mission_body == null:
		return
	var idx: int = abs(contract_order) % 3
	var titles: Array[String] = ["Vault Heist", "Item Collection Heist", "Cleanout Heist"]
	_mission_title_lbl.text = titles[idx]
	var minutes: int = _mission_minutes(idx, difficulty)
	var desc: String = _mission_description(idx, minutes)
	_mission_body.text = desc + "\nTime Limit: %d minutes" % minutes


func _mission_minutes(mission_idx: int, diff: int) -> int:
	var d: int = clampi(diff, 1, 3)
	if mission_idx == 2:
		if map_id == "old_manor":
			var old_times: Array[int] = [75, 30, 25]
			return old_times[d - 1]
		if map_id == "guildhall":
			var gh_times: Array[int] = [55, 20, 20]
			return gh_times[d - 1]
		var other_times: Array[int] = [60, 30, 20]
		return other_times[d - 1]
	var std_times: Array[int] = [120, 45, 30]
	return std_times[d - 1]


func _mission_description(mission_idx: int, minutes: int) -> String:
	var mins: String = str(minutes)
	if map_id == "old_manor":
		if mission_idx == 0:
			return "The Elway family has a magical tome they keep under the utmost protection in a vault. Tonight you will have a %s minute window when security is light. Find the book, steal it, and get out alive." % mins
		if mission_idx == 1:
			return "The Claymur Urns have been held by the Elway family for centuries. The Guild will pay handsomely if you retrieve the full set. You have a %s minute window to pilfer the Urns and make your escape." % mins
		return "Though both the Elway family and their estate are a shadow of what they once were, there are still ample treasures to be found. Get in, steal everything you can, and get out before anyone is the wiser."
	if mission_idx == 0:
		return "A rare bust called the Warburg Effigy is being held at the Guildhall for safekeeping. Tonight there is a %s minute window when security will be light. Steal the bust, embarrass the police, and turn a tidy profit." % mins
	if mission_idx == 1:
		return "The precious gems needed to restore an artifact are hidden among the trinkets gathering dust in the Guildhall. You have a %s minute window to pilfer the gems from under the very noses of the police." % mins
	return "The Constables' Guildhall is full of confiscated treasures. Infiltrate the building and reacquire some of the riches they have just left lying around, then slip away before anyone notices."


func _refresh_contract_card() -> void:
	if _contract_title_lbl == null or _contract_body == null:
		return
	var info: Array = _contract_info()
	_contract_title_lbl.text = str(info[0])
	_contract_body.text = str(info[1])


func _contract_info() -> Array:
	if contract_order <= 0:
		return [CONTRACT_INACTIVE, "No available contract for this co-op mission."]
	var disp: Dictionary = GameData.get_contract_display(contract_order)
	var title_text: String = str(disp.get("title", ""))
	if title_text == "":
		return [CONTRACT_INACTIVE, "No available contract for this co-op mission."]
	var quest_text: String = str(disp.get("quest_item", ""))
	var loc_text: String = str(disp.get("location", ""))
	var body_text: String = "Active contract: %s" % title_text
	if quest_text != "":
		body_text += "\nTarget: %s" % quest_text
	if loc_text != "":
		body_text += "\n%s" % loc_text
	return [title_text, body_text]


func _refresh_controls() -> void:
	if _controls_lbl == null:
		return
	_controls_lbl.text = "Difficulty: %s  |  Mode: %s\n[F] READY  |  [ESC] BACK" % [_difficulty_label(), mode]


func _difficulty_label() -> String:
	if difficulty == 1:
		return "Novice"
	if difficulty == 2:
		return "Thief"
	return "Master Thief"
