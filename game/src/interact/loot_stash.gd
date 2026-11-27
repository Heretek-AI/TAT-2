extends RefCounted
## Authored loot stash model (W7S-S2).
##
## The 57 BP_LootStashInteractable_Secret_ThinWall markers are already spawned
## as loot_container triggers (their meshes are level geometry). This class
## owns the deposit rule the container calls:
##   * "Deposit All Loot": every carried non-quest entry moves to the run's
##     stashed value at once;
##   * quest items are never depositable (they stay carried);
##   * each stash is one-use (port policy; no uses count is authored);
##   * the authored prompts are PromptStashDepositLoot / PromptStashNoLoot /
##     PromptStashUse, with PromptStashUsesRemaining for the remaining count.
##
## Stashed value is always kept at the end of a match (escape or capture); the
## carried haul follows the binary keep rule in loot_inventory.gd.
##
## SFX/VFX: the capture authors Ability.Stash.Use and the GC_LootStashDeposit /
## GC_LootStashDepositFinish cues, but the extracted audio library has no
## resolved media for them, so no sound is invented. `deposit_feedback` is the
## single wiring point for a future audio/VFX pass; tests install a spy to
## prove the hook fires exactly once per successful deposit.

const LootInventoryScript := preload("res://src/interact/loot_inventory.gd")

const FALLBACK_DEPOSIT_ALL := "Deposit All Loot"
const FALLBACK_NO_LOOT := "No Loot To Deposit"
const FALLBACK_STASH_USE := "Open Stash"
const FALLBACK_USES_REMAINING := "{Num} Uses Remaining"

## Called as deposit_feedback.call(host: Node, pos: Vector3, deposited: int)
## after a successful deposit. Empty by default (no invented media).
static var deposit_feedback: Callable = Callable()

## Incremented on every successful deposit; the suite uses it to prove the
## hook fires once even if a second interact arrives in the same frame.
static var deposit_count: int = 0


static func _prompts() -> Dictionary:
	var prompts: Variant = LootInventoryScript.settings().get("prompts", {})
	return prompts as Dictionary if prompts is Dictionary else {}


static func prompt_deposit_all() -> String:
	var text: String = str(_prompts().get("PromptStashDepositLoot", ""))
	return text if text != "" else FALLBACK_DEPOSIT_ALL


static func prompt_no_loot() -> String:
	var text: String = str(_prompts().get("PromptStashNoLoot", ""))
	return text if text != "" else FALLBACK_NO_LOOT


static func prompt_use() -> String:
	var text: String = str(_prompts().get("PromptStashUse", ""))
	return text if text != "" else FALLBACK_STASH_USE


static func uses_remaining_text(uses_left: int) -> String:
	var text: String = str(_prompts().get("PromptStashUsesRemaining", ""))
	if text == "":
		text = FALLBACK_USES_REMAINING
	return text.replace("{Num}", str(maxi(uses_left, 0)))


static func default_uses() -> int:
	var stash: Variant = LootInventoryScript.settings().get("stash", {})
	if stash is Dictionary:
		return maxi(int((stash as Dictionary).get("uses_per_stash", 1)), 0)
	return 1


## Interact prompt for one stash instance.
static func prompt_for(uses_left: int, can_deposit: bool) -> String:
	if uses_left <= 0:
		return "[F] %s" % prompt_use()
	if not can_deposit:
		return "[F] %s" % prompt_no_loot()
	return "[F] %s" % prompt_deposit_all()


## Deposit every carried non-quest entry. `uses_left` is the per-stash count
## (1 by default); a successful deposit consumes one use. Returns
## {ok, reason, deposited, deposited_value, uses_left, stashed_value, prompt}.
static func deposit_all(host: Node = null, uses_left: int = -1) -> Dictionary:
	var uses: int = uses_left if uses_left >= 0 else default_uses()
	var out: Dictionary = {
		"ok": false,
		"reason": "",
		"deposited": 0,
		"deposited_value": 0,
		"uses_left": uses,
		"stashed_value": maxi(GameState.stashed_loot_value, 0),
		"prompt": "",
	}
	if uses <= 0:
		out["reason"] = "spent"
		out["prompt"] = prompt_use()
		return out
	if not LootInventoryScript.has_depositable():
		# Distinguish "nothing carried" from "only contract relics": both
		# decline, but the reason is useful to the container/HUD and the suite.
		if not GameState.carried_loot.is_empty():
			out["reason"] = "quest_only"
		else:
			out["reason"] = "no_loot"
		out["prompt"] = prompt_no_loot()
		return out

	var kept_items: Array[Dictionary] = []
	var deposited_value: int = 0
	var deposited_count: int = 0
	for entry_v: Variant in GameState.carried_loot:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v as Dictionary
		if bool(entry.get("is_quest_item", false)):
			# Quest items are contract relics: never depositable.
			kept_items.append(entry)
			continue
		deposited_value += maxi(int(entry.get("value", 0)), 0)
		deposited_count += 1
	if deposited_count == 0:
		out["reason"] = "quest_only"
		out["prompt"] = prompt_no_loot()
		return out

	GameState.carried_loot = kept_items
	GameState.carried_tracking_active = true
	GameState.stashed_loot_value = maxi(GameState.stashed_loot_value, 0) + deposited_value
	GameState.notify_carried_loot_changed()
	GameState.notify_stash_changed()

	var left: int = maxi(uses - 1, 0)
	out["ok"] = true
	out["deposited"] = deposited_count
	out["deposited_value"] = deposited_value
	out["uses_left"] = left
	out["stashed_value"] = GameState.stashed_loot_value
	out["prompt"] = prompt_for(left, false)
	deposit_count += 1
	_emit_feedback(host, deposited_count)
	# W11-A: authored Player/StashInteract/StoringLoot line. Best-effort: the
	# deposit itself already succeeded, so a missing audio manager is not an
	# error path here.
	_vo_stash(host)
	return out


## W11-A stash VO (see VoDirector.EVENT_CUES["stash_deposit"]).
static func _vo_stash(host: Node) -> void:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var am: Node = (loop as SceneTree).root.get_node_or_null("AudioManager")
	if am == null or not am.has_method("play_vo_cue"):
		return
	var pos: Variant = null
	if host is Node3D and (host as Node3D).is_inside_tree():
		pos = (host as Node3D).global_position
	am.call("play_vo_cue", "stash_deposit", pos)


## SFX/VFX wiring point. No authored media resolves today, so the default
## implementation is deliberately silent; a later audio pass assigns
## loot_stash.deposit_feedback without touching gameplay code.
static func _emit_feedback(host: Node, deposited: int) -> void:
	if not deposit_feedback.is_valid():
		return
	var pos: Vector3 = Vector3.ZERO
	var node3d := host as Node3D
	if node3d != null:
		pos = node3d.global_position
	deposit_feedback.call(host, pos, deposited)


static func reset_for_test() -> void:
	deposit_feedback = Callable()
	deposit_count = 0
