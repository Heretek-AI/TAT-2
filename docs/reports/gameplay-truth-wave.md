# Gameplay truth wave (2026-11-24)

Adversarial audit follow-through: the five blocker-class defects, the
catalogue-only systems, the invented content, and the gate itself. Every change
in this wave is backed by a red-proof test or a measured run.

- **Base:** `3b843a1`
- **Shipped:** `886eff1`, `9b09942`, `9d499e7`, `d49d809`, `b910216`,
  `c4451019`*, `6ffcebe`, `d0ca274`, `0dbbbf1`, `9156634`, `8c51b15`,
  `d3b71de`, `48f6d89`, `61ab07e`, `3202283`, plus the export localization fix
  and the docs commit.
- **Gates (final main):** compile **69/0** · `run_tests` **fails=0 (58
  active suites)** · M2 **fails=0** · E2E **264/264** · door/VM/Niagara
  **PASS** · leak clean · `make audit` **PASS** (tracked baseline, 18 producers,
  13/13 content groups).

\* `4451019` is the commit hash; the table below uses the short form.

## Why

The audit found that the green suite certified a build where:

- guards could not see the player (the sight ray hit the player's own capsule
  and only the guard RID was excluded), so stealth was hearing-only and
  `ever_spotted` stayed false;
- `_merge_validated` aliased an empty `completed_contracts` target to the save
  root, dropping every contract on boot;
- the mirrored-door `CULL_DISABLED` branch tested the leaf-local determinant
  (always +1) instead of the composed door × leaf determinant;
- `T4-13` passed even with the free-play banking guard reverted (loot was 0, so
  `add_currency(0)` was a no-op);
- the FOV migration clobbered a deliberate fresh-install 75;
- 4,118 devices, 210 patrol paths and 96 clue facts were parsed but had no
  runtime consumer; the mission prep countdown, Guildhall Key, HUD identity and
  locale registration were absent or stubbed;
- `make audit` could pass a tree with missing outputs, empty tables and
  `.import` sidecars counted as assets.

## What shipped

| Area | Change | Evidence |
|---|---|---|
| Audit gate | Fail-closed content gate: 18 producers, tracked `tools/audit_baseline.json`, output hashes/counts, disk-backed coverage, exact-case allowlist, `.ubulk` companions, authenticated `errors.log`, real GLB/OGG/CSV/table checks, import gate, 14 negative-control groups | `tools/test_manifest_audit.py` PASS; negative controls in `audit-fail-closed.md` |
| Guard sight | Player RID excluded from the sight ray; T3-25 asserts `SUSPICIOUS` acquisition, a wall control and a non-target body control | det 35.7 / state 1; wall 0/0; body 0/0 |
| Save | Schema-based free-form merge; suite 49 resets before restore, asserts full `completed_contracts`, and adds a two-load regression; corrupt save is no longer silently overwritten | before `{"currency":5}` sentinel; after `{}`; two-load rows 3+4 survive |
| Mirrored doors | Composed door × leaf determinant (global basis when in tree); suite 46 asserts a real `CULL_DISABLED` surface and a single-sided control | `mirrored leaf CULL_DISABLED (control single-sided)` |
| Free-play test | `T4-13` stages loot 500 and asserts no bank; `T4-14` normal-mode control banks the authored 625 and records the order | guard reverted → FAIL; fixed → PASS |
| FOV | `fov_migrated` only on a real slider change; suite 54 instantiates SettingsUI, open/close leaves it false, 75 persists | red-proof with unconditional flag |
| Devices | `parse_devices.py` → `devices_runtime.json`; runtime layer for beams, plates, noise alarms, power, turrets, cameras, ward slow/blocker; 10 Hz tick, 60 m cull, authored action/power graph | 2,095 loaded devices (G 903 / O 1,164 / F 26 / D 2), 6,005 edges, 1,475 power edges; suite 70 |
| Patrols / loudness / LOS | Loader merges 120 Guildhall paths / 350 points; guards use authored waits/yaw/PingPong; 22 surface-loudness rows; interaction/pickpocket/takedown LOS; civilian capsule | suite 55a–55d; carpet 0.0, glass 1.5 |
| Clues / quests | `parse_clues.py` + `parse_quests.py`; authored readable clues, quest items and journal; Guildhall Set = Gem of Fire/Arcana/Strength; LootTheRoom 4000/6000/8000 | 96 facts / 90 reachable / 6 dead; contract 2 = 7 facts, 6 clues, 28 spawners; suite 65 |
| UI / locale | Real 6→1 countdown + UNREADY; Johnny Cipher; `(£)`; key row; `PRICE UNKNOWN`; deterministic pause seed; wall-outline portal; menu rain; `Loc.t()` over 8 shipped translations, CJK fallbacks | de: PLAY→Spielen; 2,946 source strings; suite 60 |
| Animation metadata | `parse_anim_meta.py` → 995/995 clips, 3,594 notifies, 235 montage sections; `notify_at()` accessor | 197 AkPlayerEvent montages, 17 CombatMontage, 5 MotionWarping; suite 75 |
| Co-op transport | Player pose broadcast (20 Hz), host-validated world events (kind/target/LOS distance/cooldown), remote visuals, door apply; suite 80 | rejects 10 m, 65-char, unknown kind; accepts 2.9 m |

## Measured performance (current export)

`build/tat2-linux-x86_64`, rebuilt from this wave, Wayland, RTX 4070 laptop,
`--qa-contract=2` (Guildhall), 3,000 frames. Statistics are post-load (after
`Loaded guildhall`), which removes the loading-screen samples.

| Quality | Resolution | Steady median FPS | p10 | p90 | mspf median | post-load samples |
|---|---|---:|---:|---:|---:|---:|
| high | 1920×1080 | **37** | 32 | 41 | 27.0 | 78 |
| high | 1280×720 | **52** | 40 | 56 | 19.2 | 58 |
| medium | 1920×1080 | **39.5** | 18 | 42 | 25.3 | 26 |
| low | 1920×1080 | **39** | 37 | 42 | 25.6 | 74 |

The medium/high/low 1080p spread is within noise (37–39.5), so the quality-gated
SSIL/fog/SSR toggles are not the 1080p limiter; the 720p result (52 FPS, 19.2 ms)
is close to the CPU ceiling estimated in the ecosystem review. This points at
draw calls / CPU work and the 160-light budget, not a single GPU effect.

The 1080p/high steady state is ~39 FPS (p10 36, p90 41, mspf median 25.6),
improved from the 27 FPS recorded on 19 Nov but still below 60. This is a
budget measurement, not a fix: the CPU/GPU split and the merge/HLOD experiment
in `docs/reports/ecosystem-reuse-review.md` remain the next performance work.

## Residuals (honest)

- **Devices:** breakables/shards (the runtime export has `breakable: null`),
  goo pipes, vault doors, sliding windows, magnetic locks, acoustic portals and
  junctions remain data-only. The five implemented families are the authored
  detector spine, power, turrets, cameras and wards.
- **Co-op:** movement/pose is client-authoritative; loot, AI, mission state and
  devices are not replicated. Door prediction has no rollback. No live
  two-process ENet gate yet (tier 5).
- **Clues/quests:** NPC clue dialogue and spawner interaction radii are not in
  the cooked data; they are not invented. Briefing-only clue sets are skipped.
- **Patrols:** routes are planar; a path spanning floors does not climb.
  Surface loudness is exercised by API/tests; real floors still approximate
  wood/stone rather than resolving physical materials.
- **UI:** the `Guildhall Key` name remains the shipped `Manor Key` family;
  localization is registered and working in the export, but only a subset of
  labels were converted to `Loc.t()`.
- **Rendering:** Den GI (VoxelGI/SSRT bake-off), sign legibility at 27 m,
  POI graybox floors, white glass/emissive plates and Niagara VM rates remain.
- **Performance:** 60 FPS at native 1080p is not achieved; see the ladder.
- **Pipeline:** cooked material graphs, Blueprint graphs and Niagara spawn
  rates remain unrecoverable; LevelSequence and full co-op tier 5 are deferred.

## Reproduction

```bash
# Gates
tools/godot --headless --path game --script tools/check_scripts_compile.gd
XDG_DATA_HOME=/tmp/tat-data tools/godot --headless --path game --script res://tests/run_tests.gd
XDG_DATA_HOME=/tmp/tat-data tools/godot --headless --path game --script res://tests/test_m2_player.gd
XDG_DATA_HOME=/tmp/tat-data tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd
make audit
python3 tools/test_manifest_audit.py

# New data producers
python3 tools/parse_clues.py && python3 tools/check_clue_quests.py
python3 tools/parse_devices.py && python3 tools/check_devices_runtime.py
python3 tools/parse_anim_meta.py && python3 tools/check_anim_meta.py

# Performance (Wayland, serialized)
make linux-build
XDG_DATA_HOME=/tmp/perf-data build/qa/measure_fps.sh 2 1920x1080 3000 postwave
```
