extends Node
## Runtime localization bridge for the shipped translation tables.
##
## The extracted CSV tables key every message by a UE GUID string whose value
## is the English source text (`game/data/generated/localization/en.csv`). The
## compiled `.translation` resources next to it carry the authored translations
## under those same GUID keys. UI code already speaks English source strings, so
## this autoload builds the reverse map source -> GUID once, registers all
## shipped translations with TranslationServer, and exposes `t()`:
##
##     label.text = Loc.t("Play")
##
## Unknown source strings pass through unchanged. A translation miss (including
## the raw GUID TranslationServer returns when a key is absent) also falls back
## to the source string, never a GUID.
##
## Duplicate English values are common in the shipped table (menu labels appear
## in several sub-tables). The first key in file order wins, deterministically,
## so the reverse map does not depend on Dictionary hash order.

const LOCALE_DIR: String = "res://data/generated/localization"
const EN_CSV_PATH: String = LOCALE_DIR + "/en.csv"
const FALLBACK_LOCALE: String = "en"

## The 8 locales shipped in game/data/generated/localization. `code` is the
## stable save/settings value; `locale` is the exact Translation resource
## locale; `label` is the language selector text (a language's own name, not
## game copy).
const LANGUAGES: Array[Dictionary] = [
	{"code": "en", "locale": "en", "label": "English"},
	{"code": "de_DE", "locale": "de_DE", "label": "Deutsch"},
	{"code": "es_ES", "locale": "es_ES", "label": "Español"},
	{"code": "fr_FR", "locale": "fr_FR", "label": "Français"},
	{"code": "ja_JP", "locale": "ja_JP", "label": "日本語"},
	{"code": "pt_BR", "locale": "pt_BR", "label": "Português (BR)"},
	{"code": "zh_Hans", "locale": "zh_Hans", "label": "简体中文"},
	{"code": "zh_Hant", "locale": "zh_Hant", "label": "繁體中文"},
]

var _source_to_key: Dictionary = {}
var _en_key_count: int = 0
var _translation_count: int = 0
var _current_code: String = "en"

## W9-P3 coverage instrumentation. Every `t()` call records whether the source
## resolved through the authored reverse map; `t_stats()` is what the string
## audit and `tests/test_w9p3_localization.gd` report. Counters only — no
## lookup behaviour changes, and the reverse map stays the pre-W9 3,404-key /
## 2,946-source dictionary.
var _t_calls: int = 0
var _t_resolved: int = 0
var _t_passthrough: int = 0
var _t_missing: Dictionary = {}
const MAX_MISSING_DIAGNOSTICS: int = 256


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Translations first: exported builds can load the .translation resources
	# even when the imported CSV is not addressable, so the English object is
	# the reliable source for the reverse map.
	_load_translations()
	_load_reverse_map()
	var saved_code: String = FALLBACK_LOCALE
	var ss: Node = get_node_or_null("/root/SaveSystem")
	if ss != null and ss.has_method("get_settings"):
		var settings: Dictionary = ss.call("get_settings") as Dictionary
		saved_code = str(settings.get("locale", FALLBACK_LOCALE))
	set_locale(saved_code)
	print("TAT-2 Loc: ", _translation_count, " translations, reverse map ", _source_to_key.size(), "/", _en_key_count, " en.csv keys, locale=", _current_code)


func languages() -> Array[Dictionary]:
	return LANGUAGES.duplicate(true)


func source_count() -> int:
	return _source_to_key.size()


func has_source(source: String) -> bool:
	return _source_to_key.has(source)


## Current shipped-locale code (one of LANGUAGES[].code).
func get_locale() -> String:
	return _current_code


## Resolve a saved/selected code to a shipped locale. Accepts the short base
## form too ("de" -> de_DE) so older saves and tests stay valid. Unknown input
## falls back to en.
func resolve_code(code: String) -> String:
	var clean: String = code.strip_edges().replace("-", "_").to_lower()
	if clean == "":
		return FALLBACK_LOCALE
	for entry: Dictionary in LANGUAGES:
		if str(entry.get("code", "")).to_lower() == clean:
			return str(entry.get("code", FALLBACK_LOCALE))
	var base: String = clean.split("_")[0]
	for entry: Dictionary in LANGUAGES:
		if str(entry.get("code", "")).to_lower().split("_")[0] == base:
			return str(entry.get("code", FALLBACK_LOCALE))
	return FALLBACK_LOCALE


func set_locale(code: String) -> void:
	var resolved: String = resolve_code(code)
	var translation_locale: String = FALLBACK_LOCALE
	for entry: Dictionary in LANGUAGES:
		if str(entry.get("code", "")) == resolved:
			translation_locale = str(entry.get("locale", FALLBACK_LOCALE))
			break
	_current_code = resolved
	TranslationServer.set_locale(translation_locale)


## Translate an English source string through the shipped GUID catalog. Missing
## sources and missing translations return the source unchanged, never a GUID.
func t(source: String) -> String:
	if source == "":
		return ""
	_t_calls += 1
	var key: String = str(_source_to_key.get(source, ""))
	# UI code keeps menu labels in caps ("PLAY"); the authored source is
	# "Play". Normalise only for the reverse-map lookup, never for the result.
	if key == "":
		# Only all-caps UI labels are normalised ("PLAY" -> "Play"); mixed-case
		# unknown copy stays unknown rather than matching unrelated text.
		if source == source.to_upper() and source != source.to_lower():
			var cased: String = source.capitalize()
			if cased != source:
				key = str(_source_to_key.get(cased, ""))
	if key == "":
		_t_passthrough += 1
		_note_missing(source)
		return source
	_t_resolved += 1
	var out: String = str(TranslationServer.translate(key))
	if out == "" or out == key:
		return source
	return out


func _note_missing(source: String) -> void:
	if _t_missing.size() >= MAX_MISSING_DIAGNOSTICS:
		return
	_t_missing[source] = int(_t_missing.get(source, 0)) + 1


## Runtime coverage counters for the W9-P3 string audit:
## {calls, resolved, passthrough, ratio, unique_missing, missing: [...]}.
## `ratio` is resolved / (resolved + passthrough) — 1.0 when every consulted
## source resolved. It is a *measurement*, not a gate: invented copy is expected
## to pass through, and the static audit counts those separately.
func t_stats() -> Dictionary:
	var denom: int = _t_resolved + _t_passthrough
	var missing: Array[String] = []
	for k: Variant in _t_missing.keys():
		missing.append(str(k))
	missing.sort()
	return {
		"calls": _t_calls,
		"resolved": _t_resolved,
		"passthrough": _t_passthrough,
		"ratio": (float(_t_resolved) / float(denom)) if denom > 0 else 0.0,
		"unique_missing": _t_missing.size(),
		"missing": missing,
	}


## Test/QA hook: reset the counters between screens so a per-screen ratio can be
## measured without restarting the process.
func reset_t_stats() -> void:
	_t_calls = 0
	_t_resolved = 0
	_t_passthrough = 0
	_t_missing.clear()


func _load_reverse_map() -> void:
	_source_to_key.clear()
	_en_key_count = 0
	# Preferred source: the generator's JSON map. CSV imports are remapped in
	# exported builds, so the raw en.csv is not reliably addressable there.
	if _load_reverse_map_from_json():
		return
	if not FileAccess.file_exists(EN_CSV_PATH):
		# Exported builds remap imported CSVs to their .translation resource;
		# the raw source may be present in the PCK but not addressable as a
		# FileAccess path. Build the same reverse map from the English resource.
		if _load_reverse_map_from_translation():
			return
		push_warning("[loc] missing English source table: ", EN_CSV_PATH, " and no en.en.translation fallback (all strings pass through)")
		return
	var f: FileAccess = FileAccess.open(EN_CSV_PATH, FileAccess.READ)
	if f == null:
		if _load_reverse_map_from_translation():
			return
		push_warning("[loc] cannot open English source table: ", EN_CSV_PATH)
		return
	var header: PackedStringArray = f.get_csv_line()
	if header.size() < 2:
		if _load_reverse_map_from_translation():
			return
		push_warning("[loc] English source table has no key/value columns: ", EN_CSV_PATH)
		return
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() < 2:
			continue
		var key: String = str(row[0]).strip_edges()
		var src: String = str(row[1])
		if key == "" or src.strip_edges() == "":
			continue
		_en_key_count += 1
		# First key wins: duplicate English values are resolved by file order,
		# not by Dictionary iteration order.
		if not _source_to_key.has(src):
			_source_to_key[src] = key


## Primary runtime source: parse_locres.py writes {guid: English} so Loc works
## identically in the editor and in an exported PCK (CSV imports are remapped).
func _load_reverse_map_from_json() -> bool:
	var path: String = LOCALE_DIR + "/sources.json"
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("[loc] sources.json is not a JSON object: ", path)
		return false
	for key_v: Variant in (parsed as Dictionary).keys():
		var key: String = str(key_v)
		var src: String = str((parsed as Dictionary)[key_v])
		if key == "" or src.strip_edges() == "":
			continue
		_en_key_count += 1
		if not _source_to_key.has(src):
			_source_to_key[src] = key
	if _en_key_count > 0:
		print("TAT-2 Loc: reverse map built from sources.json (", _en_key_count, " keys)")
		return true
	return false


## Exported-build fallback: the English .translation resource carries the same
## GUID -> English mapping as en.csv, and is a real imported resource. Build the
## reverse map from it so Loc works inside a PCK without the raw CSV.
func _load_reverse_map_from_translation() -> bool:
	var tr: Translation = TranslationServer.get_translation_object("en") as Translation
	if tr == null:
		var path: String = LOCALE_DIR + "/en.en.translation"
		var res: Resource = ResourceLoader.load(path) as Resource
		if not (res is Translation):
			return false
		tr = res as Translation
	for key: String in tr.get_message_list():
		var src: String = str(tr.get_message(key))
		if key == "" or src.strip_edges() == "":
			continue
		_en_key_count += 1
		if not _source_to_key.has(src):
			_source_to_key[src] = key
	if _en_key_count > 0:
		print("TAT-2 Loc: reverse map built from en.en.translation (", _en_key_count, " keys)")
		return true
	return false


func _load_translations() -> void:
	_translation_count = 0
	var dir: DirAccess = DirAccess.open(LOCALE_DIR)
	if dir == null:
		push_warning("[loc] missing locale directory: ", LOCALE_DIR)
		return
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".translation"):
			continue
		var path: String = LOCALE_DIR + "/" + file_name
		var res: Resource = ResourceLoader.load(path) as Resource
		if not (res is Translation):
			push_warning("[loc] not a Translation resource: ", path)
			continue
		TranslationServer.add_translation(res as Translation)
		_translation_count += 1
