# Wave 3 - Live Vulkan Strict E2E Parity Capture

- Date: 2026-11-19
- Command (verbatim): `cd /home/john/Projects/TAT-2 && bash build/qa/capture_e2e_parity.sh --strict`
- Renderer: `Godot Engine v4.7.2.stable.flathub.ed1daf0bf`, `Vulkan 1.4.357 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 4070 Laptop GPU` (headless Xvfb :99, 1280x720x24)
- Log: `build/qa/e2e_parity/capture_e2e_parity.log` (69 lines)

## Gate result: PASS

Five readout lines, quoted from the run's stdout:

```
EXIT=0 SHADER_ERRORS=0 SCRIPT_ERRORS=0 MISSING_OR_EMPTY=0
PARITY_SUMMARY: shots=21 parity_passes=21 parity_fails=0 shader_errors=0 script_errors=0
```

(EXIT / SHADER_ERRORS / SCRIPT_ERRORS / MISSING_OR_EMPTY are the first of those two lines; PARITY_SUMMARY is the second.)

The wrapper's own counts, re-checked independently against `capture_e2e_parity.log`:

```
EXIT=0
SHADER_ERRORS=0   (grep -c 'SHADER ERROR' = 0)
SCRIPT_ERRORS=0   (grep -c 'SCRIPT ERROR' = 0)
MISSING_OR_EMPTY=0
PARITY_SUMMARY: shots=21 parity_passes=21 parity_fails=0 shader_errors=0 script_errors=0
```

Supporting counts from the log: `PARITY_CHECK ... PASS` = 21, `PARITY_CHECK ... FAIL` = 0, `PARITY_IMAGE_FAIL` = 0, `PARITY_FATAL` = 0, `RD_` cascade lines = 0.
`PARITY_GD_DONE: shots_saved=21 image_failures=0 parity_passes=21 parity_fails=0`

## Failing checks

None. 0 of 21 PARITY_CHECK entries failed, so the list is empty.

## PNGs

`build/qa/e2e_parity/` contains **21** `.png` files (expected 21), 0 zero-byte, all written by this run (mtimes 18:42:18-18:44:34 today).

| Check | Shot | Verdict |
|---|---|---|
| S01 | parity_startscreen.png | PASS - Startscreen 3D backdrop + menu |
| S02 | parity_thieves_den_wide.png | PASS - labels=0 |
| S03 | parity_thieves_den_map_table.png | PASS - tokens=2 |
| S04 | parity_wardrobe.png | PASS - Wardrobe 3D thief + loadout UI |
| S05a | parity_ledger_journal.png | PASS - Ledger Journal tab |
| S05b | parity_ledger_market.png | PASS - Ledger Black Market tab |
| S06a | parity_mission_prep_manor.png | PASS - Mission Prep Elway Manor |
| S06b | parity_mission_prep_guildhall.png | PASS - Mission Prep Guildhall (Contract Inactive) |
| S07 | parity_loading_screen.png | PASS - Loading Screen full-art |
| S08 | parity_start_letter.png | PASS - Guildhall pre-dismiss start letter |
| S09 | parity_guildhall_spawn_hud.png | PASS - Guildhall rooftop sky + HUD |
| S10 | parity_guildhall_macneish_ssr.png | PASS - MacNeish Jeweller neon + wet cobblestone SSR |
| S11 | parity_1p_zipwire_crank.png | PASS - 1P Zipwire + HP damage + SoundWaves |
| S12 | parity_1p_smokebomb_arc.png | PASS - 1P Smoke Bomb + trajectory arc |
| S13 | parity_1p_vistara_diamond.png | PASS - 1P Vistara Diamond + clean Thief Vision |
| S14 | parity_guard_lantern_alert.png | PASS - Guard lantern + alert pips |
| S15a | parity_1p_slithersap.png | PASS - 1P Slithersap slot [3] |
| S15b | parity_lockpick_ui.png | PASS - Lockpick minigame UI |
| S15c | parity_map_overlay.png | PASS - [TAB] Map overlay |
| S15d | parity_ping_radial.png | PASS - [MMB] Ping radial |
| S16 | parity_old_manor_exterior.png | PASS - OldManor_P exterior terrain & SSR |

## Note (not a gate failure)

The log's last line pair is a shutdown-only leak warning, emitted at process finalize after `PARITY_GD_DONE`:

```
WARNING: 7 RIDs of type "Texture" were leaked.
   at: finalize (servers/rendering/rendering_device.cpp:8900)
```

This is one exit-time `WARNING`, not an error and not an `RD_` cascade: the script's SHADER/SCRIPT error counters are 0 and there are no mid-run rendering-device failures. Recorded for Wave 4 awareness only; no code was touched.
