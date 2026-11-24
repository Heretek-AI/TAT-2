#!/usr/bin/env bash
# Stop the live QA session and restore game/project.godot exactly.
set -u
ROOT=/home/john/Projects/TAT-2
QA="$ROOT/build/qa"
cd "$ROOT" || exit 1

for p in $(pgrep -f "/app/bin/godot-bin --path game" || true); do
  pgid=$(ps -o pgid= -p "$p" | tr -d ' ')
  echo "killing godot pid=$p pgid=$pgid"
  kill -TERM -"$pgid" 2>/dev/null || true
done
sleep 3
for p in $(pgrep -f "/app/bin/godot-bin --path game" || true); do
  pgid=$(ps -o pgid= -p "$p" | tr -d ' ')
  kill -KILL -"$pgid" 2>/dev/null || true
done

for p in $(pgrep -f "Xvfb :99" || true); do
  echo "killing xvfb pid=$p"
  kill -TERM "$p" 2>/dev/null || true
done
sleep 1

cp "$QA/project.godot.bak" game/project.godot
echo "restored game/project.godot from $QA/project.godot.bak"
echo "git diff --stat game/project.godot:"
git diff --stat -- game/project.godot
echo "git status --short game/project.godot:"
git status --short -- game/project.godot
echo "remaining processes:"
pgrep -af "godot-bin --path game|Xvfb :99" | grep -v pgrep || true
