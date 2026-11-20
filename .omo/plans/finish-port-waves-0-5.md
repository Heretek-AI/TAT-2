# Finish TAT-2 port — ordered plan (Waves 0–5)

Goal: docs/MASTER_PROMPT_OMO_ULW_FINISH_PORT.md §10 DONE gate. Tier HEAVY.
Notepad: /tmp/ulw-finish-port-notepad.md. Goal objective is binding.

## Wave 0 — Preflight (run key `tat2-wave0-preflight`)
- w0-make-test (quick): run `make test`, capture SUMMARY + SCRIPT ERROR count → waves/wave0/make-test.log
- w0-audit-baseline (quick): run `make audit` + `verify_baseline.py`, capture coverage + 8/8 → waves/wave0/audit-baseline.md
- w0-envstrip-diagnostic (deep-low): live Vulkan `--env-strip=0..8` Den RD counts per strip + offending pass hypothesis → waves/wave0/envstrip.md (needs GPU; single probe at a time)
- w0-temp-hook-inventory (quick): inventory TEMP `_env_strip_level` hook sites in mission_controller.gd (read-only) → waves/wave0/temp-hook.md
- Verifier (self, main session): re-run make test/audit, confirm files exist.

## Wave 1 — Mass-parallel fixes (run key `tat2-wave1-fixes`, dependsOn Wave 0 files)
Disjoint write scopes; one writer per file at a time.
- w1-pg1-stability (deep-low): owns level_loader.gd, weather_visuals.gd, mobile_profile.gd + shared mission_controller.gd window; RD root-cause fix, teardown fix, FPS tuning. Reads waves/wave0/envstrip.md.
- w1-pg6-audio (unspecified-high): owns audio_manager.gd, save_system.gd, noise_bus.gd, audio_*.json + call-site wiring; bus architecture + AU1/AU3/AU4/AU5/AU6 pools.
- w1-pg3-pg5-vfx (deep-low): owns main_menu.gd trim path, tat_hdr_emissive.gdshader + smoke/beam/ward/alarm VFX; T1-03-E + KF01/KF14-KF29 parity.
- w1-pg2-pg7-gameplay (deep-low): owns guard_ai.gd, thief_character.gd, HUD (gem/arcs/pips, pause text), pickpocket/takedown/doors/crank; 7 E2E alias fixes + PG-4 live-confirm prep. MUST NOT touch mission_controller.gd while w1-pg1 holds it — if conflict, serialize via dependsOn.
- Each node: change + proof (relevant suite green), report file waves/wave1/<id>.md.

## Wave 2 — Integration + export (run key `tat2-wave2-integration`, dependsOn Wave 1)
- w2-merge-verify (quick): confirm Wave 1 reports present, re-run affected suites.
- w2-remove-temp-hook (quick): single writer removes TEMP hook from mission_controller.gd; verify grep zero + suite green.
- w2-export-config (unspecified-low): create game/export_presets.cfg (Linux preset, template paths) + Makefile linux-build/linux-release/linux-run targets.
- w2-linux-export (deep-low, dependsOn export-config + remove-temp-hook): run linux export → build/tat2-linux-x86_64, capture log.

## Wave 3 — Live GPU + comparison (run key `tat2-wave3-liveqa`, dependsOn Wave 2 binary)
- w3-e2e-strict (deep-low): `capture_e2e_parity.sh --strict` → 21/21 log + PNGs.
- w3-fps-profile (deep-low): Startscreen/Den/Guildhall FPS at 720p+1080p, RD-zero check, teardown exit 0.
- w3-port-capture-score (writing): record S01–S27 route from Linux binary, make_side_by_side.sh KF01–KF30, draft COMPARISON_SCORECARD.md 120-row scores.
- Main session re-runs --strict + FPS spot checks (never trust summaries alone).

## Wave 4 — Delta closure (run key `tat2-wave4-delta`, only if scorecard shows fixable DELTA/MISSING)
- Per-pillar chains a-i→b-i per remaining item; re-export, re-capture, rescore. Skipped if Wave 3 already 0/0.

## Wave 5 — Docs, hygiene, gate (run key `tat2-wave5-closeout`)
- Update HANDOFF_NEXT_SESSION.md, FIDELITY_GAPS.md, docs/reports/linux-60fps-parity-final.md; hygiene (no build/.godot/generated/extension_api.json tracked, debug_autostart unset).
- Full gate rerun + reviewer (omo-native-gate-reviewer, HEAVY+plan triggers gate) until unconditional approval (max 2 re-reviews), then per-increment Conventional Commits.
- Cleanup: kill PIDs/tmux/sessions/containers, lsof ports, remove RUN_TMP roots + QA temp paths; record read-back receipts in notepad.

Delegation topology: workflow DAG per phase (ordering is the point); parallel background task spawns only for fully independent reads; no team_create (no cross-talk needed — handoffs via files); main session keeps Wave 0 verify, live reruns, final gate + commits.
