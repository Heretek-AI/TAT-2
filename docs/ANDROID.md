# Android Internal Build

TAT-2 ships to Android as an **internal, sideloaded APK** (no Play Store listing).
The build is a generated project: `game/` stays desktop-clean (Forward+, lossless
textures) and `build/mobile_game/` gets ETC2 textures + the Mobile renderer.

## Outputs

| Command | Output | Notes |
|---|---|---|
| `make android-release` | `build/tat2-mobile-release.apk` | arm64, Mobile/Vulkan, signed with the internal key — **this is the phone build** |
| `make android-debug` | `build/tat2-mobile-debug.apk` | arm64 + x86_64, debug key |
| `make android-debug-gl` | `build/tat2-mobile-gl-debug.apk` | emulator-only QA build (Compatibility renderer) |

Options: `TEXTURE_CAP=1024` (default; `512` roughly halves the APK), `MOBILE_ABI=arm64|both`,
`QA_CONTRACT=<order>` boots straight into a mission (0 = main menu).

Current arm64 release APK: **~914 MB** (1,393 ETC2 textures @1024 + 1,565 meshes).
Install needs ~2 GB free. `adb install -r build/tat2-mobile-release.apk` or copy the
APK to the phone and allow "install unknown apps".

## How it works

`tools/prepare_mobile_project.py`:

1. copies `src/`, `scenes/`, `data/generated/` and the 77 shipped `.tatlevel.json` files;
2. resolves the asset closure from level meshes, landscape heightmaps, `materials.json`
   and `res://assets/...` literals in scripts — 2,963 files, 2.1 GB source;
3. writes a mobile `project.godot`:
   - `renderer/rendering_method="mobile"`, landscape (`handheld/orientation=4`),
     keep-screen-on, shadow atlas 2048, MSAA 0;
   - `textures/vram_compression/import_etc2_astc=true`;
   - `[importer_defaults] texture = {VRAM compressed, mipmaps, size_limit=1024}`;
4. generates launcher icons from `T_portrait_spider.png` (ImageMagick);
5. writes `export_presets.cfg` (`com.heretek.tat2`, targetSdk 36, INTERNET + VIBRATE);
6. runs `godot --headless --import` (second pass is needed on a fresh project because
   `AudioManager` preloads `.wav` files before the audio importer has run).

The source project's `.godot` cache and import settings are untouched.

## Signing

- Keystore: `~/.config/tat2/tat2-internal.jks`, alias `tat2`.
- Passwords: `~/.config/tat2/keystore.properties` (mode 600, outside the repo).
- **Back this up.** Android will refuse to update an installed app signed with a
  different key. Losing it means uninstall/reinstall on every device.
- `make android-release` reads the properties file and passes the key to Godot via
  `GODOT_ANDROID_KEYSTORE_RELEASE_*`; no secrets are written into the project.
- Version bumps: edit `version/code` / `version/name` in the generated
  `export_presets.cfg` (or add flags to the generator) before each release.

## Touch controls

Landscape, floating stick, drag look, 13 buttons. All actions go through the normal
input actions, so `thief_character.gd` remains the single source of truth.

```
┌────────────────────────────────────────────────────────────┐
│ objective            compass                 portrait      │
│ stealth gem / hp / stam                                    │
│                    (unobstructed view)                     │
│                                                            │
│                                            [II]  [JUMP]    │
│                                      [EYE]  [WIRE]         │
│                              [FAIRY]                       │
│                              [SMOKE]        [USE]  [HIT]   │
│  ╭─────────╮                 [SAP]                         │
│  │ move    │   [CROUCH][SPRINT][LEAN L][LEAN R]            │
│  ╰─────────╯                                               │
└────────────────────────────────────────────────────────────┘
```

- **Move** — floating stick in the left 42 % × bottom 72 %; auto-sprint after 0.35 s
  at >90 % deflection (plus the SPRINT hold button).
- **Look** — drag in the right 55 %; sensitivity multiplier in Settings → Controls
  ("Touch Look"), invert reuses the existing "Invert Y".
- **USE** glows cyan when an interaction is in range and shows the verb; the desktop
  centre prompt is hidden on mobile.
- Tool buttons show charge counts and dim at zero; the ability button relabels per
  thief (WIRE / MASK / ASTRAL).
- Pause: `II` button or the Android back gesture/button (`NOTIFICATION_WM_GO_BACK_REQUEST`).
- App focus loss auto-pauses; all latched actions are released on pause/scene change.
- Look/capture mouse paths are disabled on mobile (`OS.has_feature("mobile")`) so
  Android's touch→mouse emulation cannot double-apply look.

## Mobile quality profile (`game/src/core/mobile_profile.gd`)

Runtime tiers selectable in Settings → Controls; persisted in `SaveSystem`.

| Tier | Lights | Shadow casters | 3D render scale | LOD bias | Glow | FPS cap |
|---|---|---|---|---|---|---|
| Performance | 12 | 1 | 0.70 | 2.5 | off | 30 |
| Balanced (default) | 24 | 2 | 0.85 | 2.0 | on | 60 |
| Quality | 32 | 4 | 1.00 | 1.5 | on | 60 |

Desktop keeps 96 lights / 4 shadow casters / scale 1.0. Texture resolution is baked at
build time (`TEXTURE_CAP`), so it is not part of the runtime tiers.

## Emulator caveat

The local Android emulator (`xune-test`, android-36 x86_64) boots SwiftShader into a
SELinux `execmem` denial, so it must run with `-gpu angle_indirect`. That GPU stack
cannot present Godot's Vulkan swapchain (`Couldn't present to Vulkan queue`), which
freezes Mobile-renderer builds. Emulator verification therefore uses
`make android-debug-gl` (Compatibility/GLES), which renders correctly:

- main menu loads and displays;
- QA autostart contract 1 → `TAT-2 Loaded thieves_den: meshes=272 lights=8`,
  `chunks=156 collision_bodies=2 collision_shapes=95 occluders=1`;
- touch UI renders and highlights the contextual USE button.

The **phone build uses Mobile/Vulkan** and must be verified on hardware. If a specific
device fails to start with a Vulkan error, export a Compatibility fallback with
`python3 tools/prepare_mobile_project.py --renderer gl_compatibility --abi arm64`
followed by the same release export.

## Verification

- `make test` — 16 desktop suites, including mobile profile values and the 13-button
  touch layout (`SUMMARY: fails=0`).
- `apksigner verify build/tat2-mobile-release.apk` → v2 signature valid.
- `aapt dump badging` → `com.heretek.tat2`, versionCode 1, versionName 1.0.0,
  minSdk 24, targetSdk 36, label "Thick As Thieves 2".
- `unzip -l` → 1,393 ETC2 textures, 1,565 `.scn`, one arm64 lib, no S3TC variants.

## Known limits

- No physical device was attached during this pass; FPS, thermals and load times on
  hardware are unmeasured. Guildhall (15,872 instances) is the worst case — start on
  Performance and compare with Balanced.
- Cold map load is ~16 s for Guildhall on desktop; phone storage may make it 45–90 s.
- The APK embeds the whole game (no Play Asset Delivery / OBB).
