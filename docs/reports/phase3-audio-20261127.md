# Phase 3B.3 — audio domains, unrecoverable IDs, VO wiring, `FS_Layers` proof

**Lane:** Phase 3B.3 (audio), worktree
`/home/john/Projects/.teamwork-worktrees/20261127-1810-phase3/audio`, branch
`teamwork/20261127-1810-phase3-audio`, base = the merged 58-gate baseline
(`55fb588`). **Headless only:** no GPU, no Master tap, no audio-device run.

This report records what was **measured**, what was **wired**, and what is
**not recoverable from the cook**. It does not claim a full Wwise parity: the
control plane is still the W11 slice (14/23 switch groups, 4/8 states, 16/50
RTPCs), and 357 of the 645 authored VO lines still have no owning system.

## 1. What changed

| Piece | File | What it owns |
|---|---|---|
| 3B.3a converter | `game/src/core/weather_profile.gd` | `rain_intensity_01()` — the ONE preset → authored-0..1 converter; `rain_intensity()` stays the raw accessor. Warning bookkeeping: `rain_domain_warnings()`, `rain_domain_warned_presets()`, `reset_rain_domain_warnings()`. |
| 3B.3a call sites | `game/src/core/weather_visuals.gd` (`make_rain`, `make_lens_rain`), `game/src/missions/mission_controller.gd` | all three read the converter; the divergent `0..1`, `0..1.5` and `0..1` clamps are gone. |
| 3B.3c VO director | `game/src/core/vo_director.gd` | `GUARD_BEAT_CUES` + `vo_pick_guard_beat()`; `mapped_events()` covers it; `report().guard_beat_cues`. |
| 3B.3c VO runtime | `game/src/core/audio_manager.gd` | `play_vo_guard_beat(cue, speaker, pos)`; `vo_state().last_beat`. |
| 3B.3c VO callers | `game/src/ai/guard_ai.gd` | `_play_exertion_vo()`; called from `take_knockout()` (survived hit) and `_play_guard_attack()` (melee swing). |
| 3B.3a/b/d suites | `game/tests/test_audio_control.gd`, `game/tests/test_vo_director.gd` | converter + warning path (AUD9.7–9.9), `FS_Layers` double-ban measurement (AUD8.4–8.6), guard beats + census (VO4.4–4.7, VO7.5). |

No generated data was regenerated. `game/data/generated/audio_control.json`,
`audio_wwise.json` and `weather/*.json` are read unchanged.

## 2. 3B.3a — `blood_moon` rain: one converter, one domain

### 2.1 The measured defect

The authored `Weather_Rain_Intensity` RTPC curve is authored in **0..1**
(`0 → -1.0 dB`, `0.65 → 0.0 dB`, suite 121 AUD9.5), and every shipped preset
that enables rain is in that interval:

| preset | authored `rain.intensity` |
|---|---:|
| `gloomy`, `heavy_rain`, `stormy`, `example_rain_and_wind` | 1.0 |
| `dusk_stormy` | 0.5 |
| `example2` | 0.1 |
| the off rows (`dense_fog*`, `midnight_clear*`) | 1e-06 (rain disabled) |
| **`blood_moon`** | **10.0** |

Before this lane three call sites clamped the same value to three ceilings:

| caller | old clamp | `blood_moon` result |
|---|---|---|
| `mission_controller.gd:945` (RTPC) | `0..1` | 1.0 |
| `weather_visuals.gd:447` (rain particle count) | `0..1.5` | **1.5** |
| `weather_visuals.gd:566` (lens shader) | `0..1` | 1.0 |

So the preset rendered 1.5× the full rain volume while its audio and lens read
1.0. No loaded map uses `blood_moon` (`map_weather.json` maps
`guildhall→gloomy`, `old_manor→dense_fog_old_manor`,
`thieves_den→midnight_clear_thieves_den`, `jaspering_hall→heavy_rain`,
`main_menu→midnight_clear_mission_lobby`), so this is a content-preset fix, not
a change to any shipped map's mix.

### 2.2 The converter (documented, not invented)

`WeatherProfile.rain_intensity_01(preset)`:

* in-domain (0..1) → **unchanged**;
* out-of-domain → **saturated at the nearest endpoint** + `push_warning` once
  per preset id (every occurrence counted by `rain_domain_warnings()`);
* no `rain.intensity` → `null` (the caller keeps its default).

It is a **domain saturation, not a unit conversion**: `10.0` is **not** divided
by 10 and **not** read as a percentage, because no authored unit for it has been
recovered. The documented values pinned by suite 121 are:

| input | output | note |
|---:|---:|---|
| 10.0 (`blood_moon`) | **1.0** | endpoint saturation, warning emitted |
| 0.0 | 0.0 | — |
| 1.0 | 1.0 | — |
| 0.5 / 0.65 | 0.5 / 0.65 | in-domain pass-through |
| −2.0 | 0.0 | low-endpoint saturation, warning emitted |
| missing | `null` | caller default kept |

End to end, the converted `blood_moon` value (1.0) evaluates the authored curve
at its `1.0 → 0.0 dB` endpoint (AUD9.9). The five shipped in-domain presets take
no warning path (AUD9.9).

**Open data item (owner, not this lane):** `blood_moon` authors `10.0` in a
0..1 field. If that value means a 10× storm it must be re-authored (or the
producer must emit its unit); the port saturates and reports it.

## 3. 3B.3b — IDs that are **not recoverable from the cook**

Both items below were previously described as "pending extraction". They are
not pending: the cook does not contain the data.

### 3.1 The 3 unresolved music decision keys

`1363461318`, `2658483646`, `4218600605` (and the stinger trigger `547253114`)
have **no authored value name**. Re-measured evidence:

* the bank's decision-tree keys are `AkSwitchValue` **ids**; 6 of 9 resolve to a
  named value (`Music_Switch_Phase_*`, `Escape_*`), 3 have no name dump;
* there is **no `AkTrigger` object anywhere in the extraction**
  (`grep -rl AkTrigger extracted` → 0 files), so the stinger trigger id cannot
  be named.

`AudioControl.music_select()` refuses them with `unresolved_key` and returns the
id, never an invented name (suite 121 AUD7.4). This is final: the names are not
in the package.

### 3.2 The 24 unnamed `AudioBus` objects

The state table carries **98 rows on 24 `AudioBus` nodes** (suite 121 AUD10.2).
Those buses are anonymous in the cook:

* `audio_wwise.json` reports **91 `AudioBus` objects, 0 named** (`audio_buses:
  91`, `named_buses: 16` — but all 16 named objects are `kind: "aux"` `VERB_*`
  reverb buses, none of which carries a state row);
* the state rows reference the buses by **id only**.

So per-node state overrides cannot be reproduced on a named global bus, and the
port reports them rather than inventing 24 names. **Not recoverable from the
cook**; the only routes are an authoring-side name dump or a `Wwise` project
file, neither of which is in the shipped package.

## 4. 3B.3c — VO lines whose owning systems exist

### 4.1 Wired (39 authored lines, 2 triples)

| Port beat | Authored triple | Lines | Owning system (already existed) |
|---|---|---:|---|
| `taking_damage` | `ExertionCombat/TakingDamage` | 30 (`Enforcer1`) | `GuardAi.take_knockout()`, non-lethal hit only (`health > 0`) |
| `attacking` | `ExertionCombat/Attacking` | 9 (`Enforcer1`) | `GuardAi._play_guard_attack()`, the melee swing |

The damage bark is played **before** the `ALERTED` transition so its priority 55
wins the director's 2 s window and a heard/hit guard does not also shout a sight
line; the lethal path stays silent and the existing `ExertionCombat/KnockedOut`
KO bark owns it. Cooldowns: 6 s damage, 5 s attack.

**Measured authored gap:** `Hauntstable1` recorded **neither** triple, so both
beats refuse for a Hauntstable rather than borrowing the Enforcer1 recordings
(suite 122 VO4.5). This is the same class as the existing `ExertionCombat/
KnockedOut` gap.

### 4.2 Census after wiring

| | before | after |
|---|---:|---:|
| authored VO lines | 645 | 645 |
| mapped through a cue (`mapped_events()`) | 249 | **288** |
| unmapped / counted | 396 | **357** |

Suite 122 VO4.7 pins `288` mapped and `645 - 288 = 357` unmapped, so the census
cannot drift silently.

### 4.3 The remaining 357 lines, by owning subsystem gap

Every row below is a partition of the 357 unmapped lines: each authored
`(speaker, verb, state)` bucket appears in **exactly one** row, and the `Lines`
column sums to **357** (sum check recorded in §4.4). Every family has **no
owning system in the port** (verified by grepping the shipping code, not
assumed). Each stays indexed and is playable by name through
`play_vo_event()`; none is invented or re-mapped onto another event.

| Lines | Family (authored rows) | Owning subsystem gap |
|---:|---|---|
| 74 | `IdleAloneOnPatrol/NonSpoken` (Enforcer1 40) + `/NearOtherGuard` (Enforcer1 19, Hauntstable1 15) | **Ambient patrol chatter** — no idle-bark scheduler / proximity chatter system. `IdleAloneOnPatrol/Idle` *is* mapped (wake-up), these variants are not. |
| 19 | `Enforcer1_HauntstableDSP/IdleAloneOnPatrol/NonSpoken` (19) | **DSP speaker** — an authored DSP-variant speaker with no owning system. Counted here **only**, never inside the idle-chatter row above. |
| 48 | `ThiefObserved/InsidePrivateZoneFoundThief` (Enforcer1 26, Hauntstable1 9) + `/InsidePrivateZoneTooLongSuspicious` (Enforcer1 4, Hauntstable1 5) + `/InsidePrivateZoneTooLong` (Hauntstable1 4) | **Private-zone trespass** — no private/locked-zone system exists (`grep private_zone` → none). |
| 61 | `NoiseHeard/LowSeverityNoise` (Enforcer1 10, Hauntstable1 10) + `HighSeverityNoise` (Enforcer1 2) + `HighSeverityNoiseSearching` (Enforcer1 10, Hauntstable1 10) + `NothingFoundLowSeverity` (Enforcer1 9, Hauntstable1 10) | **Hearing exists, but the bark is already owned**: a heard noise raises `NEUTRAL→SUSPICIOUS`, whose guard transition (`ThiefSeen/VisionStim`) already barks; wiring both would double-bark. The two `LowSeverityNoiseSearching` buckets (19) are already mapped through the `NEUTRAL>SEARCH` transition and are NOT in this row. |
| 40 | `GenericStim/React` (Hauntstable1 21) + `ExertionCombat/React` (Enforcer1 14) + `Exertion/AffectedBySoundEmitter` (Hauntstable1 5) | **Generic stimulus "React"** — the port's stimulus reactions are the alertness transitions (already mapped); no distinct generic-react beat. |
| 14 | `IncorrectStateObserved/General` (10) + `/FixedGeneral` (4) | **Object-state observation** — no "this door should be closed / this object moved" guard observation system. |
| 19 | `BrokenObjectObserved/Chest` (4) + `/Door` (4) + `/InitialSightingOfBrokenObject` (4) + `/InspectionOfBrokenObjectGeneral` (4) + `/Window` (3) | **Broken-object observation** — `break_container` exists as a player action, but no guard observation beat. |
| 1 | `MainQuestLoot/ContainerSeenOpen` (1) | **Open-container observation** — no quest-loot observation beat. |
| 49 | `ThiefObserved/ChasingThiefFightingThenFlees` (Enforcer1 10 + Hauntstable1 8 = 18) + `/ChasingThiefKnockOutThief` (Enforcer1 10 + Hauntstable1 9 = 19) + `/ChasingThiefLostTargetEvaded` (Enforcer1 4 + Hauntstable1 8 = 12) | **Combat sub-behaviours** — the FSM has no flee, thief-KO or evade sub-state. |
| 8 | `SmokeGrenade/Cough` (8) | **Smoke exposure** — smoke only blocks LOS (`is_blocked_by_smoke`); guards are never "in" the cloud. |
| 9 | `WakingUp/AboutToWakeUp` (9) | **KO timer** exists, but there is no authored pre-wake threshold; wiring would invent the timing. |
| 8 | `WakingUp/RevivedByAlly` (8) | **Ally revive** exists, but the revived guard already plays `WakingUp/RevivedSelf` on `KO→NEUTRAL`; a second line would double-bark. |
| 5 | `SlippingLosingBalance` (5) | **`slip_puddle` → `play_slip()` exists**, but `play_slip()` forces the KO which already barks `ExertionCombat/KnockedOut`; a third line in the same frame is a mix decision left open. |
| 1 | `InsultFairy/Active/OneOffs` (1) | **InsultFairy** — no insult system in the port. |
| 1 | `Silent/Empty` (1) | **Authored silence** (0 media) — refused by design, counted, never played. |
| **357** | **15 rows, each authored bucket in exactly one row** | — |

### 4.4 Sum check (recorded)

Round 2 fixed three defects in the §4.3 table: `BrokenObjectObserved/*` was 15
and had dropped `Door`'s 4 (now **19**), the combat trio used two single-speaker
counts (now **18 + 19 + 12 = 49**), and the 19 DSP idle lines were listed inside
the idle-chatter row as well as in their own row (now **only** their own row,
with the 74 idle-chatter row re-derived as `40 + 19 + 15`). The check below
parses the §4.3 table from this file, rebuilds the mapped/unmapped partition
from the authored index and the director's three const tables, and asserts that
each tabulated row equals its buckets' sum, that the rows sum to 357, that the
mapped/unmapped split stays 288/357, and that the three corrections hold. Run
from the repository root:

```
$ python3 - <<'EOF'
import json, re

# 1) DOCUMENT SIDE — parse the §4.3 rows (first cell all digits) and sum them.
doc = open("docs/reports/phase3-audio-20261127.md").read()
sec = doc.split("### 4.3 ")[1].split("### 4.4 ")[0]
rows = [int(m) for m in re.findall(r"^\| (\d+) \|", sec, re.M)]
assert (len(rows), sum(rows)) == (15, 357), (len(rows), sum(rows))

# 2) DATA SIDE — rebuild mapped/unmapped from the authored index + the director.
d = json.load(open("game/data/generated/audio_wwise.json"))
idx = {}
for l in d["vo"]["lines"]:
    idx.setdefault((l["speaker"], l["verb"], l["state"] or ""), []).append(l["event"])
src = open("game/src/core/vo_director.gd").read()
pairs = lambda b: re.findall(r'"verb": "([^"]+)", "state": "([^"]*)"', b)
triples = lambda b: re.findall(
    r'"speaker": "([^"]+)", "verb": "([^"]+)", "state": "([^"]*)"', b
)
g = src[src.index("const GUARD_CUES") : src.index("const EVENT_CUES")]
b = src[src.index("const GUARD_BEAT_CUES") : src.index("const EVENT_CUES")]
e = src[src.index("const EVENT_CUES") : src.index("const PRIORITY_HOLD_S")]
mapped = {
    ev
    for verb, st in pairs(g) + pairs(b)
    for sp in ("Enforcer1", "Hauntstable1")
    for ev in idx.get((sp, verb, st), [])
}
mapped |= {ev for sp, verb, st in triples(e) for ev in idx.get((sp, verb, st), [])}
rem = {k: n for k, v in idx.items() if (n := len([x for x in v if x not in mapped]))}
assert (len(mapped), 645 - len(mapped)) == (288, 357) == (288, sum(rem.values()))

# 3) The three round-2 corrections, asserted against the authored buckets.
broken = sum(n for k, n in rem.items() if k[1] == "BrokenObjectObserved")
trio_states = (
    "ChasingThiefFightingThenFlees",
    "ChasingThiefKnockOutThief",
    "ChasingThiefLostTargetEvaded",
)
trio = [
    rem[("Enforcer1", "ThiefObserved", s)] + rem[("Hauntstable1", "ThiefObserved", s)]
    for s in trio_states
]
dsp = sum(n for k, n in rem.items() if k[0] == "Enforcer1_HauntstableDSP")
idle_only = sum(
    n
    for k, n in rem.items()
    if k[1] == "IdleAloneOnPatrol" and k[0] != "Enforcer1_HauntstableDSP"
)
assert broken == 19 and rem[("Enforcer1", "BrokenObjectObserved", "Door")] == 4
assert trio == [18, 19, 12], trio
assert dsp == 19 and idle_only == 74, (dsp, idle_only)

# 4) The table is a partition: each remaining bucket is in exactly one row.
F = [
    [
        ("Enforcer1", "IdleAloneOnPatrol", "NonSpoken"),
        ("Enforcer1", "IdleAloneOnPatrol", "NearOtherGuard"),
        ("Hauntstable1", "IdleAloneOnPatrol", "NearOtherGuard"),
    ],
    [("Enforcer1_HauntstableDSP", "IdleAloneOnPatrol", "NonSpoken")],
    [
        ("Enforcer1", "ThiefObserved", "InsidePrivateZoneFoundThief"),
        ("Hauntstable1", "ThiefObserved", "InsidePrivateZoneFoundThief"),
        ("Enforcer1", "ThiefObserved", "InsidePrivateZoneTooLongSuspicious"),
        ("Hauntstable1", "ThiefObserved", "InsidePrivateZoneTooLongSuspicious"),
        ("Hauntstable1", "ThiefObserved", "InsidePrivateZoneTooLong"),
    ],
    [k for k in rem if k[1] == "NoiseHeard"],
    [
        ("Hauntstable1", "GenericStim", "React"),
        ("Enforcer1", "ExertionCombat", "React"),
        ("Hauntstable1", "Exertion", "AffectedBySoundEmitter"),
    ],
    [
        ("Enforcer1", "IncorrectStateObserved", "General"),
        ("Enforcer1", "IncorrectStateObserved", "FixedGeneral"),
    ],
    [
        ("Enforcer1", "BrokenObjectObserved", s)
        for s in (
            "Chest",
            "Door",
            "InitialSightingOfBrokenObject",
            "InspectionOfBrokenObjectGeneral",
            "Window",
        )
    ],
    [("Enforcer1", "MainQuestLoot", "ContainerSeenOpen")],
    [("Enforcer1", "ThiefObserved", s) for s in trio_states]
    + [("Hauntstable1", "ThiefObserved", s) for s in trio_states],
    [("Enforcer1", "SmokeGrenade", "Cough")],
    [("Enforcer1", "WakingUp", "AboutToWakeUp")],
    [("Enforcer1", "WakingUp", "RevivedByAlly")],
    [("Enforcer1", "SlippingLosingBalance", "")],
    [("InsultFairy", "Active", "OneOffs")],
    [("Enforcer1", "Silent", "Empty")],
]
covered = [k for keys in F for k in keys]
assert [sum(rem[k] for k in keys) for keys in F] == rows, "row composition != table"
assert len(covered) == len(set(covered)) == len(rem) and set(rem) == set(covered)
assert 357 - sum(rem[k] for k in covered) == 0

print(
    "OK rows=%d sum=%d mapped=%d unmapped=%d broken=%d trio=%s dsp=%d idle_only=%d leftover=0"
    % (
        len(rows),
        sum(rows),
        len(mapped),
        645 - len(mapped),
        broken,
        trio,
        dsp,
        idle_only,
    )
)
EOF
OK rows=15 sum=357 mapped=288 unmapped=357 broken=19 trio=[18, 19, 12] dsp=19 idle_only=74 leftover=0
```

The check is a partition proof, not only a total: each of the 15 rows is
recomputed from its authored buckets and must equal the row as written, and the
covered buckets must equal the remaining set exactly (`leftover=0`), so no line
is counted twice (the DSP 19 is disjoint from the 74 idle-chatter lines) and
none is dropped.

## 5. 3B.3d — the 5 unproduced `FS_Layers` values: the double-ban claim is REFUTED

### 5.1 What was claimed (W11 §4)

`MetalPipe`, `MetalSheet`, `Glass` are shared `FS_Material` families, so
"re-selecting them as a layer would ban the same clips twice"; `Metal` is
layer-only; `Slime` is a tool effect.

### 5.2 Measured from the authored switch containers

There are six `FS_Layers` switch containers; the footstep events reach
`466898861` and `900964187` (Walk/Run/Jog/Crouch/Jump_Land), the slide event
reaches `641948873`/`957265292`, `167586207` (Jump_Land) owns 0 media and
`913320700` (WallClimb) owns Foliage only.

Authored media per layer value (voices = media, no extra branches):

| value | 466898861 | 900964187 | 641948873 | 957265292 | 167586207 | 913320700 |
|---|---:|---:|---:|---:|---:|---:|
| MetalPipe | 0 | 0 | 0 | 0 | 0 | 0 |
| MetalSheet | 0 | 0 | 0 | 0 | 0 | 0 |
| Metal | 0 | 0 | 0 | 0 | 0 | 0 |
| Slime | 0 | 0 | **5** | **3** | 0 | 0 |
| Glass | **5** | **5** | 0 | 0 | 0 | 0 |
| Puddle | 8 | 9 | 5 | 5 | 0 | 0 |
| Glass_Broken | 10 | 10 | 0 | 0 | 0 | 0 |
| Foliage | 8 | 10 | 0 | 0 | 0 | 7 |
| Grass | 8 | 10 | 0 | 0 | 0 | 0 |
| Nothing | 0 | 0 | 0 | 0 | 0 | 0 |

Selection result on `Play_FS_Player_Walk` (319 media), `FS_Material=Stone`
(baseline **44** — the same 44 suite 121 AUD4.8 pins):

| `FS_Layers` | selected | lost from baseline | added |
|---|---:|---:|---:|
| Nothing | 44 | 0 | 0 |
| MetalPipe | 44 | **0** | 0 |
| MetalSheet | 44 | **0** | 0 |
| Metal | 44 | **0** | 0 |
| Slime | 44 | **0** | 0 |
| Glass | 49 | **0** | +5 |
| Puddle | 52 | 0 | +8 |
| Foliage | 52 | 0 | +8 |
| Grass | 52 | 0 | +8 |
| Glass_Broken | 54 | 0 | +10 |

### 5.3 Verdict: **REFUTED**

The ban is confined to the `FS_Layers` branch. Selecting a layer value **never
removes material-selected media** (`lost = 0` for every one of the ten values),
so there is **no double-ban**. Suite 121 pins it (AUD8.4–8.6):

* `MetalPipe`/`MetalSheet`/`Metal`/`Slime` change nothing (44 → 44) because
  their layer packages own **0 media** on the footstep events — producing them
  would be a no-op, not a ban;
* `Glass` is **purely additive** (+5, 0 lost).

### 5.4 The actual reasons the five stay unproduced (corrected record)

1. `MetalPipe`, `MetalSheet`, `Metal` — **0 layer media in all six authored
   `FS_Layers` containers**; no value the port could select would change
   playback.
2. `Slime` — layer media exist only on `Play_Character_Movement_Slide` (5 + 3);
   the port has no slide action, so nothing can select it; it also owns 0 media
   on the footstep events.
3. `Glass` — additive on the footstep events (+5), but **not derivable**: the
   authored gameplay graph that decides material-vs-layer for a glass surface is
   not in the cook, and the port's `glass` surface token already selects
   `FS_Material=Glass`. Producing the layer would be an invented trigger.

So the five values remain a documented `PORT_DECISION` **for these measured
reasons**, and the W11 "double-ban" rationale is withdrawn.

## 6. Gates run (this lane)

```bash
tools/godot --headless --path game --import                                  # ok
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
#   scripts checked: 229, broken: 0
tools/godot --headless --path game --script res://tests/test_audio_control.gd
#   AUDIO_CONTROL_SUMMARY: fails=0 checks=135   (was 123; +12)
#   WARNING: [weather_profile] rain.intensity 10.0 ... 0..1 domain (the pinned warning path)
tools/godot --headless --path game --script res://tests/test_vo_director.gd
#   VO_DIRECTOR_SUMMARY: fails=0 checks=60      (was 53; +7)
#   VO2.0 the director maps 288 authored lines
```

No assertion was weakened: every pre-existing check still passes, 19 checks were
added, and the two floors (`123`, `53`) are minimums the new counts exceed.

**Integrator note (no action for this lane):** the ratchet floors for
`test_audio_control.checks` and `test_vo_director.checks` may be raised
123 → 135 and 53 → 60 after the next serial `run_final_gates.sh`; the ratchet
treats these as floors ("a suite may add checks, never drop them"), so the
committed logs still satisfy the old floors in the meantime.

## 7. Not verified / open

* No GPU, no Master-bus tap: the rain change is a parameter-domain fix, verified
  by value, not by pixels or by ear.
* `blood_moon` is not mapped to a map; no played run exercises it.
* `FS_Layers` verdict is measured on the authored containers; it does **not**
  claim the shipped game's gameplay graph (absent from the cook) chose otherwise.
* The `NoiseHeard`, `SlippingLosingBalance` and `WakingUp/*` families stay
  unwired for the mix/behaviour reasons named in §4.3; each needs an owner
  decision, not a guess.
