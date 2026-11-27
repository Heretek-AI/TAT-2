# P0b Lane L — live reference: offline attempt, restore, online runbook

> **MEASURED 2026-11-26 — the shipped build will not run in Steam Offline Mode.**
> With `WantsOfflineMode=1`, build `25076818` reached the launcher's
> `LOGIN FAILED!` with only `QUIT`; the launcher requires an online login. This
> *disproves* the offline-first assumption in the preparation below; the
> pre-attempt Steps 5–7 are rewritten in §5. The machine was restored afterwards (original prefix
> active, `WantsOfflineMode=0`, save hash unchanged); no capture was taken.
> The A path (copied install + direct Proton launch) worked on 2026-11-27; the
> capture review (`docs/reports/live-ref-review-20261127.md`) found the Staff
> mission, not the Cleanout. See
> [`HANDOFF_NEXT_AGENT.md`](../HANDOFF_NEXT_AGENT.md) §0/§4.1.

**Status:** the preparation pass ran 2026-11-26; the offline attempt failed and the
machine was restored. On 2026-11-27 the **A path worked** (direct Proton launch of
the copied install/prefix, startscreen reached, prefix isolation proven). The
capture is the **Staff of Edinburgh Item Collection Heist**, not the Cleanout
Heist; see `docs/reports/live-ref-review-20261127.md`. **No valid Cleanout live
reference exists yet.** The next run is **one 900 s lossless file**, started at
the main menu, with Master/Music/SFX/Dialogue **80** and the poses held 3 s
(issue **#13**). The preparation lane's state and the attempt's side
effects are in §1.1.

**What exists now:** the appid 3341000 Proton prefix copied and byte-verified at
`/tmp/opencode/tat2-ref-prefix` (**774 files**), with the owner save explicitly
restored into `SaveGames/` (Phase 0a, 2026-11-27: `TAT_ETS.sav` md5
`976f8730eac989bab1c6c792343b7c00`, copied from
`SaveGames.pre-p0b-20261126-230522/`; the archive is untouched), and the tracked
helper [`build/qa/p0b_live_capture.sh`](../../build/qa/p0b_live_capture.sh). The
helper never launches anything; it only checks, copies, stages the copy, prints
the capture command and hashes the result.

The reference target is the **shipped UE5.5 build** `1.5.148559` (Steam appid
3341000). The port capture (Lane I) uses fixed poses; the live capture takes the
same poses in the shipped game at **2560×1440, 60 fps, 100 % screen percentage**,
lossless, with system audio. It is a matched-settings reference for P4/ROI; the
120-row scorecard's official observations come from the official clip and the 30
keyframes, not from this capture.

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
| Last written | 2026-11-18 15:24 (`pfx/system.reg`; pre-attempt, see §1.1) | copy of that state |
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
| Disk | `/home` **126 G** free; `/tmp` 32 G tmpfs, **9.1 G** free (not for video); `~/Videos` **52 G** used |
| Capture test | a real (non-game) 1600×900 X window, 60 fps, **120 frames / 2.000 s**, `libx264rgb -qp 0`, `pix_fmt=gbrp`, FLAC 48 kHz stereo — the command path works |

### 1.1 Current state after the offline attempt (2026-11-26)

The table above is the preparation baseline. The attempt changed only the
following, and this is the state the next run starts from:

- the original prefix's `pfx/system.reg`/`user.reg` were rewritten at
  **2026-11-26 23:06** (the launch option did not redirect Proton); save and
  config hashes are unchanged;
- `vkd3d-proton.cache` grew **1,743,312 → 1,744,384 B**; the `.write` sidecar is
  now **0 B**, so the 1,120 B value above is historical;
- the canonical copy is **staged**: **774 files**, and `SaveGames/` has the
  owner save **restored explicitly** from the archive
  `SaveGames.pre-p0b-20261126-230522/` (Phase 0a, 2026-11-27; `TAT_ETS.sav`
  md5 `976f8730…`; the archive is untouched). Earlier in this lane the copy was
  771 files with `SaveGames/` holding only `EnhancedInputUserSettings.sav`;
  after the restore `TAT_ETS.sav`, `EnhancedInputUserSettings.sav` and
  `steam_autocloud.vdf` are all present;
- `/home` free is **126 G** (not 188 G); `~/Videos` is **52 G**; `/tmp` is
  **9.1 G** free; VRAM free measured **5,143 MiB**;
- `verify-copy` now **FAILs** on file count by design; it is only meaningful
  before `stage`.

Do not re-copy the prefix to silence `verify-copy`; the staged state is what the
next run wants. Do not use the 2026-11-18 prefix mtimes as the isolation
baseline — snapshot them immediately before the next launch.

---

## 2. Why Offline Mode is not a capture path, and what protects the build

> **MEASURED 2026-11-26:** Offline Mode avoids the update, but the shipped
> launcher then refuses to log in — `WantsOfflineMode=1` produced `LOGIN FAILED!`
> with only `QUIT`. Offline Mode is retired. The port itself is unaffected; this
> is a launcher constraint.

As of the last check the install is still the reference build and no update is
queued: `buildid=25076818`, `TargetBuildID=0`, `StateFlags=4`, Valve
`up_to_date:true`, exe `1.5.193.148559`, appmanifest unchanged since 2026-11-18.
That is a point-in-time fact, not a control: `AutoUpdateBehavior=0` ("always
keep this game up to date") means an online **Steam Play** will update as soon as
a new build is published, and the client runs its own update check at launch.
Once a download starts, the reference is gone.

**Protection must be structural.** Choose one:

1. **Copied install + direct Proton launch (recommended, not yet measured).**
   Copy the 3.8 GB install to a private path and launch the copy's
   `TAT-Win64-Shipping.exe` under Proton with the copied prefix. Steam stays
   online for authentication only and **never launches the app**, so the
   updater is not in the path and the managed install cannot be replaced. The
   open question is whether the shipping exe initialises SteamAPI without the
   `TAT.exe` launcher; Step 6A is the test. If it fails, stop — do not fall back
   to Steam Play without the owner's approval.
2. **Steam Play with the prefix swapped (fallback).** Stop Steam, snapshot the
   install and appmanifest, swap the prefix, start Steam online and press Play.
   This accepts a small update race; abort on any `buildid`/appmanifest change.
3. **No shipped launch.** Score the 120 rows from the official clip and its 30
   keyframes, marking live-only rows `UNVERIFIED`. The official clip is on disk
   (`~/Videos/clip_1,795,033,698,901.mp4`, 3840×2160 @ 29.67 fps, 225.5 s), and
   the keyframes are the ones the scorecard already uses. This does not need a
   capture and should not wait for one.

The run itself still writes two non-code things: Steam updates the appmanifest
`LastPlayed` state, and the game appends `vkd3d-proton.cache*` inside the
**prefix/install it is actually using**. Hash both before and after and record
the deltas. An appmanifest `buildid` change is not acceptable; a cache append is
expected.

---

## 3. Blockers and the safest path

| # | Blocker | Severity | Measured / action |
|---|---|---|---|
| B1 | **Steam sign-in** | **high** | The launcher requires an **online** login; Offline Mode gives `LOGIN FAILED!`. Start Steam online and confirm the account is logged on (`RememberPassword=1`). If Steam asks for a password or Steam Guard, stop. |
| B2 | **Auto-update** | **high** | `AutoUpdateBehavior=0`. Offline Mode is not available, so the update must be kept out of the path: copied install + direct Proton launch (A), or a pre-run install snapshot + prefix swap (B). Abort on any `buildid`/appmanifest change. |
| B3 | **VRAM** | **high** | 8188 MiB total; **5,143 MiB free** at the last check. Close Brave, VS Code, Vesktop, ptyxis and every other GPU app; target **≥ 5.5 GiB free**. The helper blocks below 4 GiB; **a READY verdict below 5.5 GiB is not sufficient for a scored 1440p run**. Watch `nvidia-smi dmon`; if it thrashes, stop. |
| B4 | **Wayland / XWayland** | medium | Session is Wayland; Proton renders through XWayland (`DISPLAY=:0`). `x11grab -window_id` was verified on a 1600×900 X window (120 frames / 2 s). Verify on the *game* window with a 10 s test; fallback: window at 0,0 and `-video_size 2560x1440 -i :0.0+0,0`. Do not switch to a lossy encoder. |
| B5 | **Audio routing** | low | Default sink is HDMI with a monitor source. If the game selects the USB headset, set it as the default and capture its `.monitor`. Close all other audio sources. |
| B6 | **Disk** | medium | The 2026-11-27 capture measured **~45 MB/s** (27 GB / 600 s); a 900 s run is **~40 GB**. `/home` has **126 G** free and `~/Videos` already holds **52 G**; `/tmp` has **9.1 G** free (never capture there). Budget **2×** the measured projection, and delete the old video parts if needed. Gate on free ≥ 2× the projected size. |
| B7 | **Thermals / 60 fps** | medium | Laptop host with a history near 80 °C; the perf matrix is waived. The recorder writes 60 fps, but the game may repeat frames if it drops below 60. Record `nvidia-smi` before/after and state whether the render held 60; duplicated frames are not a native 60 fps render. |
| B8 | **Steam Cloud** | **high** | If the capture uses a copy of the owner's save, a Cloud sync could overwrite the real progression. **Disable Steam Cloud for 3341000 before the run** and keep it off until the copied prefix is deleted. This setting is in the client, not `localconfig.vdf`. |
| B9 | **`/tmp` is ephemeral** | medium | The prefix copy (590 M) is on tmpfs and disappears at reboot; the install copy is on `/home`. Re-run `copy` if the prefix is gone; never point the launch at the original prefix. |
| B10 | **Proton drift** | medium | Baseline `experimental-11.0-20261112-x86_64` / prefix `11.0-100`. If the version changed, stop. A direct launch (A) pins the Proton path; Steam Play (B) does not. |
| B11 | **Steam overlay / notifications** | low | Disable the overlay and toasts for 3341000, or they appear in the lossless capture. |
| B12 | **Save progression** | **high** | The official route's S06/KF07–KF08 rows assume the official save: Level 4, XP 94/500, Contracts #1–#2 completed, £26,275, purchased Black Market checks. An empty save changes those rows. Restore the archived owner save into the copy (recommended) or pre-declare those rows as save-state deltas — never score them as port deltas. |
| B13 | **Prefix-isolation proof** | **high** | The launch option `STEAM_COMPAT_DATA_PATH=... %command%` did **not** redirect Proton. Snapshot the original prefix's `system.reg`/`user.reg` mtimes before launch and compare after; a post-hoc "within the first minute" check is too late. |

**Safest path:** close GPU apps → preflight READY (VRAM ≥ 5.5 GiB) → choose A or
B (§2) → snapshot hashes → for A: copy the install and prove the direct launch
on the copy; for B: stop Steam, snapshot the install, swap the prefix → disable
Cloud/overlay → record the save state → launch → prove the copy/prefix is in use
→ set 1440p/60/100% → warm-up → capture → hash. If any of B1/B2/B10/B13 is not
satisfied, **stop**; a wrong build or the original prefix makes the reference
worthless and may lose the owner's save.

---

## 4. What was already done (and what was not)

Done, in this lane:

1. Copied the prefix to `/tmp/opencode/tat2-ref-prefix` (775 files,
   610,409,536 bytes) and verified it with `diff -r --no-dereference` (exit 0) and a
   symlink-target comparison (all match).
2. Tested the helper end-to-end on a **scratch copy**
   (`/tmp/opencode/tat2-stage-test`, deleted after): `copy` → byte-identical,
   `stage` → `SaveGames.pre-p0b-<ts>` + archived `GameUserSettings.ini`, empty
   `SaveGames/`. The canonical copy was later staged for the attempt and then
   explicitly restored in Phase 0a: **774 files** with the owner save present
   (see §1.1).
3. Tested the lossless x11grab path on a real X window: 1600×900, 60/1, 120 frames
   over 2.000 s, `gbrp`, FLAC 48 kHz stereo.
4. Tested `verify` on a synthetic 3 s capture: two pose PNGs, SHA-256s, and
   `manifest.json` written.
5. Read the install, appmanifest, Steam state, prefix, caches and host; no Steam,
   Proton or game process was started and no install/appmanifest/prefix file was
   written.

Not done by the preparation lane (owner/GPU step): no frame of the shipped game
was captured; no settings were changed in the original prefix; no Steam offline
switch; no Steam Cloud change. The later offline attempt is recorded in §2; it
did launch the game, failed at the launcher, and was reverted (§1.1).

---

## 5. Manual runbook (exact)

Throughout: `ROOT` = this repo worktree; the helper is
`build/qa/p0b_live_capture.sh`.

### Step 0 — decision and preconditions

- Owner picks **A** (copied install + direct Proton launch), **B** (Steam Play
  with the prefix swapped), or **C** (no shipped launch) from §2. Do not press
  Play until the choice is recorded; Offline Mode is not a fallback.
- Close Brave, VS Code, Vesktop, ptyxis, and any other GPU-heavy app. Steam must
  be running **online** and logged on for the launcher.
- Free VRAM target: **≥ 5.5 GiB** (`nvidia-smi --query-gpu=memory.free --format=csv`).
  The helper hard-blocks below 4 GiB as a floor; a READY verdict at 4–5.5 GiB is
  not enough for a scored 1440p run.
- Free disk: project the **900 s** size from a 10 s test and require **≥ 2×** it.
  The 2026-11-27 capture measured ~45 MB/s (27 GB / 600 s), so 900 s is ~40 GB;
  `/home` has **126 G** free, `~/Videos` holds **52 G**, and `/tmp` has **9.1 G**
  free. Never capture to `/tmp`.
- Do not reboot after this point unless you re-copy the prefix (it is on tmpfs).

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

A `WARN` that Steam is **online** is expected and correct now: the launcher needs
the online login. `verify-copy` is only meaningful **before** `stage`; the current
copy is staged, so its file-count failure is by design (§1.1).

### Step 2 — prefix copy (already present; re-create only if missing)

```bash
build/qa/p0b_live_capture.sh verify-copy     # only meaningful BEFORE stage
# if missing:
build/qa/p0b_live_capture.sh copy            # refuses outside /tmp/opencode
```

The canonical copy is **already staged and restored** (**774 files**; `SaveGames/`
holds `TAT_ETS.sav` md5 `976f8730…`), so `verify-copy` now FAILs on file count.
That is the expected state, not corruption; do not re-copy to silence it.
Do **not** use the original prefix for the run.

### Step 3 — save state (choose once)

`stage` archives the copied save to `SaveGames.pre-p0b-<timestamp>` and leaves an
empty `SaveGames/`. That is the right isolation move, but an empty save changes
the official route's progression rows (B12): S06/KF07–KF08 assumes Level 4, XP
94/500, Contracts #1–#2 completed, £26,275 and purchased Black Market checks.

- **Recommended:** restore the archived copy into the live `SaveGames/` so the
  run starts from the owner's progressed state (the archive stays untouched).
  **Already done in Phase 0a (2026-11-27); do it again only if `SaveGames/` is
  empty.** Use the explicit archive path — never `stage` + `tail -1`:

  ```bash
  P=/tmp/opencode/tat2-ref-prefix/pfx/drive_c/users/steamuser/AppData/Local/TAT/Saved
  ARCH="$P/SaveGames.pre-p0b-20261126-230522"
  cp -a "$ARCH/." "$P/SaveGames/"
  ls -l "$P/SaveGames/"          # TAT_ETS.sav must be present
  md5sum "$P/SaveGames/TAT_ETS.sav" "$ARCH/TAT_ETS.sav"   # both 976f8730eac989bab1c6c792343b7c00
  ```

  Measured Phase 0a state: prefix **774 files**, save md5
  `976f8730eac989bab1c6c792343b7c00`, archive untouched.

- **Alternative:** keep the empty save and pre-declare S06/KF07–KF08 and the
  footer/level rows as save-state deltas in the scorecard. Never score them as
  port deltas.

Do not re-run `stage` after restoring: it would archive the restored save and
empty the directory again. Record the footer seed, level, contracts and asset
total before the run. If the save is the owner's, **Steam Cloud must be off**
(Step 4).

### Step 4 — Steam: protect the save and record the build

In the Steam client, for **Thick As Thieves (3341000)**:

1. Properties → General → **Steam Cloud: off** (this app only). Mandatory if the
   run uses a copy of the owner's save.
2. Properties → General → **Steam Overlay: off**.
3. Settings → Notifications → disable toasts (Steam stays online).
4. Do **not** rely on `AutoUpdateBehavior` to stop updates: "only update when I
   launch" still updates at launch. Protection is the copied install (A) or the
   pre-run snapshot + prefix swap (B), not a preflight check.
5. Record the appmanifest and exe hashes now, and snapshot the original prefix's
   mtimes (the 2026-11-18 value is gone; the failed attempt wrote them at
   2026-11-26 23:06):

```bash
sha256sum ~/.steam/steam/steamapps/appmanifest_3341000.acf \
          "$HOME/.steam/steam/steamapps/common/Thick As Thieves/TAT/Binaries/Win64/TAT-Win64-Shipping.exe" \
          "$HOME/.steam/steam/steamapps/common/Thick As Thieves/TAT/Binaries/Win64/vkd3d-proton.cache"* \
  | tee /tmp/opencode/p0b_build_hashes_before.txt
stat -c '%y %n' \
  ~/.steam/steam/steamapps/compatdata/3341000/pfx/system.reg \
  ~/.steam/steam/steamapps/compatdata/3341000/pfx/user.reg \
  | tee /tmp/opencode/p0b_prefix_mtimes_before.txt
build/qa/p0b_live_capture.sh preflight | tee /tmp/opencode/p0b_preflight_before.txt
```

### Step 5 — choose the protection path (no Offline Mode)

Offline Mode is retired: it gives `LOGIN FAILED!`. Pick one:

- **A — copied install + direct Proton launch (recommended, unproven):** Steam
  stays online for auth, but it never launches the app, so the updater cannot
  replace the reference. The test is Step 6A. The open question is SteamAPI init;
  if the shipping exe will not start without `TAT.exe`, stop.
- **B — Steam Play + prefix swap (fallback):** stop Steam fully, confirm
  `compatdata/3341000.orig-p0b` does not already exist, snapshot the install
  (`cp -a` the 3.8 GB directory to `/home/john/tat2-ref-build`), move the original
  prefix to `compatdata/3341000.orig-p0b`, and `cp -a` the staged copy into
  `compatdata/3341000`. Then start Steam online and press Play. This accepts a
  small update race; abort on any appmanifest/buildid change.

If neither is acceptable, choose **C** and do not launch: re-score the 120 rows
from the official clip/keyframes and mark live-only rows `UNVERIFIED`.

### Step 6 — launch

**6A — direct Proton launch (A):**

```bash
REF="$HOME/tat2-ref-build"
# REF must not already exist; if it does, remove that disposable copy first
# (cp -a into an existing directory would nest a second Thick As Thieves/).
cp -a "$HOME/.steam/steam/steamapps/common/Thick As Thieves" "$REF"
printf '3341000' > "$REF/TAT/Binaries/Win64/steam_appid.txt"
# Steam online and logged on; do NOT press Play in the client.
cd "$REF/TAT/Binaries/Win64"
STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam/steam" \
STEAM_COMPAT_DATA_PATH=/tmp/opencode/tat2-ref-prefix \
STEAM_COMPAT_INSTALL_PATH="$REF" \
SteamAppId=3341000 SteamGameId=3341000 \
"$HOME/.steam/steam/steamapps/common/Proton - Experimental/proton" run \
  "$REF/TAT/Binaries/Win64/TAT-Win64-Shipping.exe"
```

**Not yet measured on this host.** Success = the startscreen appears (no
`LOGIN FAILED!`) and the copy's prefix writes while the original's do not
(Step 7). If it fails, stop; do not silently switch to B.

**6B — Steam Play (B, only after Step 5's snapshot and swap):**

Press **Play**. No other flags: no `-dx12`, no `PROTON_ENABLE_WAYLAND` (keep X11
so x11grab sees the window), no mods. The launch option
`STEAM_COMPAT_DATA_PATH=... %command%` is **retired**; it did not redirect Proton.

### Step 7 — prove the copy is in use (before the first save)

Do this **before** the game writes a save. Use the Step 4 snapshot.

**A — the copy is the explicit prefix; the original is `compatdata/3341000`:**

```bash
P=/tmp/opencode/tat2-ref-prefix
stat -c '%y %n' "$P/pfx/system.reg" "$P/pfx/user.reg" \
  ~/.steam/steam/steamapps/compatdata/3341000/pfx/system.reg
```

**B — the copy is now `compatdata/3341000`; the original is `.orig-p0b`:**

```bash
stat -c '%y %n' ~/.steam/steam/steamapps/compatdata/3341000/pfx/system.reg \
  ~/.steam/steam/steamapps/compatdata/3341000.orig-p0b/pfx/system.reg
```

- The prefix the game is using must have mtimes **newer than the Step 4
  snapshot** (A: the copy; B: `compatdata/3341000`).
- The original prefix (A: `compatdata/3341000`; B: `.orig-p0b`) must be
  **unchanged**.
- If the original changed, quit immediately; the run used the owner's prefix. Do
  not continue, and report it (the owner's save may have been touched).

Also confirm the expected save state:

```bash
ls -l "$P/pfx/drive_c/users/steamuser/AppData/Local/TAT/Saved/SaveGames/"
md5sum "$P/pfx/drive_c/users/steamuser/AppData/Local/TAT/Saved/SaveGames/TAT_ETS.sav"
# expected: TAT_ETS.sav present, md5 976f8730eac989bab1c6c792343b7c00
# alternative: empty (fresh save) — then record the progression deltas (B12)
```

### Step 8 — in-game video settings (record the screen)

Settings → Video, then:

| Setting | Value |
|---|---|
| Window mode | **Windowed** (not borderless) |
| Resolution | **2560×1440** client area |
| VSync | **Off** |
| FPS limit | **60** |
| Resolution / screen percentage | **100 %** (no DLSS/FSR upscaling). Set the quality preset **first**, then set this to 100; the High preset defaults to 71 %, so a `Custom` label at 100 % is expected. |
| Quality | **Reset to the shipped default preset**; do not inherit the archived Low/42 % values. The measured 2026-11-27 preset is all quality groups 2 (High) at scale 100. |
| Audio | Master / Music / SFX / Dialogue **80** (or the level that keeps a 10 s test max below −1 dBFS); record the values. The 2026-11-27 route peaked at **0.0 dBFS** at Master 100 (clipping), so 100 is not a valid audio reference. |
| HDR | Off |

The copy's archived ini still says 1920×1440 / 42 % / all-Low, so the **first**
launch will inherit those values. Change them to the table above before the scored
run, then re-read the ini (or the settings screen) to confirm. Hold the settings
screen for 3 s **or** take a settings still; hash it. Record the **quality
preset** and the actual client area in the run note. Measured 2026-11-27: the
High preset sets `ResolutionQuality=71`; re-set the scale to 100 afterwards; the
resulting settings screen reads `Custom` with View Distance/Shadows/Textures High
and scale 100, which is the intended High quality at 100 %. The game window title
is **`TAT`**, not `Thick As Thieves`; the window search below must fall back.
2560×1440 is the target because it is the owner's last 16:9 mode (Steam
`ResolutionOverride 2560x1440`); the port harness captures 1920×1080 and the ROI
stats downsample both to 480 px, so this is a detail superset, not a pixel match.
If the host cannot hold 1440p at 60, stop — do not silently drop to 1080p.

Then check the client area really is 1440p:

```bash
WID=$(xdotool search --onlyvisible --name 'Thick As Thieves' | head -1)
[ -n "$WID" ] || WID=$(xdotool search --onlyvisible --name '^TAT$' | head -1)
xdotool getwindowgeometry "$WID"     # must print 2560x1440
```

If the window is 2560×1471 (title bar) or another size, fix it before recording;
`-window_id` captures the client window, but the geometry must be 1440p for the
comparison. If the search returns nothing, list the XWayland windows
(`xdotool search --onlyvisible --name '.'`) and use the Proton/UE window; the
measured title is `TAT` (the class may be `TAT-Win64-Shipping`).

### Step 9 — warm-up, then start the recorder

Do a **warm-up run outside the scored capture**: boot → enter the Guildhall
contract → play ~60 s (move through the gate, fire the zipwire once) → return to
the menu. This warms the PSO/vkd3d caches. If you cannot return to the menu,
restart the game; the on-disk PSO cache survives. **The warm-up is not evidence.**
Start the recorder at the Startscreen; every beat from S01 in the recording is
evidence. **Measured 2026-11-27:** the recording opened in the Den (S01/S02 absent);
confirm the first recorded frame is the startscreen, not the Den, and restart at
the main menu if it is not.

### Step 10 — lossless capture (exact command)

```bash
mkdir -p "$HOME/Videos/tat2_ref_$(date +%Y%m%d)"
build/qa/p0b_live_capture.sh capture-cmd
```

The helper prints (and does not run):

```bash
OUT="$HOME/Videos/tat2_ref_YYYYMMDD"
WID=$(xdotool search --onlyvisible --name 'Thick As Thieves' | head -1)
[ -n "$WID" ] || WID=$(xdotool search --onlyvisible --name '^TAT$' | head -1)
SINK=$(pactl get-default-sink)
xdotool getwindowgeometry "$WID"          # 2560x1440
pactl list short sources | grep "$SINK.monitor"

ffmpeg -hide_banner -y \
  -f x11grab -framerate 60 -window_id "$WID" -draw_mouse 1 -i :0.0 \
  -f pulse -i "$SINK.monitor" \
  -map 0:v -map 1:a \
  -c:v libx264rgb -qp 0 -preset ultrafast -pix_fmt bgr0 -fps_mode cfr -r 60 \
  -c:a flac -ar 48000 -ac 2 \
  -t 900 "$OUT/route_lossless.mkv"
```

- `-qp 0` + `bgr0` is mathematically lossless RGB; `ffprobe` must report
  `pix_fmt=gbrp`, `avg_frame_rate=60/1`. This was verified on a real X window.
- `-draw_mouse 1` keeps the cursor, as in the official clip.
- `-t 900` covers the 3:45 route plus six 3 s holds, reading/pauses and the recorder margin; the 2026-11-27 run exceeded 420 s. Stop early with `q`.
- **Test the first 10 s** (`-t 10` to a scratch file) and check the frame is not
  black before committing to the full run. If `-window_id` yields black (XWayland
  compositor edge case), use the region fallback in §3 B4.
- **Disk gate:** measure the 10 s file size and project it to 900 s (`bytes ×
  90`); require free ≥ 2× the projection before the full run. At the measured
  rate the full capture is ≥ 45 GB.
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

**Pre-start mission check (2026-11-27):** the map table can start the **Staff of
Edinburgh Item Collection Heist** (120-minute limit, outdoor canal-side spawn)
instead of the Cleanout Heist. Before recording, the prep must read `Cleanout
Heist` / `Time Limit: 55 minutes`, and the spawn must be the brick safe room. If
it reads `Item Collection Heist` / `120 minutes` / Staff of Edinburgh, back out
and select the `CONSTABLES' GUILDHALL` Cleanout contract. Do not start the
recorder until the prep screen confirms 55 minutes.

The route assumes the **official save's progression** for S06 (ledger/Black
Market) and the footer/level rows. If you chose the empty-save alternative in
Step 3, those rows are save-state deltas; record the difference and do not score
them as port parity.

### Step 12 — the six fixed poses (plus the KF18 still)

Hold each fixed pose for **3 s** (still camera, HUD on) so the frame is stable.
**Measured 2026-11-27:** the live capture has 0 poses present and 3 partial; the
holds were not performed. Do not skip them. The
port coordinates below are **reference cues** from the existing W9 capture poses and
the measured Guildhall level data (not Lane I teleport targets); navigate by the
geometry/content in the shipped map.

| Pose | Anchor | Where / framing | Port coordinate cue | Hash |
|---|---|---|---|---|
| `gate` | KF16 01:40.20 | Alley side of the wrought-iron `CONSTABLE'S GUILDHALL` arch; guard with red eyes/alert bar, car headlights right, ZipWire `[1]` equipped, HUD on | alley gate approach (content cue; no single authored point) | `pose_gate.png` |
| `kf18_overlook` | KF18 02:14.80 | Mid-cable over the arch: crowned pillars, twin griffins, distant green guard; **moving shot** — extract the still; do not try to freeze the cable | cable from the gate pillar to the roof | `pose_kf18_overlook.png` |
| `upper_foyer` | KF27 03:27.60 | Foyer threshold, look down the hall; checkered marble, glass vitrine, armchair/ottoman, one beam band at 40.0–40.5 %, cyan node above the far doors | eye `(27, 29.67, -50)` → `(27, 29.67, -60)` | `pose_upper_foyer.png` |
| `yaw180` | KF27 +0.5 s | Same eye, turn **180°**; the reverse foyer view (beam diagonal) | eye `(27, 29.67, -50)` → `(27, 29.67, -40)` | `pose_yaw180.png` |
| `lounge` | new pose (not in the official clip) | Guildhall ground-floor Lounge, stand at the east doorway and look west into the room; tiled floor, C_20 bouncer, room dressing | eye `~(43.7, 27.05, -26.2)`; the `poi-lounge-floor` tiled meshes span x 21.98–39.50, z −43.0…−11.0; courier `(35.9, 27.0, -22.7)` faces −X | `pose_lounge.png` |
| `lounge_beam` | new pose | From the Lounge doorway, frame the Lounge beam/emitter; two crisp white beams if both are in view | beam card `(42.34, 28.9, -28.97)` | `pose_lounge_beam.png` |
| `beam_close` | KF27 beam | 2–3 m from the left-wall emitter in the foyer: emitter at **x≈17.8 %, y≈40.0 %** of frame, **one** horizontal white band at **40.0–40.5 %** height, cyan node **above the far doors** (Phase 0a erratum; not two beams / not a ceiling diamond) | foyer beam `(23.27, 29.76, -57.4)` from `(27, 29.67, -55)` | `pose_beam_close.png` |

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

**Measured 2026-11-27:** the two-part capture has no `poses.tsv`/manifest; the
review used per-frame SHA-256. A single 900 s file is required for this verify.

Then verify the **build in-game**: the pause footer must read `1.5.148559` and
`Novice`. The seed depends on the save: a restored owner save may carry the
official `1025051536`; a fresh save will differ. Record it and do not compare it
across saves. Capture the footer crop and hash it:

```bash
ffmpeg -v error -ss <footer_t> -i "$OUT/route_lossless.mkv" -frames:v 1 -f image2 -c:v png "$OUT/footer.png"
sha256sum "$OUT/footer.png"
# read it: 1.5.148559   Novice   <seed>
```

Record the frame hashes in the wave report; they prove file integrity, **not**
pixel equality with the official frames.

Check the encoded frame size explicitly (the helper warns if the frame is not
2560×1440; this is the hard record):

```bash
ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,pix_fmt,avg_frame_rate \
  -of default=nw=1 "$OUT/route_lossless.mkv"   # 2560x1440, gbrp, 60/1
```

Score the look with Lane I's `p0b_roi_stats.py` (luma percentiles, beam rows,
cream map), never by hash equality.

### Step 14 — cleanup / rollback

- Stop the game. Steam can stay online (it was online for the launcher); return
  it to its normal state after the capture is verified.
- Keep Steam Cloud **off** for 3341000 until the copied prefix is deleted, so a
  throwaway or restored save cannot overwrite the real one.
- **A:** delete `$HOME/tat2-ref-build` and `/tmp/opencode/tat2-ref-prefix` after
  the manifest is recorded and cited. **B:** stop Steam, move the copy
  `compatdata/3341000` aside (or delete it), move
  `compatdata/3341000.orig-p0b` back to `compatdata/3341000`, and only then delete
  the copied install.
- Re-hash the appmanifest and `vkd3d-proton.cache*`; record any change. A cache
  append is expected; a `buildid` change is not.
- Verify the original prefix's mtimes are unchanged from the Step 4 snapshot (the
  old 2026-11-18 baseline is gone).

---

## 6. Abort conditions (stop, do not improvise)

| Condition | Why |
|---|---|
| Steam starts downloading an update for 3341000 | The reference build can be replaced; stop and restore from the pre-run snapshot. |
| `buildid` ≠ 25076818, `TargetBuildID` ≠ 0, or `UpToDateCheck` false | The install is no longer the reference build. |
| The launcher shows `LOGIN FAILED!`, or Steam asks for a password/Steam Guard | The online login is not ready; do not improvise a re-auth mid-run. |
| The **original** prefix's `system.reg`/`user.reg` mtimes change from the Step 4 snapshot | The launch used the owner's prefix; the save may have been touched. |
| Proton Experimental version ≠ `experimental-11.0-20261112-x86_64` | Renderer drift; the prepared baseline no longer applies. |
| VRAM free < 4 GiB, or `nvidia-smi` shows thrash/OOM | The 1440p capture will stutter or fail. |
| Free space < 2× the projected 420 s size | The lossless capture will fill the disk. |
| Client area is not 2560×1440 and the deviation is not deliberately accepted | The reference is at the wrong size for the stated spec. |
| The A direct launch does not reach the game | The direct path is disproven; stop and choose B/C with the owner. |
| `-window_id` capture is black | Use the region fallback; never switch to a lossy codec. |
| Steam Cloud prompts to sync the new/restored save | Disable Cloud, do not upload; the owner's progression is at risk. |

---

## 7. What the integrator gets back

- `route_lossless.mkv` (lossless 1440p60 + FLAC system audio) in
  `~/Videos/tat2_ref_<date>/` (git-ignored; not committed).
- `manifest.json` with video + pose hashes, build id, exe version, Proton version,
  GPU/driver and sink.
- The six pose PNGs + the KF18 still + the pause-footer crop, with hashes.
- The pre/post `appmanifest`/`vkd3d` hash file, the Step 4 prefix-mtime snapshot,
  the preflight log, and the A/B isolation proof.
- The run note: capture path (A/B), install/prefix provenance, save state (seed,
  level, contracts, assets), quality preset, actual client area, free-space
  projection, whether the render held 60 fps, peak VRAM, and any settings drift.

No **valid Cleanout** capture exists yet; this lane makes no visual claim. The
capture is a matched-settings reference for P4/ROI, not a replacement for the
official clip and keyframes, and the 120-row scorecard is re-scored from a
**port** run, not from this capture. The deferred Cleanout capture is issue
**#13** (single 900 s file, audio Master/Music/SFX/Dialogue 80, poses held 3 s).
