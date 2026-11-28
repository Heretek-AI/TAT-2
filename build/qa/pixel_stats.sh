#!/usr/bin/env bash
# QA-only luminance statistics via ImageMagick (gitignored build/qa).
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
GAME=1280x720+160+140

mean_sd() {
  magick "$1" -crop "$2" +repage -colorspace Gray \
    -format "%[fx:mean*255] %[fx:standard_deviation*255]" info:
}

pct_above() {
  # $3 is a 0-255 level; ImageMagick -threshold takes a percentage.
  local level_pct
  level_pct=$(awk -v v="$3" 'BEGIN { printf "%.4f", v / 255.0 * 100.0 }')
  magick "$1" -crop "$2" +repage -colorspace Gray -threshold "${level_pct}%" \
    -format "%[fx:mean*100]" info:
}

row() {
  local label="$1" ref="$2" new="$3" crop="$4"
  local rms rsd nms nsd r16 n16 r96 n96 r200 n200
  read -r rms rsd <<<"$(mean_sd "$ref" "$crop")"
  read -r nms nsd <<<"$(mean_sd "$new" "$crop")"
  r16=$(pct_above "$ref" "$crop" 16);  n16=$(pct_above "$new" "$crop" 16)
  r96=$(pct_above "$ref" "$crop" 96);  n96=$(pct_above "$new" "$crop" 96)
  r200=$(pct_above "$ref" "$crop" 200); n200=$(pct_above "$new" "$crop" 200)
  awk -v l="$label" -v rm="$rms" -v nm="$nms" -v rs="$rsd" -v ns="$nsd" \
      -v r16="$r16" -v n16="$n16" -v r96="$r96" -v n96="$n96" \
      -v r200="$r200" -v n200="$n200" \
      'BEGIN {
        printf "%-46s mean %6.1f -> %6.1f (%+5.1f)  sd %5.1f -> %5.1f  >=16 %5.1f%% -> %5.1f%%  >=96 %5.1f%% -> %5.1f%%  >=200 %5.1f%% -> %5.1f%%\n", l, rm, nm, nm-rm, rs, ns, 100-r16, 100-n16, r96, n96, r200, n200
      }'
}

echo "Luminance 0-255 (ImageMagick Gray); game viewport 1280x720 at +160+140."
echo "Percent columns are the share of pixels at or above the level."
row "SAFE / whole viewport" sky_moon_after_spawn.png lighting_after_safe.png "$GAME"
row "SAFE / wall-spotlight 140x160+900+140" sky_moon_after_spawn.png lighting_after_safe.png "140x160+900+140"
row "SAFE / brick wall 400x300+300+250" sky_moon_after_spawn.png lighting_after_safe.png "400x300+300+250"
row "SAFE / crate+bed 750x370+250+450" sky_moon_after_spawn.png lighting_after_safe.png "750x370+250+450"
echo
row "SKY / whole viewport" sky_moon_after_sky_final.png lighting_after_sky.png "$GAME"
row "SKY / courtyard+roofs 750x370+250+430" sky_moon_after_sky_final.png lighting_after_sky.png "750x370+250+430"
row "SKY / sky+stars 900x250+200+150" sky_moon_after_sky_final.png lighting_after_sky.png "900x250+200+150"
echo
row "MOON / whole viewport" sky_moon_after_moon_final.png lighting_after_moon.png "$GAME"
row "MOON / wall 350x500+850+200" sky_moon_after_moon_final.png lighting_after_moon.png "350x500+850+200"
row "MOON / sky 600x300+200+150" sky_moon_after_moon_final.png lighting_after_moon.png "600x300+200+150"
