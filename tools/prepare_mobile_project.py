#!/usr/bin/env python3
"""Generate a self-contained Android build project for TAT-2.

The desktop project (`game/`) keeps its lossless textures and Forward+ renderer.
This tool materialises a throwaway project under `build/mobile_game/` that:
  * copies only the assets reachable from the levels, materials DB and scripts
  * reimports every texture as ETC2/ASTC VRAM-compressed with mipmaps + size cap
  * switches the renderer to Mobile, locks landscape, sets the Android presets
  * keeps the extracted UE content out of git (build/ is gitignored)

Usage:
  python3 tools/prepare_mobile_project.py --texture-cap 1024
  python3 tools/prepare_mobile_project.py --texture-cap 512 --abi arm64
  python3 tools/prepare_mobile_project.py --no-import   # assets only
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
DEFAULT_OUT = ROOT / "build" / "mobile_game"

# Level folders the shipped game can load (mission_controller + main menu).
USED_LEVEL_ROOTS = {
    "OldManor",
    "Guildhall",
    "ThievesDen",
    "ThievesDenTest",
    "FTUE",
    "Menus",
    "Buildings/Guildhall",
}

CODE_REF_RE = re.compile(r'res://(assets/[^"\'\n\)]+)')
SKIP_MESH_TOKENS = (
    "emissiveshapes/sm_sphere",
    "primitives/sm_shape",
    "fogsheet",
    "volumetric",
    "skysphere",
    "blocker",
)


def game_rel(res_path: str) -> str:
    return res_path[len("res://") :] if res_path.startswith("res://") else res_path


def used_level_files() -> list[Path]:
    files: list[Path] = []
    levels = GAME / "data" / "generated" / "levels"
    for path in sorted(levels.rglob("*.tatlevel.json")):
        rel = path.relative_to(levels).as_posix()
        if any(rel == root or rel.startswith(root + "/") for root in USED_LEVEL_ROOTS):
            files.append(path)
    return files


def collect_refs() -> tuple[set[str], list[str], int]:
    """Returns (relative asset paths, missing refs, level file count)."""
    refs: set[str] = set()
    missing: list[str] = []
    level_files = used_level_files()

    mesh_materials_path = GAME / "data" / "generated" / "mesh_materials.json"
    mesh_materials_raw = json.loads(mesh_materials_path.read_text())

    for path in level_files:
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError:
            missing.append(str(path.relative_to(GAME)))
            continue
        for mesh in data.get("meshes", []):
            ue_path = str(mesh.get("mesh", ""))
            if not ue_path.startswith("/Game/"):
                continue
            clean = ue_path.split(".")[0][len("/Game/") :]
            refs.add(f"assets/ue/Content/{clean}.glb")
        for landscape in data.get("landscapes", []):
            heightmap = str(landscape.get("heightmap", ""))
            if heightmap.startswith("res://"):
                refs.add(game_rel(heightmap))

    materials = json.loads((GAME / "data" / "generated" / "materials.json").read_text())
    for entry in materials.values():
        for tex in (entry.get("texs") or {}).values():
            if isinstance(tex, str) and tex.startswith("res://"):
                refs.add(game_rel(tex))

    for path in [*GAME.glob("src/**/*.gd"), *GAME.glob("scenes/**/*.tscn")]:
        for match in CODE_REF_RE.finditer(path.read_text(errors="ignore")):
            refs.add(match.group(1))

    # The loader never binds these; keep the build lean if they slipped in.
    refs = {r for r in refs if not any(tok in r.lower() for tok in SKIP_MESH_TOKENS)}
    return refs, missing, len(level_files)


def copy_refs(refs: set[str], out: Path) -> tuple[int, int, list[str]]:
    copied = 0
    total_bytes = 0
    missing: list[str] = []
    for rel in sorted(refs):
        src = GAME / rel
        if not src.is_file():
            missing.append(rel)
            continue
        dst = out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied += 1
        total_bytes += dst.stat().st_size
    return copied, total_bytes, missing


def copy_tree(src: Path, dst: Path, pattern: str = "*") -> int:
    count = 0
    if not src.exists():
        return 0
    for path in src.rglob(pattern):
        if not path.is_file():
            continue
        target = dst / path.relative_to(src)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        count += 1
    return count


def set_ini_setting(text: str, section: str, key: str, value: str) -> str:
    lines = text.splitlines()
    header = f"[{section}]"
    try:
        start = lines.index(header)
    except ValueError:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend([header, f"{key}={value}"])
        return "\n".join(lines) + "\n"
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("[") and lines[i].endswith("]"):
            end = i
            break
    for i in range(start + 1, end):
        if lines[i].split("=", 1)[0].strip() == key:
            lines[i] = f"{key}={value}"
            return "\n".join(lines) + "\n"
    lines.insert(end, f"{key}={value}")
    return "\n".join(lines) + "\n"


def write_project_godot(
    out: Path,
    texture_cap: int,
    autostart_contract: int = 0,
    renderer: str = "mobile",
) -> None:
    text = (GAME / "project.godot").read_text()
    text = text.replace(
        'config/features=PackedStringArray("4.7", "Forward Plus")',
        'config/features=PackedStringArray("4.7", "Mobile")',
    )
    text = set_ini_setting(text, "application", "config/icon", '"res://icon.png"')
    text = set_ini_setting(text, "display", "window/handheld/orientation", "4")
    text = set_ini_setting(
        text, "display", "window/energy_saving/keep_screen_on", "true"
    )
    text = set_ini_setting(text, "rendering", "renderer/rendering_method", '"%s"' % renderer)
    if renderer == "gl_compatibility":
        text = set_ini_setting(text, "rendering", "renderer/rendering_method.mobile", '"gl_compatibility"')
    text = set_ini_setting(
        text, "rendering", "textures/vram_compression/import_etc2_astc", "true"
    )
    text = set_ini_setting(
        text, "rendering", "lights_and_shadows/positional_shadow/atlas_size", "2048"
    )
    text = set_ini_setting(text, "rendering", "anti_aliasing/quality/msaa_3d", "0")
    if "[importer_defaults]" not in text:
        text += (
            "\n[importer_defaults]\n\n"
            "texture={\n"
            '"compress/mode": 2,\n'
            '"compress/high_quality": false,\n'
            '"mipmaps/generate": true,\n'
            f'"process/size_limit": {texture_cap}\n'
            "}\n"
        )
    if autostart_contract > 0:
        text = set_ini_setting(
            text, "tat2", "debug_autostart_contract", str(autostart_contract)
        )
    (out / "project.godot").write_text(text)


def write_export_presets(out: Path, abi: str) -> None:
    arm64 = "true" if abi in ("both", "arm64") else "false"
    x86_64 = "true" if abi in ("both", "x86_64") else "false"
    icons = out / "branding"
    preset = f"""[preset.0]

name="Android"
platform="Android"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="{out / "tat2-mobile.apk"}"
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
gradle_build/export_format=0
gradle_build/min_sdk=""
gradle_build/target_sdk=""
architectures/armeabi-v7a=false
architectures/arm64-v8a={arm64}
architectures/x86=false
architectures/x86_64={x86_64}
version/code=1
version/name="1.0.0"
package/unique_name="com.heretek.tat2"
package/name="Thick As Thieves 2"
package/signed=true
package/app_category=2
package/retain_data_on_uninstall=false
package/exclude_from_recents=false
package/show_in_android_tv=false
package/show_in_app_library=true
package/show_as_launcher_app=false
launcher_icons/main_192x192="{icons / "icon_192.png"}"
launcher_icons/adaptive_foreground_432x432="{icons / "icon_fg_432.png"}"
launcher_icons/adaptive_background_432x432="{icons / "icon_bg_432.png"}"
launcher_icons/adaptive_monochrome_432x432=""
graphics/opengl_debug=false
xr_features/xr_mode=0
screen/immersive_mode=true
screen/support_small=true
screen/support_normal=true
screen/support_large=true
screen/support_xlarge=true
user_data_backup/allow=false
command_line/extra_args=""
apk_expansion/enable=false
apk_expansion/SALT=""
apk_expansion/public_key=""
permissions/custom_permissions=PackedStringArray()
permissions/internet=true
permissions/vibrate=true
"""
    (out / "export_presets.cfg").write_text(preset)


def build_icons(out: Path) -> bool:
    portrait = GAME / "assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_spider.png"
    magick = shutil.which("magick") or shutil.which("convert")
    if not portrait.is_file() or not magick:
        print("  icons: skipped (missing portrait or ImageMagick)")
        return False
    branding = out / "branding"
    branding.mkdir(parents=True, exist_ok=True)

    def run(args: list[str]) -> None:
        subprocess.run([magick, *args], check=True)

    run(
        [
            str(portrait),
            "-resize",
            "192x192^",
            "-gravity",
            "center",
            "-extent",
            "192x192",
            str(branding / "icon_192.png"),
        ]
    )
    run(
        [
            str(portrait),
            "-resize",
            "360x360",
            "-background",
            "none",
            "-gravity",
            "center",
            "-extent",
            "432x432",
            str(branding / "icon_fg_432.png"),
        ]
    )
    run(["-size", "432x432", "xc:#1b1f2a", str(branding / "icon_bg_432.png")])
    run(
        [
            str(portrait),
            "-resize",
            "256x256^",
            "-gravity",
            "center",
            "-extent",
            "256x256",
            str(out / "icon.png"),
        ]
    )
    return True


def run_import(out: Path) -> None:
    cmd = [
        "flatpak",
        "run",
        "org.godotengine.Godot",
        "--headless",
        "--path",
        str(out),
        "--import",
    ]
    print("  running:", " ".join(cmd))
    result = subprocess.run(cmd, capture_output=True, text=True)
    tail = "\n".join((result.stdout + result.stderr).splitlines()[-8:])
    print(tail)
    if result.returncode != 0:
        sys.exit(f"Godot import failed with exit code {result.returncode}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument(
        "--texture-cap", type=int, default=1024, choices=(256, 512, 1024, 2048)
    )
    parser.add_argument("--abi", default="both", choices=("both", "arm64", "x86_64"))
    parser.add_argument("--autostart-contract", type=int, default=0)
    parser.add_argument("--renderer", default="mobile", choices=("mobile", "gl_compatibility"))
    parser.add_argument("--no-import", action="store_true")
    parser.add_argument("--no-icons", action="store_true")
    parser.add_argument(
        "--clean",
        action="store_true",
        help="delete the output project and its import cache",
    )
    args = parser.parse_args()

    out: Path = args.out.resolve()
    if out.exists() and args.clean:
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)

    print(f"[1/6] source tree -> {out}")
    copy_tree(GAME / "src", out / "src")
    copy_tree(GAME / "scenes", out / "scenes")
    copy_tree(
        GAME / "data" / "generated" / "tables", out / "data" / "generated" / "tables"
    )
    for name in ("materials.json", "mesh_materials.json"):
        shutil.copy2(
            GAME / "data" / "generated" / name, out / "data" / "generated" / name
        )

    print("[2/6] level files")
    levels_out = out / "data" / "generated" / "levels"
    level_count = 0
    for path in used_level_files():
        target = levels_out / path.relative_to(GAME / "data" / "generated" / "levels")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        level_count += 1
    print(f"  {level_count} .tatlevel.json")

    print("[3/6] referenced assets")
    refs, level_missing, _ = collect_refs()
    copied, total_bytes, missing = copy_refs(refs, out)
    print(f"  {copied} files, {total_bytes / 1048576:.0f} MB source")
    if missing:
        print(
            f"  {len(missing)} refs not found (optional fallbacks); first 5: {missing[:5]}"
        )

    print("[4/6] project.godot + export preset")
    write_project_godot(out, args.texture_cap, args.autostart_contract, args.renderer)
    write_export_presets(out, args.abi)
    if not args.no_icons:
        build_icons(out)

    print("[5/6] manifest")
    manifest = {
        "texture_cap": args.texture_cap,
        "renderer": args.renderer,
        "abi": args.abi,
        "levels": level_count,
        "assets_copied": copied,
        "assets_source_bytes": total_bytes,
        "missing_refs": missing,
        "level_missing": level_missing,
    }
    (ROOT / "build" / "mobile_manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"  build/mobile_manifest.json ({len(missing)} missing)")

    if not args.no_import:
        print("[6/6] Godot import (ETC2/ASTC + mipmaps)")
        run_import(out)
    print("done:", out)


if __name__ == "__main__":
    main()
