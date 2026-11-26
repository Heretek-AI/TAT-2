extends Area3D
## Openable placed loot container (chest / display case / secret stash).
##
## One node is spawned per UE container marker by mission_controller. The
## container MESH is level geometry (spawned by the level loader) and is never
## duplicated here: this node is an Area3D trigger only, with no mesh children
## and no per-frame work.
##
## Opening is one-shot and instant (no Interact duration is authored on the
## container Blueprints). Major/minor containers spawn exactly one loot item
## from their mapped bucket, picked deterministically from the marker
## position; the secret stash (kind "stash", no spawn bucket) is a one-use
## deposit-all — its own loot arrives as separately placed actors.

signal lockpick_updated(active: bool, progress: float, lock_level: int)
## W10-A3-GC: destructible container state. `container_broken` is the gameplay
## event (one per container, idempotent); `broken_changed` mirrors the visual
## layer swap for HUD/audio consumers. Both fire before the one-shot loot spawn
## so a listener can react to the smash independently of the loot payout.
signal container_broken(container: Node, actor: Node)
signal broken_changed(is_broken: bool)

const LootScript := preload("res://src/interact/loot_item.gd")
const LootInventoryScript := preload("res://src/interact/loot_inventory.gd")
const LootStashScript := preload("res://src/interact/loot_stash.gd")
const LockableDoorScript := preload("res://src/interact/lockable_door.gd")
const _VfxManager := preload("res://src/core/vfx_manager.gd")
const UIStringsScript := preload("res://src/ui/ui_strings.gd")

const CONTAINERS_PATH := "res://data/generated/gameplay/containers.json"
const LOOT_ACTORS_PATH := "res://data/generated/gameplay/loot_actors.json"
## W10-A3-GC: the hold-to-smash secondary action requires the player to face
## the container (ordinary interact has no facing cone by design). 0.5 is a
## ~60 deg half-angle, enough to forgive camera/body mismatch at 1.75 m.
const BREAK_HOLD_FACING_DOT: float = 0.5

## Raw UE centimetres -> Godot metres (UE X-fwd/Y-right/Z-up becomes
## Godot X-right/Y-up/Z-back: the same Y/Z swap the level extractor applies).
const CM_TO_M := 0.01

static var _containers: Dictionary = {}
static var _loot_tables: Dictionary = {}


static func containers() -> Dictionary:
	if _containers.is_empty():
		if FileAccess.file_exists(CONTAINERS_PATH):
			var f: FileAccess = FileAccess.open(CONTAINERS_PATH, FileAccess.READ)
			if f != null:
				var data: Variant = JSON.parse_string(f.get_as_text())
				if data is Dictionary:
					_containers = (data as Dictionary).get("classes", {})
	return _containers


static func loot_tables() -> Dictionary:
	if _loot_tables.is_empty():
		if FileAccess.file_exists(LOOT_ACTORS_PATH):
			var f: FileAccess = FileAccess.open(LOOT_ACTORS_PATH, FileAccess.READ)
			if f != null:
				var data: Variant = JSON.parse_string(f.get_as_text())
				if data is Dictionary:
					_loot_tables = {
						"buckets": (data as Dictionary).get("buckets", {}),
						"actors": (data as Dictionary).get("actors", {}),
					}
	return _loot_tables


## Deterministic weighted pick from a bucket class list (duplicates carry the
## designer weight): pure function of marker position + order, no RNG.
## P2 bucket-hash duplication: this static is the single source of truth;
## mission_controller._loot_bucket_index delegates here and pins parity with
## an assert, so the two waves cannot drift.
static func bucket_index(pos: Vector3, order: int, size: int) -> int:
	if size <= 0:
		return 0
	var h: float = absf(pos.x * 12.9898 + pos.y * 78.233 + pos.z * 37.719 + float(order) * 0.731)
	return posmod(int(h), size)


## Raw UE slot offset (cm, X-fwd/Y-right/Z-up) -> Godot metres (Y/Z swapped,
## like the level extractor).
static func ue_offset_to_godot(offset_cm: Vector3) -> Vector3:
	return Vector3(offset_cm.x * CM_TO_M, offset_cm.z * CM_TO_M, offset_cm.y * CM_TO_M)


## Slot FRotator (degrees, UE frame: Pitch about Y, Yaw about Z, Roll about X)
## combined with the marker orientation -> Godot euler degrees for the loot
## visual. The UE rotation is conjugated by the extractor's Y/Z swap (P) into
## Godot space, then composed with the marker basis.
static func slot_world_rotation(marker: Basis, pitch: float, yaw: float, roll: float) -> Vector3:
	var b_ue: Basis = Basis(Vector3(0, 0, 1), deg_to_rad(yaw)) * Basis(Vector3(0, 1, 0), deg_to_rad(pitch)) * Basis(Vector3(1, 0, 0), deg_to_rad(roll))
	var swap := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
	var b_godot: Basis = swap * b_ue * swap
	var e: Vector3 = (marker * b_godot).get_euler()
	return Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))


## Marker transform for the Area: position + orientation only. Marker scale is
## recorded on the entry but never applied to the trigger (it would distort
## the interaction sphere).
static func marker_transform(entry: Dictionary) -> Transform3D:
	var pos: Vector3 = entry.get("pos", Vector3.ZERO)
	var b: Array = entry.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	var basis := Basis.IDENTITY
	if b.size() >= 9:
		basis = Basis(
			Vector3(float(b[0]), float(b[3]), float(b[6])),
			Vector3(float(b[1]), float(b[4]), float(b[7])),
			Vector3(float(b[2]), float(b[5]), float(b[8]))
		).orthonormalized()
	return Transform3D(basis, pos)


var container_class: String = ""
var loot_tier: String = ""
## Authored actor name (level loader marker name). The destructible leaf/broken
## layers are keyed by it; empty means this container has no GC overlay.
var owner_name: String = ""
## W10-A3-GC: true after `break_container()`. The intact leaf is hidden and the
## authored broken overlay is shown; loot behaviour is unchanged (a smashed
## container opens once, exactly like an unlocked interact).
var broken: bool = false
var _gc_leaf: Node3D = null
var _gc_broken: Node3D = null
## Authored secret stash (containers.json kind "stash"): the trigger is a
## one-use deposit-all, never a loot spawner.
var is_stash: bool = false
var stash_uses: int = 0
var marker_pos: Vector3 = Vector3.ZERO
var marker_basis: Basis = Basis.IDENTITY
var slot_offset_cm: Vector3 = Vector3.ZERO
var slot_rotation_deg: Vector3 = Vector3.ZERO
var spawn_index: int = 0
var opened: bool = false
@export var locked: bool = false
@export var lock_level: int = 0
var lockpick_progress: float = 0.0
var is_lockpicking: bool = false
var _lockpick_actor: Node = null
## One warning per authored container class missing from containers.json.
static var _missing_class_warned: Dictionary = {}
## W9-P2 B2: authored locks this port ignores (no key inventory), counted per
## class so the exclusion is observable without per-instance spam.
## W10-A defect 8 label correction: this bucket is `CanBeLockpicked == false`
## ("unpickable"), not "key only" — 26 of the 33 placed explicit-false actors
## carry no KeyTag (build/qa/w10/re-1-locks.md §3.3).
static var _unpickable_excluded: Dictionary = {}


## W9-P2 B2: record an authored unpickable lock we deliberately do not honour.
## Counts every instance but prints once per class; `unpickable_exclusions()`
## exposes the tally to tests/probes.
func _note_unpickable_exclusion(p_class: String) -> void:
	var seen: int = int(_unpickable_excluded.get(p_class, 0))
	_unpickable_excluded[p_class] = seen + 1
	if seen == 0:
		print("[loot_container] authored unpickable lock not applied (port has no key inventory): ", p_class)


static func unpickable_exclusions() -> Dictionary:
	return _unpickable_excluded.duplicate()


## Deprecated alias of `unpickable_exclusions()` (W10-A defect 8 label rename).
## Kept so callers written before the rename — e.g. tests/test_w9p2_locks.gd,
## which must not be edited — keep reading the same per-class tally.
static func key_only_exclusions() -> Dictionary:
	return unpickable_exclusions()


func _warn_missing_container_class(p_class: String) -> void:
	if _missing_class_warned.has(p_class):
		return
	_missing_class_warned[p_class] = true
	push_warning("[loot_container] authored container class '", p_class, "' has no containers.json row; opening via the authored *_MajorLoot/*_MinorLoot tier bucket (producer gap: tools/parse_containers.py CLASSES)")


func set_locked(p_locked: bool, p_lock_level: int = 1) -> void:
	locked = p_locked
	lock_level = clampi(p_lock_level, 1, 6) if p_locked else 0
	lockpick_progress = 0.0
	is_lockpicking = false


func get_minigame_variation() -> Dictionary:
	if lock_level <= 0:
		return {}
	return LockableDoorScript.minigame_variation_for_level(lock_level, spawn_index)


func get_minigame_track() -> Dictionary:
	if lock_level <= 0:
		return {}
	return LockableDoorScript.minigame_track_for_level(lock_level, spawn_index)


func get_track_duration() -> float:
	return float(get_minigame_track().get("duration_s", 0.0))


## Must be called before add_child (like world_pickup.setup). Resolves the
## loot tier and first slot entry from containers.json; unknown classes and
## unreadable JSON fail closed to kind "none" (openable, no loot, nothing
## invented); the stash class name still resolves to the deposit trigger.
func configure(p_class: String, entry: Dictionary, p_index: int) -> void:
	container_class = p_class
	spawn_index = p_index
	owner_name = str(entry.get("owner", ""))
	marker_pos = entry.get("pos", Vector3.ZERO)
	var tr := marker_transform(entry)
	marker_basis = tr.basis
	transform = tr
	var rec: Variant = containers().get(p_class, null)
	if rec is Dictionary:
		var kind := str((rec as Dictionary).get("kind", "none"))
		if kind == "stash":
			is_stash = true
			stash_uses = maxi(int((rec as Dictionary).get("stash_uses", 1)), 0)
		elif kind == "major" or kind == "minor":
			loot_tier = kind
			var slots: Array = (rec as Dictionary).get("slot_entries", [])
			if not slots.is_empty() and slots[0] is Dictionary:
				var off: Array = (slots[0] as Dictionary).get("offset_cm", [0, 0, 0])
				var rot: Array = (slots[0] as Dictionary).get("rotation_deg", [0, 0, 0])
				if off.size() >= 3:
					slot_offset_cm = Vector3(float(off[0]), float(off[1]), float(off[2]))
				if rot.size() >= 3:
					slot_rotation_deg = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
	# Name-based fallback when containers.json is unreadable OR missing an
	# authored container class: the authored Blueprint name carries the bucket
	# tier (`*_MajorLoot_C` / `*_MinorLoot_C`) and the per-tier authored spawn
	# bucket supplies the actors, so the marker still opens with authored loot.
	# The dropped classes this restores (8 BP_SmallSafe_MajorLoot_C + 8
	# BP_Manor_Bookcase_Cabinet_MinorLoot_C in loaded Guildhall sublevels) need
	# the producer (T01) to emit their containers.json rows and the level loader
	# (T07/T09) to stop filtering them; this fallback makes the consumer half
	# right the moment either lands. Slot offsets are unknown for such a class,
	# so the loot spawns at the marker (labelled fallback, never invented).
	if loot_tier == "" and p_class.find("MajorLoot") >= 0:
		loot_tier = "major"
		_warn_missing_container_class(p_class)
	elif loot_tier == "" and p_class.find("MinorLoot") >= 0:
		loot_tier = "minor"
		_warn_missing_container_class(p_class)
	# The secret stash class keeps working (deposit trigger) when containers.json
	# is unreadable, with the one-use port default.
	if p_class.find("LootStashInteractable") >= 0:
		is_stash = true
		if stash_uses <= 0:
			stash_uses = LootStashScript.default_uses()
	# W9-P2 B2 authored locks only; no level is invented from the spawn index.
	# PORT DECISION (labelled, not authored data): the dump has **no**
	# per-instance lock level (`LockLevel`/`lock_level` appear 0 times in
	# 12,541 JSONs). The only numeric per-instance value is
	# `_lockConfig.MaxLockLevel`, a cap, so the record's level = that cap,
	# clamped to this consumer's 1..6 range; a record that is `locked` with no
	# authored cap locks at 1 (the minimum, never a formula). Absence of
	# `locked` means unlocked: class-default `_locked` values (BP_SmallSafe_C /
	# BP_LargeFancySafe_C) are CDO defaults, not placed authoring.
	#
	# Unpickable authored locks (`_lockConfig.CanBeLockpicked == false`) are
	# excluded: the port has no key inventory, so honouring them would soft-lock
	# the container. They stay open and are counted/labelled once per class (no
	# per-instance spam). W10-A defect 8: the flag means "cannot be picked", not
	# "needs a key" (re-1-locks.md §3.3). Unsupported container classes never
	# reach this function at all (level_loader.LOOT_CONTAINER_CLASSES filters
	# BP_SmallSafe_MajorLoot_C / BP_ChestTrunk_C / BP_BookcaseB_C before spawn).
	if entry.get("locked") == true:
		var can_pick: Variant = entry.get("can_lockpick", null)
		if can_pick is bool and not bool(can_pick):
			_note_unpickable_exclusion(p_class)
		else:
			var cap_lvl: int = int(entry.get("max_lock_level", 1))
			set_locked(true, clampi(cap_lvl, 1, 6))


## W10-A3-GC: bind the level-owned intact leaf and hidden broken overlay for
## this container's actor. Safe to call with nulls (a map that authors no GC).
func bind_gc_visuals(leaf: Node3D, broken_layer: Node3D) -> void:
	_gc_leaf = leaf
	_gc_broken = broken_layer
	_apply_gc_visuals()


func is_broken() -> bool:
	return broken


## True when the level bound an authored broken overlay. The gameplay smash
## trigger requires this, so a stash/storefront container that authors no GC is
## never turned into a broken trigger with no visual.
func has_broken_overlay() -> bool:
	return _gc_broken != null and is_instance_valid(_gc_broken)


## Swap the intact lid/door for the authored broken overlay and open the
## container once. This is the destruction event; it bypasses the lock exactly
## like the authored breakable component does, but never duplicates loot (the
## one-shot `opened` guard stays the only loot gate). Returns false when the
## container was already broken.
func break_container(actor: Node = null) -> bool:
	if broken:
		return false
	broken = true
	set_meta("broken", true)
	add_to_group("broken_containers")
	_clear_actor_lockpicking()
	_apply_gc_visuals()
	broken_changed.emit(true)
	container_broken.emit(self, actor)
	if is_inside_tree():
		NoiseBus.emit_noise(global_position, 6.0, _noise_source(), "break")
	if not opened:
		_open_container()
	return true


func _apply_gc_visuals() -> void:
	if _gc_leaf != null and is_instance_valid(_gc_leaf):
		_gc_leaf.visible = not broken
	if _gc_broken != null and is_instance_valid(_gc_broken):
		_gc_broken.visible = broken


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("loot_containers")
	set_meta("opened", false)
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = true
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.0
	col.shape = sph
	add_child(col)
	# No meshes: container visuals are level geometry. The per-frame distance
	# gate is off until a lockpick session starts (R10 authored cancel radius).
	set_process(false)


## R10 authored lockpick cancel radius (GA_Lockpick distance_before_cancel
## 200 cm): walking away ends the pick instead of letting it run from the
## corridor. Returns true when this call cancelled the session.
func check_lockpick_distance() -> bool:
	if not is_lockpicking:
		return false
	if _lockpick_actor == null or not is_instance_valid(_lockpick_actor) or not (_lockpick_actor is Node3D):
		return false
	var d: float = global_position.distance_to((_lockpick_actor as Node3D).global_position)
	if d <= LockableDoorScript.lockpick_cancel_distance_m():
		return false
	_cancel_lockpick()
	return true


func _process(_delta: float) -> void:
	check_lockpick_distance()


## End the minigame as a failure through the HUD (which owns the dialog and the
## completion callback), so the cancel path is exactly one failure, never two.
func _cancel_lockpick() -> void:
	var actor: Node = _lockpick_actor
	var hud_node: Node = _find_hud()
	if hud_node != null:
		if hud_node.has_method("cancel_lockpick"):
			hud_node.call("cancel_lockpick")
			return
		if hud_node.has_method("_finish_lockpick") and hud_node.has_method("is_lockpicking") \
				and bool(hud_node.call("is_lockpicking")):
			hud_node.call("_finish_lockpick", false)
			return
	_on_lockpick_finished(false, actor)


func get_interact_prompt() -> String:
	if is_stash:
		return LootStashScript.prompt_for(stash_uses, LootInventoryScript.has_depositable())
	if opened:
		return UIStringsScript.loc("[Opened]") ## PORT COPY (no authored row)
	if locked:
		if is_lockpicking:
			return UIStringsScript.loc("[Picking Lock...]") ## PORT COPY (no authored row)
		# Authored "Pick Lock" row + the port's lock-level suffix; the glyph is live.
		return InputGlyphs.prompt("interact", UIStringsScript.st_upper("ST_Lockpicking", "Lockpicking.Pompt.Start", "Pick Lock")) + " (Lv %d)" % maxi(lock_level, 1)
	return InputGlyphs.prompt("interact", UIStringsScript.st_upper("ST_Interactables", "PromptOpen", "Open"))


## W10-A3-GC: the deliberate smash is the existing stacked secondary hold (F),
## the same contract doors use for [HOLD] LOCK. It is offered only on an
## unbroken container that owns an authored broken overlay. The verb is the
## authored ST_Interactables.PromptDestroyDeployable row; the keycap prefix is
## port copy.
func get_interact_secondary_prompt() -> String:
	if broken or opened or is_stash:
		return ""
	if not has_broken_overlay():
		return ""
	return "[F] [HOLD] " + UIStringsScript.st_upper("ST_Interactables", "PromptDestroyDeployable", "Destroy")


## W10-A3-GC secondary action: hold F to smash the container open. Ordinary
## interact (tap E) still opens/lockpicks and never calls break_container, so a
## locked container is not bypassed by a tap. The player must face the container
## for the smash, unlike side-accessible ordinary interaction.
func interact_hold(actor: Node) -> void:
	if broken or opened or is_stash:
		return
	if not has_broken_overlay():
		return
	if actor is Node3D:
		var a: Node3D = actor as Node3D
		var to: Vector3 = global_position - a.global_position
		to.y = 0.0
		var fwd: Vector3 = -a.global_transform.basis.z
		fwd.y = 0.0
		if to.length() > 0.05 and fwd.length() > 0.05 \
				and fwd.normalized().dot(to.normalized()) < BREAK_HOLD_FACING_DOT:
			return
	break_container(actor)


## Interaction LOS point (W2): the marker origin sits on the floor, so the
## generic origin + 0.5 m lands inside the chest/wardrobe mesh. +1.4 m clears
## every authored container lid and stays inside the 1.75 m player reach.
func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.4


func _exit_tree() -> void:
	_clear_actor_lockpicking()


func _clear_actor_lockpicking() -> void:
	is_lockpicking = false
	set_process(false)
	if _lockpick_actor != null and is_instance_valid(_lockpick_actor) and _lockpick_actor.has_method("set_lockpicking_active"):
		_lockpick_actor.call("set_lockpicking_active", false)
	_lockpick_actor = null


func _find_hud() -> Node:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	var mission: Node = tree.get_first_node_in_group("mission")
	if mission != null:
		var h_v: Variant = mission.get("hud")
		if h_v is Node and is_instance_valid(h_v as Node):
			return h_v as Node
	var h_group: Node = tree.get_first_node_in_group("hud")
	if h_group != null and is_instance_valid(h_group):
		return h_group
	return null


func _container_label() -> String:
	# The HUD appends "— LV n" itself (hud.start_lockpick_minigame); embedding
	# the level here produced "DOOR LOCK (LV 3) — LV 3" (C4-05).
	if container_class.find("DisplayCase") >= 0:
		return UIStringsScript.loc("Display Safe") ## PORT COPY (no authored row)
	if container_class.find("Chest") >= 0:
		return UIStringsScript.loc("Locked Chest") ## PORT COPY (no authored row)
	return UIStringsScript.loc("Safe Lock") ## PORT COPY (no authored row)


## P1 container noise sourced self: same HUD-arcs gap as the doors (guards
## heard lockpicking, the player saw no feedback). Emit with the stored player
## driver when one is mid-interaction (UE lockpick noise path).
func _noise_source() -> Node:
	if _lockpick_actor != null and is_instance_valid(_lockpick_actor):
		return _lockpick_actor
	return self


func _on_lockpick_finished(success: bool, actor: Node) -> void:
	is_lockpicking = false
	set_process(false)
	if actor != null and is_instance_valid(actor) and actor.has_method("set_lockpicking_active"):
		actor.call("set_lockpicking_active", false)
	if _lockpick_actor == actor:
		_lockpick_actor = null
	if not is_inside_tree():
		return
	if success:
		locked = false
		lockpick_progress = 1.0
		lockpick_updated.emit(false, 1.0, maxi(lock_level, 1))
		_open_container()
	else:
		_VfxManager.spawn_lockpick_sparks(get_parent(), global_position + Vector3(0.0, 0.5, 0.0))
		NoiseBus.emit_noise(global_position, 5.0, _noise_source(), "lockpick")
		lockpick_updated.emit(false, lockpick_progress, maxi(lock_level, 1))


## One-shot open (after unlocking if locked). Major/minor containers spawn
## exactly one loot item at the marker position plus the slot offset; a stash
## marker deposits the carried haul (one use) and spawns nothing.
func interact(actor: Node) -> void:
	# Stash triggers are deposit-all points, not containers: they stay usable
	# while a use remains and never spawn loot.
	if is_stash:
		_deposit_stash(actor)
		return
	if opened:
		return
	if locked:
		if is_lockpicking:
			return
		var lvl: int = clampi(maxi(lock_level, 1), 1, 6)
		lock_level = lvl
		if actor != null and actor.has_method("set_lockpicking_active"):
			_lockpick_actor = actor
			actor.call("set_lockpicking_active", true)
		var hud_node: Node = _find_hud()
		if actor != null and hud_node != null and hud_node.has_method("start_lockpick_minigame"):
			is_lockpicking = true
			set_process(true)
			lockpick_updated.emit(true, lockpick_progress, lvl)
			NoiseBus.emit_noise(global_position, 4.0, _noise_source(), "lockpick")
			hud_node.call("start_lockpick_minigame", lvl, _container_label(), func(success: bool = true) -> void:
				_on_lockpick_finished(success, actor)
			)
			return
		if actor != null and is_inside_tree():
			# Headless fallback: timed unlock so Status.Lockpicking (5.0/s) ticks.
			is_lockpicking = true
			set_process(true)
			lockpick_updated.emit(true, lockpick_progress, lvl)
			_VfxManager.spawn_lockpick_sparks(get_parent(), global_position + Vector3(0.0, 0.5, 0.0))
			NoiseBus.emit_noise(global_position, 4.0, _noise_source(), "lockpick")
			var dur: float = clampf(get_track_duration(), 0.35, 1.2)
			get_tree().create_timer(dur).timeout.connect(func() -> void:
				if is_instance_valid(self) and is_lockpicking:
					_on_lockpick_finished(true, actor)
			)
			return
		locked = false
		lockpick_progress = 1.0
		_clear_actor_lockpicking()
	_open_container()


func _deposit_stash(actor: Node) -> void:
	var was_open: bool = opened
	opened = true
	set_meta("opened", true)
	var result: Dictionary = LootStashScript.deposit_all(self, stash_uses)
	if bool(result.get("ok", false)):
		stash_uses = int(result.get("uses_left", stash_uses))
		return
	# An empty/spent stash still opens (T2-19-B contract) and shows the authored
	# line instead of silently doing nothing. No use is consumed.
	if not was_open:
		var hud_node: Node = _find_hud()
		if hud_node != null and hud_node.has_method("show_toast"):
			hud_node.call("show_toast", str(result.get("prompt", "")))


func _open_container() -> void:
	if opened:
		return
	opened = true
	set_meta("opened", true)
	if loot_tier != "major" and loot_tier != "minor":
		return
	var tables := loot_tables()
	var buckets: Dictionary = tables.get("buckets", {})
	var bucket: Array = (buckets.get(loot_tier, {}) as Dictionary).get("classes", [])
	var actors: Dictionary = tables.get("actors", {})
	var l := LootScript.new()
	l.loot_tier = loot_tier
	l.is_quest_item = false
	var resolved := false
	if not bucket.is_empty():
		var cls := str(bucket[bucket_index(marker_pos, spawn_index, bucket.size())])
		var a: Variant = actors.get(cls, null)
		if a is Dictionary:
			l.item_name = str((a as Dictionary).get("name", UIStringsScript.loc("Noble Relic"))) ## PORT COPY (no authored row)
			l.display_name = l.item_name
			l.value = int((a as Dictionary).get("value", 75))
			l.mesh_path = str((a as Dictionary).get("mesh_res", ""))
			l.carry_mesh_path = str((a as Dictionary).get("carry_mesh_res", ""))
			l.is_large_carry = bool((a as Dictionary).get("is_large_carry", false))
			resolved = true
	if not resolved:
		# Labelled fallback (same policy as the mission loot wave): the
		# tier-entry pool with the legacy note mesh, counts unchanged.
		var entry: Dictionary = LootScript.tier_entry(loot_tier, spawn_index)
		l.item_name = str(entry.get("name", UIStringsScript.loc("Noble Relic #%d") % (spawn_index + 1))) ## PORT COPY (no authored row)
		l.display_name = l.item_name
		l.value = int(entry.get("value", 75))
	l.mesh_rotation_deg = slot_world_rotation(marker_basis, slot_rotation_deg.x, slot_rotation_deg.y, slot_rotation_deg.z)
	var host: Node = get_parent()
	if host == null:
		return
	host.add_child(l)
	l.global_position = marker_pos + marker_basis * ue_offset_to_godot(slot_offset_cm)
