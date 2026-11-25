# T03-AUDIO — `audio_wwise.json` schema contract (v1)

Written by the T03 integrator after verifying the source data by hand. The producer
(`tools/parse_wwise.py`, worker A) emits exactly this; the runtime
(`game/src/core/audio_wwise.gd`, worker B) consumes exactly this. Neither side may
invent a field; additions require a note in this file.

Output path (producer default): **`<--out>/audio_wwise.json`**. `--out` is required.
The integrator, never a team, writes it to `game/data/generated/`.

Deterministic: sorted keys, sorted arrays where order carries no meaning, no
timestamps, no absolute paths, no host names. `--check` re-reads the file and
fails closed when a count or invariant below drifts.

---

## Verified source facts (do not re-derive differently)

The bank `extracted/json/Audio/WwiseSharedAssetLibrary.json` is:

```
[ { "Type", "Name", "Flags", "Class", "Package",
    "CookedData": { "PackagedFiles": [ { "Header"?: {...}, "Hierarchies"?: [ {Type, Id, Data} ] } ] } } ]
```

* 8,593 packaged files; **3,543** carry `Hierarchies`. Files without them are raw media.
* The same object id appears in several soundbanks, so **the entry count is not the
  object count**. De-duplicate on `(Type, Id)` before counting:

  | type | entries | **unique** |
  |---|---|---|
  | SoundSfxVoice | 8,707 | 7,408 |
  | EventAction | 4,316 | 4,313 |
  | Event | 3,547 | **3,544** (1,296 have a UE asset dump) |
  | RandomSequenceContainer | 1,663 | 1,450 |
  | ActorMixer | 3,327 | 272 |
  | MusicTrack | 254 | 235 |
  | FxCustom | 3,353 | 199 |
  | LayerContainer | 209 | 193 |
  | MusicSegment | 203 | **188** |
  | SwitchContainer | 242 | 186 |
  | TimeMod | 123 | 96 |
  | AudioBus | 91 | **91** |
  | FxShareSet | 76 | **46** |
  | MusicRandomSequenceContainer | 43 | 41 |
  | AuxiliaryBus | 39 | **39** |
  | Attenuation | **1,978** | **23** |
  | LFO | 13 | 13 |
  | Envelope | 12 | 12 |
  | AudioDevice | 4 | 4 |
  | MusicSwitchContainer | 2 | 2 |

  `--check` asserts the unique counts (all 23 attenuation ids, 91/39 buses, 46
  sharesets, 188 segments, 2 music switch containers).

* **Ids in `Props`/`PropBundle` were written by the exporter as floats, so integer
  references must be recovered from the IEEE-754 bit pattern**:

  ```python
  def as_u32(v: float) -> int:
      return struct.unpack("<I", struct.pack("<f", float(v)))[0]
  ```

  Verified: `7.017046e-20 → 530952049`, `5.516847e-25 → 388676855`,
  `2.6510752e-22 → 463486823`, `4.226024e-26 → 357647160` — all four are real
  `Attenuation` ids. A plain `int(v)` yields 0 and silently loses the reference.
  Applies to prop ids 75 (attenuation) and to any other id-valued prop.

* **Bus props** (`Data.Props` on `AudioBus`/`AuxiliaryBus`) use the same float/int
  trap. Only props observed on buses are decoded; the rest stay opaque:
  `0 → volume_db` (**7** buses carry one, −96…−2 dB; 123 have none), `4 → hpf_db`,
  `5 → lpf_db`. 129 of 130 buses carry prop 41 = 100.0, which is *not* decoded and
  is emitted under `opaque_props`. Do **not** guess a meaning for an id the table
  does not list.
* **Bus names are not in the extraction.** 114 of 130 buses have no name anywhere.
  The 16 named ones come from `extracted/audio-meta/Audio/Reverb/**/*.json`
  (`AuxBusCookedData.AuxBusLanguageMap[].Value.AuxBusId` + `DebugName`). The bank
  stores those ids as signed 32-bit; normalise with `id & 0xFFFFFFFF` before
  matching. (`VERB_Cmn_Ext_World` = 3775949156, `VERB_ThievesDen_Int_MainRoom` =
  1554268871.)
  A bus without a name must emit `"name": null` and be referred to by id.
  **Doc correction:** "map the authored 130-bus tree by name" is impossible.
* **Event → bus**: `Event.Data.EventActionIds[]` → `EventAction.Data.ReferencedId`
  → walk `BaseParams.DirectParentId` upward (≤ 40 hops, cycle-guard) → the first
  `BaseParams.OverrideBusId` that is one of the 130 bus ids. Play events reach **38**
  distinct buses (all-action reaches the same 38; no bus is reachable only through a
  non-Play action). Events with no resolved bus emit `null` (they inherit Master).
* **Event → attenuation**: same walk, stop at the first `PropBundle.Props` id 75
  and decode with `as_u32`. ~45 % of events resolve; the rest emit `null`.
* **Event → radius / 2D**: `MaxAttenuationRadius`, `MinimumDuration`,
  `MaximumDuration`, `IsInfinite` live in the UE asset dump
  `extracted/audio-meta/Audio/Events/**/*.json` (1,298 files), not in the bank.
  Radius is centimetres (7500 = 75 m); `0.0` means authored 2D (227 events).
* **FxShareSet `Plugin.PluginId`** is the effect class (`AkConvolutionReverbFX`,
  `AkPeakLimiterFX`, `AkParameterEQFX`, `AkRoomVerbFX`, `AkMatrixReverbFX`,
  `MasteringSuiteFX`, `AkDelayFX`, `AkStereoDelayFX`, `AkMeterFX`,
  `AkHarmonizerFX`). `PluginParams.Params` holds the authored values.
  `MediaList[].SourceId` is the convolution impulse; its name is in
  `extracted/json/Audio/InitBank.json` → `InitBankCookedData.Media[].DebugName`
  (e.g. `BOOM Library IR - F&S\Metropole 05 50m FOA.wav`). **The impulse audio is a
  PLUG chunk and is not decoded** — the name is real, the samples are not.
* **Transmission loss / reverb assignment**:
  `extracted/json/WwiseAudio/DefaultGeometrySurfacePropertiesTable.json`
  (31 rows, all `TransmissionLoss = 1.0`; 3 rows name an `AcousticTexture`) and
  `DefaultReverbAssignmentTable.json` (4 rows: 8.0 s → `VERB_Cmn_Ext_World`,
  1.0 s → `VERB_Cmn_Int_Room_Large`, 0.45 → `VERB_Cmn_Int_Room_Medium`,
  0.32 → `VERB_Cmn_Int_Room_Small`).
* **Placed emitters**: the generated `.tatlevel.json` files carry the actor `pos`
  but omit `AkAmbientSound` actors entirely, so all 90 positions are derived from
  the root component's `RelativeLocation` (cm → metres via `[x/100, z/100, y/100]`).
  The raw dumps `extracted/json/Maps/**/*Audio*.json` carry the event:
  `AkAmbientSound.ActorLabel` and `TATCCAudioComponent.Properties.AkAudioEvent`.
  Join on the actor name; an `AkAmbientSound` and its paired `AkComponent` are
  **one** emitter (the component repeats the label). 13 of the 78 dump emitters
  carry placeholder labels (`AkAmbientSound7`, …) whose real event is only on the
  paired component: resolving them gives **51** distinct events (62 raw labels).
  Room beds: `TATAudioRoomComponent.Properties.AkAudioEvent`, keyed by its `Outer`
  volume name; 128 in the six `*_Audio` dumps + 8 on the startscreen = **136**
  (4 of the startscreen's 12 rooms carry no event). 48 further
  `TATCCAudioComponent` emitters carry `AkLoopingAudio` instead of `AkAudioEvent`
  and are outside this contract.
* **No VO text exists anywhere in the extraction.** `VoiceOverLines`/`Audio_Data`
  are tags and priorities; `game/data/generated/localization/sources.json` is keyed
  by GUID hash, not by event. **645** `Play_VO_*` events have dumped assets (no
  source in the extraction yields the brief's 689 — that figure counts clips, not
  events). Subtitles must therefore be *functional* (derived from the authored
  event name: speaker/line/verb/state/variant) and labelled as such, never
  presented as authored dialogue.

---

```jsonc
{
  "schema": "tat2.audio_wwise/1",
  "generated_by": "tools/parse_wwise.py",
  "sources": { "bank": "...", "events_dir": "...", "reverb_dir": "...",
               "init_bank": "...", "surface_table": "...", "reverb_table": "..." },
  "counts": {
    "bank_packaged_files": 8593, "bank_files_with_hierarchies": 3543,
    "objects_unique": 18355, "objects_entries": 28202,
    "buses": 130, "audio_buses": 91, "aux_buses": 39, "named_buses": 16,
    "fx_sharesets": 46, "fx_custom": 199, "attenuations": 23,
    "events_total": 3544, "events_ue_dumps": 1296, "events_play": 0,
    "events_with_bus": 0, "events_with_attenuation": 0, "events_2d": 0,
    "music_play_events": 0, "music_segments": 188, "music_tracks": 235,
    "vo_events": 0, "emitters": 0, "room_beds": 0
  },

  "buses": [{
    "id": 3803692087, "kind": "audio" | "aux", "name": "VERB_Cmn_Ext_World" | null,
    "parent": 123 | null,            // Data.OverrideBusId when it is a bus id
    "volume_db": -6.0 | null,        // prop 0
    "hpf_db": -12.0 | null,          // prop 4
    "lpf_db": -12.0 | null,          // prop 5
    "effects": [{ "fx": 107242095, "shareset": true }],   // FxBusParams.FxParams.Effects
    "aux_sends": [1866315672],       // AuxParams.AuxIds
    "reflections_aux": 0 | null,     // AuxParams.ReflectionsAuxBus
    "device": 3859886410 | null,     // DeviceSharesetId
    "state_groups": 0, "rtpcs": 0, "duck_rows": 0,
    "opaque_props": [{ "id": 41, "value": 100.0 }]
  }],

  "fx": [{
    "id": 107242095, "kind": "shareset" | "custom",
    "plugin": "AkConvolutionReverbFX",
    "params": { "fPreDelay": 0.0, "...": 0 },   // PluginParams.Params verbatim
    "ir_source_id": 331466410 | null,
    "ir_name": "BOOM Library IR - F&S\\Metropole 05 50m FOA.wav" | null
  }],

  "attenuation": [{
    "id": 530952049, "height_spread": true, "cone": false,
    "curves": [{
      "scaling": "dB" | "None",
      "points": [{ "from": 0.0, "to": 0.0, "interpolation": "Constant" }]
    }]
  }],

  "events": [{
    "name": "Play_Prop_Int_Door_Wood_Open", "id": 123,
    "play": true, "bus": 2755434192 | null, "attenuation": 530952049 | null,
    "max_radius_cm": 7500.0, "is_infinite": false,
    "duration_s": { "min": 0.0, "max": 0.0 },
    "media_count": 2
  }],

  "transmission_loss": [{ "material": "/Game/.../Stone.Stone",
                          "transmission_loss": 1.0,
                          "acoustic_texture": "AT_Stone" | null }],

  "reverb_assignment": [{ "decay_s": 8.0, "aux_bus": "VERB_Cmn_Ext_World",
                          "aux_bus_id": 1554268871 }],

  "reverb_buses": [{ "name": "VERB_Cmn_Ext_World", "id": 1554268871,
                     "ir_name": "BOOM Library IR - ..." | null,
                     "max_radius_cm": 2500.0 }],

  "music": {
    "play_events": ["Play_Mus_MainTitleScreen"],
    "stop_events": ["Stop_Mus_MainTitleScreen"],
    "mute_events": ["Mute_Music"], "unmute_events": ["UnMute_Music"],
    "segments": [{ "id": 1, "duration_ms": 0.0, "tempo": 120.0,
                   "entry_marker": 0.0, "exit_marker": 0.0, "marker_count": 0 }],
    "track_count": 235, "switch_container_count": 2
  },

  "ambience": {
    "emitters": [{ "map": "Guildhall_Audio", "actor": "AkAmbientSound_0",
                   "class": "AkAmbientSound" | "AkComponent" | "TATCCAudioComponent",
                   "event": "Play_Amb_BeautifulCorner_Exterior_Steam_Loop",
                   "pos": [x, y, z] }],
    "room_beds":  [{ "map": "Guildhall_Audio", "volume": "TATSpatialAudioVolume_0",
                     "event": "Play_Amb_AbbotsfordPark_Exterior_Rooftops",
                     "aux_bus": "VERB_Cmn_Ext_World" | null }]
  },

  "vo": {
    "speakers": { "Enforcer1": 389 },
    "lines": [{ "event": "Play_VO_Enforcer1_169_ThiefSeen_VisionStim_Heavy_01",
                "speaker": "Enforcer1", "line": 169, "verb": "ThiefSeen",
                "state": "VisionStim", "severity": "Heavy", "variant": 1,
                "media_count": 3 }]
  },

  "warnings": ["..."]   // human-readable, deterministic, sorted
}
```

## Producer contract

* `--out DIR` (required), `--check` (verify an existing output), `--quiet`.
* Never write outside `--out`; never touch `game/data/generated/` by default.
* Every emitted number must be derived from the files above — no literal lists of
  event names except where the name is the source (music prefixes, VO prefix).
* On a missing or unreadable source: fail with exit 2 and a one-line reason, never
  emit a partial file.
* `python3 tools/parse_wwise.py --out /tmp/opencode/t03 --check` must print a
  `WWISE_OK` summary line and exit 0.

## Runtime contract (`game/src/core/audio_wwise.gd`)

* `load_data(path := "res://data/generated/audio_wwise.json")` returns bool; a
  missing file is **not** an error — the runtime falls back and reports
  `degraded_reason()`.
* `OS.get_environment("TAT2_AUDIO_WWISE_JSON")` overrides the path (tests/QA).
* `build_buses()` creates the authored aux/reverb buses as real Godot buses with
  real `AudioEffect` instances (see below) and returns a report dictionary.
  Idempotent.
* `attenuation_for(event) -> Dictionary` with
  `{found, max_distance_m, unit_size, curve:[{from_m, gain_db}], is_2d}`.
* `occlusion_cutoff_hz(loss)` and `occlusion_gain_db(loss)` from the authored
  transmission loss.
* `music_event(kind)` (`title`, `character_select`, `guard_alerted`, …).
* No `AudioEffectConvolution` exists in Godot 4.7.2 — a convolution reverb bus
  **must** degrade to `AudioEffectReverb` seeded from the authored decay/predelay
  and say so in the bus report. This is the "missing impulse" path.
