extends RefCounted
## Shared map -> sublevel resolution and review bookmarks.
##
## Resolution MUST stay in one place: the baker, the in-game review mode and
## the editor dock all call `resolve_sublevels()`, which in turn calls
## `MissionController._map_id_to_sublevels()` — the same function the shipped
## game uses. No second map table is maintained here.
##
## `MissionController` has no entry for menus (MissionLobby is staged by
## main_menu, not by a mission), so when that call returns nothing this script
## falls back to a *discovery* rule: find
## `res://data/generated/levels/<dir>` whose normalised name matches the map id
## and collect its `<dir>_*.tatlevel.json` files (`_P` first). That is a scan,
## not a duplicated table, and the manifest records which path was used.

const LEVELS_ROOT: String = "res://data/generated/levels"
const MISSION_CONTROLLER_SCRIPT: String = "res://src/missions/mission_controller.gd"

## Camera-eye bookmark positions with a look target. Sources are cited per
## entry; heights are the authored player-start / capture base + 1.7 m eye
## height unless the source is already an eye pose (KF16).
const BOOKMARKS: Dictionary = {
	"guildhall": [
		{
			"name": "KF16_Gate",
			"pos": Vector3(13.0, 19.2, 75.8),
			"target": Vector3(16.0, 23.0, 48.7),
			"source": "build/qa/capture_zipwire_hang.gd KF16 street pose",
		},
		{
			"name": "Foyer",
			"pos": Vector3(22.0, 22.2, 125.3),
			"target": Vector3(22.0, 22.0, 115.0),
			"source": "build/qa/capture_guildhall_door.gd foyer pose + 1.7 m eye",
		},
		{
			"name": "Library",
			"pos": Vector3(-27.7, 28.7, -24.5),
			"target": Vector3(-27.7, 27.7, -19.0),
			"source": "Guildhall_Loot BP_Manor_Bookcase_Cabinet_MinorLoot_C_* (y=27) + 1.7 m eye",
		},
		{
			"name": "POI_Lounge",
			"pos": Vector3(18.6, 38.13, -54.2),
			"target": Vector3(18.6, 36.8, -48.0),
			"source": "Building_Guildhall_POI BP_Manor_Bookcase_Cabinet_MajorLoot_C_0 (y=36.43) + 1.7 m eye",
		},
		{
			"name": "Safe_Room",
			"pos": Vector3(127.27, 27.17, -5.33),
			"target": Vector3(118.0, 26.5, -5.33),
			"source": "Guildhall_Gameplay TATSafeRoomPlayerStart_0 (y=25.47) + 1.7 m eye",
		},
		{
			"name": "Vault",
			"pos": Vector3(14.0, 46.7, -47.5),
			"target": Vector3(14.0, 45.0, -40.0),
			"source": "Guildhall_Gameplay BP_VaultDoor_Sliding_C_0 (y=45) + 1.7 m eye",
		},
	],
	"thieves_den": [
		{
			"name": "Den_Hub",
			"pos": Vector3(5.5, 42.86, 272.0),
			"target": Vector3(5.5, 42.0, 262.0),
			"source": "ThievesDenTest_P TATPlayerStart_0 (y=41.16) + 1.7 m eye",
		},
		{
			"name": "Moon_Window",
			"pos": Vector3(12.0, 42.86, 266.8),
			"target": Vector3(5.75, 42.0, 266.8),
			"source": "den window backlight pose (level_loader _is_den_window_backlight, x=5.75)",
		},
	],
	"old_manor": [
		{
			"name": "Courtyard",
			"pos": Vector3(34.9, 11.65, 123.47),
			"target": Vector3(34.9, 11.0, 113.0),
			"source": "OldManor_Gameplay TATPlayerStart_2 (y=9.95) + 1.7 m eye",
		},
		{
			"name": "Manor_Approach",
			"pos": Vector3(5.95, 10.23, 126.03),
			"target": Vector3(5.95, 9.5, 116.0),
			"source": "OldManor_Gameplay TATPlayerStart_0 (y=8.53) + 1.7 m eye",
		},
		{
			"name": "Courtyard_West",
			"pos": Vector3(-74.29, 10.89, 120.48),
			"target": Vector3(-64.0, 10.0, 120.5),
			"source": "OldManor_Gameplay TATPlayerStart_4 (y=9.19) + 1.7 m eye",
		},
	],
	"mission_lobby": [
		{
			"name": "Lobby",
			"pos": Vector3(0.0, 2.5, 8.0),
			"target": Vector3(0.0, 1.2, 0.0),
			"source": "MissionLobby staged around the origin (BP_MatchLobbyDummyPlayer actors)",
		},
	],
}


static func resolve_sublevels(map_id: String, contract_order: int = 0) -> Dictionary:
	var out: Dictionary = {
		"map": map_id,
		"paths": [],
		"source": "",
		"warning": "",
		"contract_order": contract_order,
	}
	# Contract-specific sublevels are appended by the mission function for the
	# *active* contract. A map review wants that map's own contract row, so an
	# order of 0 means "first contract whose authored map_id is this map".
	var order: int = contract_order
	if order <= 0:
		order = _first_contract_order_for(map_id)
		out["contract_order"] = order
	# Loaded at call time (not preloaded): mission_controller.gd references the
	# GameState/GameData autoloads, which do not exist yet while a --script
	# entry point is still being compiled.
	var mc_script: Script = load(MISSION_CONTROLLER_SCRIPT) as Script
	if mc_script != null:
		var mc: Node = mc_script.new()
		var resolved: Variant = mc.call("_map_id_to_sublevels", map_id, order)
		mc.free()
		if resolved is Array:
			for p: Variant in (resolved as Array):
				var path: String = str(p)
				if path != "" and not (out["paths"] as Array).has(path):
					(out["paths"] as Array).append(path)
	if not (out["paths"] as Array).is_empty():
		out["source"] = "MissionController._map_id_to_sublevels"
		return out

	# Menu / unowned map fallback: directory discovery by normalised name.
	var dir_name: String = _find_level_dir(map_id)
	if dir_name == "":
		return out
	var prefix: String = dir_name.get_file().to_lower()
	var files: Array[String] = []
	for f: String in DirAccess.get_files_at(dir_name):
		if not f.to_lower().ends_with(".tatlevel.json"):
			continue
		if not f.to_lower().begins_with(prefix):
			continue
		files.append(dir_name.path_join(f))
	files.sort_custom(func(a: String, b: String) -> bool:
		return _sublevel_sort_key(a) < _sublevel_sort_key(b)
	)
	for f2: String in files:
		(out["paths"] as Array).append(f2)
	if not (out["paths"] as Array).is_empty():
		out["source"] = "directory-discovery"
		out["warning"] = "map id has no MissionController entry; resolved by directory scan"
	return out


static func bookmarks_for(map_id: String) -> Array:
	return (BOOKMARKS.get(map_id, []) as Array).duplicate(true)


static func _first_contract_order_for(map_id: String) -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var gd: Node = tree.root.get_node_or_null("GameData")
	if gd == null:
		return 0
	for c: Dictionary in gd.call("get_contracts"):
		if str(c.get("map_id", "")) == map_id:
			return int(c.get("order", 0))
	return 0


static func _find_level_dir(map_id: String) -> String:
	var want: String = map_id.replace("_", "").to_lower()
	var stack: Array[String] = [LEVELS_ROOT]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var base: String = dir.get_file().replace("_", "").to_lower()
		if base == want:
			return dir
		for sub: String in DirAccess.get_directories_at(dir):
			if not sub.begins_with("."):
				stack.append(dir.path_join(sub))
	return ""


static func _sublevel_sort_key(path: String) -> String:
	# Persistent level first (`*_P`), then the rest alphabetically. Prefixing
	# with "0"/"1" keeps the comparator cheap and deterministic.
	var stem: String = path.get_file().to_lower()
	var persistent: bool = stem.contains("_p.tatlevel") or stem.contains("_p_")
	return ("0_" if persistent else "1_") + stem
