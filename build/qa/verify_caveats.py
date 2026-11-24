import json, glob, os

for pat in ("OldManor_P", "BeautiCorner_Startscreen_P"):
    files = glob.glob(
        "game/data/generated/levels/**/*%s*.tatlevel.json" % pat, recursive=True
    )
    print(pat, "files:", files)
    for f in files:
        d = json.load(open(f))
        lands = d.get("landscapes", [])
        print("  components:", len(lands))
        for i, lc in enumerate(lands[:3]):
            print(
                "   ", i, lc.get("heightmap"), lc.get("weightmap"), lc.get("weightmaps")
            )
        # check existence of referenced pngs
        missing = 0
        for lc in lands:
            for p in [lc.get("heightmap", "")] + list(lc.get("weightmaps", [])):
                if not p:
                    continue
                rel = p.replace("res://", "game/")
                if not os.path.exists(rel):
                    missing += 1
        print("  missing referenced png paths:", missing)
