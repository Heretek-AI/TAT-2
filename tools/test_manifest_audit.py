#!/usr/bin/env python3
"""Negative-control tests for tools/manifest_audit.py (stdlib only).

Run with: ``python3 tools/test_manifest_audit.py``

Each check builds a small but complete generated-content fixture, bootstraps a
baseline through the audit's explicit --bootstrap-stamps path, then mutates one
thing and asserts the gate fails for the right reason. The fixture is built with
one-byte files, but every count/schema check is the production gate.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUDIT = ROOT / "tools" / "manifest_audit.py"
CONTAINER_CLASSES = [f"BP_TestContainer{i}_C" for i in range(5)]


def _write(path: Path, data: bytes | str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, str):
        data = data.encode("utf-8")
    path.write_bytes(data)


def _json(path: Path, data) -> None:
    _write(path, json.dumps(data, indent=1) + "\n")


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _cmd(
    base: Path, extra: list[str], stage_assets: int | None, baseline: Path
) -> list[str]:
    extracted = base / "extracted"
    generated = base / "game" / "data" / "generated"
    assets = base / "game" / "assets"
    cmd = [
        sys.executable,
        str(AUDIT),
        "--extracted",
        str(extracted),
        "--generated",
        str(generated),
        "--assets",
        str(assets),
        "--steam",
        str(base / "steam"),
        "--manifest",
        str(base / "manifest.txt"),
        "--baseline",
        str(baseline),
        "--allowlists",
        str(base / "allowlists.json"),
        "--min-coverage",
        "0.99",
        "--min-exact-coverage",
        "0.99",
        "--stage-min",
        "raw=1",
        "--stage-min",
        "json=1",
        "--stage-min",
        "audio=1",
        "--stage-min",
        "audio-meta=1",
    ]
    if stage_assets is not None:
        cmd.extend(["--stage-min", f"assets={stage_assets}"])
    cmd.extend(extra)
    return cmd


def _run(
    base: Path,
    extra: list[str] | None = None,
    *,
    stage_assets: int | None = 1,
    baseline: Path | None = None,
    expect: int = 0,
    contains: str | None = None,
) -> subprocess.CompletedProcess:
    baseline = baseline or (base / "baseline.json")
    proc = subprocess.run(
        _cmd(base, extra or [], stage_assets, baseline),
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    output = proc.stdout + proc.stderr
    if proc.returncode != expect:
        raise AssertionError(
            f"expected exit {expect}, got {proc.returncode}\n"
            f"command: {' '.join(proc.args)}\n{output}"
        )
    if contains and contains not in output:
        raise AssertionError(f"missing {contains!r} in audit output:\n{output}")
    return proc


def _build_fixture(base: Path) -> None:
    extracted = base / "extracted"
    generated = base / "game" / "data" / "generated"
    assets = base / "game" / "assets"
    steam = base / "steam"
    levels = generated / "levels"
    tables = generated / "tables"
    gameplay = generated / "gameplay"
    weather = generated / "weather"
    vfx = generated / "vfx"
    localization = generated / "localization"

    # Extracted sources first so generated outputs are newer for mtime groups.
    for stage, rel in (
        ("raw", "one.bin"),
        ("json", "Maps/one.json"),
        ("audio", "one.wav"),
        ("audio-meta", "one.json"),
    ):
        _write(extracted / stage / rel, b"x")
    _write(extracted / "anims" / "usd" / "one.usd", b"x")
    _write(extracted / "raw" / "TAT/Content/Localization/Game/Game.locres", b"x")
    _write(steam / "TAT/Content/Movies/one.mp4", b"x")

    # Manifest: four payload paths, one known case-only path, one .ubulk, one pak.
    manifest = [
        "TAT/Content/Gameplay/Quests/DT_Contracts_1_to_16.uasset",
        "TAT/Content/Art/Texture/T_Test.uasset",
        "TAT/Content/Audio/WwiseSharedAssetLibrary.uasset",
        "TAT/Content/Art/Env/SM_Test.uasset",
        "TAT/Content/Audio/WwiseSharedAssetLibrary.ubulk",
        "TAT/Content/Paks/pakchunk0-Windows.pak",
    ]
    _write(base / "manifest.txt", "\n".join(manifest) + "\n")
    filelist = [
        "TAT/Content/Gameplay/Quests/DT_Contracts_1_to_16.uasset",
        "tat/content/art/texture/t_test.uasset",  # allowlisted case-only
        "TAT/Content/Audio/WwiseSharedAssetLibrary.uasset",
        "TAT/Content/Art/Env/SM_Test.uasset",
        "TAT/Content/Audio/WwiseSharedAssetLibrary.ubulk",
        "Engine/Content/EngineMaterials/WorldGridMaterial.uasset",
        "Engine/Content/BasicShapes/Cube.uasset",
        "Engine/Content/BasicShapes/Plane.uasset",
        "Engine/Content/BasicShapes/Sphere.uasset",
        "Engine/Content/BasicShapes/Cone.uasset",
        "Engine/Content/BasicShapes/Cylinder.uasset",
    ]
    for path in filelist:
        _write(extracted / "json" / (path.rsplit("/", 1)[-1] + ".json"), b"x")
    _write(extracted / "filelist.txt", "\n".join(filelist) + "\n")
    # Physical disk artifacts for the payload stems (M3 disk-backed coverage).
    for rel in (
        "Gameplay/Quests/DT_Contracts_1_to_16",
        "Art/Texture/T_Test",
        "Audio/WwiseSharedAssetLibrary",
        "Art/Env/SM_Test",
    ):
        _json(extracted / "json" / (rel + ".json"), {"x": 1})
    _write(extracted / "assets" / "one.png", b"x")

    _json(
        base / "allowlists.json",
        {
            "note": "fixture",
            "case_only": ["TAT/Content/Art/Texture/T_Test.uasset"],
            "case_only_ubulk": [],
            "disk_missing": [],
        },
    )

    # Content: 107 levels with the required aggregate records.
    for i in range(107):
        level = {
            "source": f"fixture_{i}",
            "meshes": [],
            "actors": [],
            "decals": [],
            "niagara": [],
        }
        if i == 0:
            level["actors"] = [
                {"class": CONTAINER_CLASSES[n % len(CONTAINER_CLASSES)]}
                for n in range(254)
            ]
            level["decals"] = [{"name": f"d{n}"} for n in range(675)]
            level["niagara"] = [{"name": f"n{n}"} for n in range(3695)]
        _json(levels / f"L{i}.tatlevel.json", level)

    _json(
        gameplay / "containers.json",
        {"classes": {name: {"kind": "major"} for name in CONTAINER_CLASSES}},
    )
    _json(
        gameplay / "contracts.json",
        {
            "contracts": [{"id": f"Contract.Main.{i}"} for i in range(16)],
            "mission_loot_goals": {"Mission.Guildhall.LootTheRoom": [4000, 6000, 8000]},
        },
    )
    counts = [196] * 21
    counts[0] += 4118 - sum(counts)
    _json(
        gameplay / "devices.json",
        {
            "total": 4118,
            "families": {f"family{i}": {"count": n} for i, n in enumerate(counts)},
        },
    )
    for name in ("loot_actors", "spawners", "interactables"):
        _json(gameplay / f"{name}.json", {"records": [1]})

    for i in range(144):
        _json(
            tables / f"T{i}.json",
            {"type": "DataTable", "name": f"T{i}", "rows": {"r": i}},
        )

    texture = assets / "ue" / "Raw" / "T_Albedo.png"
    _write(texture, b"x")
    materials = {}
    for i in range(1629):
        if i < 1379:
            materials[f"/Game/M{i}"] = {
                "texs": {"albedo": "res://assets/ue/Raw/T_Albedo.png"}
            }
        else:
            materials[f"/Game/M{i}"] = {}
    _json(generated / "materials.json", materials)
    _json(generated / "mesh_materials.json", {"materials": {"x": 1}})
    _json(generated / "mesh_materials_provenance.json", {"materials": {"x": 1}})

    for i in range(17):
        _json(weather / f"W{i}.json", {"x": 1})
    for i in range(2):
        _json(vfx / f"V{i}.json", {"x": 1})

    for i in range(5018):
        _write(assets / "ue" / "audio" / "wwise" / f"clip_{i}.ogg", b"x")
    _json(
        generated / "audio_library.json",
        {"counts": {"clips": 5018, "failed": 0}, "failures": []},
    )
    _json(generated / "audio_events.json", {"events": [1]})

    for i in range(995):
        _write(assets / "ue" / "Anims" / f"anim_{i}.glb", b"x")
    _json(
        generated / "anims_manifest.json",
        {"ok": 995, "fail": 0, "total": 995, "entries": [f"a{i}" for i in range(995)]},
    )

    for i in range(15):
        _write(assets / "ue" / "videos" / f"v{i}.ogv", b"x")
    _json(generated / "videos.json", [{"id": f"v{i}"} for i in range(15)])

    for i in range(8):
        _write(localization / f"locale{i}.csv", "keys,en\nkey,value\n")
    _json(
        generated / "scene_variants.json",
        {"count": 222, "variants": [{"id": f"v{i}"} for i in range(222)]},
    )

    # errors.log marker binds the log to this filelist.
    filelist_sha = _sha(extracted / "filelist.txt")
    _write(
        extracted / "errors.log",
        f"# run 2026-11-24T00:00:00Z filelist {filelist_sha} errors 0\n",
    )


def _reset_weather_mtimes(base: Path, value: float | None = None) -> None:
    now = time.time() if value is None else value
    for path in (base / "game/data/generated/weather").rglob("*.json"):
        os.utime(path, (now, now))


def _touch_errors(base: Path) -> None:
    path = base / "extracted/errors.log"
    now = time.time()
    os.utime(path, (now, now))


def _touch_weather_vfx(base: Path) -> None:
    now = time.time()
    for rel in ("weather", "vfx"):
        for path in (base / "game/data/generated" / rel).rglob("*.json"):
            os.utime(path, (now, now))


def main() -> int:
    passed = 0
    with tempfile.TemporaryDirectory(prefix="tat2-audit-test-") as td:
        base = Path(td)
        _build_fixture(base)
        baseline = base / "baseline.json"

        # Bootstrap is explicit; normal run then compares the tracked baseline.
        _run(base, ["--bootstrap-stamps"])
        assert baseline.exists()
        _run(base)
        print("ok bootstrap + normal")
        passed += 1

        # First run without a baseline must fail; bootstrap creates one.
        missing = base / "missing-baseline.json"
        _run(base, baseline=missing, expect=1, contains="baseline")
        _run(base, ["--bootstrap-stamps"], baseline=missing)
        _run(base, baseline=missing)
        missing.unlink()
        print("ok missing baseline fails then bootstrap")
        passed += 1

        # B1: every producer output path must exist and be non-empty.
        loot = base / "game/data/generated/gameplay/loot_actors.json"
        loot_bytes = loot.read_bytes()
        loot.unlink()
        _run(base, expect=1, contains="loot_actors.json is missing")
        _write(loot, loot_bytes)
        _run(base)

        weather_file = base / "game/data/generated/weather/W0.json"
        weather_bytes = weather_file.read_bytes()
        weather_file.unlink()
        _run(base, expect=1, contains="output gen:weather decreased")
        _write(weather_file, weather_bytes)
        _run(base)
        for rel in (
            "game/data/generated/gameplay/spawners.json",
            "game/data/generated/gameplay/interactables.json",
            "game/data/generated/audio_events.json",
            "game/data/generated/mesh_materials.json",
            "game/data/generated/mesh_materials_provenance.json",
        ):
            path = base / rel
            data = path.read_bytes()
            path.unlink()
            _run(base, expect=1, contains=f"{path.name} is missing")
            _write(path, data)
            _run(base)
        print("ok missing producer output")
        passed += 1

        # B4: empty tables and empty loot-goal maps are rejected.
        table = base / "game/data/generated/tables/T0.json"
        table_bytes = table.read_bytes()
        _write(table, "{}\n")
        _run(base, expect=1, contains="tables: 1 JSON files have no rows/entries")
        _write(table, table_bytes)
        _run(base)

        contracts = base / "game/data/generated/gameplay/contracts.json"
        contracts_bytes = contracts.read_bytes()
        mutated = json.loads(contracts_bytes)
        mutated["mission_loot_goals"] = {}
        _json(contracts, mutated)
        _run(base, expect=1, contains="mission_loot_goals")
        _write(contracts, contracts_bytes)
        _run(base)
        print("ok empty tables and loot goals")
        passed += 1

        # B4: referenced binary artifacts must exist and be non-zero.
        glb = base / "game/assets/ue/Anims/anim_0.glb"
        glb_bytes = glb.read_bytes()
        glb.unlink()
        _run(base, expect=1, contains="expected >= 995 .glb")
        _write(glb, glb_bytes)
        _run(base)

        ogg = base / "game/assets/ue/audio/wwise/clip_0.ogg"
        ogg_bytes = ogg.read_bytes()
        ogg.unlink()
        _run(base, expect=1, contains="expected >= 5018 .ogg")
        _write(ogg, ogg_bytes)
        _run(base)

        tex = base / "game/assets/ue/Raw/T_Albedo.png"
        tex_bytes = tex.read_bytes()
        tex.write_bytes(b"")
        _run(base, expect=1, contains="referenced textures are zero bytes")
        _write(tex, tex_bytes)
        _run(base)

        video = base / "game/assets/ue/videos/v0.ogv"
        video.write_bytes(b"")
        _run(base, expect=1, contains="zero-byte .ogv")
        _write(video, b"x")
        _run(base)

        csv_file = base / "game/data/generated/localization/locale0.csv"
        csv_bytes = csv_file.read_bytes()
        csv_file.write_bytes(b"")
        _run(base, expect=1, contains="localization: 1 empty .csv")
        _write(csv_file, csv_bytes)
        _run(base)
        print("ok missing/zero assets")
        passed += 1

        # H6: translations are an import-gate artifact, not normalize output.
        _run(base)  # normalize-only tree passes with no .translation files
        translations = base / "game/data/generated/localization"
        for i in range(8):
            _write(translations / f"locale{i}.en.translation", b"x")
        _write(base / "extracted/assets/one.import", b"x")
        _run(base, ["--require-imports", "--min-imports", "1"])
        (translations / "locale0.en.translation").unlink()
        _run(
            base,
            ["--require-imports", "--min-imports", "1"],
            expect=1,
            contains=".translation",
        )
        for path in translations.glob("*.translation"):
            path.unlink()
        (base / "extracted/assets/one.import").unlink()
        _run(base)
        print("ok import gate and missing translations")
        passed += 1

        # B2/M9: import-only assets fail; a valid extraction-only payload passes.
        assets_stage = base / "extracted/assets"
        one_png = assets_stage / "one.png"
        one_png_bytes = one_png.read_bytes()
        one_png.unlink()
        payloads = []
        for i in range(6500):
            path = assets_stage / f"payload_{i}.png"
            _write(path, b"x")
            payloads.append(path)
        now = time.time()
        for rel in (
            "materials.json",
            "mesh_materials.json",
            "mesh_materials_provenance.json",
        ):
            target = base / "game/data/generated" / rel
            os.utime(target, (now, now))
        _run(base, stage_assets=None)  # default 6500 floor, no import sidecars
        for path in payloads:
            path.unlink()
        import_dir = assets_stage / "imported"
        for i in range(11000):
            _write(import_dir / f"f{i}.uasset.import", b"")
        _run(
            base,
            stage_assets=None,
            expect=1,
            contains="stage assets: expected >= 6500 payload files",
        )
        shutil.rmtree(import_dir)
        _write(one_png, one_png_bytes)
        now = time.time()
        for rel in (
            "materials.json",
            "mesh_materials.json",
            "mesh_materials_provenance.json",
        ):
            target = base / "game/data/generated" / rel
            os.utime(target, (now, now))
        _run(base)
        print("ok import-only assets fail / extraction-only assets pass")
        passed += 1

        # Baseline/producer drift, refresh behaviour, corrupt baseline.
        drift = base / "drift.json"
        drift.write_bytes(baseline.read_bytes())
        drift_data = json.loads(drift.read_text())
        drift_data["producers"]["tools/parse_weather.py"]["sha256"] = "0" * 64
        _json(drift, drift_data)
        _run(
            base,
            baseline=drift,
            expect=1,
            contains="producer tools/parse_weather.py changed",
        )
        print("ok producer drift")
        passed += 1

        corrupt = base / "corrupt.json"
        _write(corrupt, "{not json")
        _run(base, ["--refresh-stamps"], baseline=corrupt)
        _run(base, baseline=corrupt)
        print("ok corrupt baseline + refresh")
        passed += 1

        refresh_missing = base / "refresh-missing.json"
        refresh_missing.write_bytes(baseline.read_bytes())
        _reset_weather_mtimes(base, 1.0)
        weather_bytes = weather_file.read_bytes()
        weather_file.unlink()
        _run(
            base,
            ["--refresh-stamps"],
            baseline=refresh_missing,
            expect=1,
            contains="output gen:weather decreased",
        )
        _write(weather_file, weather_bytes)
        _reset_weather_mtimes(base)
        print("ok refresh refuses missing output")
        passed += 1

        refresh_old = base / "refresh-old.json"
        refresh_old.write_bytes(baseline.read_bytes())
        old_data = json.loads(refresh_old.read_text())
        old_data["producers"]["tools/parse_weather.py"]["sha256"] = "1" * 64
        _json(refresh_old, old_data)
        _reset_weather_mtimes(base, 1.0)
        _run(
            base,
            ["--refresh-stamps"],
            baseline=refresh_old,
            expect=1,
            contains="outputs were not regenerated",
        )
        _reset_weather_mtimes(base)
        _run(base)
        print("ok refresh refuses unregenerated outputs")
        passed += 1

        # H7/M8: errors.log marker, stale, zero-byte, whitespace-only.
        errors = base / "extracted/errors.log"
        errors_bytes = errors.read_bytes()
        errors.unlink()
        _run(base, expect=1, contains="errors.log: MISSING")
        _write(errors, errors_bytes)
        _run(base)

        errors.write_bytes(b"")
        _run(base, expect=1, contains="zero-byte log")
        _write(errors, errors_bytes)

        old = time.time() - 3600
        os.utime(errors, (old, old))
        _run(base, expect=1, contains="errors.log: STALE")
        now = time.time()
        os.utime(errors, (now, now))
        _write(errors, "\n   \n")
        _run(base)
        _write(errors, errors_bytes)
        _run(base)
        print("ok errors.log missing/stale/zero/whitespace")
        passed += 1

        # H3: case-only loss outside the allowlist and .ubulk loss.
        manifest = base / "manifest.txt"
        filelist = base / "extracted/filelist.txt"
        manifest_bytes = manifest.read_bytes()
        filelist_bytes = filelist.read_bytes()
        _write(
            manifest,
            manifest_bytes.decode() + "TAT/Content/Art/New/Thing.uasset\n",
        )
        _write(
            filelist,
            filelist_bytes.decode() + "tat/content/art/new/thing.uasset\t1\n",
        )
        disk = base / "extracted/json/Art/New/Thing.json"
        _json(disk, {"x": 1})
        _run(base, expect=1, contains="exact-case misses")
        _write(manifest, manifest_bytes)
        _write(filelist, filelist_bytes)
        _touch_errors(base)
        disk.unlink()
        _run(base)

        _write(
            filelist,
            filelist_bytes.decode().replace(
                "TAT/Content/Audio/WwiseSharedAssetLibrary.ubulk\n", ""
            ),
        )
        _run(base, expect=1, contains=".ubulk companions missing")
        _write(filelist, filelist_bytes)
        _touch_errors(base)
        _run(base)
        print("ok case-only loss and .ubulk loss")
        passed += 1

        # M3: a filelist entry with no disk artifact is caught.
        disk = base / "extracted/json/Art/Env/SM_Test.json"
        disk_bytes = disk.read_bytes()
        disk.unlink()
        _run(base, expect=1, contains="no disk artifact")
        _write(disk, disk_bytes)
        _touch_weather_vfx(base)
        _run(base)
        print("ok disk-backed coverage")
        passed += 1

    print(f"PASS: {passed} control groups")
    return 0


if __name__ == "__main__":
    sys.exit(main())
