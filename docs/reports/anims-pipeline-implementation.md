# Stage implementation: animation export pipeline (anims)

## Stage id
`anims-pipeline` — produce verifiable UE animation data as Godot-importable GLBs.

## Problem (verified red)
- `make extract` never ran `anims`; `./tat-extract anims` failed every package with
  `Animation export does not support format Gltf2. Available formats: ActorX, UEFormat, USD`.
- Zero animation files existed under `extracted/assets`; no character/guard animation in Godot.

## Deliverables
1. **`tools/tat-extract/Exporter.cs`** — new `AnimOpts()` (`EMeshFormat.USD`, mesh Gltf2 path
   untouched); `Anims()` writes to `extracted/anims/usd/`, matches `AN_`/`A_`/`AS_` prefixes
   plus `/Animation/` paths (the old `A_` prefix never matched `AN_*`), runs `FixBackslashPaths`,
   and counts empty results as failures.
2. **`tools/tat-extract/native/linux-x64/CUE4Parse-Natives.so`** (63 KB) — Linux build of the
   upstream ACL decoder (sources: `FabianFG/CUE4Parse@1.2.2.202611`, `CUE4Parse-Natives/` +
   pinned `nfrechette/acl@414689d` + `rtm@d7982f2`, cmake Release, ACL-only). Without it, all
   357 ACL-compressed anims fail with `Unable to load shared library 'CUE4Parse-Natives'`
   (the nuget only ships a Windows DLL). `make build-extractor` stages it next to the exe.
3. **`tools/usd_to_gltf.py`** — headless-Blender USDA→GLB converter: single-file and batch
   modes, `--filter`, layered-action stats (Blender 4.4+ `layers/strips/channelbags`), per-file
   authored frame-rate preservation (`timeCodesPerSecond` → `fps`/`fps_base`), and `--manifest`.
4. **`Makefile`** — `anims` step added to `extract`; new `make anims` target
   (export USD → Blender batch → GLBs + manifest).
5. **`game/assets/ue/Anims/<same relative path>.glb`** — 995 GLBs, 487 MB total (gitignored worktree artifacts).
6. **`game/data/generated/anims_manifest.json`** — 995 entries: source package → glb +
   animation name + duration + track/sampler counts (gitignored worktree artifact).

## Verification (actual command output)
- Sample export: `[anims] ok=1 fail=0`; `AN_ThiefNisha_Zipwire_Walk_Left.usda` 897 KB, 259 lines,
  `SkelAnimation` with per-frame `translations/rotations/scales` timeSamples, frames 0–74 @ 60.8108 tcs.
- Sample GLB JSON chunk: 1 animation (`AN_ThiefNisha_Zipwire_Walk_Left`), **501 channels /
  501 samplers**, 169 nodes, 1 skin; Blender-side 1,670 curves / 125,250 keys.
- Timing fidelity: GLB duration **1.2168889s** vs authored 74/60.8108 = **1.2168889s** (exact;
  Blender's exporter uses `frame/(fps*fps_base)`, verified empirically across fps/base combos).
- Full run: export `ok=995 fail=14`; conversion batch `ok=995 fail=0`; manifest `ok=995 fail=0`.
  All 14 export failures are `UBlendSpace`/`UBlendSpace1D`/`UAimOffsetBlendSpace` (parametric
  blend graphs, not keyframed anims — genuinely not convertible, documented not faked).
  23 zero-duration manifest entries are single-frame poses (additives, `_Fast_000`-style
  reference frames); all carry 18–1314 real tracks.
- Godot headless runtime proof (temporary `SceneTree` script, deleted after run):
  `GLTFDocument.append_from_file` → `generate_scene` → `AnimationPlayer` reports
  `AN_ThiefNisha_Zipwire_Walk_Left length=1.21688890457153 tracks=354`; manifest `ok=995 fail=0`;
  `SUMMARY: fails=0`, exit 0. (Note: `load("*.glb")` has no runtime loader; the check used
  `GLTFDocument`, the same importer the editor uses. Godot reports 354 tracks vs 501 GLB
  channels after its own track optimization; length is exact.)
- `make test`: 21/21 PASS, `SUMMARY: fails=0`, exit 0, zero SCRIPT ERROR.

## Files changed
- `tools/tat-extract/Exporter.cs` (modified, committed scope)
- `tools/usd_to_gltf.py` (new)
- `tools/tat-extract/native/linux-x64/CUE4Parse-Natives.so` (new)
- `Makefile` (modified)
- `game/assets/ue/Anims/**` + `game/data/generated/anims_manifest.json` (generated worktree artifacts, gitignored)
- `game/tests/_tmp_anims_check.gd` — created for verification, **deleted** afterwards (per conflict-avoidance rule `run_tests.gd` was not touched).

## Self-audit / unfinished
- Nothing unfinished: sample → full export → conversion → manifest → Godot proof → `make test` all green.
- Known limits stated plainly: 14 blendspace assets unsupported by CUE4Parse conversion itself
  (no keyframe data to convert); single-frame poses have duration 0 by construction.
- Did not touch `level_loader.gd`, `missions/**`, `weather_profile.gd`, Android files, or `run_tests.gd`.
