# T08 MATERIAL — remediation report

Team: **T08-MATERIAL** (materials / textures / material shaders).
Worktree: `/home/john/Projects/TAT-2-rem-T08-material`, branch `rem/T08-material`.
Base: `fb93f84` (`docs(audit): reclassify audio rows after the capture-artefact proof`).
Worker branches merged in by cherry-pick: `rem/T08-wA-producer` (`a2dadbd`),
`rem/T08-wB-cap` (`58a4fc7`).

Binding inputs used: `REMEDIATION_PLAN.md` invariants S1–S6, `ADJUDICATIONS.md`
**C-2** (the magenta panel is `ward_zone.gd` + `tat_ward.gdshader` on the
ward-zone box, not a missing texture and not `SM_WardBox`), `findings/RE-C-materials.md`,
`C2-materials-code.md`, `L2-materials.md`, `RE-Q-meshing.md` §RE-Q-06.

**No Vulkan capture was taken.** Every visual claim below is either a JSON/DB
measurement, a headless probe, or an explicitly labelled transfer-function model.
Where a number could only be modelled, it says so.

---

## Team summary

| # | Finding | Sev | Verdict |
|---|---|---|---|
| 1 | 541 authored tints assigned linear-as-sRGB (110,729 binds / 39 %) | P0 | **FIXED** |
| 2 | 315 authored master-texture slots dropped (`M_BlockerWard`, `M_sf2_birch_bark` 876, `DoorWard`) | P0 | **FIXED** |
| 3 | `BasePropertyOverrides.BlendMode`/`ShadingModel` never read | P1 | **FIXED** |
| 4 | GLB props ship zero textures; `MI_CatStatueA` 600× `Color` used as albedo | P1 | **FIXED** |
| 5 | Ward shader: energy×facet collapses facet contrast, alpha makes a pane | P1 | **FIXED** (shader arithmetic; no capture, see S6) |
| 6 | Name-substring matcher overrides the authored slot index | P1 | **FIXED** |
| 7 | Texture-cap coverage (285 files unseen) + allowlist without reasons | P2 | **FIXED**; 14 newly gated targets need the integrator's `make desktop-texture-cap` |
| 8 | `SM_Shape_*` debug primitives + silent flat-colour path | P2 | **FIXED** as scoped; the finding's 58/171 count is **NOT REPRODUCED** (see §8) |
| 9 | No texture streaming/eviction; roughness bake 3.7 s / 80 MB | P2 | **DEFERRED** (quantified, no safe change) |

Gate status on `rem/T08-material` with the **regenerated producer output**
(`/tmp/opencode/t08/gen2`, byte-identical to a clean re-run of the committed
parser; the integrator must run `make normalize` to put it in the shared tree):

| gate | result |
|---|---|
| `check_scripts_compile.gd` | `scripts checked: 124, broken: 0` |
| `make test` (`run_tests.gd`) | `SUMMARY: fails=0` (279 PASS; suite 91 is new) |
| `test_m2_player.gd` | `M2_SUMMARY: fails=0` (11 PASS) |
| `tests/test_t08_materials.gd` (new) | `T08_SUMMARY: fails=0` |
| `tests/probe_t08_red.gd` (new, red proof) | pre-fix `reproduced=3/3`; on this tree `reproduced=0/3` |
| `tests/probe_t08_level.gd` (new) | `debug_shape_hidden=8` on `OldManor_Geo`, `0` on the 11-override control |
| E2E tier 1 | `fails=0 passed=117 total=117` |
| E2E `--tier=s2` (loot) | `fails=0 passed=12 total=12` |
| `make texture-cap-check` | **fails closed by design on this tree** (`offenders: 14`) until `make desktop-texture-cap` — integrator action |
| `make audit` | **fails closed by design on this tree**: content-overrides PASS, the cap gate reports 24 offenders, and `manifest_audit` (run directly, all content OK — `entries=1629 with_albedo=1376 texture_refs=1523 missing_textures=0`) fails exactly 4 baseline stamps: `parse_materials.py` sha + `materials_albedo 1379→1376` + `gen:materials.json` content + `prebake_texture_cap.py` sha. `make audit-refresh-stamps` is integrator-only |

---

## 1. RE-C-08 / C2-02 — 541 authored tints were applied linear-as-sRGB (P0)

- **severity:** P0 (110,729 level binds = 39 % of 284,305)
- **S1 investigate:** `_pick_tint` (`tools/parse_materials.py:731-764` before the
  change) stores the authored UE vector verbatim; `get_material_for_ue` assigned
  it straight to `albedo_color` (`level_loader.gd:1481` before the change). Godot
  declares `albedo_color` as `source_color`, i.e. sRGB-decoded in the shader, so
  a linear UE value is one gamma too dark/saturated. The project had already
  proven the mechanism twice and not generalised it:
  `_apply_diffuse_mask_tint` (`level_loader.gd:900-916`) and the storefront decal
  (`FIDELITY_GAPS.md:210`, `lin.linear_to_srgb()` exact-path fix).
- **S2 research:** UE material colour parameters are linear; the cooked JSON
  (`materials.json.tint`) is the authored `VectorParameterValue`/cached default
  verbatim. Godot 4 `BaseMaterial3D.albedo_color` is documented `source_color`
  (sRGB→linear decode), and the port's own shaders declare the same convention
  (`tat_glass.gdshader:10-13`).
- **S3 confirm (red):** `tools/godot --headless --path game --script res://tests/probe_t08_red.gd`
  on the reverted (base-commit) loader:
  ```
  T08_RED tint_applied_linear=1 (M_EnvLoot albedo_color=(1.0, 0.361, 0.078, 1.0))
  T08_RED: reproduced=3/3
  ```
  Data census over the pre-fix `materials.json`:
  `total=541 low=530 hdr=11 low_with_albedo=447 low_with_albedo_binds=110396`;
  with the 11 HDR carries counted the RE-C figure reproduces exactly
  (456 materials / 110,729 binds).
- **S4 fix:** `level_loader.gd` — the generic tint path now composes
  `tint × Overlay × Multiply` and desaturation in linear space and encodes the
  result **once** through a new `_srgb_encode_albedo_tint()` helper
  (`max(r,g,b) > 1.0` returns the colour untouched: an HDR value is an emissive
  carry on an additive/unlit path, not surface albedo). Producer side:
  `_pick_tint` no longer accepts an HDR generic `Color` as the albedo tint when
  anything ≤1 qualifies, and falls back to the authored `Flat Color`
  (`a2dadbd`, FIX 5). That is what removes the 600× multiplier from the loot
  family rather than clamping it.
- **S5 test:** new `game/tests/t08_material_checks.gd` is wired into
  `run_tests.gd` **suite 91** and asserts the encode unit, an authored
  representative (`M_EnvLoot` 0.3611 → sRGB 0.6351), the HDR pass-through
  (`M_Hotwire_Glow` 0,5,2 unchanged) and a textured character control.
  Suite 37's two textured controls were rewritten from
  `albedo_color.r > 1.0` (which pinned C2-02) to the version-agnostic contract
  `albedo_color == sRGB(authored linear tint)`, so they hold on both the pre- and
  post-T08 data. **Recorded reason for changing an existing expectation:** the
  old expectation encoded the defect the team brief calls out for
  `MI_CatStatueA`; the new one is stricter (it pins the exact encoded value).
- **S6 confirm (green):** same red probe on this tree
  ```
  T08_RED tint_applied_linear=0 (M_EnvLoot albedo_color=(1.0, 0.635, 0.3094, 1.0))
  ```
  Post-fix data census: `low=534 hdr=7 low_with_albedo=441 low_with_albedo_binds=110397`.
  Applied-sample census (40 materials built through the real loader):
  `T08 census tint_applied: candidates=398 sampled=40 mismatched=0` — i.e. no
  second assignment path bypasses the encode (398 = authored <=1 tints with an
  albedo map, excluding the wallpaper/thievesden rescue and the composites whose
  Overlay/Multiply factors the loader folds in before the encode).
- **verdict:** FIXED. Residual: `_apply_diffuse_mask_tint` still multiplies two
  sRGB-encoded factors; that is pre-existing behaviour and a smaller error than
  the raw-linear multiply it replaced (see Open risks).

---

## 2. RE-C-05 — 315 authored master-texture slots were dropped (P0)

- **severity:** P0 (the named families: `M_sf2_birch_bark` 876 binds,
  `M_BlockerWard` 376 binds, the whole `DoorWard` family)
- **S1 investigate:** `parse_materials.py` grouped `CachedExpressionData`
  RuntimeEntries[3] names into five buckets (`albedo`, `normal`, `orm`,
  `emissive`, `opacity`). 191 distinct group-3 names exist; 128 names / 315
  references matched none and were discarded silently. The albedo then fell
  through to a ranked guess.
- **S2 research:** group 3 is `TextureValues`, index-parallel with the names in
  the same record. `M_DoorWard_DoubleSided`: names
  `[NormalTexture, MaskTexture, Distortion_Texture, GlyphTexture]`, values
  `[T_Env_Wet_FluidNormal02, T_DoorWard_Lines, T_DistortionA, T_DoorWard_Glyph_Hand]`
  — the authored glyph art is recoverable, it was simply unclassified.
  `M_sf2_birch_bark` has an empty group 3 and one authored reference,
  `T_sf2_birch_bark_base_color2`, which `_is_albedo_stem` rejected because it
  ends `_base_color2`, not `_D`.
- **S3 confirm (red):**
  `python3 -` over `extracted/json/**` and the pre-fix `materials.json`:
  ```
  M_BlockerWard     albedo T_ThievesDen_Wardrobe_D.png  albedo_source fallback-ranked
  M_DoorWard_DoubleSided albedo T_ManorDoor_D.png       albedo_source fallback-ranked
  M_sf2_birch_bark  albedo T_TreePineBark_DA.png        albedo_source fallback-ranked
  unmatched group-3 names: 128 / 315 refs
  ```
  (All three bind art from a different family: a wardrobe, the manor front door,
  a pine bark.)
- **S4 fix:** `parse_materials.py` (`a2dadbd` FIX 2/3/4):
  `MainTexture`, `Main_Texture`, `RunesTexture`, `GlyphTexture` → albedo (only
  when no albedo is set); `EmisTexture` → emissive; `MaskTexture` → opacity, with
  authored dirt/fresnel masks (`*_Ma`, mean luma 0.49) deliberately kept out of
  the silhouette slot; brush/noise/distortion/`Texture`/`Mask`/`Param` stay
  dropped. Long-form base-colour stems count as albedo **only where the material
  itself references them** (the global guess pool would have repainted 20
  UI/sky/cloud masters with a cobweb map — measured, guarded with
  `allow_long_form=False`). Emissive-only materials no longer receive a
  fallback-ranked albedo guess (FIX 4).
- **S5 test:** suite 91 producer block asserts `M_sf2_birch_bark` binds its own
  base-colour map, `M_DoorWard_DoubleSided` binds the glyph, and
  `MI_BlockerWard` has `albedo_source == "none"` with no wardrobe texture.
- **S6 confirm (green):** regenerated data
  ```
  MI_BlockerWard          tint=None src=none alb=-                            (was wardrobe, 376 binds)
  M_DoorWard_DoubleSided  src=authored alb=T_DoorWard_Glyph_Hand.png         (was T_ManorDoor_D)
  M_sf2_birch_bark        src=stream-single alb=T_sf2_birch_bark_base_color2.png (876 binds)
  ```
  Dropped group-3 references **315 → 280** (8 names / 35 refs newly classified,
  3 albedo refs and 4 `T_white` emissive refs deliberately still unbound).
  Albedo changed on **53 materials / 1,254 level binds** (876 birch + 376
  BlockerWard + 2 others). `albedo_source`: authored 692 → **727**,
  fallback-ranked 280 → **241**, none 250 → **253**. Zero new albedo binds match
  `*Noise*`, `*PaintStroke*`, `*Grunge*` or a brush stem (asserted by the
  producer).
- **verdict:** FIXED.

---

## 3. RE-C-03 / C2-08 — `BasePropertyOverrides` was half-read (P1)

- **severity:** P1 (15 wrong blends, 31 wrong shading models; 1,283 foliage binds
  depended on an unrelated token fallback, 5 stained-glass panes were opaque)
- **S1 investigate:** `_extract_real_params` read `TwoSided` and
  `OpacityMaskClipValue` from `BasePropertyOverrides`, but `BlendMode` and
  `ShadingModel` only from the top-level properties (`parse_materials.py:584-599`).
- **S2 research:** the BPO block is the authored per-instance override of the
  material's render state. `bOverride_*` flags exist on only 28/17/27 records and
  are never written `false` (absent or `true`); no record carries both a
  top-level and a BPO value for the same field, so a present BPO value can only
  be an override.
- **S3 confirm (red):** census over `extracted/json/**`: top-level `BlendMode`
  248 / BPO 324 / both 0; top-level `ShadingModel` 137 / BPO 262 / both 0.
  After parent resolution: 5 materials still lacked a blend mode and 31 a
  shading model, including `MI_ISMSpruceNeedles` (739 binds),
  `MI_ISMPineNeedles` (387), `M_sf2_plants_Inst` (157) and
  `MI_LightsStainedGlass_Yellow` (5).
- **S4 fix:** `_extract_real_params` falls back to
  `BasePropertyOverrides.{BlendMode,ShadingModel}` (honouring `bOverride_*` when
  present) and canonicalises to `EBlendMode::…` / `EMaterialShadingModel::…`.
- **S5 test:** suite 91 asserts the two foliage materials and the stained-glass
  pane carry `BLEND_Masked`; the count of BPO-only materials still missing the
  resolved field is asserted **0** by the producer run itself.
- **S6 confirm (green):** BPO-only missing field **5/31 → 0/0**; resolved blend
  changed on 15 materials, shading on 31 (all `MSM_Unlit` gains). Render-changed
  materials cover **1,290 level binds** — 1,283 foliage (now authored-masked
  instead of relying on `FOLIAGE_TOKENS`) and the 5 stained-glass panes.
- **verdict:** FIXED.

---

## 4. C2-01 / C2-02 — GLB props ship zero textures; `MI_CatStatueA` HDR albedo (P1)

- **severity:** P1 (every loot/quest/clue/pickup prop was flat white; the cat
  statue additionally blew out to cream when bound)
- **S1 investigate:** the exporter writes no `images`, no `textures` and no
  `baseColorFactor`, so a raw-instantiated GLB surface is the glTF default
  (white, roughness 1). Call sites: `interact/loot_item.gd:159-167`,
  `interact/clue_item.gd:50-53`, `interact/world_pickup.gd:79-81`,
  `interact/thrown_bottle.gd:48-53`, `interact/lockable_door.gd:118-121`.
  `ui/tool_preview.gd` and `ui/wardrobe_ui.gd` **already** bind through
  `_mesh_mats_db` (C2's "tool_preview/wardrobe are raw" claim is stale — see Doc
  corrections). Second defect: `_pick_tint` accepted the HDR shine vector
  `Color {600, 98.98, 0}` as the albedo tint while the HDR shader path is gated
  on *no* albedo, so the statue multiplied its albedo map by 600.
- **S2 research:** `materials.json` carries `MI_CatStatueA` with albedo
  `T_CatStatueA_D.png` and `Flat Color {0.948, 0.753, 0.277}` next to the
  HDR `Color`; `mesh_materials.json` maps `SM_CatStatueA` → `MI_CatStatueA`.
  The authored albedo is therefore available and was simply never consulted.
- **S3 confirm (red):**
  ```
  T08_RED raw_glb_white=1 bound_after=0 (SM_CatStatueA.glb surfaces with a raw albedo map: 0; rebound: 0)
  ```
  and the HDR tint: `MI_CatStatueA tint=[600.0, 98.983, 0.0]`.
- **S4 fix:** new static `LevelLoader.bind_prop_scene_materials(root, glb_res_path)`
  resolves the GLB path back to its `/Game/…` path (`glb_res_to_ue_path`), reads
  the slot list from the **live** loader's `_mesh_mats_db` (registered by
  `_enter_tree` → group `level_loader`), and sets a per-instance
  `surface_override_material` (never mutates the shared imported Mesh). One line
  added at each of the five call sites. Producer: HDR generic `Color` is no
  longer an albedo candidate when a ≤1 candidate exists; `Flat Color` is the
  documented fallback (see §1).
- **S5 test:** suite 91 instantiates the real `SM_CatStatueA.glb`, proves the raw
  surface has no albedo map, calls the binder and asserts the override is
  `StandardMaterial3D` with `T_CatStatueA_D.png`; asserts
  `MI_CatStatueA.albedo_color.r <= 1.0` on regenerated data.
- **S6 confirm (green):**
  ```
  T08_RED raw_glb_white=1 bound_after=1 (raw albedo map: 0; rebound: 1)
  MI_CatStatueA tint=[0.948, 0.753, 0.277, 1.0] albedo=T_CatStatueA_D.png
  ```
  Tint diff over all 1,629 materials is exactly 4 (cat, crown, owl, knife);
  3 placed instances are directly affected, and the loot family's runtime reach
  is larger than its level-bind count.
- **verdict:** FIXED.

---

## 5. L2-01 / adjudication C-2 — ward shader arithmetic (P1)

- **severity:** P1 (the single most reported visual artefact; adjudication C-2
  binds the object: `ward_zone.gd` + `tat_ward.gdshader` on the ward-zone box)
- **S1 investigate:** `col = ward_color.rgb * energy * facet` with
  `facet ∈ [0.5, 1.0]` and `energy = 1.6` at the ward-zone site (2.0 in
  `vfx_manager`). Every facet therefore sat at or above the tone curve's
  shoulder (linear blue 0.80–1.60), so ACES/AGX compressed the intended 2:1
  facet range; `ALPHA = a*(0.70+0.30*facet)` at a = 0.55 gave 0.47–0.55, a solid
  pane. The hash also keyed on the **view-space** normal, so every facet
  re-rolled as the camera turned.
- **S2 research:** KF28 shows a clustered crystal column with near-black facet
  gaps and bright edges. The object and the shader's role are correct per C-2;
  only the transfer function is wrong. No cooked graph exists to match.
- **S3 confirm (red):** L2 measured the captured panel at sd 0.031 over a
  700×600 region with `#7F5BBB` dominant. Reproduced as a transfer-function model
  over the authored facet distribution (ACES fit, uniform hash, no seam):
  ```
  tone-mapped luminance (min/max/mean/sd)  old: 0.402 0.553 0.487 0.043
  linear blue range                       old: 0.800 .. 1.600  (100 % above the shoulder)
  alpha (a=0.55)                          old: 0.468 .. 0.550  (a pane)
  ```
  The model's old sd (0.043) is the same order as L2's measured 0.031, i.e. the
  model is calibrated to the finding. **No GPU capture was taken** (team brief).
- **S4 fix:** `tat_ward.gdshader` — facet body `0.08 + 0.92·hash^1.35`; dark
  seams from the cell-border distance (`smoothstep(0.0, 0.11, edge)`, applied as
  a 0.28 multiplier); `energy` is a peak gain (`clamp(energy*0.75, …)`) instead of
  a multiplier on every facet; a lit-shard core term; object-space-only hash;
  `ALPHA = a · coverage · seam · (0.18 + 0.62·facet)`.
- **S5 test:** `run_tests.gd` suite 70.x already instantiates `ward_zone.gd`; the
  shader is compiled by the project on load. No new numeric test (see S6 limit).
- **S6 confirm (green):** same model on the new transfer:
  ```
  tone-mapped luminance (min/max/mean/sd)  new: 0.206 0.792 0.404 0.162   (3.8x the facet sd)
  linear blue range                       new: 0.240 .. 1.260  (only the top ~5 % crosses 1.0)
  alpha (a=0.55)                          new: 0.126 .. 0.439  (mean 0.26, a veil)
  seam colour (linear 0.023/0.004/0.067)  -> tone-mapped 0.028  (near-black gaps)
  ```
  Per-site alphas: ward box 0.10–0.44, VFX veil (a=0.40) 0.07–0.32, shard boxes
  (a=0.90) 0.16–0.72.
- **verdict:** FIXED (arithmetic). The *visual* result is **not verified** — a
  capture at a warded door is the confirming step, and it belongs to the
  integrator's capture wave.

---

## 6. RE-Q-06 — the loader's name matcher overrode the authored slot index (P1)

- **severity:** P1 (silent mis-texture: glass→opaque, metal variants)
- **S1 investigate:** `_bind_glb_materials` preferred a case-insensitive
  name-substring match (either direction) over the primitive index; the index was
  only a fallback. Because `short.find(surf_name) >= 0` also matches, a surface
  named `MI_TrimMetalSurfaceA` bound slot `MI_TrimMetalSurfaceA_Copper`, etc.
- **S2 research:** the producer emits `mesh_materials.json` in **GLB primitive
  order** (`slot_order_source: "glb"` 2,047/2,065, `sidecar` 18) and RE-Q
  measured 1,893 exact name-and-count matches, **0 reorderings**; Godot imports
  GLB primitives in that order. The index is authored truth.
- **S3 confirm (red):** independent replay of the old rule against the real GLB
  material names and the authored slot lists:
  ```
  meshes with a different material: 53   placed instances: 776
  ```
  (RE-Q's 55/776; the 776 instance count matches exactly, the 2-mesh delta is the
  sidecar-ordered set). Concrete: `SM_Bank_Cabins_1x4` surface 1 bound
  `MI_TrimMetalSurfaceA_Copper` instead of `MI_TrimMetalSurfaceA` (20 instances),
  `SM_VaultDoor` surface 2 bound `_DirtLayer`, `SM_DisplayCaseA` surface 1 bound
  the wood body instead of `MI_DisplayCaseAGlass`.
- **S4 fix:** `_bind_glb_materials` binds by index; the name match survives only
  for an **empty** authored slot (24 slots / 14 meshes) and only when exactly one
  slot name matches. Each rescue is counted (`slot_name_fallback_count`).
- **S5 test:** suite 91 asserts the three named meshes bind their authored slot
  and *not* the legacy name-match material, and that
  `slot_name_fallback_count == 0` on the shipped data.
- **S6 confirm (green):** `T08_RED slot_name_override=0`; probe census
  `meshes_name_overridden=53 instances=776` (the *simulated legacy* rule, i.e.
  the class still measurable) and both real loads report
  `slot_name_fallbacks=0`.
- **verdict:** FIXED.

---

## 7. RE-C-22 / C2-07 — texture-cap coverage and the allowlist (P2)

- **severity:** P2 (VRAM/load, not visual correctness)
- **S1 investigate:** `tools/prebake_texture_cap.py::_collect_targets` scoped the
  cap to `materials.json` texs + PNG literals **in `level_loader.gd` only**;
  `--check` therefore could not see any other code literal or unreferenced
  oversize PNG. The alpha-critical allowlist was a bare set with one entry and no
  recorded reason.
- **S2 research:** the four numbers that matter are the target set, the capped
  set, the visible offenders and the out-of-scope inventory. Baseline
  reimplemented: 1,512 targets (1,507 material + 17 loader − 12 overlap),
  773 capped, 1 alpha-critical, 0 offenders — matching the committed W7 log.
- **S3 confirm (red):**
  ```
  pngs under extracted/assets: 2529   over cap (>1024): 1059
  over-cap targets 774 (= 773 + 1 exempt)   over-cap OUTSIDE targets: 285 (Art/UI 93, other 192)
  ```
  The `66` bypass claim reproduces as **66 literal occurrences** in `.gd` files
  other than the loader = 51 distinct paths / 40 new / **14 genuinely over cap**
  (`T_Blackjack_D` and `T_Moon_D` are already `materials.json` targets and already
  capped — doc correction). The 14 include the 6400×3600
  `T_loadingScreen_2.png` (92.16 MB decoded RGBA, no mips).
- **S4 fix:** `_collect_targets` scans `game/src/**/*.gd` **and**
  `game/scenes/**/*.tscn` for `res://assets/**/*.png` literals (dangling literals
  counted and skipped); `--check` prints the out-of-scope inventory; the
  allowlist is a `{path: reason}` map validated on every run.
- **S5 test:** the tool's own `--check` is the gate. It now fails closed on the 14
  newly visible targets (`offenders: 14`, `run: make desktop-texture-cap`).
  Recommendation deliberately **not** to add exemptions: measured silhouette
  delta at the 1024 cap for all ten masked cut-outs (T_HorizonA_BCO, T_Grate_D,
  T_PosterA/B/C_DA, T_MixedAds_D, T_Map_FTUE_D, T_SlimeBomb_DA, Brazier_DA,
  T_WindowDecoOpaque_D) is at most **0.204 pp** of masked area, and none is
  binary-alpha; the one exemption stays the storefront glass decal, which is the
  only binary 0/255 mask and loses **100 %** of its 7,611 transparent texels.
- **S6 confirm (green, after the integrator applies the cap):** the number depends
  on *which* `materials.json` is in the tree, because the regenerated producer
  binds 16 new textures. Measured on the T08 producer output:
  ```
  targets: 1564 (materials.json 1523, code 68, scenes 0, unique 1564, dangling 4)
  capped: 773 -> 797 after apply   alpha-critical: 1   within cap: 766   offenders: 0
  out-of-scope over-cap: 261 (ui 80, other 181)
  ```
  i.e. **24 newly gated targets** = the 14 code-literal ones plus 10 material
  textures the producer now binds (`T_DoorWard_Glyph_Hand`, `T_DoorWard_Lines`,
  `T_Disguise_PP_Mask_Tileable`, `T_SpeedLinesA`, `T_TrailMaskA`,
  `T_DoorWard_Lines02`, `T_MirroredHorizontalGradient`,
  `T_WeaponImpact_Mask`, `T_DropletsMasks_Packed`, `T_Swirly`). On the *pre-T08*
  data the same tool reports `targets: 1548 / offenders: 14`, so the order of
  the integrator steps matters: `make normalize` **first**, then
  `make desktop-texture-cap`, then re-check. The 14 code-literal targets alone
  are **254.9 MB decoded RGBA → 38.5 MB (‑216.4 MB)**; the 10 new material
  targets are all 2048² or 1025² and add ~50 MB decoded.
- **verdict:** FIXED. **Blocked on the integrator** for the on-disk apply and the
  audit re-stamp (teams may not write `extracted/` or re-stamp).

---

## 8. L2-03 / L2-02 — debug primitives and the silent flat-colour path (P2)

- **severity:** P2
- **S1 investigate:** the spawn filter in `_parse_sublevel_file` skipped
  `SM_WardBox` and fog/moonshape shells by name; `SM_Shape_*` primitives were not
  filtered, and `get_material_for_ue` bound `alb == null and tint != null` as a
  flat colour with no log line at all (zero `material fallback` lines in every
  recorded session).
- **S2 research:** `/Game/Test/Art/Primitives/SM_Shape_{Sphere,NarrowCapsule,Plane}`
  are editor test primitives. Their authored slot list names
  `MI_Default_White`; **163 of the 171 campaign-wide instances carry an authored
  override** (`MI_MoonshapeEmissive` moon discs, `MI_EmissiveShape` light bulbs),
  so only the 8 without an override (all `SM_Shape_Plane` in `OldManor_Geo`)
  actually spawn white. L2's "58 in the Guildhall / 171 map-wide" is a
  slot-list reading and is **NOT REPRODUCED** as spawn population — see Doc
  corrections. The Guildhall's 58 are all emissive light shapes.
- **S3 confirm (red):** census `debug_shapes: instances=171 (Guildhall=58)`;
  no-override subset **8**; flat-colour materials **85 / 2,141 binds**, of which
  the near-white class is **17 materials / 171 binds** (all `MI_Default_White`).
- **S4 fix:** `_is_debug_shape_mesh(low_path, entry)` hides only
  `…/test/art/primitives/sm_shape_*` instances that (a) carry **no** authored
  override and (b) still resolve to `MI_Default_White`; counted as
  `debug_shape_hidden`. The flat-colour path is now counted
  (`flat_colour_material_count`, capped list, in `_finalize`) and the near-white
  class is named in a `push_warning("[level_loader] material flat white: …")`.
- **S5 test:** suite 91 asserts the sphere is recognised, the overridden
  `SM_Shape_Plane` (Den backlight) and `/Engine/BasicShapes/Cube` are not, and
  that the flat-colour counter moved. A real load is recorded by
  `tests/probe_t08_level.gd`.
- **S6 confirm (green):**
  ```
  T08_LEVEL level=OldManor_Geo.tatlevel.json      debug_shape_hidden=8  flat_colour_materials=7  slot_name_fallbacks=0
  T08_LEVEL level=Guildhall_LightingNoGameplay…   debug_shape_hidden=0  flat_colour_materials=2  slot_name_fallbacks=0
  ```
  The control (11 overridden emissive shapes) is untouched, proving the filter is
  scoped to the debug class.
- **verdict:** FIXED as scoped; the **count in the finding is NOT REPRODUCED**
  (8 genuine, 163 authored emissive shapes). The *visible* white blobs in the
  capture are therefore still unattributed — see Open risks.

---

## 9. RE-C-10 / RE-C-24 — no streaming/eviction, 3.7 s / 80 MB roughness bake (P2)

- **severity:** P2
- **S1 investigate:** `_tex_cache` is a flat map-wide dict cleared only in
  `_exit_tree`; `_roughness_remap_texture` bakes a full-resolution L8 per
  `(ORM, low, high)` and keeps the source ORM alive.
- **S2 research / measurement:** committed run log
  `docs/reports/logs/w7g-bake-core.log:38`:
  `ROUGHNESS_BAKE count=71 pixels=60293120 ms=3708 bytes=80390799 hits=34`
  → 61.5 ns/px; the same log puts the 4-sublevel Guildhall scene build at
  6,815 ms, so the bake is **54 %**. Guildhall resident texture set: 629 unique
  textures ≈ 530 MB at capped sizes with mips.
- **S3 confirm:** reproduced from the committed log (no re-measurement here; the
  host is thermal-gated and the team brief forbids GPU work).
- **S4 fix:** none. Analysed options: (a) half-res bake → 4× cheaper (~0.93 s,
  ~20 MB) but **AGENTS forbids a half-res path**; (b) disk-cached L8 keyed by
  `ORM+range` → removes the 3.7 s on every load after the first, at the cost of
  a `user://` cache with its own invalidation problem (extract changes the ORM
  bytes, so the key must hash the source); (c) eviction → the texture→batch
  residency graph does not exist (materials and MultiMesh batches are shared
  across sublevels), and a map transition already frees everything through
  `_exit_tree`, so eviction buys nothing *within* a map and nothing *across*
  maps that teardown does not already do.
- **S5 test:** n/a.
- **S6 confirm:** n/a.
- **verdict:** **DEFERRED** — quantified, no safe change inside the rule set.
  Recommendation for a later wave: (b) with a SHA-256 of the ORM bytes in the
  key, measured against the committed `ROUGHNESS_BAKE` line.

---

## Doc corrections

1. **`findings/L2-materials.md` L2-03** — "58 `SM_Shape_*` with `MI_Default_White`
   (171 map-wide) spawn as flat white geometry" is a **slot-list reading, not a
   spawn census**: 163 of the 171 instances carry an authored override
   (`MI_MoonshapeEmissive` / `MI_EmissiveShape`), and only **8** (all
   `SM_Shape_Plane`, `OldManor_Geo`) spawn untextured white. Replacement
   sentence: *"Eight editor `SM_Shape_Plane` primitives in `OldManor_Geo` bind
   `MI_Default_White` with no override and spawn as flat white geometry; the
   other 163 `SM_Shape_*` instances are authored emissive light/moon shapes and
   render correctly."*
2. **`findings/C2-materials-code.md` C2-01 / `findings/RE-C-materials.md` §5** —
   `ui/tool_preview.gd` and `ui/wardrobe_ui.gd` are **not** raw-GLB call sites:
   both already read `_mesh_mats_db` and set surface overrides
   (`tool_preview.gd::_bind_materials`, `wardrobe_ui.gd::_bind_preview_materials`).
   The raw sites are `loot_item.gd`, `clue_item.gd`, `world_pickup.gd`,
   `thrown_bottle.gd`, `lockable_door.gd` (all fixed here) and the *generated*
   decoration script inside `mission_controller.gd` (its primary path already
   goes through `_get_mesh_and_shape`).
3. **`findings/C2-materials-code.md` C2-07b / the T08 brief** — "66 texture paths
   bypass the cap (`T_Blackjack_D` 4096²)" is **66 literal occurrences / 51
   distinct paths / 40 genuinely new**, of which **14 are over cap**.
   `T_Blackjack_D` and `T_Moon_D` are `materials.json` targets and were already
   capped. Replacement sentence: *"14 over-cap textures are referenced only as
   code literals outside the loader (the 6400×3600 loading screen is the largest
   at 92 MB decoded); they bypassed both the prebake and the gate."*
4. **`findings/RE-C-materials.md` RE-C-22** — "285 over-cap PNGs sit outside the
   gate" is right, but **286** in the prose elsewhere is off by one (93 UI + 192
   other = 285; 774 + 285 = 1,059 closes exactly). After the widening the
   out-of-scope inventory is **271 (ui 80, other 191)**.
5. **`findings/RE-C-materials.md` RE-C-05** — the `M_BlockerWard` wardrobe bind is
   **not** caused by a dropped albedo slot: that material's group 3 is
   `BasePattern/DistortionPattern/Wobble Noise` and it authors no albedo at all.
   The correct fix is "no ranked albedo guess for an emissive-only material", not
   a new bucket. `parse_materials.py` now implements that (17 materials / 378
   binds, `M_BlockerWard` alone 376).
6. **`findings/RE-Q-meshing.md` RE-Q-06** — reproduced as **53 meshes / 776
   instances** (report: 55 / 776). The instance count is exact; the 2-mesh delta
   is the sidecar-ordered set and does not change the verdict.
7. **`findings/RE-C-materials.md` RE-C-09 / C-2** — WorldGrid substitution for
   `SM_WardBox`/bay windows/frames is **out of T08 scope by adjudication C-2**
   and was not touched; the ward-zone box is `ward_zone.gd` + `tat_ward.gdshader`,
   not a grid material and not `SM_WardBox` (skipped since `32fe554`).
8. **Ownership note** — `tat_beam.gdshader` and `tat_emissive_cpd.gdshader` are
   listed under T08 in the team brief but under **T07-RENDER** in
   `REMEDIATION_PLAN.md` §3. No T08 finding requires changing them, so T08 left
   them untouched to avoid a wave-3/4 conflict; T07 keeps them.
9. **`AGENTS.md` texture row** — the passing value is now
   `targets 1,564 · capped 797 (after apply) · 1 alpha-critical · 0 offenders ·
   261 over-cap files outside the gate`; the old "773 capped" line is the
   pre-T08 state.

---

## Open risks

1. **The tint-space fix changes 39 % of surface binds by one gamma.** It is the
   correct transform, but the exposure/AGX/grade was tuned *against* the wrong
   value in places (RE-C-08's "compensation is global rather than per-material").
   T07-RENDER must re-check the grade against the authored reference with this
   change in, not tune the tint back. No capture was possible for T08.
2. **The ward shader's visual result is modelled, not captured.** The arithmetic
   is fixed (3.8× facet sd, alpha 0.10–0.44 at the ward box) but the confirming
   evidence is a capture at a warded door; KF28 is the reference.
3. **The visible "flat white" props in the capture are still unattributed.**
   L2-03's population was wrong (8 debug planes, all in OldManor). The new
   `material flat white` warnings and `flat_colour_materials` census are the tool
   to enumerate the real population on the next run; the 17 near-white materials
   are all `MI_Default_White` (171 binds), so the capture's white blobs are most
   likely flat-colour props from L2-02 or a lighting/AO read.
4. **Producer blast radius beyond the named families.** The data change moves 53
   albedos (1,254 binds, of which 1,252 are the two named families) and 45 render
   blocks (1,290 binds, of which 1,283 are foliage). VFX materials
   (`MI_Flash_01_Translucent`, `MI_SmokeDust_01_Add`, `MI_SmokeDisguise_Wisps_CA`,
   `MI_EyeGlint_Circle`, `MI_Laser_Light_02`, `MI_FaerieBody`) changed blend mode
   to their authored BPO value — T12-VFX should sanity-check those against its
   shaders, not revert them.
5. **FIX 4's removal of guessed albedos** (`MI_Loot_Key` lost `T_LootBag_D`,
   the fairy bubbles lost `T_InsultFairy_Teeth_D`, `MI_TrainLights*`/
   `MI_PhoneBoothLights` lost a lamp map) is correct in kind (a guess is not
   authored) but those props now read as flat emissive surfaces. If any is
   visibly wrong, the fix is an authored slot in the producer, not restoring the
   guess.
6. **`make audit` and `make texture-cap-check` are red on this branch by design**
   until the integrator regenerates (see runbook). Nothing in T08's code can turn
   them green without writing shared/private data.
7. **The 4 loot tints now all share `Flat Color {0.948, 0.753, 0.277}`**, which is
   what the authored master carries. If the loot family was meant to read
   individually coloured, the authored difference lives in a channel the port
   does not model (the HDR interaction-shine `Color`), not in the flat base.

---

## Integrator runbook (ordered, before the merged gate)

1. `make normalize` — regenerates `game/data/generated/materials.json` (+1,523
   texture refs; `mesh_materials*` are byte-identical, so slot order is
   untouched). Verify `MI_CatStatueA.tint == [0.948, 0.753, 0.277, 1.0]`.
2. `make desktop-texture-cap` + `tools/reimport_assets.sh` — caps the 24 newly
   gated targets (expect `targets: 1564`, `capped: 797`, `within cap: 766`,
   `offenders: 0`; on the un-regenerated tree it is 1,548 / 787 / 760 / 14).
3. `make audit-refresh-stamps` — `tools/parse_materials.py` and
   `tools/prebake_texture_cap.py` hashes and the `texture_refs`/`albedo entries`
   metrics moved (`1,507 → 1,523`, `1,379 → 1,376`, both floors hold).
4. Re-commit `docs/reports/logs/**` for `run_tests` (278 → 279),
   `texture_cap` (773 → 797) and the compile count (120 → 124), then
   `make gate-ratchet`.

## Files changed

| file | change |
|---|---|
| `game/src/core/level_loader.gd` | tint sRGB encode (one call site + helper), index-first slot binding + counted empty-slot rescue, `bind_prop_scene_materials` + `glb_res_to_ue_path` + `_bind_scene_overrides`, `level_loader` group, debug-shape skip + `_is_debug_shape_mesh`, flat-colour census + warning, `_finalize` keys |
| `game/src/core/tat_ward.gdshader` | facet transfer, seams, object-space hash, alpha |
| `game/src/interact/{loot_item,clue_item,world_pickup,thrown_bottle,lockable_door}.gd` | one binder call each (T10-owned call sites, listed explicitly) |
| `tools/parse_materials.py` | BPO blend/shading, group-3 buckets, long-form albedo stems, emissive-only rule, tint pick |
| `tools/prebake_texture_cap.py` | code/scene literal targets, out-of-scope inventory, reasoned allowlist |
| `game/tests/t08_material_checks.gd` (new) | shared gate checks |
| `game/tests/test_t08_materials.gd` (new) | standalone census + gate |
| `game/tests/probe_t08_red.gd` (new) | S3/S6 red proof |
| `game/tests/probe_t08_level.gd` (new) | real-load spawn-filter proof |
| `game/tests/run_tests.gd` | suite 91, suite 37 tint contract, `_t08_expected_albedo_tint` |
