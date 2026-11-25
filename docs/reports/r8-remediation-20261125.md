# R8 — remediation wave (2026-11-25)

Twelve remediation teams, one recorded-run review and one reverse-engineering audit,
merged into a single wave. Every fix carries a red proof taken before the change and a
green re-proof after it; every team worked in an isolated worktree on its own branch and
**nothing was pushed or merged by a team** — the integrator cherry-picked, resolved
conflicts, regenerated shared data once and re-ran the complete gate set.

- **Base:** `38e7b03` (plus the audit reports at `fb93f84`)
- **Merged:** 12 branches, 43 commits
- **Upstream audits:** [`re-audit-20261124.md`](re-audit-20261124.md) (the shipped
  UE5.5 → extracted → generated → Godot chain, 17 domains) and
  [`r8-live-run-review-20261124.md`](r8-live-run-review-20261124.md) (the 281 s recording,
  filled 120-row scorecard at
  [`COMPARISON_PORT_20261124.md`](../reference/clip_1795033698901/COMPARISON_PORT_20261124.md))

## 1. What the two audits established

- The **extraction is broader than the docs claimed** (107/107 maps, 995/995 clips,
  5,018/5,018 Wwise clips, 1,629/1,637 materials, 99.92 % mesh resolution) and the
  **consumption was far thinner than the gates suggested** (81/144 tables with no reader,
  92/995 clips bound, 45/1,296 audio events reachable, 159/976 lights, 8/54 hearing stims).
- The Guildhall's black interiors were a **global light-energy cut** (976 authored lights →
  159 nodes, cut at 25.0 lm, every candle dead) plus an exposure lift gated on a preset no
  map used, plus no GI/IBL.
- The user-reported **mission-prep regression** was a camera reframe in `7128d43`: the port
  camera sat 14.06 m from the authored `CameraActor_0` and 69.1° off its heading.
- Two gameplay defects were structural: **melee damage landed at swing frame 0**, and the
  blackjack **could not be won** (the detection ramp beat the 0.45 s hold by 18 ms at
  2.4 m).
- Three state defects destroyed player data: a **corrupt save was overwritten on the same
  boot**, the payout outbox had no production caller, and a **co-op client could never
  complete** a run the host finished.

## 2. Teams and outcomes

| Team | Commit(s) | Fixed / partial / deferred | Headline measured result |
|---|---|---|---|
| **T01 PIPELINE** | `c101237`, `b35d74c` | 7 / 0 / 0 | 5 new producers (`project_ini`, `input`, `collision`, `curves`, `wwise`), a consumer audit wired into `make audit` (88/144 tables had no reader), and a hardened gate: content-based coverage `12,660/43`, `.usmap` pinned, `--refresh-stamps` requires a reason |
| **T02 STATE** | `d867c6a`, `9aae377`, `3091ddd`, `46c3e64` | 11 / 1 / 5 | corrupt saves quarantined whole; `write_save() → Error`; real outbox; host-authoritative co-op; hub clock removed; suites 91–93 |
| **T03 AUDIO** | `2b653ff` | 6 systems + 2 S6 bugs | 130-bus control plane, 31 transmission-loss rows, 90/90 emitters, 645 VO lines, pause duck, loading silence to digital zero |
| **T04 ANIM** | `8c23da2`, `51ca162` | 5 / 4 / 11 | clip durations exact (`(N−1)/N` bug), damage at 0.920–1.170 s of the swing, authored takedown pair, retarget gate |
| **T05 UI** | `0c1dba7` | P0 + 6 P1 | prep camera restored (**13 → 387** pivots inside the authored 10° cone), HP bar on the authored fill, pause dims and pays out, 5 fonts, StringTable reader |
| **T06 INPUT** | `6c24d2d`, `ad94f9a`, `5a6f0d4`, `59beaef` | 5 / 0 / 2 blocked | authored IMC table drives **39** InputMap blocks (was 21), right-stick look, 15-cell rebinding, rebind-aware glyphs |
| **T07 RENDER** | `7fcb8dc`, `e16e524` | 3 / 2 / 2 | room coverage **95→154 of 189** 16 m bubbles; gameplay interiors **31→63 of 64**; exposure applies to `gloomy`; EV curve consumed |
| **T09 GEOMETRY** | `e57684d`, `841c555`, `93c2865` | 6 / 0 / 0 | splines loft (dupes 1,049→747), LevelInstance **138/190→190/190**, authored streaming graph, 307 origin markers fixed, mantle at clip length |
| **T08 MATERIAL** | `b91b5ce`, `df9c50d`, `9abf010`, `fbfd225`, `c25f520`, `80fbd76` | 8 / 0 / 1 | tints **110,396 binds → 0** wrong-space; mis-bound slots **776 → 0**; ward facets sd 0.043→0.162 |
| **T11 AI** | `8607318` + 6 | 7 / 4 / 2 deferred | blackjack **detection 61.25 → 0.00**, KO true, `ever_spotted` false; authored sight, ranged curve, 285-portal occlusion |
| **T10 GAMEPLAY** | `ae47adb` | 9 / 1 / 0 | objective markers exist, portals re-arm through the endgame, invented locks deleted, authored steal times |
| **T12 VFX** | `dbfa2b8`, `ade1237`, `2c9a9b3`, `d1c7fa3` | 5 / 0 / 2 | instances **3,308 → 1,048** (−68 %), 810 decoded parameter sets, 60 m culling, 79 duplicate candles suppressed, probe 6 → ~65 assertions |

## 3. Gates on the merged tree (serial, measured)

| Gate | Result |
|---|---|
| GDScript compile | **152 checked, 0 broken** |
| `tests/run_tests.gd` | **`SUMMARY: fails=0`** (301 PASS; suites numbered to 97) |
| `tests/test_m2_player.gd` | **`M2_SUMMARY: fails=0`** |
| `probe_leak` (`TAT2_NO_DEN_PROBE=1`) | exit 0, `players=0` after free |
| E2E full | **`fails=0 passed=278 total=278`** |
| E2E tier 1 | **117/117** |
| door walk / viewmodel truth | `DOORWALK PASS` / `VIEWMODEL_TRUTH PASS` |
| Niagara probe | `NIAGARA_PROBE PASS` (1,048 active / 4 sprite systems / 810 parameter sets, 79 candles suppressed) |
| blackjack probe | `BLACKJACK_PROBE PASS fails=0` |
| render probe (T07) | `T07_SUMMARY: fails=0` |
| geometry probe (T09) | `GEOM_PROBE checks=7 fails=0` |
| `make audit` | **AUDIT PASS** — 12,657/12,703 coverage, 0 unexpected, reason recorded |
| `make texture-cap-check` | **OK** — 0 offenders, 261 out-of-scope over-cap (was 285) |
| `build/qa/test_perf_guard.sh` | **78/78** |
| `make gate-ratchet` | **PASS** |

## 4. Regeneration and the baseline

Performed once, by the integrator, at the merged HEAD (AGENTS rule: workers may not):

```text
make normalize   27 producers, 0 warnings
make anims       995/995 clips, 0 failures, manifest written
reimport         ok
texture cap      ok (0 offenders)
audit refresh    AUDIT PASS, reason recorded in tools/audit_baseline.json
```

One metric **decreased on purpose** and is now recorded, floored and reasoned in
`manifest_audit.EXPECTED_METRIC_DECREASES`: `parse_materials.materials_albedo`
1379 → 1376, because T08 stopped inventing a fallback albedo for materials that author
only an emissive colour. Any other decrease still fails the gate; the floor keeps a future
silent loss visible instead of normalising it away.

## 5. What the merge itself taught

- **Five teams independently added "suite 91".** They were renumbered 91–97 during the
  cherry-picks. That is a process defect in the parallel model: suite numbers are a shared
  namespace and should be allocated by the integrator, not claimed by a branch.
- **Two teams fixed adjacent code without knowing it.** T11's `_service_combat` applied
  melee damage instantly, which silently undid T04's authored hit window. The resolution
  keeps T11's ranged/role structure and routes melee through T04's
  `_apply_guard_melee_hit()` contact, with the Combat.Hit stim moved to the contact frame.
- **Three tests encoded pre-fix timing.** The shared live-hold helper and the blackjack
  probe read guard state on the release frame; after T04 they wait (bounded) for the
  authored contact. This is not a weakened assertion — it measures the authored timing.
- **One probe encoded pre-regeneration data.** `NS_LootStash` is a *mesh* renderer after
  the authored regeneration, so it authors no sprite; the expected-sprite list was stale.
- **One cross-team loss was caught by the gate**, not by review: T12 removed the
  `authored_candle_vfx` flag in favour of `_authored_flame_near()` but the cherry-pick kept
  the HEAD-side guard, leaving an undeclared identifier — compile caught it immediately.

## 6. Still open (deliberate, or needs a capture/playtest)

- **Candle lights remain 0/135 by design.** They are 0.35–1.5 m sconce glows; spending a
  budget slot costs a room its practical. Candle geometry is emissive.
- **IBL is an approximation** until T01's SkyLight cubemap export lands.
- **Lockpick has 41 assets and 0 animations**; the dial minigame has no hand animation.
- **VFX sprite resolution is wrong-token for most systems** (6 of 29 textures pass the
  soft-mask gate) — reported, not papered over.
- **Texture streaming/eviction is deferred**; the roughness bake is ~54 % of the Guildhall
  scene build.
- **No Vulkan capture has been taken.** The prep composition and the new interior lighting
  are numerically right and pixel-unconfirmed. Three captures are specified in
  `build/qa/review_20261124/INTEGRATION_RUNBOOK.md` §4.
- **The authored `FrustumPitch −22°` caps a guard's view at +0.75° elevation.** Faithful,
  but a large stealth change: playtest with `--sight-frustum=off` to isolate it.
- Container **auto-locks are gone** (authored truth), the magic door is effectively
  continuous during the endgame, the turret-alarm stim is an inference, and the steal hold
  is player-side only. All four are recorded as behavioural risks, not bugs.

## 7. Documentation

`AGENTS.md`, `README.md`, `FIDELITY_GAPS.md` and `HANDOFF_NEXT_AGENT.md` were corrected from
the teams' doc-correction lists. The load-bearing corrections:

- Loot: authored slot cost is **1/1/1**; `minor 1 / major 3` is a **port decision**;
  `DifficultyToLootMultiplier` is not stored and `DIFFICULTY_MULTIPLIER_APPLIED` does not
  exist.
- Producers: **23/26/27** (19 `parse_*.py` + 4 new, 22 normalisers, 23 stamps) — the docs
  said 21, 14 and 18 in three different places.
- The light budget is **per-room fair**, never a global energy rank.
- `game/i18n/generated/` does not exist.
- Gate semantics: coverage is **content**, not package stems; `--refresh-stamps` requires
  a written reason.
