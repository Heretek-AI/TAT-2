# gpu-session — worker summary

HEAD `cfb4986` on `teamwork/20261127-1810-phase3-gpu-session` (base `649bece`).
I ran every Phase 3 GPU capture serially through the existing wrappers under
`/tmp/opencode/tat2-godot.lock` (one Godot at a time; `pgrep` checked before each
run; the UI run wrapped in `flock ... xvfb-run`), scored each with the existing
tool, and committed the report `docs/reports/phase3-gpu-20261128.md` plus the
tracked logs (`docs/reports/logs/p0b/<tag>/`, `docs/reports/logs/phase3-gpu/`
with `host_state.txt`, `landscape_rmse.txt` and the 2026-11-28 UI sidecars +
scorer output). No `game/src` file changed and no default was flipped.

Measured: host 125 W current power limit (140 W max), 5.3 W idle before,
≤ 50.4 °C and 1260 MHz across runs, no power/thermal throttle — but
`gaming-desktop` and `split_lock=0` are **not re-proven** (unreadable as uid
1000 here; carried from the 2026-11-27 report). KF27 `foyer_beam_wide` = **3/9**
(6 bands, emitter 6.3/38.7, hot core 88; below 6/9 → material work, not a pose
tweak); pinned `foyer_beam` untouched and reproduces **5/9**; the 9/9 is
reference-only. Landscape `gap_view` RMSE: discard↔raw 1.0077/255 (0.94 % px,
19 489), off↔raw 0.0769 (0.066 % px, 1 360), discard↔off 1.0050 — the subject is
on screen (coherent 976 px lower-centre + 265 px top sliver) but only ~1 % of the
frame, so the A/B is measurable but weak. AEM meter: scene EV100 -0.864,
curve -4.0, target/adapted -4.864, exposure 0.2617, residual 0.000 EV; a
yaw180-first diagnostic reads -0.859/-4.859, so the meter is live, not latched;
fixed default 1.15 is 2.14 EV brighter. IBL ambient: irradiance_lum 7.70e-4 ×
authored intensity 2.0 × port scale 1.0 = energy 0.001540 (flat substitute 0.16);
gate unchanged, upper_foyer/yaw180 1.0–1.6 EV darker → not a win, default stays
off. UI: 28/28 frames, `UI_PIXEL_STATS PASS rows=28`; UI2-03 prompt DELTA crank
3.73/4.32, doors 3.03/3.68 (both below the unchanged 4.5 floor), secondary
3.61/4.51, key 3.42/3.62 — the authored `#636EEC` low-contrast reference value.

Marked **not verified / open** for the verifier: KF27 remains 3/9-5/9 (beam
material); landscape A/B weakness; AEM target/exposure vs fixed 1.15 is a look
decision (no calibration re-pin); IBL ambient loss; prompt contrast below floor
(authored DELTA, not a pass); host `gaming-desktop`/`split_lock` unreadable.
No capture failed and nothing was retried in a loop.
