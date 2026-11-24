import json, os

for f in [
    "game/data/generated/levels/OldManor/OldManor_P.tatlevel.json",
    "game/data/generated/levels/Menus/MainMenu/BeautifulCorner_Startscreen_P.tatlevel.json",
]:
    d = json.load(open(f))
    lands = d.get("landscapes", [])
    missing_h = 0
    missing_w = 0
    multi = 0
    for lc in lands:
        h = lc.get("heightmap", "")
        if h and not os.path.exists(h.replace("res://", "game/")):
            missing_h += 1
        wms = lc.get("weightmaps", [])
        if len(wms) > 1:
            multi += 1
        for w in wms:
            if w and not os.path.exists(w.replace("res://", "game/")):
                missing_w += 1
    print(
        f,
        "components",
        len(lands),
        "missing heightmaps",
        missing_h,
        "missing weightmaps",
        missing_w,
        "multi",
        multi,
    )
