#!/usr/bin/env bash
# make_side_by_side.sh - emit the side-by-side comparison commands for a TAT-2
# port recording (docs/REFERENCE_BASELINE.md sections 9.3/9.5/10).
#
# The script prints, but does not run, the commands; redirect stdout to keep them:
#
#   docs/reference/clip_1795033698901/tools/make_side_by_side.sh \
#     docs/reference/port_20260101/port_clip.mp4 \
#     docs/reference/port_20260101/offsets.csv > build_side_by_sides.sh
#
# offsets.csv (REFERENCE_BASELINE.md section 10 step 2) holds one row per
# segment S01-S27; '#' lines and a leading 'seg,...' / 'Snn,...' header row are
# ignored:
#
#   Snn,official_ts,port_ts,offset_s     e.g.  S01,00:00.00,00:02.35,2.35
#
# offset_s is the alignment offset in seconds (port_ts - official_ts); when the
# field is empty it is computed from the two timestamps.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: make_side_by_side.sh <port_clip> <offsets.csv>

  <port_clip>    Port recording to sample (docs/reference/port_<date>/port_clip.mp4).
  <offsets.csv>  Per-segment alignment offsets: Snn,official_ts,port_ts,offset_s

Prints (does not run) shell commands:
  * ffmpeg frame extraction per keyframe at its aligned port timestamp
  * 'magick <official> <port> +append' side-by-side pair per keyframe
  * 'magick <pairs> -hstack' review rows (5 pairs per row)

Commands go to stdout; paths assume the working directory they are run from.
Exit codes: 0 ok, 1 missing input file or bad offsets.csv row, 2 usage error.
EOF
}

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi
if [ "$#" -ne 2 ]; then
  printf 'error: expected 2 arguments, got %d\n' "$#" >&2
  usage
  exit 2
fi

port_clip=$1
offsets_csv=$2

for input in "$port_clip" "$offsets_csv"; do
  if [ ! -f "$input" ]; then
    printf 'error: input file not found: %s\n' "$input" >&2
    exit 1
  fi
done

script_dir=$(dirname -- "$0")
clean_dir=$script_dir/../clean
port_dir=$(dirname -- "$port_clip")

# MM:SS.ss (or plain seconds) -> seconds with millisecond precision.
to_seconds() {
  awk -v ts="$1" 'BEGIN {
    n = split(ts, p, ":"); s = 0
    for (i = 1; i <= n; i++) s = s * 60 + p[i] + 0
    printf "%.3f", s
  }'
}

# seconds -> mm_ss stamp used in port_<KF>_<mm_ss>.jpg (section 9.3 naming).
stamp_of() {
  awk -v t="$1" 'BEGIN {
    t = int(t + 0.5); m = int(t / 60); printf "%02d_%02d", m, t - m * 60
  }'
}

declare -A segment_offset=()
line_no=0
while IFS= read -r line || [ -n "$line" ]; do
  line_no=$((line_no + 1))
  case $line in '' | '#'*) continue ;; esac
  IFS=',' read -r seg official_ts port_ts offset extra <<<"$line"
  seg=${seg//[[:space:]]/}
  case $seg in [Ss][Ee][Gg]* | [Ss][Nn][Nn]) continue ;; esac  # header row
  if [[ ! $seg =~ ^S[0-9]{2}$ ]]; then
    printf 'error: %s:%d: bad segment id %q (want Snn, e.g. S07)\n' \
      "$offsets_csv" "$line_no" "$seg" >&2
    exit 1
  fi
  if [ -n "${extra:-}" ]; then
    printf 'error: %s:%d: expected 4 fields (Snn,official_ts,port_ts,offset_s)\n' \
      "$offsets_csv" "$line_no" >&2
    exit 1
  fi
  offset=${offset//[[:space:]]/}
  if [ -z "$offset" ]; then
    if [ -z "${official_ts//[[:space:]]/}" ] || [ -z "${port_ts//[[:space:]]/}" ]; then
      printf 'error: %s:%d: empty offset_s and no timestamps to derive it from\n' \
        "$offsets_csv" "$line_no" >&2
      exit 1
    fi
    offset=$(awk -v a="$(to_seconds "$official_ts")" -v b="$(to_seconds "$port_ts")" \
      'BEGIN { printf "%.3f", b - a }')
  fi
  if [[ ! $offset =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    printf 'error: %s:%d: offset_s %q is not numeric\n' "$offsets_csv" "$line_no" "$offset" >&2
    exit 1
  fi
  segment_offset[$seg]=$offset
done <"$offsets_csv"

# Keyframe table from KEYFRAME_INDEX.md section 3: keyframe|segment|official_ts|clean file.
# S02 and S16 carry no keyframes (KEYFRAME_INDEX.md section 2); their offsets are not sampled.
kf_table='KF01|S01|00:01.00|KF01_00m01s_startscreen.jpg
KF02|S03|00:04.50|KF02_00m04s_den_entry.jpg
KF03|S04|00:07.00|KF03_00m07s_wardrobe_loadout.jpg
KF04|S04|00:16.50|KF04_00m16s_wardrobe_vistara_diamond.jpg
KF05|S05|00:20.80|KF05_00m20s_telescope_cheese_moon.jpg
KF06|S05|00:24.60|KF06_00m24s_den_wanted_window.jpg
KF07|S06|00:27.00|KF07_00m27s_ledger_journal.jpg
KF08|S06|00:28.50|KF08_00m28s_ledger_black_market.jpg
KF09|S07|00:46.25|KF09_00m46s_den_gramophone.jpg
KF10|S08|00:52.35|KF10_00m52s_den_map_table.jpg
KF11|S09|01:00.30|KF11_01m00s_mission_prep_countdown.jpg
KF12|S10|01:06.50|KF12_01m06s_loading_screen.jpg
KF13|S11|01:10.00|KF13_01m10s_briefing_letter.jpg
KF14|S12|01:15.75|KF14_01m15s_saferoom_portal_hud.jpg
KF15|S13|01:21.38|KF15_01m21s_alley_barrons_demolition.jpg
KF16|S14|01:40.20|KF16_01m40s_zipwire_gate_headlights.jpg
KF17|S15|01:51.20|KF17_01m51s_zipwire_aim_roof.jpg
KF18|S17|02:14.80|KF18_02m14s_guildhall_arch_overlook.jpg
KF19|S18|02:25.40|KF19_02m25s_smoke_bomb_equip.jpg
KF20|S18|02:29.20|KF20_02m29s_smoke_bomb_plume.jpg
KF21|S19|02:32.20|KF21_02m32s_vistara_diamond_red_guard.jpg
KF22|S19|02:33.00|KF22_02m33s_vistara_diamond_green_guard.jpg
KF23|S20|02:41.00|KF23_02m41s_side_wing_macleod_sign.jpg
KF24|S21|03:00.60|KF24_03m00s_locked_blue_double_doors.jpg
KF25|S22|03:16.80|KF25_03m16s_parlor_pickpocket_takedown.jpg
KF26|S23|03:20.20|KF26_03m20s_parlor_guard_takedown.jpg
KF27|S24|03:27.60|KF27_03m27s_foyer_security_beam.jpg
KF28|S25|03:35.00|KF28_03m35s_foyer_arcane_barriers.jpg
KF29|S26|03:39.40|KF29_03m39s_stairs_crimson_alarm.jpg
KF30|S27|03:43.20|KF30_03m43s_pause_menu.jpg'

missing=0
while IFS='|' read -r kf seg ts file; do
  if [ -z "${segment_offset[$seg]-}" ]; then
    printf 'error: %s has no offset for %s (%s)\n' "$offsets_csv" "$seg" "$kf" >&2
    missing=1
  fi
done <<<"$kf_table"
if [ "$missing" -ne 0 ]; then
  exit 1
fi

printf '# generated by make_side_by_side.sh; run from the directory the paths below assume\n'
printf '# S02/S16 offsets are unused: those segments have no keyframes\n'
pairs=()
while IFS='|' read -r kf seg ts file; do
  aligned=$(awk -v a="$(to_seconds "$ts")" -v b="${segment_offset[$seg]}" \
    'BEGIN { printf "%.3f", a + b }')
  stamp=$(stamp_of "$aligned")
  frame=$port_dir/port_${kf}_${stamp}.jpg
  pair=$port_dir/side_by_side_${kf}_${stamp}.jpg
  printf '\n# %s (%s, official %s + %s s -> port %s s)\n' \
    "$kf" "$seg" "$ts" "${segment_offset[$seg]}" "$aligned"
  printf 'ffmpeg -v error -ss %s -i %q -frames:v 1 %q\n' "$aligned" "$port_clip" "$frame"
  printf 'magick %q %q +append %q\n' "$clean_dir/$file" "$frame" "$pair"
  pairs+=("$pair")
done <<<"$kf_table"

row=1
band=()
for pair in "${pairs[@]}"; do
  band+=("$pair")
  if [ "${#band[@]}" -eq 5 ]; then
    printf 'magick'
    printf ' %q' "${band[@]}"
    printf ' -hstack %q\n' "$port_dir/side_by_side_row_${row}.jpg"
    row=$((row + 1))
    band=()
  fi
done
if [ "${#band[@]}" -ge 2 ]; then
  printf 'magick'
  printf ' %q' "${band[@]}"
  printf ' -hstack %q\n' "$port_dir/side_by_side_row_${row}.jpg"
elif [ "${#band[@]}" -eq 1 ]; then
  printf 'magick %q +append %q\n' "${band[0]}" "$port_dir/side_by_side_row_${row}.jpg"
fi
