# W5F — SonarCloud project configuration and P0 cleanup

Worktree: `/tmp/opencode/tat2-w5f-sonar` (branch off `950f7ca`).
Scope: **tools/build/docs only.** No engine code, no `game/` runtime edit, no
Godot run, no local Sonar scan that would write a report or change the active
CLI organization.

## 1. Scope and CLI finding

| Fact | Value |
|---|---|
| SonarCloud project | `Heretek-AI_TAT-2` |
| SonarCloud organization | `heretek-ai` |
| Sonar CLI | `sonar` 1.13.1 (`/home/linuxbrew/.linuxbrew/bin/sonar`) |
| CLI active organization | `heretek-ai-1` |
| Tracked GDScript files | 127 |

The installed CLI is authenticated against the organization `heretek-ai-1`,
while the project lives in `heretek-ai`. Every issue query
(`sonar list issues`, `sonar analyze`) therefore addresses the wrong
organization and fails before it can return the 422 findings. Because of that:

* the issue keys quoted in this wave were **reconstructed by a local scan** of
  the tracked `tools/`, `build/qa/` and `docs/` sources, not fetched from the
  API. Where this report names a rule id (`S1244`) it is the rule family the
  finding belongs to, not an API-confirmed key;
* no `sonar analyze` / `sonar scan` was run. A local scan would write a report
  and can flip the CLI's working context, both of which this wave was told not
  to do.

**GDScript is not analyzed.** SonarCloud has no GDScript analyzer and the repo
declares no custom plugin, so the 127 `.gd` files — the player controller,
loader, AI, missions and UI, i.e. the actual game — contribute nothing to the
issue count. The 422 issues describe `tools/`, `build/` and `docs/` only. The
triage consequence is important: **the Sonar issue count must not be read as a
quality signal for TAT-2's game code.** GDScript correctness is gated by
`game/tests/run_tests.gd`, `test_m2_player.gd` and the E2E tiers.

The project currently has quality gate **NONE** and no coverage uploaded, so a
green Sonar run would say almost nothing even about the Python/Shell surface
(§7).

## 2. Configuration added

`.sonar-project.properties` (new, repo root):

* `sonar.projectKey=Heretek-AI_TAT-2`, `sonar.organization=heretek-ai`;
* `sonar.sources=tools,game` — hand-written, redistributable code only;
* exclusions: `docs/reference/**`, `extracted/**`, `game/assets/**`,
  `game/.godot/**`, `build/**`, `game/data/generated/**`, plus the other
  generated/derived trees the repo already treats as private
  (`game/i18n/generated/**`, `game/scenes/review/**`, `**/__pycache__/**`),
  the build outputs inside the scanned trees (`tools/**/bin/**`,
  `tools/**/obj/**`, `tools/ue4ss/cache|output/**`) and Godot's sidecars
  (`*.uid`, `*.import`, `*.log`);
* comments state the GDScript limitation and that the Sonar token must come
  from `SONAR_TOKEN`/the CLI config. **No credential, token or org-specific
  secret is in the file.**

`build/` is excluded as instructed. That is deliberate but has a cost: the
tracked QA harness under `build/qa/` (`.gd` capture/probe scripts, a few `.py`
and `.sh` helpers) drops out of analysis. It is almost entirely GDScript, which
Sonar cannot read anyway, so nothing analyzable is lost today. If the `build/`
findings ever need tracking, add `build/qa` to `sonar.sources` rather than
weakening the exclusion.

## 3. P0 fixes

All five edits are behaviour-preserving; §6 proves it for the producer whose
output is hashed by `make audit`.

| File | Finding | Change |
|---|---|---|
| `tools/prebake_texture_cap.py` | `_revert()` was annotated `-> int` and returned the literal `0` on every path (invariant return) | `-> None`; both `return 0` statements became bare `return`; the single caller (`main`) now does `_revert(...); return 0` |
| `tools/extract_audio.py:405` | dead ternary in the `alert` envelope: `(lt if t < 0.30 else lt)` — both branches are `lt` | collapsed to `(0.30 - lt)`, which is what the expression already evaluated to |
| `tools/fetch_vgmstream.sh` | `curl` download with no protocol restriction | `curl -fSL --proto '=https' --retry 3 …`; the URL is already `https://`, so the download is unchanged |
| `tools/tat-extract/Program.cs` | `new Regex(...)` for `--filter` with no match timeout (ReDoS) | added `TimeSpan.FromSeconds(2)` as the third argument |
| `tools/manifest_audit.py:1509` | `oldest_out = 0.0` used as a "not set" sentinel and tested with `==` | `oldest_out: float \| None = None`, tests are `is None`, and the empty-group branch also guards `oldest_out is None` so the type narrows before `stale = oldest_out < newest_src` |

### 3.1 `extract_audio.py:405` — intent, and the audio-owner question

The `alert` cue is two 660/520 Hz beeps over 0.70 s. `lt` is the *local* time
inside the current beep, so a per-beep fade-out would need the second beep's own
end (0.35 s) rather than the first beep's (0.30 s). The ternary as written does
not do that: it evaluates to `lt` in both branches, so both beeps fade over
0.30 s and the second one dies at ≈0.65 s, leaving a 0.05 s silent tail.

Two readings were possible:

1. **dead code only** — collapse to `(0.30 - lt)`. Same numbers, and it is
   coherent (two 0.30 s beeps, 0.05 s gap, 0.05 s tail). Chosen.
2. **wrong fade end** — the author meant `0.35 - lt` for the second beep. That
   would remove the fade-out entirely: with the `+1.0` in the envelope the tone
   would stop at full amplitude on the last sample (a click).

Option 2 changes the shipped `.wav` bytes and is an art call, not a lint fix.
**Decision: the dead ternary is fixed (option 1); the second-beep fade end is
left as an audio-owner decision** — if the cue should be re-voiced, change it in
a dedicated audio wave together with an intentional re-synthesis of
`game/assets/ue/audio/`.

## 4. Reported false positives — 5 anchor float-equality (`S1244`) findings

Not changed. Each compares freshly parsed data against a literal that came from
the same authored asset, with no arithmetic in between, and every one of them is
a fail-closed reproduction gate: approximating the comparison would let a
regenerated asset drift pass.

| # | Site | Why it is not a defect |
|---|---|---|
| 1–3 | `tools/parse_gameplay.py:365` — `out["Carpet"] != 0.0`, `out["Glass"] != 1.5`, `out["Dirt"] != 0.0` | The three anchor rows of `DA_LoudnessModifiers`, compared immediately after `float(entry["Value"]["Multiplier"])` on the parsed UE JSON. `0.0` and `1.5` are exactly representable in binary64 and arrive as exact decimal text, so the comparison is exact by construction. Any tolerance here would silently accept a changed shipped table (that is the point of the 22-surface + anchor-row gate). |
| 4 | `tools/check_clue_quests.py:567` — `anchor.get("pos") == expected["pos"]` | Compares the generated `personal_spider.json` anchor position (a list of decimal literals round-tripped through JSON) with the same literal written in the checker. No arithmetic, both sides are the identical decimal text, so `==` is the correct contract test. Positions are UE centimetre-authored pins; a tolerance would defeat the "anchor moved" check that W3O/W4O exist to enforce. |
| 5 | `tools/check_clue_quests.py:572` — `anchor.get("yaw_deg") == expected["yaw_deg"]` | Same argument for the two TAT-2 authored facings (`90.0`, `0.0`). Both are exact. |

Adjacent but *not* one of the five: `tools/check_clue_quests.py:363`
(`v == 1320.0`, the `MatchMainPhaseDuration` authored duration) has the same
character and should be marked as a false positive on the same grounds rather
than rewritten.

Recommended handling: mark these as **Won't fix / false positive in the
SonarCloud UI** with the reason above. No `sonar.issue.ignore.multicriteria`
entry was added, so the findings stay visible to a future reviewer instead of
being hidden in config.

## 5. Deferred batch — shell `[ ]` (≈147 findings)

Not touched this wave, as instructed. A local scan finds ~29 single-bracket
test sites in 9 tracked shell files (`build/qa/*.sh`, `tools/check_cbmignore.sh`,
`tools/ue4ss/*.sh`) plus Makefile recipe lines; Sonar reports 147 across the
shell surface (multi-condition lines and Makefile recipes account for the
difference). Converting them to `[[ ]]` is mechanical but touches every script's
error semantics (`[ ]` word-splits, `[[ ]]` does not), so it needs its own wave
with `bash -n` plus a real run of each script — not a drive-by edit next to the
P0 fixes.

## 6. Validation

| Check | Result |
|---|---|
| `bash -n tools/fetch_vgmstream.sh` | OK |
| `python3 -m py_compile tools/prebake_texture_cap.py tools/extract_audio.py tools/manifest_audit.py` | OK |
| `dotnet build tools/tat-extract -c Release` (`~/.dotnet10`, net10.0) | **Build succeeded — 0 errors, 15 warnings** (pre-existing NU1902/NU1903 package advisories + one pre-existing CS8603 at `Program.cs:87`) |
| `python3 tools/prebake_texture_cap.py --revert --dry-run` | runs, prints `manifest has no entries; nothing to do`, exit 0 (new `-> None` path) |
| `make texture-cap-check` | `targets: 1512 … offenders: 0` / `texture cap check: OK` |
| `make audit` | content gates all OK (levels/contracts/tables/materials/containers/decals/devices/animations/audio/localization/videos/scene_variants/niagara, mount/path 100.0 %, exact-case 99.4 %, 0 unexpected); **fails on 4 producer/infrastructure stamp entries only** — see §6.3 |

### 6.1 Producer output byte-identity

| Producer | Evidence |
|---|---|
| `extract_audio.py` | The 9 synthesized fallback cues generated by the **HEAD** version and by the fixed version are byte-identical (`old==new=True` for all 9), and both are byte-identical to the `.wav` files already in `game/assets/ue/audio/` (`new==tree=True`). `alert.wav` sha256 `4d93581c7bc1…`, 15434 samples. A sample-level comparison of the old and new envelope over all 33 600 samples of the alert cue reports **0 differences**. |
| `manifest_audit.py` | The HEAD version and the fixed version were both run against the same tree (freshness + content + baseline). **stdout is byte-identical and both exit 1** with the same four stamp failures: no freshness or content decision changed. |
| `prebake_texture_cap.py` | `_revert` has no output; `_apply`/`_check` are untouched (diff is 8 lines, all in `_revert` + its caller). `--check` is green. |
| `fetch_vgmstream.sh` | `--proto '=https'` on an `https://` URL: no byte of the downloaded archive changes; `bash -n` clean. |
| `Program.cs` | Build-only; the regex timeout does not change matching for non-pathological input, and the binary is not part of any audit hash set. |

No producer output was regenerated (that would write through the read-only
`game/assets`/`game/data` symlinks into the main checkout), and no output is
intentionally behaviour-changing.

### 6.2 Not run (by constraint)

* No Godot, no `make test`, no E2E. Nothing in this wave touches `game/`.
* No `sonar analyze` / `sonar scan` (would write a report and can change the
  CLI's active org), so the finding count is unverified after the fixes.

### 6.3 `make audit` still fails on 4 stamp entries — deliberate, and the one action left

`make audit` fails closed (correctly) because the tracked baseline
`tools/audit_baseline.json` pins the sha256 of every producer. It reports:

```
FAIL: baseline: producer tools/extract_audio.py changed since the baseline (sha256 2212587ffbf8 -> 8429ad8ead48)
FAIL: baseline: infrastructure root:tools/tat-extract/Program.cs changed since the baseline
FAIL: baseline: infrastructure root:tools/prebake_texture_cap.py changed since the baseline
FAIL: baseline: infrastructure root:tools/fetch_vgmstream.sh changed since the baseline
```

`--refresh-stamps` cannot clear the first one from here by design: it refuses a
changed producer whose outputs are "neither newer than the producer nor hash/
count changed" — exactly the case of an intentionally no-op producer edit run in
a checkout whose outputs are the untouched originals. Regenerating is also
impossible without writing through the symlinks into the main checkout.

**Follow-up on the integration checkout after cherry-pick** (≈2 min, no output
content changes — the §6.1 hashes are what `normalize` will reproduce):

```bash
make normalize            # rewrites byte-identical outputs, making them newer than the producers
make build-extractor      # stamps Program.cs
make desktop-texture-cap  # stamps prebake_texture_cap.py + reimports
make audio-tools          # stamps fetch_vgmstream.sh (no download; binary already present)
make audit-refresh-stamps
make audit                # must be exit 0
```

The resulting `tools/audit_baseline.json` diff should be **only** those four
`sha256` values (plus `updated_at`). If it shows changed output hashes or a
changed `files` count, something did change and the fix must be re-examined.

## 7. Gate and coverage recommendations

1. **Switch the CLI to the project's org** (manual, machine-local): re-auth or
   `sonar config set` the organization to `heretek-ai` (and the project key to
   `Heretek-AI_TAT-2`), then verify with a read-only `sonar list issues`. This
   needs the account that owns the project; it cannot be done from a repo file
   and was out of scope here.
2. **Create a real quality gate** — the project is on `NONE`, i.e. nothing can
   fail. Minimum useful gate for the analyzable surface:
   `reliability_rating = A`, `security_rating = A`,
   `new_blocker_violations = 0`, `new_critical_violations = 0`,
   `new_major_violations = 0`, `duplicated_lines_density ≤ 3 %`.
   Do **not** set a coverage condition until (3) lands, or the gate will sit
   "no coverage" and teach people to ignore it.
3. **Coverage** — today no coverage report exists for any producer. Cheapest
   real start: `pytest --cov=tools`-style collection cannot work directly
   because the checker scripts are `main()`-style, so the honest first step is
   `coverage run -m pytest` around `tools/test_manifest_audit.py` *after*
   splitting its asserts into importable functions, then
   `coverage run tools/manifest_audit.py …`, `coverage run tools/check_clue_quests.py`,
   `coverage run tools/check_devices_runtime.py`, combined with
   `coverage combine` → `coverage xml -o build/coverage/coverage.xml`, uploaded
   via `sonar.python.coverage.reportPaths` (already stubbed, commented, in
   `.sonar-project.properties`). `tools/tat-extract` would need
   `coverlet` + a test project to be covered at all; that is a larger project
   and should not block (2).
4. **The coverage number will be misleading while GDScript is invisible**: the
   "coverage on new code" condition would only ever see Python/Shell. Add a
   second, non-Sonar CI job for the game: `tools/godot --headless` compile
   check + `run_tests.gd` + tier-1 E2E, and treat *that* as the game's gate.
   There is no CI workflow in the repo today, so Sonar analysis is manual; a
   workflow that runs `check_scripts_compile.gd`, `make audit` and the scanner
   would make both gates real.

## 8. Files changed

```
.sonar-project.properties          new
tools/prebake_texture_cap.py       _revert -> None, caller updated
tools/extract_audio.py             dead ternary collapsed (behaviour-identical)
tools/fetch_vgmstream.sh           curl --proto '=https'
tools/tat-extract/Program.cs       Regex match timeout
tools/manifest_audit.py            None sentinel instead of 0.0
docs/reports/w5f-sonar-p0.md       this report
```

`tools/audit_baseline.json` is **not** in this commit; see §6.3.
