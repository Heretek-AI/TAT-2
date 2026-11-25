extends SceneTree
## W6U2 focused truth test: authored Black Market catalog, KF07/KF08 Ledger,
## KF03/KF04 Wardrobe and the one-time save-id migration.
##
## Run:
##   XDG_DATA_HOME=/tmp/opencode/w6u2-data tools/godot --headless --path game \
##     --script res://tests/test_w6u2_catalog.gd
##
## What is pinned:
##   * unlocks.json carries 68 rows in four authored columns (7 tools, 7 guild
##     perks, 28 Spider cosmetics, 26 Chameleon cosmetics), 55 authored prices,
##     68 unique save ids and 68 resolvable authored icons.
##   * save ids match what SaveSystem stores, and a purchase round-trips by
##     save id (the catalog, not the UI, owns the price).
##   * KF08's four visible prices are the Level-4-unlocked Spider cosmetics, so
##     the padlock/price/check states come from the structured gates.
##   * the Ledger has no "PRICE UNKNOWN" state and a locked row cannot be
##     bought even if the handler is called directly.
##   * the Wardrobe is a three-column KF03/KF04 layout with no APPLY, four
##     slots (1 and 4 signature), an authored candidate row and real locks.
##   * a legacy save is migrated once: short ids become catalog ids, unknown
##     ids survive, and a second load is a no-op.

var CatalogScript: GDScript = null
const CATALOG_PATH := "res://data/generated/gameplay/unlocks.json"

const EXPECTED_COLUMNS := {
	"tools": 7,
	"guild_perks": 7,
	"spider_cosmetics": 28,
	"chameleon_cosmetics": 26,
}
const EXPECTED_TOOL_IDS: Array[String] = [
	"zipwire", "smoke_bomb", "pickpocket_fairy", "insult_fairy",
	"slither_sap", "glamour", "vistara_diamond",
]
const EXPECTED_PERK_IDS: Array[String] = [
	"novice_difficulty", "thief_difficulty", "master_thief_difficulty",
	"guildhall", "old_manor", "spider", "chameleon",
]
const KF08_PRICES := {
	"Outfit.Spider.Head.Hair.Bob": 7500,
	"Outfit.Spider.Head.MustacheA": 5000,
	"Outfit.Spider.Head.BeardA": 7500,
	"Outfit.Spider.Head.EyepatchA": 2500,
}
## The five rows where the data asset's description copy contradicts its
## structured gate (see the producer's condition_copy_audit).
const KNOWN_COPY_MISMATCHES: Array[String] = [
	"Difficulty.MasterThief",
	"Tool.Type.MagicSlime",
	"Outfit.Chameleon.Head.HairB",
	"Outfit.Chameleon.Head.BowlerA.MustacheA",
	"Outfit.Chameleon.Head.MustacheA",
]
const TOOL_SOURCE_IDS := {
	"Tool.Type.Zipwire": "zipwire",
	"Tool.Type.SmokeBomb": "smoke_bomb",
	"Tool.Type.Pickpocket": "pickpocket_fairy",
	"Tool.Type.CuckooClock": "insult_fairy",
	"Tool.Type.MagicSlime": "slither_sap",
	"Tool.Type.Glamour": "glamour",
	"Tool.Type.VistaraDiamond": "vistara_diamond",
}
const PERK_SOURCE_IDS := {
	"Difficulty.Novice": "novice_difficulty",
	"Difficulty.Thief": "thief_difficulty",
	"Difficulty.MasterThief": "master_thief_difficulty",
	"Map.Guildhall": "guildhall",
	"Map.OldManor": "old_manor",
	"Thief.Spider": "spider",
	"Thief.Chameleon": "chameleon",
}

var fails: int = 0
var _save: Node = null
var _saved_data: Dictionary = {}
var _saved_file: String = ""
var _had_file: bool = false


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _initialize() -> void:
	await process_frame
	var save: Node = root.get_node_or_null("SaveSystem")
	if save == null:
		_check(false, "", "W6U2.0 SaveSystem autoload missing")
		_finish()
		return
	_save = save
	_saved_data = (save.get("data") as Dictionary).duplicate(true)
	_had_file = FileAccess.file_exists("user://tat2_save.json")
	if _had_file:
		_saved_file = FileAccess.get_file_as_string("user://tat2_save.json")

	CatalogScript = load("res://src/ui/unlock_catalog.gd") as GDScript
	if CatalogScript == null:
		_check(false, "", "W6U2.0 unlock_catalog.gd failed to load")
		_finish()
		return
	var catalog: RefCounted = CatalogScript.new()
	_check_catalog(catalog)
	_check_conditions(catalog)
	await _check_ledger(catalog)
	await _check_wardrobe(catalog)
	_check_save_migration(save)
	_restore(save)
	_finish()


# --- 1. catalog -----------------------------------------------------------
func _check_catalog(catalog: RefCounted) -> void:
	_check(bool(catalog.is_available()), "W6U2.1 catalog loads (%s)" % ", ".join(catalog.errors()),
		"W6U2.1 catalog unavailable: %s" % ", ".join(catalog.errors()))
	if not catalog.is_available():
		return
	var entries: Array[Dictionary] = catalog.entries()
	_check(entries.size() == 68, "W6U2.2 68 authored rows", "W6U2.2 %d rows" % entries.size())
	var counts: Dictionary = {}
	for entry: Dictionary in entries:
		var key: String = str(entry.get("shop_category", ""))
		counts[key] = int(counts.get(key, 0)) + 1
	var counts_ok: bool = true
	for key: String in EXPECTED_COLUMNS.keys():
		if int(counts.get(key, -1)) != int(EXPECTED_COLUMNS[key]):
			counts_ok = false
	_check(counts_ok and counts.size() == 4,
		"W6U2.3 columns 7 tools / 7 perks / 28 Spider / 26 Chameleon",
		"W6U2.3 column counts drifted: %s" % str(counts))

	var priced: int = 0
	var ids: Array[String] = []
	var icons_ok: int = 0
	for entry: Dictionary in entries:
		if int(entry.get("price", 0)) > 0:
			priced += 1
		ids.append(CatalogScript.save_id_of(entry))
		var tex: Texture2D = CatalogScript.icon_texture(entry)
		if tex != null:
			icons_ok += 1
	_check(priced == 55, "W6U2.4 55 rows carry an authored price", "W6U2.4 %d priced rows" % priced)
	_check(ids.size() == 68 and _unique(ids).size() == 68,
		"W6U2.5 68 unique stable save ids", "W6U2.5 duplicate/blank save ids: %d unique" % _unique(ids).size())
	_check(icons_ok == 68, "W6U2.6 68/68 authored icons resolve",
		"W6U2.6 only %d/68 icons resolve" % icons_ok)

	# SaveSystem owns the ids; the catalog must agree with it.
	var tool_ids: Array[String] = []
	var perk_ids: Array[String] = []
	for entry: Dictionary in entries:
		match str(entry.get("save_category", "")):
			"tools":
				tool_ids.append(CatalogScript.save_id_of(entry))
			"perks":
				perk_ids.append(CatalogScript.save_id_of(entry))
	tool_ids.sort()
	perk_ids.sort()
	var want_tools: Array[String] = EXPECTED_TOOL_IDS.duplicate()
	var want_perks: Array[String] = EXPECTED_PERK_IDS.duplicate()
	want_tools.sort()
	want_perks.sort()
	_check(tool_ids == want_tools, "W6U2.7 tool save ids match SaveSystem (7)",
		"W6U2.7 tool ids drifted: %s" % str(tool_ids))
	_check(perk_ids == want_perks, "W6U2.8 guild-perk save ids match SaveSystem (7)",
		"W6U2.8 perk ids drifted: %s" % str(perk_ids))
	var constants: Dictionary = _save.get_script().get_script_constant_map()
	var keys: Dictionary = constants.get("UNLOCK_CATEGORY_KEYS", {})
	var category_keys_ok: bool = keys.has("tools") and keys.has("perks") and keys.has("cosmetics")
	_check(category_keys_ok, "W6U2.9 SaveSystem exposes the three catalog categories",
		"W6U2.9 UNLOCK_CATEGORY_KEYS missing a category")
	# Every id must be round-trippable through the save lists.
	var round_trip_ok: bool = true
	for entry: Dictionary in entries:
		var cat: String = CatalogScript.category_of(entry)
		if (_save.call("unlock_list_for", cat) as Array).is_empty() and cat != "cosmetics":
			round_trip_ok = false
	_check(round_trip_ok, "W6U2.10 each catalog category maps to a save list",
		"W6U2.10 a catalog category has no save list")

	var kf08_ok: bool = true
	for tag: String in KF08_PRICES.keys():
		var entry: Dictionary = _entry_by_tag(catalog, tag)
		if int(entry.get("price", -1)) != int(KF08_PRICES[tag]):
			kf08_ok = false
	_check(kf08_ok, "W6U2.11 KF08 anchors 7,500 / 5,000 / 7,500 / 2,500",
		"W6U2.11 a KF08 anchor price drifted")

	# Drift guard: recompute save id + condition text from the tag/gate and
	# compare with the emitted values; pin the five copy/gate contradictions.
	var drift: Array[String] = []
	var copy_mismatches: Array[String] = []
	for entry: Dictionary in entries:
		var tag: String = str(entry.get("tag", ""))
		var want_id: String = _expected_save_id(tag, str(entry.get("content_type", "")))
		if CatalogScript.save_id_of(entry) != want_id:
			drift.append("%s id=%s want=%s" % [tag, CatalogScript.save_id_of(entry), want_id])
		var cond: Dictionary = CatalogScript.condition_of(entry)
		var want_text: String = _expected_condition_text(cond)
		if str(cond.get("text", "")) != want_text:
			drift.append("%s cond=%s want=%s" % [tag, str(cond.get("text", "")), want_text])
		if not bool(cond.get("copy_agrees", true)):
			copy_mismatches.append(tag)
	copy_mismatches.sort()
	var known: Array[String] = KNOWN_COPY_MISMATCHES.duplicate()
	known.sort()
	_check(drift.is_empty(), "W6U2.12 save id + condition text derive from the authored tag/gate",
		"W6U2.12 catalog drift: %s" % str(drift))
	_check(copy_mismatches == known,
		"W6U2.13 the 5 authored copy/gate contradictions are recorded, not hidden",
		"W6U2.13 copy mismatch set changed: %s" % str(copy_mismatches))


func _check_conditions(catalog: RefCounted) -> void:
	var save: Node = _save
	# KF08 profile: Level 4, contracts 1-2 completed, £26,275.
	save.set("data", save.call("_defaults"))
	var data: Dictionary = save.get("data") as Dictionary
	data["xp"] = 1500
	data["level"] = 4
	data["completed_contracts"] = {
		"1": {"best_score": 100, "ghost": false},
		"2": {"best_score": 100, "ghost": false},
	}
	data["currency"] = 26275
	_check(int(save.call("level_for_xp", 1500)) == 4,
		"W6U2.14 1500 XP is Level 4 under the authored curve",
		"W6U2.14 1500 XP resolved to another level")

	# Exactly the four level<=4 Spider cosmetics are purchasable at Level 4.
	var index: int = 0
	for tag: String in KF08_PRICES.keys():
		var entry: Dictionary = _entry_by_tag(catalog, tag)
		_check(catalog.state_of(entry) == CatalogScript.STATE_BUY,
			"W6U2.15a KF08 price row is purchasable: %s" % CatalogScript.title_of(entry),
			"W6U2.15a %s state=%s" % [tag, catalog.state_of(entry)])
		index += 1
	var gated_ok: int = 0
	for entry: Dictionary in catalog.entries_for_column("spider_cosmetics"):
		if int(entry.get("price", 0)) > 0 and catalog.state_of(entry) == CatalogScript.STATE_BUY:
			gated_ok += 1
	_check(gated_ok == 4, "W6U2.15b exactly the four authored Level-4 prices show, the rest lock",
		"W6U2.15b %d Spider rows purchasable at Level 4" % gated_ok)
	# KF08 owned rows: free unlocks and the starter set.
	var owned_ok: bool = true
	for save_id: String in ["zipwire", "smoke_bomb", "novice_difficulty", "guildhall", "old_manor", "spider", "Outfit.Spider.Head.BowlerA"]:
		var entry: Dictionary = catalog.entry(save_id)
		if entry.is_empty() or catalog.state_of(entry) != CatalogScript.STATE_PURCHASED:
			owned_ok = false
	_check(owned_ok, "W6U2.16 free + starter rows read ✓ PURCHASED (KF08 checks)",
		"W6U2.16 an owned row is not purchased")
	var locked_ok: bool = true
	for save_id: String in ["pickpocket_fairy", "thief_difficulty", "chameleon", "Outfit.Spider.Head.TopHatA"]:
		var entry: Dictionary = catalog.entry(save_id)
		if entry.is_empty() or catalog.state_of(entry) != CatalogScript.STATE_LOCKED:
			locked_ok = false
	_check(locked_ok, "W6U2.17 unmet level/contract gates read LOCKED (padlock)",
		"W6U2.17 a gated row is not locked")

	# Contract 3 unlocks the Chameleon; contract 1 must not.
	data["completed_contracts"] = {"1": {"best_score": 100, "ghost": false}}
	_check(not bool(save.call("is_thief_unlocked", "chameleon")),
		"W6U2.18a contract 1 does not unlock the Chameleon",
		"W6U2.18a any contract still unlocks the Chameleon")
	data["completed_contracts"] = {"3": {"best_score": 100, "ghost": false}}
	_check(bool(save.call("is_thief_unlocked", "chameleon")),
		"W6U2.18b contract 3 unlocks the Chameleon",
		"W6U2.18b contract 3 does not unlock the Chameleon")
	var chameleon: Dictionary = catalog.entry("chameleon")
	_check(CatalogScript.price_of(chameleon) == 10000 and CatalogScript.requires_contract(chameleon) == 3,
		"W6U2.18c Thief.Chameleon is £10,000 + Contract 3",
		"W6U2.18c Thameleon row drifted: price=%d contract=%d" % [
			CatalogScript.price_of(chameleon), CatalogScript.requires_contract(chameleon)])
	data["completed_contracts"] = {
		"1": {"best_score": 100, "ghost": false},
		"2": {"best_score": 100, "ghost": false},
	}
	data["unlocked_perks"] = (data["unlocked_perks"] as Array).duplicate()
	_check(not bool(save.call("is_thief_unlocked", "chameleon")),
		"W6U2.18d the starter perk list does not include the Chameleon",
		"W6U2.18d the Chameleon is unlocked by default")


# --- 2. ledger ------------------------------------------------------------
func _check_ledger(catalog: RefCounted) -> void:
	var ledger: Control = (load("res://src/ui/ledger_ui.gd") as GDScript).new() as Control
	root.add_child(ledger)
	await process_frame
	await process_frame
	_check(ledger.get("_catalog") != null and bool((ledger.get("_catalog") as RefCounted).call("is_available")),
		"W6U2.19 Ledger reads the catalog", "W6U2.19 Ledger catalog unavailable")
	var assets: Label = ledger.get("_assets_lbl") as Label
	_check(assets != null and assets.text == "YOUR TOTAL ASSETS: (£) 26,275",
		"W6U2.20 assets banner is the authored KF08 string",
		"W6U2.20 assets banner: %s" % (assets.text if assets != null else "null"))
	var level: Label = ledger.get("_level_lbl") as Label
	var xp: Label = ledger.get("_xp_lbl") as Label
	_check(level != null and level.text == "Level 4" and xp != null and xp.text == "0/500",
		"W6U2.21 KF07 Level + XP header (Level 4, 0/500)",
		"W6U2.21 header: %s %s" % [level.text if level != null else "?", xp.text if xp != null else "?"])
	var portrait: TextureRect = ledger.get("_portrait") as TextureRect
	_check(portrait != null and portrait.texture != null, "W6U2.22 KF07 portrait texture loads",
		"W6U2.22 portrait texture missing")
	var name_lbl: Label = ledger.get("_thief_lbl") as Label
	_check(name_lbl != null and name_lbl.text != "", "W6U2.23 KF07 handle under the portrait",
		"W6U2.23 handle label empty")
	var contracts: Node = ledger.get("_contracts_box") as Node
	_check(contracts != null and contracts.get_child_count() > 0,
		"W6U2.24 contract carousel populated", "W6U2.24 empty contract carousel")

	# Four authored tables with the authored row counts.
	var tables: HBoxContainer = ledger.get("_tables_row") as HBoxContainer
	var right: HBoxContainer = ledger.get("_right_tables_row") as HBoxContainer
	var row_counts: Dictionary = {}
	var states: Dictionary = {"purchased": 0, "locked": 0, "buy": 0}
	if tables != null and right != null:
		for host: HBoxContainer in [tables, right]:
			for child: Node in host.get_children():
				var table: VBoxContainer = child as VBoxContainer
				var key: String = table.name.replace("Table_", "")
				var rows: Node = table.find_child("Rows", true, false)
				if rows != null:
					row_counts[key] = rows.get_child_count()
					for row: Node in rows.get_children():
						var btn: Button = row as Button
						if btn == null:
							continue
						if btn.get_child_count() > 0:
							states[_bucket(btn)] = int(states.get(_bucket(btn), 0)) + 1
	_check(int(row_counts.get("tools", -1)) == 7 and int(row_counts.get("guild_perks", -1)) == 7 \
			and int(row_counts.get("spider_cosmetics", -1)) == 28 \
			and int(row_counts.get("chameleon_cosmetics", -1)) == 26,
		"W6U2.25 KF08 four tables hold 7 / 7 / 28 / 26 rows",
		"W6U2.25 table row counts: %s" % str(row_counts))
	_check(int(states["purchased"]) >= 7 and int(states["buy"]) == 4 and int(states["locked"]) >= 20,
		"W6U2.26 tables show ✓ / price / padlock states (%s)" % str(states),
		"W6U2.26 table states: %s" % str(states))

	# No unknown-price state anywhere, in code or in a row label.
	var src: String = FileAccess.get_file_as_string("res://src/ui/ledger_ui.gd")
	_check(src.find("PRICE UNKNOWN") < 0 and src.find("SPIDER_COSMETICS: Array") < 0 \
			and src.find("const TOOLS: Array") < 0,
		"W6U2.27 no hand-written price table or PRICE UNKNOWN in the Ledger",
		"W6U2.27 Ledger source still carries a placeholder price state")
	var sections: Array = ledger.call("_sections") as Array
	var unknown_rows: int = 0
	var total_rows: int = 0
	for section_v: Variant in sections:
		var section: Dictionary = section_v as Dictionary
		for item_v: Variant in section.get("items", []) as Array:
			total_rows += 1
			if str(ledger.call("_item_button_text", item_v as Dictionary)).find("PRICE UNKNOWN") >= 0:
				unknown_rows += 1
	_check(total_rows == 68 and unknown_rows == 0,
		"W6U2.28 all 68 rows label as ✓ / price / locked",
		"W6U2.28 %d/%d rows carry an unknown price" % [unknown_rows, total_rows])

	# Purchase by save id: Bob hair at its authored price.
	var before: int = int(_save.call("get_currency"))
	var bob_id: String = "Outfit.Spider.Head.Hair.Bob"
	ledger.call("_on_item_pressed", bob_id)
	var buy: Button = ledger.get("_buy_btn") as Button
	var status: Label = ledger.get("_preview_status") as Label
	_check(buy != null and buy.visible and status != null and status.text.find("7,500") >= 0,
		"W6U2.29 selected Bob Hair shows the authored £ 7,500 + BUY (%s)" % (status.text if status != null else "?"),
		"W6U2.29 Bob Hair preview: %s" % (status.text if status != null else "?"))
	ledger.call("_on_buy_pressed")
	var bob_owned: bool = bool(_save.call("is_unlocked", "cosmetics", bob_id))
	var bob_funds: int = int(_save.call("get_currency"))
	_check(bob_owned and bob_funds == before - 7500,
		"W6U2.30 BUY charges the authored price and owns the save id (£%d -> £%d)" % [before, bob_funds],
		"W6U2.30 purchase failed: owned=%s currency=%d" % [str(bob_owned), bob_funds])

	# Insufficient funds: another priced row with an empty purse.
	(_save.get("data") as Dictionary)["currency"] = 0
	var top_id: String = "Outfit.Spider.Head.MustacheA"
	var top: Dictionary = (ledger.get("_catalog") as RefCounted).call("entry", top_id)
	ledger.call("_on_item_pressed", top_id)
	ledger.call("_on_buy_pressed")
	var insufficient: Label = ledger.get("_preview_status") as Label
	_check(not bool(_save.call("is_unlocked", "cosmetics", top_id)) \
			and insufficient != null and insufficient.text.find("Insufficient funds") >= 0,
		"W6U2.31 insufficient funds fails closed (%s)" % (insufficient.text if insufficient != null else "?"),
		"W6U2.31 insufficient funds path did not report")

	# Locked row: the handler must refuse even when called directly.
	(_save.get("data") as Dictionary)["currency"] = 26275
	var locked_id: String = "Outfit.Spider.Head.TopHatA"
	ledger.call("_on_item_pressed", locked_id)
	var locked_before: int = int(_save.call("get_currency"))
	ledger.call("_on_buy_pressed")
	var locked_status: Label = ledger.get("_preview_status") as Label
	_check(not bool(_save.call("is_unlocked", "cosmetics", locked_id)) \
			and int(_save.call("get_currency")) == locked_before \
			and locked_status != null and locked_status.text.find("Requires Level") >= 0,
		"W6U2.32 a locked row cannot be bought and shows its gate (%s)" % (locked_status.text if locked_status != null else "?"),
		"W6U2.32 locked row purchase was not refused")
	if top.is_empty():
		_check(false, "", "W6U2.31b catalog row lookup failed")

	root.remove_child(ledger)
	ledger.queue_free()
	await process_frame


func _bucket(btn: Button) -> String:
	for child: Node in btn.get_children():
		var slot: HBoxContainer = child as HBoxContainer
		if slot == null:
			continue
		for state_child: Node in slot.get_children():
			if state_child is TextureRect:
				var tex: TextureRect = state_child as TextureRect
				if tex.texture != null and tex.texture.resource_path.find("CheckMark") >= 0:
					return "purchased"
				if tex.texture != null and tex.texture.resource_path.find("Locked") >= 0:
					return "locked"
			elif state_child is Label:
				return "buy"
	return "unknown"


# --- 3. wardrobe ----------------------------------------------------------
func _check_wardrobe(catalog: RefCounted) -> void:
	var wardrobe: CanvasLayer = (load("res://src/ui/wardrobe_ui.gd") as GDScript).new() as CanvasLayer
	root.add_child(wardrobe)
	await process_frame
	await process_frame
	var main: HBoxContainer = null
	for node: Node in wardrobe.get_children():
		var found: Node = node.find_child("*", true, false)
		if found == null:
			continue
	for candidate: Node in wardrobe.find_children("*", "HBoxContainer", true, false):
		var hb: HBoxContainer = candidate as HBoxContainer
		if hb.get_child_count() == 3 and hb.get_child(0) is VBoxContainer \
				and hb.get_child(1) is VBoxContainer and hb.get_child(2) is PanelContainer:
			main = hb
			break
	_check(main != null, "W6U2.33 KF03/KF04 three-column layout (loadout | 3D | customization)",
		"W6U2.33 three-column layout missing")
	if main != null:
		var center: VBoxContainer = main.get_child(1) as VBoxContainer
		_check(not center.find_children("*", "SubViewport", true, false).is_empty(),
			"W6U2.34 centre column holds the 3D thief stage",
			"W6U2.34 centre column has no SubViewport")

	var apply_buttons: int = 0
	for node: Node in wardrobe.find_children("*", "Button", true, false):
		var btn: Button = node as Button
		if btn.text.strip_edges().to_upper() == "APPLY":
			apply_buttons += 1
	var src: String = FileAccess.get_file_as_string("res://src/ui/wardrobe_ui.gd")
	_check(apply_buttons == 0 and src.find("\"APPLY\"") < 0,
		"W6U2.35 no APPLY button (BACK only, KF03)",
		"W6U2.35 APPLY still present (%d buttons)" % apply_buttons)

	var slots: Array = wardrobe.get("_slots") as Array
	var sig_ok: bool = slots.size() == 4 and str(slots[0]) == "zipwire" \
		and str(slots[3]) == "vistara_diamond" and str(slots[2]) == ""
	_check(sig_ok, "W6U2.36 KF03 slots: Zipwire (sig) / Smoke Bomb / empty / Vistara Diamond (sig) %s" % str(slots),
		"W6U2.36 slot layout: %s" % str(slots))
	var slot_icons: Array = wardrobe.get("_slot_icons") as Array
	var icon_ok: bool = slot_icons.size() == 4
	for i: int in range(slot_icons.size()):
		var tex_rect: TextureRect = slot_icons[i] as TextureRect
		var filled: bool = str(slots[i]) != ""
		if tex_rect == null or (filled and tex_rect.texture == null) or (not filled and tex_rect.texture != null):
			icon_ok = false
	_check(icon_ok, "W6U2.37 every filled slot draws its authored tool icon (empty slot has none)",
		"W6U2.37 slot icons wrong")
	var slot_locks: Array = wardrobe.get("_slot_locks") as Array
	var sig_locks: bool = slot_locks.size() == 4 \
		and (slot_locks[0] as TextureRect).visible and (slot_locks[3] as TextureRect).visible \
		and not (slot_locks[1] as TextureRect).visible
	_check(sig_locks, "W6U2.38 signature slots carry the grey padlock, Smoke Bomb does not",
		"W6U2.38 slot padlocks wrong")

	# KF04 candidate row: the four remaining Spider tools, three locked.
	wardrobe.call("_on_slot_pressed", 2)
	await process_frame
	var cells: HBoxContainer = wardrobe.get("_cells_row") as HBoxContainer
	var cell_btns: Array = wardrobe.get("_cell_btns") as Array
	var cell_locks: Array = wardrobe.get("_cell_locks") as Array
	var names: Array[String] = []
	var locked_count: int = 0
	for tool_v: Variant in (wardrobe.call("_candidate_tools") as Array):
		names.append(str((tool_v as Dictionary).get("name", "")))
	for lock_v: Variant in cell_locks:
		if (lock_v as TextureRect).visible:
			locked_count += 1
	_check(cells != null and cells.visible and cell_btns.size() == 4 and locked_count == 3,
		"W6U2.39 KF04 candidate row shows 4 tools, 3 pink padlocks (%s)" % str(names),
		"W6U2.39 candidate row: cells=%d visible=%s locked=%d" % [
			cell_btns.size(), str(cells != null and cells.visible), locked_count])
	var expected_names: Array[String] = [
		"Smoke Bomb", "Pickpocket Fairy", "Insult Fairy", "Slither Sap",
	]
	_check(names == expected_names, "W6U2.40 candidate names come from the authored rows",
		"W6U2.40 candidate names: %s" % str(names))
	# Selecting a signature slot hides the candidate row (KF03 state).
	wardrobe.call("_on_slot_pressed", 0)
	await process_frame
	_check(cells != null and not cells.visible,
		"W6U2.41 signature slot hides the candidate row",
		"W6U2.41 candidate row stayed visible for a signature slot")
	var hint: Label = wardrobe.get("_hint_lbl") as Label
	_check(hint != null and hint.text.find("Signature Tools cannot be swapped out") >= 0,
		"W6U2.42 signature slot shows the shipped notice (%s)" % (hint.text if hint != null else "?"),
		"W6U2.42 signature notice missing")

	# 3D tool preview + authored name/description.
	var holder: Node3D = wardrobe.get("_tool_holder") as Node3D
	var tool_name: Label = wardrobe.get("_tool_name_lbl") as Label
	var tool_desc: Label = wardrobe.get("_tool_desc_lbl") as Label
	_check(holder != null and holder.get_child_count() > 0 and tool_name != null \
			and tool_name.text == "Zipwire" and tool_desc != null \
			and tool_desc.text.find("spring-loaded grapple gun") >= 0,
		"W6U2.43 3D tool preview + authored Zipwire copy",
		"W6U2.43 tool preview: children=%d name=%s" % [
			holder.get_child_count() if holder != null else -1,
			tool_name.text if tool_name != null else "?"])

	# Locked candidate cannot be equipped; unlocked Smoke Bomb can fill slot 3.
	wardrobe.call("_on_slot_pressed", 2)
	await process_frame
	wardrobe.call("_on_candidate_pressed", "pickpocket_fairy")
	var after_locked: Array = wardrobe.get("_slots") as Array
	_check(str(after_locked[2]) == "", "W6U2.44 a locked candidate is not equipped",
		"W6U2.44 locked candidate replaced the slot: %s" % str(after_locked))
	wardrobe.call("_on_candidate_pressed", "smoke_bomb")
	var after_swap: Array = wardrobe.get("_slots") as Array
	_check(str(after_swap[2]) == "smoke_bomb" and str(after_swap[1]) == "",
		"W6U2.45 equipping Smoke Bomb into slot 3 swaps it out of slot 2 (%s)" % str(after_swap),
		"W6U2.45 swap result: %s" % str(after_swap))

	# The Chameleon stays locked at contract 1 (authored Contract 3 gate).
	var gs: Node = root.get_node_or_null("GameState")
	wardrobe.call("_on_portrait_pressed", "chameleon")
	_check(str(wardrobe.get("_thief_id")) == "spider",
		"W6U2.46 locked Chameleon portrait does not switch thief",
		"W6U2.46 locked Chameleon switched the thief")

	# Once the Thief.Chameleon perk is owned, the same panel swaps to the
	# Chameleon's own signature tool (Glamour) and the same four candidates.
	var perks: Array = (_save.get("data") as Dictionary).get("unlocked_perks", []) as Array
	perks.append("chameleon")
	wardrobe.call("_on_portrait_pressed", "chameleon")
	await process_frame
	var cham_slots: Array = wardrobe.get("_slots") as Array
	var cham_names: Array[String] = []
	for tool_v: Variant in (wardrobe.call("_candidate_tools") as Array):
		cham_names.append(str((tool_v as Dictionary).get("name", "")))
	_check(str(wardrobe.get("_thief_id")) == "chameleon" and cham_slots.size() == 4 \
			and str(cham_slots[0]) == "glamour" and str(cham_slots[3]) == "vistara_diamond" \
			and cham_names.size() == 4,
		"W6U2.54 an owned Chameleon swaps to Glamour + the same 4 candidates (%s)" % str(cham_slots),
		"W6U2.54 Chameleon slots: %s / %s" % [str(cham_slots), str(cham_names)])
	wardrobe.call("_on_portrait_pressed", "spider")
	perks.erase("chameleon")
	await process_frame

	root.remove_child(wardrobe)
	wardrobe.queue_free()
	await process_frame


# --- 4. save migration ----------------------------------------------------
func _check_save_migration(save: Node) -> void:
	var legacy: Dictionary = {
		"xp": 1500,
		"unlocked_tools": ["zipwire", "slithersap", "fairy", "future_tool"],
		"unlocked_perks": ["novice_difficulty", "future_perk"],
		"unlocked_cosmetics": ["bowler_hat", "parted_hair", "future_cosmetic"],
		"equipped_loadout": {
			"spider": {
				"head": "bowler_hat",
				"body": "",
				"calling_card": "",
				"tools": ["blackjack", "smoke_bomb", "slithersap", "zipwire"],
			},
		},
		"currency": 26275,
	}
	var f: FileAccess = FileAccess.open("user://tat2_save.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(legacy, "\t"))
		f.close()
	save.call("load_save")
	var data: Dictionary = save.get("data") as Dictionary
	var tools: Array = data.get("unlocked_tools", [])
	var cosmetics: Array = data.get("unlocked_cosmetics", [])
	var perks: Array = data.get("unlocked_perks", [])
	_check(bool(data.get("unlock_ids_migrated", false)),
		"W6U2.47 save-id migration stamps unlock_ids_migrated",
		"W6U2.47 migration flag missing")
	_check(tools.has("slither_sap") and tools.has("pickpocket_fairy") and not tools.has("slithersap") and not tools.has("fairy"),
		"W6U2.48 legacy tool ids rewrite to catalog ids (%s)" % str(tools),
		"W6U2.48 tool migration: %s" % str(tools))
	_check(tools.has("future_tool") and perks.has("future_perk") and cosmetics.has("future_cosmetic"),
		"W6U2.49 unknown ids are preserved",
		"W6U2.49 unknown ids dropped: tools=%s perks=%s cosmetics=%s" % [str(tools), str(perks), str(cosmetics)])
	_check(cosmetics.has("Outfit.Spider.Head.BowlerA") and cosmetics.has("Outfit.Chameleon.Head.BowlerA") \
			and cosmetics.has("Outfit.Chameleon.Head.HairB") and not cosmetics.has("bowler_hat"),
		"W6U2.50 legacy cosmetic ids map to the authored outfit tags (%s)" % str(cosmetics),
		"W6U2.50 cosmetic migration: %s" % str(cosmetics))
	var eq: Dictionary = data.get("equipped_loadout", {})
	var spider: Dictionary = (eq.get("spider", {}) as Dictionary) if eq.get("spider") is Dictionary else {}
	_check(str(spider.get("head", "")) == "Outfit.Spider.Head.BowlerA",
		"W6U2.51 a legacy loadout head becomes the authored tag (%s)" % str(spider.get("head", "")),
		"W6U2.51 loadout head: %s" % str(spider.get("head", "")))
	var slots: Array = spider.get("tools", [])
	_check(slots.has("smoke_bomb") and slots.has("slither_sap"),
		"W6U2.52 a legacy four-tool loadout keeps its owned tools in slots (%s)" % str(slots),
		"W6U2.52 legacy slots: %s" % str(slots))

	# Second load must be a no-op (idempotent), including the round-tripped file.
	var first: Array = tools.duplicate()
	var first_cosmetics: Array = cosmetics.duplicate()
	save.call("load_save")
	var after: Array = (save.get("data") as Dictionary).get("unlocked_tools", [])
	var after_cosmetics: Array = (save.get("data") as Dictionary).get("unlocked_cosmetics", [])
	_check(after == first and after_cosmetics == first_cosmetics,
		"W6U2.53 a second load is a no-op (round-trip stable)",
		"W6U2.53 migration not idempotent: %s / %s" % [str(after), str(after_cosmetics)])


func _restore(save: Node) -> void:
	save.set("data", _saved_data)
	save.call("apply_saved_settings")
	if _had_file:
		var f: FileAccess = FileAccess.open("user://tat2_save.json", FileAccess.WRITE)
		if f != null:
			f.store_string(_saved_file)
			f.close()
	elif FileAccess.file_exists("user://tat2_save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tat2_save.json"))


# --- helpers --------------------------------------------------------------
func _unique(ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids:
		if not out.has(id):
			out.append(id)
	return out


func _entry_by_tag(catalog: RefCounted, tag: String) -> Dictionary:
	for entry: Dictionary in catalog.entries():
		if str(entry.get("tag", "")) == tag:
			return entry
	return {}


func _expected_save_id(tag: String, content_type: String) -> String:
	if content_type == "Cosmetic":
		return tag
	if content_type == "Gear":
		return str(TOOL_SOURCE_IDS.get(tag, ""))
	return str(PERK_SOURCE_IDS.get(tag, ""))


func _expected_condition_text(cond: Dictionary) -> String:
	var parts: Array[String] = []
	var level_v: Variant = cond.get("requires_level", null)
	if (level_v is int or level_v is float) and int(level_v) > 0:
		parts.append("at Level %d" % int(level_v))
	var contract_v: Variant = cond.get("requires_contract", null)
	if (contract_v is int or contract_v is float) and int(contract_v) > 0:
		parts.append("in Contract %d" % int(contract_v))
	if parts.is_empty():
		return ""
	if parts.size() == 1:
		return "Unlocked " + parts[0] + "."
	return "Unlocked " + " and ".join(parts) + "."


func _finish() -> void:
	print("W6U2_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)
