# P0b route runner v1 — staged/mixed 27-beat capture

**Status:** harness built and headless-verified. The first real port capture
(**route1**, `4341439`) was `status=partial` because the S06 ledger hook called
`_show_tab` on the CanvasLayer instead of the `LedgerUI` Control; the hook is
fixed and the second capture (**route2**) is **all-green**: 13 captured / 14
deferred / 0 partial / 0 frame errors / 17 frames, exit 0. **Route2-clean**
(Phase 0b, **`912a481`**, `git.dirty=false`) reproduces the same result and is
now the **provenance reference**; route2 remains the historical
`git.dirty=true` run that carried the S06 fix before it was committed. The
**120-row re-score is still not done** (and the live Steam capture is
untouched). See [§6](#6-measured-evidence) for all runs and the measured
lines.

- Runner: `build/qa/p0b_route.gd` (`extends SceneTree`)
- Wrapper: `build/qa/p0b_route.sh` (owns the shared flock, Xvfb, timeout; exports
  `TAT2_PARITY_ONLY=1` for every mode)
- Schema: `tat2.p0b_route/1` — a **compatible** superset of the six-pose
  `tat2.p0b_capture/1`; `poses[]` is **replaced by** `beats[]` (see §3)
- Reference times/labels: `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` §2
  (mirrored in `build/qa/p0b_audio_stats.py` `REFERENCE_BEATS`)

---

## 1. Scope, and the claim boundary

The repo had a six-fixed-pose capture (`build/qa/p0b_capture.gd`) but no
multi-beat runner. A **fully played** 27-beat route is blocked by known port
defects and missing infrastructure, so v1 is explicitly **staged/mixed**:

- `route_claim` is always `"none"`.
- **13 beats are planned to be staged** through live UI/API hooks on the real
  scenes. A dry run records them as `status=planned` with **no PNG and no
  frames**; `counts.captured=0`.
- **14 beats are deferred** with a specific reason.
- The official S01–S27 start/end times are **provenance anchors**, not
  wall-clock targets. The run does not align to the clip.
- Staged frames call the audio tap's generic `mark()` only. The tap's
  S01–S27 beat entry point (`mark_beat`) is **never called**, so a fixed/staged
  frame cannot claim a played-beat alignment. `--self-test` scans the runner
  source and fails if either token appears.

`captured` is a **capture-only** state: a beat is `captured` only when a real
frame was saved, validated non-black, and every planned frame for that beat
succeeded. Dry runs never print or store a **nonzero** `captured` count; they
print `planned=13` and keep `counts.captured=0`.

This is **not** a played route and **not** the 120-row baseline. (Under a
Dummy driver the audio tap records `enabled=false` with a reason; route2 ran
with a real device and `audio.enabled=true`, but that audio is recorded, not
scored.) A later lane maps these 27 rows onto
`docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`.

### Free-play disclosure (staged substitute)

The Guildhall stage uses free play
(`GameState.begin_free_play('Mission.Guildhall.LootTheRoom')`) on contract 2 —
only to show the KF13 briefing letter over the live safe room. **It is not the
official mission selection:**

- the 2026-11-24 port baseline ran `Mission.Guildhall.LootTheRoom`,
  `Contract.Main.2`, Novice/Solo with **`free_play=false`**
  (`docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md:12-13`);
- the canonical contract-2 Guildhall row is
  **`Mission.Guildhall.VaultHeist`**; `LootTheRoom` is a side-mission row
  (`docs/reports/contract-flow.md:51,57-59`).

The manifest records this explicitly: `level.free_play_substitute=true`,
`level.official_free_play=false`, `level.historical_mission_id`,
`level.canonical_mission_id`. The 120-row scorer **must not treat this
free-play combination as the official one**.

---

## 2. Commands

```bash
# Manifest only, no scene, no GPU render (headless). Tracked manifest + log.
build/qa/p0b_route.sh --dry-run
# -> P0B_ROUTE_DRY_RUN beats=27 planned=13 deferred=14 schema=tat2.p0b_route/1

# Table/schema checks, no scene, no GPU render.
build/qa/p0b_route.sh --self-test
# -> P0B_ROUTE_SELFTEST PASS checks=62 fails=0

# The real staged capture (route1/route2/route2-clean; see §6).
build/qa/p0b_route.sh --tag=route2-clean
```

The wrapper's default mode is capture (run it with no mode flag); the runner
accepts `--mode=capture`. `--dry-run` and `--self-test` are explicit and always
headless; they instantiate no scenes and run no renderer or `nvidia-smi` query
(`gpu.queried=false`, `gpu.reason="headless"`). `--tag=` and `--seed=` are
optional.

Outputs:

| Mode | Media | Tracked evidence |
|---|---|---|
| dry-run | none | `docs/reports/logs/p0b-route/dry-run/manifest.json`, `dry-run.log` |
| self-test | `build/qa/p0b_route/selftest/` (audio sidecar) | `docs/reports/logs/p0b-route/self-test/self-test.log` |
| capture | `build/qa/p0b_route/<run_id>/<beat>_<frame>.png` + `audio.*` | `docs/reports/logs/p0b-route/<run_id>/manifest.json`, `capture.log`, `capture.log.gpu_before/after` |

`build/qa/p0b_route/**` is gitignored media. The dry-run manifest/log are
tracked, as in the P0b six-pose harness. `P0B_ROUTE_EVIDENCE_DIR` overrides the
evidence root for a later wave's own logs; a real capture always writes under
`docs/reports/logs/p0b-route/`.

### Exact GPU command

```bash
build/qa/p0b_route.sh --tag=route2
```

which runs, under the shared flock and Xvfb:

```bash
cd <repo> && timeout 1800 \
  xvfb-run -a -s '-screen 0 1920x1080x24' \
  tools/godot --path game --rendering-driver vulkan \
  --script "$PWD/build/qa/p0b_route.gd" -- \
  --mode=capture --seed=derived --run-id=<run_id>
```

Measured all-green result (route2):
`status=captured beats=27 captured=13 deferred=14 partial=0 staged_failed=0
frame_errors=0 frames=17 errors=0 exit_ok=true`.

**Exit semantics (no silent pass).** The run exits non-zero unless **all** of
the following hold: the manifest writes, `manifest_errors` is empty,
`partial=0`, `staged_failed=0`, `frame_errors=0`, and `status=="captured"`.
A hook that fails defers the beat; a planned secondary frame that fails marks
the beat `partial` (never `captured`); both force a non-zero exit and are named
in the manifest. `frames=17` is the all-green count for S01(1)+S02(1)+S03(1)+
S04(1)+S05(1)+S06(2)+S08(2)+S09(1)+S10(1)+S11(1)+S12(1)+S24(3)+S27(1); the
separate Lounge reference pose is in `extras[]`, not counted as a beat frame.

---

## 3. Manifest schema (`tat2.p0b_route/1`)

**Compatible** superset of the six-pose `tat2.p0b_capture/1`, not a drop-in
replacement: every provenance field of the six-pose manifest is present
(`schema`, `run_id`, `dry_run`, `self_test`, `started_at_utc`, `repo_root`,
`out_dir`, `git{sha,sha_short,branch,dirty}`, `host`, `gpu`, `engine`, `lens`,
`settle`, `seed`, `env`, `beam_card`, `audio`, `notes`), but the pose array is
**replaced by** `beats[]` (and a beat may carry `frames[]`). The six-pose
`poses[]` key does not exist here.

| Block | Content |
|---|---|
| `base_schema` | `"tat2.p0b_capture/1"` (the compatibility marker) |
| `mode` | `"staged"` |
| `route_claim` | `"none"` (validator rejects anything else) |
| `video` | reference clip metadata only: 225.642333 s, 3840×2160, 29.672 avg fps, 6,696 frames, AAC 48 kHz stereo, 30 keyframes |
| `level` | staged contract/mode plus the **free-play substitute** fields (`free_play_substitute=true`, `official_free_play=false`, `historical_mission_id`, `canonical_mission_id`) and the disclosure note |
| `store` | `source` = `owner_restore` \| `fresh`, `path`, `exists`, `sha256`, `schema_version`, `load_failed`, bounded `profile` + `settings`. Read-only: the runner never calls `write_save`. |
| `settings` | staged difficulty/mode/order/map/thief/free_play/resolution |
| `counts` | `beats`, `captured`, `planned`, `deferred`, `partial`, `frames`, `frame_errors`, `plan_staged`, `extras` |
| `beats[27]` | one row per official beat, in S01…S27 order |
| `extras[]` | non-beat reference poses (the Lounge C_57 `beam_close`), `beat=""`, `ref_keyframe=null` |
| `audio` | the Master-tap result, `mark_kind="mark"`, `route_claim="none"` |

Every beat row carries:
`id`, `label`, `official_start_s`, `official_end_s`, `class`
(`ui|world|camera`), `ref_keyframe`, `source` (`staged|absent`), `status`
(`captured|planned|deferred|partial`), `reason`, `stage_hook`, `png`, `t_s`,
`frame_no`, `eye`, `target`, `camera_source` (`ui|synthetic|player|mission`),
`mark_kind` (always `"mark"`), `staged`, `evidence`, plus `frames[]` and
`frame_errors[]`.

- `t_s` is seconds since the capture start (monotonic wall clock), not an
  official-clip time; `frame_no` is the ordinal of the saved staged frame in
  this run.
- `camera_source` names where the pixels came from: S03 is `synthetic`
  (Den-wide pan); S12, S24 and the Lounge extra use the **player camera**
  (`mission.player.cam`, feet = eye − 1.67, yaw/pitch, `base_fov=cam.fov=54.54`,
  physics/process frozen for the still); S05 uses the mission's `_ponder_cam`
  (`mission`); UI beats are `ui`.
- `eye`/`target` are `[]` for UI screens and 3-number arrays for world poses.
- A captured beat's `evidence` names the hook call that produced the frame.
- `partial` means at least one planned frame is missing; `reason` names the
  first failure, `frame_errors[]` lists all of them, and the row keeps the
  frames that did succeed. It is never reported as `captured`.
- Deferred rows carry a non-empty `reason`; staged rows carry a non-empty
  `stage_hook`.

Validation (runs in every mode and in `--self-test`): schema/mode/claim,
lens 54.54 / 1920×1080 / KEEP_HEIGHT, settle 60/5/median-mean, seed, video
duration, store source/path, exactly 27 unique ordered ids, monotonic times,
`end > start`, allowed class/source/status, deferred/partial reason, staged
hook, `mark_kind == "mark"`, a `camera_source` for captured world/camera beats,
dry-run rows have no PNG and stay `planned`, dry-run `gpu.queried=false`,
captured rows have a PNG/`t_s`/`frame_no`/`evidence`/`frames` and no
`frame_errors`, partial rows keep a PNG/reason/frames, counts match the rows
(captured/planned/deferred/partial/frames/frame_errors), `extras` never claim a
beat, and dry-run audio is disabled with a reason.

### The scorer does not consume this schema

`build/qa/p0b_roi_stats.py --validate-manifest` requires
`tat2.p0b_capture/1` **and** a `poses[]` array; a `tat2.p0b_route/1` manifest is
**rejected** (by design — the scorer was not changed). `--all` likewise expects
the six-pose capture layout. Route frames must be scored:

- per frame with `--port <png> --pose <id>` for the six pose ids it knows
  (`gate`, `upper_foyer`, `yaw180`, `lounge`, `lounge_beam`, `beam_close`), i.e.
  S24's `upper_foyer`/`yaw180` and the Lounge extra can be scored that way; or
- through a later **translation lane** that maps route rows/frames to the
  scorer's expectations.

Route frames outside that set (`foyer_beam`, UI beats, S03, S05, S12) are not
consumable by the current scorer and must not be claimed as scored.

---

## 4. Beat status (v1)

`planned` = in the v1 capture plan (no frame exists until the GPU run);
`deferred` = out of scope with the reason recorded in the manifest. `ref` is
the reference keyframe. The table's "v1" column is the plan; §6 records what
actually ran (route2 captured the 13 planned beats; the 14 deferred ones stay
deferred with their reasons).

| Beat | Official span | Class | Ref | v1 | Hook / blocker |
|---|---|---|---|---|---|
| S01 | 0.00–2.15 | ui | KF01 | planned | `main_menu.gd` real startscreen over its 3D backdrop |
| S02 | 2.15–2.60 | ui | KF12 | planned | `loading_screen.start_loading('', '', 'guildhall')` + `set_progress(0.62)` |
| S03 | 2.60–6.57 | world | KF02 | planned | Den mission (`order=1`), synthetic Den-wide camera (`camera_source=synthetic`) |
| S04 | 6.57–18.24 | ui | KF03/KF04 | planned | `open_wardrobe_ui()` → `open_customizer()` |
| S05 | 18.24–26.58 | camera | KF05/KF06 | planned | `toggle_telescope_ponder()`; **no exit** (L4-13); mission `_ponder_cam` |
| S06 | 26.58–38.17 | ui | KF07/KF08 | planned | `open_ledger_ui()` → `_show_tab(0)` journal, `_show_tab(1)` black market |
| S07 | 38.17–51.08 | world | KF09 | **deferred** | Multi-subject (decoration swap, boot-trail decals, gramophone, trunk cycle) and no camera/pan driver; two interact hooks exist but a single prop frame would misrepresent the beat |
| S08 | 51.08–56.08 | ui | KF10 | planned | `set_den_selected_map('guildhall')` + `open_contract_table_ui()` + `open_confirm()`; Novice/Solo kept |
| S09 | 56.08–64.80 | ui | KF11 | planned | `open_prep('guildhall', 1, 'Solo', 2, true)` (Contract Inactive) |
| S10 | 64.80–69.44 | ui | KF12 | planned | second `start_loading` + `set_progress(0.31)` |
| S11 | 69.44–70.81 | ui | KF13 | planned | Guildhall free play (`order=2`, `LootTheRoom`; **staged substitute**), `hud.is_mission_letter_open()` |
| S12 | 70.81–80.10 | world | KF14 | planned | safe-room dressing + `SafeRoomLanternStation.set_lit(true)` observed `lit=true`, player camera at the authored `TATSafeRoomPlayerStart_0` eye; missing lantern/`set_lit`/`lit` defers |
| S13 | 80.10–99.30 | world | KF15 | **deferred** | Needs catwalk→alley vault/sprint/crouch/car input; no driver; `BARRON'S DEMOLITION` asset absent (HARD_LIMIT) |
| S14 | 99.30–109.50 | camera | KF16 | **deferred** | `[1]` equip / gate aim / 1st zipwire / planter landing; no stable still-stage hook |
| S15 | 109.50–118.50 | world | KF17 | **deferred** | 2nd zipwire + ~7 s crank input; depends on S14 |
| S16 | 118.50–131.00 | world | none | **deferred** | Roofline + 3rd zipwire; depends on S14/S15; no linked keyframe |
| S17 | 131.00–143.30 | world | KF18 | **deferred** | Cable crossing, gear plate, courtyard fall damage; needs prior state |
| S18 | 143.30–150.70 | world | KF19/KF20 | **deferred** | Throw input + plume VFX (Niagara HL-1 stand-in) |
| S19 | 150.70–153.00 | camera | KF21/KF22 | **deferred** | Needs a live guard at the portico + `[4]` scan (no NPC in view; C4-08/L4-08) |
| S20 | 153.00–174.50 | world | KF23 | **deferred** | ~21 s terrace traversal with a patrol guard |
| S21 | 174.50–184.50 | world | KF24 | **deferred** | Approach + `[F] OPEN` blue doors + walk-through; content proven, traversal not |
| S22 | 184.50–197.10 | world | KF25 | **deferred** | Live constable + crouch + `[F] PICK POCKET` |
| S23 | 197.10–202.00 | camera | KF26 | **deferred** | `[HOLD] TAKEDOWN` needs the S22 guard and input |
| S24 | 202.00–209.00 | world | KF27 | planned | **Foyer only:** `upper_foyer` + `yaw180` + `foyer_beam` at the authored C_107 card cue `(27,29.67,-55)->(23.27,29.76,-57.4)`; player camera. A missing/hidden card makes the beam frame `partial` with `beam_visible=false` |
| S25 | 209.00–217.40 | world | KF28 | **deferred** | Requires crossing the foreground beam; firing `_spawn_foyer_lockdown` directly would be a faked played beat |
| S26 | 217.40–221.90 | world | KF29 | **deferred** | Depends on S25 + stair traversal |
| S27 | 221.90–225.64 | ui | KF30 | planned | `hud.toggle_pause()` over the `upper_foyer` backdrop; tap set to `PROCESS_MODE_ALWAYS` before the pause |

**13 planned / 14 deferred.** Staged frames per beat: S01 1, S02 1, S03 1,
S04 1, S05 1, S06 2, S08 2, S09 1, S10 1, S11 1, S12 1, S24 3, S27 1 → **17
beat frames**, plus one non-beat Lounge reference pose in `extras[]`.

Den stage order is deliberately **S03 → S04 → S06 → S08 → S05**: S05 enters the
telescope view and the staged runner does not drive the key exit (the live
`[F] EXIT` path is fixed in Phase 3C; the input-driven assertion lives in
`game/tests/probe_den_window.gd` and the short `route_driver.gd` segment).
Guildhall order is S11 (letter) → S12 (safe room) → S24 (foyer poses) → Lounge
extra → S27 (pause last).

### S24 pose identity (KF27)

- `upper_foyer` `(27,29.67,-50)->(27,29.67,-60)` and `yaw180`
  `(27,29.67,-50)->(27,29.67,-40)` are the p0b **foyer** slots.
- `foyer_beam` `(27,29.67,-55)->(23.27,29.76,-57.4)` is the live KF27 foyer cue
  aimed at the authored `BP_Detector_LightBeam_C_107` card
  (`build/qa/w9/facts-a4.md:576`). If no visible `lightbeam_cards` member is
  within 1.5 m of that card, the frame is recorded `partial` with
  `beam_visible=false`; the Lounge pose is **not** substituted.
- The p0b `beam_close` pose `(39,28.82,-28.97)->(42.4,28.9,-28.97)` is the
  **Lounge C_57** beam, not KF27. It is captured as the labelled extra
  `extras[0] = {id:"lounge_beam_close", subject:"Lounge C_57 beam",
  ref_keyframe:null, beat:""}` and can never be read as an S24 frame.

Hooks confirmed in the tree before writing the runner: `open_wardrobe_ui`,
`open_ledger_ui`, `open_contract_table_ui`/`open_confirm`, `open_prep`,
`start_loading`/`set_progress`, `toggle_telescope_ponder`, `hud.toggle_pause`,
`SafeRoomLanternStation.set_lit`, `player.head`/`player.cam`/`base_fov`,
`main_menu.gd`, `mission.tscn`. No hook was added or changed in `game/`.

---

## 5. Blockers recorded, not hidden

- **L4-13 — FIXED (Phase 3C).** The telescope scope now pushes an
  `InputContext` gameplay modal (`telescope_ponder`) and zeroes the body's
  velocity on entry, so a held forward key cannot carry the player into the
  west opening; `[F] EXIT` restores the player camera with the body still
  inside the Den. Verified by `game/tests/probe_den_window.gd`
  (`DEN_WINDOW PASS checks=44`, including a real-key `[F] PONDER`/`[F] EXIT`
  block) and by the short driver segment
  (`build/qa/route_driver.gd`, `S05` driven, frozen drift `0.000 m`).
- **No NPC population on the route — re-measured (Phase 3C).** At this HEAD
  the same Novice Contract 2 spawn yields 4 guards + 3 civilians at
  **85.4–150.7 m** from the route anchor (`game/tests/probe_route_npcs.gd`;
  the old "nearest 48.1 m" note is superseded). S19/S20/S22/S23 stay
  unreachable and are recorded as such, not faked.
- **No full continuous input driver — partially closed (Phase 3C).** A
  deterministic input driver exists (`build/qa/route_driver.gd` + wrapper)
  and drives the short `den_telescope` segment (S03 arrival + S05 scope
  enter/exit); the 27-beat traversal is still not driven. `route_claim` stays
  `none`.
- **S25/S26 staging would be fake** — the ward/alarm hooks exist
  (`_spawn_foyer_lockdown`, `security_beam.beam_triggered`) but firing them
  without the player crossing the beam would label a staged lockdown as the
  played beat.
- **S07 has two interact hooks** (decoration pedestal, gramophone) but the
  authored beat is a multi-subject sequence with no camera/pan driver; v1
  defers it rather than capturing a partial beat.
- **`S16` has no linked reference keyframe** in the index; the row says
  `none` rather than inventing one.
- **Free-play substitute** — see §1; not the official mission selection.
- **Scorer gap** — `p0b_roi_stats.py` does not consume `tat2.p0b_route/1`
  (see §3); most route frames need a translation lane.

---

## 6. Measured evidence

### Measured runs (port only, Xvfb Vulkan, no Steam)

All runs used the port build only, one Godot at a time, the wrapper's shared
flock, Xvfb `1920x1080x24`, and `--rendering-driver vulkan`. Wall is the
manifest `started_at_utc`→`finished_at_utc` span; the wrapper adds ~5 s of
launch overhead (route2 wrapper wall: 193 s; route2-clean wrapper wall: 207 s).

| Run | Tree | Status | captured | partial | deferred | frames | frame_errors | wall | exit | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| route1 | `4341439` (clean) | `partial` | 12 | 1 | 14 | 16 | 1 | 193 s | 1 | `docs/reports/logs/p0b-route/route1/` |
| route2 | `4341439` + S06 fix (dirty) | `captured` | 13 | 0 | 14 | 17 | 0 | 188 s | 0 | `docs/reports/logs/p0b-route/route2/` |
| **route2-clean** | **`912a481` (clean)** | **`captured`** | **13** | **0** | **14** | **17** | **0** | **201 s** | **0** | **`docs/reports/logs/p0b-route/route2-clean/`** |

route1 exact line:

```
P0B_ROUTE_CAPTURE_DONE status=partial beats=27 captured=12 deferred=14 partial=1 staged_failed=0 frame_errors=1 frames=16 errors=0 exit_ok=false
```

route1's only failure was **S06**
(`partial_capture: 1 frame(s) failed; first=black_market: ledger_ui._show_tab
missing`). Root cause: `mission_controller.open_ledger_ui()` adds a plain
`CanvasLayer` holding a `LedgerUI` Control; `_find_ui_node("ledger_ui.gd")`
returned the **layer**, and `_show_tab` lives on the **Control**
(`game/src/ui/ledger_ui.gd:552`). The journal frame saved, the Black Market
frame did not. Everything else was green: S24 `beam_visible=true` with 3/3
frames, S12/S27 captured, audio enabled (189.1 s).

Fix (runner only, no game code): `_find_ui_control(host, "ledger_ui.gd")`
returns the scripted `Control`; S06 keeps `_find_ui_node` for the layer null
check and `_free_ui`, and calls `_show_tab` on the Control. S06 defers unless
both the layer and the Control exist, and is never captured unless both the
journal and Black Market frames are saved.

route2 exact line:

```
P0B_ROUTE_CAPTURE_DONE status=captured beats=27 captured=13 deferred=14 partial=0 staged_failed=0 frame_errors=0 frames=17 errors=0 exit_ok=true
```

route2 details: S06 has both `journal` and `black_market` (2/2); S24 has
`upper_foyer`/`yaw180`/`foyer_beam` (3/3, `beam_visible=true`,
`camera_source=player`); S12 (player camera, lantern lit) and S27 (paused) are
captured; the Lounge `beam_close` extra is captured; audio is enabled
(187.42 s, 19 marks, WAV+PCM+JSON); 18 PNGs total (17 beat frames + 1 extra),
all `1920x1080`, no `SCRIPT ERROR`/`SHADER ERROR`/`Parse Error` in the log.
The manifest's `git.dirty=true` is expected: route2 ran on `4341439` plus the
uncommitted S06 fix.

### Route2-clean (Phase 0b provenance reference)

Route2-clean re-ran the same staged capture on the **clean Phase 0a HEAD**
`912a481` (`git.dirty=false`), one Godot at a time, after the S06 fix was
committed. Exact line:

```
P0B_ROUTE_CAPTURE_DONE status=captured beats=27 captured=13 deferred=14 partial=0 staged_failed=0 frame_errors=0 frames=17 errors=0 exit_ok=true manifest=<repo>/docs/reports/logs/p0b-route/route2-clean/manifest.json out=<repo>/build/qa/p0b_route/route2-clean
```

Manifest facts (`docs/reports/logs/p0b-route/route2-clean/manifest.json`):

- `git`: `sha=912a481d42611cb0de77f31d4e01e63029b68190`, `branch=main`, `dirty=false`.
- `counts`: `beats=27 captured=13 deferred=14 partial=0 frame_errors=0 frames=17 extras=1`.
- `schema` / `mode` / `route_claim`: `tat2.p0b_route/1` / `staged` / `none`; lens 54.54 / 1920x1080.
- `level`: `free_play_substitute=true`, `official_free_play=false`, historical `Mission.Guildhall.LootTheRoom`, canonical `Mission.Guildhall.VaultHeist`.
- audio: enabled, 186.259 s, 19 marks, `rms=-30.32 dBFS`, `peak=-0.76 dBFS`.
- window: `2026-11-27T15:31:32Z` to `15:34:53Z` (201 s); wrapper wall 207 s.
- frames: 18 PNGs, all 1920x1080 (17 beat frames + 1 Lounge extra).

The captured beats are the same 13 as route2; S06 has both frames, S12 is
player-camera with the lantern lit, S24 has `upper_foyer`/`yaw180`/`foyer_beam`
(3/3, `beam_visible=true` at the `C_107` card `(23.27, 29.76, -57.4)`), and
S27 is the paused frame. The capture log has no `SCRIPT ERROR`, `SHADER ERROR`
or `Parse Error`; it ends with the known teardown warning (`7 RIDs of type
"Texture" were leaked`) plus the wrapper's `exit=0` line. The media stays under
the git-ignored `build/qa/p0b_route/route2-clean/`; only the manifest, log and
GPU samples are tracked.

**Provenance:** route2-clean is the clean-tree reference for any later route
score or diff. Route1/route2 are kept as the historical partial -> fixed ->
dirty-green sequence and must not be deleted. The manifest's `route_claim`
stays `none`; this is still a staged capture, not a played route.

### Headless gates (after the S06 fix)

Measured on `4341439` with `tools/godot` (Godot 4.7.2), no GPU render, no Xvfb.

```
$ bash -n build/qa/p0b_route.sh && echo "bash_n_exit=$?"
bash_n_exit=0

$ build/qa/p0b_route.sh --dry-run
P0B_ROUTE_WALL mode=dry-run exit=0 wall=1s (headless, no GPU render)
P0B_ROUTE_DRY_RUN beats=27 planned=13 deferred=14 schema=tat2.p0b_route/1 manifest=<repo>/docs/reports/logs/p0b-route/dry-run/manifest.json

$ build/qa/p0b_route.sh --self-test
P0B_ROUTE_SELFTEST_SUMMARY checks=62 fails=0
P0B_ROUTE_SELFTEST PASS checks=62 fails=0

$ tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
scripts checked: 217, broken: 0          # exit 0

$ git diff --check
(clean, exit 0)

$ git status --short
 M build/qa/p0b_route.gd
 M docs/HANDOFF_NEXT_AGENT.md
 M docs/reports/logs/p0b-route/dry-run/dry-run.log
 M docs/reports/logs/p0b-route/dry-run/manifest.json
 M docs/reports/logs/p0b-route/self-test/self-test.log
 M docs/reports/p0b-route.md
?? docs/reports/logs/p0b-route/route1/
?? docs/reports/logs/p0b-route/route2/
```

The two run directories are new evidence; the S06 fix and the regenerated
headless logs are the working-tree changes (no commit in this wave).

Dry-run manifest spot checks: `counts.captured=0`, `counts.planned=13`,
`counts.deferred=14`, `counts.partial=0`, `counts.frame_errors=0`,
`counts.extras=1` (planned Lounge reference pose), every deferred row has a
reason, every row `mark_kind=mark`, no beat row has a PNG, `gpu.queried=false
reason=headless`, `env.TAT2_PARITY_ONLY=1`,
`level.free_play_substitute=true official_free_play=false
canonical_mission_id=Mission.Guildhall.VaultHeist`, `audio.enabled=false
reason=dry_run`, `store.source=owner_restore` (the owner save was read, not
written).

**Stale class-cache note (environmental).** The first compile run in the
earlier version of this wave reported `217 checked, 1 broken` on
`res://tests/test_audio_control.gd` (`Could not find type "AudioControl"`)
because the local `game/.godot/global_script_class_cache.cfg` predated HEAD.
This is the documented fresh-worktree trap in `AGENTS.md`; running
`tools/godot --headless --path game --import` once repaired the ignored cache
and the re-run was `217/0`. No tracked file changed.

**Verified by route2:** the Vulkan staged capture runs end to end (13/13
captured, 17 beat frames, exit 0), the S24 C_107 beam card is visible
(`beam_visible=true`), and the audio tap captures with a real device (enabled,
187.42 s). **Not verified:** the 120-row re-score, any ROI/visual score of the
route2 PNGs, the audio windows against the reference levels, and the live
Steam reference capture. The audio is recorded, not scored.

---

## 7. What the next lane owes

1. **The capture is done** (route2 all-green; route2-clean at `912a481` is the
   clean-tree reference). The next action is the **120-row re-score**: map the
   27 rows/17 frames onto
   `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`, using the
   route2-clean manifest/PNGs (`docs/reports/logs/p0b-route/route2-clean/`,
   `build/qa/p0b_route/route2-clean/`). A later re-run must still produce
   `status=captured captured=13 deferred=14 partial=0 staged_failed=0
   frame_errors=0 frames=17 exit_ok=true`.
2. If S24's `foyer_beam` reports `beam_visible=false` or any beat is
   `partial`/`deferred`, fix the hook/content or record the defect here and in
   `docs/FIDELITY_GAPS.md`; never relabel a failed/partial beat as captured
   (route1's S06 is the worked example: partial, root-caused, fixed, re-run).
3. Score only the frames the current scorer understands
   (`--port <png> --pose <id>` for the six p0b poses), or build the translation
   lane; do not feed `tat2.p0b_route/1` to `--validate-manifest`/`--all`.
4. Keep the free-play substitute caveat on every row/score derived from S09/S11;
   the official selection is `Mission.Guildhall.VaultHeist` (or the historical
   `LootTheRoom` with `free_play=false`), not this staged combination.
5. Promote deferred beats only with a real driver (input recorder or NPC
   population); the staged path must not become a substitute for S13–S26.
