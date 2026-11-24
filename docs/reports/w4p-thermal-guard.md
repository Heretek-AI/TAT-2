# W4P — fail-closed thermal guard for the perf matrix

**Status:** landed on `build/qa/run_perf_matrix.sh` + `build/qa/test_perf_guard.sh`.
**No real matrix measurements in this wave:** the host was ~82–94 °C package
during the work, so the new 78 °C start gate (correctly) refused every
sustained run. The sampler, RSS gate and scope path were exercised end to end
with a non-GPU stub binary; a real Godot run remains for a cool host (§6).

## 1. What the thermal audit found

| Defect | Before | After |
|---|---|---|
| Pre-warm unguarded | `timeout … $BIN …` in the foreground; no sampling, no kill path | same sampler as the measured run, own 1 s cadence, `PERF_THERMAL_PREWARM_PEAK` |
| Blind window | sampled every 10 × 0.5 s ≈ 5 s inside `wait_game` | independent 1 s sampler process; 5× fewer blind seconds |
| Sampling coupled to wait | `wait_game` both waits and samples; a stalled loop stopped the guard | sampler runs in its own subshell and kills the PID itself |
| No start headroom | `TEMP_START >= MAX_TEMP` only, so 91 °C could start with max 92 | `--start-temp` (78) refuses `start > 78`; `start < max` enforced |
| `RSS_PEAK` cosmetic | printed, never enforced; no `VmHWM` | `VmHWM` sampled and read at exit; `--max-rss-mb` (8192) fails the run |
| No memory cap | none | `MemoryMax=12G` + `MemorySwapMax=0` user scope, logged fallback |
| Unknown temperature | `?` only logged, run continued | pre-check, each sampler tick and a missing summary all fail closed |

## 2. Flags and gate

| Flag | Default | Meaning | Exit on violation |
|---|---|---|---|
| `--start-temp=<C>` | **78** | refuse to start when package `>` this | 8 |
| `--max-temp=<C>` | **95** | kill the launch at `>=` this | 8 |
| `--max-rss-mb=<MB>` | **8192** | fail when `VmHWM` exceeds it | 9 |
| `--sample-sec=<s>` | **1** | independent sampler cadence | 2 (bounds 1..60) |

Both temperatures are validated `60..105` and `start < max`; `--start-temp`
`>= --max-temp` is refused at argument time (`exit 2`). No headroom means no
run: `--start-temp=95 --max-temp=95` is not accepted.

Env equivalents: `PERF_START_TEMP`, `PERF_MAX_TEMP`, `PERF_MAX_RSS_MB`,
`PERF_THERMAL_SAMPLE_SEC`, `PERF_SCOPE_MEMORY_MAX`.

## 3. How the guard works

1. **Pre-check (before any launch).** `cpu_package_temp()` reads the kernel
   `x86_pkg_temp`/`TCPU` zones (fallback `sensors -u`). `thermal_decision()`
   returns `ok` / `refuse_start` / `refuse_max` / `unknown`. Logged first:
   ```
   PERF_THERMAL start=87 start_max=78 max=95 rss_max_mb=8192 sample_sec=1 scope=systemd memory_max=12G swap_max=0
   ```
   Any refusal is `exit 8`. `?` is `unknown`, never `ok`.
2. **Launch.** Each phase starts in the background inside
   `systemd-run --user --scope --collect --expand-environment=no
   --property=MemoryMax=12G --property=MemorySwapMax=0`, with the game PID
   written to a pidfile by `bash -c 'printf "%s\n" "$$" > "$1"; shift; exec "$@"'`
   before exec. `--expand-environment=no` is required: without it systemd-run
   rewrites `$$` to a literal `$` and the sampler would watch the wrong PID.
   The command's stdio still goes to the same `$LOG` / `$PREWARM_LOG`
   redirections. If `systemd-run --user --scope` fails (no user manager, e.g. a
   container), the wrapper logs
   `PERF_WARNING systemd-run --user --scope failed; launching directly (no
   MemoryMax, no MemorySwapMax=0)` and continues; `PERF_MEM_SCOPE` records
   `mode=direct`.
3. **Independent sampler.** A subshell samples temperature, `VmRSS` and
   `VmHWM` from `/proc/<pid>/status` every `--sample-sec` (1 s), appends
   `PERF_THERMAL_SAMPLE`, and rewrites its peak summary each tick so a kill
   cannot lose it. It kills the sampled PID (and stops the scope) at
   `>= --max-temp` or on a non-numeric reading. The wait loop only waits; it
   never samples.
4. **Pre-warm.** Same launch, same sampler, own summary. Reported as
   ```
   PERF_THERMAL_PREWARM_PEAK peak_c=91 peak_rss_mb=60 vmhwm_mb=60 max_c=95 abort=none
   ```
   A pre-warm abort (temperature or unknown) stops the wave before the measured
   run; a pre-warm `VmHWM` over the cap exits 9.
5. **Exit.** `VmHWM` is read once more before `wait` reaps the process, then the
   larger of sampler `VmHWM`/`VmRSS` peaks is enforced and reported:
   ```
   PERF_THERMAL peak_cpu_c=85 prewarm_peak_c=91 peak_rss_mb=60 vmhwm_mb=60 max_c=95 start_max_c=78 rss_max_mb=8192 sample_sec=1 scope=systemd abort=none
   ```

## 4. Proof commands (no GPU, safe on a hot host)

```bash
bash -n build/qa/run_perf_matrix.sh
bash -n build/qa/test_perf_guard.sh
build/qa/test_perf_guard.sh                 # 42 checks, starts no game
build/qa/run_perf_matrix.sh --guard-check=77   # exit 0
build/qa/run_perf_matrix.sh --guard-check=78   # exit 0 (== start-temp allowed)
build/qa/run_perf_matrix.sh --guard-check=79   # exit 8, refuse_start
build/qa/run_perf_matrix.sh --guard-check=95   # exit 8, refuse_max
build/qa/run_perf_matrix.sh --guard-check='?'  # exit 8, unknown (fail closed)
build/qa/run_perf_matrix.sh --start-temp=95 --max-temp=95   # exit 2, no headroom
```

`--guard-check=<C>` runs the exact runtime `thermal_decision()` on a synthetic
reading and exits before the lock, log, display or launch — it cannot start a
game. `test_perf_guard.sh` also greps the wrapper for the sampler, `VmHWM`, the
scope properties and the fail-closed paths, so deleting the guard fails the
test even on a host without sensors.

Observed output (this tree):

```
$ build/qa/test_perf_guard.sh
...
PERF_GUARD_TEST PASS checks=42 fails=0
```

## 5. Stub-harness evidence (not Godot numbers)

`PERF_BINARY` pointed at a Python stub that prints `PERF_CONFIG` /
`PERF_SUMMARY` / `PERF_DONE`, allocates memory and sleeps. This exercises the
wrapper without a GPU or a Godot process:

- 1 s cadence, both phases (real package temperatures):
  ```
  PERF_THERMAL_SAMPLE phase=prewarm pid=… t=91 rss_mb=60 vmhwm_mb=60 elapsed=0s max_c=95 …
  PERF_THERMAL_SAMPLE phase=prewarm pid=… t=89 rss_mb=60 vmhwm_mb=60 elapsed=1s max_c=95 …
  PERF_THERMAL_SAMPLE phase=prewarm pid=… t=90 rss_mb=60 vmhwm_mb=60 elapsed=2s max_c=95 …
  PERF_THERMAL_SAMPLE phase=run     pid=… t=83 rss_mb=60 vmhwm_mb=60 elapsed=0s max_c=95 …
  PERF_THERMAL_SAMPLE phase=run     pid=… t=85 rss_mb=60 vmhwm_mb=60 elapsed=1s max_c=95 …
  ```
  The pre-warm leg caught a 91 °C transient that the old 5 s sampler would have
  missed entirely.
- RSS gate: `STUB_MB=300 --max-rss-mb=256 --prewarm=0` →
  `FAIL: VmHWM 310 MB > --max-rss-mb 256 MB`, `exit 9`.
- Scope: `systemd-run` path reported `PERF_MEM_SCOPE mode=systemd`; forcing
  `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS` to an invalid target produced the
  logged fallback, `mode=direct`, and the run still completed (`exit 0`).
- Defaults refusal on this host (real reading): `PERF_THERMAL start=94
  start_max=78 max=95` → `ABORT: CPU package 94C > --start-temp 78C …`, `exit 8`.

## 6. What remains (needs a cool host)

- **Real matrix run at the 78/95 gate**:
  ```bash
  build/qa/run_perf_matrix.sh --quality=high --scale=1.0 --scaling=bilinear --tag=w4p_gate
  ```
  Expect `PERF_THERMAL start=… start_max=78 max=95`, `PERF_THERMAL_PREWARM_PEAK`,
  one `PERF_THERMAL_SAMPLE` per second per phase, and a final
  `PERF_THERMAL … vmhwm_mb=…` with `abort=none`.
- **Thermal kill at >= 95 °C was not executed** (the box could not be made hot
  on purpose). The kill path is the same `kill_guarded` used by the timeout and
  teardown paths and is covered by the source checks only.
- **Real Godot `VmHWM`** and pre-warm peak under the full Guildhall scene are
  unmeasured; the 8192 MB cap and 120-frame pre-warm cost are untested against
  the real binary.
- The reference i9-14900HX idles near 82 °C, which is above the 78 °C start
  gate. That is deliberate: cool the machine (or document an explicit
  `--start-temp` with measured headroom) before publishing numbers.
