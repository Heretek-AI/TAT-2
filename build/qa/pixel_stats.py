#!/usr/bin/env python3
"""QA-only pixel statistics for the lighting captures (gitignored build/qa).

Uses Pillow only; grayscale conversion is ITU-R 601 luma (0-255).
"""

from pathlib import Path

from PIL import Image

QA = Path(__file__).resolve().parent
GAME = (160, 140, 1440, 860)  # 1280x720 game viewport inside the 1600x1000 root


def stats(path: Path, box=None):
    im = Image.open(path).convert("L")
    if box is not None:
        im = im.crop(box)
    hist = im.histogram()
    total = sum(hist)

    def pct_at(fraction):
        target = total * fraction
        acc = 0
        for i, count in enumerate(hist):
            acc += count
            if acc >= target:
                return float(i)
        return 255.0

    mean = sum(i * c for i, c in enumerate(hist)) / total
    return {
        "mean": mean,
        "median": pct_at(0.5),
        "p10": pct_at(0.10),
        "p90": pct_at(0.90),
        "pct_lt_16": sum(hist[:16]) / total * 100.0,
        "pct_gt_96": sum(hist[97:]) / total * 100.0,
    }


def show(label, ref, new, box=None):
    r = stats(QA / ref, box)
    n = stats(QA / new, box)
    print(f"\n{label}")
    print(
        f"  ref {ref}: mean={r['mean']:.1f} median={r['median']:.0f} "
        f"p10={r['p10']:.0f} p90={r['p90']:.0f} "
        f"<16={r['pct_lt_16']:.1f}% >96={r['pct_gt_96']:.1f}%"
    )
    print(
        f"  new {new}: mean={n['mean']:.1f} median={n['median']:.0f} "
        f"p10={n['p10']:.0f} p90={n['p90']:.0f} "
        f"<16={n['pct_lt_16']:.1f}% >96={n['pct_gt_96']:.1f}%"
    )
    print(
        f"  delta mean={n['mean'] - r['mean']:+.1f} "
        f"median={n['median'] - r['median']:+.0f}"
    )


print("Luminance is 0-255 sRGB; game viewport = (160,140)-(1440,860).")
show(
    "SAFE ROOM / whole viewport",
    "sky_moon_after_spawn.png",
    "lighting_after_safe.png",
    GAME,
)
show(
    "SAFE ROOM / wall-spotlight area (global 900,140-1040,300)",
    "sky_moon_after_spawn.png",
    "lighting_after_safe.png",
    (900, 140, 1040, 300),
)
show(
    "SAFE ROOM / crate+bed area (global 250,450-1000,820)",
    "sky_moon_after_spawn.png",
    "lighting_after_safe.png",
    (250, 450, 1000, 820),
)

show(
    "SKY / whole viewport",
    "sky_moon_after_sky_final.png",
    "lighting_after_sky.png",
    GAME,
)
show(
    "SKY / courtyard+roofs (global 250,430-1000,800)",
    "sky_moon_after_sky_final.png",
    "lighting_after_sky.png",
    (250, 430, 1000, 800),
)
show(
    "SKY / sky+stars (global 200,150-1100,400)",
    "sky_moon_after_sky_final.png",
    "lighting_after_sky.png",
    (200, 150, 1100, 400),
)

show(
    "MOON / whole viewport",
    "sky_moon_after_moon_final.png",
    "lighting_after_moon.png",
    GAME,
)
show(
    "MOON / wall (global 850,200-1200,700)",
    "sky_moon_after_moon_final.png",
    "lighting_after_moon.png",
    (850, 200, 1200, 700),
)
show(
    "MOON / sky (global 200,150-800,450)",
    "sky_moon_after_moon_final.png",
    "lighting_after_moon.png",
    (200, 150, 800, 450),
)
