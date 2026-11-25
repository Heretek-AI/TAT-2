# W6 integration — six waves merged onto `main`

Integration commit range: `f803c3b` (base) → `96fae4f` (fixes). Merge order and
resolutions below; every number is from a real serial run on the merged tree
(`96fae4f`), one Godot at a time. Thermal gate waived by the user; **no perf
matrix and no parallel Godot**.

## 1. Cherry-picks (all six applied with zero file conflicts)

| # | Source | Merged as | Wave / scope |
|---:|---|---|---|
| 1 | `91ce8db` | `a29b8fb` | **W6L** loader — metallic/roughness/emissive mapping, roof classifier, occluders, searchlights |
| 2 | `d2a6d6c` | `34b1c7e` | **W6M** player — blocker-safe step-up, traversal coverage, capsule contract |
| 3 | `77a5c1a` | `b118de0` | **W6G** AI — authored hearing/perception, single-light detection |
| 4 | `dc58f60` | `7128d43` | **W6U1** UI — authored briefing, 1200 s override, prep stage, Den poster light |
| 5 | `9884082` | `e108913` | **W6U2** UI — authored ledger/black market/wardrobe catalog, save migration |
| 6 | `e8052ef` | `915373f` | **W6T** tooling — graybox content overrides, Sonar CI config |

All six were direct children of `f803c3b`, so the ordered cherry-pick never had
to replay a sibling's edit. `game/tests/run_tests.gd` was auto-merged four times
(W6L 33b, W6M 45, W6G 26/55b, W6U2 60c/8) — **no hunk dropped**: W6U1 does not
touch `run_tests.gd` (its coverage is the standalone `test_w6u1_briefing.gd`);
"suite 60" in the brief is the W5 suite-60 family that W6U2 extends at 60c.
`tools/audit_baseline.json` took the W6T side and was then regenerated (below).

## 2. `make normalize` — all 21 producers

Exit 0. The four W6 producers reported their new data:

```
Content overrides: 11 rules applied, 508 matched, 133 re-materialised
  poi-lounge-floor-tile: 130/5      poi-lounge-floorstone: 4/4
  poi-entrance-hall-floor-tile: 26/1  vault-chambers-floorstone: 36/33
  poi-3rd-floor-tile: 229/20        poi-3rd-floorstone: 16/16
  poi-3rd-roof-deck-slate: 1/1      missionlobby roof/structure: 3/3, 11/10, 8/8, 44/32
quests: contracts=16, missions=11, quest_graphs=18, mission_briefings=3; validation=PASS
unlocks: 68 entries, 68 unique save ids, 68 icons, prices 55/13
hearing: 54 stimuli, 22 loudness surfaces, 11 weather types, 285 acoustic portals
```

**W5B roof census unchanged.** `test_roof_collision` re-runs the live census and
asserts the W6L split: **733 instances / 46 unique meshes**, pitched roofs
**426 / 19 convex** and flat roofs **307 / 27 box** (pre-W6L: 334 / 399), roof
occluders **0**, `MAX_OCCLUDERS` 768. W6T's `set_material` only rewrites
`override_material(s)`, so it cannot move a collision/occluder count.

## 3. Audit — baseline diff (intentional, no silent drift)

`make audit-refresh-stamps` then `make audit`: **PASS**.

```
CONTENT_OVERRIDES: PASS        6/6 coverage regions, 0 graybox floors left
texture cap check: OK          773 capped, 1 alpha-critical kept, 0 offenders
Case-sensitive parity:         12630/12703 (99.4%), unexpected 0; effective 100.0%
Disk-backed coverage:          12657/12703 (99.6%), 0 unexpected
UBULK companions:              4088 manifest, 0 missing
AUDIT PASS
```

Baseline diff after normalize (from the W6T-side file):

| producer / output | change | verdict |
|---|---|---|
| `parse_quests.py` → `gen:gameplay/quests.json` | 421,806 → 425,493 B, sha | **W6U1** briefings |
| `parse_unlocks.py` → `gen:gameplay/unlocks.json` | 83,788 → 117,228 B, sha | **W6U2** save ids / catalog |
| `parse_gameplay.py`, `parse_tables.py` → `gen:gameplay` | 5,337,591 → 5,374,718 B | **transitive only**: the `gen:gameplay` directory hash moved by exactly 3,687 + 33,440 = 37,127 B = the two files above |
| `parse_state_tree.py` → `docs/reports/w5e-guard-state-tree.md` | sha | grep counts moved with W6G's `guard_ai.gd`; the hearing prose was updated (see §4) |
| all other entries | `newest_mtime` only | restamped, no content change |

No unrelated content drift. `make texture-cap-check` needed no re-cap run (the
`.import` sidecars are unchanged since the last `desktop-texture-cap`); no audio
tool pin changed.

## 4. Five merged-tree defects found and fixed

None were file conflicts; all appeared only when the six waves met.

1. **`level_loader.gd` — `get_meta(key, null)` error spam (W6L).** Godot treats an
   explicit `null` default as "no default" and logs
   `ERROR: The object does not have any 'meta' values with the key
   'ue_roughness_remap'` for every material without the meta (door-walk log: 6+
   occurrences). Replaced with a `has_meta()` guard. Behaviour identical
   (`test_w5b_materials` 71/71, door walk PASS).
2. **`run_tests.gd` 60c — ambient save dependency (W6U2).** The gated-row
   assertion assumed `pickpocket_fairy` is unowned, but W6U2's own migration maps
   legacy `"fairy"` → `"pickpocket_fairy"`; a live save that had played owned it,
   so the row read `✓ PURCHASED` (`state=60c` FAIL on the first full run). Fixed
   by pinning the shipped starter profile (`xp 0`, `STARTER_TOOLS`, no completed
   contracts) for the gate assertions; the whole dict is restored afterwards.
   The assertion itself is unchanged (still `Requires Contract 3` + no BUY).
3. **E2E `T3-25` — positive control over-specified (W6G).** It required
   `state == SUSPICIOUS` after 240 frames, which only held while the removed
   port-only `vis_mult` light multiplier slowed the ramp. W6G makes detection
   gain light-independent; the authored 12 m ramp legitimately reaches
   100/COMBAT in the same 4 s. The test's own docstring asks only for "reaches
   the authored SUSPICIOUS threshold", so the control is now
   `det >= 15 and state != NEUTRAL`. Both occlusion negative controls (wall,
   second-guard body) still assert exactly 0. Tier 3 re-run 25/25, then full
   E2E 264/264.
4. **`test_content_overrides.gd` — vacuous static test (W6T).** GDScript's
   `dict.get(k) or []` returns a **bool** (unlike Python), so `var arr: Array =
   … or []` threw `SCRIPT ERROR` and every `for … in (… or [])` iterated a bool.
   The test printed `fails=0` without checking anything. Added `_arr()` and
   routed all JSON lists through it: **2 → 447 executed PASS assertions**, 0
   fails, no script errors.
5. **`parse_state_tree.py` — stale generated prose (W6G).** Its curated
   state-tree table said "the 54 authored stim rows in hearing.json are not
   wired". W6G wires all 54 (MaxRange × surface × weather, `heard_by`/query
   gating, Short/Long investigation). Prose updated; report regenerated.

## 5. Gates (serial, on `96fae4f`)

| Gate | Result |
|---|---|
| compile (`check_scripts_compile.gd`) | **110 checked, 0 broken** |
| `run_tests.gd` | **fails=0**, 263 PASS |
| `test_m2_player.gd` | **fails=0**, 11 PASS |
| `probe_door_walk.gd` | **DOORWALK PASS** (no meta ERROR spam after 4.1) |
| `probe_viewmodel_truth.gd` | **VIEWMODEL_TRUTH PASS** (`zip_emissive=off`, `top_emissive=off`, `crank_bone=crank_arm`, posed, reset) |
| `probe_niagara.gd` | **NIAGARA_PROBE PASS** |
| `probe_leak.gd` (`TAT2_NO_DEN_PROBE=1`) | clean, exit 0; documented warnings only (5 authored hearing-range clamps, Niagara placement notices, deferred navmesh, Lumen-only post volume) |
| E2E `run_e2e_tests.gd` (tiers 1–4) | **264/264, fails=0** |
| `make texture-cap-check` | **OK** — 773 capped / 1 alpha-critical / 0 offenders |
| `make audit` | **PASS** — coverage 12657/12703 (99.6 %), 0 unexpected |
| `test_w5b_materials.gd` | fails=0, **71** PASS |
| `test_roof_collision.gd` | fails=0, **51** PASS |
| `test_w6l_searchlight.gd` | fails=0, **16** PASS |
| `test_hearing_ranges.gd` | fails=0, **39** PASS |
| `test_light_once.gd` | fails=0, **7** PASS |
| `test_w6u1_briefing.gd` | fails=0, **37** PASS |
| `test_w6u2_catalog.gd` | fails=0, **61** PASS |
| `test_stair_walk.gd` | fails=0, 19 PASS |
| `test_traversal_routes.gd` | fails=0, 18 PASS |
| `test_content_overrides.gd` (static) | fails=0, **447** PASS (was 2 vacuous lines) |

Compile is **110**, not ~108: the six waves add four test scripts and W6T adds
one, and the checker counts every `res://` script.

## 6. W6L roughness-bake cost (reported, not switched)

The bake adds **~3.85 s and ~98 MiB** per Guildhall load (86 bakes / 73.9 M px,
`ROUGHNESS_BAKE count=86 pixels=73924608 ms=3848`, one line per load). No gate
timed out or OOMed on it: E2E and the map probes completed normally. The
sanctioned fallback (`mat.roughness = rough_high`, no `ue_roughness_remap`) is a
**separate decision** and was not taken.

## 7. Decisions and residuals

- **W6 ownership respected.** `level_loader.gd` only W6L, `thief_character.gd`
  only W6M, `guard_ai.gd`/`noise_bus.gd`/`weather_profile.gd` only W6G,
  `game_data.gd`/`mission_controller.gd`/`hud.gd` only W6U1, `save_system.gd`
  only W6U2, `Makefile`/`content_overrides.json`/`.sonar-project.properties`/
  `.github` only W6T.
- **W5 hooks intact**: Spider personal chain, device emitters, perf guard and
  the `blocking_volume`/`swinging_doors`/`loot`/`xray_target` runtime contracts
  are unchanged; W6M only *consumes* `blocking_volume`.
- **Residuals** (carried from the wave reports, not new): stair **descent is
  re-seated, not glued** (short one-riser falls on 0.33 m treads); the 1.82 m
  capsule needs ~4 cm more headroom in tight fits; `device_geometry.gd` and the
  W3 beam mock still assume 1.78 m (owner: devices); W6T's `add_cap` is
  implemented but disabled (no capture proves a missing slab); material choices
  for the graybox overrides are authored but not capture-verified; SonarCloud
  manual binding and `test_perf_census` are still unrun; the guard StateTree
  data still does not drive `guard_ai.gd`.
- **Not run**: perf matrix, Vulkan captures, `make run` visual pass, full editor
  open, Sonar scan. Not pushed.
