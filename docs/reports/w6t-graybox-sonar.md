# W6T — graybox P0/3rd-floor overrides and Sonar CI configuration

Worktree: `/tmp/opencode/tat2-w6t-tooling` (detached from `f803c3b`; private
copy of `game/data/generated`, no Godot run). Scope: producer + expansion data
+ checker + static test + CI/config/report. No game runtime code, no
`parse_unlocks.py`, no shared docs, no Sonar scan.

## 1. Graybox P0 + 3rd floor: one tracked table

`game/data/expansion/content_overrides.json` is now the only place a graybox
kit mesh is re-materialised. `tools/parse_tables.py:apply_content_overrides()`
runs inside `extract_levels()` **after** the LevelInstance merge and **before**
each `.tatlevel.json` is written, so:

* no loader or map special case is added;
* the result is deterministic and idempotent (the producer rebuilds every
  level payload from the extract on each run);
* every rule is fail-closed on counts, overlap, mesh kind and material.

Two ops are supported: `set_material` (used by all 11 rules) and `add_cap`
(implemented and checked, **no rule enabled** — see §6).

### Rules applied (measured on the private extract)

| rule | level | matched | re-materialised | material |
|---|---|---:|---:|---|
| missionlobby-roof-decks-slate-geo3 | MissionLobby_Geo3 | 3 | 3 | MI_RoofSlateA |
| missionlobby-roof-decks-slate-periph | MissionLobby_Periphery | 8 | 8 | MI_RoofSlateA |
| missionlobby-structure-decks-concrete-geo3 | MissionLobby_Geo3 | 11 | 10 | MI_ConcreteB |
| missionlobby-structure-decks-concrete-periph | MissionLobby_Periphery | 44 | 32 | MI_ConcreteB |
| poi-lounge-floor-tile | Guildhall POI (Lounge bbox) | 130 | 5 | MI_FloorTileA_AlignXYZ |
| poi-lounge-floorstone | Guildhall POI (Lounge bbox) | 4 | 4 | MI_ConcreteB |
| poi-entrance-hall-floor-tile | Guildhall POI (Entrance Hall bbox) | 26 | 1 | MI_FloorTileA_AlignXYZ |
| vault-chambers-floorstone | Vault Ceremonial Chambers | 36 | 33 | MI_ConcreteB |
| poi-3rd-floor-tile | POI 3rdFloor | **229** | 20 | MI_FloorTileA_AlignXYZ |
| poi-3rd-floorstone | POI 3rdFloor | 16 | 16 | MI_ConcreteB |
| poi-3rd-roof-deck-slate | POI 3rdFloor | 1 | 1 | MI_RoofSlateA |

Totals: **508 matched / 133 re-materialised**. `matched` is the raw selector
count (`expect_count`); `re-materialised` is `expect_changed`. Rules are
`only_unmaterialed`, so the 209 already-authored wood floors on the 3rd floor
and the 125 already-authored Lounge/Entrance floors keep their shipped
materials; only the graybox instances are rewritten. That is why
`poi-3rd-floor-tile` matches 229 but changes 20, and why the P0 coverage check
below is “no *un-materialed* GB_Floor_2x2 left”, not “delete the authored
floors”.

Region boxes come from the authored clue anchors in
`game/data/generated/gameplay/clues.json` (Guildhall Lounge x 20–49, y 27–29,
z −43…−7; Entrance Hall x 2–18, y 29, z −29…−23), padded and made disjoint at
x = 19.5/20.

### Producer output

```
Normalized 107 level JSONs -> 134768 mesh instances, 2142 lights (stale_removed=107)
Content overrides: 11 rules applied, 508 matched, 133 re-materialised (game/data/generated/content_overrides_applied.json)
  missionlobby-roof-decks-slate-geo3: matched=3 changed=3 (MissionLobby/MissionLobby_Geo3)
  ...
```

Each `.tatlevel.json` carries a `content_overrides` block with the rule ids and
counts; each rewritten mesh entry is tagged `content_rule`. The loader ignores
both; the checker and the static test use them as provenance.

## 2. Checker (`tools/check_content_overrides.py`)

Full run on the regenerated data:

```
PASS: coverage missionlobby-roof-decks: 0 graybox floors left (11 scanned)
PASS: coverage missionlobby-structure-decks: 0 graybox floors left (55 scanned)
PASS: coverage poi-lounge-floor: 0 graybox floors left (130 scanned)
PASS: coverage poi-entrance-hall-floor: 0 graybox floors left (26 scanned)
PASS: coverage vault-chambers-floor: 0 graybox floors left (4 scanned)
PASS: coverage poi-3rd-floor: 0 graybox floors left (229 scanned)
Content override totals: 11 set_material rules, 508 matched, 133 re-materialised, 0 add_cap rules
CONTENT_OVERRIDES: PASS
```

It fails on: a selector/report count mismatch, a no-op rule
(`expect_changed = 0`), two rules selecting one instance (overlap), a
non-graybox mesh, an unknown material, an un-materialed floor left in a
coverage region, an `add_cap` on the roof-census level, or a missing level.

Non-vacuity was proved with two live negative controls: bumping
`poi-3rd-floor-tile.expect_changed` to 19 made the checker fail on both the
report and the tag count; tampering one floor's `override_material` to
`/Game/BAD` made it fail on the material. `parse_tables.py` was then re-run and
the checker returned PASS (idempotent).

`--table-only` validates the tracked table without private data; it is what the
hosted CI job runs.

## 3. W5B roof-collision census preserved

The census (733 roof shapes → 399 `BoxShape3D` + 334 convex in 13 meshes; 0 roof
occluders) is a **collision/occluder** result. This wave changes only the
`override_material` / `override_materials` JSON fields: no `mesh`, `pos`,
`basis` or `scale` field is touched, no mesh is added to
`Guildhall_PeripheryA` or `Guildhall/SkyboxGeo`, and no `add_cap` rule is
enabled. The producer also refuses an `add_cap` whose level is listed in
`roof_census_levels` (`Guildhall/Guildhall_PeripheryA`). `test_roof_collision.gd`
therefore sees the same 733/46/334/399/0 census; not re-run here (no Godot).

## 4. Static GDScript test

`game/tests/test_content_overrides.gd` (standalone, `extends SceneTree`) pins the
table contract in the engine suite: schema/ids, graybox-only meshes, material
existence in `materials.json`, positive counts and no no-op, `add_cap` roof
guard, coverage-region shape, and — when generated levels exist — that the
applied report counts and every `content_rule` instance match the table.

Run: `tools/godot --headless --path game --script res://tests/test_content_overrides.gd`

**Status: not executed** (this worktree was instructed not to run Godot). It is
not registered in `run_tests.gd`; that file is game test code owned by the
integration wave. The Python checker covers the same invariants today.

## 5. Sonar “Path A”

`.github/workflows/sonar.yml` adds two jobs:

1. **SonarCloud scan** — `actions/checkout@v4` (`fetch-depth: 0`), then
   `SonarSource/sonarqube-scan-action@v5` with `SONAR_TOKEN` and
   `SONAR_HOST_URL=https://sonarcloud.io`. If the secret is absent (fork PR) the
   scan is skipped with a notice instead of failing.
2. **GDScript ratchet (non-Sonar)** — `py_compile` of all `tools/*.py`,
   `check_content_overrides.py --table-only`, and `check_gate_ratchet.py`.
   The Godot gates need the private extract and stay local.

`.sonar-project.properties` now scopes the scan explicitly: `tools,game`
sources; excludes `docs/**` (incl. `docs/reference`), `extracted/**`,
`game/assets/**`, `game/.godot/**`, `build/**`, `game/data/generated/**`,
`game/i18n/generated/**`, review scenes, Python/ue4ss build output, Godot
sidecars and binary asset types; `sonar.python.version=3.11`;
`sonar.qualitygate.wait=true`. Coverage is excluded until a report exists.

`tools/gate_ratchet.json` records the measured floors from the W5 integration
(`94a75e3`), sourced from the AGENTS gate table — **not re-measured by W6T**:

| gate | value |
|---|---|
| compile | 101/0 |
| run_tests | 261 passes / 0 fails |
| M2 | 11 / 0 |
| E2E | 264/264 |
| audit coverage | 12657/12703, 0 unexpected |
| texture cap | 773 capped / 1 alpha-critical / 0 offenders |

`tools/check_gate_ratchet.py` enforces floors (never lower), zero-failure gates,
`e2e passed == total`, and that this report quotes the same numbers.

### Manual SonarCloud steps (not performed; no scan run)

1. SonarCloud → project `Heretek-AI_TAT-2` → Administration → Analysis Method:
   **turn OFF Automatic Analysis** (CI scan and autoscan conflict; autoscan also
   ignores `.sonar-project.properties`).
2. GitHub → repo Settings → Secrets and variables → Actions → new secret
   `SONAR_TOKEN` = a SonarCloud **project analysis token** for this project.
3. SonarCloud → Quality Gates → create/bind **“TAT-2 New Code”** (e.g. no new
   bugs/vulnerabilities, new-code coverage not enforced until a report exists,
   duplication ≤ 3 %). Bind it to the project.
4. Administration → New Code: set the period to **Previous version** (or
   “30 days”) so only new code is judged.
5. Optional: set the CLI organization to `heretek-ai` (the dev machine CLI is on
   `heretek-ai-1`, see `w5f-sonar-p0.md`).

## 6. Gates run in this worktree

| gate | result |
|---|---|
| `python3 -m py_compile tools/*.py` | OK (all Python tools, including the two new/changed files) |
| `python3 tools/parse_tables.py` | exit 0 — 107 levels, 134768 meshes; overrides 11 rules / 508 matched / 133 changed |
| `python3 tools/check_content_overrides.py` | `CONTENT_OVERRIDES: PASS` (6/6 coverage regions, 0 left) |
| `python3 tools/check_content_overrides.py --table-only` | PASS |
| `python3 tools/check_gate_ratchet.py` | `GATE_RATCHET: PASS` |
| `make audit` | **PASS** after `make audit-refresh-stamps` (producer + Makefile + `gen:levels` stamps accepted) |
| Godot gates (compile, run_tests, M2, E2E, static test, roof census) | **not run** (no Godot in this worktree) |

## 7. Decisions and risks

* **`add_cap` is implemented but unused.** No capture in this worktree proves a
  missing roof/ceiling slab; adding geometry without one would be fabricated
  content. The op is fully validated (declared count, duplicate detection,
  graybox-only, roof-census guard) so a future wave can enable a measured cap.
* **Material choice is authored but not capture-verified.** `MI_RoofSlateA` for
  roof decks, `MI_ConcreteB` for structure/floors and
  `MI_FloorTileA_AlignXYZ` for interior floors are all real entries in
  `materials.json`; the tile choice is a judgement call that should be confirmed
  in the next visual QA pass.
* **No Godot run.** Compile, `run_tests`, M2, E2E, `test_roof_collision` and the
  new static test are unverified in this worktree. Python-only gates were run.
* **Audit baseline.** `tools/audit_baseline.json` was refreshed here because
  the producer and Makefile changed and the level bytes moved. Any integration
  wave that also changes a producer/output must re-run
  `make audit-refresh-stamps` on the merged tree before `make audit`.
* **Coverage wording.** “0 remaining GB_Floor_2x2” means zero left without an
  authored override; the shipped authored floors are preserved by design.
* **Sonar still cannot see GDScript.** The Sonar job is a tooling gate, not a
  game-quality gate; the ratchet is the GDScript gate.

