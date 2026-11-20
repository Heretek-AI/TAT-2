# TAT-2 finish-port — gate status after Waves 0–4 (2026-11-19/20)

Evidence: `.omo/waves/tat2-wave{0-preflight-20261119,1-fixes-20261119,2-integration-20261119,3-liveqa-20261119}/`,
`w4-tier1-gate.md`, `COMPARISON_SCORECARD_DRAFT.md` (120 rows, tally 37/0/0/3/80).

## Tier-1 gates (§10)

| Gate | Result |
|---|---|
| `make test` fails=0, 0 SCRIPT ERROR | PASS (90 lines, exit 0) |
| Headless Tier-1 E2E 110/110 | PASS (`fails=0 passed=110 total=110`; T1-03-E, T1-08-A, T1-18-E all PASS) |
| `make audit` >= 99.4% | PASS (12630/12704 = 99.4%) |
| Live Vulkan `--strict` 21/21 | PASS (0 shader/script errors, 0 RD lines, 21 PNGs) |
| Linux export builds + runs | PASS (rebuilt 18:39, exit 0, `[DONE] savepack`) |
| 60 FPS all scenes/resolutions | **FAIL**: Startscreen + Den-720 PASS; Den-1080 57 FAIL; Guildhall 45 @720p / 8 @1080p FAIL |
| TEMP hook removed; autostart unset | PASS (0 hits both) |
| Scorecard 0 MISSING / 0 fixable DELTA | PASS (0 MISSING, 0 DELTA, 3 documented HARD_LIMITs; 80 N/A evidence-pending) |
| `verify_baseline.py` 8/8 | PASS |

## What remains

1. **Guildhall/Den-1080 FPS** — draw/script work (7851 draws, 8.9 M prims, ~11 ms
   scripts). Product-level perf task; not a correctness gap.
2. **80 N/A scorecard rows** — need the full S01–S27 route capture + `ffmpeg astats`
   audio levels. Stills E2E (21/21) covers presence; video/timing rows are unmeasured.
3. **Hygiene** — verified: no `build/`, `game/.godot/`, `game/data/generated/`,
   `extension_api.json` tracked; `debug_autostart_contract` absent.
