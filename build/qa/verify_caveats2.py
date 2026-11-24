import json, os

f = "game/data/generated/levels/Menus/MainMenu/BeautifulCorner_Startscreen_P.tatlevel.json"
d = json.load(open(f))
lands = d.get("landscapes", [])
print("components:", len(lands))
missing = 0
for lc in lands:
    for p in [lc.get("heightmap", "")] + list(lc.get("weightmaps", [])):
        if not p:
            continue
        if not os.path.exists(p.replace("res://", "game/")):
            missing += 1
print("missing referenced png paths:", missing)
for lc in lands[:2]:
    print(lc.get("heightmap"), lc.get("weightmap"), lc.get("weightmaps"))
