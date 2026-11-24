# W0T — review truth: authored visibility, review environment, core-min bake

Date: 2026-11-24
Worker: subagent in `/tmp/opencode/tat2-ns-tools` (never edited the main checkout).
Commit: `fix(review): preserve authored visibility, add review environment and core bake`

## 1. What was wrong

Review mode preserved neither authored visibility nor an environment:

- `game/src/ui/review_mode.gd` and `game/addons/tat2_review/dock.gd` set
  `visible = not hidden_by_show_toggle` on every node. Author `bHiddenInGame`
  fixtures are built by `LevelLoader` with `visible = false` and no review meta,
  so the first toggle sweep revealed them. Guildhall's 3rd-floor
  `SM_DonutShell` / `SM_Sphere4Count` debug shells are the floating cyan/blue
  blobs in the review captures.
- Review mode built no `WorldEnvironment` at all. The mission controller owns
  the shipped environment/moon/fills, so review cleared to Godot's black
  default and Foyer/Library captured black.

The loader was correct in both cases and was not edited.

## 2. Authored visibility truth

New rule, implemented once in `review_filters.gd` and used by both review UIs:

```
visible = (review_authored_visible or Hidden in game toggle) and not hidden_by_toggle
```

- `Tagger.apply_tags()` records `review_authored_visible` once, at tagging time,
  before any review toggle runs.
- `Filters.visible_after_toggles()` is the single predicate. Show-toggles can
  only hide; the new `Hidden in game` toggle (review key `H`, dock checkbox,
  persisted in root `review_toggles` metadata) is the only reveal path.
- Defaults: `Hidden in game = false` in both UIs.
- `Tagger.collect_stats()` now reports `hidden_nodes`, `hidden_records`
  (MultiMesh instances weighted), `mixed_nodes` and per-`review_sublevel`
  `{nodes, draws, lights, hidden_nodes, hidden_records}`.

### Authored-hidden accounting (measured)

| Scope | bHiddenInGame records |
|---|---:|
| Guildhall family (`levels/Guildhall` + `levels/Buildings/Guildhall`, all files) | **710** |
| Guildhall review-resolved sublevels (15 base + 1 contract/appended path) | **697** |
| Difference (contract-scoped facades/teleporters: 5+4+2+2) | 13 |

`test_review_visibility.gd` gates 710/697/13 against the generated JSON, and
loads the real authored-hidden `SM_DonutShell` and `SM_Sphere4Count` records
through the real `LevelLoader` (a two-mesh fixture) to prove they arrive
`visible=false` with `review_authored_visible=false`.

### Runtime evidence (headless, no GPU)

Full Guildhall review load, one `load_sublevels_async()` call, 160-light budget:

```
REVIEW loader done nodes=7235
REVIEW stats nodes=31734 draws=5923 lights=160 hidden_nodes=146 hidden_records=626
REVIEW env=review_only preset=midnight_clear sky=true ambient=2 bg=2 fills=0
REVIEW ready map=guildhall bookmarks=6 review_only=1 env=auto hidden_visible=0
Elapsed 12.78 s, Maximum resident set size 1,307,016 KB (~1.31 GB)
COMMAND: tools/godot --headless --path game res://scenes/review_mode.tscn -- \
         --map=guildhall --review-env=auto --quit-after-load
```

`hidden_visible=0` is the gate: with every show-toggle on and `Hidden in game`
off, none of the 146 authored-hidden nodes / 626 hidden instances leaked. Before
this change the same sweep would have made all 626 visible.

Den smoke: `REVIEW stats ... hidden_nodes=6 hidden_records=11`,
`hidden_visible=0` (12 authored flags; one skipped by the loader).

## 3. Review-only environment

New `game/addons/tat2_review/review_environment.gd` builds, after the world
load and before the camera/capture:

1. the mission's fallback `Environment` + moon values (copied; review-only);
2. `WeatherProfile.apply_environment()` with the map's extracted preset;
3. `WeatherVisuals.apply_sky()` (real sky + moon disc);
4. `MobileProfile.apply_environment()` last, like the mission;
5. Guildhall `LocalVolumetric` pass config (global density 0);
6. optional `--gameplay-fills` (gate/fence/ornate/road/foyer/safe-room omnis,
   copied values from `mission_controller.gd`, without touching gameplay state).

`mission_controller.gd` is untouched and never loads this script. CLI:
`--review-env=auto|none` (default `auto`), optional `--gameplay-fills`.

Measured: Guildhall preset `midnight_clear`, `background_mode=BG_SKY`,
`sky=true`, `ambient_light_source=2` (sky), ambient energy 0.200, moon present.
Den preset `midnight_clear_thieves_den`, sky=true.

### Non-black assertion and its threshold

`test_review_visibility.gd` §5 asserts headless: authored preset name is
`midnight_clear`; a `WorldEnvironment` exists; `BG_SKY` + non-null sky material;
reflections from sky; ambient energy **>= 0.02** (WeatherProfile's own clamp
floor); moon energy **>= 0.1**. Before W0T there was no environment at all, so
none of these could hold.

**Pixel capture not run.** This worker is headless-only by instruction; Godot's
headless display driver renders no viewport image, and no GPU/Xvfb run was
allowed. The foyer/library PNG capture is therefore *not verified* — do not
treat this report as pixel evidence. The commands for a GPU run are:

```bash
make review-capture MAP=guildhall
# or one frame:
tools/godot --path game --resolution 1280x720 res://scenes/review_mode.tscn -- \
  --map=guildhall --review-env=auto --capture=/tmp/foyer.png --capture-quit
```

Every capture writes a `<png>.review.json` sidecar with
`review_only: true`, map, env mode, preset, hidden counts and timestamp, and the
log line carries `review_only=1`. Review captures must never be used as
shipped-lighting references.

## 4. Core-min single-call bake

`tools/bake_review_map.gd --mode=single --sublevels=core` (and the dock button /
`make bake-review-core`) runs ONE `load_sublevels_async()` call over:

- Guildhall: `Building_Guildhall_POI`, `Building_Guildhall_POI_3rdFloor`,
  `Guildhall_Gameplay`, `Guildhall_LightingNoGameplay` (no PeripheryA/SkyboxGeo);
- other maps: resolved sublevels minus Periphery/SkyboxGeo/Clouds/Audio.

One 160-light budget, loader cross-sublevel dedupe, provenance tagging from
`source_sublevel`. Outputs `<map>_core.scn` + `review_core.tscn` (instances the
core scene, adds the review environment, bookmarks, camera) + manifest.
Core scene size guard: **256 MB** (assembly guard stays 150 MB).

### Measured Guildhall core bake (headless)

```
REVIEW_BAKE Load core single-call sublevels=4 budget=160
REVIEW_BAKE   built guildhall_core.scn in 3438 ms (125746197 bytes)
REVIEW_BAKE summary map=guildhall mode=single status=ok sublevels=4 scenes=2
  bytes=125756815 beams=312 labels=0 emissive=266 hidden_nodes=92 hidden_records=488 bake_ms=5507
Elapsed 6.36 s, Maximum resident set size 1,025,712 KB (~1.03 GB)
```

- Core scene: **125,746,197 bytes = 119.92 MB** (under the old 150 MB line, so
  no guard exception was needed; 256 MB leaves headroom and fails closed above).
- Loader counts: 160 lights, 14,917 mesh instances, 2,243 chunks, 547 occluders,
  12,267 collision shapes, 22 Niagara systems.
- Manifest: 4 provenance stems, aggregate checks all `ok` (`expected == actual`
  for lights/occluders/decals/Niagara/collision).
- Tagged core scene reload: 15,583 nodes, 2,069 nodes with concrete
  `review_sublevel`, 160 budgeted lights, **0 authored-hidden nodes visible**.
- Manifest hidden: 92 nodes / 488 draw records. These are loader-built hidden
  batches (174 nodes carry `source_sublevel=mixed` because one hidden mesh batch
  spans files); the authored accounting above stays the source of truth for the
  710 flags.

Per-sublevel aggregate in the Guildhall core manifest:

| review_sublevel | draws | hidden nodes | hidden records | lights |
|---|---:|---:|---:|---:|
| Building_Guildhall_POI | 8733 | 29 | 76 | 0 |
| Building_Guildhall_POI_3rdFloor | 2684 | 4 | 7 | 0 |
| Guildhall_Gameplay | 1289 | 6 | 6 | 0 |
| Guildhall_LightingNoGameplay | 140 | 33 | 52 | 0 |

Lights show 0 per sublevel because `LevelLoader` does not write a
`source_sublevel` meta on light nodes (only draw/collision nodes). The aggregate
light check (160 == 160) covers the budget; adding per-light provenance would
require editing `level_loader.gd`, which is out of scope.

Den fast single-call case: 2 sublevels (Periphery dropped), 160-light budget,
22.69 MB core scene, 258 nodes on reload, 136 provenance-tagged, 7 lights,
0 hidden-visible, 2.88 s bake / 5.86 s test wall, max RSS 695,700 KB.

## 5. Gates run (this worktree)

| Gate | Result |
|---|---|
| `tools/check_scripts_compile.gd` | `scripts checked: 85, broken: 0` |
| `game/tests/test_review_visibility.gd` | `REVIEW_VISIBILITY_SUMMARY: fails=0` (all §1/§2/§3/§5) |
| `game/tests/test_review_core_bake.gd` (Den) | `REVIEW_CORE_SUMMARY: map=thieves_den fails=0` |
| `game/tests/test_review_core_bake.gd` (Guildhall) | `REVIEW_CORE_SUMMARY: map=guildhall fails=0` |
| Guildhall core headless load | `nodes=15583`, 160 lights, 0 hidden-visible |
| `game/tests/test_review_baker.gd` | `REVIEW_TEST SUMMARY: fails=0` (assembly path unchanged) |
| `make test` | `SUMMARY: fails=0` (all existing suites) |

`make audit` was run and is **not green in this worktree**: the gameplay/clues
producer outputs differ from the tracked baseline, `vgmstream` is missing, and
the Makefile infrastructure hash changed because of the new
`bake-review-core` target. The producer drift is pre-existing (no producer was
touched by W0T); a stamp refresh belongs to the wave that regenerates that data,
not to this review fix.

## 6. What remains

- **Editor open on the 8 GB laptop is not verified.** The 371 MB / 562-light
  full-assembly Guildhall master still exists as the assembly output and is not
  the low-memory path. The 119.92 MB core scene loads headless at ~1.03 GB peak
  RSS, but opening it in the editor (and any GPU run) was outside this worker's
  headless-only constraint.
- **Pixel captures** of foyer/library are not run; see §3 for the assertions
  that stand in and the exact GPU commands. Re-run them on a real GPU before
  quoting a non-black claim.
- Per-light sublevel provenance needs a loader change (out of scope).
- Mixed hidden batches are counted but not attributed to one sublevel by design;
  authored 710 accounting is the authoritative count.
- `Hidden in game` reveal is covered by the tests and by review key `H`; a
  manual editor-dock click was not automated.
