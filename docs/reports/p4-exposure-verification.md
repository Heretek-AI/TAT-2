# P4.1 exposure + IBL lane — verification (2026-11-27, re-check at `bce2ed3`)

**Verdict: PASS (both named blockers closed).**

Re-check of fix commit `bce2ed3d89d35b9a9ac6b03a0eee8e459a296b76`
(parent `2c73291`), branch `p4-exposure`, worktree
`/home/john/.local/share/opencode/worktree/318f41/phase1-p4-exposure`.
Read-only apart from the extractor build (gitignored `bin/obj`), `/tmp`
outputs and this report. No GPU, Vulkan, Xvfb, Steam or capture was used.
All HEAD-stamped logs below were written from this worktree at
`bce2ed3`:

```
$ git rev-parse HEAD
bce2ed3d89d35b9a9ac6b03a0eee8e459a296b76
```

The two original blockers are closed:

1. **Cubemap compile/decode:** `make build-extractor` is green (0 errors) and
   the real `tat-extract cubemaps` run writes 3 cubes / 18 faces; the pinned
   API is now used correctly and the six faces are sliced from
   `CTexture.Data` (no `Crop`). See F1.
2. **Speed semantics:** `step()` now selects `speed_up` for a rising target
   (`delta > 0`) and `speed_down` for a falling target; suite 123 measures
   20.00 s / 2.00 s and the `t_up > 5 * t_down` negative control. See F2.

The default `TAT2_AEM=fixed` and `TAT2_IBL=off` paths remain no-op-compatible
(T07 still reads exposure 1.150 / ambient 0.160; no `weather_profile.gd` or
`cubemap_loader.gd` change). The new near-black cubemap data is recorded as a
non-blocking stage-1/GPU-A/B risk, not a default-path defect.

## F1 — CLOSED: extractor builds and decodes the real cubes

**Build (independent, at `bce2ed3`):**

```
$ make build-extractor
Build succeeded.
    15 Warning(s)
    0 Error(s)
Time Elapsed 00:00:02.96
BUILD_EXIT=0
```

Log: `/tmp/opencode/p4_verify_build.log` (HEAD-stamped; 0 `error CS` lines;
14 NuGet advisory warnings + the pre-existing `Program.cs:91` CS8603 nullable
warning). The pinned CUE4Parse-Conversion 1.2.2.202611 `CTexture` still has no
`Crop`; the code no longer uses one.

**Real run (independent, to a `/tmp` output):**

```
$ tools/tat-extract/bin/Release/net10.0/tat-extract cubemaps \
    --out /tmp/opencode/p4_cubemaps_verify \
    --usmap .../TAT-5.5.4-...usmap
  cubemap daylight: 256x256 PF_FloatRGBA srgb=False
  cubemap Cubemap_GroundFloor_01: 512x512 PF_FloatRGBA srgb=False
  cubemap T_FakeSpecular1: 128x128 PF_FloatRGBA srgb=False
[cubemaps] ok=3 skip=0 fail=0
errors -> .../errors.log (0 entries, this run only)
EXIT=0
```

Log: `/tmp/opencode/p4_verify_cubemaps2.log`. 18 `face_*.png` + 3
`cubemap.json` sidecars were written. The 18 PNGs and 3 sidecars are
**byte-identical** to the lane's shared
`extracted/assets/TAT/Content/Cubemaps/` output (sha256 comparison; the shared
tree additionally has Godot `.import` sidecars). The lane's real-run log is
`/tmp/opencode/p4_cubemaps_stderr.log` (`ok=3 skip=0 fail=0`,
0 errors).

**Slicing math / guards (source `tools/tat-extract/Exporter.cs:603-618,
644-662`):**

- `TextureDecoder.Decode(cube, opts.TexturePlatform)` at line 644 (the correct
  `(UTexture, ETexturePlatform)` overload; no `ExportOptions`).
- `SliceCubeFace` computes `bpp = BlockBytes / (BlockSizeX*BlockSizeY*BlockSizeZ)`;
  for `PF_FloatRGBA` the pinned table is `BlockSize 1/1/1`, `BlockBytes 8`, so
  `bpp = 8`, `rowBytes = width*8`, `faceBytes = rowBytes*faceH`, and
  `offset = faceBytes*index`. The raw 512 mip is 12,582,912 bytes =
  512·3072·8 = 6·512·512·8; the 128 mip is 786,432 = 6·128·128·8. The real 256
  cube writes 256×256 faces. The contiguous six-face slice is therefore exact
  for the three authored FloatRGBA cubes.
- Fail-loudly guards: `decoded.Height % 6 == 0` before slicing; square-face
  guard `decoded.Width == faceH`; `bpp <= 0` rejects block/unsupported formats;
  `offset + faceBytes > src.Data.Length` rejects a short/oversized buffer;
  non-six-face/missing-package/decode/encode errors go to `Count(..., false)` and
  `errors.log`.
- Control: running the same binary **without** a usmap produced
  `[cubemaps] ok=0 skip=0 fail=3` with three `MappingException` lines and
  `errors.log` entries (`/tmp/opencode/p4_verify_cubemaps.log`). The extractor's
  process exit is still 0 on `fail>0` (`Program.cs:84` returns 0 after
  `Report()`), so the audit's `errors.log` check — not the process exit — is the
  fail-closed gate. This is a non-blocking hardening note; the real run is 0
  failures and the audit log reports `errors.log: 0 ... 0 unexpected`.

**Producer acceptance:** `parse_cubemap.py` was run against the independent
`/tmp` output (output redirected to `/tmp` so the shared generated tree stayed
untouched): `cubemaps: 3 converged, 0 rejected`, 18 faces,
`faces_order = px/nx/py/ny/pz/nz`, and `by_ue_path` for all three:
`/Game/MaterialLibrary/Utility/Cubemap_GroundFloor_01`,
`/Engine/MapTemplates/daylight`,
`/Game/ThirdParty/FluidNinjaLive/UseCases/007_SmallWater/T_FakeSpecular1`.
Log: `/tmp/opencode/p4_verify_parse_cubemap.log`.

## F2 — CLOSED: authored SpeedUp/SpeedDown

`game/src/core/auto_exposure.gd:152` now selects:

```gdscript
var rate: float = speed_up if delta > 0.0 else speed_down
```

with the authored `speed_up = 0.2`, `speed_down = 2.0`. A rising target
(EV100 rising, dark → bright) is `SpeedUp` at 0.2 (20 s for +4 EV100); a
falling target is `SpeedDown` at 2.0 (2 s for −4 EV100). This matches UE's own
documentation (Speed Up = dark environment to bright environment; Speed Down =
bright environment to dark environment) and the repo RE's 20 s bright-foyer
statement.

Suite 123 was run independently at `bce2ed3`:

```
PASS: SpeedUp ramp is +0.2 EV100/s per 0.1 s (delta=+0.020000)
PASS: +4 EV100 settles at 20.0 s at the authored SpeedUp 0.2
PASS: SpeedDown ramp is -2.0 EV100/s per 0.1 s (delta=-0.200000)
PASS: -4 EV100 settles at 2.0 s at the authored SpeedDown 2.0
PASS: +4 EV100 (SpeedUp) is strictly slower than -4 EV100 (SpeedDown) (t_up=20.00s t_down=2.00s)
PASS: measured settle times are the authored 20 s / 2 s (t_up=20.00s t_down=2.00s)
AEM_PROBE: fails=0 passed=70
```

Log: `/tmp/opencode/p4_verify_aem.log` (HEAD-stamped). The probe contains the
requested negative control at `game/tests/probe_auto_exposure.gd:284-292`; the
old inverted mapping would give `t_up=2`, `t_down=20` and fail the
`t_up > 5*t_down` line.

**Fixed path:** the fix diff is limited to `Exporter.cs`, `auto_exposure.gd`,
`probe_auto_exposure.gd` and the lane report; `weather_profile.gd` and
`cubemap_loader.gd` are untouched. Suite 123 reports
`fixed reproduces today's 1.15 exactly`; T07 reports
`exposure=1.150 ambient_energy=0.160`; the default fixed smoke has no AEM
opt-in line. The default `fixed` path is unchanged.

## Re-run gates at `bce2ed3` (HEAD-stamped)

| Gate | Result | Log |
|---|---|---|
| `make build-extractor` | `Build succeeded`, 15 warnings, **0 errors**, exit 0 | `/tmp/opencode/p4_verify_build.log` |
| `tat-extract cubemaps` (real, `/tmp`) | `ok=3 skip=0 fail=0`, 18 faces, 0 errors | `/tmp/opencode/p4_verify_cubemaps2.log` |
| `parse_cubemap.py` (temp output) | `3 converged, 0 rejected`, 18 faces, 3 `by_ue_path` | `/tmp/opencode/p4_verify_parse_cubemap.log` |
| compile | `scripts checked: 223, broken: 0`, exit 0 | `/tmp/opencode/p4_verify_compile.log` |
| `make test` | **326** `PASS:` lines, `SUMMARY: fails=0`, exit 0 | `/tmp/opencode/p4_verify_make_test.log` |
| suite 123 | `AEM_PROBE: fails=0 passed=70` | `/tmp/opencode/p4_verify_aem.log` |
| suite 124 | `CUBEMAP_PROBE: fails=0 passed=25` | `/tmp/opencode/p4_verify_cubemap.log` |
| T07 | `T07_SUMMARY: fails=0`; Guildhall `exposure=1.150 ambient_energy=0.160` | `/tmp/opencode/p4_verify_t07.log` |
| `make gate-ratchet` | PASS (committed logs/floors untouched) | terminal run in this worktree |
| `make audit` | expected red until `make normalize` + re-stamp (8 failures; new `stale generated group materials` from the Cubemaps faces) | `/tmp/opencode/p4_fix_audit.log` |
| runtime smoke (fixed/default) | **HEAD-stamped PASS**: `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok`; wrapper `RUNTIME_SMOKE PASS`, exit 0 | `/tmp/tat2-smoke-LMhWfF.log`; `/tmp/opencode/p4_verify_smoke_fixed_wrap.log` |
| runtime smoke (`model TAT2_IBL=ambient`, `meter`) | not HEAD-stamped; pre-fix fixed/model/meter logs and the model anchor are covered by suite 123; no new code path in the fix | `/tmp/tat2-smoke-c36vqx.log`, `/tmp/tat2-smoke-YjDSoX.log` (pre-fix); see residual 6 |

The lane's own `/tmp` fix logs agree on the build (15 warnings/0 errors),
the real 3/18-face run, 326 PASS and the 8 expected audit failures; the 70/25
probe counts and T07 are from the HEAD-stamped standalone runs above (the
`p4_fix_test.log` only reports the suites as PASS, not their child counts).

The runtime smoke gate is now HEAD-stamped for the default/fixed path:
`p4_verify_smoke_fixed_wrap.log` ran at `bce2ed3`, the scanner returned
`RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 ... mission_ready=1`, and the
Godot log has no AEM opt-in line and no `ERROR:`/`SCRIPT ERROR`/`SHADER ERROR`.
The `model TAT2_IBL=ambient` and `meter` smoke modes were not re-run at this
HEAD; the fix changes only the `step()` selection, and suite 123 already pins
the model anchor and the meter CPU mirror. This is an evidence-completeness
note for those two opt-in modes, not a fixed/default regression.

## Conditional data blocks — still PENDING without `make normalize`

`make normalize` was **not** run. The shared generated tree is unchanged:
`game/data/generated/ibl/cubemaps.json` is absent, and
`game/data/generated/weather/gloomy.json` still lacks the new AEM fields.
Therefore at `bce2ed3`:

- Suite 124 prints `PENDING: res://data/generated/ibl/cubemaps.json absent;
  the integrator runs the cubemaps extract + parse_cubemap...` and passes
  **25** checks (the no-index path).
- Suite 123 prints `PENDING: weather/gloomy.json predates the P4.1 producer
  fields...` and passes **70** checks.
- If the integrator runs `make normalize`, the generated AEM fields and the
  `ibl/cubemaps.json` index appear and both generated blocks activate. If only
  `parse_cubemap.py` is run, the cubemap block activates but the weather AEM
  block remains PENDING. I verified the producer itself with a `/tmp` output
  (3 converged, 0 rejected); I did not leave a generated index in the shared
  tree.

## New data risk — record, not a blocker (default `TAT2_IBL=off`)

`TAT2_IBL=off` is still the default (`cubemap_loader.gd:53-63`), and
`weather_profile.gd` applies the cubemap only when `available=true`. The real
sidecars (`extracted/assets/TAT/Content/Cubemaps/*/cubemap.json`) show:

| cube | real face means / observation |
|---|---|
| `cubemap_ground_floor_01` (Gloomy SkyLight) | all faces ~2e-5–1.2e-3 (8-bit RGB); face-mean luminance ~1e-4. A raw CPU irradiance ambient would be ~0.0001 (means; not re-integrated here), not today's 0.16. No default change (`off`); the GPU A/B decides whether stage 1 needs normalization. |
| `daylight` (DenseFog Old Manor) | px/nx/py/ny/pz ~0.065–0.075 luminance; **`nz` is uniformly black (0.0)**. The orientation gauge computes `py=0.067962 < ny=0.071176` and therefore prints `CUBEMAP_ORIENT: WARN` at `probe_cubemap.gd:196-204`; the GPU A/B/face-order check must decide. |
| `t_fake_specular1` (Base/Examples) | only `pz` ~0.0039; five black faces. No default change. |

The 18 PNGs are in the shared extract; the generated index is not. These are
data/stage-1 observations, not compile or default-path defects.

## Non-blocking residuals / follow-ups

1. **Extractor process exit on per-file failure:** `Program.cs:84` returns 0
   after `Report()` even when `fail>0`; the per-cube errors are in
   `errors.log`, which the audit treats fail-closed (`errors.log: 0 unexpected`
   on the real run). The no-usmap control is `fail=3`, exit 0. Harden the exit
   code separately if the integrator's `make extract` must stop on `fail>0`.
2. **Linear-only AEM model:** `step()` is a pure linear ramp; UE 4.25+ has a
   linear phase plus an exponential tail within ~1.5 f-stops. The probe's
   exact 20 s / 2 s is the linear-phase result; the report's "UE AEM_Basic
   semantics" should be read as that approximation (or the tail implemented).
3. **`AT_CUBEMAP_PASS` plan label:** plan §4.1 names it; neither the extractor
   nor the report emits a literal marker. If it was a required acceptance
   marker, it is still absent; the substantive producer/consumer is present.
4. **Meter effect cleanup:** `auto_exposure_controller.gd:123-146` removes the
   compositor only when it owns it; if the camera already has a compositor,
   the meter effect remains in `compositor_effects` after the controller
   leaves. Meter-mode only; default `fixed` never creates the node.
5. **Anchor wording / re-pin:** the lane report calls scene −3.0 the "authored
   night anchor"; the RE says the exact converged EV100 is unknown, so this is
   the port's `EV_CURVE_NIGHT_EV100`/`NIGHT_EXPOSURE` anchor. If the GPU run
   re-pins `AEM_CALIBRATION`, update `AEM_FIXED_NIGHT_EXPOSURE` and the probe
   identity together, or the probe's `AEM_CALIBRATION * 2^7 == 1.15` check
   fails.
6. **Runtime smoke modes:** the default/fixed run is HEAD-stamped PASS
   (`exit=124`, errors 0, `mission_ready=1`); the `model TAT2_IBL=ambient` and
   `meter` modes were not re-run at this HEAD (the fix only changes the speed
   selection; suite 123 covers the model anchor and meter CPU mirror). Re-run
   those two opt-in modes when the shared Godot lock is free for a fully
   mode-complete smoke record.

## Scope / no push

`git show --stat bce2ed3` = 4 files, +168/−47:
`docs/reports/p4-exposure-ibl-lane.md`, `game/src/core/auto_exposure.gd`,
`game/tests/probe_auto_exposure.gd`, `tools/tat-extract/Exporter.cs`. No
weather_profile/mission_controller/cubemap_loader change in the fix. This
verification only adds `docs/reports/p4-exposure-verification.md`; the
extractor build wrote gitignored `tools/tat-extract/bin|obj`. The branch is
local: `git branch -r --contains bce2ed3` is empty; no push was made. The
docs-only verification commit SHA is reported in the handback/final response.
