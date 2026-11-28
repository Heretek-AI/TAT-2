# Sky + Rain Implementation (stage report)

Stage: replace flat `BG_COLOR` sky with real sky data + weather-driven rain.
Date: 2026-11-16. Repo: `<repo>` (Godot 4.7.2).

## Deliverables

1. **New `game/src/core/weather_visuals.gd`** (+ `tat_sky.gdshader`, both with
   `.uid` files matching repo convention):
   - `make_sky(preset, moon) -> Sky` — `ShaderMaterial` sky shader with
     horizon/zenith gradient, moon disc, sparse star term, cloud haze.
   - `apply_sky(env, preset, moon) -> bool` — sets `BG_SKY` + sky +
     `REFLECTION_SOURCE_SKY`; returns false for empty presets.
   - `make_rain(parent, preset) -> Node3D` — `GPUParticles3D` rain volume;
     null when `rain.enabled` is false or intensity <= 0.05.
   - `snap_rain_to(rain, target)` — follow helper used every `_process`.
2. **`mission_controller.gd`**: `_setup_environment` now resolves the preset
   once, calls `apply_environment` + `WeatherVisuals.apply_sky`, then
   `MobileProfile.apply_environment` (glow override still last). Rain is
   created after `_spawn_player` and re-centered on the player each `_process`.
   Thieves' Den ambient tweak and the main-menu `BG_COLOR` path are untouched.
3. **`level_loader.gd`**: `_is_moonshape_mesh()` + parse-time skip counted as
   `moonshape_hidden` in level stats. Nothing else is skipped.
4. **Temp check** `game/tests/_tmp_sky_check.gd`: all 25 assertions passed,
   then deleted (see output below). `run_tests.gd` untouched.
5. **`make test`: `SUMMARY: fails=0`, exit 0, zero `SCRIPT ERROR`.**
6. This report.

## Value mapping (UE -> Godot)

| UE source (JSON) | Godot use | Notes |
|---|---|---|
| `sky.horizon_color` / `sky.zenith_color` | sky shader gradient uniforms | Missing horizon -> `background_color`, then `overall_color`, then zenith x0.55; missing zenith -> `overall_color`, then horizon x0.6 (JSON only carries horizon/zenith/overall keys) |
| `moon.size` | disc half-angle = size/2, degrees, clamped [1, 40], default 6 deg when null | Only authored size; 1m_Plane_Reverse instances are ~4.25 m quads, so a large stylized disc, not the real 0.5-deg moon |
| `moon.visible == false` | disc hidden | e.g. heavy_rain, dense_fog_old_manor |
| `T_Moon_D.png` (4096x2048 equirect) | disc albedo, centered-square crop | Real lunar panorama used by `M_Moon`/`MI_Moon_Base`; centered crop is APPROXIMATE (cooked materials kept no UV rect) |
| `moon.color` (else `emissive`) | disc tint x `clamp(0.3+0.5*brightness, 0.25, 2.0)` x `sky.intensity` in [0.25, 1.5] | UE brightness spans 0.15-50, compressive map is APPROXIMATE |
| `sky.stars_brightness` | procedural hash sparkle, `clamp(b/8,0,1)`, only when > 0 | APPROXIMATE, no star catalogue recovered |
| `sky.cloud_color`/`cloud_opacity` | horizon haze band, strength `clamp(op*0.18,0,0.55)` | No cloud texture invented |
| `rain.enabled` + `rain.intensity` | `GPUParticles3D`: 60x40x60 m box, `1800*clamp(i,0,1.5)` drops in [100,2700], lifetime 1.1 s, gravity 30 m/s^2, 0.035x0.7 m unshaded alpha streak quads, world-space emission | Counts are APPROXIMATE (only on/off + scalar recovered) |
| `sky.light_color`/`intensity`, fog, moon light, post | unchanged via `WeatherProfile.apply_environment` | Ambient stays `AMBIENT_SOURCE_COLOR`; reflections use the live sky |

New raw getters in `weather_profile.gd`: `sky_stars_brightness`,
`sky_cloud_color/opacity`, `moon_disc_size/visible/brightness/color`.

## Moon-plane hiding

- Extracted data correction: the 100 `1m_Plane_Reverse` instances bind
  `MI_EmisLight_Moonlight` (unlit, texture stripped by cooking), **not**
  `MI_MoonshapeEmissive` (nothing binds it). Detection therefore has two
  clauses: (a) bound material path contains `Moonshape` or has the
  `IsMoonshape` switch (letter of the spec); (b) exact mesh
  `1m_Plane_Reverse` whose bound materials carry no albedo texture (covers
  the actual 100 planes; `SM_Moon`, benches etc. can never match).
- Skipped at parse time (no geometry/collision/spawn), counted as
  `moonshape_hidden`. OldManor_Geo: exactly 25/25 hidden, other meshes load.

## Temp-check output (deleted after run)

25/25 PASS, `SUMMARY: fails=0`, exit 0, including: heavy_rain and
midnight_clear apply `BG_SKY` + `ShaderMaterial` with uniforms matching the
preset horizon/zenith/moon colors; `{}` keeps `BG_COLOR`; rain node for
heavy_rain (1.0), none for midnight_clear (1e-06); `moonshape_hidden == 25`;
no visible moonshape node; `T_Moon_D` loads at 4096x2048.

## Verification

- `make test` (run twice, final state incl. `.uid` files): 20 PASS,
  `SUMMARY: fails=0`, exit 0, zero `SCRIPT ERROR` lines.
- Only engine shutdown noise at exit (ObjectDB/RID warnings, identical in
  the temp run; pre-existing quit-timing artifacts, exit code unaffected).

## Visual-check list (in-engine, not headless-verifiable)

- [ ] Guildhall (midnight_clear): starry gradient + moon disc overhead-ish
      (pitch -30, yaw 40), no rain, no gray quads.
- [ ] Old Manor (dense_fog_old_manor): overcast gradient, no disc
      (`visible: false`), no rain (intensity 1e-06).
- [ ] Jaspering Hall (heavy_rain): rain volume follows player, overcast haze.
- [ ] Thieves' Den: warm interior mood preserved (ambient tweak intact).
- [ ] Main menu: `BG_COLOR` backdrop + `SM_Moon` mesh intact.

## Self-audit

- No stubs/TODOs; fail-closed on empty presets; constraints respected (no
  edits to `run_tests.gd`, player/AI/pickup scripts, parsers, Makefile).
- Known approximation: moon panorama crop + star/cloud/rain parameters are
  documented as such in code, shader, and above — no invented art shipped.
- `.uid` files for the two new assets are newly generated unique IDs.
