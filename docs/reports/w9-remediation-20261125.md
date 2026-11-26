# W9 — data consumption, visual truth, UI completeness and the StateTree ceiling

The wave that followed R8. Four phases, each with its own lead and nested
investigate → research → implement → **independent audit** chain, each in a sealed
worktree that the integrator cherry-picked and re-gated.

- **Base:** `e3678be` (R8 + the two audits)
- **Tip:** `4845992`
- **Phases:** P0 verification/gates · P1 data + visual truth · P2 behaviour + fills ·
  P3 UI completeness · P4 StateTree
- **Commits:** 34

## 1. Phase results (measured, not claimed)

| Phase | Delivered | Decisive number |
|---|---|---|
| **P0** verification | three Vulkan captures, perf matrix, scorecard closure, ratchet raised to R8 | upper foyer p50 **34**, gate **23.9 %** black; AO cost ≤0.17 ms |
| **P1** data + visual | authored collision, progression, input/curves, sprite tokens, prep composition | collision **937/947 (98.9 %)**, **+2,878** instances recovered; prep mean **37.1 vs KF11 37.2**, black floor **18.8 % vs 22.9 %** |
| **P2** behaviour | fills, authored locks, ESC guard, lockpick stand-in, Den window, jam/endgame | **363 locks applied** (157 containers, 8 doors), zero invented levels; upper foyer **34 → 29** |
| **P3** UI | 3 screens, Loc wiring, pad focus, TAB map, toast | routed strings **26 → 306**; authored-mappable **26/51 → 195/195**; focus **67 checks / 10 screens**; map **13/13** actors |
| **P4** StateTree | game-neutral interpreter + shadow mode + coverage | **0 of 21 trees fully evaluable**; 113/326 tasks, 35/233 conditions; side-effect signature identical |

## 2. The decisions, and where they landed

- **Collision — every mesh at once.** Done behind `TAT2_COLLISION=authored|aabb`
  (default authored). It also exposed three producer bugs: `half_extent` was the
  *full* extent (a 2× trap), the capsule axis was wrong, and the convex bake ignored
  instance scale — together 95,293 Jolt scale errors, now zero. The port also
  recovered 2,878 instances the old 0.45 m AABB gate silently dropped.
- **Progression — authored.** `progression.gd` consumes `project_settings.json`:
  level cap 25 with XP preserved, the authored award, endgame precedence
  **KF13 → 1200/600/300 → QG → 480**, FTUE 5,000 with a one-shot migration, and
  **48 market gates** verified.
- **Locks — authored only.** The producer now emits lock level, cap and key-only
  flags; `probe_lock_inventory` reports `applied=363`, `state=APPLIED`, and the live
  log shows `swinging doors: 155 locked=2`.
- **StateTree — full runtime.** S1 shipped: a game-neutral model/parser (validates
  21/21 trees, 459/467 transitions, fails closed on five corruption modes), an
  interpreter, a shadow runner, coverage and traces. **S2 is not attempted** because
  the payload drops every node parameter — see §4.
- **VFX/materials — fix, don't accept.** Partly met: the input path bug was fixed and
  the transcription deleted; sprite tokens were re-resolved, but **23/29 was not
  reachable** — only 12 of the 29 are placed-sprite textures, 20 of 23 rejected pages
  have no alpha, and the ceiling is 15/39 without new shader modes. Reported with the
  data rather than forced.
- **Verification first.** Three captures and the perf matrix landed before any code
  changed, which is what caught the interior overshoot and the invisible skyline.

## 3. What the audit chain caught (the part worth keeping)

Every phase's auditor was someone who did not write the code, and every one of them
failed its first pass:

- **P2's invented room grade was rejected by its own pre-registered criteria** —
  C1/C3/C4/C7 failed, so the 0.49 exposure lever was reverted and the room shipped as
  fill-removal only. The pre-registration happened *before* the capture.
- **P3's string audit was inflated** by a prefix rule (+11 rows) and corrected to a
  strict exact-source count; a freed-node crash had silently skipped three modal
  assertions.
- **P4's first audit caught two false data claims** (the payload's flat `transitions[]`
  does carry `fallback`/`delay`), and the second caught a **regression the implementer
  introduced** — an ancestor transition re-entered the active state and grew the frame
  stack.
- **P4's suite-98 finding**: a test that asserted its own temporary state ("0
  boundaries, producer patch owed") had to be replaced when the patch landed.
- **P1's load claim was retracted** by audit: the direction is unresolved inside a
  ±3.9 s spread.

## 4. The StateTree ceiling, stated plainly

The dump is a **property dump, not a compiled tree**. Every task and condition that
matters depends on an authored parameter it does not carry:

- tasks: 77 classes, **18 mapped, 59 unsupported**, 113/326 instances, **94 parameter-blind**
- conditions: 36 classes, **6 mapped, 30 unsupported**, 35/233 instances, 32 blind
- **0 of 21 trees fully evaluable**

So the port runs the authored tree *in shadow* and reports where it would differ, but
the FSM still drives. A real cutover needs the producer to emit node parameters
(`EAlertnessLevel`, `DelayTask.duration`, `Move To` targets, `Bool Compare` operands);
the contract is written in `build/qa/w9/p4-t01-contract.md`. This is now recorded as a
**data ceiling**, not an open-ended TODO.

## 5. The other open items

- **Interior brightness remains open**: upper foyer p50 **29 % / 1.1 % black** and
  `yaw180` **31 / 2.5 %**, against the reference's 13–15 / 9–24. Fill removal recovered
  5 of ~19 points; the rest is authored-light level plus highlights (p95 182 vs KF27's
  34). A future lane needs the **temporal** `AEM_Basic` adaptation (0.2 f-stops/s,
  ~20 s), validated against the gate pose as well.
- **IBL** still an approximation: the SkyLight cubemap export is the blocked item
  (`available=false, sky_contribution=0.0` in the live log).
- **Lockpick** has 41 assets and **0 animations**; the labelled stand-in is what ships.
- **VFX sprites**: 6 soft-mask textures bind; 34 of 39 placed materials still use the
  procedural falloff.
- **Suite-45 stairs flake** observed once; a clean rerun is recorded.
- The invented 600×600 `KillZ` floor is labelled `PORT INVENTED` (no authored KillZ).

## 6. Gates at the tip (`4845992`)

compile **186/0** · `run_tests` **314 PASS, fails=0** (suites to 111) · M2 fails=0 ·
**E2E 278/278** (tier 1 117/117) · DOORWALK / VIEWMODEL / NIAGARA / BLACKJACK /
GEOM probes PASS · **`make runtime-smoke` PASS** (`script_errors=0`,
`mission_ready=1`, and clean with `TAT2_STATETREE=shadow`) · `make audit` PASS
(12,660/12,703) · texture cap 797/1/0 · perf guard 78/78 · `make gate-ratchet` PASS.

## 7. Process changes that came out of this wave

1. **`make runtime-smoke` is now a gate.** It exists because a live playtest threw a
   `SCRIPT ERROR` on every footstep while E2E reported 278/278 — the suites never
   exercised occlusion. It boots a real free-play mission for 90 s and fails on any
   script or shader error.
2. **Pre-register measurement criteria before running them.** The room-grade revert is
   the example: a mechanism that produced perfect stills was rejected because it failed
   numbers agreed in advance.
3. **Per-phase single worktree, lead commits, independent auditor.** Twelve R8 teams
   taught the cost of three teams claiming "suite 91"; this wave allocated numbers by
   the integrator and had one writer per file per phase.
4. **Auditors must not be authors**, and their first pass should be expected to fail.
