extends RefCounted
class_name ParityGovernance
## P0b parity-only governance (`TAT2_PARITY_ONLY=1`, default off).
##
## One place classifies every TAT-2 addition:
##   * `parity_restoration` — replaces a port placeholder with shipped authored
##     data (the graybox -> authored-material rules). Applied in both modes.
##   * `tat2_expansion` — new content or a TAT-2 overlay (prep skyline, Spider
##     personal quest, co-op transport, briefing overrides, expansion nodes and
##     any future expansion content rule). Excluded in parity-only, counted with
##     a diagnostic, never a crash.
##
## The tracked table `game/data/expansion/content_overrides.json` carries the
## class on every rule; `tools/parse_tables.py` and
## `tools/check_content_overrides.py` fail closed on a missing/unknown class.
## This script is the runtime mirror:
##   * `level_loader.gd` asks `mesh_decision()` for every tagged mesh entry;
##   * `mission_prep_ui.gd`, `game_data.gd`, `personal_quest.gd` and
##     `net_manager.gd` ask `record_allowed()` / the matching helper for their
##     expansion record or node kind.
##
## Default-off contract: `enabled()` is false unless the environment value is
## one of 1/true/yes/on (case-insensitive). Every gate then returns the shipped
## path, so the flag cannot change behaviour when it is absent.
##
## Contract test: `game/tests/test_parity_only.gd` (standalone).
## Producer gate: `tools/check_content_overrides.py` (+ `make audit`).

const ENV_FLAG: String = "TAT2_PARITY_ONLY"
const PARITY_RESTORATION: String = "parity_restoration"
const TAT2_EXPANSION: String = "tat2_expansion"
const PARITY_CLASSES: Array[String] = [PARITY_RESTORATION, TAT2_EXPANSION]
const CONTENT_OVERRIDES_PATH: String = "res://data/expansion/content_overrides.json"

## Tracked TAT-2 expansion records that are whole files. A parity-only build
## must not read or emit any of them. `owner` is the reader that consults
## `record_allowed()`; the standalone test asserts the file exists and names
## this script so the registry cannot rot silently.
const EXPANSION_RECORDS := [
	{
		"kind": "prep_skyline",
		"path": "res://data/expansion/prep_skyline.json",
		"owner": "res://src/ui/mission_prep_ui.gd",
	},
	{
		"kind": "personal_spider",
		"path": "res://data/expansion/personal_spider.json",
		"owner": "res://src/quests/personal_quest.gd",
	},
	{
		"kind": "briefing_overrides",
		"path": "res://data/expansion/briefing_overrides.json",
		"owner": "res://src/core/game_data.gd",
	},
	{
		"kind": "coop_provenance",
		"path": "res://data/expansion/coop_provenance.json",
		"owner": "res://src/core/net_manager.gd",
	},
]

## TAT-2 node kinds placed by the runtime (not shipped art). `candle_flame` is
## the procedural wick quad in `level_loader.gd` / `vfx_manager.gd`; the cooked
## candle meshes carry no wick socket, so the quad is port content.
const EXPANSION_NODE_KINDS: Array[String] = ["candle_flame"]


## True only for the documented on-values. Empty / "0" / anything else is off.
static func env_truthy(value: String) -> bool:
	match value.strip_edges().to_lower():
		"1", "true", "yes", "on":
			return true
	return false


## Default-off switch. Read on every call so tests and capture scripts can
## toggle it in-process with OS.set_environment().
static func enabled() -> bool:
	return env_truthy(OS.get_environment(ENV_FLAG))


static func is_parity_class(value: String) -> bool:
	return value in PARITY_CLASSES


## A class is applied only when the flag is off, or when it is a restoration.
static func class_allowed(parity_class: String, parity_only: bool) -> bool:
	if not parity_only:
		return true
	return parity_class == PARITY_RESTORATION


## Runtime mirror of the producer's per-rule filter.
static func rule_applies(rule: Dictionary) -> bool:
	return class_allowed(str(rule.get("parity_class", "")), enabled())


## True when a whole tracked expansion record may be read. Non-registry paths
## are allowed (this registry is the exhaustive list of TAT-2 expansion files).
static func record_allowed(path: String) -> bool:
	return record_allowed_for(path, enabled())


static func record_allowed_for(path: String, parity_only: bool) -> bool:
	if not parity_only:
		return true
	return expansion_record_kind(path) == ""


## The registered expansion kind for a path, or "" when it is not expansion.
static func expansion_record_kind(path: String) -> String:
	for rec: Dictionary in EXPANSION_RECORDS:
		if str(rec.get("path", "")) == path:
			return str(rec.get("kind", ""))
	return ""


## Runtime-placed TAT-2 nodes (candle flames) are excluded wholesale.
static func expansion_nodes_allowed() -> bool:
	return not enabled()


static func expansion_node_kind_allowed(kind: String) -> bool:
	if not enabled():
		return true
	return not (kind in EXPANSION_NODE_KINDS)


## The TAT-2 ENet transport is invented content; a parity-only run is solo.
static func coop_transport_allowed() -> bool:
	return not enabled()


## Tracked rule id -> parity_class. Missing table yields {} and every tagged
## mesh becomes "unclassified" in parity-only, i.e. skipped with a count.
static func load_rule_classes() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(CONTENT_OVERRIDES_PATH):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_OVERRIDES_PATH))
	if not (parsed is Dictionary):
		return out
	var table: Dictionary = parsed as Dictionary
	for key: String in ["rules", "add_caps"]:
		var rows: Variant = table.get(key, [])
		if not (rows is Array):
			continue
		for rv: Variant in rows as Array:
			if not (rv is Dictionary):
				continue
			var rec: Dictionary = rv as Dictionary
			out[str(rec.get("id", ""))] = str(rec.get("parity_class", ""))
	return out


## Decide one `.tatlevel.json` mesh entry. `content_rule` is the producer tag;
## `content_parity_class` is preferred when present (new data) and the tracked
## table is the fallback (data regenerated before P0b). In parity-only anything
## that is not a restoration is skipped: tat2_expansion by label, unknown by
## fail-closed.
static func mesh_decision(entry: Dictionary, rule_classes: Dictionary, parity_only: bool) -> Dictionary:
	var rid: String = str(entry.get("content_rule", ""))
	if rid == "":
		return {"skip": false, "parity_class": "", "reason": ""}
	var parity_class: String = str(entry.get("content_parity_class", ""))
	if parity_class == "":
		parity_class = str(rule_classes.get(rid, ""))
	if not parity_only:
		return {"skip": false, "parity_class": parity_class, "reason": ""}
	if parity_class == PARITY_RESTORATION:
		return {"skip": false, "parity_class": parity_class, "reason": ""}
	return {
		"skip": true,
		"parity_class": parity_class,
		"reason": "tat2_expansion" if parity_class == TAT2_EXPANSION else "unclassified",
	}


## Filter one level payload's mesh list against the rule classes. Only `meshes`
## is replaced (shallow copy): markers, guard_spawn_meta, GC/loot records and
## every other payload key are returned untouched. Counts are returned for the
## caller's diagnostic. This is the exact contract `level_loader.gd` applies
## per entry, exposed so the standalone test can prove non-mesh records survive.
static func filter_level_payload(payload: Dictionary, rule_classes: Dictionary, parity_only: bool) -> Dictionary:
	var out: Dictionary = payload.duplicate(false)
	var result: Dictionary = {
		"payload": out,
		"skipped": 0,
		"skipped_caps": 0,
		"by_rule": {},
		"by_reason": {},
	}
	if not parity_only:
		return result
	var kept: Array = []
	var by_rule: Dictionary = result["by_rule"]
	var by_reason: Dictionary = result["by_reason"]
	var skipped: int = 0
	var skipped_caps: int = 0
	var src: Array = payload.get("meshes", []) as Array
	for mv: Variant in src:
		if not (mv is Dictionary):
			kept.append(mv)
			continue
		var entry: Dictionary = mv as Dictionary
		var decision: Dictionary = mesh_decision(entry, rule_classes, true)
		if not bool(decision.get("skip", false)):
			kept.append(mv)
			continue
		skipped += 1
		if bool(entry.get("content_cap", false)):
			skipped_caps += 1
		var rid: String = str(entry.get("content_rule", ""))
		by_rule[rid] = int(by_rule.get(rid, 0)) + 1
		var reason: String = str(decision.get("reason", "unclassified"))
		by_reason[reason] = int(by_reason.get(reason, 0)) + 1
	out["meshes"] = kept
	result["skipped"] = skipped
	result["skipped_caps"] = skipped_caps
	return result
