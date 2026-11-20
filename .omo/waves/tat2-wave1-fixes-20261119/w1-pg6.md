# Wave 1 · w1-pg6 — Full audio runtime parity (PG-6)

Date: 2026-11-19
Scope: `game/src/core/audio_manager.gd`, `game/src/core/save_system.gd`, `game/src/stealth/noise_bus.gd`, `game/data/generated/audio_library.json`, `game/data/generated/audio_events.json`, `game/src/ui/settings_ui.gd` (slider routing), plus audio-only call sites in UI/player/AI/interact/missions scripts.

Result: PG-6 runtime is wired end to end against `KEYFRAME_INDEX.md` §4 and `BREAKDOWN.md`. `make test` passes with `SUMMARY: fails=0`, zero `SCRIPT ERROR`, exit 0. Prior claims of "138 events / 24 verified tags" were re-checked from the files and corrected below.

---

## 1. Bus architecture (runtime-verified)

`AudioManager._ensure_buses()` creates six buses once at startup; all added buses route to `Master` by default.

| Index | Bus | Fed by | Notes |
|---|---|---|---|
| 0 | `Master` | all buses | master slider + global output |
| 1 | `Music` | diegetic gramophone only | no score BGM anywhere; S07 gramophone is the only source |
| 2 | `SFX` | 3D one-shots (`AudioStreamPlayer3D`) | footsteps, tool/impact cues, NoiseBus mirrors |
| 3 | `Ambience` | 2D looped beds (`AudioStreamPlayer`) | S27 pause duck applied on top of the saved level |
| 4 | `UI` | 2D UI cues | hover/click/confirm/back/tab/open/purchase/error/countdown |
| 5 | `Dialogue` | VO (2D or 3D) | guard barks, mission intro |

Runtime probe output:

```
BUS Master index=0
BUS Music index=1
BUS SFX index=2
BUS Ambience index=3
BUS UI index=4
BUS Dialogue index=5
```

Volume routing: `settings_ui.gd` sliders (`master_volume`, `music_volume`, `sfx_volume`, `ambience_volume`, `ui_volume`, `dialogue_volume`) → `SaveSystem.apply_saved_settings()` → `AudioManager.apply_volumes()` → per-bus `AudioServer.set_bus_volume_db`. Old saves are backfilled (`_ensure_defaults` adds `ambience_volume`/`ui_volume`/`dialogue_volume` from the SFX value). Saved sliders are never clobbered by the pause duck: `_bus_linear` caches the slider level and `_apply_bus_level()` re-applies it with the transient offset.

S27 pause duck (AU4-05): `AudioManager` runs `PROCESS_MODE_ALWAYS`; when `SceneTree.paused` flips, Ambience is driven `-19 dB` and restored on resume. Runtime probe:

```
AMB_DB base     -1.93820023536682
AMB_DB paused  -20.9381999969482
AMB_DB restored -1.93820023536682
```

---

## 2. Ambience beds per scene (AU1/AU2)

Bed levels are intrinsic (bus at 0 dB) and derived from the measured whole-loop RMS of each decoded Ogg: `trim = target_dbfs - clip_rms_db`. User volume/master sliders scale from that reference.

| Scene | Bed key | Pin (event → media) | Clip RMS | Trim | Target dBFS | Trigger |
|---|---|---|---|---|---|---|
| S01 Startscreen | `rain` | `Play_Amb_Weather_Rain_Impact_Puddle_Loop` → `Amb_Weather_Rain_Impact_Puddle_Loop_Sml_03.wav` | -45.7 | -5.3 | **-51.0** (doc -53…-49) | `_autostart_scene_bed()` when `main_menu.tscn` is current |
| S02 Loading 1 | — | — | — | — | silence | `loading_screen.start_loading()` → `stop_all_beds(0.35)` |
| S03–S08 Thieves' Den | `den` | `Play_Amb_ThievesDen_Interior_Small_Room` → `Amb_Interior_Residence_02_Loop_Sml_02.wav` | -34.1 | -40.4 | **-74.5** (doc -76.3…-73.1) | `mission_controller` → `play_bed_scene("thieves_den")` |
| S07 Gramophone | `Music` | `Play_Mus_Source_WindowLife_Random_Playlist_All` → `Mus_Source_Phonograph_FX_Piano_Sonatina_Loop_01.wav` | -23.3 | -18.2 | **~-41.5 RMS** (doc -40…-45), peak ~-21.1 | `toggle_gramophone()` from the Den `[F] TURN ON/OFF` interactable |
| S05 PONDER sky view | `wind` | `Play_Amb_AbbotsfordPark_Exterior_Rooftops` → `Amb_Wind_Gust_Loop_V1_03.wav` | -31.9 | -7.5 | **-39.4** | `start_bed("wind")` API; no call site exists in an editable file (telescope is built in `mission_controller.gd`) |
| S09 Mission Prep | `wind_prep` | same wind clip | -31.9 | -26.1 | **-58.0** (doc -64…-52) | `mission_prep_ui.open_prep()`; stopped in `_exit_tree` |
| S10 Loading 2 | — | — | — | — | silence | `loading_screen.start_loading()` |
| S11–S21 Guildhall exterior | `rain` + `guildhall` | rain above + `Play_Amb_Int_RoomTone_A` → `Amb_Int_RoomTone_A.wav` | -45.7 / -32.8 | -5.3 / -31.2 | **-51.0** + **-64.0** | `play_bed_scene("guildhall")` (layered safe-room tone under the continuous rain) |
| Interior foyer/parlor | `roomtone` | same room-tone event (API) | -32.8 | -28.7 | **-61.5** | available via `start_bed("roomtone")`; no door trigger in an editable file |
| S27 Pause Menu | — | — | — | — | ambience **-19 dB** duck | `SceneTree.paused` transition in `AudioManager._process()` |

Explicit BGM absence: the `Music` bus has exactly one producer, `_gramophone_player`. `fire_event()` can route `Play_Mus_*` names to Music, but it has no call sites. No scene starts a Music player. Loading screens stop every bed and the gramophone.

Notes/limits: the Guildhall bed plan is scene-granular (rain + room tone layered for S11–S26). The reference's per-door outdoor→sheltered crossfade at `03:01` is not triggered because the door/mission scripts that would own the transition are outside this task's write scope. The S05 PONDER wind swell is implemented but has no trigger for the same reason.

---

## 3. Surface footsteps (AU3)

`AudioManager._build_footstep_pools()` builds round-robin pools from `audio_events.json` media for `Play_FS_Player_{Walk,Run,Jog,Crouch}` keyed by `gait|surface`; `_scene_surface()` resolves wood/stone/wet by map + a ceiling probe (Den = wood, Guildhall = wet outdoors / stone indoors, Manor = stone outdoors / wood indoors). Crouch/jog fall back across gaits when a surface family is absent, then across surfaces, so a single fixed clip is never returned.

Runtime pool sizes (verified from the JSON):

| Gait | wood | stone | carpet | metal | wet | earth | glass |
|---|---|---|---|---|---|---|---|
| walk | 18 | 8 | 7 | 25 | 25 | 26 | 15 |
| run | 36 | 12 | 20 | 64 | 33 | 32 | 15 |
| jog | 10 | 10 | 10 | — | 17 | 18 | 15 |
| crouch | — | — | — | — | 17 | 18 | 15 |

`_foot_pools` holds 23 populated pools; a six-draw walk-on-wood probe returned six distinct Oggs:

```
WOOD_DRAWS ["res://assets/ue/audio/wwise/289341983.ogg", "res://assets/ue/audio/wwise/289467836.ogg",
            "res://assets/ue/audio/wwise/289489396.ogg", "res://assets/ue/audio/wwise/289551305.ogg",
            "res://assets/ue/audio/wwise/289948908.ogg", "res://assets/ue/audio/wwise/289960723.ogg"]
WOOD_DISTINCT 6/6
```

Call site: `thief_character.gd:916` calls `play_footstep(_audio_surface(), _audio_gait(), global_position)` on the step cadence; `NoiseBus` also emits the `footstep` stimulus for AI, and `AudioManager._on_noise_emitted` deliberately skips mirroring `footstep` so the single fallback clip cannot double/defeat the variation pools.

---

## 4. UI wiring (AU4)

| UI | Cues | Call sites |
|---|---|---|
| Main menu | PLAY click | `main_menu.gd:395` (pre-existing; file excluded) |
| Settings | open / back / tab click | `settings_ui.gd:108,113,122` |
| Settings volume | master/music/SFX/ambience/UI/dialogue sliders → all six buses | `settings_ui.gd:590-620` → `SaveSystem.apply_saved_settings()` |
| Wardrobe | open latch, back, hover ticks (all buttons), thief cycle / tool / head / body / card selection ticks | `wardrobe_ui.gd:93,103,110,490,533,577,586,595` |
| Ledger / Black Market | ledger open, tab switch, item click, purchase chime / error, back, hover ticks | `ledger_ui.gd:85,97,273,445,454,468` |
| Mission Prep | open, back, hover, mission-row click, READY confirm | `mission_prep_ui.gd:89,102,114,141,622` |
| Map Table / contract selector | open, back, contract select, difficulty click, `[H]`/`[R]` toggles, host/join confirm·error, modal confirm, cancel, hover | `contract_table_ui.gd:48,54,490` + handlers |
| HUD pause | pause open, resume/back | `hud.gd:1864,2890` (pre-existing; file excluded) |
| Countdown (S09) | 6 × 1.00 s ticks | `AudioManager.start_countdown()` from `mission_controller.gd:210` |

`AudioManager.wire_hover_sfx(root)` recursively connects `mouse_entered` on every `BaseButton` once, so S04/S08 metallic hover ticks do not need per-control plumbing.

---

## 5. Gameplay SFX wiring (AU5)

| Cue | Call site | Status |
|---|---|---|
| Smoke bomb throw/cast | `smoke_projectile.gd:52-54` → `play_cue("smoke_cast")` | real Wwise clip |
| Smoke detonation hiss/cloud | `smoke_projectile.gd:159-161` → `play_cue("smoke_cloud")` | real Wwise clip |
| Bottle smash | `thrown_bottle.gd` → `NoiseBus "bottle"` → `_sfx["bottle"]` | real clip |
| Door open/slam | `swinging_door.gd` / `lockable_door.gd` → `NoiseBus "door"` | real clip |
| Lockpick / jam | `lockable_door.gd`, `loot_container.gd`, `hud.gd` → `NoiseBus "lockpick"/"lockpick_jam"` | real clip |
| Loot / clue pickup | `clue_item.gd`, `loot_item.gd` → `NoiseBus "clue"/"loot"` | real clip |
| Zipwire | `thief_character.gd` emits `NoiseBus "wire"` → `grapple` clip | mirror only; dedicated `zipwire_launch/attach/crank/detach` cues resolve but the player file is excluded from this pass |
| Pickpocket / Takedown | `thief_character.gd` emits `NoiseBus "takedown"/"fairy"/"pickpocket_spotted"` | mirror only; dedicated `pickpocket_success/fail`, `takedown_impact` resolve but the player file is excluded |
| Car horn | `play_car_horn()` API + real clip verified | no car interactable exists to call it |
| Ward activate/hit/end, light beam trip/hum, alarm loop, jaw-trap | `EXTRA_PINS`/`CUE_PINS` resolve to real clips | no gameplay system/call site exists in `game/src` (mission_controller excluded) |

`NoiseBus` tags mirror to 3D SFX through `_on_noise_emitted` (`takedown/slithersap/ko/melee → blackjack`, `wire/rope → grapple`, `moth/chime/vision/disguise → fairy`, `spotted/alert/whistle/hunt → alert`, `pickup/coin/steal/clue → loot`, `bottle/smash/shatter → bottle`, `gate → door`, `lockpick_jam → lockpick`). The `footstep` tag is intentionally excluded to preserve AU3 variation.

---

## 6. VO wiring (AU6)

| Cue | Call site | Clip |
|---|---|---|
| Guard alert | `guard_ai.gd:477,486` → `play_vo("guard_alert", pos)` | `VO_Enforcer1_169_NoiseHeard_HighSeverityNoiseSearching_18.wav` |
| Guard search / lost target | `guard_ai.gd:920` → `play_vo("guard_search", pos)` | `VO_Enforcer1_10_ThiefObserved_LostTargetToPatrol_02.wav` |
| Mission intro (ThiefNisha) | `mission_controller.gd:212` → `play_vo("fairy_intro")` | `VO_FairyTristan_597_Tutorial_Intro_01.wav` |
| Guard suspicion (low severity) | no call site in an editable file | clip resolves (`guard_suspicious`) |
| Post-KO / smoke-reaction barks | no per-line Wwise subtitles exist; KEYFRAME §4 is bandpass-resolved VO, not a line map | functional cues used |

VO plays on `Dialogue`, 3D when a position is supplied (guards), 2D for the mission intro.

---

## 7. Asset/event reality check (prior claims corrected)

- Decoded Wwise library: **5,018/5,018 OGG files exist**; `audio_library.json` records `clips: 5018`, `failed: 0`, total duration `39,222.2 s` (10.9 h).
- `audio_events.json`: **1,296 events**; **1,205** have at least one media row whose Ogg exists; **33 tags**, all `status: "verified"` (not 24).
- The 91 events without a usable clip are convolution/IR assets (`AK_Factory_IR\...`, `AudioEase Altiverb ...`, `BOOM Library IR ...`) with `clip: null`; they are not playable game cues.
- Runtime pin audit: **43/43 pins resolve** to an existing Ogg (43 = EXTRA_PINS 17 + CUE_PINS 14 + BED_PINS 6 + VO_PINS 4 + countdown + gramophone).
- Runtime coverage: pins reference **41 distinct Wwise events** (the wind/wind_prep and roomtone/guildhall pairs share events); plus the 4 footstep gait events = **45 events**, reaching **330 distinct decoded clips** (pin clips + footstep media). The "138 events wired" figure is not supported by the files and is not repeated here.
- Headless instantiation probe: **31/31** probed named clips (`has_real_clip`) returned true, including every UI cue, both beds, gramophone, countdown, all VO cues, and all SFX tags.

---

## 8. Verification

Command: `cd /home/john/Projects/TAT-2 && make test`

Audio/adjacent suites in the run:

```
PASS: AudioManager autoload active
PASS: LedgerUI, MissionPrepUI, ArtNouveauTheme, SaveSystem progression & Footprint/Wisp VFX verified
PASS: 35b Settings teal theme, 6 grouped cards, persisted values wired into ThiefCharacter
PASS: 35c Mission Prep loaded all 11 CDT_Missions rows with real artwork, icons & preview PBR
```

Tail:

```
PASS: 43 zipwire crank AN_ThiefNisha_Zipwire__Reload_Loop resolves via ensure_fp_clip and plays on crank
PASS: 44 triage locks (outline/reticle/lockpick/arms/vm/loco/crank/toggle/lantern/steal/stealth/visreg)
PASS: 45 stairs snap (max_angle 50 deg, snap 0.3 m, wall-block/constant-speed kept, stair slope 32.7 deg walkable, 55 deg blocked, no new mantle)
PASS: 46 Den doors leaf disabled past 70 deg (layer 0 + disabled, re-enabled on close) & window wall split gap=0.95m + sill + lintel (2m marker gate kept)
SUMMARY: fails=0
WARNING: 28 ObjectDB instances were leaked at exit (run with `--verbose` for details).
ERROR: 7 resources still in use at exit (run with `--verbose` for details).
ERROR: 6 RID allocations of type 'N17RendererSceneCull8InstanceE' were leaked at exit.
MAKE_TEST_EXIT=0
```

`SCRIPT ERROR` count in the full log: **0**. The exit-time `ObjectDB`/resource/RID warnings are non-gating engine cleanup notices of the same category present in the pre-change baseline; no test failed and no script failed to compile.

Additional headless runtime probes (same build, no test harness):

```
BED_TARGET rain -51.0
BED_TARGET den -74.5
BED_TARGET roomtone -61.5
BED_TARGET wind -39.4
BED_TARGET guildhall -64.0
BED_TARGET wind_prep -58.0
CLIP_SUMMARY 31/31
FOOT_POOLS 23
WOOD_DISTINCT 6/6
RAIN_START true
ACTIVE_BEDS {"rain":{"bus":"Ambience","target_dbfs":-51.0,"volume_db":-5.30000019073486}}
AMB_DB base -1.93820023536682
AMB_DB paused -20.9381999969482
AMB_DB restored -1.93820023536682
```

---

## 9. Files changed in this pass (with reasons)

1. `game/src/core/audio_manager.gd`
   - Measured bed trims (`BED_CLIP_RMS_DB`/`BED_TRIM_DB`) so rain lands at -51.0 and the Den at -74.5 intrinsic dBFS.
   - Added the S09 `wind_prep` bed (-58.0 dBFS, -64…-52 doc range).
   - Added S27 pause duck on the Ambience bus (-19 dB, saved level preserved through `_bus_linear`/`_apply_bus_level`).
   - Added `wire_hover_sfx()` for one-call recursive UI hover routing.
2. `game/src/ui/mission_prep_ui.gd`
   - Start/stop the S09 rooftop wind bed with the prep screen lifecycle; READY confirm cue; mission-row selection tick; hover wiring.
3. `game/src/ui/contract_table_ui.gd`
   - Map Table audio: open/back, contract select, difficulty/mode toggles, host/join confirm·error, modal confirm/cancel, hover wiring.
4. `game/src/ui/ledger_ui.gd`
   - Hover wiring for ledger/Black Market buttons (open/tab/item/purchase/error/back already existed).
5. `game/src/ui/wardrobe_ui.gd`
   - Hover wiring plus selection ticks for thief cycle, tool, head, body and calling-card controls.

No forbidden file was edited in this pass (`mission_controller.gd`, `project.godot`, `level_loader.gd`, `weather_visuals.gd`, `main_menu.gd`, shaders, `guard_ai.gd`, `thief_character.gd`, HUD files untouched).

Working-tree note: `git diff` also lists pre-existing/concurrent wave changes outside this task (for example `project.godot`, `guard_ai.gd`, `level_loader.gd`, `hud.gd`, `main_menu.gd`, `thief_character.gd`, `settings_ui.gd`, `loading_screen.gd`, `smoke_projectile.gd`, `vfx_manager.gd`, `lockable_door.gd`, `swinging_door.gd`). Those were present before or added alongside this pass and are not part of the w1-pg6 edit set above.

## 10. Pre-existing PG-6 wiring verified, not modified this pass

- `game/src/core/save_system.gd` — `apply_saved_settings()` pushes all six bus volumes (including ambience/UI/dialogue) and backfills old saves.
- `game/src/stealth/noise_bus.gd` — `noise_emitted` signal + seven surface tags; AudioManager connects it.
- `game/src/ui/settings_ui.gd` — ambience/UI volume sliders already added and wired through `SaveSystem`.
- `game/src/ui/loading_screen.gd:199` — stops all beds on loading (S02/S10 silence).
- `game/src/player/thief_character.gd:916` — surface/gait footstep call.
- `game/src/ai/guard_ai.gd:477,486,920` — guard VO.
- `game/src/missions/mission_controller.gd:207,210,212,914` — scene beds, countdown, intro VO, gramophone toggle.
- `game/src/player/smoke_projectile.gd:52-54,159-161` — smoke cast/cloud cues.
- `game/project.godot` — `NoiseBus` and `AudioManager` autoloads.
- `game/src/ui/hud.gd`, `game/src/ui/main_menu.gd` — existing pause/menu click cues.

## 11. Remaining gaps / intentionally out of scope

- Guildhall outdoor→indoor bed crossfade at the S21 door is approximated by layering rain + room tone; the door trigger lives in files this task forbids editing.
- S05 PONDER wind bed is implemented but has no editable trigger (telescope is created in `mission_controller.gd`).
- Dedicated Zipwire/Pickpocket/Takedown cues resolve but are currently represented by the NoiseBus 3D mirrors because `thief_character.gd` is excluded.
- Ward/light-beam/alarm/jaw-trap/car-horn cues resolve to real clips but have no gameplay system/call site in `game/src` yet.
- `guard_suspicious` resolves but has no low-severity hook in an editable file.
- Hearth-crackle bed for S22 has no pinned loop in the event join; not synthesized.
- Quit-to-desktop digital-silence tail (S27 end) is not hooked; the pause duck is implemented, and the quit action is owned by HUD/main-menu files outside scope.
- Reference `-53…-49` / `-76…-73` dBFS ranges are matched as intrinsic bed levels (bus at 0 dB); user volume sliders scale from that reference, as a mix target should.
