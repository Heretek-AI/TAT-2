# Performance truth and structural levers (2026-11-24)

Scope: honest quality control + fixed-pose measurement (W0b), structural
prototype (W1p), integrated measurements on `main`, and the review pipeline
that makes the world inspectable.

## Measurement contract

- Release export `build/tat2-linux-x86_64`, rebuilt from the measured HEAD.
- Host Wayland compositor, RTX 4070 Laptop (driver 620.73.04), Forward+,
  vsync off, Dummy audio, `XDG_DATA_HOME` isolated.
- Contract 4 (Guildhall), six fixed poses (`spawn_overlook`, `gate_approach`,
  `gate_sign`, `foyer`, `upper_foyer`, `door_approach`), 180 warm-up frames,
  time-based sampling, every pose summarized.
- Xvfb is **not** comparable: the same 1080p pose measured 66.55 ms under Xvfb
  versus 20.4 ms on the host. The wrapper defaults to the host display and
  labels Xvfb runs.

## Quality ladder is real now

The old "four runs all level 2" failure is gone. `settings.graphics_quality`
(low/medium/high, default high) is persisted, validated, and exposed in
Settings; `--perf-quality` logs one `PERF_CONFIG` with the effective values and
the weather system reports level 0/1/2.

## Integrated 1080p results (p50 wall frame)

| Run | Config | p50 ms | p50 FPS | mean FPS | 1% low | worst pose (p50 ms) | draws |
|---|---|---:|---:|---:|---:|---|---:|
| high baseline (first) | high, 160 lights, 6 shadows | 19.61 | **50.99** | 50.52 | 27.14 | door_approach 24.52 | 1.9k–11.0k |
| high baseline (repeat) | same binary as levers | 18.05 | **55.40** | 55.92 | 35.31 | door_approach 20.28 | 1.9k–11.0k |
| PeripheryA 100 m | high + `TAT2_PERIPH_RANGE=100` | 19.04 | 52.51 | 52.37 | 32.64 | door_approach 20.13 | 1.9k–9.7k |
| same-material cell merge | high + `TAT2_MERGE_CELLS=plain` | 20.49 | 48.81 | 46.23 | 20.64 | door_approach 30.91 | 2.1k–11.3k |
| Performance preset | low, 64 lights, 2 shadows, native | 17.02 | 58.77 | 56.33 | 27.53 | door_approach 27.53 | 1.9k–11.0k |

Read this honestly:

- **Run-to-run variance is larger than every lever delta.** Two identical
  high/1080p controls measured 50.99 and 55.40 p50 FPS. GPU clock/thermal state
  (270 MHz idle before, 2.55 GHz / 74 °C after) moves the number more than the
  100 m cull or the low preset does.
- **PeripheryA 100 m is not a proven win.** It cuts ~1.7k draws and improves
  `door_approach` in one pair (24.5 → 20.1 ms) but is slower than the repeat
  control overall. Keep it as an off-by-default QA lever until a repeated,
  clock-controlled A/B shows a stable gain.
- **Cell merge is a measured regression.** Surface draws fall 6.1 % (10,642 →
  9,994) but runtime draw calls rise (~300 more on the measured poses) and the
  coarser merged AABBs overdraw more: p50 48.81 vs 55.40 and `door_approach`
  30.91 vs 20.28 ms. Do **not** enable it.
- **The Performance preset is not 60 FPS.** p50 58.77 looks close, but p95 is
  28.65 ms, 1 % low is 27.53 FPS, and `door_approach` is 27.53 ms. It is a
  documented low/64/2 configuration, not a shipped 60 FPS claim.
- The frame is GPU-bound at high (render GPU ~19 ms vs CPU ~7 ms); the worst
  poses are also CPU/geometry-heavy (physics ~6 ms, process ~25 ms at
  `door_approach`). A draw-count-only fix cannot reach 60.

## What this means for the next performance wave

The levers measured so far do not reach 16.67 ms. The remaining honest options,
in order of expected value:

1. **Light and shadow budget as a real preset, not a one-off.** 160 lights and
   6 hero shadows are still active in "low". Measure 64/2 and 32/1 with
   repeated runs; the low preset kept the same draw counts, so the light cost is
   in shading, not batching.
2. **Occlusion/HLOD, not naive merge.** PeripheryA is 55.9 % of surface draws;
   a 100 m visibility range only trims the visible fraction. Merging by
   material made culling coarser and lost. The next structural attempt should
   preserve per-item culling (HLOD impostors or occlusion), not fuse AABBs.
3. **Repeated, clock-controlled measurement.** Lock the GPU clock or run each
   config 3× and report the median; one 5-minute run cannot resolve a <10 %
   change on this laptop.
4. **Then revisit resolution scaling.** Native 1080p is the target; 0.85 FSR1
   was not measured in this wave and should not be sold as a fix before the
   native budget is understood.

## Artefacts

- `build/qa/perf/perf_integrated_high_1080.log`
- `build/qa/perf/perf_baseline2_high_1080.log`
- `build/qa/perf/perf_periph100_high_1080.log`
- `build/qa/perf/perf_merge_high_1080.log`
- `build/qa/perf/perf_integrated_perf_1080.log`
- `docs/reports/perf-measurement-w0b.md` (harness design and validation)
- `docs/reports/w1p-structural-perf-prototype.md` (census and merge details)

All logs are gitignored build artifacts; the numbers above are copied from the
`PERF_SUMMARY`/pose JSON lines in those files.
