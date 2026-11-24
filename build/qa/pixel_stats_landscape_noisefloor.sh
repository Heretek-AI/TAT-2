#!/usr/bin/env bash
# Compare before-vs-after against the same-code run-to-run noise floor
# on identical flat patches of the courtyard capture.
set -u
cd "$(dirname "$0")" || exit 1
SCRATCH=scratch/landscape_noisefloor
mkdir -p "$SCRATCH"

PATCHES=(
  "grass|60x30+690+665"
  "dirt_left|60x40+550+720"
  "dirt_right|50x30+820+750"
  "snow_slab|60x30+810+720"
  "street|60x40+200+650"
  "roof|80x40+400+440"
  "facade|60x60+380+550"
  "sky|100x80+600+200"
)

printf '| Patch | Geometry | Before->after RMSE | After run1->run2 RMSE | Before->after mean delta |\n'
printf '|---|---|---:|---:|---:|\n'
for row in "${PATCHES[@]}"; do
  IFS='|' read -r name geom <<< "$row"
  magick lighting_after_sky.png -crop "$geom" +repage "$SCRATCH/b.png"
  magick landscape_after_courtyard.png -crop "$geom" +repage "$SCRATCH/a1.png"
  magick landscape_after_courtyardrun2.png -crop "$geom" +repage "$SCRATCH/a2.png"
  ba=$(compare -metric RMSE "$SCRATCH/b.png" "$SCRATCH/a1.png" null: 2>&1)
  aa=$(compare -metric RMSE "$SCRATCH/a1.png" "$SCRATCH/a2.png" null: 2>&1)
  bm=$(magick "$SCRATCH/b.png" -colorspace Gray -format '%[fx:mean*255]' info:)
  am=$(magick "$SCRATCH/a1.png" -colorspace Gray -format '%[fx:mean*255]' info:)
  delta=$(awk -v b="$bm" -v a="$am" 'BEGIN { printf "%+.2f%%", (a-b)/b*100.0 }')
  printf '| %s | `%s` | %s | %s | %s |\n' "$name" "$geom" "$ba" "$aa" "$delta"
done
