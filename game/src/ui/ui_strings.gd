class_name UIStrings
extends RefCounted
## UI-side reader for the authored StringTables.
##
## 54 generated StringTables (1,687 rows) ship under
## `res://data/generated/tables/StringTables/`. Before T05 only `ST_Settings`
## was read, so almost every UI label was a hardcoded English literal (RE-L-14 /
## RE-L-15). This is the single UI-side accessor: it returns the authored English
## row and then routes it through the `Loc` autoload, so the existing locale
## pipeline (source string -> GUID -> translation, English fallback) applies.
##
## Ownership: table *production* belongs to T01-PIPELINE (`tools/parse_tables.py`);
## this file only reads what is already generated and never writes or regenerates
## anything. Callers pass the authored table name and key, plus the literal the
## port used to hardcode as the last-resort fallback.

const TABLE_DIR: String = "res://data/generated/tables/StringTables/"

static var _cache: Dictionary = {}


## Rows of one table (empty when the table is missing or malformed).
static func table(table_name: String) -> Dictionary:
	if _cache.has(table_name):
		return _cache[table_name] as Dictionary
	var out: Dictionary = {}
	var path: String = TABLE_DIR + table_name + ".json"
	if FileAccess.file_exists(path):
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				var entries_v: Variant = (parsed as Dictionary).get("entries", {})
				if entries_v is Dictionary:
					out = entries_v as Dictionary
	_cache[table_name] = out
	return out


## The authored English row, or `fallback` when the table/key is missing.
static func raw(table_name: String, key: String, fallback: String = "") -> String:
	var rows: Dictionary = table(table_name)
	if rows.has(key):
		return str(rows[key])
	return fallback


## Locale translation of an authored source string (English when no locale is
## active or the locale lacks the row). Never returns a GUID (localization.gd).
static func t(source: String) -> String:
	if source.is_empty():
		return source
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return source
	var tree: SceneTree = loop as SceneTree
	if tree == null or tree.root == null:
		return source
	var loc: Node = tree.root.get_node_or_null("Loc")
	if loc != null and loc.has_method("t"):
		return str(loc.call("t", source))
	return source


## Authored row -> locale translation. The one call the UI should use.
static func st_text(table_name: String, key: String, fallback: String = "") -> String:
	return t(raw(table_name, key, fallback))


## Upper-case authored row (the port's menu-style labels).
static func st_upper(table_name: String, key: String, fallback: String = "") -> String:
	return st_text(table_name, key, fallback).to_upper()


## Number of rows a table contributes (diagnostics / tests).
static func row_count(table_name: String) -> int:
	return table(table_name).size()


## Drop the parsed-table cache (tests that switch data trees).
static func clear_cache() -> void:
	_cache.clear()
