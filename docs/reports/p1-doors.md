# P1 Lane D — S21 blue double doors, prompts, lockpick (V3-03 / UI2-05 / PG-2, KF24)

| | |
|---|---|
| lane | P1 Lane D (`p1-doors`) |
| worktree | `/home/john/.local/share/opencode/worktree/318f41/p1-doors` |
| branch | `w10/p1-doors` |
| base | `27b4d5c` (P0b tip) |
| engine | Godot 4.7.2.stable.official.ed1daf0bf via native `tools/godot` |
| probe | `game/tests/probe_p1_doors.gd` (headless, no renderer, no writes) |
| gate line | `P1_DOORS PASS` / `P1_DOORS FAIL` |

Scope: make the S21 subject present and scoreable — the authored blue/cream
double doors, the `[F] OPEN` over `[F] [HOLD] LOCK` stack and its `[F] CLOSE`
flip, and an honest statement about the circular lockpick minigame.

Everything below is measured from the committed generated data, the shipped
`materials.json`/GLB payloads, and the probe run, unless it is explicitly
labelled `INFERENCE`.

## 1. Which door S21 is (authored identity)

`Building_Guildhall_POI` carries exactly four `swinging_doors` records for the
two porch double doors (each actor authors a `Pivot` and a `SecondPivot`):

```
BP_Manor_Porch_Door_8x8_C_0.Pivot        (11.50, 27.50, -73.50)
BP_Manor_Porch_Door_8x8_C_0.SecondPivot  (14.48, 27.50, -73.50)
BP_Manor_Porch_Door_8x8_C_1.Pivot         (5.50, 27.50, -73.50)
BP_Manor_Porch_Door_8x8_C_1.SecondPivot   (8.48, 27.50, -73.50)
```

* class `BP_Civic_Doorway_6x8_C`, one leaf each,
* leaf mesh `/Game/Art/Environment/Civic/Doors/SM_Civic_DoorDouble_x4`,
* the placed actor's authored `OriginalMesh` is the same
  `SM_Civic_DoorDouble_x4` (`extracted/json/Maps/Buildings/Guildhall/Building_Guildhall_POI.json`,
  `BP_Manor_Porch_Door_8x8_C_0`),
* no authored `_locked`, no `CanBeLockpicked: false`, and
  `_lockConfig {MinLockLevel: 2, MaxLockLevel: 3, KeyTag: Item.Key.Buildings.Guildhall}`
  → the doors are *unlocked* on approach, which is exactly the state KF24
  (`03:00.60`) shows: `[F] OPEN` above `[F] [HOLD] LOCK`, never a pick prompt.

Around the four pivots the level places the civic doorway frames, columns,
sconces, railing and crates that read as the arched side portico in S21.
`Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json` is in the
`guildhall` sublevel list (`mission_controller._map_id_to_sublevels`), so these
doors are spawned in the mission; P0b's review simply never walked to them
(`build/qa/review_20261124/kf_presence.md`, KF24: "subject absent — nearest door
prompt pair, timber leaf"; git-ignored review artifact).

## 2. The authored material slots (V3-03)

The leaf mesh authors **two** material slots, in GLB primitive order:

| slot | GLB primitive | tris | authored material | albedo |
|---|---|---:|---|---|
| 0 | 0 | 621 | `/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalA_brass` | `T_TrimMetalA_D.png` |
| 1 | 1 | 344 | `/Game/MaterialLibrary/Environment/Wood/Manor/MI_ManorTrim` | `T_ManorTrim_D.png` |

A CPU triangle projection of the GLB (no GPU, no invented art) shows slot 0 is
the raised **diamond mullion grid plus the twin vertical pulls**, and slot 1 is
the **full 1.5 x 4.0 m slab** behind it (one leaf of a 3 m double doorway,
4 m tall — `ExtendedBounds` 75.6 x 12.9 x 200 cm).

Two corrections to the row's wording, both measured:

* **There is no glass material on this door.** `mesh_materials.json` and the GLB
  name only the brass and manor-trim materials; the "panes" are the solid slab
  behind the mullion grid. The separate `SM_Civic_DoorDoubleD_Glass` mesh is the
  interior doorway-D insert and is **not placed** in `Building_Guildhall_POI`
  (0 instances). "Dark glass panes" is therefore an appearance read of the slab
  in shadow, not a missing slot.
* **"Blue-painted wood" has no blue material.** The authored slab albedo is
  `T_ManorTrim_D` (brown wood with cream diamond/key trim bands) and the authored
  mullion albedo is brass. In KF24 the cream mullions and the dark blue-grey
  slab are those two materials under the portico's cool night ambient.
  `INFERENCE:` the blue cast is lighting/exposure, not a paint material — there
  is no `MI_*Door*Blue*` material in `materials.json` and no per-instance
  material override on either pivot (`OverrideMaterials: null` in the raw dump).
  Scoring the blue read therefore belongs to the lighting rows, not V3-03.

The runtime path already binds these by index: `level_loader._get_mesh_and_shape`
→ `_bind_glb_materials(mesh, mesh_materials[mesh])` (GLB order, index-keyed), and
`swinging_door._build_leaf` consumes that mesh unchanged. The probe reads the
resulting `MeshInstance3D` surfaces and asserts the two albedo paths, slot order
and that the slots are not collapsed into one.

## 3. The prompt stack (UI2-05)

Door-side copy (unchanged, KF24 verbatim):

```
closed, unlocked   [F] OPEN      + [F] [HOLD] LOCK
swinging/open      [F] CLOSE     + (none)
closing            [F] OPEN      + (none)      (interact blocked while tweening)
locked ([HOLD])    [F] PICK LOCK (Lv N) + (none)   PORT COPY, never shown in the clip
```

HUD-side, KF24's second row draws **its own white F keycap** under the primary
badge (4K crop of `03:00.60`: badge `F` + `OPEN`, then badge `F` + `[HOLD] LOCK`;
KF25 shows the same badge on `[F] [HOLD] TAKEDOWN`). The port printed the second
row as raw text `[F] [HOLD] LOCK`, i.e. the brackets and the F were label glyphs,
not a keycap. Fixed: the secondary row is now an `HBoxContainer` of
`ThemeScript.white_keycap(...)` + label, and `_set_secondary_prompt` parses the
leading `[KEY]` token the same way the primary does (`E` → `F` legacy alias).
The *copy* is untouched (`get_interact_secondary_prompt()` still returns the
KF24 string), so every test-facing string is stable.

## 4. Authored lock band on `[HOLD] LOCK`

`swinging_door.configure()` now keeps the record's authored `_lockConfig` band
(`authored_min_lock_level` / `authored_max_lock_level`) for every record, locked
or not, and `interact_hold()` re-locks with `relock_level()` inside that band.

Why: the S21 porch doors author `MinLockLevel 2 / MaxLockLevel 3`, but because
they are authored *unlocked*, `configure()` never set a level and the old
`set_locked(true, maxi(lock_level, 1))` re-locked them at **Lv 1 — below the
authored minimum**. The prompt then advertised `(Lv 1)`. `PORT_DECISION:` the
band's **floor** is used for an unlocked door (neither authored value is "the"
level; the floor is the cheaper authored lock), and an already-locked door keeps
its level. Doors with no authored band keep the legacy Lv 1 fallback.

## 5. Circular lockpick minigame (PG-2)

* **Available and authored-parameterised.** `interactables.json` (producer:
  `DA_LockpickMinigameVariations.json` + `GA_Lockpick.json` +
  `GE_Lockpicking.json` + `CT_LockpickDamage`) carries `arc_angle_deg`,
  `duration_s`, `defined_sections` (`Lockpick.TrackSection.Breakable`),
  jam damage 5/10/20/40 and the 200 cm cancel radius. The HUD builds
  `LockpickMinigameOverlay` + `LockpickDial` and runs the authored track list
  for the door's level (`_pick_lockpick_tracks`).
* **HARD_LIMIT:** the authored UMG widget tree for that overlay is not in the
  dump (no lockpick widget asset under `Content/UI` or
  `Content/Gameplay/Interactables/Locks`), so the dial's look is a port
  rendering of authored arc parameters, not authored art. Not faked as parity.
* **PORT_DECISION:** PG-2's live parity scenario looks for
  `LockpickWheel` / `LockpickArc`; the port's nodes are
  `LockpickMinigameOverlay` / `LockpickDial`. There is no authored name to
  rename to, so the mapping is recorded here instead of adding alias nodes to
  satisfy a harness check.

## 6. Files

| file | change |
|---|---|
| `game/src/ui/hud.gd` | KF24/KF25 secondary prompt row is a keycap + label; `_set_secondary_prompt` parses the leading `[KEY]` token |
| `game/src/interact/swinging_door.gd` | authored `_lockConfig` band kept on every record; `relock_level()`; `interact_hold()` no longer drops below `MinLockLevel` |
| `game/tests/probe_p1_doors.gd` | new headless probe (records, material slots, prompt transitions, HUD stack layout, lock/open/close, lockpick status) |
| `docs/reports/p1-doors.md` | this report |

## 7. Probe

```bash
flock /tmp/opencode/tat2-godot.lock bash -c 'cd <worktree> && \
  tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd" && \
  tools/godot --headless --path game --script res://tests/probe_p1_doors.gd'
```

Measured on `w10/p1-doors` (Godot 4.7.2.stable.official.ed1daf0bf, headless, no renderer):

```
scripts checked: 203, broken: 0
P1_DOORS probe — S21 blue double doors (KF24)
  ok: S21 records = 4 (2 actors x Pivot+SecondPivot), got 4
  ok: every S21 record: class BP_Civic_Doorway_6x8_C, 1 leaf
      /Game/Art/Environment/Civic/Doors/SM_Civic_DoorDouble_x4, unlocked, lockpickable
    record BP_Manor_Porch_Door_8x8_C_0.Pivot@(11.50,27.50,-73.50)
    record BP_Manor_Porch_Door_8x8_C_0.SecondPivot@(14.48,27.50,-73.50)
    record BP_Manor_Porch_Door_8x8_C_1.Pivot@(5.50,27.50,-73.50)
    record BP_Manor_Porch_Door_8x8_C_1.SecondPivot@(8.48,27.50,-73.50)
  ok: authored lock config present (min_lock_level=2.0 max_lock_level=3.0 on the first record)
  ok: 4/4 S21 door nodes built a pivot + leaf (got 4)
  ok: leaf has 2 GLB surfaces (got 2)
    leaf AABB size=(1.513941, 4.00001, 0.259206) surfaces=2
  ok: leaf extent 1.51 x 4.00 m == authored 1.5 x 4.0
  ok: surface 0 material is a BaseMaterial3D (StandardMaterial3D)
    slot 0 albedo=T_TrimMetalA_D.png normal=T_TrimMetalA_N.png orm=T_TrimMetalA_ORM.png roughness=
  ok: surface 1 material is a BaseMaterial3D (StandardMaterial3D)
    slot 1 albedo=T_ManorTrim_D.png normal=T_ManorTrim_N.png orm=T_ManorTrim_ORM.png roughness=
  ok: slot 0 (mullions + twin pulls) = MI_TrimMetalA_brass
  ok: slot 1 (painted slab) = MI_ManorTrim
  ok: slots are not collapsed/duplicated (order is real, not slot 0 twice)
  ok: each slot binds its own authored ORM map (AO + metallic + roughness input)
  ok: closed primary == "[F] OPEN"
  ok: closed secondary == "[F] [HOLD] LOCK"
  ok: during the swing primary flips to "[F] CLOSE"
  ok: during the swing the [HOLD] LOCK row is withdrawn
  ok: the leaf is swinging (angle 0.0 -> 26.2 deg)
  ok: swing completes at the authored 90 deg (got 90.0)
  ok: open door stays on "[F] CLOSE"
  ok: while closing primary is "[F] OPEN"
  ok: close returns the pivot to 0 deg (got 0.0)
  ok: closed again restores "[F] OPEN" + "[F] [HOLD] LOCK"
  ok: door carries the authored lock band 2..3 (got 2..3)
  ok: interact_hold locks the closed door
  ok: [HOLD] LOCK stays inside the authored band (lock_level=2 in 2..3)
  ok: locked primary reads "[F] PICK LOCK (Lv 2)"
  ok: locked door offers no second hold action
  ok: interact on the locked door starts a pick
  ok: the pick drives actor.set_lockpicking_active(true)
  ok: the pick unlocks the door (locked=false)
  ok: a successful pick swings the door past the 70 deg leaf gate (angle 90.0)
  ok: the unlock clears actor.set_lockpicking_active
  ok: HUD primary label renders "OPEN"; primary keycap renders F
  ok: HUD secondary text renders "[HOLD] LOCK"
  ok: HUD secondary row has its own white F keycap
    HUD layout: parent_w=1280 primary row y=668.0..698.0 secondary row y=698.0..722.0
  ok: HUD stacks the secondary BELOW the primary
  ok: both rows share the reticle centre (primary 640.0, secondary 640.0)
  ok: the stack is centred on the screen axis (row centre 640.0, axis 640.0)
  ok: HUD flips to "CLOSE"
  ok: HUD hides the whole secondary row when the door reports none
  ok: authored lockpick table present in interactables.json
  ok: authored minigame is ARC/circular: arc_angle_deg=80 deg, duration=3.0 s
  ok: authored jam table + cancel radius present (jam 5/10/20/40, cancel=200 cm)
  ok: HUD owns the circular lockpick overlay entry points
    lockpick UI nodes on the built HUD fragment: overlay=true dial=true
P1_DOORS checks=47 fails=0
P1_DOORS PASS
```

Regression set on the same tree (the two touched shared scripts):

```
check_scripts_compile  scripts checked: 203, broken: 0
run_tests.gd           SUMMARY: fails=0   (322 PASS, unchanged floor)
```

`roughness=` is empty in both slots because the ORM map is consumed through the
L8 roughness bake (`roughness_texture` green channel, an `ImageTexture` with no
resource path); the `orm=` column is the same authored map bound as AO +
metallic, so the PBR set is complete for both slots. The probe exits with the
same `ObjectDB instances were leaked at exit` / `resources still in use`
lines the committed `probe_blackjack_race` and `test_gc_break_trigger` logs
carry; they are the engine's exit-order noise, not a new leak.

## 8. Rows

| row | before | after | evidence |
|---|---|---|---|
| V3-03 blue door paint/mullions/brass | N/A-route (subject never reached) | **scoreable**: 4 authored porch pivots spawn, 2 authored slots bound in GLB order, slot paths asserted | §1–§2, probe |
| UI2-05 blue door prompts | DELTA (pair rendered, second row without a keycap) | **PASS at copy + layout**: `[F] OPEN` over `[F] [HOLD] LOCK` with two badges, flip to `[F] CLOSE`, secondary withdrawn while swinging | §3, probe |
| PG-2 `circular_lockpick_minigame_ui` | "no circular lockpick minigame" | **open, re-scoped**: the dial exists and is authored-parameterised; the authored widget art is a HARD_LIMIT and the harness node names are a PORT_DECISION | §5 |

Wording that must follow this report: V3-03's four descriptors are **two**
authored slots (mullions = brass slot, "glass" = the slab); do not describe the
blue cast as an authored paint material without a lighting row to carry it.

## 9. Not in this lane

* No GPU capture: the visible blue/cream read is scored by the integrator's
  `build/qa/p0b_capture.sh` KF24 pose.
* No producer or generated-data edit: `game/data/generated` stayed read-only.
* The doors' *lock* state at mission time is untouched: they are authored
  unlocked, so a normal approach never shows a pick prompt (matching KF24).
