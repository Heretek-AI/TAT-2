# W7 integration — acceptance + truth wave (2026-11-24)

Five lanes ran in isolated worktrees from `74a43b8`, each with its own
`XDG_DATA_HOME`, and were cherry-picked onto `main` in the order S2 → S5 → gates
→ hearing → visual. This report records the **merged-tree** measurement; the
per-lane numbers in each lane report are not repeated here.

Measured on `6760dd0ece9b15159d9c30ced2497355875d259a`.

## Commits

| Commit | Lane | Subject |
|---|---|---|
| `8654a64` | W7S | `feat(loot): carried inventory, stash, payout and save v8` |
| `bfef943` | W7E | `feat(mission): two-phase timer, 25 escape markers and endgame extraction` |
| `2f4adda` | W7G | `chore(gates): export provenance, roughness cache, core bake and Sonar gate plan` |
| `81ac8ab` | — | `chore(audit): re-stamp the baseline at the W7 merged tree` |
| (W7H) | W7H | `fix(player,ai): surface-resolved hearing, swing-door noise and stair descent` |
| `6760dd0` | W7V | `feat(ui): KF11 skyline, Cotter wardrobe and acceptance captures` |

## Gates (full set, serial, merged tree)

Logs: [`logs/w7-merged/`](logs/w7-merged/).

| Gate | Result |
|---|---|
| compile | 120 / 0 |
| run_tests | 278 PASS, fails=0 |
| M2 | 11 PASS, fails=0 |
| door walk / viewmodel / Niagara | `DOORWALK PASS` / `VIEWMODEL_TRUTH PASS` / `NIAGARA_PROBE PASS` |
| probe_leak (`TAT2_NO_DEN_PROBE=1`) | exit 0, 0 ERROR lines |
| E2E | 278 / 278 (tier 1: 117; includes `--tier=s2`) |
| `build/qa/test_perf_guard.sh` | 78 checks, 0 fails |
| `make texture-cap-check` | capped 773, alpha-critical 1, offenders 0 |
| `make audit` | PASS — disk-backed coverage 12657 / 12703 (99.6 %), 0 unexpected, 13/13 content groups |
| `make gate-ratchet` | PASS |

E2E moved 264 → 278 because W7H added the guard-sprint pair (`T1-23-A/B`) and
W7S added the 12-case S2 loot tier.

## Integration defects found by the merged run (fixed here)

1. **Door-collapse dropped the stashed haul.** W7E's `_on_door_collapsed()`
   failed the run without a payout, so an endgame timeout destroyed stashed
   value that S2's rule says is always kept. It now banks the same failure
   payout as a main-clock timeout (guarded by `_payout_applied`) and shows the
   payout score instead of gross `loot_value`. Made while resolving the W7E
   cherry-pick conflict, so it rides in `bfef943` rather than its own commit.
2. **Stale import cache broke the moon.** The first merged E2E run failed
   `T1-01-C` (`moon_visible=0.0`) because `game/.godot/imported` held only the
   uncompressed `.ctex` for `T_Moon_D.png` and three `T_RoofSlateA` maps, so the
   S3TC load path failed and the disc never became visible. `tools/godot
   --headless --path game --import` regenerated the `.s3tc.ctex` variants
   (no tracked file changed; `project.godot` untouched). Tier 1 then passed
   117/117 and the full run 278/278. **This is an environment repair, not a code
   fix** — a fresh checkout that has never been imported will reproduce it.

## Audit

The baseline stamp had to move because the loot producers changed output:

- `parse_settings.py` is new → `gen:gameplay/loot_settings.json`;
- `parse_loot.py` → `loot_actors.json` (carry fields);
- `parse_contracts.py` → `contracts.json` (`reward_money`);
- `parse_containers.py` → `containers.json` (stash kind);
- `parse_tables.py` / `parse_gameplay.py` move only through their
  `gen:gameplay` directory hash.

Before re-stamping, the six producers were re-run and produced **byte-identical
output** (same sha256), so the accepted hashes are producer output, not hand
edits. Coverage did not move (12703 resolved, 12657/12703, 0 unexpected); the
re-stamp accepted producer hashes, freshness stamps and the `Makefile` entry
only.

## Cross-lane contamination (contained)

A worktree's `game/data` is a symlink into the main checkout, so a lane that
runs `make normalize` writes into `main`. W7S did so before the guardrail, which
is why the baseline drifted mid-wave; it reverted `tools/audit_baseline.json` to
HEAD and integration re-stamped at the merged tree. All four remaining lanes
were told to treat generated data as read-only, and did.

Lesson for the next wave: **give each lane its own generated-data copy, or make
`make normalize` refuse to run outside the main checkout.** A shared writable
symlink plus five lanes is a race by construction.

## Decisions applied

- Main clock from the mission row (LootTheRoom 3300 s = 55:00), map row as
  fallback.
- Endgame 1200 s (KF13 override), 240 s per gate, all 25 authored markers;
  VaultHeist keeps 300 s.
- Loot: 12 slots, minor 1 / major 3 / quest 1; binary keep (escape keeps
  carried, capture keeps 0, stashed always kept); no difficulty multiplier.
- Hearing: geometric surface resolver + swing-door creak + indoor weather
  scope before any balance tuning.
- Descent: D1 ray fix + D5 landing coalescing; D2 stays default-off.
- KF11: full distant skyline as tracked TAT-2 expansion content.
- Roughness: full-resolution bake retained, process-global cache.
- Sonar: new-code Reliability A + Security A + duplication ≤ 3 %; no coverage,
  no maintainability.

## Open / not measured

- **Perf matrix not run.** The export is stamped and hashed, but no publishable
  run exists and the thermal gate is waived, not passed. Do not quote FPS.
- **Editor ≤ 2.5 GB VRAM threshold unproven** — `nvidia-smi memory.used` is
  device-wide. Needs a per-process instrument and a normal close.
- **SonarCloud gate still unbound**: autoscan off, project token, "TAT-2 New
  Code" gate and Previous-version period are manual UI steps.
- **Live playtests owed**: 25 m sprint hearing indoors, silent-surface feel,
  0.33 m civic descent camera, swing-creak in a corridor, indoor/outdoor seam
  under the Old Manor arches and Jaspering colonnade, roof eave feel.
- **Walked descents 0.18–0.30 m still take 4–12 airborne frames** with D2 off
  (measured D2 opt-in: 1–2 frames, 0.001 m shove-back).
- **C8 Guildhall haze/wet ground and C9 horizon-vs-zenith captures** were not
  taken; their staging is in the mission path, outside the visual lane.
- Deferred visual polish: monochrome slot icons, blurred Ledger/Wardrobe
  background, briefing paper tone/creases and the `SPACE` keycap.
- Co-op: host-once banking is local-only; client extraction does not RPC.
