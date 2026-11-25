class_name UnlockCatalog
extends RefCounted
## Read-only view of the authored Black Market catalog emitted by
## tools/parse_unlocks.py (game/data/generated/gameplay/unlocks.json).
##
## The Ledger Black Market and the Wardrobe are data-driven: every row, price,
## icon, title, description and unlock gate comes from the shipped
## DA_UnlockableContentEntries table. Nothing in this class invents a price:
## a row is either purchased, gated (padlock) or purchasable at its authored
## price. If the file is missing or fails a schema/count check the catalog is
## "unavailable" and both panels fail closed (no BUY path), never silently
## falling back to a hand-written table.
##
## Save ids are the stable identity SaveSystem stores:
##   * tools / guild perks -> snake_case SaveSystem ids (zipwire, guildhall, ...)
##   * cosmetics           -> the authored outfit tag (Outfit.Spider.Head.BowlerA)
## blackjack is a built-in starting tool and is not one of the 68 rows.

const CATALOG_PATH: String = "res://data/generated/gameplay/unlocks.json"
const CATALOG_SCHEMA: String = "tat2.unlock_catalog/1"
const EXPECTED_ENTRIES: int = 68
const EXPECTED_COLUMN_COUNTS: Dictionary = {
	"tools": 7,
	"guild_perks": 7,
	"spider_cosmetics": 28,
	"chameleon_cosmetics": 26,
}
const COLUMN_KEYS: Array[String] = [
	"tools", "guild_perks", "spider_cosmetics", "chameleon_cosmetics",
]
const STATE_PURCHASED: String = "purchased"
const STATE_LOCKED: String = "locked"
const STATE_BUY: String = "buy"

## Icon textures are shared by both panels and never freed by a panel.
static var _icon_cache: Dictionary = {}

var _available: bool = false
var _errors: Array[String] = []
var _entries: Array[Dictionary] = []
var _by_save_id: Dictionary = {}
var _columns: Array[Dictionary] = []
var _built_ins: Array[Dictionary] = []


func _init() -> void:
	reload()


func reload() -> bool:
	_available = false
	_errors.clear()
	_entries.clear()
	_by_save_id.clear()
	_columns.clear()
	_built_ins.clear()
	if not FileAccess.file_exists(CATALOG_PATH):
		_errors.append("missing " + CATALOG_PATH)
		return false
	var f: FileAccess = FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		_errors.append("cannot open " + CATALOG_PATH)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (parsed is Dictionary):
		_errors.append("catalog is not a JSON object")
		return false
	var doc: Dictionary = parsed as Dictionary
	var catalog_v: Variant = doc.get("catalog", null)
	if not (catalog_v is Dictionary):
		_errors.append("catalog block missing (regenerate with tools/parse_unlocks.py)")
		return false
	var catalog: Dictionary = catalog_v as Dictionary
	if str(catalog.get("schema", "")) != CATALOG_SCHEMA:
		_errors.append("catalog schema %s, expected %s" % [
			str(catalog.get("schema", "")), CATALOG_SCHEMA])
		return false
	var rows_v: Variant = doc.get("entries", null)
	if not (rows_v is Array):
		_errors.append("entries is not an array")
		return false
	var rows: Array = rows_v as Array
	if rows.size() != EXPECTED_ENTRIES:
		_errors.append("%d entries, expected %d" % [rows.size(), EXPECTED_ENTRIES])
		return false
	for row_v: Variant in rows:
		if not (row_v is Dictionary):
			_errors.append("entry is not an object")
			return false
		var row: Dictionary = row_v as Dictionary
		var save_id: String = str(row.get("save_id", "")).strip_edges()
		if save_id == "":
			_errors.append("entry %s has no save_id" % str(row.get("tag", "?")))
			return false
		if _by_save_id.has(save_id):
			_errors.append("duplicate save_id %s" % save_id)
			return false
		if not (row.get("condition") is Dictionary):
			_errors.append("%s has no condition block" % save_id)
			return false
		if int(row.get("price", -1)) < 0:
			_errors.append("%s has no authored price" % save_id)
			return false
		_by_save_id[save_id] = row
		_entries.append(row)
	# Column membership is authored by the producer; validate the counts so a
	# content drift cannot quietly move a row into another table.
	for column_v: Variant in (catalog.get("columns") as Array if catalog.get("columns") is Array else []):
		if not (column_v is Dictionary):
			continue
		var column: Dictionary = (column_v as Dictionary).duplicate(true)
		var key: String = str(column.get("key", ""))
		var want: int = int(EXPECTED_COLUMN_COUNTS.get(key, -1))
		var have: int = 0
		for entry: Dictionary in _entries:
			if str(entry.get("shop_category", "")) == key:
				have += 1
		if have != want:
			_errors.append("column %s has %d rows, expected %d" % [key, have, want])
			return false
		column["count"] = have
		_columns.append(column)
	if _columns.size() != COLUMN_KEYS.size():
		_errors.append("catalog declares %d columns, expected %d" % [
			_columns.size(), COLUMN_KEYS.size()])
		return false
	var built_v: Variant = catalog.get("built_ins", [])
	if built_v is Array:
		for built_row: Variant in built_v as Array:
			if built_row is Dictionary:
				_built_ins.append((built_row as Dictionary).duplicate(true))
	_available = true
	return true


func is_available() -> bool:
	return _available


func errors() -> Array[String]:
	return _errors.duplicate()


## All 68 authored rows in table order.
func entries() -> Array[Dictionary]:
	return _entries.duplicate()


func entry(save_id: String) -> Dictionary:
	var row_v: Variant = _by_save_id.get(save_id.strip_edges(), null)
	return (row_v as Dictionary).duplicate(true) if row_v is Dictionary else {}


func has(save_id: String) -> bool:
	return _by_save_id.has(save_id.strip_edges())


## The four KF08 tables in shipped order (TOOLS, GUILD PERKS, SPIDER
## COSMETICS, CHAMELEON COSMETICS), each {key, title, save_category, thief}.
func columns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for column: Dictionary in _columns:
		out.append(column.duplicate(true))
	return out


func entries_for_column(key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var clean: String = key.strip_edges()
	for row: Dictionary in _entries:
		if str(row.get("shop_category", "")) == clean:
			out.append(row)
	return out


func built_in_tools() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in _built_ins:
		out.append(row.duplicate(true))
	return out


static func save_id_of(entry: Dictionary) -> String:
	return str(entry.get("save_id", "")).strip_edges()


## SaveSystem category alias ("tools" / "perks" / "cosmetics").
static func category_of(entry: Dictionary) -> String:
	return str(entry.get("save_category", "")).strip_edges()


static func title_of(entry: Dictionary) -> String:
	var display_v: Variant = entry.get("display", {})
	var title_v: Variant = (display_v as Dictionary).get("title", {}) if display_v is Dictionary else {}
	if title_v is Dictionary:
		return str((title_v as Dictionary).get("text", ""))
	return ""


static func description_of(entry: Dictionary) -> String:
	var display_v: Variant = entry.get("display", {})
	var desc_v: Variant = (display_v as Dictionary).get("description", {}) if display_v is Dictionary else {}
	if desc_v is Dictionary:
		return str((desc_v as Dictionary).get("text", ""))
	return ""


static func price_of(entry: Dictionary) -> int:
	var raw: Variant = entry.get("price", 0)
	return int(raw) if (raw is int or raw is float) else 0


static func icon_res_of(entry: Dictionary) -> String:
	var icon_v: Variant = entry.get("icon", {})
	if icon_v is Dictionary:
		return str((icon_v as Dictionary).get("res", ""))
	return ""


static func icon_texture(entry: Dictionary) -> Texture2D:
	var path: String = icon_res_of(entry)
	if path == "":
		return null
	var cached: Variant = _icon_cache.get(path, null)
	if cached is Texture2D:
		return cached as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var loaded: Resource = ResourceLoader.load(path)
	if loaded is Texture2D:
		_icon_cache[path] = loaded
		return loaded as Texture2D
	return null


static func condition_of(entry: Dictionary) -> Dictionary:
	var cond_v: Variant = entry.get("condition", {})
	return (cond_v as Dictionary).duplicate(true) if cond_v is Dictionary else {}


## The authored gate sentence ("Unlocked at Level 4." / "Unlocked in Contract
## 3."), or "" for a row with no gate (available from the start).
static func condition_text(entry: Dictionary) -> String:
	return str(condition_of(entry).get("text", ""))


static func requires_level(entry: Dictionary) -> int:
	var raw: Variant = condition_of(entry).get("requires_level", null)
	return int(raw) if (raw is int or raw is float) else 0


static func requires_contract(entry: Dictionary) -> int:
	var raw: Variant = condition_of(entry).get("requires_contract", null)
	return int(raw) if (raw is int or raw is float) else 0


## Player level, always re-derived from XP by SaveSystem.
func player_level() -> int:
	var prog: Dictionary = SaveSystem.get_level_progress()
	return int(prog.get("level", 1))


func completed_contract_orders() -> Dictionary:
	var cc_v: Variant = SaveSystem.data.get("completed_contracts", {})
	return cc_v as Dictionary if cc_v is Dictionary else {}


## Structured gate check (the field the shipped game applies). A missing gate
## is satisfied; a present gate must be met. Rows carry at most one level and
## one contract gate in the shipped table, and both are enforced when present.
func conditions_met(entry: Dictionary) -> bool:
	var need_level: int = requires_level(entry)
	if need_level > 0 and player_level() < need_level:
		return false
	var need_contract: int = requires_contract(entry)
	if need_contract > 0 and not completed_contract_orders().has(str(need_contract)):
		return false
	return true


## A row is owned when it is in the save, or when the authored table makes it
## free (price 0) and its gate is met -- the shipped build shows those as
## already purchased (KF08: Zipwire / Smoke Bomb / Novice / Guildhall / Spider).
func is_purchased(entry: Dictionary) -> bool:
	var save_id: String = save_id_of(entry)
	if save_id == "":
		return false
	var category: String = category_of(entry)
	if category != "" and SaveSystem.is_unlocked(category, save_id):
		return true
	return price_of(entry) == 0 and conditions_met(entry)


## "purchased" | "locked" | "buy" -- exactly the three KF08 table states.
func state_of(entry: Dictionary) -> String:
	if is_purchased(entry):
		return STATE_PURCHASED
	if not conditions_met(entry):
		return STATE_LOCKED
	return STATE_BUY


func can_purchase(entry: Dictionary) -> bool:
	if not _available or entry.is_empty():
		return false
	if state_of(entry) != STATE_BUY:
		return false
	return SaveSystem.get_currency() >= price_of(entry)


## Authored price for display. The shipped frame prints thousands separators
## (7,500 / 26,275) through the same helper the HUD uses.
func price_text(entry: Dictionary) -> String:
	return GameState.format_thousands(price_of(entry))


## Short lock reason for the preview card, from the structured gate.
static func lock_reason(entry: Dictionary) -> String:
	var need_level: int = requires_level(entry)
	var need_contract: int = requires_contract(entry)
	if need_level > 0 and need_contract > 0:
		return "Requires Level %d and Contract %d" % [need_level, need_contract]
	if need_level > 0:
		return "Requires Level %d" % need_level
	if need_contract > 0:
		return "Requires Contract %d" % need_contract
	return ""
