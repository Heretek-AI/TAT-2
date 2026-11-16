# Guard real-animation implementation report

Stage: guard-animations (subagent of TAT-2 wave fleet)
Date: 2026-11-16
Repo: `/home/john/Projects/TAT-2` (Godot 4.7.2, `main`)

Guards now play the REAL extracted UE animation clips instead of procedural
bobbing. No placeholder/fabricated motion: every played track is baked source
data, retargeted by bone name with rest-pose-delta math and a measured
cm→m unit factor. Anything that cannot be retargeted is skipped and the
procedural fallback keeps playing.

## Deliverables

1. `game/src/core/animation_library.gd` (new, `class_name GuardAnimationLibrary`)
   - Loads `res://data/generated/anims_manifest.json` once (static cache),
     resolves each role to an explicit clip name with RegEx fallback
     (`ROLE_PATTERNS`, constrained to GuardEnforcer/`GE_HA`/Hauntstable GLBs).
   - Loads animation GLBs at runtime with `GLTFDocument.append_from_buffer`
     + `generate_scene` (the `Anims/` folder ships without editor `.import`
     files, so `ResourceLoader` cannot open them; a `PackedScene` branch is
     kept for files that do have imports).
   - Copies each `Animation` into a fresh resource with track paths remapped
     from `SKEL_Base/.../Skeleton3D:<bone>` to `<target skeleton>:<bone>`,
     keeping a track only when the bone exists in the target skeleton.
   - Retarget math (same-topology skeletons, different rest pose and units):
     `q_out = q_mesh_rest * q_anim_rest⁻¹ * q_anim`,
     `p_out = p_mesh_rest + k * R_corr * (p_anim − p_anim_rest)` with the
     parent-frame correction `R_corr = R_mesh_parent * R_anim_parent⁻¹`,
     `k` derived from the pelvis rest-length ratio (≈0.0116).
     Root-bone translation is stripped for locomotion roles (in-place
     conversion; scripted velocity owns displacement).
   - Loop mode: `LOOP_LINEAR` for idle/walk/run/search/knockdown,
     `LOOP_NONE` for attack/slip one-shots.
   - API: `has_clips()`, `clip_for_state(state_name, weapon, moving)`,
     `clip_for_role(role, weapon)`, `clip_length(key)`,
     `applied_clip_count()`, `bone_report()`.
2. `game/src/ai/guard_ai.gd` (modified, anim section only)
   - `_setup_guard_anims()` builds `GuardAnimPlayer` (child of `visual_root`,
     `root_node` = skeleton's parent so one retargeted library fits all three
     mesh variants) when ≥4 clips retarget; otherwise null + fallback.
   - `_update_guard_anim()`: NEUTRAL→idle/walk, SUSPICIOUS→idle/walk,
     ALERTED/COMBAT→alert idle/run, SEARCH→search loop, KNOCKED_OUT→knockdown
     loop; attack montage one-shot with `clip_length` lock; `play_slip()`
     public for the MagicSlime tool wave (slip once → knockdown loop via
     `animation_finished`); KO/recover tip-over tweens skipped when real clips
     own the player; procedural bob kept as the no-clip fallback.
   - All playback guarded by `_anim_can_play()` (valid player, inside tree,
     not queued for deletion).
3. Temp check `game/tests/_tmp_guard_anim.gd`: full green (`fails=0`, zero
   SCRIPT ERROR), then self-deleted (`DirAccess.remove_absolute`, `err=0`).
4. This report.

## Clip mapping (all files verified present on disk)

| Role | Club (Enforcer/Security) | Hauntstable | Dur (s) |
|---|---|---|---|
| neutral_idle | `AN_GuardEnforcer_NeutralFresh_Idle` | `AN_GE_HA_NeutralFresh_Idle` | 4.98 |
| neutral_walk | `AN_GuardEnforcer_NeutralFresh_Walk_F` | `AN_GE_HA_NeutralFresh_Walk_F` | 3.28 |
| suspicious_idle | `AN_GuardEnforcer_Suspicious_Idle` | `AN_GE_HA_Suspicious_Idle` | 5.88 / 4.98 |
| suspicious_walk | `AN_GuardEnforcer_Suspicious_Walk_F` | `AN_GE_HA_Suspicious_Walk_F` | 2.18 |
| alert_idle | `AN_GuardEnforcer_Club_Alert_Idle` | `AN_GE_HA_Alert_Idle` | 10.02 / 10.05 |
| alert_run | `AN_GuardEnforcer_Club_Alert_Run_F` | `AN_GE_HA_Alert_Run_F` | 0.65 |
| attack | `AN_GuardEnforcer_Club_Attack_Light_A_Montage` (both sets; no HA-specific attack clip exists) | same | 2.12 |
| search | `AN_GuardEnforcer_Club_VigilantSuspicious_Search` | `AN_Hauntstable_VigilantSuspicious_Search_Montage` | 5.98 |
| knockdown | `AN_GuardEnforcer_Club_Knockdown_Prone__Idle` (both sets) | same | 0.98 |
| slip | `AN_GuardEnforcer_Slip_MagicSlime_Montage` (both sets) | same | 5.82 |

State mapping: NEUTRAL→neutral_* (walk when moving), SUSPICIOUS→suspicious_*,
ALERTED/COMBAT→alert_* (run when moving), SEARCH→search, KNOCKED_OUT→knockdown,
COMBAT strike→attack montage, MagicSlime→`play_slip()`→slip→knockdown.

## Bone-intersection evidence

- Guard mesh skeletons: 97 bones (`root, pelvis, thigh_r, …`). Animation
  skeletons: 167 bones (97 shared + 70 first-person `_1p`/camera helpers).
- Animated bone-name union across the 10 club clips: 160 names;
  **matched with mesh: 95/97**. Missing: `ik_hand_root`, `ik_foot_root`
  (static IK helpers whose constant tracks the importer prunes; no skin
  impact). Dropped extras: 65 `_1p`/camera/weapon-helper names with no mesh
  counterpart — reported, never invented.
- Rest-pose audit (global-FK comparison, probe): segment ratios
  thigh 0.515m/46.0 = 0.0112, calf same, head 2.05m/167.2 = 0.0123,
  pelvis 1.16m/100.0 = 0.0116 → animation GLBs are centimetre-unit on a
  ~12–16%-smaller rig; local rest frames differ (e.g. pelvis 120°, root 90°),
  which the delta-from-rest conversion absorbs.
- Root-motion audit (source clips, cm): walk root z 0→349.5 (3.28 s ⇒
  ≈1.24 m/s scaled) vs patrol 1.5 m/s; suspicious walk ≈2.5 m/s vs 1.7 m/s;
  alert run ≈7.6 m/s vs chase ≈2.1–3.0 m/s (sprint cadence — worst foot-slide
  case, accepted). Root translation is stripped for locomotion so scripted
  velocity owns displacement.

## Temp-check output (final run, self-deleted afterwards)

```
PASS: guard_ai.gd loads
GUARD ANIM: build+settle took 753ms
PASS: AnimationPlayer attached to guard
GUARD ANIM: applied_clip_count=10
PASS: guard has >= 4 real clips
animations=["alert_idle", "alert_run", "attack", "knockdown", "neutral_idle",
  "neutral_walk", "search", "slip", "suspicious_idle", "suspicious_walk"]
GUARD ANIM: current_animation=neutral_walk
PASS: current_animation non-empty
bone intersection mesh_bones=97 anim_bones=160 matched=95 ...
PASS: bone intersection >= 90
PASS: guard has Skeleton3D
PASS: guard position advances (moved 0.829m)
global bone0 delta=0.0 bone10 delta=0.1 / local bone0 delta=0.0 bone10 delta=0.1
PASS: skeleton LOCAL bones moved over 0.5s
PASS: no unit-scale blowup (pelvis global delta sane)
after knock_out current=knockdown — PASS
after play_slip current=slip — PASS
after revive current=search — PASS
GUARD ANIM CHECK: fails=0 / self-delete err=0
```

## Verification commands (exit codes)

- Temp check RED (no library yet): `fails=1` as expected.
- Temp check GREEN ×3 incl. final self-deleting run: exit `0`, `fails=0`,
  zero `SCRIPT ERROR`.
- `make test` with changes: exit `0`, `SUMMARY: fails=0`, `SCRIPT ERROR` count `0`.
- `make test` baseline (my 3 paths stashed, other waves' files untouched):
  exit `0`, `SUMMARY: fails=0`, identical `3 ObjectDB instances leaked at
  exit` warning → leak is pre-existing, not from this change. Restored via
  `git stash pop`.
- `make test` final (temp file deleted): exit `0`, `SUMMARY: fails=0`,
  `SCRIPT ERROR` count `0`.

## Limits (stated plainly)

- No AnimBlueprint/state machine: direct clip switching with 0.25 s blends.
  Montage timing = clip length (attack lock 2.12 s; slip 5.82 s → knockdown).
- Locomotion is in-place; cadence vs scripted speed is approximate, so some
  foot slide remains (worst: alert sprint at ~3× chase speed).
- Pose quality was verified headless only (bone deltas + scale sanity
  bounds); recommend an in-game visual pass.
- Hauntstable weapon set reuses the Club attack montage (no HA-specific
  attack clip in the manifest); the temp check exercised the club set, the HA
  set shares the identical code path and resolves against the same 97-bone
  name set.
- Untouched as constrained: `run_tests.gd`, `level_loader.gd`,
  `mission_controller.gd`, `thief_character.gd`, parsers, extractor,
  `Makefile`, Android files. The pre-existing `_tmp_levelcomp_check.gd` and
  root `extension_api.json` are not mine and were left alone.
