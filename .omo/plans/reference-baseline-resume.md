# reference-baseline-resume - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**Who this is for and what changes for them:** For you as the owner: you will be able to record the Godot port slice and score it side by side against the official clip instead of stopping at a half-finished breakdown. The next comparison session gets two finished documents to start from, and the repo stops shipping scratch material.

**What you'll get:** A continuous, evidence-backed description of the whole 3:45 clip; a master baseline with the subsystem, gap, and hard-limit matrices and a 60-plus-row comparison checklist; a blank scorecard for the port recording; a one-command verifier; a passed security audit; and a clean docs-only merge on your main branch.

**Why this approach:** We resume the existing multi-agent run instead of redoing two finished tasks, and we repair the one task that was paused with no committed work. Every worker claim is re-checked by an independent verifier, and the final merge is guarded by a backup ref and a strict conflict policy.

**What it will NOT do:** It will not touch game code or the clean keyframe images, will not invent quotes or claims, will not skip or weaken a verifier check, and will not push anything.

**Effort:** XL
**Risk:** High - the final merge must reconcile two divergent docs trees, and long worker runs must be made checkpoint-safe after the previous attempt lost all in-flight work.
**Decisions to sanity-check:** the final merge lands on `main` with docs conflicts resolved to the audited base tree; the stale task is re-dispatched rather than marked done; nothing is pushed.

Your next move: run `/ulw-execute reference-baseline-resume` (after the high-accuracy review), or tell me what to change. Full execution detail follows below.

---

> TL;DR (machine): XL, High risk, 10 todos + 4 final verifiers; resume the teamwork run, finish S05-S27, write baseline/template/verifier, pass the security audit, merge docs to main.

## Scope
### Affected user and ideal state
<!-- From the draft ledger: who this touches and how they use the result, then one IS row per property with its reason, then one GAP row per difference with its reason. Every todo below closes a GAP row; ## Success criteria proves every IS row. -->
**Affected user:** The owner (U1), who records a comparable slice of their Godot 4.7 port and scores it against the official footage; the next comparison session (U2), human or agent, which uses the finished baseline instead of re-deriving clip facts; and future readers/maintainers (U3), who need one authoritative tree with no scratch material. Today U1 has verified M2 keyframes and legends but the breakdown stops at `S04`; U2 must reconstruct facts from `_carryover/`; U3 sees scratch, probe, and build files in the shipped tree. After this plan, U1 records and scores, U2 opens two finished documents, and U3 sees exactly one spec, legends, breakdown, baseline, template, and verifier.

| Row | Statement (ideal state) | Reason |
| --- | --- | --- |
| IS-1 | `BREAKDOWN.md` describes `S01-S27` continuously with all seven subsections per segment, explicit BGM presence/absence, measured audio levels, and citations opened against the current repo. | The breakdown is the spine of the comparison; one gap or unmeasured audio claim makes the baseline untrustworthy. |
| IS-2 | `docs/REFERENCE_BASELINE.md` contains the ten required sections, a 27-row timeline plus Mermaid flow, 18 subsystem rows, 8 PG and 9 HL matrix rows, and at least 60 checklist rows covering every segment; port columns stay blank. | U1 needs one master target; U2 needs the checklist without re-reading the clip. |
| IS-3 | `COMPARISON_TEMPLATE.md` mirrors the baseline checklist exactly (same row IDs, criteria, references, official observations), has 27 per-segment image slots and 27 alignment rows, and pre-fills no scores. | A drifting template silently compares the wrong criteria. |
| IS-4 | `tools/verify_baseline.py` implements all eight handoff checks, exits 0 on the finished tree, is deterministic, and proves renderer byte-identity without touching `annotated/`. | The user needs repeatable proof, and the next session must be able to re-run it cheaply. |
| IS-5 | Every shipped claim is evidence-backed: at least 12 adversarial spot checks (4 visual, 3 HUD verbatim, 3 audio, 2 gameplay timings), 6 annotated images re-opened, 8 citations re-opened, results in `## Verification log`; proven errors fixed and logged in `KEYFRAME_INDEX.md` `## Errata`. | A comparison-ready baseline fails if a label, timestamp, quote, or citation is wrong. |
| IS-6 | The mandatory pre-merge security audit PASSes with zero Critical/High findings and is recorded in `verify/security-audit.json` plus `events.jsonl`. | The teamwork engine blocks the final merge on Critical/High; the user needs an auditable gate, not a skipped step. |
| IS-7 | After the final merge, `main` contains the finished baseline with only docs changes; no change to `game/`, repo-root `tools/`, `build/`, or `extracted/`; the folder is at or under 25 MiB; no `_carryover/`, `_build/`, or probe files; nothing pushed. | The handoff is docs-only and the user's game work must remain untouched. |
| IS-8 | The run is terminal and reproducible: all nine DAG tasks `verified_pass`, no stale `worker_active`, `verify/final.json` PASS, worktrees cleaned, and a final report lists files, counts, verifier output, spot-check results, `UNCERTAIN:` items, and the exact next step. | Resuming must not leave the same ambiguous half-state that forced this session. |

| Row | Today differs from | Why it matters | Closed by todos |
| --- | --- | --- | --- |
| GAP-1 | IS-1: `BREAKDOWN.md` has 223 lines and only `S01-S04`; `S05-S27` are absent. | The core M3 deliverable is 23/27 segments unfinished. | 2, 3, 4 |
| GAP-2 | IS-8: `breakdown-s05-s13` is `worker_active` round 1; its worktree is clean at `d55fd48`; its branch has zero commits ahead of base; its worker session ended `idle/succeeded` at `03:09:07Z` with no durable output. | A stale active state blocks `teamwork_next`; marking it `worker_done` would send a no-op diff to a verifier. | 1, 2 |
| GAP-3 | IS-2: `docs/REFERENCE_BASELINE.md` does not exist. | U1 and U2 have no master index or comparison framework. | 5 |
| GAP-4 | IS-3: `COMPARISON_TEMPLATE.md` does not exist. | The next recording session has no fill-in scorecard. | 6 |
| GAP-5 | IS-4: `tools/verify_baseline.py` does not exist. | M4 has no independent proof surface. | 7 |
| GAP-6 | IS-5: no M4 verification log, spot checks, or errata pass has run. | Claims are still worker self-reports. | 8 |
| GAP-7 | IS-6: no `verify/security-audit.json`; the security gate has never run. | The engine cannot reach the final merge. | 9 |
| GAP-8 | IS-7: `teamwork/base-20261118-185627-d692` (`d55fd48`) is not merged into `main` (`6d6b4ba`); the branches diverged after `8a653df` and both added the same docs tree, so add/add conflicts are expected on every docs file the run modified. | The finished baseline is invisible to the user until it lands on their working branch. | 10 |
| GAP-9 | IS-7: `_carryover/`, `_build/`, `tools/.probe2`, and `tools/.write_probe` are still present; the folder is 16 MiB before the breakdown and baseline grow. | Scratch material ships and the size budget can silently break. | 2-8 (final cleanup in 8) |
| GAP-10 | IS-8: six DAG tasks are `pending`, two are `verified_pass`, there is no `verify/final.json`, and eleven worktrees remain registered. | The run cannot be called finished or safely re-entered. | 1, 9, 10 |

### Must have

- A repaired run state whose only active task is genuinely live, followed by `S05-S13`, `S14-S20`, and `S21-S27` merged into the team base with verifier PASS reports.
- `docs/REFERENCE_BASELINE.md`, `COMPARISON_TEMPLATE.md`, and `tools/verify_baseline.py`, each independently verified against the handoff's done-when conditions.
- M4 adversarial spot checks and a substantive `## Verification log`, plus `KEYFRAME_INDEX.md` errata for every proven factual fix.
- A PASS security-audit record with zero Critical/High findings.
- The audited base merged into `main` under the conflict policy in Decision D8, with a backup ref, no push, and a clean tree.
- An independent final verification wave that re-runs the proof rather than trusting the sentinel's report.

### Must NOT have (guardrails, anti-slop, scope boundaries)

- No edits to `game/` (especially `game/src/missions/mission_controller.gd`), repo-root `tools/`, `build/`, `extracted/`, `game/.godot/`, or `game/data/generated/`.
- No changes to `clean/*.jpg`; `KEYFRAME_INDEX.md` edits only for proven factual errors, each logged in `## Errata`.
- No re-litigating the HUD correction: Light Gem = light exposure + direction; red arcs = player noise. Forbidden legacy phrases stay `threat arc`, `threat/alert arc`, `alert arc`, and `threat pip`.
- No new VO quotes, invented mechanics, engine parameters, or off-screen content; write `UNCERTAIN:` plus the reason instead.
- No new milestones, no taxonomy redesign, no changes to `S01-S04` except proven errata.
- No `git push`, no force-push, no branch deletion before the merge is verified.
- No skipped, weakened, or deleted `verify_baseline.py` check; no faked or "looks right" spot check.
- No shipping `_carryover/`, `_build/`, `.probe*`, or scratch files, and no scratch files left in `/tmp`.

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: `none` for product code (the handoff is docs-only and forbids game edits); every todo instead carries agent-executed QA: the teamwork verifier runs the task's real commands, and the Senpi executor repeats the decisive checks independently. The closest thing to a regression suite is `tools/verify_baseline.py` plus the adversarial spot checks and git/tree assertions.
- Evidence root: `.omo/evidence/reference-baseline-resume/` in `/home/john/Projects/TAT-2`, one file per todo named `task-1-resume.md`, `task-2-checks.md`, `task-3-checks.md`, through `task-10-merge.md`, each with the exact commands and raw output, plus the run's per-task verifier report under `verify/`.
- Zero human intervention: every check is a command, an image open, or an audio re-measurement; F3 re-runs the decisive ones on the merged tree.
- Failure proof: each todo names a deliberate mutation in a temp copy (boundary shift, missing image, missing BGM line, forbidden wording, bad PG id, unsafe script input) that must make the checker fail; the real tree is never mutated for a negative test.
- Trust boundary: worker summaries, sentinel PASS messages, and verifier reports are claims until the executor re-runs the named command or re-opens the named artifact.

## Execution strategy
### Run constants (use verbatim)

```
REPO=/home/john/Projects/TAT-2
RUN=$REPO/.opencode/teamwork/20261118-185627-d692
BASE=teamwork/base-20261118-185627-d692
WTROOT=/home/john/Projects/.teamwork-worktrees/20261118-185627-d692
CLIP="/home/john/Videos/clip_1,795,033,698,901.mp4"
EVID=$REPO/.omo/evidence/reference-baseline-resume
SENTINEL=ses_e0e53c38bffeUSx4c9ChYYfjKH
```

Every task is driven through the existing OpenCode sentinel session, one DAG task per `opencode run` turn, so the executor can gate each boundary. The example below uses the task-2 log; every todo names the log it writes:

```
cd "$REPO"
opencode run --session "$SENTINEL" --agent team/sentinel --auto "<task instruction>" \
  > "$EVID/task-2-sentinel.log" 2>&1
```

Run that in a background PTY and watch the log with a monitor; never sleep or poll. If the session cannot be resumed or loses its state, start a fresh sentinel session with the same instruction and the run id, and record the fallback in the evidence file. The sentinel's `teamwork_*` tools are the only supported way to transition state, merge task branches, and run the security gate; do not hand-edit `state.json`, `plan.dag.json`, or `verify/*.json`. Verifier worktrees use `$WTROOT/verifier-<task>` in detached HEAD at the worker branch; never reuse the worker worktree.

### Parallel execution waves

- **W0 - todo 1:** preflight and state repair. Nothing else can dispatch until the stale task is `pending` and `teamwork_next` lists it as ready.
- **W1 - todo 2:** S05-S13. It appends to `BREAKDOWN.md`, so it cannot share a wave with S14-S20 or S21-S27.
- **W2 - todo 3:** S14-S20. It reads S05-S13's file state and appends to the same file.
- **W3 - todo 4:** S21-S27. It reads S14-S20's file state and appends to the same file.
- **W4 - todo 5:** REFERENCE_BASELINE. It reads the complete 27-segment breakdown.
- **W5 - todo 6:** COMPARISON_TEMPLATE. It reads the baseline's section 8 row set and must stay in lockstep with it.
- **W6 - todo 7:** verify_baseline.py. It reads the template and the final artifact set.
- **W7 - todo 8:** M4 final. It runs the verifier and mutates the shipped tree (hygiene).
- **W8 - todo 9:** security audit. It requires all nine tasks `verified_pass`; it guards the final merge.
- **W9 - todo 10:** final merge and cleanup. It requires audit PASS.
- **W10 - F1-F4:** the final verification wave, read-only, parallel.

Every edge below is a write-serialization or read dependency, not a scheduling preference.

### Dependency matrix
| Todo | Writes (files, shared state) | Depends on (reason) | Blocks |
| --- | --- | --- | --- |
| 1 | `state.json` (via `teamwork_task_update`); evidence log | none | 2-10 |
| 2 | `BREAKDOWN.md` (S05-S13), `_build/audio-s05-s13.md`, `_build/citations-s05-s13.md`, branch, base | 1 (state must be dispatchable) | 3-10 |
| 3 | `BREAKDOWN.md` (S14-S20), `_build/audio-s14-s20.md`, `_build/citations-s14-s20.md`, branch, base | 2 (same file and base) | 4-10 |
| 4 | `BREAKDOWN.md` (S21-S27), `_build/audio-s21-s27.md`, `_build/citations-s21-s27.md`, branch, base | 3 (same file and base) | 5-10 |
| 5 | `docs/REFERENCE_BASELINE.md`, branch, base | 4 (needs all 27 segments) | 6-10 |
| 6 | `COMPARISON_TEMPLATE.md`, optional helper, branch, base | 5 (row set comes from section 8) | 7-10 |
| 7 | `tools/verify_baseline.py`, branch, base | 6 (checks the template's artifact set) | 8-10 |
| 8 | `BREAKDOWN.md` fixes, `REFERENCE_BASELINE.md` verification log, `KEYFRAME_INDEX.md` errata, deleted `_build/` and `_carryover/`, branch, base | 7 (the script must exist and pass) | 9-10 |
| 9 | `verify/security-audit.json`, `events.jsonl` | 8 (all tasks must be `verified_pass`) | 10 |
| 10 | `main` merge commit, `verify/final.json`, `final.md`, cleaned worktrees | 9 (audit PASS) | F1-F4 |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [ ] 1. Preflight and repair the resumable teamwork run
  What to do / Must NOT do: Create `$EVID`. `.omo/` is the planner's local workspace and is intentionally untracked; repo hygiene checks exclude it. Prove the M2 baseline is still healthy on `$WTROOT/sentinel`: 30 files in `clean/`, 30 in `annotated/`, `render_annotations.py --check` exit 0, `callout_spec.json` has 30 keyframes and 195 callouts, `CALLOUT_LEGENDS.md` has 30 `### KF` sections and 195 data rows (`grep -c '^| [0-9]'`), the `BREAKDOWN.md` header still has the clip-metadata table, contents list, Mermaid flow, and audio-method note, folder <= 25 MiB, `HEAD` is `d55fd48`. Prove the stale task has no durable output: `git -C $WTROOT/breakdown-s05-s13 rev-parse HEAD` is `d55fd48`, `git status --porcelain` is empty, `grep -c '^## S' BREAKDOWN.md` is 4, and `_build/` holds only `hud-semantics.md`, `m2-audit.md`, `m2_apply_fixes.py`, `m2_audit_validate.py`. Prove no worker turn is live: query `session_v2` for `ses_e0e3d5d46ffei6zVJq1mpf3MjW` (expect `idle_outcome=succeeded`, last update `2026-11-19T03:09:07Z`) and confirm no `opencode run`/worker process is active. Run the sentinel once with this instruction, then stop: "Resume run 20261118-185627-d692. Call teamwork_resume. Repair breakdown-s05-s13: it is worker_active with a clean worktree at d55fd48 and zero commits; set it to pending via teamwork_task_update with agent team/sentinel, then call teamwork_next and report the ready list. Do not dispatch a worker. Do not mark worker_done. Do not edit state by hand." Capture the before (`inProgress`) and after (`READY FOR WORKER`) outputs. If the session cannot resume, start a fresh sentinel session with the same instruction and record the fallback. Must NOT: dispatch a worker in this todo, call `teamwork_worktree setup` for this task, hand-edit `state.json`, or delete any worktree.
  Closes: GAP-2, GAP-10
  Parallelization: Wave 0 | Blocked by: none | Blocks: 2-10
  References (executor has NO interview context - be exhaustive): `$RUN/state.json` (breakdown-s05-s13 worker_active round 1, updated 03:03:37Z); `$RUN/plan.dag.json` (dependency chain, maxRounds 4); `/home/john/.config/opencode/agents/team/sentinel.md` steps 1-9; `/home/john/.config/opencode/teamwork/ARTIFACTS.md` (state lifecycle, resume rule); `/home/john/.cache/opencode/npm/opencode-teamwork-v2@latest/1795040971748/node_modules/opencode-teamwork-v2/plugins/opencode-teamwork/tools.ts` lines 1418-1455 (any valid status may be set) and 1220-1265 (`worker_active` is `inProgress`, not ready); `$RUN/pitfalls.md`; `$WTROOT/breakdown-s05-s13`; `$WTROOT/sentinel`; OpenCode session query in `~/.local/share/opencode/opencode.db` (`session_v2`).
  Acceptance criteria (agent-executable): (1) `jq -r '.tasks["breakdown-s05-s13"].status' $RUN/state.json` prints `pending`. (2) The sentinel log contains `READY FOR WORKER` and `breakdown-s05-s13` under it. (3) `jq -r '[.tasks[] | select(.status=="worker_active" or .status=="verifier_active")] | length' $RUN/state.json` prints `0`. (4) The evidence file contains the pre-repair `inProgress` output and the post-repair ready output. (5) The M2 preflight values above are recorded with their commands. (6) No live worker process was found before the repair.
  QA scenarios (name the exact tool + invocation; time and failures driven through a fake clock or an injected fault, never a real wait or outage): happy - run the preflight commands and the sentinel repair prompt, then re-run the three acceptance `jq`/log checks; evidence `$EVID/task-1-resume.md`. Failure - before repairing, run `teamwork_next` and capture that `breakdown-s05-s13` is listed as `inProgress` (proves the repair is load-bearing); if a live worker process exists, stop and record it instead of double-dispatching; if the sentinel session cannot resume, start a fresh session with the same run id and repeat, recording the fallback.
  Commit: N | chore(teamwork): repair run state (operational state only, not a repo commit)
  Recommended task executor category: unspecified-high

- [ ] 2. Complete, verify, and merge BREAKDOWN S05-S13
  What to do / Must NOT do: Drive exactly one DAG task through the sentinel: `teamwork_next`, set `worker_active` round 1, dispatch a fresh `team/worker` in the existing worktree `$WTROOT/breakdown-s05-s13` (never call `teamwork_worktree setup` for it), then `worker_done`, then a `team/verifier` in a detached verifier worktree (the previous run's pitfall: setup reusing a worker branch fails; use `git worktree add --detach`), then merge only on PASS. Worker addendum to append to `spec-breakdown-s05-s13.json`: the previous attempt produced no commit; start from HEAD `d55fd48`; append only S05-S13; commit after each segment with its evidence file; if you must stop, commit the partial work and list exactly what remains; never touch S01-S04, `clean/`, or files outside `BREAKDOWN.md` and `_build/`; every segment must state BGM presence or `No BGM (explicit absence)`; use the corrected HUD semantics and no forbidden wording. Verifier must run the spec's own list plus: an independent block grep over S05-S13 for `BGM`/`music`/`silence` (the m2-audit pitfall), the forbidden-wording grep, 3 audio re-measurements (S06 `00:26.58-00:38.17`, S09 `00:56.08-01:04.80`, S13 `01:20.10-01:39.30`), 8 citation re-opens, and 4 video moments (telescope cut `00:20.2`, Gramophone `00:45-00:48`, car horn `01:35.7`, map-table modal `00:55.3`). On FAIL, log a pitfall and re-dispatch round 2 (cap 4). Stop after this task and report; do not start S14-S20. Must NOT: merge a partial branch, verify an empty diff, edit S01-S04, call `teamwork_worktree setup` for the existing worktree, or commit `summary.md`.
  Closes: GAP-1, GAP-2
  Parallelization: Wave 1 | Blocked by: 1 (state must be dispatchable) | Blocks: 3-10
  References: `$RUN/spec-breakdown-s05-s13.json` (full requirements, acceptance, local checks, verification, avoidPitfalls); `docs/HANDOFF_OPENCODE_REFERENCE_BASELINE.md` section 5.1 lines 233-302 and section 2 rules; `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` section 2 (segment table lines 26-60), section 3 (keyframes 62-100), section 4 (audio/VO 101-173), section 5 (verbatim UI 174-247); `docs/reference/clip_1795033698901/BREAKDOWN.md` S01-S04 lines 62-223; `docs/reference/clip_1795033698901/callout_spec.json`; `$RUN/pitfalls.md`; `~/.config/opencode/agents/team/worker.md` and `verifier.md` for the roles; the clip at `$CLIP`.
  Acceptance criteria (agent-executable): (1) `git -C $WTROOT/breakdown-s05-s13 log --oneline $BASE..HEAD | wc -l` is at least 9 (one commit per segment). (2) `grep -c '^## S' docs/reference/clip_1795033698901/BREAKDOWN.md` is 13. (3) `grep -n '^## S0[5-9]\|^## S1[0-3]'` lists the nine headings in order. (4) A shell loop over S05-S13 confirms each section has exactly one of `### Narrative`, `### Visual`, `### HUD / UI`, `### Gameplay and interactions`, `### Audio`, `### TAT-2 cross-reference`, `### What to check in the port recording`, and seven Visual bullets labelled `(V1)`-`(V7)`. (5) Each S05-S13 section contains an explicit BGM presence or `No BGM (explicit absence)` statement. (6) `grep -n -i 'threat arc\|alert arc\|threat pip' BREAKDOWN.md` has no hit. (7) `git diff $BASE..HEAD -- BREAKDOWN.md | grep '^-[^-]'` is empty (S01-S04 bytes unchanged). (8) `git diff --stat $BASE..HEAD` lists only `BREAKDOWN.md`, `_build/audio-s05-s13.md`, and `_build/citations-s05-s13.md`. (9) `_build/audio-s05-s13.md` has 9 `### S` entries, each with an ffmpeg command and a measured dBFS/LUFS value. (10) `_build/citations-s05-s13.md` lists every citation used, with file:line and the confirming fact. (11) `jq -r '.tasks["breakdown-s05-s13"].status' $RUN/state.json` is `verified_pass`; `git -C $WTROOT/sentinel log --oneline -1` contains `Merge task breakdown-s05-s13`. (12) `$RUN/verify/report-breakdown-s05-s13.json` has `"status":"PASS"`.
  QA scenarios: happy - run the twelve acceptance checks and the verifier's three audio re-measurements and four video moments; evidence `$EVID/task-2-sentinel.log`, `$EVID/task-2-checks.md`, `$RUN/verify/report-breakdown-s05-s13.json`. Failure - in a temp copy of the branch, delete one segment's BGM line and insert the phrase `threat arc`; the BGM block grep and the forbidden-wording grep must both fail; discard the temp copy and never mutate the real branch.
  Commit: Y | docs(reference): add BREAKDOWN S05-S13 with audio and citation evidence (one commit per segment; sentinel merge commit)
  Recommended task executor category: unspecified-high

- [ ] 3. Complete, verify, and merge BREAKDOWN S14-S20
  What to do / Must NOT do: Same one-task sentinel loop for `breakdown-s14-s20`: dispatch a fresh worker in `$WTROOT/breakdown-s14-s20`, append S14-S20 only, commit per segment, then verifier, then merge on PASS. Worker addendum: never edit S01-S13; commit after each segment; if stopping early, commit partial and list what remains. Verifier must run the spec list plus: 2 audio re-measurements (S17 fall impact `02:23.30`, S18 smoke detonation `02:28.20`), the fall-damage evidence audit (no damage at `~01:44` in S14; damage at `02:23.30` in S17 with `red_px` going 0 to about 27,560 and the Health Bar at about 75%), a re-extracted frame at `02:23.30`, 6 citation re-opens, and the independent BGM and forbidden-wording greps. On FAIL, log a pitfall and re-dispatch round 2 (cap 4). Stop after this task.
  Closes: GAP-1
  Parallelization: Wave 2 | Blocked by: 2 (same file and base) | Blocks: 4-10
  References: `$RUN/spec-breakdown-s14-s20.json`; handoff section 5.1 lines 269-302; `KEYFRAME_INDEX.md` sections 2-5 (especially S14/S17/S18 rows and the fall-damage claims); `BREAKDOWN.md` through S13; `callout_spec.json`; `$RUN/pitfalls.md`.
  Acceptance criteria (agent-executable): (1) `grep -c '^## S'` is 20. (2) `grep -n '^## S1[4-9]\|^## S20'` lists the seven headings in order. (3) Each S14-S20 has the seven required subsections and seven Visual bullets. (4) Both fall-damage claims are backed by a recorded pixel/frame measurement in `_build/` and re-confirmed by the verifier at `02:23.30`; S14 explicitly says no damage at `~01:44`. (5) Every segment states BGM presence or explicit absence. (6) `git diff $BASE..HEAD -- BREAKDOWN.md | grep '^-[^-]'` is empty for S01-S13. (7) `_build/audio-s14-s20.md` has 7 entries with commands and values; `_build/citations-s14-s20.md` lists every citation. (8) `grep -n -i 'threat arc\|alert arc\|threat pip'` has no hit. (9) `$RUN/verify/report-breakdown-s14-s20.json` status PASS; task status `verified_pass`; base merge commit exists.
  QA scenarios: happy - run the nine checks and the verifier's two audio re-measurements and frame re-extraction; evidence `$EVID/task-3-checks.md`, `$RUN/verify/report-breakdown-s14-s20.json`. Failure - in a temp copy, change S14 to claim fall damage at `01:44`; the pixel/frame check must refute it; discard the copy.
  Commit: Y | docs(reference): add BREAKDOWN S14-S20 with fall-damage evidence
  Recommended task executor category: unspecified-high

- [ ] 4. Complete, verify, and merge BREAKDOWN S21-S27
  What to do / Must NOT do: Same one-task sentinel loop for `breakdown-s21-s27`: dispatch a fresh worker in `$WTROOT/breakdown-s21-s27`, append S21-S27 only, commit per segment, then verifier, then merge on PASS. Worker addendum: never edit S01-S20; commit after each segment; if stopping early, commit partial and list what remains; distinguish the white mechanical jaw-trap icon, the orange unconscious-head icon, the purple ward, and the green vines; do not conflate the wall beam emitter with the overhead rotating security camera; S27 must record the `-240 dBFS` digital silence to the end. Verifier must run the spec list plus: re-extract the S27 tail and confirm the modal click, ambience duck, and `-240 dBFS` silence; re-open a frame at `03:29.00` and confirm the purple ward plus green vines plus both status icons are described distinctly; 2 audio re-measurements; 6 citation re-opens; the independent BGM and forbidden-wording greps. On FAIL, log a pitfall and re-dispatch round 2 (cap 4). Stop after this task.
  Closes: GAP-1
  Parallelization: Wave 3 | Blocked by: 3 (same file and base) | Blocks: 5-10
  References: `$RUN/spec-breakdown-s21-s27.json`; handoff section 5.1; `KEYFRAME_INDEX.md` sections 2-5 (S21-S27 rows, KF24-KF30); `BREAKDOWN.md` through S20; `callout_spec.json`; `$RUN/pitfalls.md`.
  Acceptance criteria (agent-executable): (1) `grep -c '^## S'` is 27. (2) `grep -n '^## S2[1-7]'` lists the seven headings in order; S27 ends at `03:45.64`. (3) Each S21-S27 has the seven required subsections and seven Visual bullets. (4) The three status-icon types and the two ward colours are described distinctly and consistently with KF28/KF29. (5) S27's Audio table records digital silence `-240.0 dBFS` to the end. (6) Every segment states BGM presence or explicit absence. (7) `git diff $BASE..HEAD -- BREAKDOWN.md | grep '^-[^-]'` is empty for S01-S20. (8) `_build/audio-s21-s27.md` has 7 entries; `_build/citations-s21-s27.md` lists every citation. (9) `grep -n -i 'threat arc\|alert arc\|threat pip'` has no hit. (10) `$RUN/verify/report-breakdown-s21-s27.json` status PASS; task status `verified_pass`; base merge commit exists.
  QA scenarios: happy - run the ten checks and the verifier's S27-tail and `03:29.00` re-opens; evidence `$EVID/task-4-checks.md`, `$RUN/verify/report-breakdown-s21-s27.json`. Failure - in a temp copy, call the purple ward `blue` or conflate the beam with the camera; the rubric and the frame re-open must catch it; discard the copy.
  Commit: Y | docs(reference): add BREAKDOWN S21-S27 with alarm and ward evidence
  Recommended task executor category: unspecified-high

- [ ] 5. Write and verify docs/REFERENCE_BASELINE.md
  What to do / Must NOT do: One-task sentinel loop for `reference-baseline`: dispatch a fresh worker in `$WTROOT/reference-baseline`, write the ten sections in order, commit, verify, merge on PASS. The worker must read all 27 breakdown sections, `KEYFRAME_INDEX.md`, `CALLOUT_LEGENDS.md`, `callout_spec.json`, `docs/HANDOFF_NEXT_SESSION.md`, `docs/FIDELITY_GAPS.md`, `docs/ARCHITECTURE.md`, `docs/PERFORMANCE.md`, `docs/ANDROID.md`, and `docs/reports/*.md`; re-open every citation (survey2 is candidate-only). Section 5 must define the corrected HUD semantics; section 8 must have at least 60 concrete rows covering every S01-S27 with blank port columns; section 9 must have a per-segment alignment anchor and runnable ffmpeg/magick commands plus the 1280x720 stretched-render note; section 10 must be the step-by-step comparison workflow; the file must end with `## Verification log` and the M4 placeholder note. Verifier: independently count rows and distinct segments, re-open 10 random citations, check all four pillar tables, check the Mermaid reaches S27, check the 27-row timeline, and re-read section 9 for runnable commands. Must NOT: invent a citation, copy a stale line number, pre-fill port observations or scores, or edit `BREAKDOWN.md`, `KEYFRAME_INDEX.md`, `callout_spec.json`, or `clean/`.
  Closes: GAP-3
  Parallelization: Wave 4 | Blocked by: 4 (needs all 27 segments) | Blocks: 6-10
  References: `$RUN/spec-reference-baseline.json`; handoff section 5.2 lines 304-334; `docs/reference/clip_1795033698901/BREAKDOWN.md`; `KEYFRAME_INDEX.md`; `CALLOUT_LEGENDS.md`; `callout_spec.json`; `_carryover/survey2_subsystems_gaps_limits.md` (candidate map only); `docs/HANDOFF_NEXT_SESSION.md`; `docs/FIDELITY_GAPS.md`; `docs/reports/*.md`.
  Acceptance criteria (agent-executable): (1) `grep -n '^## '` shows sections 1-10 in order plus `## Verification log`. (2) The timeline table has 27 unique `S` rows; the Mermaid flow references every segment. (3) Section 6 has 18 subsystem rows; section 7 has 8 `PG-` and 9 `HL-` rows. (4) Section 8's header is exactly `| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score | Notes |`; `grep -c '^| V[1-7] \|^| AU[1-6] \|^| UI[1-5] \|^| G[1-5] '` is at least 60; all 27 segments appear; port columns are blank; the score enum is defined. (5) Section 5 defines the gem and arcs semantics; the forbidden-wording grep is zero. (6) Section 9 contains 27 alignment anchors, exact ffmpeg/magick commands, and the 1280x720 note. (7) `## Verification log` exists with the M4 placeholder. (8) No `TODO` or `<fill` remains. (9) `$RUN/verify/report-reference-baseline.json` status PASS; task `verified_pass`; base merge commit exists.
  QA scenarios: happy - run the nine checks and the verifier's 10 citation re-opens; evidence `$EVID/task-5-checks.md`, `$RUN/verify/report-reference-baseline.json`. Failure - in a temp copy, drop one checklist row or omit `S19`; the row/segment count must fail; add a forbidden phrase and the grep must fail; discard the copy.
  Commit: Y | docs(reference): add master baseline and comparison checklist
  Recommended task executor category: unspecified-high

- [ ] 6. Write and verify COMPARISON_TEMPLATE.md
  What to do / Must NOT do: One-task sentinel loop for `comparison-template`: dispatch a fresh worker in `$WTROOT/comparison-template`, write `docs/reference/clip_1795033698901/COMPARISON_TEMPLATE.md` as a blank scorecard that reuses every row ID, criterion, reference, and official observation from baseline section 8, add 27 per-segment image slots, 27 alignment rows, and the per-pillar summary table, and optionally add `tools/make_side_by_side.sh` (plain bash, usage with no args, refuses a nonexistent input). Commit, verify, merge on PASS. The verifier must independently diff the template rows against baseline section 8 (missing or changed row = FAIL), count 27 segment sections and 27 alignment rows, confirm no pre-filled scores, and run the helper with no args and with a missing file. Must NOT: invent criteria, pre-fill scores, edit `REFERENCE_BASELINE.md`, or reference a nonexistent image path.
  Closes: GAP-4
  Parallelization: Wave 5 | Blocked by: 5 (row set comes from section 8) | Blocks: 7-10
  References: `$RUN/spec-comparison-template.json`; handoff section 5.3 lines 335-348; `docs/reference/clip_1795033698901/REFERENCE_BASELINE.md` section 8; `BREAKDOWN.md`; `KEYFRAME_INDEX.md` section 2.
  Acceptance criteria (agent-executable): (1) Every checklist row ID from baseline section 8 appears exactly once in the template with identical criterion and reference text. (2) `grep -c '^## S'` is 27; `grep -c '^| S[0-2][0-9] '` is 27. (3) The summary table has per-pillar counts and a total row. (4) The score enum and usage instructions are at the top. (5) Port observation, Score, and Notes are blank; no pre-filled score appears. (6) If the helper exists: `bash -n` passes; running it with no args prints usage and creates no files; a nonexistent input is refused. (7) `$RUN/verify/report-comparison-template.json` status PASS; task `verified_pass`; base merge commit exists.
  QA scenarios: happy - run the seven checks and the row-ID diff; evidence `$EVID/task-6-checks.md`, `$RUN/verify/report-comparison-template.json`. Failure - in a temp copy, remove one baseline row or change a criterion; the diff must fail; run the helper with a missing path and confirm it refuses; discard the copy.
  Commit: Y | docs(reference): add blank comparison scorecard and side-by-side helper
  Recommended task executor category: unspecified-high

- [ ] 7. Write and verify tools/verify_baseline.py
  What to do / Must NOT do: One-task sentinel loop for `verify-script`: dispatch a fresh worker in `$WTROOT/verify-script`, write the tracked script with all eight checks from handoff section 6, commit, verify, merge on PASS. The script must be runnable as `/usr/bin/python3 docs/reference/clip_1795033698901/tools/verify_baseline.py` from the repo root, resolve paths relative to itself, use stdlib plus Pillow only, print one `[PASS]`/`[FAIL]` line per check with a real count, exit 0 only if all pass, and have no timestamps, randomness, or network. Check 8 must copy the clip directory to a temp dir, run the renderer there, and compare SHA-256 for all 30 files, never touching the real `annotated/`. The verifier must run the script twice and diff the output, run negative mutations in a temp copy (shift S05 end, remove an annotated image, resize one image, change a taxonomy code, change a PG id), confirm each targeted check fails, confirm the real tree is unchanged, read the script for an always-true path, and time the run. Must NOT: weaken, skip, or delete a check to get green; use inline `python -c`; hardcode PASS; modify `annotated/` or `clean/` during check 8.
  Closes: GAP-5
  Parallelization: Wave 6 | Blocked by: 6 (checks the template's artifact set) | Blocks: 8-10
  References: `$RUN/spec-verify-script.json`; handoff section 6 lines 352-368; `docs/reference/clip_1795033698901/tools/render_annotations.py`; `BREAKDOWN.md`; `KEYFRAME_INDEX.md`; `CALLOUT_LEGENDS.md`; `callout_spec.json`; `COMPARISON_TEMPLATE.md`.
  Acceptance criteria (agent-executable): (1) `cd $REPO && /usr/bin/python3 docs/reference/clip_1795033698901/tools/verify_baseline.py` exits 0 and prints eight `[PASS]` lines plus a summary. (2) Two consecutive runs produce identical output. (3) `py_compile` passes. (4) The temp-copy mutations trigger the expected `[FAIL]` for checks 1, 3, 6, and 7; check 8 proves 30/30 SHA-256 matches and leaves the real `annotated/` untouched. (5) No network import, no `TODO`, no always-true path. (6) Runtime is under five minutes. (7) `$RUN/verify/report-verify-script.json` status PASS; task `verified_pass`; base merge commit exists.
  QA scenarios: happy - run the script twice, diff, and run the five mutations; evidence `$EVID/task-7-checks.md`, `$RUN/verify/report-verify-script.json`. Failure - if a mutation still passes, the check is vacuous and the todo FAILs; the worker must fix the check, not the mutation. Record the exact failing command and output.
  Commit: Y | docs(reference): add deterministic baseline verifier
  Recommended task executor category: unspecified-high

- [ ] 8. Complete M4 final: spot checks, hygiene, and carryover removal
  What to do / Must NOT do: One-task sentinel loop for `m4-final`: dispatch a fresh worker in `$WTROOT/m4-final`, run `verify_baseline.py`, fix every failure without weakening the script, then perform the handoff's adversarial spot checks: at least 12 claims across `BREAKDOWN.md` (4 visual, 3 HUD verbatim, 3 audio, 2 gameplay timings), each with claim, evidence command, and verdict; at least 6 random annotated images re-opened; at least 8 random citations re-opened. Fix every refuted claim; add `KEYFRAME_INDEX.md` `## Errata` entries for proven factual errors. Append `## Verification log` to `REFERENCE_BASELINE.md` with the verifier output summary, the 12-row table, the 6 image checks, the 8 citation checks, hygiene output, and remaining `UNCERTAIN:` items. Delete `_build/`, `_carryover/`, `tools/.probe2`, and `tools/.write_probe` only after the verifier passes and `callout_spec.json` exists; first fold anything still useful from `_carryover/` into the final docs; make `tools/merge_callout_specs.py` fail gracefully when `_carryover/` is gone. Optionally append a <= 10-line pointer to `docs/HANDOFF_NEXT_SESSION.md`. Commit, verify, merge on PASS. Must NOT: fake a spot check, skip a failing check, delete `_carryover/` early, touch `game/`, or leave `_build/`/probe files.
  Closes: GAP-6, GAP-9
  Parallelization: Wave 7 | Blocked by: 7 (the verifier must exist and pass) | Blocks: 9-10
  References: `$RUN/spec-m4-final.json`; handoff section 6 lines 369-391 and section 7; `docs/REFERENCE_BASELINE.md`; `BREAKDOWN.md`; `KEYFRAME_INDEX.md`; `tools/verify_baseline.py`; `tools/merge_callout_specs.py`; `$RUN/pitfalls.md`.
  Acceptance criteria (agent-executable): (1) `verify_baseline.py` exits 0; its output is summarized in `## Verification log`. (2) The log has at least 12 rows with 4 visual, 3 HUD verbatim, 3 audio, and 2 gameplay checks; every row has a command and a verdict; every refuted claim is fixed. (3) The log records at least 6 annotated images and 8 citations re-opened. (4) `KEYFRAME_INDEX.md` `## Errata` contains an entry for every factual fix; `clean/` is unchanged. (5) `_build/`, `_carryover/`, `.probe2`, and `.write_probe` are absent (`find` output empty). (6) `du -sh` is at most 25 MiB; every annotated JPEG is under 750 KB. (7) `git diff --stat 8a653df..HEAD -- game tools build extracted` is empty. (8) `tools/merge_callout_specs.py` exits nonzero with a clear message and no traceback when `_carryover/` is gone. (9) No shipped doc references `_carryover`. (10) `$RUN/verify/report-m4-final.json` status PASS; task `verified_pass`; base merge commit exists.
  QA scenarios: happy - re-run the verifier, re-do 4 of the 12 spot checks, re-open 2 annotated images, re-open 3 citations, and confirm the deleted paths; evidence `$EVID/task-8-checks.md`, `$RUN/verify/report-m4-final.json`. Failure - in a temp copy, remove one annotated image and confirm the verifier fails; create a verification-log row with a claim and no command and confirm the rubric fails; restore the copy.
  Commit: Y | docs(reference): final verification log, errata, and hygiene
  Recommended task executor category: unspecified-high

- [ ] 9. Run the mandatory pre-merge security audit
  What to do / Must NOT do: Call `teamwork_next`; expect `READY_FOR_SECURITY_AUDIT` (all nine tasks `verified_pass`). Dispatch `team/security-auditor` on the sentinel base worktree `$WTROOT/sentinel` with the cumulative docs diff and the new scripts. The auditor must audit the seven classes in its role plus: no secrets or credentials in docs/scripts; no command or argument injection in `verify_baseline.py`, `render_annotations.py`, `merge_callout_specs.py`, or `make_side_by_side.sh`; no path traversal from CLI args; no shipped instruction that an agent would execute destructively verbatim; no stored prompt injection in the docs; no private data. Record findings with `teamwork_security_audit` (`status`, `severityCounts`, `summary`, `findings`). If Critical/High: the gate must FAIL; stop, add a remediation todo or re-open the owning task, fix, and re-audit. Do not merge on FAIL. Must NOT: self-audit, skip the auditor, hand-edit `verify/security-audit.json`, or treat a docs-only diff as exempt.
  Closes: GAP-7
  Parallelization: Wave 8 | Blocked by: 8 (all tasks must be verified_pass) | Blocks: 10
  References: `/home/john/.config/opencode/agents/team/security-auditor.md`; `/home/john/.config/opencode/teamwork/ARTIFACTS.md` (security-audit schema and the Critical/High block); `sentinel.md` step 10; `$RUN/state.json`; `$RUN/events.jsonl`; the merged base worktree `$WTROOT/sentinel`; the new scripts and docs.
  Acceptance criteria (agent-executable): (1) `jq -r '.status' $RUN/verify/security-audit.json` prints `PASS`. (2) `.severityCounts.critical` and `.severityCounts.high` are `0`. (3) `$RUN/events.jsonl` has a `security_audit` event with `"to":"PASS"`. (4) `teamwork_next` returns `ALL_TASKS_PASSED`. (5) The audit report names the files inspected and the commands run; no "looks fine" only.
  QA scenarios: happy - run the gate and the four checks; evidence `$EVID/task-9-audit.md`, `$RUN/verify/security-audit.json`. Failure - in a temp copy, plant a fake `sk-...` token and an unquoted `$(...)` command in a script; the secret and injection scans must flag both; never commit the fake; record the detection and remove the temp copy.
  Commit: N | security gate record only (run artifact, not a repo commit)
  Recommended task executor category: unspecified-high

- [ ] 10. Merge the audited base into main, clean up, and record final verification
  What to do / Must NOT do: Ensure `main` is clean and at `6d6b4ba`; if `main` has moved, stop unless it is a descendant of `6d6b4ba` and record the new SHA. Create `backup/main-pre-reference-baseline` at `main` (timestamp the name if it already exists). Merge `$BASE` into `main` with `--no-ff`: `git -C $REPO merge --no-ff $BASE -m "docs(reference): merge verified official-footage baseline"`. If the merge has conflicts only under `docs/`, resolve every conflicted docs path to the audited base tree with `git -C $REPO checkout $BASE -- docs`, `git -C $REPO add -A docs`, and `git -C $REPO commit --no-edit` (or `git merge --continue`); if any conflict is outside `docs/`, `git merge --abort` and stop. Verify the docs tree equals base, the game/build/tools/extracted scope is untouched, the folder is <= 25 MiB, and the tree is clean excluding the local `.omo/` planner workspace. Run `teamwork_worktree cleanup` for the run (keep the base branch and the backup ref until final verification passes), write `final.md`, and dispatch the sentinel's final verifier on the merged `main` to produce `$RUN/verify/final.json`. Produce the handoff section 7 report content: files created/changed, callout and keyframe counts, folder size, verifier output, spot-check counts and errata, remaining `UNCERTAIN:` items, and the exact next step (record the port slice using the capture protocol, then request the comparison). Must NOT: push, force-push, delete branches before final verification, hand-resolve a non-docs conflict, or edit game code.
  Closes: GAP-8, GAP-10
  Parallelization: Wave 9 | Blocked by: 9 (audit PASS) | Blocks: F1-F4
  References: `sentinel.md` steps 11-12; `ARTIFACTS.md` (final merge and final verifier); `$RUN/state.json`; `$RUN/verify/security-audit.json`; `docs/REFERENCE_BASELINE.md` section 9; handoff section 7 lines 395-406; the main worktree `$REPO`; the base worktree `$WTROOT/sentinel`.
  Acceptance criteria (agent-executable): (1) `git -C $REPO log --oneline -1` is the merge commit and `git -C $REPO merge-base --is-ancestor $BASE main` exits 0. (2) `git -C $REPO diff --stat $BASE..main -- docs/REFERENCE_BASELINE.md docs/reference` is empty. (3) `git -C $REPO diff --stat 6d6b4ba..main -- game tools build extracted` is empty. (4) `git -C $REPO status --porcelain -- ':!.omo'` is empty (the planner's `.omo/` workspace is intentionally untracked). (5) `du -sh $REPO/docs/reference/clip_1795033698901` is at most 25 MiB and `find` shows no `_carryover`, `_build`, or probe files. (6) `$RUN/verify/final.json` status PASS; `jq -r '[.tasks[] | select(.status!="verified_pass")] | length' $RUN/state.json` is 0. (7) `git worktree list` shows only `$REPO` and any user-owned worktrees. (8) The final report contains the handoff section 7 fields.
  QA scenarios: happy - run the eight checks and read `verify/final.json`; evidence `$EVID/task-10-merge.md`, `$RUN/verify/final.json`, `$RUN/final.md`. Failure - in a scratch clone (never the real repo), create a non-docs conflict and confirm `git merge --abort` restores the pre-merge state; create a docs conflict and confirm `git checkout $BASE -- docs` yields a tree equal to base for the deliverable paths; record both runs and discard the clone.
  Commit: Y | docs(reference): merge verified official-footage baseline (merge commit; no push)
  Recommended task executor category: unspecified-high

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [ ] F1. Plan compliance audit
  Independent `omo-native-gate-reviewer` audit of the merged tree against every todo's acceptance criteria and the handoff's M2/M3/M4 done-when conditions. It must re-run the decisive commands, not read the executor's summary. Any shortfall becomes a new `- [ ] N.` row; it is never a note. Evidence `$EVID/f1-compliance.md`.
  Recommended task executor category: unspecified-high
- [ ] F2. Code quality review
  Independent review of `tools/verify_baseline.py`, the `render_annotations.py` diff, `tools/merge_callout_specs.py`, and `tools/make_side_by_side.sh` for stubs, always-true paths, unsafe shell, unquoted variables, path traversal, nondeterminism, TODO markers, and silent exception swallowing. Re-run `bash -n` and `py_compile`. Evidence `$EVID/f2-quality.md`.
  Recommended task executor category: unspecified-high
- [ ] F3. Real manual QA
  On the merged `main`: run `verify_baseline.py`; open six annotated images (three from S05-S13, three from S21-S27) and confirm their leaders/labels; re-extract and inspect three breakdown audio slices and three claimed video moments; run the side-by-side helper with no args and with a missing file; confirm the negative behaviors. Evidence `$EVID/f3-manual-qa.md`.
  Recommended task executor category: unspecified-high
- [ ] F4. Ideal-state fidelity
  Check IS-1 through IS-8 one-to-one against the delivered artifacts and the merged tree. Any shortfall becomes a new `- [ ] N.` row, never a note. Evidence `$EVID/f4-fidelity.md`.
  Recommended task executor category: unspecified-high

## Commit strategy

- **Worker branches:** `teamwork/20261118-185627-d692-<task>`; each worker commits on its own branch. Breakdown workers commit once per segment (BREAKDOWN plus its `_build/` evidence file) so a pause costs at most one segment. Messages follow `docs(reference): <what changed>` or `audit(m2): <what changed>`.
- **Task merges:** after a verifier PASS, the sentinel merges the worker branch into `teamwork/base-20261118-185627-d692` with a merge commit named `Merge task <taskId> (<branch>)`. Only `verified_pass` branches merge; a `verified_fail` branch stays open for the next round.
- **Final merge:** one `--no-ff` merge commit on `main` named `docs(reference): merge verified official-footage baseline`, preceded by `backup/main-pre-reference-baseline`. Resolve docs add/add conflicts to the audited base tree; abort on any non-docs conflict. No push, no force-push, no rebase of merged history.
- **Repo hygiene:** `_carryover/`, `_build/`, and probe files are deleted in the M4 commit after the verifier passes. The base branch, worker branches, and backup ref stay until F1-F4 approve, then the team worktrees are pruned (branches are kept as history).
- **Never:** commit `summary.md`, scratch files, temp frames, secrets, or anything under `game/`, `build/`, `extracted/`, or repo-root `tools/`.

## Success criteria
> One row per IS row. The plan is complete only when every IS row has a delivering todo and a proving QA scenario; F4 checks the delivered behavior against these rows 1:1, and a shortfall becomes new `- [ ] N.` rows, never a note.
| IS | Delivering todo(s) | Proving QA scenario | Evidence |
| --- | --- | --- | --- |
| IS-1 | 2, 3, 4 | S01-S27 continuity, seven subsections per segment, BGM block grep, 3+2+2 audio re-measurements, citation re-opens | `$RUN/verify/report-breakdown-*.json`, `$EVID/task-2-checks.md` ... `task-4-checks.md` |
| IS-2 | 5 | Ten sections in order, 27 timeline rows, 18 subsystems, 8 PG / 9 HL, >=60 rows, every segment represented, 10 citation re-opens | `$RUN/verify/report-reference-baseline.json`, `$EVID/task-5-checks.md` |
| IS-3 | 6 | Independent row-ID/criterion diff against baseline section 8, 27 segments, 27 alignment rows, helper no-arg and missing-file behavior | `$RUN/verify/report-comparison-template.json`, `$EVID/task-6-checks.md` |
| IS-4 | 7 | Eight `[PASS]` lines, two identical runs, positive and negative mutations, 30/30 SHA-256 renderer match, runtime < 5 min | `$RUN/verify/report-verify-script.json`, `$EVID/task-7-checks.md` |
| IS-5 | 8 | 12-row spot-check table (4 visual / 3 HUD / 3 audio / 2 gameplay), 6 image re-opens, 8 citation re-opens, errata entries | `$RUN/verify/report-m4-final.json`, `$EVID/task-8-checks.md` |
| IS-6 | 9 | `security-audit.json` PASS, 0 Critical/High, `events.jsonl` PASS line, `teamwork_next` ALL_TASKS_PASSED | `$RUN/verify/security-audit.json`, `$EVID/task-9-audit.md` |
| IS-7 | 10 | Docs tree equals base, no game/tools/build/extracted diff, clean tree, <=25 MiB, no scratch, no push | `$RUN/verify/final.json`, `$EVID/task-10-merge.md` |
| IS-8 | 1, 9, 10, F1-F4 | All nine tasks `verified_pass`, no stale active task, `final.json` PASS, worktrees pruned, final report complete | `$RUN/state.json`, `$RUN/final.md`, `$EVID/f1-compliance.md` ... `f4-fidelity.md` |
