# P0b-HARNESS lane — acceptance harness (2026-11-26)

| | |
|---|---|
| lane | P0b-HARNESS (Lane H of `P0B_WAVE_BRIEF.md`) |
| base | `main` `09d8a30` (P0a merged) |
| branch | `w10/p0b-harness` (not pushed) |
| engine | `4.7.2.stable.official.ed1daf0bf` via native `tools/godot` |
| host | Linux x86_64, headless, one Godot at a time under `/tmp/opencode/tat2-godot.lock` |
| evidence logs | [`logs/p0b-harness/`](logs/p0b-harness/) |
| data | `game/data/generated` read-only symlink; no producer/loader edit |

This lane builds the acceptance instruments. It does not touch the loader, the
producer, the audit baseline or any extracted asset. Every number below comes
from a committed log in `docs/reports/logs/p0b-harness/`.

## Measured

| gate | result | evidence |
|---|---|---|
| compile | **199 checked / 0 broken** | `compile.log` |
| `run_tests.gd` | **322 PASS / fails=0** (suites 117/118/120 added) | `run_tests.log` |
| E2E tier 1 | **117 / 117**, `T1-22-A` ratchet check green | `e2e_tier1.log` |
| E2E tier a2 | **22 / 22**, wall 35.88 s | `e2e_a2.log` |
| E2E tier p2 | **12 / 12**, `expected_fail=1 expected_delta=1 unexpected_fail=0` | `e2e_p2.log` |
| cream RED proof | **RED as designed** (2 expected failures; not registered) | `cream.log` |
| `make gate-ratchet` | **PASS** with the new `e2e_a2` / `e2e_p2` gates | `gate_ratchet.log` |

`run_tests` moved 319 → 322 because suites **117** (guard placement, 35
checks), **118** (civilian, 22 checks) and **120** (GC hold-smash, 21 checks)
now run in the `w10_suite` child-engine loop. Suite **119** is deliberately not
registered: `test_w10a2_cream.gd` is a standalone RED proof of the
invented-white emissive (below).

## Suite registration

`game/tests/run_tests.gd` `w10_suite`:

| suite | file | summary marker | measured |
|---|---|---|---|
| 117 | `test_w10a2_guard_placement.gd` | `GUARD_PLACEMENT_SUMMARY: fails=0` | 948 ms |
| 118 | `test_w10a2_civilian.gd` | `W10A2_CIV_SUMMARY: fails=0` | 2436 ms |
| 120 | `test_gc_break_trigger.gd` | `GC_TRIGGER PASS` | 3585 ms |

The suite-number comment now reads `112-120`; the gap at 119 is explained in
that comment so the next reader does not "fix" it by registering a red suite.

## E2E tier `a2` — one real Contract 02 Novice load

`game/tests/e2e/e2e_a2_playtest.gd`, standalone (`--tier=a2`), not part of
`all`. It snapshots GameState, boots one real mission
(`instantiate_mission(2, 900, 1)`), frees it and restores the snapshot.

| check | measured |
|---|---|
| `A2-01/02` boot | `map=guildhall`, `mission=Mission.Guildhall.VaultHeist` |
| `A2-03` mode | `difficulty=1`, `free_play=false`, `phase=main` |
| `A2-04` run clock | `run_time_limit=7200 s` == authored mission row 7200 s (Novice) |
| `A2-05` guards | 4 (`PORT_DECISION` 4/6/8) |
| `A2-GUARD-META` | every guard carries `spawn_marker` |
| `A2-GUARD-DIST` | distances 0.967–1.313 m (≤ 2.0 m) |
| `A2-GUARD-FLOOR` | every guard ≤ 0.5 m off its marker floor ray |
| `A2-GUARD-BUCKET` | Lanterns/Bouncers only, never Hauntstable |
| `A2-GUARD-VISIBLE` | every guard visible with meshes |
| `A2-LOUNGE-BBOX` | tracked `poi-lounge-floor` region read from `content_overrides.json` = `(20,24,-46)..(52,32,-5)` |
| `A2-LOUNGE-GUARD` | Lounge guard marker `C_20` inside that bbox |
| `A2-CIV-COUNT` | 3 civilians |
| `A2-CIV-LOUNGE` | one civilian inside the tracked bbox |
| `A2-CIV-BIND` | total 9, bound 9, textured 8, `default_white=0` |
| `A2-CIV-FACING` | skeleton basis · actor forward `dot=1.0000` |
| `A2-CIV-FLEE` | stand-in player 4 m out (+30° clear candidate): `state=flee`, `yelps=1` |
| `A2-WHITE` | 6,740 visible render nodes, 397 shader surfaces, **0 unexplained**, 3 allowlisted groups |
| `A2-SHELL` | 4/4 horizontal shell rays + floor hit from the Lounge guard |
| `A2-TURRET` | authored 1,145 visible / 0 hidden; runtime 0 meshless, 0 missing paths (91 individual nodes; the rest are merged cells) |
| `A2-GC-STATS` | `gc_layers_built=174` (≥95), `gc_leaves_built=80` (≥79), `visible_broken=0`, `missing=0` |
| `A2-GC-SWAP` | one real chest leaf → broken, opened once |

### Near-white allowlist (explicit, measured in the same run)

| key | instances | reason |
|---|---|---|
| `/engine/basicshapes/` | 3 (1 cone, 2 cubes) | authored `/Engine/BasicShapes` placeholders with the engine `BasicShapeMaterial` (not in the shipped material DB; neutral 0.9547 grey, **no emission**). The loader reports `material flat white: BasicShapeMaterial … flat=3`. `PORT_DECISION`, not a loader invention. |
| `guardlantern/lanternmesh/` | 2–5 | port guard lantern GLB glass is untextured; the authored warm lantern light (1.0, 0.72, 0.34, energy 1.4) carries the colour. `PORT_APPROX` actor prop. |
| `carriedkeymesh/` | 3 | port guard carried-key GLB uses the glTF default; `PORT_APPROX` actor prop. |
| `/game/art/effects/skybox/`, `/game/art/effects/clouds/` | 0 in this load | authored unlit sky cards (kept for maps that show them). |

The cream-slab class (`1m_Plane_Reverse` / `MI_EmisLight_Moonlight`) is **not**
allowlisted. The tier also fails if a future edit tries to allowlist it:
`_check_near_white()` clears any allowlist match whose key contains
`1m_plane_reverse` or `emislight_moonlight`.

**`a2` is not in `all`.** It is green standalone (35.88 s) and self-contained;
the full run's floor stays 278/278 until the integrator adds it and reports the
new total. Adding it is a one-line change in `run_e2e_tests.gd`; no measured
reason blocks it.

## E2E tier `p2` — authored-data parity, never in `all`

`game/tests/e2e/e2e_p2_parity.gd`, standalone (`--tier=p2`). PASS checks are the
gate; recorded deviations print as `P2_EXPECTED_FAIL` / `P2_EXPECTED_DELTA` and
do not fail the tier. `P2_SUMMARY: … unexpected_fail=0` is the stable gate
marker; `fixed=N` tells the data wave what to promote.

| check | result | evidence |
|---|---|---|
| `P2-GUARD-META` | PASS | `guard_spawn_meta`: 116 markers, 116 buckets, 113 layer lists, 3 without layers, 0 unresolved |
| `P2-GUARD-BUCKETS` | PASS | Lanterns 67 / Bouncers 35 / Hauntstable 14 (selector must exclude the last) |
| `P2-GUARD-C20` | PASS | `C_20` = `DA_SpawnBucket_StandardGuards_Bouncers` + 4 `Security_GroundFloor_Lounge_*` layers |
| `P2-CIV-SLOTS` | PASS | body 3 (`PantsC`, `ShirtC`, `ArmsLegs`), head 6 (slot 3 `Base_Head`) |
| `P2-CIV-ALBEDO` | PASS | shirt `T_CivFemale_Common_01_Shirt_D.png`, head `T_CivFemale_Base_Head_D.png` |
| `P2-CIV-PANTS-ALBEDO` | **EXPECTED FAIL** | generated albedo `T_Civ_M_01_Top_D.png`; authored `T_CivFemale_Common_01_Pants_D.png` is in the `opacity` slot (`materials.json` `MI_CivFemale_Common_01_PantsC.texs`) |
| `P2-CIV-PANTS-OPACITY` | PASS | confirms the `BaseColorOpacity` → opacity misclassification is the cause |
| `P2-BEAM-AUTHORED` | PASS | `MI_LightBeam_SM` `BaseColor=[5.0, 4.3813, 3.5156, 0.5]`, `EmissiveMultiplier=3.0`, Additive, two-sided, Unlit |
| `P2-BEAM-SHADER` | PASS | loader builds `tat_beam.gdshader` (labelled stand-in) |
| `P2-BEAM-PORT-APPROX` | **EXPECTED DELTA** | port colour `(1.000, 0.930, 0.820)`, authored normalised `(1.000, 0.876, 0.703)`: `dG=0.054`, `dB=0.117`; energy port 1.70 vs authored 3.0×0.5=1.50, `dE=0.20` |
| `P2-CENSUS-TURRET` | PASS | 229 actors, 1,145 visible, 0 hidden, 0 missing GLBs (5 unique paths) |
| `P2-CENSUS-GC-LOOT` | PASS | Guildhall_Loot 95 components / 79 leaves, 0 visible emitted, 0 unresolved |
| `P2-CENSUS-GC` | PASS | whole payload: 107 level files, 336 components / 336 hidden / 0 visible / 0 unresolved / 93 fallback / 5 sibling SMC / 166 leaves |
| `P2-GC-LABEL` | PASS | authored `ST_Interactables.PromptDestroyDeployable = "Destroy"`; the `[F] [HOLD] ` keycap prefix is port copy |

Citations (all authored rows, no runtime guessing):

- pants: `game/data/generated/materials.json` →
  `MI_CivFemale_Common_01_PantsC.texs.albedo = T_Civ_M_01_Top_D.png`,
  `.texs.opacity = T_CivFemale_Common_01_Pants_D.png`.
- beam: `game/data/generated/materials.json` → `MI_LightBeam_SM`
  (`vectors.BaseColor`, `params.EmissiveMultiplier`, `render.blend_mode`);
  port constants in `game/src/core/level_loader.gd:1478-1482`.
- turret/GC: `Guildhall_Gameplay.tatlevel.json` (`actors` / `meshes`),
  `Guildhall_Loot.tatlevel.json.gc_stats`, whole-tree `gc_stats`.
- GC label: `game/data/generated/tables/StringTables/ST_Interactables.json`
  (`entries.PromptDestroyDeployable`) and `game/src/interact/loot_container.gd:403`.

## `test_w10a2_cream.gd` — RED proof (suite 119 is not registered)

Standalone SceneTree proof; **not** in `run_tests.gd` and not a gate. Current
result (`cream.log`):

```
CREAM_CHECK PASS moon cards authored hidden: total=122 visible=0 (want >=60 / 0)
CREAM_CHECK PASS MI_EmisLight_Moonlight resolves without invented white (class=StandardMaterial3D)
CREAM_EXPECTED_FAIL _apply_ue_emissive invents no white for EmissiveStrength-only material (enabled=true colour=(1.0, 1.0, 1.0, 1.0) energy=2.00)
CREAM_EXPECTED_FAIL loader exposes a tat_invented_white counter (67 properties)
CREAM_PROOF: RED passes=2 expected_fail=2
```

The two expected failures are the data wave's contract:

1. `_apply_ue_emissive()` must not invent white when a material has
   `EmissiveStrength` but no `EmissiveColor` and no emissive map. It currently
   leaves `col = (1,1,1)` and applies the strength (measured with a synthetic
   `EmissiveStrength=2.0` material → white, energy 2.00).
2. The loader must expose a `tat_invented_white` counter/meta so the census is
   measurable. It does not exist today.

The authored moon cards themselves are already safe: all **122**
`1m_Plane_Reverse` instances across every generated level are
`hidden_in_game: true`, and `MI_EmisLight_Moonlight` resolves to the black unlit
material (no albedo, no emission).

## `T1-22-A` replacement

The old check was `run_tests.gd` contains the literal `# 38.`. It is replaced by
`e2e_helpers.suite_ratchet_stats(rt_src, ratchet_v, log_text)`:

- numbered suite markers from comments (`# 117.`) **and** child-engine suite ids
  (`["117", …]`) must be **≥ 38**, with **max ≥ 120**;
- the floor is read from `tools/gate_ratchet.json` `gates.run_tests.passes`
  (no second copy in the test);
- the committed log named by `evidence.dir` + `evidence.run_tests` must record
  `SUMMARY: fails=0` and at least the floor's `PASS` lines.

Measured at this tip: `markers=97 max=120 floor=319 log_PASS=319 log_fails=0`
(the P0a committed log is still the ratchet evidence). Tier 1 stays green
(117/117).

## Gate ratchet

Added after the measured runs:

| key | value | log |
|---|---|---|
| `gates.e2e_a2.passed/total/fails` | 22 / 22 / 0 | `docs/reports/logs/p0b-harness/e2e_a2.log` |
| `gates.e2e_p2.expected_fail/expected_delta/fixed/unexpected_fail` | 1 / 1 / 0 / 0 | `docs/reports/logs/p0b-harness/e2e_p2.log` |

`tools/check_gate_ratchet.py` now accepts a repo-root-relative evidence path
(one containing `/`) so a later wave can keep its own log directory; bare
filenames still resolve under `evidence.dir`. No existing floor was lowered:
`e2e` stays 278/278 (a2 is standalone), `run_tests` stays 319 and `compile`
stays 196 because their committed evidence is still the P0a log. Those three
floors should be raised at merged HEAD (measured here: 322 and 199).

## Remaining for the data wave

- **Cream fix** (`_apply_ue_emissive` + `tat_invented_white` counter), then make
  `test_w10a2_cream.gd` green and register it as suite **119**; raise
  `run_tests` accordingly.
- **Pants albedo** producer fix (`parse_materials` must read the
  `BaseColorOpacity` companion as albedo, not opacity), then the p2 expected
  FAIL becomes a PASS and `fixed` moves to 1.
- **Beam material** P4 authored centre-line/fade; p2's expected DELTA then
  measures the new values.
- **a2 into `all`** after one full-run measurement; report the new E2E total and
  wall clock (a2 adds ~36 s here).
- **Ratchet re-stamp** at merged HEAD (compile 196→199, run_tests 319→322).

## Reproduce

```bash
flock /tmp/opencode/tat2-godot.lock -c 'tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"'
flock /tmp/opencode/tat2-godot.lock -c 'tools/godot --headless --path game --script res://tests/run_tests.gd'
flock /tmp/opencode/tat2-godot.lock -c 'tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=1'
flock /tmp/opencode/tat2-godot.lock -c 'tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=a2'
flock /tmp/opencode/tat2-godot.lock -c 'tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=p2'
flock /tmp/opencode/tat2-godot.lock -c 'tools/godot --headless --path game --script res://tests/test_w10a2_cream.gd'   # expected exit 1
make gate-ratchet
```
