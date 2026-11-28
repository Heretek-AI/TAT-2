# T11-AI — guard and civilian AI remediation

Team: **T11-AI** (`guard_ai.gd`, `civilian_npc.gd`, `hearing_data.gd`,
`noise_bus.gd`, AI-facing `light_probe.gd`, new `game/src/ai/*`).
Worktree `<worktree>/T11-ai`, branch `rem/T11-ai`, base
`fb93f84`. No push, no merge, no rebase, no write to the main checkout.

Programme rule followed: every finding has S1–S6 with a command and its output,
or an explicit `BLOCKED-ON <team>` / `NOT REPRODUCED`. The extract and the
generated data are shared read-only; this wave regenerated nothing.

---

## RE-I-02 — five authored sight fields never extracted; the 3.5 m rear bypass makes the blackjack unwinnable
- **severity:** P1
- **S1 investigate:** `game/src/ai/guard_ai.gd:1479` (`fb93f84`):
  ```gdscript
  if angle > fov_deg * 0.5 and dist > 3.5:
      return false
  ```
  The cone is bypassed for every target inside **3.5 m**; the authored
  `MinimumSightRadius` is **100 cm**, so the bypass is 3.5×. Inside that window
  the authored ramp is `100 / (0.4 · dist)`: at the 2.4 m blackjack reach
  (`thief_character.gd:2733`) it is **104.2 pts/s**, reaching ALERTED (45) in
  **0.432 s** against a **0.45 s** hold (`HOLD_INTERACT_SEC`,
  `thief_character.gd:144`) and setting `GameState.ever_spotted`
  (`guard_ai.gd:1265-1268`) → GHOST forfeited. `tools/parse_gameplay.py:320-336`
  reads only `SightRadius`, `LoseSightRadius`, `PeripheralVisionAngleDegrees`;
  the other five fields never reach `guard_ai.json`.
- **S2 research:** `extracted/json/AI/Controllers/AIC_GuardBase.json`
  subobject 29 `TATAISenseConfig_Sight_0`, `_EscalationStateToSettings[1].Value`
  (Fresh/Mindful/Vigilant) = `2000 / 2500 / 40 / MinimumSightRadius 100 /
  PointOfViewBackwardOffset 120 / NearClippingRadius 150 / FrustumAspectRatio
  2.0 / FrustumPitch -22`; row 0 (Drowsy) = `3000 / 3500 / 60 / 100 / 50 / 50 /
  2.0 / -22`. `AIC_Bouncer` = `2500 / 3000 / 40 / 100 / 50 / 50 / 1.2 / -21`
  (all three rows), `AIC_Hauntstable` = `3000 / 3500 / 40 / 120 / 150 / 2.0 /
  -22` (Bouncer values are **not** Hauntstable's), `AIC_Civilian` = four rows
  (`1000/1500/10/-10`, `1500/2000/50/-20`, `2000/2500/50/-2`,
  `2500/3000/60/0`). Authored `MaxAge` 10 s sits on the same component.
- **S3 confirm (red):** `game/tests/probe_blackjack_race.gd` on the pre-fix tree
  (`git stash push -- game/src`, probe untracked, one headless run):
  ```
  [phase A] pose: dist=2.20 m angle=90.6 deg fov=80.0
  [phase A] inhabited 3.5 m bypass -> seen=true (ramp 113.6 pts/s, ALERTED at 0.396 s vs hold 0.45 s)
  [phase A] authored frustum    -> seen=true
  [phase A] FAIL: a rear approach inside the blackjack reach is still seen by the authored frustum
  [phase B] prompt=
  [phase B] held=0.467 s seen_during_hold=true det=61.25 ko=false ever_spotted=true takedowns=0
  [phase B] FAIL: guard saw the thief during the hold
  [phase B] FAIL: takedown did not knock the guard out
  [phase B] FAIL: ever_spotted was set by the takedown
  [phase B] FAIL: detection ramp ran during the hold (61.2469700064969)
  BLACKJACK_PROBE FAIL fails=5
  ```
  Note the empty prompt: the guard *turned to face* the player, so the takedown
  prompt itself was already gone — the defect is bigger than "the hold loses".
- **S4 fix:** new `game/src/ai/sight_model.gd` owns the authored model:
  `MinimumSightRadius` as the only cone-free radius, the POV backward offset as
  the perception eye, `NearClippingRadius` as the frustum near plane,
  `FrustumAspectRatio` as horizontal/vertical (`vertical half =
  atan(tan(horizontal half)/aspect)`), `FrustumPitch` as the view elevation
  centre. `guard_ai._can_see_player` (`:1728`) replaces the 3.5 m test with
  `SightModel.frustum_admits(...)`; the occlusion ray still leaves the model
  head so a POV pushed into a wall cannot blind a guard. The data half is a
  documented contract on `guard_ai.json.escalation_tables.<profile>.<row>`
  (`minimum_sight_radius_m`, `point_of_view_backward_offset_m`,
  `near_clipping_radius_m`, `frustum_aspect_ratio`, `frustum_pitch_deg`, plus
  the `hauntstable` and `civilian` profiles the producer never builds). Until
  T01 emits them, `AUTHORED_FALLBACK` carries the exact asset values.
- **S5 test:** `probe_blackjack_race.gd` (new), suite `91a` (all eight fields ×
  four rows compared to the raw asset), `91b` (frustum matrix incl. balcony and
  point blank), `91d` (live hold), `55c` live block (physics running; the old
  block froze every actor and called `_try_blackjack` directly).
- **S6 confirm (green):**
  ```
  [phase A] authored frustum    -> seen=false
  [phase A] PASS: rear approach outside the authored frustum
  [phase B] prompt=[F] [HOLD] TAKEDOWN
  [phase B] held=0.467 s seen_during_hold=false det=0.00 ko=true ever_spotted=false takedowns=1
  [phase B] PASS: authored 0.45 s hold inside the 2.2 m reach knocks out an unaware guard without ever_spotted
  BLACKJACK_PROBE PASS fails=0
  ```
  Gate lines: compile 127/0; `make test` `SUMMARY: fails=0` (279 PASS);
  `test_m2_player` `M2_SUMMARY: fails=0`; `test_hearing_ranges`
  `HEARING_RANGES_SUMMARY: fails=0` (39); E2E `fails=0 passed=278 total=278`.
- **verdict:** **FIXED** (runtime consumer + behavioural test). Data half
  **BLOCKED-ON T01** (`tools/parse_gameplay.py:sight_table()` must emit the five
  keys and the two extra profiles; `test_ai` 91a turns red if a fallback value
  drifts from the asset).

- **Brief correction — the 0.15 light floor is authored, not invented.** The
  brief lists "a 0.15 light floor" alongside the 3.5 m bypass. Verified against
  `extracted/json/AI/Data/C_LightIntensityToRangeMultiplier.json`:
  `Time 0.0 → Value 0.15` (`RCIM_Cubic`) and `Time 1.0 → Value 1.0`
  (`RCIM_Linear`), i.e. `light_probe.light_intensity_range_multiplier` is 1:1
  and **was not changed**. What made the blackjack unwinnable was the
  interaction: the bypass treated the whole 2.4 m reach as visible, so the
  light-scaled range never mattered. With the authored 1.0 m minimum radius the
  floor is inert at every authored row (0.15 × 20 m = 3.0 m > 1.0 m) and the
  cone excludes a rear approach, so the fix is the bypass alone.

### Before/after — the blackjack race (same pose, same 0.45 s hold, 2.2 m rear)

| measurement | before (`fb93f84`) | after |
|---|---|---|
| takedown prompt at 2.2 m behind | `""` (guard turned to face) | `[F] [HOLD] TAKEDOWN` |
| guard sees the thief during the hold | **true** | **false** |
| detection meter at release | **61.25** | **0.00** |
| guard knocked out | false | **true** |
| `GameState.ever_spotted` | **true** (GHOST forfeited) | false |
| `GameState.takedowns` | 0 | 1 |
| probe failures | 5 | 0 |

Modelled race at the reach edge: detection 100/(0.4·2.4) = **104.2 pts/s** →
ALERTED at **0.432 s** vs the **0.45 s** hold, i.e. the old gate lost by
**18 ms** at exactly 2.4 m and by ~10× that margin closer in (inside the 2.0 m
critical range the ramp returns `INF` and the guard goes straight to COMBAT).

---

## RE-I-11 — guard combat is authored ranged; the port was a 1 m melee
- **severity:** P1
- **S1 investigate:** `guard_ai.gd:1349-1357` (`fb93f84`) damages the player
  only inside `MELEE_RADIUS 1.0`; `player_tools.json.guard_melee.far_damage`
  (2.0) was extracted and unread (`rg -n "far_damage|accuracy|shock"
  game/src/ai` → no hits).
- **S2 research:** `CT_Melee_RangedAttackDamage` row `Damage`: linear keys
  `(0 cm, 10.0)` → `(2000 cm, 2.0)`, `RCCE_Constant` at both infinities.
  `GA_MeleeRangedAttack` CDO: `DamageAmount` wires that row,
  `DamageType = DamageType.Shock`, `EffectToApplyOnHit =
  GE_Melee_RangedAttack_Shock`, `DamageRadius 100 cm`, `NumberOfShots 1`,
  `DelayBeforeFirstShot 0.1`, `DelayBetweenShots 1.5`,
  `DelayAfterAttackAnimation 0.75`, `LineOfSightTraceProfile = AOE`.
  `GE_Melee_RangedAttack_Cooldown` 2.0 s. `GE_Melee_RangedAttack_AccuracyStack`
  10.0 s, `AggregateBySource`, `StackLimitCount 3`.
  `GE_Melee_RangedAttack_Shock` 3.0 s, `DamageReductionMultiplier`
  Multiplicitive ×1.1, HUD icon `S_HUD_Icon_shock`.
  `EQS_FindRangedAttackLocation`: grid 1500/250 cm around the target, distance
  test **200–1000 cm**, visibility trace at 50 cm → the authored firing
  position is 2–10 m with LOS. `DT_ReactionEvents.Combat`: default role
  `AI.Behavior.Role.Combat.RangedAttack`, one `…Combat.Chaser` (max 1, grace
  5 s). `ST_Subtree_Combat` names the branch "Handle Ranged Attacks and Melee
  up close".
- **S3 confirm (red, code path):** the pre-fix COMBAT branch is a single
  distance gate at 1 m (`git show fb93f84:game/src/ai/guard_ai.gd` lines
  1349-1357) and the curve's far key has no reader. A guard at 8 m with clear
  LOS therefore deals **0** damage — reproduced by the new live case in 91i,
  which cannot pass against that branch (there is no ranged code path to
  invoke).
- **S4 fix:** `game/src/ai/ranged_attack.gd` (curve, 20 m extent, 2 s cooldown,
  1 m splash radius, 2–10 m band, accuracy stack bookkeeping, shock contract);
  `guard_ai._service_combat` / `_fire_ranged_at` (`:1523`, `:1572`) replace the
  melee-only branch. Everyone is `Ranged` by default and melees inside 1 m;
  `ReactionRoles.claim_combat` grants the single `Chaser` only when a guard is
  already inside the band minimum, so the first guard to see you at 8 m does
  not charge. `take_knockout` now raises alertness on a *surviving* hit
  (`React to Damage`, RE-I-08) and emits the authored `Combat.Hit` stim.
- **S5 test:** suite 91i — curve values (10/6/2/2 at 0/10/20/35 m), `deliver`
  at 10 m (damage 6, shock 3 s), the chaser/ranged pair, and a **live** COMBAT
  guard at 8 m whose target takes the curve value.
- **S6 confirm:** `PASS: 91 W8 AI (...) ranged curve ...`; `make test`
  `fails=0`.
- **verdict:** **FIXED** for the curve, range, cooldown, role pair and shock
  *contract*. `RandomizationBasedOnAccuracyStack` is a
  `MapProperty<int, Vector>` on the ability CDO with **no serialised keys**, so
  no per-stack jitter value exists in the dump: the port tracks the authored
  stack count/window/limit and applies no jitter
  (`accuracy_randomization_available() = false`). Victim-side shock needs the
  `DamageReductionMultiplier` attribute (OSECore) and a player status effect —
  **BLOCKED-ON T04** (`apply_shock(seconds, multiplier)` is called when the
  method exists; the HUD icon name is carried for T05).

---

## RE-I-10 / RE-I-06 — no navigation at all; patrol/chase/investigation are straight lines
- **severity:** P1 (nav) / P2 (path coverage)
- **S1 investigate:** `rg -n "NavigationRegion3D|NavigationAgent3D|map_get_path"
  game/src` → **0 hits**; `guard_ai._move_ai` steers `target - position` into
  `move_and_slide`. 113 of 173 multi-point paths turn more than 30°
  (lane count).
- **S2 research:** every `AIC_*` ships a `TATPathFollowingComponent`, three
  `NavArea_*` and four `GA_NavLink_*` behaviours; a navmesh per map. Baking is
  T09's (level_loader geometry).
- **S3 confirm (red):** the grep above is the proof: no navigation node exists
  in `game/src` before this commit.
- **S4 fix:** `game/src/ai/nav_steering.gd` — a `NavigationAgent3D` consumer
  with an explicit three-state contract (`unknown` / `ready` / `no_map`).
  `map_ready()` requires a synced map **and at least one navigation region**
  (Godot's default map syncs with zero regions, so iteration id alone is not
  evidence). On `no_map` it returns the straight-line vector, counts
  `degraded_frames()` and warns **once per process**. The agent is created
  lazily, so a map-less session never instantiates one. Used by
  `guard_ai._move_ai` and `civilian_npc`.
- **S5 test:** suite 91k — no baked map ⇒ `state == no_map`,
  `degraded_frames ≥ 1`, global counter moves, steering equals the straight
  vector.
- **S6 confirm:** `PASS: 91 W8 AI (... nav degradation)`; the live Guildhall
  run (`probe_leak.gd`) shows the single warning from
  `nav_steering._note_degraded`, which is the intended explicit degradation.
- **verdict:** **FIXED** (consumer). Navmesh **baking is BLOCKED-ON T09**; until
  it lands every guard takes the documented straight-line fallback. Remaining
  RE-I-06 gaps not taken this wave: `loop_type` `""` treated as wrap (104/210
  paths, no class default in the dump), `wait_deviation` still dropped, ≤8
  paths used per map (spawn budget, T10).

---

## RE-I-07 — seven guard spawn buckets unparsed; Bouncer row and HA_CLIPS unreachable
- **severity:** P2
- **S1 investigate:** `tools/parse_spawners.py:30-35` `BUCKET_KIND` covers four
  map buckets; the seven guard buckets produce no `buckets[]` entry.
  `mission_controller.gd:3543-3547` picks the lantern by `idx % 2`;
  `guard_ai.escalation_profile()` (`fb93f84:338-342`) keyed the Bouncer row off
  a node name (`bouncer`/`haunt`) **no spawner writes**, so the 25/30/40/aspect
  1.2 row and `HA_CLIPS` were dead in normal play, and Hauntstable guards got
  the Bouncer row instead of their own 30/35/40.
- **S2 research:** the seven buckets in
  `extracted/json/Missions/Spawners/Buckets/`:
  `KeyHolder → BP_GuardSecurity_KeyHolder_C`;
  `Hauntstable → BP_Hauntstable_C`;
  `PrivateSecurity → BP_GuardSecurity_Club_C`;
  `PrivateSecurity_Lanterns → BP_GuardSecurity_ClubLantern_C`;
  `StandardGuards_Bouncers → BP_GuardEnforcer_Club_C / ClubB_C`;
  `StandardGuards_Lanterns → BP_GuardEnforcer_ClubLantern_C / LanternB_C`;
  `…JasperingHall_Lantern → BP_GuardSecurity_JasperingHall_ClubLantern_C / B_C`.
  `DA_AIStatesToSpeed_Hauntstable` authors one Neutral row at **75 cm/s**.
- **S3 confirm (red):** `rg -n "Hauntstable|Bouncer" game/src` → only
  `guard_ai`'s own name heuristic; `python3` over the seven bucket JSONs lists
  classes that appear in no producer output (`spawners.json` has 8 buckets, none
  of them a guard bucket).
- **S4 fix:** `game/src/ai/guard_roster.gd` — the seven buckets as a documented
  contract (`AUTHORED_BUCKETS`), a read of `spawners.json.guard_buckets` when
  the producer emits it (JSON wins), and a `roster_bucket` export on the guard.
  `escalation_profile()`, `_guard_weapon_set()`, `_resolve_guard_glb_path()`,
  `carries_lantern`, `patrol_speed` and the spawn-time carried key now follow
  the bucket; an unbound spawn keeps the old behaviour and reports
  `roster_source() == "unbound"`.
- **S5 test:** suite 91g (all seven buckets resolve, Enforcer-Club → bouncer,
  Hauntstable → its own 30 m row + `hauntstable` clip set, KeyHolder carries
  `key_guildhall`), 91h (KeyHolder profile through a live node).
- **S6 confirm:** `PASS: 91 W8 AI (... roster buckets ...)`; `make test`
  `fails=0`.
- **verdict:** **PARTIAL — FIXED** for the AI consumer; **BLOCKED-ON T01** for
  `spawners.json.guard_buckets` and **BLOCKED-ON T10** for spawning the bucket
  class per marker (`mission_controller._spawn_guards`; the marker→bucket
  binding lives on the level actor's `TATSpawnerComponent`, i.e. T09's level
  producer must carry it). Until both land, `roster_source()` stays `unbound`
  and every guard keeps today's Enforcer body and index-based lantern/key.

---

## RE-I-12 — reaction caps and vision stimuli absent
- **severity:** P2
- **S1 investigate:** `guard_ai._hear` (`fb93f84:1519-1597`) is a broadcast:
  every guard in radius promotes `NEUTRAL → SUSPICIOUS` and walks to the
  stimulus; no role, no cap, no standby, no grace. `rg -n
  "GuardDowned|DetectedPlayer|DisguiseWorn" game/src` → no hits.
- **S2 research:** `DT_ReactionEvents` (8 rows): `HeavyStim` default `Standby`,
  `Investigator` max **2** with **0.5 s** registration grace; the four light
  stimulus rows max 2 with grace 0; `Phonograph` Investigator max **0**;
  `Combat` default `RangedAttack` + one `Chaser` (grace 5 s);
  `SawIncorrectObject` one `Fixer`. `DT_StimProperties` (8 rows) includes
  **`GuardDowned` Heavy**.
- **S3 confirm (red):** the broadcast is a single loop over the emitted signal
  (`rg -c "noise_record_emitted.connect"` → one per guard) with no registry,
  no cap and no role: every listener in radius reaches
  `if state == Alertness.NEUTRAL: _set_state(Alertness.SUSPICIOUS)`
  (`fb93f84:1595-1597`). The red proof is the code path; suite 91e now measures
  the fixed behaviour (4 listeners → 2 investigators + 2 standby).
- **S4 fix:** `game/src/ai/reaction_roles.gd` (investigator cap/grace per
  severity, Phonograph 0, one Chaser, deterministic arrival order — the EQS
  scoring query is not recoverable, so no invented score); `NoiseBus` stamps a
  monotonic `event_id` on every record so listeners agree on "the same sound";
  `guard_ai._hear` claims a role and **standby listeners keep the memory but do
  not walk**; `guard_ai._scan_downed_guards` (`:1612`) notices a
  `guard_bodies` body through the authored sight geometry (throttled 0.5 s),
  raises witnesses and sends at most two to the body.
- **S5 test:** suite 91e (one heavy stimulus, four guards, exactly 2
  investigators + 2 standby, registry count 2) and 91f (a knocked-out guard is
  noticed by a witness at 5 m, investigate target is the body).
- **S6 confirm:** `PASS: 91 W8 AI (... investigator cap, GuardDowned ...)`;
  `make test` `fails=0`.
- **verdict:** **FIXED** for caps, standby, the combat pair and `GuardDowned`.
  Not implemented: EQS reaction scoring, `SawIncorrectObject` Fixer, smart-object
  claims (they belong with the StateTree consumer, RE-I-01, still BLOCKED).

---

## RE-I-05 — hearing: 8 of 54 rows reachable, walls do not block
- **severity:** P1 (occlusion) / P2 (reachability)
- **S1 investigate:** `guard_ai._hear` never raycast; `HearingData.acoustic_portals()`
  had no runtime caller (`rg -n "acoustic_portal" game/src` → the accessor
  only). `PORT_TAG_TO_STIM` mapped 7 tags + the gait split = 8 authored rows.
- **S2 research:** all 54 `DT_HearingStimProperties` rows declare
  `PropogateThroughOpenPortals`; 285 `BP_TATAcousticPortal` boxes exist with
  Godot transforms in `hearing.json.acoustic_portals` (100 cm cube × authored
  instance scale). **No attenuation value is recoverable** (no `AkAttenuation`
  asset, no wall-penalty field), so only a binary wall/portal rule is defensible.
- **S3 confirm (red):** `hearing_data.reachable_stim_tags(<pre-fix tag set>)`
  = **8**; and `_hear` had no raycast at all (`rg -n acoustic_portal game/src`
  → the accessor only), so a wall could not block any stimulus — a code-path
  proof, no runtime measurement available without reverting.
- **S4 fix:** `game/src/ai/hearing_occlusion.gd` — one segment test
  (listener eye → source chest, world layer 1): blocked unless the crossing
  point lies inside an authored portal OBB **and** no closed `swinging_doors`
  door is within 1.6 m of it. Fail-open on a missing physics space, counted.
  Three authored rows gain emitters from files this team owns:
  `combat_hit → Combat.Hit` (10 m, non-lethal hits only — a blackjack one-shot
  is the `Takedown` row, not `Combat.Hit`), `npc_yelp → NPC.Yelp` (25 m),
  `npc_call_help → NPC.CallForHelp` (30 m).
- **S5 test:** suite 91j — reachable rows = **11** (`stim_count` 54, reachable +
  unreachable partition 54), open-floor stimulus heard, the same stimulus
  behind a wall not heard and `blocks` incremented, portal registry 285.
- **S6 confirm:** `PASS: 91 W8 AI (... hearing occlusion ...)`; `make test`
  `fails=0`; `test_hearing_ranges` 39 PASS unchanged.
- **verdict:** **PARTIAL — FIXED** for occlusion and 3 rows (**8 → 11 of 54**
  reachable, measured). The remaining **43 rows have no emitter in the port**
  (`GlassBreak`, `SecurityDevice.Alarm.Triggered`, `Player.SprintingPanting`,
  `Landed`, `Loot.TalkingLoot*`, `Coughing.*`, `Tool.*`, `Trap.*`…). They are
  data awaiting an emitter owner, not a wiring defect this team can close: the
  emitters live in `thief_character.gd` (T04/T10), `devices/*` and
  `interact/*` (T10). `docs/FIDELITY_GAPS.md:498`'s "all 54 wired" is corrected
  below.

---

## RE-I-09 — civilians: 73-state tree, own senses, 40 HP vs a wander loop
- **severity:** P2
- **S1 investigate:** `civilian_npc.gd` (324 lines) never referenced the
  player, guards, noise or health (`rg -n "player|guards" civilian_npc.gd` →
  comments only); header said "no detection and no interaction". Civilians also
  occupied layer 8, and the guard sight ray mask included layer 8, so a
  civilian could silently make a guard blind.
- **S2 research:** `AIC_Civilian` sight rows (above); `CT_AIStats`
  `CivilianBaseHealth 40`, `CivilianKnockoutDuration 60 s`, regen 5;
  `ST_Civilian` 73 states with React to Intruder → Flee → Cower,
  `ST_TriggerFlee_Civilian` (17) and `ST_Subtree_Flee` (32); VO
  `VOLC_Fleeing_ObservedThief_CallForHelp`.
- **S3 confirm (red):** the greps above; suite 91l asserts a visible thief now
  triggers `flee`, a yelp and a 40-damage knockout — none of which existed.
- **S4 fix:** `civilian_npc.gd` gains the authored 40 HP / 60 s KO / 5 HP/s
  regen, its own `AIC_Civilian` sight row through `SightModel`, a
  `WANDER → FLEE → COWER → WANDER` cycle with the authored `NPC.Yelp` on sight
  and `NPC.CallForHelp` once while fleeing, heavy-stimulus hearing, and
  `NavSteering`. The guard sight ray mask drops layer 8 (civilians are
  detectable actors, not cover).
- **S5 test:** suite 91l (visible thief ⇒ flee + yelp; 40 damage ⇒ downed).
- **S6 confirm:** `PASS: 91 W8 AI`; `make test fails=0`; suite 55d (civilian
  capsule) unchanged and green.
- **verdict:** **PARTIAL — FIXED** for senses, flee/yelp/help, HP/KO and the
  cover bug. **NOT IMPLEMENTED, labelled:** clue giving (`ST_ClueGiving`), the
  `EQS_FindCivilianCowerPoint` search, civ VO lines, and
  `DA_DetectionSettings_Civilian`'s staged ramp (0.25–0.45 s/m, critical
  2–15 m, weapon multiplier 1.125–1.5) — the port uses one authored sight gate,
  not a detection meter. Those need a producer for the civilian detection
  settings (T01) plus a bigger state machine.

---

## RE-I-13 — the stolen key has no lock consumer
- **severity:** P1 (dead loop) / P2 (no takedown window)
- **S1 investigate:** `guard_ai.steal_carried_item` calls
  `GameState.add_stolen_key` (`:1975-1978` `fb93f84`); `rg -n
  "has_stolen_key" game/src` → declaration only (`game_state.gd:439`); the HUD
  key row is the only reader. `_key_pool_for_map` gives keys to
  `idx % 2 == 0 or idx == 1` guards by index.
- **S2 research:** `BP_GuardSecurity_KeyHolder` is a dedicated character class
  and `DA_SpawnBucket_KeyHolder` is a real spawn bucket; the map key names
  (`Guildhall Key`, `Elway Manor Key`) come from the text tables via the
  mission controller's key pool. The extracted interactable data carries no
  `RequiredItem`/`KeyItem` field (`_lockConfig` = `MaxLockLevel` + `_locked`),
  so the shipped key→lock binding is genuinely UNEXTRACTED.
- **S3 confirm (red):** `game_state.has_stolen_key` has zero call sites
  (`rg` above), and no guard ever carries a roster-authored key (the KeyHolder
  bucket never spawns).
- **S4 fix (AI half):** the roster gives the KeyHolder the map's authored key
  (`key_guildhall` / `key_manor`) at spawn; `steal_carried_item` is then the
  only path into `GameState.stolen_keys`, and the authored key *name* reaches
  the pickpocket prompt.
- **S5 test:** suite 91h — a live guard with `roster_bucket =
  BP_GuardSecurity_KeyHolder_C`, pickpocketed, grants
  `GameState.has_stolen_key("key_guildhall")`.
- **S6 confirm:** `PASS: 91 W8 AI (... roster buckets ...)`; `fails=0`.
- **verdict:** **PARTIAL — AI half FIXED; lock consumer BLOCKED-ON T10**
  (`game/src/interact/*` is T10's file set). Proposed patch, one place:
  ```gdscript
  # lockable_door.gd, in the locked branch of interact()/interact_hold()
  if locked and current_key_id() != "" and GameState.has_stolen_key(current_key_id()):
      locked = false
  ```
  with `current_key_id()` derived from the level actor's key tag once T09's
  level producer carries it. Until then the HUD row remains a promise (T05).

---

## RE-I-08 (partial) — `React to Damage`
- **severity:** P2
- **S1/S2:** `take_knockout` (`fb93f84:1613`) reduced HP with **no** alertness
  change; `ST_Guard` "React to Damage" is a real branch (and was missing from
  `tools/parse_state_tree.py` `PORT_COVERAGE`).
- **S3 confirm:** the function body is the proof (no `_set_state`); unreachable
  today because the only damage source is the lethal blackjack.
- **S4 fix:** a *surviving* hit now raises `investigate_pos`/detection to
  ALERTED and emits `Combat.Hit`; a lethal hit falls straight through to the KO.
- **S5/S6:** covered by 91i's live case and `make test fails=0`.
- **verdict:** **FIXED** (one branch). The other 12 branches (focus, lockdown,
  flee, clue giving, smart objects) remain **BLOCKED** on the StateTree
  consumer, which needs T01's `guard_behavior.json` flattening work and a
  design decision this wave does not own.

---

## RE-I-04 — detection ramps are a hardcoded mirror with no test
- **severity:** P3
- **S1:** `DETECTION_RAMPS` (`guard_ai.gd:79-84`) duplicates
  `detection.json`; suite 52 only checks the four keys exist.
- **S2:** `DA_DetectionSettings.RampSettings` values (200/0.0/0.4/1.0 ×4).
- **S3:** `rg -n "agnostic|DETECTION_RAMPS" game/tests/` → no value comparison.
- **S4:** no engine change (the values are correct); the const stays the runtime
  source, deliberately, so a data regeneration cannot silently change stealth
  mid-wave.
- **S5:** suite 91c compares every ramp row (`agnostic`, `critical_time`,
  `critical_range`, `crouch_min`, `crouch_mult`) to `detection.json`, failing on
  drift.
- **S6:** `PASS: 91 W8 AI`; `fails=0`.
- **verdict:** **FIXED** (the test blind spot).

---

## RE-I-14 — tests: 55c froze physics; no ramp/geometry/hold coverage
- **severity:** P2
- **S1:** `run_tests.gd:5505-5604` called `set_physics_process(false)` on every
  actor and invoked `_try_blackjack` directly.
- **S3 (red):** with physics frozen the old 3.5 m bypass could not lose a race,
  so the suite passed while the mechanic was broken (probe: 5 failures).
- **S4/S5:** suite 55c keeps its geometry gates and gains a **live** 0.45 s hold
  block; new `game/tests/probe_blackjack_race.gd`; new suite 91 (a–l). No
  assertion was weakened or deleted — 55c only got stricter.
- **S6:** 55c `PASS ... live 0.45 s hold wins`; 91 PASS; 279 PASS total.
- **verdict:** **FIXED**.

---

## RE-I-15 — documented numbers that disagree with the data
- **severity:** P3 → doc corrections listed at the end. The 54-stims claim is now
  **measured** (11 of 54) instead of asserted; the patrol count 673 is already
  correct in `HANDOFF_NEXT_AGENT.md:57` / `FIDELITY_GAPS.md:34`.
- **verdict:** **FIXED IN REPORT** (integrator applies).

---

## RE-I-01 / RE-I-03 — not taken this wave
- **RE-I-01 StateTree consumer:** 784 KB `guard_behavior.json` still has zero
  consumers; the port keeps the FSM. **BLOCKED-ON T01** (a flattened,
  machine-readable behaviour record — the current per-tree dump is
  documentation, not an executable plan) plus a design decision on how much of
  the 459-state tree the port wants.
- **RE-I-03 alertness ladder:** the invented 15/45/100 rungs remain (documented
  as retained). Changing them changes every stealth timing at once and needs a
  playtest budget this wave does not have. **DEFERRED** with the mismatch
  recorded.
- **C4-08 (4/6/8 guards, file-order selection, no `guards=N` line):**
  `mission_controller._spawn_guards` is T10's file. Reproduced by the lane; not
  changed here. **BLOCKED-ON T10**. Note that the navmesh warning C4-08 quotes
  is unrelated and still only fires once (it is a wander-target validity check).
- **RE-A-13 (height-difference curve):** **NOT REPRODUCED.** The integrator's
  correction is confirmed from the raw asset: both keys are
  `Time 2.0 / Value 1.0 / RCIM_Constant` and `Time 3.0 / Value 0.0 /
  RCIM_Linear`, so the segment 2–3 m holds **1.0** and the port's step to 0.0
  at 3.0 m is faithful. No change was made to
  `height_difference_strength_multiplier`, and `eval_curve` is deliberately not
  used for it (it would lerp, i.e. introduce the bug the lane imagined).

---

## Team summary

| verdict | findings |
|---|---|
| **FIXED** | RE-I-02 runtime half, RE-I-04, RE-I-08 (React to Damage), RE-I-10 consumer, RE-I-11 curve/range/roles, RE-I-12 caps + GuardDowned, RE-I-14 |
| **PARTIAL (fixed part named)** | RE-I-05 (occlusion + 3 rows, 8→11/54), RE-I-07 (roster consumer), RE-I-09 (senses/flee/HP), RE-I-13 (key source) |
| **BLOCKED-ON T01** | RE-I-02 data (5 sight keys + 2 profiles), RE-I-07 data (`guard_buckets`), RE-I-11 accuracy jitter values, RE-I-09 civilian detection settings |
| **BLOCKED-ON T09** | navmesh baking (RE-I-10), marker→bucket level data (RE-I-07) |
| **BLOCKED-ON T10** | guard spawn class per bucket (RE-I-07/C4-08), key→lock consumer (RE-I-13) |
| **BLOCKED-ON T04** | victim-side shock attribute/status (RE-I-11) |
| **NOT REPRODUCED** | RE-A-13 |
| **DEFERRED** | RE-I-03 ladder, RE-I-01 StateTree consumer |

Gate set on the wave tip `0d98bb9` (serial, headless, no GPU):

| gate | result |
|---|---|
| `tools/godot … check_scripts_compile.gd` | `scripts checked: 127, broken: 0` |
| `make test` | `SUMMARY: fails=0` — **279 PASS** (was 278; +suite 91, 55c live block) |
| `test_m2_player.gd` | `M2_SUMMARY: fails=0` (11 PASS) |
| `test_hearing_ranges.gd` | `HEARING_RANGES_SUMMARY: fails=0` (39 PASS) |
| `tests/e2e/run_e2e_tests.gd` | `SUMMARY: fails=0 passed=278 total=278` |
| `tests/probe_blackjack_race.gd` | `BLACKJACK_PROBE PASS fails=0` |
| `build/qa/test_perf_guard.sh` | `PERF_GUARD_TEST PASS checks=78 fails=0` |
| `make gate-ratchet` | `GATE_RATCHET: PASS` |
| `make audit` | 13/13 content groups OK; **fails on tool-version drift**: `vgmstream: '…r2168 (Oct 25 2026)' -> 'missing'` — the CLI is not on `PATH` in this container. Proven **pre-existing**: `git stash push -- game/src game/tests build/qa` leaves the tree at `fb93f84`+`8607318` and the audit prints the identical single failure, so no T11 change causes it. The integrator must install the tool or re-stamp at the merged HEAD; **do not** re-baseline silently. |

Commits on `rem/T11-ai`: `8607318` holds **all** source and test changes; the
report itself is added and refined by doc-only commits on top (they touch
nothing but this file — `git log --oneline rem/T11-ai` is the authority).
The code is deliberately **one** commit: the findings share `guard_ai.gd` with
interleaved hunks, and any file-level split would leave an intermediate commit
that does not compile — AGENTS requires every commit to be green.

---

## Doc corrections (integrator applies; teams must not edit these files)

1. `docs/FIDELITY_GAPS.md:498` — replace "**all 54 authored hearing stims are
   wired**" with: "**54/54 authored rows load; 11 are reachable from the port's
   emitter tags** (measured by `run_tests` suite 91j: takedown, ImpactGeo,
   OpeningCreak, LockPicking.Picked, LockPicking.Jammed, Trap.NoiseAlarm,
   Combat.Hit, NPC.Yelp, NPC.CallForHelp, Footstep.Walking, Footstep.Running).
   The other 43 rows have no emitter — each needs an owner in
   `thief_character.gd`, `devices/` or `interact/`."
2. `docs/FIDELITY_GAPS.md:500` — "285 portals read-only" → "285 authored
   acoustic portals consumed by a **binary** rule (`hearing_occlusion.gd`):
   a segment that crosses world geometry is heard only through a portal box
   with no closed swinging door in it. No attenuation value is recoverable from
   the dump, so there is no dB/m penalty."
3. `docs/FIDELITY_GAPS.md:110` — the "3.5 m close-range bypass **retained**"
   line is no longer true: the bypass is replaced by the authored
   `MinimumSightRadius` **100 cm**, and the authored frustum
   (`FrustumPitch −22°`, aspect 2.0 ⇒ **−44.7…+0.7°** elevation) now gates
   above-horizon targets.
4. `docs/FIDELITY_GAPS.md` guard-combat section — "1 m melee, 10 damage" →
   "ranged: 10 dmg @ 0 m → 2 @ 20 m (`CT_Melee_RangedAttackDamage`), 2 s
   cooldown, firing position 2–10 m (`EQS_FindRangedAttackLocation`), one
   Chaser + everyone else Ranged (`DT_ReactionEvents.Combat`); the 1 m close
   engagement reuses the authored 100 cm `DamageRadius`."
5. `docs/FIDELITY_GAPS.md` civilians section — "no detection and no
   interaction" → "own `AIC_Civilian` sight row, 40 HP / 60 s KO, flee on sight
   with the authored `NPC.Yelp` (25 m) and one `NPC.CallForHelp` (30 m). Still
   absent: `ST_ClueGiving`, `EQS_FindCivilianCowerPoint`, civ VO lines and
   `DA_DetectionSettings_Civilian`'s staged ramp."
6. `docs/FIDELITY_GAPS.md:121` — the stale "Guard patrols: not recoverable"
   line contradicts `:34`; the accurate statement is "39 of 249 `BP_AIPatrolPath`
   actors author no points".
7. `AGENTS.md` §Known traps — add two lines: (a) "**No navigation map ⇒ one loud
   warning per process.** `game/src/ai/nav_steering.gd` degrades to
   straight-line steering and counts frames until T09 bakes a
   `NavigationRegion3D`; it is not an error." (b) "`--sight-frustum=off` and
   `guard.sight_frustum_enabled=false` disable **only** the authored vertical
   frustum gate (diagnostic); the horizontal cone and the authored 1.0 m
   minimum radius always apply."
8. `AGENTS.md` §Commands and gates — `tests/test_hearing_ranges.gd` (39 checks)
   is a real gate but is missing from the list; add it, and consider
   `tests/probe_blackjack_race.gd` (one headless run, ~2 s, exits non-zero on a
   broken takedown) next to `probe_leak.gd`.
9. `docs/reports/gameplay-truth-wave.md:33` — "patrols had no consumer" is
   stale (210 paths / 673 points are consumed since W7).
10. `docs/HANDOFF_NEXT_AGENT.md` — the AI status line should say:
    "Guard sight = authored 8-field geometry (5 fields still producer-blocked;
    constants equal the asset and are parity-tested); combat = authored ranged;
    reaction caps + `GuardDowned` live; hearing occlusion binary; guards/civilians
    use `NavigationAgent3D` when a map exists and degrade loudly otherwise;
    roster buckets resolve but are not yet spawned (T01 + T10)."

---

## Open risks

1. **The vertical frustum is a large gameplay change.** With `FrustumPitch −22°`
   and aspect 2.0 a guard's view stops at **+0.75°** elevation, so a player
   **0.6 m higher at 5 m** is invisible (near-clip exempts only < 1.5 m). That
   is the authored arithmetic (and the audit's claim (b)), and it makes
   balconies/rooftops real stealth space — but on stairs it can also make a
   guard lose a player one step up. Verify in a playtest; the per-guard
   `sight_frustum_enabled` flag isolates it without touching the cone.
2. **Stairs and ramps** are the realistic failure mode of (1): floor-height
   differences of 0.3–1 m inside the 5–10 m band flip the verdict. If playtests
   disagree, the honest lever is the authored pitch semantics (which are
   inferred: the struct is TAT's, not stock UE), not a clamp.
3. **Hearing is now binary and wall-blocking.** 273 of the 285 authored portals
   live in sublevels `devices_runtime.json` never expands, so portal *coverage*
   is unverified: a doorway without an authored box reads as a wall. Missions
   may feel deafer than shipped. There is no attenuation value to soften this
   with — the only defensible lever is portal coverage (T09).
4. **Body-notice range is not light-gated.** `_scan_downed_guards` uses
   `lose_sight_range` (25 m) without the light multiplier, so a guard in the
   dark notices a body at full range. There is no authored rule for a body's
   visibility; flagged rather than invented.
5. **Ranged combat balance is unmeasured.** A guard now deals 6–10 damage per
   2 s at 2–10 m instead of 10 per 2 s at 1 m; combined with 2–4 ranged guards
   per room this is a step change in lethality. Needs a difficulty pass (T10's
   spawn budget interacts).
6. **`ReactionRoles` is process-global** and is pruned lazily on hearing
   events. A mission reload does not clear it (`guard_ai.cleanup_static_caches`
   does not touch it), so event ids from a previous mission can only collide if
   the counter wraps — not reachable in practice, but the registry is not
   mission-scoped.
7. **Civilians panic in a loop** while the thief stays visible: yelp every
   ~14 s per civilian, each a 25 m heavy stimulus. With 5 civilians and 2
   investigators capped this is bounded, but it is a noise amplifier that no
   playtest has measured.
8. **`guard_ai.gd` is now ~2 500 lines** with two responsibilities. Splitting
   `_service_combat` / perception into components is the obvious follow-up; not
   done here to keep the diff reviewable.
9. **The producer contract is a contract, not data.** If T01 emits different key
   names than the five documented ones, sight silently falls back to constants
   and 91a keeps passing (it compares the *resolved* row to the asset). The
   producer must use the names in `sight_model.gd:CONTRACT_KEYS`.
10. **`make audit` is red for an environmental reason** (vgmstream CLI missing).
    No T11 finding can fix it; it must not be re-baselined silently.
