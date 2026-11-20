# TAT-2 Codebase × Gameplay Audit — Merged Report

Date (UTC): 2026-11-20. Method: merge of four read-only lane reports; every
Top-10 item below was re-opened this turn and cites the reproduced span.
No product code touched.

Lane sources (`game/` HEAD post-round-1 + round-2 playtest fixes):

- `audit-core.md` — `game/src/core/` + `game/src/stealth/`. P0 5 / P1 41 / P2 10.
- `audit-gameplay.md` — missions, thief, guard AI, civilians, interact ×9,
  noise/light-gem, save handoffs. P0 8 / P1 14 / P2 12.
- `audit-ui.md` — all 10 files under `game/src/ui/`. P0 1 / P1 4 / P2 9.
- `audit-pipeline.md` — `tools/tat-extract/`, `tools/parse_*.py`,
  `game/data/generated/`, `game/tests/`. P0 5 / P1 9 / P2 7.

Totals across lanes: **P0 19 / P1 68 / P2 38** (before dedup; §2 notes the merges).

Spot-check result: **10 of 10 re-read claims reproduced, 0 dropped.**
Checked spans: `audio_manager.gd:478-484`, `game_state.gd:126-131`,
`thief_character.gd:1760-1783`, `guard_ai.gd:1011-1022`,
`main_menu.gd:412-414`, `level_loader.gd:1685-1688`,
`Exporter.cs:209`, `parse_tables.py:1202-1208`, plus
`net_manager.gd:159-173` and `settings_ui.gd:14-18` as second witnesses for
their lanes. No lane claim is repeated below that was not re-opened.

---

## 1. Top 10 cross-cutting findings (deduped)

Dedup merges applied: core P0-3 + gameplay P0-7 → T3 (one loot-threshold
split); gameplay P0-1 + P0-2 → T7 (one deploy-handoff defect);
gameplay P0-3 + P0-4 → T8 (one key-contract defect family);
pipeline P0-1 + P0-2 → T10 (one extractor-trust defect).
UI P0-1 stands alone as T9. Core P0-2 (anim clip) and gameplay P0-8
(civilians) fall just outside the top 10 and head the P0 backlog (§3).

### T1 — Blackjack has no light attack; KO guards farm the takedown counter [gameplay]

`game/src/player/thief_character.gd:1772-1779` — both branches assign
`heavy_dmg`; `base_dmg` (`:1760`, `BlackjackDamageLight`) is fetched and never
used. The loop (`:1764-1783`) never skips `state == 5` (KNOCKED_OUT) while
`GameState.takedowns += 1` (`:1781`) and the 4.5 m takedown noise (`:1782`)
fire on every swing; `knock_out` early-returns on already-KO
(`guard_ai.gd:1181-1182`). Repeated swings on one sleeping guard inflate score
(`hud.gd:1728` consumes `GameState.takedowns`) and re-alert the area.
Fix: use `base_dmg` for the non-behind case, skip state 5, count only
transitions into KO. (Reproduced verbatim this turn.)

### T2 — SEARCH guards cannot be re-alerted by sight; vision/hearing disagree [gameplay]

`game/src/ai/guard_ai.gd:1016` (`state < Alertness.ALERTED`) is false for
`SEARCH(4)` and `:1020` (`state == NEUTRAL`) likewise, so a SEARCHing guard
staring at the player at detection 15–99 stays in SEARCH; only
`>= 100 → _enter_combat()` escapes. The noise path (`:1158-1160`,
`if state != ALERTED and state != COMBAT`) correctly pulls SEARCH→ALERTED —
the two senses implement different transition tables. Dead zone 15–99 jumps
straight to instant combat at 100. Fix: rank-based comparisons
(`ALERTNESS_RANK`), not raw enum order (`SEARCH(4) > COMBAT(3)`).
(Reproduced verbatim this turn.)

### T3 — Two loot thresholds disagree; riches alone can complete missions [core + gameplay]

`game/src/core/game_state.gd:126-130`: `are_all_objectives_complete()`
returns `true` on `loot_value >= loot_goal` with quest entries incomplete,
and `update_objective_progress()` (`:110-112`) fires `objective_completed` on
the loot path. Meanwhile `escape_gate.gd:75` opens on
`loot_collected >= GameState.loot_needed`, where `loot_needed = 5`
(`game_state.gd:26`) is never assigned anywhere else (grep-verified) and
`reset_run` (`:47-62`) never touches it — while a Cleanout sets
`loot_goal = 1000 × difficulty` (`mission_controller.gd:1186`).
Net: the gate opens at 5 items *or* at goal (a shortcut around a £3000 goal),
and the HUD (`hud.gd:2152`) shows count-vs-5 while objectives track value.
Three readers, three thresholds. Fix as one: single source of truth
(`loot_goal` + quest flags), gate and HUD read it. (Reproduced this turn.)

### T4 — Unauthenticated `any_peer` RPCs drive `interact()`/`triggered` by node name [core]

`game/src/core/net_manager.gd:75-77` (`sync_player_state`), `:86-88`
(`sync_world_event`), `:159-173`: `root.find_child(target_name, true, false)`
then `target.call("interact", self)` / `target.emit_signal("triggered")` —
any peer spoofs positions and triggers vaults/doors/quest logic by name, no
allowlist, no ownership check; `interact` receives the NetManager, not the
interactor. Not shippable for public lobbies as-is. Must land before the
co-op deploy path is enabled (T7), or the newly reachable co-op mode is born
vulnerable. (Reproduced this turn.)

### T5 — `player.get_rid()` on a `Node3D` throws on every Guildhall/OldManor footstep [core]

`game/src/core/audio_manager.gd:469-484`: `_is_indoor()` builds
`Array[RID] = [player.get_rid()]`, but `Node3D` has no `get_rid()` (only
`CollisionObject3D`). Path runs per footstep via `_footstep_clip` →
`_scene_surface` → `_is_indoor` outside the Den (which early-returns `"wood"`
before the raycast). First non-Den step throws. Fix: exclude by
`CollisionObject3D` (`get_collision_exceptions` / collision-layer check) or
guard with capability check. (Reproduced verbatim this turn.)

### T6 — Collision shapes past 32k are silently dropped: walk-through geometry [core]

`game/src/core/level_loader.gd:1685-1688`:
`if int(ctx.get("collision_shapes", 0)) >= MAX_TOTAL_SHAPES: return`
(`MAX_TOTAL_SHAPES = 32000`, `:95`). No warning, no counter. Guildhall maps +
curb ribbons (3 boxes per segment, `:2021-2024`, P1-L4 feeds this budget)
share it, so overflow drops colliders late in load order depending on parse
order — walk-through walls/floors. Fix with the curb cap as one job: budget
partition (buildings vs curbs), counted warning, fail-loud at export.
(Reproduced verbatim this turn.)

### T7 — Deploy handoff drops the mission choice AND the co-op mode [gameplay]

Two halves, one seam (`mission_controller.gd:1132-1134`
`reset_run(order_id, map_id)`). (a) `mission_prep_ui.gd:151` emits
`(map_id, difficulty, mode, contract_order)` with no mission id; setup
re-derives positionally (`:1150-1153`,
`matching[absi(order) % matching.size()]`), discarding the OptionButton
override (`mission_prep_ui.gd:688-693`). (b) The table keeps a local
`coop_mode` (`contract_table_ui.gd:23,504-507`) emitted in `mission_selected`
(`:517,544`, zero listeners); the deploy closure takes `(order_id, map_id)`
only. The sole live writer is the Den floor R-toggle (`:726`). Host/Join +
DEPLOY launches whatever the R-key last set. Fix: thread mission id + mode
through deploy; T4 (net auth) must land first. (Lane-verified; spans quoted
in lane report.)

### T8 — Mission data lost to key mismatches: clue text + Den-card F hint [gameplay]

(a) `_spawn_clues` reads `contract_info.get("clue", …fallback)`
(`mission_controller.gd:1222`) and loading reads `get("clue", "")` (`:147`),
but `GameData.get_contract_display` only ever writes `"clue_facts"` (array,
`game_data.gd:389`; zero `"clue"` writers) — mission clue and loading clue are
always generic/empty while the table intel panel (which reads `clue_facts`)
is correct. (b) The Den card sends `"hints"` (`:930,966-970,981`) but
`set_den_lookat_card` (`hud.gd:1840-1871`) renders only
`lines/difficulty/mode/prompt/bottom_hints` — the F row
("Prepare for Mission" / "PONDER" / "EXIT") is dropped; only the 3D Area
prompts advertise it. Both are producer/consumer contract breaks, fixable as
one pass: reconcile keys, add a debug assert on missing keys.
(Lane-verified; key names quoted in lane report.)

### T9 — Main-menu Contract Journal is built, permanently hidden, unreachable [ui]

`game/src/ui/main_menu.gd:414` (`journal_panel.visible = false`) behind
`:412` `# Contract Journal drawer (hidden until "CONTRACTS & CO-OP" is clicked)`.
No "CONTRACTS & CO-OP" button exists — the menu is exactly
PLAY/SETTINGS/CREDITS/QUIT (`:391,400,404,408`) — and PLAY hardcodes
`selected_order = 1` (`:393`). Contract selection, difficulty choice, and
co-op from the main menu are dead paths; the only live route is the Den map
table. Fix after T7 (journal LAUNCH must use the fixed deploy path): add the
entry, or delete drawer + comment if the Den table is the intended single
route. (Panel + comment reproduced this turn.)

### T10 — Extractor allowlists silently drop assets and count skips as success [pipeline]

`tools/tat-extract/Exporter.cs:205`: closed mesh allowlist
(`SM_/SK_/SKM_/GB_` + round-2 `VFX_/Coin_` + 8 path substrings); texture
(`:169-174`, `T_` or `/Textures/` + 4 hardcoded stems) and material (`:132`,
`MI_/M_`) gates are the same shape — anything outside drops with no
dropped-file log (it already bit once: round-2 +9 GLBs). Worse,
`Exporter.cs:209` (same `:123`, `:186`) checks the wrong output path for the
overwrite-skip and `Count("meshes", true)`s the skip — `ok=` cannot
distinguish fresh / skipped / re-exported. Plus `Trunc(300)` + 5000-entry cap
+ append-never-rotate `errors.log` (`:53,69,307`). Fix: real-path skip check
with separate skip counter, per-command skipped-by-filter counts (or
deny-list), untruncated per-run error log. (Allowlist + skip lines reproduced
this turn.)

---

## 2. P0 fix list, dependency-ordered

Every edge states its reason. Items merged in §1 are fixed as one job.

1. **T10 extractor trust (P0-2 skip-count, P0-3 error log, then P0-1
   allowlists).** Reason: all downstream content numbers (door counts,
   mesh binds, `mesh_materials.json`) are measured by this tool — fix the
   ruler before re-measuring. Inside the job: skip-path correction first
   (pure measurement), then error-log hygiene, then allowlist widening with
   skipped-by-filter counts.
2. **Pipeline P0-4 (parsers swallow corrupt levels,
   `parse_tables.py:1202-1208`) + P0-5 (MID `""` provenance,
   `parse_tables.py:763-766,809-856`).** Reason: depends on (1) — once the
   extractor reports honestly, the normalizer must fail closed too, or
   corrupt `Maps/*.json` still vanishes silently. Emit
   `null`-vs-`UNRESOLVED` distinction + sidecar list.
3. **T6 collider budget (+ L4 curb cap).** Reason: needs honest mesh/collider
   numbers from (1)–(2) to size the partition; world integrity underlies
   every gameplay fix below (spawns, chases, escapes assume solid floors).
4. **T5 audio crash.** Reason: independent crash, one-line class of fix;
   takes priority by severity once the world loads. No dependencies.
5. **T3 loot-threshold unification.** Reason: redefines the win condition —
   every spawner/economy/ledger check below must be validated against the
   single threshold, so it precedes balance work.
6. **T1 blackjack (use `base_dmg`, skip state 5, count real KOs).**
   Reason: follows (5) — the takedown counter feeds score/ghost thresholds
   that only mean something after the win condition is fixed.
7. **Core P0-2 (`animation_library.gd:~660/~700` first-clip ignore) +
   gameplay victim-sync (`guard_ai.gd:411` `play_takedown_vic` uncalled;
   attacker montage fires on whiff, `thief_character.gd:1759`).**
   Reason: follows (6) — takedown damage/counter must be right before its
   presentation is wired; fix clip-name matching, then call (or delete)
   `play_takedown_vic` explicitly.
8. **T2 SEARCH sight promotion (rank-based).** Reason: independent of
   5–7 but touches the same guard file regions; sequence after to avoid
   merge churn in `guard_ai.gd`. Includes the KO-wake meter ceiling
   (P1, `:1223-1230` keeps pre-KO 100) in the same pass.
9. **Gameplay P0-8 (civilians wander once, `civilian_npc.gd:186-196`;
   `_pick_new_target` only in `_ready`).** Reason: independent AI loop;
   scheduled after guard work so civilian repick/stuck-timeout can reuse the
   guard-scan patterns. Add navmesh/ray validation + stuck timeout.
10. **T4 net auth (allowlist + ownership on `sync_world_event`,
    throttle `sync_player_state`).** Reason: must precede enabling any new
    co-op entry point — hardening before widening.
11. **T7 deploy handoff (mission id + mode through deploy).**
    Reason: follows (10) — the co-op half of this fix becomes reachable
    externally, so the transport must already be authenticated. Also follows
    (5): mode/difficulty feed `reset_run`, which reads the unified goal.
12. **T8 key mismatches (clue + card hints).** Reason: consumer-side fixes;
    safe any time after (5) (clue facts ride `get_contract_display`,
    touched by the loot work). Add missing-key debug asserts.
13. **T9 journal entry.** Reason: terminal — LAUNCH must call the fixed
    deploy path from (11); otherwise the restored button ships the old drop.

---

## 3. P1 backlog (condensed; full spans in lane reports)

**Core (41):** loader L1 missing-mesh hole / L2 null-texture guessing /
L3 Den string-gating / L5 guildhall `discard_holes` map-name match /
L6 emissive-vs-shadowless desync; anim A1 shared-instance wipe / A2
pelvis-only scale / A3 static-cache leak; weather-visuals W1 4K pano per
build / W2 sky leak / W3 mobile-ungated rain; weather-profile P1 JSON
re-parse per lookup / P2 unconditional volumetric+SSIL+SSR-48 / P3 fog-energy
24× / P4 glow loop; mobile M1 per-query tree lookup / M2 desktop scaler
stomp / M3 glow-cap order; VFX V1 alarm 4.5→5.4 strobe + fade-tween fight /
V2 ward wash over caps / V3 unclamped wisp + infinite tween / V4 per-step
allocation storm / V5 `ttl=0` never-free / V6 per-texel mask loop; audio U1
`MAX_VOICES` silent drop / U2 `fire_event` bypasses trims / U3 scene-unsafe
await timers / U4 bed OGG duplicate-to-loop; game-data G1 tutorial→
`jaspering_hall` + `"example"` catch-all / G2 unknown-map inherits FTUE
unlimited / G3 `parts[1]` filename parse / G4 invented
`MatchDurationsByDifficulty[1/2]` keys / G5 raw-PNG icon check; game-state
S1 dual completion sources / S2 set-counter over-increment + stale
`loot_needed`; net N1 optimistic `is_coop` / N2 spawn-before-handshake;
save C1 deduct-before-validate / C2 blind merge + silent write failure;
light-probe H1 unoccluded directionals / H2 unreachable darkness /
H3 layer-1-only mask + 0.9 m offset / H4 single-slot multi-sampler cache.

**Gameplay (14 groups):** pickpocket free/silent on alert victims; ALERTED
outruns COMBAT (`chase_speed` unscaled); in-combat 15/s regen heals 0→full in
~2 s; dead `hearing_range` (radius = emitter loudness); sight rays ignore
bodies (mask 1); retention snaps 20→30 m and drops the light gate; disguise
hard-gate vs still-running drain; sprint ×8 dwarfs light/crouch; KO wake
searches own feet; ally-revive first-in-group + escalation strand; door/lock
noise sourced `self` so HUD arcs never flash; clue re-fires toast+noise per
press; contract→mission positional link + dead `mission_selected` /
`objective_completed` signals + fail/timeout persist nothing + timer runs
during letter/minigame + smoke visual/gameplay desync + Jaspering Hall
unpreviewable + flat Novice→Thief guard count; thief-side batch (crank on
wall-climb, no astral cleanup, tap-fire hop, mantle skipping
regen/drain/probe/hold, fairy recheck on moved pos, smoke charge-before-spawn,
sap instant-30 m, crank 0.5 s refund, fall immunity chains, `tool_used` gaps,
viewcone call-order guard).

**UI (4):** ledger prices are placeholders (must not ship as parity);
`settings_ui.gd:14-18,340-345` duplicates the design system (local `TEAL_*`
+ tab styler + group card — reproduced this turn); `mobile_touch_ui.gd`
bypasses theme entirely (0 token refs); `main_menu.gd:344-345,421-422`
menu/journal chrome inline.

**Pipeline (9):** `Packages()` TAT/-only gate + single-pak mount (dangling
`WorldGridMaterial` bind is proof); `Tables()` 9-root allowlist; material
Tier-2/3 albedo guesses unmarked (no `fallback_tier`); GLB-missing sidecar
fallback unmarked + degenerate-primitive slot hiding; quest-fallback
invariant is prose not `SystemExit`; hardcoded
`alerted_combat_fallback_m_s = 2.5`; spawner approximations untested +
`assert` vanishes under `-O`; `manifest_audit` gates mount not pipeline
(`dumped` printed-not-gated, `errors.log` unread, no freshness check); test
blind spots (audio audibility, save round-trip, guard transitions, VFX look,
15/18 contracts uninstantiated, mobile/export, GLB-for-every-`mesh_res`).

## 4. P2 backlog (condensed)

**Core (10):** D1 `FP_BLEND` unread; D2 `bone_report`/`has_fp_role` no
callers; D3 triplicated AU4 headers; D4 bypassed volume trims; D5
`contracts_source_table` write-only; D6 `_sample_calls` telemetry; D7
`noise_bus` comment-only contract; D8 unchecked bus-0/`dir.rename`;
D9 triplicated `_aim_node`; D10 `set_tier` silent no-op + static leak.

**Gameplay (12 groups):** rain on result screens; table highlights wrong
row; timeout reason recomputed; gaze bypasses `set_den_selected_map`;
escape not floor-grounded; wardrobe cursor asymmetry; `is_hub`
order-vs-map_id split; `"lock"` tag audio-less; swinging relock downgrades
to Lv1; container 1-6 vs jam 1-4; `loot_item` prompt fallback; thief/GC
hygiene batch (preview raycasts in `_process`, per-tick signal spam,
two-clock hold, no-hysteresis sprint, downed/grapple invariant, no revive
signal, dual vision vars, anim fallback asymmetry, `TPTakedownPlayer`
never stopped, inverted `_end_astral` guard, `players.back()`, runtime
GDScript compile, SEARCH pan vs `look_at`, civilian guard-table coupling,
bucket-hash duplication, wall-clock light cache, dynamic fail radius,
mid-air bottle failsafe).

**UI (9):** missing pink/green tokens (HARD_LIMIT 5.7 pass); HUD legacy
`hotbar_lbl` + `lockpick_bar` still driven while invisible; loading `_bar`
permanently hidden; confirm modal omits F key; splash missing for
non-Manor/Guildhall maps; prep countdown comment overpromises; smallest-text
audit (11 px badges → 10 px mobile floor; secondary prompt to ≥13–14);
wardrobe dual live 3D previews + dead `_panel_style`; redundant prep
header/controls text.

**Pipeline (7):** `Levels()`/`Anims()`/`Audio()` mixed-domain predicates +
uncounted `continue`s; empty-map → `thieves_den` default masks future gaps;
`Value<=1` spawn-pool exclusion by value not key; closed 5-class container
dict; `GRAPH_HEAVY` constants + undecoded Niagara graphs; wall-clock test
margins (0.55 s door, 0.15 s vs 80 ms probe window) + shared-autoload
ordering without fixtures; symlink/`.import` staleness + no reimport/freshness
manifest.

## 5. Non-findings (checked, healthy — do not re-litigate)

- **Stealth core is sound:** `light_probe.gd` throttling (~12.5 Hz), 0.75 m
  position cache, squared-distance early-outs, per-range reject before
  raycast are correct; `noise_bus.gd` (26 lines) is the right seam — pure
  relay, spatial logic consistently `distance <= loudness` in listeners.
  Light-gem chain (sample → `GameState.player_light_visibility` → guard
  `max(sampled, movement floor)` → `light_intensity_range_multiplier`
  0.15–1.0 → HUD lerp) is coherent end to end.
- **Save write path is clean:** atomic tmp-rename, XP `maxi(100, score/2)`,
  level re-derived from the authored curve, `_ensure_defaults` backfill,
  clamp discipline. (Gaps are read-path/persist-scope, listed as P1.)
- **Mission topology is complete:** victory only via escape gate,
  failure via downed/timer; Den has no timer/escape by construction;
  spawner type-guards, mesh-empty guards, modulo zero-division guard, and
  typed-vs-legacy loot fallback (no double-spawn) all verified.
- **Contract table is the theme reference:** 28 token refs, no pink/green
  leakage; use it as the pattern for the settings/mobile/menu passes.
- **HUD custom-draw is appropriate:** 112 inline colors are gameplay
  presentation (orb/reticle/pips/markers), not theme bypasses; overlay
  chrome routes through ThemeScript (40 refs); `VERSION_STRING` KF30 footer
  correct.
- **`parse_gameplay.py` fails closed** (every missing source raises `Fail`;
  single hardcoded combat-speed exception is P1-6); **`parse_loot.py`
  buckets fail closed** (`SystemExit` on missing bucket/mesh);
  **`parse_spawners.py` meshes fail closed** (modulo the `-O` note, P1-7).
- **Test suite is a real regression net:** every prior incident class has a
  pinned numeric assertion (door/swing counts, PeripheryA, CarUnderpass,
  discard-holes, light ratios, moon/cloud constants); frame-cap waits are
  the correct subscribe-then-await pattern and fail closed, not flaky-green.
- **Standing HARD_LIMIT items stay as-is:** unrecovered portrait art,
  missing tool meshes, outfit thumbnails, KF card copy, invented-price
  prohibition (prices listed P1, not to be "fixed" by invention), single
  loading art, port-authored staging numbers. No action.

## 6. Dropped / unreproducible claims

**Count: 0.** All 10 spot-checks reproduced on re-read; no lane claim was
dropped and no file:line was corrected. (Minor: lane line numbers drift by
±2 lines against HEAD in `audio_manager.gd` (`:482` → `:478`) and
`game_state.gd` — spans identical, anchor only.)
