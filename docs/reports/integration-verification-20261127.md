# Final integration verification — `phase12-integration` @ `5a66567`

**Audit target:** `/home/john/.local/share/opencode/worktree/318f41/phase12-integration`
**Tip:** `5a66567f766fb1bbab6a7d1c57a56c871dbb5b91` (`phase12-integration`, `main`, `origin/main`)
**Measured code/gate head:** `37bb69e`; the final 49-gate run was made at its
docs pre-stamp `60474c0` (code identical to `37bb69e`)
**Method:** `git`, `grep`, `python3`, and the committed logs only. No Godot, GPU,
Vulkan/Xvfb or Steam process was started by this audit; no repo file was edited.
**Report path:** `/tmp/opencode/integration-verification-final-20261127.md`

## Verdict: PASS

All four formal findings from the first audit are closed: the six cherry-picked
verifier tips have a provenance table with independently reproduced patch-ids,
the in-run `gate_ratchet.log` is the runner's wrapped log with the exact hash,
the stale current-status claims are replaced by the final values, and the tree
is clean at `origin/main = 5a66567`. The substance re-checks green, and the GPU
evidence lane is included in `37bb69e` with its four open gaps explicitly
measured and declared.

One residual documentation nit: the mirror *fix* `dd0bec8` (tip of the
`p4-mirrors` branch) is **not** an ancestor of `5a66567`; its stable patch-id is
identical to `8111bbe`, which is an ancestor and is the commit used by the GPU
evidence. The report's provenance table covers the six verifier tips and the
mirror verifier tip (`07ecb56`), but does not list `dd0bec8`/`8111bbe`. This does
not break the six-tip cherry-pick contract, but it is not literal ancestry for
`dd0bec8`.

## 1. Cherry-pick provenance — CLOSED for the six verifier tips

`docs/reports/integration-20261127.md:39-57` adds the “Cherry-pick provenance”
table. I independently ran `git show <tip> | git patch-id --stable` and the same
on the integrated commit for all six pairs:

| Lane | Verifier tip | Integrated commit | Patch-id result |
|---|---|---|---|
| landscape/beams | `371eb4a` | `acf5953` | **SAME** `7b3bd0093a1039644411cba7faf467b640ab6df3` |
| GC/bookcases | `dfa1a40` | `66fcbd4` | **SAME** `2d04d7c3dab7634307f10d73267548e1e6576f63` |
| navmesh | `0200d62` | `178c4aa` | **SAME** `3cc23f76cd05fb7e40713d8ae049f52459824e29` |
| audio W11 | `f4b907f` | `262d138` | **SAME** `e0468f2277bec32a11e8cdc2824b5289c39c628f` |
| P4 exposure/IBL | `26ed975` | `93a518b` | **SAME** `290b614f9e15784adcac1533ecd1e4b6e8637b18` |
| UI | `b4471e9` | `495e554` | **SAME** `8c93e7a23ab8886cbc51d82a904b2da95e41999c` |

The table's prefixes at `docs/reports/integration-20261127.md:48-53` match these
full ids. The report's reproduce command (`:56-57`) is the one used here.
Patch-id equivalence is accepted as the cherry-pick contract; the six pairs are
closed.

**Mirrors:** `07ecb56` and `dffb35f` are ancestors of `5a66567`
(`git merge-base --is-ancestor` = 0). `dd0bec8` is the **tip of `p4-mirrors`**
(a fix after the verifier report) and is **not** an ancestor; its patch is
preserved in `8111bbe` (`git patch-id` both = `58174ae13e087dd202365b35675678c744849881`),
which is an ancestor. The GPU evidence cites `8111bbe`
(`docs/reports/gpu-phase12-20261127.md:465`), but the provenance table does not
list this seventh replay. This is the only residual provenance/documentation
gap; content is preserved.

## 2. In-run `gate_ratchet.log` — CLOSED

`docs/reports/logs/final/gate_ratchet.log`:

- starts `== FINAL_GATE gate_ratchet` (`:1`) and ends `EXIT: 0` /
  `FINISHED: 2026-11-27T17:28:55-05:00`;
- sha256 **`7d859b9740a50710bf127c1b126ae513d59431f82f2540cbd1ac30944c2912b2`**
  (`sha256sum`), size **11,088** bytes, mtime **2026-11-27 17:28:55**;
- `PASS: measured_on=37bb69e` (`:24`), `PASS: report names measured_on=37bb69e`
  (`:191`), `GATE_RATCHET: PASS` (`:193`).

`gate_ratchet_poststamp.log` is a separate file (mtime 17:29:34, size 10,879,
different content; it is a post-run baseline check, not the gate log).

The final run:

- `docs/reports/logs/final/final-run.log:4` head
  `60474c004d21b0f19481cdf0b223afde2e12a78a`, started 17:06:31,
  `uncommitted_entries_at_start: 0`;
- exactly **49** `FINAL_GATE name=` entries (`:15-107`), **49/49 exit=0**
  (`grep -c '^FINAL_GATE name=.* exit=0 '` = 49);
- `:108` `FINAL_GATES PASS head=60474c004d21b0f19481cdf0b223afde2e12a78a gates=49`;
- `final-summary.txt` has 49 lines, all `exit=0`, and its names match the
  runner's 49 gates exactly (`comm` no differences).

`37bb69e..60474c0` touches only `AGENTS.md`, `docs/HANDOFF_NEXT_AGENT.md`,
`docs/reports/integration-20261127.md` and `tools/gate_ratchet.json`; the code is
identical to `37bb69e`, so the pre-stamped run measures the declared code head.
`60474c0..5a66567` touches only the integration report and
`docs/reports/logs/final/**`; no code or test file changed.

## 3. Stale docs — CLOSED for current claims

Grep of `AGENTS.md`, `docs/HANDOFF_NEXT_AGENT.md`,
`docs/FIDELITY_GAPS.md` and `docs/reports/integration-20261127.md`:

- `324 checks` — **none**.
- `45 gates` — **none**.
- `poses=6` — **none**.
- `21/21` (self-test) — **none**.
- KF27 `7/7` — **none**; the remaining `7/7` hits are producer tests
  (`AGENTS.md:112`, `:545`; `HANDOFF:144`; `integration:133`) and the
  `86/47/7/44/31` probe counts.
- `measured_on=71e77f6` — **none**.
- `45/45` remains only in explicitly historical Phase 0b prose
  (`AGENTS.md:262`, `HANDOFF:438`, `FIDELITY_GAPS.md:149`).
- `154 runtime` / `144 de-dup` remain only in the explicitly historical W9
  paragraph (`AGENTS.md:150-153`), not in the current table or Definition of
  Done.

Current values are present and consistent:

- `327 checks` — `AGENTS.md:64`, `:88`, `:132`; `HANDOFF:121`; `integration:110`.
- `49 gates` — `AGENTS.md:69`, `:85`, `:131`, `:550`; `HANDOFF:9`, `:92`,
  `:116`, `:154`; `integration:105`.
- `poses=7` — `AGENTS.md:110`; `HANDOFF:143`; `FIDELITY_GAPS.md:399`.
- `23/23` self-test — `FIDELITY_GAPS.md:399` (`23/0` in the other tables);
  committed `docs/reports/logs/p0b/self-test/self-test.log` ends
  `P0B_SELFTEST PASS checks=23 fails=0`.
- KF27 `9/9` — `AGENTS.md:110`; `FIDELITY_GAPS.md:400`;
  `docs/reports/logs/final/p0b_kf27_reference.log:7`.
- locks `162 = 152 + 10` — `AGENTS.md:98`, `:134`, `:527`; `HANDOFF:128`;
  `FIDELITY_GAPS.md:46`, `:601`; `integration:127`.
- `measured_on=37bb69e` — `AGENTS.md:85`, `:118`;
  `tools/gate_ratchet.json:3`; `gate_ratchet.log:24`, `:191`.

Historical W9 prose is the only remaining `154 runtime`/`144 de-dup`
occurrence; it is labelled “The 2026-11-25 W9 wave” and is not a current claim.

## 4. Clean tree / origin — CLOSED

- `git status --porcelain` = **empty** (0 entries).
- `HEAD` = `origin/main` = **`5a66567f766fb1bbab6a7d1c57a56c871dbb5b91`**.
- `git diff --name-only 7de2f0c..5a66567` filtered for `extracted/`,
  `game/assets/ue/`, `game/data/generated/` = **NONE**.
- Tracked generated/extracted/UE-asset files: `game/data/generated/` = 0,
  `extracted/` = 0, `game/assets/ue/` = 0.
- `build/` changes in the range are only tracked QA sources
  (`build/qa/*.gd`, `*.sh`, `*.py`, `*.json`); no `build/` PNG/log/binary
  artifact (`grep` for `build/.*\.(png|jpg|jpeg|webp|exr|hdr|bin|pck|log|wav|ogg)$`
  = none).
- No binary/asset paths in the whole range.

## Substance re-check

- **49/49:** `final-run.log` 49 gate entries, all `exit=0`, `FINAL_GATES PASS …
  gates=49`; `final-summary.txt` 49/49.
- **Ratchet floors only raised:** `tools/gate_ratchet.json` vs `912a481` has no
  lowered value; only raises/additions (compile 217→228, run_tests 324→327,
  locks 154/144→162/152, beams 7→9, P5 44→54, audio 71→123, poses 6→7, plus the
  new nav/landscape/VO/AEM/cubemap/self-test/route/capture-filter gates).
  `measured_on=37bb69e`.
- **No test weakened:** `git diff --name-only cb19415..5a66567 -- game/tests`
  is empty. The only harness changes are `build/qa/mirror_probe.gd` (correct
  +Z winding and viewport-scaled sampling) and `build/qa/capture_p5_ui.gd`
  (flatten sidecar extras), both fixes; no assertion or floor was removed. The
  49-gate counts are unchanged: compile 228/0, run_tests 327/0, audio 123, VO
  53, AEM 77, cubemap 37, P5 54, beams 9, landscape 7, nav 70, GC 52, locks
  162/152/10, E2E 300/300, a2 22/22, p2 17/17, capture 7/23/9-of-9, audit
  12660/12703, texture 1567/796/1/0, string 112, perf 78.
- **Data markers:** `ibl/cubemaps.json` = 3 cubemaps / 18 faces / 0 rejected;
  nav manifest = Guildhall 2958 tiles/14709 polys, Old Manor 1469/9059, FTUE
  1558/5576; `ui/stealthball_array.json` = `payload_present`, 21 authored
  slices, `mapping.kind=directional`; `audio_control.json` `music.containers=2`,
  keys 9 / resolved 6. Final `P5_UI PASS checks=54` with
  `GEM_PAYLOAD present=true: layers=21 table=21 kind=directional slice=9 missing=[]`.
- **GPU evidence `37bb69e`:** ancestor of `5a66567`; mirror readback
  `MIRROR_PROBE RESULT … pass=1` (`docs/reports/logs/p4-mirrors/p4mirrors_final.log:42`,
  wrapper `EXIT=0`); UI sidecar fix at `06c8956` and final run
  `docs/reports/logs/phase2-ui/20261127T215654Z/run.md:32,45,46` —
  `captures=28 failures=0`, 28 sidecars, all 28 carry `roi.*`, and every
  mission sidecar records `hud.gem=path:authored_array bound:true layers:21`.
  Open gaps are explicitly measured and declared:
  **KF27 5/9** (`gpu-phase12-20261127.md:141`), **landscape A/B no subject**
  (`:120-127`), **AEM meter 0.2615 vs authored 1.150** (`:246-254`), **prompt
  contrast 3.24–4.32** (`:609`, `ui_pixel_stats.log:7,8,11,12`). These are
  known residuals, not gate failures; the 4.5 prompt floor was not lowered.

## Residual risks (non-blocking)

1. **Mirror fix provenance** — `dd0bec8` is not an ancestor; `8111bbe` is its
   patch-identical integrated commit (ancestor, used by the GPU run). The
   provenance table should add this seventh replay row for completeness.
2. **AEM/VO/cubemap standalone log freshness** — the 53/77/37 ratchet evidence
   logs are the pre-run standalone logs; the 49-gate `run_tests` suites re-run
   the probes and check `fails=0`, but not the counts. The counts are unchanged
   and match the final table.
3. **Historical W9 wording** — `AGENTS.md:150-153` still says 154/144 in the
   explicitly historical W9 paragraph; current table/DoD say 162/152.
4. **GPU residuals** — KF27 5/9, landscape no subject, AEM meter residual and
   prompt contrast 3.24–4.32 remain open by design; they are measured and
   declared, not hidden.
