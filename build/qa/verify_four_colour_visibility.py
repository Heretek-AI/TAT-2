import json, glob

files = sorted(
    glob.glob("game/data/generated/levels/**/*.tatlevel.json", recursive=True)
)
hits = []
for f in files:
    d = json.load(open(f))
    for i, lc in enumerate(d.get("landscapes", [])):
        names = [l.get("layer", "") for l in lc.get("layers", [])]
        colour = [
            n
            for n in names
            if n.lower() not in ("puddle", "groundwet")
            and "visibility" not in n.lower()
        ]
        vis = any("visibility" in n.lower() for n in names)
        if len(colour) == 4 and vis:
            hits.append((f, i, lc.get("source"), len(lc.get("weightmaps", [])), names))
print("components with 4 colour layers + visibility:", len(hits))
for h in hits:
    print(h)
