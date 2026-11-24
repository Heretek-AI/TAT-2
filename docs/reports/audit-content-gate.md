# Audit content gate (W0)

**Date:** 2026-11-24
**Scope:** `tools/manifest_audit.py`, `Makefile`, `README.md`
**Command:** `make audit`

The audit was a mount-consistency + mtime check. It now gates generated
content, stage counts, `errors.log` presence and producer drift. This report
records the measured pass and every negative control that was run.

## What the gate checks

1. **Mount/path consistency** compares manifest TAT paths to
   `extracted/filelist.txt` case-insensitively and excludes
   `TAT/Content/Paks/pakchunk0-Windows.pak` from the denominator. The old
   exact-case 99.4 % figure is still printed as a diagnostic; it counts 73
   case-only differences as misses. It is no longer the coverage gate.
2. **Content groups** (13) assert measured counts per generated domain.
3. **Producer stamps** (`build/audit/producer_stamps.json`, gitignored) store
   the sha256 of 15 producers plus the output counts/metrics observed on a
   green audit. mtimes remain a secondary freshness signal; they cannot
   survive a checkout.
4. **`errors.log`** must exist whenever extraction produced files, must be at
   least as new as `filelist.txt`, and keeps the enumerated BlendSpace
   allowlist. Absence and staleness are now failures, not warnings.
5. **Stage floors** replace `> 0`: raw ≥ 120, json ≥ 12 000, assets ≥ 11 000,
   audio ≥ 5 000, audio-meta ≥ 1 200. Per-run override: `--stage-min NAME=N`.

Escape hatch: `make audit-refresh-stamps` (or
`python3 tools/manifest_audit.py --refresh-stamps`) accepts a changed producer
after regeneration and rewrites the stamps. It still runs every content and
`errors.log` check.

## Repairs made before the green run

- `python3 tools/parse_contracts.py` regenerated
  `game/data/generated/gameplay/contracts.json`; it now contains
  `mission_loot_goals` (`Mission.Guildhall.LootTheRoom: [4000, 6000, 8000]`).
  The file is gitignored, so this is a tree repair, not a commit.
- `extracted/errors.log` was absent. A zero-byte log was created to represent
  the clean run. The extractor currently deletes the log when a run is clean;
  the new contract requires it to always write/truncate the file, otherwise
  the next clean extraction will fail this gate by design.

## Green run (2026-11-24)

```
Manifest TAT entries: 12704
Pak containers excluded: 1 (TAT/Content/Paks/pakchunk0-Windows.pak)
Mount/path consistency (case-insensitive, pak excluded): 12703/12703 (100.0%)
Mount/path consistency (exact-case diagnostic, previously reported as 99.4 %): 12630/12703 (99.4%), 73 case-only differences
stage raw: 141 files (min 120)
stage json: 12541 files (min 12000)
stage assets: 11251 files (min 11000)
stage audio: 5019 files (min 5000)
stage audio-meta: 1441 files (min 1200)
Files written to extracted: 30393
errors.log: clean (empty, 2026-11-24 00:03)
content levels: OK   files=107, min=107
content contracts: OK   entries=16, expected=16, mission_loot_goals=True
content tables: OK   files=144, min=144
content materials: OK   entries=1629, min_entries=1620, with_albedo=1379, min_albedo=1370
content containers: OK   records=254, min=250, classes=5
content decals: OK   records=675, min=670
content devices: OK   total=4118, expected=4118, families=21, expected_families=21, family_sum=4118
content animations: OK   ok=995, min_ok=995, fail=0, entries=995, total=995
content audio: OK   clips=5018, min_clips=5018, failed=0, failure_records=0
content localization: OK   csv=8, translation=8, expected=8
content videos: OK   ogv=15, manifest=15, expected=15
content scene_variants: OK   count=222, records=222, expected=222
content niagara: OK   records=3695, min=3695
stamps: 15 producers match build/audit/producer_stamps.json
manifest -> extracted/_manifest.json
stamps -> build/audit/producer_stamps.json (15 producers)
AUDIT PASS
```

`python3 -m py_compile tools/manifest_audit.py` exits 0. `black --check` reports
the file unchanged.

## Negative controls (each reverted)

| Control | Result |
|---|---|
| Rename `game/data/generated/anims_manifest.json` | exit 2 (make) / `content animations: FAIL`; `FAIL: animations: FileNotFoundError: .../anims_manifest.json` |
| Move one `.tatlevel.json` out of `generated/levels` | exit 2 / `content levels: FAIL files=106, min=107`; failure names levels and `parse_tables.py` |
| Rename `extracted/errors.log` | exit 2 / `FAIL: errors.log: MISSING at extracted/errors.log: 30393 extracted files exist ...` |
| Backdate `extracted/errors.log` before `filelist.txt` | exit 2 / `FAIL: errors.log: STALE at extracted/errors.log (2026-11-20 00:00, 0 bytes) ...` |
| Remove `mission_loot_goals` from contracts.json | exit 2 / `content contracts: FAIL entries=16, expected=16, mission_loot_goals=False`; failure names the key and `parse_contracts.py` |
| Append a comment to `tools/parse_weather.py` | exit 2 / `stamps: producer drift: 1 failure(s)`; failure names the producer, old/new sha and the regeneration command |
| `--stage-min assets=999999` | exit 1 / stage assets floor failure with expected/actual |
| Remove the stamps file | exit 0 / `first run: no stamps, writing after a green audit`; stamps written |
| Producer change + `make audit-refresh-stamps`, then restore + refresh | exit 0 both times; drift accepted only under the explicit flag |

All temporary edits and renamed files were restored; the final `make audit`
exits 0 and `git diff` shows only the intended source/docs changes.

## Not verified

- The extractor was not re-run. `errors.log` is a zero-byte repair, not fresh
  extractor output; the extractor change to always emit it is a follow-up.
- Full `make test` / E2E were out of scope for W0 and were not run.
