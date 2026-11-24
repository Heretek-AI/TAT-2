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

## Not a filter predicate: this toggle controls whether the authored
## `bHiddenInGame` fixtures (loader `visible = false`) may be revealed. It is
## kept out of `matches()` so a "show everything" sweep can never unhide them
## by accident.
const AUTHORED_HIDDEN_TOGGLE: String = "Hidden in game"


## The node's `visible` as the loader authored it, captured by the tagger.
## Nodes without the meta (synthetic fixtures, older bakes) count as visible.
static func authored_visible(node: Node) -> bool:
	if node.has_meta("review_authored_visible"):
		return bool(node.get_meta("review_authored_visible"))
	return true


## Single source of truth for review visibility:
##   visible = (authored_visible or HiddenInGame toggle) and not hidden_by_toggle
## `toggles` holds toggle name -> enabled. Missing keys mean enabled, except
## `Hidden in game`, which defaults off.
static func visible_after_toggles(node: Node, toggles: Dictionary) -> bool:
	var visible: bool = authored_visible(node)
	if not visible and bool(toggles.get(AUTHORED_HIDDEN_TOGGLE, false)):
		visible = true
	if not visible:
		return false
	for toggle: String in toggles.keys():
		if toggle == AUTHORED_HIDDEN_TOGGLE:
			continue
		if bool(toggles[toggle]):
			continue
		if matches(node, toggle):
			return false
	return true


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
## are role filters on individual nodes. `Hidden in game` is the authored
## visibility exception and is handled by `visible_after_toggles()`, not by
## `matches()`.
static func all_toggles() -> Array[String]:
	return [
		"Periphery", "POI", "Gameplay", "Lighting", "Decals", "Collision",
		"Niagara", "Beams", "World labels", "Emissive plates",
		"Doors", "Loot", "Devices", AUTHORED_HIDDEN_TOGGLE,
	]
