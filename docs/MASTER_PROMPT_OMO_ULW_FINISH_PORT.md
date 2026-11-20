# `omo` Mass-`ulw` Master Prompt: Finish TAT-2 (Godot 4.7.2 · Linux 60 FPS · Visual & Gameplay Parity)

> **How to launch this in standalone `omo` (pi coding agent):**
> Run `omo` inside `/home/john/Projects/TAT-2` and send:
> ```text
> ulw Read and execute docs/MASTER_PROMPT_OMO_ULW_FINISH_PORT.md end to end. Orchestrate mass-parallel background agents across Waves 0–5, verify every fix both headlessly and on live Vulkan Forward+ + the exported Linux binary, score all 120 rows of docs/reference/clip_1795033698901/COMPARISON_TEMPLATE.md, and do not stop until every Tier-1 gate in §10 passes.
> ```

---

## 0. Mission & Scope

You are completing the **Godot 4.7.2 Forward+ / Jolt Physics** port of *Thick As Thieves* in `/home/john/Projects/TAT-2`, using:
- **Official UE5 installation (reverse-engineering source of truth):** `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/` (and pre-extracted `extracted/`, 4.7 GB)
- **Official-footage reference baseline (visual, audio, UI, and gameplay comparison target):** `/home/john/Projects/TAT-2/docs/REFERENCE_BASELINE.md` and `/home/john/Projects/TAT-2/docs/reference/clip_1795033698901/`

### Scope Tiers
- **Tier 1 (MANDATORY for `<promise>DONE</promise>`):**
  1. Close all open Parity Gaps **`PG-1` through `PG-7`** across **Startscreen (`MainMenu`) → Thieves' Den → Mission Prep / Loading / Briefing → Constables' Guildhall**.
  2. Achieve **>= 60 FPS** (`<= 16.67 ms` frame time) on Linux Vulkan Forward+ at `1280x720` and `1920x1080` across Startscreen, Thieves' Den, and Constables' Guildhall, with **zero `RenderingDevice` cascades** and **clean quit-to-desktop teardown**.
  3. Ship a standalone **Godot 4.7.2 Linux x86_64 export build** (`game/export_presets.cfg` + `Makefile` `linux-build` / `linux-run` targets → `build/tat2-linux-x86_64`).
  4. Record/capture the matching route from the Linux build, run `make_side_by_side.sh`, score all **120** criteria in `COMPARISON_TEMPLATE.md`, and iterate until **zero `MISSING`** and **zero fixable `DELTA`** items remain (only documented `HARD_LIMIT`s).
  5. Pass `make test` (`fails=0`, `0 SCRIPT ERROR`), Tier-1 E2E (`110/110`), `make audit` (`>= 99.4%`), and live Vulkan `capture_e2e_parity.sh --strict` (`21/21`).
- **Tier 2 (Best-effort after Tier 1 is 100% green, or document remaining status):**
  - `OldManor_P` terrain walk/collision verification (`PG-8`), Steam-56 full-set diff, and Android APK regression (`make android-release` per `docs/ANDROID.md`).

---

## 1. Orchestration Rules (`omo` Mass `ulw` Mode)

- **Do NOT use `opencode-teamwork-v2` (`teamwork_*` tools) or per-task git worktrees.** Run directly in `/home/john/Projects/TAT-2` using `omo` `ultrawork` (`ulw`) parallel background agents, Hashline edits, and disciplined wave merges.
- **File-ownership discipline (zero concurrent edit collisions):**
  - Never let two parallel agents edit the same `.gd` or `.gdshader` file at the same time.
  - Partition Wave 1–2 workers strictly by subsystem/file ownership (e.g., `audio_manager.gd` + `save_system.gd` vs. `main_menu.gd` + `tat_hdr_emissive.gdshader` vs. `guard_ai.gd` + `thief_character.gd` vs. `mission_controller.gd`).
  - Only ONE agent at a time touches `game/project.godot`, `game/tests/run_tests.gd`, or `game/src/missions/mission_controller.gd`.
- **Never trust agent summaries alone:** Re-run `make test`, live Vulkan captures, and FPS probes yourself after every wave merge.

---

## 2. Environment, Paths & Gotchas (Read Before Touching Code)

| Item | Exact Value / Rule |
|---|---|
| **Godot binary** | `flatpak run org.godotengine.Godot` (`4.7.2.stable.flathub`) |
| **Linux export templates** | `/home/john/.var/app/org.godotengine.Godot/data/godot/export_templates/4.7.2.stable/` (already installed) |
| **Python** | `/usr/bin/python3` for Pillow/numpy scripts (`docs/reference/...`); check `Makefile` (`python3`) for `tools/parse_*.py` |
| **Official UE5 build** | `"/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/"` (quote path — spaces!) |
| **Extracted UE5 dump** | `extracted/` (13,162 packages, 2,045 GLB, 2,416 PNG, 107 level dumps, 141 tables, 1,437 BP/mat dumps) |
| **Reference baseline** | `docs/REFERENCE_BASELINE.md` + `docs/reference/clip_1795033698901/{KEYFRAME_INDEX.md,BREAKDOWN.md,CALLOUT_LEGENDS.md,COMPARISON_TEMPLATE.md,clean/,annotated/,tools/}` |
| **Repo docs** | `docs/HANDOFF_NEXT_SESSION.md`, `docs/FIDELITY_GAPS.md`, `docs/ARCHITECTURE.md`, `docs/PERFORMANCE.md`, `docs/reports/*.md` |
| **Pre-existing uncommitted edit** | `game/src/missions/mission_controller.gd` currently has TEMP `--env-strip=0-8` debug hook (`PG-1`). **Use it to diagnose Den RD cascade, then REMOVE the TEMP hook cleanly before Wave 5.** |
| **Never commit / pollute** | Never commit `build/`, `game/.godot/`, `game/data/generated/`, or `extension_api.json`. Never leave `debug_autostart_contract` set in `game/project.godot`. |

### GDScript 4.7 & Probe Gotchas (`docs/HANDOFF_NEXT_SESSION.md:121-135`)
1. No `:=` on untyped `Dictionary` / `Variant`.
2. **Never** write `bool(Object.get(...))` — throws `Nonexistent 'bool' constructor`; use `value == true`.
3. Headless `--script` cannot `preload()` scripts referencing autoloads — use runtime `load()`.
4. Headless probes: wait for both `doors` and `guards` groups, always `quit()` on every path, redirect output to a file (never pipe through `head`), and wrap in `timeout`.
5. **Never** run two mission-load probes concurrently (heavy CPU/RAM).
6. Headless `make test` uses Godot's dummy renderer and **does NOT compile GLSL** — shader/rendering changes MUST be verified with `--rendering-driver vulkan` or live desktop capture.

---

## 3. Reverse-Engineering & Recreation Policy

1. **Extract before inventing:** When a gameplay constant, UI string, material parameter, level prop, or Wwise audio event is missing or wrong, inspect `extracted/`, `tools/tat-extract/`, `tools/parse_*.py`, and `"/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/"` first.
2. **Authorized reference-matched recreation for Hard Limits (`HL-1`, `HL-2`, `HL-4`, `HL-6`, `HL-7`):**
   - Because compiled Niagara VectorVM rates (`HL-1`) and expressionless cooked UE5 material node graphs (`HL-2`) cannot be extracted, you are **explicitly authorized** to build **reference-matched procedural Godot shaders, materials, and `GPUParticles3D` systems** calibrated visually against `docs/reference/clip_1795033698901/clean/KF01..KF30` and `BREAKDOWN.md`.
   - Document every such recreation honestly in `docs/FIDELITY_GAPS.md` / `docs/reports/` as `APPROX_SHADER` / `REFERENCE_MATCHED` (never claim it was VM-decompiled).
3. **Truth hierarchy:** Official footage (`docs/reference/` + `/home/john/Videos/clip_1,795,033,698,901.mp4`) + live official game assets > `docs/HANDOFF_NEXT_SESSION.md` > older reports.

---

## 4. Workstream 1 — Live GPU Stability & Linux 60 FPS (`PG-1`)

Target files: `game/src/missions/mission_controller.gd`, `game/src/core/level_loader.gd`, `game/src/core/weather_visuals.gd`, `game/src/core/mobile_profile.gd`, `game/project.godot`.

1. **Diagnose & eliminate Den RD cascade (`PG-1`):**
   - Run the existing `--env-strip=0` through `--env-strip=8` levels on Thieves' Den (Contract 1) on live Vulkan Forward+ and record exact `RenderingDevice` (`texture_create` / `update_sizes` / `uniform_set`) counts per strip level.
   - Identify the exact offending pass (glow/bloom, adjustment LUT, SSR, SSIL, volumetric fog, reflection probe, or shadow/viewport scale) and fix the root cause (e.g., stable render-target sizing, bounded bloom/SSIL/fog settings, probe update mode) so `strip 7` (full pipeline) runs with **0 RD cascade warnings**.
   - **Remove the TEMP `--env-strip=0-8` hook** (`_env_strip_level` var, helpers, and call sites) from `game/src/missions/mission_controller.gd` once fixed.
2. **Fix Vulkan swapchain / `X connection` teardown crash (`PG-1`):**
   - Ensure clean `SceneTree` / `Window` / `SubViewport` / `RID` shutdown on Quit (`S27`) and in screenshot/capture scripts (`build/qa/capture_*.gd`), eliminating exit-time crashes and `X connection` drops.
3. **Profile & optimize to >= 60 FPS on Linux (`1280x720` and `1920x1080`):**
   - Measure frame time (`<= 16.67 ms`), draw calls, active lights, shadow casters, and `MultiMesh` batching across **Startscreen**, **Thieves' Den**, and **Constables' Guildhall** (including the dense interior/exterior overlook `S16–S20` and foyer `S24–S25`).
   - Tune `LevelLoader` visibility ranges, `BoxOccluder3D` culling, shadow-caster light budget, SSIL/SSR/volumetric fog sample counts, and `SubViewport` update policies (`mission_prep_ui.gd` / `wardrobe_ui.gd`) without sacrificing visual parity against `docs/reference/`.

---

## 5. Workstream 2 — Full Audio Runtime Parity (`PG-6`)

Target files: `game/src/core/audio_manager.gd`, `game/src/core/save_system.gd`, `game/src/stealth/noise_bus.gd`, `game/data/generated/audio_{library,events}.json`, plus call sites in `ui/`, `player/`, `ai/`, `interact/`, `missions/`.

Currently `5,018` decoded Wwise OGGs exist in `game/assets/ue/audio/wwise/`, yet `AudioManager` only plays 9 static tags (`PG-6`). Close `PG-6` against `KEYFRAME_INDEX.md` §4 and `BREAKDOWN.md`:
1. **Bus architecture & `SaveSystem` routing:** Create proper Godot audio buses (`Master`, `Music`, `SFX`, `Ambience`, `UI`, `Dialogue`) and wire `SaveSystem.apply_saved_settings()` (`settings_ui.gd` sliders) to drive all buses.
2. **Ambience & room tone (`AU1`):**
   - Startscreen (`S01`): steady night rain + distant street air (`-53 to -49 dBFS`), **explicit zero BGM**.
   - Thieves' Den (`S03–S08`): quiet interior room tone (`-76 to -73 dBFS`), **no ambient BGM** until Gramophone is activated (`S07`, `00:44–00:50` diegetic 1920s jazz).
   - Guildhall (`S12–S26`): safe-room quiet tone, exterior rain/wind + distant car horn (`S13`), interior foyer/parlor room tone, **no BGM**.
3. **UI audio (`AU4`):** Menu hover/click/back (`S01`, `S04`, `S06`, `S27`), tab switch (`[Q]/[E]`), 6-second Mission Prep countdown ticks (`S09`, `00:59–01:05`), Black Market purchase chime.
4. **Surface-specific footsteps & foley (`AU3`):** Detect floor material/surface (`wood`, `cobble`, `puddle`, `carpet`/`stone`) and play randomized variation pools from `audio_events.json` (eliminating single-clip repetition).
5. **Gameplay SFX & VO (`AU5`, `AU6`):** Wire ZipWire aim/launch/crank/latch (`S14–S17`), Smoke Bomb equip/throw/hiss (`S18`), Pickpocket/Takedown grapple/impact (`S22–S23`), Security Beam hum/trip (`S24`), Arcane Barrier hum (`S25`), Crimson Alarm klaxon (`S26`), and ThiefNisha + Guard alert/suspicion/takedown VO lines (`KEYFRAME_INDEX.md` §4).

---

## 6. Workstream 3 — Visual, Shader & VFX Parity (`PG-3` `T1-03-E`, `PG-5`, `HL-1`, `HL-2`, `HL-7`)

Compare directly against `docs/reference/clip_1795033698901/clean/KF01..KF30` and `BREAKDOWN.md`:
1. **Fix `T1-03-E` (`PG-3`):** Implement the missing left-corner trim specular path in `game/src/ui/main_menu.gd` / `level_loader.gd` so Tier-1 E2E `T1-03-E` passes.
2. **Startscreen & Neon (`PG-5`, `KF01`):** Tune Startscreen ambient/exposure, flickering `Mac Neish` / `Jeweller` magenta neon (`00:00.1–00:02.1` flicker cadence) + pale-gold core saturation, wet cobblestone puddle specular reflections, and foreground vintage car silhouette.
3. **Thieves' Den (`KF02–KF11`):**
   - Arched frosted leaded-glass window volumetric teal-cyan moonlight shaft (`KF02`, `KF05`, `KF06`), Telescope `PONDER` night sky + cratered full moon (`KF05`), Wardrobe armoire warm interior light + Spider/Chameleon models (`KF03–KF04`), Ledger Journal & Black Market diegetic panels (`KF07–KF08`), Gramophone (`KF09`), Map Table tokens (`KF10`), Mission Prep ThiefNisha + `6`s countdown (`KF11`).
4. **Guildhall Lighting, Atmosphere & Reference-Matched VFX (`HL-1`, `HL-2`, `HL-7`, `KF14–KF29`):**
   - Street rain streaks & wet cobble puddles (`KF15–KF17`), distant car headlights (`KF16`), rooftop mist/fog (`KF17–KF18`).
   - **Smoke Bomb plume (`S18`, `KF20`):** Replace plain box stand-in (`PG-7`) with layered billowing volumetric-style `GPUParticles3D` smoke cloud + subtle linger/dissipate matching `KF20`.
   - **Foyer Security Beam (`S24`, `KF27`):** Volumetric/emissive scanning cone/beam from wall emitter (`y~40%`) + floor plate glow.
   - **Arcane Barriers (`S25`, `KF28`) & Crimson Alarm (`S26`, `KF29`):** Shimmering cyan/magenta arcane barrier shader + alarm strobe/vignette pulse on trip.

---

## 7. Workstream 4 — Gameplay, AI, UI & E2E Parity (`PG-2`, `PG-3`, `PG-4`, `PG-7`)

1. **Fix `T1-18-E` (`PG-3`):** Resolve missing `escape_points` (`escapes=0`) on Contract 2 level data/loader so Tier-1 E2E passes **`110/110`**.
2. **Fix all 7 Live E2E Parity Fails (`PG-2`):**
   - `S03` (`map_table_look_at_card`), `S04` (`wardrobe` `clipped_controls`), `S06a`/`S06b` (`mission_lobby_fov_20` — `11.33` vFOV vs `20.0` hFOV), `S11` (`zipwire_crank` `equipped_tool!=zipwire`), `S14` (`guard_pips_and_offscreen_arcs` node naming), `S15b` (`circular_lockpick_minigame_ui` node naming).
   - Run `bash build/qa/capture_e2e_parity.sh` and `--strict` until **`21/21` PASS**.
3. **Live-confirm Phase 4 mechanics (`PG-4`):**
   - ZipWire crank clip playback (`6ab91a3`), stairs snap `0.3` / `50°` (`2799c8e`), and swinging door `70°` open-leaf disable + Den `0.95 m` window gap (`b58c69e`) on live GPU.
4. **Close `PG-7` Gameplay & HUD Polish against `docs/reference/`:**
   - **Normative HUD parity (`KF14–KF30`):**
     - **Light Gem (`UI3`):** bottom-center diamond showing light exposure amount + directional warm sector.
     - **Player Noise Arcs (`UI5`):** concentric red arcs flanking/above the gem driven by player noise output (never enemy threat).
     - **Guard Alert Pips (`UI5`):** distinct overhead/directional red (`alert`, `KF21`) & green (`suspicion`, `KF22`) indicators.
     - **Pause Menu (`KF30`):** `RESUME`, `SETTINGS`, `RETURN TO THIEF'S DEN` (note clip exact text!), `QUIT`, build/seed footer.
   - **1P ZipWire viewmodel (`player-1p.md:99-104`):** Wire 1P ZipWire launch/crank/equip animations (`KF16–KF17`).
   - **Lockable blue double doors (`KF24`), Parlor Pickpocket (`KF25`) & Guard Takedown (`KF26`):** Ensure smooth prompt (`[F]`, `[HOLD]`), takedown transition/animation, and foyer beam/ward/alarm state machine (`S24–S26`) match the clip's flow.
   - **Guard locomotion:** Reduce foot-slide (`guard-animations.md:131-143`) by matching locomotion playback rate to `velocity.length()`.

---

## 8. Workstream 5 — Standalone Godot 4.7.2 Linux Export Build

1. **Create `game/export_presets.cfg`:**
   - Configure `[preset.0]` for `"Linux"` (`platform="Linux"`, `export_path="../build/tat2-linux-x86_64"`, `binary_format/architecture="x86_64"`, `custom_template/debug` & `release` pointing to `/home/john/.var/app/org.godotengine.Godot/data/godot/export_templates/4.7.2.stable/linux_debug.x86_64` and `linux_release.x86_64` or default template discovery).
2. **Add `Makefile` targets (`linux-build`, `linux-release`, `linux-run`):**
   - `$(GODOT) --headless --path game --export-release "Linux" $(CURDIR)/build/tat2-linux-x86_64` (output under gitignored `build/`).
3. **Verify exported Linux binary:**
   - Launch `build/tat2-linux-x86_64` directly (without the Godot editor), play through Startscreen → Den → Guildhall, verify **0 `SCRIPT ERROR`**, **0 `SHADER ERROR`**, **>= 60 FPS**, and clean exit code `0`.

---

## 9. Workstream 6 — Visual & Gameplay Comparison Loop (`docs/reference/`)

1. **Capture Port Footage (`docs/REFERENCE_BASELINE.md` §9):**
   - Using the Linux build at `1920x1080` (or `1280x720` scaled), record/capture the **exact 27-segment route (`S01–S27`)** into `docs/reference/port_<YYYYMMDD>/` (or `build/qa/port_comparison/` if keeping large video out of git — save lightweight JPEGs & scored markdown in `docs/reference/port_<YYYYMMDD>/`).
2. **Generate Side-by-Side Pairs:**
   - Use `docs/reference/clip_1795033698901/tools/make_side_by_side.sh <port_clip> <offsets.csv>` to extract all 30 aligned `KF01–KF30` side-by-side images.
   - Inspect **every** side-by-side pair visually (`V1–V7`, `UI1–UI5`) and check audio/gameplay timings (`AU1–AU6`, `G1–G5`).
3. **Score `COMPARISON_TEMPLATE.md` (120 rows):**
   - Copy `COMPARISON_TEMPLATE.md` to `docs/reference/port_<YYYYMMDD>/COMPARISON_SCORECARD.md` and score all 120 rows (`PASS | DELTA | MISSING | HARD_LIMIT | N/A`).
   - **Iterate:** For every row scored `MISSING` or fixable `DELTA` (anything NOT a true `HARD_LIMIT`), fix it in Godot, re-export/re-capture, and re-score until Tier-1 parity is achieved.

---

## 10. Wave Execution Plan & `<promise>DONE</promise>` Gate

### Recommended Mass-Parallel Wave Flow
- **Wave 0 (Preflight):** Run `make test`, `make audit`, `verify_baseline.py`, and `--env-strip=0..8` RD cascade diagnostic on live Vulkan.
- **Wave 1 (Mass Parallel — Disjoint Files):**
  - Agent 1: `PG-1` RD cascade root-cause + teardown fix + 60 FPS profiling (`level_loader.gd`, `weather_visuals.gd`, `mission_controller.gd`).
  - Agent 2: `PG-6` Full `AudioManager` + `SaveSystem` bus routing + ambience/music/UI/footstep/VO wiring.
  - Agent 3: `PG-3` (`T1-03-E`, `T1-18-E`) + `PG-5` Startscreen neon/exposure + `HL-1`/`HL-2` VFX shaders (`Smoke`, `Beam`, `ArcaneBarrier`, `Alarm`).
  - Agent 4: `PG-2` (7 E2E parity fixes) + `PG-7` (1P ZipWire, HUD Light Gem/noise arcs, Pause menu text, guard foot-slide, pickpocket/takedown).
- **Wave 2 (Integration & Linux Export):** Merge Wave 1 changes, remove TEMP `--env-strip=0-8` from `mission_controller.gd`, add `game/export_presets.cfg` + `Makefile` `linux-build`, export `build/tat2-linux-x86_64`.
- **Wave 3 (Live GPU & Comparison Loop):** Run live Vulkan tests (`capture_e2e_parity.sh --strict`), benchmark >= 60 FPS across Startscreen/Den/Guildhall, record port route, run `make_side_by_side.sh`, and score all 120 rows of `COMPARISON_SCORECARD.md`.
- **Wave 4 (Delta Closure & Verification):** Fix every remaining non-`HARD_LIMIT` `DELTA`/`MISSING` row, re-export Linux binary, re-verify side-by-side.
- **Wave 5 (Docs & Hygiene):** Update `docs/HANDOFF_NEXT_SESSION.md`, `docs/FIDELITY_GAPS.md`, and a final `docs/reports/linux-60fps-parity-final.md` report; verify `git status` has no `build/`, `game/.godot/`, `game/data/generated/`, or `extension_api.json` tracked.

### `<promise>DONE</promise>` Acceptance Gate (Every Check Must Exit `0`)
- [ ] `make test` → all suites `SUMMARY: fails=0`, `0 SCRIPT ERROR`
- [ ] Headless Tier-1 E2E (`run_e2e_tests.gd`) → `SUMMARY: fails=0 passed=110 total=110`
- [ ] `make audit` → `>= 99.4%` coverage
- [ ] Live Vulkan `capture_e2e_parity.sh --strict` → `21/21 PASS`, `0 SHADER ERROR`, `0 SCRIPT ERROR`, `0 RD cascade warnings`, clean exit
- [ ] Linux export `build/tat2-linux-x86_64` builds cleanly and runs Startscreen + Den + Guildhall at **>= 60 FPS** (`<= 16.67 ms` frame time) with clean exit
- [ ] `mission_controller.gd` TEMP `--env-strip=0-8` hook removed; `project.godot` `debug_autostart_contract` not left set
- [ ] `docs/reference/port_<YYYYMMDD>/COMPARISON_SCORECARD.md` has all **120** rows scored with **0 `MISSING`** and **0 fixable `DELTA`** items
- [ ] `docs/reference/clip_1795033698901/tools/verify_baseline.py` → `8/8 [PASS]` (baseline integrity preserved)
