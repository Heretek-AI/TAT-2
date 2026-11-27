# W10-P3 — Wwise control plane (switches, states, RTPCs)

Lane AUD. Base `8a3ad62`. Producer + consumer first slice: the shipped bank's
**switch/state/RTPC** graph now reaches the runtime instead of only its buses,
attenuations and music segments (which T03 already owns). This is not a claim of
a full mix, music or VO port; §5 lists exactly what is wired and what is not.

## 1. What shipped

| Piece | File | What it owns |
|---|---|---|
| Producer | `tools/parse_audio_control.py` (new) | `game/data/generated/audio_control.json`, schema `tat2.audio_control/1` — switch groups/values, state groups/values + per-state property rows, RTPCs + authored curves, switch containers/packages/media, event→control edges. `--check` enforces the verified count table and canonical bytes. |
| Consumer | `game/src/core/audio_control.gd` (new, `class_name AudioControl`) | `set_switch` / `set_state` / `set_rtpc`, switch-aware media selection, curve evaluation (gain/pitch/low-pass), state override rows, QA state. Pure consumer: no bank parsing, no invented name or binding. |
| Runtime wiring | `game/src/core/audio_manager.gd` | Footstep surface/gait switches, interior/exterior state, pause modal state, detection RTPC → music gain/pitch, `mix_state().control`. |
| Gate | `game/tests/test_audio_control.gd` (new, suite **121**) | 71 checks: counts, group names, state rows, fail-closed setters, footstep selection, curve math, runtime wiring, degraded path. |
| Pipeline | `Makefile`, `tools/manifest_audit.py` | `parse_audio_control` added to `NORMALIZERS` (after `convert_wwise`, so the decode step can never be a dependency) and to the producer table. |

The producer never reads `audio_events.json`, `audio_wwise.json` or any decoded
clip: selection data is **MediaIds**, and the runtime joins them to clips through
the existing `audio_events.json` load, so parse order cannot couple the two
producers.

## 2. Measured inventory

From `AUDIO_CONTROL_OK switch=14/23 switch_values=84 state=4/8
state_values=10 rtpcs=16/50 curves=142 containers=185 package_media=13146
events=180` (one run on the shipped extraction):

| Row | Measured | Note |
|---|---:|---|
| Switch groups (named / bank ids) | **14 / 23** | Names come only from `AkSwitchValue` dumps; 9 bank group ids have no dump and are emitted `name: null`. |
| Switch values (named) | **84** | 6 duplicate dumps inside one tree + 84 mirror copies across the two extraction trees (`audio-meta` vs `json`); counted, never emitted twice. |
| State groups (named / bank ids) | **4 / 8** | `Player_HeightenedSenses`, `Player_Downed`, `Weather_isExterior`, `Modal_State`. |
| State values (named) | **10** | 2 duplicate dumps, 10 mirrors. |
| RTPCs (named / total ids) | **16 / 50** | 34 bank ids have no `AkRtpc` dump (name `null`). 2 named RTPCs are authored but never referenced by the bank (`Character_DownButNotOut`, `Character_ReceivedDamage`). |
| Authored curves | **142** | De-duplicated **per curve** (param + accumulation + scaling + points + interpolation), never per param: the detection RTPC alone carries 4 volume shapes across 13 nodes. |
| Switch containers | **185** | 186 `SwitchContainer` objects exist; one (`334139453`) has group 0 and no package and is counted `unset`, not emitted. |
| Package media ids | **13 146** | Each package is a **superset**: it includes every nested switch branch (see §3). |
| Named events with control data | **180** | 260 event→container, 166 event→switch-group, 34 event→state-group, 140 event→RTPC edges. 57 further events with control data have no `AkAudioEvent` dump name and are omitted. |

### Producer gaps / anomalies (recorded, not fixed)

- **Dangling switch values — 70 (group, value) pairs.** A `SwitchPackage`
  references a value id that has no `AkSwitchValue` dump *for that group*. Names
  are group-scoped: `MetalPipe`/`WoodObject` are named under
  `PhysmatImpact_Material` and unnamed under `FS_Material`; `FS_Material` also
  references `2720957842`, which no dump names at all. Their media is still
  emitted with `name: null`.
- **Two named switch groups have no `SwitchContainer`** (`Music_Switch_Escape`
  2359962185, `Music_Switch_Phase` 3991168261): the two `MusicSwitchContainer`
  objects select through a `DecisionTree` key, not `SwitchPackages`, so their
  group carries no package media.
- **The music `DecisionTree` keys do not all resolve** to those groups' named
  values (e.g. `1363461318`, `2658483646`, `3143687845`, `4218600605` under the
  Phase container). This producer therefore emits the *package* graph only and
  leaves the music decision tree unbound; a music lane must resolve it.
- **Sample families do not always match the value name.** The `Glass` package
  plays the `MetalPipe` sample family, `Bark` plays `WetHardSurface`,
  `WoodFloor` plays the `WoodBeam` recordings, `WoodBeam` plays `Woodfloor`, and
  `Tile` plays the `Stone` container (the same node id). This is authored
  content reuse in the bank, not a join error (the same pairing appears in both
  material containers 444141124 and 94670918). No name was "repaired".
- **The brief's "5 state groups" is not reproducible.** The extraction carries
  **4** named state groups (11 `AkStateValue` files in `audio-meta`, one dup) and
  **8** state-group ids the bank references. The port emits 4 named + 4
  id-only; the test asserts 4 and prints why, rather than inventing a fifth.

## 3. Media selection contract (and the measured footstep result)

`packages[].media` is a superset (it includes nested switch branches, because a
nested group's runtime value is unknown at parse time). Selection is therefore a
**ban**, not a pick:

```
banned  = union over every reached container of
          (all media its packages cover) - (all media the selected package covers)
allowed = the event's media - banned
```

Unset groups use the container's authored `DefaultSwitch`; a media id no
container covers (a plain layer on its own Play action) is never banned; the
identity is returned when the ban would empty the event (a port must not go
silent). This is exact for parallel Play-action containers and for nested ones.

Measured on `Play_FS_Player_Walk` (319 media ids):

| Selection | Kept | Surface clips |
|---|---:|---|
| unset (authored defaults) | 38 | default branch (Stone) |
| `FS_Material=Stone`, gait Walk, Cotter, Local, Layers Nothing | **44** | 16 Stone-family, **0** Carpet/Tile/Dirt/Mud/Grass/ShallowWater/Puddle/Slime/Metal/Electrical/Wood surface clips |
| `FS_Material=WoodFloor` (same rest) | 44 | the bank's WoodBeam family (8), 0 Stone |
| `FS_Material=Carpet` | 45 | Carpet + the ShallowWater family (the Carpet package shares a node with ShallowWater) |
| `FS_Material=Stone` + `FS_Layers=Puddle` | 52 | Stone + the Puddle layer |

The 12 loot-bag foley and 16 cloth/metal garment layers survive every selection
because they are separate Play actions no switch container covers — correct, not
a leak.

## 4. RTPC curves: exact vs approximated

- `Linear` and `Constant` segments are exact (Wwise semantics); out-of-range
  values clamp to the endpoints; a single-point curve is constant.
- `Exp1/2/3`, `Log1/2/3`, `S-Curve`, `Inverse S-Curve` segments are evaluated
  **linearly** and counted in `curve_report().approximated` (`PORT_APPROX`).
  Godot exposes no formula for them and the port does not invent one.
- Wwise filter percent -> Hz is `20 * 2^(v/10)` (0 -> 20 Hz, 100 -> 20480 Hz).
  Applied only to the `low_pass`/`high_pass` params; measured 44% -> 422.2 Hz on
  the authored id-only RTPC `2141048674`.
- Measured on the detection RTPC's music node (`MusicRandomSequenceContainer:248405997`,
  points `[0,-1] [0.20189,-1] [1,0]`): 0 -> **-1.0 dB**, 0.6 -> **-0.5012 dB**,
  1 -> **0 dB**. Pitch on `MusicRandomSequenceContainer:405990808`
  (`[0,0] [0.17547,62] [1,86]`): 0 -> **1.0**, 0.6 -> **1.0439** (+74.36 cents),
  1 -> **1.0507** (+86 cents).

## 5. Wired vs deferred

**Wired (this slice).**

Footstep surface -> authored `FS_Material` value (the table the runtime uses;
derived by measuring which bank package carries the family's media, so `wood`
is `WoodFloor` — the package that carries the wood/beam samples — not a guess):

| Port surface key | Authored value | Evidence |
|---|---|---|
| `stone` | `Stone` | package 1216965916 carries `FS_Thief_Walk_Stone-*` |
| `carpet` | `Carpet` | package 2412606308 carries `FS_Thief_Walk_Carpet_*` |
| `metal` | `MetalGrate` | package 320551647 carries `FS_Thief_Walk_MetalGrate_*` |
| `wet` | `ShallowWater` | package 2306839888 carries `FS_Thief_Walk_ShallowWater_*` |
| `earth` | `Dirt` | package 2195636714 carries `FS_Thief_Walk_Dirt/Mud_*` |
| `glass` | `Glass` | package 2449969375 (plays the `MetalPipe` recordings; authored reuse, §2) |
| `wood` | `WoodFloor` | package 3111880208 carries the `WoodBeam` recordings + the wood layer |

| Control | Authored source | Runtime |
|---|---|---|
| Footstep surface | `FS_Material` (14 values) | `play_footstep()` sets the value from the surface key, then filters the token pool by the authored package media. |
| Footstep/movement gait | `Character_Movement_Mode` (5 values) | same call, from `thief_character._audio_gait()` (walk/run/crouch). |
| Locally controlled | `Character_IsLocallyControlled` | set to `Local` once at load (single-player build); `Remote` never set. |
| Interior/exterior | `Weather_isExterior` state | `set_environment(indoor)` sets `Interior`/`Exterior` alongside the existing authored reverb send. |
| Modal | `Modal_State` state | the pause transition sets `Modal_Menu`/`Modal_Gameplay` alongside the existing -19 dB duck. |
| Detection level | `Character_Enemy_Detection_Level_RTPC` | `set_detection_level(0..1)` (polled from `guards` group `get_alert_state().suspicion` at 250 ms) drives the authored music-node **gain** (music player volume) and **pitch** (music player `pitch_scale`). |

**Deferred, with the exact reason.**

- **State *property* application.** State groups carry per-node volume/pitch/LPF
  rows (e.g. `Weather_isExterior=Interior` mutes one weather node to -108 dB; 15
  rows on `Player_HeightenedSenses`). They are emitted and exposed through
  `state_override_rows()`, but a global bus cannot reproduce a per-node override
  and this slice does not claim one. No node is muted.
- **Music switch containers** (`Music_Switch_Escape`, `Music_Switch_Phase`):
  `DecisionTree` keys are unbound (§2); music remains the T03 `start_music()`
  path only.
- **`Character_Select` / `Enemy_Identity` / `PhysmatImpact_*` /
  `MissionEndScreen_CountSpeed_Switch` / `IsInteractablePropLocal` /
  `Music_Phonograph_Player_MusicPlaylist` / `FS_Layers`**: values are authored and
  selectable, but nothing calls them yet. Footsteps leave `FS_Layers` at its
  authored `Nothing` default; the layer (puddle/glass-broken/foliage/grass) needs
  the surface resolver's layer input, not a new invention.
- **RTPC low-pass application to the mix**: generic `low_pass_hz()` exists and is
  tested, but none of the 16 **named** RTPCs carries a low-pass curve, so no
  named control drives a filter yet. The two authored LPF curves are on id-only
  RTPCs (no asset dump); wiring one would need a caller that owns that id.
- **Volume for the detection RTPC on the Music bus**: deliberately applied to the
  *music player*, not the bus. The bus level is the slider + authored trim + duck
  contract pinned by `test_audio_mix.gd`; adding a per-frame RTPC term there
  would fight it and change that gate's numbers without an authored justification.

## 6. Gates run (this lane, private data copy)

```bash
python3 tools/parse_audio_control.py                 # AUDIO_CONTROL_OK switch=14/23 switch_values=84 state=4/8 state_values=10 rtpcs=16/50 curves=142 containers=185 package_media=13146 events=180
python3 tools/parse_audio_control.py --check         # same line, exit 0
python3 tools/check_consumers.py                     # CONSUMER AUDIT PASS (audio_control.json is runtime-read)
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"   # scripts checked: 215, broken: 0
tools/godot --headless --path game --script res://tests/test_audio_control.gd       # AUDIO_CONTROL_SUMMARY: fails=0 checks=71
tools/godot --headless --path game --script res://tests/test_audio_mix.gd           # AUDIO_MIX_SUMMARY: fails=0 passed=49
tools/godot --headless --path game --script res://tests/test_audio_lifecycle.gd     # AUDIO_LIFECYCLE_SUMMARY: fails=0
```

Fail-closed behaviour was also proven with a synthetic asset tree (three
conflict classes: same (group,value) with two names, two name prefixes in one
group, two groups claiming one name) — each raised `ControlConflict` and wrote
nothing; a clean pair loaded. That harness is not committed (it mutates
`CONTROL_ROOTS`); the committed gate asserts the same invariants on real data
through `--check` (duplicate ids, unknown group/container references, canonical
bytes, absolute-path leaks).

Suite 121 is registered in `run_tests.gd` as a child process, so `make test`
runs it and requires `AUDIO_CONTROL_SUMMARY: fails=0 checks=71`.

The lane did **not** run `make audit` to green: `python3 tools/manifest_audit.py
--min-coverage 0.99 --min-exact-coverage 0.99` exits 1 with exactly two
baseline-only failures, both of which are the integrator's re-stamp —

```
FAIL: baseline: no entry for producer tools/parse_audio_control.py; regenerate with `python3 tools/parse_audio_control.py` then run --refresh-stamps
FAIL: baseline: infrastructure root:Makefile changed since the baseline; regenerate with `make extract / make normalize` then run --refresh-stamps
```

— while every content check (levels, tables, materials, containers, devices,
animations, audio, localization, videos, scene variants, Niagara) passes and the
consistency/coverage gate does not complain about the new output. This lane must
not touch `tools/audit_baseline.json`. E2E and a GPU capture were not run.

`make test` (the full `run_tests.gd`, which now runs suite 121 as a child
process) is green on the lane tree: `SUMMARY: fails=0`, with
`PASS: 121 W10-P3 audio control ... (937 ms)`. The suite itself measured
`AUDIO_CONTROL_SUMMARY: fails=0 checks=71` standalone.

## 7. Reproduce

```bash
python3 tools/parse_audio_control.py && python3 tools/parse_audio_control.py --check
flock /tmp/opencode/tat2-godot.lock -c 'tools/godot --headless --path game --script res://tests/test_audio_control.gd'
```
