# TAT-2 — *Thick As Thieves* rebuilt in Godot 4.7

A private-use, asset-faithful port of the shipped UE5.5 game *Thick As Thieves*
to **Godot 4.7.2** (Forward+, Jolt, 1280×720 reference). The port loads the real
extracted geometry, materials, landscapes, audio, animation and gameplay tables;
the TAT-2 expansion adds **The Moth** thief, **Jaspering Hall** and co-op.

> **Private-use notice.** Extracted assets from the Steam install live in
> `extracted/` and `game/assets/ue/`, both git-ignored. Only original code, tools
> and expansion content are committed. Do not redistribute extracted content.

**Status (2026-11-23, `a410adc`)** — playable end-to-end: startscreen → Den →
contract prep → Guildhall run → scoring, plus free-play cleanout, two-player
ENet co-op and all four E2E tiers.

| Gate | Result |
|---|---|
| GDScript compile (`tools/check_scripts_compile.gd`) | **58 scripts, 0 broken** |
| Unit/integration (`tests/run_tests.gd`) | **54 suites, fails=0** |
| M2 traversal/tools (`tests/test_m2_player.gd`) | **fails=0** |
| E2E (`tests/e2e/run_e2e_tests.gd`, tiers 1–4) | **262/262** (tier 1: 115) |
| Door walk · viewmodel truth · Niagara | **PASS** |
| Steam manifest + content audit (`make audit`) | exit 0, fail-closed tracked baseline, mount/path 100.0 % (exact-case 99.4 %), 13/13 content groups |

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
| `make test` | 54-suite headless integration run |
| `make audit` | Fail-closed gate: mount/disk coverage, 13 content domains, producer output hashes, `errors.log` marker, freshness |
| `make audit-bootstrap` | Explicit first run; writes the tracked `tools/audit_baseline.json` |
| `make audit-refresh-stamps` | Escape hatch after regeneration; missing/decreased outputs still fail |
| `make audit-imports` | Separate Godot import gate (`.import` sidecars + `.translation`) |
| `make normalize` | Run all 17 generated-data producers |
| `make linux-build` / `make linux-run` | Linux x86_64 export / run |
| `make android-debug` / `make android-release` | Signed internal APK |
| `make desktop-texture-cap` | Re-bake the 1024 px texture cap |

`tools/audit_baseline.json` is tracked and records every producer/infrastructure
hash, external tool version and per-output content digest. A normal run with no
baseline fails; `make audit-bootstrap` is the explicit first-run path.
`tools/audit_allowlists.json` holds the 73 known case-only path normalizations,
33 case-only `.ubulk` companions and 46 known-undumped manifest paths.

Headless gates that are not Make aliases:

```bash
tools/godot --headless --path game --script tools/check_scripts_compile.gd
tools/godot --headless --path game --script res://tests/test_m2_player.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd
tools/godot --headless --path game --script res://probe_leak.gd
```

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
- **QA autostart:** `--qa-free-play`, `--qa-mission`, `--qa-contract <n>`.

## Repository layout

```
game/                 Godot project (src/, scenes/, tests/, assets/ue -> extracted)
tools/                extractor (.NET/CUE4Parse), 17 normalizers, audit + guards
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
- [`docs/reports/review-remediation-wave.md`](docs/reports/review-remediation-wave.md)
  — latest wave: beams, two-sided materials, albedo recovery, doors, traversal
  blockers, FOV, loot grounding, sign, free play.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md),
  [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md),
  [`docs/reports/`](docs/reports/) — module map, batching numbers, per-area reports.

## Known residuals

See [`docs/FIDELITY_GAPS.md`](docs/FIDELITY_GAPS.md). The visible ones: Guildhall
POI graybox floors/floating furniture, sign lettering low-contrast at 27 m, some
white glass/emissive plates, the Den's 43.5 vs UE 52.6 Lumen GI gap, and a
7-texture probe-exit warning (`TAT2_NO_DEN_PROBE=1` is the clean path).
