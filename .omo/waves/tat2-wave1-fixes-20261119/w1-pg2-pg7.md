# W1 PG-2 / PG-7 / PG-4 - gameplay, HUD & parity fixes

Date: 2026-11-19
Lane: w1-pg2-pg7-gameplay (deep-low)
Write scope: `game/src/ai/guard_ai.gd`, `game/src/player/thief_character.gd`, HUD, `game/src/interact/`, zipwire/crank wiring, guard locomotion.

Live capture was **not** run here (Wave 3 owns `capture_e2e_parity.sh`). Every S-check
below was replayed with a temporary headless probe (`build/qa/parity_probe.gd`, deleted
after the run) that executes the same predicates as `build/qa/capture_e2e_parity.gd`.

## Verification (this run)

### `make test`

Command: `cd /home/john/Projects/TAT-2 && make test` -> exit 0.

Tail:

```text
PASS: 43 zipwire crank AN_ThiefNisha_Zipwire__Reload_Loop resolves via ensure_fp_clip and plays on crank
PASS: 44 triage locks (outline/reticle/lockpick/arms/vm/loco/crank/toggle/lantern/steal/stealth/visreg)
PASS: 45 stairs snap (max_angle 50 deg, snap 0.3 m, wall-block/constant-speed kept, stair slope 32.7 deg walkable, 55 deg blocked, no new mantle)
PASS: 46 Den doors leaf disabled past 70 deg (layer 0 + disabled, re-enabled on close) & window wall split gap=0.95m + sill + lintel (2m marker gate kept)
SUMMARY: fails=0
WARNING: 28 ObjectDB instances were leaked at exit (run with --verbose for details).
ERROR: 7 resources still in use at exit (run with --verbose for details).
ERROR: 6 RID allocations of type 'N17RendererSceneCull8InstanceE' were leaked at exit.
```

- `SUMMARY: fails=0` (log line 923), 46 suites / 90 PASS lines.
- `SCRIPT ERROR` count: **0** (`grep -c 'SCRIPT ERROR'` -> 0).
- Exit-time ObjectDB/RID leak warnings are the known harness noise already recorded in
  `w0-test.md`; they do not fail the gate.

### Headless Tier-1 E2E

Command:
`flatpak run org.godotengine.Godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=1`

```text
PASS: [T1-07-A] 1P Zipwire real GLB loaded from Art/Gameplay/Gear (true)
PASS: [T1-07-B] 1P SmokeBomb=true Slithersap=true real GLBs
PASS: [T1-07-C] 1P BlackJack=true Fairy=true VistaraDiamond=true
PASS: [T1-07-D] 1P tool GLB binds authored PBR texture/material (true)
PASS: [T1-07-E] fp_tool_root child count after switches=1 (expected 1)
FAIL: [T1-08-A] 1P arms SK_ThiefNisha__BodyUpper PBR bound (false)
PASS: [T1-08-B] 1P clips loco=true tool_clips=true count=4
PASS: [T1-08-C] disguise_anim=true zipwire_anim=true
PASS: [T1-08-D] stationary idle holds pose without reset_bone_poses() (reset_found=false)
PASS: [T1-08-E] 1P viewmodel SubViewport/layer isolation (false)
...
PASS: [T1-21-D] OldManor spawn headroom=true forward=true
PASS: [T1-22-E] Steam refs=56 (>=56) & capture_e2e_parity.gd present=true
SUMMARY: fails=1 passed=109 total=110
```

`T1-08-A` is **not caused by this lane** (see Open items): the PG-1 texture cap added to
`level_loader.gd` wraps the 4096x4096 `T_ThiefNisha_Top_D.png` in an `ImageTexture`
with an empty `resource_path`, and the tier-1 check reads `albedo_tex.resource_path`.
Pre-wave-1 logs (`/tmp/e2e_tier1_now.log:56`, `/tmp/ulw-w1-e2e-tier1.log:56`) show
that check PASS; `make test` is unaffected. Every check owned by this lane passes.

### Parity probe (same predicates as the live capture)

```text
PROBE S04 clipped=0 []
PROBE S04 turntable=true
PROBE S06 cams=["MissionLobbyCamera fov=20.000 keep=0"] has_fov20=true lobby=true
PROBE S03 ready=true hud=true has_set_card=true tokens=2 named_card=false den_card=true
PROBE S11 ready=true player=true hud=true equipped0=zipwire
PROBE S11 equipped_after_tool1=zipwire has_slots=true has_reticle=true
PROBE S11 fallback_zipwire_body=false
PROBE S14 guards=6 hud_alert_method=true
PROBE S14 guard_alert_state=true raw={ "state": "SUSPICIOUS", ... }
PROBE S14 guardpip=true offscreen=true
PROBE PROMPT primary=[F] PICK POCKET secondary=[F] [HOLD] TAKEDOWN
PROBE HUD secondary_lbl=[F] [HOLD] TAKEDOWN visible=true
PROBE HOLD guard_state=5 takedowns=1
PROBE DOOR secondary=[F] [HOLD] LOCK locked0=false
PROBE DOOR after_hold locked=true level=1 secondary2=
PROBE S15b has_open=true has_start=true wheel=false arc=false dial=true
PROBE PAUSE buttons=["RESUME", "SETTINGS", "RETURN TO THIEF'S DEN", "QUIT TO DESKTOP"] footer=1.5.148559   Novice   721384951
PROBE_DONE
```

## PG-2 - the seven live parity fails

The working tree already carried partial fixes for S03/S14/S15b (HUD aliases) and most
PG-7 HUD work when this lane started. Each was re-verified against the capture predicate;
the remaining gaps were closed in this lane.

| Check | Capture predicate | Result | Evidence |
|---|---|---|---|
| S03 `map_table_look_at_card` | `hud.has_method("set_map_table_card")` or a `MapTableCard` node | PASS | `hud.gd:1814` alias -> `set_den_lookat_card`; card node `DenLookAtCard` (`hud.gd:1201-1212`); mission pushes it (`mission_controller.gd:799-800`); probe `has_set_card=true tokens=2 den_card=true` |
| S04 `clipped_controls` | no visible Button/PanelContainer outside 0..1284 x 0..724 | PASS | probe `clipped=0 []`, `turntable=true` (wardrobe layout is owned by another lane; verified, not edited) |
| S06a / S06b `mission_lobby_fov_20` | a Camera3D descendant with `abs(fov-20)<=2.5` | PASS | `mission_prep_ui.gd:54` `LOBBY_CAM_FOV=20.0`, `:404-405` `fov=20` + `KEEP_WIDTH`; probe `fov=20.000 keep=0` (0 = KEEP_WIDTH). A direct Camera3D probe confirmed `.fov` reads back the set value under KEEP_WIDTH, so 20.0 is the horizontal FOV and ~11.33 is only the rendered vertical |
| S11 `equipped_tool!=zipwire` | `get_equipped_tool()=="zipwire"` after `tool_1`, no `ZipwireBody` fallback | PASS | `thief_character.gd:556-557` `tool_1 -> equip_tool("zipwire")`; probe `equipped_after_tool1=zipwire`, `fallback_zipwire_body=false`, slots/reticle methods present |
| S14 `guard_pips_and_offscreen_arcs` | `GuardPip*` or `Offscreen*` node under the HUD; guard `get_alert_state` + lantern light | PASS | `hud.gd:2520` `GuardPip_%d`, `:2533` `OffscreenArc_%d`; `guard_ai.gd:1027` `get_alert_state`; probe `guardpip=true offscreen=true`, `get_alert_state={...}` |
| S15b `circular_lockpick_minigame_ui` | `open_lockpick_minigame` method or `LockpickWheel/LockpickArc` node | PASS | `hud.gd:1770` `open_lockpick_minigame`; `LockpickMinigameOverlay`/`LockpickDial` (`hud.gd:1255/1310`); probe `has_open=true dial=true` |

No live PNG capture was produced in this lane (Wave 3 re-runs
`bash build/qa/capture_e2e_parity.sh --strict`).

## PG-7 - gameplay / HUD polish

- **Light Gem (UI3):** the bottom-centre gem mask is now a cut **diamond**
  (`abs(x)+abs(y)` metric, diamond rim) instead of a sphere; the warm directional sector
  and exposure shading are preserved (`hud.gd:56-77`, `STEALTH_ORB_SHADER`). The
  player publishes the strongest-light direction/strength at 4 Hz
  (`thief_character.gd:630` `_refresh_light_sector`), and the HUD maps it to the
  sector angle.
- **Player noise arcs (UI5):** `_on_noise_emitted` only accepts noise whose source is in
  the `player` group (guards/doors cannot drive the arcs) and ignores zero-loudness
  events; `SoundWavesDraw` renders concentric red arcs flanking the gem
  (`hud.gd:234-268, 2880-2895`).
- **Guard alert pips (UI5):** on-screen overhead pips are red for alerted/combat and
  green for suspicion/warning; the off-screen directional arcs now use the same red/green
  scheme (previously yellow/orange) (`hud.gd:2495-2535`).
- **Pause menu (KF30):** `RESUME`, `SETTINGS`, `RETURN TO THIEF'S DEN` (straight
  apostrophe), `QUIT TO DESKTOP`, plus the bottom-left `<build>   <difficulty>   <seed>`
  footer (`hud.gd:1592-1655`). The label is kept **clip-exact** as `QUIT TO DESKTOP`
  (CALLOUT_LEGENDS KF30 rows 2-3); the task's `QUIT` names that entry.
- **1P ZipWire viewmodel:** real 1P tool GLB + launch (`zipwire_cast`), loop crank
  (`AN_ThiefNisha_Zipwire__Reload_Loop`), idle/walk/sprint/travel roles
  (`thief_character.gd:1001`; `animation_library.gd:79-86`); `make test` PASS 43.
- **Blue double doors (KF24):** closed unlocked doors now expose the stacked
  `[F] [HOLD] LOCK` secondary under `[F] OPEN`, and holding F locks the door
  (`swinging_door.gd:222-236`, `lockable_door.gd:301-316`). `[F] CLOSE` appears once open.
- **Pickpocket / takedown (KF25/KF26):** guard prompts are clip-exact
  `[F] PICK POCKET` (`guard_ai.gd:1160/1187`); the HUD stacks
  `[F] [HOLD] TAKEDOWN` beneath it (`hud.gd:1062-1085`, `thief_character.gd:1328`);
  holding F for 0.45 s runs the blackjack takedown (guard knockdown clip +
  `GameState.takedowns`, `thief_character.gd:540-552, 1340-1348`); a circular
  hold-progress arc is drawn around the reticle (`hud.gd:312-319`). Probe: guard
  `state=5` (KO), `takedowns=1`.
- **Guard foot-slide:** locomotion playback is driven by
  `velocity.length() / clip ground speed`, clamped and eased, with attack/slip/KO
  resetting `speed_scale=1` (`guard_ai.gd:27-33, 382-392`). Verified present in the
  file and green through `make test`; no code change was needed beyond the prompt strings.

## PG-4 - live-confirm prep

No new code is needed for the three Phase-4 mechanics; they are already asserted headlessly
and only need the Wave-3 live replay:

| Mechanic | Headless evidence | Live replay |
|---|---|---|
| ZipWire crank clip playback | `make test` PASS 43 (clip resolves via `ensure_fp_clip`, plays on crank) | S11 `parity_1p_zipwire_crank.png` |
| Stairs snap 0.3 m / 50 deg | `make test` PASS 45 | Guildhall/Den traversal capture |
| Swinging door 70 deg leaf disable + Den 0.95 m window gap | `make test` PASS 46 | Den door close-up capture |

## Files changed (this lane)

| File | Reason |
|---|---|
| `game/src/ui/hud.gd` | Diamond Light Gem mask; stacked secondary prompt label + per-frame poll; reticle hold-progress arc; red/green off-screen alert arcs; removed the misleading `Pick Lock -> [HOLD] LOCK` remap now that HOLD LOCK is a real secondary action |
| `game/src/player/thief_character.gd` | Hold-F secondary interact (takedown / door lock) with `HOLD_INTERACT_SEC`; `get_look_secondary_prompt()`; `interact_hold_progress` for the reticle arc; `PICK POCKET` hint label |
| `game/src/ai/guard_ai.gd` | Clip-exact `[F] PICK POCKET` prompt on the guard and its carried-item proxy (file also carries the pre-existing foot-slide rate matcher, verified here) |
| `game/src/interact/swinging_door.gd` | `get_interact_secondary_prompt()` + `interact_hold()` for `[F] [HOLD] LOCK` |
| `game/src/interact/lockable_door.gd` | Same `[F] [HOLD] LOCK` secondary/hold for the legacy lockable door |
| `build/qa/parity_probe.gd` | Temporary headless parity probe that produced the evidence above; deleted after the run |

Files readable but not written here include `mission_controller.gd`, `project.godot`,
`level_loader.gd`, `weather_visuals.gd`, `mobile_profile.gd`, audio, `main_menu.gd`,
shaders and `run_tests.gd`.

## Open items / assumptions

1. **T1-08-A cross-lane regression (not this lane):** `level_loader.gd`'s PG-1
   `_cap_texture` returns `ImageTexture.create_from_image(...)` for the 4096x4096
   `T_ThiefNisha_Top_D.png`, so `albedo_tex.resource_path` is empty. The tier-1 check
   reads that path. Suggested owner fix: `out.take_over_path(res_path)` on the capped
   texture (or check `use_albedo_tex` instead). `T_ThiefNisha_Body_D.png` is 2048 and
   is not capped, which is why only surface 0 (Top) trips the check.
2. **Stale tier-4 FOV expectation:** `game/tests/e2e/e2e_tier4_scenarios.gd:107` still
   expects `cam.fov == 11.33`, while the capture and T1-05-B require 20.0 with
   `KEEP_WIDTH` (rendered vertical ~11.33). Not part of tier-1; needs the e2e owner.
3. **Pause quit label:** kept `QUIT TO DESKTOP` because that is the clip-exact KF30
   string; the task's four-item list calls that entry `QUIT`.
4. **Live capture:** deliberately not run by this lane. Wave 3 should run
   `bash build/qa/capture_e2e_parity.sh --strict` and expect 21/21 with the predicates
   above.
