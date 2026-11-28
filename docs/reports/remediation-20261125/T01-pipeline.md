# T01 — PIPELINE remediation report

Team: **T01-PIPELINE** (extraction → producers → generated data → audit gate).
Worktree: `<worktree>/T01-pipeline`, branch `rem/T01-pipeline`,
base `38e7b03`. Date: 2026-11-25.
Inputs: `REMEDIATION_PLAN.md`, `AUDIT_BRIEF.md`, `findings/RE-A-pipeline.md`.

Scope discipline: every file touched is in the T01 ownership list —
`tools/parse_*.py`, `tools/manifest_audit.py`, `tools/check_logic_data.py`,
`tools/audit_baseline.json`, `tools/gate_ratchet.json`, `tools/tat-extract/**`,
plus additive `tools/` files. Two additive gate files were required by the
brief's own wording (`check_consumers.py`, `consumer_allowlist.json`) and two
test files per new producer. Three further files needed a one-line or
data-only change and are flagged in **§ Ownership deviations**: `Makefile`
(wiring, mandated by the brief), `tools/audit_allowlists.json` (coverage data),
`tools/test_manifest_audit.py` (its own suite, red on `main`).

**`game/data/generated/` was never written.** Every producer was validated with
`--out-dir /tmp/opencode/rem-T01/…`; the real regeneration is the integrator's
step (§ Integrator steps).

---

## Ownership deviations (three files, stated for the integrator)

1. **`Makefile`** — the brief requires the new producers to be wired
   (`NORMALIZERS`), `check_logic_data.py` to get a target, and `--refresh-stamps`
   to require a reason; all three are Makefile edits. Nothing else in the
   Makefile changed and no existing target's behaviour was altered except
   `audit` (two new dependencies) and `audit-refresh-stamps` (mandatory
   `REASON=`).
2. **`tools/audit_allowlists.json`** — the coverage fix cannot be honest without
   it: the three false-negative `SK_Tarp*` entries had to go and the 43 real
   gaps had to be labelled by kind (`disk_missing_kinds`). No other team touches
   this file; the change is data-only and every entry is evidence-backed.
3. **`tools/test_manifest_audit.py`** — not on the T01 list, but it is the unit
   suite for the file T01 owns, it was **red on `main`**, and the new negative
   controls (content stub, rename, allowlist staleness, refresh reason,
   provenance) belong with the code they cover. Without the repair the brief's
   own test command could not go green.

`tools/audit_baseline.json` and `tools/gate_ratchet.json` are **deliberately
untouched** — see § Baseline state and integrator step 5.

---

## Finding register (the seven P0/P1/P2 items in the brief)

| # | Finding | RE-A id(s) | Sev | Verdict |
|---|---|---|---|---|
| P1 | `DefaultGame.ini` has no producer (progression / project / scoring) | RE-A-01 (DataAssets), RE-A-11 | P0 | **FIXED** (consumer `BLOCKED-ON T10`) |
| P2 | Enhanced Input never ingested (5 IMC / 65 IA / 2 curves) | RE-A-04 | P1 | **FIXED** (consumer `BLOCKED-ON T06`) |
| P3 | `AggGeom` collision dumped and unread (1 992 packages) | RE-A-07 adjacent | P1 | **FIXED** (consumer `BLOCKED-ON T09`, data for T11) |
| P4 | 81/144 tables unread and the gate cannot see it | RE-A-03, RE-A-09, RE-A-12 | P1 | **FIXED** (new fail-closed consumer audit) |
| P5 | Gate weaknesses: stem-presence coverage, unpinned `.usmap`/binary, `--refresh-stamps` accepts drift | RE-A-08, RE-A-09, RE-A-10 | P1 | **FIXED** |
| P6 | Five empty `game_data.gd` load roots + false "31 CurveTables" comment | RE-A-01, RE-A-13 | P2 | **FIXED (data side)**; comment/roots `BLOCKED-ON C1/T10` |
| P7 | `check_logic_data.py` wired to no target | RE-A-02 | P2 | **FIXED** |

---

## Team summary

| Verdict | Count | Items |
|---|---|---|
| FIXED | 7 | P1 ini producer, P2 Enhanced Input, P3 AggGeom, P4 consumer audit, P5 gate weaknesses, P6 curve data, P7 `check_logic_data` wiring |
| FIXED, consumer `BLOCKED-ON` another team | 3 of the 7 | P1→T10, P2→T06, P3→T09 (+T11 for hulls) |
| BLOCKED-ON (named owner, no code written here) | 9 owners | T03 (7 tables), T05 (13 UI/video), T06 (glyph/sensitivity), T08 (`C_EyeGlow`), T09 (`mesh_collision` reader), T10 (`project_settings` reader; `game_data.gd` comment/roots), T11 (`guard_behavior`, nav hulls), T07 (weather tag resolver), T12 (geometry collections) |
| NOT REPRODUCED | 1 | RE-A-13's "authored ≈0.5 at 2.5 m" — the curated interp-mode reading disproves it (P6) |
| DEFERRED (written reason) | 3 | 225 `WidgetTree` extraction (no consumer, would add dead weight — the defect P4 fixes); `Destructibles/` extractor root (needs a full re-extract, T12/T09); `videos.json` player (T05's UI work) |

New tracked files: 4 producers, 4 producer tests, `check_consumers.py`,
`consumer_allowlist.json`, its test. Modified: `manifest_audit.py`,
`audit_allowlists.json`, `test_manifest_audit.py`, `Makefile`.
`git diff --stat 38e7b03..HEAD`: 15 files, 7 079 insertions, 39 deletions.

Measured gate evidence in this worktree: compile 120/0 · `make test`
`SUMMARY: fails=0` · `make test-producers` 24+18+25+35+10+30 checks all PASS ·
`make gate-ratchet` PASS · `check_logic_data` 8 335 checks / 0 failures ·
`manifest_audit` green except the deliberate baseline entries (§ Baseline
state) · post-regeneration rehearsal fully green (§ Rehearsal).

---

## P1 — `DefaultGame.ini` has no producer

- **severity**: P0 (T10-GAMEPLAY cannot start loot/XP/endgame work without it)
- **S1 investigate**: `extracted/raw/TAT/Config/DefaultGame.ini` is 898 CRLF
  lines and is read by **nothing**: `git grep -n DefaultGame HEAD -- tools game/src`
  → exit 1 (no hit). The sections that matter are
  `[/Script/TAT.TATProjectSettings]` (line 166, incl.
  `EndgameDurationsByDifficulty[0..2]` at 334-336, `PostFtueContracts` 174,
  `FtueMinThievesDenMoney` 175, `+Maps=` 177-178),
  `[/Script/TAT.TATProgressionSettings]` (714: `MaximumLevel=25`,
  `LevelUpXP=500`, the per-action XP weights),
  `[/Script/TAT.TATScoringSettings]` (798).
- **S2 research**: the ini *is* the authored truth — these are the shipped
  cooked config keys (`README`/`AGENTS` never mention them; `parse_settings.py`
  only reads `DT_Missions_*`). Values verified by direct read:
  `MaximumLevel 25`, `LevelUpXP 500`, `XPPerMinute 0.6`,
  `WinXP 80 / MissionXP 20 / ContractsXP 20 / OpenQueueXP 5`,
  `MajorLootXP 6 / MinorLootXP 2`, difficulty multipliers `Easy 1.0 / Normal
  2.0 / Hard 3.0`, `CoopXPMultiplier 1.5`,
  `FtueMinThievesDenMoney 5000`,
  `EndgameDurationsByDifficulty = [1200, 600, 300]`,
  `PostFtueContracts = ((Contract.Main.1, Complete), (Contract.Main.2, Objective))`,
  maps Guildhall → `VaultHeist, Set, LootTheRoom` (authored order) and OldManor →
  `Set, Vault, LootTheRoom`, scoring `MissionCompleteBonus 300`,
  `ContractCompleteBonus 100`, both loot-value multipliers `0.1`.
- **S3 confirm (red)**:
  ```
  $ ls game/data/generated/project_settings.json
  ls: cannot access ...: No such file or directory
  $ git grep -n "DefaultGame" HEAD -- tools game/src   → exit 1
  ```
- **S4 fix**: new `tools/parse_project_ini.py` (1 002 lines). A real UE ini
  parser (nested structs, `((a=1),(a=2))`, `+`/`-` array ops, `Key[i]`,
  quoted strings, enums, `LOCTABLE`/`INVTEXT`/`NSLOCTEXT` kept verbatim) emits
  `project_settings.json` (`tat2.project_settings/1`) with `progression`,
  `project`, `scoring`, `general` and **`raw`** (every authored key of every
  covered section, exact source string). `unmapped_keys` must be empty and the
  producer fails if any covered key is missing from `raw`, so a section key can
  never be silently dropped. The authored index order of
  `EndgameDurationsByDifficulty` is emitted as an index map with
  `difficulty_index_source = "unproven: index order only"` — **no** `[0]==Easy`
  claim is invented (no `ETATDifficulty` enum exists in the dumps).
- **S5 test**: `python3 tools/test_parse_project_ini.py` → `PASS: 30 checks`
  (schema, `maximum_level == 25`, three difficulty multipliers,
  `ftue_min_thieves_den_money == 5000`, two maps with authored mission order,
  `[1200.0, 600.0, 300.0]`, `MissionCompleteBonus == 300.0`,
  `unmapped_keys == []`, parser unit cases for nested structs / `+`-`-` /
  LOCTABLE / indexed props, two-run byte identity). Two independent producer
  runs are sha256-identical (`52de98e4…`).
- **S6 confirm**: `python3 tools/parse_project_ini.py --out-dir <scratch>` →
  exit 0, 2 maps, 8 map-type rows, 158 project `raw` keys; the post-regeneration
  rehearsal (§ Rehearsal) loads it through the real audit with the baseline
  stamp recorded.
- **verdict**: **FIXED**. Runtime consumer is T10's (`project_settings.json` is
  allowlisted `blocked_on_team T10`); the data side is complete.

## P2 — Enhanced Input is never ingested

- **severity**: P1 (unblocks T06-INPUT)
- **S1 investigate**: `extracted/json/Gameplay/Input/**` holds 5
  `InputMappingContext` and 65 `InputAction` dumps. `git grep -c
  InputMappingContext HEAD -- tools` → exit 1. `game_data.gd:109` asks for
  `res://data/generated/tables/Gameplay/Input/Character`, which does not exist.
  The runtime's bindings are 21 hand-authored actions in `game/project.godot`.
- **S2 research**: measured from the dumps —
  `IMC_Character 76`, `IMC_Character_ClimbTest 69`, `IMC_Character_Testing 77`,
  `IMC_MapTool 4`, `IMC_Radial 11` rows; **91 shipping rows / 52 actions / 58
  keys** across the three shipping contexts (Character+Radial+MapTool),
  **237 rows / 54 actions** including the two dev contexts, 65 `InputAction`
  assets, 2 response `CurveFloat` assets. Trigger/modifier values are authored:
  `HoldTimeThreshold 0.2` (8 rows), `LowerThreshold 0.18 / UpperThreshold 0.98`
  (plus `0.12/0.98` and `0.5/0.95` variants), 12 chord rows.
- **S3 confirm (red)**: `ls game/data/generated/gameplay/input_actions.json` →
  missing.
- **S4 fix**: new `tools/parse_input.py` → `gameplay/input_actions.json`
  (`tat2.input_actions/1`): every context with every authored mapping row in
  source order, each resolved trigger/modifier (class, authored values, path,
  and the full authored `properties` dict), action metadata
  (`PlayerMappableKeySettings`, LOCTABLE key + table + source string), the 65
  actions with their contexts/keys, and the two gamepad curves with per-key
  `InterpMode`/tangents. Resolution is **per package, not per file** (a dev
  context references `IMC_Character`'s export list). `unresolved` must be `[]`
  and an unknown trigger or modifier class fails the producer instead of being
  dropped.
- **S5 test**: `python3 tools/test_parse_input.py` → `PASS: 10 checks`
  (91/52/58/237/54/65/2 counts, shipping flags, `IA_Ability_Action_Primary`
  bound to `LeftMouseButton` + `Gamepad_RightTrigger`, `Hold 0.2`,
  `DeadZone 0.18/0.98`, a real chord action, `unresolved == []`, unknown class
  fails closed, byte identity).
- **S6 confirm**: producer exit 0, 270 658 bytes, two runs sha256-identical
  (`ebd5e2b2…`).
- **verdict**: **FIXED**. Consumer `BLOCKED-ON T06`.
- **Carried defect for T06** (found by the producer, not fixed — authored data):
  all five shipped `ActionPrimary` mappable-settings objects store
  `DisplayName`/`DisplayCategory` **transposed** (`DisplayName.Key =
  InputSetting.Category.Interaction`). The producer emits authored fields
  verbatim and adds `display_name_key`/`display_category_key`, so T06 must
  resolve the label by key prefix rather than trust the field name for those
  actions.

## P3 — `AggGeom` collision is dumped and unread

- **severity**: P1 (T09 collision creation, T11 nav bounds)
- **S1 investigate**: `git grep -c AggGeom HEAD -- tools game/src` → exit 1.
- **S2 research**: 1 992 packages carry `Properties.AggGeom`;
  measured elements across all four lists: **Box 2 334, Sphere 50, Sphyl 295,
  Convex 5 922** = **8 601** total, plus **8 382** BodySetup-only (the brief's
  number) and **219** `SkeletalBodySetup` elements (2 935 + 219 setups). The
  `/Engine/BasicShapes/*` carriers and the Guildhall set are included.
  `FKBoxElem.X/Y/Z` are **half-extents**; `FKSphylElem` is Radius+Length;
  `FKConvexElem.VertexData` is a point cloud **and** `IndexData` is authored on
  5 919/5 922 hulls (my brief said no triangulation is dumped — that was
  wrong; the producer preserves it behind a flag).
- **S3 confirm (red)**: `ls game/data/generated/mesh_collision.json` → missing.
- **S4 fix**: new `tools/parse_collision.py` → `mesh_collision.json`
  (`tat2.mesh_collision/1`), keyed by the owner package, with
  `counts` (meshes, elements, per-type, body-setup vs skeletal split, empty
  setups, multi-body packages, complex-as-simple packages, nav-collision
  packages) and per-mesh `body_setups[]` slices carrying `owner_path`,
  `owner_type`, `collision_trace_flag`, profile/object-type/response list.
  Vertices are emitted **flat** (`vertices_flat`, 3 × `vertex_count`, maps 1:1 to
  Godot `PackedVector3Array`); triangle `index_data` is opt-in
  (`--with-index-data`) because `ConvexPolygonShape3D` consumes point clouds and
  the index list dominates the file size.
- **S5 test**: `python3 tools/test_parse_collision.py` → `PASS: 25 checks` (counts,
  `SM_CanA` half-extent `[15.940169, 15.669875, 25.463127]`, a 32-vertex/180-index
  hull, a capsule with positive radius+length, all four element types in a
  fixture, `vertices_flat` length == 3 × `vertex_count`, closed vocabulary on an
  unknown element list, byte identity in both index modes).
- **S6 confirm**: producer exit 0; sizes and counts in § Rehearsal.
- **verdict**: **FIXED**. Consumers `BLOCKED-ON T09` (loader collision) and for
  the hull data `T11` (nav bounds).

## P4 — 81/144 normalised tables have no consumer and the gate cannot see it

- **severity**: P1
- **S1 investigate**: `make audit` proves output hashes and file counts; it
  never reads GDScript (`rg -c "game/src|\.gd" tools/manifest_audit.py` → 0).
  Reproduced with a purpose-built enumerator: of 194 generated files, **97 were
  unreachable** from `game/src` — **88 table files** (of 144) and **9
  analysis/manifest JSONs** — while the gate printed
  `content tables: OK files=144`.
- **S2 research**: the reachability model is the runtime's own:
  `game_data.gd` loads 13 `_load_tables_from_dir` roots (4 literal + 9 in a
  `for dir_path in [...]` list). The audit parses those roots out of the
  GDScript, so a new root widens the audit automatically and an unparseable
  root argument fails closed.
- **S3 confirm (red)**: `python3 tools/check_consumers.py` (before the
  allowlist existed) → `CONSUMER AUDIT FAILED: 74 failure(s)`, listing
  `tables/Gameplay/Clues/**`, `tables/StringTables/**`, `tables/UI/**`,
  `gameplay/guard_behavior.json`, `videos.json`, … plus
  `EMPTY table roots: 5`.
- **S4 fix**: new `tools/check_consumers.py` + `tools/consumer_allowlist.json`,
  wired into `make audit` as `check-consumers`. Each unreachable file needs a
  rule `{glob, kind, reason[, consumer, claim_token][, owner][, optional]}`.
  Eight kinds, including `text_via_locres`, `folded_into_aggregate`,
  `producer_intermediate`, `tests_only`, `placeholder`, `provenance` and
  `blocked_on_team` (which **must** name an owner — that is how the gate records
  who owes a reader). The checker fails on: an unreachable file with no rule; a
  rule that matches nothing (no allowlist rot); an empty reason; an unknown kind;
  `blocked_on_team` without an owner; a rule that names a `consumer` without a
  `claim_token`, or whose `claim_token` is absent from that file (falsifiable
  claims — this caught two of my own rules that wrongly named
  `tools/convert_wwise.py` for the Wwise tables, which no tool reads).
- **S5 test**: `python3 tools/test_check_consumers.py` → `PASS: 24 checks`
  (unconsumed fails, non-recursive root does not cover subdirs, recursive root
  does, literal reader counts, tests-only is classified not passed, complete
  allowlist passes, reason/owner/kind/claim validations, `**` spans directories,
  root parser fail-closed, empty root note-then-failure).
- **S6 confirm**: `python3 tools/check_consumers.py` → `CONSUMER AUDIT PASS`,
  194 files: 97 runtime-read (dir_scan 31, literal 34, table_root 32),
  97 allowlisted with reasons (88 tables + 9 manifests), `blocked on a named owner: T03 7, T05 10, T06 1,
  T10 1, T11 1`, and `EMPTY table roots: 5` printed as the P6 defect.
- **verdict**: **FIXED**. The 97 allowlisted files are now a tracked, reasoned
  list, and the owners are explicit: T03 (7 Wwise/voice tables), T05 (10
  UI/indicator/prompt/video), T06 (1 glyph table), T10 (1 match settings),
  T11 (1 StateTree payload) — see § BLOCKED-ON.

## P5 — Gate weaknesses

- **severity**: P1
- **S1 investigate**: three independent weaknesses.
  1. `_build_disk_index()` indexed `_stem()` only, so *any* file with a matching
     name counted as coverage: a 4-byte placeholder dump counted, and an export
     renamed by UE was reported missing. Measured:
     `Disk-backed coverage: 12657/12703 (99.6%)` with three false negatives
     (`SK_TarpA/B/C` are present as `SKM_Tarp*.glb`).
  2. `rg -n "usmap|ue4ss" tools/manifest_audit.py tools/audit_baseline.json Makefile`
     → 0 hits; the 2 600 600-byte mapping file that names **every** unversioned
     property in all 12 541 dumps was unpinned, and the built
     `bin/Release/net10.0/tat-extract` was not checked at all.
  3. `--refresh-stamps` accepted a changed producer whenever every output was
     newer than the script — which a regenerated output always is — and wrote
     the new baseline with no record of why.
  **Additional finding (not in the lane file)**: the audit's own negative-control
  suite was **red on `main`** — `python3 tools/test_manifest_audit.py` →
  `AssertionError: expected exit 0, got 1` because `_build_fixture()` was never
  extended when six producers were added (`loot_settings`, `unlocks`, `hearing`,
  `perception`, `guard_behavior`, `anims_meta` outputs missing). The brief's
  stated baseline ("`test_manifest_audit.py`") was therefore wrong.
- **S2 research**: UE exports skeletal meshes as `SKM_<name>` (the three
  `SK_Tarp*` paths are in `extracted/assets/TAT/Content/ClothSimulation/` as
  `SKM_TarpA/B/C.glb`); `Program.cs:30` + `FindUsmap()` (`:119-124`)
  auto-discover any `*.usmap`; `make extract` rebuilds the binary from
  `Exporter.cs`/`Program.cs`.
- **S3 confirm (red)**: the four commands in `/tmp/opencode/rem-T01/red/` —
  coverage 12657/12703 with 3 allowlisted false negatives; 0 usmap hits;
  `--refresh-stamps` without any reason succeeds; `test_manifest_audit.py`
  red on `main` (captured in `red/test_manifest_main.log`).
- **S4 fix** (all in `tools/manifest_audit.py` unless stated):
  * **content coverage**: the disk index is `{stem: {suffix: content|stub}}`;
    a JSON dump counts only when it carries an exported `"Type"` (all 12 541
    real dumps do; a 4-byte stub does not). Renamed exports resolve through a
    second `alias` index that only holds names absent from the direct index, and
    the count of rename-resolved paths is printed, so a rename can never mask a
    real loss. New hard failures: `content-free stub`, `stale disk_missing
    allowlist entry`, `unlabelled disk_missing path`, `spare disk_missing_kinds
    label`.
  * **`tools/audit_allowlists.json`**: the three `SK_Tarp*` paths are removed
    (they resolve) and all 43 remaining `disk_missing` paths are labelled by
    kind in `disk_missing_kinds`, printed every run
    (`movie_wrapper 18, graybox_template 13, geometry_collection 4,
    gameplay_asset 2, shader_cache 2, editor_copy 2, cloth_simulation 1,
    perf_harness 1`). The note now says what each kind is; the old wording
    ("movies/shader archives/editor-only content") hid 13 graybox templates, 4
    geometry collections and 4 gameplay assets.
  * **`.usmap` pin**: hashed into the baseline under `provenance.usmap`
    (presence-conditional; a *changed* hash always fails, absence is a loud note
    and `--require-usmap` turns it into a failure, `--usmap PATH` pins an
    explicit file so a worktree can point at the main checkout). Ambiguity (two
    `.usmap` files) fails.
  * **extractor binary**: recorded (size/sha/mtimes) and checked by
    `_extractor_freshness()` — the binary must be newer than its `.cs`/`.csproj`
    sources; a stale `bin/Release` now fails.
  * **`--refresh-stamps` requires `--refresh-reason TEXT`** (exit without it)
    and appends `{utc, reason, notes}` to `refresh_log` in the baseline (last 20),
    printing `baseline: refresh reason recorded: …`. `make audit-refresh-stamps`
    now requires `REASON=…`.
  * **`tools/test_manifest_audit.py` repaired and extended**: the fixture now
    derives every producer output from `manifest_audit.PRODUCERS`
    (`_satisfy_producer_outputs`), so a new producer can never silently break
    the suite again, and six control groups were added (content stub, rename,
    allowlist staleness + kinds, refresh reason required and recorded, provenance
    pinning incl. `_extractor_freshness`, plus import-based pure-function tests).
- **S5 test**: `python3 tools/test_manifest_audit.py` → `PASS: 18 control
  groups` (the suite that was *red* on `main`, see S3).
- **S6 confirm**: `python3 tools/manifest_audit.py --min-coverage 0.99
  --min-exact-coverage 0.99` now prints
  `Disk-backed content coverage: 12660/12703 (99.7%), resolved by
  exported-name rename 3, allowlisted missing 43, unexpected 0` and
  `allowlisted missing by kind: …`. In the worktree the only remaining failures
  are the deliberate new-producer baseline entries (see § Baseline state).
- **verdict**: **FIXED**.

## P6 — five empty `game_data.gd` load roots and the "31 CurveTables" comment

- **severity**: P2
- **S1 investigate**: `game_data.gd:92-112` loads 13 roots; five do not exist:
  `tables/Gameplay/Input/Character`, `tables/Gameplay/Traversal/Dodge`,
  `tables/AI/Alertness`, `tables/Gameplay/Carry`,
  `tables/Art/Environment/Weather`. The comment claims the roots "load all 31
  authored CurveTables".
- **S2 research**: measured — 23 `CurveTable` **assets** exist (18 `CT_*` + 5
  `Curve_*_Table`) and *all 23 are already normalised and loaded*; there are
  **16 standalone curve assets** (14 `CurveFloat` + 2 `CurveLinearColor`) and
  **108 curve objects nested inside Blueprint packages** (99 `CurveFloat`,
  6 `CurveVector`, 3 `CurveLinearColor`). The five empty roots are exactly where
  eight of the 16 standalone assets live, so "31" was never a count of anything:
  the roots were added for curve assets that no producer emitted.
  **RE-A-01 correction**: "87 shipped curve assets" is wrong — `rg -l
  '"Type": "CurveFloat"'` counts *packages containing* a curve export, and 99 of
  those 113 exports are Blueprint sub-objects. The true split is 16 standalone
  assets, 108 nested curve objects, 23 CurveTables.
- **S3 confirm (red)**: `ls` of the five roots → `No such file or directory`
  (all five); `find game/data/generated/tables -name 'CT_*' | wc -l` → 18,
  `… -name 'Curve_*_Table'` → 5, so 23 CurveTables — not 31.
- **S4 fix**: new `tools/parse_curves.py` → one `<out>/tables/<pkg-dir>/<Name>.json`
  per standalone asset (rows keyed `Value` / `R,G,B,A` / `X,Y,Z`, per-key
  `InterpMode`/`TangentMode`/tangents preserved) plus `curves.json`, an index
  that also lists the 108 nested curve objects with owner + key count so nothing
  is silently dropped. The emitted schema matches what `game_data.gd` already
  accepts (`{rows: {row: {Keys: [...]}}}`, rows containing `Keys` are stored as
  curves), so **no GDScript change is needed** for the data to load. The
  producer refuses to overwrite a `CurveTable` file (single-writer rule).
- **S5 test**: `python3 tools/test_parse_curves.py` → `PASS: 35 checks`
  (16/108/23 counts, all five former-empty roots now non-empty, the alertness
  curve's authored `(2.0, 1.0, RCIM_Constant) → (3.0, 0.0, RCIM_Linear)` keys,
  both gamepad response curves, sparse-channel handling, CurveTable
  non-overwrite, keyless-curve fails closed, byte identity).
- **S6 confirm**: the rehearsal run fills all five roots
  (`AI/Alertness` 1, `Art/Environment/Weather` 2 + `Skybox/` 1,
  `Gameplay/Carry` 1, `Gameplay/Input/Character` 2, `Gameplay/Traversal/Dodge` 1)
  and `check_consumers.py` then reports no empty roots.
- **verdict**: **FIXED on the data side**. The runtime side is
  **`BLOCKED-ON C1/T10`**: `game_data.gd` still carries the false "31 authored
  CurveTables" comment, and four of the 16 emitted curve files
  (`tables/Gameplay/Indicators/C_GlyphIndicator_MajorLoot.json`,
  `tables/MaterialLibrary/…/C_EyeGlow.json`, `tables/UI/Settings/*.json`) sit
  outside every loaded root, so their readers are T05/T06/T08 deliverables. The
  consumer allowlist records those three owners explicitly.
- **RE-A-13 correction (documented, not "fixed")**: the lane report claims the
  authored alertness curve is "≈0.5 at 2.5 m" and the port's step is "twice as
  sensitive". Under UE semantics the `InterpMode` stored on key *i* governs the
  segment **[key i, key i+1)**, so `(2.0, 1.0, RCIM_Constant)` holds **1.0**
  across 2–3 m and drops to 0.0 at the 3.0 m key — which is exactly what
  `guard_ai.gd:153-156` does. The lane's arithmetic (linear 2→3) applies the
  wrong key's mode. `guard_ai.gd` is T11-owned, so nothing was changed; T11 must
  be told **not** to "fix" it, and that if it does consume the new curve it must
  honour the per-key mode rather than `GameData.eval_curve()` (which always
  lerps and would produce the 0.5 the lane expected — i.e. introduce the bug).

## P7 — `check_logic_data.py` is wired into no target

- **severity**: P2
- **S1 investigate**: `git grep -n check_logic_data HEAD -- Makefile .github
  build/qa` → exit 1. The validator (8 335 checks: unlocks 68, hearing 54/22/11/
  285, perception, 21 StateTrees/467 transitions) was dead code guarding a dead
  payload.
- **S2 research**: the checker's expected values are documented as shipped-build
  counts kept deliberately outside the producers — exactly the independent
  expectation the gate lacks (RE-A-09).
- **S3 confirm (red)**: the grep above → no target.
- **S4 fix**: `Makefile` gains `check-logic` (runs the validator) and `audit`
  depends on it; `check-consumers` added the same way; `test-producers` runs
  every `tools/test_*.py`.
- **S5/S6**: `python3 tools/check_logic_data.py` → `LOGIC_DATA PASS: 8335
  checks, 0 failures`; `make check-logic` → same; `make audit` now fails if the
  payload regresses instead of silently shipping a stale `guard_behavior.json`.
- **verdict**: **FIXED**. (The *consumer* of `guard_behavior.json` remains
  `BLOCKED-ON T11` — see RE-A-02 below.)

---

## Rehearsal: what the gate looks like after the integrator regenerates

Because the shared `game/data/generated` tree is read-only for this team, the
post-regeneration state was proved on a **copy** of it
(`/tmp/opencode/rem-T01/rehearsal/generated`, 64 MB, 328 files, `tar`-copied):

```
python3 tools/parse_curves.py         --out-dir <copy>   # +16 tables, +curves.json
python3 tools/parse_project_ini.py    --out-dir <copy>   # +project_settings.json
python3 tools/parse_input.py          --out-dir <copy>   # +gameplay/input_actions.json
python3 tools/parse_collision.py      --out-dir <copy>   # +mesh_collision.json
```

| Evidence | Result |
|---|---|
| new files written | 20 (16 curve tables + 4 aggregates) |
| former-empty roots | 5/5 non-empty |
| `check_consumers.py --generated <copy> --strict-optional` | **PASS** — 214 files, 109 runtime-read, 105 allowlisted with reasons, 0 empty roots, blocked owners T03 7 / T05 13 / T06 2 / T08 1 / T09 1 / T10 2 / T11 1 |
| `manifest_audit.py --generated <copy> --usmap <main usmap> --bootstrap-stamps` | **AUDIT PASS** — 27 producers, 14 freshness groups fresh, coverage 12 660/12 703 (99.7 %), 3 rename-resolved, 43 allowlisted by kind, usmap pinned (`TAT-5.5.4-148559…usmap`, 2 600 600 B) |
| `manifest_audit.py` second run (no flags) | **AUDIT PASS** — `baseline: matches …/baseline.json` |

Payload sizes: `mesh_collision.json` 17 626 566 B (1 992 meshes / 8 601 elements;
`body_setup_elements 8 382` + 219 skeletal, flat `vertices_flat`); with
`--with-index-data` 23 018 877 B; `project_settings.json` 36 KB;
`curves.json` 80 KB; `gameplay/input_actions.json` 268 KB. The first cut of the
collision file was 25 321 646 B with `indent=2` triangle indices and
`[x,y,z]` vertex lists; the delivered default is 30 % smaller and maps directly
to `PackedVector3Array`.

---

## Baseline state and why `make audit` is red in this worktree

`tools/audit_baseline.json` is a *description of the generated tree*, so it
cannot be truthful before the tree is regenerated. In this worktree
`make audit` therefore fails with exactly:

```
FAIL: producer tools/parse_curves.py: output gen:curves.json is missing
FAIL: baseline: no entry for producer tools/parse_curves.py
FAIL: producer tools/parse_project_ini.py: output gen:project_settings.json is missing
FAIL: baseline: no entry for producer tools/parse_project_ini.py
FAIL: producer tools/parse_input.py: output gen:gameplay/input_actions.json is missing
FAIL: baseline: no entry for producer tools/parse_input.py
FAIL: producer tools/parse_collision.py: output gen:mesh_collision.json is missing
FAIL: baseline: no entry for producer tools/parse_collision.py
FAIL: baseline: infrastructure root:Makefile changed since the baseline
FAIL: baseline: infrastructure root:tools/audit_allowlists.json changed since the baseline
```

(This is the audit working correctly: it refuses to pretend.) The rehearsal
above proves the same gate is green after regeneration. Everything else in the
gate is green in the worktree: compile 120/0, `make test` 278/fails=0, all six
producer suites, `make gate-ratchet`, `check_logic_data` 8 335/0.

`make audit` also needs `--allow-tool-drift` **in this container only**, because
`tools/bin/vgmstream/vgmstream-cli` is absent (`vgmstream: 'r2168' -> 'missing'`).
That is an environment gap, not a tree regression, and it is the same on `main`.

---

## Integrator steps (exact)

Run from the main checkout, one at a time, no parallel Godot.

1. **Cherry-pick** the branch (two commits, listed under § Commits) and
   confirm `git status --short` is clean except the new tracked files.
2. **Regenerate the data** (this is the only step that writes `game/data/generated`):
   ```bash
   make normalize                 # 26 normalisers, incl. the 4 new producers
   ```
   Expected new/changed files: `project_settings.json`, `curves.json`,
   `gameplay/input_actions.json`, `mesh_collision.json`, and 16 files under
   `tables/{AI,Art,Character,Gameplay,MaterialLibrary,UI}/…`.
3. **Refresh the baseline with a reason** (now mandatory):
   ```bash
   make audit-refresh-stamps REASON="T01: four new producers (curves, DefaultGame.ini, Enhanced Input, AggGeom) + content coverage semantics; regenerated with make normalize"
   ```
   The baseline records that reason in `refresh_log`, plus the `provenance.usmap`
   hash (2 600 600 B) and `provenance.extractor_binary`.
4. **Verify green**:
   ```bash
   make audit                                    # content-overrides, texture-cap, check-logic, check-consumers, manifest audit
   python3 tools/check_consumers.py --strict-optional   # drop the `optional` flags afterwards
   make test-producers                           # all tools/test_*.py
   ```
   After that succeeds, **delete `"optional": true`** from the four staged rules
   in `tools/consumer_allowlist.json` (`curves.json`, `project_settings.json`,
   `gameplay/input_actions.json`, `mesh_collision.json`,
   `tables/MaterialLibrary/**`) so a future disappearance fails the gate.
5. **The ratchet**: `make audit` now prints `Disk-backed coverage:
   12660/12703` instead of `12657/12703`. `tools/gate_ratchet.json`'s audit
   evidence regex is exact, so it will fail until the new log is committed:
   save the full `make audit` output as `docs/reports/logs/<wave>/audit.log`
   and update `tools/gate_ratchet.json` (`measured_on`, `audit.coverage_num`
   `12657 → 12660`) in the same commit as the new log. **Do not raise the floor
   without the log** (`check_gate_ratchet.py` requires both to agree).
6. **Then** run the rest of the wave gate set (`test_m2_player`, `probe_leak`,
   the three probes, E2E) — none of them consume the new files yet, so they are
   unaffected.

Docs the integrator should update from § Doc corrections: `AGENTS.md` (producer
count, coverage semantics, refresh reason, consumer audit), `README.md:64`,
`HANDOFF_NEXT_AGENT.md:100,317`, `FIDELITY_GAPS.md:17`.

---

## BLOCKED-ON (runtime consumers this team cannot write)

| Owner | Item | Where it is recorded |
|---|---|---|
| **T10** | `project_settings.json` reader (XP amounts, `MaximumLevel 25`, endgame durations, authored map→mission lists) | `consumer_allowlist.json` |
| **T06** | `gameplay/input_actions.json` reader + rebinding/glyph model; also the transposed `DisplayName`/`DisplayCategory` on `ActionPrimary`; `DT_InputKeysToGlyphs` | `consumer_allowlist.json` |
| **T09** | `mesh_collision.json` reader (simple collision creation in the loader) | `consumer_allowlist.json` |
| **T11** | `mesh_collision.json` hulls for nav bounds; `guard_behavior.json` StateTree consumer (RE-A-02); **do not** "fix" the alertness step (see P6) | allowlist + this report |
| **T03** | 7 Wwise/voice tables extracted and read by nothing (`tables/Audio/Audio_Data/**`, `tables/WwiseAudio/**`) | `consumer_allowlist.json` |
| **T05** | 13 UI-side items: `DT_ThiefVisionIndicators`, `C_GlyphIndicator_MajorLoot`, `DT_InteractPromptStyles`, `tables/UI/**` (incl. the sensitivity curves), `videos.json` (15 clips, 153 MB, no player — RE-A-06) | `consumer_allowlist.json` |
| **T08** | `C_EyeGlow` colour curve for the eye material | `consumer_allowlist.json` |
| **C1/T10** | `game_data.gd`: delete the false "31 authored CurveTables" comment (23 exist; the 13 roots load 45 files after this change) and decide whether the four non-loaded curve files get a root | this report |
| **T07** | RE-A-05: 11 of 16 weather presets are unreachable through `manager_overrides`; the presets are now loaded by directory scan, so the gate cannot catch the missing tag→preset resolver | this report |
| **T12** | RE-A-07: 18 `GeometryCollection` dumps + 4 never dumped (`Destructibles/`) still have no consumer | this report |

## Not reproduced / deliberately not fixed

- **RE-A-04's `WidgetTree` half** (225 widget blueprints): no producer was
  added. The UI is hand-built and T05 owns the rewrite; extracting 225 widget
  trees into a format no consumer can use would add dead weight to the gate (the
  exact defect P4 fixes). Recorded as a finding, not a fix.
- **RE-A-06 videos**: the 15 `.ogv` are converted and `videos.json` exists; the
  player is T05's. Allowlisted `blocked_on_team T05`.
- **RE-A-07 `Destructibles/` is not in the extractor's `tables` root list**
  (`Exporter.cs:146`): adding a root changes the extractor and therefore the
  whole extraction — out of scope for a gate commit, and it needs a full
  re-extract. Recorded for T12/T09.
- **RE-A-13's arithmetic** is disproved (§ P6) rather than fixed.

---

## Doc corrections (for the integrator; not edited here)

1. **Producer count.** After this branch: `ls tools/parse_*.py | wc -l` → **23**;
   Makefile `NORMALIZERS` → **26** entries; `manifest_audit.PRODUCERS` →
   **27** stamped. Before this branch the tree had 19 / 22 / 23.
   `README.md:64` ("all 21 generated-data producers"), `HANDOFF_NEXT_AGENT.md:100`
   ("14 producers") and `:317` ("18 producers") are all wrong; use
   "**23 `parse_*.py` producers, 26 normalisers, 27 stamped**" or, better, drop
   the number and point at `NORMALIZERS`.
2. **`58 DT_ / 79 ST_ … → 144` is not a reconciliation.**
   `FIDELITY_GAPS.md:17` should read: 144 normalised tables = **60 DataTable**
   (57 `DT_*`, 1 `DEPRECATED_*`, 2 unprefixed) + **57 StringTable** (56 `ST_*`,
   1 `St_*`) + **23 CurveTable** (18 `CT_*` + 5 `Curve_*_Table`) +
   **4 CompositeDataTable** (3 `CDT_*` + 1 `DT_`). The `79 ST_` figure is not
   reproducible on this tree (measured 56 `ST_*`, all `StringTable`), and
   RE-A-11's "22 of the 79 `ST_` are StateTree" is impossible — StateTrees are
   `extracted/json/AI/StateTrees/*` and never enter `tables/`.
3. **RE-A-01 "87 shipped curve assets"** → **16 standalone curve assets**,
   **108 curve objects nested in Blueprint packages**, **23 `CurveTable`
   assets**. `rg -l '"Type": "CurveFloat"'` counts packages containing a curve
   export, not assets.
4. **RE-A-13 alertness curve** — see P6: the authored ramp is a step at 3.0 m
   (RCIM_Constant on the 2.0 m key governs [2,3)), so `guard_ai.gd:153-156` is
   faithful and the lane's "≈0.5 at 2.5 m" is wrong. The comment's *conclusion*
   is right; its wording ("the 3.0 m key drops the strength to 0.0") should say
   "the 2.0 m key is `RCIM_Constant`, so the multiplier holds 1.0 until the next
   key at 3.0 m".
5. **Coverage number.** `Disk-backed coverage` is now
   `Disk-backed content coverage: 12660/12703 (99.7%)` with 3 paths resolved by
   the exported-name rename and 43 allowlisted by kind (was 12 657/46). Any doc
   quoting 12 657/12 703 or "46 missing" must be updated, and
   `gate_ratchet.json`'s audit floor follows the new log (§ Integrator step 5).
6. **`tools/manifest_audit.py` header** (layer list) now documents six layers
   including content coverage, `--refresh-reason` and the `.usmap`/binary pin —
   quote the file rather than the old five-layer summary.
7. **`docs/reports/tables-coverage.md:30-31`** (found by the input producer)
   says the two gamepad response curves "load as CurveTables". They are
   `CurveFloat` assets; `parse_tables.py` cannot ingest them and the directory
   the runtime asked for did not exist. That report is stale on both points.
8. **`AGENTS.md` "Commands and gates"** should add `make check-consumers`,
   `make check-logic`, `make test-producers`, and `make audit-refresh-stamps
   REASON=…`; the audit table row "`make audit` exit 0, … 99.6 % (12657/12703)"
   becomes 99.7 % (12 660/12 703).
9. **RE-A-08's allowlist note** ("movies/shader archives/editor-only content")
   understated the 46 paths: after the fix the tracked file labels all 43 by
   kind, and 37 of them are content-bearing or content-adjacent (18 movie
   wrappers, 13 graybox templates, 4 geometry collections, 1 cloth sim,
   2 gameplay assets), 6 are noise (2 editor copies, 2 shader caches, 1 perf
   harness, and the 1 `cloth_simulation` BP is content). Cite
   `disk_missing_kinds` instead of prose.
10. **`55b`-style collision counts**: "8 382 primitives / 5 922 convex" is
    BodySetup-only; the total across `BodySetup` + `SkeletalBodySetup` is
    **8 601** elements (2 334 box + 50 sphere + 295 sphyl + 5 922 convex) in
    1 992 packages. Both numbers are correct at different scope — a doc should
    say which.

## Open risks

1. **`mesh_collision.json` size.** The first cut was 25 MB with `indent=2` and
   per-hull `index_data`. The delivered default drops the triangle indices
   (Godot's `ConvexPolygonShape3D` takes a point cloud) and emits flat vertex
   arrays; the exact size is recorded on the commit. If T09 wants exact authored
   triangles it must run `parse_collision.py --with-index-data` and accept the
   larger file plus a baseline refresh.
2. **`gen:tables` has two writers** (`parse_tables.py`, `parse_curves.py`). They
   never write the same file (the curve producer refuses to overwrite a
   `CurveTable`) but they share one baseline digest, so a change to either
   requires one refresh. Deliberate; documented in `PRODUCERS`.
3. **`--refresh-stamps` is still a one-command re-baseline** — it now records
   *why* and cannot be silent, but it cannot detect a wrong-but-stable value.
   The independent expectations remain `check_logic_data.py` (now wired) and the
   13 content assertions; a field-level golden-value check is still absent.
4. **`.usmap` pin is presence-conditional.** A worktree without
   `tools/ue4ss/output/*.usmap` prints a loud note rather than failing, because
   requiring it would make every fresh worktree's audit red. The main checkout
   has it (2 600 600 B) and the integrator's `make audit` pins it. Use
   `--require-usmap` on the full tree if a hard floor is wanted.
5. **New producers are unproven at runtime.** Nothing in `game/src` reads
   `project_settings.json`, `input_actions.json` or `mesh_collision.json` yet, so
   the four findings are fixed on the data side only; the allowlist records the
   owner and the gate will keep printing them until a reader lands.
6. **`parse_input.py` synthesises one value**: an absent `ValueType` is reported
   as `"Boolean"` with `value_type_authored: false` (57/65 actions) because UE
   omits class-default properties from the dump. Flagged, not measured.
7. **Nothing here was verified in-engine** (no Godot run in this team beyond
   `make test`; no capture). All counts are file-level measurements with the
   command recorded in the report or the producer tests.

---

## Commits

| SHA | Subject |
|---|---|
| `08d526d` | `feat(audit): fail-closed consumer audit for generated data` — `tools/check_consumers.py`, `tools/consumer_allowlist.json`, `tools/test_check_consumers.py`, `Makefile` (`check-logic` + `check-consumers` wired into `make audit`). Green on its own; no baseline impact. |
| `b5bc309` | `feat(pipeline): four staged producers + audit content/provenance semantics` — `parse_curves.py`, `parse_project_ini.py`, `parse_input.py`, `parse_collision.py` + 4 test suites, `manifest_audit.py` (coverage/provenance/refresh reason/PRODUCERS), `audit_allowlists.json`, `test_manifest_audit.py`, `Makefile` (`NORMALIZERS`, `test-producers`, `REASON=`). Requires the integrator's regeneration + one refresh. |

This report is **not committed**: `build/qa/*` is git-ignored by design
(`.gitignore:25`, only `.gd`/`.sh`/`.py` under `build/qa/` are tracked). It lives
at `build/qa/review_20261124/remediation/T01-pipeline.md` in this worktree, as
the delivery format requires.

