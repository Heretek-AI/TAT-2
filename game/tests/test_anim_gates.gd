extends SceneTree
## Animation gate (RE-F-04/06/09/11/12/17). Run:
##   tools/godot --headless --path game --script res://tests/test_anim_gates.gd
##
## Four assertions that no other suite makes:
##  1. Clip-duration fidelity against the extracted source: every converted
##     clip's GLB duration must equal the authored SequenceLength, or -- while
##     the shipped manifest predates the producer retime -- the exact legacy
##     (N-1)/N model. Once `anims_manifest.json` declares duration_mode
##     "authored" (written by tools/usd_to_gltf.py) the legacy branch is
##     refused, so a producer fix without a `make anims` regeneration fails
##     here instead of shipping a cadence drift nobody measures.
##  2. Every role the runtime can select resolves to a clip present in the
##     manifest, and the single-candidate tables (FP_CLIPS/FP_TOOL_CLIPS) are
##     complete -- a missing name there is a silent no-op in gameplay.
##  3. The authored CombatHitbox windows really do bracket the contact instants
##     the runtime now waits for (RE-F-12), and polling frame 0 is silent.
##  4. The takedown pair is one authored pair (equal length), and a real guard
##     clip retargets onto the real guard skeleton and moves it (RE-F-17; the
##     only previous proof was a deleted temp check).

const GuardAnimLib = preload("res://src/core/animation_library.gd")
const AnimNotifyScript = preload("res://src/player/anim_notify.gd")

## 0.5 % of the authored length: wider than the tps quantisation residual
## (<= 1/tps, i.e. <= 0.1 % on the slowest clips) and far tighter than the
## (N-1)/N defect (0.2-33 %).
const DURATION_TOL: float = 0.005

const GUARD_BODY_GLB: String = "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/Dyn/SK_GuardEnforcer_Dyn__Body.glb"

var fails: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var meta: Dictionary = _json("res://data/generated/anims_meta.json")
	var man: Dictionary = _json("res://data/generated/anims_manifest.json")
	_check(not meta.is_empty() and not man.is_empty(), "gate inputs load (anims_meta + anims_manifest)",
		"gate inputs missing: meta=%d manifest=%d keys" % [meta.size(), man.size()])
	if meta.is_empty() or man.is_empty():
		print("ANIM_GATE_SUMMARY: fails=", fails)
		quit(1)
		return
	_suite_duration(meta, man)
	_suite_bound_roles(man)
	_suite_hit_windows()
	_suite_takedown_pair(meta)
	await _suite_guard_melee_timing()
	await _suite_guard_retarget()
	GuardAnimationLibrary.cleanup_static_caches()
	print("ANIM_GATE_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


func _const_map(path: String) -> Dictionary:
	var script: Script = load(path) as Script
	return script.get_script_constant_map() if script != null else {}


func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


## 1. Clip duration fidelity vs the extracted source (RE-F-04).
func _suite_duration(meta: Dictionary, man: Dictionary) -> void:
	var clips: Dictionary = meta.get("clips", {}) as Dictionary
	var entries: Array = man.get("entries", []) as Array
	var strict: bool = str(man.get("duration_mode", "")) == "authored"
	var checked: int = 0
	var exact: int = 0
	var legacy: int = 0
	var zero_pose: int = 0
	var bad: Array[String] = []
	for e: Variant in entries:
		if not (e is Dictionary):
			continue
		var entry: Dictionary = e as Dictionary
		var clip: String = str(entry.get("animation", ""))
		var m: Variant = clips.get(clip, null)
		if clip == "" or not (m is Dictionary):
			continue
		var authored: float = float((m as Dictionary).get("length", -1.0))
		if authored <= 0.0:
			continue
		checked += 1
		var dur: float = float(entry.get("duration", 0.0))
		var acts: Array = entry.get("actions", []) as Array
		var span: float = 0.0
		if not acts.is_empty() and acts[0] is Dictionary:
			var fr: Array = (acts[0] as Dictionary).get("frame_range", []) as Array
			if fr.size() == 2:
				span = float(fr[1]) - float(fr[0])
		if span <= 0.0:
			# Additive single-pose clip: one key, duration 0 by construction
			# (RE-F-05); not a duration defect and not retimed by the producer.
			if dur <= 1e-6:
				zero_pose += 1
			else:
				bad.append("%s zero-span but dur=%.4f" % [clip, dur])
			continue
		if absf(dur - authored) / authored <= DURATION_TOL:
			exact += 1
			continue
		var legacy_dur: float = span / (span + 1.0) * authored
		if not strict and absf(dur - legacy_dur) / authored <= DURATION_TOL:
			legacy += 1
			continue
		bad.append("%s dur=%.4f authored=%.4f span=%.0f (%.2f%% short)" % [
			clip, dur, authored, span, (1.0 - dur / authored) * 100.0])
	var mode: String = "authored (strict)" if strict else "legacy (N-1)/N tolerated until make anims)"
	_check(bad.is_empty(),
		"clip durations match the extracted source (%d clips: %d authored-exact, %d legacy, %d zero-pose, mode=%s)" % [
			checked, exact, legacy, zero_pose, mode],
		"clip duration mismatch in %d/%d clips (mode=%s): %s" % [
			bad.size(), checked, mode, "; ".join(bad.slice(0, 6))])
	if strict:
		_check(legacy == 0, "manifest declares duration_mode=authored and no clip still uses the (N-1)/N length",
			"%d clips still have the legacy (N-1)/N duration although the manifest declares duration_mode=authored: run make anims" % legacy)


## 2. Every selectable role resolves to a clip the manifest ships (RE-F-09).
func _suite_bound_roles(man: Dictionary) -> void:
	var shipped: Dictionary = {}
	for e: Variant in (man.get("entries", []) as Array):
		if e is Dictionary:
			shipped[str((e as Dictionary).get("animation", ""))] = true
	var consts: Dictionary = _const_map("res://src/core/animation_library.gd")
	var missing_roles: Array[String] = []
	var checked_roles: int = 0
	# Tables with a fallback list: at least one candidate must ship.
	for table_name: String in ["CLUB_CLIPS", "HA_CLIPS", "LANTERN_CLIPS"]:
		var table: Dictionary = consts.get(table_name, {}) as Dictionary
		for role: Variant in table:
			var cands: Variant = table[role]
			var ok: bool = false
			if cands is Array:
				for c: Variant in (cands as Array):
					if shipped.has(str(c)):
						ok = true
			elif cands is String:
				ok = shipped.has(str(cands))
			checked_roles += 1
			if not ok:
				missing_roles.append("%s.%s" % [table_name, role])
	# Single-candidate tables: the exact name must ship (no regex fallback).
	for table_name: String in ["FP_CLIPS", "FP_TOOL_CLIPS", "GEAR_CLIPS", "TP_CRANK_CLIPS", "TP_TAKEDOWN_CLIPS"]:
		var table: Dictionary = consts.get(table_name, {}) as Dictionary
		for role: Variant in table:
			var spec: Variant = table[role]
			var clip: String = ""
			if spec is String:
				clip = str(spec)
			elif spec is Dictionary:
				clip = str((spec as Dictionary).get("clip", ""))
			checked_roles += 1
			if clip == "" or not shipped.has(clip):
				missing_roles.append("%s.%s -> %s" % [table_name, role, clip])
	var thief_consts: Dictionary = _const_map("res://src/player/thief_character.gd")
	for const_name: String in ["TAKEDOWN_ATK_CLIP", "BLACKJACK_SWING_CLIP"]:
		var clip: String = str(thief_consts.get(const_name, ""))
		checked_roles += 1
		if not shipped.has(clip):
			missing_roles.append("%s -> %s" % [const_name, clip])
	# RE-F-13: the lantern run role resolves to a clip whose authored ground
	# speed is 5.39 m/s, not the shared 7.6 club constant, so the scripted
	# 2.5 m/s chase no longer clamps playback to the 0.35 floor.
	var speeds: Dictionary = _const_map("res://src/ai/guard_ai.gd").get("CLIP_GROUND_SPEED_BY_CLIP", {}) as Dictionary
	var lantern: Dictionary = consts.get("LANTERN_CLIPS", {}) as Dictionary
	var run_cands: Array = lantern.get("alert_run", []) as Array
	var run_clip: String = str(run_cands[0]) if not run_cands.is_empty() else ""
	var run_speed: float = float(speeds.get(run_clip, 0.0))
	var run_rate: float = 2.5 / run_speed if run_speed > 0.0 else 0.0
	_check(run_clip == "AN_GuardEnforcer_Lantern_Alert_Run__F" and absf(run_speed - 5.39) < 0.02 and run_rate > 0.35,
		"lantern guard run uses its authored %.2f m/s clip (2.5 m/s chase -> playback %.2f, above the 0.35 clamp)" % [run_speed, run_rate],
		"lantern run speed wrong: clip=%s speed=%.3f rate=%.3f" % [run_clip, run_speed, run_rate])
	_check(missing_roles.is_empty(),
		"every runtime clip role resolves to a shipped clip (%d roles, %d clips in the manifest)" % [checked_roles, shipped.size()],
		"roles with no shipped clip: " + ", ".join(missing_roles))


## 3. Authored hit windows bracket the runtime contact instants (RE-F-06/12).
func _suite_hit_windows() -> void:
	var club: String = "AN_GuardEnforcer_Club_Attack_Light_A_Montage"
	var club_seq: String = "AN_GuardEnforcer_Club_Attack_Light_A"
	var club_span: Vector2 = AnimNotifyScript.hit_span(club)
	var club_windows: Array = AnimNotifyScript.windows_for(club)
	var club_seq_windows: Array = AnimNotifyScript.windows_for(club_seq)
	var club_hit: float = AnimNotifyScript.hit_time(club)
	_check(club_windows.size() == 9 and club_seq_windows.size() == 9,
		"club montage resolves its 9 authored CombatHitbox states from the sequence sibling",
		"club hitboxes: montage=%d sequence=%d (expected 9/9)" % [club_windows.size(), club_seq_windows.size()])
	_check(club_span.x >= 0.919 and club_span.y <= 1.171 and club_hit > club_span.x and club_hit < club_span.y,
		"club swing contact %.3fs sits inside the authored %.3f-%.3fs window" % [club_hit, club_span.x, club_span.y],
		"club hit window wrong: span=%s hit=%.3f" % [str(club_span), club_hit])

	var clock = AnimNotifyScript.new()
	clock.arm(club)
	var at_zero: Vector2 = clock.poll(0.0)
	var at_half: Vector2 = clock.poll(0.5)
	var at_contact: Vector2 = clock.poll(club_hit)
	_check(at_zero == Vector2.ZERO and at_half == Vector2.ZERO and at_contact != Vector2.ZERO,
		"hitbox clock is silent at frame 0 and through 0.5s, fires at the authored contact",
		"hitbox clock: t=0 -> %s, t=0.5 -> %s, t=%.3f -> %s" % [str(at_zero), str(at_half), club_hit, str(at_contact)])

	var bj: String = str(_const_map("res://src/player/thief_character.gd").get("BLACKJACK_SWING_CLIP", ""))
	var bj_span: Vector2 = AnimNotifyScript.hit_span(bj)
	var bj_hit: float = AnimNotifyScript.hit_time(bj)
	_check(bj_span.x >= 0.279 and bj_span.y <= 0.501 and bj_hit > bj_span.x and bj_hit < bj_span.y,
		"blackjack contact %.3fs sits inside the authored %.3f-%.3fs window" % [bj_hit, bj_span.x, bj_span.y],
		"blackjack hit window wrong: span=%s hit=%.3f" % [str(bj_span), bj_hit])


## 4a. Takedown attacker and victim are the same authored synced pair (RE-F-11).
func _suite_takedown_pair(meta: Dictionary) -> void:
	var thief_consts: Dictionary = _const_map("res://src/player/thief_character.gd")
	var atk: String = str(thief_consts.get("TAKEDOWN_ATK_CLIP", ""))
	var vic: String = str(thief_consts.get("TAKEDOWN_VIC_CLIP", ""))
	var clips: Dictionary = meta.get("clips", {}) as Dictionary
	var atk_len: float = AnimNotifyScript.authored_length(atk)
	var vic_len: float = AnimNotifyScript.authored_length(vic)
	var table: Dictionary = (_const_map("res://src/core/animation_library.gd").get("CLUB_CLIPS", {}) as Dictionary)
	var guard_pref: String = ""
	var cands: Variant = table.get("takedown_vic", [])
	if cands is Array and not (cands as Array).is_empty():
		guard_pref = str((cands as Array)[0])
	_check(atk_len > 0.0 and vic_len > 0.0 and absf(atk_len - vic_len) <= 0.05,
		"takedown pair lengths agree: Atk %.3fs / Vic %.3fs (%s + %s)" % [atk_len, vic_len, atk, vic],
		"takedown pair does not match: Atk %.3f (%s) / Vic %.3f (%s)" % [atk_len, atk, vic_len, vic])
	_check(guard_pref == vic,
		"guard takedown role prefers the same pair's victim clip (%s)" % vic,
		"guard takedown role prefers '%s', expected the pair's victim '%s'" % [guard_pref, vic])
	_check(clips.has(atk) and clips.has(vic), "both takedown halves have authored metadata",
		"missing metadata for takedown halves: %s / %s" % [atk, vic])


## 3b. Behavioural: the guard's club swing damages inside the authored window
## and not on the frame it starts (RE-F-12). Drives the real guard_ai state
## machine on the real skeleton; the contact clock polls the real
## AnimationPlayer position, so seeking the clip is the same path as playback.
func _suite_guard_melee_timing() -> void:
	var guard_scr: Script = load("res://src/ai/guard_ai.gd") as Script
	var guard: CharacterBody3D = guard_scr.new() as CharacterBody3D
	guard.name = "AnimGateGuard"
	root.add_child(guard)
	await process_frame
	var stub_script := GDScript.new()
	stub_script.source_code = "extends CharacterBody3D\nvar hits: Array = []\nfunc take_damage(amount: float) -> void:\n\thits.append(amount)\n"
	stub_script.reload()
	var stub: CharacterBody3D = CharacterBody3D.new()
	stub.set_script(stub_script)
	stub.add_to_group("player")
	root.add_child(stub)
	await process_frame
	guard.global_position = Vector3.ZERO
	stub.global_position = Vector3(0.0, 0.0, -0.8)
	var player: AnimationPlayer = guard.get("anim_player") as AnimationPlayer
	if player == null or not player.has_animation("attack"):
		guard.queue_free()
		stub.queue_free()
		_check(false, "", "guard melee timing: real attack clip did not retarget (anim_player=%s)" % str(player))
		return
	guard.call("_play_guard_attack")
	var hits_at_start: int = (stub.get("hits") as Array).size()
	guard.call("_tick_attack_hit_window")
	var hits_at_frame0: int = (stub.get("hits") as Array).size()
	player.seek(0.5, true)
	guard.call("_tick_attack_hit_window")
	var hits_midwind: int = (stub.get("hits") as Array).size()
	var window: Vector2 = AnimNotifyScript.hit_span("AN_GuardEnforcer_Club_Attack_Light_A_Montage")
	player.seek(window.x + 0.01, true)
	guard.call("_tick_attack_hit_window")
	var hits_in_window: int = (stub.get("hits") as Array).size()
	guard.call("_tick_attack_hit_window")
	var hits_repeat: int = (stub.get("hits") as Array).size()
	var applied: Array = stub.get("hits") as Array
	guard.queue_free()
	stub.queue_free()
	await process_frame
	_check(hits_at_start == 0 and hits_at_frame0 == 0 and hits_midwind == 0 and hits_in_window == 1 and hits_repeat == 1,
		"guard club damage lands once inside the authored %.3f-%.3fs window, never on frame 0 or mid wind-up (amount=%.0f)" % [window.x, window.y, float(applied[0]) if applied.size() > 0 else 0.0],
		"guard melee timing wrong: start=%d frame0=%d midwind=%d in_window=%d repeat=%d (window=%s)" % [hits_at_start, hits_at_frame0, hits_midwind, hits_in_window, hits_repeat, str(window)])


## 4b. A real guard clip retargets onto the real guard skeleton and moves it.
func _suite_guard_retarget() -> void:
	if not ResourceLoader.exists(GUARD_BODY_GLB):
		_check(false, "", "guard retarget gate: body GLB missing " + GUARD_BODY_GLB)
		return
	var packed: PackedScene = ResourceLoader.load(GUARD_BODY_GLB) as PackedScene
	if packed == null:
		_check(false, "", "guard retarget gate: cannot instantiate " + GUARD_BODY_GLB)
		return
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	await process_frame
	var sk: Skeleton3D = null
	for n: Node in inst.find_children("*", "Skeleton3D", true, false):
		sk = n as Skeleton3D
		if sk != null and sk.get_bone_count() > 0:
			break
	if sk == null:
		inst.queue_free()
		_check(false, "", "guard retarget gate: no Skeleton3D in " + GUARD_BODY_GLB)
		return
	var lib = GuardAnimLib.new()
	var built: bool = lib.setup("club", sk)
	var player: AnimationPlayer = lib.build_player(sk, sk.get_parent(), inst) if built else null
	var applied: int = lib.applied_clip_count() if built else 0
	_check(player != null and applied >= 4,
		"guard clip library retargets %d/%d roles onto the %d-bone guard skeleton" % [applied, 11, sk.get_bone_count()],
		"guard retarget gate failed: setup=%s player=%s applied=%d" % [str(built), str(player), applied])
	if player == null:
		inst.queue_free()
		return
	var before: Array[Quaternion] = []
	for b: int in range(sk.get_bone_count()):
		before.append(sk.get_bone_pose_rotation(b))
	player.play("alert_idle")
	for _i: int in range(24):
		await process_frame
	var moved: int = 0
	for b: int in range(sk.get_bone_count()):
		if absf(before[b].dot(sk.get_bone_pose_rotation(b))) < 0.999:
			moved += 1
	_check(moved >= 5, "guard clip 'alert_idle' animates %d bones over 0.4s" % moved,
		"guard clip retarget produced no motion: %d bones changed over 0.4s" % moved)
	inst.queue_free()
	await process_frame
