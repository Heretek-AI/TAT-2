#!/usr/bin/env bash
# P0b Lane L — live-reference preparation and verification (NEVER launches anything).
#
# Why this file exists
# --------------------
# The parity baseline needs a capture of the *shipped* UE5.5 build 1.5.148559
# (Steam appid 3341000) made on this machine, with the same 1440p/60/100%
# settings and the same 27-beat route as the port capture. The shipped install
# is the only ground truth, but it is also a live Steam app whose appmanifest
# says AutoUpdateBehavior=0 (always update). This helper records the exact
# build state, copies the Proton prefix (not the 3.8 GB install) to a scratch
# path, stages a throwaway save in the copy, prints the lossless capture
# command, and hashes the captured frames.
#
# Hard rules encoded here:
#   * It never starts Steam, Proton, or the game. There is no "launch"
#     subcommand; `capture-cmd` only prints a command for the owner.
#   * It never writes the install, the appmanifest, or the original prefix.
#     `copy` writes only $P0B_PREFIX (default /tmp/opencode/tat2-ref-prefix),
#     `stage` writes only inside that copy, and `verify` writes only under
#     $P0B_CAPDIR (default ~/Videos/tat2_ref_<date>).
#   * It refuses to touch a prefix path outside /tmp/opencode.
#
# Usage:
#   build/qa/p0b_live_capture.sh preflight [--no-net] [--allow-low-vram]
#   build/qa/p0b_live_capture.sh copy [--force]
#   build/qa/p0b_live_capture.sh verify-copy
#   build/qa/p0b_live_capture.sh stage
#   build/qa/p0b_live_capture.sh capture-cmd
#   build/qa/p0b_live_capture.sh verify [--capdir DIR]
#   build/qa/p0b_live_capture.sh steps
#
# Exit: preflight 0 = READY, 2 = NOT_READY (blockers printed); other commands
# 0 on success, 1 on failure, 2 on a refused unsafe action.
set -uo pipefail

APPID=3341000
BUILDID_EXPECTED=25076818
SHIPPING_VERSION_EXPECTED=1.5.193.148559
BOOTSTRAP_VERSION_EXPECTED=1.5.148559
PROTON_VERSION_EXPECTED="experimental-11.0-20261112-x86_64"

STEAM_ROOT="${STEAM_ROOT:-$HOME/.steam/steam}"
GAME_DIR="$STEAM_ROOT/steamapps/common/Thick As Thieves"
ACF="$STEAM_ROOT/steamapps/appmanifest_${APPID}.acf"
PREFIX_SRC="$STEAM_ROOT/steamapps/compatdata/${APPID}"
PREFIX_DST="${P0B_PREFIX:-/tmp/opencode/tat2-ref-prefix}"
CAPDIR="${P0B_CAPDIR:-$HOME/Videos/tat2_ref_$(date +%Y%m%d)}"
CAPFILE="$CAPDIR/route_lossless.mkv"

Z="\033[0m"; R="\033[31m"; G="\033[32m"; Y="\033[33m"; B="\033[36m"
say()  { printf '%b%s%b\n' "$1" "$2" "$Z"; }
ok()   { printf '%b  OK  %b %s\n' "$G" "$Z" "$*"; }
warn() { printf '%b WARN %b %s\n' "$Y" "$Z" "$*"; }
bad()  { printf '%b FAIL %b %s\n' "$R" "$Z" "$*"; }
die()  { bad "$*"; exit 1; }
refuse() { bad "$*"; exit 2; }

BLOCKERS=0
blocker() { bad "$*"; BLOCKERS=$((BLOCKERS + 1)); }

have() { command -v "$1" >/dev/null 2>&1; }

acf_field() { # acf_field <key>
  sed -n "s/.*\"$1\"[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$ACF" 2>/dev/null | head -1
}

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------- preflight
cmd_preflight() {
  local net=1 allow_low_vram=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-net) net=0 ;;
      --allow-low-vram) allow_low_vram=1 ;;
      -h|--help) usage ;;
      *) die "unknown preflight option: $1" ;;
    esac
    shift
  done

  say "$B" "== Build / install =="
  [ -f "$ACF" ] || die "missing appmanifest: $ACF"
  local buildid state auto target updated
  buildid="$(acf_field buildid)"
  state="$(acf_field StateFlags)"
  auto="$(acf_field AutoUpdateBehavior)"
  target="$(acf_field TargetBuildID)"
  updated="$(acf_field LastUpdated)"
  printf '  appmanifest : %s\n' "$ACF"
  printf '  buildid     : %s (expected %s)\n' "${buildid:-?}" "$BUILDID_EXPECTED"
  printf '  StateFlags  : %s (4 = Fully Installed)\n' "${state:-?}"
  printf '  AutoUpdate  : %s (0 = always keep this game up to date)\n' "${auto:-?}"
  printf '  TargetBuild : %s (0 = no queued update)\n' "${target:-?}"
  printf '  LastUpdated : %s (%s)\n' "${updated:-?}" "$(date -d "@${updated:-0}" '+%F %T' 2>/dev/null || echo '?')"
  [ "$buildid" = "$BUILDID_EXPECTED" ] || blocker "buildid $buildid != $BUILDID_EXPECTED; do not capture"
  [ "$state" = "4" ] || blocker "StateFlags $state != 4; the install is not fully installed"
  [ "$target" = "0" ] || blocker "TargetBuildID $target != 0; an update is queued"
  [ "$auto" = "0" ] && warn "AutoUpdateBehavior=0: an ONLINE launch will update as soon as a new build is published"

  local exe="$GAME_DIR/TAT/Binaries/Win64/TAT-Win64-Shipping.exe"
  if [ -f "$exe" ] && have exiftool; then
    local ver
    ver="$(exiftool -s -s -s -FileVersion "$exe" 2>/dev/null)"
    printf '  shipping exe : %s\n' "$ver"
    case "$ver" in
      *"$SHIPPING_VERSION_EXPECTED"*) ok "shipping exe version contains $SHIPPING_VERSION_EXPECTED" ;;
      *) blocker "shipping exe version '$ver' does not contain $SHIPPING_VERSION_EXPECTED" ;;
    esac
  else
    warn "cannot read shipping exe version (missing exe or exiftool)"
  fi
  local boot="$GAME_DIR/TAT.exe"
  if [ -f "$boot" ] && have exiftool; then
    local bver
    bver="$(exiftool -s -s -s -FileVersion "$boot" 2>/dev/null)"
    printf '  bootstrap    : %s\n' "$bver"
    case "$bver" in
      *"$BOOTSTRAP_VERSION_EXPECTED"*) ok "bootstrap version contains $BOOTSTRAP_VERSION_EXPECTED (pause-footer build)" ;;
      *) blocker "bootstrap version '$bver' does not contain $BOOTSTRAP_VERSION_EXPECTED" ;;
    esac
  else
    warn "cannot read TAT.exe version"
  fi
  if [ -f "$GAME_DIR/TAT/Binaries/Win64/vkd3d-proton.cache" ]; then
    printf '  vkd3d cache  : %s bytes (%s)\n' \
      "$(stat -c %s "$GAME_DIR/TAT/Binaries/Win64/vkd3d-proton.cache")" \
      "$(stat -c %y "$GAME_DIR/TAT/Binaries/Win64/vkd3d-proton.cache")"
    printf '  vkd3d write  : %s bytes (%s)\n' \
      "$(stat -c %s "$GAME_DIR/TAT/Binaries/Win64/vkd3d-proton.cache.write" 2>/dev/null || echo 0)" \
      "$(stat -c %y "$GAME_DIR/TAT/Binaries/Win64/vkd3d-proton.cache.write" 2>/dev/null || echo '?')"
    warn "the game writes vkd3d-proton.cache* inside the install dir; hash them before/after the run"
  fi

  say "$B" "== Steam client state =="
  if pgrep -f '[s]teamwebhelper' >/dev/null 2>&1; then
    ok "Steam client is running (this script does not touch it)"
  else
    warn "Steam client is not running; start it manually and sign in"
  fi
  local lu="$STEAM_ROOT/config/loginusers.vdf"
  if [ -f "$lu" ]; then
    local persona offline remember
    persona="$(grep -m1 'PersonaName' "$lu" | sed 's/.*"\(.*\)".*/\1/')"
    offline="$(grep -m1 'WantsOfflineMode' "$lu" | sed 's/.*"\(.*\)".*/\1/')"
    remember="$(grep -m1 'RememberPassword' "$lu" | sed 's/.*"\(.*\)".*/\1/')"
    printf '  account     : %s\n' "${persona:-?}"
    printf '  offline     : WantsOfflineMode=%s (0 = currently online)\n' "${offline:-?}"
    printf '  remembered  : RememberPassword=%s\n' "${remember:-?}"
    [ "$offline" = "1" ] || warn "Steam is online; switch to Offline Mode BEFORE pressing Play"
    [ "$remember" = "1" ] || warn "RememberPassword!=1: offline mode may require a sign-in"
  else
    warn "loginusers.vdf not found; cannot confirm the remembered account"
  fi

  say "$B" "== Update availability =="
  if [ "$net" = "1" ] && have curl && have python3; then
    local json
    json="$(curl -fsS --max-time 15 \
      "https://api.steampowered.com/ISteamApps/UpToDateCheck/v1/?appid=${APPID}&version=${buildid}" 2>/dev/null)" \
      || { warn "UpToDateCheck request failed; verify offline before launching"; json=""; }
    if [ -n "$json" ]; then
      printf '  %s\n' "$json"
      if printf '%s' "$json" | grep -q '"up_to_date":true'; then
        ok "Valve reports buildid $buildid is the current public build"
      else
        blocker "Valve does NOT report buildid $buildid up to date; an update exists"
      fi
    fi
  else
    warn "update check skipped (--no-net or curl/python3 missing)"
  fi

  say "$B" "== Proton prefix copy =="
  [ -d "$PREFIX_SRC/pfx" ] || blocker "missing original prefix: $PREFIX_SRC"
  if [ -d "$PREFIX_DST/pfx" ]; then
    printf '  copy        : %s\n' "$PREFIX_DST"
    printf '  files       : %s\n' "$(find "$PREFIX_DST" -type f 2>/dev/null | wc -l)"
    printf '  apparent    : %s bytes\n' "$(du -sb "$PREFIX_DST" 2>/dev/null | cut -f1)"
    printf '  version     : %s\n' "$(cat "$PREFIX_DST/version" 2>/dev/null || echo '?')"
    if [ -f "$PREFIX_DST/pfx/system.reg" ] && [ -f "$PREFIX_SRC/pfx/system.reg" ] &&
       [ "$(stat -c %s "$PREFIX_DST/pfx/system.reg")" = "$(stat -c %s "$PREFIX_SRC/pfx/system.reg")" ]; then
      ok "copy still matches the original prefix (system.reg size)"
    else
      warn "copy differs from the original (already used, or partially staged); see verify-copy"
    fi
  else
    blocker "missing prefix copy: $PREFIX_DST (run: $0 copy)"
  fi
  local proton="$STEAM_ROOT/steamapps/common/Proton - Experimental/version"
  if [ -f "$proton" ]; then
    printf '  proton      : %s\n' "$(cat "$proton")"
    grep -q "$PROTON_VERSION_EXPECTED" "$proton" \
      && ok "Proton Experimental is $PROTON_VERSION_EXPECTED" \
      || warn "Proton Experimental changed; the renderer may differ from the prep baseline"
  else
    warn "Proton Experimental not found at $proton"
  fi

  say "$B" "== Host / capture path =="
  printf '  session     : XDG_SESSION_TYPE=%s DISPLAY=%s WAYLAND_DISPLAY=%s\n' \
    "${XDG_SESSION_TYPE:-?}" "${DISPLAY:-?}" "${WAYLAND_DISPLAY:-?}"
  if have nvidia-smi; then
    local gpu free
    gpu="$(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null | head -1)"
    read -r _total free <<<"$(nvidia-smi --query-gpu=memory.total,memory.free --format=csv,noheader,nounits 2>/dev/null | head -1 | tr ',' ' ')"
    printf '  gpu         : %s\n' "${gpu:-?}"
    printf '  vram free   : %s MiB (blocker below 4096 MiB)\n' "${free:-?}"
    if [ "${free:-0}" -lt 4096 ] 2>/dev/null; then
      if [ "$allow_low_vram" = "1" ]; then
        warn "VRAM free ${free} MiB < 4096 MiB (allowed by --allow-low-vram)"
      else
        blocker "VRAM free ${free} MiB < 4096 MiB; close GPU apps (browser, editor, chat) first"
      fi
    else
      ok "VRAM headroom looks sufficient for 1440p"
    fi
  else
    warn "nvidia-smi not found; cannot check VRAM"
  fi
  if have ffmpeg && ffmpeg -hide_banner -h demuxer=x11grab 2>/dev/null | grep -q -- '-window_id'; then
    ok "ffmpeg $(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}') x11grab supports -window_id"
  else
    blocker "ffmpeg x11grab without -window_id; install the distro ffmpeg"
  fi
  have xdotool || blocker "xdotool missing; the capture command needs the game window id"
  have ffprobe || blocker "ffprobe missing"
  have sha256sum || blocker "sha256sum missing"
  if have pactl; then
    local sink
    sink="$(pactl get-default-sink 2>/dev/null)"
    printf '  default sink: %s\n' "${sink:-?}"
    if [ -n "$sink" ] && pactl list short sources 2>/dev/null | grep -q "${sink}.monitor"; then
      ok "monitor source ${sink}.monitor is available"
    else
      warn "no monitor source for the default sink; pick a sink in the runbook"
    fi
  else
    warn "pactl not found; audio capture will need a manual source"
  fi
  printf '  capture dir : %s\n' "$CAPDIR"
  printf '  disk free   : %s\n' "$(df -h "$(dirname "$CAPDIR")" 2>/dev/null | awk 'NR==2{print $4}')"
  if pgrep -f '[T]AT-Win64-Shipping|[T]AT\.exe' >/dev/null 2>&1; then
    blocker "the shipped game is already running; stop it before preflight"
  fi

  say "$B" "== Verdict =="
  if [ "$BLOCKERS" -eq 0 ]; then
    say "$G" "P0B_LIVE_PREFLIGHT READY buildid=$buildid"
    return 0
  fi
  say "$R" "P0B_LIVE_PREFLIGHT NOT_READY blockers=$BLOCKERS"
  return 2
}

# ---------------------------------------------------------------- copy
cmd_copy() {
  local force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=1 ;;
      -h|--help) usage ;;
      *) die "unknown copy option: $1" ;;
    esac
    shift
  done
  case "$PREFIX_DST" in
    /tmp/opencode/*) ;;
    *) refuse "P0B_PREFIX '$PREFIX_DST' is outside /tmp/opencode; refusing" ;;
  esac
  [ -d "$PREFIX_SRC/pfx" ] || die "missing original prefix: $PREFIX_SRC"
  if [ -e "$PREFIX_DST" ]; then
    [ "$force" = "1" ] || refuse "$PREFIX_DST exists; pass --force to replace it"
    rm -rf -- "$PREFIX_DST" || die "could not remove $PREFIX_DST"
  fi
  mkdir -p "$(dirname "$PREFIX_DST")" || die "mkdir failed"
  say "$B" "copying $PREFIX_SRC -> $PREFIX_DST"
  cp -a --reflink=auto "$PREFIX_SRC" "$PREFIX_DST" || die "cp failed"
  cmd_verify_copy
  printf 'P0B_LIVE_PREFIX_COPY path=%s bytes=%s files=%s\n' \
    "$PREFIX_DST" "$(du -sb "$PREFIX_DST" | cut -f1)" "$(find "$PREFIX_DST" -type f | wc -l)"
}

cmd_verify_copy() {
  [ -d "$PREFIX_DST/pfx" ] || die "no prefix copy at $PREFIX_DST"
  [ -d "$PREFIX_SRC/pfx" ] || die "no original prefix at $PREFIX_SRC"
  local n_src n_dst
  n_src="$(find "$PREFIX_SRC" -type f | wc -l)"
  n_dst="$(find "$PREFIX_DST" -type f | wc -l)"
  [ "$n_src" = "$n_dst" ] || die "file count differs: original=$n_src copy=$n_dst"
  local diffout
  diffout="$(diff -r --no-dereference "$PREFIX_SRC" "$PREFIX_DST" 2>&1)" || {
    printf '%s\n' "$diffout" | head -20
    die "prefix copy differs from the original"
  }
  ok "prefix copy is byte-identical ($n_dst files, $(du -sb "$PREFIX_DST" | cut -f1) bytes)"
  printf 'P0B_LIVE_PREFIX_VERIFY MATCH files=%s bytes=%s\n' "$n_dst" "$(du -sb "$PREFIX_DST" | cut -f1)"
}

# ---------------------------------------------------------------- stage
cmd_stage() {
  [ -d "$PREFIX_DST/pfx" ] || die "no prefix copy at $PREFIX_DST; run: $0 copy"
  local saved="$PREFIX_DST/pfx/drive_c/users/steamuser/AppData/Local/TAT/Saved"
  local cfg="$saved/Config/Windows/GameUserSettings.ini"
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  if [ -d "$saved/SaveGames" ]; then
    mv "$saved/SaveGames" "$saved/SaveGames.pre-p0b-$ts" || die "could not archive SaveGames"
    ok "archived SaveGames -> SaveGames.pre-p0b-$ts"
  fi
  mkdir -p "$saved/SaveGames" || die "could not create SaveGames"
  if [ -f "$cfg" ]; then
    cp -a "$cfg" "$cfg.pre-p0b-$ts" || die "could not archive GameUserSettings.ini"
    ok "archived GameUserSettings.ini -> GameUserSettings.ini.pre-p0b-$ts"
  fi
  cat <<EOF

Staged the COPY only: $PREFIX_DST
  - the old save is preserved as SaveGames.pre-p0b-$ts
  - the game will create a fresh save in SaveGames/
  - the old video settings are archived, not edited

Set these IN-GAME (Settings -> Video) and record the screen for 3 s:
  * Windowed, 2560x1440 client area (not 1920x1440 / not 42% like the old ini)
  * VSync off, FPS limit 60
  * Resolution / screen percentage 100% (no DLSS/FSR upscaling)
  * Reset quality to the shipped default preset; do not inherit the old Low values
  * HDR off
Do not hand-edit the ini to guess the default preset.
EOF
}

# ---------------------------------------------------------------- capture command
cmd_capture_cmd() {
  local wid sink
  wid="$(xdotool search --onlyvisible --name 'Thick As Thieves' 2>/dev/null | head -1 || true)"
  sink="$(pactl get-default-sink 2>/dev/null || true)"
  mkdir -p "$CAPDIR" 2>/dev/null || true
  cat <<EOF
# Run this ONLY after: Steam -> Go Offline, the copied prefix is verified in
# use, the new save exists, and the in-game video settings are confirmed.
# It does not start the game; it records the already-running window.

OUT="$CAPDIR"
WID="${wid:-\$(xdotool search --onlyvisible --name 'Thick As Thieves' | head -1)}"
SINK="${sink:-\$(pactl get-default-sink)}"
xdotool getwindowgeometry "\$WID"     # must print a 2560x1440 client area
pactl list short sources | grep "\$SINK.monitor"

ffmpeg -hide_banner -y \\
  -f x11grab -framerate 60 -window_id "\$WID" -draw_mouse 1 -i :0.0 \\
  -f pulse -i "\$SINK.monitor" \\
  -map 0:v -map 1:a \\
  -c:v libx264rgb -qp 0 -preset ultrafast -pix_fmt bgr0 -fps_mode cfr -r 60 \\
  -c:a flac -ar 48000 -ac 2 \\
  -t 420 "\$OUT/route_lossless.mkv"

# -qp 0 + bgr0 = mathematically lossless RGB; ffprobe must report pix_fmt=gbrp.
# Stop early with q. Keep the whole 27-beat route plus the six hold poses.
EOF
  [ -n "$wid" ] || warn "no 'Thick As Thieves' X window found yet (expected before the run)"
  [ -n "$sink" ] || warn "no default Pulse sink found"
}

# ---------------------------------------------------------------- verify
cmd_verify() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --capdir) CAPDIR="${2:?--capdir needs a path}"; CAPFILE="$CAPDIR/route_lossless.mkv"; shift ;;
      -h|--help) usage ;;
      *) die "unknown verify option: $1" ;;
    esac
    shift
  done
  [ -f "$CAPFILE" ] || die "missing capture: $CAPFILE"
  have ffprobe || die "ffprobe missing"
  have python3 || die "python3 missing"
  have sha256sum || die "sha256sum missing"
  local vinfo
  vinfo="$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,width,height,pix_fmt,avg_frame_rate,nb_frames \
    -show_entries format=duration,size -of default=nw=1 "$CAPFILE")" || die "ffprobe failed"
  printf '%s\n' "$vinfo"
  printf '%s' "$vinfo" | grep -q 'pix_fmt=gbrp' \
    && ok "lossless RGB (pix_fmt=gbrp)" \
    || warn "pix_fmt is not gbrp; the capture is not provably lossless RGB"
  printf '%s' "$vinfo" | grep -q 'avg_frame_rate=60/1' \
    && ok "60 fps" || warn "avg_frame_rate is not 60/1"

  local poses="$CAPDIR/poses.tsv"
  if [ ! -f "$poses" ]; then
    cat >"$poses" <<'EOF'
# name<TAB>seconds<TAB>note   (fill after scrubbing the lossless capture)
gate	0.0	KF16 01:40.20, arch + guard + car headlights + ZipWire
upper_foyer	0.0	KF27 03:27.60, foyer threshold, eye (27,29.67,-50) -> (27,29.67,-60)
yaw180	0.0	same eye -> (27,29.67,-40)
lounge	0.0	east doorway ~ (43.7,27.05,-26.2) looking west into the Lounge
lounge_beam	0.0	Lounge beam ~ (42.34,28.9,-28.97)
beam_close	0.0	foyer beam ~ (23.27,29.76,-57.4), emitter x~17.8% y~40%
EOF
    die "wrote a template $poses — fill the six seconds, then rerun verify"
  fi

  local tmphash="$CAPDIR/.pose_hashes.tsv"
  : >"$tmphash"
  local name t png hash n=0
  while IFS=$'\t' read -r name t _; do
    case "$name" in ''|'#'*) continue ;; esac
    [ -n "$t" ] || die "poses.tsv: no seconds for $name"
    png="$CAPDIR/pose_${name}.png"
    ffmpeg -v error -y -ss "$t" -i "$CAPFILE" -frames:v 1 -f image2 -c:v png "$png" \
      || die "extract failed for $name at ${t}s"
    hash="$(sha256sum "$png" | cut -d' ' -f1)"
    printf '%s\t%s\t%s\t%s\n' "$name" "$t" "$png" "$hash" >>"$tmphash"
    printf '  %-14s t=%-8s %s  %s\n' "$name" "$t" "$hash" "$png"
    n=$((n + 1))
  done <"$poses"
  [ "$n" -ge 1 ] || die "no poses extracted"

  local vidhash acfhash exehash buildid_now exever protonver
  vidhash="$(sha256sum "$CAPFILE" | cut -d' ' -f1)"
  acfhash="$([ -f "$ACF" ] && sha256sum "$ACF" | cut -d' ' -f1 || echo '')"
  buildid_now="$(acf_field buildid)"
  [ "$buildid_now" = "$BUILDID_EXPECTED" ] \
    || warn "capture appmanifest buildid '$buildid_now' != expected '$BUILDID_EXPECTED'"
  exehash=""
  exever=""
  if [ -f "$GAME_DIR/TAT/Binaries/Win64/TAT-Win64-Shipping.exe" ]; then
    exehash="$(sha256sum "$GAME_DIR/TAT/Binaries/Win64/TAT-Win64-Shipping.exe" | cut -d' ' -f1)"
    have exiftool && exever="$(exiftool -s -s -s -FileVersion "$GAME_DIR/TAT/Binaries/Win64/TAT-Win64-Shipping.exe" 2>/dev/null)"
  fi
  protonver="$(cat "$STEAM_ROOT/steamapps/common/Proton - Experimental/version" 2>/dev/null || echo '')"

  P0B_CAPDIR="$CAPDIR" P0B_CAPFILE="$CAPFILE" P0B_VINFO="$vinfo" \
  P0B_VIDHASH="$vidhash" P0B_ACFHASH="$acfhash" P0B_EXEHASH="$exehash" \
  P0B_BUILDID="$buildid_now" P0B_EXEVER="$exever" P0B_PROTON="$protonver" \
  P0B_POSESHASH="$tmphash" P0B_PREFIX="$PREFIX_DST" \
  python3 - <<'PY'
import json, os, subprocess, datetime
capdir = os.environ['P0B_CAPDIR']
vinfo = {}
for line in os.environ['P0B_VINFO'].splitlines():
    if '=' in line:
        k, v = line.split('=', 1); vinfo[k] = v
poses = []
for line in open(os.environ['P0B_POSESHASH'], encoding='utf-8'):
    name, t, png, h = line.rstrip('\n').split('\t')
    poses.append({'name': name, 't_s': float(t), 'png': os.path.basename(png), 'sha256': h})
def cmd(*a):
    try: return subprocess.run(a, capture_output=True, text=True, timeout=15).stdout.strip()
    except Exception: return ''
manifest = {
    'generated_at': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
    'capture': {
        'path': os.path.abspath(os.environ['P0B_CAPFILE']),
        'sha256': os.environ['P0B_VIDHASH'],
        'codec': vinfo.get('codec_name'), 'width': vinfo.get('width'),
        'height': vinfo.get('height'), 'pix_fmt': vinfo.get('pix_fmt'),
        'avg_frame_rate': vinfo.get('avg_frame_rate'),
        'nb_frames': vinfo.get('nb_frames'),
        'duration_s': vinfo.get('duration'),
    },
    'host': {
        'gpu': cmd('nvidia-smi', '--query-gpu=name,driver_version', '--format=csv,noheader'),
        'session': os.environ.get('XDG_SESSION_TYPE', ''),
        'display': os.environ.get('DISPLAY', ''),
        'sink': cmd('pactl', 'get-default-sink'),
    },
    'build': {
        'appid': 3341000,
        'appmanifest_buildid': os.environ['P0B_BUILDID'],
        'appmanifest_sha256': os.environ['P0B_ACFHASH'],
        'shipping_exe_sha256': os.environ['P0B_EXEHASH'],
        'shipping_exe_version': os.environ['P0B_EXEVER'],
    },
    'prefix': os.environ['P0B_PREFIX'],
    'proton_version': os.environ['P0B_PROTON'],
    'poses': poses,
    'notes': 'New save; in-game footer seed differs from the official 1025051536. Compare with Lane I ROI stats, not pixel equality.',
}
out = os.path.join(capdir, 'manifest.json')
with open(out, 'w', encoding='utf-8') as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
print('P0B_LIVE_MANIFEST', out)
PY
  rm -f "$tmphash"
  printf 'P0B_LIVE_VERIFY PASS poses=%s video_sha256=%s\n' "$n" "$vidhash"
}

# ---------------------------------------------------------------- steps
cmd_steps() {
  cat <<'EOF'
P0b live reference — condensed runbook (full detail: docs/reports/p0b-live-capture.md)

 0. Close every GPU-heavy app; target >= 5.5 GiB VRAM free.
 1. ./p0b_live_capture.sh preflight          # must print READY
 2. ./p0b_live_capture.sh copy               # /tmp/opencode/tat2-ref-prefix
 3. ./p0b_live_capture.sh stage              # new save in the COPY only
 4. Steam: disable Cloud + overlay for 3341000; record appmanifest hash.
 5. Steam: Go Offline (do not press Play while online).
 6. Launch Options: STEAM_COMPAT_DATA_PATH=/tmp/opencode/tat2-ref-prefix %command%
 7. Press Play; verify the COPY's pfx mtime changes and the original's does not.
 8. Settings: Windowed 2560x1440, VSync off, 60 cap, 100%, default preset.
 9. Warm-up run: boot -> mission -> 60 s -> back to the menu; then record.
10. ./p0b_live_capture.sh capture-cmd          # review, then run by hand
11. Play the 27 beats; hold the six poses for 3 s each.
12. Fill poses.tsv; ./p0b_live_capture.sh verify
13. Pause-menu footer must read 1.5.148559 / Novice / <new seed>; hash the frame.
EOF
}

# ---------------------------------------------------------------- dispatch
CMD="${1:-preflight}"; [ $# -gt 0 ] && shift
case "$CMD" in
  preflight)   cmd_preflight "$@" ;;
  copy)        cmd_copy "$@" ;;
  verify-copy) cmd_verify_copy "$@" ;;
  stage)       cmd_stage "$@" ;;
  capture-cmd) cmd_capture_cmd "$@" ;;
  verify)      cmd_verify "$@" ;;
  steps)       cmd_steps "$@" ;;
  launch)      refuse "this helper never launches Steam/Proton/the game; use the manual runbook" ;;
  -h|--help|help) usage ;;
  *) die "unknown command: $CMD (try: $0 steps)" ;;
esac
