extends RefCounted
## Review visibility predicates shared by the editor dock and the in-game
## review mode. A node matches when its baked `review_sublevel`,
## `review_kind`, `review_issue` or `review_role` metadata says so.
##
## Sublevel groups are token matches on the .tatlevel.json stem; there is no
## duplicated sublevel table here. `Gameplay` intentionally covers the authored
## spawner/loot/clue/contract sublevels (they are mission furniture, not
## geometry), while Landscape and the persistent level stay visible always.

const PERIPHERY_TOKENS: Array[String] = ["periphery", "skybox", "facade", "clouds", "audio"]
const POI_TOKENS: Array[String] = ["poi", "vault", "ceremonial"]
const GAMEPLAY_TOKENS: Array[String] = [
	"gameplay", "loot", "contract", "setspawners", "missionclues",
	"clue", "pickup", "teleporter", "sequencer", "pathblocker", "spawn",
]


static func matches(node: Node, toggle: String) -> bool:
	var sublevel: String = str(node.get_meta("review_sublevel", "")).to_lower()
	var kind: String = str(node.get_meta("review_kind", ""))
	var issue: String = str(node.get_meta("review_issue", ""))
	var role: String = str(node.get_meta("review_role", ""))
	match toggle:
		"Periphery":
			return has_token(sublevel, PERIPHERY_TOKENS)
		"POI":
			return has_token(sublevel, POI_TOKENS)
		"Gameplay":
			return has_token(sublevel, GAMEPLAY_TOKENS)
		"Lighting":
			return kind == "light" or kind == "fog"
		"Decals":
			return kind == "decal"
		"Collision":
			return kind == "collision" or kind == "occluder"
		"Niagara":
			return kind == "niagara"
		"Beams":
			return issue == "beam_lines"
		"World labels":
			return issue == "world_label"
		"Emissive plates":
			return issue == "emissive_plate"
		"Doors":
			return role == "door"
		"Loot":
			return role == "loot"
		"Devices":
			return role == "device"
	return false


static func has_token(text: String, tokens: Array[String]) -> bool:
	for t: String in tokens:
		if text.find(t) >= 0:
			return true
	return false


## Toggles that hide a whole sublevel or a whole node class. Doors/Loot/Devices
## are role filters on individual nodes.
static func all_toggles() -> Array[String]:
	return [
		"Periphery", "POI", "Gameplay", "Lighting", "Decals", "Collision",
		"Niagara", "Beams", "World labels", "Emissive plates",
		"Doors", "Loot", "Devices",
	]
