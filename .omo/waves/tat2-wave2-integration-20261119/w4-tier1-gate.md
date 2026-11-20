# W4 gate evidence — headless Tier-1 E2E full rerun (Wave 1 tree)

Date: 2026-11-19
Command: `flatpak run org.godotengine.Godot --headless --path game
--script res://tests/e2e/run_e2e_tests.gd -- --tier=1`
Log: `.omo/waves/tat2-wave2-integration-20261119/tier1-full-rerun.log`
Exit: 0

## Result

```
SUMMARY: fails=0 passed=110 total=110
```

- `PASS: [T1-03-E] left_corner_trim_fix code=true mat=false`
- `PASS: [T1-08-A] 1P arms SK_ThiefNisha__BodyUpper PBR bound (true)` —
  the `_cap_texture` empty-resource_path regression flagged by both Wave 1
  lanes is confirmed fixed by `take_over_path(res_path)` in
  `game/src/core/level_loader.gd`.
- `PASS: [T1-18-E] Escape multipliers ghost=1.25 shadow=1.10 loud=1.00 escapes=1`
- Exit-time noise only (5 resources, 2 RendererSceneCull RIDs); 0 SCRIPT ERROR.
- `make audit` re-run on Wave 1 tree: 12630/12704 = 99.4% (>= 99.4% gate holds).

## Still open (not gates for this file)

- Live strict E2E: 21/21 PASS (w3-e2e-strict.md, independently verified).
- FPS: Startscreen + Den-720 PASS; Den-1080 marginal FAIL (57); Guildhall FAIL
  (45 @720p, 8 @1080p) — product-level draw/script work, Wave 4 owner.
- Comparison scorecard: pending w3-scorecard node.
