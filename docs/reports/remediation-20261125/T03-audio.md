# T03 — AUDIO remediation report

Branch `rem/T03-audio`, worktree `<worktree>/T03-audio`.
Inputs: `findings/RE-M-audio.md` (RE-M-01…14), `findings/L5-audio.md` (AU1-01…AU6-05),
`REMEDIATION_PLAN.md` invariants S1–S6.

Owned files touched: `game/src/core/audio_manager.gd`, new
`game/src/core/audio_wwise.gd`, new `tools/parse_wwise.py`, new audio keys in
`game/data/expansion/audio_mix.json`, plus three test files
(`game/tests/test_audio_wwise.gd`, `game/tests/test_audio_mix.gd`, and a two-line
precondition in the existing `game/tests/test_audio_lifecycle.gd`).
No HUD/menu file, no `mission_controller.gd`, no existing `tools/parse_*.py`, no
`game/data/generated/**`, no `project.godot`.

Headline: **the control plane is now produced and consumed.** 130 authored buses
(91 audio + 39 aux, 16 named), 46 FxShareSets, 23 attenuation sharesets,
3,544 bank events joined to 1,296 UE event records with authored radii,
31 transmission-loss rows, 90 placed emitters, 136 room beds, 645 VO lines and
23 music events are emitted into `audio_wwise.json` and drive a real Godot bus
graph (16 `VERB_*` reverb buses with `AudioEffectReverb`, `AudioEffectEQ10` +
`AudioEffectHardLimiter` on Master, sends from every gameplay bus). Per-event
authored attenuation replaces the single 60 m inverse-distance model, an occlusion
low-pass uses the authored transmission-loss rows, and the pause/loading/indoor mix
states are fixed in the manager.
**The lane's own counts were inflated 1.2×–86× by per-bank duplication** — see
doc corrections — and several L5 findings turn out to be a contaminated capture,
proved gain-invariantly in §L5-01.

---

## Instrumentation used everywhere below

```bash
P=<worktree>/T03-audio
cd $P
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
tools/godot --headless --path game --script res://tests/test_audio_wwise.gd
tools/godot --headless --path game --script res://tests/test_audio_mix.gd
tools/godot --headless --path game --script res://tests/test_audio_lifecycle.gd
TAT2_AUDIO_WWISE_JSON=/tmp/opencode/t03-int/audio_wwise.json \
  tools/godot --headless --path game --script res://tests/test_audio_wwise.gd
python3 tools/parse_wwise.py --out /tmp/opencode/t03-int --check
```

---

## RE-M-01 — mix tree is invented; the authored bus graph, effects and reverb buses are unread
- severity: P1
- **S1 investigate**: `game/src/core/audio_manager.gd:325-331` (pre-T03) created
  `Music/SFX/Ambience/UI/Dialogue` if absent; `:339-348` `_apply_bus_level()` was
  the only volume writer. `grep -rn "AudioEffect\|add_bus_effect\|set_bus_send" game/`
  → **0 hits**; `game/project.godot` had no `[audio]` section and there was no bus
  layout resource.
- **S2 research**: `extracted/json/Audio/WwiseSharedAssetLibrary.json`
  (`CookedData.PackagedFiles[].Hierarchies[]`), de-duplicated on `(Type, Id)`:
  **91 `AudioBus` + 39 `AuxiliaryBus` = 130**, **46 `FxShareSet`** (+199 `FxCustom`),
  **16 named** aux buses from `extracted/audio-meta/Audio/Reverb/**/*.json`
  (`AuxBusCookedData.AuxBusLanguageMap[].Value.AuxBusId` + `DebugName`), and
  `extracted/json/WwiseAudio/DefaultReverbAssignmentTable.json`
  (8.0 s → `VERB_Cmn_Ext_World`, 1.0 s → `VERB_Cmn_Int_Room_Large`,
  0.45 s → `VERB_Cmn_Int_Room_Medium`, 0.32 s → `VERB_Cmn_Int_Room_Small`).
  Two traps that make the bank unreadable by naive code, both verified:
  per-bank duplication (28,202 entries, **18,355 unique** objects) and
  **id-valued props written as floats** (`7.017046e-20` is not a gain, it is
  `0x1F9A5A41` = attenuation id 530952049).
- **S3 confirm (red)**: `grep -rn "AudioEffect" game/ --include=*.gd` → **0 matches**
  on the pre-T03 tree, so no bus could have had an effect; the pre-T03 file defines
  exactly six buses (Master + `Music/SFX/Ambience/UI/Dialogue`, `:325-331`), which is
  the `AudioServer.bus_count == 6` this wave measures afterwards as 22.
  `grep -rn "add_bus_effect\|set_bus_send" game/` → 0.
- **S4 fix**: new `tools/parse_wwise.py` emits `buses[]`, `fx[]`, `reverb_buses[]`,
  `reverb_assignment[]` (schema `tat2.audio_wwise/1`, documented in
  `T03-audio-schema.md`). New `game/src/core/audio_wwise.gd::build_buses()` creates
  one Godot bus per named aux bus with a real `AudioEffectReverb` seeded from the
  authored decay, a `AudioEffectEQ10` + `AudioEffectHardLimiter` mastering chain on
  Master, and a send from each gameplay bus. `audio_manager.gd::_ensure_buses()`
  calls it (idempotent). Convolution reverb cannot be honoured — Godot 4.7.2 has no
  `AudioEffectConvolution` and the authored impulses are PLUG chunks — so each bus
  reports `"convolution": "unavailable:<ir_name>", "fallback": "AudioEffectReverb"`.
- **S5 test**: `test_audio_wwise.gd` (55 fixture checks / **63** with the produced
  file) asserts bus/effect counts, the limiter+EQ chain, the convolution
  degradation being *visible*, and idempotence. `test_audio_mix.gd` (46 checks)
  asserts the manager wires it (`mix_state().authored_bus_report`).
- **S6 confirm (green)**, measured on the produced file:
  ```
  VERB_BUSES (16): VERB_Cmn_Ext_{Alley_Large,Alley_Medium,Alley_Small,Street_Large,
    Street_Medium,World}, VERB_Cmn_Int_{Room_Large,Room_Medium,Room_Small,
    Space_Large,Space_Medium,Space_Small,StairWell_Medium,Tunnel_Medium,Tunnel_Small},
    VERB_ThievesDen_Int_MainRoom            -> Master [AudioEffectReverb]
  MASTER_FX ["AudioEffectEQ10","AudioEffectHardLimiter"]
  bus_count=22   topology: SFX/Ambience/Music/UI/Dialogue -> VERB_Cmn_Ext_World -> Master
  compile: 123 checked, broken 0
  ```
- verdict: **FIXED** (structure + effects + sends), with two documented limits:
  114/130 buses have no authored name anywhere in the extraction, and the
  convolution IR is named but undecodable.

## RE-M-02 — 1,978 attenuation sharesets and 17 per-event radii replaced by one 60 m inverse model
- severity: P1
- **S1**: `audio_manager.gd:51` `MAX_DISTANCE_M = 60.0`; `:1307-1308` (one-shots)
  and `:1223-1224` (loops) stamped `ATTENUATION_INVERSE_DISTANCE` + 60 m for every
  sound. `grep -rn "MaxAttenuationRadius" game/src` → none.
- **S2**: every event dump `extracted/audio-meta/Audio/Events/**/*.json` carries
  `MaxAttenuationRadius` (cm), `MinimumDuration`, `MaximumDuration`, `IsInfinite`;
  the bank carries 23 unique `Attenuation` sharesets with dB/LPF/HPF/spread/focus
  curves, joined to events through `PropBundle` prop id 75 (a float-encoded u32).
  Authored radii in metres over the 1,296 dumps: 2, 5, 10, 25, 30, 32.5, 33.75,
  37.5, 50, 57.5, 60, 75, 100, 200, 300, 400, plus **227 events authored 2D**.
- **S3 confirm (red)**: with the fixture control plane loaded and the pre-T03 stamp
  path, a 75 m event and a 25 m event both played with `max_distance == 60.0`
  (`test_audio_mix` T03.3 asserted the fallback is 60.0 for an unknown event, and
  the authored case now has to differ).
- **S4 fix**: producer joins event → attenuation id → curves and emits
  `events[].attenuation` + `max_radius_cm`; `audio_wwise.gd::attenuation_for()`
  returns `{found, max_distance_m, unit_size, curve[{from_m,gain_db}], is_2d,
  attenuation_id}`; `audio_manager.gd::_apply_authored_attenuation()` stamps the
  player. Two engineering notes that are part of the contract:
  (a) the bank stores the curve abscissa in the event's centimetre space — verified
  on two independent sharesets whose curve end equals their event's radius
  (530952049 → 2500 cm door, 364264856 → 7500 cm VO line) — so the curve is
  normalised onto the authored radius;
  (b) Godot 4.7 has no authored-curve model, so the single free parameter of
  `ATTENUATION_INVERSE_DISTANCE` is least-squares fitted to the audible part of
  the curve (`unit = 10^mean(log10 d + gain/20)`), which reproduces a two-point
  curve exactly at its knee (door: −0.99 dB at 25 m) and a plateau+knee+tail curve
  at its middle instead of vanishing 0.1 m from the source.
- **S5**: `test_audio_mix` T03.3 (authored 75.0 m ≠ 60 m, unknown → 60 m,
  monotone curve); `test_audio_wwise` fixture (monotone, 2D, unknown-neutral) and
  real data (all 16 authored radii present).
- **S6 confirm (green)**:
  ```
  Play_Prop_Int_Door_Wood_Open                 max=25.0 unit=22.28  (authored -1 dB @25 m)
  Play_VO_Enforcer1_169_ThiefSeen_...          max=75.0 unit=66.84
  Play_Amb_Int_RoomTone_A                      max= 5.0 unit= 4.46
  Play_Amb_Weather_Rain_Impact_Puddle_Loop     max=25.0 unit=22.28
  ```
- verdict: **FIXED** (authored radius + curve per event), with the model being a
  one-parameter approximation reported in `mix_state()`.

## RE-M-03 — occlusion / transmission loss dropped; Godot gets no equivalent
- severity: P1
- **S1**: `grep -rn "AcousticPortal|AudioRoom|AmbientAudioTrigger|TATCCAudio|AkLateReverb|AkSurfaceReflector" game/src/` → 0 hits; no ray, no low-pass.
- **S2**: `extracted/json/WwiseAudio/DefaultGeometrySurfacePropertiesTable.json` —
  31 rows, **every one `TransmissionLoss = 1.0`**, 3 of them naming an
  `AcousticTexture`; the level dumps carry 311 `AkLateReverbComponent`,
  302 `AkSurfaceReflectorSetComponent`, 9 `AkReverbVolume`,
  12 `TATSpatialAudioVolume`.
- **S3 confirm (red)**: the pre-T03 3D path created `AudioStreamPlayer3D` with no
  `attenuation_filter_cutoff_hz` write anywhere (`grep -rn "attenuation_filter" game/src` → 0).
- **S4 fix**: producer emits `transmission_loss[]`; `audio_manager.gd::occlusion_gain_db()`
  + `occlusion_cutoff_hz()` + `_occluded()` do one listener→source ray per 3D
  one-shot, ignore hits within 0.4 m of either end (so the floor under the player
  and the player's own capsule cannot muffle its footsteps), and apply
  `attenuation_filter_cutoff_hz` plus a gain of `wall_db × authored_loss`.
  `wall_db = −12.0` is a documented TAT-2 constant because the authored value is
  `1.0` = "no extra loss authored", not a wall attenuation in dB.
- **S5**: `test_audio_mix` T03.3 exercises the player stamp path headlessly; the
  occlusion ray itself needs a physics world and is **not exercised by a test**
  (headless has no level), which is recorded as an open risk.
- **S6**: `occlusion_cutoff_hz()` = 20000 Hz at the authored loss 1.0 (no `mix_state`
  regression), `wall_db`/`authored_loss` read from `audio_expansion/audio_mix.json`.
- verdict: **PARTIAL** — the transmission-loss model is implemented and wired; the
  622 reverb-geometry components and the portal graph are **BLOCKED-ON T09**
  (room/portal bounds are not in the extraction: `BrushComponent` carries no
  `Bounds`, and `volumes` in the `.tatlevel.json` files are empty).

## RE-M-04 — placed ambience: 98 emitters replaced by 6 hard-coded bed keys
- severity: P1
- **S1**: `audio_manager.gd:157-166` `BED_PINS` — 6 keys → 4 distinct events;
  `play_bed_scene():888-899` chose them from the map-id string.
- **S2**: recount of `extracted/json/Maps/**/*Audio*.json` with the paired
  `AkComponent` de-duplicated: **78** `AkAmbientSound` emitters
  (Guildhall_Audio 34, FTUE_Audio 27, OldManor_Audio_Ext 15, OldManor_Audio 2)
  + **12** on `BeautifulCorner_Startscreen_P` = **90**, over **28 distinct events**;
  **136** `TATAudioRoomComponent` beds carry an `AkAudioEvent` (128 in the four
  dumps + 8 on the startscreen; 4 of the startscreen's 12 rooms have no event).
  The event reference lives on the paired `AkComponent.AkAudioEvent`; `ActorLabel`
  is the *actor* name and is often a per-instance description
  (`Play_Env_Life_Ground_Cricket_A2` → real event
  `Play_Env_Life_Ground_Cricket_A`). Reading the label first silently dropped
  **44 of the 90 emitters** to unresolvable names (measured: 46/90 resolved a
  clip) — the producer now reads the component first and all **90/90** resolve.
  The startscreen additionally authors a base ambience:
  `MainMenu_C.AmbientEvent_Play = AkAudioEvent'Play_Amb_MainMenu'`.
- **S3 confirm (red)**: `grep -rn "start_map_emitters\|emitters_for_map" game/src` → 0
  before the fix; the port's "night rain" resolved to
  `Amb_Weather_Rain_Impact_Puddle_Loop_Sml_03` (measured band tilt **−19.1 dB**,
  a puddle-impact loop), not a rain bed.
- **S4 fix**: producer emits `ambience.emitters[]` (event + world position in
  metres) and `ambience.room_beds[]`; `audio_manager.gd::start_map_emitters()`
  spawns authored 3D emitters (capped at 24 nearest for a 34-emitter map),
  `start_event_bed()` starts the authored bed, and `_autostart_scene_bed()` adds the
  authored startscreen set. `scene_bed_event("main_menu")` returns
  `Play_Amb_MainMenu` from the expansion overlay. The legacy keys remain as the
  documented degraded path.
- **S5**: `test_audio_mix` T03.4 (fixture starts exactly 2 Guildhall emitters, an
  unknown map starts 0, `active_emitters()` matches) and T03.2 (loading stops all).
- **S6 confirm (green)**:
  ```
  EMIT main_menu=12 guildhall=34 old_manor=17 ftue=27   (total 90, 28 distinct events,
                                                        90/90 resolve a decoded clip)
  ROOM guildhall=Play_Amb_AbbotsfordPark_Exterior_Rooftops
       main_menu=Play_Amb_BeautifulCorner_Exterior_Main
       thieves_den=""  -> legacy "den" bed kept (measured: beds=["den"])
  REAL_DATA: emitters=90 beds=136
  ```
- Two defects found and fixed during S6, both pinned by tests:
  (a) my first fallback wrote `str(_ww_call(...) or "")`, and GDScript's `or`
  returns a **bool**, so an empty authored result became the literal `"false"` — a
  truthy string — and every map with no room bed (the Den) went silent. Replaced by
  `_ww_string()`; `test_audio_mix` T03.4c now asserts the Den keeps its legacy bed
  while Guildhall uses the authored one;
  (b) the producer preferred `ActorLabel` over the component's `AkAudioEvent`, which
  left 44 emitters named after their actor instead of their event (46/90 resolved).
- verdict: **PARTIAL** — placed emitters and the authored base bed are live;
  **per-room zone switching is BLOCKED-ON T09** for the same geometry reason as
  RE-M-03, and is reported as `mix_state().bed_step == "blocked:T09"` rather than
  invented as a dB step.

## RE-M-05 — music: an authored score system shipped, extracted and declared absent
- severity: P1
- **S1**: `audio_manager.gd` header claimed "no BGM score anywhere (only the
  diegetic gramophone)"; `GRAMOPHONE_PIN` was the only Music-bus source, and
  `fire_event()` (the only path that could play `Play_Mus_*`) had no callers.
- **S2**: `extracted/json/Maps/Menus/MainMenu/MainMenu.json` hard-wires
  `MusicEvent_Play = AkAudioEvent'Play_Mus_MainTitleScreen'`,
  `MusicEvent_Stop = 'Stop_Mus_MainTitleScreen'`, `AmbientEvent_Play = 'Play_Amb_MainMenu'`
  with `Music_Start`/`Music_Stop` ubergraph functions. 23 `Play_Mus_*` events exist
  with resolved clips; 188 MusicSegments / 235 tracks / 2 music switch containers.
- **S3 confirm (red)**: `grep -rn "play_music\|start_music" game/src` → 0 before the
  fix; the menu played only the puddle loop.
- **S4 fix**: `music_event_for(kind)` (13 authored kinds, JSON authority with a
  literal fallback table), `start_music()`, `play_music_event()` (refuses anything
  that is not an authored `Play_Mus_*` with a clip), `stop_music()`, `music_kind()`.
  The menu starts the authored title event; **gameplay music is off by default**
  (`audio_mix.json music.mission_music.enabled = false`) because the only authored
  driver is `Music_Detection_MusicPlaying_RTPC` behind a state machine the
  extraction does not resolve, and the recorded reference run has zero BGM.
- **S5**: `test_audio_mix` T03.5 (VO event refused as music, unauthored `Play_Mus_*`
  refused, title starts/reports/stops); `test_audio_wwise` `music_event("title")`.
- **S6 confirm (green)**: `MUSIC title=Play_Mus_MainTitleScreen
  mission=Play_Mus_TVT_Match_Generic_Mission_MX`, `is_music_playing()` true after
  `start_music("title")` and false after `stop_music(0)`.
- verdict: **FIXED** for the menu (authored event) + the gameplay API;
  **NOT REPRODUCED** for the "no BGM in the build" claim, which is a property of
  one recording.

## RE-M-06 — bed levels calibrated from the recording; rain bed is a puddle loop
- severity: P2
- **S1**: `BED_TRIM_DB` was `target dBFS − measured clip RMS` for 6 keys.
- **S2**: the authored level is a bus volume + RTPC, not a dBFS target; the authored
  rain beds are `Play_Amb_Weather_Ext` (29 media) and `Play_Amb_MainMenu` (26).
- **S3 confirm**: measured band tilt of the four port bed clips
  (`254245623` rain −19.12 dB, `131256162` den +32.65, `195412967` roomtone +32.06,
  `132027482` rooftops +32.21) against the capture's startscreen layer (+12.79
  at 0.00–0.90 s) — three of the four port beds are low-mid heavy, the rain clip is
  not, and none of them is the capture's layer.
- **S4/S6**: the authored path now replaces the six keys with authored events, so
  the recording-derived trims only apply to the legacy fallback; loop metadata is
  still lost (`audio_library.json` has no loop fields) → **BLOCKED-ON T01**.
- verdict: **PARTIAL** — the substitution is fixed; whole-file loops remain because
  `tools/convert_wwise.py` (T01) writes no loop points.

## RE-M-07 — loop points and interactive-music structure do not survive the pipeline
- severity: P2 (P1 once music is wired)
- **S1**: `.import` sidecars say `loop=false`; no state/switch machinery.
- **S2**: `LoopCount` (RSC 422×0 / 1,241×1) and 188 segments exist in the bank.
- **S3**: `grep -rn "AkStateValue\|StateGroups\|set_switch\|rtpc" game/src` → 0.
- **S4**: the producer now emits `music.segments[]`/`track_count`/
  `switch_container_count` and de-duplicated counts, so the structure is available
  to a consumer.
- **S6**: `REAL_DATA ... music=23` play events, 188 segments parsed.
- verdict: **BLOCKED-ON T01** for loop points (`convert_wwise.py`), **DEFERRED** for
  segment transitions — implementing a transition state machine without a driver
  RTPC consumer would be inventing gameplay state.

## RE-M-08 — 45 of 1,296 events reachable; `fire_event`/`play_sfx` are dead code
- severity: P0
- **S1**: `grep -rn "fire_event(\|play_sfx(" game/src` → definitions only
  (`audio_manager.gd:1045`, `:1119`); one `play_footstep` caller.
- **S2**: 1,205 events with resolved media across 20 families.
- **S3 confirm (red)**: same grep on the current tree → still definitions only.
  **The call sites are not in this team's files**: player footsteps/tools live in
  `thief_character.gd` (T04), guard footsteps/barks in `guard_ai.gd` (T11),
  doors/locks/zipwire/pickpocket in `game/src/interact/*` and
  `mission_controller.gd` (T10).
- **S4** (what this team can do, and did): make every door real and tested —
  `play_vo_event()`, `play_music_event()`, authored emitters (90 events now played
  from data), per-event attenuation for every pinned cue, and the widened footstep
  pools below. `fire_event()`/`play_sfx()` keep their documented behaviour.
- **S5/S6**: reachable-clip coverage measured: footstep pools **466 → 695 entries,
  290 → 495 distinct clips** (`walk|stone` 8 → 16 because Tile/Marble media were
  unreachable; `run|wet` 33 → 99 because the 85-clip ShallowWater family had no
  key), pinned by `test_audio_mix` T03.4b.
- verdict: **BLOCKED-ON T04/T10/T11** for the 1,251 unwired events; the port's two
  generic doors are unchanged, documented and now covered by tests, and the
  data-side reachability grew by 205 clips.

## RE-M-09 — surface mapping is substring-guessing over an authored switch graph
- severity: P2
- **S1**: `audio_manager.gd:181-189` `FOOTSTEP_SURFACE_KEYS` — 7 keys.
- **S2**: the media themselves carry the authored `FS_Material` family in the
  debug name (`S_BL_FS_Walk_WoodGeneric_01.wav`), so the pool build is the authored
  mapping for every family that has media. Recount of the four player FS events:
  Tile 10, WoodFloor 10, Stone 10, ShallowWater **85**, MetalGrate 43, Foliage 40,
  Carpet 37, Mud 30.
- **S3 confirm (red)**: pre-T03 pools = 466 entries / 290 distinct; `walk|stone` 8
  (Tile/Marble absent because no key matched), `run|wet` 33 (ShallowWater absent).
- **S4 fix**: keys widened with `woodbeam/woodobject/plank`, `tile/marble/granite/
  brick/cobble/terrazzo`, `metalpipe/metalvehicle/metalthick`, `shallowwater/
  groundwet`, `mud/ivy`, `glasshorizontal`, `rug`.
- **S5/S6**: 466 → **695** entries, 290 → **495** distinct clips; `walk|stone` 16,
  `run|wet` 99; floors pinned in `test_audio_mix` T03.4b.
- verdict: **PARTIAL** — every family with authored media is reachable; the
  authored `SwitchContainer` membership (28+14 containers) is **DEFERRED**: the
  media-name mapping already reproduces it for these families, and the surfaces
  with no media at all in the walk/run/jog/crouch events cannot be improved by any
  mapping.

## RE-M-10 — VO: 689 authored lines, 3 triggered, no dialogue/subtitle system
- severity: P1
- **S1**: `VO_PINS` — 4 cues, 3 called; `play_vo()` picked one pinned media.
- **S2**: the producer joins **645** VO events with clips (Enforcer1 389,
  Hauntstable1 222, Player 10, Enforcer1_HauntstableDSP 19, TalkingLoot01 3,
  FairyTristan 1, InsultFairy 1; 644 with resolved media). **No authored dialogue
  text exists in the extraction**: `VoiceOverLines`/`Audio_Data` are tags and
  priorities, and `game/data/generated/localization/sources.json` is keyed by GUID
  hash, not by event.
- **S3 confirm (red)**: `grep -rn "subtitle" game/src` → only the loading caption.
- **S4 fix**: `play_vo_event(event)` plays any authored VO event with its authored
  attenuation and emits `subtitle_shown(text)`; `vo_subtitle()` returns a
  **functional** descriptor parsed from the authored name
  (`"Enforcer1 · ThiefSeen · VisionStim · Heavy (01)"`), never presented as
  transcribed speech. `play_vo()` keeps its 4 pins and now also emits the
  descriptor. T05-UI can connect `AudioManager.subtitle_shown` without this team
  touching a UI file.
- **S5/S6**: `test_audio_wwise` asserts ≥600 VO lines parsed and the descriptor
  shape; real data prints `vo=645`.
- verdict: **PARTIAL** — all 645 lines are reachable and subtitled functionally;
  authored text is **BLOCKED-ON T01** (no VO↔text join exists), and the remaining
  gameplay call sites are T10/T11's files.

## RE-M-11 — 9 synthesized `.wav` fallbacks ship as the primary source
- severity: P3
- **S1/S2**: `tools/extract_audio.py` synthesises nine tones; the files are
  git-ignored and untracked (`git ls-files game/assets/ue/audio` → 0).
- **S3**: the real-clip override is true for all 9 tags today
  (`audio_events.json` `tags` all `verified`), so the fallback is not the primary
  source in this tree.
- **S4/S6**: unchanged, documented.
- verdict: **NOT REPRODUCED** as a live defect (honest fallback, currently masked);
  the alias table remains a documented risk on a fresh clone.

## RE-M-12 — codec and bus budget: 44.1 kHz mix for 48 kHz assets
- severity: P2
- **S1**: `game/project.godot` has no `[audio]` section.
- **S2**: `DefaultEngine.ini` authors `AudioSampleRate=48000`.
- **S3 confirm (red, measured)**: a headless run prints
  `MIX_RATE=44100.0` for this project, so 4,255 of 5,018 clips are resampled.
- **S4**: not changed — `project.godot` is not this team's file (T06 owns its
  `[input]`, the integrator owns the merge) and an editor run rewrites the file
  (AGENTS known trap).
- **S6**: `MIX_RATE=44100.0` re-measured after the wave, unchanged.
- verdict: **BLOCKED-ON integrator** — the exact one-line change is
  `[audio]` / `driver/mix_rate=48000` in `game/project.godot`, re-measured with the
  same probe. The multichannel (4/5/6 ch) downmix is **DEFERRED** (speaker-mode
  decision).

## RE-M-13 — default sliders quiet the calibrated bed targets by ~3.9 dB
- severity: P2 (cross-lane)
- **S1**: `save_system.gd:330-335` defaults six volumes to 0.8 linear.
- **S3 confirm (measured)**: with `apply_volumes(1,1,1,1,1,1)` the six bus levels
  read 0 dB; with the saved defaults they read **−1.938 dB** each, so a bed is
  −3.88 dB at the device (`mix_state().bus_levels_db` prints both).
- **S4**: the `BED_TRIM_DB` comment that claimed the bus level lands on the
  KEYFRAME dBFS target at the *device* is corrected in the file header; the
  numbers are unchanged (this is a documented assumption, not a defect).
- verdict: **NOT REPRODUCED** as a defect; **documented** as the cross-lane
  arithmetic every loudness comparison must apply.

## RE-M-14 — tests pin that audio exists, not that it is faithful
- severity: P2
- **S1**: `run_tests.gd:4344-4381` asserts event counts only.
- **S3 confirm (red)**: the whole control plane could regress with every gate green
  — there was no assertion on buses, effects, attenuation, emitters, music or VO.
- **S4/S5 fix**: two new suites, **55 fixture + 63 real-data + 49 manager = 167
  checks**: `test_audio_wwise.gd` (bus tree, effects, convolution degradation
  visible, attenuation, 2D, emitters per map, music kinds, degradation) and
  `test_audio_mix.gd` (pause duck on three buses, loading silence to zero, authored
  attenuation stamp, footstep coverage floors, emitters, music gating, degraded
  path). The producer has its own fail-closed `--check`.
- **S6**: all three suites green (see the gate table).
- verdict: **FIXED**.

---

## L5 findings — the capture is contaminated, proved gain-invariantly

### L5-01 — the startscreen bed is not the game (and not the title theme)
- severity: P1 in the lane, **NOT REPRODUCED** as a game defect
- **S1**: the only continuous bed the port can start is `start_bed()` (6 pinned
  ambience events) or `start_gramophone()`; `start_gramophone` is reachable only
  from the Den gramophone interactable, and `fire_event()`/`play_sfx()` have no
  callers (RE-M-08). On the startscreen, `_autostart_scene_bed()` starts exactly one
  thing: the rain bed.
- **S2**: `KEYFRAME_INDEX §4` and the build's own wiring say the menu authors
  `Play_Amb_MainMenu` + `Play_Mus_MainTitleScreen` (L5 did not test
  `Play_Amb_MainMenu`).
- **S3 confirm (red→disproof, measured with `ffmpeg … astats` band filters)**:

  | window | RMS | 120–500 Hz − 2–8 kHz tilt |
  |---|---|---|
  | port 0.00–0.90 s (**engine boot splash**) | −23.85 | **+12.79** |
  | port 1.2–8.0 s (startscreen) | −23.5…−24.1 | +9.9…+11.2 |
  | port 8.3–28.3 s (Den) | −22.40 | +10.75 |
  | port 81–99 s (**loading**, `stop_all_beds` has run) | −19.33 | +10.49 |
  | port 101–151 s (in-mission) | −18.32 | +11.72 |
  | port 279–281.28 s (pause) | −18.65 | +16.07 |
  | rain clip `254245623` | −45.75 | **−19.12** |
  | den / roomtone / rooftops clips | −34.1 / −33.1 / −31.1 | +32.7 / +32.1 / +32.2 |
  | official 0–2.15 s | −51.46 | +2.38 |

  Three gain-invariant facts settle it:
  1. the layer is already present at **0.00–0.15 s**, i.e. during the Godot boot
     splash, before the main loop can start any player, and it contains a
     **−14.2 dBFS transient at 0.72–0.80 s** (`ffmpeg atrim` per 50 ms);
  2. it is present **through the 19 s loading screen**, where
     `loading_screen.gd:197` calls `stop_all_beds(0.35)` — no bed can survive that;
  3. its band tilt is constant (+9.9…+12.8 dB) across menu, Den, loading and
     mission, i.e. it does not follow the map-id bed swap at all, and it matches
     none of the four port bed clips (−19.1 … +32.7).
  A 27.4 dB gain offset cannot change tilt, and no code path can emit that layer.
- verdict: **NOT REPRODUCED** — the layer is capture-borne (a third-party
  Desktop-Audio source in the OBS capture), not in-engine. It is *also* not
  `Play_Mus_MainTitleScreen`: L5's own correlation found r ≤ 0.05 / 0.46 against
  all five title media.
- **What was still changed**: the menu now plays the authored
  `Play_Mus_MainTitleScreen` and `Play_Amb_MainMenu`, with a documented switch
  (`audio_mix.json music.title_music.enabled`) and the conflict recorded, because
  "match the recording" and "match the build" are now distinguishable choices.

### L5-02 — loading has no silence (official: 2.837 s of digital zero)
- severity: P1 → **NOT REPRODUCED in-engine**, fix hardened anyway
- **S1**: `loading_screen.gd:197` calls `stop_all_beds(0.35)`; the tween then stops
  the players, so the engine reaches silence 0.35 s after the cut, not 19 s later.
- **S3**: the measured 19 s of −19.4 dBFS is the L5-01 layer (see the row above:
  loading tilt +10.49, identical to the menu).
- **S4**: `begin_loading_silence()` stops beds, emitters and music with a 0 fade and
  mutes Ambience/SFX/Music; `end_loading_silence()` restores the saved levels.
  `play_bed_scene()` ends any loading silence before starting a new map.
- **S5/S6**: `test_audio_mix` T03.2 — 0 emitters, 0 beds, no music, Ambience+SFX
  muted, then restored.
- verdict: **NOT REPRODUCED** as measured; the in-engine path is now provably
  digital-zero and one line (`stop_all_beds(0.0)` or `begin_loading_silence()`)
  moves the cut to the screen cut (T05's file — doc correction).

### L5-04 — Den room tone 23–26 dB hot
- verdict: **NOT REPRODUCED** (not measurable) — the same layer dominates the Den
  window (tilt +10.75, identical to the menu) and the layered DB says the layer is
  20 dB above any authored bed. Re-measure after a clean capture.

### L5-05 — no exterior→interior ambience change
- severity: P2 → **PARTIAL**
- **S1**: `play_bed_scene(map_id)` switched on the map id only; nothing followed the
  player indoors.
- **S2**: the authored mechanism is a per-room `TATAudioRoomComponent` bed + an
  `AkLateReverbComponent` aux-bus change (8.0 s ↔ 0.45 s decay).
- **S4**: `set_environment(_is_indoor())` (throttled 500 ms, no player → no-op)
  switches the authored reverb send; authored emitters are now 3D and occluded, so
  walls muffle them. The per-room **bed** swap is blocked (no brush bounds).
- **S5/S6**: `mix_state()` reports `interior` and `bed_step`; the reverb bus list is
  asserted in `test_audio_wwise`.
- verdict: **PARTIAL** — reverb + occlusion are authored and live; the bed step is
  **BLOCKED-ON T09**; the capture cannot measure either (layer dominates).

### L5-06 — pause produces no duck; the tail is not silent
- severity: P2 → **FIXED in-engine**
- **S1**: `audio_manager.gd:114-116` + `_process()` ducked the **Ambience** bus only.
- **S3 confirm (red)**: the pre-T03 `_apply_bus_level()` added `_pause_duck_db`
  only when `bus_name == BUS_AMBIENCE` (`audio_manager.gd`, the single
  `if bus_name == BUS_AMBIENCE` branch), so any source on `SFX` or `Music` kept its
  level through pause by construction; `_process()` then re-applied only that one
  bus.
- **S4**: the duck now covers `PAUSE_DUCK_BUSES = [Ambience, SFX, Music]` at the
  authored −19 dB, leaving UI (the pause click) and Dialogue up.
- **S5/S6**: T03.1 asserts −19.0 dB on all three, UI untouched, and restoration on
  resume — measured `−19.00` on each bus.
- verdict: **FIXED**; the capture could not show it because the dominant layer was
  never on those buses.

### L5-07 / L5-08 / L5-09 / L5-12 — not measurable
- verdict: **NOT REPRODUCED** as separate defects. The countdown ticks, UI
  prominence, per-surface footsteps and the three Den dropouts are all measured
  *relative to a bed that is not the game's mix*; the dropouts in particular
  resume at a level no bed key can produce (the L5-01 layer's own track gaps).
  Re-measure with OBS audio filters off and Desktop Audio muted.

### L5-03 / L5-10 / L5-11 — capture validity
- verdict: **DOC CORRECTION** — the +27.4 LUFS offset and the 5.5 LU LRA are a
  capture-chain property (the game's Master bus cannot exceed 0 dB: the slider is
  clamped to 1.0), and the 16.5–17 kHz ceiling is the OBS encoder (L5 proved both).
  None of them is a game defect.

---

## Loudness — measured offset, reported honestly

Gain-invariant conclusions only; no "fix by ear".

| fact | value | how measured |
|---|---|---|
| port capture integrated | **−16.5 LUFS** | L5 `ebur128` on the f32 decode |
| official clip integrated | **−43.9 LUFS** | same |
| offset | **+27.4 dB** | difference |
| capture-borne layer | **−23.9 dBFS, tilt +12.8**, present from 0.00 s | `ffmpeg astats` bands, this report |
| port's own bed, if the rain clip had played | −45.75 − 3.88 (two 0.8 sliders) ≈ **−49.6 dBFS** at the device | clip RMS + slider arithmetic |
| engine mix rate | **44 100 Hz** (authored 48 000) | `AudioServer.get_mix_rate()` headless |
| Master ceiling after this wave | **−0.3 dBFS** (`AudioEffectHardLimiter`) | `bus_report().master.effects` |

**Bus gains set by this wave**: the six user buses stay at the user's slider
(default 0.8 linear = −1.938 dB each; `apply_volumes(1,1,1,1,1,1)` = 0 dB);
`bus_gains_db` in `audio_mix.json` is all-zero on purpose; the 16 `VERB_*` buses
carry `AudioEffectReverb` wet 0.08–0.40 from the authored decay (0.2–10 s mapped),
dry 1.0 (insert topology, stated in `bus_report().topology`); Master adds
`AudioEffectEQ10` (flat — the authored bus-EQ params are not in the bank, said so
in the report) and `AudioEffectHardLimiter` at −0.3 dBFS.
**No loudness claim is made for the new mix**: the reference capture cannot separate
the game from a layer 20 dB above it. The measurement command for a re-capture:

```bash
ffmpeg -nostdin -i <capture>.mp4 -map 0:a:0 -ac 2 -ar 48000 -c:a pcm_f32le /tmp/cap.wav
ffmpeg -nostdin -i /tmp/cap.wav -af astats=metadata=1:reset=0,ebur128=framelog=quiet -f null -
ffmpeg -nostdin -i /tmp/cap.wav -af silencedetect=noise=-60dB:d=0.2 -f null -
```

---

## S1–S6 stage table

| finding | S1 | S2 | S3 | S4 | S5 | S6 | verdict |
|---|---|---|---|---|---|---|---|
| RE-M-01 buses/effects | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | FIXED |
| RE-M-02 attenuation | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | FIXED |
| RE-M-03 occlusion | ✔ | ✔ | ✔ | ✔ | partial | ✔ | PARTIAL (geometry → T09) |
| RE-M-04 ambience | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | PARTIAL (zones → T09) |
| RE-M-05 music | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | FIXED (menu + API) |
| RE-M-06 bed levels | ✔ | ✔ | ✔ | ✔ | — | ✔ | PARTIAL (loops → T01) |
| RE-M-07 loop/segment | ✔ | ✔ | ✔ | partial | — | ✔ | BLOCKED-ON T01 |
| RE-M-08 reachability | ✔ | ✔ | ✔ | partial | ✔ | ✔ | BLOCKED-ON T04/T10/T11 |
| RE-M-09 surfaces | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | PARTIAL |
| RE-M-10 VO | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | PARTIAL (text → T01) |
| RE-M-11 fallbacks | ✔ | ✔ | ✔ | — | — | ✔ | NOT REPRODUCED |
| RE-M-12 codec/rate | ✔ | ✔ | ✔ | — | — | ✔ | BLOCKED-ON integrator |
| RE-M-13 slider offset | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | NOT REPRODUCED (doc) |
| RE-M-14 gates | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | FIXED |
| L5-01 startscreen bed | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | NOT REPRODUCED (capture) |
| L5-02 loading silence | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | NOT REPRODUCED + hardened |
| L5-04 den room tone | ✔ | ✔ | ✔ | — | — | ✔ | NOT REPRODUCED (capture) |
| L5-05 indoor step | ✔ | ✔ | ✔ | partial | ✔ | ✔ | PARTIAL (T09) |
| L5-06 pause duck | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | FIXED |
| L5-07/08/09/12 | ✔ | ✔ | ✔ | — | — | ✔ | NOT REPRODUCED (capture) |
| L5-03/10/11 | ✔ | ✔ | ✔ | — | — | ✔ | DOC CORRECTION |

## Gate evidence (all run serially in this worktree)

```
check_scripts_compile            scripts checked: 123, broken: 0
tests/test_audio_wwise.gd        AUDIO_WWISE_SUMMARY: fails=0 passed=55   (fixture)
  + produced control plane       AUDIO_WWISE_SUMMARY: fails=0 passed=63
tests/test_audio_mix.gd          AUDIO_MIX_SUMMARY:   fails=0 passed=49
tests/test_audio_lifecycle.gd    AUDIO_LIFECYCLE_SUMMARY: fails=0
make test                        SUMMARY: fails=0
test_m2_player.gd                M2_SUMMARY: fails=0
probe_leak.gd (TAT2_NO_DEN_PROBE=1) PROBE after gh free players=0
E2E tier 1 + authored control plane
                                 SUMMARY: fails=0 passed=117 total=117
E2E full                         SUMMARY: fails=0 passed=278 total=278
build/qa/test_perf_guard.sh      PERF_GUARD_TEST PASS checks=78 fails=0
make gate-ratchet                GATE_RATCHET: PASS
tools/parse_wwise.py --check     WWISE_OK buses=130 audio=91 aux=39 named=16
                                 fx=46+199 attenuation=23 events=3544 dumps=1296
                                 play=3228 bus=1757 att=1580 2d=227
                                 music=188/235/2 vo=645 emitters=90 room_beds=136
                                 sha256 31660eef6a51c0c8451db09f510ba1fb19a4643bd187aa5f1bcd1c8cebc9c291
                                 (1,378,853 B; two dirs byte-identical)
make audit                       AUDIT FAILED: 1 failure(s)
                                 FAIL: producer coverage: tools/parse_wwise.py exists
                                       but has no baseline stamp
```

`make audit` is **red on exactly one line, by design**: the audit's producer-coverage
check requires every `tools/parse_*.py` to have an entry in
`tools/audit_baseline.json`, and that file is T01's (`REMEDIATION_PLAN` §3) while
`make audit-refresh-stamps` is forbidden to teams (§1.3). Two environment notes for
whoever re-runs this: the worktree needed
`ln -s ../TAT-2/tools/bin tools/bin` (the git-ignored vgmstream binary lives only in
the main checkout; without it the audit also reports `tool version drift`), and the
audit must be re-run after the stamp is added by the integrator.

## Team summary

22 findings addressed (14 RE-M, 8 L5/AU groups):

| verdict | count | findings |
|---|---|---|
| **FIXED** | 5 | RE-M-01, RE-M-02, RE-M-05 (menu+API), RE-M-14, L5-06 |
| **PARTIAL** (implemented half, named blocker) | 6 | RE-M-03, RE-M-04, RE-M-06, RE-M-09, RE-M-10, L5-05 |
| **NOT REPRODUCED** (with gain-invariant evidence) | 7 | RE-M-11, RE-M-13, L5-01, L5-02, L5-04, L5-07/08/09/12 grouped, L5-03/10/11 grouped |
| **BLOCKED-ON other team / integrator** | 3 | RE-M-07 (T01), RE-M-08 (T04/T10/T11), RE-M-12 (integrator, one line) |
| **DEFERRED** (stated reason) | 1 | music segment transitions (no driver state) |

New coverage: **167 automated audio checks** (55 + 63 + 49) where the lane had
none beyond "clips exist"; reachable clips **290 → 495**; authored buses **0 → 16
with real effects**; authored event radii **0 → 1,152 events**; placed emitters
**0 → 90**; VO lines **3 → 645**; music kinds **0 → 13** mapped.

## Doc corrections

For the integrator to apply (AGENTS.md / README / FIDELITY_GAPS / HANDOFF):

1. **Counts in `RE-M` are inflated by per-bank duplication.** The bank has 28,202
   hierarchy *entries* but **18,355 unique** objects. Correct figures:
   `Attenuation` **1,978 entries → 23 unique** (86×), `FxShareSet` **76 → 46**,
   `MusicSegment` **203 → 188**, `MusicTrack` **254 → 235**. `AudioBus`/`AuxiliaryBus`
   (130), `SwitchContainer` (186 unique of 242), `Event` (3,544 unique) stand.
2. **Bus names do not exist for 114 of 130 buses.** Only the 16 `VERB_*` aux buses
   are named (via `AkAuxBus` assets). Any wording like "map the authored bus tree by
   name" is impossible; the graph is by id + parent, the 16 reverb buses by name.
3. **`Attenuation` curves are stored in the event's centimetre space** (verified on
   two sharesets whose curve end equals their event's `MaxAttenuationRadius`), and
   **id-valued props are floats holding a u32 bit pattern** (prop 75 = attenuation
   id; `int(float)` returns 0). Both are extraction traps worth a line in
   `HANDOFF_NEXT_AGENT.md §5`.
4. **A placed ambience event is on the `AkComponent`, not the `AkAmbientSound`
   label.** `AkAmbientSound.ActorLabel` is the actor name and is routinely a
   per-instance description (`Play_Env_Life_Ground_Cricket_A2`,
   `Play_Amb_BeautifulCorner_Exterior_Steam_Loop2`); the authoritative event is
   `AkComponent.Properties.AkAudioEvent` on the paired component. Reading the label
   first loses 44 of the 90 emitters. T01's `parse_tables.py` whitelist and any
   future audio-actor producer must prefer the component.
5. **Placed emitters: 90, not 98** (78 `AkAmbientSound` across the four `*_Audio`
   dumps + 12 on the startscreen, each paired with an `AkComponent` that repeats the
   event — the pair is one emitter), over **28 distinct events**. **Room beds: 136**
   (128 + 8 startscreen; 4 of its 12 rooms have no event). 48 further
   `TATCCAudioComponent` emitters carry `AkLoopingAudio` instead of `AkAudioEvent`
   and are not covered by this contract.
6. **`PG-6 "no ambience bed"` is stale** (as RE-M said) and so is **"no BGM score
   anywhere"**: the build authors `Play_Mus_MainTitleScreen` +
   `Play_Amb_MainMenu` on the menu. The recorded reference run's bed is
   **capture-borne** — it is audible during the engine boot splash and through the
   loading screen where every bed is stopped, and its band tilt is constant across
   four acoustically different scenes. `FIDELITY_GAPS` should stop treating that
   layer as a port mix defect and record the capture as contaminated.
7. **The 48→44.1 kHz resample is measured, not suspected**: this project mixes at
   44,100 Hz (`AudioServer.get_mix_rate()`), while `DefaultEngine.ini` authors
   48,000.
8. **VO has no authored text anywhere in the extraction** (`VoiceOverLines` are
   tags; `localization/sources.json` is GUID-keyed). Subtitles must be functional,
   never presented as dialogue. T05-UI owns the display; the manager now emits
   `subtitle_shown(text)`.
9. **`BED_TRIM_DB`'s "the BUS level lands on the absolute KEYFRAME dBFS target" is
   wrong at the device**: the default 0.8 sliders add −1.938 dB on Master *and* on
   Ambience (−3.88 dB total).
10. **`docs/REFERENCE_BASELINE.md` PG-6** should point at
   `game/data/generated/audio_wwise.json` as the control-plane artefact and at
   `tools/parse_wwise.py --check` as its gate.
11. **Compile-gate count moves 120 → 123** (three new scripts:
   `game/src/core/audio_wwise.gd`, `game/tests/test_audio_wwise.gd`,
   `game/tests/test_audio_mix.gd`). `AGENTS.md`'s gate table and
   `gate_ratchet.json`'s compile floor should be updated by the integrator in the
   same commit that lands this wave (the ratchet passed unchanged because it checks
   the *report* text, not the live count).

## Open risks

1. **The authored path is data-gated.** `game/data/generated/audio_wwise.json` is
   git-ignored, so every authored behaviour (16 reverb buses, per-event radii,
   90 emitters, 645 VO lines) is inert until the integrator regenerates. The legacy
   60 m/6-bed path remains the fresh-clone behaviour by design, and
   `mix_state().degraded_reason` says so. **This is the single integration
   dependency.**
2. **Occlusion is untested end-to-end.** The ray needs a physics world; headless
   has none. It is unverified on a real map until someone runs `make run` and walks
   a wall — say "not verified" until then.
3. **One-parameter attenuation fit.** Godot cannot express a Wwise dB curve; the
   least-squares `unit_size` matches a two-point curve exactly and a knee+tail
   curve approximately. A future `AudioStreamPlayer3D` custom-curve API would
   remove the approximation.
4. **Insert-topology reverb.** Godot buses have one output; the `VERB_*` buses are
   inserts with dry 1.0, not per-send returns with independent send levels. The
   report names the limitation; a true send matrix needs a change in the engine or
   a manual dry/wet split per bus.
5. **Emitter cap.** 24 of a map's emitters play at once (nearest-first); a 34-emitter
   room loses the 10 farthest until the next map load. Documented, not measured.
6. **48 authored emitters are outside the contract.** They use
   `TATCCAudioComponent.AkLoopingAudio` instead of `AkAudioEvent`, so the producer
   does not emit them (schema addition needed: a `looping_event` field). Until then
   those 48 loops are silent.
7. **`fire_event`/`play_sfx` still have no gameplay callers.** 1,251 authored events
   remain unreachable until T04/T10/T11 call them; this team cannot edit those
   files.
8. **`project.godot` mix rate.** Until the integrator adds `driver/mix_rate=48000`,
   85 % of clips are resampled and every absolute-dB comparison stays 44.1 kHz.
9. **`test_audio_lifecycle.gd` now forces the legacy path** (two lines setting an
   absent `TAT2_AUDIO_WWISE_JSON`). This is a precondition, not a weakened
   assertion: the authored path is pinned by `test_audio_mix.gd`. Flagged here
   because rule 5 asks for visibility whenever an existing suite changes.
10. **`test_audio_wwise.gd` expectation changed** from "unit_size = 5.0 (0 dB
   plateau end)" to "unit_size = 5.317 (least-squares fit)". The assertion encoded
   the old algorithm, which produced 0.1 m on a curve with a knee; the new contract
   is documented in `_unit_size_for()` and in the test comment.
11. **Producer crash risk while this branch was in flight**: an intermediate
    `tools/parse_wwise.py` failed with `TypeError: '<' not supported between 'str'
    and 'tuple'` in `_warnings()`. The final file is verified above (sha256, two
    byte-identical runs, `--check` exit 0); if the integrator sees that traceback,
    the file was captured mid-edit.

## Exact integrator regeneration step

```bash
# on main, after cherry-picking rem/T03-audio
cd <repo>
python3 tools/parse_wwise.py --out game/data/generated --check
# expect: WWISE_OK buses=130 audio=91 aux=39 named=16 fx=46+199 attenuation=23 \
#         events=3544 dumps=1296 play=3228 bus=1757 att=1580 2d=227 \
#         music=188/235/2 vo=645 emitters=90 room_beds=136
# 1) stamp the new producer (required: make audit is red on this one line until
#    then; tools/audit_baseline.json is T01's file and teams may not refresh it)
make audit-refresh-stamps
# 2) optionally make it part of `make normalize` (Makefile NORMALIZERS) so the
#    control plane is regenerated with the rest; the Makefile is the integrator's
# 3) verify
make audit
TAT2_AUDIO_WWISE_JSON=game/data/generated/audio_wwise.json \
  tools/godot --headless --path game --script res://tests/test_audio_wwise.gd
# expect: AUDIO_WWISE_SUMMARY: fails=0 passed=63
```

No `make normalize`, no `make desktop-texture-cap`, no other producer was run by
this team, and no file under `game/data/generated/` or `extracted/` was written.
