#!/usr/bin/env bash
# Per-crop before/after comparison for the landscape weightmap wave.
# Before: build/qa/lighting_after_{sky,safe}.png
# After:  build/qa/landscape_after_{courtyard,safe}.png
set -u
cd "$(dirname "$0")" || exit 1
SCRATCH=scratch/landscape_pixels
mkdir -p "$SCRATCH"

# name|before|after|geometry
CROPS=(
  "courtyard viewport|lighting_after_sky.png|landscape_after_courtyard.png|1280x720+160+140"
  "courtyard ground band|lighting_after_sky.png|landscape_after_courtyard.png|1080x210+180+650"
  "courtyard centre ground|lighting_after_sky.png|landscape_after_courtyard.png|420x150+520+680"
  "courtyard street left|lighting_after_sky.png|landscape_after_courtyard.png|220x130+160+600"
  "courtyard roof (control)|lighting_after_sky.png|landscape_after_courtyard.png|330x110+300+405"
  "courtyard facade (control)|lighting_after_sky.png|landscape_after_courtyard.png|300x170+300+515"
  "courtyard sky (control)|lighting_after_sky.png|landscape_after_courtyard.png|600x200+420+150"
  "safe viewport|lighting_after_safe.png|landscape_after_safe.png|1280x720+160+140"
  "safe floor band|lighting_after_safe.png|landscape_after_safe.png|760x110+180+730"
  "safe wall (control)|lighting_after_safe.png|landscape_after_safe.png|600x280+600+200"
  "safe crate (control)|lighting_after_safe.png|landscape_after_safe.png|360x190+300+560"
  "safe bed (control)|lighting_after_safe.png|landscape_after_safe.png|390x210+1010+500"
)

printf '| Crop | Geometry | Mean gray before | Mean gray after | Mean delta | RMSE | RMSE (norm) |\n'
printf '|---|---|---:|---:|---:|---:|---:|\n'
for row in "${CROPS[@]}"; do
  IFS='|' read -r name before after geom <<< "$row"
  b="$SCRATCH/${name// /_}_before.png"
  a="$SCRATCH/${name// /_}_after.png"
  convert "$before" -crop "$geom" +repage "$b"
  convert "$after"  -crop "$geom" +repage "$a"
  bmean=$(convert "$b" -colorspace Gray -format '%[fx:mean*255]' info:)
  amean=$(convert "$a" -colorspace Gray -format '%[fx:mean*255]' info:)
  delta=$(awk -v b="$bmean" -v a="$amean" 'BEGIN { printf "%+.2f%%", (a-b)/b*100.0 }')
  rmse=$(compare -metric RMSE "$b" "$a" null: 2>&1)
  printf '| %s | `%s` | %.2f | %.2f | %s | %s |\n' "$name" "$geom" "$bmean" "$amean" "$delta" "$rmse"
done
