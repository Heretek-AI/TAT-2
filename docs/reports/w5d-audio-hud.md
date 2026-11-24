# W5D — audio lifecycle + reference Light Gem / compass

Date: 2026-11-24
Worktree: `/tmp/opencode/tat2-w5d-audio-hud` (branched from `950f7ca`)
Scope: repeating-cue lifecycle in `audio_manager.gd`, the alarm-eye loop stop,
single-player bed re-entry, the HUD Light Gem mask and the compass readout.
Wardrobe/UI text panels were explicitly out of scope.

## Defects addressed

1. **Duplicate cues.** `play_cue()` / `play_sfx()` / `play_ui()` started a new
   player for every call. Signal fan-out (button pressed + menu confirm,
   NoiseBus stimulus + explicit cue) produced the same cue at the same position
   twice in one frame.
2. **Sustained clips without a handle.** `alarm_loop`, `smoke_cloud` and
   `lightbeam_hum` are `*_Loop` clips played through the one-shot path. Every
   `alarm_eye._trigger_alarm()` started another copy and nothing ever stopped
   it; the smoke hiss had the same shape.
3. **Bed overlap.** `play_bed_scene()` called `stop_all_beds(0.2)` and then
   `start_bed()` immediately. `stop_bed()` only scheduled a fade and the player
   stayed in the tree, so two players shared one bed key for 0.2–0.35 s.
4. **Light Gem.** `STEALTH_ORB_SHADER` masked with `abs(p.x) + abs(p.y)` (a cut
   diamond) while its normals already assumed a unit sphere.
5. **Compass.** A 580 px `T_compass_lines` strip plus a 1,600 px scrolling
   label carrying every cardinal (`W · NW · N · NE …`). The reference HUD shows
   one heading at the centre tick.

## Changes

### `game/src/core/audio_manager.gd`

- `CUE_DEDUPE_MS = 120`, `_cue_last_msec` keyed `cue|position` (2D cues share
  one bucket, 3D cues use centimetre position). `_cue_duplicate()` prunes stale
  entries above 256 keys. Applied in `play_cue()`, `play_ui()` and `_play_at()`
  (therefore `play_sfx()` and `_on_noise_emitted()`).
  `play_footstep()` and the `footstep` tag are exempt: footsteps are already
  cadence-gated in `thief_character.gd`.
- `LOOP_CUES = ["alarm_loop", "smoke_cloud", "lightbeam_hum"]`. These now use
  one handle per `cue|position` (`_replace_loop_cue()`), on a looped duplicate
  of the shared Ogg (`_loop_variant()`, cached in `_bed_loop_cache`) so one-shot
  players of the same clip keep their `finished` signal.
- `stop_cue(cue, pos = null)` stops one position or every handle for the cue;
  `active_loop_cues()` exposes sorted handle keys for QA.
- `play_cue(cue, pos, duration_s = 0.0)`: a positive duration auto-stops that
  handle after the TTL, token-guarded so a replacement is never stopped by the
  previous handle's timer. `smoke_projectile.gd` passes `SMOKE_TTL_S` (25 s).
- Beds: `stop_bed()` / `stop_all_beds()` share `_fade_out_bed()`, registering
  `key -> {player, tween}` in `_fading_beds`. `start_bed()` calls
  `_cancel_fading_bed()` first: kills the fade tween and `free()`s the old
  player before creating the replacement (no same-key overlap, not even one
  frame). `cleanup_on_exit()` clears the new dictionaries.

### `game/src/devices/alarm_eye.gd`

- Stores the trigger position and a `_alarm_loop_started` flag.
- `_stop_alarm_loop()` calls `AudioManager.stop_cue("alarm_loop", pos)` and is
  invoked by `reset_alarm()` (only if this eye was alarmed), by the tick's
  lose-sight transition, on death in `take_damage()`, and in `_exit_tree()`.
  Position-keyed so an idle/other camera cannot silence a live alarm.

### `game/src/player/smoke_projectile.gd`

- The `smoke_cloud` cue is now a sustained handle with the smoke cloud's 25 s
  TTL instead of an unbounded loop.

### `game/src/ui/hud.gd`

- `STEALTH_ORB_SHADER`: `float d = length(p)` with the mask reaching the unit
  circle (`smoothstep(0.90, 1.0, d)`); sphere normals, specular, fresnel and the
  warm light sector are untouched.
- Compass: `COMPASS_DIRECTIONS`, `compass_heading_name(deg)` (nearest of eight,
  wrap-safe) and `update_compass_heading(deg)`. `_process()` writes only that
  one heading. The cardinal ribbon (`ribbon_clip` / `ribbon_lbl`) is kept as a
  preserved public property but hidden and empty. `T_compass_lines` is still
  wired (the E2E T1-14-D contract names it) as a native-size 100×30 centre
  line, so the source reference and the authored asset remain.
- `compass_lbl` is the single visible heading label at 15 px.

### Tests (standalone, not registered in `run_tests.gd`)

- `game/tests/test_audio_lifecycle.gd` — 13 checks.
- `game/tests/test_hud_gem_compass.gd` — 11 checks.

## Measured evidence

All runs sequential, native Godot 4.7.2, `XDG_DATA_HOME=/tmp/opencode/w5d-data`.

| Gate | Command | Result |
|---|---|---|
| compile | `tools/godot --headless --path game --script $PWD/tools/check_scripts_compile.gd` | `scripts checked: 98, broken: 0` (96 baseline + 2 new tests) |
| audio lifecycle | `res://tests/test_audio_lifecycle.gd` | `AUDIO_LIFECYCLE_SUMMARY: fails=0`, exit 0 (13/13 PASS) |
| HUD gem/compass | `res://tests/test_hud_gem_compass.gd` | `HUD_GEM_COMPASS_SUMMARY: fails=0`, exit 0 (11/11 PASS) |
| M2 player | `res://tests/test_m2_player.gd` | `M2_SUMMARY: fails=0`, exit 0 |

Audio evidence highlights:

```
PASS: W5D.2 scene re-entry keeps one rain player (players=1 levels=1)
PASS: W5D.4 same cue|position inside 120 ms is dropped (first=true second=false voices 1->1)
PASS: W5D.6 same cue|position plays again after the 120 ms window
PASS: W5D.8 rapid footsteps are not suppressed (cadence owns the rate)
PASS: W5D.10 re-trigger replaces the handle instead of stacking
PASS: W5D.11 alarm_eye.reset_alarm() stops its own alarm loop
PASS: W5D.12 an unalarmed eye's reset leaves other loops running
PASS: W5D.13 sustained smoke cue auto-stops at its duration (2 -> 1 handles)
```

HUD evidence highlights:

```
PASS: W5D.2 Light Gem mask is length(p) (glazed sphere, not a diamond)
PASS: W5D.3 sphere normals kept (z = sqrt(1 - dot(p,p)))
PASS: W5D.7 the full cardinal ribbon is retired (hidden, empty text)
PASS: W5D.8 authored compass strip is a small centre line (100 px)
PASS: W5D.9 exactly one visible heading label on the strip
PASS: W5D.11 StealthOrbInner material uses the circular gem shader
```

Not run in this wave (by instruction): full `run_tests.gd`, full E2E, door/
viewmodel/Niagara probes, Vulkan captures. The W5D worktree cannot re-baseline
the shared suite counts and does not claim to.

## Risks / open notes

- **120 ms dedupe is global per cue|position.** An intentional immediate
  repeat of the same cue at the same position (e.g. two UI clicks inside
  120 ms) is dropped. That is the intended fan-out fix; footsteps are exempt,
  and cadence-owned loops (countdown, beds) never pass through this path.
- **The alarm loop is shared by clip, not per camera instance.** Handles are
  position-keyed, so each camera owns its own loop. Two cameras at the *same*
  position would share one handle; a reset from either stops it. Acceptable for
  the authored placements (distinct positions), and recorded here.
- **Smoke hiss now has a 25 s TTL** rather than living forever. If the VFX TTL
  is ever changed, update the `play_cue` duration in `smoke_projectile.gd`.
- `lightbeam_hum` has a handle and a stop path but currently has no caller; the
  path is covered only structurally by the audio test.
- The retired ribbon nodes remain in the tree (hidden, empty) to preserve the
  public property contract used by callers/E2E. A later wave may remove them
  once those references are migrated.
- `_bed_loop_cache` now holds both bed and sustained-cue loop duplicates keyed
  by clip path; teardown clears it as before.
