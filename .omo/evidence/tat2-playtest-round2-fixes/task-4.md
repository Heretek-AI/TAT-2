# Task 4 — Zipwire crank wired to the 3P model (handle moves when cranking after firing)

Date (UTC): 2026-11-20. Build: HEAD `ca7e8ed` + round-1 worktree (per task-0 ledger; 8 CONFIRMED / 1 STALE / 1 UNPROVEN, crank symptom 5 CONFIRMED 1P-only).

## (a) Ground truth re-derived (nothing invented)

- Backlog F13 (`cooked found`): UE source `TAT/Content/Art/Animation/Thief/Anim/Gear/Zipwire/AN_Zipwire_Crank_Montage.uasset`.
- Cooked, re-verified this turn:
  - `extracted/json/Art/Animation/Thief/Anim/Gear/Zipwire/AN_Zipwire_Crank_Montage.json`: `AnimMontage/AN_Zipwire_Crank_Montage`, CompositeSections `CrankStart -> CrankLoop`, SegmentLength **4.6666665**, Slot `UpperBody`, linked sequence `AN_Zipwire__Reload`. The 4.65 s 3P form.
  - Manifest `game/data/generated/anims_manifest.json` (995 entries): `AN_Zipwire_Crank_Montage` duration **4.650059485579117 s**, 501 tracks / 501 samplers; `AN_Zipwire__Reload` same duration, 501 tracks; `AN_Zipwire__Gear_Zipwire_Reload` same duration, 54 tracks (tool skeleton); `AN_ThiefNisha_Zipwire__Reload_Loop` duration 1.3168724215233159 s (the 1P loop, untouched).
  - `extracted/json/Art/Gameplay/Gear/Zipwire/SKEL_Zipwire.json` ReferenceSkeleton bones: `root, base, barrel, crank, crank_arm, crank_handle, arrow, blade_top, blade_left, blade_right, spring01..03, hinge_upper, hinge_lower, battery, gear, trigger` — the crank-handle bone/track is `crank -> crank_arm -> crank_handle`.
- Footage: `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` S15 (01:49.50–01:58.50, 2nd ZipWire launch & crank ascent): circular progress reticle with `CRANK [LMB]` (KF17 01:51.20), rhythmic ratchet hand-cranking SFX 01:56.1–02:01.2.
- Prior work: `.omo/evidence/tat2-playtest-ground-truth-fixes/task-9.log` (1P loop wiring; `animation_library.gd:84` verified correct there and untouched here).

## (b) Rig resolved (not the hidden 1P viewmodel)

- Firing thief rig = the 3P body skeleton under `mesh_root` (`SK_ThiefNisha_Dyn__Body_NoPostProcABP` GLB instance; `_tp_crank_body_skel()` returns its first `Skeleton3D`, never `fp_arm_skel`/`fp_anim_player`).
- Handle = the zipwire tool's crank: real `SK_Zipwire` `crank_handle` bone under `fp_tool_root` when the tool GLB loaded, else the new `ZipwireCrankHandle` fallback sub-node (below). The 1P viewmodel player (`fp_anim_player`) is never referenced by any `_tp_crank_*` code path (verified: zero occurrences outside comments).

## (c) Clip driven

- 3P montage: `AN_Zipwire_Crank_Montage` (4.65 s 3P form) via the new anim-library entry `TP_CRANK_CLIPS["zipwire_crank_3p"]` + `ensure_tp_crank_clip(player)` (similarity retarget, thief-skeleton precedent; dedicated library instance per call so the 1P `applied` map is never polluted). Played looped on a `TPCrankPlayer` (child of the 3P skeleton's parent, `root_node` = skeleton parent, mirroring `build_fp_player`) while `_is_cranking` holds; stopped in `_tp_crank_stop()`.
- Distinct from the 1P loop: `animation_library.gd:84` (`FP_TOOL_CLIPS["zipwire_crank"]` → `AN_ThiefNisha_Zipwire__Reload_Loop`, `loop: true`) byte-identical before/after (verified via `sed -n 82,86p` + zero removed lines in the anim-lib diff).

## (d) Drive path (while `_is_cranking` holds)

- `_begin_wire_crank` → `_play_wire_crank_clip` → `_tp_crank_start()` (also on both 1P no-op arms-off paths, so the 3P handle still moves where the 1P viewmodel is hidden/absent).
- `_tick_wire_crank` → `_tp_crank_tick()` after `crank_progress` update: absolute handle angle `TAU * 3.0 * crank_progress` (3 full turns per crank; rests exactly when cranking stops) applied as `crank_handle` bone-pose rotation on the real tool skeleton, else `ZipwireCrankHandle` pivot rotation on the fallback.
- Completion branch + `_end_wire_crank` → `_tp_crank_stop()` stops the montage player; handle keeps its final pose until the next crank resets it (`_tp_crank_reset_handle()` in `_tp_crank_start`).
- All failures warn-and-continue (missing 3P body, bind failure, manifest/zero-bone no-op); never crashes, never fabricates motion.

## (e) Fallback handle sub-node (fallback mesh lacked one)

- `_build_fp_zipwire_fallback` now appends a `ZipwireCrankHandle` `Node3D` pivot at `(0.035, -0.01, 0.06)` with `CrankArm` box + `CrankKnob` cylinder children, mirroring the `SKEL_Zipwire` `crank_arm -> crank_handle` chain. Previously the fallback had only `ZipwireBody`/`ZipwireBow`/`ZipwireTip`.

## Verification (file-level, this turn)

- Re-read edited spans: crank state (~:989–1050), viewmodel-rig 3P funcs (~:2275–2370), fallback (~:2660–2700); drive path references `mesh_root` (6x) / `fp_tool_root` tool skeleton (8x) / `TPCrankPlayer` (3x), never `fp_anim_player`.
- `animation_library.gd:84` unchanged; anim-lib diff has zero removed lines (pure addition: `TP_CRANK_CLIPS` + `ensure_tp_crank_clip`); guard consts/functions (`CLUB_CLIPS`, `HA_CLIPS`, `ROLE_ORDER`, `ROLE_PATTERNS`, `build_player`, `_resolve_clip`, `clip_for_state`) untouched.
- Targeted check: `gdparse` on both edited files → rc=0 (parse OK).
- Changed ranges: `thief_character.gd` crank spans + new `_tp_crank_*` funcs + fallback handle; `animation_library.gd` +40 lines (3P crank entry); this file. No `make test`, no live-GPU run (orchestrator-gated).
- Assumptions recorded: handle spin axis = local X (Godot crank-pivot default; no visual verify available); 3 turns per full crank (visual clarity over the ~6 s hold); similarity retarget for the 3P montage (same exporter pipeline as the proven 1P path).
