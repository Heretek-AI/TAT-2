#!/usr/bin/env python3
"""Convert the Steam .mp4 movie set to Godot-playable .ogv and emit a manifest.

Godot 4.7 plays Ogg Theora through VideoStreamPlayer; the shipped game uses MP4
(Splash, the 4K intro and 13 FTUE tutorial clips). This tool transcodes each source
once, records duration and provenance, and writes game/data/generated/videos.json.

Usage:
    python3 tools/convert_videos.py [--steam-dir DIR] [--out-dir DIR] [--manifest PATH] [--force]

Exit codes: 0 success, 1 ffmpeg missing, no sources, or a conversion failed.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

STEAM_MOVIES = "TAT/Content/Movies"


def probe_duration(path: Path) -> float:
    out = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return float(out.stdout.strip() or 0.0)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--steam-dir",
        default=str(
            Path.home() / ".local/share/Steam/steamapps/common/Thick As Thieves"
        ),
    )
    parser.add_argument("--out-dir", default=str(root / "game/assets/ue/videos"))
    parser.add_argument(
        "--manifest", default=str(root / "game/data/generated/videos.json")
    )
    parser.add_argument(
        "--force", action="store_true", help="re-encode existing .ogv files"
    )
    args = parser.parse_args()

    if shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None:
        print("ERROR: ffmpeg/ffprobe not installed", file=sys.stderr)
        return 1

    movies = Path(args.steam_dir) / STEAM_MOVIES
    sources = sorted(movies.rglob("*.mp4"))
    if not sources:
        print(f"ERROR: no .mp4 under {movies}", file=sys.stderr)
        return 1

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest: list[dict] = []
    failures = 0

    for src in sources:
        rel = src.relative_to(movies).with_suffix(".ogv")
        dst = out_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if args.force or not dst.is_file():
            result = subprocess.run(
                [
                    "ffmpeg",
                    "-y",
                    "-loglevel",
                    "error",
                    "-i",
                    str(src),
                    "-c:v",
                    "libtheora",
                    "-q:v",
                    "7",
                    "-c:a",
                    "libvorbis",
                    "-q:a",
                    "4",
                    str(dst),
                ],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                failures += 1
                print(
                    f"FAILED {src.name}: {result.stderr.strip()[:200]}", file=sys.stderr
                )
                continue
        manifest.append(
            {
                "id": src.stem,
                "source": src.relative_to(Path(args.steam_dir)).as_posix(),
                "path": f"res://assets/ue/videos/{rel.as_posix()}",
                "duration_sec": round(probe_duration(dst), 3),
            }
        )

    manifest_path = Path(args.manifest)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"videos: {len(manifest)} converted -> {out_dir}; manifest {manifest_path}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
