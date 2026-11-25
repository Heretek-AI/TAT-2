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

| Gate | Passing value (W7 merged tree, `6760dd0`, logs in `docs/reports/logs/w7-merged/`) |
|---|---|
| compile | 120 checked, 0 broken |
| `run_tests.gd` | `SUMMARY: fails=0` (278 PASS; suites numbered to 90) |
| `test_m2_player.gd` | `M2_SUMMARY: fails=0` (11 PASS) |
| door walk / viewmodel / Niagara probes | `DOORWALK PASS` / `VIEWMODEL_TRUTH PASS` / `NIAGARA_PROBE PASS` (3695 authored / 3308 active / 36 systems) |
| E2E | `fails=0 passed=278 total=278` (tier 1: 117; includes `--tier=s2`) |
| `make texture-cap-check` | OK — 773 capped, 1 alpha-critical kept, 0 offenders |
| `make audit` | exit 0, tracked baseline matches, disk-backed coverage 99.6 % (12657/12703), 0 unexpected, exact-case 0 unexpected, 13/13 content groups |

The 2026-11-24 W7 wave (five lanes, cherry-picked) re-ran the **complete** set
serially on `6760dd0` — compile, `run_tests`, M2, the three probes, `probe_leak`
(`TAT2_NO_DEN_PROBE=1`), E2E 278/278, `test_perf_guard.sh` (78/78), `make audit`
and `make texture-cap-check` — after regenerating and re-stamping the audit
baseline. Evidence: [`docs/reports/logs/w7-merged/`](docs/reports/logs/w7-merged/)
and [`docs/reports/w7-integration.md`](docs/reports/w7-integration.md). E2E moved
264 → 278 (W7H guard-sprint pair + W7S 12-case loot tier); `run_tests` moved
263 → 278 (S2 suites 89/90, W7E suite, W7H tests).

If `.godot/imported` lacks the `.s3tc.ctex` variants, `T1-01-C` fails with
`moon_visible=0.0`. Run `tools/godot --headless --path game --import` first; it
repairs the cache and changes no tracked file.

The perf matrix is **not run** (thermal gate waived, but no parallel Godot and
the host idles near 80 °C); the editor core opened but its ≤2.5 GB VRAM
threshold is unproven because `nvidia-smi memory.used` is device-wide.

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

**The symlinked data tree is read-only for workers.** `game/data` is a single
shared directory, so a worker that runs `make normalize`, any `tools/parse_*.py`
or `make audit-refresh-stamps` writes into the main checkout and rewrites the
audit baseline for every other lane mid-run. In W7 that happened and produced a
phantom `make audit` failure in four lanes. Only the integrator regenerates
generated data, and only at the merged HEAD; a worker that needs new producer
output must ask for it. If a lane genuinely must regenerate, give it a private
copy of `game/data` instead of the symlink.

## Definition of done for any wave

```bash
git status --short                      # clean, or only intentional new files
make audit                              # exit 0
tools/godot … check_scripts_compile.gd  # 0 broken
make test                               # fails=0
tools/godot … test_m2_player.gd         # fails=0
tools/godot … probe_leak.gd             # expected result or documented warning
tools/godot … run_e2e_tests.gd          # 278/278, no new failures
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
