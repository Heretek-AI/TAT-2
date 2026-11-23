# E2E baseline (unmasked)

Run: `timeout 2400 ./tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd`
Logs: before `/tmp/opencode/e2e_exact.log`; after `/tmp/opencode/e2e_afterfix.log`
(worktree at `1c009d9`).

| | before (fresh run) | after this pass |
|---|---:|---:|
| total | 256 | 256 |
| passed | 204 | 246 |
| failed | 52 | 10 |
| `[BOOT]` | 0 | 0 |
| `SCRIPT ERROR` | 0 | 0 |
| compile (`tools/check_scripts_compile.gd`) | 58 / 0 | 58 / 0 |

## Harness changes (no check deleted or skipped)

- `boot_problems()` — one-shot `[BOOT]` guard for `res://data/generated`,
  `res://assets/ue` and `<repo>/extracted/json`; a missing root prints one
  `[BOOT] missing <root>` cause plus one `[BOOT] FATAL` line and exits non-zero
  (`SUMMARY: fails=1`). Verified by running the suite with `game/data` moved
  aside: 2 `[BOOT]` lines, no per-check failures.
- `find_camera_env()` — prefers `Camera3D.environment` anywhere in the subtree
  (including inside the startscreen `SubViewport`) and falls back to
  `WorldEnvironment`; `find_env()` now delegates to it so every startscreen
  check reads the environment the camera actually renders.
- `force_authored_viewport()` — headless reports a 1280x1280 visible rect while
  the authored canvas is 1280x720; the runner now sets the root window to
  1280x720 so layout checks measure the target canvas.
- `viewmodel_contract()` — shared assertion for direct-to-camera 1P viewmodels:
  FP rig parented to the camera, zero per-player SubViewports, every viewmodel
  surface on the `vm_fov_deg` shader, no viewmodel shadow casters.
- `make_level_host()` — a level-controller stand-in exposing the same
  `light_probe` + smoke-AABB contract that `mission_controller` gives guards.

## Tier-2/3/4 IDs resolved on disk

- `T2-03-B/D`: startscreen reads the camera-bound Environment (volumetric fog,
  SSR, SSIL true); directional energy compared to the loader's authored
  `_build_light` value (0.45), not the pre-refactor 0.1 ceiling.
- `T2-05-A`: driven from `GameData.get_all_missions()` `icon_path`; only
  genuinely empty rows hide the icon, authored `ObjectiveDisplayImage` rows
  keep theirs.
- `T2-05-B`: fov (vs `LOBBY_CAM_FOV`) / `KEEP_WIDTH` / stage `1280x720` reported
  separately; stage viewport is the clip contract (root full-rect size was
  measuring the wrong 1280x1280 headless canvas).
- `T2-05-E`: FTUE `Mission.Tutorial.Single` duration 0 renders "Unlimited" and
  no "0 minute" string.
- `T2-08-C/D`: real UE manifest sprint clip (`AN_Sprint_F_1P`) — no `root`
  position track, rotation keys preserved.
- `T2-08-E`, `T3-08`, `T4-04`: real viewmodel seam (rig under camera, no
  SubViewport, `vm_fov_deg` on every surface, no shadow casters); the real 1P
  Zipwire GLB stays required.
- `T2-09-A/B/D`, `T3-02`, `T3-06`, `T4-05`/`T4-06`: real `equip_tool()` /
  `get_active_reticle_state()` / `_use_equipped_primary()` APIs.
- `T2-10-A`: zipwire 20 m boundary with the measured far/near distances.
- `T2-10-C`: drives `try_auto_mantle()` directly (the old setup let wall-climb
  solve the 5 m wall); rejects 5 m and accepts a 2 m control ledge.
- `T2-11-B`: typed `Array[Dictionary]` so `mission_controller.smokes` is live.
- `T2-13-B`: asserts `SoundWavesDraw.energy == 0` and `get_soundwave_intensity()`
  for zero-loudness noise (parent `visible` is not the render gate).
- `T2-14-C`: drives the real compass mapping; yaw 0/359/-180 yields N/N/E/S.
- `T2-16-A`: contract-1 empty intro goes through `request_mission_letter()` and
  emits a non-empty fallback body; HUD `show_mission_letter()` opens.
- `T2-16-D`: only top-level modal `PanelContainer`s are gated; scroll/content
  children are excluded.
- `T2-17-A`, `T4-02`: token bases asserted explicitly — GuildHall 0.24,
  OldManor `0.24 * (45.56192 / 27.39531)`, plus the 1.15x selection growth.
- `T2-18-A/B/C`, `T4-07`: real `set_mission_objectives` /
  `update_objective_progress` / `mark_objective_done` /
  `are_all_objectives_complete`; explicit `set_item_*` ids do not double-count
  `set_main`.
- `T2-20-A`: `get_alert_state().state == "KNOCKED_OUT"` with a seeded carried
  item.
- `T3-03`: thrown smoke -> NoiseBus `"smoke"` tag -> guard LOS blocked through
  the settled cloud (sub-values logged).
- `T3-07`: guard lantern registered through `level_ctrl.light_probe`; probe
  rises to 0.258 (>0.10).
- `T3-11`: lamp placed inside the 1.5 m inhibitor radius.
- `T3-12`: seeded guard pocket, guard faced away from the player for the steal
  check; stolen item leaves `has_carried_item() == false`.
- `T3-13`: resolved `CT_LockpickDamage` curve (40 at Lv4) plus container
  minigame track, not a literal in `loot_container.gd`.
- `T3-14`: FOV expected from `thief_character.CAMERA_FOV` (clamped to the
  slider); world camera syncs to it and the viewmodel keeps its authored
  `FP_VM_FOV_DEG` lock. Compatible with the pending 54.54 vertical-FOV commit.
- `T3-17`: locked vault minigame track + real objective completion.
- `T3-18`: **wired the real feature**: HUD now loads
  `T_compass_verticality_arrow.png` and shows an up/down arrow on compass PoIs
  above/below the player (`hud.gd`), asserted with above/below ping pongs.
- `T4-02`: `DenMapTableArea` (not `*MapTableCard*`).
- `T4-03`: MissionPrep FOV asserted from `LOBBY_CAM_FOV` (20.0) + `KEEP_WIDTH`,
  not the old 11.33 vertical.
- `T4-05`: `carries_lantern` + `enable_lantern()`.
- `T4-06`: real `disguise_ttl` so the disguise survives the lockpick journey.

## Remaining failures — exact IDs, category, reason deferred

| ID | Failure (after log) | Category | Why deferred |
|---|---|---|---|
| T1-02-E | safe-room spot energy 0.588 (test expects 0.3333) | stale tier-1 expectation | `e2e_tier1_features.gd` is frozen for this pass; value is the loader's current authored mapping (same class as T2-03-B, already fixed in tier 2). |
| T1-03-B | startscreen `env=false` | stale tier-1 timing | Tier 1 waits 2–3 frames; `main_menu._bind_menu_env()` binds the camera Environment after 12 frames. `find_env` now prefers the camera env, but the frozen tier cannot wait longer. Owned by the startscreen env worker. |
| T1-03-C | `volumetric_fog_enabled=false` | same as T1-03-B | Frozen tier-1 timing; env is true once bound (T2-03-D/T3-09/T4-01 pass). |
| T1-04-C | MainMenu SSR `false` | same as T1-03-B | Frozen tier-1 timing; T3-09/T4-01 assert SSR/SSIL on the same camera env and pass. |
| T1-08-D | `reset_bone_poses()` still present | genuine M3 player-anim gap | Product change in `thief_character.gd` (not owned here); stationary idle must hold without resetting the skeleton. |
| T1-10-B | cable not persistent during grapple | M3 zipwire state machine | Covered by the pending `fix(camera+zipwire)` work (cable hang/crank state machine); tier 1 is frozen here. |
| T1-11-D | smoke trajectory arc preview inactive | genuine M3 tool gap | Trajectory preview is not wired in the frozen tier-1 scenario. |
| T1-11-E | Slithersap raycast puddle 0→0 | genuine M3 tool gap | No `RigidBody` puddle spawn on the immediate raycast path. |
| T1-17-C | token `scale.x == 0.24` | stale tier-1 expectation | Same authored token change as T2-17-A/T4-02 (OldManor now the UE ratio); tier 1 is frozen. |
| T3-20 | stationary disguise 1P clip is `AN_ThiefNisha_Zipwire_StandIdle` | genuine M3 anim gap | The UE 1P set has disguise walk/sprint/crouch/crouch-idle clips but no stationary disguise idle; the state machine correctly falls through to the tool idle. HUD vignette passes. Needs an authored/approved disguise idle clip, not a test change. |

## Rules for closing

- A failure is fixed only when the **on-disk** assertion passes without patching
  the runner and without deleting/weakening a check.
- Tier-1 rows marked "stale tier-1 expectation/timing" close when the frozen
  tier-1 file is reopened by its owner (or when the startscreen env binds before
  the tier's 2–3 frame sample).
- Genuine M3/M4/M6 rows close with the milestone that owns the system.
- The suite must keep `[BOOT] == 0` and `SCRIPT ERROR == 0`; a new boot/parse
  failure is a blocker, not a baseline entry.

## Next re-run

Re-run all tiers after the 54.54 vertical-FOV + zipwire cable commit lands and
after the startscreen env binding settles; drop the resolved rows. The remaining
assertions are constant-driven, so they survive the FOV default change.
