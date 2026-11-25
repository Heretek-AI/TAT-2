# AGENTS.md — operating rules for this repository

Applies to every coding agent working in `/home/john/Projects/TAT-2`, whatever
the harness (OpenCode, Claude Code, Codex). Read this file before editing,
regenerating data, capturing screenshots or claiming a gate is green.

**What this repo is:** a private-use, asset-faithful port of the shipped UE5.5
game *Thick As Thieves* to Godot 4.7.2. The game loads the real extracted assets;
`extracted/`, `game/assets/ue/` and `game/data/generated/` are git-ignored and
must never be committed or redistributed. Only original code, tools and the
TAT-2 expansion content belong in git.

## Read before you touch

| If you are about to… | Read first |
|---|---|
| Change rendering, loader, materials or lighting | [`docs/FIDELITY_GAPS.md`](docs/FIDELITY_GAPS.md), the latest [`docs/reports/`](docs/reports/) wave |
| Regenerate or extend extracted data | [`docs/HANDOFF_NEXT_AGENT.md`](docs/HANDOFF_NEXT_AGENT.md) §5 (pipeline gotchas) |
| Change gameplay, UI or mission flow | handoff §1 (state), the owning `game/tests/` suites |
| Add or fix tests / E2E assertions | `game/tests/e2e/run_e2e_tests.gd` header, tier files |
| Take a screenshot or compare with UE | `build/qa/` harness sources, handoff §2 |
| Ship a wave | this file §“Definition of done”, then update the docs |

## Non-negotiable rules

1. **Never commit extracted content.** `extracted/`, `game/assets/ue/`,
   `game/data/generated/`, `game/i18n/generated/`, `build/` artifacts and
   `game/.godot/` are private/derived. `build/qa/` **script sources** are tracked
   on purpose; PNG/log artifacts are not.
2. **Never edit `game/` while a Godot process is running.** Scripts load lazily;
   a mid-run edit produces meaningless results. Edit between runs only.
3. **Do not weaken, skip or delete a test to go green.** Fix the game, or record
   the defect with evidence and an owner in `docs/FIDELITY_GAPS.md`. Changing an
   expectation is allowed only when the assertion itself was wrong (e.g. the
   intentional `MI_LightBeam_SM` shader exception in T2-04-C).
4. **Serialize GPU work.** Headless is the default. For Vulkan captures run one
   Godot at a time under Xvfb; never poll or run parallel GPU jobs.
5. **Generated data is produced, not hand-edited.** Fix the producer
   (`tools/parse_*.py`) then `make normalize`. Regenerated files are gitignored;
   commit the producer and the code that consumes it.
6. **Keep the authored lens.** World FOV is 54.54 vertical (UE 85 horizontal at
   16:9). The only permitted migration is the one-time legacy saved `fov: 75` →
   54.54; never clamp explicit user values.
7. **Respect runtime contracts.** Groups and flags other code depends on:
   `blocking_volume` (invisible designer blockers must stay solid but unclimbable),
   `swinging_doors`, `loot`, `xray_target`, `GameState.free_play` /
   `free_play_pending`, `MissionPrepUI.open_prep(..., free_play)`. Do not rename
   or repurpose them without updating every consumer and test.
8. **Native engine binary first.** Use `tools/godot` (falls back to Flatpak).
   `godot` is not on `$PATH`.
9. **One coherent commit per change**, with gate evidence in the message or the
   wave report. Push `main` when the tree is clean and gates are green.
10. **Never fabricate a measurement.** Captures, ROIs and timings must come from a
    real run; say “not verified” otherwise.

## Commands and gates

```bash
make run         # native 4.7.2 client, F3 overlay
make test        # tests/run_tests.gd — 59 suites (re-measure; see gate table)
make audit       # fail-closed content + producer/output baseline gate

tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
tools/godot --headless --path game --script res://tests/test_m2_player.gd
tools/godot --headless --path game --script res://probe_leak.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=1
```

| Gate | Passing value (W7G re-measured compile/run_tests/M2/probe_leak/E2E; the other rows are the W6 base) |
|---|---|
| compile | 110 checked, 0 broken |
| `run_tests.gd` | `SUMMARY: fails=0` (263 PASS; suites numbered to 88) |
| `test_m2_player.gd` | `M2_SUMMARY: fails=0` (11 PASS) |
| door walk / viewmodel / Niagara probes | `DOORWALK PASS` / `VIEWMODEL_TRUTH PASS` / `NIAGARA_PROBE PASS` (3695 authored / 3308 active / 36 systems) |
| E2E | `fails=0 passed=264 total=264` (tier 1: 115) |
| `make texture-cap-check` | OK — 773 capped, 1 alpha-critical kept, 0 offenders (base; not re-measured in W7G) |
| `make audit` | exit 0, tracked baseline matches, disk-backed coverage 99.6 % (12657/12703), 0 unexpected, exact-case 0 unexpected, 13/13 content groups (base; not measurable in the W7G worktree — see below) |

The 2026-11-24 W7G wave re-ran **compile, `run_tests`, M2, `probe_leak`
(`TAT2_NO_DEN_PROBE=1`) and E2E 264/264** serially on `74a43b8` + the wave tree,
plus `build/qa/test_perf_guard.sh` (78/78), the Linux export stamp and the core
bake. Evidence: [`docs/reports/logs/`](docs/reports/logs/) and
[`docs/reports/w7g-gates.md`](docs/reports/w7g-gates.md).

**`make audit` was not run in W7G.** `game/data` is a symlink into the main
checkout and the W7S lane's uncommitted loot producers changed 4 `gen:gameplay`
files plus a directory hash; audit would fail on drift this wave does not own.
Integration regenerates and re-stamps at the merged HEAD. The audit and
texture-cap floors in `tools/gate_ratchet.json` are unchanged base values and
are **not** evidence for W7G.

The perf matrix is **not run** (thermal gate waived, but no parallel Godot and
the host idles near 80 °C); the editor core opened but its ≤2.5 GB VRAM
threshold is unproven because `nvidia-smi memory.used` is device-wide. The
merged tree will measure higher than these floors (S2 suites, W7E/W7H tests);
integration raises them with fresh logs.

Anything below these numbers is a regression. Do not re-baseline silently; find
the cause or record it.

## Architecture in one screen

```
game/src/core/        level_loader (UE→Godot world), game_data, game_state,
                      save_system, audio_manager, shaders (tat_*.gdshader)
game/src/player/      thief_character (movement, mantle, wall climb, zipwire)
game/src/ai/          guard_ai, civilian_npc
game/src/stealth/     light_probe, noise_bus
game/src/interact/    swinging_door, loot, clues, escape gates
game/src/missions/    mission_controller (spawns, Den/Guildhall fills, sign, free play)
game/src/ui/          main_menu, contract_table, mission_prep, hud, wardrobe, settings
game/tests/           run_tests.gd, test_m2_player.gd, probe_*.gd, e2e/tiers 1-4
tools/                tat-extract (.NET), parse_*.py producers, manifest_audit
build/qa/             tracked capture/probe scripts; PNG output ignored
```

## Known traps

- **`game/assets/ue/Raw` is read-only.** Write the physical path under
  `extracted/assets/…`; the hidden `TAT/` subtree must keep its `.gdignore` or
  duplicate UIDs return.
- **Texture cap is not reproducible from extraction.** Rerun
  `make desktop-texture-cap` after a clean extract and after `make normalize`.
- **`parse_materials.py` must read `BasePropertyOverrides`** (two-sided, blend,
  unlit) and prefer a child MI's own `_D` companion over the parent master's
  painterly `T_PaintStrokesD`. Regressing either silently breaks gates, doors and
  floors.
- **`MI_LightBeam_SM` is a deliberate exception** to the HDR neon path: it uses
  additive `tat_beam.gdshader`. T2-04-C guards the exception plus three
  `StandardMaterial3D` negative controls.
- **WorldGrid substitution is scoped** to door/gate/fence meshes. WorldGrid is
  still intentional for spheres/emitters; never hide it globally.
- **Loot/civilian spawns are grounded by mesh AABB + floor ray** (0.03 m
  clearance). Do not reintroduce a blanket vertical offset.
- **Free play must not bank progression.** `_on_extracted()` skips both
  `record_contract_complete` and `add_currency`; a normal deploy clears
  `free_play`/`free_play_pending`.
- **Guildhall POI graybox floors** (1,637 `GB_Floor_2x2`) are a deferred content
  project, not a loader defect. Do not “fix” them by nudging the loader.
- **Den probe leak:** 7 texture RIDs warn at exit; `TAT2_NO_DEN_PROBE=1` is the
  clean path. Not a script error.
- **Roughness bake is full-resolution and process-cached.** The L8
  `low + g*(high-low)` bake is keyed by ORM+range in a process-global cache and
  released only when the last live loader leaves the tree. Do not add a
  half-res path; `TAT2_ROUGH_BAKE=off` is a documented diagnostic fallback
  (`roughness=high`, no texture), never the default.
- **The QA export is stamped, not trusted.** `make linux-build` writes
  `build/tat2-linux-x86_64.stamp.json`; the perf wrapper fails closed on a
  missing, stale or hash-mismatched stamp, and a dirty build is not
  publishable. `scenes/review/**` is excluded from the export. Do not hand-edit
  or delete the stamp; rebuild.
- **`export_presets.cfg` must not contain `#` comments.** Godot's `ConfigFile`
  parser does not treat `#` as a comment: it merges the comment and the next
  key into one malformed key, so `exclude_filter` silently disappears and the
  export includes `scenes/review/**` with no error. Use `;` or keep the
  rationale in the report. Prove it with
  `ConfigFile.has_section_key("preset.0", "exclude_filter")` (must be true).
- **Editor opens rewrite `project.godot`.** A visible editor run reorders the
  file and drops the project's comments/settings. Never commit that rewrite;
  `git checkout -- game/project.godot` after an editor check.
- **Sonar does not see GDScript.** Its gate is new-code Reliability A +
  Security A + duplication <= 3 %; coverage and maintainability are not gate
  conditions. The GDScript floors live in `tools/gate_ratchet.json` and are
  checked against the committed logs in `docs/reports/logs/`.
- **Maps with authored placeholders** (`Mission.Example.*` fallbacks, Niagara
  placement notices, fog clamp, deferred navmesh) log expected warnings; do not
  “clean up” the logs by suppressing the messages.

## Parallel waves

Long waves may be split across subagents in separate git worktrees. Symlink
`game/assets`, `game/data/generated` and `extracted` into the worktree, copy
`game/.godot` for imports, never edit the main checkout from a worker, and
cherry-pick the worker commit onto `main` after its gates pass. Resolve conflicts
by taking both intents (e.g. the `blocking_volume` tag comment), then rerun the
full gate set on the merged tree — not just the worker's suite.

## Definition of done for any wave

```bash
git status --short                      # clean, or only intentional new files
make audit                              # exit 0
tools/godot … check_scripts_compile.gd  # 0 broken
make test                               # fails=0
tools/godot … test_m2_player.gd         # fails=0
tools/godot … probe_leak.gd             # expected result or documented warning
tools/godot … run_e2e_tests.gd          # 264/264, no new failures
build/qa/test_perf_guard.sh             # 78/78, no GPU
make gate-ratchet                       # floors + committed logs agree
git push origin main
```

When a Linux export is part of the wave, add `make linux-build` +
`make linux-stamp-verify` and record the `EXPORT_STAMP`/`PERF_PCK` lines.

Then update, in the same wave:

- `docs/FIDELITY_GAPS.md` — what changed and what remains;
- a `docs/reports/<wave>.md` with measured evidence;
- `docs/HANDOFF_NEXT_AGENT.md` — HEAD, gates, open work;
- `README.md` only when user-facing commands/status change.
