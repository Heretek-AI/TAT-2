# TAT-2 — *Thick As Thieves* rebuilt in Godot 4.7

A private-use, asset-faithful port of the shipped UE5.5 game *Thick As Thieves*
to **Godot 4.7.2** (Forward+, Jolt, 1280×720 reference). The port loads the real
extracted geometry, materials, landscapes, audio, animation and gameplay tables;
the TAT-2 expansion adds **The Moth** thief, **Jaspering Hall** and co-op.

> **Private-use notice.** Extracted assets from the Steam install live in
> `extracted/` and `game/assets/ue/`, both git-ignored. Only original code, tools
> and expansion content are committed. Do not redistribute extracted content.

**Status (2026-11-24, `bc063d2`)** — playable end-to-end: startscreen → Den →
contract prep → Guildhall run → two-phase escape → scoring, plus free-play
cleanout, carried-loot capacity and stashing, two-player ENet co-op and all five
E2E tiers.

| Gate | Result |
|---|---|
| GDScript compile (`tools/check_scripts_compile.gd`) | **120 scripts, 0 broken** |
| Unit/integration (`tests/run_tests.gd`) | **278 checks, fails=0** (suites numbered to 90) |
| M2 traversal/tools (`tests/test_m2_player.gd`) | **fails=0** (11) |
| E2E (`tests/e2e/run_e2e_tests.gd`, tiers 1–4 + `s2`) | **278/278** (tier 1: 117) |
| Door walk · viewmodel truth · Niagara · leak probe | **PASS** |
| Steam manifest + content audit (`make audit`) | exit 0, fail-closed tracked baseline, disk-backed coverage 99.6 % (12657/12703), 13/13 content groups |
| Gate ratchet (`make gate-ratchet`) | **PASS** — floors verified against committed logs |

Not yet measured: the perf matrix (no publishable FPS run) and the editor's
per-process VRAM. Do not quote frame rates from any older run.

## Quick start

```bash
make run        # launch the game (native tools/godot, Flatpak fallback)
make test       # headless unit/integration suite
make audit      # fail-closed content + producer-baseline gate
python3 tools/test_manifest_audit.py  # negative controls for the audit
```

A fresh clone needs the private assets first:

```bash
make extract              # CUE4Parse dump of the Steam install
make normalize            # generated JSON (levels, materials, gameplay, …)
make anims                # 995 animation GLBs (Blender, ~30 min)
tools/reimport_assets.sh  # Godot import
make desktop-texture-cap  # 1024 px cap + mipmaps (rerun after clean extract)
```

Requirements: Godot 4.7.2 (`tools/godot` wrapper), Python 3, .NET 10 SDK (extractor),
Blender (anims). Linux x86_64 desktop is the supported target; Android internal
builds are documented in [`docs/ANDROID.md`](docs/ANDROID.md).

## Commands

| Command | Purpose |
|---|---|
| `make run` | Launch the desktop client (`F3` = FPS/draw-call overlay) |
| `make test` | Headless integration run (278 checks) |
| `make audit` | Fail-closed gate: texture cap, mount/disk coverage, 13 content domains, producer output hashes, `errors.log` marker, freshness |
| `make gate-ratchet` | Assert the gate floors in `tools/gate_ratchet.json` against the committed logs in `docs/reports/logs/` |
| `make audit-bootstrap` | Explicit first run; writes the tracked `tools/audit_baseline.json` |
| `make audit-refresh-stamps` | Escape hatch after regeneration; missing/decreased outputs still fail |
| `make audit-imports` | Separate Godot import gate (`.import` sidecars + `.translation`) |
| `make normalize` | Run all 21 generated-data producers |
| `make linux-build` / `make linux-stamp-verify` / `make linux-run` | Linux x86_64 export, its HEAD/PCK provenance stamp, and a run |
| `make android-debug` / `make android-release` | Signed internal APK |
| `make desktop-texture-cap` | Re-bake the 1024 px texture cap |
| `make texture-cap-check` | Read-only: fail if any over-cap loader texture lacks the cap + mipmaps |
| `make editor` | Open the Godot editor with the **TAT-2 Review** dock |
| `make bake-review MAP=guildhall` | Headless bake of one binary `LevelLoader` scene per sublevel (+ manifest) |
| `make bake-review-core` | Bake the single-file core map used for load/VRAM checks |
| `make review MAP=guildhall` | In-game free-camera review of the static world (no mission) |
| `build/qa/test_perf_guard.sh` | Exercise the perf wrapper's stamp/temperature/RSS contracts without launching a game |

`tools/audit_baseline.json` is tracked and records every producer/infrastructure
hash, external tool version and per-output content digest. A normal run with no
baseline fails; `make audit-bootstrap` is the explicit first-run path.
`tools/audit_allowlists.json` holds the 73 known case-only path normalizations,
33 case-only `.ubulk` companions and 46 known-undumped manifest paths.

Headless gates that are not Make aliases:

```bash
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
tools/godot --headless --path game --script res://tests/test_m2_player.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd
tools/godot --headless --path game --script res://probe_leak.gd
```

## World review

The real Guildhall/Den/Old-Manor world can be inspected without starting a
mission, with the same `LevelLoader` the game uses:

```bash
make bake-review MAP=guildhall   # per-sublevel .scn + world.scn + review.tscn + manifest
make editor                      # TAT-2 Review dock: bake/open, sublevel+kind toggles, bookmarks
make review MAP=guildhall        # in-game free camera (WASD/QE, 1-0 toggles, F1-F6 bookmarks, P capture)
make review-capture MAP=guildhall # offscreen six-bookmark PNG sweep (no window presentation needed)
```

Generated scenes land in `game/scenes/review/<map>/` and are git-ignored
(extracted-content derivatives). The in-game camera loads the live world, not
the baked scenes; `P` saves PNGs to `user://review_captures/`. Architecture,
tagging vocabulary, measured Den/lobby numbers and limits are in
[`docs/reports/review-map-baker.md`](docs/reports/review-map-baker.md).

## Playing

- **Thieves:** The Spider (grapple wire), The Chameleon (disguise integrity),
  The Moth (astral scout, TAT-2 expansion).
- **Gadgets:** Slithersap, smoke bomb, pickpocket fairy, blackjack, Thief Vision,
  lean left/right.
- **Contracts:** 16 shipped contracts across Old Manor and Guildhall on Novice /
  Thief / Master Thief, plus the FTUE tutorial route. The TAT-2 expansion adds
  The Moth, the Jaspering Hall prep/tutorial identity and 2-player ENet co-op.
- **Free play:** in the Thieves' Den map table press **`G`** (or the
  `FREE PLAY: GUILDHALL CLEANOUT [G]` button) for a score-only Contract Inactive
  run of `Mission.Guildhall.LootTheRoom`. No contract progress or currency is
  banked.
- **Run clock:** 55:00 on the main window (the mission's authored duration).
  Completing the objectives summons the escape doors and starts a separate
  20:00 endgame window; the doors stay open for 4 minutes each, then collapse.
- **Loot:** 12 authored inventory slots — minor loot takes 1, major loot 3, so
  four majors fill the bag. A full bag refuses the pickup with the authored
  `INVENTORY FULL` line. Deposit everything at a stash to free slots; stashed
  value is banked even if you are caught, while carried loot is only kept if you
  escape.
- **QA autostart:** `--qa-free-play`, `--qa-mission`, `--qa-contract <n>`.

## Repository layout

```
game/                 Godot project (src/, scenes/, tests/, assets/ue -> extracted)
tools/                extractor (.NET/CUE4Parse), 21 normalizers, audit + gates
build/qa/             tracked capture/probe harness sources (captures ignored)
docs/                 architecture, performance, fidelity tracker, wave reports, handoffs
extracted/            private extraction cache (gitignored)
```

Runtime code lives under `game/src/{core,player,ai,stealth,interact,missions,ui}`;
data under `game/data/generated/` (gitignored, produced by `make normalize`).

## Documentation

- [`AGENTS.md`](AGENTS.md) — operating rules, gates and traps for coding agents.
- [`docs/HANDOFF_NEXT_AGENT.md`](docs/HANDOFF_NEXT_AGENT.md) — current state,
  pipeline gotchas and open work.
- [`docs/FIDELITY_GAPS.md`](docs/FIDELITY_GAPS.md) — live 1:1 coverage tracker and
  every documented residual.
- [`docs/reports/w7-integration.md`](docs/reports/w7-integration.md) — latest
  wave: loot capacity/stash/payout and save v8, two-phase run clock and 25 escape
  markers, surface-resolved hearing, stair descent, KF11 backdrop and Cotter
  wardrobe, export provenance and the Sonar plan.
- [`docs/reports/review-remediation-wave.md`](docs/reports/review-remediation-wave.md)
  — earlier wave: beams, two-sided materials, albedo recovery, doors, traversal
  blockers, FOV, loot grounding, sign, free play.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md),
  [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md),
  [`docs/reports/`](docs/reports/) — module map, batching numbers, per-area reports.

## Known residuals

See [`docs/FIDELITY_GAPS.md`](docs/FIDELITY_GAPS.md). The visible ones: Guildhall
POI graybox floors/floating furniture, sign lettering low-contrast at 27 m, some
white glass/emissive plates, the Den's 43.5 vs UE 52.6 Lumen GI gap, and a
7-texture probe-exit warning (`TAT2_NO_DEN_PROBE=1` is the clean path).

Behavioural residuals: walked descents of 0.18–0.30 m still take 4–12 airborne
frames, the two-phase timer banks local-only in co-op, the post-match haul screen
is not built, and XP still uses the port's invented rule rather than the authored
`DefaultGame.ini` curve — which brings the 48 level-gated market items far
earlier than authored. Hearing is range-based: walls and closed doors do not
block sound yet.
