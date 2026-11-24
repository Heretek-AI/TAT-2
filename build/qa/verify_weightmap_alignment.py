import json, glob

files = sorted(
    glob.glob("game/data/generated/levels/**/*.tatlevel.json", recursive=True)
)
mismatch = 0
empty = 0
for f in files:
    d = json.load(open(f))
    for lc in d.get("landscapes", []):
        wms = lc.get("weightmaps", [])
        wm = lc.get("weightmap", "")
        if wms:
            if wm != wms[0]:
                mismatch += 1
        else:
            empty += 1
print(
    "weightmap != weightmaps[0]:", mismatch, "components with empty weightmaps:", empty
)
