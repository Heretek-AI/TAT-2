import json, glob
from collections import Counter

files = sorted(
    glob.glob("game/data/generated/levels/**/*.tatlevel.json", recursive=True)
)
comps = 0
with_wm = 0
wm_counts = Counter()
max_wm = 0
layers_with_tex_ge_2 = 0
for f in files:
    d = json.load(open(f))
    for lc in d.get("landscapes", []):
        comps += 1
        wms = lc.get("weightmaps", [])
        if wms:
            with_wm += 1
        wm_counts[len(wms)] += 1
        max_wm = max(max_wm, len(wms))
        for layer in lc.get("layers", []):
            if int(layer.get("tex", 0)) >= 2:
                layers_with_tex_ge_2 += 1
print(
    "all levels: files=%d components=%d with_weightmaps=%d"
    % (len(files), comps, with_wm)
)
print("weightmap count distribution:", dict(sorted(wm_counts.items())), "max:", max_wm)
print("layers with tex >= 2:", layers_with_tex_ge_2)

d = json.load(
    open("game/data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json")
)
lands = d["landscapes"]
print("Guildhall components:", len(lands))
multi = [i for i, lc in enumerate(lands) if len(lc.get("weightmaps", [])) > 1]
print("Guildhall multi-weightmap indexes:", multi)
print("Guildhall multi count:", len(multi))
for i in multi:
    lc = lands[i]
    layers = [(l["layer"], l["tex"], l["channel"]) for l in lc["layers"]]
    print("  index %d: wms=%d layers=%s" % (i, len(lc["weightmaps"]), layers))

for i in (1, 6, 10):
    lc = lands[i]
    print("index %d: weightmaps=%s" % (i, lc.get("weightmaps")))
    layers = [(l["layer"], l["tex"], l["channel"]) for l in lc["layers"]]
    print("  layers=%s" % (layers,))
