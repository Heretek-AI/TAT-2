# Evidence task-1 — UE ground-truth backlog (Todo 1)

Backlog: `.omo/waves/tat2-ground-truth/backlog.md` (14 value rows F1–F14 + machine-checkable JSON index).
Verify command (exit 0, 14 keys): parse the `json` code block in backlog.md with `python3 -c` and assert 14 finding keys each with `source` + `status`. See Verification below.

## Method

1. Read plan Todo 1 + draft Findings F1–F14 ledger + KEYFRAME_INDEX.md (S01–S27, KF01–KF30).
2. Read `tools/tat-extract/{Program,Exporter}.cs` (CUE4Parse 1.2.2.202611, GAME_UE5_5) to confirm the cooked pipeline.
3. Corrected the Pak root: plan text says `TAT/Paks/`; on disk it is `TAT/Content/Paks/` (`pakchunk0-Windows.{pak,ucas,utoc}`, `global.{ucas,utoc}`, 2.8 GB).
4. Cross-checked every row against prior extraction output (`extracted/filelist.txt` 22005 entries; `extracted/json/` 12560 files) with `json.load` — counts quoted in backlog.md.
5. Named Ghidra targets (`TAT-Win64-Shipping.exe`) with UE export anchors and `offset: TBD` where cooked data cannot yield the value. No Ghidra run, no decompiled bodies, no invented offsets.

## Happy vs stalled path per finding

- F1 floating Den props — HAPPY (cooked): `ThievesDen_Geo.json` 348 exports; per-prop transforms available. Fix todo grounds props from these transforms.
- F2 ledger/market — HAPPY (cooked): `SM/MI_OpenedLedger`, `T_OpenedLedger_*`, `T_Map_ThievesDen_D`, CLS/DT contract tables present. Layout cites KF07/KF08 verbatim strings.
- F3 wardrobe — HAPPY (cooked): `BP_ThievesDen_Wardrobe_Contents` 83 exports + SM/MI/MLI + shell art. Layout cites KF03/KF04.
- F4 map buildings — HAPPY (cooked): `SM/M_MapBuilding_GuildHall` + D/N/ORM textures. Grow/shrink curve type decided in Todo 10.
- F5 window vista — HAPPY (cooked): `SM_ThievesDen_WindowBorder` + Geo actor list. Exterior mesh choice finalizes in Todo 5. Cites KF02/KF06.
- F6 telescope — HAPPY (cooked): `SM_TeleScope` + `BP_HidingSpot_Telescope` (filelist) + T_TeleScope textures. Zoom/FOV numbers go through Ghidra only if UMG/BP JSON lacks them. Cites KF05.
- F7 curbs — STALLED (ghidra): no `*Curb*`/`*Kerb*` asset in filelist or `extracted/json`. Target: `TAT-Win64-Shipping.exe` + `Guildhall_Landscape` spline / `Guildhall_Geometry` curb-adjacent actors, offset TBD (Todo 8). Footage fallback KF15/KF16.
- F8 missing meshes/ground — HAPPY (cooked): `Guildhall_Landscape.json` 156 exports + `Guildhall_Geometry.json` 981 actors + `Guildhall_P.json`. Missing-bind diff runs in Todo 8. Cites KF18/KF15.
- F9 flicker — STALLED (ghidra): cull/occluder flags + glow scalars need per-export pulls not enumerated here; car-mesh path UNMAPPED pending Todo 3 probe. Target: `Guildhall_Geometry` volume actors, offset TBD (Todo 8). Footage fallback KF27/KF29 (+KF16 car sightline).
- F10 diamond light — HAPPY (cooked): `BP_VistaraDiamond_Tool` + `MI_VistaraDiamond` (emissive/energy scalars) + `SK_VistaraDiamond`. Cap finalizes in Todo 10. Cites KF21/KF22/KF09.
- F11 white guards — HAPPY (cooked): `SK_GuardEnforcer_Dyn__Body{,_Elite}` + head variants + `MI_GuardEnforcer_Body{A,C}` + `BP_GuardEnforcer_Club`. Bind coverage check runs in Todos 3/7. Cites KF16/KF25.
- F12 guard AI/anim — HAPPY (cooked): `ST_Guard` 37 exports + subtrees + `DAM_CharacterAnimationMapping_GuardBase` + `AnimSet_Guard_Club`. Transition/clip roles resolve in Todo 7. Cites KF16/KF25–KF26 + S13–S16 VO.
- F13 crank reload — HAPPY (cooked): `AN_Zipwire_Crank_Montage` AnimMontage + `SK_Zipwire` + cast-idle set. Bone-share/montage length finalize in Todo 9. Cites KF17.
- F14 RD cascade — STALLED (ghidra/probe): texture dims are cooked-enumerable but the root cause per the librarian verdict (`godotengine/godot#86631`) is engine-side live viewport/RD-target sizes, not UE data. Value source = Todo 2 probe; Ghidra texture-streaming path only if the cascade survives the probe fix. No single KF; gate is `grep -c RenderingDevice.*ERROR == 0`.

## Verification

Run from the repo root against the committed backlog:

```
python3 -c "
import json, re
t = open('.omo/waves/tat2-ground-truth/backlog.md').read()
m = re.search(r'\`\`\`json\s*(\{.*?\})\s*\`\`\`', t, re.S)
idx = json.loads(m.group(1))
assert len(idx) == 14, len(idx)
assert set(idx) == {'F%d' % i for i in range(1, 15)}, sorted(idx)
assert all('source' in v and 'status' in v for v in idx.values())
print('keys:', len(idx))
"
```

Result: exit 0, `keys: 14` (11 `found`/cooked, 3 `stalled`/ghidra: F7, F9, F14). Re-read of backlog.md from disk confirmed before reporting.
