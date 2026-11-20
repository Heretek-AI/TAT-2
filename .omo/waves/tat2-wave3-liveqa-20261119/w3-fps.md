# W3 FPS + teardown — export binary (Wave 1 tree, rebuilt 18:39)

Date: 2026-11-19
Binary: `build/tat2-linux-x86_64` (Wave 1 tree, `make linux-build` exit 0)
Method: `--display-driver wayland --rendering-driver vulkan --audio-driver Dummy
--quit-after N --print-fps --disable-vsync -- --qa-contract=<1|4>`,
steady state = samples after `TAT-2 Loaded`, first 3 post-load dropped.
Logs: `/tmp/w3-fps-logs/{startscreen720,startscreen1080,den720,den1080,gh720,gh1080}.log`,
run SUMMARY: `/tmp/w3-fps-logs/SUMMARY.txt` (all 5 runs exit 0, ALLDONE).

## Result table (median of steady-state `Project FPS` samples)

| scene | 1280x720 | 1920x1080 |
|---|---|---|
| Startscreen | 120 FPS (n=46, min 119) PASS | 120 FPS (n=46, min 119) PASS |
| Thieves Den (contract 1) | 120 FPS (n=50, min 26 load) PASS | 57 FPS (n=70, min 38) **FAIL** (marginal, -3) |
| Guildhall (contract 4) | 45 FPS (n=100, mean 29.6 w/ load stalls) **FAIL** | 8 FPS (n=261, mean 7.5) **FAIL** |

## Teardown + RD

- All 5 runs exit 0. Exit-time ObjectDB/resource leak warnings only (same class
  as Wave 0 baseline), no crash, no `double free`, no `X connection` drop.
- RD cascade grep (`Too many mipmaps|texture_create|update_sizes|uniform_set`):
  **0 in all 6 logs** — zero cascades sustained on this binary.

## Reading the Guildhall numbers

- gh720 median 45 matches the PG-1 lane's Wayland measurement (45.0) on the same
  tree: consistent, real work shortfall (7851 draws / 8.9 M prims + ~11 ms
  scripts per the lane's cost attribution), not a measurement artifact.
- gh1080 median 8 is worse than the lane's 29 on the same binary/flags; the
  concurrent `nvidia-smi` VRAM log shows the GPU pegged at 100% util / 74 C
  during the rerun window, so contention (or background-window present
  throttling) cannot be excluded. Either way it is a FAIL against the 60 gate —
  recorded honestly, not papered over.
- den1080 median 57 vs the lane's 67: same story, marginal FAIL either way.
- Wave 4 owns the Guildhall/Den-1080 deficit (draw/script work, a product-level
  perf task); no code was touched in this lane.
