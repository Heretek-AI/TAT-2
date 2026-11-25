class_name InputRebinder
extends RefCounted
## Authored rebinding with conflict detection and save persistence (RE-H-05).
##
## The shipped build enables rebinding in `DefaultInput.ini:119-124`
## (`bEnableUserSettings=True`, `UserSettingsClass=/Script/TAT.TATEnhancedInputUserSettings`)
## and marks 17 mapping rows `PlayerMappableKeySettings`. The conflict sentence is
## authored: `ST_Settings_Input.InputSetting.Input.RebindSameKey` =
## "{InKey} is already bound to {ActionNames}."
##
## Persistence lives in `SaveSystem.data["settings"]["bindings"]` as
##   { "<port action id>": { "kb": ["G"], "pad": ["Gamepad_FaceButton_Top"] } }
## i.e. the same UE key names the table uses, never Godot enum integers, so a
## future engine/table change can still migrate it. Only actions the player
## actually changed are stored (`overrides`); everything else reads the authored
## table, so a table fix (T01) flows through without rewriting saves.
##
## `save_system.gd` is owned by T02-STATE: this file only adds a key to the
## settings dictionary it already persists. The schema marker is written next to
## it (`bindings_schema`) so T02 can migrate the block as one unit later.

const SETTINGS_KEY: String = "bindings"
const SCHEMA_KEY: String = "bindings_schema"
const BINDINGS_SCHEMA_VERSION: int = 1

const CONFLICT_TEMPLATE_FALLBACK: String = "{InKey} is already bound to {ActionNames}."
const STRINGS_PATH: String = "res://data/generated/tables/StringTables/ST_Settings_Input.json"

static var _conflict_template: String = ""


# ---------------------------------------------------------------------------
# Persistence contract
# ---------------------------------------------------------------------------

## Reads the persisted overrides out of a settings dictionary, dropping anything
## that no longer matches the table (unknown action, unknown key name, malformed).
static func overrides_from_settings(settings: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw: Variant = settings.get(SETTINGS_KEY, {})
	if not (raw is Dictionary):
		return out
	for action_v: Variant in (raw as Dictionary).keys():
		var action: String = str(action_v)
		if InputActions.row_for(action).is_empty():
			continue
		var per_device_v: Variant = (raw as Dictionary)[action_v]
		if not (per_device_v is Dictionary):
			continue
		var per_device: Dictionary = per_device_v as Dictionary
		var entry: Dictionary = {}
		for device: String in [InputActions.DEVICE_KB, InputActions.DEVICE_PAD]:
			if not per_device.has(device):
				continue
			var names_v: Variant = per_device[device]
			if not (names_v is Array):
				continue
			var names: Array[String] = []
			for name_v: Variant in (names_v as Array):
				var name: String = str(name_v)
				if name == "":
					continue
				if InputActions.events_for_key(name).is_empty():
					continue
				if InputActions.device_for_key(name) != device:
					continue
				if not names.has(name):
					names.append(name)
			entry[device] = names
		if not entry.is_empty():
			out[action] = entry
	return out


## Writes the overrides into a settings dictionary (does not touch the disk).
static func write_overrides(settings: Dictionary, overrides: Dictionary) -> void:
	settings[SETTINGS_KEY] = overrides.duplicate(true)
	settings[SCHEMA_KEY] = BINDINGS_SCHEMA_VERSION


## Persists through SaveSystem when it is present. Returns false when no save
## node exists (headless harness without autoloads) — the caller may still hold
## the in-memory dictionary.
static func persist(overrides: Dictionary, save_node: Node = null) -> bool:
	var ss: Node = save_node
	if ss == null:
		var loop: SceneTree = Engine.get_main_loop() as SceneTree
		if loop == null:
			return false
		ss = loop.root.get_node_or_null("SaveSystem")
	if ss == null:
		return false
	var data_v: Variant = ss.get("data")
	if not (data_v is Dictionary):
		return false
	var data: Dictionary = data_v as Dictionary
	if not (data.get("settings") is Dictionary):
		data["settings"] = {}
	write_overrides(data["settings"] as Dictionary, overrides)
	if ss.has_method("write_save"):
		ss.call("write_save")
		return true
	return false


# ---------------------------------------------------------------------------
# Effective bindings and conflicts
# ---------------------------------------------------------------------------

## Effective key names for one action/device: the override when present, else the
## authored table.
static func effective_keys(action: String, device: String, overrides: Dictionary = {}) -> Array[String]:
	if overrides.has(action) and overrides[action] is Dictionary:
		var entry: Dictionary = overrides[action] as Dictionary
		if entry.has(device) and entry[device] is Array:
			var out: Array[String] = []
			for v: Variant in (entry[device] as Array):
				out.append(str(v))
			return out
	return InputActions.authored_key_names(action, device)


## Actions (other than `except_action`) whose effective binding on `device`
## already uses `key_name`.
static func conflicts_for(key_name: String, device: String, except_action: String, overrides: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	if key_name == "":
		return out
	for action: String in InputActions.ids():
		if action == except_action:
			continue
		if effective_keys(action, device, overrides).has(key_name):
			out.append(action)
	return out


static func conflict_template() -> String:
	if _conflict_template != "":
		return _conflict_template
	_conflict_template = CONFLICT_TEMPLATE_FALLBACK
	if FileAccess.file_exists(STRINGS_PATH):
		var f: FileAccess = FileAccess.open(STRINGS_PATH, FileAccess.READ)
		if f != null:
			var doc: Variant = JSON.parse_string(f.get_as_text())
			if doc is Dictionary:
				var entries: Variant = (doc as Dictionary).get("entries", {})
				if entries is Dictionary:
					var raw: String = str((entries as Dictionary).get("InputSetting.Input.RebindSameKey", "")).strip_edges()
					if raw != "":
						_conflict_template = raw
	return _conflict_template


## The authored sentence with the placeholders filled. `key_text` is the display
## form ("G", "X"); labels are the conflicting actions' authored display names.
static func conflict_message(key_text: String, labels: Array) -> String:
	var names: String = ""
	for i: int in range(labels.size()):
		if i > 0:
			names += ", "
		names += str(labels[i])
	return conflict_template().replace("{InKey}", key_text).replace("{ActionNames}", names)


# ---------------------------------------------------------------------------
# Mutations (in-memory; caller persists)
# ---------------------------------------------------------------------------

## Binds `event` to `action` on `device`. Returns
## {ok, key_name, message, conflicts[], labels[]}. A conflict is a refusal: the
## shipped build never silently steals another action's key.
static func rebind(action: String, device: String, event: InputEvent, overrides: Dictionary, key_text: String = "") -> Dictionary:
	var result: Dictionary = {"ok": false, "key_name": "", "message": "", "conflicts": [] as Array[String], "labels": [] as Array[String]}
	if InputActions.row_for(action).is_empty():
		result["message"] = "Unknown action: " + action
		return result
	var key_name: String = InputActions.key_name_for_event(event)
	if key_name == "":
		result["message"] = "That input cannot be bound here."
		return result
	if InputActions.device_for_key(key_name) != device:
		result["message"] = "Wrong device for that key."
		return result
	var conflicts: Array[String] = conflicts_for(key_name, device, action, overrides)
	if not conflicts.is_empty():
		var labels: Array[String] = []
		for other: String in conflicts:
			labels.append(InputGlyphs.action_label(other))
		result["key_name"] = key_name
		result["conflicts"] = conflicts
		result["labels"] = labels
		var shown: String = key_text if key_text != "" else InputGlyphs.key_label(key_name)
		result["message"] = conflict_message(shown, labels)
		return result
	if not overrides.has(action) or not (overrides[action] is Dictionary):
		overrides[action] = {}
	var entry: Dictionary = overrides[action] as Dictionary
	entry[device] = [key_name]
	var keys: Array[String] = []
	for v: Variant in (entry[device] as Array):
		keys.append(str(v))
	entry[device] = keys
	result["ok"] = true
	result["key_name"] = key_name
	return result


## Removes one device's override, restoring the authored binding for it.
static func reset_action(action: String, device: String, overrides: Dictionary) -> void:
	if not overrides.has(action) or not (overrides[action] is Dictionary):
		return
	var entry: Dictionary = overrides[action] as Dictionary
	entry.erase(device)
	if entry.is_empty():
		overrides.erase(action)


static func reset_all(overrides: Dictionary) -> void:
	overrides.clear()


## True when the action/device currently differs from the authored table.
static func is_overridden(action: String, device: String, overrides: Dictionary) -> bool:
	if not overrides.has(action) or not (overrides[action] is Dictionary):
		return false
	return ((overrides[action] as Dictionary).get(device, null) is Array)


## Applies the persisted overrides on boot. Called by InputContext._ready().
static func apply(overrides: Dictionary, table_rows: Array = []) -> Dictionary:
	return InputActions.apply_to_input_map(table_rows, overrides)
