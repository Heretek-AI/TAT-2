# Wave 0 Preflight - Manifest Audit

Date: 2026-11-19
Command: `cd /home/john/Projects/TAT-2 && make audit`
Exit code: 0 (PASS - gate `--min-coverage 0.90` satisfied)

## Raw output

```
python3 tools/manifest_audit.py --min-coverage 0.90
Manifest TAT entries: 12704
Resolved in CUE4Parse: 12630 (99.4%)
Files written to extracted: 30128
```

## Coverage

**99.4%** (12630 / 12704 manifest TAT entries resolved in CUE4Parse)

Coverage is defined in `tools/manifest_audit.py` as `resolved / len(manifest_tat)`,
where `resolved` counts manifest `TAT/` paths (excluding `.ubulk`/`.uexp`/`.uptnl`)
present in `extracted/filelist.txt`, and the gate fails below 90%.

## Notes

- Unresolved manifest entries: 74 (0.6%).
- 30128 files written across `extracted/{raw,json,assets,audio,audio-meta}`.
