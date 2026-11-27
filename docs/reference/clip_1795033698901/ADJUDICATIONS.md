# Adjudications — binding verdicts for the remediation programme

Teams: treat this file as authoritative over the individual lane reports where it
speaks. It is appended as F1b lands.

## F1a — visual/capture (settled)

| # | Question | Verdict | What teams must do |
|---|---|---|---|
| C-1 | Are `sheets/w_*.png` from another build? | **No — they are from the master MP4.** RMSE 0.55 % / 0.81 % vs a 0.28–0.61 % resampler floor; the other recording on disk scores 24.5 %. All three "build fingerprint" strings are mis-reads (`STRIKE PIN` at 163.8, `TUMBLER 1/2` + `LOCK JAMMED!` in both artefacts at 164.97; `SPACE: JAM`, `TOGGLE PIN`, `PICK UP` occur zero times in the tree). `[E] CLOSE` vs `[F] CLOSE` is authored: two door classes (`lockable_door.gd:316`, `swinging_door.gd:250`). | **Do not** spend time on a "different build". L4's capture-integrity finding is closed as NOT REPRODUCED. The real defect behind it is that two door classes print different keys for the same verb — T05/T06 own the prompt contract. |
| C-2 | What is the magenta/violet panel? | **L2 is right, both sites.** `ward_zone.gd:164-179` + `_apply_active:226` render `tat_ward.gdshader` on the ward-zone `BoxMesh`. Constant G/R 0.766 over a 1.4× brightness range excludes the WorldGrid albedo (sd 0.393) and the crate-stencil fallback (teal, alpha 0.176). A 24–26 px facet lattice at 19.2 facets/panel height ⇒ **0.12–0.18 m**, matching `1/5.5 = 0.182 m` and the authored 3.5 m box. `SM_WardBox` has been skipped since `32fe554`, two days before the capture. | T08-MATERIAL fixes the ward's facet contrast/alpha (energy×facet collapses sd to 0.031; alpha 0.6–0.86 makes it a solid pane). T08 must **not** chase a missing texture or WorldGrid substitution for this object. |
| C-3 | Is the telescope present? | **Yes.** `TELESCOPE / [F] PONDER`, `KILCAIRN SKYLINE / [F] EXIT` and the cheese moon read cleanly at 1:1 in `f_0020–f_0027`. L5's absence claim is a method artefact. | KF05 is `PRESENT`; score it. The real defect is L4-13: the `[F] EXIT` drops the player on the Den roof. T10-GAMEPLAY owns it. |
| C-4 | Health bar or panel frame? | **Both, different elements.** The framed top-left artefact is the health bar: `T_healthBar_straight_frame.png`, exactly 1024×256, under a flat 204×20 fill with a **permanent** blood-splatter. The mission text has **no frame** in the shipped UI (C5 is right on that point). RE-L's duplication is real — a compressed second copy of the frame beside the right cap, the objective line overprinted with itself, `[HOLD] PIN MENU` over `MMB` — but there is only **one** `HudScript`/`hp_frame`, so the cause is **undetermined**. | T05-UI fixes the bar composition (authored shaped fill, splatter only when damaged, correct height) and investigates the duplication with the named experiment: instrument `_ready`/`add_child` counts for the HUD and the hp frame. Do not implement a "second HUD" theory. |
| C-5 | `UNADVY` garble, overlapping lock hints? | **Neither exists.** `UNREADY` is clean at 1:1; the lock hint is one line matching `hud.gd:3019` character for character. | No fix. Closing both as NOT REPRODUCED. Any remaining glyph ghosting is the separate HUD-duplication issue in C-4. |

**F1a spot-check:** 8/8 re-run evidence commands reproduced (L1 coverage 58.5 % at t=193
and 44.3 % at t=260; L2 `#7F5BBB` and `0.481254`; L3 both strings; L4 bar-at-166 and
the 18.8 s cut). Two **attributions** need correcting: L1's "~40 %" belongs to `t=260`,
not `t=258`.

## F1b — data/code (settled)

| # | Question | Verdict | What teams must do |
|---|---|---|---|
| C-1 | HUD objective counter | **`[0/1]`.** The take is `Contract.Main.2` (`Into the Lion's Den`), authored `kind: single`, one item → one row (`mission_controller.gd:2665-2667`) → `hud.gd:2488` prints `Mission: Into the Lion's Den [0/1]  (mm:ss)` + `❧ Steal the Vis'ara Files`. Decisive: the frames carry a timer suffix **and** a `❧` sub-line, which the free-play branch (`hud.gd:2453-2467`) cannot produce, so `[0/4,000]` is a different but also-correct path. A localised NCC against the shipped Raleway ranks `[0/1]` first (0.6145) and `[0/11]` last (0.5164). | C4 was right. RE-J's loot-counter model applies to **free play only**. W0b/L3/L4 are misreads of the italic `1`+`]` kerning. T10 must not "fix" the counter; it is correct. |
| C-2 | Endgame window | **1200 s at every difficulty.** Precedence: tracked KF13 override → QG `EndgameDuration` (480) → 480 fallback. **No difficulty term exists.** Main window 3300 / 1200 / 1200. The ini ladder 1200/600/300 is real but **no producer reads any `.ini`**. QG `MatchMainPhaseDuration 1320` is extracted and unconsumed. | The runtime 1200 is **correct**; do not change it. T01 must extract the ini ladder so the *future* difficulty-based design is data-driven, and T10 must document that the ladder is currently inert. |
| C-3 | Prep regression mechanism | **Camera reframe in `7128d43` is primary** — 14.06 m / 69.06° from the authored `CameraActor_0` (reproduced from `MissionLobby_Geo3`). The 1.26 m thief move in `6760dd0` is **secondary**. L3's "byte-identical" is a diff-range artefact (`git log -S` shows the string exists only in `7128d43`). | T05 fixes the camera first, then the skyline scale, then hands the grade to T07. `build/qa/vf_mission_prep.png` is the reference frame. |
| C-4 | Loot constants | Authored slot cost is **1/1/1**; `major = 3` is a **documented port decision**. `DifficultyToLootMultiplier` is neither stored nor applied, and `DIFFICULTY_MULTIPLIER_APPLIED` exists **only inside `AGENTS.md`**. | T10 keeps major=3 but labels it as a port decision in code and docs; T01 extracts the multiplier; the AGENTS sentence is replaced (see doc corrections). |
| C-5 | Graybox floors | The visible checker is **authored granite** (`SM_Floor_2x2A` → `MI_GraniteFloorA` → `T_GraniteFloorA_D`). **1,622 of 1,637** `GB_Floor_2x2` carry authored materials; the other 15 are **red wood varnish**, not grey. | `FIDELITY_GAPS`' graybox attribution is wrong about what the player sees. T09 fixes the 15 genuine cases and the override table; nobody "fixes" the granite. |

**F1b spot-check:** 5/5 reproduced across five lanes (RE-I 210/673, RE-A 76/5/6/23 +
five empty dirs, RE-N-03, RE-Q-05, RE-G-08). **One number fails:** RE-D-02's
"915 deduped lights" does not reproduce — the runtime `160` does, the undeduped sum is
**999**, and the dedupe rule is not quoted. T07 must derive the true authored count and
record the rule rather than repeat 915.

**Doc corrections from F1b:** nine, listed in `findings/F1b-adjudication.md`
§Doc corrections with replacement sentences. The integrator applies them after the
teams land; teams must not edit `AGENTS.md`/`README.md`/`FIDELITY_GAPS.md` directly.
