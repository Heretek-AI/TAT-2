#!/usr/bin/env bash
# Flat-patch before/after stats for the landscape weightmap wave.
set -u
cd "$(dirname "$0")" || exit 1
SCRATCH=scratch/landscape_patches
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

printf '| Patch | Geometry | Mean gray before | Mean gray after | RMSE raw | RMSE blurred 3px |\n'
printf '|---|---|---:|---:|---:|---:|\n'
for row in "${PATCHES[@]}"; do
  IFS='|' read -r name geom <<< "$row"
  b="$SCRATCH/${name}_before.png"
  a="$SCRATCH/${name}_after.png"
  magick lighting_after_sky.png -crop "$geom" +repage "$b"
  magick landscape_after_courtyard.png -crop "$geom" +repage "$a"
  bm=$(magick "$b" -colorspace Gray -format '%[fx:mean*255]' info:)
  am=$(magick "$a" -colorspace Gray -format '%[fx:mean*255]' info:)
  raw=$(compare -metric RMSE "$b" "$a" null: 2>&1)
  magick "$b" -blur 0x3 "$SCRATCH/${name}_before_blur.png"
  magick "$a" -blur 0x3 "$SCRATCH/${name}_after_blur.png"
  blur=$(compare -metric RMSE "$SCRATCH/${name}_before_blur.png" "$SCRATCH/${name}_after_blur.png" null: 2>&1)
  printf '| %s | `%s` | %.2f | %.2f | %s | %s |\n' "$name" "$geom" "$bm" "$am" "$raw" "$blur"
done
