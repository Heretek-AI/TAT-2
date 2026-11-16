extends Node
## Atomic JSON save system (mirrors TATAtomicSave): XP, level, completed contracts, settings.

const SAVE_PATH := "user://tat2_save.json"
const TMP_PATH := "user://tat2_save.json.tmp"

var data: Dictionary = {
	"xp": 0,
	"level": 1,
	"completed_contracts": {},
	"unlocked_tools": ["blackjack", "slithersap", "smoke_bomb", "pickpocket_fairy"],
	"settings": {
		"mouse_sensitivity": 0.0025,
		"sprint_toggle": false,
		"fov": 75.0,
	}
}


func _ready() -> void:
	load_save()


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		data.merge(parsed, true)


func write_save() -> void:
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.rename("tat2_save.json.tmp", "tat2_save.json")


func record_contract_complete(order: int, score: int, ghost: bool) -> void:
	var k := str(order)
	var prev: Dictionary = data["completed_contracts"].get(k, {})
	data["completed_contracts"][k] = {
		"best_score": maxi(int(prev.get("best_score", 0)), score),
		"ghost": bool(prev.get("ghost", false)) or ghost,
	}
	data["xp"] = int(data["xp"]) + maxi(100, score / 2)
	write_save()
