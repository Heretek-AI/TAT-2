# Stage report: real ThiefNisha first-person rig (player-1p)

## Stage id
player-1p — replace the procedural FP gloves + civilian 3P body with the real
ThiefNisha meshes and real 1P animation clips.

## Deliverables
1. `game/src/core/animation_library.gd`: added `build_fp_player()` plus
   `FP_CLIPS` / `FP_ORDER` / `FP_BLEND`, reusing the existing bone-name /
   rest-delta / pelvis-rest unit-factor retarget (`_retargeted` is now a thin
   wrapper over the generalized `_retarget_general`; guard behavior unchanged).
2. `game/src/player/thief_character.gd`:
   - 3P body is now `SK_ThiefNisha_Dyn__Body_NoPostProcABP` + `SK_ThiefNisha_Dyn__Head`
     (still hidden in first person via `mesh_root.visible = false`).
   - 1P viewmodel is the real `SK_ThiefNisha__BodyUpper` under the camera,
     aligned by derivation (see below); `SK_ThiefNisha__BodyLower` deliberately
     omitted (same full skeleton — would need a second player; legs are below
     the FP frustum).
   - `AN_Walk_F_1P` / `AN_Sprint_F_1P` / `AN_Crouch_F_1P` selected by planar
     speed + crouch/sprint with 0.2 s crossfade; stationary holds the bind pose
     (no fabricated idle).
   - `fp_tool_root` mounted on `weapon_r_1p` via `BoneAttachment3D`
     (fallbacks `hand_r_1p`, `hand_r`, then camera-relative).
   - Full procedural rig kept as automatic fallback (`_fp_use_real_arms`).
3. Temporary probe `game/tests/_tmp_fp_arms.gd`: 14/14 PASS, then deleted
   (plus a debug probe used once to diagnose rotation-only sprint motion).
4. `make test` (i.e. `run_tests.gd` untouched): SUMMARY: fails=0, exit 0,
   zero `SCRIPT ERROR`.
5. This report.

## Files changed
- `game/src/core/animation_library.gd`
- `game/src/player/thief_character.gd`
- `docs/reports/player-1p.md` (this file)

## BP component -> GLB mapping
Source: `extracted/json/Character/Player/BP_Player_Thief_Spider.json`
(BP_Player_Base supplies attach parents; no relative offsets are authored —
the 1P framing lives in the skeleton's camera joints).

| BP component       | SkeletalMesh (BP)                              | GLB used (res://…)                                                              |
|--------------------|-----------------------------------------------|---------------------------------------------------------------------------------|
| `Mesh3P_Body`      | `SK_ThiefNisha_Dyn__Body_NoPostProcABP`       | `assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/Dyn/SK_ThiefNisha_Dyn__Body_NoPostProcABP.glb` |
| `Mesh3P_Head`      | `SK_ThiefNisha_Dyn__Head`                     | `assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/Dyn/SK_ThiefNisha_Dyn__Head.glb`               |
| `Mesh1P_UpperBody` | `SK_ThiefNisha__BodyUpper`                    | `assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/SK_ThiefNisha__BodyUpper.glb`                 |
| `Mesh1P_LowerBody` | `SK_ThiefNisha__BodyLower`                    | not instanced (see limits)                                                      |

## Clip mapping (manifest `game/data/generated/anims_manifest.json`)
| State (planar > 0.5 m/s, on floor) | Clip | Manifest duration |
|------------------------------------|------|-------------------|
| walk                               | `AN_Walk_F_1P` (`TAT/Content/Art/Animation/Base/Anim/AN_Walk_F_1P.glb`) | 0.95 s |
| sprint                             | `AN_Sprint_F_1P` | 0.617 s |
| crouch                             | `AN_Crouch_F_1P` | 0.884 s |
| stationary / not playing           | bind pose hold (`stop()` + `reset_bone_poses()`) | — |

All three loop (`LOOP_LINEAR`), `root` translation stripped (in-place
locomotion; scripted velocity drives displacement), blend 0.2 s.

## Unit / pose derivation (nothing guessed)
- Mesh side is meters: BodyUpper POSITION bounds span y 0.94–1.52 and the
  imported `Skeleton3D` rests read out in meters.
- Anim side is centimeters (e.g. `camera_position` rest y ≈ 167).
- Conversion reuses `animation_library.gd`: per-bone rest-delta rotation
  (`q_mesh * q_anim`) and position (`mesh_rest + corr * (src - src_rest) * k`)
  with `k` = pelvis-rest-length ratio (cm→m).
- 1P placement: the mesh and anim skeletons both contain `camera_position`
  (fallback `game_camera`); the instanced root is counter-moved by
  `(holder←skeleton * rest(camera_joint))⁻¹` so the camera joint lands exactly
  on the camera. Local chain only — no world dependency, identity scale.
- Tool mount: `weapon_r_1p` resolved at runtime (verified present in the
  imported skeleton).

## Authored-data finding (verified, not assumed)
- `SK_ThiefNisha__BodyUpper` vertices are weighted 100% to `_1p` bones
  (56 joints, JOINTS_0 analysis).
- `AN_Walk_F_1P` animates 71 regular bones and **0** `_1p` bones: the `_1p`
  chain holds an authored fixed hold pose (2-key static offsets, e.g.
  `hand_r_1p` rot deviation 0.20 from bind). `AN_Sprint_F_1P` animates 51
  `_1p` bones (rotation-only on the arms: position keys static, rotation
  spread up to 0.67 on `upperarm_r_1p`).
- Consequence: verbatim retarget is the faithful choice — mirroring the walk
  swing onto the `_1p` arms would fabricate motion the shipped clip does not
  contain. The probe therefore proves bone motion on the sprint clip
  (hand rotation change), walk selection by `current_animation`, and the UE
  design (steady FP hold pose + procedural camera bob, matching the BP's
  `TATFirstPersonViewModifier_*` stack which our bob/breathe replicates).

## Screenshots
Headless run: no screenshots possible. Visual checks for a headed run:
1. In game, arms are Nisha's gloved/upper-body mesh (not grey boxes) and
   swing subtly with bob while walking, pump while sprinting, lower while
   crouching; standing still settles to the bind hold pose.
2. Blackjack/sap/bomb/fairy/zipwire tool models render in the right hand and
   swing on use.
3. No 3P body visible in first person (mesh_root hidden); arms framed
   relative to camera without clipping through the view.

## Limits (no motion invented)
- No 1P idle or jump clip exists in the install — stationary holds bind pose.
- `SK_ThiefNisha__BodyLower` omitted (duplicate full skeleton; below frustum).
- Disguise 1P clips (`AN_Disguise_*_1P`, incl. walk/sprint/crouch-idle/jump)
  and zipwire 1P clips (`AN_Zipwire_{Walk,Run}_F_1P`, `AN_Zipwire_Travel[_Start]_1P`)
  exist in the manifest and parse through the same path — available for later
  (disguise/zipwire states), not wired in this stage.

## Commands run (exit codes)
- `flatpak run org.godotengine.Godot --headless --path game --script res://tests/_tmp_fp_arms.gd`
  - before changes: 10 fails (RED, exit 1)
  - after changes: 14/14 PASS, SUMMARY: fails=0 (exit 0); one intermediate
    run had 13/14 (position-only comparison) before the rotation-aware fix.
- `flatpak run org.godotengine.Godot --headless --path game --script res://tests/_tmp_fp_dbg.gd`
  (one-off diagnostic, exit 0; deleted).
- `flatpak run org.godotengine.Godot --headless --path game --script res://tests/run_tests.gd`
  — 20/20 PASS, SUMMARY: fails=0, exit 0, zero `SCRIPT ERROR`.

## Self-audit notes
- Touched only the two allowed production files + temp probes + this report;
  `run_tests.gd`, `guard_ai.gd`, `level_loader.gd`, `mission_controller.gd`,
  parsers, extractor, Makefile, Android files untouched.
- No TODOs/stubs/mocks introduced; failure paths return false and fall back.
- Open: headed visual confirmation (1–3 above) still needs a human with a GPU
  run; the ObjectDB/resource warnings at headless exit are pre-existing
  teardown noise, not errors.
