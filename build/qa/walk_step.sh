#!/usr/bin/env bash
# Hold w for N seconds on the live :99 session, then capture a root frame.
set -u
SECS="${1:?usage: walk_step.sh <seconds> <out.png>}"
OUT="${2:?usage: walk_step.sh <seconds> <out.png>}"
DISPLAY=:99 xdotool keydown w
sleep "$SECS"
DISPLAY=:99 xdotool keyup w
sleep 1
DISPLAY=:99 import -window root "$OUT"
echo "saved $OUT after ${SECS}s walk"
