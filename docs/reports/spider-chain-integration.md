# Spider personal chain — integration and real-map verification (01 → 04)

Date: 2026-11-24. Main HEAD: **`eb55bc1`**. Working tree clean.

This report records the integrated state of the Spider personal quest on `main`:
the chain, its real-map placements, the Owl's authored support, the measured
probe output, the thermal envelope it ran under, the integrated commits, and the
gates that were **not** run. It does not replace the per-wave reports
([`w0s`](w0s-spider-foundation.md), [`w1s`](w1s-spider-runtime.md),
[`w2p`](w2p-subset-probe.md), [`w3o`](w3o-owl-placement.md),
[`w4o`](w4o-w3o-remediation.md), [`w4p`](w4p-thermal-guard.md),
[`w4p`](w4p-probe-suite-fix.md)); it records what actually runs now.

## Status in one paragraph

The Spider chain is **live**: first Guildhall deploy → Library letter → Den /
next deploy electrotype → Vault Owl → Lounge courier → Old Manor Courtyard
informant, ending at `stage=complete` with the seven authored facts. The subset
real-map probe passes **90/90 checks** with `stage=complete`, the exact shipped
lines, `[E] Talk` / `[E] Take Theban Owl`, and no loot, currency, contract or
objective mutation. Full `make test`, `test_m2_player`, E2E 264/264, the real
perf matrix and a full editor open were **deferred** and are not claimed here.

## Chain as shipped

| Stage | Trigger | Actor / authored pin | Facts granted |
|---|---|---|---|
| `intro` | first `guildhall` deploy (contract or free play) | Library note `BP_Readable_ClueSpawner_Guildhall_C_28` `(-26.8541, 28.0021, -9.4431)` | `01:Intro` |
| `letter` | read the note (`[E] Read`) | same note | `01:FoundLetter` |
| `electrotype` | `on_hub_enter()` at Den setup, or the next deploy | — | `01:MallickSlip`, `01:StatuePet` |
| `located` | `guildhall` deploy while `electrotype` | Vault Owl `BP_QuestSpawner_Item_C_2` `(-31.6286, 36.4655, -43.9759)`; authored fallback `_C_0` `(10.9846, 54.5118, -54.9085)` | `02:OwlLocation` |
| `carrying` | take the Owl (`[E] Take Theban Owl`) | Lounge courier `BP_Readable_ClueSpawner_Guildhall_C_1` `(35.9, 27.0019, -22.728)`; fallback `_C_33` `(8.2, 28.4942, -66.1)` | — (Owl held) |
| `delivered` | first courier talk (`[E] Talk`) | same courier | `03:HandedOff` |
| `info` | first informant talk on Old Manor | Courtyard C1 `(1.5, 10.1096, 13.0)`; fallbacks `BP_SmartObject_GuardDefensiveLocation_C_839/838/840` | `04:GotInfo` |
| `complete` | the next informant interaction | — | — |

Shipped lines (read from the expansion record, not code literals):

- 03 first: `Aye, it's a Langnacht night tonight. I'll take the goods.`
- 03 follow-up: `We're done here. Skedaddle aff.`
- 04 first: `I heard you're looking for dirt on Mallick. This might help. If anyone asks, you didn't get it from me.`
- 04 follow-up: `We're done here. I have nothing else for you.`

Journal lines come from the authored facts (`I delivered the goods`;
`Chisholm gave me a copy of Mallick's police records. I'll review them later.`).

The record is `game/data/expansion/personal_spider.json` (8 beats, 7 grantable
facts). Save state is per thief under `personal_quest.<thief>` with
`personal_quest_schema: 1`; the chain binds to the Spider and is a no-op for the
Chameleon (zero actors, unchanged save). `03:Reminder` and `04:Renegade` are
never granted; `ObjectiveComplete_Clue` / `ObjectiveComplete_Electrogram` are
never granted and never journaled.

The Owl is a personal quest item: it sets no loot count/value, no currency, no
`quest_item_acquired`, and is deliberately not in the `loot` or `xray_target`
groups. The chain writes no contract progress and, in free play, banks nothing.

## Real-map placements (measured by the subset probe)

One `LevelLoader.load_sublevels()` call per map:
Guildhall = `Building_Guildhall_POI` + `Guildhall_Gameplay` +
`Guildhall_MissionClues`; Old Manor = `OldManor_P` + `OldManor_Gameplay` +
`OldManor_Clues`. The literal four-sublevel list cannot ground any pin (the
walk surfaces live in `Building_Guildhall_POI` / `OldManor_P`); that finding is
in [`w2p-subset-probe.md`](w2p-subset-probe.md).

| Anchor | Pin | `y_source` | Placed / foot (m) | Surface (m) | Authored yaw |
|---|---|---|---|---|---|
| library note | `(-26.8541, 28.0021, -9.4431)` | `pin` | `pos_y=28.0021`, foot `27.9972` | table top `28.0000` (letter sinks 2.84 mm) | none (flat sheet) |
| Vault Owl | `(-31.6286, 36.4655, -43.9759)` | `pin` | `pos_y=36.4655`, foot `36.4656` | pedestal top `36.4645` | none (its visual root spins) |
| Lounge courier | `(35.9000, 27.0019, -22.7280)` | `floor` | spawn `pos_y=27.0221`, settled `27.0017`, foot `27.0011` | floor `27.0015` | **90°** (faces −X into the Lounge) |
| 04 informant | `(1.5000, 10.1096, 13.0000)` | `floor` | `pos_y=10.1102`, foot `10.1096` | floor `10.0896` | **0°** (faces the Courtyard approach) |

Load counts printed by the probe:

```text
PQ-SUBSET loaded guildhall meshes=11132 lights=160 bodies=74  shapes=8864
PQ-SUBSET loaded old_manor meshes=5483  lights=160 bodies=397 shapes=5003
```

The probe stand point is now selected on the walk floor, inside the player's
authored **1.75 m** interaction range (`TATInteractionTargeterComponent.
MaxInteractionRange`), not on the prop's table or pedestal:

```text
PQ-SUBSET stand letter   walk_floor_y=27.0000 overlaps=0 los=true (offset 1.5 m @ 135 deg)
PQ-SUBSET stand Owl      walk_floor_y=35.5000 overlaps=0 los=true (offset 0.6 m @ 0 deg)
```

No per-spawner interaction radius is invented. The prompt comes from the
shipped strings: `[E] Read`, `[E] Take Theban Owl`, `[E] Talk`.

## Owl support — the authored pedestal, no TAT-2 shelf

The reverse-engineering pass found `SM_Manor_BookcasePedestal` in
`Guildhall_Gameplay` at `(-32, 35.5, -43.997)` with a measured world top of
**~36.4645 m**. The Owl pin `BP_QuestSpawner_Item_C_2` is at `y=36.4655`, i.e.
**1.0 mm above that top** and 0.9655 m above the Vault walk floor. The pin is a
real surface point, not a spawner display offset.

Probe evidence:

```text
PQ_PLACE kind=quest_item y=pin anchor=owl pin_y=36.4655 floor_y=36.4645 pos=(-31.6286, 36.4655, -43.9759)
PQ-SUBSET authored surface Owl y=36.4645 lateral=0.000 pin_offset=0.0010 foot_offset=0.0011
PASS: [pq-subset] Owl support is the BookcasePedestal top (36.4645 +/- 0.10 m)
```

No TAT-2 shelf or bookcase is added and the pin is not moved. A missing support
now **fails** the probe instead of passing as “none”.

## Probe result (measured on `main`, 90/90)

Command (one Godot process, isolated save home):

```bash
XDG_DATA_HOME=/tmp/opencode/w2p-data \
  taskset -c 0-3 tools/godot --headless --path game \
  --script res://tests/probe_personal_quest_subset.gd
```

Tail:

```text
TAT-2 personal quest: map=guildhall thief=spider stage=intro plan=1 spawned=1 anchors=library_note
TAT-2 personal quest: letter read thief=spider stage=letter
TAT-2 personal quest: map=guildhall thief=spider stage=located plan=1 spawned=1 anchors=owl
TAT-2 personal quest: courier spawned after Owl pickup at (35.9, 27.02209, -22.728)
TAT-2 personal quest: map=old_manor thief=spider stage=delivered plan=1 spawned=1 anchors=informant
...
PASS: [pq-subset] Owl ends delivered
PASS: [pq-subset] seven chain facts persisted
PASS: [pq-subset] suppressed fact absent: DT_ClueFacts_Personal_Spider_01:ObjectiveComplete_Clue
PASS: [pq-subset] suppressed fact absent: DT_ClueFacts_Personal_Spider_01:ObjectiveComplete_Electrogram
PASS: [pq-subset] suppressed fact absent: DT_ClueFacts_Personal_Spider_03:Reminder
PASS: [pq-subset] suppressed fact absent: DT_ClueFacts_Personal_Spider_04:Renegade
PASS: [pq-subset] chain banks no loot
PASS: [pq-subset] chain banks no currency
PASS: [pq-subset] chain adds no objective
PASS: [pq-subset] chain completes no contract
PASS: [pq-subset] Chameleon record untouched (none)
PASS: [pq-subset] save file persists stage=complete
PASS: [pq-subset] save file persists the seven facts and delivered Owl
PASS: [pq-subset] reloaded save keeps the completed chain
PQ-SUBSET stage=complete owl=delivered
PQ-SUBSET fact=DT_ClueFacts_Personal_Spider_01:Intro
PQ-SUBSET fact=DT_ClueFacts_Personal_Spider_01:FoundLetter
PQ-SUBSET fact=DT_ClueFacts_Personal_Spider_01:MallickSlip
PQ-SUBSET fact=DT_ClueFacts_Personal_Spider_01:StatuePet
PQ-SUBSET fact=DT_ClueFacts_Personal_Spider_02:OwlLocation
PQ-SUBSET fact=DT_ClueFacts_Personal_Spider_03:HandedOff
PQ-SUBSET fact=DT_ClueFacts_Personal_Spider_04:GotInfo
PERSONAL QUEST SUBSET PASS checks=90 fails=0
THERMAL subset-final start=85000mC peak=90000mC end=89000mC (peak 194.0F) rc=0 aborted=0
```

Also asserted: authored XZ, floor ray and ±0.05 m flatness, `y_source`, mesh
bottom not sunk, authored support, prompts, interactability, chest-height
interaction LOS, the courier's `[E] Talk` → `delivered` + `03:HandedOff` + the
exact 03 line, the informant's first talk → `info` + `04:GotInfo` + the exact 04
line, and the follow-up → `complete` + the exact close line. The Owl pickup
spawns the courier in the same frame; the informant is stage-gated to
`delivered`.

Evidence log: `/tmp/opencode/thermal-subset-final.log` (local, not tracked).

## Other verification actually run

| Check | Result | Evidence |
|---|---|---|
| Full GDScript compile | **96 checked, 0 broken** | `/tmp/opencode/thermal-compile.log` |
| `run_tests.gd -- --spider-only` | **`PASS: 87`, `PASS: 88`, `SUMMARY: fails=0`** | `/tmp/opencode/thermal-spider-only.log` |
| Pure placement test | **26/26** (`PQ-PLACE SUMMARY: fails=0 checks=26`) | `/tmp/opencode/verif/step3b-pq-spawner.log` |
| `probe_leak` | **PASS**; `PROBE after den free players=0`, `after gh free players=0` | seam-smoke log, integration run |
| `make audit` | **`AUDIT PASS`, exit 0**, tracked baseline matches | re-run on `eb55bc1` for this report |
| Subset real-map probe | **90/90, `stage=complete`** | `/tmp/opencode/thermal-subset-final.log` |

`make audit` on `eb55bc1`: 107 levels, 16 contracts, 144 tables, 1,629
materials (1,379 albedo, 0 missing textures), 4,118 devices, 995 animations,
5,018 audio clips, 8 locales, 15 videos, 222 scene variants, 3,695 Niagara
records; freshness fresh for every group; baseline matches.

## Thermal envelope

The host is the same i9-14900HX laptop used by the earlier waves; package
temperature is the binding constraint, not test time. Every run used one Godot,
`taskset -c 0-3`, a 12 GiB / 0 swap cgroup and a hard kill at 95 °C.

| Run | Start | Peak | End | rc / abort |
|---|---:|---:|---:|---|
| compile `check_scripts_compile.gd` | 83 °C | 92 °C | 92 °C | 0 / none |
| `--spider-only` (87 + 88) | 82 °C | 90 °C | 82 °C | 0 / none |
| subset real-map probe | 85 °C | 90 °C | 89 °C | 0 / none |

The probe log also contains a refused launch at **96 °C > 90 °C** from an
earlier attempt; the run that produced the 90/90 result never crossed 95 °C, so
it is a genuine result, not a truncation. Earlier revisions were killed at
95–98 °C (see [`w1s`](w1s-spider-runtime.md), [`w2p`](w2p-subset-probe.md)), and
two complete-suite attempts were aborted by the watchdog. That history is why
the full gates below are deferred rather than quietly assumed.

## Perf guard (W4P, `eb55bc1`)

`build/qa/run_perf_matrix.sh` now fails closed on host state:

- `--start-temp` default **78 °C** refuses a sustained run above it;
  `--max-temp` default **95 °C** kills the launch at or above it; both validated
  `60..105` with `start < max` (no-headroom combinations exit 2).
- An **independent 1 s sampler** logs `PERF_THERMAL_SAMPLE` for pre-warm and the
  measured run, writes `PERF_THERMAL_PREWARM_PEAK`, and kills the sampled PID
  itself; the wait loop no longer samples.
- `VmHWM` is enforced (`--max-rss-mb`, default **8192**); each launch gets a
  `MemoryMax=12G` / `MemorySwapMax=0` user scope with a logged direct-launch
  fallback.
- Unknown (`?`) temperature, a sampler that does not start, or a missing
  sampler summary aborts instead of running.

`build/qa/test_perf_guard.sh` passes **42/42** without launching a game, and
`--guard-check=<C>` exercises the exact runtime decision (77/78 pass; 79/95/`?`
exit 8). **No real perf matrix was run**; the 78 °C start gate refuses this host
at idle (82–94 °C). Details: [`w4p-thermal-guard.md`](w4p-thermal-guard.md).

## codebase-memory hardening

`9f8f36a` + `877d6ad` bound the local codebase-memory service and index only
source:

- service limits **4 GiB max / 3 GiB high / swap 0**;
  `CBM_MEM_BUDGET_MB=3072`.
- `index_max_files=20000`, `index_max_source_mb=512`; the marketplace package
  was patched to honour them.
- `.cbmignore` is a source whitelist (`game/src`, `game/tests`, `game/addons`,
  `game/scenes`, `game/data/expansion`, `tools/`, `docs/`, root files) and
  explicitly excludes `extracted/`, `build/`, `game/.godot/`,
  `game/data/generated/`, `game/scenes/review/`, tool `bin`/`obj`/cache and
  `__pycache__`.
- `tools/check_cbmignore.sh` passes **26/26** (`CBMIGNORE CHECK PASS: heavy trees
  ignored, source whitelist intact`).

## Commits integrated

| Commit | Change |
|---|---|
| `184e97e` | runtime base: NPC actors, dialogue modal, Owl pickup, 04 informant, mission hooks |
| `7aa2a67` | subset real-map probe; spawn pass extracted to `personal_quest_spawner.gd`; `GameData.get_civilian_meshes()`; static floor scan |
| `b0a14c6` | per-kind placement policy: readables/quest items keep the authored pin, NPCs use floor + 0.02 m |
| `025725b` | W4O remediation: global settle, thief binding, authored yaw, pedestal support, dead floor-fallback removed |
| `fab73ec` | placement test loads the spawner after autoloads |
| `6ad84e3` | 8 tracked `.gd.uid` files for the new quest/probe scripts |
| `c81ff0e` | subset probe loads after autoloads; `--spider-only` runs 87 + 88; suite 88 in-tree host |
| `b03d367` | probe stub mission owns the Owl hook; standing capsule uses the walk floor |
| `3e26c7a` | probe stand-point selection and NPC settle tolerance |
| `eb55bc1` | W4P perf guard: guarded pre-warm, 1 s thermal sampler, RSS limit |
| `9f8f36a`, `877d6ad` | codebase-memory guard and source-only index whitelist |

## Deferred — explicitly not claimed

These were **not** run on `eb55bc1` and must not be quoted as green:

1. Full `make test` (59 suites; suites 86 and the whole non-Spider set).
2. `tests/test_m2_player.gd`.
3. `tests/e2e/run_e2e_tests.gd` (264/264) and tier 1.
4. The real six-pose perf matrix at `--start-temp 78 --max-temp 95`.
5. A full editor open / TAT-2 Review dock interaction on this 8 GB laptop GPU.

Run them on a cool host, one Godot at a time. The current host idles near
82 °C, above the guard's 78 °C start gate.

## Residuals

- **No authored pointer to the 04 informant.** The Courtyard C1 point is a
  grounded logical point, not an actor; the chain can idle at `delivered`.
  Old Manor is contract-only, so a player who never deploys an Old Manor
  contract cannot reach the informant. No pointer or Guildhall fallback is
  invented.
- **`03:Reminder` withheld** and **`04:Renegade` excluded** by design; the
  producer census still reports 6 dead fact rows (the chain grants `01:Intro`
  at runtime).
- **No VO, portrait or nameplate.** The dialogue modal is one authored line plus
  `CONTINUE`, no pause.
- **Letter sinks 2.84 mm** into the table (`SM_NoteOpenA` bottom `27.99716` vs
  table top `28.000`). Accepted as paper contact; the pin is unchanged.
- **Run vs persistent facts.** Personal facts are persisted per thief in
  `SaveSystem`; contract facts remain run-only and are wiped on deploy.
- **Co-op is local-only for this chain.** No personal-quest state or NPC/dialogue
  events are replicated; host authority for loot/AI is still open.
- **Authored yaw is plausible but unverified visually.** Courier 90° and
  informant 0° are TAT-2 data with a `yaw_note`; confirm on the loaded interior
  and change the JSON, not the code.
- **Full gates and perf numbers are deferred** (above).
- `docs/FIDELITY_GAPS.md` previously described the Spider lines as orphaned
  with “NPC quest planned W2”; this report and the gap entry replace that text.

## Reproduce

```bash
# placement policy only (no map, no GPU)
tools/godot --headless --path game --script res://tests/test_personal_quest_spawner.gd

# thermal shortcut: suites 87 + 88, no mission load
tools/godot --headless --path game --script res://tests/run_tests.gd -- --spider-only

# real-map placement + chain (one Godot, isolated save home)
XDG_DATA_HOME=/tmp/opencode/w2p-data tools/godot --headless --path game \
  --script res://tests/probe_personal_quest_subset.gd

# fail-closed perf guard without a game
build/qa/test_perf_guard.sh
build/qa/run_perf_matrix.sh --guard-check=79   # exit 8, refuse_start
```
