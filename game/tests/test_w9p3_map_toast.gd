extends SceneTree
## W9-P3-C4 contract test: authored TAB-map boundaries + authored loot toast.
##
## No Vulkan, no capture. Two halves:
##   MAP   `MapBoundaries` parses the producer's `map_boundaries` array (the
##         `build/qa/w9/parse_tables-map-boundaries.patch` contract), resolves
##         the authored labels/anchors and picks the floor under the player. The
##         synthetic payload below is copied 1:1 from the extracted actors
##         (Guildhall_P TATWorldMapBoundary_0/1/2/3/5: positions, sizes, labels,
##         anchors), so the parse is tested against the authored numbers.
##   TOAST `UIToast` renders the authored `ST_Toasts.MajorLootTaken` template
##         with the live player/loot names, the authored panel/icon/animation
##         pattern, and reports the icon fallback.
##
## Run:  tools/godot --headless --path game --script res://tests/test_w9p3_map_toast.gd

const MapBoundariesScript: GDScript = preload("res://src/ui/map_boundaries.gd")
const UIToastScript: GDScript = preload("res://src/ui/ui_toast.gd")
const UIStringsScript: GDScript = preload("res://src/ui/ui_strings.gd")

var fails: int = 0
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _wait(n: int) -> void:
	for _i: int in range(n):
		await process_frame


func _check(ok: bool, what: String, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS: ", what)
	else:
		fails += 1
		printerr("FAIL: ", what, (" | " + detail) if detail != "" else "")


## The five Guildhall boundary actors exactly as extracted:
## TATWorldMapBoundary_0 (Primary, "Constables' Guildhall", anchors 315,621 ->
## 1712,1679, BoxComponent at UE (1454,701,6730) cm scale 117.5/117.5/1) and the
## four Secondary floor boxes.
func _guildhall_payload() -> Dictionary:
	return {
		"map_boundaries": [
			{
				"name": "TATWorldMapBoundary_0",
				"class": "TATWorldMapBoundary",
				"pos": [14.54, 67.3, 7.01],
				"size": [235.0, 2.0, 235.0],
				"label_source": "Constables' Guildhall",
				"label_key": "Guildhall.MapName",
				"label_table": "/Game/StringTables/ST_MapTool.ST_MapTool",
				"map_type": "",
				"primary": true,
				"anchor_top_left": [315.0, 621.0],
				"anchor_bottom_right": [1712.0, 1679.0],
				"texture_height_offset": 7500.0,
			},
			{
				"name": "TATWorldMapBoundary_1",
				"class": "TATWorldMapBoundary",
				"pos": [10.24, 27.5, -37.84],
				"size": [100.0, 14.0, 100.0],
				"label_source": "First Floor",
				"label_key": "F5968C2D4F25A4507F4C61ADC383C75C",
				"label_table": "",
				"map_type": "ETATWorldMapBoundaryType::Secondary",
				"primary": false,
				"anchor_top_left": [315.0, 621.0],
				"anchor_bottom_right": [1712.0, 1679.0],
				"texture_height_offset": 0.0,
			},
			{
				"name": "TATWorldMapBoundary_2",
				"class": "TATWorldMapBoundary",
				"pos": [10.24, 39.5, -37.84],
				"size": [100.0, 8.0, 100.0],
				"label_source": "Second Floor",
				"label_key": "2812591E40D5A945938155AB6508AC6B",
				"label_table": "",
				"map_type": "ETATWorldMapBoundaryType::Secondary",
				"primary": false,
				"anchor_top_left": [315.0, 621.0],
				"anchor_bottom_right": [1712.0, 1679.0],
				"texture_height_offset": 0.0,
			},
			{
				"name": "TATWorldMapBoundary_3",
				"class": "TATWorldMapBoundary",
				"pos": [10.24, 52.24, -37.84],
				"size": [100.0, 16.0, 100.0],
				"label_source": "Rooftop",
				"label_key": "9E203849428FBA1FBB9E968F681EE6C4",
				"label_table": "",
				"map_type": "ETATWorldMapBoundaryType::Secondary",
				"primary": false,
				"anchor_top_left": [315.0, 621.0],
				"anchor_bottom_right": [1712.0, 1679.0],
				"texture_height_offset": 0.0,
			},
			{
				"name": "TATWorldMapBoundary_5",
				"class": "TATWorldMapBoundary",
				"pos": [29.84, 6.25, -9.51],
				"size": [148.0, 24.0, 148.0],
				"label_source": "Basement",
				"label_key": "0432A8E54A7C63532835109BA740B657",
				"label_table": "",
				"map_type": "ETATWorldMapBoundaryType::Secondary",
				"primary": false,
				"anchor_top_left": [315.0, 621.0],
				"anchor_bottom_right": [1712.0, 1679.0],
				"texture_height_offset": -350.0,
			},
		]
	}


func _run() -> void:
	await _map_checks()
	await _toast_checks()
	await _hud_integration_checks()
	print("W9P3_MAP_TOAST_SUMMARY: fails=%d checks=%d" % [fails, checks])
	quit(1 if fails > 0 else 0)


func _map_checks() -> void:
	var rows: Array[Dictionary] = MapBoundariesScript.parse(_guildhall_payload())
	_check(rows.size() == 5, "W9P3-C4.1 five Guildhall boundaries parse (%d)" % rows.size())
	_check(str(MapBoundariesScript.level_path("guildhall")).ends_with("Guildhall/Guildhall_P.tatlevel.json"),
		"W9P3-C4.2 guildhall maps to the persistent Guildhall_P payload")
	_check(str(MapBoundariesScript.level_path("thieves_den")).ends_with("ThievesDenTest/ThievesDenTest_P.tatlevel.json"),
		"W9P3-C4.3 thieves_den maps to ThievesDenTest_P")
	# The produced level JSON has no map_boundaries today: the HUD must report
	# its fallback rather than pretending the authored set exists.
	_check(str(MapBoundariesScript.source_for_map("guildhall")) == "fallback",
		"W9P3-C4.4 the generated level has no boundaries yet -> fallback is reported")
	var prim: Dictionary = MapBoundariesScript.primary_for(rows)
	_check(str(prim.get("name", "")) == "TATWorldMapBoundary_0", "W9P3-C4.5 primary is boundary_0",
		str(prim.get("name", "")))
	_check(MapBoundariesScript.label_for(prim) == "Constables' Guildhall",
		"W9P3-C4.6 primary label resolves through ST_MapTool.Guildhall.MapName (%s)" % MapBoundariesScript.label_for(prim))
	_check(MapBoundariesScript.label_for(rows[1]) == "First Floor",
		"W9P3-C4.7 GUID-only label resolves through the locres (%s)" % MapBoundariesScript.label_for(rows[1]))
	_check(MapBoundariesScript.label_for(rows[4]) == "Basement",
		"W9P3-C4.8 second GUID label (%s)" % MapBoundariesScript.label_for(rows[4]))
	# Anchors: 315,621 -> 1712,1679 in a 2048^2 map texture.
	var r: Rect2 = MapBoundariesScript.anchor_rect(prim)
	_check(absf(r.position.x - 315.0 / 2048.0) < 0.001 and absf(r.position.y - 621.0 / 2048.0) < 0.001,
		"W9P3-C4.9 anchor top-left is 315,621 of 2048 (%.4f,%.4f)" % [r.position.x, r.position.y])
	_check(absf(r.size.x - 1397.0 / 2048.0) < 0.001 and absf(r.size.y - 1058.0 / 2048.0) < 0.001,
		"W9P3-C4.10 anchor rect is 1397x1058 of 2048 (%.4f,%.4f)" % [r.size.x, r.size.y])
	# Floor picking: a player standing on the First Floor box (y 27.5 + 4.48/2).
	var p1: Vector3 = Vector3(10.24, 29.6, -37.84)
	_check(str(MapBoundariesScript.boundary_at(rows, p1).get("name", "")) == "TATWorldMapBoundary_1",
		"W9P3-C4.11 the player on the First Floor box selects it")
	var p_roof: Vector3 = Vector3(10.24, 54.5, -37.84)
	_check(str(MapBoundariesScript.boundary_at(rows, p_roof).get("name", "")) == "TATWorldMapBoundary_3",
		"W9P3-C4.12 the player on the rooftop selects Rooftop")
	var outside: Vector3 = Vector3(500.0, 0.0, 500.0)
	_check(str(MapBoundariesScript.boundary_at(rows, outside).get("name", "")) == "TATWorldMapBoundary_0",
		"W9P3-C4.13 outside every floor box falls back to the primary capture volume")
	_check(MapBoundariesScript.parse({}).is_empty(), "W9P3-C4.14 an absent array parses to empty")
	# 13 authored actors total across the four maps (extracted count).
	var counts: Dictionary = {}
	for map_id: String in ["guildhall", "old_manor", "ftue", "thieves_den"]:
		counts[map_id] = MapBoundariesScript.for_map(map_id).size()
	_check(counts["guildhall"] == 0 and counts["old_manor"] == 0 and counts["ftue"] == 0 and counts["thieves_den"] == 0,
		"W9P3-C4.15 all four generated payloads carry 0 boundaries today (producer patch owed)",
		str(counts))


func _toast_checks() -> void:
	var authored: String = UIStringsScript.raw("ST_Toasts", "MajorLootTaken", "")
	_check(authored == "{PlayerName} took the {MajorLootName}!",
		"W9P3-C4.16 ST_Toasts.MajorLootTaken is the authored template (%s)" % authored)
	var want: String = str(UIToastScript.major_loot_text("The Spider", "Cat Statue"))
	_check(want == "The Spider took the Cat Statue!",
		"W9P3-C4.17 the toast text is the authored line with the live names (%s)" % want)
	UIStringsScript.reset_loc_stats()
	var stashed: String = str(UIToastScript.stashed_text("Cat Statue"))
	_check(stashed == "You stashed the Cat Statue!", "W9P3-C4.18 authored stash line (%s)" % stashed)
	var stats: Dictionary = UIStringsScript.loc_stats()
	_check(int(stats.get("resolved", 0)) >= 1,
		"W9P3-C4.19 the toast source resolves through Loc (resolved=%d)" % int(stats.get("resolved", 0)))
	var holder: CanvasLayer = CanvasLayer.new()
	root.add_child(holder)
	var ctl: Control = UIToastScript.new() as Control
	holder.add_child(ctl)
	await _wait(2)
	var res: Dictionary = ctl.call("show_major_loot", "Cat Statue", "")
	await _wait(2)
	_check(bool(res.get("shown", false)), "W9P3-C4.20 show_major_loot builds a toast", str(res))
	var texts: Array = ctl.call("toast_texts") as Array
	var found: bool = false
	for t_v: Variant in texts:
		var t: String = str(t_v)
		if t.find("Cat Statue") >= 0 and t.find("took the") >= 0:
			found = true
	_check(found, "W9P3-C4.21 the live toast carries the authored line (%s)" % str(texts))
	var tstats: Dictionary = ctl.call("stats") as Dictionary
	_check(int(tstats.get("shown", 0)) == 1, "W9P3-C4.22 one toast shown")
	_check(int(tstats.get("icon_fallback", 0)) >= 1,
		"W9P3-C4.23 the missing row PaperSprite is counted as an icon substitution (%d)" % int(tstats.get("icon_fallback", 0)))
	holder.queue_free()
	# The authored smoke material is a UE MD_UI material (CornerRadius/Power),
	# not a texture: the port panel must not claim it imports one.
	_check(not ResourceLoader.exists("res://assets/ue/Raw/Art/UI/Materials/T_UI_Smoke.png"),
		"W9P3-C4.24 no M_UI_Smoke texture exists (the port panel is a labelled reconstruction)")
	_check(ResourceLoader.exists("res://assets/ue/Raw/Art/UI/Icons/T_Glyph_MajorLoot.png"),
		"W9P3-C4.25 the authored major-loot glyph exists on disk")


## HUD wiring: the overlay reports the fallback until the producer emits rows,
## and a major pickup raises the authored toast through the real GameState bus.
func _hud_integration_checks() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	_check(gs != null, "W9P3-C4.26 GameState autoload is present")
	var hud: CanvasLayer = (load("res://src/ui/hud.gd") as GDScript).new() as CanvasLayer
	root.add_child(hud)
	await _wait(4)
	_check(hud.has_method("map_boundary_source"), "W9P3-C4.27 HUD exposes map_boundary_source()")
	_check(str(hud.call("map_boundary_source")) == "fallback",
		"W9P3-C4.28 the HUD reports the labelled fallback window today (%s)" % str(hud.call("map_boundary_source")))
	_check((hud.call("map_boundary_rows") as Array).is_empty(),
		"W9P3-C4.29 no authored boundary rows are claimed (producer regeneration owed)")
	_check(hud.has_method("pause_panel_for_test") and hud.call("pause_panel_for_test") != null,
		"W9P3-C4.30 the pause panel is wired for focus")
	if gs != null:
		var carried_arr: Array = gs.get("carried_loot") as Array
		var saved: Array = carried_arr.duplicate()
		carried_arr.clear()
		var before: int = int((hud.find_children("Toast_*", "PanelContainer", true, false)).size())
		# Major loot -> authored toast. Append into the typed array (Object.set
		# from an untyped Array silently yields an empty Array[Dictionary]).
		carried_arr.append({"name": "CatStatue", "display_name": "Cat Statue",
			"value": 225, "tier": "major", "slot_cost": 1})
		gs.call("notify_carried_loot_changed")
		await _wait(3)
		var after: int = int((hud.find_children("Toast_*", "PanelContainer", true, false)).size())
		_check(after > before, "W9P3-C4.31 a major pickup raises a HUD toast (%d -> %d)" % [before, after])
		var toast_text: String = ""
		for l: Node in hud.find_children("*", "Label", true, false):
			var t: String = (l as Label).text
			if t.find("Cat Statue") >= 0 and t.find("took the") >= 0:
				toast_text = t
		_check(toast_text != "", "W9P3-C4.32 the HUD toast prints the authored line (%s)" % toast_text)
		# Minor loot -> no authored toast row, so no new toast.
		var before_minor: int = int((hud.find_children("Toast_*", "PanelContainer", true, false)).size())
		carried_arr.append({"name": "Bowl", "display_name": "Silver Bowl",
			"value": 45, "tier": "minor", "slot_cost": 1})
		gs.call("notify_carried_loot_changed")
		await _wait(2)
		var after_minor: int = int((hud.find_children("Toast_*", "PanelContainer", true, false)).size())
		_check(after_minor == before_minor, "W9P3-C4.33 minor loot raises no major-loot toast")
		# Stash/reset: the used count drops. The next major pickup must still
		# toast (the baseline has to follow the decrease -- audit-c4 5c).
		carried_arr.clear()
		gs.call("notify_carried_loot_changed")
		await _wait(2)
		var before_after_stash: int = int((hud.find_children("Toast_*", "PanelContainer", true, false)).size())
		carried_arr.append({"name": "CatStatue2", "display_name": "Cat Statue",
			"value": 225, "tier": "major", "slot_cost": 1})
		gs.call("notify_carried_loot_changed")
		await _wait(3)
		var after_after_stash: int = int((hud.find_children("Toast_*", "PanelContainer", true, false)).size())
		_check(after_after_stash > before_after_stash,
			"W9P3-C4.33a a major pickup after a stash decrease still toasts (%d -> %d)" % [before_after_stash, after_after_stash])
		carried_arr.clear()
		for e: Variant in saved:
			carried_arr.append(e)
		gs.call("notify_carried_loot_changed")
	# The port-invented world Label3D must not come back with thief vision:
	# loot_item.set_xray_highlight does `label.visible = on or is_quest_item`.
	var item: Node3D = (load("res://src/interact/loot_item.gd") as GDScript).new() as Node3D
	if item != null:
		item.set("item_name", "CatStatue")
		item.set("display_name", "Cat Statue")
		item.set("loot_tier", "major")
		item.set("value", 225)
		root.add_child(item)
		await _wait(4)
		var lbl: Label3D = item.get("label") as Label3D
		_check(lbl != null and not lbl.visible, "W9P3-C4.34 the HUD hides the invented world loot label at spawn")
		item.call("set_xray_highlight", true, "")
		await _wait(1)
		_check(lbl != null and lbl.visible, "W9P3-C4.35 thief vision re-shows the label (the bug the HUD must undo)")
		hud.call("set_thief_vision", true)
		await _wait(3)
		_check(lbl != null and not lbl.visible, "W9P3-C4.36 the HUD re-hides the invented label after the vision toggle")
		item.queue_free()
		await _wait(2)
	hud.queue_free()
	await _wait(2)
