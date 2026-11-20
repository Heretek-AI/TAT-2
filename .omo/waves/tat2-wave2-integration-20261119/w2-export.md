# W2 — Linux export (`w2-linux-export`)

- Lane: `w2-linux-export` (wave key `tat2-wave2-integration-20261119`), dependsOn `w2-export-config` + `w2-remove-temp-hook`
- Date: 2026-11-19, 18:41:05 → 18:44:43 EST
- Tree: HEAD `a13d625802ef4631b803d1d43f51c7598278b353` + Wave 1 working-tree changes (uncommitted)
- Engine: Godot `4.7.2.stable.flathub.ed1daf0bf`, preset `Linux` from `game/export_presets.cfg` (release template `4.7.2.stable/linux_release.x86_64`, `embed_pck=false`)
- Config edited: **none** — preset was valid as-is (both `custom_template/*` paths resolve to installed 4.7.2 templates)

## 1. Verdict

**PASS.** Fresh Linux export produced with exit code 0 and **zero** `SCRIPT ERROR`, `SHADER ERROR` and `ERROR:` lines
in the 50,119-line export log. Artifacts on disk:

- `build/tat2-linux-x86_64` — 73,519,416 bytes, 2026-11-19 18:42:13, ELF 64-bit x86-64, stripped
- `build/tat2-linux-x86_64.pck` — 2,886,847,450 bytes, 2026-11-19 18:44:43 (sidecar, because `embed_pck=false`)

The previous binary (17:35 that day) was overwritten, so the stale-artifact condition is cleared.

## 2. Command and log

```
make linux-build
  -> flatpak run org.godotengine.Godot --headless --path game --export-release "Linux" \
       /home/john/Projects/TAT-2/build/tat2-linux-x86_64
```

- Exit: `MAKE_RC=0`, elapsed `219s`
- Full log: `.omo/waves/tat2-wave2-integration-20261119/w2-export-build.log` (5,451,676 bytes, 50,119 lines)
- Error counts in log: `SCRIPT ERROR` = 0, `SHADER ERROR` = 0, `ERROR:` = 0
- Warning count: 2,045, all `WARNING: UID duplicate detected between res://assets/ue/Raw/...`
  (imported UE raw-asset UID collisions; harmless and pre-existing, nothing in `game/src` or `game/scenes` involved)

### Log tail (last 25 lines, verbatim)

```
[  98% ] savepack | Storing File: res://src/ui/art_nouveau_theme.gd.remap
[  98% ] savepack | Storing File: res://src/ui/contract_table_ui.gd.remap
[  98% ] savepack | Storing File: res://src/ui/hud.gd.remap
[  98% ] savepack | Storing File: res://src/ui/ledger_ui.gd.remap
[  98% ] savepack | Storing File: res://src/ui/loading_screen.gd.remap
[  98% ] savepack | Storing File: res://src/ui/main_menu.gd.remap
[  98% ] savepack | Storing File: res://src/ui/mission_prep_ui.gd.remap
[  98% ] savepack | Storing File: res://src/ui/mobile_touch_ui.gd.remap
[  98% ] savepack | Storing File: res://src/ui/settings_ui.gd.remap
[  98% ] savepack | Storing File: res://src/ui/wardrobe_ui.gd.remap
[  98% ] savepack | Storing File: res://tests/e2e/e2e_helpers.gd.remap
[  98% ] savepack | Storing File: res://tests/e2e/e2e_tier1_features.gd.remap
[  98% ] savepack | Storing File: res://tests/e2e/e2e_tier2_boundaries.gd.remap
[  98% ] savepack | Storing File: res://tests/e2e/e2e_tier3_pairwise.gd.remap
[  98% ] savepack | Storing File: res://tests/e2e/e2e_tier4_scenarios.gd.remap
[  98% ] savepack | Storing File: res://tests/e2e/run_e2e_tests.gd.remap
[  98% ] savepack | Storing File: res://tests/run_tests.gd.remap
[  98% ] savepack | Storing File: res://tests/test_m2_player.gd.remap
[  98% ] savepack | Storing File: res://probe_leak.gd.remap
[  98% ] savepack | Storing File: res://.godot/global_script_class_cache.cfg
[  98% ] savepack | Storing File: res://.godot/uid_cache.bin
[  98% ] savepack | Storing File: res://project.binary
[ DONE ] savepack

MAKE_RC=0 elapsed=219s
```

### Log head (first 12 lines, verbatim)

```
== linux-build start 2026-11-19T18:41:05-05:00 ==
flatpak run org.godotengine.Godot --headless --path game --export-release "Linux" /home/john/Projects/TAT-2/build/tat2-linux-x86_64
Godot Engine v4.7.2.stable.flathub.ed1daf0bf - https://godotengine.org

[   0% ] first_scan_filesystem | Started Project initialization (5 steps)
[   0% ] first_scan_filesystem | Scanning file structure...
[  16% ] first_scan_filesystem | Loading global class names...
[  33% ] first_scan_filesystem | Verifying GDExtensions...
[  50% ] first_scan_filesystem | Creating autoload scripts...
[  66% ] first_scan_filesystem | Initializing plugins...
[  83% ] first_scan_filesystem | Starting file scan...
[ DONE ] first_scan_filesystem
```

## 3. Artifact evidence

```
$ ls -la --time-style=full-iso build/tat2-linux-x86_64 build/tat2-linux-x86_64.pck
-rwxr-xr-x. 1 john john   73519416 2026-11-19 18:42:13.416714832 -0500 build/tat2-linux-x86_64
-rw-r--r--. 1 john john 2886847450 2026-11-19 18:44:43.218775565 -0500 build/tat2-linux-x86_64.pck

$ file build/tat2-linux-x86_64
build/tat2-linux-x86_64: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked,
interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 5.15.0, stripped
```

Timestamps postdate every Wave 1 edit (latest source mtime seen: `game/src/ui/hud.gd` 17:19:04), and all 17
Wave 1-modified scripts appear in the packed `.remap` list (`hud.gd`, `thief_character.gd`, `guard_ai.gd`,
`audio_manager.gd`, `level_loader.gd`, `vfx_manager.gd`, `lockable_door.gd`, `swinging_door.gd`,
`smoke_projectile.gd`, `main_menu.gd`, `settings_ui.gd`, `wardrobe_ui.gd`, `ledger_ui.gd`,
`loading_screen.gd`, `contract_table_ui.gd`, `mission_prep_ui.gd`, `mobile_profile.gd` — one hit each).

Binary size equals the stock `linux_release.x86_64` template (73,519,416 bytes) because `embed_pck=false`;
the game payload lives in the 2.81 GB `.pck` beside it. Both files must ship together.

## 4. Smoke run (not Wave 3 live QA)

```
$ ./build/tat2-linux-x86_64 --headless --quit
SMOKE_RC=0
WARNING: 4 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
ERROR: 1 resources still in use at exit (run with `--verbose` for details).
   at: clear (core/io/resource.cpp:822)
```

The binary loads its `.pck` and exits 0. The two exit-time cleanup lines are the known pre-existing
ObjectDB/RID teardown noise itemised in `waves/tat2-wave1-fixes-20261119/w1-pg1.md` §5, not SCRIPT/SHADER
errors from this export. No GPU/live gameplay check was run here — Wave 3 (`w3-e2e-strict`, `w3-fps-profile`)
owns that against this binary.

## 5. Caveats

- Export was serialised behind a sibling lane's Godot run (waited for no `godot-bin` process) so the project
  import cache was not contended; the 219 s figure includes only `make linux-build` itself.
- `build/` is gitignored; the artifacts are untracked, as intended.
