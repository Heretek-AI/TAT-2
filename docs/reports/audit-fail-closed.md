# Audit fail-closed hardening (2026-11-24)

Follow-up to [`audit-content-gate.md`](audit-content-gate.md). The first content
gate still trusted a gitignored baseline, never compared output hashes, counted
Godot `.import` sidecars as extracted assets, accepted metadata-only tables and
did not bind `errors.log` to the extraction run.

## What changed

- **Tracked baseline.** `tools/audit_baseline.json` records each producer's
  sha256, every output path as `{files, bytes, sha256, newest_mtime}`, the
  content metrics, infrastructure hashes (Makefile, `tools/tat-extract/*`, helper
  scripts), and external tool versions. Normal runs compare all of them.
  Missing/decreased/empty outputs fail. Output content changes fail until
  `make audit-refresh-stamps`; a normal first run with no baseline fails and
  `make audit-bootstrap` is the explicit creation path.
- **Refresh validates regeneration.** `--refresh-stamps` refuses missing or
  decreased outputs and only accepts a changed producer when every output is
  newer than the producer or its hash/count changed. Corrupt baselines can be
  rebuilt with `--refresh-stamps`.
- **Tracked allowlists.** `tools/audit_allowlists.json` names the 73 known
  case-only payload normalizations, the 33 case-only `.ubulk` companions and 46
  manifest paths with no physical extraction artifact. Exact-case parity and
  disk-backed coverage are gated; new misses fail.
- **`.ubulk` companions** are checked separately: all 4,088 manifest entries
  must be present in `filelist.txt` (case-insensitive), with only the 33 known
  case differences allowed.
- **Stage payload.** `.import`, `.uid`, `.translation`, `.md5` and hidden files
  do not count. The assets floor is 6,500 payload files (measured 6,659; 4,592
  sidecars excluded). Godot imports are an opt-in `--require-imports` /
  `make audit-imports` gate.
- **Content is parsed, not trusted.** All 144 table JSONs need non-empty
  `rows`/`entries`; 995 animation GLBs, 5,018 audio OGGs, 1,507 referenced
  textures, 15 videos and 8 localisation CSVs must exist and be non-zero.
  `mission_loot_goals` must equal
  `{"Mission.Guildhall.LootTheRoom": [4000, 6000, 8000]}`.
- **`errors.log` run marker.** `tools/tat-extract/Exporter.cs` now always writes
  `# run <utc> filelist <sha256> errors <n>` before failure lines and never
  deletes the file. The audit requires the marker to match the current
  `filelist.txt` and body count. Zero-byte logs fail; whitespace-only legacy
  logs are treated as clean.
- **Path args everywhere.** `--extracted/--generated/--assets/--steam` drive
  producer outputs, freshness and content checks; `--baseline/--allowlists`
  drive the baseline.
- **Fail-closed defaults.** Coverage/parity default to 99 %; staleness and
  unexpected error lines fail. Explicit opt-outs: `--allow-stale`,
  `--allow-unexpected-errors`, `--allow-tool-drift`.
- **Negative-control suite.** `python3 tools/test_manifest_audit.py` builds a
  complete temporary tree and exercises 14 control groups.
- **Clue/quest/device producers.** `parse_clues.py` (`gameplay/clues.json`),
  `parse_quests.py` (`gameplay/quests.json`) and `parse_devices.py`
  (`gameplay/devices_runtime.json`) are registered in `NORMALIZERS` and in the
  baseline with their output bytes/counts/hashes. Removing any of those files
  fails the gate; `tools/check_devices_runtime.py` reports 58,512 checks.
- **Stable tool probes.** A missing executable records `"missing"` without being
  invoked. Present tools are reduced to a stable version line (`Blender 5.3.0`,
  `ffmpeg version 9.0.2`, `vgmstream CLI decoder r2168 (Oct 25 2026)`,
  `10.0.404`); usage text is never recorded.

## Evidence

`make build-extractor`: succeeded, 0 errors (15 pre-existing warnings).

`python3 tools/test_manifest_audit.py`:

```
ok bootstrap + normal
ok missing baseline fails then bootstrap
ok missing producer output
ok empty tables and loot goals
ok missing/zero assets
ok import gate and missing translations
ok import-only assets fail / extraction-only assets pass
ok producer drift
ok corrupt baseline + refresh
ok refresh refuses missing output
ok refresh refuses unregenerated outputs
ok errors.log missing/stale/zero/whitespace
ok case-only loss and .ubulk loss
ok disk-backed coverage
PASS: 14 control groups
```

`make audit` on the repaired tree:

```
Manifest TAT entries: 16792 (12703 payload, 4088 .ubulk, 1 pak)
Mount/path consistency (case-insensitive, pak excluded): 12703/12703 (100.0%)
Case-sensitive parity: raw 12630/12703 (99.4%), allowlisted 73/73, unexpected 0; effective 100.0%
Disk-backed coverage: 12657/12703 (99.6%), allowlisted missing 46, unexpected 0
UBULK companions: 4088 manifest, 0 case-insensitive missing, 0 unexpected exact-case missing
stage assets: 6659 payload files (min 6500, 4592 importer/sidecar files excluded)
godot-import (separate gate): 10677 .import sidecars, 8 .translation files
content levels: OK   files=107, min=107, invalid=0
content contracts: OK   entries=16, expected=16, loot_goals=True
content tables: OK   files=144, min=144, invalid=0
content materials: OK   entries=1629, min_entries=1620, with_albedo=1379, min_albedo=1370, texture_refs=1507, missing_textures=0
content containers: OK   records=254, min=250, classes=5
content decals: OK   records=675, min=670
content devices: OK   total=4118, expected=4118, families=21, expected_families=21, family_sum=4118
content animations: OK   ok=995, min_ok=995, fail=0, entries=995, total=995, glb=995, zero_glb=0
content audio: OK   clips=5018, min_clips=5018, failed=0, failure_records=0, ogg=5018, zero_ogg=0
content localization: OK   csv=8, expected=8, empty=0
content videos: OK   ogv=15, manifest=15, expected=15, zero_ogv=0
content scene_variants: OK   count=222, records=222, expected=222
content niagara: OK   records=3695, min=3695
baseline: matches tools/audit_baseline.json
AUDIT PASS
```

Manual negative controls (all reverted): removing
`gameplay/loot_actors.json` fails on both the missing producer output and the
`gen:gameplay` count decrease; writing `{}` to a table fails
`tables: 1 JSON files have no rows/entries`; setting `mission_loot_goals = {}`
fails the expected map. The automated suite covers the remaining controls.

## Residuals

- `tools/audit_baseline.json` must be refreshed after a legitimate generated-data
  regeneration; a parallel worker changing shared generated data will make a
  normal audit fail until the baseline is refreshed and committed.
- Blender (`5.3.0`) and FFmpeg (`9.0.2`) are recorded in the baseline; vgmstream
  was not installed and is recorded as `missing`. Installing or upgrading any
  of them fails the audit until `--refresh-stamps`.
- The full extraction was not re-run. The current `errors.log` marker was
  produced by the rebuilt extractor's `probe` run against the existing
  `filelist.txt`.
