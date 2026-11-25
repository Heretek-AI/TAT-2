# W9-P1 / A2 — independent audit (adversarial)

Auditor: independent A2 auditor (did not write this code).
Worktree: `/home/john/Projects/TAT-2-rem-w9-p1`.
Scope: commit `bb37003` (authored progression) + the `game_data.gd` endgame hunk
carried by `5b112b1`.
HEAD moved three times during this audit (`ff0f21d`, `5a516f9`, …) because other
lanes commit into the same worktree; **every scoped file is byte-identical
between `bb37003` and the HEAD audited below** (`git diff --stat bb37003..HEAD --
<scoped files>` → empty).
Test runs used `tools/godot` 4.7.2 headless under
`flock /tmp/opencode/tat2-godot.lock`, one instance at a time.

Method: read the diff and the data, recompute the authored numbers from the
generated JSON independently, run every lane test that is standalone-runnable,
and try to break the migration/precedence claims. The full `run_tests.gd` gate
is **not** independently executed here (it exceeds the 300 s per-invocation
Godot budget imposed on this audit); see “Not verified”.

---

## 1. Was any existing test weakened? — **AUDIT: PASS**

`git diff c2a1cd8..HEAD -- game/tests/test_w7e_endgame.gd
game/tests/test_t02_save_integrity.gd game/tests/test_w7s_loot_save.gd` shows
only the hunks below. No assertion is deleted, none is loosened (the three
endgame checks gain a `endgame_source` clause), and each hunk carries a reason.

| Assertion | Old → new | Verdict |
|---|---|---|
| `test_w7e_endgame.gd:149-156` S5.1c | endgame 300 / `quest_graph` → 1200 / `project_settings`; main 7200 unchanged | PASS — the **old 300 was the authored QG plan**, not an invented value; the change is a precedence decision, documented in-line. It is not a goalpost move (the QG value is still asserted in S5.2a and W9.4d). Caveat F4. |
| `test_w7e_endgame.gd:161-169` S5.1d | endgame 480 → 1200 / `project_settings` | PASS — same reason; OldManor Vault's QG 480 stays asserted by W9.4d. |
| `test_w7e_endgame.gd:189-197` S5.2d | 300 / `quest_graph` → 1200 / `project_settings` | PASS — same reason; S5.2a `QG plan endgame stays 480` untouched (line 174). |
| `test_t02_save_integrity.gd:144` T02-01 | recovered currency 0 → 5000 | PASS — the corrupt-load path keeps the *default* profile (`_report_load_failure` → `_ensure_defaults`, line 1025) and writes nothing; the default currency is now the authored floor. |
| `test_t02_save_integrity.gd:263,267` T02-05 | 600 → 5500 (staged 100 + payout 500) | PASS — arithmetic: 5000 floor + 500. **The +500 settle delta is preserved**, which is what the test exists to prove. |
| `test_t02_save_integrity.gd:297,302` T02-06 | 300 → 5300 | PASS — fresh `_new_save()` carries the new default 5000 + 300; the replay is still a no-op. |
| `test_w7s_loot_save.gd:200,205` 90.30/90.33 | 800 → 5700 (staged 100 + pending 700) | PASS — same +5000 default, +700 settle delta preserved, second load still proves no double-bank. |
| `run_tests.gd:4302-4312,4324-4330` suite 49 | currency 0 → 5000 (cases A and B) | PASS — both cases stage `_defaults()`; case A also has a completed contract, case B a non-empty `completed_contracts`, so the migration clause is a no-op and 5000 is the default. |

The decisive control is the assertion the lane **did not** touch:
`test_t02_save_integrity.gd:187-200` stages `currency = 777` **plus a completed
contract** and still expects `777` (suite 92; reviewed here, not re-run — see
“Not verified”). That is the “veteran keeps their money” case, and it proves the
+5000 shifts above are not a blanket re-baseline.
Likewise `test_w7s_loot_save.gd:155,159,176,230` (2500, 2500, 123, 900) are
unchanged (suite 90; reviewed, not re-run).

No test was skipped or deleted. **Every changed expectation is a consequence of
one intended product change (default currency 0 → 5,000) or the documented
endgame precedence change; none is a lowered bar.**

---

## 2. The authored trajectory — **AUDIT: PASS**

Read directly (not via the port):
`game/data/generated/project_settings.json` (`progression.maximum_level = 25`,
`level_up_xp = 500`) and
`game/data/generated/tables/Gameplay/Tuning/CT_XPToLevel.json` (`XPToLevel` keys
`(0,0) (1,500) (4,500) (5,1000) (9,1000) (10,2500) (24,2500)`,
`RCIM_Linear`, constant extrapolation).

Independent recomputation (linear interpolation, integer levels land on keys):

```
L1-4   = 500  (4 x 500  =  2,000)
L5-9   = 1000 (5 x 1000 =  5,000)
L10-24 = 2500 (15 x 2500 = 37,500)
cumulative to L25 = 44,500
```

`res://tests/test_w9_progression.gd` (run twice) matches exactly:

```
PASS: W9.2a xp_threshold_for_level 1..25 equals the authored CT_XPToLevel curve
PASS: W9.2b groups: 1-4 = 500, 5-9 = 1000, 10-25 = 2500
PASS: W9.2c cumulative: L1=0, L2=500, L5=2000, L10=7000
PASS: W9.2d total(25)=44,500 and 26+/200 clamp to 44,500
PASS: W9.1c 500,000 XP loads to level 25 and keeps every point (xp=500000)
W9_PROGRESSION SUMMARY: fails=0
```

Cap-with-XP-kept independently confirmed in code and by the run:
`save_system.gd:1213-1224` `level_for_xp` stops at
`clampi(mini(MAX_SAVE_LEVEL, Progression.maximum_level()), 1, MAX_SAVE_LEVEL)`
(25) and never subtracts XP past it; `xp_total_for_level` clamps the *target* to
25, so `xp_total_for_level(26) == 44500` (`save_system.gd:1201-1209`, W9.2d).
`xp` is untouched at 500,000 (`_sync_level_from_xp` only clamps to
`MAX_SAVE_XP = 1_000_000`, line 768).

**Claim count is wrong, not the test:** the commit says “36 PASS”. The file has
36 `_check(` *occurrences* including the function definition
(`grep -c "_check(" → 36`), i.e. **35 call sites**; the run prints 35 `PASS: W9`
lines. See F1.

---

## 3. Does the migration corrupt a profile? — **AUDIT: PASS**

Load path (`save_system.gd:945-1000`): `_merge_validated` (unknown root keys are
dropped, `save_system.gd:444-450`), `_ensure_defaults` (backfills
`progression_schema`/`progression_migrated`), `_sync_level_from_xp`, then
`_migrate_progression` (`save_system.gd:749-762`):

```gdscript
if bool(data.get("progression_migrated", false)):
    return false
var has_contracts: bool = cc_v is Dictionary and not (cc_v as Dictionary).is_empty()
if not has_contracts and int(data.get("currency", 0)) < floor_money:
    data["currency"] = floor_money
data["progression_schema"] = PROGRESSION_SCHEMA_VERSION
data["progression_migrated"] = true
```

| Case | Result | Evidence |
|---|---|---|
| v8 save, contracts + 1,234 currency | 1,234 survives; stamp added; write once | `has_contracts` → no grant. Reviewed control (suite 92, not re-run): `test_t02_save_integrity.gd:187-200` (777 + contract → 777). Executed: W9.5b (`0` + contract → `0`). |
| empty profile, 123 currency | → 5,000 **once** | Executed: `PASS: W9.5c empty profile with 123 is raised to 5,000 on load`. |
| spend it to 2,500, reload | stays 2,500 | Executed: `PASS: W9.5d after spending to 2,500 a reload does not re-grant`. |
| any completed contract | never granted | Executed: `PASS: W9.5b contract 1 completed + currency 0 stays 0 (migration still stamps)`. |
| unknown/future root key | dropped, not fatal | `_merge_into` `if not target.has(key): … continue` (`save_system.gd:447-450`); the load path has no error branch for unknown keys. |
| corrupt bytes | defaults in memory, nothing written | `_report_load_failure` (`:1009-1027`) quarantines and returns before the migrations; T02-01 (reviewed). |
| no save file | defaults 5,000, flag set in memory; first real `write_save` persists it | `load_save` no-file branch (`:945-955`); the flag is mutated in `data` even though that branch does not write. |

No path lowers `currency`, rewrites `completed_contracts`, destroys `xp`
(only `MAX_SAVE_XP`, pre-existing), or drops unlocks (`_ensure_defaults` still
appends the starter lists; `level_for_xp` only lowers an inflated legacy level
to 25, and no gate requires > 25 — `unlocks.json` max is 25).

Two non-corrupting observations:
- **F6**: the W9 test docstring (`test_w9_progression.gd:22-23`) and the commit
  message say the developer save “is never read or written”. False: the
  SaveSystem autoload `_ready()` (`save_system.gd:211-214`) calls `load_save()`
  on `user://tat2_save.json`, and the new migration writes it. My own run
  changed that file: `…/Thick As Thieves 2/tat2_save.json`, mtime
  `2026-11-25 11:23:24`, now `currency 5000, progression_migrated true`. This is
  product behaviour (and pre-W9 boots already wrote pending migrations), but the
  claim as written is wrong and should be corrected.
- Spending a banked **timeout** run (no completed contract) before the upgrade
  re-earns the floor once; that is the documented “empty profile” rule, not
  corruption.

---

## 4. KF13 precedence — **AUDIT: PASS**

`game/src/core/game_data.gd:725-740`:

```gdscript
func get_mission_endgame_seconds(mission_id: String, difficulty_index: int = -1) -> float:
    var ov_v: Variant = briefing_overrides.get(mission_id)      # 1. KF13
    if ov_v is Dictionary: … return float(secs)
    var idx: int = difficulty_index if difficulty_index >= 0 else current_difficulty_index
    if idx >= 0 and Progression.endgame_ladder_authored():      # 2. ladder
        return Progression.endgame_seconds_for_difficulty(idx)
    var plan: Dictionary = get_mission_plan(mission_id)         # 3. QG
    return float(plan.get("endgame_duration", 0.0))
```

and the 4th level is `mission_controller.gd:95,808-810`
(`ENDGAME_FALLBACK_SEC = 480.0` when the resolved limit is `<= 0`).

`game/data/expansion/briefing_overrides.json` has exactly one row,
`Mission.Guildhall.LootTheRoom` → `endgame_seconds: 1200, source: "KF13"`.

Proven at runtime (standalone W7E, `W7E_SUMMARY: fails=0`):

```
TAT-2 run clock: map=guildhall mission=Mission.Guildhall.LootTheRoom main_s=3300.0 main_source=mission_row endgame_s=1200.0 endgame_source=KF13
PASS: S5.2b runtime endgame=1200 s from the KF13 override
TAT-2 run clock: map=guildhall mission=Mission.Guildhall.VaultHeist … endgame_s=1200.0 endgame_source=project_settings
PASS: S5.1c contract deploy resolves the authored per-map contract row (7200 s main + authored 1200 s Novice endgame)
PASS: S5.1d OldManor contract deploy resolves Mission.OldManor.Vault (7200 s main + authored 1200 s Novice endgame)
PASS: S5.2a QG plan endgame stays 480 s (no silent re-baseline)
PASS: S5.2d VaultHeist uses the authored 1200 s Novice endgame ladder
TAT-2 run clock: map=guildhall mission=- main_s=7200.0 main_source=map_row endgame_s=480.0 endgame_source=fallback
```
`get_mission_plan(...).endgame_duration` is still 480 / 300 / 480
(`PASS: W9.4d QG plans unchanged: LootTheRoom 480, VaultHeist 300, OldManor Vault 480`).

The KF13 letter therefore still wins for LootTheRoom at every difficulty
(W9.4a `… at difficulty index 0/1/2`, source `KF13`). Caveat **F4** applies to
the *ladder vs QG* level only.

---

## 5. Endgame ladder correctness — **AUDIT: PASS**

`progression.gd:290-306` clamps `index` to `arr.size() - 1` and applies
`maxf(value, 0)`; `:312-320` (`endgame_ladder_authored`) returns false when the
array is missing/empty/non-numeric, and `game_data.gd` then keeps the QG plan.
So a wrong index selects the nearest authored row (never 0 s from an
out-of-range index), and a broken ladder falls back to the QG value rather than
inventing a window. A *published* index of `2` yields 300 s, not 0.

- Index→difficulty mapping: documented as a port decision in
  `progression.gd:49-58` (`PORT DECISION (difficulty mapping)`, 1/2/3 =
  Easy/Normal/Hard) and repeated at `:292-294` (“carried here, not proven”).
  The producer label `project.difficulty_index_source = "unproven: index order
  only"` is quoted in the code. **PASS.**
- Den hub stays 0: `mission_controller.gd:774-788` returns before any
  `get_mission_endgame_seconds` call and sets `endgame_time_limit = 0.0`;
  `test_t02_state_lifecycle.gd:288` pins it. **PASS.**
- Mission with no index keeps 480: with `current_difficulty_index = -1` the
  accessor returns the QG plan (`OldManor Vault = 480`, W9.4d) and the
  controller falls back to 480 when the plan is absent (S5.1b above). **PASS.**
- Executed: `PASS: W9.4b VaultHeist ladder 1200/600/300 with source
  project_settings`; `PASS: W9.4e _apply_run_clock (unedited) gets 1200/600/300
  from GameState.reset_run()`.

Caveat **F4** (not a code defect): the *ordering* of the ladder above the
per-mission QG value is an unproven port decision; only the index map is
labelled as such.

---

## 6. The 48 market gates — **AUDIT: PASS**

Independent count from `game/data/generated/gameplay/unlocks.json`:
68 entries, **48** with a positive numeric `requires_level`; distribution
`2:2, 3:1, 4:2, 5:1, 6:3, 7:1, 8:2, 9:2, 10:3, 11:4, 12:2, 13:2, 14:2,
15:3, 16:2, 17:2, 18:2, 19:2, 20:3, 21:2, 22:2, 23:1, 25:2` — levels **2..23
and 25**, exactly as claimed. `requires_contract` is `null` on every row.
The two level-25 rows are `Outfit.Spider.CallingCard.ModelShip` and
`Outfit.Chameleon.CallingCard.ModelShip`.

`res://tests/test_w6u2_catalog.gd`:

```
PASS: W6U2.31 insufficient funds fails closed (Insufficient funds (have (£) 0, need £ 5,000))
PASS: W6U2.32 a locked row cannot be bought and shows its gate (Requires Level 5)
…
W6U2_SUMMARY: fails=0
```

and W9.6b/6c (executed in the W9 run) check every gate at `xp_total_for_level(n)`
and `… - 1`, plus 44,499 → level 24 / locked and 44,500 → level 25 / unlocked:
`PASS: W9.6c level 25 (2 ModelShip rows) is reachable at 44,500 XP, locked at
44,499`. My cumulative table independently gives 44,499 → 24 (needs 44,500).

---

## 7. No invented numbers — **AUDIT: PASS**, with three findings

Every authored constant added to `game/src` is a named, documented fallback
(`Progression.FALLBACK_*`, `progression.gd:30-47`) and every getter counts its
fallback use (`_note`, `load_diagnostics`, `fallback_count`). The authored
values reach runtime from JSON, not literals (W9.0c/0d read `raw()`).

Findings:
- **F5 (latent drift, P3):** `game_state.gd:291`
  `GameData.current_difficulty_index = clampi(difficulty - 1, 0, 2)` hard-codes
  the top ladder index instead of deriving it from
  `project.endgame_durations_by_difficulty`. A fourth difficulty/ladder row
  would silently publish index 2 (300 s) for difficulty 4.
- **F9 (P3):** `save_system.gd:1171` `var difficulty: int = 1` — the Novice
  fallback used when `GameState` is absent is not labelled as a fallback in the
  comment block. Fail-closed (minimum award), but undocumented.
- **F3 (P2, false comment):** `progression.gd:274-275` says the FTUE per-tag
  credit is “the smallest authored category weight (`contracts_xp = 20`)”.
  It is not the smallest: `open_queue_xp = 5`, `minor_loot_xp = 2`,
  `major_loot_xp = 6`. The value is correctly labelled a PORT DECISION; the
  justification is false and should be restated (“the contract-completion
  weight”).

No authored gameplay value is hidden as a bare literal in the new code.

---

## 8. `run_tests` integration — **AUDIT: PASS** (registration), full run not executed

Suite 99 (`game/tests/run_tests.gd:7490-7516`) is registered before the final
summary (`:7533`) and mirrors the established suite-83 child-engine pattern:

```gdscript
var w9p_args: PackedStringArray = [
    "--headless",
    "--path", ProjectSettings.globalize_path("res://"),
    "--script", "res://tests/test_w9_progression.gd",
]
var w9p_code: int = OS.execute(OS.get_executable_path(), w9p_args, w9p_out, true)
…
if w9p_code != 0 or w9p_text.find("W9_PROGRESSION SUMMARY: fails=0") < 0:
    printerr("FAIL: 99 …"); fails += 1
```

Exit code **and** summary are both required (fail-closed); the child prints
`W9_PROGRESSION SUMMARY: fails=0` and `_finish()` calls
`quit(0 if fails == 0 else 1)`. The child isolates its fixtures under
`user://w9_progression/` (no other suite's path).

Registration markers are unique:
`# 35b.` at `:3217`, `# 98. W9-P1-A4 night-grade guard` at `:7414`,
`# 99. W9-P1 A2 authored progression` at `:7490` — one each, in that order,
before the summary. (`W9-P1-A4 night-grade guard` appears 3× on screen because
the block has a comment, a `printerr` and a `print`; there is one suite.)

Not executed: the full `run_tests.gd` (see below), so suite 49/90/92 as run by
the registry are reviewed but not re-run.

---

## Findings (none blocks the code; F1/F2 must be fixed before the wave report)

- **F1 (P2, evidence claim):** commit `bb37003` says “36 PASS”; the suite has
  35 checks and prints 35 PASS (`grep -c "_check("` = 36 includes
  `func _check(...)`). Summary `fails=0` is correct.
- **F2 (P2, evidence):** the commit points at `build/qa/w9/p1-report.md` for the
  tables; **that file does not exist** (`find . -name 'p1-report*'` → nothing
  outside `extracted/`). `build/qa/*` is git-ignored, so this is a missing local
  artifact, not a committed one — but the claim is unverifiable as written.
- **F3:** false “smallest authored category weight” comment (see §7).
- **F4 (P2, fidelity decision):** the *precedence* “authored ladder > per-mission
  QG EndgameDuration” is a port decision with no cited evidence. It changes the
  runtime window of `Mission.Guildhall.VaultHeist` from the authored QG 300 s to
  1200 s at Novice (4×) and `Mission.OldManor.Vault` 480 → 1200. The index map
  is labelled as a port decision; the precedence level is not. Either label it
  as a port decision (with evidence) or cite the shipped code path that proves
  `EndgameDurationsByDifficulty` outranks the QG node.
- **F5:** hard-coded top ladder index `2` in `game_state.gd:291`.
- **F6:** “developer save … never read or written” is false; the autoload boot
  migrates it (observed; the file changed during my run). See §3.
- **F7 (P3, cosmetic):** at the cap, `get_level_progress()` returns
  `xp_needed = 2500` (the level-25 curve sample), so a max-level profile shows
  `2499/2500` forever (`save_system.gd:1408-1414`). Not a level-up loop
  (`in_level` is clamped to `needed - 1`), but “MAX” would be honest.
- **F8 (P3, integration):** at committed HEAD,
  `tools/consumer_allowlist.json` still lists `project_settings.json` as
  `blocked_on_team` (`optional: true`) although `progression.gd` now reads it.
  Harmless today (the checker `continue`s on reachable files and the rule is
  optional), and the working tree has an uncommitted removal — but the A2
  commit should have dropped the rule. `tools/check_consumers.py` on the current
  tree: `CONSUMER AUDIT PASS`, 215 files, 151 runtime-read.

## Not verified

- **Full `run_tests.gd`** (the 301-pass wave gate). It cannot be run inside the
  300 s per-invocation limit imposed on this audit; no post-W9 `run_tests` log
  exists under `build/qa/w9/logs/` (only `p1_baseline_run_tests.log`, 08:18,
  pre-change). The changed T02/W7S/suite-49 assertions are `RefCounted
  run(host)` suites and are not standalone-runnable (they `preload`
  `save_system.gd`, whose `GameData` static reference was already there at
  `c2a1cd8`; standalone invocation fails to compile, pre-existing).
- Explicit `$?` capture of the W9 child process: the confirmation run never
  acquired the shared `flock` (another lane held it for > 4 min) and was
  cancelled before it launched Godot; the output file was never created. The
  exit path is `_finish() → quit(0 if fails == 0 else 1)` and the run printed
  `fails=0` twice.
- `make audit` / `make gate-ratchet` re-stamp for this wave. `make
  gate-ratchet` passes on the committed R8 evidence
  (`GATE_RATCHET: PASS … measured_on=e3678be`); the W9 tree still needs its own
  logs and report before the wave closes.

## Measured runs (all headless, serialised)

```
test_w9_progression.gd   W9_PROGRESSION SUMMARY: fails=0   (35 PASS)
test_w7e_endgame.gd      W7E_SUMMARY: fails=0
test_m2_player.gd        M2_SUMMARY: fails=0
test_w6u2_catalog.gd     W6U2_SUMMARY: fails=0
make gate-ratchet        GATE_RATCHET: PASS
check_consumers.py       CONSUMER AUDIT PASS (215 files, 151 runtime-read)
```

## VERDICT

**AUDIT: PASS** for all eight items. The authored numbers reproduce from the
generated data, the level cap keeps XP, the KF13 letter still wins, the ladder
cannot produce a silent 0 s, the 48 gates and the 44,500 boundary are correct,
and no existing test was weakened — every changed expectation is the arithmetic
of the intended 5,000 default or the documented endgame precedence, with the
veteran control (`777` with a contract) left untouched.

The code is sound; the **evidence claims need correction**: F1 (35 PASS, not
36), F2 (missing `p1-report.md`), and F4 (the ladder-over-QG precedence is an
unproven, unlabelled port decision that changes the shipped VaultHeist window
4×). Those are documentation/decision-record defects, not behaviour defects, and
none is a reason to reject the commit — but F1/F2/F4 should be fixed in the W9
report before the wave is called green.
