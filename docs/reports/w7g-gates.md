# W7G — export provenance, roughness cache, core bake and Sonar gate plan

**Base:** `74a43b8` (`docs: record the W6 integration and the re-measured gate
set`)
**Worktree:** `/tmp/opencode/tat2-w7g-gates`
**Scope:** QA/export gates, the loader roughness cache only, Sonar Path A
config, docs. No gameplay/UI/hearing/S2/S5 code, no producer, no audit.
**Date:** 2026-11-24

Every performance and editor number below is **lane-local**: this host, this
worktree, one Godot at a time, `XDG_DATA_HOME=/tmp/opencode/w7g-data`. They are
not a substitute for the perf matrix, which was **not run** (the host idles near
80 °C; the user waived the thermal gate but not the one-Godot rule).

`make audit` is **not measurable in this worktree**: `game/data` is a symlink
into the main checkout and the W7S lane's uncommitted loot producers changed 4
`gen:gameplay` files plus the directory hash, so audit would fail on drift this
wave does not own. Integration regenerates and re-stamps at the merged HEAD. The
audit floors in `tools/gate_ratchet.json` are unchanged base values
(12657/12703) and are not evidence for this wave.

---

## 1. Export provenance

### 1.1 `make linux-build` writes a stamp

`build/qa/export_stamp.sh write` runs after a successful export and writes
`build/tat2-linux-x86_64.stamp.json` (gitignored with `build/`):

```json
{
  "schema": "tat2.export_stamp/1",
  "preset": "Linux",
  "git_sha": "<HEAD short 12>",
  "git_sha_full": "<HEAD>",
  "git_dirty": <true|false>,
  "built_at": "<UTC ISO-8601>",
  "godot": "4.7.2.stable.official.ed1daf0bf",
  "binary": "tat2-linux-x86_64",
  "binary_sha256": "<sha>",
  "binary_bytes": <n>,
  "pck": "tat2-linux-x86_64.pck",
  "pck_sha256": "<sha>",
  "pck_bytes": <n>,
  "pck_embedded": 0,
  "exclude": "scenes/review/**"
}
```

`make linux-stamp-verify` re-checks it without exporting. Exit codes: 0 ok,
3 stale (stamp HEAD != current HEAD), 4 artifact hash/size mismatch, 5 missing
stamp/artifact, 6 dirty build with `--require-clean`.

Measured on this tree (real export after the `ConfigFile` fix below;
[`logs/w7g-export.log`](logs/w7g-export.log)):

```
EXPORT_STAMP git=74a43b81865b dirty=true built_at=2026-11-25T02:41:55Z
  binary=tat2-linux-x86_64 binary_bytes=73519416
  binary_sha=d9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63
  pck=tat2-linux-x86_64.pck pck_bytes=2574092822
  pck_sha=642fb0559d4ff9ce2898cbfdc1cf82f145c06f989558c2d375956449062ef564
EXPORT_STAMP_WARNING tracked tree dirty at build time: this build is not publishable
```

`make linux-stamp-verify` returns `EXPORT_STAMP_OK` for the same artifacts.
`build/qa/run_perf_matrix.sh --provenance-check=build/tat2-linux-x86_64` prints
`PROVENANCE_CHECK OK publishable=0 reason=dirty_build` (this worktree has the
private data symlinked, so its tracked tree is intentionally dirty) plus the PCK
line; `--publishable-only` refuses with exit 2 before any launch. A clean main
checkout at the same commit would stamp `dirty=false` and be publishable.

### 1.2 The perf wrapper refuses an unprovenanced export

`build/qa/run_perf_matrix.sh` calls `export_stamp.sh verify` before the lock,
display or launch:

* default `build/tat2-linux-x86_64` → a missing, stale or mismatched stamp is
  **fail-closed** (`exit 2`, message says to run `make linux-build`);
* `PERF_BINARY=<path>` without a stamp is allowed for stubs/A-B runs but is
  logged `PERF_PROVENANCE ... publishable=0 reason=unverified_override`; a stale
  stamp on an override still fails closed;
* a dirty tracked tree at build time keeps the run allowed but
  `publishable=0 reason=dirty_build`; `--publishable-only` turns that into a
  refusal;
* the log always records the PCK path, SHA-256 and size:

```
PERF_PROVENANCE mode=export publishable=... reason=... stamp_git=<sha> godot=... stamp=<path>
PERF_PCK path=... sha=... bytes=... binary_sha=... binary_bytes=... embedded=0
PERF_MEM_SCOPE mode=... memory_max=... memory_max_mb=... swap_max=0 ram_total_mb=... max_rss_mb=... pid=...
```

### 1.3 Memory scope and RSS sanity

`MemoryMax` is no longer a fixed `12G`. It is derived from `/proc/meminfo`
`MemTotal` at 75 % (whole GiB, 2 GiB floor), overridable with
`PERF_SCOPE_MEMORY_MAX` (`12G`/`12288M`). The RSS ceiling now:

* accepts 1024..262144 MB (the old 256 MB floor allowed a cap that cannot boot
  Godot; it was only ever exercised against a stub);
* may not exceed total RAM (a cap above RAM can never fire);
* may not exceed the derived `MemoryMax` (the cgroup would kill the run before
  the gate could report it);
* is lowered automatically to the scope when the caller did not set it (an
  8 GB host gets 6 GiB, not 8192 MB);
* has a synthetic decision probe, `--rss-check=<MB>` (exit 0/9), like
  `--guard-check` for temperature.

### 1.4 QA export excludes baked review scenes — and the `ConfigFile` trap

`game/export_presets.cfg` sets `exclude_filter="scenes/review/**"`.

**Trap found while validating the visible open:** Godot's `ConfigFile` parser
does **not** accept `#` comments. Writing an explanatory `# W7G …` comment above
`exclude_filter` silently merged the comment and the key into one malformed key
(`CHECK KEY #W7G:…exclude_filter=scenes/review/**`), so
`has_section_key("preset.0", "exclude_filter")` was **false** and the exclusion
was not applied — with no error during export. The comment was removed; a
`ConfigFile` probe now reports:

```
CHECK has_exclude=true
CHECK exclude=scenes/review/**
```

This is recorded in `AGENTS.md` as a known trap: keep `export_presets.cfg` free
of `#` comments (use `;` or the report).

Proof of exclusion on the second export, with the 194 MiB core scene present:

| check | result |
|---|---|
| export log lines for `res://scenes/review/` | **0** |
| export log lines for tracked `res://scenes/review_mode` | **1** (kept) |
| PCK size vs the first export (before the bake existed) | 2,572,650,373 → 2,574,092,822 (+1.44 MB, not +194 MB) |

The +1.44 MB is Godot import sidecar churn from the editor open, not the baked
scene. The exclusion is applied.

### 1.5 Guard tests

`build/qa/test_perf_guard.sh` was extended from the thermal/argument checks to
78 checks, all passing on this host:

```
PERF_GUARD_TEST PASS checks=78 fails=0
```

New coverage: 1024 MB floor, 262144 MB ceiling, cap-vs-RAM/scope refusal,
`--rss-check` ok/refuse/unknown, `MemoryMax` derivation + override, `PERF_PCK`
and `PERF_PROVENANCE` log lines, stale/mismatch fail-closed messages, the
`--publishable-only` path, the export preset exclusion, and a synthetic stamp
suite (write → verify 0, stale → 3, PCK tamper → 4, missing PCK → 5, missing
stamp → 5).

**Latent test defect fixed:** the three “hot idle” cases in the W4P test
(`79/94/95 °C`) were missing their `--guard-check` argument, so they ran the
full pre-check and only “passed” because the host was hot enough to exit 8 — on
a cool host they would have launched a game. They now pass the synthetic
temperature explicitly, so the guard test never starts a game.

---

## 2. Roughness: full resolution, process-global cache

W6L's exact `low + g*(high-low)` L8 bake is **kept at full authored
resolution** — no half-res path was added. What changed:

| W6L | W7G |
|---|---|
| per-loader-instance dictionary | process-global dictionary keyed by `orm_path|low|high` |
| cleared on every loader exit | cleared only when the last live loader leaves the tree (explicit `cleanup_roughness_cache()` for out-of-tree probes) |
| counters only for bakes | counters reset at both load entry points; log adds `bytes` and cache `hits` |
| no off switch | `TAT2_ROUGH_BAKE=off` fallback (`roughness=high`, no ORM green bind), resolved once per process |

Measured on the first real Guildhall load (`run_tests`, same 73.9 M px as W6L):

```
ROUGHNESS_BAKE_MODE on=1 resolution=full cache=process
ROUGHNESS_BAKE count=86 pixels=73924608 ms=4089 bytes=98566111 hits=46 (L8 low+g*(high-low), full-res, process cache)
```

**86 bakes / 73,924,608 px / 4,089 ms / 98.6 MB / 46 cache hits** on the first
Guildhall load. `bytes` is the L8 texture plus mip chain (4/3 of the base
plane); the W6L estimate was ~98 MiB. The cache probe that exercises two live
loaders, a distinct range, and teardown re-bake produced:

```
ROUGHNESS_BAKE_MODE on=1 resolution=full cache=process
ROUGH_CACHE mode_a=true mode_b=true
ROUGH_CACHE shared=true distinct_range=true a_count=1 a_hits=0 b_count=1 b_hits=1 a_bytes=1398101 a_px=1048576
ROUGH_CACHE after_teardown_rebaked=true c_count=1 c_hits=0
```

Two live loaders reused one bake (`shared=true`, `b_hits=1`), a different range
baked its own texture (`distinct_range=true`), and after both were freed a new
loader re-baked instead of hitting (`after_teardown_rebaked=true`,
`c_hits=0`). The probe is a throwaway harness; the log is
[`logs/w7g-rough-cache.log`](logs/w7g-rough-cache.log).

`probe_leak` (with the cache active) is **clean**: exit 0, 0 RID/texture leak
markers, both Den and Guildhall players freed, and the log shows the mode line
once plus one `ROUGHNESS_BAKE` line per map — [`logs/w7g-probe_leak.log`](logs/w7g-probe_leak.log).
The cache is therefore cleared in the teardown path and does not survive as an
exit leak.

`TAT2_ROUGH_BAKE=off` was not used for any gate. It exists as a documented
diagnostic fallback only; the shipped path is the bake.

---

## 3. Editor core bake

`make bake-review-core` at this HEAD (Guildhall POI + 3rd floor + Gameplay +
Lighting in one `load_sublevels_async()` call, 160-light budget). Log:
[`logs/w7g-bake-core.log`](logs/w7g-bake-core.log).

```
REVIEW_BAKE Load core single-call sublevels=4 budget=160
ROUGHNESS_BAKE count=71 pixels=60293120 ms=3708 bytes=80390799 hits=34
REVIEW_BAKE   built guildhall_core.scn in 6815 ms (203393969 bytes)
REVIEW_BAKE summary map=guildhall mode=single status=ok sublevels=4 scenes=2
  bytes=203404687 beams=435 labels=0 emissive=266 hidden_nodes=92
  hidden_records=488 bake_ms=8546
```

Size vs the 256 MiB editor guard:

| artifact | bytes | MiB | margin vs 256 MiB |
|---|---:|---:|---:|
| `guildhall_core.scn` | 203,393,969 | **194.0** | **52.6 MiB (24.2 % under)** |
| whole `guildhall_core/` bundle | 203,404,687 | 194.0 | 52.6 MiB |

The prediction (~218 MB) was conservative; the measured scene is 194 MiB. No
bake change was needed.

Headless load of `review_core.tscn` (real run, `/usr/bin/time -v`; log
[`logs/w7g-core-load.log`](logs/w7g-core-load.log)):

```
CORE_LOAD load_ms=387 instantiate_ms=372 meshes=1006 lights=169
  vmhwm_mb=782 vmrss_mb=782 vmpeak_mb=3400
Maximum resident set size (kbytes): 798896
```

`vmhwm_mb`/`vmrss_mb` are this process's `VmHWM`/`VmRSS` from
`/proc/<pid>/status`; 782 MB is the headless peak.

### Visible open on the 8 GB RTX 4070 Laptop

Log: [`logs/w7g-core-visible.log`](logs/w7g-core-visible.log). The editor was
opened on `res://scenes/review/guildhall_core/review_core.tscn` (window
`25165826`, scene present), sampled every 2 s for 80 s, then terminated by the
harness.

**Instrument and limits:** VRAM was sampled with
`nvidia-smi --query-gpu=memory.used`, which reports **total device memory in use
on the GPU**, not this editor process's resident textures. The first sample was
4,931 MB before the scene had loaded, so that number includes the
desktop/compositor and any other GPU work on the host. The 6,931 MB peak is
therefore **not evaluable against the ≤2.5 GB per-process threshold with this
instrument** — it is evidence neither of a pass nor of a fail. Process memory
came from `/proc/<pid>/status`: RSS peak 3,456 MB, **VmHWM 3,934 MB**, which is
within the ≤5.6 GB process budget (instrument named).

What was and was not observed: the editor was invoked with the scene path and the
window-only capture (`/tmp/opencode/w7g-core-visible.png`, not committed)
confirms the `review_core` tab and its node tree (`ReviewCore → guildhall_core`,
`ReviewEnvironment`, `ReviewMoon`, `ReviewGameplayFills`, `ReviewCamera`). The 3D
viewport was not framed on the map, so this is **not** a visual-fidelity check.
No crash or OOM occurred during the 80 s window, and the harness sent SIGTERM
afterwards; that is **not an acceptance result**. A real open must (a) be
measured with a per-process VRAM instrument —
`nvidia-smi --query-compute-apps=pid,used_gpu_memory` for this PID, or a Vulkan
heap-budget probe — (b) frame and inspect the scene, and (c) be closed normally
by the user, not killed by the harness. Until then the editor core's ≤2.5 GB
threshold is unproven, and the 194 MiB bake remains the current guard.

The editor run also rewrote `game/project.godot` (comment/section churn) and
generated `.uid` sidecars; the rewrite was reverted with
`git checkout -- game/project.godot` and the sidecars are untracked, so neither
is in this commit. This is now an `AGENTS.md` trap.

Temperatures reached **82.38 °C GPU / 97 °C CPU**. The thermal gate is waived by
the user, so these are recorded, not judged as a pass or fail.

---

## 4. Sonar Path A

### 4.1 What is configured

* `.github/workflows/sonar.yml` — checkout (fetch-depth 0) → `SONAR_TOKEN`
  presence probe → SonarCloud scan; `SONAR_TOKEN` absent (fork PR) skips with a
  notice instead of failing. Every action is pinned to a commit SHA:
  `actions/checkout@11d5960a…` (v4.4.0),
  `actions/setup-python@a26af69b…` (v5.6.0),
  `SonarSource/sonarqube-scan-action@2f77a1ec…` (v5).
* `.sonar-project.properties` — `sonar.sources=tools,game,.github` (workflow
  changes are analyzed), generated/private trees excluded, `qualitygate.wait`
  true with a 600 s timeout, coverage excluded because there is no report.
* Gate definition (new code only): **Reliability rating A**, **Security rating
  A**, **duplication on new code ≤ 3 %**. Coverage and Maintainability are
  deliberately not gate conditions: Sonar has no GDScript analyzer, so the game
  runtime is invisible to it, and there is no coverage upload.

**No scan was run in this wave.** The workflow is inert until the manual steps
below are done; the gate remains unbound and the first hosted run is the first
real Sonar result.

### 4.2 Exact manual steps (not performed here)

1. SonarCloud → project `Heretek-AI_TAT-2` → Administration → Analysis Method:
   **turn OFF Automatic Analysis**. Autoscan conflicts with this CI scan and
   ignores `.sonar-project.properties`.
2. GitHub → repo Settings → Secrets and variables → Actions → new repository
   secret `SONAR_TOKEN` = a SonarCloud **project analysis token** for this
   project (not a user token).
3. SonarCloud → Quality Gates → create/bind **“TAT-2 New Code”**: new-code
   Reliability rating A, Security rating A, duplication ≤ 3 %; no coverage and
   no maintainability condition. Bind it to the project.
4. Administration → New Code: period = **Previous version** (or 30 days) so
   only new code is judged.
5. Keep the scan action pinned to a commit SHA. The current pin is
   `2f77a1ec69fb1d595b06f35ab27e97605bdef703` (v5); bump the SHA and the
   version comment together.
6. Confirm `.sonar-project.properties` still lists `.github` in
   `sonar.sources` so workflow edits are scanned.

---

## 5. Ratchet, committed evidence and gates

### 5.1 Ratchet values (base measurements — not inflated for unmerged lanes)

`tools/gate_ratchet.json`:

| gate | value |
|---|---|
| measured_on | **`74a43b8`** (the base commit these logs came from) |
| compile | **110 checked / 0 broken** |
| `run_tests` | **263 passes / 0 fails** |
| M2 | **11 passes / 0 fails** |
| E2E | **264 passed / 264 total / 0 fails** |
| audit (base only, not re-measured here) | 12657 / 12703 / 0 unexpected |
| texture cap (base only, not re-measured here) | 773 capped / 1 alpha-kept / 0 offenders |

These are the base floors, not the merged-tree numbers. S2 (suites 89/90 and a
12-case `--tier=s2`), W7E's suite and W7H's tests will measure higher on the
merged tree; integration raises the floors **with fresh logs** at that HEAD.
Nothing is pre-inflated here.

### 5.2 Checker derives from the JSON

`tools/check_gate_ratchet.py` no longer contains a second copy of any count.
It:

* reads every gate value from `gate_ratchet.json`;
* enforces zero-failure invariants, `e2e.passed == e2e.total`, and
  `0 < audit.coverage_den` with `coverage_num <= coverage_den`;
* for the gates named under `evidence`, builds the expected summary line from
  the JSON (`scripts checked: <checked>, broken: <broken>`,
  `SUMMARY: fails=…`, `M2_SUMMARY: fails=…`,
  `SUMMARY: fails=… passed=… total=…`) and requires **at least `passes`**
  `^PASS` lines for `run_tests`/`m2`;
* requires `probe_leak` evidence with `PROBE start` and no
  `leaked at exit`/`SCRIPT ERROR`;
* builds the report-quoting regexes from the same JSON values, so a stale
  report cannot claim a green gate;
* prints `NOTICE` (not PASS) for `audit`/`texture_cap` because they have no log
  in this wave; integration must attach one when it re-measures.

**Evidence layout and failure behaviour** — `gate_ratchet.evidence.dir` plus one
filename per gate, e.g.:

```
docs/reports/logs/w7g-compile.log       scripts checked: 110, broken: 0
docs/reports/logs/w7g-run_tests.log     SUMMARY: fails=0  + >= 263 PASS lines
docs/reports/logs/w7g-m2.log            M2_SUMMARY: fails=0 + >= 11 PASS lines
docs/reports/logs/w7g-e2e.log           SUMMARY: fails=0 passed=264 total=264
docs/reports/logs/w7g-probe_leak.log    PROBE start, no leak markers
```

A missing log fails with the exact command to run
(`run `make test` and commit the log`); a log whose summary does not match the
ratchet is reported as **stale/mismatched** with the same command; a PASS count
below the floor reports the measured count, the floor and the command. There is
no silent skip.

### 5.3 Gates measured in this wave

| Gate | Result | Evidence |
|---|---|---|
| compile | **110 checked, 0 broken** | [`logs/w7g-compile.log`](logs/w7g-compile.log) |
| `run_tests.gd` | **fails=0, 263 PASS** | [`logs/w7g-run_tests.log`](logs/w7g-run_tests.log) |
| `test_m2_player.gd` | **fails=0, 11 PASS** | [`logs/w7g-m2.log`](logs/w7g-m2.log) |
| E2E tiers 1–4 | **264/264, fails=0** | [`logs/w7g-e2e.log`](logs/w7g-e2e.log) |
| `probe_leak.gd` (`TAT2_NO_DEN_PROBE=1`) | **clean**, 0 leaks | [`logs/w7g-probe_leak.log`](logs/w7g-probe_leak.log) |
| Guildhall roughness line (first load) | 86 bakes / 73.9 M px / 4089 ms / 98.6 MB / 46 hits | same `run_tests` log |
| roughness cache probe | shared, distinct range, teardown re-bake | [`logs/w7g-rough-cache.log`](logs/w7g-rough-cache.log) |
| `test_perf_guard.sh` | **78/78** | §1.5 |
| export stamp + PCK | §1.1 | [`logs/w7g-export.log`](logs/w7g-export.log) |
| core bake + headless load | 194.0 MiB; VmHWM 782 MB | [`logs/w7g-bake-core.log`](logs/w7g-bake-core.log), [`logs/w7g-core-load.log`](logs/w7g-core-load.log) |
| visible editor open | VRAM threshold **not evaluable**; VmHWM 3,934 MB | [`logs/w7g-core-visible.log`](logs/w7g-core-visible.log) |

Machine-readable quote checked by `tools/check_gate_ratchet.py` (values read
from `gate_ratchet.json`): `compile | 110/0`, `run_tests | 263`, `M2 | 11`,
`E2E | 264/264`, audit base `12657/12703`.

**Not measured / not run:**

* `make audit` — **not measurable in this worktree**: W7S's uncommitted loot
  producers changed 4 `gen:gameplay` files plus the directory hash; integration
  regenerates and re-stamps at the merged HEAD. No audit log is committed and no
  audit floor was changed.
* `make texture-cap-check` — not re-run this wave; the base floor is unchanged
  in the ratchet and integration must re-measure.
* the perf matrix (`run_perf_matrix.sh`) — explicitly **not run**; the wrapper's
  new stamp/RSS/`MemoryMax` paths were tested without a game.
* a Vulkan visual capture (no rendering change in this wave).
* a SonarCloud scan (manual steps above).

---

## 6. Decisions and residuals

* **Bake stays full-resolution.** The memory decision was already made in W6L;
  this wave adds the process cache and the byte accounting, not a quality
  trade-off. A half-res path would halve the ~98.6 MB but is not taken.
* **The stamp is the only publishable path.** A dirty tree still builds (useful
  for QA) but is never `publishable=1`; an explicit `PERF_BINARY` override is
  labelled `unverified_override`.
* **The editor VRAM threshold is unproven, not passed.** `nvidia-smi
  memory.used` is a device-wide instrument; a per-process measurement is still
  required, and the harness-terminated open is not an acceptance result.
* **`MemoryMax` is a guard, not a budget.** 75 % of RAM is deliberately
  generous; the enforced number is still the RSS ceiling, and both are logged.
* **Sonar remains a tooling gate.** It cannot see GDScript; the ratchet plus the
  committed gate logs are the game-quality floor, and the Sonar gate stays
  unbound until the manual steps in §4.2.
* **Residuals:** the core bake is 194.0 MiB against a 256 MiB guard (52.6 MiB
  margin); audit drift belongs to W7S and must be resolved at integration; the
  perf matrix and a clean per-process editor VRAM measurement remain open.
