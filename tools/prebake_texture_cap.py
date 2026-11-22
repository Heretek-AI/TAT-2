#!/usr/bin/env python3
"""Pre-bake the 1024 px long-edge cap into loader-managed PNG imports.

`level_loader.gd` (PG-1) currently caps oversized textures at load time in
`_cap_image()`: every texture is decoded at full resolution and then resized
in RAM. That avoids 8 GB of VRAM on an 8 GB card, but it still decodes
2048/4096 px PNGs on every load. This tool moves the same cap into Godot's
import settings so the `.ctex` is stored at the capped size and the runtime
resize becomes a no-op.

Scope is deliberately narrow -- only PNGs the level loader manages:

* every ``res://...png`` value in a ``texs`` dict of
  ``game/data/generated/materials.json``; and
* every ``res://assets/...png`` literal in ``game/src/core/level_loader.gd``.

For each target whose source long edge exceeds ``--cap`` (default 1024), the
matching ``.png.import`` sidecar gets exactly two settings:

    mipmaps/generate=true
    process/size_limit=<cap>

Everything else is preserved byte-for-byte, including ``compress/mode=0``,
``uid=``, ``dest_files=`` and the source PNG. The sidecar's ``dest_files``
(``.ctex`` plus its ``.md5``) are deleted so the next Godot ``--import``
rebuilds them at the capped size.

Safety / behaviour:

* ``--dry-run`` is read-only: no sidecar, manifest, PNG or dest file changes.
* A second apply is idempotent: already-capped files report ``already`` and
  their dest files are left alone.
* ``--revert`` restores the original values recorded in
  ``build/texture_cap_manifest.json`` and deletes the dest files again so the
  next reimport rebuilds the uncapped chain.
* An existing tighter size limit (0 < limit < cap) is left alone rather than
  loosened.

Use ``make desktop-texture-cap`` after any fresh extraction: the extraction
wipes ``extracted/`` (and therefore these sidecars); rerunning the target is
required.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import struct
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, NoReturn

ROOT = Path(__file__).resolve().parent.parent
MATERIALS_REL = Path("game/data/generated/materials.json")
LOADER_REL = Path("game/src/core/level_loader.gd")
MANIFEST_REL = Path("build/texture_cap_manifest.json")

PNG_SIG = b"\x89PNG\r\n\x1a\n"
CAP_KEYS = ("process/size_limit", "mipmaps/generate")
DEFAULT_CAP = 1024
MIN_CAP = 16
MAX_CAP = 16384

# Keys inside [params] are unquoted "key=value"; uid/dest_files/source_file are
# quoted values under other sections. This map is used to prove that a rewrite
# touched nothing except the two cap keys.
_PARAM_LINE = re.compile(r"(?m)^([A-Za-z0-9_./]+)=(.*)$")
_LOADER_LITERAL = re.compile(r'res://assets/[^"\'\s]+?\.png', re.IGNORECASE)


def _error(message: str) -> NoReturn:
    print(f"prebake_texture_cap: error: {message}", file=sys.stderr)
    raise SystemExit(1)


def _res_to_path(root: Path, res_path: str) -> Path:
    """Map res:// to the Godot project root at <repo>/game."""
    if not res_path.startswith("res://"):
        _error(f"not a res:// path: {res_path}")
    return root / "game" / res_path[len("res://") :]


def _png_size(path: Path) -> tuple[int, int] | None:
    """Read width/height from the PNG IHDR without decoding the image."""
    try:
        with path.open("rb") as fh:
            head = fh.read(24)
    except OSError:
        return None
    if len(head) < 24 or head[:8] != PNG_SIG or head[12:16] != b"IHDR":
        return None
    width, height = struct.unpack(">II", head[16:24])
    if width == 0 or height == 0:
        return None
    return width, height


def _read_text(path: Path) -> str:
    # newline="" keeps CRLF sidecars byte-identical outside the edited lines.
    with path.open("r", encoding="utf-8", newline="") as fh:
        return fh.read()


def _write_text_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        mode = stat.S_IMODE(path.stat().st_mode)
    except FileNotFoundError:
        mode = 0o644
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
        os.chmod(tmp_name, mode)
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def _get_param(text: str, key: str) -> str | None:
    match = re.search(r"(?m)^" + re.escape(key) + r"=([^\r\n]*)\r?$", text)
    return match.group(1).strip() if match else None


def _set_param(text: str, key: str, value: str) -> str:
    pattern = re.compile(r"(?m)^" + re.escape(key) + r"=[^\r\n]*")
    if pattern.search(text):
        return pattern.sub(f"{key}={value}", text, count=1)
    return _insert_param(text, f"{key}={value}")


def _insert_param(text: str, line: str) -> str:
    """Insert a key at the end of [params], preserving the file's EOL style."""
    eol = "\r\n" if "\r\n" in text else "\n"
    header = re.search(r"(?m)^\[params\][^\r\n]*(\r?\n)?", text)
    if header:
        start = header.end()
        following = re.search(r"(?m)^\[", text[start:])
        if following:
            pos = start + following.start()
            return text[:pos] + line + eol + text[pos:]
        if not text.endswith(("\n", "\r")):
            text += eol
        return text + line + eol
    if not text.endswith(("\n", "\r")):
        text += eol
    return text + eol + "[params]" + eol + line + eol


def _delete_param(text: str, key: str) -> str:
    pattern = re.compile(r"(?m)^" + re.escape(key) + r"=[^\r\n]*(?:\r?\n)?")
    return pattern.sub("", text, count=1)


def _param_map(text: str) -> dict[str, str]:
    return {m.group(1): m.group(2) for m in _PARAM_LINE.finditer(text)}


def _guard_untouched(before: str, after: str, res_path: str) -> None:
    """Fail if a rewrite changed anything other than the two cap keys."""
    old = _param_map(before)
    new = _param_map(after)
    for key in sorted(set(old) | set(new)):
        if key in CAP_KEYS:
            continue
        if old.get(key) != new.get(key):
            _error(
                f"internal safety check failed for {res_path}: "
                f"unexpected change to {key!r}"
            )


def _dest_files(text: str) -> list[str]:
    match = re.search(r"(?m)^dest_files=(.*)$", text)
    if not match:
        return []
    try:
        parsed: Any = json.loads(match.group(1).strip())
    except (TypeError, ValueError):
        return []
    if not isinstance(parsed, list):
        return []
    return [str(item) for item in parsed if isinstance(item, str)]


def _dest_paths(root: Path, text: str) -> list[Path]:
    paths: list[Path] = []
    for res_path in _dest_files(text):
        if not res_path.startswith("res://"):
            continue
        dest = _res_to_path(root, res_path)
        paths.append(dest)
        paths.append(Path(str(dest) + ".md5"))
    return paths


def _delete_dests(root: Path, text: str, dry_run: bool) -> tuple[int, int]:
    """Delete the sidecar's .ctex/.md5 dest files. Returns (ctex, md5) counts."""
    ctex = 0
    md5 = 0
    for path in _dest_paths(root, text):
        if not path.is_file():
            continue
        is_md5 = path.name.endswith(".md5")
        if dry_run:
            if is_md5:
                md5 += 1
            else:
                ctex += 1
            continue
        try:
            path.unlink()
        except OSError as exc:
            _error(f"could not delete dest file {path}: {exc}")
        if is_md5:
            md5 += 1
        else:
            ctex += 1
    return ctex, md5


def _collect_targets(root: Path) -> tuple[list[str], int, int]:
    materials_path = root / MATERIALS_REL
    loader_path = root / LOADER_REL
    if not materials_path.is_file():
        _error(
            f"missing {materials_path}; run `make normalize` (or `make extract`) first"
        )
    if not loader_path.is_file():
        _error(f"missing {loader_path}; is this the repo root?")

    try:
        materials = json.loads(materials_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        _error(f"cannot read {materials_path}: {exc}")
    if not isinstance(materials, dict):
        _error(f"{materials_path} is not a JSON object")

    material_pngs: set[str] = set()
    for info in materials.values():
        if not isinstance(info, dict):
            continue
        texs = info.get("texs")
        if not isinstance(texs, dict):
            continue
        for value in texs.values():
            if (
                isinstance(value, str)
                and value.startswith("res://")
                and value.lower().endswith(".png")
            ):
                material_pngs.add(value)

    loader_pngs = set(_LOADER_LITERAL.findall(loader_path.read_text(encoding="utf-8")))
    targets = sorted(material_pngs | loader_pngs)
    return targets, len(material_pngs), len(loader_pngs)


def _load_manifest(root: Path) -> dict[str, Any]:
    path = root / MANIFEST_REL
    if not path.is_file():
        return {"version": 1, "cap": None, "entries": {}}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        _error(f"cannot read manifest {path}: {exc} (fix or remove it)")
    if not isinstance(data, dict):
        _error(f"manifest {path} is not a JSON object")
    entries = data.get("entries")
    if not isinstance(entries, dict):
        _error(f"manifest {path} has no entries object")
    return data


def _save_manifest(root: Path, manifest: dict[str, Any]) -> None:
    path = root / MANIFEST_REL
    manifest["version"] = 1
    manifest["updated_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    entries = manifest.get("entries", {})
    manifest["entries"] = {key: entries[key] for key in sorted(entries)}
    _write_text_atomic(path, json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def _mode_label(dry_run: bool) -> str:
    return "DRY-RUN" if dry_run else "APPLY"


def _report(
    counts: Counter[str],
    targets: int,
    material_pngs: int,
    loader_pngs: int,
    cap: int,
    capped_bytes: int,
    already_bytes: int,
    dest_ctex: int,
    dest_md5: int,
    dry_run: bool,
) -> None:
    skipped = sum(counts.values()) - counts["capped"] - counts["already"]
    overlap = material_pngs + loader_pngs - targets
    print(
        f"targets: {targets} "
        f"(materials.json {material_pngs}, level_loader.gd {loader_pngs}, "
        f"overlap {overlap})"
    )
    print(f"mode: {_mode_label(dry_run)} (cap {cap} px long edge)")
    print(f"capped: {counts['capped']} ({capped_bytes / 1_000_000:.1f} MB source)")
    print(f"already: {counts['already']} ({already_bytes / 1_000_000:.1f} MB source)")
    print(f"skipped: {skipped}")
    for reason in sorted(counts):
        if reason in ("capped", "already"):
            continue
        print(f"  {reason}: {counts[reason]}")
    verb = "would delete" if dry_run else "deleted"
    print(f"dest files {verb}: {dest_ctex} .ctex, {dest_md5} .md5")
    if counts["capped"] and dry_run:
        print("dry-run: no .import, PNG, manifest or dest file was written")


def _apply(root: Path, cap: int, dry_run: bool, verbose: bool) -> int:
    targets, material_pngs, loader_pngs = _collect_targets(root)
    manifest = _load_manifest(root)
    entries: dict[str, Any] = manifest["entries"]
    manifest["cap"] = cap

    counts: Counter[str] = Counter()
    capped_bytes = 0
    already_bytes = 0
    dest_ctex = 0
    dest_md5 = 0
    entries_changed = False

    for res_path in targets:
        source = _res_to_path(root, res_path)
        size = _png_size(source)
        if size is None:
            counts["missing_or_unreadable_png"] += 1
            if verbose:
                print(f"skip (not a readable PNG): {res_path}")
            continue
        longest = max(size)
        if longest <= cap:
            counts["within_cap"] += 1
            continue

        import_path = Path(str(source) + ".import")
        if not import_path.is_file():
            counts["missing_import_sidecar"] += 1
            if verbose:
                print(f"skip (no .import sidecar): {res_path}")
            continue

        text = _read_text(import_path)
        current_limit = _get_param(text, "process/size_limit")
        if current_limit is None:
            limit_value = 0
        else:
            try:
                limit_value = int(current_limit)
            except ValueError:
                counts["invalid_size_limit"] += 1
                if verbose:
                    print(f"skip (invalid size_limit={current_limit!r}): {res_path}")
                continue
        if 0 < limit_value < cap:
            counts["tighter_limit_kept"] += 1
            if verbose:
                print(f"skip (already tighter limit {limit_value}): {res_path}")
            continue

        current_mips = _get_param(text, "mipmaps/generate")
        source_bytes = source.stat().st_size
        if limit_value == cap and (current_mips or "").lower() == "true":
            counts["already"] += 1
            already_bytes += source_bytes
            if verbose:
                print(f"already capped: {res_path}")
            continue

        counts["capped"] += 1
        capped_bytes += source_bytes

        entry = entries.get(res_path)
        if (
            entry is None
            or entry.get("reverted")
            or not isinstance(entry.get("original"), dict)
        ):
            entry = {
                "source_size": [size[0], size[1]],
                "original": {
                    "process/size_limit": current_limit,
                    "mipmaps/generate": current_mips,
                },
            }
            entries[res_path] = entry
            entries_changed = True
        entry["source_size"] = [size[0], size[1]]
        entry["applied"] = {
            "process/size_limit": str(cap),
            "mipmaps/generate": "true",
        }
        entry["reverted"] = False

        if dry_run:
            ctex, md5 = _delete_dests(root, text, dry_run=True)
            dest_ctex += ctex
            dest_md5 += md5
            continue

        new_text = _set_param(text, "process/size_limit", str(cap))
        new_text = _set_param(new_text, "mipmaps/generate", "true")
        _guard_untouched(text, new_text, res_path)
        _write_text_atomic(import_path, new_text)
        ctex, md5 = _delete_dests(root, new_text, dry_run=False)
        dest_ctex += ctex
        dest_md5 += md5
        if verbose:
            print(f"capped: {res_path} ({size[0]}x{size[1]} -> <= {cap})")

    if not dry_run and (entries_changed or counts["capped"]):
        _save_manifest(root, manifest)

    _report(
        counts,
        len(targets),
        material_pngs,
        loader_pngs,
        cap,
        capped_bytes,
        already_bytes,
        dest_ctex,
        dest_md5,
        dry_run,
    )
    if not dry_run:
        print(f"manifest: {root / MANIFEST_REL}")
    elif not (root / "game/.godot").is_dir():
        print(
            "note: game/.godot is absent, so there are no dest files to delete; "
            "the next Godot --import builds them"
        )
    return 0


def _revert(root: Path, dry_run: bool, verbose: bool) -> int:
    manifest = _load_manifest(root)
    entries: dict[str, Any] = manifest["entries"]
    if not entries:
        print("revert: manifest has no entries; nothing to do")
        return 0

    counts: Counter[str] = Counter()
    dest_ctex = 0
    dest_md5 = 0
    changed = False
    fallback_limit = str(manifest.get("cap") or DEFAULT_CAP)

    for res_path in sorted(entries):
        entry = entries[res_path]
        if entry.get("reverted"):
            counts["already_reverted"] += 1
            continue
        source = _res_to_path(root, res_path)
        import_path = Path(str(source) + ".import")
        if not import_path.is_file():
            counts["missing_import_sidecar"] += 1
            if verbose:
                print(f"skip (no .import sidecar): {res_path}")
            continue

        text = _read_text(import_path)
        current = {
            "process/size_limit": _get_param(text, "process/size_limit"),
            "mipmaps/generate": _get_param(text, "mipmaps/generate"),
        }
        original = entry.get("original")
        if not isinstance(original, dict):
            original = {
                "process/size_limit": "0",
                "mipmaps/generate": "false",
            }
        applied = entry.get("applied")
        if not isinstance(applied, dict):
            applied = {
                "process/size_limit": fallback_limit,
                "mipmaps/generate": "true",
            }

        if current == {key: original.get(key) for key in CAP_KEYS}:
            # Already back at the original values (e.g. re-extracted tree).
            counts["already_original"] += 1
            entry["reverted"] = True
            changed = True
            continue
        if current != {key: applied.get(key) for key in CAP_KEYS}:
            counts["skipped_modified_sidecar"] += 1
            if verbose:
                print(f"skip (sidecar differs from applied values): {res_path}")
            continue

        new_text = text
        for key in CAP_KEYS:
            value = original.get(key)
            if value is None:
                new_text = _delete_param(new_text, key)
            else:
                new_text = _set_param(new_text, key, str(value))
        _guard_untouched(text, new_text, res_path)

        if not dry_run:
            _write_text_atomic(import_path, new_text)
        ctex, md5 = _delete_dests(root, new_text, dry_run=dry_run)
        dest_ctex += ctex
        dest_md5 += md5
        counts["reverted"] += 1
        entry["reverted"] = True
        entry["reverted_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
        changed = True
        if verbose:
            print(f"reverted: {res_path}")

    if changed and not dry_run:
        _save_manifest(root, manifest)

    verb = "would revert" if dry_run else "reverted"
    print(f"revert: {verb} {counts['reverted']} of {len(entries)} manifest entries")
    for reason in sorted(counts):
        if reason == "reverted":
            continue
        print(f"  {reason}: {counts[reason]}")
    dest_verb = "would delete" if dry_run else "deleted"
    print(f"dest files {dest_verb}: {dest_ctex} .ctex, {dest_md5} .md5")
    if dry_run:
        print("dry-run: no .import, PNG, manifest or dest file was written")
    else:
        print(f"manifest: {root / MANIFEST_REL}")
    return 0


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Write the long-edge texture cap and mipmap generation into the "
            ".png.import sidecars of loader-managed textures."
        )
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="report what would change without writing anything (run this first)",
    )
    parser.add_argument(
        "--cap",
        type=int,
        default=DEFAULT_CAP,
        metavar="PX",
        help=f"maximum long edge in pixels (default {DEFAULT_CAP})",
    )
    parser.add_argument(
        "--revert",
        action="store_true",
        help="restore original import values from the manifest",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="list every capped/skipped/reverted file",
    )
    args = parser.parse_args(argv)
    if not MIN_CAP <= args.cap <= MAX_CAP:
        parser.error(f"--cap must be between {MIN_CAP} and {MAX_CAP}")
    if args.revert and args.cap != DEFAULT_CAP:
        parser.error("--cap cannot be combined with --revert")
    return args


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    print(f"repo: {ROOT}")
    if args.revert:
        return _revert(ROOT, args.dry_run, args.verbose)
    return _apply(ROOT, args.cap, args.dry_run, args.verbose)


if __name__ == "__main__":
    raise SystemExit(main())
