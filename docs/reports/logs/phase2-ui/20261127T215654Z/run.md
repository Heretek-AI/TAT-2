# P5 UI capture — integrated run `20261127T215654Z`

Worktree: `/home/john/.local/share/opencode/worktree/318f41/phase12-integration`
Branch: `phase12-integration`, tip **`06c8956`** (`8111bbe` mirror harness fix +
`06c8956` UI sidecar fix, on top of `18d1fa7`).
Payload: shared `extracted/` + `game/data/generated/` (`T_stealthball_Array`,
21 slices, `stealthball_array.json` present).
GPU: one Godot at a time under `flock /tmp/opencode/tat2-godot.lock`,
`xvfb-run -a -s "-screen 0 2560x1440x24"`, Vulkan. PNGs are **not** tracked
(they stay in `/tmp/opencode/p5-ui-captures/20261127T215654Z/`); this directory
tracks the logs, the 28 sidecars and the metrics JSON.

This is the **integrated** tree — the UI lane's own run (`20261127T213840Z`) was
on its lane worktree; this run re-measures the same harness against the P4 look
changes merged in the integration.

## Command

```bash
flock /tmp/opencode/tat2-godot.lock -c \
  "xvfb-run -a -s '-screen 0 2560x1440x24' env XDG_DATA_HOME=/tmp/opencode/p5-ui-data \
   tools/godot --path game --rendering-driver vulkan \
   --script '/home/john/.local/share/opencode/worktree/318f41/phase12-integration/build/qa/capture_p5_ui.gd'"
```

`capture.log` is that command's stdout (`$ …` first line and the trailing
`EXIT=0 DURATION=198s` are the lane runner's, not the harness's).

## Result

```
P5_CAPTURE_DONE run_id=20261127T215654Z captures=28 failures=0 out=/tmp/opencode/p5-ui-captures/20261127T215654Z
```

14 frames × 2 sizes (1280×720, 1920×1080) = 28 PNG + 28 sidecars, exit 0.

**Sidecar fix confirmed:** all **28/28** sidecars carry `roi.*` lines. The old
run (`20261127T212154Z`) had 10 truncated before `roi.*`; at `06c8956`
`contract_table` (2 rois), `wardrobe` (3), `ledger` (4), `ledger_market` (4) and
`briefing` (3) all record their ROI luma rows at both sizes.

## Authored gem

```
GEM_PAYLOAD present=true: layers=21 table=21 kind=directional slice=9 missing=[]
P5_UI PASS checks=54
```

(headless `probe_p5_ui.gd`, `probe_p5_ui.log`.) Every mission sidecar records
`hud.gem=path:authored_array bound:true layers:21 kind=directional`.

## Strict pixel metrics

```
build/qa/ui_pixel_stats.py --dir …/20261127T215654Z \
  --json …/ui_pixel_stats.json \
  --require startscreen,den_hud,pause,prep,briefing,contract_table,wardrobe,ledger,safe_room,crank,doors,key,pause_backdrop --strict
UI_PIXEL_STATS SUMMARY rows=28 fails=24        (exit 1)
```

Thresholds unchanged (`STRICT_PROMPT_CONTRAST=4.5`, `STRICT_PAUSE_BLUR_RATIO=0.60`,
`STRICT_PAUSE_DIM_RATIO=0.90`). `ui_pixel_stats.log` is the full console table;
`ui_pixel_stats.json` is the machine copy.

Classification of the 24 failures (see the integration report §10 for the
measurement detail): 18 are ROI-mask artifacts (ink touching a mask edge while
the text/artwork is complete: `crank`, `doors`, `prep`, `key`, `ledger`,
`ledger_market`, `contract_table` legend), 4 are genuine prompt-contrast values
below 4.5 (`crank` 3.81/4.32, `doors` 3.24/3.70), and 2 are the pause
`blur_ratio` artifact (the scorer's edge-energy box includes the modal; outside
the modal it is 0.19/0.18).
