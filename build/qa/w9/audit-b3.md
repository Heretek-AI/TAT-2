# W9-P2 B3 — independent audit (L4-13 Den guard, L4-01 jam damage, magic-door continuity)

**Auditor:** independent subagent; I did not write the B3 code.
**Worktree:** `/home/john/Projects/TAT-2-rem-w9-p2`
**HEAD:** `b13260b` plus the shared W9-P2 working-tree edits (B1 `level_loader` /
roof probe, B2 authored locks + HUD/interact files, C1 ESC guard, B3
`mission_controller` helper and the three new tests). All numbers below are on
that mixed tree, which is the tree the lead's gate set covers.
**Date:** 2026-11-25
**Rules honoured:** read-only except this file; no commit; no capture/Vulkan; every
Godot run headless under
`flock /tmp/opencode/tat2-godot.lock -c "timeout … tools/godot --headless --path game --script …"`.

File hashes at audit time (for reproducibility):

```
3242bd2f…  game/src/missions/mission_controller.gd
ad5d6719…  game/tests/probe_den_window.gd
46f83131…  game/tests/test_jam_damage.gd
b672a64b…  game/tests/test_w9p2_endgame_continuity.gd
04558cad…  game/tests/run_tests.gd
```

## 1. Independent re-runs — all exit 0

| run | result |
|---|---|
| `tests/probe_den_window.gd` | `DEN_WINDOW PASS checks=34`, exit 0, 34 `^PASS`, 0 `FAIL` |
| `tests/test_jam_damage.gd` | `JAM_DAMAGE PASS checks=29`, exit 0, 29 `^PASS`, 0 `FAIL` |
| `tests/test_w9p2_endgame_continuity.gd` | `ENDGAME_CONTINUITY PASS checks=23`, exit 0, 23 `^PASS`, 0 `FAIL` |
| `tests/run_tests.gd` | exit 0, **308 `^PASS`**, **0 `^FAIL`**, `SUMMARY: fails=0` |

The three targeted logs were written to `/tmp/opencode/b3audit/{den,jam,endgame}.log`
and are not committed. The full run reproduces the report's 308/0 exactly,
including both new suites:

```
PASS: 104 W9-P2 B3 jam damage is the authored value (no balance change) (3434 ms)
PASS: 105 W9-P2 B3 magic-door continuity during the endgame (dormant never extracts) (2033 ms)
SUMMARY: fails=0
```

## 2. Item 1 — L4-13 Den west window: **PASS**

### 2.1 The production diff is exactly what the report claims

`git diff b13260b -- game/src/missions/mission_controller.gd` has four hunks:
B1's foyer-fill removal, B3's one call + one helper, and B2's
`table_max_lock_level()` door change. The B3 hunks are the only B3 production
edit: one call at the end of the telescope block in `_setup_thieves_den_hub`
(after `DenTelescopeArea` exists) and one definition of
`_add_den_west_window_blocker`; `grep -c` confirms one call and one definition,
and the helper returns early if the node already exists.

Geometry read from the code (anchor `DEN_WEST_WINDOW_ANCHOR = (-6.06, 43.05,
271.4)`, floor `40.26688`):

- box = `0.12 × (45.10 - (40.26688 - 0.05)) × 2.00` = **0.12 × 4.883 × 2.00 m**;
- inner (`+X`) face **-6.06**, top **45.10**, z **270.4..272.4**, bottom **40.217**;
- `collision_layer = 1`, `collision_mask = 0`, group `blocking_volume`, no mesh,
  not in `interactables`.

The player's mask includes layer 1 (`thief_character.gd:529`), and
`thief_character.gd` treats `blocking_volume` as solid-but-never-a-surface in
both `_try_step_up` (line 1950) and the mantle wall/ledge probes (lines 2114,
2146), so the tag contract claimed in the report is real.

### 2.2 Shape/tag proven by the probe

Quoted from my run:

```
PASS: [den] blocker is layer 1 / mask 0
PASS: [den] blocker is tagged blocking_volume (solid, never a mantle/ledge/climb anchor)
PASS: [den] blocker is not an interactable
PASS: [den] blocker has no mesh (invisible)
PASS: [den] blocker carries one BoxShape3D
PASS: [den] blocker inner face sits on the wall plane x=-6.06 (inner=-6.060)
PASS: [den] blocker top covers the opening top y=45.10 (top=45.100)
PASS: [den] blocker box covers the opening (0.12 x 4.88 x 2.00)
PASS: [den] blocker extends down to the floor (bottom=40.217 floor=40.267) so the 0.30 m wall probe hits it
PASS: [den] blocker is centred on the opening z=271.4
PASS: [den] blocker is solid on layer 1 at all four mantle sample heights (4/4)
```

The 4/4 ray check is real: four `intersect_ray` queries at
`floor_y+0.3, 41.2, 42.6, 44.5` from `x=-5.85` to `x=-6.30`, mask 1, and each
hit's collider must be the blocker itself (a start east of the glass plane, so
the ray cannot be satisfied by the pane).

### 2.3 "NOT REPRODUCED on this HEAD" is supported

My run reproduces the claim's numbers exactly:

```
DEN_WINDOW walk start=(-4.56, 40.11766, 271.4) final=(-5.258759, 40.11788, 271.4386) min_x=-5.2588 max_y=40.1179 mantled=false frames=180
DEN_WINDOW strong start=(-5.266029, 40.24085, 271.4411) final=(-5.389379, 43.13602, 271.4675) min_x=-5.3895 max_y=43.1532 wall_climbed=true frames=240
DEN_WINDOW pre_fix blocker_off min_x=-5.3895 max_y=43.1532 escaped=false final=(-5.389379, 43.13602, 271.4675)
DEN_WINDOW pre_fix_escape_reproduced=false (shell collision still closes the opening: true)
DEN_WINDOW pre_fix blocker_on min_x=-5.3895 max_y=43.1532 final=(-5.389379, 43.13602, 271.4675)
```

The sprint's stop is the authored collision, not the guard: capsule radius is
0.32 m (`thief_character.gd:49`), and `-5.3895 - 0.32 = -5.7095`, i.e. the
measured `SM_ThievesDen_Glass` plane at ≈ `-5.71`. The blocker's inner face is
at `-6.06`, **0.35 m behind** that plane, so it cannot be the operative stop in
any of the three runs — which is exactly why the blocker-off A/B and the
blocker-on A/B print identical coordinates. Disabling the glass shape at runtime
also leaves the sprint contained, so the "shell collision still closes it"
diagnostic is supported by the probe, not just asserted.

**Caveat (non-blocking).** The 180-frame walk ends at `-5.2588`, 0.45 m east of
the glass plane: it is blocked earlier (surrounding prop/frame), so those three
walk checks do not actually reach the opening and should not be read as window
evidence. The substantive evidence is the sprint attempt and the blocker-off
A/B. Also, the probe header/A-B comment says the A/B will "prove the guard is
load-bearing", while the inline diagnostic correctly says it cannot on HEAD
(`escaped=false`); the wording is self-contradictory even though the behaviour
and the impl report are honest. The guard is inert on this HEAD and is
defense-in-depth only.

### 2.4 It cannot block the telescope LOS

```
DEN_WINDOW telescope_los clear=true eye=(-3.9202, 41.78641, 270.7337) point=(-4.9202, 41.66688, 270.7337)
PASS: [den] telescope interaction LOS stays clear of the blocker
```

Geometry agrees: telescope area x `-4.9202` is 1.14 m east of the inner face,
and the whole eye→interaction-point segment lies east of `-4.9202`. The blocker
also has no mesh, so it cannot render into the ponder view or cast a mesh shadow.
(`DenMoonBeam` sits on the same plane and is already occluded for the light
probe by the authored glass at `-5.71`, so the new body adds no occlusion
change there.)

### 2.5 Two small numeric corrections

- The report/lead claim **1.28 m** from the ponder camera; measured is
  `-6.06 - (-4.8202) = 1.2398` → **1.24 m**. `b3-impl.md` already records 1.24
  and notes the brief's 1.28 was approximate; `p2-report.md` §B3 and the lead's
  claim still repeat 1.28. Doc-only fix.
- The report repeats the "0.745 m sill" (41.0 - 40.255); the player's actual
  floor is 40.118, i.e. 0.88 m. Harmless (the blocker starts below both).

Verdict: **PASS** — NOT REPRODUCED is measured on the current tree; the guard
exists, is shaped/placed/tagged as claimed, is provably solid on layer 1 (4/4),
and does not touch the telescope LOS or the ponder camera.

## 3. Item 2 — L4-01 jam damage: **PASS**

### 3.1 It drives the production path, not a copy

`test_jam_damage.gd` loads the real `res://src/ui/hud.gd`, adds a `DummyBody`
stub (300 HP, `take_damage`, `set_lockpicking_active`) to the `"player"` group
(which is what HUD `_get_player()` reads), then calls the real
`start_lockpick_minigame(3, …)` and `_attempt_lockpick_strike()`. The stub
records damage events/total, so the "exactly four `take_damage(20)` calls" check
is on the real applier, not a mock of it.

Quoted from my run:

```
JAM_DAMAGE first_jam cursor=0.000 health=280.0 jam_timer=0.500 status=LOCK JAMMED!
PASS: [jam] LV3 jam removes the authored 20 (300 -> 280)
PASS: [jam] authored jam_damage_delay_s = 0.5 s
PASS: [jam] a jam does not invoke the lockpick completion callback
PASS: [jam] a second strike inside the 0.5 s jam window deals no damage
PASS: [jam] four LV3 jams = 80 damage (300 -> 220, 73.3 %%)
PASS: [jam] exactly four take_damage(20) calls (total 80)
PASS: [jam] health bar hidden at 300/300 (full health)
PASS: [jam] health bar reveals at 299/300 (hp_frac < 0.999)
JAM_DAMAGE health_bar hp=220/300 frac=0.7333 fill=187.733/256
PASS: [jam] door/container cancel callbacks (success=false) deal no damage
PASS: [jam] headless door fallback unlocks on its timer
PASS: [jam] headless door fallback deals no damage
PASS: [jam] jam_damage_for_level(1) = 5 (CT_LockpickDamage)
…
PASS: [jam] levels 5/6 return the labelled 80/160 doubling fallback (authored rows stop at 4)
PASS: [jam] interactables.json carries authored rows 1..4 only (5/6 are the fallback)
PASS: [jam] table provenance is CT_LockpickDamage
JAM_DAMAGE PASS checks=29
```

### 3.2 The values are authored, and the chain is real

- `game/data/generated/gameplay/interactables.json` →
  `lockpick.jam_damage_by_lock_level = {"1":5,"2":10,"3":20,"4":40}`,
  `jam_damage_delay_s = 0.5`, `curve_table = CT_LockpickDamage`.
- `game/data/generated/tables/Gameplay/Tuning/CT_LockpickDamage.json`
  `DamageByLockLevel` keys Time 1..4 = **5 / 10 / 20 / 40**, no row 5/6.
- `tools/parse_interactables.py:parse_lockpick_damage()` builds the dict from
  the authored curve keys — not a literal table.
- The HUD is the only applier: `hud.gd:3279-3282` reads
  `_lockpick_db.jam_damage_by_lock_level` (loaded from the same JSON) and calls
  the player's `take_damage`. `grep` over `game/src/` finds no other jam
  damage; `lockable_door.get_jam_damage()` is used only to scale the no-HUD
  fallback's progress gain, and that path is tested to deal no damage.
- 300 max HP is the authored `CT_PlayerStats.BaseHealth` fallback
  (`thief_character.gd:244/545`), unchanged by the diff.

The test's expected 5/10/20/40 are literals that pin the authored values (it
also asserts the JSON has rows 1..4 and the `CT_LockpickDamage` provenance), so
a producer value drift would fail the test rather than silently pass — acceptable
for an authored-value regression test. Levels 5/6 are the labelled
`FALLBACK_JAM_DAMAGE` inference and are currently unreachable: doors cap at
`max_lock_level = 4` and `containers.json` has 0 locked classes.

### 3.3 No production change for jam

`git diff b13260b` touches no damage/jam code:

- `hud.gd`: only the C1 ESC-consume guard (no jam branch);
- `lockable_door.gd` / `loot_container.gd` / `swinging_door.gd`: B2 authored-lock
  fields only, no `take_damage`/`jam` edits;
- no `thief_character.gd` health change, no AI file in the diff.

Verdict: **PASS** — DECIDED + TESTED, authored 5/10/20/40 with the 0.5 s window,
HUD-only application, no balance change.

## 4. Item 3 — magic-door continuity: **PASS**

### 4.1 The test uses a real Area3D overlap and asserts the dormant rule

`test_w9p2_endgame_continuity.gd` instantiates the real `escape_gate.gd`
(`Area3D`, 3×3×3 shape, `collision_mask = 2`, `body_entered` connected in
`_ready`) and a real `CharacterBody3D` stub on layer 2; every extraction is a
real physics overlap, not a direct callback. My run:

```
ENDGAME_CONTINUITY dormant extracted=0 available=false phase=endgame
PASS: [endgame] a dormant gate emits nothing in the endgame
PASS: [endgame] dormant overlap is not a use
ENDGAME_CONTINUITY incomplete extracted=0 use_count=0
PASS: [endgame] activated gate with incomplete objectives emits nothing
ENDGAME_CONTINUITY complete extracted=1 use_count=1
PASS: [endgame] one body entry on an available endgame gate emits exactly one extracted
PASS: [endgame] extraction counts one use
PASS: [endgame] the authored 240 s cycle expires the gate
ENDGAME_CONTINUITY rearm returned=1 count=1->1 rearm_count=0->1 available=true phase=endgame
PASS: [endgame] _rearm_escape_gates re-arms the expired marker
PASS: [endgame] re-arm restores is_available() immediately (same tick)
PASS: [endgame] rearm_count grows on the re-arm
PASS: [endgame] GameState.active_escape_count() is unchanged across the re-arm
PASS: [endgame] marker record stays activated/not-expired for HUD parity
ENDGAME_CONTINUITY resolved extracted=0 phase=resolved
PASS: [endgame] a resolved run emits nothing on a body overlap
PASS: [endgame] collapse makes the gate unavailable
PASS: [endgame] activate() refuses forever after collapse
PASS: [endgame] a collapsed gate never re-arms
ENDGAME_CONTINUITY collapsed extracted=0 activated=false active=false
PASS: [endgame] a collapsed gate emits nothing on a body overlap
ENDGAME_CONTINUITY PASS checks=23
```

The re-arm assertion has **no await** between `_rearm_escape_gates()` and
`is_available()`, so "same tick" is what is measured. `escape_gate.gd`'s
`_on_body_entered` independently requires `is_available()` + `PHASE_ENDGAME` +
complete objectives; `_rearm_escape_gates()` skips collapsed and active markers,
calls `activate()`, and restores the record (`rearm_count` 0→1,
`active_escape_count()` 1→1).

### 4.2 The `_process` wiring is verified by code read, not by the test

The test calls `_rearm_escape_gates()` on a detached `MissionController`
instance, so it would still pass if the call site were deleted. I read the call
site: `mission_controller.gd:4494` is inside the `PHASE_ENDGAME` branch of
`_process`, directly after the endgame timer and before the light probe tick.
That, plus `collapse()` being terminal (`activate()` refuses), supports
"continuous re-arm kept". The report's "at most a one-frame boundary gap" is
correct: if the gate's own `_process` expires after the mission's `_process` in
the same frame, it re-arms on the next tick.

### 4.3 No production change for endgame

`git diff b13260b -- game/src/interact/escape_gate.gd game/src/core/game_state.gd`
is empty. The continuous re-arm is the pre-existing R10 behaviour, pinned by a
new test.

Verdict: **PASS** — DECIDED + TESTED; dormant never extracts, one entry → one
extraction, re-arm within the tick, collapse terminal, no production change.

## 5. Test wiring, balance and gate counts

- Suites **104/105** are registered in `run_tests.gd` in the 101–105 block and
  gated on **exit 0 AND the PASS marker**, so a sub-suite that prints PASS but
  exits non-zero (or vice versa) fails the parent. Not weakened.
- Full `run_tests.gd` on this tree: **308 PASS / 0 FAIL / `SUMMARY: fails=0`**
  (303 + suites 101–105), matching `p2-report.md` §"Golden gate set". R8 floor
  301 is not lowered.
- B3 adds only three new test files and one `run_tests` block. No existing
  assertion was removed or relaxed by B3. The 488-line
  `test_roof_collision.gd` diff and the 9-line `test_t10_gameplay.gd` diff are
  B1/B2 lane edits (hull probes; `lock_level` → `max_lock_level`), inspected for
  B3 content: none.
- Combat balance: no AI/health/damage number changed. The only gameplay-value
  change in the shared tree is B2's authored door lock level (`3` →
  `table_max_lock_level()` = 4), documented in B2, not B3.

## 6. Report honesty

- `p2-report.md` §B3 verdicts "**NOT REPRODUCED on this HEAD + GUARD ADDED**"
  (L4-13) and "**DECIDED + TESTED**" (jam, endgame) match the measured evidence
  and the diff. The lane did not claim the guard stops a live escape; it says the
  guard is defense-in-depth and cannot be exercised as load-bearing on HEAD,
  because the shell collision is in front of it.
- The open item — "only a GPU capture can settle the ponder view's pixels" — is
  correctly stated. The probe pins the camera rig/vista contract, not the KF05
  image, so the claim "the KF05 ponder view is a PASS" should be read as
  **rig/vista PASS**, not pixels.
- `build/qa/w9/facts-b3.md` does not exist in this worktree (only
  `facts-a1..a4`, `facts-b1`, `facts-b2`); the impl report says so and measured
  the premises directly. Process gap for the lead, not a code defect.
- Compile count: `b3_compile.log` says `scripts checked: 165, broken: 0`, the
  final `compile_p2.log` says 164/0; both are clean, the count moved with the
  shared tree. The 165 in `b3-impl.md` is not the final merged count.
- The pre-existing `audio_manager.gd:712 _occluded` warning is real and not B3:
  it appears in `b3_den_red.log` (before the helper), in my probe run with the
  same `play_footstep` backtrace, and `audio_manager.gd` is unchanged by the
  diff.

## 7. Minor, non-blocking findings

1. `p2-report.md` §B3 (and the lead's claim) still says the ponder camera is
   **1.28 m** from the blocker; measured **1.24 m**. `b3-impl.md` already has
   the right number.
2. The 180-frame "held forward walk" stops 0.45 m before the glass plane (early
   prop/frame), so those three checks do not reach the opening; the sprint and
   the blocker-off A/B are the real containment evidence.
3. The probe's header/A-B comments call the A/B a "load-bearing proof", while
   its inline diagnostic correctly says it is not on HEAD. Wording only.
4. `test_jam_damage.gd` header says "W9-P2 B2 (L4-01)"; L4-01/jam is B3. Cosmetic.
5. The endgame test calls `_rearm_escape_gates()` directly; the per-tick call
   site (`mission_controller.gd:4494`) is only pinned by review, not by the test.
6. The blocker is anchored to the constant `DEN_WEST_WINDOW_ANCHOR`, not to
   `_den_window_staging()`'s result. On this map staging logs
   `source=authored-west-opening anchor=(-6.06, 43.05, 271.4)`, so they agree; a
   future parsed-window anchor change would need the guard to follow.

None of these changes a measured result or weakens a gate.

## Verdict

| item | verdict |
|---|---|
| B3 L4-13 guard shape/tag/LOS, not-reproduced evidence | **PASS** |
| B3 L4-01 jam (authored table, HUD-only, no balance change) | **PASS** |
| B3 magic-door continuity (dormant / re-arm / terminal collapse) | **PASS** |
| Production scope (no HUD/interact jam or endgame edits) | **PASS** |
| Tests wired and full run 308/0 | **PASS** |
| Report honesty (verdicts + open items) | **PASS** (two doc nits above) |

AUDIT: PASS
