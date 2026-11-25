extends SceneTree
## W9-P2 B3 (L4-01): lockpick jam damage is the authored/intended outcome.
##
## Authored chain:
##   * CT_LockpickDamage.DamageByLockLevel = 5 / 10 / 20 / 40 (levels 1..4),
##     produced 1:1 into interactables.json `lockpick.jam_damage_by_lock_level`.
##   * GE_Lockpicking / DA_LockpickMinigameVariations: a strike outside every
##     breakable section jams the lock (`jam_damage_delay_s` 0.5 s) and applies
##     the row for the lock level. The only production applier is
##     hud.gd `_attempt_lockpick_strike()` -> player.take_damage().
##   * Door/container cancel callbacks (`_on_lockpick_finished(false, actor)`)
##     never call take_damage, and the no-HUD door fallback unlocks on a timer
##     without damage.
##
## Record check: player max_health 300, four LV3 jams = 80 -> 220/300 (73.3 %)
## is the record's ~75 % first health-bar reveal (bar reveals below 99.9 %).
##
## This test instantiates the real HUD script and a player stub in the "player"
## group (the HUD's `_get_player()`), so the production jam path runs headless.
## It is a decision test, not a balance change: no production code is edited.
##
## Run (never beside another Godot; thermal rule):
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game \
##       --script res://tests/test_jam_damage.gd"

const HUD_PATH := "res://src/ui/hud.gd"
const DOOR_SCRIPT := "res://src/interact/swinging_door.gd"
const CONTAINER_SCRIPT := "res://src/interact/loot_container.gd"
const LOCKABLE_SCRIPT := "res://src/interact/lockable_door.gd"

var fails: int = 0
var checks: int = 0


class DummyBody extends Node3D:
	var max_health: float = 300.0
	var health: float = 300.0
	var max_stamina: float = 100.0
	var stamina: float = 100.0
	var lockpicking_active: bool = false
	var damage_events: int = 0
	var damage_total: float = 0.0

	func _ready() -> void:
		add_to_group("player")

	func take_damage(amount: float) -> void:
		damage_events += 1
		damage_total += amount
		health = maxf(0.0, health - amount)

	func set_lockpicking_active(active: bool) -> void:
		lockpicking_active = active


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, ok: String, fail: String = "") -> bool:
	checks += 1
	if cond:
		print("PASS: [jam] ", ok)
		return true
	fails += 1
	printerr("FAIL: [jam] ", fail if fail != "" else ok)
	return false


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


## Sets `_lockpick_cursor_t` to a value outside every breakable section (plus
## the authored early-unlock grace) of the current track. Falls back to -1.0 if
## the whole track is covered, which the strike still reads as "no hit".
func _force_cursor_outside(hud: Node) -> float:
	var tracks: Array = hud.get("_lockpick_tracks") as Array
	var idx: int = int(hud.get("_lockpick_track_idx"))
	var db: Dictionary = hud.get("_lockpick_db") as Dictionary
	var grace: float = float(db.get("early_unlock_threshold_s", 0.1))
	var sections: Array = []
	var dur: float = 1.8
	if idx >= 0 and idx < tracks.size() and tracks[idx] is Dictionary:
		var tr: Dictionary = tracks[idx] as Dictionary
		dur = maxf(0.2, float(tr.get("duration_s", 1.8)))
		var sv: Variant = tr.get("defined_sections", [])
		if sv is Array:
			sections = sv as Array
	var t: float = 0.0
	while t < dur:
		var inside: bool = false
		for s_v: Variant in sections:
			if not (s_v is Dictionary):
				continue
			var sd: Dictionary = s_v as Dictionary
			var s0: float = float(sd.get("start_s", 0.0)) - grace
			var s1: float = float(sd.get("end_s", 0.2)) + grace
			if t >= s0 and t <= s1:
				inside = true
				break
		if not inside:
			hud.set("_lockpick_cursor_t", t)
			return t
		t += 0.01
	hud.set("_lockpick_cursor_t", -1.0)
	return -1.0


func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("JAM_DAMAGE FAIL: GameState autoload missing")
		quit(1)
		return
	gs.call("reset_run", 2, "guildhall")
	gs.set("state", "playing")

	var dummy: DummyBody = DummyBody.new()
	dummy.name = "JamDamageDummy"
	root.add_child(dummy)
	var hud: CanvasLayer = (load(HUD_PATH) as GDScript).new() as CanvasLayer
	hud.name = "JamDamageHud"
	root.add_child(hud)
	await _wait(4)
	if not _check(dummy.is_in_group("player"), "player stub is in the 'player' group", "stub group missing"):
		quit(1)
		return
	_check(hud.get("_hp_container") != null and hud.get("hp_fill") != null,
		"HUD built its health-bar container and fill", "HUD health bar missing")
	_check(hud.get("_lockpick_root") != null and hud.get("_lockpick_status_lbl") != null,
		"HUD built the lockpick minigame overlay", "lockpick overlay missing")

	# --- One authored LV3 jam ------------------------------------------------
	var cb_hits: Array = [0]
	hud.call("start_lockpick_minigame", 3, "Door Lock", func(_success: bool = true) -> void:
		cb_hits[0] = int(cb_hits[0]) + 1)
	_check(bool(hud.get("_lockpick_active")), "LV3 lockpick minigame starts",
		"minigame did not become active")
	_check(dummy.lockpicking_active, "engine contract: player.set_lockpicking_active(true) called",
		"player was not told the lockpick is active")
	var cursor: float = _force_cursor_outside(hud)
	var health_before: float = dummy.health
	hud.call("_attempt_lockpick_strike")
	print("JAM_DAMAGE first_jam cursor=%.3f health=%.1f jam_timer=%.3f status=%s" % [
		cursor, dummy.health, float(hud.get("_lockpick_jam_timer")),
		str((hud.get("_lockpick_status_lbl") as Label).text)])
	_check(is_equal_approx(dummy.health, 280.0),
		"LV3 jam removes the authored 20 (300 -> 280)", "health=%.3f want 280" % dummy.health)
	_check(is_equal_approx(float(hud.get("_lockpick_jam_timer")), 0.5),
		"authored jam_damage_delay_s = 0.5 s",
		"jam timer=%.3f want 0.5" % float(hud.get("_lockpick_jam_timer")))
	var status: String = (hud.get("_lockpick_status_lbl") as Label).text
	_check(status.find("LOCK JAMMED!") >= 0, "status shows LOCK JAMMED!", "status='%s'" % status)
	_check(int(cb_hits[0]) == 0, "a jam does not invoke the lockpick completion callback",
		"callback fired on a jam")

	# --- A second immediate strike must be swallowed by the jam window -------
	var health_after_first: float = dummy.health
	var events_after_first: int = dummy.damage_events
	hud.call("_attempt_lockpick_strike")
	_check(is_equal_approx(dummy.health, health_after_first)
			and dummy.damage_events == events_after_first,
		"a second strike inside the 0.5 s jam window deals no damage",
		"health=%.1f events=%d" % [dummy.health, dummy.damage_events])

	# --- Four LV3 jams -> 220/300 and the 73.3 % first reveal ----------------
	dummy.health = 300.0
	dummy.damage_events = 0
	dummy.damage_total = 0.0
	var jams: int = 0
	for _i: int in range(4):
		# The HUD ticks the window down in _process; clear it deterministically.
		hud.set("_lockpick_jam_timer", 0.0)
		_force_cursor_outside(hud)
		var before: float = dummy.health
		hud.call("_attempt_lockpick_strike")
		if dummy.health < before:
			jams += 1
	_check(jams == 4 and is_equal_approx(dummy.health, 220.0),
		"four LV3 jams = 80 damage (300 -> 220, 73.3 %%)",
		"jams=%d health=%.1f damage_events=%d" % [jams, dummy.health, dummy.damage_events])
	_check(dummy.damage_events == 4 and is_equal_approx(dummy.damage_total, 80.0),
		"exactly four take_damage(20) calls (total 80)",
		"events=%d total=%.1f" % [dummy.damage_events, dummy.damage_total])

	# --- Health-bar reveal contract ------------------------------------------
	dummy.health = 300.0
	hud.call("_update_health_and_stamina", dummy, false)
	var hp_container: Control = hud.get("_hp_container") as Control
	var hp_fill: TextureRect = hud.get("hp_fill") as TextureRect
	print("JAM_DAMAGE bar300 health=%.1f max=%.1f visible=%s" % [
		dummy.health, dummy.max_health, str(hp_container.visible) if hp_container != null else "null"])
	_check(hp_container != null and not hp_container.visible,
		"health bar hidden at 300/300 (full health)",
		"visible=%s health=%.1f/%.1f" % [
			str(hp_container.visible) if hp_container != null else "null", dummy.health, dummy.max_health])
	dummy.health = 299.0
	hud.call("_update_health_and_stamina", dummy, false)
	_check(hp_container != null and hp_container.visible,
		"health bar reveals at 299/300 (hp_frac < 0.999)")
	dummy.health = 220.0
	hud.call("_update_health_and_stamina", dummy, false)
	var consts: Dictionary = hud.get_script().get_script_constant_map()
	var max_w: float = float(consts.get("HP_BAR_MAX_W", 256.0))
	var want_w: float = max_w * (220.0 / 300.0)
	_check(hp_fill != null and absf(hp_fill.size.x - want_w) <= 0.01,
		"fill width after four LV3 jams = %.3f px (220/300 of %.0f)" % [want_w, max_w],
		"fill width=%.3f want %.3f" % [hp_fill.size.x if hp_fill != null else -1.0, want_w])
	print("JAM_DAMAGE health_bar hp=%.0f/%.0f frac=%.4f fill=%.3f/%.0f" % [
		dummy.health, dummy.max_health, dummy.health / dummy.max_health,
		hp_fill.size.x if hp_fill != null else -1.0, max_w])

	# --- Door/container cancel callbacks never damage ------------------------
	var host := Node3D.new()
	host.name = "JamCallbackHost"
	root.add_child(host)
	var door: Node = (load(DOOR_SCRIPT) as GDScript).new() as Node
	door.name = "JamCallbackDoor"
	door.call("configure", {
		"pos": [0.0, 0.0, 0.0],
		"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
		"leaves": [],
		"locked": true,
		"lock_level": 3,
	}, null)
	host.add_child(door)
	var container: Node = (load(CONTAINER_SCRIPT) as GDScript).new() as Node
	container.name = "JamCallbackContainer"
	container.call("configure", "BP_DisplayCaseA_MajorLoot_C", {
		"pos": Vector3(500.0, 0.0, 500.0),
		"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
	}, 0)
	host.add_child(container)
	await _wait(2)
	_check(bool(door.get("locked")) and bool(container.get("locked")) == false,
		"door configured locked at an authored level, container configured unlocked",
		"door locked=%s container locked=%s" % [str(door.get("locked")), str(container.get("locked"))])
	var cb_health: float = dummy.health
	door.call("_on_lockpick_finished", false, dummy)
	container.call("_on_lockpick_finished", false, dummy)
	_check(is_equal_approx(dummy.health, cb_health),
		"door/container cancel callbacks (success=false) deal no damage",
		"health %.1f -> %.1f" % [cb_health, dummy.health])
	_check(door.has_method("_on_lockpick_finished") and container.has_method("_on_lockpick_finished"),
		"door and container expose the real cancel callback under test")

	# --- No-HUD door fallback (headless): timed unlock, no damage ------------
	_check(get_nodes_in_group("mission").is_empty() and not hud.is_in_group("hud"),
		"no HUD is discoverable for the headless door fallback")
	door.set("locked", true)
	door.set("lock_level", 3)
	door.set("is_lockpicking", false)
	door.set("_lockpick_actor", null)
	# Inside the authored 2.0 m cancel radius, as a real lockpicker is.
	dummy.global_position = Vector3(0.8, 0.0, 0.0)
	var fb_health: float = dummy.health
	door.call("interact", dummy)
	_check(bool(door.get("is_lockpicking")), "headless door fallback starts its timed unlock",
		"door did not enter the fallback branch")
	await _wait(2) # let the fallback's SceneTreeTimer start
	await create_timer(2.0).timeout # wall-clock 2.0 s > the clamped 1.2 s fallback
	await _wait(2)
	print("JAM_DAMAGE fallback locked=%s health=%.1f" % [str(door.get("locked")), dummy.health])
	_check(not bool(door.get("locked")),
		"headless door fallback unlocks on its timer", "door still locked after 2 s")
	_check(is_equal_approx(dummy.health, fb_health),
		"headless door fallback deals no damage", "health %.1f -> %.1f" % [fb_health, dummy.health])

	# --- Authored table + labelled level 5/6 fallback ------------------------
	var door_scr: GDScript = load(LOCKABLE_SCRIPT) as GDScript
	var wants: Array[float] = [5.0, 10.0, 20.0, 40.0]
	for i: int in range(4):
		var lvl: int = i + 1
		var got: float = float(door_scr.call("jam_damage_for_level", lvl))
		_check(is_equal_approx(got, wants[i]),
			"jam_damage_for_level(%d) = %.0f (CT_LockpickDamage)" % [lvl, wants[i]],
			"level %d = %.1f want %.1f" % [lvl, got, wants[i]])
	_check(is_equal_approx(float(door_scr.call("jam_damage_for_level", 5)), 80.0)
			and is_equal_approx(float(door_scr.call("jam_damage_for_level", 6)), 160.0),
		"levels 5/6 return the labelled 80/160 doubling fallback (authored rows stop at 4)",
		"level 5/6 = %.1f/%.1f want 80/160" % [
			float(door_scr.call("jam_damage_for_level", 5)),
			float(door_scr.call("jam_damage_for_level", 6))])
	var table: Dictionary = door_scr.call("lockpick_table") as Dictionary
	var per_level_v: Variant = table.get("jam_damage_by_lock_level", {})
	var per_level: Dictionary = per_level_v as Dictionary if per_level_v is Dictionary else {}
	var authored_rows_ok: bool = per_level.has("1") and per_level.has("2") \
		and per_level.has("3") and per_level.has("4") \
		and not per_level.has("5") and not per_level.has("6")
	_check(authored_rows_ok,
		"interactables.json carries authored rows 1..4 only (5/6 are the fallback)",
		"jam_damage_by_lock_level keys=%s" % str(per_level.keys()))
	_check(str(table.get("curve_table", "")) == "CT_LockpickDamage",
		"table provenance is CT_LockpickDamage", "curve_table=%s" % str(table.get("curve_table", "")))

	var ok: bool = fails == 0
	print("JAM_DAMAGE ", "PASS" if ok else "FAIL", " checks=%d" % checks)
	quit(0 if ok else 1)
