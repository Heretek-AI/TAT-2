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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_reverse_map()
	_load_translations()
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
		return source
	var out: String = str(TranslationServer.translate(key))
	if out == "" or out == key:
		return source
	return out


func _load_reverse_map() -> void:
	_source_to_key.clear()
	_en_key_count = 0
	if not FileAccess.file_exists(EN_CSV_PATH):
		push_warning("[loc] missing English source table: ", EN_CSV_PATH, " (all strings pass through)")
		return
	var f: FileAccess = FileAccess.open(EN_CSV_PATH, FileAccess.READ)
	if f == null:
		push_warning("[loc] cannot open English source table: ", EN_CSV_PATH)
		return
	var header: PackedStringArray = f.get_csv_line()
	if header.size() < 2:
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
