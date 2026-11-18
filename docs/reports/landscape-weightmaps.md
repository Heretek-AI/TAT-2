# Guildhall landscape weightmaps: second texture, fifth colour slot & visibility mask (2026-11-17)

Guildhall's landscape material could only ever sample `WeightmapTextures[0]`. The parser emitted a single `weightmap` path; the loader skipped every layer whose `tex` was not `0`, capped colour slots at four, and spent one of those slots on `LandscapeVisibilityLayerInfo`; the shader bound one weightmap and four colour slots. 8 of Guildhall's 18 landscape components allocate layers to a second weightmap, and `LandscapeComponent_11` alone carries seven allocations: six blended layers (five colour layers plus the `Puddle` overlay) and the `Visibility` mask. The fix emits a `weightmaps` array for every component, binds `weightmap_1`, expands to five colour slots with per-slot `layer_tex_idx_*`, gives visibility/puddle/groundwet their own texture indices and channels, and makes `weight_at()` return zero for unknown indices. 210 of 210 landscape components across 103 level files carry the array; the three new tests pass in headless and under a real Vulkan renderer.

## Root cause (R1 evidence)

### 1. The parser emitted only `WeightmapTextures[0]`

`tools/parse_tables.py` read the cooked `WeightmapTextures` array but kept only its first element:

```python
wtextures = props.get("WeightmapTextures") or []
weightmap = ""
if wtextures:
    wname = (
        (wtextures[0].get("ObjectName") or "")
        .split(".")[-1]
        .rstrip("'")
    )
    if wname:
        weightmap = f"res://assets/ue/Raw/Maps/{h_rel}/{wname}.png"
```

Every `WeightmapLayerAllocation` still carried its authored `WeightmapTextureIndex`, but the runtime had no path for index `1`. Across the generated levels:

- **103 level files, 210 landscape components.** All 210 carry at least one weightmap.
- **195 components have one weightmap, 15 have two.** No component has more than two; 225 weightmap entries in total and none are empty.
- **0 layers have `tex >= 2`.** The current data only exercises indices `0` and `1`.
- In Guildhall, **8 of 18 components** have two weightmaps: generated indexes `0, 2, 5, 6, 7, 8, 9, 10`.

### 2. The loader skipped `tex != 0`, capped colour slots at four, and spent one on visibility

The old `_landscape_weighted_material()` had four coupled limits:

```gdscript
var slot: int = 0
for l_var: Variant in (lc.get("layers", []) as Array):
    if slot >= 4:
        break
    if not (l_var is Dictionary):
        continue
    var l: Dictionary = l_var
    var lname: String = str(l.get("layer", ""))
    var channel: int = int(l.get("channel", 0))
    var tex_idx: int = int(l.get("tex", 0))
    if lname == "Puddle":
        if tex_idx == 0:
            mat.set_shader_parameter("puddle_channel", channel)
            ...
        continue
    if lname == "GroundWet":
        if tex_idx == 0:
            mat.set_shader_parameter("groundwet_channel", channel)
        continue
    if tex_idx != 0:
        continue
    var is_visibility: bool = lname.to_lower().contains("visibility")
    if is_visibility:
        mat.set_shader_parameter("layer_channel_%d" % slot, channel)
        mat.set_shader_parameter("layer_visibility_%d" % slot, 1)
        slot += 1
        continue
    ...
    mat.set_shader_parameter("layer_tex_%d" % slot, tex)
    mat.set_shader_parameter("layer_channel_%d" % slot, channel)
    slot += 1
```

For `LandscapeComponent_11` (generated index `6`, confirmed against the extracted `LandscapeComponent_11` object: same `Weightmap_7.png` / `Weightmap_90.png` paths and the same seven allocations):

| Allocation | Layer | Weightmap index | Channel | Old loader | New loader |
|---|---|---|---:|---|---|
| colour 0 | `GroundA` | 0 | 0 | bound | bound |
| colour 1 | `GrassA` | 0 | 1 | bound | bound |
| colour 2 | `CobbleA` | 0 | 2 | bound | bound |
| mask | `LandscapeVisibilityLayerInfo` | 0 | 3 | consumed colour slot 3 | `visibility_tex_idx=0`, `visibility_channel=3` |
| blend | `Puddle` | 1 | 0 | skipped (four-slot cap; also `tex != 0`) | `puddle_tex_idx=1`, `puddle_channel=0` |
| colour 3 | `CobbleB` | 1 | 1 | skipped (cap; `tex != 0`) | `layer_tex_idx_3=1`, `layer_channel_3=1` |
| colour 4 | `RockTileA` | 1 | 2 | skipped (cap; `tex != 0`) | `layer_tex_idx_4=1`, `layer_channel_4=2` |

The old loader rendered only `GroundA`, `GrassA` and `CobbleA` for this component. The visibility mask occupied slot 3, and the three layers allocated to the second weightmap were dropped. The four-slot cap also meant that a single-weightmap component with four colour layers plus a visibility layer would have lost one colour layer, because the visibility layer consumed one of the four slots. The index-1 test is the direct evidence that the visibility layer no longer spends a colour slot: `CobbleA` moves from slot 3 to slot 2 (`layer_channel_2 == 3`) and slots 3/4 stay at `-1`.

### 3. The shader bound one weightmap and four slots

`game/src/core/tat_landscape.gdshader` had one weightmap sampler and four colour slots:

```glsl
uniform sampler2D weightmap : filter_linear, repeat_disable;
uniform sampler2D layer_tex_0 : source_color, repeat_enable;
uniform sampler2D layer_tex_1 : source_color, repeat_enable;
uniform sampler2D layer_tex_2 : source_color, repeat_enable;
uniform sampler2D layer_tex_3 : source_color, repeat_enable;
uniform int layer_channel_0 = -1;
...
uniform int layer_visibility_0 = 0;
...
vec4 w = texture(weightmap, UV);
```

`layer_visibility_*` overloaded the colour slots, `puddle_channel` and `groundwet_channel` were always read from weightmap 0, and there was no `weightmap_1` to sample. A layer allocated to index `1` had no representation in the shader at all.

## Fix (R2)

### 1. Parser: emit `weightmaps` for every component

`tools/parse_tables.py` now builds an array and keeps `weightmap` as its first element for existing consumers:

```python
weightmaps = []
for wt in wtextures:
    wname = ""
    if isinstance(wt, dict):
        wname = (
            (wt.get("ObjectName") or "")
            .split(".")[-1]
            .rstrip("'")
        )
    weightmaps.append(
        f"res://assets/ue/Raw/Maps/{h_rel}/{wname}.png"
        if wname
        else ""
    )
weightmap = weightmaps[0] if weightmaps else ""
```

A non-dict entry appends `""` rather than shifting the array, so `weightmaps[i]` stays aligned with an authored `WeightmapTextureIndex == i`. Verified for all 210 components: `weightmap == weightmaps[0]` in every case (0 mismatches); the current data has 225 entries and 0 empty entries, so the `""` path is defensive rather than exercised.

### 2. Loader: bind two weightmaps, five colour slots, dedicated visibility/puddle/groundwet indices

`game/src/core/level_loader.gd` now reads the array, falls back to the old `weightmap` key for compatibility, and binds a second texture only when its path exists:

```gdscript
var wm_paths: Array = []
var wm_raw: Variant = lc.get("weightmaps", [])
if wm_raw is Array:
    wm_paths = wm_raw as Array
var wm_path: String = str(wm_paths[0]) if wm_paths.size() > 0 else ""
if wm_path == "":
    wm_path = str(lc.get("weightmap", ""))
...
var wm1: Texture2D = null
if wm_paths.size() > 1:
    var wm1_path: String = str(wm_paths[1])
    if wm1_path != "" and (FileAccess.file_exists(wm1_path) or ResourceLoader.exists(wm1_path)):
        wm1 = _load_tex(wm1_path)
var bound_count: int = 2 if wm1 != null else 1
var source: String = str(lc.get("source", ""))
if wm_paths.size() > 2:
    push_warning("Landscape %s: %d weightmaps extracted but only %d bound; extra weightmaps are not sampled" % [source, wm_paths.size(), bound_count])
```

Each layer's authored texture index is now bound per slot, and a layer is skipped only when its index is unbound. The warning names the component, layer name, allocation index and weightmap index:

```gdscript
var tex_idx: int = int(l.get("tex", 0))
if tex_idx < 0 or tex_idx >= bound_count:
    push_warning("Landscape %s: layer '%s' (index %d) skipped, weightmap index %d is unbound (%d bound)" % [source, lname, layer_i, tex_idx, bound_count])
    continue
```

The visibility layer no longer increments the colour slot; it writes `visibility_tex_idx` / `visibility_channel` and continues. `Puddle` writes `puddle_tex_idx` / `puddle_channel`; `GroundWet` writes `groundwet_tex_idx` / `groundwet_channel`; colour layers write `layer_tex_N`, `layer_channel_N` and `layer_tex_idx_N` for `N` in `0..4`.

### 3. Shader: `weight_at()`, five colour slots, gated visibility

`weight_at()` is the single place that decides which weightmap a layer reads:

```glsl
vec4 weight_at(int tex_idx, vec2 uv) {
    if (tex_idx == 0) {
        return texture(weightmap, uv);
    }
    if (tex_idx == 1) {
        return texture(weightmap_1, uv);
    }
    return vec4(0.0);
}
```

Unknown indices return zero weight instead of silently reading weightmap 0. The shader now declares `weightmap_1`, `layer_tex_0..4`, `layer_channel_0..4`, `layer_tex_idx_0..4`, `visibility_tex_idx`, `visibility_channel`, `puddle_tex_idx`, `groundwet_tex_idx`. The visibility mask is sampled only when holes are actually discarded and only when both index and channel are configured:

```glsl
float vis = 1.0;
if (discard_holes > 0.5 && visibility_tex_idx >= 0 && visibility_channel >= 0) {
    vis = channel_value(weight_at(visibility_tex_idx, UV), visibility_channel);
}
```

This avoids the failure mode where a half-configured mask (`channel_value()` returns `0.0`) would erase the whole landscape. Puddle and groundwet reads use `weight_at(puddle_tex_idx, UV)` and `weight_at(groundwet_tex_idx, UV)`.

## Verified counts & measurements

### Data counts

| Scope | Value |
|---|---:|
| Level files scanned | 103 |
| Landscape components | 210 |
| Components with `weightmaps` | 210 / 210 |
| Components with one weightmap | 195 |
| Components with two weightmaps | 15 |
| Components with more than two weightmaps | 0 |
| Weightmap entries | 225 |
| Empty weightmap entries | 0 |
| Layers with `tex >= 2` | 0 |
| Guildhall landscape components | 18 |
| Guildhall components with two weightmaps | 8 (`0, 2, 5, 6, 7, 8, 9, 10`) |

Colour-layer counts across the 210 components (excluding `Puddle`, `GroundWet` and visibility): `1` layer × 107, `2` × 80, `3` × 17, `4` × 4, `5` × 2. No component exceeds five colour layers.

### Test assertions (block 24)

The three new assertions in `game/tests/run_tests.gd` pass:

```text
PASS: Guildhall landscape second weightmap slot 4 (RockTileA tex_idx=1, channel=2, CobbleB tex_idx=1, channel=1, puddle tex_idx=1, puddle channel=0, weightmap_1=res://assets/ue/Raw/Maps/Guildhall/Guildhall_Landscape/Weightmap_90.png)
PASS: Guildhall landscape visibility on second weightmap (visibility tex_idx=1, channel=0, puddle tex_idx=0, puddle channel=3)
PASS: single-weightmap landscape leaves weightmap_1 unbound (layer_tex_idx=00000, channel_2=3, channel_3=-1, channel_4=-1)
```

What they pin down:

- **Index 6 (`LandscapeComponent_11`):** `layer_tex_idx_3 == 1`, `layer_channel_3 == 1`, slot 4 `RockTileA` has `tex_idx == 1` / `channel == 2`, `puddle_tex_idx == 1`, and the bound `weightmap_1` resource path equals the component's authored `weightmaps[1]` (`Weightmap_90.png`).
- **Index 10:** `visibility_tex_idx == 1`, `visibility_channel == 0`, `puddle_tex_idx == 0`, `puddle_channel == 3`.
- **Index 1 (single weightmap):** `layer_channel_2 == 3` (CobbleA is genuinely bound), `layer_channel_3 == -1`, `layer_channel_4 == -1`; all five `layer_tex_idx_*` values are `0` and `weightmap_1` stays unbound.

### Gates

`make test` (headless):

```text
SUMMARY: fails=0
WARNING: 6 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
ERROR: 6 RID allocations of type 'N17RendererSceneCull8InstanceE' were leaked at exit.
```

`grep -c "SCRIPT ERROR"` on that log is `0`. The `ObjectDB` / `RID` lines are pre-existing exit-time leak reports (the same lines are in the 12:53 `build/qa/make_test.log`), not script errors; they are recorded here rather than hidden.

Real-renderer run (`--rendering-driver vulkan`, Forward+, RTX 4070):

```text
Godot Engine v4.7.2.stable.flathub.ed1daf0bf - https://godotengine.org
Vulkan 1.4.357 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 4070 Laptop GPU
...
SUMMARY: fails=0
```

`grep -c "SHADER ERROR"` = `0`; `grep -c "SCRIPT ERROR"` = `0`; exit status `0`. Headless uses the dummy renderer, so this Vulkan run is the only real proof the modified GLSL compiles. The same three landscape assertions pass in it.

`make audit`:

```text
Manifest TAT entries: 12704
Resolved in CUE4Parse: 12630 (99.4%)
Files written to extracted: 28157
```

Full logs: `build/qa/make_test_landscape.log`, `build/qa/make_test_vulkan_landscape.log`, `build/qa/make_audit_landscape.log`.

## Runtime & visual QA

### Capture setup

Both captures used the isolated-display procedure: `Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp -ac`, `debug_autostart_contract=4`, `env -u WAYLAND_DISPLAY -u XAUTHORITY DISPLAY=:99 flatpak run org.godotengine.Godot --path game`, a poll for `TAT-2 Loaded guildhall` (up to 150 s) plus 10 s settle, then `DISPLAY=:99 import -window root`. `game/project.godot` was restored from the backup; `git diff --stat game/project.godot` is empty and the file matches `HEAD` exactly. The reference images were not overwritten.

Run log (both viewpoints; full logs in `build/qa/run_ls_safe.log` and `build/qa/run_ls_sky.log`):

```text
Godot Engine v4.7.2.stable.flathub.ed1daf0bf - https://godotengine.org
Vulkan 1.4.357 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 4070 Laptop GPU

TAT-2 QA autostart contract=4 map=guildhall
TAT-2 environment: bg=2 ambient_src=2 ambient_energy=1.0 ambient_color=(0.8745, 0.9137, 1.0, 1.0) sky=true fog=true fog_density=0.0006000000285
TAT-2 Loaded guildhall: meshes=63210 lights=96
```

Zero `SCRIPT ERROR`, zero `SHADER ERROR`, and no landscape warnings in either capture log.

### Screenshots

| Screenshot | Viewpoint | Compared against |
|---|---|---|
| `build/qa/landscape_after_courtyard.png` | Balcony / overlook; courtyard, street and roof surfaces visible | `build/qa/lighting_after_sky.png` |
| `build/qa/landscape_after_safe.png` | Guildhall safe-room spawn | `build/qa/lighting_after_safe.png` |

Both are `1600x1000` full-screen captures; the game viewport is `1280x720+160+140`.

### Measured pixel difference

ImageMagick RMSE is reported in 16-bit quantum units with the normalized `0–1` value in parentheses. Mean gray is `0–255`.

Whole-frame and band-level comparison, before → after vs the same-code run-to-run noise floor (two captures of the unchanged build):

| Pair | Crop | Before → after RMSE | Same-code run 1 → run 2 RMSE |
|---|---|---:|---:|
| Courtyard | full frame `1600x1000` | `3890.06` (`0.0593585`) | `5233.61` (`0.0798598`) |
| Courtyard | viewport `1280x720+160+140` | `5125.61` (`0.0782117`) | `6895.89` (`0.105225`) |
| Courtyard | ground band `1080x210+180+650` | `6547.59` (`0.0999097`) | `8294.92` (`0.126572`) |
| Safe | full frame `1600x1000` | `235.768` (`0.00359759`) | `2.37232` (`3.61994e-05`) |
| Safe | viewport `1280x720+160+140` | `310.651` (`0.00474024`) | `3.12581` (`4.76968e-05`) |
| Safe | floor band `760x110+180+730` | `7.23929` (`0.000110464`) | `3.44251` (`5.25294e-05`) |

Per-crop means and RMSE:

| Crop | Geometry | Mean gray before | Mean gray after | Mean delta | RMSE |
|---|---|---:|---:|---:|---:|
| Courtyard viewport | `1280x720+160+140` | 63.28 | 62.78 | −0.79% | `5125.61` (`0.0782117`) |
| Courtyard ground band | `1080x210+180+650` | 76.39 | 76.30 | −0.12% | `6547.59` (`0.0999097`) |
| Courtyard centre ground | `420x150+520+680` | 83.44 | 83.78 | +0.41% | `4896.64` (`0.074718`) |
| Courtyard street left | `220x130+160+600` | 89.01 | 87.83 | −1.33% | `4481.71` (`0.0683865`) |
| Courtyard roof (control) | `330x110+300+405` | 82.28 | 82.02 | −0.31% | `3108.39` (`0.047431`) |
| Courtyard facade (control) | `300x170+300+515` | 86.30 | 86.39 | +0.10% | `4792.29` (`0.0731257`) |
| Courtyard sky (control) | `600x200+420+150` | 7.02 | 7.01 | −0.19% | `1748.8` (`0.026685`) |
| Safe viewport | `1280x720+160+140` | 84.35 | 84.35 | +0.00% | `310.651` (`0.00474024`) |
| Safe floor band | `760x110+180+730` | 93.19 | 93.19 | +0.00% | `7.23929` (`0.000110464`) |
| Safe wall (control) | `600x280+600+200` | 89.26 | 89.26 | +0.00% | `6.56623` (`0.000100194`) |
| Safe crate (control) | `360x190+300+560` | 63.33 | 63.33 | −0.00% | `7.59051` (`0.000115824`) |
| Safe bed (control) | `390x210+1010+500` | 77.38 | 77.38 | −0.00% | `5.0535` (`7.71115e-05`) |

Same-code noise floor on flat patches of the courtyard pair:

| Patch | Geometry | Before → after RMSE | Same-code run 1 → run 2 RMSE | Before → after mean delta |
|---|---|---:|---:|---:|
| Grass | `60x30+690+665` | `8921.98` (`0.136141`) | `10342.5` (`0.157816`) | +3.08% |
| Dirt left | `60x40+550+720` | `2066.99` (`0.0315403`) | `2530.82` (`0.0386178`) | −1.28% |
| Dirt right | `50x30+820+750` | `13616` (`0.207767`) | `15226.1` (`0.232336`) | +1.97% |
| Snow slab | `60x30+810+720` | `7760.48` (`0.118417`) | `9851.42` (`0.150323`) | −1.30% |
| Street | `60x40+200+650` | `3290.06` (`0.0502031`) | `4790.09` (`0.0730921`) | −1.37% |
| Roof (control) | `80x40+400+440` | `2114.32` (`0.0322624`) | `2561.86` (`0.0390914`) | +0.10% |
| Facade (control) | `60x60+380+550` | `4890.61` (`0.074626`) | `7338.23` (`0.111974`) | +3.29% |
| Sky (control) | `100x80+600+200` | `434.243` (`0.00662613`) | `284.94` (`0.0043479`) | +2.36% |

### Honest reading of the evidence

- **Safe room:** the surfaces are effectively pixel-identical. The floor band is `7.24` RMSE (`0.011%`), and the wall/crate/bed controls are `5.05–7.59` RMSE (`0.008–0.012%`). The only visible difference in the pair is the HUD timer text (`119:36` vs `119:43`), which accounts for the larger whole-viewport figure (`310.65`, `0.47%`).
- **Courtyard:** the before → after difference is **smaller than the same-code run-to-run difference** at full frame (`3890.06` vs `5233.61`), viewport (`5125.61` vs `6895.89`) and ground band (`6547.59` vs `8294.92`). The pair also differs in the HUD timer text (`118:27` vs `119:29`), which the ground-band crop excludes. In the flat-patch table, seven of eight patches have a lower before → after RMSE than the same-code noise floor; the eighth is the sky patch, where both values are negligible (`0.66%` vs `0.43%`). A subimage search on a `200x150` facade crop matched at `399,450` against the expected `400,450`, consistent with a ~1 px camera/TAA jitter between runs.
- **Conclusion:** the second weightmap is bound and the shader compiles, but at these two viewpoints the rendered landscape surfaces are **visually indistinguishable** from the unchanged build. This is a valid negative visual result, not evidence that the binding failed. The result is limited to these two viewpoints: this wave did not isolate which of the eight affected components are in frame, and did not capture a close-up of one.

## Caveats & follow-ups (not fixed)

### `OldManor_P` and `BeautifulCorner_Startscreen_P` still have no extracted landscape PNGs

> **Superseded on 2026-11-18** — for Startscreen by `8f07b7d` (20 PNGs) and for `OldManor_P` by `24abf18` (155 PNGs; suite 38) — see `## OldManor_P extraction (2026-11-18)` below. The text that follows is the pre-extraction record.

`tools/tat-extract/Exporter.cs:166` only exports `.umap` textures whose package path contains `"Landscape"`:

```csharp
ForEach(Packages(p => (p.EndsWith(".uasset") && (...)) || (p.EndsWith(".umap") && p.Contains("Landscape"))), "textures", f =>
```

- `OldManor_P`: **128 components**, **263 referenced PNG paths missing** (128 heightmaps + 135 weightmaps; 7 components have two weightmaps).
- `BeautifulCorner_Startscreen_P` (the brief's `BeautiCorner_Startscreen_P`): **64 components**, **128 referenced PNG paths missing** (64 heightmaps + 64 weightmaps).

Because the heightmaps are missing as well, `_build_one_landscape()` returns at its `if not FileAccess.file_exists(hpath) and not ResourceLoader.exists(hpath): return` guard, so these 128 + 64 components are not built at all. That is unchanged by this wave. The single-surface `_landscape_material()` fallback remains the behavior for a component whose heightmap exists but whose weightmap does not, exactly as before. This is counted as a gap, not fixed in this wave.

### The weightmap cap is two; UE supports up to four

The loader binds `weightmap` and `weightmap_1`, and warns when `weightmaps.size() > 2`. The current data never reaches that path: the maximum is two weightmaps and no layer uses `tex >= 2`. A future map with three or four weightmaps would now warn rather than silently dropping the extra layers, but those layers would still not render.

### The colour-slot cap is five, and a sixth would still be dropped silently

No current component exceeds five colour layers (distribution `107 / 80 / 17 / 4 / 2` for `1 / 2 / 3 / 4 / 5`). The loader's `if slot >= 5: continue` guard has no warning, so a hypothetical sixth colour layer would be dropped without the component/layer warning that unbound weightmap indices now get.

### The negative visual result is limited to these two viewpoints

The comparison is valid for the requested balcony/overlook and safe-room framing. It does not prove the second weightmap is invisible in all views, and it does not isolate a close-up of an affected component. A future capture that teleports to `LandscapeComponent_11` and fills the frame with its `CobbleB` / `RockTileA` surfaces would be the direct visual proof.

## Reproduce

```bash
# Data counts (read-only)
python3 build/qa/verify_landscape_counts.py
python3 build/qa/verify_empty_weightmaps.py
python3 build/qa/verify_colour_counts.py
python3 build/qa/verify_caveats3.py

# Gates
make test                          # SUMMARY: fails=0, 0 SCRIPT ERROR
make audit                         # 12630 / 12704 (99.4%)

# Real-renderer shader proof (Xvfb :99, Vulkan/Forward+)
bash build/qa/run_vulkan_tests.sh  # fails=0, 0 SHADER ERROR

# Captures (temporary edits to game/project.godot, restored on exit)
bash build/qa/capture_landscape.sh safe   # -> build/qa/landscape_after_safe.png
bash build/qa/capture_landscape.sh sky    # -> build/qa/landscape_after_courtyard.png

# Measurements (same crops, before vs after)
bash build/qa/pixel_stats_landscape.sh
bash build/qa/pixel_stats_landscape_frames.sh
bash build/qa/pixel_stats_landscape_noisefloor.sh
```

The capture helper writes `build/qa/project.godot.bak`, appends the QA autostart contract, and restores the file in its `EXIT` trap. The `build/qa/*.py` and `build/qa/*.sh` helpers are temporary QA artifacts in the gitignored build tree. The reference images `lighting_after_sky.png` and `lighting_after_safe.png` are left untouched.

## OldManor_P extraction (2026-11-18)

The `OldManor_P` / `BeautifulCorner_Startscreen_P` gap in "Caveats & follow-ups" above is now fully resolved: Startscreen by `8f07b7d` (20 PNGs = 1 heightmap + 19 weightmaps; all 64 component references resolve) and OldManor by `24abf18` (155 PNGs = 101 heightmaps + 54 weightmaps), which adds the exact `OldManor_P` basename to the `.umap` textures predicate (`tools/tat-extract/Exporter.cs`).

- **Predicate change**: exact `OldManor_P` basename match in the `.umap` textures predicate (Startscreen was already extracted; no widening to all `.uasset` textures).
- **Counts**: `155` PNGs written (`101` heightmaps + `54` weightmaps; `135` weightmap references, `7` components with two weightmaps).
- **Tests**: suite `38` asserts `128` components / `101` / `54` / `0` missing and a real `_build_one_landscape()` build.
- **Commit**: `24abf18 feat(extract): export OldManor_P landscape heightmaps and weightmaps`.
- **Live evidence**: Old Manor landscape builds (one component exercised by suite 38; all 128 heightmap paths present); `build/qa/vf_old_manor.png` renders cleanly. Terrain walk/collision was not verified.
- **Remaining limit**: landscape splines/grass data remains unparsed at runtime. Full wave report: `docs/reports/visual-polish.md`.
