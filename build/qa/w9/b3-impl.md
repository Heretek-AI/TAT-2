# W9-P2 B3 — implementation report (L4-13, L4-01, magic-door continuity)

Worktree: `/home/john/Projects/TAT-2-rem-w9-p2` (branch `rem/w9-p2`)
Base commit: `b13260b` (`docs(w9): P1 report — ratchet target and the docs owed at integration`)
Date: 2026-11-25
Status: **A GREEN (34 checks), B GREEN (29 checks), C GREEN (23 checks)**.
No commit, no push, no generated-data or `extracted/` edit, no GPU run.

`build/qa/w9/facts-b3.md` does **not exist** in this worktree (only
`facts-a1..a4`, `facts-b1`, `facts-b2`). This lane used the facts in the B3
brief plus direct measurement on the loaded Den. The brief's L4-13 premise was
found to be stale on this HEAD (see §A.3).

The worktree is shared with the concurrent B1/B2 lanes: at run time
`level_loader.gd`, `lockable_door.gd`, `loot_container.gd`, `swinging_door.gd`,
`hud.gd`, `thief_character.gd`, `run_tests.gd`, `test_roof_collision.gd` and
`test_t10_gameplay.gd` also carried uncommitted edits (B1 room grade, B2
authored locks, C1 ESC guard). I did not edit those files. The probes/tests
below ran against that mixed tree; my only production edit is the new Den
helper in `mission_controller.gd`.

## Files

Created (tests, all tracked-able):

- `game/tests/probe_den_window.gd` — L4-13 Den telescope ponder + west-window
  guard probe. 34 checks.
- `game/tests/test_jam_damage.gd` — L4-01 authored jam-damage decision test
  (real HUD script + player stub). 29 checks.
- `game/tests/test_w9p2_endgame_continuity.gd` — magic-door re-arm/terminal
  continuity test (real `EscapeGate` + real Area3D overlap). 23 checks.

Changed (production, minimal hunk):

- `game/src/missions/mission_controller.gd`
  - one call at the end of the telescope block in `_setup_thieves_den_hub`
    (`_add_den_west_window_blocker(floor_y)`);
  - one new Den helper `_add_den_west_window_blocker()` after
    `_setup_thieves_den_hub`.
  - No other function touched.

Evidence logs (git-ignored): `build/qa/w9/logs/b3_*.log`.

## Commands (every run headless, under the shared lock)

```
flock /tmp/opencode/tat2-godot.lock -c "timeout 900 tools/godot --headless --path game --script res://tests/probe_den_window.gd"

flock /tmp/opencode/tat2-godot.lock -c "timeout 900 tools/godot --headless --path game --script res://tests/test_jam_damage.gd"

flock /tmp/opencode/tat2-godot.lock -c "timeout 900 tools/godot --headless --path game --script res://tests/test_w9p2_endgame_continuity.gd"

flock /tmp/opencode/tat2-godot.lock -c "timeout 900 tools/godot --headless --path game --script $PWD/tools/check_scripts_compile.gd"
```

---

# A. L4-13 — `[F] EXIT` / Den west-window escape

## A.1 Decision and fix

Add the requested invisible guard at the authored west opening, tagged with the
loader's `blocking_volume` contract (solid to walk into, never a mantle / ledge /
climb / zipwire anchor). Implemented as one `StaticBody3D`:

- `DenWestWindowBlocker`, `collision_layer = 1`, `collision_mask = 0`;
- one `BoxShape3D`, `0.12 x 4.883 x 2.00` m;
- inner (`+X`) face at the measured wall plane `x = -6.06`, top at
  `y = 45.10`, z `270.40..272.40`, from the opening top down to the floor
  (`bottom = floor_y - 0.05`, measured `40.217`);
- no mesh, not an `interactables` member, added after `DenTelescopeArea`.

The box extends below the 41.0 m sill on purpose: `try_auto_mantle()`'s first
wall probe samples only 0.30 m above the feet (below the sill), so a box that
started at 41.0 would be missed by that probe and the mantle would still fire
through the opening if the real collision were gone. The blocker top is the
opening lintel; its inner face is the measured plane; the telescope Area3D
centre stays 1.14 m inboard of it and the ponder camera sits 1.24 m east of the
inner face (measured; the brief's 1.28 m was approximate).

## A.2 Hunk

```gdscript
	tele_script.reload()
	tele_area.set_script(tele_script)
	tele_area.set("mission_ctrl", self)
	add_child(tele_area)

	# L4-13: guard the authored west opening after the telescope exists, so the
	# ponder camera/Area3D contract is measured against the final scene.
	_add_den_west_window_blocker(floor_y)
```

```gdscript
func _add_den_west_window_blocker(floor_y: float) -> void:
	if get_node_or_null("DenWestWindowBlocker") != null:
		return
	const THICKNESS: float = 0.12
	const OPENING_HALF_H: float = 2.05 # anchor y 43.05 +/- 2.05 = 41.0..45.1 m
	const OPENING_HALF_Z: float = 1.0 # anchor z 271.4 +/- 1.0 = 270.4..272.4 m
	var top_y: float = DEN_WEST_WINDOW_ANCHOR.y + OPENING_HALF_H
	var bottom_y: float = minf(floor_y, top_y - OPENING_HALF_H * 2.0) - 0.05
	var blocker := StaticBody3D.new()
	blocker.name = "DenWestWindowBlocker"
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	blocker.position = Vector3(
		DEN_WEST_WINDOW_ANCHOR.x - THICKNESS * 0.5,
		(bottom_y + top_y) * 0.5,
		DEN_WEST_WINDOW_ANCHOR.z)
	var shape := BoxShape3D.new()
	shape.size = Vector3(THICKNESS, top_y - bottom_y, OPENING_HALF_Z * 2.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	blocker.add_child(col)
	blocker.add_to_group("blocking_volume")
	add_child(blocker)
```

(The full comment block is in the file; it records the design and the stale
premise.)

## A.3 RED — measured on the unmodified code

Command as above, unmodified tree (no `DenWestWindowBlocker`):

```
FAIL: [den] DenWestWindowBlocker missing (west opening unguarded)
DEN_WINDOW walk start=(-4.56, 40.11766, 271.4) final=(-5.258759, 40.11788, 271.4386) min_x=-5.2588 max_y=40.1179 mantled=false frames=180
PASS: [den] held forward walk stays inside the Den (min_x=-5.2588 > x=-6.06)
PASS: [den] held forward walk never climbs past the opening top y=45.10 (max_y=40.1179)
PASS: [den] no auto-mantle onto the 0.745 m sill
DEN_WINDOW FAIL checks=18
```

**The scripted walk did not reproduce the escape.** The player stops at
`x = -5.2588`, 0.35 m short of the briefed plane, with no mantle. The strong
attempt (closer start `x=-5.30`, forward + sprint, 4 s) was added to the probe
and also does not escape: it wall-climbs and stalls at `y = 43.1532`:

```
DEN_WINDOW strong start=(-5.266029, 40.24085, 271.4411) final=(-5.389379, 43.13602, 271.4675) min_x=-5.3895 max_y=43.1532 wall_climbed=true frames=240
```

Direct collision measurement on the loaded Den (`/tmp/opencode/b3_probe_wall*.gd`,
throwaway debug, not committed):

- the first collider west of the player at `z=271.4` is the authored
  `SM_ThievesDen_Glass` / `SM_ThievesDen` collision at `x ≈ -5.71`
  (`ConcavePolygonShape3D`, layer 1), not `x=-6.06`;
- rays from `x=-5.2..-6.0` are blocked at `x ≈ -5.71` for every y 40..45.75 and
  z 266.4..274.2: the pane/west wall is solid in the loaded collision;
- disabling only the `SM_ThievesDen_Glass` shape at runtime does **not** reopen
  it — the `SM_ThievesDen` shell collision still closes the opening (A.4 A/B).

Cause: W9-P1 `7939a61` (“consume the authored UE AggGeom for every mesh”) now
bakes authored collision for the glass/shell. The brief's “`SM_ThievesDen_Glass`
has no collision” was true for the state the L4-13 record was captured on, not
for HEAD. So on this HEAD the original walk-out is already blocked by collision;
the blocker is defense-in-depth at the authored plane, not the live stop.

## A.4 GREEN — after the helper

```
DEN_WINDOW floor_y=40.26688 tele=(-4.9202, 40.26688, 270.7337)
PASS: [den] ponder enter sets _ponder_active
PASS: [den] ponder enter makes DenTelescopeCam current
PASS: [den] ponder enter builds the DenWindowVista diorama
PASS: [den] ponder eye is the authored tripod offset (0.1, 1.7, 0)
PASS: [den] ponder exit clears _ponder_active
PASS: [den] ponder exit clears DenTelescopeCam.current
PASS: [den] ponder exit restores the player camera
PASS: [den] ponder exit frees the vista node
PASS: [den] telescope toggle never writes the player transform
DEN_WINDOW player_before=(-3.6, 40.11766, 271.4) player_after_toggle=(-3.6, 40.11766, 271.4)
PASS: [den] DenWestWindowBlocker exists
PASS: [den] blocker is layer 1 / mask 0
PASS: [den] blocker is tagged blocking_volume (solid, never a mantle/ledge/climb anchor)
PASS: [den] blocker is not an interactable
PASS: [den] blocker has no mesh (invisible)
PASS: [den] blocker inner face sits on the wall plane x=-6.06 (inner=-6.060)
PASS: [den] blocker top covers the opening top y=45.10 (top=45.100)
PASS: [den] blocker box covers the opening (0.12 x 4.88 x 2.00)
PASS: [den] blocker extends down to the floor (bottom=40.217 floor=40.267) so the 0.30 m wall probe hits it
PASS: [den] blocker is centred on the opening z=271.4
PASS: [den] blocker is solid on layer 1 at all four mantle sample heights (4/4)
PASS: [den] telescope interaction LOS stays clear of the blocker
DEN_WINDOW telescope_los clear=true eye=(-3.9202, 41.78641, 270.7337) point=(-4.9202, 41.66688, 270.7337)
DEN_WINDOW walk start=(-4.56, 40.11766, 271.4) final=(-5.258759, 40.11788, 271.4386) min_x=-5.2588 max_y=40.1179 mantled=false frames=180
PASS: [den] held forward walk stays inside the Den (min_x=-5.2588 > x=-6.06)
PASS: [den] held forward walk never climbs past the opening top y=45.10 (max_y=40.1179)
PASS: [den] no auto-mantle onto the 0.745 m sill
DEN_WINDOW strong start=(-5.266029, 40.24085, 271.4411) final=(-5.389379, 43.13602, 271.4675) min_x=-5.3895 max_y=43.1532 wall_climbed=true frames=240
PASS: [den] forward+run stays inside the Den (min_x=-5.3895 > x=-6.06)
PASS: [den] forward+run never clears the opening top y=45.10 (max_y=43.1532)
PASS: [den] found the authored SM_ThievesDen_Glass collision to simulate the pre-fix state
DEN_WINDOW pre_fix blocker_off min_x=-5.3895 max_y=43.1532 escaped=false final=(-5.389379, 43.13602, 271.4675)
DEN_WINDOW pre_fix_escape_reproduced=false (shell collision still closes the opening: true)
DEN_WINDOW pre_fix blocker_on min_x=-5.3895 max_y=43.1532 final=(-5.389379, 43.13602, 271.4675)
PASS: [den] the same pre-fix walk is contained with the blocker on (min_x=-5.3895 > -6.06, max_y=43.1532 < 45.10)
DEN_WINDOW PASS checks=34
```

The probes A/B is a **simulation of the historical state**, not a claim about
the unmodified current tree: it disables only the `SM_ThievesDen_Glass` shape at
runtime and shows the player is still contained by the shell collision, so the
blocker-on/off walk result is identical. The guard's solidity is proven by the
four layer-1 rays from the reveal side (`4/4`); its *load-bearing* mantle
refusal cannot be exercised on HEAD because the shell collision is in front of
it. A loader/AggGeom change would be needed to measure that, which is outside
this lane.

## A.5 What a GPU capture must settle

- KF05 ponder framing through the now-invisible body (no mesh, but a capture
  should confirm no shadow / near-plane artifact and unchanged vista framing).
- Whether the authored AggGeom closing the west window reads correctly in the
  render (the visual window vs the simplified collision is a loader fidelity
  question, not this lane's fix).
- The headless wall-climb pose at `y ≈ 43.15` sits inside the glass/mullion; a
  capture would show whether the 1P camera visibly clips there.
- The plank roof beyond the opening is still unverifiable headless.

---

# B. L4-01 — jam damage is authored/intended (no balance change)

Decision: **keep the authored 5/10/20/40 and the 0.5 s jam window.** No
production change. The HUD is the only applier (`hud.gd:3252-3267` in the
brief's line numbering; current tree `_attempt_lockpick_strike`).

`game/tests/test_jam_damage.gd` instantiates the real HUD script plus a
`DummyBody` player stub (300 max health, `take_damage`, `health`,
`max_health`, `set_lockpicking_active`, in the `"player"` group) and drives the
production strike path.

Command as above. Output (`build/qa/w9/logs/b3_jam_green.log`):

```
JAM_DAMAGE first_jam cursor=0.000 health=280.0 jam_timer=0.500 status=LOCK JAMMED!
PASS: [jam] LV3 jam removes the authored 20 (300 -> 280)
PASS: [jam] authored jam_damage_delay_s = 0.5 s
PASS: [jam] status shows LOCK JAMMED!
PASS: [jam] a jam does not invoke the lockpick completion callback
PASS: [jam] a second strike inside the 0.5 s jam window deals no damage
PASS: [jam] four LV3 jams = 80 damage (300 -> 220, 73.3 %)
PASS: [jam] exactly four take_damage(20) calls (total 80)
JAM_DAMAGE bar300 health=300.0 max=300.0 visible=false
PASS: [jam] health bar hidden at 300/300 (full health)
PASS: [jam] health bar reveals at 299/300 (hp_frac < 0.999)
JAM_DAMAGE health_bar hp=220/300 frac=0.7333 fill=187.733/256
PASS: [jam] fill width after four LV3 jams = 187.733 px (220/300 of 256)
PASS: [jam] door/container cancel callbacks (success=false) deal no damage
PASS: [jam] no HUD is discoverable for the headless door fallback
PASS: [jam] headless door fallback starts its timed unlock
JAM_DAMAGE fallback locked=false health=220.0
PASS: [jam] headless door fallback unlocks on its timer
PASS: [jam] headless door fallback deals no damage
PASS: [jam] jam_damage_for_level(1) = 5 (CT_LockpickDamage)
PASS: [jam] jam_damage_for_level(2) = 10 (CT_LockpickDamage)
PASS: [jam] jam_damage_for_level(3) = 20 (CT_LockpickDamage)
PASS: [jam] jam_damage_for_level(4) = 40 (CT_LockpickDamage)
PASS: [jam] levels 5/6 return the labelled 80/160 doubling fallback (authored rows stop at 4)
PASS: [jam] interactables.json carries authored rows 1..4 only (5/6 are the fallback)
PASS: [jam] table provenance is CT_LockpickDamage
JAM_DAMAGE PASS checks=29
```

Interpretation / labels:

- 5/10/20/40 are authored 1:1 (`CT_LockpickDamage.DamageByLockLevel` ->
  `interactables.json lockpick.jam_damage_by_lock_level`).
- Level 5/6 = 80/160 is the **labelled port doubling inference**
  (`FALLBACK_JAM_DAMAGE`), not an authored row: the table stops at 4, the test
  asserts that.
- Four LV3 jams = 80 -> 220/300 = 73.3 %, matching the record's ~75 % first
  health-bar reveal (the bar reveals at `hp_frac < 0.999`, tested explicitly).
- The second strike during the 0.5 s window is swallowed by the production
  guard (health and damage-event count unchanged), so a jam cannot stack.
- The door/container `_on_lockpick_finished(false, ...)` callbacks and the
  no-HUD door timed fallback do not damage (documented fallback).

Assumption: the test constructs a bare HUD CanvasLayer, not the full mission
HUD; it does not edit `hud.gd`. The concurrent C1 ESC-guard edit to `hud.gd`
was present during the run and is orthogonal (no jam branch).

---

# C. Magic-door continuity — keep continuous, document + test

Decision: **keep the current continuous re-arm behaviour.** No production
change unless a test found a contradiction (it did not).

`game/tests/test_w9p2_endgame_continuity.gd` uses a real `EscapeGate` Area3D
and a real `CharacterBody3D` player stub on collision layer 2; every extraction
is a real `body_entered` overlap, not a direct callback.

Command as above. Output
(`build/qa/w9/logs/b3_endgame_continuity_green.log`):

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

The re-arm is asserted with **no `await` between `_rearm_escape_gates()` and
`is_available()`**: one endgame tick restores the door, so the only possible gap
is the single tick boundary noted in the brief. `active_escape_count()` stays
`1 -> 1`; the marker record stays `activated=true, expired=false`. Collapse is
terminal (`activate()` false, `rearm_count` frozen, no extraction).

---

# Gates

Ran:

- `tools/check_scripts_compile.gd`: `scripts checked: 165, broken: 0`
  (`build/qa/w9/logs/b3_compile.log`).

Not run (lead owns the gate set; worktree also carries concurrent lanes'
uncommitted edits):

- `run_tests.gd`, `test_m2_player.gd`, the three probes' peers, E2E tier 1,
  `make audit`, `make gate-ratchet`, captures. No GPU process was started.

# Other observations (not fixed — outside this lane's ownership)

- Pre-existing headless script error during the Den walk:
  `audio_manager.gd:712 _occluded`: `Trying to assign an array of type
  "Array[PhysicsBody3D]" to a variable of type "Array[RID]"`, triggered by
  `play_footstep` from `thief_character._physics_process`. It appears in the
  RED log before my edit and in every walk run; it does not abort the probe.
  Reported for the lead.
- `facts-b3.md` missing (see header).
- The Den telescope `floor_y` is the mid-settle anchor `40.26688`, while the
  player's final floor is `40.11766` (0.149 m lower); the blocker bottom uses
  the anchor, which is still below the 0.30 m mantle wall probe. Not a blocker
  issue; noted because the probe prints both.
