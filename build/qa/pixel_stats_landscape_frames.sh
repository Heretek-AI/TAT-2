#!/usr/bin/env bash
# Whole-frame and band-level before/after vs same-code noise floor.
set -u
cd "$(dirname "$0")" || exit 1
SCRATCH=scratch/landscape_frames
mkdir -p "$SCRATCH"

crop() { magick "$1" -crop "$2" +repage "$3"; }
metric() { compare -metric RMSE "$1" "$2" null: 2>&1; }

crop lighting_after_sky.png 1280x720+160+140 "$SCRATCH/b_sky_vp.png"
crop landscape_after_courtyard.png 1280x720+160+140 "$SCRATCH/a1_sky_vp.png"
crop landscape_after_courtyardrun2.png 1280x720+160+140 "$SCRATCH/a2_sky_vp.png"
crop lighting_after_sky.png 1080x210+180+650 "$SCRATCH/b_sky_ground.png"
crop landscape_after_courtyard.png 1080x210+180+650 "$SCRATCH/a1_sky_ground.png"
crop landscape_after_courtyardrun2.png 1080x210+180+650 "$SCRATCH/a2_sky_ground.png"
crop lighting_after_safe.png 1280x720+160+140 "$SCRATCH/b_safe_vp.png"
crop landscape_after_safe.png 1280x720+160+140 "$SCRATCH/a1_safe_vp.png"
crop landscape_after_saferun2.png 1280x720+160+140 "$SCRATCH/a2_safe_vp.png"
crop lighting_after_safe.png 760x110+180+730 "$SCRATCH/b_safe_floor.png"
crop landscape_after_safe.png 760x110+180+730 "$SCRATCH/a1_safe_floor.png"
crop landscape_after_saferun2.png 760x110+180+730 "$SCRATCH/a2_safe_floor.png"

printf '| Pair | Crop | Before->after RMSE | Same-code run1->run2 RMSE |\n'
printf '|---|---|---:|---:|\n'
printf '| Courtyard | full frame 1600x1000 | %s | %s |\n' "$(metric lighting_after_sky.png landscape_after_courtyard.png)" "$(metric landscape_after_courtyard.png landscape_after_courtyardrun2.png)"
printf '| Courtyard | viewport `1280x720+160+140` | %s | %s |\n' "$(metric "$SCRATCH/b_sky_vp.png" "$SCRATCH/a1_sky_vp.png")" "$(metric "$SCRATCH/a1_sky_vp.png" "$SCRATCH/a2_sky_vp.png")"
printf '| Courtyard | ground band `1080x210+180+650` | %s | %s |\n' "$(metric "$SCRATCH/b_sky_ground.png" "$SCRATCH/a1_sky_ground.png")" "$(metric "$SCRATCH/a1_sky_ground.png" "$SCRATCH/a2_sky_ground.png")"
printf '| Safe | full frame 1600x1000 | %s | %s |\n' "$(metric lighting_after_safe.png landscape_after_safe.png)" "$(metric landscape_after_safe.png landscape_after_saferun2.png)"
printf '| Safe | viewport `1280x720+160+140` | %s | %s |\n' "$(metric "$SCRATCH/b_safe_vp.png" "$SCRATCH/a1_safe_vp.png")" "$(metric "$SCRATCH/a1_safe_vp.png" "$SCRATCH/a2_safe_vp.png")"
printf '| Safe | floor band `760x110+180+730` | %s | %s |\n' "$(metric "$SCRATCH/b_safe_floor.png" "$SCRATCH/a1_safe_floor.png")" "$(metric "$SCRATCH/a1_safe_floor.png" "$SCRATCH/a2_safe_floor.png")"
