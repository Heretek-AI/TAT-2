# Handoff — Thick As Thieves Godot 4.7.2 port (next session)

**Repo:** `/home/john/Projects/TAT-2`
**Code tip at handoff:** `6fd286f` (W10-A merged + the guard diagnostic + a suite-45
measurement fix); this file is the docs commit on top of it, pushed to `origin/main`.
**Working tree:** clean apart from private/derived data. Worktrees can be removed.
**Godot:** `4.7.2.stable` via native `tools/godot` (`godot` is **not** on `$PATH`).
**Renderer:** Forward+ · Jolt 60 Hz · 1280×720 reference · Linux x86_64.
**Steam reference:** `/home/john/.steam/steam/steamapps/common/Thick As Thieves/`.

## 1. State in one paragraph

The port runs the shipped Guildhall with authored collision (98.9 % of meshes),
authored progression and locks, authored UI tables, a Wwise control plane, and a
StateTree interpreter in **shadow** mode. Three waves have landed since W7: **R8**
(12 remediation teams), **W9** (data consumption, visual truth, UI completeness) and
**W10-A** (correctness and evidence). The remaining work is no longer "make it load";
it is a small set of **specific gameplay defects** found in a live playtest, then
behaviour (AI, Niagara, audio) and finally the exposure/IBL look pass.

## 2. Gates at this HEAD (all measured, logs in `docs/reports/logs/w10/`)

| Gate | Value |
|---|---|
| compile | **190 checked, 0 broken** |
| `run_tests.gd` | **319 PASS, fails=0** (suites to 116) |
| `test_m2_player.gd` | fails=0 |
| E2E | **278/278** (tier 1 117) |
| probes | doorwalk · viewmodel truth · Niagara · blackjack · geometry · **collision per-map** (`COL_MAPS PASS maps=3 min_coverage=0.976 dropped=0`) · lock inventory (`applied=154`) |
| `make runtime-smoke` | **PASS** (`exit=124`, 0 `ERROR:`, `mission_ready=1`) |
| `make audit` | PASS — 12,660/12,703, 0 unexpected |
| texture cap | 797/1/0 |
| perf guard | 78/78 |
| `make gate-ratchet` | PASS (W10-A floors; raise, never lower) |

**Caveat:** no Vulkan capture since the lighting work. The interior numbers in
`docs/reports/w9-remediation-20261125.md` were measured on frame `215507`, where a
light-card slab covers half the screen — they are **not** a valid interior baseline
(see §4.5).

## 3. TOP PRIORITY — the playtest defects (guards and the civilian)

The 2026-11-25 playtest (Contract 02, `Mission.Guildhall.VaultHeist`) reported **no
guards anywhere**, an **untextured, inert NPC**, **cream slabs**, **floating on
nothing**, and walking through geometry. The first two are fully diagnosed:

### 3.1 Guards are placed on the floor above (`HIGH`)

`_ground_position(pos, 8.0, 30.0, 0.15)` (`mission_controller.gd:3662`) casts from
**8 m above** the marker and returns the **first** hit — a ceiling as often as a floor.
Runtime proof (`build/qa/w10/guards-report.md`, `guard-runtime.md`):

| guard | marker y | grounded y | floor | offset |
|---|---|---|---|---|
| `_100` | 36.50 | **44.20** | 35.53 | **+8.67 m** |
| `_101` | 36.65 | **44.20** | 35.53 | **+8.67 m** |
| `_102` | 37.85 | 36.65 | 36.50 | +0.15 |
| `_114` | 46.32 | 45.20 | 45.05 | +0.15 |

The hit is `SM_FloorConcreteB_4x4` at **44.05** — the 3rd-floor slab. Two guards walk
their 2nd-floor patrol route while standing on the 3rd floor.

**Fixes (in order):**
1. `_ground_position`: step past hits **above** the marker, accept the first surface at
   or below it (only `_spawn_guards` calls it).
2. Reject `|grounded − marker| > 2.0 m` with `push_warning` and skip; valid markers
   give 0.8–1.2 m.
3. Test: every guard within 2.0 m of its nearest marker (two of four fail today).
4. **Selection** (design): at Novice the first four eligible markers are 13–23 m above
   the start; the ground-floor Lounge marker `C_20` is rank **14** and never chosen
   (it is 0.70 m from the civilian). Add a storey-band pass or nearest-first, and drop
   the 3 `BP_AirshipGuard_*` skybox markers (y 122–394).
5. Optional: the producer's `spawn_elements` still classes the 800
   `BP_SmartObject_GuardDefensiveLocation_C` as `kind=guard`; the **loader** already
   diverts them (`candidates=119, smart_objects=800`), so this only matters for a
   future consumer — split `guard`/`guard_post` there.

**Not the cause:** guard meshes/textures/materials are fine (2–4 meshes each, visible,
AABB 1.881 × 2.319 × 0.662 m, bottom at the feet); no culling or freeing; lanterns lit.

### 3.2 The civilian is untextured and blind (`HIGH`, two one-liners)

- **Untextured:** `civilian_npc.gd:208-225` instantiates `SK_CivFemale_Common_01C` and
  its head GLB **raw** (zero textures, no `baseColorFactor`) and never calls
  `LevelLoader.bind_prop_scene_materials()` — the C2-01 fix used by loot, clues,
  pickups, bottles and doors. The authored albedo/ORM/normal maps all exist.
- **Blind:** `_can_see` (`civilian_npc.gd:452-468`) starts the LOS ray at
  `SightModel.eye_position()`, which is offset **1.2 m behind** the actor to orient the
  frustum. A doorway-backed civilian therefore starts the ray inside the jamb and never
  sees the player. Use `global_position + Vector3.UP * 1.5` (as `guard_ai.gd:1902`
  does). The 180° character yaw convention (guard `615`/`1182`, player `790`) is also
  missing and may make it face backwards.
- The test does not catch either: it uses no meshes and no wall behind the civilian.

### 3.3 Also confirmed, not yet fixed

| Defect | Evidence | Fix |
|---|---|---|
| **63 cream slabs** from `1m_Plane_Reverse` + `MI_EmisLight_Moonlight` | no albedo/opacity/emissive vector; loader invents white emissive at 0.5 (`level_loader.gd:1231-1249`, `1688-1689`) | treat light cards as additive/skipped; never default white |
| **All 229 turrets invisible** (1,308 parts) | `build_bp_mesh_templates` (`parse_tables.py:191-239`) never walks the BP parent chain; turret meshes live in the parent | merge parent templates; count unresolved stubs |
| **157 GeometryCollection actors never emitted** | 48 chests + 31 display cases etc.; no GC branch (`parse_tables.py:2083-2242`) | resolve GC mesh or fall back to the BP SMC; fail-loud |
| **3,288 mirrored instances, winding unverified** | 1,601 are floors/roofs; `level_loader.gd:6882-6887` flags it | one capture with `CULL_DISABLED`, then compensate |
| **Landscape visibility may be inverted** | `tat_landscape.gdshader:80-117` discards `vis > 0.5`; UE convention is 1 = visible. 27 m shell 70–87 % > 0.5, street 0–4 % | one reference sample |
| **Sky contributes no light** | sky 59 vs adjacent surfaces 2 (30:1); `sky_contribution=0`, `IBL available=false` | cubemap export + consumer (W10-C) |
| **Authored −4.00 EV bias not applied** | emissives 4 stops hot against a zero floor | apply the curve (W10-C) |

Fixed already in W10-A: ward-shard floating (coplanar convexes now skipped — 160
billboards), stair coalescing (stair paths exempt from the 16-hull cap), post-match
Continue/focus/ESC/timeout, trace file cap, runtime-smoke `ERROR:` scan.

## 4. Wave plan for the next session

**W10-A2 — playtest hotfix (do this first, ~2 days).**
§3.1 F1–F4, §3.2 both fixes, §3.3 cream slabs and turrets. Everything here has a
measured cause; none is a design discussion. Exit: a Novice run with a guard in the
ground-floor Lounge, guards within 2 m of their markers, a dressed civilian that flees,
and no cream slabs.

**W10-B — behaviour (~1–2 weeks).**
B1 StateTree parameters producer → navmesh bake → EQS consumer. B2 Niagara activation
bridge (2,647 of 3,695 placements never activate). Audio direction (23 music events,
645 VO lines, 85/11/16 switch/state/RTPC assets) moves to W11 unless B finishes early.

**W10-C — look (~1 week).**
Producer emits the AEM scalars (EV100 −10…+1, 0.2/2.0 f-stops/s, bias 0, V3 curve);
temporal model as a pure `step(dt, ev100)`; **pre-registered** criteria at both poses
*and* the gate approach. Cubemap export (`TextureCube` has no extractor branch) **and**
the consumer that never loads it. Re-grade on a representative frame set, not `215507`.

## 5. How to run everything

```bash
make run                     # native client
make test                    # run_tests (319)
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
tools/godot --headless --path game --script res://tests/test_m2_player.gd
tools/godot --headless --path game --script res://tests/probe_collision_authored.gd   # COL_MAPS
tools/godot --headless --path game --script res://tests/probe_lock_inventory.gd       # applied=154
tools/godot --headless --path game --script res://tests/probe_guard_positions.gd      # guard/marker offsets
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd          # 278
make runtime-smoke           # exit 124 only, ERROR: scan
make audit && make gate-ratchet
TAT2_GUARD_DIAG=1 tools/godot --headless --path game -- --qa-free-play   # guard spawn diagnostics
```

## 6. Invariants and hazards

- **Single Godot at a time.** Use `flock /tmp/opencode/tat2-godot.lock`; captures run
  alone. Never edit `game/` while a run is live.
- **Generated data is produced, not edited.** `game/data/generated/` and `extracted/`
  are read-only; regenerate only at merged HEAD (`make normalize`, `make anims`), then
  `make audit-refresh-stamps REASON=…`.
- **Workers do not push.** Two origin advances were observed this session that the
  integrator did not issue (`04d2e15` at 22:36, `7db091b` later). Content was correct,
  but treat any worker push as a contract violation and verify `origin/main` after each
  merge.
- **Do not weaken a test.** Changing an expectation needs evidence the assertion was
  wrong (e.g. the suite-45 delta → destination fix in `6fd286f`).
- **Collision is authored `AggGeom`** (`TAT2_COLLISION=authored|aabb`); planar convexes
  are skipped; stairs are exempt from the hull cap. Do not "fix" a floating surface by
  moving the loader's grounding offsets — check the ray first.
- **The StateTree runs in shadow** (`TAT2_STATETREE=off|shadow`): the FSM still drives.
  0/21 trees are fully evaluable because the payload drops node parameters; the contract
  is `build/qa/w9/p4-t01-contract.md`. Do not invent parameters.

## 7. Where the evidence lives

- `docs/reports/r8-remediation-20261125.md` — 12 teams, measured before/after.
- `docs/reports/w9-remediation-20261125.md` — four phases + what remains.
- `build/qa/w9/` — P0–P4 reports, audits, capture statistics.
- `build/qa/w10/` — W10-A report and audits, the guard investigation
  (`guards-report.md`, `guard-runtime.md`, `guard-static.md`, `guard-diag.log`),
  the collision per-map log and the lock inventory.
- `docs/reports/remediation-20261125/` — the 13 R8 team registers (S1–S6 evidence).
- `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` — 120-row scorecard.

## 8. Definition of done for the next run

```bash
git status --short                    # clean
make audit                            # PASS
make test                             # fails=0
tools/godot … probe_collision_authored.gd  # COL_MAPS PASS
tools/godot … probe_lock_inventory.gd      # applied == 154
tools/godot … probe_guard_positions.gd     # every guard within 2 m of a marker
tools/godot … run_e2e_tests.gd             # 278/278
make runtime-smoke                          # PASS
make gate-ratchet                           # PASS
git push origin main
```
