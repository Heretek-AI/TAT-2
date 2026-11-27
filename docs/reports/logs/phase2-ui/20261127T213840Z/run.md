# P5 UI capture — run `20261127T213840Z`

Worktree: `/home/john/.local/share/opencode/worktree/318f41/phase2-ui`
Branch: `w10/phase2-ui` (harness fix on top of `8a19144`)
Data: shared `extracted/` + `game/data/generated/` at the integrated payload
(`T_stealthball_Array` 21 slices, `stealthball_array.json` present).
GPU: one Godot at a time under `flock /tmp/opencode/tat2-godot.lock`,
`xvfb-run -a -s "-screen 0 2560x1440x24"`, Vulkan. PNGs are **not** tracked
(they stay in `/tmp/opencode/p5-ui-captures/20261127T213840Z/`); this directory
tracks the logs, the 28 sidecars, and the metrics JSON.

## Command

```bash
flock /tmp/opencode/tat2-godot.lock -c \
  "xvfb-run -a -s '-screen 0 2560x1440x24' env XDG_DATA_HOME=/tmp/opencode/p5-ui-data \
   tools/godot --path game --rendering-driver vulkan \
   --script '/home/john/.local/share/opencode/worktree/318f41/phase2-ui/build/qa/capture_p5_ui.gd'"
```

## Result

```
P5_CAPTURE_DONE run_id=20261127T213840Z captures=28 failures=0 out=/tmp/opencode/p5-ui-captures/20261127T213840Z
CAPTURE_EXIT=0
```

14 frames × 2 sizes (1280×720, 1920×1080), 28 PNG + 28 sidecars. The previous
GPU-lane run (`20261127T212154Z`) had 10 sidecars truncated before `roi.*`; this
run has `roi.*` for every shot at both sizes (the proof is below).

## Authored payload evidence (probe, headless)

```
GEM_PAYLOAD present=true: layers=21 table=21 kind=directional slice=9 missing=[]
P5_UI PASS checks=54
```

`tools/parse_stealthball_array.py` measured the real payload: 21 slices,
256×256 `PF_DXT5`, lit fraction 0.0076–0.8484, cap angles clustered around
−122° (upper-left) with slice 20 the one outlier at +71°. `mapping.kind =
directional` (pairwise spread 169.4°). The HUD bound all 21 slices in every
captured mission frame (`hud.gem=path:authored_array bound:true layers:21`).

## Flat-sidecar proof (previously truncated shots)

`contract_table` and `briefing`, both sizes, now carry the ROI fields:

```
contract_table @ 1280x720   roi.table   roi.legend
contract_table @ 1920x1080  roi.table   roi.legend
briefing @ 1280x720         roi.paper   roi.paper_text   roi.world
briefing @ 1920x1080        roi.paper   roi.paper_text   roi.world
```

The same holds for `wardrobe` (3 ROIs), `ledger` (4) and `ledger_market` (4)
at both sizes; see `sidecars/*.txt`.

## Strict pixel table (28 rows; 24 failures)

`ui_pixel_stats.py --dir <run> --json ui_pixel_stats.json --require
startscreen,den_hud,pause,prep,briefing,contract_table,wardrobe,ledger,safe_room,crank,doors,key,pause_backdrop --strict`
exits **1**; thresholds unchanged. Full log in `ui_pixel_stats.log`.

| Row | Measured | Classification |
|---|---|---|
| `contract_table` legend clipped left/top | contrast 5.54 (tight 7.15), bbox starts at the ROI corner | **metric ROI closure** — the ROI corner sits on the panel border; no text is cut by the element |
| `crank` prompt contrast 3.62/4.35, clipped top/bottom | ROI spans the 128 px reticle ring + label; label-only contrast 7.64 | **metric ROI** (ring in ROI) + borderline element contrast (~4.3) |
| `doors` prompt contrast 3.07/3.81, clipped top/bottom | ROI spans both prompt rows; element-level 3.9–4.31 | **borderline contrast choice** (< 4.5 WCAG), **not** a clip: keycap + text fully inside their row |
| `key` row clipped bottom | tight contrast **7.74**, bbox 28..284 × 957..999 | **metric ROI** — the 7 %-tall ROI ends 1 px under the glyphs |
| `ledger`/`ledger_market` tabs clipped bottom | contrast 7.6–8.1 | **metric ROI** — panel chrome at the ROI edge |
| `pause` blur 7.87/6.58 | outside the modal: backdrop 3.712 → paused 0.211, **ratio 0.057** | **metric mask** — the edge term counted the modal's sharp panel; the world *is* blurred |
| `pause` footer ink=0, contrast 1.10 | footer found at (26,1046)–(318,1060), tight contrast **5.44** | **metric ROI** — the footer is bottom-left, not centred |
| `prep` prompt/cards clipped left/top/bottom | contrast 7.83/8.33 | **metric ROI** — card/panel borders touch the ROI edge |
| `briefing` line_count 10 @1080 | first run 302..372 merges two lines; last run 705..727; margin 142 px, overflow false | **detector artifact** — the headless probe pins the authored 11-line layout |
| `crank` gem angle error 88–90° | `amount=0.000` (staged concealed state) | **metric artifact** — no lit cap to locate; the `safe_room` gem reads a coherent −64° |
| `startscreen`/`wardrobe`/`pause_backdrop` | no text/gem failures | — |

No failure in this run is a confirmed UI clipping or missing element. The one
real (borderline) UI observation is prompt contrast around **4.0–4.3** against
the scene at the doors/crank pose, below the 4.5 strict floor but consistent
with the reference's UI2-03 `DELTA` (dark glyph, thin outline); the prompt is
readable with its shadow.

## Residual visual gaps

- The authored array is predominantly a **fixed upper-left cap with varying lit
  fraction** (an exposure ramp); the `directional` label is driven by slice 20's
  +71° outlier. The runtime's 0.35 angle term can select slice 20 at low amounts
  (it is dark blue), so the gem's rendered direction is not yet adjudicated
  against KF14/17/24/25 by eye.
- The gem's on-screen size/placement inside the frame is derived from the
  authored `ImageSize 144` geometry; the capture measures the cap but does not
  score it against the reference frames.
- Prompt contrast and the `key`/`footer`/`legend` ROIs need adjudication-level
  ROIs before they can be promoted to a pass/fail metric; this run records the
  numbers, not a visual verdict.
- The `crank`/`doors`/`key` frames reuse the frozen safe-room HUD (amount 0), so
  their gem is the concealed slice; those rows judge prompts/keys, not the gem.
