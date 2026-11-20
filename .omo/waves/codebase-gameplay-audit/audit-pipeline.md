# TAT-2 Asset Pipeline + Test Suite Audit

Date (UTC): 2026-11-20. HEAD post-round-1+round-2 playtest fixes.
Scope: read-only analysis. No code/data edits, no extractions run. Only file written: this report.
Ground truth: `.omo/waves/tat2-ground-truth/backlog.md`. Prior evidence: `.omo/evidence/tat2-playtest-ground-truth-fixes/` (`task-1.md`, `task-0.md` in round-2 dir), `.omo/evidence/tat2-playtest-round2-fixes/task-0.md`, `task-1.md`.
Inventory: 37 GDScript files (per task context); `tools/tat-extract/Exporter.cs` (311 lines), `tools/tat-extract/Program.cs` (102 lines), `tools/parse_*.py` (10 files, 9416 lines incl. helpers), `tools/manifest_audit.py` (49 lines), `game/tests/run_tests.gd` (3459 lines, blocks #1–#37 + #0–#37 numbering), `game/tests/e2e/` (5 .gd, 4075 lines), `game/data/generated/` (materials.json, mesh_materials.json, anims_manifest.json, audio_*.json, gameplay/*.json, levels/*, tables/*, vfx/*, weather/*), `Makefile` (extract/audit/test/linux/android targets).

Note on standing read-only agreement: the project agreement treats `/home/john/Projects/TAT-2` as read-only for diagnostics. This task explicitly authorizes writing ONLY this report path, so this one new file is written and no source/data file is touched.

## 1. tools/tat-extract/Exporter.cs — Packages / Meshes / Tables filters, round-2 repair, silent-drop risks

### 1.1 Packages() gate — TAT/ + round-2 BasicShapes exception

`tools/tat-extract/Exporter.cs:30-37`:

```csharp
IEnumerable<GameFile> Packages(Func<string, bool>? pathPred = null) =>
    _p.Files.Values.Where(f => (f.Extension == "uasset" || f.Extension == "umap")
                               && (f.Path.StartsWith("TAT/", StringComparison.OrdinalIgnoreCase)
                                   // task-1 (round-2 mesh repair): Engine/BasicShapes primitives are
                                   // referenced by Den/Guildhall levels but live outside TAT/.
                                   || f.Path.StartsWith("Engine/Content/BasicShapes/", StringComparison.OrdinalIgnoreCase))
```

What this proves: everything outside `TAT/` is still dropped except the one round-2 exception. `Engine/` coverage is 1 subdirectory, not all of `Engine/Content/`. Any future level reference to `/Engine/...` outside `BasicShapes/` (e.g. `EngineMaterials`, `EngineMeshes`, editor meshes such as `SplineEditorMesh`, `WorldGridMaterial` carriers) is silently excluded from every command (`json`, `tables`, `levels`, `materials`, `meshes`, `textures`, `anims`, `audio-pkg`) because they all funnel through `Packages()`. Round-2 evidence confirms the mechanism: `task-1.md` §3 table shows `VFX_SkySearchLight_Mesh` binds after repair to `['/Engine/EngineMaterials/WorldGridMaterial']` — the material itself was never exported (it lives under `/Engine/`, not `/BasicShapes/`), only the mesh that references it was. The bind is a dangling path, not a resolved material.

`tools/tat-extract/Program.cs:30-32` mounts only one pak dir:

```csharp
var provider = new DefaultFileProvider(Path.Combine(opt.Game, "TAT/Content/Paks"), SearchOption.TopDirectoryOnly,
```

`TopDirectoryOnly` + hardcoded `TAT/Content/Paks` means extra pak chunks, patch paks, or DLC dirs placed beside the mount root are invisible. No warning is emitted for unmounted siblings.

### 1.2 Tables() roots — closed allowlist

`tools/tat-extract/Exporter.cs:133-139`:

```csharp
public void Tables()
{
    var roots = new[] { "TAT/Content/Gameplay/", "TAT/Content/AI/", "TAT/Content/Missions/", "TAT/Content/Character/", "TAT/Content/Core/", "TAT/Content/StringTables/", "TAT/Content/Maps/", "TAT/Content/UI/", "TAT/Content/Audio/" };
    ForEach(Packages(p => p.EndsWith(".uasset") && roots.Any(p.StartsWith)), "tables", DumpJson);
}
```

Any DataTable/CurveTable outside those 9 roots (e.g. `TAT/Content/Art/`, `TAT/Content/ThirdParty/`, `TAT/Content/Developers/`) never reaches `extracted/json/` and therefore never reaches `parse_tables.py` / `parse_gameplay.py` / `parse_contracts.py`. Failure mode is silent: the file is simply not queued. There is no log line listing skipped-by-root files.

### 1.3 Levels() predicate — name-prefix heuristic

`tools/tat-extract/Exporter.cs:130`:

```csharp
public void Levels() => ForEach(Packages(p => p.EndsWith(".umap") || Path.GetFileName(p).StartsWith("BPP_") || Path.GetFileName(p).StartsWith("SV_") || Path.GetFileName(p).StartsWith("S_") || Path.GetFileName(p).StartsWith("SS_") || Path.GetFileName(p).StartsWith("QG_")), "levels", DumpJson);
```

`BPP_/SV_/S_/SS_/QG_` are Blueprint class prefixes, not level suffixes. Any `.uasset` whose filename happens to start with `S_` (a very common UE prefix: `SM_`, `SK_`, `SKM_` all start with `S` — but the check is `StartsWith("S_")` with underscore so `SM_` does not match; still, `S_<anything>` blueprints such as sound/state blueprints are pulled into `levels/`) is dumped as a level, while a genuine streaming sublevel that does not end in `.umap` and does not carry one of those 5 prefixes is missed. The predicate mixes two domains (map files vs actor blueprints) with no comment or test.

### 1.4 Materials() predicate — name + path heuristic

`tools/tat-extract/Exporter.cs:132`:

```csharp
public void Materials() => ForEach(Packages(p => p.EndsWith(".uasset") && (Path.GetFileName(p).StartsWith("MI_") || Path.GetFileName(p).StartsWith("M_") || p.Contains("/Developers/") || p.Contains("/MaterialLibrary/"))), "materials", DumpJson);
```

Mirrors `parse_materials.py` discovery (`MI_*/M_*`, `MaterialLibrary/Developers/`). Consequence: `MaterialInstance` assets not following the prefix (e.g. `MLI_*`, `MM_*`, numbered suffixes like `*_MI8` are handled downstream in parse_materials but never exported here unless under the two magic paths) are dropped before the parser ever sees them. `parse_materials.py:1-40` docstring says discovery is by name `MI_*/M_*, *_MI/*_MI8` — wider than the exporter — so the exporter is the narrower gate. The two filters disagree; exporter wins silently.

### 1.5 Meshes() allowlist — round-2 widened, still closed

`tools/tat-extract/Exporter.cs:203-205` (round-2 repair comment + filter):

```csharp
// task-1 (round-2 mesh repair): also queue VFX_*/Coin_* meshes and Engine
// BasicShapes primitives dropped by the SM_/SK_/SKM_/GB_ allowlist.
var files = Packages(p => p.EndsWith(".uasset") && (_o.Filter != null || Path.GetFileName(p).StartsWith("SM_") || Path.GetFileName(p).StartsWith("SK_") || Path.GetFileName(p).StartsWith("SKM_") || Path.GetFileName(p).StartsWith("GB_") || Path.GetFileName(p).StartsWith("VFX_") || Path.GetFileName(p).StartsWith("Coin_") || p.Contains("/Meshes/") || p.Contains("/Mesh/") || p.Contains("/Test/LevelKits/") || p.Contains("/GasLamps/") || p.Contains("/Furniture/Tables/") || p.Contains("/Levers/") || p.Contains("/GeneratedMeshes/") || p.Contains("/BasicShapes/") || p.Contains("/Developers/"))).ToList();
```

Pre-round-2 the allowlist was `SM_/SK_/SKM_/GB_` + path substrings; round-2 added `VFX_`, `Coin_`, `/BasicShapes/` (evidence `task-1.md` §1: "widened the name allowlist … with `StartsWith("VFX_")`, `StartsWith("Coin_")`, and `Contains("/BasicShapes/")`"). Verified effect: `find extracted/assets -name '*.glb' | wc -l` 2045 → 2054 (+9: 3 coins + VFX mesh + 5 shapes + 1 material-only package yielding no mesh). Residual risk is structural, not numeric: any mesh whose asset name does not start with those 6 prefixes and whose path lacks those 8 substrings is still skipped. UE has no such naming law (`SKEL_*`, `T_*` meshes, unprefixed developer meshes, `VFX_SkySearchLight_Mesh` itself only passed because of the new `VFX_` prefix — a `VFXSky*` without underscore would still drop). The `--filter` bypass (`_o.Filter != null` short-circuits the allowlist) proves the author knows the allowlist is lossy, but default `make extract` runs unfiltered.

Silent-drop amplifier — overwrite-skip checks the wrong path (`Exporter.cs:209`):

```csharp
if (!_o.Overwrite && File.Exists(OutPath("assets", f.Path, ".glb"))) { Count("meshes", true); continue; }
```

`task-1.md` §2 documents: "the pre-existing overwrite-skip check looks at `extracted/assets/<rel>.glb` while the exporter writes GLBs to `extracted/assets/TAT/Content/<rel>.glb`, so every unfiltered run re-exports all ~2000 packages." Counted as `ok` (`Count("meshes", true)`) either way, so the `[meshes] ok=/fail=` line cannot distinguish "skipped, already fresh" from "exported now" from "skipped by stale check". Same pattern at `Exporter.cs:123` (`json`) and `Exporter.cs:186` (`textures`).

Error truncation + counting (`Exporter.cs:51`, `Exporter.cs:69`, `Exporter.cs:235`, `Exporter.cs:302-308`):

```csharp
(ok ? _ok : _fail).AddOrUpdate(kind, 1, (_, v) => v + 1);
```

```csharp
static string Trunc(string s) => s.Length > 300 ? s[..300] : s;
```

```csharp
Count("meshes", r.Success && (r.DiskFilePaths?.Count ?? 0) > 0, r.Error != null ? $"{r.ObjectPath}: {Trunc(e.Error.Message)}" : null);
```

```csharp
File.AppendAllLines(Path.Combine(_o.Out, "errors.log"), _errors);
```

Consequences: (a) messages truncated to 300 chars — UE paths + inner exception chains routinely exceed that; (b) `_errors` capped at 5000 entries (`Exporter.cs:53`: `if (!_errors.IsEmpty ... _errors.Count < 5000`), beyond that failures are counted but message-less; (c) `errors.log` is appended (`AppendAllLines`), never rotated — stale errors from prior runs persist and are indistinguishable from current-run errors; (d) `Report()` prints only `ok=/fail=` per kind, no skipped/queued denominator split, so a filter that drops 90% of packages still reports `ok=N fail=0`.

`FixBackslashPaths` (`Exporter.cs:237-250`) moves files with `\` in the returned disk path to a `/`-normalized path via `File.Move(..., true)`. Silent overwrite (`true`) + no log line: if two exports collide after normalization, the second silently wins.

### 1.6 Textures() filter — narrow, map-special-cased

`tools/tat-extract/Exporter.cs:166-174`:

```csharp
ForEach(Packages(p => (p.EndsWith(".uasset") && (Path.GetFileName(p).StartsWith("T_") || p.Contains("/Textures/") || p.Contains("/UI/") || p.Contains("Icon") || p.Contains("WindowPanels_Oldmanor")
        || Path.GetFileName(p).StartsWith("WindowPanel_", StringComparison.Ordinal)
        || Path.GetFileName(p).StartsWith("StorefrontWoodTile_", StringComparison.Ordinal)
        || Path.GetFileName(p).StartsWith("TrimFabricFancyA_", StringComparison.Ordinal)
        || Path.GetFileName(p).StartsWith("OldBricksB_", StringComparison.Ordinal))) || (p.EndsWith(".umap") && (p.Contains("Landscape")
            || p.Contains("BeautifulCorner_Startscreen_P")
            || Path.GetFileNameWithoutExtension(p).Equals("OldManor_P", StringComparison.OrdinalIgnoreCase)))), "textures", f =>
```

Texture allowlist mixes three mechanisms (prefix `T_`, path substrings, four hardcoded asset stems) plus three hardcoded umap texture sources. Any texture not starting with `T_` and outside `/Textures/`/`/UI/` (UE allows arbitrary texture names; photo-scanned and ThirdParty textures often lack `T_`) is dropped. The four hardcoded stems (`WindowPanel_`, `StorefrontWoodTile_`, `TrimFabricFancyA_`, `OldBricksB_`) are per-asset patches with no general rule — the next missing-texture asset needs another code edit. Decode/encode nulls are counted (`Exporter.cs:188,190`: `if (decoded == null) { Count("textures", false, f.Path + ": decode null"); continue; }`) but produce no PNG and no placeholder — downstream `parse_materials.py` then falls back to stem/category heuristics (see §2.2) with no signal that the source PNG was never exported.

### 1.7 Audio() — extension + path + export-type triple gate

`tools/tat-extract/Exporter.cs:280`:

```csharp
var raw = _p.Files.Values.Where(f => (f.Extension is "wem" or "bnk" or "ubulk") && f.Path.Contains("Wwise", StringComparison.OrdinalIgnoreCase));
```

`tools/tat-extract/Exporter.cs:288-293`:

```csharp
ForEach(Packages(p => p.EndsWith(".uasset") && (p.Contains("/WwiseAudio/") || p.Contains("/Audio/"))), "audio-pkg", f =>
{
    var pkg = _p.LoadPackage(f);
    foreach (var e in pkg.GetExports())
    {
        if (!e.ExportType.StartsWith("Ak")) continue;
```

Three silent drops: (a) audio in non-`Wwise` paths with those extensions is ignored; (b) audio packages outside `/WwiseAudio/`/`/Audio/` are ignored; (c) non-`Ak`-prefixed exports inside an audio package are skipped without counting (`continue` with no `Count`). `Report()` therefore overstates audio coverage.

### 1.8 Anims() filter

`tools/tat-extract/Exporter.cs:260`:

```csharp
foreach (var f in Packages(p => p.EndsWith(".uasset") && (Path.GetFileName(p).StartsWith("AN_") || Path.GetFileName(p).StartsWith("A_") || Path.GetFileName(p).StartsWith("AS_") || p.Contains("/Animation/"))))
```

`A_*` prefix matches any asset starting with `A_` (audio? actors? `A_` is two characters including underscore — broad). Conversely `AN_` montages under non-`/Animation/` paths without those prefixes are missed. No `Count("anims", false)` for filtered-out files — they are invisible.

## 2. tools/parse_*.py + parse_materials / loot / spawners — coverage gaps, hardcoded fallbacks

### 2.1 parse_tables.py — the level normalizer; silent continues dominate

File: `tools/parse_tables.py` (2631 lines). Entry `main()` at `parse_tables.py:2622` calls `extract_datatables()`, `extract_levels()`, `fix_interactables_var_track_bounds()`, `copy_fonts()`.

Fail-open vs fail-closed is mixed. `build_level_transforms` (`parse_tables.py:240-258`) and `build_glb_stem_index` (`parse_tables.py:268-282`) swallow JSON errors:

```python
try:
    exps = json.loads(jf.read_text())
except Exception:
    continue
```

`extract_levels` loop (`parse_tables.py:1202-1208`):

```python
for jf in sorted((EX / "json" / "Maps").rglob("*.json")):
    if jf.name.startswith("BPP_"):
        continue
    try:
        exps = json.loads(jf.read_text())
    except Exception:
        continue
    if not isinstance(exps, list) or not exps:
        continue
```

`BPP_*` files are skipped here (they are re-consumed as packed-actor templates elsewhere). Any corrupt/empty level JSON is skipped with no error counter — there is no `errors.log` equivalent; only `print` of aggregate counts.

Depth cap: `get_world_mat` (`parse_tables.py:1249-1276`) caps `AttachParent` chains at `depth > 12` and returns `mat4_identity()` — a deeply nested prop silently snaps to origin. No counter for depth-cap hits.

`BP_COMPONENT_TYPES` (`parse_tables.py:285-294`): `NiagaraComponent, DecalComponent, RectLightComponent, SkyLightComponent, ExponentialHeightFogComponent, PostProcessComponent, SkyAtmosphereComponent, VolumetricCloudComponent`. These are resolved via SCS templates (`resolve_bp_component`, up to 6 levels of Template inheritance). Unresolvable cases increment `niagara_unresolved` / `decals_unresolved` / `splines_skipped` (`parse_tables.py:1296-1299`) but several sibling branches `continue` without incrementing any counter (e.g. `parse_tables.py:1904`, `parse_tables.py:1935`, `parse_tables.py:1974`, `parse_tables.py:2005`, `parse_tables.py:2044`). Net: the unresolved tallies are lower bounds, not totals.

`_resolve_override_item` (`parse_tables.py:750-806`) returns `""` for unresolvable `MaterialInstanceDynamic` refs and records at most 10 samples (`mid_stats["samples"]`, `parse_tables.py:763-766`, `parse_tables.py:804-806`):

```python
if mid_stats is not None:
    mid_stats["unresolved"] += 1
    if len(mid_stats["samples"]) < 10:
        mid_stats["samples"].append((map_ue_path or "", op, on))
```

Beyond 10 samples, further distinct unresolved MIDs are counted but unidentifiable. `_component_override_paths` (`parse_tables.py:809-856`) "Preserves '' for None/unresolvable slots … and trims only trailing ''" — interior `""` slots survive into `tatlevel.json` and are resolved at load time by `mesh_materials.json` order or fallback; the provenance of "authored empty" vs "failed to resolve" is lost.

`_extract_emissive_cpd` (`parse_tables.py:866-884`) returns `None` unless exactly 5 numeric floats; any other length silently yields no CPD (no counter).

`fix_interactables_var_track_bounds` (tail of `parse_tables.py`) patches `arc_angle_deg→arc_deg` / `durationSeconds→duration_s` aliases and rewrites the JSON in place. It is a silent schema migration: generated files change without a version bump, and `manifest_audit.py` cannot detect it (see §3).

LevelInstance merge (Pass 2, `parse_tables.py:2240+`): pending refs resolved recursively from in-memory payloads so alphabetical ordering does not matter. Unresolved LevelInstances increment `total_level_instances_unresolved` (`parse_tables.py:1196`). This is one of the few properly counted gaps — and `run_tests.gd` block #20 pins the one known case (`Facade_Apartment_CarUnderpass`), not the general mechanism.

Spline skip (`parse_tables.py:2290-2296`):

```python
if not mesh_path or "SplineEditorMesh" in mesh_path:
    splines_skipped += 1
    continue
```

Editor-preview splines are intentionally skipped — correct, but `splines_skipped` is printed per-level, not aggregated, so global spline loss is unknown.

### 2.2 parse_materials.py — widest heuristics, weakest provenance

File: `tools/parse_materials.py` (1024 lines). Docstring `parse_materials.py:1-40` declares the UE→Godot mapping including explicitly NOT-mapped terms (shading model `MSM_Unlit`, `Opacity` scalars, `Spec` colour vectors, `Refraction`, rain/puddle/grunge/noise/tiling switches, mask/channel selectors). Those are documented coverage gaps, not bugs — but they mean any asset relying on them renders differently with no runtime warning.

Discovery disagreement (see §1.4): parser accepts `MI_*/M_*, *_MI/*_MI8` by name plus `MaterialLibrary/Developers` paths; exporter only emits `MI_*/M_*` + those paths. Parser-side width is moot for anything the exporter never dumped.

Three-tier albedo fallback (`parse_materials.py:611-657`, `_stem_fallback_albedo`):

```python
def _stem_fallback_albedo(
    mat_name: str, pkg: str, parent: str, tex_by_stem: dict
) -> str:
```

Tier 1 direct stem match, Tier 2 ranked candidate (`_best_albedo_candidate` over tokens/family/path-category), Tier 3 category fallback:

```python
# 3) Category fallback: material/pkg/parent name mentions Brick/Stone/Wood/etc.
hay: str = (mat_name + " " + pkg + " " + parent).lower()
for cat, stems in CATEGORY_FALLBACK_STEMS.items():
    if cat in hay:
        for cand in stems:
            if cand in tex_by_stem:
                found: str = tex_by_stem[cand]
                return found
return ""
```

`CATEGORY_FALLBACK_STEMS` at `parse_materials.py:434`, `TOKEN_DROP` stop-word list at `parse_materials.py:546` (includes `black, white, blue, red, green, yellow, orange, purple, teal, cream, grey, gray, pink, cyan, magenta, dark, light, bright, old, new, smooth, rough, dirty, clean, worn, alt, variant, var`). Any material whose name contains a category word (e.g. `MI_BrickTrim`) can bind a generic category texture with no record that the bind is a guess — `materials.json` carries no `fallback_tier` field. The guard report (`Mapped 2054 mesh material slot lists (2031 GLB-ordered, 23 sidecar-fallback)`) counts GLB-vs-sidecar order only, not how many albedo binds came from Tier 2/3 guessing.

`_glb_primitive_material_names` (`parse_materials.py:80-118`) returns `None` when the GLB is missing/unparseable and the caller falls back to sidecar order — again without marking the entry. Degenerate-primitive filtering ("fewer than 3 distinct indices or 0 triangles … filtered so the emitted count matches the imported ArrayMesh surface count") means `mesh_materials.json` slot count matches Godot's import, not UE's authored slot count; a slot UE intended but Godot drops is invisible downstream.

### 2.3 parse_loot.py — fail-closed for buckets, fail-open for quest

File: `tools/parse_loot.py` (374 lines). Docstring `parse_loot.py:1-30` states the mesh rule (tagged `Interact` StaticMeshComponent wins, else `StaticMesh_GEN_VARIABLE`, else first StaticMeshComponent; `Glass_GEN_VARIABLE` never wins) and the quest fallback ("quest actors with a missing mesh keep mesh_res '' and are served the box fallback in loot_item.gd (labelled, never invented)").

Bucket actors are fail-closed (`parse_loot.py:170`, `parse_loot.py:194-213`):

```python
raise SystemExit(f"missing bucket file: {bucket_file}")
```

```python
raise SystemExit(f"{cls}: mesh missing on disk: {obj_path}")
```

Quest actors are fail-open: missing mesh keeps `mesh_res ""` and the runtime shows a labelled box. The `fallback` block (`parse_loot.py:335-354`) records `generic_quest_actor`, `unmapped_contract_tags`, `unmapped_quest_tags`, `skipped_blueprints`, `missing_mesh_quest_actors`, with the note "All 16 shipped contract loot_tags resolve to a dedicated actor (VistaraFiles included), so the fallback never fires on shipped content". That invariant is asserted in prose, not in code — no `SystemExit` if a shipped tag becomes unmapped after a re-extract. `Mesh choice` for quest actors inherits the same `choose_mesh` heuristic; `InstancedStaticMeshComponent Interact proxies are recorded for transparency but are not the visible loot` — proxies are dropped from spawn with only a JSON note.

`find_bp_file` (`parse_loot.py:37-44`) resolves `/Game/.../BP_Foo.BP_Foo_C` by stem search (`sorted(EX.rglob(stem + ".json"))`, first match). Duplicate stems (same BP name in two UE folders) silently resolve to the alphabetically-first file. Same helper is duplicated in `parse_spawners.py:37-44`.

### 2.4 parse_spawners.py — 5 documented approximations, hard asserts

File: `tools/parse_spawners.py` (326 lines). Docstring `parse_spawners.py:1-15`: "Values that only exist in cooked Blueprint graphs (health heal amount, ammo refill amount, bottle throw speed/impact noise, civilian walk speed) are NOT invented here; they are documented approximations in docs/reports/spawners.md and implemented as clearly-labelled constants in the GDScript side."

Emitted `approximations` block (`parse_spawners.py:306-311`):

```python
"approximations": {
    "health_heal_amount": "NOT SERIALIZED in cooked graphs; implemented as full heal (documented).",
    "ammo_refill_amount": "NOT SERIALIZED in cooked graphs; implemented as refill-all-charges (documented).",
    "bottle_throw_speed_m_s": "NOT SERIALIZED; documented approximation 12.0 m/s.",
    "bottle_impact_noise_m": "NOT SERIALIZED; documented approximation 10.0 m radius.",
    "civilian_walk_speed_m_s": "NOT SERIALIZED; documented approximation 1.4 m/s.",
    "civfemale_clips": "NO CivFemale clips in the animation manifest; generic MM_Unarmed_* clips retargeted by bone name, else rest pose.",
},
```

These are honest, labelled gaps — the risk is downstream: nothing in `spawners.json` schema forces the GDScript constants to stay in sync with these strings, and `run_tests.gd` does not assert any of the five values.

Hard asserts (`parse_spawners.py:288`, `parse_spawners.py:294`):

```python
assert not missing, f"resolved meshes missing on disk: {missing}"
```

```python
assert not missing_civ, f"civilian meshes missing on disk: {missing_civ}"
```

Fail-closed is correct here, but `assert` is stripped under `python -O` — a validator that vanishes under optimization. `raise SystemExit` (used at `parse_spawners.py:193` for missing bucket files) would survive.

### 2.5 parse_gameplay.py — fail-closed, one hardcoded fallback

File: `tools/parse_gameplay.py` (611 lines). Docstring `parse_gameplay.py:1-9`: "Fails closed: any missing source aborts." Every missing source/property/export raises `Fail` (`parse_gameplay.py:26`, `parse_gameplay.py:30`, `parse_gameplay.py:43`, `parse_gameplay.py:56`, plus ~15 call-site `raise Fail`). This is the strictest parser — good.

One exception (`parse_gameplay.py:374-377`):

```python
"alerted_combat_fallback_m_s": 2.5,
"sources": {
    "neutral_suspicious": "extracted/json/AI/Data/DA_AIStatesToSpeed_Guard.json (StatesToSpeeds 150/170)",
    "fallback": "extracted/json/Character/Guards/BP_Guard_Base.json (TATCharacterAIMovement MaxWalkSpeed 250)",
},
```

`alerted_combat_fallback_m_s = 2.5` is `250 cm / 100` — the arithmetic is right, but unlike every other value in the file it is a hand-written constant, not a read of `DA_AIStatesToSpeed_Guard` (which only carries `neutral`/`suspicious`; `alerted`/`combat` speeds live elsewhere or nowhere). If `BP_Guard_Base.json MaxWalkSpeed` changes, this constant rots with no failing check — the `sources.fallback` string is prose, not a dependency.

### 2.6 parse_contracts.py / parse_containers.py / parse_interactables.py

- `parse_contracts.py:93-130`: `load_contract_rows` tries `DT_Contracts_1_to_16.json` then `CDT_Contracts.json` fallback; `Contract.Main.15 ContractOrder=0` repaired from row key (`parse_contracts.py:104-112`: `if order <= 0: order = key_order`). `ue_asset_to_res` (`parse_contracts.py:48-60`) returns `""` for empty asset paths; `map_id_from_ue` (`parse_contracts.py:62-80`) defaults unknown/empty maps to `thieves_den` — Contract 1's empty Map path becomes the hub by rule, not by data. Reasonable, but a genuinely missing map path on any other contract would also silently become `thieves_den`.
- `parse_containers.py:110-121`: exactly 5 hardcoded Blueprint classes (`BP_ChestTrunk_MajorLoot`, `BP_DisplayCaseA_MajorLoot`, `BP_LootStashInteractable_Secret_ThinWall`, `BP_Storefront_DisplayCaseB_MinorLoot/D`). A 6th container Blueprint in cooked data is never emitted — the file has no discovery, only the `CLASSES` dict. Fail-closed within the 5 (`raise SystemExit` on missing JSON or bucket mismatch) is correct.
- `parse_interactables.py:74`, `parse_interactables.py:113`: `display_name` / `loot_tag` return `""` on missing shapes; `spawn_pool` excludes `Value 0` (currency placeholders) and `Value 1` (renown test item) — a real loot item ever shipped with `Value <= 1` would vanish from spawn pools with no warning. Door durations absent from source become explicit `null` (`pick_duration_s: null`, `open_duration_s: null`) — the honest pattern the rest of the pipeline should copy.

### 2.7 parse_vfx.py / parse_weather.py

- `parse_vfx.py:31-32`: `GRAPH_HEAVY_MIN_SCRIPTS = 18`, `GRAPH_HEAVY_MIN_LUTS = 72` — top-decile cutoffs over the 120-system corpus (`parse_vfx.py:25-30` comment). Any资产 drift that moves the bulk distribution silently reclassifies systems; cutoffs are constants, not percentiles. `systems.json` records 120 systems (`graph_heavy: 21, mesh_or_ribbon: 70, sprite_only: 29`). Niagara compiled graphs are NOT translated ("parameters are recorded only as names/types … defaults live in raw ParameterData bytes and are not decoded", `parse_vfx.py:1-20` docstring) — every VFX spawn in `run_tests.gd` blocks #8/#9 therefore proves plumbing, not authored look.
- `parse_weather.py:473+` `main()`: `manager_overrides` per map; `choose_preset` falls back to class default when a map defines no `PresetOverrides` (Guildhall: `"reason": "map manager defines no PresetOverrides, so class default applies; MidnightClear is the canonical night-clear weather"`). Colours keep UE `LinearColor` HDR >1.0 vs `FColor` /255 distinction (`_norm_color`). `No numbers are invented: fields absent from the source JSON become null` — the file's strongest line. Residual: `TAG_BY_PRESET` and `MANAGER_BY_MAP` are closed dicts; a new weather tag or map id yields `null`/KeyError rather than a discovered preset.

## 3. game/data/generated/ staleness + manifest_audit validator coverage

### 3.1 What generated/ holds (not bulk data — schemas + timestamps)

`game/data/generated/` (Nov 16–20 timestamps): `anims_manifest.json` (529 KB, Nov 16), `audio_events.json` (1.47 MB, Nov 19), `audio_library.json` (1.42 MB, Nov 17), `gameplay/` (13 files incl. `contracts.json` 25 KB, `interactables.json` 60 KB, `loot_actors.json` 45 KB, `spawners.json` 10 KB), `levels/` (Buildings/FTUE/Guildhall/MissionLobby/OldManor/ThievesDen/etc. `*.tatlevel.json`), `tables/` (AI/Art/Audio/Character/Gameplay/Map/StringTables/UI/WwiseAudio), `materials.json` (1.2 MB, Nov 20), `mesh_materials.json` (442 KB, Nov 20, 2054 keys), `vfx/` (`systems.json` 120 systems + `catalogue.md`), `weather/` (15 presets + `map_weather.json`, Nov 17).

Staleness vectors (all read-only observations, no extraction run):
- `extracted/` (gitignored) is the only source of truth for `game/data/generated/`; `extracted/filelist.txt` (22005 entries per backlog) + `extracted/json/` (12560 files) are pre-round-2 snapshots except the 9 round-2 GLBs. `materials.json`/`mesh_materials.json` (Nov 20) are newer than `weather/*` (Nov 17) and `gameplay/contracts.json` (Nov 16) — the tree is a mix of parser vintages with no manifest recording which `extracted/` snapshot produced which generated file. Re-running `make extract` (full unfiltered, ~2000 packages, slow per `task-1.md` §2) followed by a subset of `parse_*.py` can leave half the tree on the old snapshot with no error.
- `parse_tables.py` in-place alias patch (`arc_angle_deg→arc_deg`, `durationSeconds→duration_s`) mutates generated JSON without bumping any version — a diff of `interactables.json` cannot tell "re-extracted" from "alias-patched".
- `game/assets/ue/Content → extracted/assets/TAT/Content` and `game/assets/ue/Raw → extracted/assets` are symlinks (per `task-1.md` §2). Deleting/regenerating `extracted/` orphans every `res://assets/ue/` path; nothing validates symlink targets at test boot (block #0 checks autoloads only).

### 3.2 manifest_audit.py — what it actually validates

`tools/manifest_audit.py:1-49`, full file:

```python
"""Compare extracted files against Steam Manifest_UFSFiles_Win64.txt."""
...
STEAM_MANIFEST = Path.home() / ".local/share/Steam/steamapps/common/Thick As Thieves/Manifest_UFSFiles_Win64.txt"
...
    mounted = set()
    for line in filelist.read_text().splitlines():
        if line:
            mounted.add(line.split("\t")[0])
    ...
    manifest_tat = []
    for line in Path(args.manifest).read_text(errors="replace").splitlines():
        p = line.split("\t")[0].strip()
        if p.startswith("TAT/") and not p.endswith((".ubulk", ".uexp", ".uptnl")):
            manifest_tat.append(p)
    # Check how many manifest TAT files are in mounted pak/utoc
    resolved = sum(1 for p in manifest_tat if p in mounted)
    # Check how many were actually dumped to extracted/
    dumped = 0
    for sub in ("raw", "json", "assets", "audio", "audio-meta"):
        d = ex / sub
        if d.exists():
            dumped += sum(1 for _ in d.rglob("*") if _.is_file())
    cov = resolved / max(1, len(manifest_tat))
    print(f"Manifest TAT entries: {len(manifest_tat)}")
    print(f"Resolved in CUE4Parse: {resolved} ({cov:.1%})")
    print(f"Files written to {ex}: {dumped}")
    if cov < args.min_coverage:
        raise SystemExit(f"coverage {cov:.1%} < {args.min_coverage:.1%}")
```

And `Makefile:38`: `python3 tools/manifest_audit.py --min-coverage 0.90`.

What it proves: ≥90% of `TAT/` manifest entries (minus `.ubulk/.uexp/.uptnl`) appear in `filelist.txt` (i.e. CUE4Parse mounted them). What it does NOT prove, by construction:
1. `dumped` is printed but never gated — thousands of mounted-but-never-dumped files pass silently. The `--min-coverage` gate applies to `resolved` (mounted), not to dumped/parsed/generated.
2. No per-stage gate: `raw` vs `json` vs `assets` vs `audio` counts are summed into one number; a stage that exported 0 files still passes if the mount coverage is ≥90%.
3. `filelist.txt` staleness: the audit reads whatever `filelist.txt` is on disk; a months-old `list` output passes as long as it covers the manifest. No timestamp/hash check against current paks.
4. `errors.log` is never read — `ok=9 fail=0`-style per-kind failures do not affect the audit.
5. Non-`TAT/` coverage (`Engine/Content/BasicShapes/`, the round-2 exception) is outside `manifest_tat` (`p.startswith("TAT/")`), so the round-2 fix it enabled is unmeasured by the gate that guards the pipeline.
6. Generated-data freshness: nothing compares `extracted/` mtimes against `game/data/generated/` mtimes, and nothing checks that every `extracted/json/Maps/*.json` has a corresponding `*.tatlevel.json` (or vice versa). A level deleted from cooked data leaves a stale generated file with no failing check.

## 4. game/tests/run_tests.gd — what the tests prove, blind spots, flaky patterns

### 4.1 What runs: 37 numbered blocks, not 90 isolated tests

`game/tests/run_tests.gd` (3459 lines) contains numbered blocks `# 1.`–`# 37.` (plus `# 0` boot). The "90 tests" figure counts individual `PASS:`/`FAIL:` assertions across `run_tests.gd` + `game/tests/e2e/` (`e2e_tier1_features.gd` 22 `_feat_*` funcs, `e2e_tier2_boundaries.gd`, `e2e_tier3_pairwise.gd`, `e2e_tier4_scenarios.gd`, `run_e2e_tests.gd` harness, `e2e_helpers.gd`). `grep -c "PASS:|FAIL:" run_tests.gd` ≈ 49 assertion sites (each block emits 1–6). Representative pins:

- Blocks #1–#2 (contracts/curves): 18 contracts, Contract 2 title `Into the Lion's Den`, sublevel tags + `tables.size()`, `CT_PlayerStats.BaseHealth` 300→150, `CT_AIStats.GuardKnockoutDuration` 300, `CT_Tool_Blackjack.BlackjackDamageHeavy` 75.
- Block #4 (Old Manor smoke): `guards >= 4`, `loots >= 5`, `swinging_doors >= 120` + `leaves >= 120`, pivot-mesh 90° swing (`absf(absf(rot.y) - PI*0.5) < 0.02` after `await create_timer(0.55).timeout`).
- Block #10 (Guildhall terrain): fog-density preset wins (`0.0006` vs stale `0.004`), raycast grounding, `LandscapeCollision_12` 63×63 span, alley/overhang `y≈18.56`, safe-light aim/angle, `spawn_lights >= 1`.
- Block #11 (perf): `chunk_count >= 500`, `multimeshes >= 200`, `bodies >= 4`, `0 < shapes < 32000`, `occluders > 0`, `max_chunk_span < 140`, `culled >= 300`.
- Blocks #18–#21 (extraction regressions): door files `>= 70`, doors `>= 281`, leaves `>= 373`, `unresolved == 0`, `pivot_mesh_leaves >= 111`; PeripheryA `meshes >= 10000`, `near_spawn >= 200`; `CarUnderpass` instance present + `>= 100` near meshes; `discard_holes == 0.0`.
- Blocks #22–#23, #28–#32 (fidelity): moon size `9.838636`, cloud `3.299213`, horizon/zenith overall_color products, moon-disc emissive `(0.5137, 0.5216, 1.0)`, light ratio `45/15 == 3.0`, ceiling `2500 → 4.0`, radius 1:1, MID/slot-remap/`bVisible:false`/SplineEditorMesh matrix, emissive CPD + glass shader replaces flat-blue.
- Blocks #34–#37 (phase 2A/2B, probe retune, neon HDR tints).

This is a strong regression net for shipped content: every prior incident class (stale map default, doorway-hinge doors, black-void PeripheryA, missing car underpass, visibility-hole discard, light-energy collapse, flat-blue glass) has a pinned numeric assertion. The suite fails closed on counts (`doors < 281` fails; `unresolved != 0` fails).

### 4.2 What the suite does NOT prove (blind spots)

1. Audio audibility: block #1 asserts `AudioManager` autoload exists; no block plays a `.wem`/`.bnk`-derived cue or asserts `audio_events.json`/`audio_library.json` audibility. `extract_audio.py` / `convert_wwise.py` / `fetch_vgmstream.sh` output is untested.
2. Save persistence round-trip: block #9 reads `get_level_progress()` / `get_currency()`; no block writes, reloads, and re-reads progression. Corrupt-save handling untested.
3. Guard AI beyond smoke: block #4 asserts spawn counts; `guard_ai.gd` state machine (`ST_Guard`, `ST_InvestigateStims_Guard`, `DAM_CharacterAnimationMapping_GuardBase` per backlog F12) transitions, escalation ramps (`DA_DetectionSettings` 4 ramps), and clip-role mapping are covered only indirectly via e2e tier funcs, not via targeted unit pins in `run_tests.gd`.
4. VFX look: blocks #8/#9 spawn `lockpick_sparks`, `blackjack_swing`, `window_godray`, `footprint_decal`, `blue_wisp` and assert non-null/visible — never color/intensity/count vs authored Niagara params (which the parser explicitly does not decode, §2.7). A wrong-but-present effect passes.
5. Weather beyond two presets + map table: block #17 pins `dense_fog` + `midnight_clear_thieves_den` + `preset_name_for_map` for 6 maps; `gloomy/stormy/heavy_rain/blood_moon/dusk_stormy/sunrise_clear_skybox` presets have no apply-environment assertion. `TAG_BY_PRESET` gaps (§2.7) are untested.
6. Container/spawner/loot runtime wiring: `containers.json` (5 classes), `spawners.json` buckets, `loot_actors.json` tag→actor map are asserted at generation time (fail-closed `SystemExit`/`assert`), not at runtime — no `run_tests.gd` block spawns every bucket entry and checks `mesh_exists`.
7. Multi-contract coverage: blocks #4/#7/#10 boot contracts 3/1/4 only. Contracts 2, 5–18 missions (`DT_Missions_*` Vault 7200/2700/1800 limits) are data-present (`contracts.json`) but never instantiated in the suite.
8. Mobile/export paths: block #16 pins `mobile_profile` tiers + touch UI button count; `prepare_mobile_project.py` texture-cap/ETC2 output and the Linux/Android export itself (`make linux-build`, `make android-*`) are outside the suite. `export_presets.cfg` untested.
9. `BPP_*`/sublevel future-proofing: blocks #19–#20 pin PeripheryA + CarUnderpass; any new packed actor or LevelInstance added by a future extract has no generic "every pending_li resolved" runtime check — only the parser-side counter.
10. `.godot` import determinism: no block asserts that all 995 GLBs import without error (see §5).

### 4.3 Flaky patterns (real, bounded)

- Wall-clock timers (2 sites): `run_tests.gd:113` `await create_timer(0.55).timeout` (door swing — tween 0.5 s + margin, reasonable but machine-speed dependent); `run_tests.gd:458` `await create_timer(0.15).timeout` (light-probe throttle 80 ms window vs 150 ms wait — 70 ms margin; slow CI can flake the `v3 >= v1` recompute check). No other `sleep`/`delay` in the file.
- Frame-count waits (bounded, correct pattern): `run_tests.gd:84-86` (`wait_frames < 240` for player+doors), `run_tests.gd:152-154` (`den_wait < 60`), `run_tests.gd:257-259` (`gh_wait < 240`), e2e `run_e2e_tests.gd:91+` settle harness + `e2e_tier4` `p2_wait < 80`. All are subscribe-then-await with caps (not bare sleeps) — the right pattern. Residual risk: caps are frame counts, so a headless software-GL run 10× slower than the 4070 Vulkan capture in `task-0.md` (§2: `Vulkan 1.4.357 - Forward+ - NVIDIA GeForce RTX 4070`) can hit the cap and fail closed rather than flake green. Fail-closed is the safe direction.
- Order dependence: blocks mutate shared autoloads (`gs.thief_id spider→moth→spider`, `gs.active_map_id old_manor→guildhall`, `mp_scr.set_force_mobile(true)→false`, `set_tier(0)→set_tier(1)`). Each block restores what it dirties today, but there is no save/restore fixture — inserting a block or reordering can cascade. Block #10 explicitly documents the hazard it guards ("Regression: simulate a stale GameState default … The contract's map preset must win").
- Tolerance style: mixed exact (`is_equal_approx` on 300.0/75.0), epsilon windows (`absf(...) < 0.001`–`0.2`), and count floors (`>= 281`). Floors ratchet only upward by convention; nothing prevents a future edit from lowering a floor to green a regression.
- E2E harness (`game/tests/e2e/run_e2e_tests.gd:12-24`): `_load_patched` reload path + comment that probe-tuned checks "stay FAIL and are documented" — a harness that can load patched scripts mid-run and that documents known-FAILs risks normalizing red. (Read 2026-11-20; exact known-FAIL set lives in that file's header comment.)

## 5. .godot import health for extracted GLBs

- Counts (2026-11-20): `find game/assets/ue -name '*.glb' | wc -l` = 995; `find game/assets/ue -name '*.glb.import' | wc -l` = 995 — every GLB has a sibling `.import` (1:1, no orphan GLB without import metadata). `game/.godot/imported/` holds 25190 entries; `game/.godot/` has no `*.log` files (no import log to mine — absence of evidence, not evidence of health).
- Total `.import` files under `game/assets/ue/` = 6086 (fonts, PNGs, OGGs, GLBs). GLBs are 995/6086 ≈ 16%.
- `mesh_materials.json` keys = 2054 vs on-disk GLBs under `game/assets/ue/` = 995. The gap is expected architecture, not loss: `mesh_materials.json` covers `extracted/assets/` (full 2054 incl. `Raw/`, anims, engine shapes) while `game/assets/ue/Content` is a curated/symlinked subset; plus `extracted/assets` holds `TAT/Content/` + `Engine/Content/` roots. But no check asserts the mapping "every `mesh_res` referenced by a shipped `*.tatlevel.json` exists under `res://assets/ue/`" — the runtime compensates with labelled fallbacks (box fallback in `loot_item.gd`, `missing mesh … skipping draw item` warnings — 9 such warnings in the `task-0.md` §2 live log: 2× `VFX_SkySearchLight_Mesh` + 4× `Cylinder` + 3× `Plane`, all pre-round-2) instead of a failing import gate.
- `.glb.import` staleness: `.import` files record source mtime + import params; re-exporting a GLB with different CUE4Parse conversion settings (`EMeshQuality.Highest`, `ETextureFormat.Png`, `exportMorphTargets: true` per `Exporter.cs:134-155`) without reimport leaves Godot rendering the stale imported mesh. `Makefile: extract` has no `reimport` step and `manifest_audit.py` does not compare GLB mtimes vs `.import` mtimes.

## 6. Ranked issue list

Conventions: P0 = data loss / silent drop (shipped content missing or wrong with no failing check). P1 = coverage gap (honest fallback, untested path, or validator blind spot that could become P0). P2 = hygiene (correctness-adjacent cleanup, determinism, debuggability). Each P0/P1 quotes the exact lines behind it.

### P0 — fix before next extract/test gate (5)

- **P0-1. Exporter allowlists silently drop nameless meshes/textures/materials.** `Exporter.cs:205` allowlist + `Exporter.cs:169-174` texture filter + `Exporter.cs:132` materials filter are closed sets with no dropped-file log. Evidence it already bit: round-2 `Coin_*/VFX_*/BasicShapes` (+9 GLBs). Any future asset outside the 6 mesh prefixes / `T_`-or-`/Textures/` rule drops the same way. Quote: `Path.GetFileName(p).StartsWith("SM_") || … || Path.GetFileName(p).StartsWith("Coin_") || p.Contains("/Meshes/") …` and `Path.GetFileName(p).StartsWith("T_") || p.Contains("/Textures/") …`. Fix: emit `skipped-by-filter` counts per command, or invert to deny-list.
- **P0-2. Overwrite-skip checks the wrong GLB path, counts skips as ok.** `Exporter.cs:209`: `if (!_o.Overwrite && File.Exists(OutPath("assets", f.Path, ".glb"))) { Count("meshes", true); continue; }` vs actual write root `extracted/assets/TAT/Content/<rel>.glb` (documented in round-2 `task-1.md` §2: "every unfiltered run re-exports all ~2000 packages"). Same at `Exporter.cs:123` (json) and `Exporter.cs:186` (textures). Every skip inflates `ok=`. Fix: check the real output path; count skips separately.
- **P0-3. `errors.log` truncation + cap + append rots the failure signal.** `Exporter.cs:69`: `static string Trunc(string s) => s.Length > 300 ? s[..300] : s;` with `Exporter.cs:53` 5000-entry cap and `Exporter.cs:307` `File.AppendAllLines(...)` (never rotated). Long UE chains are cut, worst incidents go message-less past 5000, and stale runs persist. Fix: no truncate (or 4 KB), no silent cap (spill to `errors-N.log`), truncate-not-append per run.
- **P0-4. parsers swallow corrupt levels with `continue` and no counter.** `parse_tables.py:1202-1208`: `try: exps = json.loads(jf.read_text()) except Exception: continue` (+ `if not isinstance(exps, list) or not exps: continue`, `if jf.name.startswith("BPP_"): continue`). A corrupt `Maps/*.json` vanishes from `levels/` with zero failing signal; `manifest_audit.py` cannot see it (§3.2). Fix: count + list skipped files, fail the normalize step on any skip.
- **P0-5. MID/slot-remap `""` slots lose "authored empty" vs "failed resolve" provenance.** `parse_tables.py:809-856` (`_component_override_paths`: `Preserves "" for None/unresolvable slots … Never invents values`) + `parse_tables.py:763-766` (10-sample cap). Interior `""` flows into `tatlevel.json` → runtime fallback order; the 11th distinct unresolved MID is unidentifiable. Fix: emit `null` for authored-empty vs `"UNRESOLVED:<ref>"` sentinel (or sidecar list), raise the sample cap, fail on growth.

### P1 — coverage gaps to close (9)

- **P1-1. `Packages()` TAT/-only gate + single-pak mount.** `Exporter.cs:32-35`: `f.Path.StartsWith("TAT/") … || f.Path.StartsWith("Engine/Content/BasicShapes/")`; `Program.cs:30-31`: `new DefaultFileProvider(Path.Combine(opt.Game, "TAT/Content/Paks"), SearchOption.TopDirectoryOnly, …)`. Quote above in §1.1. `/Engine/EngineMaterials/WorldGridMaterial` bind for the repaired VFX mesh is dangling proof. Fix: allow-list `/Engine/` material/texture deps or vendor them; warn on unmounted sibling paks.
- **P1-2. `Tables()` 9-root allowlist.** `Exporter.cs:135`: `var roots = new[] { "TAT/Content/Gameplay/", … "TAT/Content/Audio/" };`. Any table outside the 9 roots never reaches parsers, silently. Fix: log skipped-table count; add `Art/`+`ThirdParty/` or invert.
- **P1-3. `parse_materials` Tier-2/3 albedo guesses are unmarked.** `parse_materials.py:649-657`: `# 3) Category fallback: material/pkg/parent name mentions Brick/Stone/Wood/etc.` + `TOKEN_DROP` (`parse_materials.py:546`) + `CATEGORY_FALLBACK_STEMS` (`parse_materials.py:434`). A `MI_BrickTrim` can bind a generic brick texture with no `fallback_tier` in `materials.json`. Fix: record `albedo_source: authored|stem|ranked|category|none` per material; assert Tier-3 count does not grow.
- **P1-4. GLB-missing → sidecar-order fallback unmarked; degenerate-primitive filtering hides slot loss.** `parse_materials.py:80-118` (`return None … caller falls back to sidecar order`) + `Mapped 2054 … (2031 GLB-ordered, 23 sidecar-fallback)`. 23 sidecar-fallback entries are the visible tip; per-entry fallback bit is missing. Fix: per-entry `slot_order_source` field.
- **P1-5. Quest-loot generic/box fallback invariant is prose, not code.** `parse_loot.py:335-354` (`generic_quest_actor`, `unmapped_contract_tags`, `missing_mesh_quest_actors`, `"fallback never fires on shipped content"`). No `SystemExit` if a shipped tag unmaps post-reextract. Fix: assert `unmapped_contract_tags == []` for shipped tags.
- **P1-6. `parse_gameplay` hardcoded combat speed.** `parse_gameplay.py:374`: `"alerted_combat_fallback_m_s": 2.5,` with prose `sources.fallback`. Only non-`Fail`-closed value in an otherwise fail-closed file. Fix: read from source or pin with a test asserting `2.5 == BP_Guard_Base MaxWalkSpeed/100`.
- **P1-7. Spawner approximations untested at runtime; `assert` vanishes under `-O`.** `parse_spawners.py:307-311` (5 `NOT SERIALIZED` strings) + `parse_spawners.py:288,294` (`assert not missing …`). No `run_tests.gd` block asserts heal/refill/throw-speed/noise/walk-speed. Fix: runtime pins for the 5 constants; `raise SystemExit` instead of `assert`.
- **P1-8. `manifest_audit` gates mount, not pipeline.** `tools/manifest_audit.py:36-44` (`cov = resolved / …; if cov < args.min_coverage`) + `Makefile:38` (`--min-coverage 0.90`). `dumped` printed-not-gated; `errors.log` unread; `Engine/` outside `manifest_tat`; no generated-freshness check. Fix: gate per-stage dump counts, fail on `errors.log` non-empty for the current run, add generated-vs-extracted freshness check.
- **P1-9. Test blind spots: audio, saves, guard transitions, VFX look, 15/18 contracts, mobile/export.** §4.2 items 1–10. No single quote suffices; the evidence is absence across 3459 lines + e2e tiers. Highest-value adds: (a) instantiate all 18 contracts' maps at least to sublevel-load; (b) spawner/container/loot full-bucket runtime sweep; (c) save write/reload round-trip; (d) one audible-cue smoke test; (e) GLB-exists-for-every-`mesh_res` gate (closes §5 gap).

### P2 — hygiene (7)

- **P2-1. `Levels()`/`Anims()`/`Audio()` predicates mix domains.** `Exporter.cs:130` (`BPP_/SV_/S_/SS_/QG_` inside `Levels()`), `Exporter.cs:260` (`A_*` over-broad), `Exporter.cs:288-293` (`if (!e.ExportType.StartsWith("Ak")) continue;` uncounted). Split level-vs-blueprint discovery; count every `continue`.
- **P2-2. `parse_contracts` empty-map → `thieves_den` default.** `parse_contracts.py:62-80` (`return "thieves_den"` for empty/unknown). Correct for Contract 1, masking for any future empty path. Emit a warning listing defaulted contracts.
- **P2-3. `parse_interactables` `Value<=1` spawn-pool exclusion.** `spawn_pool` drops `Value 0/1`. A real `Value 1` item would vanish silently. Allow-list the known test item by key instead of by value.
- **P2-4. `parse_containers` closed 5-class dict.** `parse_containers.py:CLASSES` (5 entries). Add discovery + warn on unknown `*Container*/*Stash*/*DisplayCase*` BPs.
- **P2-5. VFX `GRAPH_HEAVY` constants + undecoded graphs.** `parse_vfx.py:31-32` (`18`/`72`). Recompute percentiles per run or document drift review; record `parameter_defaults: unknown (ParameterData not decoded)` explicitly per system.
- **P2-6. Test wall-clock margins + shared-mutable-autoload ordering.** `run_tests.gd:113` (0.55 s), `run_tests.gd:458` (0.15 s vs 80 ms window), frame caps `240/60/240/80`, in-place `gs/mp_scr` mutation without fixtures. Widen the 150 ms margin, add save/restore fixture for autoloads.
- **P2-7. Symlink + `.import` staleness + no reimport step.** `game/assets/ue/Content → extracted/assets/TAT/Content` symlink + 995 `.glb.import` files with no `make reimport`; `Makefile: extract` → parsers with no freshness manifest recording which `extracted/` snapshot produced which generated file. Add `generated/_manifest.json` (extracted git-hash/mtime per output) + `godot --import` step.

## Counts

- P0 (data loss / silent drop): **5**
- P1 (coverage gap): **9**
- P2 (hygiene): **7**
- Total: **21**

## What was re-opened to verify each claim

Every `file:line` above was read in-session 2026-11-20: `Exporter.cs` (full 311 lines), `Program.cs` head, `manifest_audit.py` (full 49 lines), `Makefile` (full), `run_tests.gd` blocks #1–#37 + timer/wait greps, `parse_tables.py` §§240–360/700–880/1190–1330/1830–2050/2160–2360/tail, `parse_materials.py` docstring + `434/546/605–657/984–1018`, `parse_loot.py` docstring + `37–44/103–126/157–213/282–354`, `parse_spawners.py` docstring + `193/267–294/306–311`, `parse_gameplay.py` docstring + `26–56/360–420/486–534/587`, `parse_contracts.py` `48–130`, `parse_containers.py` `107–130`, `parse_interactables.py` `74–130/tail`, `parse_vfx.py` `1–40/334–343/392`, `parse_weather.py` docstring + `473+`, `map_weather.json` head, `mesh_materials.json` key count (2054), GLB/`.import` counts (995/995), `.godot/imported` entry count (25190), round-2 `task-0.md`/`task-1.md` §§1–3, ground-truth `backlog.md` (F1–F14 index).
