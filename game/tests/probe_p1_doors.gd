extends SceneTree
## P1 Lane D — S21 blue double doors (V3-03 / UI2-05 / PG-2 / KF24).
##
## Measures, from the committed generated data and the real door scripts:
##
##   1. RECORDS — the authored S21 door records in `Building_Guildhall_POI`:
##      actor `BP_Manor_Porch_Door_8x8_C_0/1`, one `Pivot` + one `SecondPivot`
##      leaf each, leaf mesh `SM_Civic_DoorDouble_x4` (6x8 civic double door,
##      the mesh the shipped porch door's `OriginalMesh` names). No authored
##      `_locked`, no `CanBeLockpicked: false` — so these are the unlocked
##      blue doors KF24 shows `[F] OPEN` over `[F] [HOLD] LOCK` on.
##   2. MATERIAL SLOTS — the leaf's two surfaces bind the authored materials in
##      GLB primitive order (slot 0 = MI_TrimMetalA_brass: the diamond mullion
##      grid + the twin pulls; slot 1 = MI_ManorTrim: the painted slab). The
##      probe reads the runtime `MeshInstance3D`'s surface materials and their
##      albedo texture paths, i.e. what the renderer actually samples.
##   3. PROMPTS — the authored stack and its transitions:
##      closed unlocked -> `[F] OPEN` above `[F] [HOLD] LOCK`;
##      during/after the swing -> `[F] CLOSE` with no secondary;
##      closed again -> the pair returns; held F -> locked -> `[F] PICK LOCK`.
##      The HUD half is measured on the real HUD widgets: the primary prompt
##      row and the secondary label are built and the secondary sits BELOW the
##      primary (KF24 layout), with the visible keycap reading `F`.
##   4. INTERACTION — interact opens (90 deg), interact closes (0 deg),
##      interact_hold locks, a pick on the locked door unlocks + swings.
##   5. LOCKPICK — the authored circular minigame parameters are present in
##      `interactables.json` (arc_angle_deg / tracks / jam damage) and the HUD
##      owns a circular dial overlay. The authored UMG widget tree itself is not
##      in the dump, so the overlay is a PORT_DECISION rendering, not authored
##      art: printed as HARD_LIMIT and never faked.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game --script res://tests/probe_p1_doors.gd"
##
## The probe never writes anything and never starts a renderer.

## Autoload-dependent scripts are loaded at runtime (not preloaded): a preload
## is compiled before the SceneTree registers `GameState`/`NoiseBus`, which
## leaves the script uncompiled in `--script` runs (same reason
## tests/test_m2_player.gd uses load()).
const POI_RECORD: String = "res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json"
const INTERACTABLES: String = "res://data/generated/gameplay/interactables.json"

## The two S21 porch-door actors (8x8 = 3 m double doorway, 4 m leaves).
const S21_ACTORS: Array[String] = ["BP_Manor_Porch_Door_8x8_C_0", "BP_Manor_Porch_Door_8x8_C_1"]
## Authored leaf mesh for those actors (producer: `swinging_doors[].leaves[].mesh`).
const DOOR_MESH_UE: String = "/Game/Art/Environment/Civic/Doors/SM_Civic_DoorDouble_x4"
## Expected authored slots in GLB primitive order, with the albedo each
## material resolves to in `materials.json` (measured, not invented).
const SLOT_UE: Array[String] = [
	"/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalA_brass",
	"/Game/MaterialLibrary/Environment/Wood/Manor/MI_ManorTrim",
]
const SLOT_ALBEDO: Array[String] = [
	"res://assets/ue/Raw/MaterialLibrary/Environment/Metal/T_TrimMetalA_D.png",
	"res://assets/ue/Raw/MaterialLibrary/Environment/Wood/Manor/T_ManorTrim_D.png",
]
## The authored ORM map each slot binds (AO + metallic + the roughness bake input).
const SLOT_ORM: Array[String] = [
	"res://assets/ue/Raw/MaterialLibrary/Environment/Metal/T_TrimMetalA_ORM.png",
	"res://assets/ue/Raw/MaterialLibrary/Environment/Wood/Manor/T_ManorTrim_ORM.png",
]
## Leaf extent of SM_Civic_DoorDouble_x4 (GLB bounds 1.5 x 4.0 x 0.26 m).
const LEAF_SIZE: Vector3 = Vector3(1.5, 4.0, 0.26)

## KF24 verbatim copy (REFERENCE_BASELINE UI2-05); never reworded.
const PROMPT_OPEN: String = "[F] OPEN"
const PROMPT_LOCK: String = "[F] [HOLD] LOCK"
const PROMPT_CLOSE: String = "[F] CLOSE"
const PROMPT_PICK_PREFIX: String = "[F] PICK LOCK"

var fails: int = 0
var checks: int = 0


class DummyActor:
	extends Node3D
	var lockpicking_active: bool = false

	func set_lockpicking_active(value: bool) -> void:
		lockpicking_active = value


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok: ", msg)
	else:
		fails += 1
		print("  FAIL: ", msg)


func _init() -> void:
	call_deferred("_run")


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


## The authored records for the two S21 porch doors, in file order.
func _s21_records(data: Dictionary) -> Array:
	var out: Array = []
	for rec_var: Variant in (data.get("swinging_doors", []) as Array):
		if not (rec_var is Dictionary):
			continue
		var rec: Dictionary = rec_var as Dictionary
		var actor: String = str(rec.get("actor", ""))
		if S21_ACTORS.has(actor):
			out.append(rec)
	return out


func _leaf_meshes(rec: Dictionary) -> Array:
	var out: Array = []
	for leaf_var: Variant in (rec.get("leaves", []) as Array):
		if leaf_var is Dictionary:
			out.append(str((leaf_var as Dictionary).get("mesh", "")))
	return out


## Frames to let tweens/timers run headless (physics at 60 Hz).
func _wait_frames(n: int) -> void:
	for _i: int in range(n):
		await physics_frame


func _run() -> void:
	print("P1_DOORS probe — S21 blue double doors (KF24)")
	print("  project=", ProjectSettings.globalize_path("res://").simplify_path())
	var LoaderScript: GDScript = load("res://src/core/level_loader.gd") as GDScript
	var DoorScript: GDScript = load("res://src/interact/swinging_door.gd") as GDScript
	var HudScript: GDScript = load("res://src/ui/hud.gd") as GDScript
	if LoaderScript == null or DoorScript == null or HudScript == null:
		print("P1_DOORS FAIL: door/hud/loader scripts did not compile")
		quit(1)
		return

	# --- 1. authored records ------------------------------------------------
	var data_v: Variant = _read_json(POI_RECORD)
	if not (data_v is Dictionary):
		print("P1_DOORS FAIL: cannot read ", POI_RECORD)
		quit(1)
		return
	var data: Dictionary = data_v as Dictionary
	var records: Array = _s21_records(data)
	_check(records.size() == 4,
		"S21 records = 4 (2 actors x Pivot+SecondPivot), got %d" % records.size())
	var rec_positions: Array[String] = []
	var records_ok: bool = true
	for rec_var: Variant in records:
		var rec: Dictionary = rec_var as Dictionary
		var cls: String = str(rec.get("class", ""))
		var meshes: Array = _leaf_meshes(rec)
		var pos: Array = rec.get("pos", [])
		if pos.size() >= 3:
			rec_positions.append("%s@(%.2f,%.2f,%.2f)" % [
				str(rec.get("name", "?")), float(pos[0]), float(pos[1]), float(pos[2])])
		var ok: bool = cls == "BP_Civic_Doorway_6x8_C" and meshes.size() == 1 \
			and str(meshes[0]) == DOOR_MESH_UE \
			and rec.get("locked") != true and rec.get("can_lockpick") != false
		if not ok:
			records_ok = false
			print("    record mismatch: ", rec.get("name"), " class=", cls, " leaves=", meshes,
				" locked=", rec.get("locked"), " can_lockpick=", rec.get("can_lockpick"))
	_check(records_ok,
		"every S21 record: class BP_Civic_Doorway_6x8_C, 1 leaf %s, unlocked, lockpickable" % DOOR_MESH_UE)
	for line: String in rec_positions:
		print("    record ", line)
	_check(not records.is_empty() and str(records[0].get("max_lock_level", "")) != "",
		"authored lock config present (min_lock_level=%s max_lock_level=%s on the first record)"
			% [str(records[0].get("min_lock_level", "<none>")), str(records[0].get("max_lock_level", "<none>"))])

	# --- 2. runtime doors + authored material slots -------------------------
	var loader: Node = LoaderScript.new()
	loader.name = "P1DoorsLoader"
	# In the tree so its `_exit_tree` cache teardown runs on the free below
	# (the roughness/material caches are process-global otherwise).
	root.add_child(loader)
	loader.call("_load_material_dbs")
	var holder: Node3D = Node3D.new()
	holder.name = "P1Doors"
	root.add_child(holder)

	var doors: Array = []
	for rec_var: Variant in records:
		var door: Node3D = DoorScript.new()
		# configure() must run before add_child: _ready() builds the pivot and
		# leaves only for a valid record (same contract as mission_controller).
		door.call("configure", rec_var as Dictionary, loader)
		holder.add_child(door)
		doors.append(door)
	await _wait_frames(3)

	var built: int = 0
	for d_var: Variant in doors:
		var d: Node3D = d_var as Node3D
		var piv: Variant = d.get("pivot")
		if piv is Node and (piv as Node).get_child_count() > 1:
			built += 1
	_check(built == 4, "4/4 S21 door nodes built a pivot + leaf (got %d)" % built)

	var leaf: MeshInstance3D = null
	for d_var: Variant in doors:
		var piv_v: Variant = (d_var as Node3D).get("pivot")
		if not (piv_v is Node):
			continue
		for ch: Node in (piv_v as Node).get_children():
			if ch is MeshInstance3D:
				leaf = ch as MeshInstance3D
				break
		if leaf != null:
			break
	_check(leaf != null, "leaf MeshInstance3D present on the first door")
	if leaf == null or leaf.mesh == null:
		print("P1_DOORS FAIL: no leaf mesh (doors=%d built=%d)" % [doors.size(), built])
		quit(1)
		return

	var mesh: Mesh = leaf.mesh
	_check(mesh != null and mesh.get_surface_count() == 2,
		"leaf has 2 GLB surfaces (got %d)" % (mesh.get_surface_count() if mesh != null else -1))
	var aabb: AABB = mesh.get_aabb()
	print("    leaf AABB size=", aabb.size, " surfaces=", mesh.get_surface_count())
	_check(absf(aabb.size.x - LEAF_SIZE.x) < 0.02 and absf(aabb.size.y - LEAF_SIZE.y) < 0.02,
		"leaf extent %.2f x %.2f m == authored 1.5 x 4.0" % [aabb.size.x, aabb.size.y])

	var slot_albedo: Array[String] = []
	var slot_orm: Array[String] = []
	for s: int in range(mesh.get_surface_count()):
		var mat: Material = leaf.get_surface_override_material(s)
		if mat == null:
			mat = mesh.surface_get_material(s)
		var bm: BaseMaterial3D = mat as BaseMaterial3D
		_check(bm != null, "surface %d material is a BaseMaterial3D (%s)"
			% [s, (mat.get_class() if mat != null else "<null>")])
		var albedo_path: String = ""
		if bm != null and bm.albedo_texture != null:
			albedo_path = bm.albedo_texture.resource_path
		var orm_path: String = ""
		if bm != null and bm.ao_texture != null:
			orm_path = bm.ao_texture.resource_path
		slot_albedo.append(albedo_path)
		slot_orm.append(orm_path)
		print("    slot %d albedo=%s normal=%s orm=%s roughness=%s" % [
			s, albedo_path.get_file(),
			(bm.normal_texture.resource_path.get_file() if bm != null and bm.normal_texture != null else "<none>"),
			orm_path.get_file(),
			(bm.roughness_texture.resource_path.get_file() if bm != null and bm.roughness_texture != null else "<baked/flat>"),
		])
	_check(slot_albedo.size() == 2 and slot_albedo[0] == SLOT_ALBEDO[0],
		"slot 0 (mullions + twin pulls) = %s (got %s)"
			% [SLOT_UE[0].get_file(), slot_albedo[0].get_file() if slot_albedo.size() > 0 else "<none>"])
	_check(slot_albedo.size() == 2 and slot_albedo[1] == SLOT_ALBEDO[1],
		"slot 1 (painted slab) = %s (got %s)"
			% [SLOT_UE[1].get_file(), slot_albedo[1].get_file() if slot_albedo.size() > 1 else "<none>"])
	_check(slot_albedo.size() == 2 and slot_albedo[0] != slot_albedo[1],
		"slots are not collapsed/duplicated (order is real, not slot 0 twice)")
	_check(slot_orm.size() == 2 and slot_orm[0] == SLOT_ORM[0] and slot_orm[1] == SLOT_ORM[1],
		"each slot binds its own authored ORM map (AO + metallic + roughness input)")

	# --- 3. authored prompt stack -----------------------------------------
	var door0: Node3D = doors[0] as Node3D
	var actor := DummyActor.new()
	holder.add_child(actor)
	# Stand at the leaf: the R10 authored lockpick cancel radius (GA_Lockpick
	# distance_before_cancel 200 cm) ends a pick from further away.
	actor.global_position = door0.global_position + Vector3(0.0, 0.0, 0.6)

	var p_open: String = str(door0.call("get_interact_prompt"))
	var s_lock: String = str(door0.call("get_interact_secondary_prompt"))
	_check(p_open == PROMPT_OPEN, "closed primary == \"%s\" (got \"%s\")" % [PROMPT_OPEN, p_open])
	_check(s_lock == PROMPT_LOCK, "closed secondary == \"%s\" (got \"%s\")" % [PROMPT_LOCK, s_lock])
	print("    KF24 stack: \"%s\" above \"%s\"" % [p_open, s_lock])

	door0.call("interact", actor)
	var swing_prompt: String = str(door0.call("get_interact_prompt"))
	var swing_secondary: String = str(door0.call("get_interact_secondary_prompt"))
	_check(swing_prompt == PROMPT_CLOSE,
		"during the swing primary flips to \"%s\" (got \"%s\")" % [PROMPT_CLOSE, swing_prompt])
	_check(swing_secondary == "",
		"during the swing the [HOLD] LOCK row is withdrawn (got \"%s\")" % swing_secondary)
	var mid_angle: float = float(door0.call("open_angle_deg"))
	await _wait_frames(12)
	var mid_angle2: float = float(door0.call("open_angle_deg"))
	_check(mid_angle2 > mid_angle, "the leaf is swinging (angle %.1f -> %.1f deg)" % [mid_angle, mid_angle2])
	await _wait_frames(24)
	_check(float(door0.call("open_angle_deg")) > 85.0,
		"swing completes at the authored 90 deg (got %.1f)" % float(door0.call("open_angle_deg")))
	_check(str(door0.call("get_interact_prompt")) == PROMPT_CLOSE and bool(door0.get("is_open")),
		"open door stays on \"%s\"" % PROMPT_CLOSE)

	door0.call("interact", actor)
	var closing_prompt: String = str(door0.call("get_interact_prompt"))
	var closing_secondary: String = str(door0.call("get_interact_secondary_prompt"))
	_check(closing_prompt == PROMPT_OPEN, "while closing primary is \"%s\" (got \"%s\")" % [PROMPT_OPEN, closing_prompt])
	_check(closing_secondary == "", "while closing the secondary stays withdrawn")
	await _wait_frames(36)
	_check(float(door0.call("open_angle_deg")) < 1.0,
		"close returns the pivot to 0 deg (got %.1f)" % float(door0.call("open_angle_deg")))
	_check(str(door0.call("get_interact_prompt")) == PROMPT_OPEN
			and str(door0.call("get_interact_secondary_prompt")) == PROMPT_LOCK,
		"closed again restores \"%s\" + \"%s\"" % [PROMPT_OPEN, PROMPT_LOCK])

	# --- 4. [HOLD] LOCK + pick open ----------------------------------------
	var authored_min: int = int(door0.get("authored_min_lock_level"))
	var authored_max: int = int(door0.get("authored_max_lock_level"))
	_check(authored_min == 2 and authored_max == 3,
		"door carries the authored lock band 2..3 (got %d..%d)" % [authored_min, authored_max])
	door0.call("interact_hold", actor)
	_check(bool(door0.get("locked")), "interact_hold locks the closed door")
	var relock_lvl: int = int(door0.get("lock_level"))
	_check(relock_lvl >= maxi(authored_min, 1) and relock_lvl <= authored_max,
		"[HOLD] LOCK stays inside the authored band (lock_level=%d in %d..%d)"
			% [relock_lvl, maxi(authored_min, 1), authored_max])
	var pick_prompt: String = str(door0.call("get_interact_prompt"))
	_check(pick_prompt == "%s (Lv %d)" % [PROMPT_PICK_PREFIX, relock_lvl],
		"locked primary reads \"%s (Lv %d)\" (got \"%s\")" % [PROMPT_PICK_PREFIX, relock_lvl, pick_prompt])
	_check(str(door0.call("get_interact_secondary_prompt")) == "",
		"locked door offers no second hold action")
	print("    locked: \"%s\"" % pick_prompt)

	door0.call("interact", actor)
	_check(bool(door0.get("is_lockpicking")), "interact on the locked door starts a pick")
	_check(bool(actor.lockpicking_active), "the pick drives actor.set_lockpicking_active(true)")
	await _wait_frames(120)  # headless timed unlock: track 3.0 s clamps to 1.2 s, then the swing
	_check(not bool(door0.get("locked")), "the pick unlocks the door (locked=false)")
	_check(bool(door0.get("is_open")) and float(door0.call("open_angle_deg")) > 70.0,
		"a successful pick swings the door past the 70 deg leaf gate (angle %.1f)" % float(door0.call("open_angle_deg")))
	_check(not bool(actor.lockpicking_active), "the unlock clears actor.set_lockpicking_active")

	# --- 5. HUD stacked-prompt layout (real HUD widgets) --------------------
	var hud: CanvasLayer = HudScript.new()
	hud.name = "P1DoorsHUD"
	var ui_root: Control = Control.new()
	ui_root.name = "P1DoorsHudRoot"
	ui_root.size = Vector2(1920.0, 1080.0)
	root.add_child(ui_root)
	hud.call("_build_reticle_and_prompt", ui_root)
	ui_root.add_child(hud)
	await _wait_frames(2)
	hud.call("_set_prompt", PROMPT_OPEN)
	hud.call("_set_secondary_prompt", PROMPT_LOCK)
	await _wait_frames(2)
	var primary_lbl: Label = hud.get("interact_lbl") as Label
	var secondary_lbl: Label = hud.get("_prompt_secondary_lbl") as Label
	var keycap: PanelContainer = hud.get("_prompt_keycap") as PanelContainer
	var keycap_lbl: Label = hud.get("_prompt_keycap_lbl") as Label
	var s_keycap: PanelContainer = hud.get("_prompt_secondary_keycap") as PanelContainer
	var s_keycap_lbl: Label = hud.get("_prompt_secondary_keycap_lbl") as Label
	_check(primary_lbl != null and primary_lbl.text == "OPEN" and primary_lbl.visible,
		"HUD primary label renders \"OPEN\" (got \"%s\")" % (primary_lbl.text if primary_lbl != null else "<null>"))
	_check(keycap != null and keycap.visible and keycap_lbl != null and keycap_lbl.text == "F",
		"HUD primary keycap renders F (got \"%s\")" % (keycap_lbl.text if keycap_lbl != null else "<null>"))
	_check(secondary_lbl != null and secondary_lbl.visible and secondary_lbl.text == "[HOLD] LOCK",
		"HUD secondary text renders \"[HOLD] LOCK\" (got \"%s\")"
			% (secondary_lbl.text if secondary_lbl != null else "<null>"))
	_check(s_keycap != null and s_keycap.visible and s_keycap_lbl != null and s_keycap_lbl.text == "F",
		"HUD secondary row has its own white F keycap (got \"%s\")"
			% (s_keycap_lbl.text if s_keycap_lbl != null else "<null>"))
	if primary_lbl != null and secondary_lbl != null:
		var p_row: Control = primary_lbl.get_parent() as Control
		var s_row: Control = hud.get("_prompt_secondary_row") as Control
		var p_rect: Rect2 = p_row.get_global_rect()
		var s_rect: Rect2 = s_row.get_global_rect() if s_row != null else secondary_lbl.get_global_rect()
		var parent_w: float = ((p_row.get_parent() as Control).size.x) if p_row != null and p_row.get_parent() is Control else 0.0
		print("    HUD layout: parent_w=%.0f primary row y=%.1f..%.1f secondary row y=%.1f..%.1f"
			% [parent_w, p_rect.position.y, p_rect.end.y, s_rect.position.y, s_rect.end.y])
		_check(s_rect.position.y >= p_rect.end.y - 6.0,
			"HUD stacks the secondary BELOW the primary (primary end %.1f, secondary start %.1f)"
				% [p_rect.end.y, s_rect.position.y])
		_check(absf(p_rect.get_center().x - s_rect.get_center().x) <= 1.0,
			"both rows share the reticle centre (primary %.1f, secondary %.1f)"
				% [p_rect.get_center().x, s_rect.get_center().x])
		_check(parent_w > 0.0 and absf(p_rect.get_center().x - parent_w * 0.5) <= 1.0,
			"the stack is centred on the screen axis (row centre %.1f, axis %.1f)"
				% [p_rect.get_center().x, parent_w * 0.5])
	hud.call("_set_prompt", PROMPT_CLOSE)
	hud.call("_set_secondary_prompt", "")
	await _wait_frames(1)
	_check(primary_lbl != null and primary_lbl.text == "CLOSE",
		"HUD flips to \"CLOSE\" (got \"%s\")" % (primary_lbl.text if primary_lbl != null else "<null>"))
	_check(secondary_lbl != null and not secondary_lbl.visible
			and (s_keycap == null or not s_keycap.visible),
		"HUD hides the whole secondary row when the door reports none")

	# --- 6. lockpick: authored parameters vs authored widget art -----------
	var inter: Variant = _read_json(INTERACTABLES)
	var lp: Dictionary = {}
	if inter is Dictionary and (inter as Dictionary).get("lockpick") is Dictionary:
		lp = (inter as Dictionary)["lockpick"] as Dictionary
	_check(not lp.is_empty(), "authored lockpick table present in interactables.json")
	var variations: Dictionary = lp.get("variations_by_difficulty", {}) if lp.get("variations_by_difficulty", {}) is Dictionary else {}
	var first_variation: Dictionary = {}
	if variations.get("0") is Array and not (variations["0"] as Array).is_empty():
		first_variation = (variations["0"] as Array)[0] as Dictionary
	var first_track: Dictionary = {}
	if first_variation.get("tracks") is Array and not (first_variation["tracks"] as Array).is_empty():
		first_track = (first_variation["tracks"] as Array)[0] as Dictionary
	_check(float(first_track.get("arc_angle_deg", 0.0)) > 0.0,
		"authored minigame is ARC/circular: arc_angle_deg=%.0f deg, duration=%.1f s"
			% [float(first_track.get("arc_angle_deg", 0.0)), float(first_track.get("duration_s", 0.0))])
	_check(not (lp.get("jam_damage_by_lock_level", {}) as Dictionary).is_empty()
			and float(lp.get("distance_before_cancel", 0.0)) > 0.0,
		"authored jam table + cancel radius present (jam=%s cancel=%.0f cm)"
			% [str(lp.get("jam_damage_by_lock_level", {})), float(lp.get("distance_before_cancel", 0.0))])
	_check(hud.has_method("start_lockpick_minigame") and hud.has_method("open_lockpick_minigame"),
		"HUD owns the circular lockpick overlay entry points")
	var dial: Node = ui_root.find_child("LockpickDial", true, false)
	var overlay: Node = ui_root.find_child("LockpickMinigameOverlay", true, false)
	print("    lockpick UI nodes on the built HUD fragment: overlay=%s dial=%s"
		% [str(overlay != null), str(dial != null)])
	# HARD_LIMIT / PORT_DECISION: the overlay art itself is not in the dump.
	var widget_dumps: int = 0
	for dir_candidate: String in [
		"res://assets/ue/Content/UI",
		"res://assets/ue/Content/Gameplay/Interactables/Locks",
	]:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_candidate)):
			var d: DirAccess = DirAccess.open(dir_candidate)
			if d != null:
				d.list_dir_begin()
				var e: String = d.get_next()
				while e != "":
					if e.to_lower().find("lockpick") >= 0:
						widget_dumps += 1
					e = d.get_next()
				d.list_dir_end()
	print("    HARD_LIMIT: authored lockpick UMG widget dump entries=%d (0 = art not exported);"
		% widget_dumps, " the dial is a PORT_DECISION rendering of the authored arc parameters.")
	print("    PORT_DECISION: PG-2's parity scenario looks for LockpickWheel/LockpickArc;"
		+ " the port's nodes are LockpickMinigameOverlay/LockpickDial (no authored name to rename to).")

	# --- summary ----------------------------------------------------------
	print("P1_DOORS checks=%d fails=%d" % [checks, fails])
	print("P1_DOORS ", "PASS" if fails == 0 else "FAIL")
	# Free what the probe built (immediate, not queue_free: quit() follows) so
	# the run exits without ObjectDB/resource leak lines of its own making.
	ui_root.free()
	holder.free()
	loader.free()
	quit(0 if fails == 0 else 1)
