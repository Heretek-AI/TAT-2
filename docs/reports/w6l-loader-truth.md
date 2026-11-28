# W6L — loader material + collision truth

**Base:** `f803c3b` (W5 integration, re-measured gate set)
**Worktree:** `/tmp/opencode/tat2-w6l-loader`
**Owner:** `game/src/core/level_loader.gd` + its standalone tests
**Date:** 2026-11-24

This wave closes the loader-material and roof-classifier findings from the
audits. Nothing outside the loader, its shader inputs (`opacity_scale` is set by
the loader, the shader is unchanged), the three standalone tests and the two
stale glass expectations in `run_tests.gd` (suite 33b) was touched. No generated
data, producers, player, mission, UI or save code changed.

Measured on `f803c3b` + this wave, serial, `XDG_DATA_HOME=/tmp/opencode/w6l-data`.
Timings are wall-clock on a host that also ran other agents' Godot processes;
the bake figure below is self-reported by the loader, not a stopwatch guess.

---

## 1. Metallic precedence — 584 dielectric materials fixed

`_apply_ue_pbr_params()` read `FlatMetallic` first, before the authored
`Metallic Map?` / `Use Metallic Map` switch. Every M_Env* metal instance carries
the master's `FlatMetallic 0.0`, so the ORM blue channel was multiplied by zero.

Now: switch on **and** an ORM bound → `metallic = 1.0` (the map is the value);
`FlatMetallic` is only the map-off fallback (and the fallback at bind time if
the ORM fails to load).

| material | before | after |
|---|---|---|
| `MI_Phonograph` | metallic 0.0, metal map ignored | **1.0**, blue channel drives |
| `MI_TrimMetalA_brass` | metallic 0.0 | **1.0** |
| `MI_Map_ThievesDen` (switch off) | 0.0 | **0.0** (control) |

DB-wide assertion in `test_w5b_materials.gd`: all **584** generated materials
with map-on + ORM resolve to 1.0, and every map-off ORM material keeps its
authored flat value.

## 2. Roughness range — never the midpoint again

UE's M_Env* masters interpolate `Roughness Low..High` along the map. Godot
multiplies `roughness` by the ORM green channel, so `(low+high)*0.5 * g`
halved every authored value (parchment 0.50·g, brass 0.575·g → mirror metal).

Now `low + g*(high-low)` is baked once per (ORM, range) into a single-channel
**L8** texture and the scalar stays 1.0. The identity range (0..1) is not baked
at all — the authored ORM *is* the value with scalar 1.0. A `Roughness` scalar
still wins; a missing ORM uses the safe high end.

| material | range | before (mean) | after (mean) |
|---|---|---|---|
| `MI_TrimMetalA_brass` | 0.15..1.0 | 0.575 · G = **0.17** | baked **0.407** (target ≈0.41) |
| `MI_PosterWanted` (paper) | 0..1.0 | 0.5 · G = **0.35** | authored map, **0.703** (target band ≈0.67) |
| `MI_Phonograph` | 0..1.0 | 0.5 · G | identity map, scalar 1.0 |

218 generated materials bake a real range; 0 keep the midpoint. Inverted but
non-negative authored ranges (e.g. `MI_TrimWickerClay_Copper` 1.0→0.1) bake as a
decreasing ramp, which is what the authored values ask for.

**Cost (measured, not guessed):** the heaviest map (Guildhall, full census)
requests **86 bakes / 73.9 M px / 3848 ms**, reported as one
`ROUGHNESS_BAKE count=… pixels=… ms=…` line per load. Iterating the entire
materials DB (140 ranges / 118.5 M px) costs 5.1–7.3 s on the loaded host.
Memory is ~98 MiB of L8 + mips for Guildhall instead of ~400 MiB for an RGBA
copy. The bake is cached per ORM+range and cleared in `_exit_tree`.

If the load cost is rejected, the sanctioned fallback is one line in
`_apply_ue_pbr_params`: set `mat.roughness = rough_high` and do not set
`ue_roughness_remap` — parchment stays exact (identity), brass drops to 0.31
instead of 0.41, and no texture is allocated.

L8 sampling was verified with a readback render (`ImageTexture` L8 →
`texture().g == luminance` on 4.7.2 Vulkan), so the bake is read correctly by
`roughness_texture_channel = GREEN`.

## 3. Two-tone emissive — tint + family ceilings, white clip removed

The generic emissive lookup never read `EmissiveTintA/B`, so the authored
50–100× `EmissiveStrength` multiplied a **white** fallback (2.2 × 50 = 110,
clamped 16). That was the white-clip source.

`_two_tone_emissive_tint()` resolves the lit end by luminance (B for the warm
glass families; A where the module authors its lit tone in A and B is black),
and `_emissive_energy_cap()` bounds each family: glass 3.0, guard lantern 1.6,
large lamps 2.5, global ceiling 4.0. `MI_LightSmGlassA_Gold` keeps its exact
special case (EmissiveTintB `(1.0, 0.6058, 0.1927)`, energy 2.2).

| material | before | after |
|---|---|---|
| `MI_LightSmGlassA_Gold` | TintB, 2.2 | **unchanged, byte-identical** |
| `MI_LightSmGlassA_Blue` | white, 16.0 | B `(0.072, 0.413, 1.0)`, **3.0** |
| `MI_LanternGuardGlass_Yellow` | white, 11.0 | A `(1.0, 0.723, 0.429)`, **1.6** |
| `MI_LightLrgABC_Glass_Orange` | white, 16.0 | A `(0.2, 0.056, 0.0)`, **2.5** |
| `MI_GlassLight_Gold` | white, 8.8 | A `(1.0, 0.579, 0.229)`, **3.0** |

DB-wide test: after simulating the loader's emissive binding for all **1629**
generated materials, none exceeds energy 4.0 and none emits pure white above
4.0.

## 4. Den pane — a mask is the opacity

`MI_GlassPanels_oldmanor` (ThievesDen glass) authors `Opacity 2.0`;
`MI_GlassPanels` authors 1.5. With the authored `_O` mask at 0.51 those
multipliers pushed raw alpha past 1.0, saturating the pane centre.

Mask-based glass now caps `opacity_scale` at 1.0 (`_build_glass_material`).
At mask 0.51 the raw alpha is 0.510 and the centre transmission is
`0.51 · 0.42 = 0.214` — the thin-glass floor, with the fresnel rim intact
(`min(raw, 0.90)` still applies). Mask-less glass keeps its authored scalar
(verified: 2.0 stays 2.0).

## 5. Poster backlight — MSM_Subsurface is not foliage

The foliage gate treated any `MSM_Subsurface` as foliage. The masked
double-sided master is shared by WANTED posters, decal posters, coins, scrolls,
candles, slime bubbles and the anti-stealth device, so every flat card got
`backlight_enabled` and was lit from behind.

`_is_authored_foliage()` now requires `MSM_TwoSidedFoliage` or a
leaf/bark/foliage token in the material path or bound albedo (bark keeps its own
no-backlight rule). `MI_PosterWanted`, `MI_PosterA`, `MI_DecalPosters` and
`MI_Coins` are off; `MI_BirchLeaves` and `MI_ISMPineNeedles` stay on;
`MI_BirchBark` stays off. The `DiffuseColorMask?` guard is unchanged, and its
W5B comment now records that the tint path was inert and is **not** the
cyan-poster cause.

## 6. Roof classifier — measured geometry, not the `end` token

`roof_collision_kind()` is now `roof_collision_kind(path[, mesh])` and decides
by *measured top coverage*: upward-facing area within 10 cm of the AABB top,
over the AABB footprint. Decks measure 1.00, fascia 1.90, pitched shells
0.000–0.16; `ROOF_FLAT_TOP_FRAC = 0.5`. Props/trim (`chimney`, `vent`, `pipe`,
`gutter`, `rail`, `watertower`, `tank`, roof-detail windows, spikes) keep the
exact box by token, so a chimney is never hulled.

The `end` token is gone, which fixes the **92 pitched EndA/EndB instances**:

| family | instances | height | top coverage | before | after |
|---|---|---|---|---|---|
| `SM_RoofUrban_Ext_EndA/EndB_2x4x4` (+Mirror) | 68 | 4.316 m | 0.012–0.014 | BoxShape3D | **hull** (42–55 pts) |
| `SM_RoofUrbanB_Ext_EndA/EndB_2x2x8` (+Mirror) | 24 | 8.474 m | 0.0000 | BoxShape3D | **hull** (31–36 pts) |

Census shifts (PeripheryA, 733 instances / 46 meshes):

* convex **426 / 19** (was 334 / 13)
* box **307 / 27** (was 399 / 33)

The ridge bypass is asserted directly: `SM_RoofUrban_Ext_EndB_2x4x4_Mirror` at
`(115.0, 57.5, 26.5)` (beside the flipped `Mid_4x4`) is a hull whose top-band
coverage is 0.001, not a box plateau, and both instances are uniform-scaled so
the hull equals the visual surface.

Additional censuses:

* **POI 3rd floor:** 29 instances / 4 meshes → **28 convex / 1 deck** (box).
* **Old Manor tower roofs:** 6 meshes, all outside `/roofs/` (`kind=none`),
  all `ConcavePolygonShape3D` (19–118 m assemblies), none an occluder.
* **Non-uniform scale:** all 39 non-uniformly scaled roof instances are the
  `GB_RoofFloor_6x6` deck (up to 3.0 × 1.0 × 2.4); the mesh-local `BoxShape3D`
  is unchanged and the node scale applies, so no pitched hull is distorted.
* Hull vs visual: every End hull bbox reproduces the mesh AABB top and z span
  (≤0.01 m), and its eave band sits 3.38 m / 7.2–7.9 m below the old box top
  (mirror variants flip which end is the eave, so the deeper band is used).

## 7. Occluders — stairs removed, 768 still filled

`stair` was an include token, and a flight's AABB is a long mostly-empty ramp;
with roofs excluded in W5B, stair AABBs were next in line for the freed slots.
The token is removed (not fill-ratio-gated: the audit allowed either, and the
name removal is deterministic and cheap).

* no `/roofs/` mesh qualifies (0/46) and no stair mesh qualifies (0/32).
* the exterior 4x6 wall still qualifies (control).
* the authored Guildhall sublevel walk yields **3587** qualifying instances →
  capped at exactly **768**; the first-768 selection sequence is identical
  across two builds, and the predicate re-evaluates identically on a sample.
* the real full-map load reports `occluders=768` (`probe_perf_census`).

This is still a cap: the selected set depends on load order, which is stable
for the authored sublevel list. If sublevels are reordered, the *set* changes
(the count stays 768).

## 8. Searchlight

`VFX_SkySearchLight_Mesh` bound the engine `WorldGridMaterial`, so the authored
sky searchlight cone was the grey checkerboard. The additive light-shaft path
now also matches `skysearchlight`, and `searchlight` **only** on `vfx_`/`/vfx/`
assets, so the fixtures (`SM_Searchlight`, `…Base`, `…LensSmall`,
`…SwivelSmall`) keep their authored MI_Searchlight materials. WorldGrid stays
intentional elsewhere (`SM_Sphere_100cm` control).

---

## Gates

| gate | result |
|---|---|
| compile | **102 checked, 0 broken** |
| `run_tests.gd` | **SUMMARY: fails=0** (261 PASS) |
| `test_m2_player.gd` | **M2_SUMMARY: fails=0** (11 PASS) |
| `test_w5b_materials.gd` | **fails=0** (71 assertions) |
| `test_roof_collision.gd` | **fails=0** (51 assertions) |
| `test_w6l_searchlight.gd` | **fails=0** (16 assertions) |
| `probe_perf_census.gd` | `elapsed_ms=12333`, `occluders=768`, `ROUGHNESS_BAKE count=86 pixels=73924608 ms=3848` |
| E2E | **not run** (out of scope for this focused wave) |
| `make audit` | **content OK, baseline FAIL** — see note |
| `make texture-cap-check` | OK — 773 capped, 1 alpha-critical kept, 0 offenders |

`make audit` in this worktree fails **only** on producer/tool baselines that
live in the shared checkout this worktree symlinks (`game/data` →
`<repo>/game/data`): `gen:gameplay` differs from
`tools/audit_baseline.json` for `parse_tables.py`, `parse_gameplay.py` and
`parse_unlocks.py` (sibling W6G regenerated them in the main checkout), and the
`vgmstream` CLI is absent on this host. Manifest coverage (12703 payload,
99.6 % disk-backed, 0 unexpected), exact-case parity, all 13 content groups,
`scene_variants` 222/222, `niagara` 3695/3695 and the texture cap (773 capped,
1 alpha-critical, 0 offenders) are **OK**. This wave changes no producer and no
generated data, so the baselines cannot be affected by it.

`run_tests.gd` suite 33b changed from `opacity_scale == 1.5 / 2.0` to
`== 1.0` for `MI_GlassPanels` / `…_oldmanor`. The old expectation encoded the
saturation this wave removes; the assertion was wrong, not weakened (AGENTS §3).

## Risks / open items

1. **Roughness bake cost:** 3.85 s per Guildhall load, 98 MiB L8. The fallback
   (roughness = high) is documented above if the user rejects it. The bake is
   re-done on every load because the cache is per-loader (matches the existing
   texture/material cache lifecycle; a process-global cache would need RID
   accounting to keep `probe_leak` clean).
2. **Parchment target:** the audit's ≈0.67 sits inside the measured paper band
   (0.63–0.70); the test pins the two extremes it can name exactly (brass 0.407,
   poster paper 0.703) and the formula, not an unknown "parchment" asset.
3. **Inverted authored roughness ranges** are honoured as decreasing ramps
   rather than flattened. They were previously averaged (wrong); if any look
   wrong in play they should be fixed in the authored data, not the loader.
4. **Glass cap scope:** every mask-based glass material now caps at 1.0. This is
   intentional (a mask is the opacity) but it is a broader look change than the
   Den pane alone; capture review on storefront/display glass is still owed.
5. **Emissive caps** are family ceilings, not per-material grades; the
   `Emissive On` (no `?`) master switch is still accepted as authored-on.
6. **Occluder selection** remains first-768-in-load-order; count is stable, set
   is content-order dependent.
7. **Not measured:** a Vulkan capture comparison of the Den pane / lamps /
   roofs against UE (this wave is static-data + headless truth only). The L8
   sampling check used a readback render, not a full scene capture.
