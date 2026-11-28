# Phase 3B.3 — audio domains, unrecoverable IDs, VO wiring, `FS_Layers` proof

**Lane:** Phase 3B.3 (audio), worktree
`/home/john/Projects/.teamwork-worktrees/20261127-1810-phase3/audio`, branch
`teamwork/20261127-1810-phase3-audio`, base = the merged 58-gate baseline
(`55fb588`). **Headless only:** no GPU, no Master tap, no audio-device run.

This report records what was **measured**, what was **wired**, and what is
**not recoverable from the cook**. It does not claim a full Wwise parity: the
control plane is still the W11 slice (14/23 switch groups, 4/8 states, 16/50
RTPCs), and 357 of the 645 authored VO lines are still unwired — 254 with no
owning subsystem, 102 unwired at an existing path (where the open item is an
attribution/behaviour decision), and 1 authored silence (§4.3).

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
column sums to **357** (sum check recorded in §4.4). The table separates two
cases, and each row's gap cell says which one it is:

* a **genuinely missing subsystem** — nothing in the port owns the beat
  (**254** of the 357 lines: 224 in wholly-missing rows plus the 30 flee/evade
  lines inside the mixed row 9); or
* a **beat that is unwired at an existing path** — the owning path exists and is
  reachable, and the open item is an attribution/behaviour decision, not a
  missing system (**102** of the 357 lines: 61 `NoiseHeard`, 19
  `ChasingThiefKnockOutThief`, 9 `AboutToWakeUp`, 8 `RevivedByAlly`, 5
  `SlippingLosingBalance`).

The remaining 1 line is **authored silence** (`Silent/Empty`, 0 media), which is
neither. `ChasingThiefKnockOutThief` is the second kind: the terminal
downed→capture path exists and is reachable (§4.3.1). Every line stays indexed
and is playable by name through `play_vo_event()`; none is invented or re-mapped
onto another event.

| Lines | Family (authored rows) | Owning subsystem gap |
|---:|---|---|
| 74 | `IdleAloneOnPatrol/NonSpoken` (Enforcer1 40) + `/NearOtherGuard` (Enforcer1 19, Hauntstable1 15) | **Missing subsystem: ambient patrol chatter** — no idle-bark scheduler / proximity chatter system. `IdleAloneOnPatrol/Idle` *is* mapped (wake-up), these variants are not. |
| 19 | `Enforcer1_HauntstableDSP/IdleAloneOnPatrol/NonSpoken` (19) | **Missing subsystem: DSP speaker** — an authored DSP-variant speaker with no owning system. Counted here **only**, never inside the idle-chatter row above. |
| 48 | `ThiefObserved/InsidePrivateZoneFoundThief` (Enforcer1 26, Hauntstable1 9) + `/InsidePrivateZoneTooLongSuspicious` (Enforcer1 4, Hauntstable1 5) + `/InsidePrivateZoneTooLong` (Hauntstable1 4) | **Missing subsystem: private-zone trespass** — no private/locked-zone system exists (`grep private_zone` → none). |
| 61 | `NoiseHeard/LowSeverityNoise` (Enforcer1 10, Hauntstable1 10) + `HighSeverityNoise` (Enforcer1 2) + `HighSeverityNoiseSearching` (Enforcer1 10, Hauntstable1 10) + `NothingFoundLowSeverity` (Enforcer1 9, Hauntstable1 10) | **Unwired at an existing path: the bark is already owned** — a heard noise raises `NEUTRAL→SUSPICIOUS`, whose guard transition (`ThiefSeen/VisionStim`) already barks; wiring both would double-bark. Making the noise line win is an authored-behaviour substitution (which line wins on a heard-only stimulus) and is left as a labelled follow-up, not invented here. The two `LowSeverityNoiseSearching` buckets (19) are already mapped through the `NEUTRAL>SEARCH` transition and are NOT in this row. |
| 40 | `GenericStim/React` (Hauntstable1 21) + `ExertionCombat/React` (Enforcer1 14) + `Exertion/AffectedBySoundEmitter` (Hauntstable1 5) | **Missing subsystem: generic "react"** — the port's stimulus reactions are the alertness transitions (already mapped); no distinct generic-react beat. |
| 14 | `IncorrectStateObserved/General` (10) + `/FixedGeneral` (4) | **Missing subsystem: object-state observation** — no "this door should be closed / this object moved" guard observation system. |
| 19 | `BrokenObjectObserved/Chest` (4) + `/Door` (4) + `/InitialSightingOfBrokenObject` (4) + `/InspectionOfBrokenObjectGeneral` (4) + `/Window` (3) | **Missing subsystem: broken-object observation** — `break_container` exists as a player action, but no guard observation beat. |
| 1 | `MainQuestLoot/ContainerSeenOpen` (1) | **Missing subsystem: open-container observation** — no quest-loot observation beat. |
| 49 | `ThiefObserved/ChasingThiefFightingThenFlees` (Enforcer1 10 + Hauntstable1 8 = 18) + `/ChasingThiefKnockOutThief` (Enforcer1 10 + Hauntstable1 9 = 19) + `/ChasingThiefLostTargetEvaded` (Enforcer1 4 + Hauntstable1 8 = 12) | **Mixed.** `ChasingThiefFightingThenFlees` (18) and `ChasingThiefLostTargetEvaded` (12): **missing sub-state** — a chase ends only as `ChasingThiefLostTargetSearching` / `LostTargetFound` (both mapped), with no "thief fled mid-fight" or "search ended in evasion" beat. `ChasingThiefKnockOutThief` (19): **unwired at an existing path** — guard damage → `take_damage` → `_enter_downed()` → `downed` → `_finish_run("capture")` is reachable today (§4.3.1); the open item is the **attribution decision** (which damage source / which guard owns the line), not a missing system. |
| 8 | `SmokeGrenade/Cough` (8) | **Missing subsystem: smoke exposure** — smoke only blocks LOS (`is_blocked_by_smoke`); guards are never "in" the cloud. |
| 9 | `WakingUp/AboutToWakeUp` (9) | **Unwired at an existing path: KO timer** — `ko_timer` exists, but there is no authored pre-wake threshold; wiring would invent the timing. |
| 8 | `WakingUp/RevivedByAlly` (8) | **Unwired at an existing path: ally revive** — the revive exists, but the revived guard already plays `WakingUp/RevivedSelf` on `KO→NEUTRAL`; a second line would double-bark. |
| 5 | `SlippingLosingBalance` (5) | **Unwired at an existing path: slip** — `slip_puddle` → `play_slip()` exists, but `play_slip()` forces the KO which already barks `ExertionCombat/KnockedOut`; a third line in the same frame is a mix decision left open. |
| 1 | `InsultFairy/Active/OneOffs` (1) | **Missing subsystem: InsultFairy** — no insult system in the port. |
| 1 | `Silent/Empty` (1) | **Authored silence** (0 media) — refused by design, counted, never played. |
| **357** | **15 rows, each authored bucket in exactly one row** | — |

### 4.3.1 The existing downed→capture path behind `ChasingThiefKnockOutThief`

The player's terminal health path exists and is reachable from three damage
sources, all through the same `take_damage` entry:

| Source | Call site |
|---|---|
| guard melee | `guard_ai.gd:804-805` → `player.take_damage(MELEE_DAMAGE)` |
| ranged shock | `ranged_attack.gd:133-134` → `victim.call("take_damage", …)` |
| fall | `thief_character.gd:648` → `take_damage(dmg, "fall")` |

`take_damage` floors health at 0 (`thief_character.gd:2499`) and calls
`_enter_downed()` (`:723`), which emits `downed_started` (`:734`); when the
downed timer expires `_tick_downed` emits `downed` (`:743`). The two connects are
`mission_controller.gd:3721` (`downed_started.connect(_on_player_downed_started)`)
and `:3722` (`downed.connect(_on_player_downed)`); `:3723` is `add_child`. Then
`_on_player_downed` (`:5363-5364`) calls `_finish_run("capture")`.

Two facts matter for the audio decision:

* the player has **no health regeneration** — `health` is only set to
  `max_health` at init (`:549`) and in `revive()` (`:760`), and reduced in
  `take_damage` (`:2499`), so a downed player cannot walk the health back up;
* **nothing plays VO at downed or capture** — the only `play_vo` in
  `mission_controller.gd` is the fairy intro, so attributing the line there
  cannot double-bark.

The open item is therefore **attribution, not existence**: which source owns the
line (the guard that landed the blow, only a melee finisher rather than fall
damage, or the nearest chaser at the `downed` signal), and what should happen in
a build where `revive()` (`thief_character.gd:756`) clears `downed` before the
timer fires. That method has **no production caller** in this tree — the only
callers are tests (`e2e_tier2_boundaries.gd:801,809`,
`e2e_tier4_scenarios.gd:295`), which use it to exercise the downed/revive
contract — so no shipped path pre-empts the capture today, but a future reviver
would. Those are behaviour decisions for the owner, so the line is not wired
here.


### 4.4 Sum check (recorded)

Round 2 fixed three defects in the §4.3 table: `BrokenObjectObserved/*` was 15
and had dropped `Door`'s 4 (now **19**), the combat trio used two single-speaker
counts (now **18 + 19 + 12 = 49**), and the 19 DSP idle lines were listed inside
the idle-chatter row as well as in their own row (now **only** their own row,
with the 74 idle-chatter row re-derived as `40 + 19 + 15`).

Round 3 corrected the framing: row 9 no longer claims the thief-KO beat is a
missing sub-state, and §4.3.1 records the reachable downed→capture path.

Round 4 adds no numbers; it makes the check **row-specific** rather than relying
on one document-wide token, so deleting only row 9's KO/attribution clause fails
even though the rest of the wording still mentions an existing path. The check
now also:

* parses the row labels and re-derives the split asserted in §4.3 —
  **254** have no owning subsystem, **102** are unwired at an existing path
  (61 `NoiseHeard` + 19 thief-KO + 9 pre-wake + 8 ally-revive + 5 slip), and
  **1** is authored silence, so a mislabelled row fails;
* pins the round-4 citations — `mission_controller.gd:3721`/`:3722` are the two
  connects (`:3723` is `add_child`, so a range ending there would be wrong) and
  `revive()` has **no production caller** (`e2e_tier2_boundaries.gd:801,809`,
  `e2e_tier4_scenarios.gd:295` call it as a test API);
* keeps the round-3 downed→capture assertions (no player health regeneration,
  `_finish_run("capture")` on `downed`).

It parses the §4.3 table from this file, rebuilds the mapped/unmapped partition
from the authored index and the director's three const tables, and cross-checks
document and data per family. Run from the repository root:

```
$ python3 - <<'EOF'
import json, re

# 1) DOCUMENT SIDE — parse §4.3 into {first family token: Lines} (keyed, so a
#    same-size row swap fails) and classify every row by its gap-cell label.
doc = open("docs/reports/phase3-audio-20261127.md").read()
sec = doc.split("### 4.3 ")[1].split("### 4.4 ")[0]
rows = re.findall(r"^\| (\d+) \| `([^`]+)`[^|]*\| (.+?) \|$", sec, re.M)
doc_rows = {tok: int(n) for n, tok, _gap in rows}
EXPECT = {
    "IdleAloneOnPatrol/NonSpoken": 74,
    "Enforcer1_HauntstableDSP/IdleAloneOnPatrol/NonSpoken": 19,
    "ThiefObserved/InsidePrivateZoneFoundThief": 48,
    "NoiseHeard/LowSeverityNoise": 61,
    "GenericStim/React": 40,
    "IncorrectStateObserved/General": 14,
    "BrokenObjectObserved/Chest": 19,
    "MainQuestLoot/ContainerSeenOpen": 1,
    "ThiefObserved/ChasingThiefFightingThenFlees": 49,
    "SmokeGrenade/Cough": 8,
    "WakingUp/AboutToWakeUp": 9,
    "WakingUp/RevivedByAlly": 8,
    "SlippingLosingBalance": 5,
    "InsultFairy/Active/OneOffs": 1,
    "Silent/Empty": 1,
}
assert doc_rows == EXPECT, doc_rows
assert len(doc_rows) == 15 and sum(doc_rows.values()) == 357
# Framing must be row-specific, not one document-wide token: the mixed row has
# to keep the KO attribution clause, and the old false claim must be gone.
row9 = [g for n, tok, g in rows if tok == "ThiefObserved/ChasingThiefFightingThenFlees"]
assert len(row9) == 1 and "attribution" in row9[0].lower(), row9
assert "existing path" in row9[0].lower() and "downed" in row9[0].lower(), row9
assert "no flee, thief-KO or evade sub-state" not in sec
assert "Every family has **no owning system" not in sec

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

# 3) FAMILY -> authored buckets, keyed by the same token as the table row.
TRIO = (
    "ChasingThiefFightingThenFlees",
    "ChasingThiefKnockOutThief",
    "ChasingThiefLostTargetEvaded",
)
FAM = {
    "IdleAloneOnPatrol/NonSpoken": [
        ("Enforcer1", "IdleAloneOnPatrol", "NonSpoken"),
        ("Enforcer1", "IdleAloneOnPatrol", "NearOtherGuard"),
        ("Hauntstable1", "IdleAloneOnPatrol", "NearOtherGuard"),
    ],
    "Enforcer1_HauntstableDSP/IdleAloneOnPatrol/NonSpoken": [
        ("Enforcer1_HauntstableDSP", "IdleAloneOnPatrol", "NonSpoken")
    ],
    "ThiefObserved/InsidePrivateZoneFoundThief": [
        ("Enforcer1", "ThiefObserved", "InsidePrivateZoneFoundThief"),
        ("Hauntstable1", "ThiefObserved", "InsidePrivateZoneFoundThief"),
        ("Enforcer1", "ThiefObserved", "InsidePrivateZoneTooLongSuspicious"),
        ("Hauntstable1", "ThiefObserved", "InsidePrivateZoneTooLongSuspicious"),
        ("Hauntstable1", "ThiefObserved", "InsidePrivateZoneTooLong"),
    ],
    "NoiseHeard/LowSeverityNoise": [k for k in rem if k[1] == "NoiseHeard"],
    "GenericStim/React": [
        ("Hauntstable1", "GenericStim", "React"),
        ("Enforcer1", "ExertionCombat", "React"),
        ("Hauntstable1", "Exertion", "AffectedBySoundEmitter"),
    ],
    "IncorrectStateObserved/General": [
        ("Enforcer1", "IncorrectStateObserved", "General"),
        ("Enforcer1", "IncorrectStateObserved", "FixedGeneral"),
    ],
    "BrokenObjectObserved/Chest": [
        ("Enforcer1", "BrokenObjectObserved", s)
        for s in (
            "Chest",
            "Door",
            "InitialSightingOfBrokenObject",
            "InspectionOfBrokenObjectGeneral",
            "Window",
        )
    ],
    "MainQuestLoot/ContainerSeenOpen": [
        ("Enforcer1", "MainQuestLoot", "ContainerSeenOpen")
    ],
    "ThiefObserved/ChasingThiefFightingThenFlees": [
        ("Enforcer1", "ThiefObserved", s) for s in TRIO
    ]
    + [("Hauntstable1", "ThiefObserved", s) for s in TRIO],
    "SmokeGrenade/Cough": [("Enforcer1", "SmokeGrenade", "Cough")],
    "WakingUp/AboutToWakeUp": [("Enforcer1", "WakingUp", "AboutToWakeUp")],
    "WakingUp/RevivedByAlly": [("Enforcer1", "WakingUp", "RevivedByAlly")],
    "SlippingLosingBalance": [("Enforcer1", "SlippingLosingBalance", "")],
    "InsultFairy/Active/OneOffs": [("InsultFairy", "Active", "OneOffs")],
    "Silent/Empty": [("Enforcer1", "Silent", "Empty")],
}
data_rows = {k: sum(rem.get(b, 0) for b in buckets) for k, buckets in FAM.items()}
assert data_rows == EXPECT == doc_rows
covered = [b for buckets in FAM.values() for b in buckets]
assert len(covered) == len(set(covered)) == len(rem) and set(rem) == set(covered)

# 4) Classify the table by its row labels and re-derive the 254 / 102 / 1 split.
missing_doc = sum(
    int(n) for n, _tok, gap in rows if gap.startswith("**Missing subsystem")
)
unwired_doc = sum(
    int(n) for n, _tok, gap in rows if gap.startswith("**Unwired at an existing path")
)
silence_doc = sum(
    int(n) for n, _tok, gap in rows if gap.startswith("**Authored silence")
)
mixed = [int(n) for n, _tok, gap in rows if gap.startswith("**Mixed")]
assert len(mixed) == 1, mixed
flee, ko, evaded = (
    rem[("Enforcer1", "ThiefObserved", s)] + rem[("Hauntstable1", "ThiefObserved", s)]
    for s in TRIO
)
assert (flee, ko, evaded) == (18, 19, 12)
missing, unwired = missing_doc + flee + evaded, unwired_doc + ko
assert (missing, unwired, silence_doc) == (254, 102, 1), (missing, unwired, silence_doc)
assert missing + unwired + silence_doc == 357
plain = sec.replace('**', '')
assert '254 of the 357' in plain and '102 of the 357' in plain

# 5) The two round-4 citation fixes.
# (checked against §4.3 prose only: this check's own text lives in §4.4)
assert "mission_controller.gd:3721" in sec and ":3722" in sec
assert not re.search(r"mission_controller\.gd:37\d\d-\d", sec)
assert "no production caller" in sec
assert "e2e_tier2_boundaries.gd:801,809" in sec and "e2e_tier4_scenarios.gd:295" in sec

# 6) Round-2/3 facts still hold.
assert sum(rem[k] for k in rem if k[1] == "BrokenObjectObserved") == 19
assert rem[("Enforcer1", "BrokenObjectObserved", "Door")] == 4
dsp = sum(n for k, n in rem.items() if k[0] == "Enforcer1_HauntstableDSP")
assert (
    dsp == 19
    and sum(
        n
        for k, n in rem.items()
        if k[1] == "IdleAloneOnPatrol" and k[0] != "Enforcer1_HauntstableDSP"
    )
    == 74
)
mc = open("game/src/missions/mission_controller.gd").read()
th = open("game/src/player/thief_character.gd").read()
ga = open("game/src/ai/guard_ai.gd").read()
assert 'func _on_player_downed() -> void:\n\t_finish_run("capture")' in mc
assert "player.downed_started.connect(_on_player_downed_started)" in mc
assert "player.downed.connect(_on_player_downed)" in mc
assert "func _enter_downed()" in th and "downed.emit()" in th
assert "player.take_damage(MELEE_DAMAGE)" in ga
assert re.search(r"^\s*health = maxf\(0\.0, health - amount\)$", th, re.M)
assert len(re.findall(r"^\s*health = max_health$", th, re.M)) == 2  # init + revive only

print(
    "OK rows=%d sum=%d mapped=%d unmapped=%d missing=%d unwired=%d silence=%d "
    "broken=%d trio=%s dsp=%d idle_only=%d ko_path=downed->capture leftover=0"
    % (
        len(doc_rows),
        sum(doc_rows.values()),
        len(mapped),
        645 - len(mapped),
        missing,
        unwired,
        silence_doc,
        sum(rem[k] for k in rem if k[1] == "BrokenObjectObserved"),
        [flee, ko, evaded],
        dsp,
        sum(
            n
            for k, n in rem.items()
            if k[1] == "IdleAloneOnPatrol" and k[0] != "Enforcer1_HauntstableDSP"
        ),
    )
)
EOF
OK rows=15 sum=357 mapped=288 unmapped=357 missing=254 unwired=102 silence=1 broken=19 trio=[18, 19, 12] dsp=19 idle_only=74 ko_path=downed->capture leftover=0
```

Both sides are compared as `{family token: Lines}` maps, so the table can no
longer drift from the data even where two rows share the same line count (the
three single-line rows, the two 8-line rows). The check also proves the
partition is complete: every remaining bucket is covered exactly once
(`leftover=0`), so the DSP 19 is disjoint from the 74 idle-chatter lines.

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
