import json, glob

files = sorted(
    glob.glob("game/data/generated/levels/**/*.tatlevel.json", recursive=True)
)
empty_entries = 0
total_entries = 0
for f in files:
    d = json.load(open(f))
    for lc in d.get("landscapes", []):
        for w in lc.get("weightmaps", []):
            total_entries += 1
            if w == "":
                empty_entries += 1
print("weightmap entries:", total_entries, "empty:", empty_entries)
