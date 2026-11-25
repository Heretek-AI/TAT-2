# W9-P3-C2 independent audit — Loc pipeline, StringTables, fallback, reverse map

**AUDIT: PASS** — all four scope outcomes verify. Four bookkeeping conditions
must be closed at integration (listed in §8); none changes runtime behaviour.

Auditor: independent (did not write this code). Worktree
`/home/john/Projects/TAT-2-rem-w9-p3`, branch `rem/w9-p3`, base `8ce9a86`.
No source, test or commit was touched; the only write is this file (throwaway
probes and helper scripts live in `/tmp/opencode/`).

**The worktree was live while this audit ran.** The implementer edited
`game/src` and the tool between 15:37 and 16:16, and fixed two of this audit's
findings as they landed (see §9). All numbers below were re-taken on the
settled tree at **16:15:47** and the hashes were re-checked after the runs:

```
16:15:47
3dd68993…  build/qa/w9/p3_string_audit.py
58b8fe52…  game/src/core/localization.gd
34dc692b…  game/src/ui/ui_strings.gd
d9dde19b…  game/src/ui/settings_ui.gd
6ecb408a…  game/src/ui/hud.gd
d0833e3f…  game/tests/test_w9p3_localization.gd
861f01c8…  build/qa/w9/p3-report.md
```

---

## Item 1 — measurement tool, numbers, and whether it games — **PASS**

### 1.1 Exact lines

```
$ python3 build/qa/w9/p3_string_audit.py --rev 8ce9a86
UI_STRINGS total=147 routed=26 authored=49 routed_authored=26 invented=98
COVERAGE routed/total=0.1769
COVERAGE authored_routed/authored=0.5306
KINDS _loc=3 _loc_upper=5 hud_feedback=13 literal=107 slider_label=1 st_text=10 st_upper=8

$ python3 build/qa/w9/p3_string_audit.py --same-files-as 8ce9a86
UI_STRINGS total=268 routed=268 authored=160 routed_authored=160 invented=108
COVERAGE routed/total=1.0000
COVERAGE authored_routed/authored=1.0000
KINDS _loc=5 _loc_upper=5 glyph_prompt=1 loc=121 loc_template=4 st_template=9 st_text=54 st_upper=69

$ python3 build/qa/w9/p3_string_audit.py            # all files
UI_STRINGS total=303 routed=303 authored=195 routed_authored=195 invented=108
COVERAGE routed/total=1.0000
COVERAGE authored_routed/authored=1.0000
KINDS _loc=5 _loc_upper=5 glyph_prompt=1 loc=121 loc_template=4 st_template=9 st_text=83 st_upper=75
```

Per file (routed / total): `hud 70/70`, `mission_controller 36/36`,
`mission_prep_ui 34/34`, `ledger_ui 24/24`, `wardrobe_ui 24/24`,
`contract_table_ui 21/21`, `post_match_ui 21/21`, `mobile_touch_ui 16/16`,
`settings_ui 15/15`, `main_menu 14/14`, `progression_ui 9/9`,
`loot_container 9/9`, `tutorial_ui 5/5`, `clue_item 3/3`,
`loading_screen 2/2`. Before: `26/147`; same old file set: `268/268`.

The report's headline, per-file table and `KINDS` line all match these numbers
after its 16:15 refresh.

### 1.2 Independent recomputation

A clean-room scanner (`/tmp/opencode/w9p3_recount.py`, no import of the tool)
reproduces **303 total / 303 routed** and every per-file count exactly. The
only reconciliation needed was the tool's empty-literal guard on the two
`"title": ""` / `"prompt": ""` dictionary rows. The tool is not inventing
totals.

### 1.3 Classification rules — reviewed, one past defect now fixed

The rules are: one row per visible string expression; a helper call is
`routed`; `authored` = exact table value, exact locres source, or the port's
ALL-CAPS form of an authored Title-case row.

While the audit was running the tool still accepted a **prefix rule**
(`authored_match()`: any authored value starting with the literal, or with its
pre-`{}`/`%s` head). It produced **11 rows counted `authored` with no authored
row**: `'Objective'` (vs `Objective: `), `'Move'`, `'Wire'`, `'Location'`,
`'Lockpicking'`, `'Host Co-op'`, `'Esteemed Colleague -'`, `'Steal the %s'` ×2.
At 16:11 the rule was removed (with a comment citing `audit-c2 §1.4`). On the
settled tree: **195 authored, 0 prefix-only**; the 29 non-keyed authored rows
all match exactly or by ALL-CAPS title-case. I re-derived my strict count
(194 at 16:09, 195 after the last row) and it now equals the tool's exactly.

### 1.4 Fifteen rows spot-checked against source + table/key

| # | site | literal | tool | reality |
|---|---|---|---|---|
| 1 | `contract_table_ui.gd:240` | `Solo Mode` | R/X | `loc("Solo Mode")`, no authored row — correct |
| 2 | `hud.gd:1829` | `TUMBLER %d / %d` | R/X | `loc(...)`, no authored row — correct |
| 3 | `hud.gd:2315` | `NOTICE` | R/X | `loc("NOTICE")`, no authored row — correct |
| 4 | `hud.gd:2983` | `Contract #{number}` | R/A | `st_template("ST_Screens","Screen.Contract.Number",…)`; key = `Contract #{number}` — correct |
| 5 | `hud.gd:2984` | `Objective` | R/X | `loc("Objective")`; no authored row (now correctly **X**) |
| 6 | `ledger_ui.gd:927` | `The authored catalog is missing…` | R/X | `loc(...)`, no row — correct |
| 7 | `main_menu.gd:783` | `Warren Spector — Studio Director` | R/X | `loc(...)`, no row — correct |
| 8 | `mission_prep_ui.gd:1390` | `Vault Heist` | R/A | `st_text("ST_Screens","Screen.MissionLobby.VaultQuestTitle",…)`; key exists — correct |
| 9 | `mobile_touch_ui.gd:108` | `HIT` | R/X | `loc("HIT")`, no row — correct |
| 10 | `post_match_ui.gd:332` | `` (empty fallback) | R/A | `st_text("ST_Screens","Screen.PostMatch.LootEarned","")`; key = `Loot Earned: £{0}` — correct |
| 11 | `progression_ui.gd:193` | `` (empty fallback) | R/A | `st_upper("ST_Screens","Screen.Back","")`; key = `Back` — correct |
| 12 | `settings_ui.gd:897` | `Press Any Key` | R/A | `st_text("ST_Settings_Input","InputSetting.PressAnyKey",…)`; key = `Press Any Key` — correct |
| 13 | `wardrobe_ui.gd:781` | `Head` | R/A | `st_text("ST_ThievesDen","Wardrobe.OutfitHead",…)`; key = `Head` — correct |
| 14 | `mission_controller.gd:1352` | `Customize Loadout` | R/A | `loc(...)`; exact locres source — correct |
| 15 | `loot_container.gd:310` | `Pick Lock` | R/A | `st_upper("ST_Lockpicking","Lockpicking.Pompt.Start",…)`; key = `Pick Lock` — correct |

15/15 correct on the settled tree.

### 1.5 Residual metric caveats (do not affect the pass, but do bound the claim)

* **Three visible sites are still outside the counter**: the two
  `_set_hint("The Chameleon is locked. Unlock it in the Black Market
  (£10,000, Contract 3).")` calls (`wardrobe_ui.gd:494`, `:1025`) and
  `_set_hint(("Locked - %s" …) if … else "Locked - not owned")`
  (`wardrobe_ui.gd:1073`). The tool gained `._set_hint(`/`._status(` regexes at
  16:11, but the call sites are bare `_set_hint(` / `_status(`, so they match
  nothing (`KINDS` has no `hint`/`status`). The settings status fallback
  (`settings_ui.gd:939`) is now runtime-routed via `UIStrings.loc(str(...))`
  but is not a countable literal.
* **One non-copy format scaffold is counted as port copy**:
  `hud.gd:2954` `loc("%s: %s[%s/%s]")`. `invented` is therefore 108 counted,
  107 of them real copy.
* **Mixed lines count once as routed while carrying raw English**:
  the credits tail `" — OtherSide Entertainment / Megabit"`
  (`main_menu.gd:749`), `"  ·  [BACKSLASH] TO SWAP"` (`settings_ui.gd`),
  `"LOCK "` (`hud.gd`), `" — LV %d"` (`hud.gd`).
* **The tool is untracked and git-ignored** (see §8.1).

So "303/303" is 100 % of the metric's universe (helper calls + `.text`
assignments), not literally 100 % of every English word on screen. The report's
own sentence "108 … every one carries a PORT COPY comment" holds for the 107
copy rows; the exceptions are the format-scaffold row and the `hud.gd:1048`
duplicate legend build (inside `_on_input_device_changed`, commented only at
the first site).

---

## Item 2 — localisation proof — **PASS**

```
$ flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game \
    --script res://tests/test_w9p3_localization.gd'
TAT-2 Loc: 8 translations, reverse map 2946/3404 en.csv keys, locale=en
W9P3_LOC: source_count=2946 (pre-W9 documented=2946)
W9P3_LOC: reverse map exactly 2946 sources (matches the pre-W9 count)
W9P3_LOC: routed sources checked=56 reverse_map_members=56
W9P3_LOC: de-DE.csv ST_Screens.Screen.MainMenu.Play = 'Spielen'
W9P3_LOC: Loc.t('Play') under de_DE = 'Spielen'
W9P3_LOC: Loc.t('PLAY') under de_DE = 'Spielen'
W9P3_LOC_SUMMARY: fails=0 checks=19          # exit 0
```

Independent probe (`/tmp/opencode/probe_w9p3_c2.gd`, not committed) reads the
German CSV itself instead of trusting the test's constant:

```
TAT-2 Loc: 8 translations, reverse map 2946/3404 en.csv keys, locale=en
AUDIT_C2 PASS: reverse map sources == 2946 [2946]
AUDIT_C2 PASS: reverse map en.csv keys == 3404 [3404]
AUDIT_C2: de-DE.csv ST_Screens.Screen.MainMenu.Play = 'Spielen'
AUDIT_C2 PASS: Loc.t('Play') == de-DE.csv authored value [Spielen / Spielen]
AUDIT_C2 PASS: Loc.t('PLAY') resolves to the same German row [Spielen]
AUDIT_C2 PASS: unknown source returns itself [__no_such_source__]
AUDIT_C2 PASS: unknown source is never empty
AUDIT_C2 PASS: unknown source never becomes a GUID [__no_such_source__]
AUDIT_C2 PASS: locale restored to en
AUDIT_C2 PASS: Loc.t('Play') is English again [Play]
AUDIT_C2_PROBE_SUMMARY: fails=0 checks=14
```

German value: **`Spielen`**. Unknown key: **`__no_such_source__`** verbatim,
not a GUID, not empty. Boot line: **2946/3404**. `en` restored.

---

## Item 3 — settings screen — **PASS, one wording defect**

`settings_ui.gd:121` now reads:

```gdscript
func _label(key: String, fallback: String) -> String:
	var v: String = UIStringsScript.st_text("ST_Settings", key, fallback).strip_edges()
	return v if v != "" else fallback
```

The old direct `_st` table read (which bypassed Loc) is gone; `_st` is still
loaded and is now dead. Three keys do not exist in `ST_Settings`:

```
Settings.Volume.AmbienceVolume           absent (fallback 'Ambience Volume'; no locres source → stays English in every locale)
Settings.Volume.UIVolume                 absent (fallback 'UI Volume';       no locres source → stays English)
Settings.GraphicsQuality.DesktopQuality  absent (fallback 'Graphics Quality'; IS an authored source → translates: de 'Grafikqualität')
```

**Disclosed?** Yes, in `p3-report.md` §2.1/§7.4 and
`p3-facts-strings.md` — **not** inline at the call sites.

**Defect:** the report calls all three "a producer gap". That is true for the
two volume keys (the shipped game never had those sliders), but
`DesktopQuality` is a **port key-name error**: the producer emits
`ST_Settings.Settings.GraphicsQuality = 'Graphics Quality'` and
`Settings.GraphicsQuality.QualityPreset = 'Quality Preset'`. It is a one-line
port fix. A **fourth** missing key, `ST_Settings.Settings.Header`
(settings modal title, `settings_ui.gd:462`), is not mentioned at all; its
fallback `"Settings"` is an authored source, so it still translates.

---

## Item 4 — `localization.gd` unchanged except counters — **PASS**

Function-by-function comparison with `git show 8ce9a86:game/src/core/localization.gd`:

```
SAME _load_reverse_map
SAME _load_reverse_map_from_json
SAME _load_reverse_map_from_translation
SAME _load_translations
SAME _ready / get_locale / has_source / languages / resolve_code / set_locale / source_count
DIFF t
ADDED _note_missing / t_stats / reset_t_stats
```

The whole `t()` diff is four added lines:

```gdscript
 	_t_calls += 1
 	if key == "":
+		_t_passthrough += 1
+		_note_missing(source)
 		return source
+	_t_resolved += 1
```

Reverse-map construction (first key wins in file order; `sources.json` first,
CSV/`.translation` fallbacks), ALL-CAPS normalisation and the
`out == "" or out == key → return source` fallback are byte-identical.
The pre-existing suite 60f/60g localisation block in `run_tests.gd` is
untouched, and the runtime map is still 2946 sources / 3404 keys.

---

## Item 5 — the 108 port-copy rows — **PASS with labels to fix**

* **107 are genuine port-only copy** (HUD legends, lockpick minigame, mobile
  captions, co-op status, diagnostics, credits names, loading %). Twelve
  spot-checked with exact match over all 36 StringTables + 3404 locres sources:
  none has an exact authored row.
* **1 is not copy**: `hud.gd:2954` `loc("%s: %s[%s/%s]")` — format scaffolding,
  counted as invented.
* **Labels** are present within a few lines for every copy row. The ones my
  ±2-line scan flags are continuation lines of already-commented calls
  (`hud.gd:1048`, `:1863`, `:1914`, `:3526`), the letter title
  (`hud.gd:2073` `Esteemed Colleague -`), the `" — LV %d"` fragment, and the
  scaffold — not unlabelled copy.
* **Three `PORT COPY` comments are factually wrong** — the literal *is* an
  authored source, so the tool counts it `authored` while the comment says
  "no authored row":
  - `contract_table_ui.gd:536` `InputGlyphs.prompt("pause", "CANCEL")` —
    locres `Cancel` → de `Abbrechen`; routing it through `Loc` would translate
    the button. This is the one that costs a real translation.
  - `hud.gd:1474` `loc("Crank")` — locres `Crank` → de `Kurbeln`; `loc()` is
    the right helper, only the comment is wrong.
  - `mobile_touch_ui.gd:553` `loc("Mask")` — its locres source is the engine
    debug row `FNaniteVisualizationData.Mask`, so the comment is defensible but
    the `authored` flag is accidental.
* **One could have used an authored row**: `clue_item.gd:123`
  `loc("[E] Read Clue: ")` — `ST_Interactables.PromptReadClue = 'Read Clue'`
  exists; the phrase is port composition but the verb fragment is authored.

No case found where a whole invented sentence duplicates an authored row.

---

## Item 6 — no test weakened — **PASS**

```
$ git diff --stat 8ce9a86 -- game/tests/
 game/tests/run_tests.gd | 27 +++++++++++++++++++++++++++
 1 file changed, 27 insertions(+)
$ git diff 8ce9a86 -- game/tests/ | grep -c '^-[^-]'
0
```

Only four gate lines were added (suites 106–109, each requiring exit 0 **and**
its summary marker). No assertion was edited, relaxed or deleted; the existing
60f/60g localisation assertions are untouched. The new localisation test is 19
checks (6 passthrough/source, 1 map size, 3 routed-source, 8 German/restore,
1 final locale).

One residual weakness: the map-size check is a **range** `[2900, 3000]` with a
separate `== 2946` message, so a small drift would print a note rather than
fail. It currently passes at exactly 2946; the exact value is independently
asserted by my probe.

---

## Item 7 — English unchanged where the authored row equals the old literal — **PASS**

Dynamic probe (`/tmp/opencode/probe_w9p3_c2_english.gd`, `locale=en`, real
helpers): **35 rows rendered, 29 identical**; the 6 "differences" include 2 of
my own expected-value strings. The four genuine changes:

| where | old | new | authored row that justifies it |
|---|---|---|---|
| `ledger_ui.gd` BUY ×3 | `BUY` | `PURCHASE` | `ST_ThievesDen.Ledger.BlackMarket.Purchase = 'Purchase'` |
| `wardrobe_ui.gd:773` | `CUSTOMIZATION` | `CUSTOMIZATIONS` | `ST_BlackMarket.Category.Customizations = 'Customizations'` |
| `hud.gd` ping marker | `◆ WAYPOINT (12m)` | `◆ WAYPOINT (12 m)` | `ST_GeneralUI.Format.Distance = '{Distance} m'` |
| `main_menu.gd:782` credits fallback | `OtherSide Entertainment` | `Otherside Entertainment` | `ST_Credits.Company.Otherside = 'Otherside Entertainment'` (fallback list only) |

Two deletions of invented copy are documented and correct (five loading flavour
lines, `MAP TABLE — CONTRACT SELECTOR`). No user-visible English change was
found without an authored row behind it. The three `ST_Settings` fallbacks
render unchanged (`Ambience Volume`, `UI Volume`, `Graphics Quality`).

All keycap re-renders verified on the live InputMap: `jump`=`SPACE`,
`interact`=`F`, `pause`=`ESC`, `secondary_action`=`RMB`, `Q`/`E` unchanged.

---

## 8. Conditions to close at integration (none is a runtime defect)

1. **Commit the tool.** `build/qa/w9/p3_string_audit.py` is untracked and
   ignored: `.gitignore:25:build/qa/*` excludes the parent directory, so the
   `!build/qa/**/*.py` negation cannot apply and `git add -A` will silently drop
   it. `p3-report.md` §0 calls it "committed" while §7.3 tells the integrator to
   force-add — make §0 true, e.g. `git add -f build/qa/w9/p3_string_audit.py`.
2. **Fix the `DesktopQuality` sentence** (§2.1): it is a port key-name error
   (`Settings.GraphicsQuality` exists), not a producer gap. Mention
   `Settings.Header` as the fourth missing key.
3. **Fix the three `PORT COPY` comments** (`CANCEL`, `Crank`, `Mask`), and
   ideally route `CANCEL` through `Loc` (`loc("Cancel")` → de `Abbrechen`).
4. **Bound the "100 %" claim** where it is written: add the three uncounted
   `_set_hint` strings (§1.5) or state that the metric counts helper calls and
   `.text` sites only.

---

## 9. What moved during this audit (for the record)

The implementer edited the tree between 15:37 and 16:16. Two findings were
fixed while I was measuring, and the numbers below are the before/after of my
own observations — recorded so the integrator knows the reported totals are not
the 15:55 ones:

| time | tool | total | authored | notes |
|---|---|---|---|---|
| 15:37 | `p3_string_audit.py` mid-edit | — | — | `NameError: ROUTED_MARKERS` (transient) |
| 15:55 | `2bf7c304` | 298 | 205 | prefix rule present; 11 false `authored`; `Touch Look` uncounted |
| 16:09 | `2bf7c304` + new `hud.gd` | 299 | 205 | duplicate map-footer build added |
| 16:11 | `7aae4083` | 300 | 194 | **prefix rule removed**; `slider_label` added |
| 16:15 | `3dd68993` | 303 | 195 | `Touch Look` routed; two more rows |

The report was refreshed at 16:15 and now quotes 303 / 195 / 108, matching the
settled tree. My clean-room and strict recomputations agree with the final
tool.

---

## Appendix — commands run (serialised under `/tmp/opencode/tat2-godot.lock`)

```
python3 build/qa/w9/p3_string_audit.py --rev 8ce9a86
python3 build/qa/w9/p3_string_audit.py --same-files-as 8ce9a86
python3 build/qa/w9/p3_string_audit.py [--verbose] [--tsv /tmp/opencode/p3-final.tsv]
flock … tools/godot --headless --path game --script res://tests/test_w9p3_localization.gd
flock … tools/godot --headless --path game --script /tmp/opencode/probe_w9p3_c2.gd
flock … tools/godot --headless --path game --script /tmp/opencode/probe_w9p3_c2_english.gd
git show 8ce9a86:game/src/core/localization.gd   (function-level diff)
git diff 8ce9a86 -- game/tests/
git check-ignore -v build/qa/w9/p3_string_audit.py
python3 /tmp/opencode/w9p3_recount.py   # clean-room recount: 303/303
python3 /tmp/opencode/w9p3_fuzzy.py     # 0 prefix-only "authored" rows
python3 /tmp/opencode/w9p3_portcopy.py  # 108 authored=0 rows, labels
python3 /tmp/opencode/w9p3_english.py   # old literal vs rendered English
```

---

## Re-audit (3a9aa34)

Scope: confirm the four closing conditions only; no source or test was edited and
the earlier audit is not re-derived. HEAD
`3a9aa34aeeffc057a36c2eb16f7f365ea9b4f7eb` on `rem/w9-p3`; the audited files are
clean (`git status --short` empty for them) and the worktree tool is byte-identical
to HEAD (`f5d55afc…` both sides).

### C1 — tool committed, prefix rule gone, runs — **FIXED**

```
$ git ls-tree -r --name-only HEAD | grep p3_string_audit.py
build/qa/w9/p3_string_audit.py

$ git check-ignore --no-index -v build/qa/w9/p3_string_audit.py
.gitignore:25:build/qa/*	build/qa/w9/p3_string_audit.py
$ git check-ignore -v build/qa/w9/p3_string_audit.py    # index-aware
(no output — tracked, so not ignored)
```

The `.gitignore` rule still matches with `--no-index`, i.e. the file is tracked
because it was **force-added**, as required. The rule still applies to any *new*
evidence file.

```
$ git show HEAD:build/qa/w9/p3_string_audit.py | grep -c "No prefix inference"
1
```

`authored_match()` now returns `False` after the exact / ALL-CAPS title-case
checks; there is no prefix or truncated-head inference left.

```
$ python3 build/qa/w9/p3_string_audit.py --rev 8ce9a86
UI_STRINGS total=151 routed=26 authored=51 routed_authored=26 invented=100
COVERAGE routed/total=0.1722
COVERAGE authored_routed/authored=0.5098
KINDS _loc=3 _loc_upper=5 hint=4 hud_feedback=13 literal=107 slider_label=1 st_text=10 st_upper=8

$ python3 build/qa/w9/p3_string_audit.py --same-files-as 8ce9a86
UI_STRINGS total=271 routed=271 authored=160 routed_authored=160 invented=111
COVERAGE routed/total=1.0000
COVERAGE authored_routed/authored=1.0000
KINDS _loc=5 _loc_upper=5 loc=125 loc_template=4 st_template=9 st_text=54 st_upper=69

$ python3 build/qa/w9/p3_string_audit.py
UI_STRINGS total=306 routed=306 authored=195 routed_authored=195 invented=111
COVERAGE routed/total=1.0000
COVERAGE authored_routed/authored=1.0000
KINDS _loc=5 _loc_upper=5 loc=125 loc_template=4 st_template=9 st_text=83 st_upper=75
```

The plain run is exactly the expected **306 / 306 / 195 / 111**, coverage
1.0000 / 1.0000. The before/same-files numbers moved from the 16:15 audit
(147→151, 268→271) because the new `hint` rule counts the old wardrobe
`_set_hint(...)` literals: the baseline legitimately grows when the universe
widens. `p3-report.md` §0 quotes the same 26/151, 306/306, 195/195, 111.

Per file: `hud 69/69`, `mission_controller 36/36`, `mission_prep_ui 34/34`,
`wardrobe_ui 28/28`, `ledger_ui 24/24`, `contract_table_ui 21/21`,
`post_match_ui 21/21`, `mobile_touch_ui 16/16`, `settings_ui 15/15`,
`main_menu 14/14`, `progression_ui 9/9`, `loot_container 9/9`,
`tutorial_ui 5/5`, `clue_item 3/3`, `loading_screen 2/2`.

### C2 — DesktopQuality wording — **FIXED**

`p3-report.md` §2.1 now reads:

> Two authored keys are genuinely missing from the producer
> (`Settings.Volume.AmbienceVolume`, `Settings.Volume.UIVolume`) and stay
> English; `Settings.GraphicsQuality.DesktopQuality` was a port key-name error
> (the authored row is `Settings.GraphicsQuality`), and `Settings.Header` is
> also missing (the settings title falls back).

Code confirms it:

```
$ sed -n '620p' game/src/ui/settings_ui.gd
	lab.text = _label("Settings.GraphicsQuality", "Graphics Quality")

$ grep -rn "DesktopQuality" game/src/
(none)
```

### C3 — PORT COPY labels — **FIXED**

```
$ sed -n '536,537p' game/src/ui/contract_table_ui.gd
	# "Cancel" is an authored locres source (reverse-map ALL-CAPS normalisation).
	cancel_btn.text = InputGlyphs.prompt("pause", UIStringsScript.loc("CANCEL"))

$ sed -n '1472,1474p' game/src/ui/hud.gd
	# "Crank" is an authored source (ST_Tools Tools_Deploy_Crank / the locres);
	# [RMB] is the live secondary-action glyph.
	_crank_prompt_lbl.text = InputGlyphs.prompt("secondary_action", UIStringsScript.loc("Crank").to_upper())

$ sed -n '553p' game/src/ui/mobile_touch_ui.gd
			label.text = UIStringsScript.loc("Mask").to_upper() ## PORT COPY (no authored row)
```

`CANCEL` is routed through `Loc` and is an authored source; `Crank`'s comment is
corrected to name the authored source; `MASK`'s comment is unchanged and the
reason is documented in `p3-facts-strings.md:704` ("only unrelated Nanite 'Mask'
in sources.json") and `:818` ("`MASK` -> Nanite `Mask` (cleared)").

Translation note (not a condition failure): the exact source `CANCEL`
(GUID `2571C234…`) has **no de-DE row**, so the button still renders English in
German; the title-case source `Cancel` (GUID `020697CD…`) carries
`de = Abbrechen`. Routing `CANCEL` is correct; the German string is a
translation-table gap, not a code gap.

### C4 — metric bounds — **FIXED**

```
$ sed -n '73p' build/qa/w9/p3_string_audit.py
    ("hint", re.compile(r"\.?_set_hint\(\s*" + ARG + r"\s*\)"))
```

The regex now accepts the no-dot call form, and the wardrobe hints are routed
and counted (`wardrobe_ui.gd` 28/28, was 24/24):

```
RX game/src/ui/wardrobe_ui.gd:496  'The Chameleon is locked. Unlock it in the Black Market (£10,000, Contract 3).'
RX game/src/ui/wardrobe_ui.gd:1029 'The Chameleon is locked. Unlock it in the Black Market (£10,000, Contract 3).'
RX game/src/ui/wardrobe_ui.gd:1077 'Locked - '
RX game/src/ui/wardrobe_ui.gd:1077 'Locked - not owned'
```

Every non-empty `_set_hint(...)` in `wardrobe_ui.gd` is now
`UIStringsScript.loc(...)` / `.st_text(...)`; the only bare calls left are
`_set_hint("")`. **No visible wardrobe hint is outside the universe.**

Remaining uncounted literals found (noted, not gating):

* `settings_ui.gd:939` `"That input cannot be bound here."` — inside `str(...)`.
  Runtime passes it through `Loc.t` (unknown source → English) but the `status`
  regex only matches a direct literal argument.
* `settings_ui.gd:901` `"[ UNBOUND ]"` — a visible conditional fallback in a
  `.text` assignment whose RHS starts with `"["`; the tool's head-literal rule
  reads `"["` (a keycap) and skips it. It is not routed.
* Format-only wrappers (`hud.gd:3770` `"◆ %s (%s)"`, `ledger_ui.gd:205`
  `"[%s] %s"`, `contract_table_ui.gd:331` `"#%02d  %s"`) carry routed content and
  are not copy; the surrounding assignments are not counted as rows.

### Regression check at 3a9aa34

```
$ flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game \
    --script res://tests/test_w9p3_localization.gd'
TAT-2 Loc: 8 translations, reverse map 2946/3404 en.csv keys, locale=en
W9P3_LOC_SUMMARY: fails=0 checks=19
```

### Updated verdict

**AUDIT: PASS** — all four conditions **FIXED** at `3a9aa34`; one
translation-table note (`CANCEL` has no de-DE row) and two sub-row metric gaps
(`settings_ui.gd:939` inside `str(...)`, `settings_ui.gd:901` `[ UNBOUND ]`)
recorded for the next pass. No source or test defect remains from the C2 audit.
