# W6G — authored guard hearing / perception (S1a + S1b)

Wave: W6G (worker worktree `/tmp/opencode/tat2-w6g-logic`, based on `f803c3b`).
Scope owned: `game/src/ai/hearing_data.gd` (new), `game/src/stealth/noise_bus.gd`,
`game/src/ai/guard_ai.gd`, `game/src/core/weather_profile.gd` (SoundCarry
accessor only), device noise emitters, standalone hearing tests. No edits to
`game_data.gd`, `save_system.gd`, `level_loader.gd`, `thief_character.gd`, UI or
the mission controller.

## Data consumed

Producer output `tools/parse_hearing.py` + `tools/parse_gameplay.py`
(gitignored generated tables, regenerated, not edited):

| table | count | use |
|---|---|---|
| `hearing.json` `stimuli` | 54 | authored hearing stims: MaxRange, Inner/OuterInvestigationRange, severity, propagation, heard-by, behaviours, query bitmask |
| `hearing.json` `loudness_modifiers.by_surface` | 22 | surface loudness parity with `guard_ai.json` |
| `hearing.json` `weather_sound_carry` | 11 | weather type -> `Weather.SoundCarry.*` tag + multiplier |
| `perception.json` `senses` | 2 | shared range modifiers (hearing, vision_guard) |
| `guard_ai.json` `escalation_tables` | 2 profiles / 7 rows | GuardBase Fresh/Mindful/Vigilant/Drowsy, Bouncer Fresh/Mindful/Vigilant |
| `hearing.json` `acoustic_portals` | 285 | exposed read-only; runtime occlusion layer stays W6.3 |

Ranges are metres in the runtime layer (`metric` mirror, cm fallback only when
the mirror is absent).

## What changed

### 1. `game/src/ai/hearing_data.gd` (new)

Single cached reader/normaliser for the tables above:

* 54-row stim registry by full and short tag; unknown -> `{}` (fail closed).
* Authored range anomalies clamped once and logged once, raw values kept:
  `LockPicking.Picked` outer 5.0 -> 3.0 m, `Alert.ShareKnowledge` outer 30 -> 15,
  `EnterExitHedge` / `Device.SecretSwitch` outer 8 -> 7.5, `Tool.DartLaunch`
  inner 3.0 > outer 2.0 reordered.
* `heard_by(stim, faction)` and `accepts_query(stim, mask)` (opaque authored
  bitmask; the listener supplies its accepted mask).
* `resolve_port_tag` / `resolve_stim(tag, gait)` map port emitter tags:
  `noise_alarm -> Trap.NoiseAlarm` (15 m), `bottle -> ImpactGeo` (10 m),
  `takedown -> Takedown` (2.5 m), `door`/`lock -> OpeningCreak` (5 m),
  `lockpick -> LockPicking.Picked` (3 m), `footstep -> Walking 4 m / Running
  20 m by gait`. Legacy tags (documented `LEGACY_TAGS`) keep
  `min(loudness, HearingRange)`.
* Weather multiplier, perception modifier product (Nervous 1.2, SoundCarry
  High_Extra 1.25, ...), Drowsy/Asleep vision x0.1.
* Surface loudness + parity check against `guard_ai.json` (all 22 rows).
* Read-only portal accessor (`acoustic_portal_count()` = 285).

### 2. `game/src/stealth/noise_bus.gd`

`emit_noise` signature and the `noise_emitted(origin, loudness, source, tag)`
signal are unchanged (AudioManager, HUD SoundWaves, E2E and suite 55b keep
working). Every emission now also builds a record and emits
`noise_record_emitted(record)` carrying the resolved stim row, gait, surface,
surface multiplier and the legacy final loudness. `build_record()` is pure and
callable from tests. Gait for the `footstep` tag comes from the source flags
(`is_sprinting` / `is_crouching`) with the port's authored loudness bands
(<=2 crouch, >=6 sprint) as the fallback for sourceless callers.

### 3. `game/src/ai/guard_ai.gd`

* Listens to `noise_record_emitted`; `_on_noise_emitted(...)` remains as a
  backwards-compatible wrapper.
* Authored radius:
  `min(stim.MaxRange x surface multiplier, HearingRange x weather x perception)`.
  The authored MaxRange replaces the old `min(loudness, 25 m)` clamp for mapped
  tags; the legacy path is unchanged for unmapped tags.
* `heard_by` (hostiles) and the query bitmask gate the stimulus.
* Investigation: exact stim location inside the authored outer band, otherwise
  the deterministic midpoint of the inner..outer band on the guard's side.
  Short/Long selection comes from `behaviors`; Long sets an 8 s post-search fan
  (Short 4 s), mirroring `ST_InvestigateStims_Guard` Short/Long Investigation.
* **Hearing no longer writes the 0..100 meter.** It raises alertness through the
  existing `_set_state` transition (SUSPICIOUS from NEUTRAL; `guard_alert` keeps
  its authored ALERTED path and may set `ever_spotted` when a real alerted guard
  is the caller). The old `detection = maxf(..., 25/60)` writes are gone.
* Weather sound carry resolved once per guard from the map's authored weather
  tag (`WeatherProfile.sound_carry_multiplier_for_map`, indoor = the Den preset).
* Escalation: `guard_ai.json` GuardBase/Bouncer rows drive sight/lose/FOV per
  alertness (NEUTRAL Fresh, SUSPICIOUS/SEARCH Mindful, ALERTED/COMBAT Vigilant,
  KNOCKED_OUT Drowsy + x0.1 Asleep). A caller/test that pins `sight_range`
  disables further authored writes for that instance, so E2E LOS probes that
  set 40/200 m are never overwritten.
* **Single light:** removed the port-only `vis_mult` ramp multiplier. Light now
  affects acquisition RANGE only (authored
  `C_LightIntensityToRangeMultiplier`); the new pure
  `detection_gain_per_second(dist, crouch, sprint, height)` is the one ramp and
  is light-independent. 15/45/100 thresholds retained.
* `get_alert_state()` exposes the resolved hearing diagnostics
  (`hearing_multiplier`, `last_heard_stim`, `last_heard_distance_m`,
  `last_heard_radius_m`, `investigation_kind`).

### 4. `game/src/core/weather_profile.gd`

SoundCarry accessor only: `weather_tag_for_map`, `sound_carry_for_map`,
`sound_carry_multiplier_for_map`, `map_is_indoor`. The tag join lives in
`hearing_data.gd`, so the 11 authored rows have one reader.

### 5. Device emitters

`noise_alarm.gd` and `alarm_eye.gd` keep their tags and metre loudness
(`noise_alarm` 15 m, `guard_alert` 25 m) — the bus now resolves
`noise_alarm` to the authored 15 m `Trap.NoiseAlarm` stim, and `guard_alert`
stays on the documented legacy path so the 12/14 m guard shout and the 25 m
alarm eye do not widen or cascade (see balance risks). Suite 70.4b/70.7 keep
their exact tag/loudness/state assertions.

### 6. Tests

* `game/tests/test_hearing_ranges.gd` (new, 39 checks).
* `game/tests/test_light_once.gd` (new, 7 checks).
* Suite 26 (`run_tests.gd` block 26): new assertion `W6G single light path`
  (detection gain equal at 0.05 and 0.95 light; no `vis_mult`; no hearing
  detection writes). The pre-existing decay-transition check now starts from
  "an arbitrary high meter value (the sight ramp owns it since W6G)" instead of
  the stale "heard-only guard sets 60" comment — the assertion itself is
  unchanged.
* Suite 55b: asserted contract updated, not weakened. It previously required
  `detection > 0` after a heard footstep (hearing seeded the meter). W6G removes
  that by design, so 55b now requires `state != 0` **and**
  `detection == 0` **and** the resolved authored stim
  (`Footstep.Walking` at 5 m, `Footstep.Running` at 8 m). Evidence: the old
  meter write is the exact behaviour this wave deletes; the new assertion is
  strictly stronger about the new contract.

## Measured evidence (this worktree, serial, one Godot at a time)

```
compile (tools/check_scripts_compile.gd) : scripts checked: 104, broken: 0
run_tests.gd                             : SUMMARY: fails=0  (262 PASS)
test_hearing_ranges.gd                   : HEARING_RANGES_SUMMARY: fails=0  (39 PASS)
test_light_once.gd                       : LIGHT_ONCE_SUMMARY: fails=0  (7 PASS)
test_m2_player.gd                        : M2_SUMMARY: fails=0  (11 PASS)
```

`XDG_DATA_HOME=/tmp/opencode/w6g-data` for every run. No E2E tier was run in
this worker (per the wave brief: focused tests only); the merged checkout must
re-run the full gate set. `make audit` / `make texture-cap-check` were **not**
run here — no generated data changed, but they remain part of the merge gate.

New scripts have no `.gd.uid` yet (Godot writes them on the next editor/import
scan); nothing in the wave depends on the UID.

## Balance risks (measured deltas, all authored)

| stimulus | port (before) | W6G authored | delta |
|---|---|---|---|
| sprint footstep on glass/stone | 8 m x1.5 = 12 m | `min(20 x1.5, 25)` = 25 m | +13 m |
| walk footstep on glass | 3.5 x1.5 = 5.25 m | `min(4 x1.5, 25)` = 6 m | +0.75 m |
| crouch footstep on glass | 1.5 x1.5 = 2.25 m | `min(4 x1.5, 25)` = 6 m | +3.75 m |
| takedown | 4.5 m | 2.5 m | -2 m |
| lockpick | 4-5 m | 3 m | -1..2 m |
| lock / door | 3 / 5.5 m | 5 m each | ±0.5..2 m |
| thrown bottle | 10 m (port APPROX) | 10 m (`ImpactGeo`) | 0 |
| noise alarm | 15 m | 15 m (`Trap.NoiseAlarm`) | 0 |
| guard shout / alarm eye | 14/12/25 m | unchanged (legacy) | 0 |

* The footstep jump is the largest one: crouch-walking on hard surfaces becomes
  audible at ~6 m (was ~2.25 m) and sprinting at up to 25 m (was ~12 m). Carpet,
  grass, foliage, dirt and ivy remain silent (surface x0.0). If playtesting
  finds stealth too punishing, the honest lever is a lower emitter loudness or a
  crouch-specific authored row, not re-clamping the stim in the guard.
* Removing `vis_mult` makes close-range detection ramp at the authored rate in
  darkness (up to ~2.9x the old 0.35 floor) — but the authored light->range
  curve still collapses acquisition to 15 % of the sight range at zero light
  (20 m -> 3 m), so acquisition in shadow is still heavily gated. This is the
  intended single-light behaviour; it should be watched in the playtest matrix.
* `guard_alert` deliberately stays on the legacy path: mapping it to
  `NPC.CallForHelp` (30 m) would widen every guard shout and cascade alerts
  across a level, and would break the authored 25 m alarm-eye contract (suite
  70.7: 20 m ALERTED / 26 m NEUTRAL). Documented in `LEGACY_TAGS`.

## RE gaps / inferences (not verified against shipped runtime)

1. **Query bitmask semantics** (30/62/86/127) are not recovered. The listener
   gate is bit-intersection with a guard mask of 127 (accept all); no per-family
   filtering is claimed.
2. **Investigation target**: the shipped tree moves to the stim location and
   then runs EQS for nearby locations; it does not expose the runtime pick. The
   50 % inner..outer band point is an inference from the property names.
3. **Weather indoor/outdoor** side uses the existing preset classification (the
   Den is the only indoor preset); per-room acoustics belong to the deferred
   portal layer.
4. **`Status.Nervous` 1.2** is plumbed through `perception_tags` but nothing
   authors that tag in the port yet (stays 1.0).
5. **Escalation profile selection** is name-based (`bouncer`/`haunt` ->
   AIC_Bouncer), the same hint the skeleton/weapon-set choice already uses. There
   is no exported faction/profile field in the port.
6. **Bouncer has no authored Drowsy row** — KO keeps the last conscious sense
   values and only the x0.1 Asleep modifier applies.
7. **`lockpick` conflates Picked/Jammed** in the port emitters (read-only files
   this wave); it resolves to `LockPicking.Picked`. A follow-up should split the
   tags so a jammed pick uses `LockPicking.Jammed` (10 m).
8. **285 acoustic portals**: data accessor only. No occlusion, no
   `PropogateThroughOpenPortals` runtime, no portal-aware attenuation (W6.3).
9. `guard_alert` is the only stim-shaped legacy tag; the remaining
   `LEGACY_TAGS` are port-only feedback with no authored hearing row.
