# W0 Baseline Integrity - clip_1795033698901

Date: 2026-11-19
Command:

```
cd /home/john/Projects/TAT-2 && /usr/bin/python3 docs/reference/clip_1795033698901/tools/verify_baseline.py
```

Note: the default `python3` on PATH (linuxbrew) has no Pillow; `/usr/bin/python3`
carries Pillow 13.0.0, which is the interpreter the script's docstring specifies.

## Result: 8/8 [PASS] (exit code 0)

```
[PASS] 1. Timeline continuity - 27 segments S01-S27, boundaries identical in both docs, 00:00.00..03:45.64 contiguous
[PASS] 2. Template completeness - 27/27 segments carry all 7 '### ' subsections in order
[PASS] 3. Image integrity - 60 linked JPEGs valid at 1920x1080, clean/ == annotated/ (30 files), annotated max 535 KB, folders under 25 MiB
[PASS] 4. Callout parity - 30 keyframes, 195 callouts, spec counts == legend row counts, badge ids 1..N contiguous
[PASS] 5. Timestamp parity - 30 keyframe timestamps identical across KEYFRAME_INDEX, callout_spec.json, CALLOUT_LEGENDS.md, BREAKDOWN.md
[PASS] 6. Code taxonomy - 23 taxonomy codes valid, category matches prefix in spec and legend rows
[PASS] 7. Cross-ref IDs - 122 cross-reference rows valid, PG 1..8, HL 1..9, subsystem 1..18, parity statuses in allowed set
[PASS] 8. Determinism - 30/30 re-rendered JPEGs SHA-256 identical to annotated/ (source untouched)
8/8 [PASS]
```

Baseline is intact and reproducible; no source artifacts were modified.
