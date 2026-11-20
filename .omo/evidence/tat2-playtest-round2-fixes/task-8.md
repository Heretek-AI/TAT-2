# Task 8 — Cap tool/lamp light rig (night blow-out fix)

Date (UTC): 2026-11-20. File-level verify only (no `make test`, no live-GPU run per task; orchestrator owns settle).
Scope: `game/src/player/thief_character.gd` diamond/light spans + `game/src/core/vfx_manager.gd` flash/OrbLight spans + this ledger. Crank/takedown/guard spans untouched by this turn. Ground truth read first: Wave 0 ledger `task-0.md` (symptom 7 CONFIRMED — `DIAMOND_ENERGY_CAP := 0.65` covered only the 1P gem; uncapped: orb 2.2, cable 2.8, flashes 2-3, loader tongs path; screenshots show blown lamp-bloom orbs), F10 backlog row (`MI_VistaraDiamond` found), prior `task-10.log` (gem 1.25 → 0.65, mission glow 0.65 kept).

Auth note: standing read-only agreement (`system/agreements`, broken x5) says treat `TAT-2` as read-only. Current task explicitly authorizes the listed spans, so per the boundaries rule (current instruction wins) this turn edits ONLY those spans + this file.

Design: every in-scope emitter now carries the DIAMOND-style triple — `const X_ENERGY_CAP := 0.65`, `assert(... <= CAP + 0.001)`, `print("<Sentinel>: ...")`. Cap value 0.65 everywhere = mission `glow_intensity 0.65` / `DenMoonBeam` 0.65 bloom reference (task-10.log); gem cap and mission glow unchanged. Nothing invented: UE-cooked values cited per row; unrecoverable numerics are standing HARD_LIMITs below, never approximations.

## 1. Per-emitter rows (15 capped; 2 standing HARD_LIMITs)

| # | Emitter (prior) | UE source / HARD_LIMIT | Cap | Span (post-edit) | Sentinel |
|---|---|---|---|---|---|
| 1 | Vistara gem 0.65 (kept) | `extracted/json/Art/Gameplay/Gear/VistaraDiamond/MI_VistaraDiamond.json`: `Emissive On?` = false, `Emissive` = null (verified this turn) | 0.65 | thief `:2541-2553` (`_apply_vistara_materials`, pre-existing) | `DiamondCap: vistara gem emission_energy=` |
| 2 | Zipwire cable 2.8 | `extracted/json/Art/Gameplay/Gear/Zipwire/MI_Zipwire.json`: `Emissive On?` = false, `Emissive` = null (verified this turn) — UE authors emissive OFF, so any port glow is invention; capped to bloom ref | 0.65 | thief `:1077-1098` (`_update_zipwire_cable`) | `CableCap: zipwire cable emission_energy=` |
| 3 | Fairy orb (tool surf) 2.2 | No UE orb authoring recovered: `SK_PickpocketFairy.json` carries no emissive/MI; `MI_PickpocketFairy_Jar.json` has NO Emissive param (Normal+ORM only); `grep -c Light/Intensity` over all 8 PickpocketFairy JSONs = 0; filelist light search = 0 hits (evidence §3). Exact UE orb energy unrecoverable → HARD_LIMIT H1; capped to 0.65 | 0.65 | thief `:2575-2588` (`_apply_fairy_materials`) | `FairyCap: fairy orb emission_energy=` |
| 4 | Zipwire tip fallback 2.0 | Port-authored fallback glow, no UE source → HARD_LIMIT H1; clamped via helper | 0.65 | thief `:2715-2719` (`_build_fp_zipwire_fallback` + helper clamp `:2679`) | `ZipwireTipCap: zipwire tip emission_energy=` |
| 5 | Fairy fallback orb 2.5 | Port-authored fallback glow, no UE source → HARD_LIMIT H1; clamped via helper | 0.65 | thief `:2833-2838` (`_build_fp_fairy_fallback` + helper clamp `:2679`) | `FairyFallbackCap: fairy fallback emission_energy=` |
| 6 | Sap vial 1.5 | `extracted/json/Art/Gameplay/Gear/Slithersap/MI_SlimeBomb.json` (+Glass): `Emissive On?` = true with `T_SlimeBomb_E` texture, but numeric `EmissiveStrength` is a runtime param NOT enumerated in cooked MI (only named in `CachedExpressionData.ParameterInfoSet`). Exact UE multiplier unrecoverable → HARD_LIMIT H1; capped to 0.65 | 0.65 | thief `:2809-2817` (`_build_fp_sap_fallback`) | `SapCap: sap vial emission_energy=` |
| 7 | Smoke trajectory 2.0 | No UE trajectory authoring (port aiming guide) → HARD_LIMIT H1 | 0.65 | thief `:2856-2883` (`_update_smoke_trajectory`) | `SmokeTrajCap: smoke traj emission_energy=` |
| 8 | FP fallback helper (uncapped branch) | Port-authored; safety clamp for all `_fp_fallback_mat(..., energy)` callers | 0.65 | thief `:2670-2683` (`_fp_fallback_mat`: `minf(energy, CAP)` + assert + conditional print) | `FallbackCap: fp fallback emission_energy=` |
| 9 | Brass tongs (loader MI path) | Same MI as row 1 (Emissive Off, null) — safe; clamp is belt-and-braces | 0.65 | thief `:2561-2563` (post-load `minf` clamp + assert + print) | `TongsCap: tongs emission_energy=` |
| 10 | 3P/viewmodel wrap (loader PBR branch) | `_wrap_material_for_vm` passed `std.emission_energy_multiplier` through uncapped; now `minf(..., 0.65)` | 0.65 | thief `:2043-2063` (`_wrap_material_for_vm`) | `TongCap: viewmodel emission_energy=` |
| 11 | VFX fairy orb emissive 2.0 | Same as row 3 (no UE orb authoring) → HARD_LIMIT H1 | 0.65 | vfx `:27-49` (`spawn_fairy_orb` orb_mat) | `FairyOrbCap: fairy orb emission_energy=` |
| 12 | OrbLight 1.2 | No UE point-light authoring for the fairy orb (search evidence §3: 0 hits across fairy JSONs + filelist) → HARD_LIMIT H1 | 0.65 | vfx `:28-63` (`spawn_fairy_orb` OrbLight) | `OrbLightCap: orb light energy=` |
| 13 | Sap spark emissive 3.0 | Same as row 6 (EmissiveStrength unrecovered) → HARD_LIMIT H1 | 0.65 | vfx `:122-144` (`spawn_sap_burst` spark_mat) | `SapSparkCap: sap spark emission_energy=` |
| 14 | SapFlash light 2.0 | No UE flash-light authoring (search evidence §3) → HARD_LIMIT H1 | 0.65 | vfx `:123-170` (`spawn_sap_burst` SapFlash) | `SapFlashCap: sap flash energy=` |
| 15 | IgnitionFlash (smoke) light 3.0 | No UE flash-light authoring (search evidence §3) → HARD_LIMIT H1 | 0.65 | vfx `:626-640` (`spawn_smoke_plume` IgnitionFlash) | `SmokeFlashCap: ignition flash energy=` |

Kept (verified, not edited): gem 0.65, mission `glow_intensity 0.65`, `DenMoonBeam` 0.65, `light_probe.gd:115` weights.

## 2. Standing HARD_LIMITs (unrecoverable in scope — never approximated)

- H1 — Exact UE emissive/light numerics for the fairy orb, OrbLight, SapFlash/IgnitionFlash lights, smoke trajectory, fallback glows, and the SlimeBomb `EmissiveStrength` scalar are unrecoverable from cooked data in scope. Search evidence (run this turn): `MI_PickpocketFairy_Jar.json` has no Emissive param at all; `grep -c 'Light|PointLight|Intensity|Candela|Lumen'` = 0 across all 8 PickpocketFairy JSONs; `grep -ril 'SapBurst|FairyOrb|OrbLight|IgnitionFlash|SapFlash'` over `extracted/json/` = empty; filelist fairy-light grep = 3 audio-only hits (`Play_tristan_fairy_ftue_stealth_orb_*`, VO, not lights); `MI_SlimeBomb.json` names `EmissiveStrength` only as a runtime `ParameterInfoSet` entry with no value enumerated. Fix direction: cap all of them to the port bloom reference 0.65 (mission glow) per the task, with per-emitter assert + run-log line. No value invented.
- H2 — `level_loader.gd` generic PBR path NOT edited (out of scope: only thief/vfx spans writable this turn). Standing facts: `get_material_for_ue` sets `mat.emission_energy_multiplier = 2.2` when an emissive texture binds (`:693-698`), and `_apply_ue_emissive` scales up to `clampf(..., 0.0, 16.0)` / `clampf(..., 0.0, 8.0)` (`:459-487`). No per-material UE scalar was recovered for the generic path in scope. Tongs stay safe regardless: source MI is Emissive-Off (row 1) plus the new `TongsCap`/`TongCap` clamps on the consuming side. If the loader default ever needs capping, that is a follow-up task owning `level_loader.gd`.

Out of scope, deliberately untouched (not tool/lamp rig): `spawn_grapple_beam` 2.5, `spawn_lockpick_sparks` 2.5, `spawn_blue_wisp` orb 3.0 / mote 2.5 / default param 0.30 (already under cap), foyer `housing` 3.0 / `node` 3.0 / `plate` 0.35 (under cap) / `EmitterGlow` 1.2, ward `wash` 1.6 / mote 2.0, vine 2.0 / `VineGlow` 1.2, alarm `spot` 4.5 + strobe 2.2/5.4 + `bulb` 4.0 + cone energy 2.2. Left for their owning tasks; not capped here per scope.

## 3. Changed ranges (post-edit line numbers)

- thief_character.gd: `:1077` cable const; `:1096-1098` cable cap+assert+print; `:2043` wrap const; `:2060-2063` wrap clamp+assert+print; `:2541` tongs const; `:2561-2563` tongs clamp+assert+print; `:2575-2588` fairy orb const+cap+assert+print; `:2670-2683` fallback helper clamp; `:2715-2719` zipwire tip assert+print; `:2809-2817` sap vial const+cap+assert+print; `:2833-2838` fairy fallback const+assert+print; `:2856-2883` smoke traj const+cap+assert+print. Gem `:2542-2553` unchanged.
- vfx_manager.gd: `:27-28` fairy/orblight consts; `:47-49` orb cap; `:61-63` orblight cap; `:122-123` sap consts; `:142-144` spark cap; `:168-170` sap flash cap; `:626` ignition const; `:638-640` ignition flash cap.
- This file: `.omo/evidence/tat2-playtest-round2-fixes/task-8.md` (exists).

## 4. Verification (file-level + targeted check, no suite/GPU run)

- Re-read every edited span from disk after edit — content matches §1/§3.
- `grep` for the triple: thief = 12 `const X_CAP := 0.65` lines (11 new + gem), 12+ asserts, 12 prints; vfx = 5 consts, 5 asserts, 5 prints. Full `git diff` for the two files adds 30 `Cap:` lines (`git diff ... | grep -c '^+.*Cap:'` = 30). Every capped emitter has assert + print; `grep` output pasted in the turn log.
- Added-lines scope proof: `git diff -- <two files> | grep '^+' | grep -i 'crank|takedown|guard_ai'` hits are ONLY the pre-existing Wave-2 worktree (`_tp_crank_*` 3P drive, `_begin_wire_crank` comments — "crank done" per brief); this turn's 30 added lines contain no crank/takedown/guard logic changes. Takedown spans (`animation_library`, `thief _try_blackjack`) and guard spans (`guard_ai`) have zero added lines from this turn.
- Targeted value check: all in-scope bare literals replaced — no remaining `= 1.2/1.5/2.0/2.2/2.5/2.8/3.0` on the §1 spans; remaining `>0.65` literals in vfx_manager belong to the out-of-scope list above (beam/lockpick/wisp/housing/ward/vine/alarm), verified by read.
- `make test` NOT run (task instruction; Waves 1-2 suite-green 90 PASS at settle must not regress — edits are scalar clamps + asserts/prints, no API changes).
