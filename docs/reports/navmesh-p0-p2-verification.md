# Navmesh N-P0/N-P1/N-P2 — independent lane verification (2026-11-27)

| | |
|---|---|
| lane | `wave/navmesh-p0-p2` at `82952dd` (base `a1c3597`) |
| worktree | `/home/john/.local/share/opencode/worktree/318f41/phase2-navmesh` |
| scope | read-only verification of plan §5 N-P0/N-P1/N-P2, the lane report, the commit/diff and the measured evidence |
| method | Python/shell only; the extractor dump under `/tmp/opencode/nav-p0/nav` was re-parsed, the 80-link geometry was re-measured with an independent polygon-distance implementation, the 80 door groups were re-derived from the exact 15-file Guildhall sublevel set, and the committed code/docs were read line by line. **No Godot, no Vulkan/Xvfb, no Steam, no GPU process.** |
| verdict | **PASS (conditional)** — the code, producer output, 80/64/4 links, 35/45 split, 42/38 door links, 70-check probe, 218/324/M2 gates, 7/7 producer tests, smoke and no-push/scope claims are reproduced. **One merge-blocking documentation fix:** `RC_NULL_AREA` is **0**, not 63 (`RC_WALKABLE_AREA` is 63), in three current docs. **One N-P3 risk to record:** 43 of Guildhall's 45 one-way links have an opposite-direction parallel copy that the producer's exact-pair direction census ignores (Old Manor 45/49, FTUE 4/4). |

The lane is off by default (`TAT2_NAV` absent/`off`); no player-visible navigation changes at HEAD unless the env var is set.

---

## 1. N-P0 — extractor, producer, compact asset

### 1.1 The extractor diff

`tools/tat-extract/Exporter.cs`:

- deletes the previous JSON before decoding (`:557`), so a failed run cannot leave stale data for `parse_nav.py`;
- reads `SupportedAreas` from the generic property tags (`:618–646`) and emits `{id, class}` entries; the class is accepted as `StrProperty` or `NameProperty` (the typed reader exposes no member in CUE4Parse 1.2.2);
- reads `NavDataConfig` (`:648–664`) and emits `agent_radius_cm` / `agent_height_cm` / `agent_step_height_cm`; the top-level `agent_*_cm` fields now prefer the authored config over the `0.0` typed members (`:810–817`);
- refuses a ground polygon with more than 6 vertices (`:690–697`, `Detour max is 6; refusing to clamp`) instead of the old `Math.Min(VertCount, 6)`, and emits `max_poly_verts` (`:836`);
- keeps the previous tile/cache totals and the `poly_count_total` / `offmesh_connection_total` contract.

Verified against the extractor dump that produced the committed numbers: `/tmp/opencode/nav-p0/nav/Maps/{Guildhall,OldManor,FTUE}/*.json` all carry `schema=tat2.nav_tiles/1`, `supported_areas` (8 entries, `63=NavArea_Default`), `nav_data_config` `45/240/45`, and `max_poly_verts=6`. The Guildhall cache is 2,302,750 B with `2958/2958` decompress OK; Old Manor 1,279,995 B / `1469/1469`; FTUE 1,018,865 B / `1558/1558`. The `.cache.bin` file sizes match the JSON fields exactly.

### 1.2 `tools/parse_nav.py` — reproduced byte-for-byte

Command (writes only to `/tmp`):

```bash
python3 tools/parse_nav.py \
  --input /tmp/opencode/nav-p0/nav \
  --out /tmp/opencode/verify-nav-out
```

Output:

```text
NAV_MAP guildhall: tiles=2958 polys=14709 verts=30918/40126 offmesh=221->123pairs->80 links (bidirectional=35 one_way=45) max_poly_verts=6 areas=8 bin=518220B
NAV_MAP old_manor: tiles=1469 polys=9059 verts=17643/22865 offmesh=216->113pairs->64 links (bidirectional=15 one_way=49) max_poly_verts=6 areas=8 bin=302902B
NAV_MAP ftue: tiles=1558 polys=5576 verts=11711/16483 offmesh=11->8pairs->4 links (bidirectional=0 one_way=4) max_poly_verts=6 areas=8 bin=195358B
NAV_MANIFEST /tmp/opencode/verify-nav-out/manifest.json maps=3
```

The four outputs are byte-identical to the lane's `/tmp/opencode/nav-gen`:

```text
75d8ffb0bb169ef74be05acaa1c8ecaac8a5ab717aafeab57cf27ef428266c04  ftue.nav.bin
e5c38741b2675342a69f55fb0660a61be6d38e8bf024eed1c6135473518a9dc8  guildhall.nav.bin
ebbc4782df2c01dd3a603d063a298ab467370ed7035a60d374718d7c539b3b59  old_manor.nav.bin
fc15cc5806116aecb025f61017d8bf6868bd939d3a8f7bbc0c3185cd2edb8830  manifest.json
```

The manifest was independently checked field by field: tiles/polys/authored polys/verts/authored verts/raw/pairs/links/bidir/one-way/bin bytes match the report §1–2 and the probe constants. The 30,918/17,643/11,711 dedupe counts were also recomputed directly from the raw tile arrays (all emitted vertices, exact centimetres) and match. The authored totals equal the emitted arrays exactly (40,126 / 22,865 / 16,483), so the `authored_verts` field is not a subset count.

Fail-closed rules confirmed in code and by `build/qa/test_parse_nav.py`:

- `supported_areas` required; `63` must be `NavArea_Default` (`parse_nav.py:128–155`);
- `nav_data_config` required with positive radius/height (`:158–168`);
- ground poly 3..6 only; 7+ and <3 refused (`:229–235`);
- area 0 refused; area not in `SupportedAreas` refused; `DT_POLYFLAGS_DISABLED` refused (`:243–255`);
- `poly_count_total - offmesh_connection_total == walkable polys` (`:261–271`);
- off-mesh records must equal the declared total (`:305–307`).

`python3 build/qa/test_parse_nav.py` → **7/7 PASS** (`positive merge + per-map areas`, missing `supported_areas`, area 63 not Default, 7-vertex poly, `NavArea_Null`, missing `nav_data_config`, one-way direction preserved). This is the report's `parse_nav 7/7`.

The 7+ vertex extractor refusal itself is not exercised by a real malformed asset (the authored data maxes at 6); it is verified by code inspection plus the producer test's 7-vertex refusal and the `max_poly_verts` field.

### 1.3 The counts

| item | verified value |
|---|---|
| Guildhall tiles / walkable polys / deduped verts | **2,958 / 14,709 / 30,918** (authored 14,930 polys / 40,126 verts) |
| Guildhall raw off-mesh -> exact pairs -> logical links | **221 -> 123 -> 80** |
| Guildhall links bidirectional / one-way | **35 / 45** |
| Old Manor | **1,469 / 9,059 / 17,643**; **216 -> 113 -> 64**; **15 / 49** |
| FTUE | **1,558 / 5,576 / 11,711**; **11 -> 8 -> 4**; **0 / 4** |
| binary bytes | **518,220 / 302,902 / 195,358** |
| radius/height census (Guildhall) | **203 x (100/100), 18 x (30/60) = 221** |

The 221 raw records all carry flag 64, confirming the report's "never from the raw flags" rule.

### 1.4 Areas and the 63 trap

Manifest area tables (all 8 classes present per map):

| map | Default 63 | Obstacle 1 | LowHeight 62 | PrivateArea 2 | Bushes | Door |
|---|---:|---:|---:|---:|---:|---:|
| Guildhall | 14,558 | 7 | 0 | 0 | **3** (144) | **4** (0) |
| Old Manor | 8,874 | 0 | 0 | 0 | **4** (185) | **3** (0) |
| FTUE | 5,575 | 1 | 0 | 0 | **3** (0) | **4** (0) |

The parser requires `63=NavArea_Default`, refuses area 0, and the runtime rejects a binary whose poly area byte is 0. This matches report §3 and the probe (`area 63 is NavArea_Default`, `8 authored supported areas`).

**Finding F1 (documentation, merge-blocking).** Three current docs say Recast's `RC_NULL_AREA` is 63:

- `docs/HANDOFF_NEXT_AGENT.md:278–279`
- `docs/reports/next-phases-plan-20261127.md:49`
- `docs/reports/navmesh-spike.md:84`

That is false. Recast's own header defines `RC_NULL_AREA = 0` and `RC_WALKABLE_AREA = 63` (Recast.h; the same values the producer relies on: area 0 is null, 63 is Default/walkable). The correct sentence is "`NavArea_Default=63` is walkable; `NavArea_Null`/`RC_NULL_AREA` is 0, so never treat 63 as null." The code (`parse_nav.py`, `nav_runtime.gd`) and the lane report §3 are correct; only the three doc rationales are wrong.

---

## 2. N-P1 — the runtime region

`game/src/ai/nav_runtime.gd` (218th checked script) was read in full:

- `TAT2_NAV` is truthy only for `on`/`1`/`true`/`yes`; absent is off (`:88–90`). `TAT2_NAV_DIR` overrides the asset root (`:99–101`). Default off.
- `setup()` builds one `NavigationMesh` + one `NavigationRegion3D`, sets vertices/polygons without baking, and applies `cell_size=0.01`, `edge_connection_margin=0.05`, `link_connection_radius=1.0` **before** the region enters the map (`:148–173`). It checks magic/version/vertex/poly/link ranges, poly 3..6, area 0, trailing bytes (`:453–531`) and manifest/binary poly+vertex counts (`:135–146`).
- `wait_ready()` requires an iteration id > 0, at least one region, and a mesh point within 1 m of the first-poly centroid (`:201–224`); 300-frame fail-closed ceiling.
- `register_swinging_doors()` groups the real `swinging_doors` nodes by `door_entry.actor`, averages leaf pivots, averages `basis.z` with sign alignment, uses ±2.2 m endpoints, snaps, and skips the whole door if either snap is >2.5 m (`:232–303`). It enables a link only while every leaf reports `open_angle_deg() > 70` (`:324–332`).
- `clear()` frees every baked link, every door link and the region; called at `start_contract()` and `_exit_tree()` (`mission_controller.gd:818`, `:5354`; `nav_runtime.gd:346–368`).
- `setup()` does **not** compare the manifest `links` field with the binary `link_count`; it compares polys and verts only. A corrupted link count would build. This is a minor robustness gap (F3), not a defect in the shipped asset (producer writes both 80).

`mission_controller.gd` order is exactly as reported: `_spawn_swinging_doors(ue_level_data)` (`:937`) → `await _start_nav_runtime(map_id)` (`:938`) → guards/loot (`:942` onward). The Den branch stays before `_setup_thieves_den_hub`/`_spawn_guards` and `_start_nav_runtime` returns `skipped` for `thieves_den` (`:4661–4690`). The smoke log's `NAV_RUNTIME` line is printed before `TAT-2 mission_ready` (line 105 vs line 132 of `/tmp/tat2-smoke-E8lupz.log`), so guards spawned after the region was ready.

### 2.1 Runtime probe and smoke (lane logs, not committed)

The probe log `/tmp/opencode/nav-probe5.log` is bound to the committed tree by its own line references: the missing-asset warning trace ends at `nav_runtime.gd:578`, `nav_runtime_probe.gd:294` and `:343`, which are the exact committed lines. Its final line is:

```text
NAV_RUNTIME_PROBE checks=70 fails=0
PROBE_EXIT=0
```

It includes: 8 areas / 63 Default / 45-240-45 config; 14,709 polys / 30,918 verts; 80 links / 35 bidir / 45 one-way; map cell 0.01 / margin 0.05 / link radius 1.0; the 3-waypoint 4.15 m doorless path; the prison off/on; the far-door skip; `clear()`; `TAT2_NAV=off`; missing assets; and the Old Manor/FTUE asset builds (9,059/64/15 and 5,576/4/0).

The real free-play smoke logs (`/tmp/tat2-smoke-E8lupz.log`, `/tmp/tat2-smoke-ReVhaq.log`) contain:

```text
NAV_DOORS groups=80 links=42 skipped=38 open_now=0
NAV_RUNTIME map=guildhall state=ready ready=true polys=14709 verts=30918 links=80 bidir=35 oneway=45 door_links=42 door_skipped=38 build_ms=30 ready_frames=57 ready_ms=865
...
TAT-2 mission_ready map=guildhall meshes=64682 lights=160 chunks=6337
```

and the second run has `build_ms=29 ready_frames=79 ready_ms=1215`. Both wrapper summaries are `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 mission_ready=1`; the wrapper uses `tools/godot --headless` (`build/qa/runtime_smoke.sh:37`), so no GPU. The exact load range is **ready_ms 865–1215 (0.865–1.215 s)**, or **0.894–1.245 s including build_ms 29–35**; report §8's "0.9–1.2 s" is a rounded range, not a contradiction (F4, minor).

### 2.2 Independent geometry checks (no Godot)

I reimplemented point-to-triangle distance over the exact producer binary and checked every baked link:

- **155/160 endpoints within 2.5 m** and **79/80 links with at least one side on the mesh** — exactly the probe's `NAV_LINKS endpoints_near=155/160 links_with_side=79/80`;
- the only link with **both** sides off is **`NavLink_71`**, `a=(1950,-500,5800) -> b=(2250,-500,5800)` raw (3.0 m), **6.37 m / 6.06 m** from the mesh — exactly the report's "authored 3 m drop, both endpoints ~6 m off";
- the next-worst one-sided endpoints are `NavLink_50` 2.66 m, `NavLink_54` 2.65 m, `NavLink_29` 2.55 m, which explains the 155/160 count without a second broken link.

I also re-derived the door links from the exact 15-file Guildhall sublevel set (`Building_Guildhall_POI`, `_3rdFloor`, `Guildhall_Vault_CeremonialChambers`, `Guildhall_Geometry`, `Guildhall_PeripheryA`, plus the other 10 loaded files with 0 door records): **155 door records, 80 distinct actors**, and with the same midpoint/normal/±2.2 m/snap-2.5 m rule: **42 links, 38 skipped**. This exactly matches the smoke's `80/42/38` and confirms the report's "38 skipped by the 2.5 m snap" is the fail-closed result, not a missing data path. The closest skipped actor is `StaticMeshActor_3764` at **2.76 / 2.64 m** (the next two are 2.86/2.81 and 2.97/1.23), so the 2.5 m rule is exact but the 42/38 split is threshold-sensitive for a handful of near-boundary actors — it must not be widened silently (the report's own warning).

The prison test is also reproducible from the raw data: the baked off-mesh records `(-2.5, 36.5, -64.4) -> (0.5, 36.5, -64.4)` are a one-way -X→+X link across the prison doorway; the probe's east→west path stops **1.33 m** short with the door link off and reaches **0.00 m** with it on. The probe log records `NAV_PRISON off ... reach=1.33` and `NAV_PRISON on ... reach=0.00`, plus `NAV_DOOR_PATH ... waypoints=3 length_m=4.15`.

---

## 3. Gates and evidence

| gate | lane log | verified |
|---|---|---|
| compile | `/tmp/opencode/nav-final-compile-m2.log:3` — `scripts checked: 218, broken: 0` | 218 `.gd` files under `game/` at HEAD; the count matches. This is +1 over the 217-gate baseline because of `nav_runtime.gd`; the 217 floor is untouched. |
| `run_tests` | `/tmp/opencode/nav-run-tests.log:2930` — `SUMMARY: fails=0`; 324 `^PASS` lines; suites 121 | 324 PASS lines; no new suite; consistent with the 324 baseline. |
| M2 | `/tmp/opencode/nav-final-compile-m2.log:92` — `M2_SUMMARY: fails=0`; 12 `PASS: M2` lines | 12/0. |
| `parse_nav` | `build/qa/test_parse_nav.py` | **7/7 PASS**, reproduced locally (no Godot). |
| probe | `/tmp/opencode/nav-probe5.log:117` — `checks=70 fails=0` | exact; bound to the committed code by line references; geometry independently re-measured. |
| smoke | `/tmp/opencode/nav-runtime-smoke*.log` — `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 ... mission_ready=1` | exact; actual Godot log has the NAV lines before `mission_ready`; headless wrapper. |
| `make audit` | not re-run (outside this read-only verification scope) | report §6 says expected producer/baseline drift only + missing `vgmstream`; no committed audit log exists in this commit. The integrator's re-stamp remains required. |

**Evidence scope note.** These gate logs are lane-local under `/tmp`; the commit does **not** add `docs/reports/logs/nav...`. That is expected: the plan makes the 46th probe gate part of N-P3 and the integrator's full serial set. The lane report correctly says the integrator must regenerate, re-stamp and run the full set. Nothing here is in the committed 45-gate ratchet, so no floor moves.

---

## 4. Risks in report §8 — verification

| risk | verdict | evidence |
|---|---|---|
| `NavLink_71` one-way drop, both endpoints ~6 m off mesh | **CONFIRMED** | independent geometry: 6.37/6.06 m; link is 3.0 m; `155/160`, `79/80` exactly as probe. |
| one-way prison baked link can cross a closed door | **CONFIRMED** | raw records `(-2.5,36.5,-64.4) -> (0.5,36.5,-64.4)` (-X→+X), flag 64; the probe only tests east→west (the door-link direction). The baked direction remains enabled. Report is right to leave it to N-P3. |
| 38 skipped door links, windows/outside-nav rooms | **CONFIRMED** | exact 155-record/80-actor re-derivation gives 42/38; skipped actors include windows and `BP_Prison_WallA_DoorwayA` (4.32/3.59 m). |
| no Old Manor/FTUE doorway/path/door-link test | **CONFIRMED** | probe builds 9,059/64/15 and 5,576/4/0 assets only; no path on those maps. |
| load +0.9–1.2 s | **CONFIRMED (rounded)** | smoke `ready_ms=865` and `1215`, `build_ms=29/30`; exact 0.865–1.215 s ready (0.894–1.245 s incl. build). |
| no GPU/parity claim | **CONFIRMED** | all Godot invocations are `--headless`; no Xvfb/Vulkan/Steam in the lane logs. |
| multi-floor / one region | **CONFIRMED** | one region, all 14,709 polys; no per-floor split. |

### 4.1 Additional risk not in §8 — the 35/45 split drops reverse directions

The 35/45 split is exactly what the producer writes and the probe checks, but it is **not** the full authored direction set. In `tools/parse_nav.py:398–404`, `dir_ba` counts only records whose endpoints are exactly `(b, a)` on the **canonical** exact pair. The merge step (`:363–379`) also folds parallel copies at <=150 cm; those copies can carry the opposite direction at a different position. Counting direction across the whole cluster instead gives:

| map | exact-pair bidirectional | producer (canonical) bidirectional | one-way links with an opposite-direction parallel copy | truly one-way |
|---|---:|---:|---:|---:|
| Guildhall | 35 | 35 | **43** | 2 |
| Old Manor | 15 | 15 | **45** | 4 |
| FTUE | 0 | 0 | **4** | 0 |

Example (Guildhall, tile `(-10,-1)`): `(-9300,1850,-930)->(-9600,1850,-930)` and `(-9600,1850,-860)->(-9300,1850,-860)` are 70 cm apart, one each direction; the producer merges them into one cluster and keeps only one direction because the reverse is not the exact canonical pair. The merge's own code comment says "the merged copies carry the other direction; count the whole cluster", but the implementation does not count parallel-copy directions. If the 150 cm merge is meant to collapse one physical link, 43/45/4 of these one-way links should be bidirectional; if the parallel copies are distinct lanes, the merge itself combines two links. Either way, the report's "35/45" needs a label as a **merge/port decision**, and the report's §8 should record the one-way-direction risk. This is the largest fidelity risk in the lane; it is dormant while `TAT2_NAV=off`, so it is an N-P3 decision/test, not a blocker for this off-by-default lane.

---

## 5. No push / scope / hygiene

- `git status --short` in the worktree is clean before this verification file; the only untracked file after writing is this report.
- `git rev-list --count origin/main..HEAD` = **1** (the lane commit); `git branch -r --contains 82952dd` is empty — **not pushed**.
- Parent is `a1c3597`; the branch is one coherent commit.
- Commit files: 15 (AGENTS, Makefile, 2 build/qa nav scripts + producer test, 6 docs, `nav_runtime.gd`, `mission_controller.gd`, `parse_nav.py`, `Exporter.cs`). **No** `extracted/`, `game/assets/ue/`, `game/data/generated/` or `.godot/` paths are in the commit.
- The worktree's `extracted` and `game/data/generated` are symlinks to the main checkout; the lane's nav asset is in `/tmp/opencode/nav-gen`, not in the shared generated tree. No data regeneration in the main checkout.
- No GPU/Steam process: the probe and smoke are `--headless`; this verifier ran no Godot at all.
- Minor doc staleness: `docs/reports/final-20261127.md:360` still says "**No runtime navigation change** ... The next lane is the P1 Detour consumer" while the same commit lands that consumer. The section is historical (P2-NAV spike at `3809b4d`), but a "(superseded by N-P1)" note would avoid confusion (F5, minor).

---

## 6. Findings and required actions

| id | severity | finding | action |
|---|---|---|---|
| F1 | **merge-blocking doc** | `RC_NULL_AREA` is **0**, not 63; `RC_WALKABLE_AREA` is 63. The false claim is in `HANDOFF:278–279`, `next-phases-plan:49`, `navmesh-spike:84`. Code and the N-P0 report are correct. | Fix the three sentences before merge. No code change. |
| F2 | **N-P3 risk** | 43/45/4 of the one-way links have an opposite-direction parallel copy that the exact-pair census ignores; the 35/45 split is a merge decision, not the full authored direction set. | Record in report §8 and decide/test in N-P3 (both directions, guard trajectory). The lane is off by default, so this does not block the merge. |
| F3 | minor | `nav_runtime.setup()` checks manifest poly/vertex counts but not manifest `links` vs binary `link_count`. | One-line check; not needed for the shipped 80-link asset. |
| F4 | minor | "0.9–1.2 s" rounds the measured 0.865–1.215 s ready (0.894–1.245 s incl. build). | Quote the exact range if the number is reused. |
| F5 | minor | `final-20261127.md:360` historical "No runtime navigation change / next lane is P1 Detour" is stale at HEAD. | Optional "(superseded by N-P1)" note. |

**No blocking code, runtime, probe or gate defect was found.** The 218/0 compile, 324/0 run_tests, 12/0 M2, 7/7 parse_nav, 70/0 probe and smoke are consistent with the committed code and the independent reproductions above. The required merge fix is documentation-only (F1); F2 is a producer-merge semantics risk the next nav wave must own.

---

## 7. Verdict

**PASS (conditional).** N-P0/N-P1/N-P2 meet the plan and the report's measured claims; the 221→123→80 / 216→113→64 / 11→8→4 links, 35/45, per-map areas, 63=Default, 2,958/14,709/30,918, 42/38 door links, prison 1.33→0, 70-check probe, 218/324/M2/7/7/smoke, no-push and scope are all verified. Merge after the F1 doc correction; carry F2 into N-P3 and record it in the lane report's risks.

Verifier limitation: no Godot run was performed (by instruction), so the compile/run_tests/M2/probe/smoke numbers are the lane's `/tmp` logs bound to the committed code by format and source-line references, not a fresh engine run. The producer and link geometry were independently reproduced without Godot.
