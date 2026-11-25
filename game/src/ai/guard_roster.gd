extends RefCounted
## Authored guard roster (RE-I-07): the seven guard spawn buckets.
##
## Shipped assets: `extracted/json/Missions/Spawners/Buckets/*.json`, class
## `TATActorSpawnBucketAsset`, one `Entries[].ClassToSpawn` per row. The port
## spawns one node type and picks lantern/key by spawn index
## (`mission_controller.gd:3543-3572`), so the KeyHolder never exists, the
## Hauntstable never appears, and the Bouncer sense row is unreachable.
##
## DATA CONTRACT (the half that is BLOCKED-ON T01)
## `spawners.json` currently carries the four map-spawner buckets
## (`tools/parse_spawners.py:BUCKET_KIND`: bottles, ammo, health, civilians).
## It must also emit, for each of the seven guard buckets:
##   "guard_buckets": [ { "bucket": "DA_SpawnBucket_KeyHolder",
##                        "classes": ["/Game/Character/Guards/BP_..._C"] }, ... ]
## and the level placement side must bind a marker to a bucket (the binding lives
## on the level actor's `TATSpawnerComponent`, which the level dump does not
## carry -- see the report note for T09). Until then AUTHORED_BUCKETS below is
## the documented contract and `roster_class()` is the seam the spawner calls:
## passing a bucket class (or a bucket name) selects the authored row; passing
## nothing keeps today's behaviour and reports `source="unbound"`, so the caller
## can log that the roster is not being driven.
##
## Why the AI owns this table: the bucket decides the *sense profile*, the
## animation set and the carried key, all of which are guard_ai inputs. Spawning
## the right node is mission_controller's half (BLOCKED-ON T10).

const PROFILE_GUARDBASE := "guardbase"
const PROFILE_BOUNCER := "bouncer"
const PROFILE_HAUNTSTABLE := "hauntstable"

## Weapon tokens accepted by animation_library.setup(): "club", "lantern",
## "hauntstable". Every non-Hauntstable guard reuses the club/ClubLantern sets.
const WEAPON_CLUB := "club"
const WEAPON_LANTERN := "lantern"
const WEAPON_HAUNTSTABLE := "hauntstable"

## Guard body GLBs (same paths guard_ai resolved by name before).
const MODEL_ENFORCER := "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/Dyn/SK_GuardEnforcer_Dyn__Body.glb"
const MODEL_SECURITY := "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Security/SK_GuardSecurity_01_Body.glb"
const MODEL_HAUNTSTABLE := "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Hauntstable/SK_Hauntstable__Body.glb"

## Authored patrol speed per guard class. DA_AIStatesToSpeed_Hauntstable authors
## one Neutral row at 75 cm/s (the Hauntstable's slow patrol); guards use
## DA_AIStatesToSpeed_Guard 150/170. Reported, not forced: guard_ai keeps its
## exports and the spawner may override.
const PATROL_SPEED_GUARD_M_S := 1.5
const PATROL_SPEED_HAUNTSTABLE_M_S := 0.75

## The seven authored guard buckets, transcribed from the seven bucket JSONs.
## `classes` are the `ClassToSpawn` asset paths with the `_C` suffix kept.
const AUTHORED_BUCKETS: Dictionary = {
	"DA_SpawnBucket_KeyHolder": {
		"classes": ["/Game/Character/Guards/BP_GuardSecurity_KeyHolder.BP_GuardSecurity_KeyHolder_C"],
		"profile": PROFILE_GUARDBASE,
		"weapon": WEAPON_CLUB,
		"model": MODEL_SECURITY,
		"lantern": false,
		"carries_key": true,
	},
	"DA_SpawnBucket_Hauntstable": {
		"classes": ["/Game/Character/Guards/BP_Hauntstable.BP_Hauntstable_C"],
		"profile": PROFILE_HAUNTSTABLE,
		"weapon": WEAPON_HAUNTSTABLE,
		"model": MODEL_HAUNTSTABLE,
		"lantern": false,
		"carries_key": false,
	},
	"DA_SpawnBucket_PrivateSecurity": {
		"classes": ["/Game/Character/Guards/BP_GuardSecurity_Club.BP_GuardSecurity_Club_C"],
		"profile": PROFILE_GUARDBASE,
		"weapon": WEAPON_CLUB,
		"model": MODEL_SECURITY,
		"lantern": false,
		"carries_key": false,
	},
	"DA_SpawnBucket_PrivateSecurity_Lanterns": {
		"classes": ["/Game/Character/Guards/BP_GuardSecurity_ClubLantern.BP_GuardSecurity_ClubLantern_C"],
		"profile": PROFILE_GUARDBASE,
		"weapon": WEAPON_LANTERN,
		"model": MODEL_SECURITY,
		"lantern": true,
		"carries_key": false,
	},
	"DA_SpawnBucket_StandardGuards_Bouncers": {
		"classes": [
			"/Game/Character/Guards/BP_GuardEnforcer_Club.BP_GuardEnforcer_Club_C",
			"/Game/Character/Guards/BP_GuardEnforcer_ClubB.BP_GuardEnforcer_ClubB_C",
		],
		"profile": PROFILE_BOUNCER,
		"weapon": WEAPON_CLUB,
		"model": MODEL_ENFORCER,
		"lantern": false,
		"carries_key": false,
	},
	"DA_SpawnBucket_StandardGuards_Lanterns": {
		"classes": [
			"/Game/Character/Guards/BP_GuardEnforcer_ClubLantern.BP_GuardEnforcer_ClubLantern_C",
			"/Game/Character/Guards/BP_GuardEnforcer_ClubLanternB.BP_GuardEnforcer_ClubLanternB_C",
		],
		"profile": PROFILE_GUARDBASE,
		"weapon": WEAPON_LANTERN,
		"model": MODEL_ENFORCER,
		"lantern": true,
		"carries_key": false,
	},
	"DA_SpawnBucket_StandardGuards_PrivateSecurity_JasperingHall_Lantern": {
		"classes": [
			"/Game/Character/Guards/BP_GuardSecurity_JasperingHall_ClubLantern.BP_GuardSecurity_JasperingHall_ClubLantern_C",
			"/Game/Character/Guards/BP_GuardSecurity_JasperingHall_ClubLanternB.BP_GuardSecurity_JasperingHall_ClubLanternB_C",
		],
		"profile": PROFILE_GUARDBASE,
		"weapon": WEAPON_LANTERN,
		"model": MODEL_SECURITY,
		"lantern": true,
		"carries_key": false,
	},
}

## Fallback row for a guard with no bucket: no profile, no weapon/model override,
## so the legacy name heuristic stays in charge and `source` is "unbound" so the
## caller can report the gap. (A profile here would silently disable the
## heuristic: `Guard_Bouncer_1` must still resolve to the Bouncer row.)
const UNBOUND_ROW: Dictionary = {
	"bucket": "",
	"classes": [],
	"profile": "",
	"weapon": "",
	"model": "",
	"lantern": false,
	"carries_key": false,
}

## Map id -> the stolen-key id the KeyHolder carries (GameState key ids; the
## mission controller's key pool names). Guildhall is the shipped "steal the
## constable's key" loop (RE-I-13).
const MAP_KEY_ID: Dictionary = {
	"guildhall": "key_guildhall",
	"old_manor": "key_manor",
}
const DEFAULT_KEY_ID := "key_vault"

static var _json_buckets: Dictionary = {}
static var _json_loaded: bool = false


static func _load_json_buckets() -> void:
	if _json_loaded:
		return
	_json_loaded = true
	if not FileAccess.file_exists("res://data/generated/gameplay/spawners.json"):
		return
	var f: FileAccess = FileAccess.open("res://data/generated/gameplay/spawners.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	var rows_v: Variant = (parsed as Dictionary).get("guard_buckets", [])
	if not (rows_v is Array):
		return
	for row_v: Variant in (rows_v as Array):
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		var bucket: String = str(row.get("bucket", ""))
		if bucket != "":
			_json_buckets[bucket] = row


## True when the producer emits the seven guard buckets.
static func produced() -> bool:
	_load_json_buckets()
	return _json_buckets.size() > 0


## Bucket names the producer emitted (empty when the data half is missing).
static func produced_buckets() -> Array[String]:
	_load_json_buckets()
	var out: Array[String] = []
	for k: Variant in _json_buckets.keys():
		out.append(str(k))
	return out


## Authored roster row for a bucket name or a bucket-class path. Returns
## UNBOUND_ROW (plus `source="unbound"`) when nothing matches.
static func roster_for(bucket_or_class: String) -> Dictionary:
	var key: String = bucket_or_class.strip_edges()
	if key == "":
		return unbound_row("empty")
	_load_json_buckets()
	var bucket: String = key
	if not AUTHORED_BUCKETS.has(bucket):
		bucket = ""
		for name: Variant in AUTHORED_BUCKETS.keys():
			var classes_v: Variant = (AUTHORED_BUCKETS[name] as Dictionary).get("classes", [])
			for c_v: Variant in (classes_v as Array):
				if _class_matches(key, str(c_v)):
					bucket = str(name)
					break
			if bucket != "":
				break
	if bucket == "":
		for name: Variant in _json_buckets.keys():
			var classes_v: Variant = (_json_buckets[name] as Dictionary).get("classes", [])
			for c_v: Variant in (classes_v as Array):
				if _class_matches(key, str(c_v)):
					bucket = str(name)
					break
			if bucket != "":
				break
	if bucket == "":
		return unbound_row(key)
	var out: Dictionary = (AUTHORED_BUCKETS.get(bucket, {}) as Dictionary).duplicate(true)
	var json_row: Dictionary = _json_buckets.get(bucket, {}) as Dictionary
	for k: Variant in json_row.keys():
		if k == "bucket" or k == "classes":
			continue
		out[str(k)] = json_row[k]
	out["bucket"] = bucket
	if not out.has("classes"):
		out["classes"] = (json_row.get("classes", []) as Array).duplicate()
	out["source"] = "authored" if not json_row.is_empty() else "contract"
	return out


## "unbound" row carrying the requested key so a log says what was ignored.
static func unbound_row(requested: String) -> Dictionary:
	var out: Dictionary = UNBOUND_ROW.duplicate(true)
	out["requested"] = requested
	out["source"] = "unbound"
	return out


## UE class paths may arrive with or without the `_C` suffix and with a
## `/Game/...` or bare-name spelling; compare the trailing object name only.
static func _class_matches(a: String, b: String) -> bool:
	var na: String = a.split("/")[-1].split(".")[-1].trim_suffix("_C")
	var nb: String = b.split("/")[-1].split(".")[-1].trim_suffix("_C")
	return na != "" and na.to_lower() == nb.to_lower()


## Authored carried-key id for a guard, or "" when the roster says it carries
## none. `map_id` selects the map's key (Guildhall Key / Elway Manor Key).
static func carried_key_id(row: Dictionary, map_id: String) -> String:
	if row.get("carries_key", false) != true:
		return ""
	return str(MAP_KEY_ID.get(map_id.to_lower(), DEFAULT_KEY_ID))


## Display name of the carried key for the pickpocket prompt.
static func carried_key_name(key_id: String) -> String:
	match key_id:
		"key_guildhall":
			return "Guildhall Key"
		"key_manor":
			return "Elway Manor Key"
		"key_vault":
			return "Vault Key"
	return "Key"


## Authored patrol speed for a roster row.
static func patrol_speed_m_s(row: Dictionary) -> float:
	if str(row.get("profile", "")) == PROFILE_HAUNTSTABLE:
		return PATROL_SPEED_HAUNTSTABLE_M_S
	return PATROL_SPEED_GUARD_M_S
