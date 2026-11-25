extends SceneTree
## W9-P3-C1 gate: post-match/XP, progression and tutorial screens exist from
## the authored tables, and the result panel speaks the authored status
## vocabulary (no invented GHOST/SHADOW/BRAWLER / CONSTABULARY).
##
## Run:  tools/godot --headless --path game --script res://tests/test_w9p3_screens.gd

const UIStringsScript: GDScript = preload("res://src/ui/ui_strings.gd")
const FocusNavScript: GDScript = preload("res://src/ui/focus_nav.gd")
const TutorialTextScript: GDScript = preload("res://src/ui/tutorial_text.gd")

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


func _labels_text(root_node: Node) -> String:
	var out: PackedStringArray = []
	for l: Node in root_node.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	for r: Node in root_node.find_children("*", "RichTextLabel", true, false):
		out.append((r as RichTextLabel).text)
	# Button text is a property, not a child Label: collect it here so the
	# assertions see authored button rows (Continue / Back / Play Tutorial).
	for b: Node in root_node.find_children("*", "Button", true, false):
		out.append((b as Button).text)
	return "\n".join(out)


func _has_text(text: String, want: String) -> bool:
	return want != "" and text.to_lower().find(want.to_lower()) >= 0


func _label_named(root_node: Node, name_want: String) -> Label:
	for l: Node in root_node.find_children(name_want, "Label", true, false):
		return l as Label
	return null


func _run() -> void:
	await _post_match_checks()
	await _progression_checks()
	await _tutorial_checks()
	print("W9P3_SCREENS_SUMMARY: fails=%d checks=%d" % [fails, checks])
	quit(1 if fails > 0 else 0)


func _post_match_checks() -> void:
	var script: GDScript = load("res://src/ui/post_match_ui.gd") as GDScript
	_check(script != null, "W9P3-C1.1 post_match_ui.gd loads")
	if script == null:
		return
	var scr: CanvasLayer = script.new() as CanvasLayer
	root.add_child(scr)
	await _wait(4)
	_check(scr.has_method("open_result"), "W9P3-C1.2 PostMatchUI exposes open_result()")
	scr.call("open_result", true, 1200, {"contract_order": 2}, 120)
	await _wait(4)
	var text: String = _labels_text(scr)
	var escaped: String = UIStringsScript.raw("ST_PostMatch", "PostMatch.Status.Escaped", "Escaped").to_upper()
	_check(text.find(escaped) >= 0, "W9P3-C1.3 the status uses the authored Escaped row (%s)" % escaped)
	_check(text.find("GHOST") < 0 and text.find("SHADOW") < 0 and text.find("BRAWLER") < 0 \
		and text.find("CONSTABULARY") < 0,
		"W9P3-C1.4 no invented GHOST/SHADOW/BRAWLER/CONSTABULARY rating remains")
	var xp_header: String = UIStringsScript.raw("ST_PostMatch", "XP.Breakdown", "XP Breakdown")
	_check(_has_text(text, xp_header), "W9P3-C1.5 the authored XP.Breakdown header exists (%s)" % xp_header)
	for key: String in ["XP.Breakdown.Contract.Successful", "XP.Breakdown.Mission.Successful",
			"XP.Breakdown.Extraction.Successful", "XP.Breakdown.Time", "XP.Breakdown.Difficulty"]:
		var row: String = UIStringsScript.raw("ST_PostMatch", key, "")
		_check(row != "" and _has_text(text, row), "W9P3-C1.6 authored breakdown row %s (%s)" % [key, row])
	_check(text.find("+120") >= 0, "W9P3-C1.7 the measured XP gain is shown (+120)")
	var ss: Node = root.get_node_or_null("/root/SaveSystem")
	var lvl: Dictionary = (ss.call("get_level_progress") as Dictionary) if ss != null else {"level": 1}
	var level_line: String = str(UIStringsScript.t("Level {CurrentLevel}")).replace("{CurrentLevel}", str(int(lvl.get("level", 1))))
	_check(text.find(level_line) >= 0, "W9P3-C1.8 the authored level line (%s)" % level_line)
	var cont: String = UIStringsScript.raw("ST_Screens", "Screen.Continue", "Continue").to_upper()
	_check(_has_text(text, cont), "W9P3-C1.9 the continue button is the authored Screen.Continue (%s)" % cont)
	_check(not (scr.call("debug_controls") as Array).is_empty(), "W9P3-C1.10 PostMatchUI is focus-navigable")
	_check(bool(FocusNavScript.ring_is_complete(scr)), "W9P3-C1.11 PostMatchUI focus ring is complete")
	# Captured state: authored Caught, no invented prose.
	scr.call("open_result", false, 0, {}, 0)
	await _wait(2)
	var text2: String = _labels_text(scr)
	var caught: String = UIStringsScript.raw("ST_PostMatch", "PostMatch.Status.Caught", "Caught").to_upper()
	_check(text2.find(caught) >= 0, "W9P3-C1.12 the captured state uses the authored Caught row (%s)" % caught)
	# ESC / pad-B close path (the same close() the _unhandled_input ui_cancel
	# branch calls): no screen may stay open behind a cancelled input.
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	scr.call("_unhandled_input", cancel)
	await _wait(2)
	_check(not bool(scr.call("is_open")), "W9P3-C1.12a ui_cancel closes the post-match screen")
	scr.queue_free()
	await _wait(2)


func _progression_checks() -> void:
	var script: GDScript = load("res://src/ui/progression_ui.gd") as GDScript
	_check(script != null, "W9P3-C1.13 progression_ui.gd loads")
	if script == null:
		return
	var scr: CanvasLayer = script.new() as CanvasLayer
	root.add_child(scr)
	await _wait(4)
	scr.call("open_progression")
	await _wait(4)
	var text: String = _labels_text(scr)
	var ss2: Node = root.get_node_or_null("/root/SaveSystem")
	var lvl: Dictionary = (ss2.call("get_level_progress") as Dictionary) if ss2 != null else {"level": 1}
	var level_line: String = str(UIStringsScript.t("Level {CurrentLevel}")).replace("{CurrentLevel}", str(int(lvl.get("level", 1))))
	_check(text.find(level_line) >= 0, "W9P3-C1.14 progression shows the authored level line (%s)" % level_line)
	_check(_has_text(text, UIStringsScript.raw("ST_Screens", "Screen.Label.Stats", "Stats")) \
		or _has_text(text, UIStringsScript.raw("ST_Screens", "Screen.PostMatch.Unlocks", "Black Market Unlocks")),
		"W9P3-C1.15 progression shows an authored section header")
	_check(_has_text(text, UIStringsScript.raw("ST_Screens", "Screen.Back", "Back")),
		"W9P3-C1.16 progression has the authored Back button")
	_check(not (scr.call("debug_controls") as Array).is_empty(), "W9P3-C1.17 progression is focus-navigable")
	_check(bool(FocusNavScript.ring_is_complete(scr)), "W9P3-C1.18 progression focus ring is complete")
	var cancel2: InputEventAction = InputEventAction.new()
	cancel2.action = "ui_cancel"
	cancel2.pressed = true
	scr.call("_unhandled_input", cancel2)
	await _wait(2)
	_check(not bool(scr.call("is_open")), "W9P3-C1.18a ui_cancel closes progression")
	scr.queue_free()
	await _wait(2)


func _tutorial_checks() -> void:
	var script: GDScript = load("res://src/ui/tutorial_ui.gd") as GDScript
	_check(script != null, "W9P3-C1.19 tutorial_ui.gd loads")
	if script == null:
		return
	var scr: CanvasLayer = script.new() as CanvasLayer
	root.add_child(scr)
	await _wait(4)
	scr.call("open_tutorial")
	await _wait(4)
	_check(scr.has_method("open_category"), "W9P3-C1.20 TutorialUI exposes open_category()")
	var text: String = _labels_text(scr)
	_check(text.find("Collect the key") >= 0, "W9P3-C1.21 authored objective copy renders (Tut_Objective_Collect_Key)")
	# Controls page: the authored <img id="EquipMap"/> resolves to the bound key.
	scr.call("open_category", "controls")
	await _wait(4)
	var ctl_text: String = _labels_text(scr)
	_check(ctl_text.find("[TAB]") >= 0, "W9P3-C1.22 the authored FTUE icon renders the live map glyph ([TAB])")
	# Infographics page: authored <Danger> becomes the authored colour.
	scr.call("open_category", "infographics")
	await _wait(4)
	var info_text: String = _labels_text(scr)
	_check(info_text.find("[color=#bd1f1f]") >= 0,
		"W9P3-C1.23 authored <Danger> renders the DT_RichTextStyleSheet_FTUE colour (#BD1F1F)")
	_check(TutorialTextScript.style_fallbacks() == 0,
		"W9P3-C1.24 rich-text styles come from the generated table, not the fallback (%d)" % int(TutorialTextScript.style_fallbacks()))
	_check(int(scr.call("video_count")) == 15,
		"W9P3-C1.25a the generated videos.json index is read (15 FTUE movies, playback still blocked)")
	_check(TutorialTextScript.input_id_count() == 14,
		"W9P3-C1.25 all 14 DT_RichTextInputs ids load (%d)" % int(TutorialTextScript.input_id_count()))
	# Every category opens.
	var keys: Array[String] = ["objectives", "controls", "infographics", "story", "den"]
	for k: String in keys:
		scr.call("open_category", k)
		await _wait(1)
		var n: int = (scr.find_children("TutorialCard_*", "PanelContainer", true, false)).size()
		_check(n >= 1, "W9P3-C1.26 category '%s' has authored entries (%d)" % [k, n])
	var play: String = UIStringsScript.raw("ST_Screens", "Screen.MainMenu.PlayTutorial", "Play Tutorial").to_upper()
	_check(_has_text(_labels_text(scr), play), "W9P3-C1.27 the Play Tutorial entry uses the authored row (%s)" % play)
	_check(not (scr.call("debug_controls") as Array).is_empty(), "W9P3-C1.28 tutorial is focus-navigable")
	_check(bool(FocusNavScript.ring_is_complete(scr)), "W9P3-C1.29 tutorial focus ring is complete")
	var cancel3: InputEventAction = InputEventAction.new()
	cancel3.action = "ui_cancel"
	cancel3.pressed = true
	scr.call("_unhandled_input", cancel3)
	await _wait(2)
	_check(not bool(scr.call("is_open")), "W9P3-C1.29a ui_cancel closes the tutorial")
	# No invented prose: every rendered body must exist in an authored table.
	var authored_hit: int = 0
	var authored_miss: int = 0
	for r: Node in scr.find_children("Body", "RichTextLabel", true, false):
		var body: String = (r as RichTextLabel).text
		var plain: String = TutorialTextScript.strip_tags(body)
		if plain.strip_edges() == "":
			continue
		var found: bool = false
		for table: String in ["ST_Tutorial", "ST_Tutorial_Infographics", "ST_Tutorial_ThievesDen"]:
			for v: Variant in UIStringsScript.table(table).values():
				if str(v).find(plain.substr(0, 24)) >= 0:
					found = true
					break
			if found:
				break
		if found:
			authored_hit += 1
		else:
			authored_miss += 1
	_check(authored_miss == 0,
		"W9P3-C1.30 every rendered tutorial body traces to an authored row (%d hit / %d miss)" % [authored_hit, authored_miss])
	scr.queue_free()
	await _wait(2)
