# Asset retirements

Assets removed from the generated tree because they have no non-hidden `res://` route and no
reference from the port. Each entry records the evidence required by task 11.2.

## 2026-11-21 — UltraDynamicSky weather mask brushes (3)

| Asset | Reason |
|---|---|
| `TAT/Plugins/UltraDynamicSky/Content/Textures/Weather/Mask_Brushes/Brush_Circle.png` | Reachable only through `res://assets/ue/Raw/TAT/Plugins/...`; the Raw route is now ignored by `extracted/assets/TAT/.gdignore`. Zero path references and zero UID references in `game/` (`.gd`, `.tscn`, `.tres`, `.json`, `.godot`). |
| `.../Mask_Brushes/Brush_Radial.png` | Same as above; UID `uid://bgqpknxmn0gq2` unreferenced. |
| `.../Weather/DLWE_Radial_Brush.png` | Same as above; UID `uid://bow54ocv4lfhi` unreferenced. |

These are Ultra Dynamic Sky demo/mask textures. The shipped game's rain presets use the
weather material parameters parsed from `BP_WeatherPreset_*`, not these brushes, so retiring
them does not remove any gameplay or rendering behaviour.

Their `.import` sidecars named the now-ignored `Raw/TAT` route and could never be repaired to a
visible route (`game/assets/ue` exposes only `Content` and `Raw`). Deleting the sidecars is
sufficient to keep the tree clean; `make extract` may re-dump the source PNGs into the ignored
tree, which Godot will not scan and therefore cannot re-import.
