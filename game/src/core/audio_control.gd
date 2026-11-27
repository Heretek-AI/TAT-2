class_name AudioControl
extends RefCounted
## Wwise control plane for the port: switches, states and RTPCs.
##
## Source: `res://data/generated/audio_control.json`, schema
## `tat2.audio_control/1`, produced by `tools/parse_audio_control.py` from the
## shipped bank (`WwiseSharedAssetLibrary.json`) plus the `AkSwitchValue` /
## `AkStateValue` / `AkRtpc` asset dumps. This class only consumes that
## document; it never reads the bank and never invents a group, value, curve or
## binding.
##
## What the authored data actually is (measured, see the producer's counts):
##   * 14 named switch groups / 84 values.  A switch group is the *only* thing
##     that selects media: its `SwitchContainer` packages own media ids.
##   * 4 named state groups / 10 values.  A state group carries per-node
##     property overrides (volume dB, pitch cents, ...); it never selects media.
##     `state_override_rows()` exposes those rows for a consumer that owns the
##     matching node; this slice only records the state and drives the port's
##     interior/exterior reverb and modal duck through `audio_manager`.
##   * 16 named RTPCs (34 more the bank references are id-only) with 142
##     authored node/param curves.  One RTPC has a different curve per node, so
##     `gain_db(rtpc, node)` / `pitch_scale` / `low_pass_hz` take the node when a
##     caller knows it and otherwise pick the authored curve carried by the most
##     nodes (documented, deterministic) — never an invented average.
##
## Media selection is a *ban*, not a pick. `packages[].media` is a superset
## (it includes nested switch branches), so:
##   banned  = union over reached containers of
##             (every package's media - the selected package's media)
##   allowed = the event's media - banned
## A media id no container covers (a plain layer on its own Play action) is
## never banned. This is exact for parallel and nested containers and is why
## `Play_FS_Player_Walk` + `FS_Material=Stone` leaves the Stone surface clips
## and drops every Carpet/Tile/Dirt one.
##
## Degradation contract: the JSON is derived content and is absent on a fresh
## clone. `load_data()` then returns false, `degraded_reason()` explains why,
## every getter returns a documented neutral value and `select_media()`
## returns the input unchanged, so `audio_manager` keeps its pre-control-plane
## behaviour (surface-token footstep pools) rather than going silent.
##
## Curve interpolation: `Linear` and `Constant` segments are evaluated exactly
## as Wwise defines them. The exponential/logarithmic/SCurve segment shapes are
## not reproduced (Godot has no public formula for them), so they are evaluated
## linearly and counted in `curve_report()`; that is a labelled approximation,
## never an invented curve.

const SCHEMA: String = "tat2.audio_control/1"
const DEFAULT_PATH: String = "res://data/generated/audio_control.json"
const ENV_OVERRIDE: String = "TAT2_AUDIO_CONTROL_JSON"

## Wwise filter properties are a 0..100 "percent" where 100 = 20 kHz and each
## unit is 1/10 octave: hz = 20 * 2^(percent / 10).  Both endpoints are exact
## (0 -> 20 Hz, 100 -> 20480 Hz).
const FILTER_OCTAVES: float = 10.0
const FILTER_HZ_FLOOR: float = 20.0

## Param names the producer emits (Wwise AkPropID). Only these are applied.
const PARAM_VOLUME: String = "volume_db"
const PARAM_PITCH: String = "pitch_cents"
const PARAM_LOW_PASS: String = "low_pass"
const PARAM_HIGH_PASS: String = "high_pass"

var _loaded: bool = false
var _reason: String = ""
var _path: String = ""

var _counts: Dictionary = {}
var _switch_blocks: Array = []
var _state_blocks: Array = []
var _rtpc_blocks: Array = []
var _containers: Dictionary = {}
var _events: Dictionary = {}

## name/id -> block
var _switch_by_name: Dictionary = {}
var _switch_by_id: Dictionary = {}
var _state_by_name: Dictionary = {}
var _state_by_id: Dictionary = {}
var _rtpc_by_name: Dictionary = {}
var _rtpc_by_id: Dictionary = {}
## group id -> {lowercase value name: value id}
var _switch_values: Dictionary = {}
var _state_values: Dictionary = {}
## group id -> {value id: name}
var _switch_value_names: Dictionary = {}
var _state_value_names: Dictionary = {}

## Runtime state: group id -> value id, rtpc id -> value.
var _switch_state: Dictionary = {}
var _state_state: Dictionary = {}
var _rtpc_state: Dictionary = {}

## Curve evaluation counters (approximation disclosure, never a gate).
var _curve_calls: int = 0
var _curve_approx_calls: int = 0


## Loads the control document. [param path] empty means the default path,
## overridable with TAT2_AUDIO_CONTROL_JSON (tests).
func load_data(path: String = "") -> bool:
	reset()
	_path = path
	if _path.is_empty():
		_path = OS.get_environment(ENV_OVERRIDE)
	if _path.is_empty():
		_path = DEFAULT_PATH
	if not FileAccess.file_exists(_path):
		_reason = "missing:%s" % _path
		return false
	var text: String = FileAccess.get_file_as_string(_path)
	if text.is_empty():
		_reason = "unreadable:%s" % _path
		return false
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_reason = "not_json:%s" % _path
		return false
	var doc: Dictionary = parsed as Dictionary
	if str(doc.get("schema", "")) != SCHEMA:
		_reason = "schema:%s" % str(doc.get("schema", ""))
		return false
	var counts_v: Variant = doc.get("counts", {})
	if counts_v is Dictionary:
		_counts = counts_v as Dictionary
	var groups_v: Variant = doc.get("switch_groups", [])
	if groups_v is Array:
		_switch_blocks = groups_v as Array
	for block_v: Variant in _switch_blocks:
		if not (block_v is Dictionary):
			continue
		var block: Dictionary = block_v as Dictionary
		var gid: int = int(block.get("id", 0))
		_switch_by_id[gid] = block
		var gname: String = str(block.get("name", ""))
		if not gname.is_empty():
			_switch_by_name[gname.to_lower()] = block
		var by_name: Dictionary = {}
		var by_id: Dictionary = {}
		for value_v: Variant in block.get("values", []) as Array:
			if not (value_v is Dictionary):
				continue
			var value: Dictionary = value_v as Dictionary
			var vid: int = int(value.get("id", 0))
			var vname: String = str(value.get("name", ""))
			if not vname.is_empty():
				by_name[vname.to_lower()] = vid
			by_id[vid] = vname
		_switch_values[gid] = by_name
		_switch_value_names[gid] = by_id
	var states_v: Variant = doc.get("state_groups", [])
	if states_v is Array:
		_state_blocks = states_v as Array
	for block_v: Variant in _state_blocks:
		if not (block_v is Dictionary):
			continue
		var block: Dictionary = block_v as Dictionary
		var gid: int = int(block.get("id", 0))
		_state_by_id[gid] = block
		var gname: String = str(block.get("name", ""))
		if not gname.is_empty():
			_state_by_name[gname.to_lower()] = block
		var by_name: Dictionary = {}
		var by_id: Dictionary = {}
		for value_v: Variant in block.get("values", []) as Array:
			if not (value_v is Dictionary):
				continue
			var value: Dictionary = value_v as Dictionary
			var vid: int = int(value.get("id", 0))
			var vname: String = str(value.get("name", ""))
			if not vname.is_empty():
				by_name[vname.to_lower()] = vid
			by_id[vid] = vname
		_state_values[gid] = by_name
		_state_value_names[gid] = by_id
	for key: String in ["rtpcs", "unnamed_rtpcs"]:
		var rows_v: Variant = doc.get(key, [])
		if not (rows_v is Array):
			continue
		for row_v: Variant in rows_v as Array:
			if not (row_v is Dictionary):
				continue
			var row: Dictionary = row_v as Dictionary
			_rtpc_blocks.append(row)
			var rid: int = int(row.get("id", 0))
			_rtpc_by_id[rid] = row
			var rname: String = str(row.get("name", ""))
			if not rname.is_empty():
				_rtpc_by_name[rname.to_lower()] = row
	var containers_v: Variant = doc.get("switch_containers", [])
	if containers_v is Array:
		for container_v: Variant in containers_v as Array:
			if container_v is Dictionary:
				var container: Dictionary = container_v as Dictionary
				_containers[int(container.get("id", 0))] = container
	var events_v: Variant = doc.get("events", {})
	if events_v is Dictionary:
		_events = events_v as Dictionary
	_loaded = true
	return true


## Clears every index and every runtime value. Safe on a fresh instance.
func reset() -> void:
	_loaded = false
	_reason = ""
	_counts = {}
	_switch_blocks = []
	_state_blocks = []
	_rtpc_blocks = []
	_containers = {}
	_events = {}
	_switch_by_name = {}
	_switch_by_id = {}
	_state_by_name = {}
	_state_by_id = {}
	_rtpc_by_name = {}
	_rtpc_by_id = {}
	_switch_values = {}
	_state_values = {}
	_switch_value_names = {}
	_state_value_names = {}
	_switch_state = {}
	_state_state = {}
	_rtpc_state = {}
	_curve_calls = 0
	_curve_approx_calls = 0


func is_loaded() -> bool:
	return _loaded


func degraded_reason() -> String:
	return _reason


func counts() -> Dictionary:
	return _counts.duplicate(true)


func switch_group_count() -> int:
	return int(_counts.get("switch_groups", 0))


func state_group_count() -> int:
	return int(_counts.get("state_groups", 0))


func rtpc_count() -> int:
	return int(_counts.get("rtpcs", 0))


func switch_groups() -> Array:
	return _switch_blocks.duplicate(true)


func state_groups() -> Array:
	return _state_blocks.duplicate(true)


## Names of every named RTPC, sorted. The 34 id-only rows are not in this list.
func rtpc_names() -> Array:
	var out: Array = []
	for row_v: Variant in _rtpc_blocks:
		if not (row_v is Dictionary):
			continue
		var name_v: Variant = (row_v as Dictionary).get("name", null)
		if name_v == null:
			continue
		var name: String = str(name_v)
		if not name.is_empty():
			out.append(name)
	out.sort()
	return out


## ---------------------------------------------------------------------------
## Switches
## ---------------------------------------------------------------------------

## Sets [param group] to [param value]. Both accept the authored name
## (case-insensitive) or the numeric id. Returns false and changes nothing when
## either side is unknown, so a typo can never silently select a default.
func set_switch(group: Variant, value: Variant) -> bool:
	if not _loaded:
		return false
	var block: Dictionary = _find_switch_group(group)
	if block.is_empty():
		return false
	var value_id: int = _resolve_switch_value(block, value)
	if value_id == 0:
		return false
	_switch_state[int(block.get("id", 0))] = value_id
	return true


## Authored value name for the group's current switch, "" when unset/unknown.
func switch_value(group: Variant) -> String:
	var block: Dictionary = _find_switch_group(group)
	if block.is_empty():
		return ""
	var gid: int = int(block.get("id", 0))
	if not _switch_state.has(gid):
		return ""
	var names: Dictionary = _switch_value_names.get(gid, {})
	return str(names.get(int(_switch_state[gid]), ""))


## Current value id for the group, 0 when unset/unknown (0 is never a value id).
func switch_id(group: Variant) -> int:
	var block: Dictionary = _find_switch_group(group)
	if block.is_empty():
		return 0
	return int(_switch_state.get(int(block.get("id", 0)), 0))


## Names of the group's authored values, sorted.
func switch_value_names(group: Variant) -> Array:
	var block: Dictionary = _find_switch_group(group)
	if block.is_empty():
		return []
	var out: Array = []
	for value_v: Variant in block.get("values", []) as Array:
		var name: String = str((value_v as Dictionary).get("name", ""))
		if not name.is_empty():
			out.append(name)
	out.sort()
	return out


func has_switch_group(group: Variant) -> bool:
	return not _find_switch_group(group).is_empty()


## ---------------------------------------------------------------------------
## States
## ---------------------------------------------------------------------------

## Sets [param group] to [param value] (name or id). Returns false on unknown.
## States drive authored property overrides, not media selection.
func set_state(group: Variant, value: Variant) -> bool:
	if not _loaded:
		return false
	var block: Dictionary = _find_state_group(group)
	if block.is_empty():
		return false
	var value_id: int = _resolve_state_value(block, value)
	if value_id == 0:
		return false
	_state_state[int(block.get("id", 0))] = value_id
	return true


func state_value(group: Variant) -> String:
	var block: Dictionary = _find_state_group(group)
	if block.is_empty():
		return ""
	var gid: int = int(block.get("id", 0))
	if not _state_state.has(gid):
		return ""
	var names: Dictionary = _state_value_names.get(gid, {})
	return str(names.get(int(_state_state[gid]), ""))


func state_id(group: Variant) -> int:
	var block: Dictionary = _find_state_group(group)
	if block.is_empty():
		return 0
	return int(_state_state.get(int(block.get("id", 0)), 0))


func state_value_names(group: Variant) -> Array:
	var block: Dictionary = _find_state_group(group)
	if block.is_empty():
		return []
	var out: Array = []
	for value_v: Variant in block.get("values", []) as Array:
		var name: String = str((value_v as Dictionary).get("name", ""))
		if not name.is_empty():
			out.append(name)
	out.sort()
	return out


## The authored property rows the group's *current* state applies, across every
## node that carries them: [{param, param_id, value, node}]. Empty when the
## state is unset or has no override. This is the honest surface for a consumer
## that owns one of those nodes; there is no global "state volume".
func state_override_rows(group: Variant) -> Array:
	var block: Dictionary = _find_state_group(group)
	if block.is_empty():
		return []
	var gid: int = int(block.get("id", 0))
	if not _state_state.has(gid):
		return []
	var state_id_now: int = int(_state_state[gid])
	var out: Array = []
	for row_v: Variant in block.get("overrides", []) as Array:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		for value_v: Variant in row.get("values", []) as Array:
			if not (value_v is Dictionary):
				continue
			var value: Dictionary = value_v as Dictionary
			if int(value.get("state", 0)) != state_id_now:
				continue
			for node_v: Variant in value.get("nodes", []) as Array:
				out.append({
					"param": str(row.get("param", "")),
					"param_id": int(row.get("param_id", -1)),
					"value": float(value.get("value", 0.0)),
					"node": str(node_v),
				})
	return out


## ---------------------------------------------------------------------------
## RTPCs
## ---------------------------------------------------------------------------

## Sets an RTPC by authored name or numeric id. Returns false when the id is not
## in the document (an id the bank never references cannot be set).
func set_rtpc(name: Variant, value: float) -> bool:
	if not _loaded:
		return false
	var row: Dictionary = _find_rtpc(name)
	if row.is_empty():
		return false
	_rtpc_state[int(row.get("id", 0))] = float(value)
	return true


func rtpc_value(name: Variant) -> float:
	var row: Dictionary = _find_rtpc(name)
	if row.is_empty():
		return 0.0
	return float(_rtpc_state.get(int(row.get("id", 0)), 0.0))


## Authored additive gain in dB for the RTPC's current value, 0.0 when the RTPC
## has no volume curve. [param node] ("Type:Id") picks that node's authored
## curve; empty picks the curve carried by the most nodes.
func gain_db(name: Variant, node: String = "") -> float:
	return curve_value(name, PARAM_VOLUME, rtpc_value(name), node)


## Authored pitch offset as a linear ratio (2 ^ (cents / 1200)).
func pitch_scale(name: Variant, node: String = "") -> float:
	var cents: float = curve_value(name, PARAM_PITCH, rtpc_value(name), node)
	return pow(2.0, cents / 1200.0)


## Authored low-pass cutoff in Hz, 0.0 when the RTPC has no low-pass curve.
func low_pass_hz(name: Variant, node: String = "") -> float:
	var percent: float = curve_value(name, PARAM_LOW_PASS, rtpc_value(name), node)
	if percent <= 0.0:
		return 0.0
	return FILTER_HZ_FLOOR * pow(2.0, clampf(percent, 0.0, 100.0) / FILTER_OCTAVES)


## Evaluates the authored curve for [param param] at [param x]. Returns 0.0 when
## the RTPC or the param has no curve.
func curve_value(name: Variant, param: String, x: float, node: String = "") -> float:
	var curve: Dictionary = _find_curve(name, param, node)
	if curve.is_empty():
		return 0.0
	return evaluate_curve(curve.get("points", []) as Array,
		curve.get("interpolation", []) as Array, x)


## Pure curve evaluation, exposed for tests and for callers with their own
## points. Clamps outside the authored range (Wwise behaviour).
func evaluate_curve(points: Array, interpolation: Array, x: float) -> float:
	if points.is_empty():
		return 0.0
	_curve_calls += 1
	if points.size() == 1:
		return _point_y(points[0])
	var first: Array = points[0] as Array
	if x <= _point_x(first):
		return _point_y(first)
	for index: int in range(points.size() - 1):
		var left: Array = points[index] as Array
		var right: Array = points[index + 1] as Array
		var x0: float = _point_x(left)
		var x1: float = _point_x(right)
		if x < x0:
			continue
		if x > x1:
			continue
		if is_equal_approx(x1, x0):
			return _point_y(right)
		var mode: String = ""
		if index < interpolation.size():
			mode = str(interpolation[index])
		if mode == "Constant":
			return _point_y(left)
		if mode != "Linear":
			_curve_approx_calls += 1
		var t: float = (x - x0) / (x1 - x0)
		return lerpf(_point_y(left), _point_y(right), t)
	var last: Array = points[points.size() - 1] as Array
	return _point_y(last)


## What the curve evaluator actually did, for QA. `approximated` counts segments
## whose authored shape (Exp/Log/SCurve) was evaluated linearly.
func curve_report() -> Dictionary:
	return {"calls": _curve_calls, "approximated": _curve_approx_calls}


## ---------------------------------------------------------------------------
## Media selection
## ---------------------------------------------------------------------------

## Control surface an event reaches, straight from the document: {event_id,
## containers, switch_groups, state_groups, rtpcs}. Empty for an event with no
## authored control.
func event_control(event_name: String) -> Dictionary:
	var block: Variant = _events.get(event_name, null)
	if block is Dictionary:
		return (block as Dictionary).duplicate(true)
	return {}


## Filters [param media_ids] (MediaIds from audio_events.json) down to what the
## current switch values can play. Identity when the event has no control data
## or the document is absent, and the identity again if the ban would empty the
## event (fail-open: a port must never go silent because a value is unset).
func select_media(event_name: String, media_ids: Array) -> Array:
	if not _loaded or media_ids.is_empty():
		return media_ids
	var block_v: Variant = _events.get(event_name, null)
	if not (block_v is Dictionary):
		return media_ids
	var block: Dictionary = block_v as Dictionary
	var banned: Dictionary = {}
	var have_ban: bool = false
	for container_id_v: Variant in block.get("containers", []) as Array:
		var container_v: Variant = _containers.get(int(container_id_v), null)
		if not (container_v is Dictionary):
			continue
		var container: Dictionary = container_v as Dictionary
		var group_id: int = int(container.get("group", 0))
		var wanted: int = int(_switch_state.get(group_id, container.get("default", 0)))
		var covered: Dictionary = {}
		var selected: Dictionary = {}
		var selected_found: bool = false
		for package_v: Variant in container.get("packages", []) as Array:
			if not (package_v is Dictionary):
				continue
			var package: Dictionary = package_v as Dictionary
			var is_selected: bool = int(package.get("switch", -1)) == wanted
			for media_v: Variant in package.get("media", []) as Array:
				var mid: int = int(media_v)
				covered[mid] = true
				if is_selected:
					selected[mid] = true
			if is_selected:
				selected_found = true
		if not selected_found:
			# Unknown/unset value with no matching package: fall back to the
			# authored default package, and if that is missing too, do not ban.
			var default_id: int = int(container.get("default", 0))
			for package_v: Variant in container.get("packages", []) as Array:
				if not (package_v is Dictionary):
					continue
				var package: Dictionary = package_v as Dictionary
				if int(package.get("switch", -1)) != default_id:
					continue
				for media_v: Variant in package.get("media", []) as Array:
					selected[int(media_v)] = true
				selected_found = true
				break
		if not selected_found:
			continue
		for mid_v: Variant in covered.keys():
			var mid: int = int(mid_v)
			if not selected.has(mid):
				banned[mid] = true
				have_ban = true
	if not have_ban:
		return media_ids
	var out: Array = []
	for media_v: Variant in media_ids:
		if not banned.has(int(media_v)):
			out.append(media_v)
	if out.is_empty():
		return media_ids
	return out


## Media ids the event's packages for [param group] = [param value] cover,
## unioned across every reached container of that group. Used by the footstep
## test and by QA; it is the raw authored package data, not a selection.
func media_ids_for(event_name: String, group: Variant, value: Variant) -> Array:
	var block_v: Variant = _events.get(event_name, null)
	var group_block: Dictionary = _find_switch_group(group)
	if not (block_v is Dictionary) or group_block.is_empty():
		return []
	var value_id: int = _resolve_switch_value(group_block, value)
	if value_id == 0:
		return []
	var out: Dictionary = {}
	for container_id_v: Variant in (block_v as Dictionary).get("containers", []) as Array:
		var container_v: Variant = _containers.get(int(container_id_v), null)
		if not (container_v is Dictionary):
			continue
		var container: Dictionary = container_v as Dictionary
		if int(container.get("group", 0)) != int(group_block.get("id", 0)):
			continue
		for package_v: Variant in container.get("packages", []) as Array:
			if not (package_v is Dictionary):
				continue
			var package: Dictionary = package_v as Dictionary
			if int(package.get("switch", -1)) != value_id:
				continue
			for media_v: Variant in package.get("media", []) as Array:
				out[int(media_v)] = true
	var ids: Array = out.keys()
	ids.sort()
	return ids


## Current switch/state/RTPC values, for QA and the wave report.
func state() -> Dictionary:
	var switches: Dictionary = {}
	for gid_v: Variant in _switch_state.keys():
		var gid: int = int(gid_v)
		var names: Dictionary = _switch_value_names.get(gid, {})
		switches[str(names.get(int(_switch_state[gid]), str(gid)))] = switch_name_for(gid)
	var states: Dictionary = {}
	for gid_v: Variant in _state_state.keys():
		var gid: int = int(gid_v)
		var names: Dictionary = _state_value_names.get(gid, {})
		states[str(names.get(int(_state_state[gid]), str(gid)))] = state_name_for(gid)
	var rtpcs: Dictionary = {}
	for rid_v: Variant in _rtpc_state.keys():
		var rid: int = int(rid_v)
		var row: Dictionary = _rtpc_by_id.get(rid, {})
		var key: String = str(row.get("name", str(rid)))
		rtpcs[key] = float(_rtpc_state[rid])
	return {
		"loaded": _loaded,
		"degraded_reason": _reason,
		"switch_groups": switch_group_count(),
		"state_groups": state_group_count(),
		"rtpcs": rtpc_count(),
		"switches": switches,
		"states": states,
		"rtpc_values": rtpcs,
		"curves": curve_report(),
	}


## The authored node (Type:Id) of the first curve for [param param] whose type
## matches [param type_prefix] (e.g. "MusicRandomSequenceContainer"). Lets a
## caller bind a curve by node type without inventing a binding; "" when none.
func curve_node_for_type(name: Variant, param: String, type_prefix: String) -> String:
	var row: Dictionary = _find_rtpc(name)
	if row.is_empty():
		return ""
	for curve_v: Variant in row.get("curves", []) as Array:
		if not (curve_v is Dictionary):
			continue
		var curve: Dictionary = curve_v as Dictionary
		if str(curve.get("param", "")) != param:
			continue
		for node_v: Variant in curve.get("nodes", []) as Array:
			var node: String = str(node_v)
			if node.begins_with(type_prefix + ":"):
				return node
	return ""


## Group name for an id, for reporting an unnamed (id-only) group as its id.
func switch_name_for(group_id: int) -> String:
	var block: Dictionary = _switch_by_id.get(group_id, {})
	var name: String = str(block.get("name", ""))
	return name if not name.is_empty() else str(group_id)


func state_name_for(group_id: int) -> String:
	var block: Dictionary = _state_by_id.get(group_id, {})
	var name: String = str(block.get("name", ""))
	return name if not name.is_empty() else str(group_id)


## ---------------------------------------------------------------------------
## Internals
## ---------------------------------------------------------------------------
func _find_switch_group(group: Variant) -> Dictionary:
	if group is int:
		var by_id: Variant = _switch_by_id.get(int(group), null)
		return (by_id as Dictionary) if by_id is Dictionary else {}
	if group is float:
		var by_id_f: Variant = _switch_by_id.get(int(group), null)
		return (by_id_f as Dictionary) if by_id_f is Dictionary else {}
	var key: String = str(group).strip_edges()
	if key.is_valid_int():
		var by_num: Variant = _switch_by_id.get(int(key), null)
		if by_num is Dictionary:
			return by_num as Dictionary
	var by_name: Variant = _switch_by_name.get(key.to_lower(), null)
	return (by_name as Dictionary) if by_name is Dictionary else {}


func _find_state_group(group: Variant) -> Dictionary:
	if group is int:
		var by_id: Variant = _state_by_id.get(int(group), null)
		return (by_id as Dictionary) if by_id is Dictionary else {}
	if group is float:
		var by_id_f: Variant = _state_by_id.get(int(group), null)
		return (by_id_f as Dictionary) if by_id_f is Dictionary else {}
	var key: String = str(group).strip_edges()
	if key.is_valid_int():
		var by_num: Variant = _state_by_id.get(int(key), null)
		if by_num is Dictionary:
			return by_num as Dictionary
	var by_name: Variant = _state_by_name.get(key.to_lower(), null)
	return (by_name as Dictionary) if by_name is Dictionary else {}


func _find_rtpc(name: Variant) -> Dictionary:
	if name is int:
		var by_id: Variant = _rtpc_by_id.get(int(name), null)
		return (by_id as Dictionary) if by_id is Dictionary else {}
	if name is float:
		var by_id_f: Variant = _rtpc_by_id.get(int(name), null)
		return (by_id_f as Dictionary) if by_id_f is Dictionary else {}
	var key: String = str(name).strip_edges()
	if key.is_valid_int():
		var by_num: Variant = _rtpc_by_id.get(int(key), null)
		if by_num is Dictionary:
			return by_num as Dictionary
	var by_name: Variant = _rtpc_by_name.get(key.to_lower(), null)
	return (by_name as Dictionary) if by_name is Dictionary else {}


func _resolve_switch_value(block: Dictionary, value: Variant) -> int:
	var gid: int = int(block.get("id", 0))
	var names: Dictionary = _switch_values.get(gid, {})
	var ids: Dictionary = _switch_value_names.get(gid, {})
	if value is int or value is float:
		var numeric: int = int(value)
		return numeric if ids.has(numeric) else 0
	var key: String = str(value).strip_edges()
	if key.is_valid_int():
		var numeric_key: int = int(key)
		if ids.has(numeric_key):
			return numeric_key
	return int(names.get(key.to_lower(), 0))


func _resolve_state_value(block: Dictionary, value: Variant) -> int:
	var gid: int = int(block.get("id", 0))
	var names: Dictionary = _state_values.get(gid, {})
	var ids: Dictionary = _state_value_names.get(gid, {})
	if value is int or value is float:
		var numeric: int = int(value)
		return numeric if ids.has(numeric) else 0
	var key: String = str(value).strip_edges()
	if key.is_valid_int():
		var numeric_key: int = int(key)
		if ids.has(numeric_key):
			return numeric_key
	return int(names.get(key.to_lower(), 0))


## Best authored curve for (rtpc, param): the named node's curve when given,
## otherwise the curve carried by the most nodes (tie -> first authored row).
func _find_curve(name: Variant, param: String, node: String) -> Dictionary:
	var row: Dictionary = _find_rtpc(name)
	if row.is_empty():
		return {}
	var best: Dictionary = {}
	var best_nodes: int = -1
	for curve_v: Variant in row.get("curves", []) as Array:
		if not (curve_v is Dictionary):
			continue
		var curve: Dictionary = curve_v as Dictionary
		if str(curve.get("param", "")) != param:
			continue
		var nodes: Array = curve.get("nodes", []) as Array
		if not node.is_empty() and nodes.has(node):
			return curve
		if nodes.size() > best_nodes:
			best = curve
			best_nodes = nodes.size()
	return best


func _point_x(point: Variant) -> float:
	if point is Array and (point as Array).size() >= 2:
		return float((point as Array)[0])
	return 0.0


func _point_y(point: Variant) -> float:
	if point is Array and (point as Array).size() >= 2:
		return float((point as Array)[1])
	return 0.0
