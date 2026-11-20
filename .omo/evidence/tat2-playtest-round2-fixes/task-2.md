# Task-2 evidence — Den telescope + window vista (UE-derived)

Date (UTC): 2026-11-20. No `make test`, no live-GPU run (orchestrator owns
suites at settle). Verify is file-level: every edited span re-read from disk,
diff hunk headers checked for minis overlap (none — minis hunks in the
worktree diff are round-1's), test-46 contract re-checked by reading
`game/tests/run_tests.gd:3360+`.

## Value sources (nothing invented)

- Backlog F5/F6 rows (`cooked found`): WindowBorder
  `extracted/json/Art/Environment/Urban/WallWindow/SM_ThievesDen_WindowBorder.json`;
  telescope `BP_HidingSpot_Telescope` +
  `SM_TeleScope.json` (BodySetup_1, `MI_TeleScope_Inst`).
- task-5.log (prior round): WindowBorder StaticMeshComponent0 UE cm
  **(523.73975, 26666.291, 4064.7085)** scale (1.0401987, 1.0, 0.9991704);
  glass shell UE cm (132.74524, 27135.502, 3957.8376) yaw -90.135864;
  floor/shell same transform; moons `BP_MoonShape_C_0..C_7` (full C_1 =
  SM_Shape_Sphere at UE cm (750.6698, 27377.701, 4185.192));
  telescope Root UE cm (-492.02435, 27073.371, 4011.2234), Camera rel
  (10, 0, 170) cm yaw 148, MainMesh yaw 60.084366, no cooked FOV.
- `game/data/generated/levels/ThievesDen/ThievesDen_Geo.tatlevel.json`
  (read 2026-11-20): WindowBorder port pos **(5.2374, 40.6471, 266.6629)**
  (= UE/100 with Y/Z swapped — the axis map used everywhere below);
  `SM_ThievesDen` + `SM_ThievesDen_Glass` + `SM_ThievesDen_Floor` all at
  port (1.3275, 39.5784, 271.355) (= glass UE cm/100, same map).
  No telescope, no moon mesh in the tatlevel (single glass instance).
- Converted GLBs on disk: `SM_ThievesDen_Glass.glb` (2 prims, baked
  materials `MI_GlassPanels_oldmanor` + `MI_GlassPanels`, opaque: no alpha
  mode, no images); `SM_ThievesDen.glb` shell; WindowBorder has **no GLB**
  (ledger task-0 A7 PRESENT-UPSTREAM).
- `materials.json` + `mesh_materials.json`: glass binds
  `[MI_GlassPanels_oldmanor, MI_GlassPanels]` (both `BLEND_Translucent…`,
  `MSM_ThinTranslucent`, two-sided; textures `WindowPanel[_Oldmanor]_{D,N,ORM,O}.png`
  + `WindowPanels_Oldmanor_*.png` all present on disk) and frame bind
  `MI_StoreFrontTrimA` (wood trim, textures present). Selected pane bind
  `MI_GlassPanels` (Emissive 0.002, Roughness 1.79 = frosted; oldmanor's
  Emissive 1.0 would glow).
- Footage: KEYFRAME S05 (KF05 00:20.80 — rooftops, full moon, giant rotating
  golden cheese + 3 chunks, `[F] EXIT`; wind whoosh swell 00:19.6–00:21.9
  peaking -39.5 dBFS RMS = the `wind` bed trim -39.4), KF02 (00:04.50 moon
  shaft through arched frosted window), KF06 (00:24.60 leaded-glass window).

## mission_controller.gd edits (spans re-read)

- Hub moonbeam (lines 383–408): `win_pos = (5.2374, 40.6471, 266.6629)`
  (WindowBorder UE/100, axis-swapped — replaces hand (-5.8, 43.0, 271.5),
  which sat outside the shell on the wrong side); `beam_target =
  (-0.4317, anchor.y + 0.1, 268.9349)` where XZ = window stepped back along
  the scope→window axis by L = 6.1076 m (horizontal WindowBorder→floor-shell-
  center distance, both UE-derived), Y on the floor plane (F1 rule).
  `outward = win - beam` therefore extends the scope→window axis past the
  wall. Comment carries the full derivation.
- Vista spawn (lines 729–843): layout axis kept as `outward` (now UE-fed);
  moon r 5.0→**2.2** / h 10→4.4 at axis*38 + up **3.0** (~5° disc sharing the
  13° frame); rooftop row spacing 5.5→**1.6**, width 6.0→**2.6** (±4.5 m
  inside the ~3.9 m half-width frame math, heights kept); cheese at +1.5
  (center-frame below moon, KF05 composition); halo r 7.5→4.0; focus meta =
  `win + outward*34 + up 0.65` so the scope→window ray threads the opening
  onto the staged vista (sightline verified by hand computation in this
  file's § derivations, not by a live run).
- `toggle_telescope_ponder` (lines 845–901): map_id guard now
  `push_warning`s instead of silent return; same-frame re-entry guard via
  `ponder_toggle_frame` meta (no new member var) so the Area path and the
  lookat path collapse to exactly one flip per F press regardless of
  `_unhandled_input` order; ponder eye = tripod Area **global_position** +
  UE camera rel (0.1, 1.7, 0.0), refreshed every enter; focus = vista meta
  with on-axis fallback (3x the UE scope→window port delta
  (10.1576, 0.55, -4.0708)); `start_bed("wind")` on enter /
  `stop_bed("wind")` on exit (S05 swell hook, has_method-guarded).
- `_unhandled_input` (lines ~1000–1010): added lookat-path **enter** —
  F with lookat target `telescope` enters the zoom (the [F] PONDER card
  shows to 3.5 m, past the 1.8 m Area3D range). Exit branch unchanged.
  F now dispatches to exactly one effective toggle per press (frame guard).

## level_loader.gd edits (spans re-read)

- `den_window_gap_spec` (lines 1526–1545): the four dead hand keys
  (`vista_moon_ue`, `vista_moon_bodies`, `vista_glass_ue`, `vista_frame_ue`)
  **deleted** (not consumed — vista geometry is MISSING-UPSTREAM per ledger
  task-0 A8, so no hand UE path may masquerade as a value; the F5-precedent
  replica in mission_controller stands). Test-46 contract untouched
  (gap/sill/lintel/marker/boxes only).
- `_add_den_window_split` tail (line 1602) + new `_clip_den_window_visual`
  (lines 1604–~1670): after the 4 collider boxes, the sibling visual
  `MeshInstance3D` whose transform matches `tr` is hidden and replaced by
  an opening-fitted frosted pane (`MI_GlassPanels`, ThinTranslucent) plus
  jamb/head/sill trim (`MI_StoreFrontTrimA`, the authored WindowBorder bind
  from mesh_materials.json — the frame GLB is missing upstream, extractor
  allowlist `tools/tat-extract/Exporter.cs:200`). Sizes reuse the
  `DEN_WINDOW_*` split constants and the collider box depth; no hand
  measurement. No collision emitted; no-ops on a bare host (test-46's
  `_add_den_window_split` direct call finds no visual → 4-shape delta kept).

## Headless-safe loader behavior

- `_clip_den_window_visual` touches only in-tree Node inspection, `BoxMesh`
  + `get_material_for_ue` binds (ResourceLoader-exists-checked, same path
  task-5.log established as headless-safe), and per-node meta; it returns
  before any material work when no sibling visual exists, so the bare-host
  test path is behavior-identical (4 colliders, 0 visuals).
- Vista replica unchanged in kind: `BoxMesh`/`SphereMesh` +
  `StandardMaterial3D`, no external assets, no physics queries.

## Assumptions (recorded)

- UE→port axis map (X/100, Z/100, Y/100) confirmed by tatlevel pos vs
  task-5.log UE cm for both WindowBorder and glass.
- Telescope zoom 13° still KF05-framed (no cooked UE FOV — unchanged).
- `anchor.y` is the Den floor (F1 rule, unchanged); beam Y = anchor.y + 0.1.
- Glass assembly is a single instance, so hiding it at the split removes no
  other window's glass; fitted pane + trim cover exactly the collider gap.
