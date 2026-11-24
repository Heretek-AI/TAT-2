extends "res://src/ai/civilian_npc.gd"
## Stand-still personal-chain NPC for the Spider quest (W1S).
##
## Reuses the authored civilian body/head rig and idle animation from
## CivilianNPC but never wanders: a quest conversation happens where the
## producer pinned the actor. The NPC is a normal `interactables` member with a
## chest-height LOS point, the shipped `[E] Talk` prompt
## (ST_Interactables.PromptTalk) and one authored line per interaction.
##
## Beat ownership (PersonalQuest owns stage/facts; this actor only asks):
##   courier   (Guildhall Lounge)      carrying -> delivered, 03:HandedOff
##   informant (Old Manor Courtyard)   delivered -> info, 04:GotInfo,
##                                     then a later interaction closes `info`.
##
## No fact is invented, no ObjectiveComplete_* row is granted, no loot value,
## currency, contract progress or objective is touched. The first line and the
## follow-up both come from the expansion record; the follow-up is shown on the
## next interaction, never as a second page of the same panel.

const PersonalQuestScript := preload("res://src/quests/personal_quest.gd")
const NpcClueDialogueScript := preload("res://src/quests/npc_clue_dialogue.gd")

## Shipped interaction prompt for a talkable NPC (ST_Interactables.PromptTalk).
const PROMPT_TALK: String = "[E] Talk"
## Torso/chest target: the civilian origin is the floor and the body is about
## 1.7 m tall, so +1.2 m sits inside the chest for the interaction LOS ray.
const INTERACT_HEIGHT_M: float = 1.2

@export var anchor_id: String = ""
@export var thief_id: String = "spider"

var _dialogue: Node = null
## Frame of the last talk; the press that opens the panel must not immediately
## re-enter this actor after the panel closes in the same event dispatch.
var _last_talk_frame: int = -1


## Must be called before add_child (CivilianNPC.setup contract).
func setup_npc(p_anchor_id: String, p_thief_id: String, body: String, head: String, spawn: Vector3) -> void:
	anchor_id = p_anchor_id
	thief_id = p_thief_id.strip_edges() if p_thief_id.strip_edges() != "" else str(PersonalQuestScript.character_id())
	setup(body, head, spawn)
	set_meta("personal_quest_anchor", anchor_id)


func _ready() -> void:
	super._ready()
	add_to_group("interactables")
	add_to_group("personal_quest_npcs")


## Quest NPCs hold their pinned spot: gravity only, no wander, idle animation.
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_play_role("idle")
	move_and_slide()


func get_interact_prompt() -> String:
	return PROMPT_TALK


func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * INTERACT_HEIGHT_M


## Resolve one interaction against the chain. Mutates the persisted record via
## PersonalQuest (idempotent) and returns:
##   {ok, first, text, stage, previous, granted}
## `text` is the authored first line on the beat transition and the authored
## follow-up on every later interaction.
func resolve_talk() -> Dictionary:
	var stage: String = PersonalQuestScript.stage_for(thief_id)
	match anchor_id:
		"courier":
			if stage == "carrying":
				var advance: Dictionary = PersonalQuestScript.deliver_owl(thief_id)
				if bool(advance.get("ok", false)):
					return _payload(true, "delivered", advance)
			if PersonalQuestScript.stage_index(stage) >= PersonalQuestScript.stage_index("delivered"):
				return _payload(false, "delivered", {})
		"informant":
			if stage == "delivered":
				var advance2: Dictionary = PersonalQuestScript.deliver_info(thief_id)
				if bool(advance2.get("ok", false)):
					return _payload(true, "info", advance2)
			if stage == "info":
				# Follow-up closes the chain: info -> complete, no new fact.
				var closed: Dictionary = PersonalQuestScript.close_info(thief_id)
				return _payload(false, "info", closed)
			if stage == "complete":
				return _payload(false, "info", {})
	return {"ok": false, "first": false, "text": "", "stage": stage, "previous": stage, "granted": []}


func _payload(first: bool, beat_stage: String, advance: Dictionary) -> Dictionary:
	var beat: Dictionary = PersonalQuestScript.beat_for(beat_stage)
	var dialogue: Dictionary = beat.get("dialogue", {}) as Dictionary
	var text: String = str(dialogue.get("line", "")) if first else str(dialogue.get("follow_up", ""))
	return {
		"ok": text.strip_edges() != "",
		"first": first,
		"text": text,
		"stage": PersonalQuestScript.stage_for(thief_id),
		"previous": str(advance.get("previous", "")),
		"granted": advance.get("granted", []) as Array,
	}


func interact(_actor: Node) -> void:
	if not is_inside_tree():
		return
	if _dialogue_open():
		return
	if Engine.get_process_frames() == _last_talk_frame:
		return
	var payload: Dictionary = resolve_talk()
	if not bool(payload.get("ok", false)):
		return
	_last_talk_frame = Engine.get_process_frames()
	var host: Node = _find_hud()
	var dialogue: Node = _ensure_dialogue(host)
	if dialogue != null:
		dialogue.call("open", host, str(payload.get("text", "")))


func _dialogue_open() -> bool:
	return _dialogue != null and is_instance_valid(_dialogue) and bool(_dialogue.call("is_open"))


## Lazily create the modal under the HUD so it inherits the HUD CanvasLayer and
## process mode. Returns null when no HUD/host exists (headless mock calls can
## still resolve_talk() directly).
func _ensure_dialogue(host: Node) -> Node:
	if _dialogue != null and is_instance_valid(_dialogue) and _dialogue.is_inside_tree():
		return _dialogue
	if host == null:
		return null
	_dialogue = NpcClueDialogueScript.new()
	_dialogue.name = "NpcClueDialogue"
	if not _dialogue.is_connected("closed", Callable(self, "_on_dialogue_closed")):
		_dialogue.connect("closed", Callable(self, "_on_dialogue_closed"))
	host.add_child(_dialogue)
	return _dialogue


## The closing press must not re-enter the actor on the same frame even when
## the dialogue's _input happens to run before the player's.
func _on_dialogue_closed() -> void:
	_last_talk_frame = Engine.get_process_frames()


## Same HUD lookup the loot containers and doors use: mission.hud first, then
## the "hud" group.
func _find_hud() -> Node:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	var mission: Node = tree.get_first_node_in_group("mission")
	if mission != null:
		var h_v: Variant = mission.get("hud")
		if h_v is Node and is_instance_valid(h_v as Node):
			return h_v as Node
	var h_group: Node = tree.get_first_node_in_group("hud")
	if h_group != null and is_instance_valid(h_group):
		return h_group
	return null
