#!/usr/bin/env bash
set -u
ROOT="/home/john/Projects/TAT-2"
CONTRACT="${1:?contract}"
RES="${2:?WxH}"
FRAMES="${3:?frames}"
TAG="${4:?tag}"
OUT="$ROOT/build/qa/perf"
LOG="$OUT/fps_${TAG}_${RES}_focus.log"
XAUTH="/run/user/1000/xauth_pHUFjC"
cd "$ROOT" || exit 2
(
  timeout 25s env DISPLAY=:0 XAUTHORITY="$XAUTH" xdotool search --sync --onlyvisible --name "Thick As Thieves" windowactivate --sync %@ >/dev/null 2>&1
  env DISPLAY=:0 XAUTHORITY="$XAUTH" xdotool getactivewindow getwindowgeometry >> "$LOG" 2>&1
) &
env -u WAYLAND_DISPLAY DISPLAY=:0 XAUTHORITY="$XAUTH" \
  /usr/bin/timeout -s TERM 300s \
  ./build/tat2-linux-x86_64 --display-driver x11 --resolution "$RES" \
  --audio-driver Dummy --quit-after "$FRAMES" --print-fps \
  -- "--qa-contract=${CONTRACT}" > "$LOG" 2>&1
ST=$?
echo "EXIT=$ST LOG=$LOG"
python3 - "$LOG" <<'PY'
import re, statistics, sys
p = sys.argv[1]
fps = []
for line in open(p, errors="replace"):
    m = re.search(r"Project FPS: (\d+) \(([\d.]+) mspf\)", line)
    if m:
        fps.append((int(m.group(1)), float(m.group(2))))
print("samples", len(fps))
if fps:
    f = [v[0] for v in fps]; ms = [v[1] for v in fps]
    s = sorted(ms)
    print("fps min/p10/median/mean/p90/max", min(f), sorted(f)[int(len(f)*0.1)], statistics.median(f), round(statistics.mean(f),1), sorted(f)[int(len(f)*0.9)], max(f))
    print("mspf median/mean/p95", round(statistics.median(ms),2), round(statistics.mean(ms),2), round(s[min(int(len(s)*0.95), len(s)-1)],2))
    print("frames_over_16_67ms_pct", round(100*sum(1 for x in ms if x > 16.67)/len(ms),1))
PY
grep -E "QA autostart|Geometry:|SCRIPT ERROR|SHADER ERROR|Too many mipmaps|double free" "$LOG" | tail -10
exit "$ST"
