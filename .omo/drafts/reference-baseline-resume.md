---
slug: reference-baseline-resume
status: approved
intent: clear
approval: approved by user via question tool on 2026-11-19 ("Approve"); plan authoring only, no execution
review_required: true
plan_path: .omo/plans/reference-baseline-resume.md
plan_sha256: null
review_round_id: null
review_round_limit: 5
pending-action: write and review .omo/plans/reference-baseline-resume.md
review:
  plan_reviewer:
    status: pending
    workspace_root: null
    runtime_home: null
    target: .omo/plans/reference-baseline-resume.md
    round_id: null
    plan_sha256: null
    launch_id: null
    session: null
    result: null
approach: Resume the existing OpenCode teamwork run 20261118-185627-d692 with its own sentinel session, repair the one stale worker_active task (zero committed output) by re-dispatching it in place, then drive the remaining DAG tasks (S14-S20, S21-S27, REFERENCE_BASELINE, COMPARISON_TEMPLATE, verify_baseline.py, M4 final) through worker -> verifier -> merge gates, run the mandatory security audit, merge the audited base into main under a conflict policy, clean up, and finish with a Senpi-side final verification wave.
---

# Draft: reference-baseline-resume

## Affected user and ideal state

People and consumers this output touches:

- **U1 - the owner (user).** Today: they have verified keyframes and callout legends for M2 but the footage breakdown stops at `S04`; they cannot yet compare their Godot port side by side against the official clip. After: they can follow one capture protocol, record the port slice, and score it against a complete, evidence-backed baseline.
- **U2 - the next comparison session (human or agent).** Today: must reconstruct clip facts and TAT-2 cross-references from `_carryover` scratch and old surveys. After: opens `docs/REFERENCE_BASELINE.md` + `COMPARISON_TEMPLATE.md` and works without re-deriving anything.
- **U3 - future repo readers/maintainers.** Today: a copied-in `_carryover/` scratch tree and probe files muddy what is authoritative. After: exactly one normalized spec, one legends file, one breakdown, one baseline, one template, one verifier; scratch is gone and history is clean.

| Row | Statement (ideal state) | Reason |
| --- | --- | --- |
| IS-1 | `BREAKDOWN.md` describes `S01-S27` continuously with all seven subsections per segment, explicit BGM presence/absence, measured audio levels, and citations opened against the current repo. | The breakdown is the spine of the comparison; a gap or an unmeasured audio claim makes the whole baseline untrustworthy. |
| IS-2 | `docs/REFERENCE_BASELINE.md` contains the ten required sections, a 27-row timeline + Mermaid flow, 18 subsystem rows, 8 PG + 9 HL matrix rows, and at least 60 checklist rows covering every segment, with port columns blank. | U1 needs one master target document; U2 needs the checklist without re-reading the clip. |
| IS-3 | `COMPARISON_TEMPLATE.md` mirrors the baseline checklist exactly (same row IDs, criteria, references, official observations), has 27 per-segment image slots and 27 alignment rows, and pre-fills no scores. | A drifting template silently compares the wrong criteria. |
| IS-4 | `tools/verify_baseline.py` implements all eight handoff checks, exits 0 on the finished tree, is deterministic, and proves renderer byte-identity without touching `annotated/`. | The user needs a repeatable proof, not a claim; the next session needs to re-run it cheaply. |
| IS-5 | Every shipped claim is evidence-backed: at least 12 adversarial spot checks (4 visual, 3 HUD verbatim, 3 audio, 2 gameplay timings), 6 annotated images re-opened, 8 citations re-opened, results in `## Verification log`; proven factual errors fixed and logged in `KEYFRAME_INDEX.md` `## Errata`. | A comparison-ready baseline fails if a label, timestamp, quote, or citation is wrong. |
| IS-6 | The mandatory pre-merge security audit PASSes with zero Critical/High findings and is recorded in `verify/security-audit.json` + `events.jsonl`. | The teamwork engine blocks the final merge on Critical/High; the user needs an auditable gate, not a skipped step. |
| IS-7 | After the final merge, `main` contains the finished baseline with only docs changes; no change to `game/`, repo-root `tools/`, `build/`, `extracted/`; folder <= 25 MiB; no `_carryover/`, `_build/`, or probe files; no push. | The handoff is docs-only and the user's game work must remain untouched. |
| IS-8 | The run is terminal and reproducible: all nine DAG tasks `verified_pass`, no stale `worker_active`, `verify/final.json` PASS, worktrees cleaned, and a final report lists files, counts, verifier output, spot-check results, `UNCERTAIN:` items, and the exact next step. | Resuming must not leave the same ambiguous half-state that forced this session. |

| Row | Today differs from | Why it matters | Closed by todos |
| --- | --- | --- | --- |
| GAP-1 | IS-1: `BREAKDOWN.md` has 223 lines and only `S01-S04`; `S05-S27` are absent. | M3a is the core deliverable and is 23/27 segments unfinished. | 2, 3, 4 |
| GAP-2 | IS-8: `breakdown-s05-s13` is `worker_active` round 1, its worktree is clean at `d55fd48`, its branch has zero commits ahead of base, and its worker session ended `idle/succeeded` at `03:09:07Z` with no durable output. | A stale active state blocks `teamwork_next`; marking it `worker_done` would send a no-op diff to a verifier. | 1, 2 |
| GAP-3 | IS-2: `docs/REFERENCE_BASELINE.md` does not exist. | U1/U2 have no master index or comparison framework. | 5 |
| GAP-4 | IS-3: `COMPARISON_TEMPLATE.md` does not exist. | The next recording session has no fill-in scorecard. | 6 |
| GAP-5 | IS-4: `tools/verify_baseline.py` does not exist. | M4 has no independent proof surface. | 7 |
| GAP-6 | IS-5: no M4 verification log, spot checks, or errata pass has run. | Claims are still worker self-reports. | 8 |
| GAP-7 | IS-6: no `verify/security-audit.json`; the security gate has never run. | The engine cannot legally reach the final merge. | 9 |
| GAP-8 | IS-7: `teamwork/base-20261118-185627-d692` (d55fd48) is not merged into `main` (6d6b4ba); the two branches diverged after `8a653df` and both added the same docs tree, so add/add conflicts are expected on every docs file the run modified. | The finished baseline is invisible to the user until it lands on their working branch. | 10 |
| GAP-9 | IS-7: `_carryover/`, `_build/`, `tools/.probe2`, `tools/.write_probe` are still present; folder is 16 MiB before `BREAKDOWN.md` and the new baseline grow. | Scratch material ships and the size budget can silently break. | 2-8 (cleanup in 8) |
| GAP-10 | IS-8: six DAG tasks are `pending`; two are `verified_pass`; no `verify/final.json`; eleven worktrees still registered (including three verifier worktrees and the sentinel). | The run cannot be called finished or safely re-entered. | 1, 9, 10 |

## Components (topology ledger)

| id | Outcome (one line) | Status | Evidence path |
| --- | --- | --- | --- |
| C1 | Resume/repair the run and re-dispatch the stale breakdown task | active | `.opencode/teamwork/20261118-185627-d692/state.json` |
| C2 | `BREAKDOWN.md` S05-S13 committed, verified, merged | active | spec-breakdown-s05-s13.json |
| C3 | `BREAKDOWN.md` S14-S20 committed, verified, merged | active | spec-breakdown-s14-s20.json |
| C4 | `BREAKDOWN.md` S21-S27 committed, verified, merged | active | spec-breakdown-s21-s27.json |
| C5 | `docs/REFERENCE_BASELINE.md` committed, verified, merged | active | spec-reference-baseline.json |
| C6 | `COMPARISON_TEMPLATE.md` (+ optional helper) committed, verified, merged | active | spec-comparison-template.json |
| C7 | `tools/verify_baseline.py` committed, verified, merged | active | spec-verify-script.json |
| C8 | M4 final: spot checks, hygiene, carryover deletion, merged | active | spec-m4-final.json |
| C9 | Security audit recorded PASS | active | `.opencode/teamwork/.../verify/security-audit.json` |
| C10 | Base merged into `main`, worktrees cleaned, final verification recorded | active | `verify/final.json`, git history |

No component is deferred: the user asked for the handoff end to end.

## Open assumptions (announced defaults)

| Assumption | Adopted default | Rationale | Reversible? |
| --- | --- | --- | --- |
| Resume mechanism | Drive the existing run through its existing OpenCode sentinel session (`ses_e0e53c38bffeUSx4c9ChYYfjKH`) and the `teamwork_*` plugin; do not reimplement the DAG in Senpi. | The state machine, security gate, verifier reports, and merge tooling already exist and hold 2 completed tasks; a reimplementation would duplicate them and lose the audit trail. | Yes (state on disk is authoritative). |
| Stale task handling | Treat `breakdown-s05-s13` as an attempt with no commit: set it back to `pending`, reuse the existing worktree/branch, re-dispatch round 1. Do not mark `worker_done` and do not run a verifier on an empty diff. | Verified: worktree `HEAD` = base `d55fd48`, `git status` clean, 4 breakdown sections, no `_build/audio-s05-s13.md` or `citations-s05-s13.md`; worker session `ses_e0e3d5d46ffei6zVJq1mpf3MjW` ended `succeeded` at `03:09:07Z` with no commit. | Yes. |
| Incremental durability | Every long-running worker commits after each completed segment (and its evidence file), not only at the end. | The previous attempt lost all in-flight work to a time-boxed pause. A commit per segment bounds rework to one segment. | Yes. |
| Final merge target | Merge `teamwork/base-20261118-185627-d692` into `main` with `--no-ff`, a backup ref, and docs add/add conflicts resolved to the base tree; abort on any non-docs conflict. No push. | The user asked for the "final merge"; the sentinel's documented final step is base -> user's working branch. `main` has a parallel snapshot commit, so a fast-forward is impossible. | Yes (backup ref + pre-merge commit). |
| Carryover deletion | Delete `_carryover/` only after `verify_baseline.py` exits 0 and `callout_spec.json` exists, as handoff rule 10 requires. | Explicit handoff instruction; contents remain in git history. | Yes (history). |
| Budget | Keep the run's `$20` default budget; no new paid service; the team models are the free `opencode-go/muse-spark` route. | `costs.json`: `budgetUsd: 20`, `spentUsd: 0`. | Yes. |
| Review | `review_required: true`: run plan-consultant gap analysis, then plan-reviewer rounds after approval. | Default-on in this skill; the user did not decline. | No (required before handoff). |
| Advisory lanes | `architect` and `ultrabrain` advisory consultations are skipped. | Both categories have no connected provider model on this machine; the skill says skip when unavailable. | N/A |

## Findings (cited - path:lines)

1. **Run state** - `.opencode/teamwork/20261118-185627-d692/state.json`: `hud-semantics` and `m2-audit` are `verified_pass` (rounds 1 and 2); `breakdown-s05-s13` is `worker_active` round 1, updated `2026-11-19T03:03:37.054Z`; `breakdown-s14-s20`, `breakdown-s21-s27`, `reference-baseline`, `comparison-template`, `verify-script`, `m4-final` are `pending` round 0.
2. **DAG order** - `plan.dag.json`: a strict chain `hud-semantics -> m2-audit -> breakdown-s05-s13 -> breakdown-s14-s20 -> breakdown-s21-s27 -> reference-baseline -> comparison-template -> verify-script -> m4-final`; `maxRounds: 4` each.
3. **Stale worker** - `/home/john/Projects/.teamwork-worktrees/20261118-185627-d692/breakdown-s05-s13`: `git log --oneline -1` = `d55fd48`; `git status --porcelain` empty; `grep -c '^## S' BREAKDOWN.md` = 4; `_build/` contains only `hud-semantics.md`, `m2-audit.md`, `m2_apply_fixes.py`, `m2_audit_validate.py`. Worker session `ses_e0e3d5d46ffei6zVJq1mpf3MjW` (title "Write breakdown S05-S13", parent `ses_e0e53c38bffeUSx4c9ChYYfjKH`) last updated `2026-11-19T03:09:07Z`, `idle_outcome` `succeeded`; no live worker process.
4. **Sentinel session** - `ses_e0e53c38bffeUSx4c9ChYYfjKH` is titled "Teamwork run 20261118-185627-d692", agent `team/sentinel`, directory `/home/john/Projects/TAT-2`, last updated `03:09:25Z`, `idle_outcome` `succeeded`. The `teamwork_*` tools are provided by the OpenCode plugin `opencode-teamwork-v2` (`~/.config/opencode/agents/team/sentinel.md:5-11`, plugin cache `opencode-teamwork-v2@latest`), not by Senpi.
5. **M2 state** - base `d55fd48` has 30 clean and 30 annotated JPEGs (confirmed 2026-11-19), `render_annotations.py --check` exit 0, `callout_spec.json` schema 1.1 with 30 keyframes and 195 callouts, `CALLOUT_LEGENDS.md` with 30 sections and 195 data rows, `BREAKDOWN.md` with 4 sections plus a complete header (metadata table, contents list, Mermaid flow, audio-method note), folder 16 MiB. `verify/report-m2-audit.json` PASS 14/14; `verify/report-hud-semantics.json` PASS 19/19.
6. **Handoff contracts** - `docs/HANDOFF_OPENCODE_REFERENCE_BASELINE.md`: §2 hard rules (write paths, `/usr/bin/python3`, quote the video path, folder <= 25 MiB, no game edits), §4.1-4.6 M2, §5.1-5.3 M3, §6 M4 checks 1-8 + adversarial spot checks + hygiene + `_carryover/` deletion, §7 final report, §8 tips. The doc's line 417 asks for a `## Progress` section if a session stops early; this session will instead leave the durable teamwork state and this plan.
7. **Per-task specs** - `.opencode/teamwork/20261118-185627-d692/spec-*.json` already encode requirements, acceptance criteria, local checks, verifier checks, dependencies, and pitfalls for every remaining task. The plan reuses them as the executor contract instead of re-writing them.
8. **Security gate** - `~/.config/opencode/teamwork/ARTIFACTS.md` (`verify/security-audit.json` schema) and `team/sentinel.md` step 10: all tasks `verified_pass` -> `teamwork_next` returns `READY_FOR_SECURITY_AUDIT`; a FAIL with Critical/High returns `BLOCKED_BY_SECURITY`; only a PASS reaches `ALL_TASKS_PASSED`.
9. **State-machine repair is supported** - `plugins/opencode-teamwork/tools.ts` (`teamwork_task_update`, lines ~1418-1455) accepts every valid status from any current status, so `worker_active -> pending` is a legal repair; `teamwork_next` (lines ~1220-1265) classifies `worker_active`/`verifier_active` as `inProgress` and only dispatches `pending`/retry-ready tasks, which is why the repair must happen before re-dispatch.
10. **Divergent branches** - `git log main..teamwork/base-20261118-185627-d692` = `d55fd48`, `a96363d`, `cb0e5e3`, `da2c3f6`, `08db332`, `9904b00`; `git log teamwork/base...main` = `6d6b4ba` ("Add tools for merging callout specs and rendering annotations"). Both `9904b00` and `6d6b4ba` add the same reference tree; `git diff --stat main base -- docs/reference/.../tools` shows base's `merge_callout_specs.py` and `render_annotations.py` diverged (577 insertions / 68 deletions) and base removed `.probe2`/`.write_probe`. A plain merge will produce add/add conflicts on the docs files the run touched.
11. **Toolchain** - `/home/john/Videos/clip_1,795,033,698,901.mp4` exists (265,161,125 B); `ffprobe`: h264 3840x2160, `r_frame_rate 179/6`, `avg_frame_rate 2110119665/71113994`, `nb_frames 6696`, duration `225.642333 s`, AAC audio. `/usr/bin/ffmpeg` 9.0.2, `/usr/bin/magick` 7.1.2-35, `/usr/bin/python3` with Pillow 13.0.0 + numpy 2.5.4, Noto Sans Bold/SemiBold/Regular all exist.
12. **Pitfalls to carry forward** - `pitfalls.md`: (a) `teamwork_worktree({action:'setup', role:'verifier'})` fails on a branch already used by a worktree; the previous run used a detached verifier worktree. (b) A checked-in validator claimed explicit BGM enforcement but passed KF11/KF13/KF20/KF26 with zero BGM mentions; an independent block grep caught it. Every breakdown verifier must repeat that independent grep.
13. **No live execution now** - no `teamwork run`/worker process is running; the OpenCode server processes are long-lived daemons. The stale `worker_active` is a dead session, not an in-flight turn.
14. **Planner workspace** - `.omo/` is untracked and not ignored by `.gitignore` (`git status --short` shows `?? .omo/`). It is the planner's local workspace and must not fail the final clean-tree check; use `git status --porcelain -- ':!.omo'` or an equivalent pathspec exclusion.

## Decisions (with rationale)

- **D1 - Resume the existing run, not a fresh one.** Use `ses_e0e53c38bffeUSx4c9ChYYfjKH` and the plugin. Reason: 2/9 tasks and their merge history already exist; a fresh run would duplicate them and lose `verify/report-*`.
- **D2 - Repair, don't verify a void.** Set `breakdown-s05-s13` to `pending` and re-dispatch; a verifier on an empty diff cannot produce a meaningful PASS.
- **D3 - Reuse the existing worktree for `breakdown-s05-s13`; do not call `teamwork_worktree setup` for it.** The branch/worktree already exist; setup would fail with the pitfall in `pitfalls.md`.
- **D4 - Incremental commits.** Each breakdown worker commits after each segment (BREAKDOWN + evidence file), so a pause costs at most one segment.
- **D5 - Keep the chain sequential.** S05-S13, S14-S20, S21-S27 all append to `BREAKDOWN.md`; parallel writers would conflict. `reference-baseline` reads the full breakdown; `comparison-template` reads the baseline; `verify-baseline` reads the template; `m4-final` reads the verifier. The only parallel stage is the final verification wave.
- **D6 - Verifier independence.** The verifier gets the branch diff and its own clean/detached worktree, never the worker's conversation. It re-runs commands rather than reading summaries. The BGM block-grep and the `threat arc`/`alert arc` grep are mandatory on every breakdown task.
- **D7 - Security audit scope.** The auditor audits the combined base diff (docs + new scripts): secrets, command injection in `make_side_by_side.sh`/`verify_baseline.py`/`render_annotations.py`, path traversal from CLI args, instructions in shipped docs that an agent might execute verbatim, and hygiene. Docs-only work does not lower the gate.
- **D8 - Final merge policy.** Create `backup/main-pre-reference-baseline` at `main`; merge `teamwork/base-20261118-185627-d692` with `--no-ff`; resolve every conflicted path under `docs/` by taking the base tree (`git checkout teamwork/base-... -- docs`); abort on any conflict outside `docs/`; verify the resulting deliverable docs tree equals base and `git diff 6d6b4ba..HEAD -- game tools build extracted` is empty; no push.
- **D9 - Final proof is independent.** After the sentinel reports ALL_TASKS_PASSED and the merge lands, a fresh Senpi-side verification wave re-runs `verify_baseline.py`, samples the verification log, checks the ideal-state rows, and confirms the worktree is clean. The sentinel's own report is a claim until then.
- **D10 - Do not resurface the old worker session.** Re-dispatch a fresh team/worker in the same worktree; the old 37-message session has no durable output and a fresh context avoids inheriting a partial plan.

## Scope IN

- Repair the teamwork state and re-dispatch `breakdown-s05-s13` in the existing worktree.
- Complete and verify `BREAKDOWN.md` S05-S13, S14-S20, S21-S27 on `teamwork/base-20261118-185627-d692`.
- Write and verify `docs/REFERENCE_BASELINE.md`, `docs/reference/clip_1795033698901/COMPARISON_TEMPLATE.md`, optional `tools/make_side_by_side.sh`, and `tools/verify_baseline.py`.
- Run M4 final: `verify_baseline.py`, 12+ adversarial claims, 6 annotated-image checks, 8 citation checks, `## Verification log`, `KEYFRAME_INDEX.md` errata, `_build/` + `_carryover/` + probe-file removal, size/scope hygiene.
- Run the mandatory `team/security-auditor` gate and record `verify/security-audit.json`.
- Merge the audited base into `main` with the D8 policy, clean up worktrees, and write the final `verify/final.json` + final report.
- Keep the run's `$20` budget and use the existing free team model.

## Scope OUT (Must NOT have)

- No edits to `game/` (especially `game/src/missions/mission_controller.gd`), repo-root `tools/`, `build/`, `extracted/`, `game/.godot/`, `game/data/generated/`.
- No changes to `clean/*.jpg`; `KEYFRAME_INDEX.md` edits only for proven factual errors, each logged in `## Errata`.
- No re-litigating the HUD correction: Light Gem = light exposure + direction; red arcs = player noise. Forbidden legacy phrases remain `threat arc`, `threat/alert arc`, `alert arc`, `threat pip`.
- No new VO quotes, invented mechanics, engine parameters, or off-screen content; `UNCERTAIN:` + reason instead.
- No new milestones, no redesign of the callout taxonomy, no changes to S01-S04 except proven errata.
- No `git push`, no force-push, no branch deletion before the merge is verified.
- No skipping, weakening, or deleting a `verify_baseline.py` check to get green; no faked or "looks right" spot checks.
- No shipping `_carryover/`, `_build/`, `.probe*`, or scratch files in `/tmp` left behind.

## Open questions

None that the evidence leaves open. The final-merge target is read from the user's explicit "final merge" instruction plus the sentinel's documented final step; D8 states it plainly so the approval gate can veto it. The only prompt left is the approval gate itself.

## Approval gate

status: approved
approved: 2026-11-19 (question tool, "Approve")
approach: Resume the existing teamwork run, repair the stale task, drive the remaining chain through worker -> verifier -> merge, run the mandatory security audit, merge the audited base into `main` with the D8 policy, clean up, and finish with an independent final verification wave.
next: plan-consultant gap analysis, fold findings, then initialize the review round and run plan-reviewer; execution starts only afterwards via `/ulw-execute`.
