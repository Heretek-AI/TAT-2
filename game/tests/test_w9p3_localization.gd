extends SceneTree
## W9-P3 localisation proof (C2 lane): the Loc pipeline actually translates, an
## unknown source passes through unchanged, the reverse map keeps its pre-W9
## size, and the authored rows the UI now routes resolve through Loc.
##
##   tools/godot --headless --path game --script res://tests/test_w9p3_localization.gd
##
## Prints `W9P3_LOC_SUMMARY: fails=<N> checks=<M>` and exits non-zero on failure.
## Wired as run_tests.gd suite 109 by the W9-P3 lead.

## Authored rows the W9-P3 wiring routes (built from the p3 audit TSV). Every one
## must resolve to non-empty text that is never a 32-hex GUID; at least 40 must be
## members of the reverse map (`sources.json` / en.csv), which is what proves they
## are piped through Loc rather than passed through by accident.
const ROUTED_SOURCES: Array[String] = [
	"Play", "Settings", "Credits", "Quit", "Continue", "Resume",
	"Return to Thief's Den", "Quit To Desktop", "Back", "Journal", "Black Market",
	"Your Total Assets", "Purchased", "LOCKED", "Language", "Gamepad", "Display",
	"Press Any Key", "Wardrobe", "Edit Loadout", "Head", "Body", "Calling Card",
	"Select a loadout slot to equip or swap out tools", "Contract", "Ill-Gotten Gains",
	"Cash in Hand", "Loot Earned: £{0}", "Loot Lost: £{0}", "Contract #{number}",
	"Difficulty: {difficulty}", "Mode: {mode}",
	"Mission Starting in <Num>{number}</>...", "Ready", "Unready", "Loading...",
	"Master Thief", "Novice", "Thief", "Prepare for Mission", "Constables' Guildhall",
	"Elway Manor", "Jammed!", "{Distance} m",
	"Time Limit: {matchDurationInMinutes} minutes", "Exit", "Read", "Open", "Close",
	"Ponder", "Read Ledger", "Loot", "Danger", "Clues", "Escape Point", "Main Target",
]
const MIN_RESOLVED_SOURCES: int = 40
const EXPECTED_SOURCE_COUNT: int = 2946
const SOURCE_COUNT_MIN: int = 2900
const SOURCE_COUNT_MAX: int = 3000
const DE_CSV_PATH: String = "res://data/generated/localization/de-DE.csv"
const DE_PLAY_KEY: String = "ST_Screens.Screen.MainMenu.Play"

var _fails: int = 0
var _checks: int = 0


func _initialize() -> void:
	await process_frame
	var loc: Node = get_root().get_node_or_null("Loc")
	if loc == null:
		printerr("FAIL: Loc autoload missing (project.godot [autoload] Loc)")
		print("W9P3_LOC_SUMMARY: fails=1 checks=0")
		quit(1)
		return
	_check_unknown_passthrough(loc)
	_check_source_count(loc)
	_check_routed_sources(loc)
	_check_german(loc)
	# Always leave the process on English: other suites assume the English bundle.
	loc.call("set_locale", "en")
	_check(loc.call("get_locale") == "en", "locale restored to en")
	print("W9P3_LOC_SUMMARY: fails=%d checks=%d" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("FAIL W9P3: %s%s" % [label, (" (%s)" % detail) if detail != "" else ""])


func _hex32(text: String) -> bool:
	if text.length() != 32:
		return false
	for i: int in range(text.length()):
		var c: String = text.substr(i, 1)
		if "0123456789abcdefABCDEF".find(c) < 0:
			return false
	return true


## An unknown source must come back verbatim: never empty, never a GUID.
func _check_unknown_passthrough(loc: Node) -> void:
	var unknown: String = "__no such source__"
	var out: String = str(loc.call("t", unknown))
	_check(out == unknown, "unknown source returns itself", "got '%s'" % out)
	_check(out != "", "unknown source is never empty")
	_check(not _hex32(out), "unknown source never becomes a GUID", out)
	_check(str(loc.call("t", "")) == "", "empty source stays empty")
	_check(not bool(loc.call("has_source", unknown)), "unknown source is not in the reverse map")
	_check(bool(loc.call("has_source", "Play")), "authored source 'Play' is in the reverse map")


## The reverse map must keep the pre-W9 size (3404 keys / 2946 sources).
func _check_source_count(loc: Node) -> void:
	var count: int = int(loc.call("source_count"))
	print("W9P3_LOC: source_count=%d (pre-W9 documented=%d)" % [count, EXPECTED_SOURCE_COUNT])
	_check(count >= SOURCE_COUNT_MIN and count <= SOURCE_COUNT_MAX,
		"reverse map size unchanged", "%d not in [%d, %d]" % [count, SOURCE_COUNT_MIN, SOURCE_COUNT_MAX])
	if count == EXPECTED_SOURCE_COUNT:
		print("W9P3_LOC: reverse map exactly %d sources (matches the pre-W9 count)" % EXPECTED_SOURCE_COUNT)


## Every routed authored row resolves, and enough of them are genuine members.
func _check_routed_sources(loc: Node) -> void:
	var members: int = 0
	var empty: Array[String] = []
	var guids: Array[String] = []
	for src: String in ROUTED_SOURCES:
		var out: String = str(loc.call("t", src))
		if bool(loc.call("has_source", src)):
			members += 1
		if out.strip_edges() == "":
			empty.append(src)
		elif _hex32(out):
			guids.append(src)
	_check(empty.is_empty(), "every routed source resolves non-empty", ", ".join(empty))
	_check(guids.is_empty(), "no routed source resolves to a GUID", ", ".join(guids))
	print("W9P3_LOC: routed sources checked=%d reverse_map_members=%d" % [ROUTED_SOURCES.size(), members])
	_check(members >= MIN_RESOLVED_SOURCES,
		"at least %d routed sources are reverse-map members" % MIN_RESOLVED_SOURCES, "members=%d" % members)


## de_DE: the authored Play row must change, and must match the bundled CSV.
func _check_german(loc: Node) -> void:
	var csv_value: String = _csv_value(DE_CSV_PATH, DE_PLAY_KEY)
	print("W9P3_LOC: de-DE.csv %s = '%s'" % [DE_PLAY_KEY, csv_value])
	_check(csv_value != "", "de-DE.csv carries the authored Play row")
	loc.call("set_locale", "de_DE")
	_check(str(loc.call("get_locale")) == "de_DE", "set_locale('de_DE') takes effect")
	var de_play: String = str(loc.call("t", "Play"))
	print("W9P3_LOC: Loc.t('Play') under de_DE = '%s'" % de_play)
	_check(de_play != "Play", "Loc.t('Play') is translated under de_DE", de_play)
	_check(de_play == csv_value, "Loc.t('Play') equals the authored de-DE row", "'%s' vs '%s'" % [de_play, csv_value])
	_check(de_play == "Spielen", "authored de-DE value is 'Spielen'", de_play)
	# A menu label the port uppercases still translates (reverse lookup normalises).
	var de_play_upper: String = str(loc.call("t", "PLAY"))
	print("W9P3_LOC: Loc.t('PLAY') under de_DE = '%s'" % de_play_upper)
	_check(de_play_upper != "PLAY", "Loc.t('PLAY') (the port's caps label) is translated", de_play_upper)
	# Unknown copy is not translated, and a second locale restores English.
	var unknown: String = str(loc.call("t", "__no such source__"))
	_check(unknown == "__no such source__", "unknown source passes through under de_DE", unknown)
	loc.call("set_locale", "en")
	_check(str(loc.call("t", "Play")) == "Play", "Loc.t('Play') is English again after set_locale('en')")


## Value column of one CSV row (`key,value`, comma-joined for multi-comma values).
func _csv_value(path: String, key: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	for line: String in text.split("\n"):
		var clean: String = line.strip_edges()
		if clean.begins_with(key + ","):
			return clean.substr(key.length() + 1).strip_edges()
	return ""
