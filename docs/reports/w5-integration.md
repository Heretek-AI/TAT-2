# W5 integration — six parallel waves merged onto `main`

Date: 2026-11-24
Base: `950f7ca` (docs: record the Spider chain, guard fixes and deferred full gates)
Integration checkout: `<repo>` (primary), not a worktree.
Mode: serial, one Godot at a time. Thermal gate waived by the user; the perf
matrix, GI, captures and a parallel Godot were **not** run.

## 1. Commits

All six branches were cut from `950f7ca`, so each cherry-pick replays a W5 diff
against a `main` that already contains the earlier W5 waves.

| Source | Cherry-picked | Subject |
|---|---|---|
| `9e94a16` | `e6daa96` | fix(player): authored step-up, 60° floor, mantle gate and wardrobe LOS (W5A) |
| `0fbf4c6` | `4b3a4ff` | fix(loader): roof collision, masked opacity, mountain and poster materials (W5B) |
| `da8c79f` | `34c2893` | fix(weather): rainy Guildhall, horizon haze and west Den window staging (W5C) |
| `91c1b0d` | `d7c0b7c` | fix(audio,hud): cue lifecycle, single bed and reference gem/compass (W5D) |
| `3772a51` | `683e592` | feat(data): unlock, hearing and guard-state-tree producers (W5E) |
| `dde229a` | `b6e8cd5` | chore(sonar): project config and P0 fixes (W5F) |
| — | `94a75e3` | chore(audit): re-stamp baseline after W5 normalize |

## 2. Conflicts and resolutions

No cherry-pick stopped: git auto-merged the three expected files. Each merge was
verified by content, not by exit code.

| File | Waves | Resolution |
|---|---|---|
| `game/tests/run_tests.gd` | W5A (suite 45, ~line 3529) vs W5C (suite 10 / 17 / 17b-c, ~line 313-1169) | **Both intents kept.** Suite 45 pins the authored values (60°, 0.25–0.3 snap, 1.82 m capsule, 0.45 m step, `atan2(0.25,0.33)` = 37.1°, 70° blocked). Suite 10 asserts the authored `gloomy` mapping derived from `preset_name_for_map("guildhall")` × `FOG_DENSITY_SCALE`, **not** `midnight_clear`. The regions are disjoint, so the merge is textual, not a hunk choice. |
| `tools/manifest_audit.py` | W5E (`PRODUCERS`: parse_unlocks/parse_hearing/parse_state_tree) vs W5F (`_print_freshness` sentinel ~1509) | **Both kept.** The three producer entries are present (lines 199–210) and the `oldest_out: float \| None = None` sentinel + allowlist message are present (lines ~1498–1511). |
| `tools/audit_baseline.json` | W5C (`gen:weather` pin) vs W5E (three producer entries + `gen:gameplay` 17→21 files) | **Both kept**, then regenerated: `parse_hearing/parse_state_tree/parse_unlocks` entries present and `gen:weather` still pinned at the W5C content (`38638` B). The authoritative values were then rewritten by `make normalize` + `make audit-refresh-stamps` (§3). |

Conflict-free as expected: `Makefile` (NORMALIZERS gained `parse_unlocks
parse_hearing parse_state_tree`), `tools/parse_weather.py`,
`game/src/core/level_loader.gd`, `game/src/player/thief_character.gd`,
`game/src/core/audio_manager.gd`, `game/src/ui/hud.gd`.

## 3. Producers and regenerated outputs

`make normalize` (exit 0) ran all 21 normalizers including the three new
producers:

| Producer | Output |
|---|---|
| `parse_unlocks.py` | 68 unlockables (Cosmetic 54 / Difficulty 3 / Gear 7 / Map 2 / Thief 2), 55 priced, 0..750000 |
| `parse_hearing.py` | 54 stimuli, 22 loudness surfaces, 11 weather types, 285 acoustic portals; `perception.json` 5/4 modifiers, 5 authored anomalies recorded |
| `parse_state_tree.py` | 21 StateTrees / 459 states / 467 transitions; `ST_Guard` 126/148/17, `ST_Civilian` 73/82/10 |
| `parse_weather.py` | Guildhall → `gloomy` (`wet_ground=5, haze_volumes=27, cloud_masks=4, moon_actors=8`), 16 presets byte-identical |

**Idempotence.** A second `make normalize` changed **nothing** (326-file SHA-256
manifest identical), so the regenerated tree is a fixed point of the merged
producers. `PYTHONHASHSEED=random` re-runs of `parse_vfx.py` are also
byte-identical.

### Content changes accepted by the re-stamp (4)

`git diff tools/audit_baseline.json`: 42 insertions / 42 deletions, of which 38
are `newest_mtime` restamps and 4 are content:

| Output | Producer | Change | Cause |
|---|---|---|---|
| `gen:weather` | `parse_weather.py` | 38,494 → 38,638 B | **W5C** — Guildhall `gloomy`; only `map_weather.json` changed |
| `gen:gameplay` | `parse_tables.py`, `parse_gameplay.py` | 4,213,797 → 5,337,591 B, 17 → 21 files | **W5E** — unlocks/hearing/perception/guard_behavior |
| `gen:gameplay/devices_runtime.json` | `parse_devices.py` | 2,115,363 → 2,115,474 B | pre-existing checkout drift (below) |
| `gen:vfx` | `parse_vfx.py` | 1,390,631 → 1,391,652 B | pre-existing checkout drift (below) |

**The last two are not caused by any W5 commit** — no W5 branch touches
`parse_devices.py`, `parse_vfx.py`, `parse_materials.py`, `extracted/` or
`game/data/generated/vfx`. They were already drifted before this integration's
normalize (the pre-normalize hashes did not match the pin), they reproduce
deterministically now, and they pass every content gate: `devices` 4,118
records / 21 families, `niagara` 3,695 records, `parse_vfx` classes
21 `graph_heavy` / 70 `mesh_or_ribbon` / 29 `sprite_only` across 120 systems
(the exact numbers suite 46 pins). They are recorded here rather than blessed
silently; a later wave can bisect which worktree wrote the drifted copies if it
matters.

Stamp-only drift from **W5F**, no output change: `tools/extract_audio.py`
source drift (the 9 synthesized fallbacks are byte-identical, per the W5F
report), `tools/tat-extract/Program.cs`, `tools/prebake_texture_cap.py`,
`tools/fetch_vgmstream.sh` sha256 values. `desktop-texture-cap` / `audio-tools`
did **not** need a re-run: `make texture-cap-check` still passes with the same
773/1/0 split and vgmstream is still r2168.

## 4. Audit

```
make audit-refresh-stamps   # intentional: producers and outputs changed
make audit                  # PASS, exit 0
```

`make audit`: **AUDIT PASS**, 0 FAIL, 13/13 content groups OK, baseline matches,
disk-backed coverage **12657/12703 (99.6 %)**, 46 allowlisted missing,
**unexpected 0**, exact-case **0** unexpected, 4,639 Engine/Content files
mounted, engine-deps OK.

## 5. Gates (serial, measured on `94a75e3` + docs)

| Gate | Result |
|---|---|
| `tools/check_scripts_compile.gd` | **101 checked, 0 broken** (96 + the 5 new W5 tests) |
| `res://tests/run_tests.gd` (full) | **`SUMMARY: fails=0`**, exit 0, 261 PASS, suites numbered to 88 |
| `res://tests/test_m2_player.gd` | **`M2_SUMMARY: fails=0`**, exit 0, 11 PASS |
| `res://tests/probe_door_walk.gd` | **`DOORWALK PASS`** |
| `res://tests/probe_viewmodel_truth.gd` | **`VIEWMODEL_TRUTH PASS`** (zip/top emissive off, crank bone posed+reset) |
| `res://tests/probe_niagara.gd` | **`NIAGARA_PROBE PASS`** files=107 authored=3695 active=3308 skipped=387 systems=36 |
| `res://probe_leak.gd` (`TAT2_NO_DEN_PROBE=1`) | exit 0, clean path, 0 leftover players, no RID warnings |
| `res://tests/e2e/run_e2e_tests.gd` (full) | **`fails=0 passed=264 total=264`**, exit 0 |
| `make texture-cap-check` | **OK** — 773 capped, 1 alpha-critical kept, 738 within cap, **0 offenders** |
| `make audit` | **PASS** (§4) |

Extra verification of the new W5 standalone tests (not part of the standing gate
list, run because the merged tree must own them):

| Test | Result |
|---|---|
| `tests/test_stair_walk.gd` | `W5A_SUMMARY: fails=0` (7/7) |
| `tests/test_roof_collision.gd` | `ROOF_COLLISION_SUMMARY: fails=0` (27/27) |
| `tests/test_w5b_materials.gd` | `W5B_MATERIAL_SUMMARY: fails=0` (27/27) |
| `tests/test_audio_lifecycle.gd` | `AUDIO_LIFECYCLE_SUMMARY: fails=0` (13/13) |
| `tests/test_hud_gem_compass.gd` | `HUD_GEM_COMPASS_SUMMARY: fails=0` (11/11) |

Cross-wave evidence inside the full suite:

```
PASS: 45 stairs (max_angle 60.0 deg, snap 0.3 m, capsule 1.82 m, step 0.45 m + 0.2 m probe, civic flight 37.1 deg walkable, 70 deg blocked, wall-block/constant-speed kept, no new mantle)
PASS: Guildhall map preset wins over stale default map (preset=gloomy fog_density=0.00480000022799)
PASS: W5C Guildhall weather = authored gloomy (rain=1.0 wet=1.0 fog=0.16 evidence={ wet_ground: 5, haze_volumes: 27, cloud_masks: 4, moon_actors: 8 })
PASS: W5C near-field fog calibrated (density=0.0048 transmittance 20/30/120 m=0.91/0.87/0.56)
PASS: W5C horizon haze floor (outdoor=0.55 lum=0.129 den=0, exposure untouched)
PASS: W5C sky shader one moonlit cloud tint + coverage/opacity split (cloud_tint uses=3)
PASS: W5C Den window staging anchors the west framed window (facing=(-0.848048, 0.0, 0.529919) source=window_positions anchor=(-6.06, 43.05, 271.4) sil_lum=0.066)
```

No assertion was weakened, skipped or deleted. The only expectations changed are
the ones W5A/W5C proved stale (50°→60°, 55°→70° control, `atan2(0.18,0.28)`→
`atan2(0.25,0.33)`, `guildhall → midnight_clear`→`gloomy`, `density × 0.01`→
`× FOG_DENSITY_SCALE`, `fog_sky_affect == 0`→ the outdoor/indoor floor
constants), each of which now reads its value from the producer or a constant.

## 6. Not run, by instruction or constraint

- Perf matrix, GI, screenshots/Vulkan captures, `make run` visual pass.
- No parallel Godot; every gate above ran alone. Thermal gate waived.
- **No push was issued by this integration.** `main` is clean at the docs commit
  on top of `94a75e3`. `origin/main` was nevertheless observed at `94a75e3`
  (reflog: `update by push` after `b6e8cd5`), i.e. an external actor pushed the
  code commits during the run; there are no git hooks and nothing in the
  Makefile/`build/qa` pushes. The docs commit is the only local-only commit.
