# W9-P2 B2 — independent audit (AUDIT-B2)

**Auditor:** independent B2 auditor (did not write the code under review).
**Worktree:** `/home/john/Projects/TAT-2-rem-w9-p2`, branch `rem/w9-p2`.
**Base HEAD:** `b13260b` (`docs(w9): P1 report — ratchet target and the docs owed at
integration`) + the lanes' uncommitted working tree.
**Date:** 2026-11-25.
**Mode:** read-only. This file is the only repo file written. No commit, no
producer edit, no capture, no Vulkan. `game/assets`, `game/data/generated` and
`extracted` are symlinks into the main checkout and were only read.

**Verdict: `AUDIT: PASS`** — every lead claim under audit is true and the
consumer/producer halves are exact. One documentation defect (F1) must be fixed
before the integrator follows the regeneration acceptance steps; it is not a
code or gate defect. Details in “Findings”.

---

## 0. What was run (all headless, one Godot at a time under the lock)

Every Godot invocation was:

```bash
flock /tmp/opencode/tat2-godot.lock -c \
  "timeout 900 tools/godot --headless --path game --script <script>"
```

| # | Script | Result (verbatim marker) |
|---|---|---|
| 1 | `res://tests/test_w9p2_locks.gd` | `LOCKS PASS checks=28` (exit 0, 28 PASS / 0 FAIL) |
| 2 | `res://tests/test_lockpick_cancel.gd` | `LOCKPICK_CANCEL PASS checks=18` (exit 0) |
| 3 | `res://tests/test_lockpick_hands.gd` | `LOCKPICK_HANDS PASS checks=20` (exit 0) |
| 4 | `res://tests/probe_lock_inventory.gd` | `LOCK_INVENTORY PASS authored_containers=157 authored_doors=8 authored_windows=8 locked_now=0` (exit 0) |
| 5 | `res://tests/run_tests.gd` | `SUMMARY: fails=0`, **308** `PASS:` lines, **0** `FAIL:` lines, exit 0 |
| 6 | `tools/check_scripts_compile.gd` | `scripts checked: 164, broken: 0` |
| 7 | `/tmp/opencode/b2audit/esc_repro2.gd` (live / revert) | audit-only ESC repro, see §4 |
| 8 | `/tmp/opencode/b2audit/esc_real_control.gd` (live / revert) | audit-only real-main-loop ESC control, see §4 |
| 9 | `/tmp/opencode/b2audit/count_locks.py` | independent raw-dump census, see §1 |
| 10 | `/tmp/opencode/b2audit/join_locks.py`, `probe_post_regen.py` | independent generated↔authored join, see §3/§9 |

Suite 101–105 lines from the full run:

```text
PASS: 101 W9-P2 B2 authored locks (cap-as-level, key-only/window exclusions, no invented level) (910 ms)
PASS: 102 W9-P2 B2 lockpick ESC cancel does not open pause (LV4 path) (1376 ms)
PASS: 103 W9-P2 B2 labelled lockpick hands stand-in (no authored mesh/animation) (1387 ms)
PASS: 104 W9-P2 B3 jam damage is the authored value (no balance change) (3249 ms)
PASS: 105 W9-P2 B3 magic-door continuity during the endgame (dormant never extracts) (2139 ms)
SUMMARY: fails=0
```

The b2 report says the compile count is 165; it is 164 now. That counter moves
with the other lanes' uncommitted scripts — not a defect, 0 broken either way.

---

## 1. Claim 1 — authored data (PASS)

> 173 placed `_locked` (157 containers / 8 doors / 8 windows); no per-instance
> level anywhere; caps 155×2 / 3×1; the producer drops all lock fields;
> generated data has 0 lock records; runtime 0 locks.

**Independent census** (`count_locks.py`, walks `extracted/json`, keeps records
whose `Outer.ObjectName` starts with `Level'` and `Properties._locked is True`):

```text
scanned json files: 12541
TOTAL placed _locked=true: 173
families: {'container': 157, 'door': 8, 'window': 8}
caps (0 == none): {0: 15, 1: 3, 2: 155}
can_lockpick placed values: {'False': 4}
```

Per class (matches the probe's own table exactly):

```text
BP_BookcaseB_C 2 | BP_ChestTrunk_C 3 | BP_ChestTrunk_MajorLoot_C 89
BP_DisplayCaseA_MajorLoot_C 55 | BP_GB_DoorSolo_C 1 | BP_Manor_WindowB_4x650_C 2
BP_OldManor_Doorway_4x650_C 2 | BP_Prison_WallA_DoorwayB2_6x6_C 1
BP_Res_Int_Doorway_C 1 | BP_SM_OldManor_WindowB_4x850_C 6
BP_SmallSafe_MajorLoot_C 8 | BP_VaultDoor_Sliding_C 3
```

Per map: Guildhall_Loot 87, OldManor_Loot 65, OldManor_Geo 10, OldManor_Gameplay 3,
Building_Guildhall_POI 1, FTUE_JewelryStore 1, FTUE_SpawnArea 1, FTUE_Gameplay 3,
BeautifulCorner_Startscreen 2 (sum 173).

**No per-instance level:** every quoted key in the 12,541 JSONs that contains
`LockLevel` is `MaxLockLevel` (261), `MinLockLevel` (45) or `DamageByLockLevel`
(2). The exact key `"LockLevel"` occurs **0** times. The fact is therefore
“no per-instance level”, not “absent by accident”.

**Producer drops the fields:** `grep -i lock tools/parse_tables.py` finds no
`_locked` / `_lockConfig` handling (only unrelated lockpick-device validation),
`git diff -- tools/parse_tables.py` is 0 lines and `git status -- tools/` is
empty. Generated records carry no lock keys:

```text
generated pre-regen lock keys over 107 *.tatlevel.json:
  locked 0 | max_lock_level 0 | min_lock_level 0 | can_lockpick 0 | key_tag 0
marker keys:  basis,class,name,pos,scale,source
swing keys:   actor,basis,class,leaves,name,pos,source
```

`runtime 0 locks` is the probe's measured `locked_now=0`, and my own scan of the
generated tree agrees. **No window or key-only door is locked at runtime today**
(trivially: nothing is locked).

---

## 2. Claim 2 — the rule (PASS)

> Locked iff `locked == true`; level = authored `max_lock_level` cap
> (containers 1..6, doors 1..4), labelled a port decision; `locked` with no cap
> → 1; key-only and window actors excluded; `entry.lock_level` no longer read;
> old `3 + count % 2` / `count % 12 == 5` heuristics and the SceneVariant
> default 3 gone (now the authored cap 4).

**Code read (working tree, verbatim):** `loot_container.configure` —

```gdscript
if entry.get("locked") == true:
    var can_pick: Variant = entry.get("can_lockpick", null)
    if can_pick is bool and not bool(can_pick):
        _note_key_only_exclusion(p_class)
    else:
        var cap_lvl: int = int(entry.get("max_lock_level", 1))
        set_locked(true, clampi(cap_lvl, 1, 6))
```

`swinging_door.configure` — same shape, window first, then key-only, then
`clampi(cap_lvl, 1, LockableDoorScript.table_max_lock_level())`. Both are
commented as a labelled **port decision** (“the dump has no per-instance
LockLevel, so a record's level is its authored cap”), and that label is also in
`lockable_door.gd` and `mission_controller.gd`.

**Grep for invented values (every hit reported):**

| pattern | hits | verdict |
|---|---|---|
| `entry.get("lock_level"` | **0** | removed from both consumers |
| `set_locked(true, 3)` | **0** | old SceneVariant literal gone |
| `1 + (` | **0** | no cap formula |
| `count % 12` | **1**, `mission_controller.gd:4188` | a comment recording that the formula stays deleted |
| `3 + count` | 1, same comment | deleted |
| `% 2` | 8: `guard_ai.gd:1566` (scan phase), `level_loader.gd:6753` (light selection), `vfx_manager.gd:402/1044`, `mission_controller.gd:3751/3779` (guard lantern parity, carried-item parity), `light_probe.gd:260` (round-robin), `mission_controller.gd:4187` (the deleted-formula comment) | none lock-related |
| `% 3` | 8: `game_state.gd:54/486`, `vfx_manager.gd:1045/1113/1123`, `mission_controller.gd:1655` (difficulty cycle), `contract_table_ui.gd:526`, `mission_prep_ui.gd:1373` | none lock-related |

`lock_level` still exists as the **runtime member/parameter** on
`lockable_door.gd`, `loot_container.gd`, `swinging_door.gd` and the HUD; that is
the resolved node level, not `entry.lock_level`.

**SceneVariant level is the authored cap:** `interactables.json` has
`doors.max_lock_level = 4`; `tools/parse_interactables.py:267` reads it from
`BP_SwingingDoor.json` → `Default__BP_SwingingDoor_C._lockConfig.MaxLockLevel`,
which I read in the dump as `4`. `mission_controller.gd:4191` is
`door.set_locked(true, DoorScript.table_max_lock_level())` with
`const DoorScript := preload("res://src/interact/lockable_door.gd")`. No
invented 3 remains.

**`locked` with no cap → 1:** the 15 no-cap locked actors are 8 windows, 4
key-only doors (3 Vault + Res), 2 `BP_BookcaseB_C` (never spawned) and the
prison doorway (1 actor → 2 pivot nodes). Only the prison doorway exercises the
fallback, at 1, as documented.

---

## 3. Claim 3 — runtime blocked; producer contract exact (PASS + finding F1)

> BLOCKED-ON-INTEGRATOR-REGENERATION (producer contract + patch; `git diff --
> tools/parse_tables.py` empty; `git apply --check` passes); expected after
> regeneration 144 locked containers + 10 door nodes, 18 excluded (16 window +
> 2 key-only).

| Check | Result |
|---|---|
| `git diff -- tools/parse_tables.py` | 0 lines; `git status --short -- tools/` empty |
| `git apply --check build/qa/w9/parse_tables-lock-fields.patch` | exit 0, 5 hunks |
| patch on a pristine copy (`patch -p1` in `/tmp`) then `py_compile` | applies + `PY_COMPILE_OK` |
| patch keys vs consumer | `locked, max_lock_level, min_lock_level, can_lockpick, key_tag` — identical to `MARKER_LOCK_KEYS` and both `configure` readers; no sixth key, no rename |
| helper executes on the real dump (imported from `/tmp`) | `placed locked=True: 173 caps: {0:15, 1:3, 2:155}`; key sets `{locked+max:155, locked:10, can+key+locked:4, key+locked+max:3, key+locked:1, can+locked:2}` — matches the contract’s §4 output |
| `aidx` in scope at the door pre-pass | yes — `aidx = actor_by_name.get(actor_name)` is already used for `door_tag`/`door_group` two lines above; the patch reuses the same `exps[aidx].get("Properties")` |
| `props` in scope at marker/generic-actor sites | yes — both branches use the same `props` the existing record already reads `Tags`/`SpawnGroup` from |
| absence rule | `_authored_lock_fields` emits only keys present on the placed actor; `{}` → `{}`; `MaxLockLevel: 0` → `max_lock_level: 0` (consumer clamps to 1, no bug) |

**Independent join** (`join_locks.py`: every generated record resolved to its
owning raw actor in the same `source` JSON):

```text
locked container DISTINCT actors: 144   (markers: 144, actors: 144)
door nodes after the consumer rule: 10  {level_1: 2, level_2: 8}
window nodes (consumer excludes): 16
key-only nodes (consumer excludes): 2
```

This reproduces the lead’s **144 / 10 / 16 / 2** exactly. Level split 2×1 +
8×2 also matches (§5 of the contract). The prison doorway is the 2×level-1 pair;
its authored `_lockConfig` is `{"KeyTag": "Item.Key.Buildings.Guildhall"}` with
no `CanBeLockpicked` (actor `StaticMeshActor_528`), so the “pickable, lock at 1”
discrepancy the lane flagged against the brief is real and correctly documented.

### Finding F1 — the contract’s derived acceptance numbers are wrong (docs only)

The distinct-actor figures above are right, but the **numbers the integrator is
told to expect from the raw regenerated files are not**, because the same
authored actor is emitted into **both** `markers` and `actors` (the producer’s
marker branch does not `continue`; the generic-actor branch 4b then runs too —
visible today: Guildhall_Loot has 48 chest markers and the same 48 chest
actors). Exact post-regeneration values, resolved record-by-record:

```text
markers:         161   (144 supported containers + 8 BP_SmallSafe markers + 9 door markers)
actors:          173   (all authored locked actors)
swinging_doors:   28   (10 applied doors + 16 windows + 2 key-only)
=> probe locked_now = 362
```

So on the integrated tree:

* `probe_lock_inventory.gd` will print **`locked_now=362`**, not `154`
  (`b2-impl.md:282,311,316` and `b2-producer-contract.md:273`);
* the contract §6 step-3 snippet will print **`marker_locked=334`,
  `door_locked=12`, `window_locked=16`**, not `144 / 10 / 0`
  (`b2-producer-contract.md:249-250`).

The **gameplay** outcome is unaffected and remains 144 locked containers +
10 locked door nodes (the loader reads `markers` for containers and
`swinging_doors` for doors; it never reads `actors`), and the probe still exits
0 (its `fails` come only from the authored assertions). But an integrator who
follows steps 3/5 literally will see mismatched numbers and may “fix” a correct
producer. Required correction before integration: either count distinct
`(class, name)` for containers and read only the `markers` array, or restate the
expected values as above. Suggested probe fix: count `markers`-only containers +
`swinging_doors`, and report the two arrays separately.

---

## 4. Claim 4 — the ESC bug (PASS, independently reproduced RED→GREEN)

> RED `LOCKPICK_CANCEL FAIL checks=18 fails=2` (paused=true), GREEN
> `LOCKPICK_CANCEL PASS checks=18`; the guard is the minimal
> `_pause_consumed_frame` stamp checked in `_process`.

I did not revert the repo. Instead I rebuilt the HUD at runtime with **exactly
the three B2 hunks removed** and proved the result is byte-identical to HEAD:

```text
working tree hud.gd sha256 : 9c9018d2c4dc2fe8fbf98c2b4a93780c8b6911a7741a1320785369bb792dc9c5
git show b13260b:hud.gd    : 502985b65f52a0ca6890ee9c7d625ceb83d2919b25fde0ea273e1a3b915ba63b
reverted (3 hunks removed): 502985b65f52a0ca6890ee9c7d625ceb83d2919b25fde0ea273e1a3b915ba63b
```

`git diff b13260b -- game/src/ui/hud.gd` is 17 insertions / 1 deletion in three
hunks and nothing else: the member comment + `var _pause_consumed_frame`, the
`_input` stamp (+comment), and the `_process` `if`→`if pass / elif` guard
(+comment). The sha equality proves those three hunks are the entire difference
and that no other HUD code changed.

### 4a. Manual drive (same order as the lane’s suite)

`_input`(ESC) then `_process(0.016)` in one frame, `Input.action_press("pause")`:

```text
# esc_repro2.gd --mode=live
AUDIT frames: before=0 after_input=0 after_process=0 pause_just_pressed=true
AUDIT VERDICT mode=live paused=false lockpicking=false callback=[false]
AUDIT later_esc mode=live paused=true

# esc_repro2.gd --mode=revert (sha == HEAD, see above)
AUDIT VERDICT mode=revert paused=true lockpicking=false callback=[false]
AUDIT later_esc mode=revert paused=true
```

### 4b. Real main-loop control (engine-delivered ESC)

`Input.parse_input_event(ESC)`, engine flushes the event itself; the HUD’s own
`_pause_consumed_frame` is read back and compared with the process frame the
HUD `_process` actually runs in:

```text
LIVE   : ESC frame counter=2 stamp=2 pause_just=true lockpicking=false
         probe: frame=2 pause_just=true
         after _process: paused=false
         later real ESC (frame 6): paused=true
REVERT : ESC frame counter=2 stamp=<null> pause_just=true lockpicking=false
         after _process: paused=true
         later real ESC (frame 6): paused=true
```

So the premise is confirmed in the real engine (`_input` and that frame’s
`_process` share process frame 2), the pre-fix code **does** open the pause menu
on the same ESC (the bug), and the stamp is minimal and correct: monotonic, set
only on the lockpick ESC branch, never reset, cannot match a later frame.

**Is a normal ESC still able to pause?** Yes, in three independent ways: the
real-loop run above (`later real ESC: paused=true`), the manual repro, and the
lane suite’s last case (`PASS: a later ESC with no lockpick still opens the
pause menu`). The `_npc_dialogue_closed_frame` guard still works too (the full
`run_tests` suite passes).

I did not run the lane suite itself against the reverted HUD (it hardcodes
`res://src/ui/hud.gd` and the repo is read-only for me); its RED claim
`checks=18 fails=2` is exactly the two `must not pause the tree` assertions,
which my two repros reproduce. The `fails=2` arithmetic is consistent.

---

## 5. Claim 5 — lockpick hands (PASS)

> No authored lockpick mesh/animation (41 assets, 0 anim, 0 glb); labelled
> procedural stand-in, null-safe; `LOCKPICK_HANDS PASS checks=20`.

Independent check of `extracted/filelist.txt`:

```text
lockpick filelist lines : 41  (36 *.uasset + 5 *.ubulk)
*.anim / *.glb / *.gltf : 0
"lockpick" in anims_manifest.json / anims_meta.json : 0
```

The stand-in is a `Node3D` parented to the 1P rig with `PickShaft` (11 cm
cylinder), `PickTip` (bent box) and `PickHandle` (grip), two procedural
`StandardMaterial3D`s, node meta `authored=false` and a `port_standin` string
that names the missing authored asset. It is created/freed only from
`set_lockpicking_active`, which every lockpick caller (HUD, door, container,
swinging door) already uses. Null-safe when `fp_rig` is null (tested). The pose
offset is composed with `fp_base_rig_pos`, and the bob code at
`thief_character.gd:4571` still composes `fp_base_rig_pos + bob`, so nothing
fights; the base is restored and a second cycle leaves no node or drift
(tested). **Not verified:** how it looks — no capture was taken (headless only).
The lane labels it a stand-in, so this is a scope note, not a defect.

---

## 6. Claim 6 — `test_t10_gameplay.gd` 91.3c (PASS)

> The 91.3c expectation changed from the removed non-authored `lock_level` to
> the authored `max_lock_level`; same intent.

`git diff b13260b --numstat -- game/tests/test_t10_gameplay.gd` is `6 3`
(**one hunk**, 6 insertions / 3 deletions): the fixture key `"lock_level": 2` → `"max_lock_level": 2`, a comment,
and the message text. The assertion
`bool(locked_door.get("locked")) and int(locked_door.get("lock_level")) == 2`
still checks “an authored lock record is honoured at its authored level”; it
reads the runtime `lock_level` member (set by `set_locked`), not the removed
entry field. The justification is correct: `"LockLevel"` occurs 0 times in the
dump, so the old fixture was testing a field that never existed. **No other
expectation in the file was relaxed** (one hunk, and 91.3a/91.3b/91.4+ are
untouched). 91.3a still passes post-regen by construction: its `GH_LEVELS` are
`Guildhall_Loot` + `Guildhall_Gameplay`, neither of which has an authored-locked
door.

(`91.3a` still ORs in the dead `entry.lock_level` test at line 236. Harmless —
the producer always emits `locked` alongside `max_lock_level` — but it is now
dead code; nit F4.)

---

## 7. Claim 7 — no weakened gate (PASS)

> New suites 101-103 are in `run_tests.gd`, full run 308/0; they fail closed
> (exit + PASS marker).

* `run_tests.gd` registers 101–105 as `[number, description, script, marker]`
  and runs each as a **child process**:
  `OS.execute(OS.get_executable_path(), ["--headless", "--path", …, "--script", …], out, true)`.
  The gate is `if w9p2_code != 0 or text.find(marker) < 0: fails += 1`.
  A crashed, missing, failing or marker-less child therefore fails the parent.
* Each suite ends `quit(0 if fails == 0 else 1)` and prints its PASS marker only
  when `fails == 0` (`test_w9p2_locks.gd:189-193`,
  `test_lockpick_cancel.gd:166-170`, `test_lockpick_hands.gd:137-141`,
  `probe_lock_inventory.gd:225-231`).
* Measured full run: **308 PASS / 0 FAIL / `SUMMARY: fails=0` / exit 0**, and
  `run_tests.gd:7570` is `quit(0 if fails == 0 else 1)`.
* The parent’s own suite numbering has a cosmetic gap (99 → 101; no suite 100 in
  this tree). Not a gate.
* Not fault-injected: I read the fail-closed path and the child exit codes
  rather than injecting a failing child, because that would need a repo edit.

---

## 8. Exclusions: labelled and counted, not silent (PASS)

* `swinging_door._note_lock_exclusion(reason, class)` counts per
  `reason|class`, prints **once per class** (`window`, `key_only`), and exposes
  `lock_exclusions()` / `key_only_exclusions()`; `loot_container` has the same
  for key-only containers. Both are `static`, so the tally survives the node and
  is observable without per-instance spam.
* The rule, the reasons and the counts are written in `loot_container.gd`,
  `swinging_door.gd`, `lockable_door.gd`, `mission_controller.gd`, the producer
  contract §2/§5 and `b2-impl.md` §2/§3.
* No authored key-only container exists (all 4 placed `can_lockpick == false`
  are doors), so the container counter is currently 0 — it is a guard, not dead
  silence.
* Today **0** windows or key-only doors are locked, because no generated record
  carries `locked` at all (`locked_now=0`, and 0 lock keys in the raw tree).

---

## 9. Findings

### F1 — BLOCKING FOR THE INTEGRATOR STEPS (documentation only)
`locked_now=154` (and the §6 step-3 `144 / 10 / 0`) are wrong. Exact
post-regeneration values: `locked_now=362`; the snippet prints
`marker_locked=334, door_locked=12, window_locked=16`. Derivation in §3.
Cause: the producer emits the same actor into `markers` **and** `actors`
(verified on today’s data: 48/48 chest names in both arrays), and the snippet
reads raw records *before* the consumer’s window/key-only exclusion.
Fix the probe’s runtime counter (count distinct `(class,name)` or `markers`
only) and/or the documented expectations. The 144 containers / 10 doors / 16
windows / 2 key-only **gameplay** numbers are correct and need no change.

### Nits (non-blocking)
* **N1** `test_w9p2_locks.gd` L151-154 calls `set_locked(true, cap)` directly —
  it proves the setter clamps, not that `mission_controller` passes the cap. The
  real pin is the source grep at L180-181 (string match). Acceptable for a
  source pin; a spawn-level test with `scene_locked: true` would be stronger.
* **N2** `test_w9p2_locks.gd:186` `lc_src.find("% 2") < 0` is a fragile source
  grep: any future `"% 2d"` format string in `loot_container.gd` fails it.
* **N3** `probe_lock_inventory.gd` `_collect_json("data/generated/levels")`
  counts 108 “levels” (includes `_mid_unresolved.json`) vs 107
  `*.tatlevel.json`; cosmetic.
* **N4** `91.3a` still ORs the dead `entry.lock_level` (see §6).
* **N5 (pre-existing, inert)** container range is 1..6 while the HUD clamps the
  minigame to 0..5; an authored cap of 6 would display “LV 6” and run level 5.
  Authored caps are only 1 and 2, so no effect. Not introduced by B2.
* **N6 (observation)** the SceneVariant branch sets `set_locked(true, 4)` after
  `configure`, so a door that were both authored-locked (cap 2) and
  SceneVariant-locked would be raised to 4. No such overlap exists: `Locks.Doors`
  variants live only in `Buildings/*`, while the authored-locked doors are in
  OldManor/FTUE/POI. Inert today; if the overlap ever appears, prefer
  `maxi(cap, existing)` or keep the record’s cap.

---

## 10. Not verified by this audit

* `test_m2_player.gd`, E2E tier 1 / S2, `make audit`, `test_perf_guard.sh`,
  `make gate-ratchet`, captures — the lead’s numbers stand unverified here
  (out of this audit’s scope; no GPU work was performed).
* Visual quality of the procedural lockpick stand-in (headless only).
* Behaviour on the integrated, regenerated tree: everything about “APPLIED” is a
  join/derivation from the raw dump plus the patched helper, not an executed
  regeneration (which is forbidden on this branch).

---

## 11. Final

| Claim | Verdict |
|---|---|
| 1. authored data 173 = 157/8/8, caps 155×2 + 3×1, no per-instance level, producer drops, generated 0, runtime 0 | **PASS** |
| 2. rule: `locked` only, cap-as-level (1..6 / 1..4, labelled), no-cap → 1, key-only + window excluded, `entry.lock_level` gone, old formulas + SceneVariant 3 gone → authored 4 | **PASS** |
| 3. runtime blocked; patch exact and unapplied; `git apply --check` ok; 144 containers / 10 doors / 16 windows / 2 key-only | **PASS** with F1 (documented `locked_now`/snippet expectations wrong; game numbers right) |
| 4. ESC bug RED→GREEN; minimal stamp guard; normal ESC still pauses | **PASS** (reproduced independently, manual *and* real loop, reverted sha == HEAD) |
| 5. hands: no authored mesh/anim; labelled procedural stand-in; null-safe | **PASS** |
| 6. 91.3c fixture moved to the authored `max_lock_level`, same intent, nothing else relaxed | **PASS** |
| 7. suites 101-105 wired, fail-closed, full run 308/0 | **PASS** |

No invented lock value survives in the consumers; no gate is weakened; every
number in the lead’s claims is reproduced except the probe’s post-regeneration
`locked_now`, which is F1 and must be corrected in the contract before the
integrator relies on it.

```
AUDIT: PASS
```
