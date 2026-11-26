# P0b Lane L — live reference preparation (no launch)

**Status:** prepared 2026-11-26 in worktree `w10/p0b-live`, base `09d8a30`.
**Nothing was launched.** Steam, Proton and the shipped game were not started by this
lane; the Steam client was already running (PID 17548) and was only inspected.
**What exists now:** the appid 3341000 Proton prefix copied and byte-verified at
`/tmp/opencode/tat2-ref-prefix`, and the tracked helper
[`build/qa/p0b_live_capture.sh`](../../build/qa/p0b_live_capture.sh). The helper never launches
anything; it only checks, copies, stages the copy, prints the capture command and
hashes the result.

The live reference is the **shipped UE5.5 build** `1.5.148559` (Steam appid 3341000):
the only ground truth for the 120-row baseline. The port capture (Lane I) uses fixed
poses; this plan captures the same poses in the shipped game at **2560×1440, 60 fps,
100 % screen percentage**, lossless, with system audio.

---

## 1. Measured state (2026-11-26, this host)

### Install and appmanifest

| Item | Measured value |
|---|---|
| Install | `~/.steam/steam/steamapps/common/Thick As Thieves/` (`TAT.exe`, `TAT/Binaries/Win64/TAT-Win64-Shipping.exe`, `TAT/Content/Paks/pakchunk0-Windows.ucas`) |
| appmanifest | `~/.steam/steam/steamapps/appmanifest_3341000.acf` |
| `buildid` | **25076818** |
| `StateFlags` | **4** (Fully Installed) |
| `AutoUpdateBehavior` | **0** — *Always keep this game up to date* |
| `TargetBuildID` | **0** — no queued update |
| `AllowOtherDownloadsWhileRunning` | 0 |
| `LastUpdated` | **2026-09-16 18:39:53** (epoch 1789598393) |
| `LastPlayed` | **2026-11-18 15:28:06** (epoch 1795033686) |
| `SizeOnDisk` | 3,806,904,534 bytes |
| Depot | `3341001`, manifest `3980737812781455101` |
| appmanifest sha256 | `02e5a3fcf4425eaf24b805752c6d32d8943a82ccef688df3921cc153a2a77d57` |
| Shipping exe version | `1.5.193.148559 //TAT/tat_release_nosrc` |
| Bootstrap `TAT.exe` version | `tatp-1.5.148559-release-193` |
| Shipping exe sha256 | `a774ee8f728c99e68384612307cfbc87d911cafe0cff61a90605849054a65164` |

### Steam client

| Item | Measured value |
|---|---|
| Client | running since 2026-11-26 12:57:46; `steamwebhelper -buildid=1794536281` |
| Login | **logged on** (`connection_log.txt` 12:57:51 `Logged On … 'OK'`) |
| Account | `Johnny Cipher` (`johnnycipher`), `RememberPassword=1`, `AutoLogin=1` |
| Offline flag | `WantsOfflineMode=0` (currently **online**) |
| appinfo | `appcache/appinfo.vdf` refreshed 2026-11-26 14:14 |
| Update check | `ISteamApps/UpToDateCheck appid=3341000&version=25076818` → `{"success":true,"up_to_date":true,"version_is_listable":true}` |
| Content log | no 3341000 update events since 2026-11-18; only App Running/Fully Installed transitions |
| Launch options (3341000) | none |
| Compat mapping (3341000) | no explicit entry; the prefix was created with **Proton Experimental** |

### Proton prefix

| Item | Original | Copy |
|---|---|---|
| Path | `~/.steam/steam/steamapps/compatdata/3341000` | **`/tmp/opencode/tat2-ref-prefix`** |
| Size | 610,409,536 bytes apparent (`du -sh` 590 M) | 610,409,536 bytes apparent (`du -sh` 584 M; block accounting differs, bytes are identical) |
| Files | 775 | 775 |
| `version` | `11.0-100` | `11.0-100` |
| `config_info` | `Proton - Experimental` / `11.0-100` | same |
| Last written | 2026-11-18 15:24 (`pfx/system.reg`) | copy of that state |
| Verification | — | `diff -r --no-dereference` clean; all 775 files and every symlink match (`diff` exit 0) |

Proton installed: `Proton - Experimental` version file
`1794497090 experimental-11.0-20261112-x86_64`; `toolmanifest.vdf` requires app
4183110. The prefix's `11.0-100` matches this build. The copy preserves the
`pfx/dosdevices/z: -> /` symlink (it is **not** dereferenced).

### Shipped save, settings and caches

| Item | Measured value |
|---|---|
| Save dir | `pfx/drive_c/users/steamuser/AppData/Local/TAT/Saved/SaveGames/` (36 K) |
| Save files | `TAT_ETS.sav`, `EnhancedInputUserSettings.sav`, `steam_autocloud.vdf` |
| `GameUserSettings.ini` | mixed saved state: `[Settings.Video] WindowMode=Windowed`, `Resolution=(1920,1440)`, **`ResolutionQuality=42`**, every `sg.*Quality=0` (Low), VSync off, FPS limit 0; the TAT block still says `FullscreenMode=1` and `ResolutionSizeX/Y=3840×2134`; HDR off |
| UE PSO cache | `Saved/TAT_PCD3D_SM6.upipelinecache` (364 K, 2026-11-18 15:28) |
| vkd3d cache | **inside the install**: `TAT/Binaries/Win64/vkd3d-proton.cache` 1,743,312 B (11-18 15:18) + `.write` 1,120 B (11-18 15:27) |
| Steam shader cache | `steamapps/shadercache/3341000/` 172 M (`fozpipelinesv6`, `nvidiav1`, `DXVK_state_cache`) |
| Crash dumps | two under `Saved/Crashes/` (1.4 M); not a blocker |

**The saved video settings are not usable as the reference.** `ResolutionQuality=42`
and all-Low were left by an earlier low-spec run; the capture requires 1440p at 100 %
and the shipped default preset. Reset them **in-game** and record the settings screen.

### Host

| Item | Measured value |
|---|---|
| GPU | NVIDIA GeForce RTX 4070 **Laptop** GPU, driver 620.73.04, **8188 MiB** |
| VRAM free at inspection | **2,253–2,499 MiB** (Brave 757 MiB, VS Code 886 MiB, Vesktop 459 MiB, ptyxis 137 MiB, kwin 15 MiB, plus Steam) |
| Session | `XDG_SESSION_TYPE=wayland`, `DISPLAY=:0` (XWayland), `WAYLAND_DISPLAY=wayland-1` |
| Display | HDMI-A-1 3840×2160 @ 119.86 Hz |
| Audio | default sink `alsa_output.pci-0000_01_00.1.hdmi-stereo`, monitor available; USB Sony INZONE H9 suspended |
| ffmpeg | 9.1; `x11grab` supports `-window_id` |
| Disk | `/home` 188 G free; `/tmp` 31 G tmpfs (not for video) |
| Capture test | a real (non-game) 1600×900 X window, 60 fps, **120 frames / 2.000 s**, `libx264rgb -qp 0`, `pix_fmt=gbrp`, FLAC 48 kHz stereo — the command path works |

---

## 2. Can an offline launch avoid updating the install?

**Yes, if Steam is switched to Offline Mode before Play. Currently no update is
offered**, so an online launch *today* would not update:

- `TargetBuildID=0`, no queued update; `appmanifest` mtime 2026-11-18;
- `content_log.txt` has no download/update events for 3341000 since 2026-11-18;
- Valve's `UpToDateCheck` says buildid **25076818 is up to date** (queried today);
- the installed exe is `1.5.193.148559`, i.e. the 1.5.148559 build.

**But `AutoUpdateBehavior=0` means an online launch will update as soon as a new
build is published.** The install last changed 2026-09-16, 71 days ago; a patch can
ship at any time. Therefore:

1. **Switch Steam to Offline Mode before pressing Play.** Offline mode does not
   contact the CDN, so it cannot download a build.
2. Re-run the preflight immediately before the run; abort if `buildid` is no longer
   25076818, `TargetBuildID` is not 0, or `UpToDateCheck` says `up_to_date:false`.
3. **If Offline Mode cannot be entered, do not launch.** Wait for the owner. Do not
   "try it online and see"; a background auto-update would destroy the reference
   install (3.8 GB re-download, and the build may no longer be 1.5.148559).

The run itself necessarily writes two non-code things: Steam updates the
appmanifest `LastPlayed` state, and the game appends its `vkd3d-proton.cache*`
inside the install directory. This lane did **not** do either; hash both before and
after and record the deltas. Nothing else in the install should change.

---

## 3. Blockers and the safest path

| # | Blocker | Severity | Measured / action |
|---|---|---|---|
| B1 | **Steam sign-in** | medium | Already logged on with a remembered password; offline mode should work. If Steam asks for a password or a Steam Guard code, stop: do not switch online to re-auth during the capture window. |
| B2 | **Auto-update** | **high** | `AutoUpdateBehavior=0`. Offline Mode is mandatory. Verify `buildid=25076818`, `TargetBuildID=0` and `UpToDateCheck=true` immediately before. Abort on any change. |
| B3 | **VRAM** | **high** | 8188 MiB total, only **2,253–2,499 MiB free**. Close Brave, VS Code, Vesktop, ptyxis and every other GPU app; target **≥ 5.5 GiB free** (preflight blocks below 4 GiB). A 1440p native UE5.5 scene on an 8 GiB laptop GPU is still tight; watch `nvidia-smi dmon` and `nvidia-smi --query-gpu=memory.used`. If it thrashes, stop; do not silently drop to 1080p. |
| B4 | **Wayland / XWayland** | medium | Session is Wayland; Proton/Wine renders through XWayland (`DISPLAY=:0`). `ffmpeg x11grab -window_id` was verified on a real 1600×900 X window (120 frames/2 s, 60/1). Capturing the *game* window is unverified until the run: check with `xdotool getwindowgeometry` and a 10 s test. Fallback: put the window at 0,0 and capture `-video_size 2560x1440 -i :0.0+0,0`; do not switch to a lossy encoder. |
| B5 | **Audio routing** | low | Default sink is HDMI, monitor available. If the game selects the USB headset instead, set it as the default sink and capture **its** `.monitor`. Close all other audio sources; the monitor captures the whole system mix. |
| B6 | **Disk** | low | `/home` has 188 G; the capture must go there (`~/Videos/...`), never `/tmp` (31 G tmpfs, wiped on reboot). Measure the first 10 s bitrate before the full run. |
| B7 | **Thermals / 60 fps** | medium | This is a laptop host with a history near 80 °C; the perf matrix was waived. The recorder still writes 60 fps, but the game may repeat frames if it drops below 60. Record `nvidia-smi` before/after and state whether the render held 60; never call duplicated frames a native 60 fps render. |
| B8 | **Steam Cloud** | medium | The throwaway save could sync to the owner's cloud and later overwrite the real progression. **Disable Steam Cloud for 3341000 before the run** and keep it off until the copy is deleted. The original save is preserved inside the copy as `SaveGames.pre-p0b-*`. |
| B9 | **`/tmp` is ephemeral** | low | The prefix copy is on tmpfs and disappears at reboot. Re-run `p0b_live_capture.sh copy` if `/tmp/opencode/tat2-ref-prefix` is gone; never point the launch at the original prefix. |
| B10 | **Proton drift** | medium | Steam may update Proton Experimental. The prep baseline is `experimental-11.0-20261112-x86_64` / prefix `11.0-100`. If the version changed, stop: the renderer is no longer the prepared one. |
| B11 | **Steam overlay / notifications** | low | Disable the Steam overlay and notifications for the app, or they will appear in the lossless capture. |

**Safest path:** close GPU apps → preflight READY → copy/verify/stage → disable
Cloud/overlay → record hashes → **Go Offline** → launch with the copied prefix →
verify the copy is in use → set 1440p/60/100 % in-game → warm-up → capture → hash.
If any of B1/B2/B10 is not satisfied, **stop and wait for the owner**; a wrong build
or the original prefix makes the reference worthless and may lose the owner's save.

---

## 4. What was already done (and what was not)

Done, in this lane:

1. Copied the prefix to `/tmp/opencode/tat2-ref-prefix` (775 files,
   610,409,536 bytes) and verified it with `diff -r --no-dereference` (exit 0) and a
   symlink-target comparison (all match).
2. Tested the helper end-to-end on a **scratch copy**
   (`/tmp/opencode/tat2-stage-test`, deleted after): `copy` → byte-identical,
   `stage` → `SaveGames.pre-p0b-<ts>` + archived `GameUserSettings.ini`, empty
   `SaveGames/`. The canonical copy was left untouched by `stage`.
3. Tested the lossless x11grab path on a real X window: 1600×900, 60/1, 120 frames
   over 2.000 s, `gbrp`, FLAC 48 kHz stereo.
4. Tested `verify` on a synthetic 3 s capture: two pose PNGs, SHA-256s, and
   `manifest.json` written.
5. Read the install, appmanifest, Steam state, prefix, caches and host; no Steam,
   Proton or game process was started and no install/appmanifest/prefix file was
   written.

Not done (owner/GPU step): no frame of the shipped game was captured; no settings
were changed in the original prefix; no Steam offline switch; no Steam Cloud change.

---

## 5. Manual runbook (exact)

Throughout: `ROOT` = this repo worktree; the helper is
`build/qa/p0b_live_capture.sh`.

### Step 0 — owner approval and preconditions

- Owner confirms the capture may run now (offline, new save, Steam Cloud off).
- Close Brave, VS Code, Vesktop, ptyxis, and any other GPU-heavy app. Leave Steam
  running (it must be running to launch the game).
- Free VRAM target: **≥ 5.5 GiB** (`nvidia-smi --query-gpu=memory.free --format=csv`).
  The helper hard-blocks below 4 GiB as a floor; 5.5 GiB is the recommended
  headroom for 1440p native. More is better.
- Do not reboot after this point unless you re-copy the prefix.

### Step 1 — preflight (must print READY)

```bash
cd "$ROOT"
build/qa/p0b_live_capture.sh preflight
# expected: P0B_LIVE_PREFLIGHT READY buildid=25076818
```

It checks: appmanifest `buildid/StateFlags/AutoUpdateBehavior/TargetBuildID`, the
shipping and bootstrap exe versions, Steam login/offline flag, Valve `UpToDateCheck`,
the prefix copy, Proton version, VRAM, ffmpeg `-window_id`, `xdotool`, `pulse`
monitor, disk, and that no TAT process is running. `WARN` lines are conditions the
owner must handle; `FAIL` lines block.

### Step 2 — prefix copy (already present; re-create only if missing)

```bash
build/qa/p0b_live_capture.sh verify-copy     # byte-for-byte check, pre-run only
# if missing:
build/qa/p0b_live_capture.sh copy            # refuses outside /tmp/opencode
```

Do **not** use the original prefix for the run. The copy is what isolates the new
save and protects the owner's progression.

### Step 3 — stage a throwaway save in the copy

```bash
build/qa/p0b_live_capture.sh stage
```

This moves the copy's `SaveGames/` to `SaveGames.pre-p0b-<timestamp>` (the owner's
save state as copied), creates an empty `SaveGames/`, and archives
`GameUserSettings.ini`. It does **not** edit the ini: the video settings are set
in-game because the shipped default preset is not known until the menu is read.

### Step 4 — Steam: protect the install and the save

In the Steam client, for **Thick As Thieves (3341000)**:

1. Properties → General → **Steam Cloud: off** (this app only).
2. Properties → General → **Steam Overlay: off**.
3. Settings → Notifications → disable toasts (or set the client to offline first).
4. Do **not** change `AutoUpdateBehavior` thinking it stops updates: "only update
   when I launch" still updates at launch. Offline Mode is the only reliable stop.
5. Record the appmanifest and exe hashes now:

```bash
sha256sum ~/.steam/steam/steamapps/appmanifest_3341000.acf \
          "$HOME/.steam/steam/steamapps/common/Thick As Thieves/TAT/Binaries/Win64/TAT-Win64-Shipping.exe" \
          "$HOME/.steam/steam/steamapps/common/Thick As Thieves/TAT/Binaries/Win64/vkd3d-proton.cache"* \
  | tee /tmp/opencode/p0b_build_hashes_before.txt
build/qa/p0b_live_capture.sh preflight | tee /tmp/opencode/p0b_preflight_before.txt
```

### Step 5 — Steam Offline Mode (before Play)

Steam menu → **Go Offline…** → confirm. Wait until the client shows **Offline
Mode** and the store/friends panels are unavailable. Do not press Play while the
client is online. If offline mode fails, **stop** (B1/B2).

### Step 6 — launch with the copied prefix

Properties → Launch Options:

```text
STEAM_COMPAT_DATA_PATH=/tmp/opencode/tat2-ref-prefix %command%
```

Press **Play**. This is the standard Proton prefix override used with Steam launch
options; step 7 proves it took effect. If Steam ignores it, **stop** — do not fall
back to the original prefix. No other flags: no `-dx12` (DX12 is the default path),
no `PROTON_ENABLE_WAYLAND` (keep X11 so x11grab sees the window), no mods.

### Step 7 — prove the copy is in use (do this within the first minute)

In another terminal:

```bash
stat -c '%y %n' /tmp/opencode/tat2-ref-prefix/pfx/system.reg \
                 /tmp/opencode/tat2-ref-prefix/pfx/user.reg \
                 ~/.steam/steam/steamapps/compatdata/3341000/pfx/system.reg
```

- The **copy's** `system.reg`/`user.reg` mtimes must be **now**.
- The **original** prefix's `system.reg` mtime must stay **2026-11-18 15:24**.
- If the original changed, quit immediately; the run used the owner's prefix. Do
  not continue, and report it (the owner's save may have been touched).

Also confirm the new save appears:

```bash
ls -l /tmp/opencode/tat2-ref-prefix/pfx/drive_c/users/steamuser/AppData/Local/TAT/Saved/SaveGames/
# expected: a fresh TAT_ETS.sav, not the archived one
```

### Step 8 — in-game video settings (record the screen)

Settings → Video, then:

| Setting | Value |
|---|---|
| Window mode | **Windowed** (not borderless) |
| Resolution | **2560×1440** client area |
| VSync | **Off** |
| FPS limit | **60** |
| Resolution / screen percentage | **100 %** (no DLSS/FSR upscaling) |
| Quality | **Reset to the shipped default preset**; do not inherit the archived Low/42 % values |
| HDR | Off |

The copy's archived ini still says 1920×1440 / 42 % / all-Low, so the **first**
launch will inherit those values. Change them to the table above before the scored
run, then re-read the ini (or the settings screen) to confirm. Hold the settings
screen for 3 s so the recording contains the exact values.

Then check the client area really is 1440p:

```bash
WID=$(xdotool search --onlyvisible --name 'Thick As Thieves' | head -1)
xdotool getwindowgeometry "$WID"     # must print 2560x1440
```

If the window is 2560×1471 (title bar) or another size, fix it before recording;
`-window_id` captures the client window, but the geometry must be 1440p for the
comparison. If the search returns nothing, list the XWayland windows
(`xdotool search --onlyvisible --name '.'`) and use the Proton/UE window; the title
is normally `Thick As Thieves`, but the class may be `TAT-Win64-Shipping`.

### Step 9 — warm-up, then discard

Do a **warm-up run outside the scored capture**: boot → enter the Guildhall
contract → play ~60 s (move through the gate, fire the zipwire once) → return to the
menu. This warms the PSO/vkd3d caches. Then start the recorder at the Startscreen
and play the route from S01. If you cannot return to the menu, restart the game and
start recording at the Startscreen; the on-disk PSO cache survives.

The first ~120 s of any run (boot, load, shader compile) are **not** evidence and
must not be scored.

### Step 10 — lossless capture (exact command)

```bash
mkdir -p "$HOME/Videos/tat2_ref_$(date +%Y%m%d)"
build/qa/p0b_live_capture.sh capture-cmd
```

The helper prints (and does not run):

```bash
OUT="$HOME/Videos/tat2_ref_YYYYMMDD"
WID=$(xdotool search --onlyvisible --name 'Thick As Thieves' | head -1)
SINK=$(pactl get-default-sink)
xdotool getwindowgeometry "$WID"          # 2560x1440
pactl list short sources | grep "$SINK.monitor"

ffmpeg -hide_banner -y \
  -f x11grab -framerate 60 -window_id "$WID" -draw_mouse 1 -i :0.0 \
  -f pulse -i "$SINK.monitor" \
  -map 0:v -map 1:a \
  -c:v libx264rgb -qp 0 -preset ultrafast -pix_fmt bgr0 -fps_mode cfr -r 60 \
  -c:a flac -ar 48000 -ac 2 \
  -t 420 "$OUT/route_lossless.mkv"
```

- `-qp 0` + `bgr0` is mathematically lossless RGB; `ffprobe` must report
  `pix_fmt=gbrp`, `avg_frame_rate=60/1`. This was verified on a real X window.
- `-draw_mouse 1` keeps the cursor, as in the official clip.
- `-t 420` covers the 3:45 route plus six 3 s holds and pauses; stop early with `q`.
- **Test the first 10 s** (`-t 10` to a scratch file) and check the frame is not
  black before committing to the full run. If `-window_id` yields black (XWayland
  compositor edge case), use the region fallback in §3 B4.
- Do not run OBS, another ffmpeg, or any GPU capture at the same time.
- Record `nvidia-smi --query-gpu=name,driver_version,memory.used,clocks.current.graphics,temperature.gpu --format=csv`
  before and after into `$OUT/gpu_before.csv` / `gpu_after.csv`.

### Step 11 — play the 27-beat route

The route is the official §9.1 script. Play it in this order; the times are the
official anchors, used only to find the beats, not to force clock alignment.

| # | Seg (official ts) | Beat |
|---|---|---|
| 1 | S01 00:00.00 | Startscreen; let the neon flicker play; hover `PLAY`. |
| 2 | S02 00:02.15 | Click `PLAY`; record the loading art. |
| 3 | S03 00:02.60 | Enter the Thieves' Den; walk the attic pan toward the mirror. |
| 4 | S04 00:06.57 | Wardrobe: browse `Zipwire`, `Head` (`Bowler Hat`→`Cap`), `Body` (`Classic`), slots 1–4, slot-3 drawer, `Vistara Diamond`, `Pickpocket Fairy`; close. |
| 5 | S05 00:20.23 | Telescope `[F] PONDER`, hold the sky ~1.5 s, `[F] EXIT`; 5 Wanted posters; walk to the desk. |
| 6 | S06 00:26.58 | `[F] READ LEDGER`; `JOURNAL`; `BLACK MARKET`; hover the 9 listed items; re-open `JOURNAL`; close. |
| 7 | S07 00:44.40 | `[F] CHANGE DECORATION` (owl→spider chest); cross the boot-trail decals; `[F] TURN ON` the Gramophone; cycle trunk treasures; map table. |
| 8 | S08 00:51.50 | Inspect `ELWAY MANOR` then `CONSTABLES' GUILDHALL`; keep `Novice`/`Solo`; `[F] ENTER MATCH`; `[SPACE] PREPARE FOR MISSION`. |
| 9 | S09 00:56.08 | Mission Prep: toggle `[F] READY`; let the 6 s countdown run out. |
| 10 | S10 01:04.80 | Record the second loading screen. |
| 11 | S11 01:09.44 | Dismiss the Briefing Letter with `[SPACE] CONTINUE`. |
| 12 | S12 01:10.81 | Safe room: `[F] TURN ON` the lantern; view the Escape Portal; exit to the catwalk; vault into the alley. |
| 13 | S13 01:20.10 | Pass `BARRON'S DEMOLITION`; sprint the wet cobbles; crouch; `[F] INTERACT` the car (honk + headlights); approach the gate. |
| 14 | S14 01:39.30 | Equip ZipWire `[1]`; frame the gate; fire the 1st zipwire; land in the planter foliage beside the chest. |
| 15 | S15 01:49.50 | Aim at the roof ridge; fire the 2nd zipwire; crank to the roof. |
| 16 | S16 01:58.50 | Traverse the roofline; crank onto the chimney block; pass the winch; fire the 3rd zipwire to the gate pillar. |
| 17 | S17 02:11.00 | Cross the cable; land by the gear plate; drop to the courtyard (take the fall damage). |
| 18 | S18 02:23.30 | Equip Smoke Bomb `[2]`; pass the crates/griffins; throw onto the grand stairs; watch the plume. |
| 19 | S19 02:31.40 | Equip Vistara Diamond `[4]`; scan the constable (RED→GREEN); swap back to `[1]`. |
| 20 | S20 02:33.00 | Traverse the side wing past `MACLEOD` to the garden terrace. |
| 21 | S21 02:55.00 | Enter the side portico; `[F] OPEN` the blue double doors; inspect the scaffolding; walk through. |
| 22 | S22 03:05.80 | Cross to the Fireplace Parlor; crouch behind the constable; `[F] PICK POCKET` the `Guildhall Key`. |
| 23 | S23 03:17.40 | Immediately `[F] [HOLD] TAKEDOWN` the constable. |
| 24 | S24 03:24.00 | Cross the parlor into the marble foyer; approach the beams without crossing. |
| 25 | S25 03:29.00 | Cross the foreground beam (ward lockdown); turn past `WC` toward the stairwell emitter. |
| 26 | S26 03:38.20 | Ascend the slate staircase under the crimson alarm to the upper landing. |
| 27 | S27 03:41.90 | Open the Pause Menu; hover `QUIT TO DESKTOP` (stop recording before quitting; PG-1 teardown). |

Do not change difficulty, mode or settings mid-run. The official run is
`CONSTABLES' GUILDHALL — Cleanout Heist`, `Novice`, `Solo`.

### Step 12 — the six fixed poses (plus the KF18 still)

Hold each fixed pose for **3 s** (still camera, HUD on) so the frame is stable. The
port coordinates below are **reference cues** from the existing W9 capture poses and
the measured Guildhall level data (not Lane I teleport targets); navigate by the
geometry/content in the shipped map.

| Pose | Anchor | Where / framing | Port coordinate cue | Hash |
|---|---|---|---|---|
| `gate` | KF16 01:40.20 | Alley side of the wrought-iron `CONSTABLE'S GUILDHALL` arch; guard with red eyes/alert bar, car headlights right, ZipWire `[1]` equipped, HUD on | alley gate approach (content cue; no single authored point) | `pose_gate.png` |
| `kf18_overlook` | KF18 02:14.80 | Mid-cable over the arch: crowned pillars, twin griffins, distant green guard; **moving shot** — extract the still; do not try to freeze the cable | cable from the gate pillar to the roof | `pose_kf18_overlook.png` |
| `upper_foyer` | KF27 03:27.60 | Foyer threshold, look down the hall; checkered marble, glass vitrine, armchair/ottoman, two beams, cyan ceiling node | eye `(27, 29.67, -50)` → `(27, 29.67, -60)` | `pose_upper_foyer.png` |
| `yaw180` | KF27 +0.5 s | Same eye, turn **180°**; the reverse foyer view (beam diagonal) | eye `(27, 29.67, -50)` → `(27, 29.67, -40)` | `pose_yaw180.png` |
| `lounge` | new pose (not in the official clip) | Guildhall ground-floor Lounge, stand at the east doorway and look west into the room; tiled floor, C_20 bouncer, room dressing | eye `~(43.7, 27.05, -26.2)`; the `poi-lounge-floor` tiled meshes span x 21.98–39.50, z −43.0…−11.0; courier `(35.9, 27.0, -22.7)` faces −X | `pose_lounge.png` |
| `lounge_beam` | new pose | From the Lounge doorway, frame the Lounge beam/emitter; two crisp white beams if both are in view | beam card `(42.34, 28.9, -28.97)` | `pose_lounge_beam.png` |
| `beam_close` | KF27 beam | 2–3 m from the left-wall emitter in the foyer: emitter at **x≈17.8 %, y≈40 %** of frame, two horizontal white beams wall-to-wall, cyan ceiling diamond above the far doors | foyer beam `(23.27, 29.76, -57.4)` from `(27, 29.67, -55)` | `pose_beam_close.png` |

The official framing references are `docs/reference/clip_1795033698901/clean/`:
`KF16_01m40s_zipwire_gate_headlights.jpg`,
`KF18_02m14s_guildhall_arch_overlook.jpg`,
`KF27_03m27s_foyer_security_beam.jpg`. Open them side by side while framing.

For each hold, note the capture timestamp (seconds in `route_lossless.mkv`) and
write it into `poses.tsv`:

```text
name<TAB>seconds<TAB>note
gate<TAB>12.4<TAB>KF16 gate hold
...
```

### Step 13 — verify and hash

```bash
cd "$ROOT"
P0B_CAPDIR="$HOME/Videos/tat2_ref_YYYYMMDD" build/qa/p0b_live_capture.sh verify
```

Expected output: `P0B_LIVE_VERIFY PASS poses=N video_sha256=…`, plus
`manifest.json` in the capture dir containing:

- the capture SHA-256, codec/`gbrp`, 60/1, size/duration;
- GPU/driver, session, sink;
- appmanifest buildid/sha256 and shipping exe sha256/version;
- Proton version and prefix path;
- per-pose PNG SHA-256 and timestamps.

Then verify the **build in-game**: pause menu footer must read
`1.5.148559` and `Novice`; the seed will be **new** (the official footer seed
`1025051536` belongs to the official save — do not expect it). Capture the footer
crop and hash it:

```bash
ffmpeg -v error -ss <footer_t> -i "$OUT/route_lossless.mkv" -frames:v 1 -f image2 -c:v png "$OUT/footer.png"
sha256sum "$OUT/footer.png"
# read it: 1.5.148559   Novice   <new seed>
```

Record the frame hashes in the wave report; they prove file integrity, **not**
pixel equality with the official frames. Score the look with Lane I's
`p0b_roi_stats.py` (luma percentiles, beam rows, cream map), never by hash equality.

### Step 14 — cleanup / rollback

- Stop the game, return Steam online only after the capture is verified.
- Keep Steam Cloud **off** for 3341000 until the copy is deleted, so the throwaway
  save cannot overwrite the real one.
- Delete `/tmp/opencode/tat2-ref-prefix` only after the manifest is recorded and
  cited; the original prefix and save were never touched (verify the original `system.reg`
  mtime is still 2026-11-18 15:24).
- Re-hash the appmanifest and `vkd3d-proton.cache*`; record any change. The game
  appending to its cache is expected; an appmanifest `buildid` change is not.

---

## 6. Abort conditions (stop, do not improvise)

| Condition | Why |
|---|---|
| Steam is online when you press Play | Auto-update can replace 1.5.148559. |
| `buildid` ≠ 25076818, `TargetBuildID` ≠ 0, or `UpToDateCheck` false | The install is no longer the reference build. |
| Offline Mode fails or Steam asks for a password/Steam Guard | Do not go online mid-run. |
| The **original** prefix's `system.reg` mtime changes | The launch used the owner's prefix; the save may have been touched. |
| Proton Experimental version ≠ `experimental-11.0-20261112-x86_64` | Renderer drift; the prepared baseline no longer applies. |
| VRAM free < 4 GiB, or `nvidia-smi` shows thrash/OOM | The 1440p capture will stutter or fail. |
| Client area ≠ 2560×1440 after the setting change | The comparison would be at the wrong resolution. |
| `-window_id` capture is black | Use the region fallback; never switch to a lossy codec. |
| Steam Cloud prompts to sync the new save | Disable Cloud, do not upload; the owner's progression is at risk. |

---

## 7. What the integrator gets back

- `route_lossless.mkv` (lossless 1440p60 + FLAC system audio) in
  `~/Videos/tat2_ref_<date>/` (git-ignored; not committed).
- `manifest.json` with video + pose hashes, build id, exe version, Proton version,
  GPU/driver and sink.
- The six pose PNGs + the KF18 still + the pause-footer crop, with hashes.
- The pre/post `appmanifest`/`vkd3d` hash file and the preflight log.
- A short note: did the render hold 60 fps, what was the peak VRAM, any captured
  settings drift.

No capture exists yet; this lane makes no visual claim. The 120-row baseline is
scored only after the owner runs this plan and Lane I's ROI stats consume the
frames.
