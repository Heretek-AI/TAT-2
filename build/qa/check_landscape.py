import json

d = json.load(open("extracted/json/Maps/Guildhall/Guildhall_Landscape.json"))
for obj in d:
    name = obj.get("Name", "")
    if "LandscapeComponent_11" in name:
        props = obj.get("Properties", {})
        print("Name:", name, "Class:", obj.get("Class"))
        print("Outer:", obj.get("Outer"))
        print("WeightmapTextures:")
        for wt in props.get("WeightmapTextures", []):
            print("  ", wt.get("ObjectName"), "->", wt.get("ObjectPath"))
        print("WeightmapLayerAllocations:")
        for a in props.get("WeightmapLayerAllocations", []):
            li = (a.get("LayerInfo") or {}).get("ObjectName", "")
            print(
                "  layer=",
                li,
                "tex=",
                a.get("WeightmapTextureIndex"),
                "ch=",
                a.get("WeightmapTextureChannel"),
            )
        print("WeightmapScaleBias:", props.get("WeightmapScaleBias"))
        print()
