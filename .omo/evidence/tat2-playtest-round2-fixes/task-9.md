# Task 9 — Wire takedowns end to end (synced Atk + Vic blackjack handoff)

Date (UTC): 2026-11-20. File-level verify only (no `make test`, no live-GPU run per task; orchestrator owns settle).
Scope: `game/src/core/animation_library.gd` role tables + `game/src/player/thief_character.gd` blackjack Atk span + `game/src/ai/guard_ai.gd` victim spans + this ledger. Crank, diamond, minis, head-bind spans untouched. Ground truth read first: Wave 0 ledger `task-0.md` symptom 8 CONFIRMED (`grep -c takedown animation_library.gd` = 0, `_try_blackjack` instant-KO with no victim handoff; upstream clips PRESENT-BUT-UNWIRED per §4 asset A5), F12 backlog row (ST_Guard + DAM + AnimSet clip roles), prior waves suite-green note in task brief.

Checkpoint (steer 2026-11-20): all four deliverable parts DONE, none in flight — (1) takedown roles in animation_library with manifest+GLB cites DONE; (2) Atk bind in thief `_try_blackjack` DONE; (3) Vic bind in guard victim path DONE; (4) this task-9.md DONE (this write + disk re-read confirms).

Auth note: standing read-only agreement (`system/agreements`, broken x5) says treat `TAT-2` as read-only. Current task explicitly authorizes the listed spans, so per the boundaries rule (current instruction wins) this turn edits ONLY those spans + this file. Approval was requested via the question tool before editing; the 30-minute wait timed out with no answer and the tool instructed best-judgment completion, so the scoped edits below were applied and verified file-level.

Design: explicit-bind only. No clip is invented; no Attack/unused quarantine clip (`AN_Takedown_Fall*_Vic*`, `AN_Takedown_Guard_Heavy_Front_Atk*`, `AN_BlackJack_Takedown_In/Loop*`) is referenced by any role table or bind span — they are named in one library comment solely to record their exclusion. Guard victim reuses the existing slip pattern (one-shot flag + finished-handoff to knockdown loop + KO-handle ownership). Thief attacker mirrors the F13 3P crank drive (dedicated `TPTakedownPlayer` on the 3P rig, never the 1P viewmodel). Missing-clip behavior is loud no-op (`push_warning` with the full UE path), never a crash; camera punch + `GameState.takedowns` counter + noise are kept by the caller in all cases.

## 1. Roles (animation_library.gd) — DONE

Guard victim role `takedown_vic` added to both weapon tables (no HA-specific takedown exists upstream, so both sets share the Synced victim clips), to `ROLE_ORDER`, and to `ROLE_PATTERNS`. Not added to `LOOP_ROLES` (one-shot) or `STRIP_ROOT_TRANSLATION` (guard one-shots keep root). Regex fallback matches only Synced stealth-vic / overhead montages, so the quarantine set cannot match even if enumerated (guard-related gate in `_resolve_clip` also excludes non-GuardEnforcer quarantine names).

Thief attacker roles in new `TP_TAKEDOWN_CLIPS` (3P rig only, consumed via `ensure_tp_takedown_atk_clip`, never by 1P or guard): primary `takedown_atk_3p`, alternates `takedown_atk_stealth_3p` / `takedown_atk_overhead_3p`. One-shot (`loop: false`), in-place (`strip root: true`), thief-skeleton similarity retarget (same precedent as crank/FP).

## 2. Clip cites (all manifest + on-disk verified this turn) — DONE

Manifest: `game/data/generated/anims_manifest.json` (995 entries). Disk base: `game/assets/ue/Anims/` + manifest `glb`. All 8 bound clips `exists=True`, 501 tracks each:

| # | Clip (manifest `animation`) | Manifest `glb` | Dur | Role bind |
|---|-----------------------------|----------------|-----|-----------|
| 1 | `AN_StealthTakedown_GuardEnforcer__Vic_Montage` | `TAT/Content/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__Vic_Montage.glb` | 3.483 | guard `takedown_vic` primary |
| 2 | `AN_StealthTakedown_GuardEnforcer__Vic` | `TAT/Content/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__Vic.glb` | 3.483 | guard `takedown_vic` fallback |
| 3 | `AN_TakedownOverhead_Behind_Montage` | `TAT/Content/Art/Animation/Base/Anim/Synced/AN_TakedownOverhead_Behind_Montage.glb` | 1.650 | guard `takedown_vic` fallback |
| 4 | `AN_TakedownOverhead_Behind` | `TAT/Content/Art/Animation/Base/Anim/Synced/AN_TakedownOverhead_Behind.glb` | 1.650 | guard `takedown_vic` fallback |
| 5 | `AN_TakedownOverhead_Front_Montage` | `TAT/Content/Art/Animation/Base/Anim/Synced/AN_TakedownOverhead_Front_Montage.glb` | 1.650 | guard `takedown_vic` fallback + thief `takedown_atk_overhead_3p` |
| 6 | `AN_TakedownOverhead_Front` | `TAT/Content/Art/Animation/Base/Anim/Synced/AN_TakedownOverhead_Front.glb` | 1.650 | guard `takedown_vic` fallback |
| 7 | `AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage` | `TAT/Content/Art/Animation/Thief/Anim/Gear/BlackJack/AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage.glb` | 4.233 | thief `takedown_atk_3p` primary |
| 8 | `AN_StealthTakedown_GuardEnforcer__Atk_Montage` | `TAT/Content/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__Atk_Montage.glb` | 3.483 | thief `takedown_atk_stealth_3p` alternate |

Extracted-source cross-check: `extracted/json/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__{Atk,Vic}*.json` + `AN_TakedownOverhead_*.json` and `extracted/json/.../BlackJack/AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind*.json` present (44 takedown JSONs on disk).

## 3. Binds — DONE

Atk — `thief_character.gd` `_try_blackjack` span: `_play_blackjack_camera_punch()` kept, then `_tp_takedown_atk_start()` added before damage eval. New `_tp_takedown_atk_start()` resolves `_tp_crank_body_skel()`, creates/reuses `TPTakedownPlayer`, prefers the cached animation, else `ThiefAnimLib.new().setup("club", skel)` + `ensure_tp_takedown_atk_clip(player)`, plays with `FP_ANIM_BLEND`. Both failure exits `push_warning` with the full UE path `TAT/Content/Art/Animation/Thief/Anim/Gear/BlackJack/AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage` and return without touching KO/counter/noise. Guard loop, damage curve, behind-dot, `take_knockout`, `GameState.takedowns += 1`, punch, VFX unchanged.

Vic — `guard_ai.gd` victim spans: new `_takedown_vic_anim` flag; new `play_takedown_vic()` (role `takedown_vic`, `0.2` blend, owns player like slip); `knock_out()` prefers `takedown_vic` montage (sets flag, `1.0` speed, `0.25` blend) and falls back to `knockdown` loop when the role did not retarget; `_on_guard_anim_finished()` adds the `_takedown_vic_anim -> knockdown` handoff mirroring slip; `_update_guard_anim()` yields while `_slip_anim or _takedown_vic_anim`; `_play_guard_attack()` and `_recover_from_ko()` clear the flag. `take_knockout -> knock_out` path unchanged, so the blackjack KO now enters the synced montage automatically.

## 4. Handoff sequence (blackjack takedown) — DONE

1. Player triggers `_try_blackjack` (F hold / blackjack input): 1P swing + swing VFX + `_play_blackjack_camera_punch` (unchanged).
2. `_tp_takedown_atk_start`: thief 3P rig plays `AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage` (4.233 s, `TPTakedownPlayer`); loud UE-path warning + silent continue if unresolvable.
3. Guard loop: `take_knockout(final_dmg) -> knock_out()`: victim plays `AN_StealthTakedown_GuardEnforcer__Vic_Montage` (3.483 s, `_takedown_vic_anim` owns the player).
4. `GameState.takedowns += 1` + `NoiseBus takedown` 4.5 (kept).
5. Guard `_on_guard_anim_finished(takedown_vic) -> _play_guard_clip("knockdown", true)`: prone loop owns KO; wake path unchanged (`_recover_from_ko` clears flag, plays `search`).

## 5. Changed ranges (post-edit)

- `game/src/core/animation_library.gd` (749 lines): role tables `:25-69` (`CLUB_CLIPS :26-37`, `HA_CLIPS :38-50`, `ROLE_ORDER :51-55`, `ROLE_PATTERNS :56-68`); takedown 3P table `TP_TAKEDOWN_CLIPS :502-506`; `ensure_tp_takedown_atk_clip :546-575` (after `ensure_tp_crank_clip :524-544`). Crank/FP/diamond/minis/head lines untouched.
- `game/src/player/thief_character.gd` (3030 lines): handoff call `:1759` in `_try_blackjack :1748-1783`; new `_tp_takedown_atk_start :1807-1832` after `_play_blackjack_camera_punch :1786-1797`. Damage/counter/noise/punch/VFX lines unchanged.
- `game/src/ai/guard_ai.gd` (1602 lines): flag `:162`; attack clear `:381`; slip clear `:399`; `play_takedown_vic :411-421`; finished handoff `:425-449`; update guard `:475`; `knock_out` Vic-prefer `:1192-1206`; recover clear `:1236`. Attack/slip/knockdown clip names and locomotion untouched.

## 6. Verify

- Re-read all edited spans from disk before reporting (done; ranges above). Re-read this file from disk after this write (done).
- Manifest grep: every code-referenced bound clip (8/8) resolves to an `anims_manifest.json` entry with `glb` present on disk under `game/assets/ue/Anims/` (verified this turn; the two regex-fragment misses in the raw grep are comment line-wraps, not clip refs).
- Quarantine grep: no `Attack/unused` or `BlackJack/.../unused` clip appears in any role table or bind span (exclusion recorded in the `TP_TAKEDOWN_CLIPS` comment).
- Crank/diamond/minis/head spans untouched: `zipwire_crank`, `FP_TOOL_CLIPS` blackjack entries, minis/head binds show no diff beyond the listed ranges.
- No `make test` / live-GPU run (orchestrator owns settle per task).
