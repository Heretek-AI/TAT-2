# Task P0-T10 evidence — extractor reports honestly

Date (UTC): 2026-11-20. Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md`
(T10) + lane report `audit-pipeline.md` (P0-1/P0-2/P0-3). Build: HEAD `b5b3588`
plus this task's `tools/tat-extract/Exporter.cs` edit (only tracked edit).
`dotnet build tools/tat-extract -c Release` (SDK 10.0.404) → `0 Error(s)`.

Scope kept: no conversion setting touched (`DefaultOpts`/`AnimOpts`
byte-identical), no allowlist widened, no extra asset queued — every predicate
kept its old accept set; only counting/reporting changed. `make test` not run
per task rule; verify is exporter runs + file re-reads.

## 1. Code fix (only tracked edit: `tools/tat-extract/Exporter.cs`)

- **Real skip path (meshes):** new `RealMeshPath()` =
  `<out>/assets/<full game path>.glb` (e.g. `assets/TAT/Content/...Coin.glb`),
  matching where `ExportSession` actually writes. Old check tested the
  `OutPath()`-stripped location (`assets/Art/...`) that is never written, so
  it never hit (round-2 `task-1.md` §2: every unfiltered run re-exported all
  ~2000 packages). `DumpJson` (json/tables/levels/materials) and `Textures`
  skip checks already tested their real write paths — kept, only recounting
  changed.
- **Separate skip counters:** new `_skip` dict + `CountSkip()`; overwrite-skips
  and allowlist drops no longer `Count(kind, true)`. `Report()` prints
  `ok=/skip=/fail=` per kind; `ok=` now means "exported now".
- **Skipped-by-filter counts + documented deny-lists:** `Tables()` /
  `Levels()` / `Materials()` / `Textures()` / `Meshes()` each count
  `candidates − queued` as `<kind>-filtered` and carry a comment naming the
  exact allowlist/deny-list that drops them (unchanged semantics).
- **Per-run untruncated error log:** `Trunc(300)` deleted (zero remaining
  `Trunc` refs), 5000-entry silent cap removed (all failures enqueued),
  `File.AppendAllLines` → `File.WriteAllLines` (truncate, never append), plus
  stale `errors.log` is deleted when the run is clean. `DumpJson` now takes
  the command kind, so `tables`/`levels`/`materials` no longer masquerade as
  `json` in the report.

## 2. Before behavior (from ground truth, not re-measured)

- `Exporter.cs:209` (old): skip check on stripped path → never hit;
  every skip counted `Count("meshes", true)` → `ok=` mixed fresh/skipped.
- `Trunc(300)` + `_errors.Count < 5000` + `AppendAllLines` → cut, capped,
  ever-growing `errors.log`.
- Allowlist drops (`Exporter.cs:205`, `:169-174`, `:132`, 9 tables roots)
  had no counter at all.

## 3. After — bounded re-runs (new binary)

`tables --filter 'DT_Contracts_1_to_16' --out /tmp/tat-verify/t2` (fresh dir):

- `tables finished 1` → `[tables] ok=1 skip=0 fail=0`, JSON written.

Same command re-run (file present):

- `[tables] ok=0 skip=1 fail=0` — skip on the real write path, not counted ok.
- Stale-log check: planted `errors.log` containing `STALE-JUNK-FROM-PRIOR-RUN`
  before the re-run; after the clean run the file is **gone** (per-run log,
  truncate-not-append + clean-delete).

`meshes --filter 'Coin_Bronze' --out /tmp/tat-verify/m1` (fresh dir):

- `queuing 1 mesh packages...` → `[meshes] ok=1 skip=0 fail=0`,
  GLB at `m1/assets/TAT/Content/Art/Gameplay/Loot/LootMinor/Coins/Coin_Bronze.glb`
  (real path — matches `RealMeshPath`, not the old stripped path).

Same command re-run (GLB present):

- `[meshes] ok=0 skip=1 fail=0` — old code would have re-exported here
  (stripped path never exists) and reported `ok=1`.

`tables --filter 'Coin_' --out /tmp/tat-verify/t3` (deny-list demo):

- `tables finished 0` → `[tables-filtered] ok=0 skip=3 fail=0`
  (3 coin `.uasset` under `Art/`, outside the 9 tables roots — counted, not
  silently dropped).

Code-level: `grep` confirms zero `Trunc` refs, zero `5000` cap, zero
`AppendAllLines`; `CountSkip`/`RealMeshPath`/`WriteAllLines` all wired.
This file re-read from disk after writing (done).
