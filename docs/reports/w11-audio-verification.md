# W11 audio lane verification — 2026-11-27 (recheck at `ac51d4b`)

| | |
|---|---|
| lane | Phase 2 / Audio W11 (A–E) |
| worktree | `/home/john/.local/share/opencode/worktree/318f41/phase2-audio` |
| branch | `w11/audio` |
| fix commit | `ac51d4b` (`fix(audio): W11-D disguise RTPC domain and player-instance rebind`) |
| parent | `1e63c79` (`feat(audio): W11 VO director, music keys, FS_Layers, RTPC callers, state census`) |
| verifier mode | read-only except this report; **headless suites only**, no GPU capture, no audio-device run, no Steam, no push |
| verdict | **PASS** — both W11-D blockers found at `1e63c79` are closed; every re-run gate is green at `ac51d4b` |

The previous revision of this file was **FAIL** at `1e63c79`: the disguise
integrity was fed into the authored RTPC as `0..100` (the curve is `0..1`), and
the player's `disguise_changed` was bound once per process although a new
`ThiefCharacter` is created for every contract. `ac51d4b` changes only
`game/src/core/audio_manager.gd`, `game/tests/test_audio_control.gd`,
`game/tests/test_vo_director.gd` and the lane report. The producer, generated
`audio_control.json`, `FS_Layers`, music and state data are untouched.

## 1. Blocker 1 — disguise RTPC domain: CLOSED

`ac51d4b` adds a single normalising entry point:

```gdscript
# game/src/core/audio_manager.gd
const RTPC_DISGUISE_MAX: float = 100.0

func push_disguise_integrity(integrity_0_100: float) -> bool:
    var value: float = clampf(integrity_0_100 / RTPC_DISGUISE_MAX, 0.0, 1.0)
    return set_rtpc("Character_DisguiseIntegrity", value)
```

`_on_disguise_changed()` now calls `push_disguise_integrity(integrity)` instead
of storing `clampf(integrity, 0.0, 100.0)`. The authored curve is untouched:

```
Character_DisguiseIntegrity (141988265), first volume curve:
[0.0, 0.0] [0.39834, -1.0] [1.0, -1.0]
```

All 8 authored volume curves still start `(0,0)` and end `(1,-1)`; the other
seven differ only in the knee. A fresh producer run is byte-identical to
`game/data/generated/audio_control.json` (`b86e73c7…`, 524787 bytes, 13
warnings; see §4).

The tests now assert the domain and the mid-knee:

```
PASS: AUD6.11 disguise 0/25/50/75/100 stores 0/0.25/0.5/0.75/1.0
PASS: AUD6.11 disguise 25 -> -0.627605 dB (mid-curve, not the -1 dB endpoint)
PASS: AUD6.11 the disguise_changed handler stores 75 as 0.75
PASS: AUD9.6 disguise curve x=0 -> 0 dB
PASS: AUD9.6 disguise curve x=1 -> exactly -1.0 dB (authored 0..1 domain)
PASS: AUD9.6 the disguise RTPC is left at the authored 1.0 (not 100.0)
```

The misleading `set_rtpc(disguise, 100.0)` restore is gone; the test restores
`1.0` and asserts `rtpc_value(disguise) == 1.0` (`test_audio_control.gd:575-578`).
The 25 → -0.627605 value is the port's existing `evaluate_curve` evaluation of
the first authored segment (the evaluator linearises non-linear `Exp1` segments
and reports that in `curve_report()`); the authored control points themselves
are unchanged. This is the value the acceptance expects and is not a new
approximation.

The four other callers keep their authored domains (unchanged by `ac51d4b`):

| RTPC | caller conversion | authored domain |
|---|---|---|
| `Character_Stamina_RTPC` | `stamina / max_stamina * 100`, clamp 0..100 | 0..100 |
| `Character_FS_isCrouching` | `1 if is_crouching else 0` | 0..1 |
| `Character_Fall_Velocity_Z` | `velocity.y * 100`, clamp -5000..500 | cm/s, -5000..500 |
| `Weather_Rain_Intensity` | `clampf(preset.rain.intensity, 0, 1)` | 0..1 |

The `blood_moon` preset still authors `rain.intensity = 10.0`; the caller clamps
to 1.0, as documented.

## 2. Blocker 2 — player-instance rebind: CLOSED

The one-shot `_vo_player_bound` bool is gone. `ac51d4b` tracks the instance:

```gdscript
var _vo_bound_player: Node = null

func _sync_vo_sources() -> void:
    ...
    if _vo_bound_player != null and not is_instance_valid(_vo_bound_player):
        _vo_bound_player = null
        if _vo_director != null:
            _vo_director.call("reset_cooldowns")
    if player == null:
        _disconnect_vo_player()
        return
    if _vo_bound_player == player:
        return
    _disconnect_vo_player()
    if not player.has_signal("disguise_changed"):
        return
    var cb: Callable = Callable(self, "_on_disguise_changed")
    if not player.is_connected("disguise_changed", cb):
        player.connect("disguise_changed", cb)
    _vo_bound_player = player
    if _vo_director != null:
        _vo_director.call("reset_cooldowns")
```

`_disconnect_vo_player()` drops the tracked connection and clears the
reference; `cleanup_on_exit()` calls it (`audio_manager.gd:472`), so no callable
into the autoload survives teardown. A freed binding is cleared by
`is_instance_valid`, a replaced live player is explicitly disconnected, and
the current player is connected once (`is_connected` guard). Cooldowns,
priority and rotation are reset when the player instance changes.

Suite 122's `VO8.1–VO8.5` drives two live `FakePlayer` instances through the
real `_process` path (not a direct call):

```
PASS: VO8.1 the first player's disguise_changed is bound exactly once
PASS: VO8.2 the first player's disguise RTPC stores 25 as 0.25
PASS: VO8.2 repeated frames do not duplicate the connection
PASS: VO8.3 the second player's disguise_changed is bound
PASS: VO8.3 the replaced player's connection is disconnected
PASS: VO8.4 the second player's 0 integrity plays the authored ending line
PASS: VO8.4 the ending line emits its functional subtitle
PASS: VO8.4 the second player's 0 integrity stores 0.0
PASS: VO8.5 the player binding is cleared when no player exists
```

The second player is added while the first is still alive (the first is only
removed from the `player` group, then freed at teardown). `VO8.4` asserts
`last_cue.cue == "disguise_ending"`, `last_cue.event ==
"Play_VO_Player_DisguiseEnding"`, a `subtitle_shown` emission containing
`DisguiseEnding`, and the stored RTPC value `0.0`. `VO8.5` removes both from the
group and `queue_free()`s them; after four frames `vo_state().bound_player` is
false.

## 3. Unchanged measurements

Recomputed at `ac51d4b` from the committed data and the director constants:

```
VO lines=645 triples=76 speakers=7 mapped=249 mapped_triples=35
unmapped=396 unmapped_triples=41
MUSIC containers=2 keys=9 resolved=6 unresolved=3 transitions=2 stingers=1 bound=4
STATE rows=183 nodes=62 bus_rows=98 bus_nodes=24 other=85 groups=7 of 8
FS event_media=319 stone_nothing=44 stone_puddle=52 added=8
```

The VO coverage distinction from the previous report still holds: 235 mapped
guard lines + 6 wired player/quest lines + 8 `caller: none` cues = 249 mapped;
the other 396 are unmapped. The `Hauntstable1` `ExertionCombat/KnockedOut` gap
is unchanged.

The producer check and fresh regeneration:

```
AUDIO_CONTROL_OK switch=14/23 switch_values=84 state=4/8 state_values=10
rtpcs=16/50 curves=142 containers=185 package_media=13146 events=180
music=2 music_keys=6/9 music_transitions=2 music_stingers=1
CHECK_EXIT=0
b86e73c7e28f16ad203cec772493bd0220294f5a48637505a5dc0b667a38b501  regen/audio_control.json
b86e73c7e28f16ad203cec772493bd0220294f5a48637505a5dc0b667a38b501  game/data/generated/audio_control.json
CMP_EXIT=0
```

Nothing in `tools/parse_audio_control.py` or the generated data changed in
`1e63c79..ac51d4b`; the private `game/data/generated` copy is byte-identical to
a fresh producer run.

## 4. Gates re-run at `ac51d4b`

All Godot invocations were `--headless`; no GPU capture and no audio-device run.
Every log below starts with `HEAD=ac51d4b…` and ends with `HEAD_AFTER=ac51d4b…`
where the script records it. Logs are in `/tmp/opencode/w11-audio-recheck/`.

| log | key lines | result |
|---|---|---|
| `short.log` | `scripts checked: 219, broken: 0`; `AUDIO_CONTROL_SUMMARY: fails=0 checks=123`; `VO_DIRECTOR_SUMMARY: fails=0 checks=53`; `M2_SUMMARY: fails=0` (12 `PASS:` lines); all exits 0 | PASS |
| `make_test.log` | `PASS: 121 …`, `PASS: 122 …`; `SUMMARY: fails=0`; `PASS_LINES=325`; `MAKE_TEST_EXIT=0` | PASS |
| `e2e_leak.log` | `SUMMARY: fails=0 passed=300 total=300`; `PROBE after gh free players=0`; `E2E_EXIT=0`, `LEAK_EXIT=0` | PASS |
| `runtime_smoke2.log` | `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok`; `RUNTIME_SMOKE PASS`; `SMOKE_EXIT=0` | PASS |
| `producer_data.log` | `CHECK_EXIT=0`; `CMP_EXIT=0`; identical hashes | PASS |
| `counts.log` | the exact counts in §3 | PASS |
| `string_greps.log` | `UI_STRINGS total=311 routed=311 authored=199 routed_authored=199 invented=112`; `LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0 files=107`; exits 0 | PASS |
| `git.log` | `HEAD=ac51d4b…`; branch `w11/audio`; parent `1e63c79…`; `REMOTE_CONTAINS_HEAD` empty | no push |

Log sha256 (each file's first line is `HEAD=ac51d4b2413b5257965172f3ff520484745e4aa1`):

```
40ed7472ebdd7356163f47fa40198259e538e80b67f2ca3dee80768112dada2f  short.log
ddd406b4cc210d568c497d2d42a060c5bfbcbdf97ca9e8c1d72efe7fd0523c4d  make_test.log
fd483b7f106718cdd77ace90c618095e8b6b878e764b36382a9672c51f9f0d6a  e2e_leak.log
a2bf5b65dcfb0e25f6c571fce9d0b1552c4ce8817cd781a9342863e27b228734  runtime_smoke2.log
5b45780e98dd62879dd189a0888a65d33b455aadd662c2bc7929aaf56a13bbf1  producer_data.log
332c7d0b06a260e73fdd3446301b34d3f6a957276d54e0873795c8ff8a357180  counts.log
77a27572dd326dc4244d499275e55b1bc9f07948c53c5c0fc0825e2ae2ecdca1  string_greps.log
1552b09dcf822bb0e072cffb08c5a0deffc17fa56420bf8daabb4ba61cce35c7  git.log
```

`make test` still prints **325** `^PASS:` lines: the suite count is **122**
(suite 121 now 123 checks, suite 122 now 53), but the parent counts one PASS line
per suite plus its inline assertions, not each child-suite check.

The first runtime-smoke attempt (`runtime_smoke.log`) used an outer 300 s
timeout while another lane held `/tmp/opencode/tat2-godot.lock`; it was killed
while waiting for the lock and produced no scan line. It is superseded by
`runtime_smoke2.log` (1800 s outer timeout, the script's own internal lock,
90 s free-play window). No game failure occurred in the discarded attempt.

The lane's own post-fix transcript independently reports the same
`AUDIO_CONTROL_SUMMARY: fails=0 checks=123`, `VO_DIRECTOR_SUMMARY: fails=0
checks=53`, `SUMMARY: fails=0` with 325 PASS lines, E2E 300/300, leak exit 0 and
`RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 mission_ready=1`; the logs above are
the post-commit re-run.

## 5. Residual risks (recorded)

**Accepted — cooldowns reset on player change.** `_sync_vo_sources()` calls
`reset_cooldowns()` whenever the tracked player is freed or replaced. This is
intentional: a new contract starts with a clean bark budget and the new player's
`disguise_ending` line cannot be suppressed by the previous player's guard
barks. Cost: a bark can repeat across a contract boundary, and if a player node
is replaced mid-run the director's cooldowns/priority/rotation reset then too.
Suite 122 manually resets the director before the second emit, so the automatic
reset is code-verified but not directly asserted. Low; accepted.

**Accepted — per-frame `get_first_node_in_group("player")`.** `_sync_vo_sources`
runs every `_process` and does one group lookup plus an identity/validity check.
The port is single-player (one node in the group), the call allocates nothing,
and it sits beside the existing per-frame `_sync_environment()` /
`_sync_detection()`. If profiling ever shows a cost, replace it with group
add/remove signals or a cached weak reference. Low; accepted.

**Flagged low — single-player first-in-group policy.** `get_first_node_in_group`
binds the first player; a co-op build would need a per-player policy. The port
is single-player; accepted for this lane.

**Flagged low — `RTPC_DISGUISE_MAX = 100.0`.** The conversion constant matches
the player's current integrity maximum (`disguise_integrity` starts/resets at
100.0). If that maximum changes, the constant must change; the authored curve
does not. Low.

**Flagged low — same-player early return trusts the connection.** When the
tracked player is still current, `_sync_vo_sources` returns without re-checking
`is_connected`; an external disconnect of that Callable would not be repaired
until the player instance changes. No system disconnects it today. Low.

**Pre-existing, accepted — curve interpolation.** The `25 → -0.627605 dB` value
is the existing `evaluate_curve` linear evaluation of the authored `Exp1`
segment (`curve_report()` counts these approximations); the authored control
points are untouched, and this is the acceptance value. Not introduced by
`ac51d4b`.

None of these is a remaining blocker for W11-A..E.

## 6. Documentation check

The lane report (`docs/reports/w11-audio-20261127.md`) was updated in `ac51d4b`
and the previous verification's documentation nits are resolved:

- branch header now `w11/audio`;
- `NoiseHeard/*` is 61 unmapped (80 family total, 19 mapped);
- `Metal` is layer-only; `FS_Material` has `MetalGrate`/`MetalPipe`/`MetalSheet`
  and `Slime`; the port's `metal` token maps to `MetalThick`/`MetalGrate`;
- `FS_Layers` defaults are 4×`Nothing`, 2×`Foliage`;
- the five curves target `ActorMixer`, `LayerContainer` and
  `RandomSequenceContainer` nodes;
- suite 121 is 71 → 123 (the 52 added checks sum: music 15, selection 3, layers
  3, RTPC 15, state 7, runtime 9); suite 122 is 53;
- `make test` is described as 325 `^PASS:` lines, suite count 122.

## 7. Hand-off

1. Integrate the private `audio_control.json` (byte-identical here) and run
   `--check`.
2. Re-stamp `tools/audit_baseline.json` for `tools/parse_audio_control.py` and
   `gen:audio_control.json`; the `vgmstream` environment drift recorded in the
   previous pass is unchanged by this fix.
3. Raise the ratchet from a serial `build/qa/run_final_gates.sh` run:
   `compile.checked` 219, `run_tests.passes` 325,
   `test_audio_control.checks` 123, suite 122 at 53. Do not hand-edit without
   the log.
4. Update `docs/HANDOFF_NEXT_AGENT.md` §4.5 and `docs/FIDELITY_GAPS.md` audio
   rows (control plane 123 checks; music 6/9; `FS_Layers` wired; 249/645 mapped;
   state 183/62/98/24/85).
5. The lane branch is local; no push. This report is the only docs commit
   after `ac51d4b`.

**Verdict: PASS.** Both W11-D blockers are closed with code, data and suite
evidence; the VO index, music control plane, `FS_Layers`, RTPC domains, state
census, producer output and every re-run gate are green at `ac51d4b`.
