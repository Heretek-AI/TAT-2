# T04-ANIM — animation remediation

Worktree: `/home/john/Projects/TAT-2-rem-T04-anim`, branch `rem/T04-anim`.
Base: `38e7b03` (W7 merged tree + docs). Two local commits, **not pushed**:

| commit | scope |
|---|---|
| `5319bf6` | `tools/usd_to_gltf.py` + `tools/test_usd_to_gltf_duration.py` — authored clip durations (RE-F-04) |
| `4163632` | `anim_notify.gd` (new), `thief_character.gd`, `guard_ai.gd`, `tests/run_tests.gd`, `tests/test_m2_player.gd`, `tests/test_anim_gates.gd` (new) — hit windows, takedown pair/rig, per-clip run speed, traversal clip selection |

Environment note: `game/data/generated/`, `extracted/`, `game/assets/` are the
read-only symlinks. `tools/bin/` was symlinked from the main checkout (git-ignored
fetched binaries) so `make audit` reports only the producer-baseline line.

## Gate evidence (all headless, serial, on the committed tree)

| gate | result |
|---|---|
| `check_scripts_compile.gd` | `scripts checked: 122, broken: 0` (baseline 120 + `anim_notify.gd` + `test_anim_gates.gd`) |
| `make test` | `SUMMARY: fails=0` |
| `test_m2_player.gd` | `M2_SUMMARY: fails=0` (11 baseline + new **M2.10** = 12 checks) |
| `tests/test_anim_gates.gd` (new) | `ANIM_GATE_SUMMARY: fails=0` (14 assertions) |
| `run_e2e_tests.gd` (full) | `SUMMARY: fails=0 passed=278 total=278` |
| `python3 tools/test_usd_to_gltf_duration.py` | `Ran 9 tests … OK` |
| `make gate-ratchet` | `GATE_RATCHET: PASS` |
| `make audit` | **fails with exactly one line, by design**: `baseline: producer tools/usd_to_gltf.py changed since the baseline (sha256 5b5606018166 -> aa6191039691); regenerate with make anims … then run --refresh-stamps`. `make anims` / `--refresh-stamps` are the integrator's (see §"Integrator steps"). The earlier `tool version drift: vgmstream … missing` line was the worktree's missing git-ignored `tools/bin/`; after symlinking it, only the producer line remains. |

Regression check against the W7 floors: compile 122/0 vs 120/0 (new files only),
`run_tests` fails=0, M2 fails=0, E2E 278/278 — none below floor.

---

## RE-F-04 — every clip exports `(N−1)/N` of its authored duration
- **severity:** P1 (lane said P3; the cadence error compounds on every loop)
- **S1 investigate:** `tools/usd_to_gltf.py:100-105` (pre-fix) set
  `render.fps = round(tps)`, `fps_base = tps/round(tps)`, i.e. effective fps = `timeCodesPerSecond`.
  The USDA writer emits N samples at timecodes 0…N−1 with `tps = N/L`, and Blender's glTF
  exporter writes seconds as `frame/(fps*fps_base)`, so the GLB lasts `(N−1)/tps = (N−1)/N · L`.
- **S2 research:** `timeCodesPerSecond` is `N / SequenceLength`. Verified across all 995 headers:
  `startTimeCode = 0` everywhere, `N = end−start+1`, and `N/tps == anims_meta.length` for 982/995
  (the other 13 differ ≤0.1 % because tps is quantised to an integer). Blender source:
  `io_scene_gltf2/blender/exp/animation/keyframes.py:13` → `seconds = frame / (fps*fps_base)`.
- **S3 confirm (red):** read-only sweep over 995 USDA headers × 995 manifest entries:
  the legacy model `|dur − span/tps| / authored` holds to **5.6e-8** for 972/972 multi-key clips;
  signed residual median **−0.917 %**, mean −2.644 %, 441 clips > 1 % fast, 156 > 2 %, 38 > 5 %.
  Worst `AN_Zipwire_CastIdle_000` 0.008333 s vs authored 0.016667 s (**−50 %**); worst ≥0.5 s clip
  `MM_Unarmed_Jump_Apex` −4.762 %. `AN_Mantle_100CM` 0.9836 vs 1.0.
  Unit test red: `python3 tools/test_usd_to_gltf_duration.py` → 8 failures (helper absent; old
  formula pinned as short).
- **S4 fix:** new pure `read_usd_header()` + `compute_render_fps()`; `convert_one()` uses the
  imported action span: `L = (end−start+1)/tps`, `fps_eff = span/L`, written as `fps=round`,
  `fps_base=fps_eff/fps`. Zero-span single-pose/additive clips keep the legacy mapping (23 clips,
  duration 0 by construction). `write_manifest()` emits `"duration_mode": "authored"`.
- **S5 test:** `tools/test_usd_to_gltf_duration.py` (9 cases, stdlib) → `OK`;
  `py_compile` OK. Blender 5.3 headless A/B on four real clips (old script vs new, outputs in
  `/tmp/opencode/t04/glb/`): Mantle_100CM 0.983607 → **1.000000**; Club_Alert_Run_F 0.650406 →
  **0.666667**; Face_Exp_Anger 6.633499 → **6.666667**; Zipwire_CastIdle_000 0.008333 →
  **0.016667** — channel/key counts identical (501/61, 501/41, 501/201, 501/2).
- **S6 confirm (green):** all 972 multi-key clips re-timed from the headers: 962 within 0.1 % of
  `anims_meta.length`, median residual 4e-6 %, worst +1.64 % (`AN_PaperStack__Unequip_Montage`,
  header tps quantisation). Gate `test_anim_gates.gd` support: 995 clips checked — 186 already
  within 0.5 % authoring, **786 on the exact legacy model**, 23 zero-pose, **0 unexplained**.
  The gate refuses the legacy model once the manifest declares `duration_mode=authored`.
- **verdict:** **FIXED (producer)**. The 995 GLBs on disk remain legacy until the integrator runs
  `make anims`; the gate is written to accept that state exactly once and to fail afterwards if a
  clip is neither authored-length nor exactly legacy.

## RE-F-06 — 3,594 authored notifies extracted, exposed and never consumed
- **severity:** P2
- **S1/S2:** notify times are in `anims_meta.json`; `GuardAnimationLibrary.get_notifies/notify_at`
  are data-only (`rg -n "notify_at|get_notifies" game/src` → library only).
- **S3 confirm:** the club's played clip is `AN_GuardEnforcer_Club_Attack_Light_A_Montage`, which
  authors **no** `CombatHitbox` (only `CombatMontage` + 2 audio events); the 9 hitbox states live
  on the sibling sequence `AN_GuardEnforcer_Club_Attack_Light_A` at 0.920–1.170 s of 2.133 s.
  `guard_ai.gd` applied `MELEE_DAMAGE` in the same frame it called `_play_guard_attack()`.
- **S4 fix:** new `game/src/player/anim_notify.gd` (`AnimNotifyClock`): resolves a clip's windows
  of a notify class, falls back `_Montage → sequence`, clips them to the authored length, and
  returns each window once as the owner polls `AnimationPlayer.current_animation_position`
  (loop-aware). Used by `guard_ai._tick_attack_hit_window()` and the player's blackjack path.
- **S5/S6:** gate asserts the montage resolves 9 windows from the sequence, the contact instant is
  inside them, and the clock is silent at t=0 and 0.5 s. See RE-F-12.
- **verdict:** **PARTIAL** — hitbox windows (95 events) are now consumed. Footsteps (1,321),
  AkPlayerEvent VO/SFX (205), `ForceControllerRotation` (83), montage `TransitionToLocomotion`
  (45) and the 16 WorldInteractCamera states remain data-only: audio is T03's bus work, camera
  and locomotion transitions need T11/T10 hooks. The clock is the API they need
  (`windows_for(clip, class)`, `poll(pos)`).

## RE-F-07 — 235 montage sections / 214 slot declarations have no consumer
- **severity:** P2
- **S1:** `get_sections` is called only by `run_tests.gd:6581`; playback ignores sections and slots.
- **S3:** confirmed by the lane and unchanged here. The one montage the port plays whole is the
  guard attack (`DefaultSlot`, full body), so the current behaviour is not slot-wrong for it.
- **verdict:** **DEFERRED (T04 follow-up / T11)**. Section-based crank playback and an
  `UpperBody`/`UpperBodyOnlyWhenMoving` mask need a layered animation player; the clock from
  RE-F-06 is the prerequisite for the section timing and is now in place.

## RE-F-08 — 414 root-motion clips: translation kept, semantics unused
- **severity:** P2
- **S1/S2:** `STRIP_ROOT_TRANSLATION` covers only the 3 locomotion roles; everything else keeps the
  root track applied to the mesh's `root` bone, which slides the mesh inside the capsule.
- **S3:** not re-measured here; the lane's numbers (walk 349.5 cm/3.28 s, takedown Atk 148 cm) are
  reproduced by the frame-range/root checks above.
- **verdict:** **DEFERRED**, and it is now the **main open risk of the RE-F-11 fix**: both takedown
  halves are retargeted in place (root stripped), so the authored 148 cm closing travel is not
  applied and the two rigs can stand up to ~1.5 m apart during the grapple. The camera frames both
  bodies to keep it readable, but this is not the authored shared-space choreography. Fixing it
  needs a root-motion/motion-warping layer (T04 follow-up, with T09 for actor displacement).

## RE-F-09 — 92 of 995 clips wired; 903 orphans
- **severity:** P2
- **S1/S2/S3:** re-counted over the working tree (method in `## Orphan clip inventory`):
  **94 bound / 901 orphans (90.6 %)**, 765 unique orphan motions, **80 (8.0 %) playable in
  principle**. The lane's 92/85/903 is off by two: the 8 tables hold 88 distinct names (not 87),
  and two `CLIP_INTERNAL_EXACT` alias strings are real manifest clips
  (`AN_ThiefNisha_Zipwire__Reload`, `…_Gear_Zipwire_Reload`).
- **S4:** the bound set grows by the two traversal roles wired under RE-F-14, and the gate now
  asserts every role resolves to a shipped clip (so the set cannot silently shrink).
- **verdict:** **PARTIAL** — the prioritised inventory is delivered (below); binding the rest is
  design work (damage reactions, guard reactions, civilian panic), not a mechanical sweep.

## RE-F-10 — 3P thief body hidden, no 3P locomotion
- **severity:** P2
- **S1:** `thief_character.gd:716` `mesh_root.visible = false`; the only 3P players are crank and
  takedown.
- **S3:** unchanged: there is still no 3P locomotion player (would need a new state machine).
- **S4:** the takedown presentation now makes the 3P body visible for the montage and restores the
  first-person rig afterwards (`_tp_takedown_present` / `_tp_takedown_restore`), so the authored
  takedown is on screen.
- **verdict:** **PARTIAL** — visibility now works for the takedown; 3P locomotion remains absent.

## RE-F-11 — takedown on the wrong rig, victim from a different synced pair
- **severity:** P1
- **S1 investigate:** `thief_character.gd:2706-2750` (`_try_blackjack`) played the 1P swing, then
  `_tp_takedown_atk_start()` on `mesh_root` while `mesh_root.visible = false` (`:716`), using
  `AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage` (4.234 s). The guard's
  `take_knockout` → `play_takedown_vic` played `AN_StealthTakedown_GuardEnforcer__Vic_Montage`
  (3.500 s) — the victim half of a *different* pair. Both started at t=0.
- **S2 research (authored pairs in `anims_meta.json`):**
  `AN_StealthTakedown_GuardEnforcer__Atk` = 3.500 s and `…__Vic` = 3.500 s (one pair);
  the BlackJack `…_FromBehind_Montage` = 4.234 s is a single combined clip with **no separate
  victim half** anywhere in the 995 (searched every `*takedown*` / `*blackjack*` name).
- **S3 confirm (red):** pairing assertion fails against the old constants — the attacker clip's
  authored length (4.234 s) and the guard's preferred victim clip (3.500 s) differ by 0.734 s and
  are not siblings; and `mesh_root.visible == false` at play time, so no authored frame was shown.
- **S4 fix:** `TAKEDOWN_ATK_CLIP = AN_StealthTakedown_GuardEnforcer__Atk_Montage`,
  `TAKEDOWN_VIC_CLIP = …__Vic_Montage` (the guard table already prefers the Vic). The attacker
  montage is started **in `_apply_blackjack_hit`, on the same frame as `take_knockout`**, so both
  halves run from t=0 together; and `_tp_takedown_present()` makes the 3P body visible, hides the
  1P rig and shows a temporary third-person camera aimed at the pair for the montage length, then
  `_tp_takedown_restore()` puts first person back (also called from `_enter_downed` and on replay).
- **S5 test:** `test_m2_player.gd` **M2.10** — real player, real 3P skeleton:
  `PASS: M2.10 synced takedown plays on the visible 3P rig (AN_StealthTakedown_GuardEnforcer__Atk_Montage) and restores first person`.
  Gate: pair lengths agree (3.500/3.500), guard role prefers the pair's Vic, both halves have meta.
- **S6 confirm:** M2 12/12, E2E 278/278 (no camera or takedown regression).
- **verdict:** **FIXED** (pairing + visible rig + shared start frame). Spatial limitation → RE-F-08
  open risk.

## RE-F-12 — melee damage at swing frame 0; authored window 0.92–1.17 s
- **severity:** P1
- **S1:** `guard_ai.gd:1353-1358` `player.take_damage(MELEE_DAMAGE)` immediately before
  `_play_guard_attack()`; `_try_blackjack` called `g.take_knockout()` before the swing advanced.
- **S2:** `AN_GuardEnforcer_Club_Attack_Light_A` hitboxes 0.920/0.950/0.970/0.983/1.017/1.020/
  1.050/1.070/1.120 s, each 0.05 s → span **0.920–1.170 s** of a **2.133 s** swing;
  `AN_BlackJack_Attack_Light__Slash_R_01` hitboxes 0.280–0.380 s + 0.12 s duration → **0.280–0.500 s**
  of a 0.667 s swing. Contact instants used: midpoints **1.045 s** and **0.390 s**.
- **S3 confirm (red):** gate assertions against the old behaviour — an instant `take_damage` on the
  swing frame gives `hits_at_frame0 = 1` inside a 0.920–1.170 s window (the behavioural test failed
  exactly that way before the fix, and the clock test failed because the montage alone has no
  hitboxes).
- **S4 fix:** clock armed in `_play_guard_attack()` with the *source* clip (the library renames
  animations to role keys, so `_source_clip_for_role()` resolves the manifest name per weapon set);
  `_tick_attack_hit_window()` polls `current_animation_position` from `_update_guard_anim()` and
  applies damage once, re-checking the UE 100 cm DamageRadius at contact. Any KO/slip/takedown/
  cancel path disarms it. Player side: `_queue_blackjack_hit()` + `_tick_pending_melee()` wait for
  the authored contact (polls the FP player when that clip is still current, elapsed-time fallback
  so an interrupted swing still lands), and `_apply_blackjack_hit()` re-checks the 2.4 m reach.
- **S5 test:** gate **behavioural** on the real guard skeleton:
  `PASS: guard club damage lands once inside the authored 0.920-1.170s window, never on frame 0 or mid wind-up (amount=10)`
  (seek 0.0 / 0.5 / 0.93 s, then a repeat poll that must not double-hit).
  `run_tests` 55c now advances the clock (`_tick_pending_melee(0.5)`) instead of expecting a
  frame-0 KO — same assertion (behind → KO), new authored timing.
- **S6 confirm:** gate 14/14, `make test` fails=0, E2E 278/278.
- **verdict:** **FIXED**.

## RE-F-13 — lantern guard run clip 5.39 m/s vs the shared 7.6 constant
- **severity:** P2
- **S1:** `guard_ai.gd:31-35` `CLIP_GROUND_SPEED` keyed by role; `:700-710`
  `clampf(planar / clip_speed, 0.35, 1.8)`.
- **S2 (re-measured from the GLBs, not trusted):** root track ground speed ×1.16 rig scale:
  neutral walk 349.5 cm/3.283 s = 1.064 → **1.24**; suspicious 467.1/2.183 = 2.139 → **2.48**;
  club run 425.0/0.650 = 6.538 → **7.59**; lantern `…_Alert_Run__F` 673.4/1.450 = 4.643 → **5.39**;
  lantern `…_Alert_Run_F` net 0.0 cm → in-place.
- **S3 confirm (red):** at a 2.5 m/s chase the lantern clip needs 2.5/5.39 = 0.46 but the 7.6
  constant yields 0.329 → clamped to 0.35, legs cycling ~1.9 m/s under a 2.5 m/s body.
- **S4 fix:** `CLIP_GROUND_SPEED_BY_CLIP` override consulted *by resolved source clip* before the
  role constant; the in-place variant is 0.0 so it is never rate-scaled.
- **S5/S6:** gate
  `PASS: lantern guard run uses its authored 5.39 m/s clip (2.5 m/s chase -> playback 0.46, above the 0.35 clamp)`.
- **verdict:** **FIXED**. Note: the `…_Run_F` override is currently unreachable because
  `LANTERN_CLIPS["alert_run"]` lists `…__F` first and it ships — kept as a guard against a table
  reorder (see orphan inventory §6.2).

## RE-F-14 — 7 `FP_TOOL_CLIPS` entries unreachable
- **severity:** P3
- **S1/S2:** literal scan over all 63 `game/src/**/*.gd`: the role strings
  `zipwire_travel`, `zipwire_travel_up`, `zipwire_travel_up_start`, `zipwire_travel_start`,
  `climb_idle`, `climb_to_mantle`, `vault` had zero call-site returns.
- **S3 confirm (red):** independent scan (quoted literals, table definition vs call site) —
  all 7 unreachable at `HEAD`.
- **S4 fix:** `climb_to_mantle` (`AN_Climb_Ledge_ToMantle`) is selected when a mantle follows a
  wall-climb crest (`_climb_crest_grace`, 0.12 s, set when a climb ends airborne); `vault`
  (`AN_CrouchMantle_100`) is selected for a crouched mantle. Both are the authored states those
  clips were made for; no new state was invented.
- **S5/S6:** gate role-resolution check counts them; the two new roles are reachable by
  construction, the remaining five are documented below.
- **verdict:** **PARTIAL (2/7 wired)**. Deliberately still unreachable and left in the table:
  * the four `zipwire_travel*` poses — the comment at `_select_fp_anim_role` already records that
    `AN_Zipwire_Travel_1P` retargets the tool below the camera (muzzle y ≈ −0.34 m), so selecting
    it would be a visible regression; the authored hang pose is `zipwire_cast_idle`;
  * `climb_idle` (`AN_Climb_Ledge_Idle`) — needs a stationary ledge-hang state that the movement
    system does not have; inventing one is gameplay (T09/T10), not animation.

## RE-F-15 — lockpick: 41 assets, 0 animations, hands freeze
- **severity:** P3
- **S1/S2/S3:** verified: `grep -ic lockpick extracted/filelist.txt` = **41**, of which **0** are
  animation assets; `anims_manifest.json` has no `*lockpick*` clip. The 41:
  abilities `GA_Lockpick`, `GA_Lockpick_Cancel`, `GA_Lockpick_TrackFinished`,
  `GA_Lockpick_TrackInteract_Attempt/Broken/Jammed`; UI `BPUI_LockpickMinigame`, `…Screen`,
  `…Cursor`, `BPUI_CombinationLock_Widget/Digit`, `BPI_LockpickMInigameUI`, `BPUI_LockpickTrackEnd`,
  `BPUI_Tutorial_Video_Lockpicking`, `lockpicking_tutorial_video`;
  data `DA_LockpickMinigameVariations`, `CT_LockpickDamage`, `GC_Lockpick_Duration`,
  `GC_Lockpick_Interrupted`, `GC_Lockpick_TrackSection_Broken/Jammed`, `GE_Lockpicking`,
  `ST_Lockpicking`, `Play_tristan_fairy_ftue_lockpick_chests__doors__valuable_loot_01`;
  art `T_Lockpicking_BG`, `…_Cursor`, `…_KeyholeCover`, `…_RingTrack`, `…_RingTrack_Jammable`,
  `T_KeyholeMaskWidescreenCutout`, `T_KeyholeMaskWidescreenSize`, `T_Icon_Lockpick_QuestionMark`,
  `T_Icon_LockpickTrackEnd`, `Icon_Ability_Lockpick`, `M_LockpickCutout`, `BG_Vignette`.
- **verdict:** **DEFERRED — recorded data gap** (the brief's allowed second branch). There is no
  authored lockpick pose to bind; binding an unrelated crouch/interact clip would be invention.
  A real fix needs an authored 1P lockpick pose (content) or a hand-authored pose (art decision).

## RE-F-16 — mantle: 0.30 s of movement vs 0.73–2.57 s clips
- **severity:** P1
- **S1:** `thief_character.gd:1221` `_mantle_t = minf(1.0, _mantle_t + delta / 0.3)`; the authoured
  clip lengths from `anims_meta.json`: 050 **0.733**, 100 **0.983**, 150 **1.150**, 200 **1.733**,
  250 **2.233**, 300 **2.567** s → movement is 2.4–8.6× faster than the arms.
- **S2:** the 0.3 s constant is the port's `GE_Traversal_AutoMantle` note; the authored clip length
  is the animation truth. **The movement curve lives in `_physics_process`, i.e. the physics/
  movement contract owned by T09/RE-G**, not in an animation file.
- **S3 confirm:** the numbers above (read-only, from `anims_meta.json`); no code change was made.
- **verdict:** **BLOCKED-ON T09**. Exact contract handed over:
  * replace `delta / 0.3` with `delta / clip_length(_mantle_clip_role)` (0.733/0.983/1.150/1.733/
    2.233/2.567 s), or introduce `MANTLE_MOVE_SEC` per height band with those values;
  * `e2e_tier1_features.gd::T1-10-D` presses jump, advances **45 physics frames (0.75 s)** and
    requires `y >= 1.8` on a 2.0 m ledge — with the authored 1.733 s clip the player is only ~0.5 m
    up at 0.75 s, so that assertion must move to the clip length in the same change;
  * `e2e_tier2_boundaries.gd::T2-10-C` only checks the mantle *decision*, unaffected.
  Do not ship the movement change without updating T1-10-D; that is why this lane did not touch it.

## RE-F-17 — retarget is faithful but has no runtime gate
- **severity:** P2
- **S1/S2:** the only proof was a deleted 2026-11-16 temp check (`applied_clip_count=10`);
  `rg -n "applied_clip_count" game/tests` showed metadata census + text greps only.
- **S3 confirm (red):** no test loaded a guard GLB and asserted bone motion; the new suite would
  fail if `build_player` returned null or an identical pose.
- **S4 fix:** `test_anim_gates.gd` §4b instantiates the real
  `SK_GuardEnforcer_Dyn__Body.glb`, retargets the club table, plays `alert_idle` for 24 frames and
  counts bones whose `get_bone_pose_rotation` changed.
- **S5/S6:**
  `PASS: guard clip library retargets 11/11 roles onto the 100-bone guard skeleton`;
  `PASS: guard clip 'alert_idle' animates 70 bones over 0.4s`.
- **verdict:** **FIXED**.

## RE-F-01 / 02 / 03 / 05 / 18 / 19 / 20 / 21 — unchanged (P2/P3)
- **RE-F-01 (14 blendspaces):** **DEFERRED** — structurally unconvertible by `AnimationExporter`;
  no runtime blendspace. Nothing in this lane changes it.
- **RE-F-02 (27 AnimBlueprints, 0 `AnimationTree`):** **DEFERRED** — state machines stay
  hand-written; adding an `AnimationTree` is an architecture change beyond a finding fix.
- **RE-F-03 (57 AnimSet/DAM mapping assets):** **DEFERRED** — the guard role tables remain
  hand-authored; the new gate at least detects a role whose clip disappears from the manifest.
- **RE-F-05 (60 additive clips flattened):** **DEFERRED** — producer-side (USDA), no additive
  consumer exists. The duration fix deliberately leaves their zero-duration export alone.
- **RE-F-18 (civilians use 2 base clips, 0 CivMale):** **DEFERRED** — `civilian_npc.gd` is not in
  this lane's file ownership; the orphan inventory gives the exact 43-clip list and the two states
  (`flee`, `cower`) that would use 9 of them.
- **RE-F-19 (995 GLBs + manifest ship in the PCK):** **DEFERRED** — packaging question for the
  integrator/export lane; the new gate adds no runtime cost.
- **RE-F-20 (214 queued packages counted nowhere):** **DEFERRED** — extractor accounting
  (`tools/tat-extract`), T01's area.
- **RE-F-21 (24 curves name-only):** **DEFERRED** — data ceiling of the cooked extract; the report
  records it so nobody re-runs extraction expecting `loco_speed`.

## Not a lane finding, found while fixing: two dead stop paths
`find_children("*", "TPTakedownPlayer", true, false)` never matched: the second argument is a
**class** filter, and no class is named `TPTakedownPlayer` (it is an `AnimationPlayer` node named
that). The same pattern in `_tp_crank_stop` meant the P2 "stale montage" stops were no-ops for both
3P players. Fixed to `find_children("TPTakedownPlayer", "AnimationPlayer", true, false)` (and the
crank equivalent) in `4163632`; covered by M2.10's restore assertion and by replaying the takedown.

`tool_preview.gd` was inspected (it is in this lane's file list) and holds no animation state —
it is a static gear-mesh stage (`ToolPreviewStage`); nothing to change.

---

## Team summary

| verdict | count | findings |
|---|---|---|
| **FIXED** | 5 | RE-F-04, RE-F-11, RE-F-12, RE-F-13, RE-F-17 |
| **PARTIAL** | 4 | RE-F-06 (hitboxes only), RE-F-09 (inventory + 2 roles), RE-F-10 (takedown visibility), RE-F-14 (2/7 roles) |
| **BLOCKED-ON T09** | 1 | RE-F-16 (mantle movement duration; exact contract above) |
| **DEFERRED** | 11 | RE-F-01, 02, 03, 05, 07, 08, 15 (recorded data gap), 18, 19, 20, 21 |
| **total** | 21 | |

P1 items from the brief: 1 (duration) **FIXED**, 2 (hit windows) **FIXED**, 3 (takedown) **FIXED**,
4 (mantle) **BLOCKED-ON T09 with contract**. P2 items: 5 (lantern speed) **FIXED**,
6 (lockpick) **recorded data gap**, 7 (reachable set / orphans) **PARTIAL + inventory**,
8 (gate) **FIXED** (new `test_anim_gates.gd`, 14 assertions).

---

## Orphan clip inventory

Method: every quoted `"AN_*"`/`"MM_*"` literal in the 63 `game/src/**/*.gd` files, cross-matched
against the 995 manifest `animation` names; two independent scans (Python walk + `grep -rhoE`)
agree on the same 95 literals. "Bound" = literal ∩ manifest. Family = the first path segment under
`TAT/Content/Art/Animation/`. Authored seconds are `anims_meta.length` sums, not GLB durations.

### Headline
| step | clips | % |
|---|---|---|
| manifest (782 sequences + 213 montages) | 995 | 100.0 |
| distinct clip-name literals in `game/src` | 95 | — |
| **bound** | **94** | 9.4 |
| **orphans** | **901** | **90.6** |
| unique orphan motions (156 montages duplicate a sequence) | 765 | 76.9 |
| playable in principle (minus 7 unreachable table roles, 6 dead fallbacks, 1 alias) | **80** | 8.0 |
| reach a player in a shipped mission (also minus `HA_CLIPS`, never selected) | 73 | 7.3 |

### Family table (orphans only)
| family | clips | bound | orphan | orphan % | orphan authored s |
|---|---|---|---|---|---|
| `Base/Anim/*` | 301 | 24 | 277 | 92.0 | 573.1 |
| `GuardEnforcer/*` | 285 | 26 | 259 | 90.9 | 908.7 |
| `Thief/*` | 204 | 30 | 174 | 85.3 | 221.7 |
| `ThiefNisha/*` | 134 | 11 | 123 | 91.8 | 213.2 |
| `CivMale/*` | 43 | 0 | 43 | 100.0 | 384.8 |
| `ThiefCotter/*` | 16 | 3 | 13 | 81.2 | 29.2 |
| `Art/Gameplay/Gear` | 6 | 0 | 6 | 100.0 | 9.1 |
| `Art/_DO_NOT_USE` | 5 | 0 | 5 | 100.0 | 3.9 |
| `AI/Escalation` | 1 | 0 | 1 | 100.0 | 1.0 |
| **total** | **995** | **94** | **901** | **90.6** | **2344.8** |

### Top 10 to bind next (small, additive, no producer run)
| # | clips | family / sub-family | what would use it | call site |
|---|---|---|---|---|
| 1 | ~4 | `Base/Anim/Damage` Stagger F/L/R/B | guard hit reaction; today a hit has zero body feedback | `guard_ai.apply_damage` → new `damage` role over the loco loop |
| 2 | ~4 | `GuardEnforcer/Club/Action` React/Recognize/Extend/Rush | being spotted is the core loop beat and has no pose | `guard_ai._set_state(ALERTED)` / sight acquisition |
| 3 | 4 | `GuardEnforcer/Club/Interact` Alarm/BreakDown/Investigate/Low-Pickup | all four gameplay beats exist | `guard_ai` investigate + alarm hooks |
| 4 | 6 | `Base/Anim/Action/Lean` L/R In-Loop-Out | 1P arms while Q/R leans; clips are `UpperBodyOnlyWhenMoving` | `_select_fp_anim_role` lean branch |
| 5 | 4–5 | `GuardEnforcer/Club/Attack` Light_B/C, Heavy_A, Block, Stomp | only 1 of 5 authored attacks is bound | `guard_ai._play_guard_attack` by combat tier |
| 6 | 9 | `CivMale/Anim/Locomotion` Flee_F/B/L/R + `CivMale/Anim/Damage` Cower | civilians are the alarm channel and currently stroll | `civilian_npc._play_role` new `flee`/`cower` |
| 7 | 3 | `CivMale` idle variants + `Idle_Nervous_Look_Around_Montage` | cheapest believability win | same `_play_role` |
| 8 | ~9 | `Thief/Anim/Gear/BlackJack` Slash_L 01–03, Parry, Block, Dodge ×4 | the player's only swung weapon has one swing | `_try_blackjack` / `_fp_play_action` |
| 9 | ~4 | `Base/Anim/Interact` Grab/Instant/Loop | world interaction has no arm animation at all | `game/src/interact/*` start |
| 10 | 3–6 | directional loco (`GuardEnforcer/Club|Lantern Alert_Run_Left/Right/Bwd`) | removes the visible strafe/backpedal slide | `guard_ai._update_guard_loco_playback` |

### Reachability of the 7 RE-F-14 roles (after `4163632`)
`zipwire_travel`, `zipwire_travel_up`, `zipwire_travel_up_start`, `zipwire_travel_start`,
`climb_idle` remain unselectable (reasons in RE-F-14); `climb_to_mantle` and `vault` are now
selected by `try_auto_mantle`.

### Additional dead table entries (beyond the 7)
- `TP_TAKEDOWN_CLIPS.takedown_atk_3p` (the old BlackJack montage) is now unreachable: the single
  call site passes `takedown_atk_stealth_3p`. `takedown_atk_overhead_3p` was already dead.
- Six priority-list fallbacks can never fire while the primary resolves, including
  `AN_GuardEnforcer_Lantern_Alert_Run_F` (see RE-F-13) and four `takedown_vic` alternates.
- **`HA_CLIPS` is never selected at runtime**: `_guard_weapon_set()` returns `hauntstable` only for
  a node name containing `haunt`, and the single guard spawn site names guards
  `Guard_%d` / `Guard_ClubLantern_%d`. The 7 bound `AN_GE_HA_*` clips and 80 Hauntstable clips are
  unreachable in a mission even though the table exists — a T11/T10 spawn-side finding, not fixed
  here.

---

## Doc corrections (integrator applies)

1. **AGENTS.md gate table** — add the animation gate line:
   `tools/godot --headless --path game --script res://tests/test_anim_gates.gd` →
   `ANIM_GATE_SUMMARY: fails=0` (14 assertions). M2 baseline moves **11 → 12** (`M2.10`).
   Compile baseline is **122** checked on this tree (new files).
2. **`docs/FIDELITY_GAPS.md`**
   * `PG-7` "simplified takedown motion" — mechanism is now fixed: the pair is
     Atk/Vic 3.500 s, both start together, the 3P body is shown under a temporary third-person
     camera. Remaining gap: root motion is still stripped, so the authored 148 cm closing travel
     is not applied (RE-F-08).
   * add: **melee damage timing** is now authored (club contact 1.045 s of 2.133 s; blackjack
     0.390 s of 0.667 s); the old "damage on swing frame 0" note is stale.
   * add: **lockpick has no authored animation** (41 assets, 0 clips; list in RE-F-15); the hands
     hold the equip/idle pose during the dial minigame.
   * add: **guard damage reactions have no animation** (5 hit-react + 14 stagger clips unused);
     same for guard sight reactions and civilian cower/flee.
   * update `PG-7` foot-slide: the lantern run now uses its authored 5.39 m/s clip; the club/HA
     7.59 m/s vs 2.5 m/s chase remains (~3×).
   * add: `HA_CLIPS` is never selected (no `haunt*` guard node name), so the 7 bound
     `AN_GE_HA_*` clips and 80 Hauntstable clips cannot play in a mission.
3. **`docs/HANDOFF_NEXT_AGENT.md`** — HEAD `4163632` on `rem/T04-anim`, gates as in the table
   above; open work: integral mantle duration (T09), root-motion layer, montage sections/slots,
   footstep notify consumer (T03), orphan binding per the inventory.
4. **`docs/REFERENCE_BASELINE.md`** (if it carries clip counts) — 995 converted clips now export
   authored length after regeneration; 94 wired / 901 orphans / 80 playable in principle.
5. **RE-F lane file corrections** (for the record, no edit by this lane): RE-F-09's 92/85/903
   should read 94/87-at-HEAD/901 (see Team summary), and "41 Damage reactions" should read
   "5 hit reactions + 14 staggers + 2 knockdowns + 2 damage one-shots + 18 crawl clips".

---

## Open risks

1. **Stale animation data until regeneration.** The producer is fixed but the 995 GLBs and
   `anims_manifest.json` on disk are legacy. The gate accepts the exact legacy model once and
   refuses it after `duration_mode=authored` appears — so the first integrator run after `make anims`
   is the real strict check. Until then, in-game cadence still uses the old lengths.
2. **Takedown spatial seam (RE-F-08).** Both halves are retargeted in place; the authored root
   travel is stripped, so the attacker and victim can be ~1.5 m apart while the montage plays. The
   camera frames both, but this is not the authored shared-space grapple. Needs root-motion/motion
   warping and actor displacement (T09 for the capsule, T04 for the retarget mode).
3. **Melee whiffs are now possible.** Damage is checked at the authored contact inside the 1.0 m UE
   DamageRadius; a player who backs off during the 0.92 s wind-up is not hit. That is authored
   behaviour, but it changes difficulty feel and has not been play-tested (no GPU run this lane).
4. **Blackjack KO is 0.390 s delayed.** A guard can turn/leave in that window; the strike then
   whiffs (reach re-checked). `run_tests` 55c and E2E pass, but the feel is unmeasured.
5. **Takedown presentation is a 3.5 s third-person camera.** It does not lock movement or input;
   the player can walk during the montage (the camera follows the pair). If the player is captured
   mid-montage, `_enter_downed` stops and restores the presentation.
6. **`HA_CLIPS` unreachable** (spawn naming) and `TakedownOverhead_*` alternates dead — table/data
   drift that no gate catches today; listed for T10/T11.
7. **Ten clips keep a ≤1.64 % residual** after the producer fix because the USDA
   `timeCodesPerSecond` is not exactly `N/SequenceLength`; the exact authored length exists only in
   the JSON dump, not in the USD. Fixing that is an extractor/producer decision (T01).
8. **Footsteps and VO notifies remain unconsumed** (1,321 + 205 events). The clock is in place;
   wiring audio is T03's bus work and needs the surface-aware footstep mapping.
9. **Not verified visually.** No GPU/Vulkan run, no capture. Every visual claim above is a code +
   data claim; the 3P presentation, camera framing and foot-slide improvement are unobserved.

---

## Integrator steps (regeneration is yours)

1. Cherry-pick `5319bf6` then `4163632` onto `main` (wave order; T11 merges later and should pick up
   the `guard_ai.gd` animation hunk — it touches `_play_guard_attack`, `_update_guard_anim`, the
   melee hook in `_move_ai`, `_update_guard_loco_playback` and the new `_source_clip_for_role`,
   `_apply_guard_melee_hit`, `_tick_attack_hit_window`, `_attack_source_clip` — no behaviour change
   outside animation timing).
2. `make anims` (≈30 min, writes `game/assets/ue/Anims/**` and
   `game/data/generated/anims_manifest.json`, now with `duration_mode: authored`).
3. `make audit-refresh-stamps` (producer baseline: `tools/usd_to_gltf.py` sha256 changed) then
   `make audit` → exit 0.
4. Re-run, serially, on the merged tree: compile, `make test`, `test_m2_player` (expect 12),
   `probe_leak`, door/viewmodel/Niagara probes, **`tests/test_anim_gates.gd` (expect fails=0 and
   `mode=authored (strict)` with `legacy=0`)**, E2E 278/278, `build/qa/test_perf_guard.sh`,
   `make gate-ratchet`.
5. If the strict duration branch reports legacy clips after `make anims`, the regeneration did not
   take (check `anims_manifest.json` has `duration_mode` and `entries[].duration` ≈ authored).
6. Do not re-baseline the M2 count without updating `AGENTS.md` (11 → 12) and the gate table.
