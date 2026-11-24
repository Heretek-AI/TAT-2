import json, glob
from collections import Counter

files = sorted(
    glob.glob("game/data/generated/levels/**/*.tatlevel.json", recursive=True)
)
colour_counts = Counter()
max_colour = 0
max_example = None
for f in files:
    d = json.load(open(f))
    for lc in d.get("landscapes", []):
        n = 0
        for l in lc.get("layers", []):
            name = l.get("layer", "").lower()
            if name == "puddle" or name == "groundwet" or "visibility" in name:
                continue
            n += 1
        colour_counts[n] += 1
        if n > max_colour:
            max_colour = n
            max_example = (
                f,
                lc.get("source"),
                [(l["layer"], l["tex"], l["channel"]) for l in lc["layers"]],
            )
print("colour layer count distribution:", dict(sorted(colour_counts.items())))
print("max colour layers:", max_colour)
print("example:", max_example)
