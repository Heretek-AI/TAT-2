# Materials real-UE-params implementation

Stage: use REAL UE material parameters (no invented numbers).
Date: 2026-11-16 (UTC).

## Deliverables

1. `tools/parse_materials.py` — now emits per resolved material:
   - `params`: flattened scalar dict (inherited through `Parent` when the child
     lacks the key; child wins),
   - `vectors`: dict name -> `[r, g, b, a]`,
   - `switches`: dict name -> bool (from `StaticParametersRuntime`),
   - `render`: `blend_mode`, `two_sided`, `shading_model`, `opacity_mask_clip`
     (from material level or inherited parent; `BasePropertyOverrides` /
     `OpacityMaskClipValue` / numeric `bOpacityMaskClipValue`),
   - `phys_material`: name from `PhysMaterial` (`ObjectPath` basename,
     `ObjectName` fallback),
   - existing `texs`/`tint` keys and inheritance semantics unchanged.
   - Filter: entries kept only if they have a texture, tint, param, vector,
     switch, render flag, or phys material.
   - UE->Godot mapping documented in the script docstring.
2. `game/src/core/level_loader.gd` — `get_material_for_ue()` consumes the new
   data via `_apply_ue_pbr_params` / `_apply_ue_render_flags` (base, before
   art overrides) and `_apply_ue_emissive` (merged after the emissive-texture
   bind). Glass/wallpaper/wood/brick overrides unchanged and still win.
3. `game/data/generated/materials.json` — regenerated (gitignored artifact).

## Verification (temp script, deleted afterwards)

- `python3 tools/parse_materials.py` -> `Resolved 1552 materials (1217 with real
  params)` (was 1272 texture/tint-only). With switches: 787. With render:
  1484. With phys_material: 505.
- Sample entry `.../MI_ModularFurnitureDarkBrown`: params `Gradient Min 9.0`,
  `Gradient Max 11.0`, `Noise Power 2.4175`, `Roughness Low 1.0`,
  `RefractionDepthBias 0.0`; vectors `FlatDiffuse [0.1198, 0.1099, 0.0973,
  1.0]`; switches `Enable Rain Effect ? false`; render `opacity_mask_clip
  0.3333`; `phys_material WoodObject`.
- Temporary `game/tests/_tmp_mat_check.gd` (SceneTree, 17 asserts, file
  deleted after run):
  `flatpak run org.godotengine.Godot --headless --path game --script
  res://tests/_tmp_mat_check.gd` -> exit 0, zero SCRIPT ERROR, all PASS:
  White roughness 1.0; GB_Metal metallic 0.9 / roughness 0.5; Bulb roughness
  0.5 / specular 0.6 / emission (0.1042, 0.0366, 0.0119) energy 1.0 / cull
  disabled / alpha; Puddle specular 0.75 / roughness 0.25 / alpha; Droplets
  scissor with UE clip 0.5; glasspanels frosted override intact.
- `make test` NOT run: working tree is busy (another agent owns
  `game/tests/run_tests.gd`, `mission_controller.gd`, `Exporter.cs`).

## Unmapped parameter names (kept in JSON, deliberately not applied)

- `Opacity*` scalars (Opacity, Glass Opacity, OpacityFalloffBase/End, ...):
  layer-paint opacities, not alpha.
- `Refraction` / `RefractionDepthBias` (1217 files): no Godot equivalent.
- Rain/puddle/grunge/noise/tiling scalars + switches: weathering system.
- `ShadingModel` (`MSM_Unlit` x200, Subsurface, ...): stored only; art
  direction relies on shaded+emission.
- `Specular` *colour vectors* (39 files): only scalar Specular/Spec mapped.
- `Gradient Min/Max`, `Noise Power`, lone `Roughness Low`: blend/layer
  remap bounds, not absolute values (Low/High pairs averaged only when both
  present).
- `BLEND_Additive` (84 files): only Translucent/AlphaComposite -> alpha and
  Masked -> scissor per spec.
- `PhysMaterial`: stored for debugging only.

## Commands (all exit 0)

- `python3 tools/parse_materials.py`
- `flatpak run org.godotengine.Godot --headless --path game --script res://tests/_tmp_mat_check.gd` (temp file, since removed)
