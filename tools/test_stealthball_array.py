#!/usr/bin/env python3
"""Tests for tools/png_rgba.py + tools/parse_stealthball_array.py (stdlib only).

Run with: ``python3 tools/test_stealthball_array.py``

Three halves:

* PNG decode: a synthetic encoder writes one PNG per filter type (0-4) plus
  RGB / gray / gray+alpha colour types, and the reader must return the exact
  source pixels (this is the only pixel decoder in `tools/`, so a filter bug
  would silently corrupt every derived gem stat);
* derivation: 21 synthetic slices with a known directional cap and 21 with a
  centred exposure ramp are measured; the producer must report the right
  `mapping.kind`, per-slice angle/fraction and a deterministic JSON body;
* absence/incompleteness: no manifest -> `payload_absent` (exit 0, exit 2 with
  `--require-payload`), a manifest with a missing slice -> `payload_incomplete`
  and a non-zero exit.

The producer is always invoked with an explicit ``--extracted``/``--out``; the
test never writes into ``game/data`` or ``extracted/``.
"""

from __future__ import annotations

import json
import math
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRODUCER = ROOT / "tools" / "parse_stealthball_array.py"
sys.path.insert(0, str(ROOT / "tools"))

from png_rgba import PngError, read_rgba, read_rgba_bytes  # noqa: E402

FAILS = 0
CHECKS = 0


def check(cond: bool, ok: str, fail: str) -> None:
    global FAILS, CHECKS
    CHECKS += 1
    if cond:
        print("PASS:", ok)
    else:
        print("FAIL:", fail)
        FAILS += 1


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def _filter_row(ftype: int, row: bytes, prev: bytes, bpp: int) -> bytes:
    out = bytearray(len(row))
    for i, v in enumerate(row):
        left = row[i - bpp] if i >= bpp else 0
        up = prev[i] if prev else 0
        upleft = prev[i - bpp] if prev and i >= bpp else 0
        if ftype == 0:
            pred = 0
        elif ftype == 1:
            pred = left
        elif ftype == 2:
            pred = up
        elif ftype == 3:
            pred = (left + up) >> 1
        else:
            pred = _paeth(left, up, upleft)
        out[i] = (v - pred) & 0xFF
    return bytes(out)


def encode_png(
    width: int, height: int, pixels: bytes, channels: int, ftype: int
) -> bytes:
    """Encode 8-bit non-interlaced rows with one fixed filter type."""
    if channels not in (1, 2, 3, 4):
        raise ValueError("channels")
    ctype = {1: 0, 2: 4, 3: 2, 4: 6}[channels]
    stride = width * channels
    raw = bytearray()
    prev = b""
    for y in range(height):
        row = pixels[y * stride : (y + 1) * stride]
        raw.append(ftype)
        raw.extend(_filter_row(ftype, row, prev, channels))
        prev = row

    def chunk(kind: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + kind
            + body
            + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, ctype, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def test_png() -> None:
    w, h = 7, 5
    src = bytearray()
    for y in range(h):
        for x in range(w):
            src.extend(
                (
                    (x * 31 + y * 7) & 0xFF,
                    (x * 11 + y * 53) & 0xFF,
                    (x * 3 + y * 97) & 0xFF,
                    (x * 17 + y * 5) & 0xFF,
                )
            )
    src = bytes(src)
    for ftype in range(5):
        data = encode_png(w, h, src, 4, ftype)
        dw, dh, rgba = read_rgba_bytes(data)
        check(
            dw == w and dh == h and rgba == src,
            "PNG RGBA filter %d round-trips" % ftype,
            "filter %d mismatch" % ftype,
        )

    rgb = bytes(src[i] for i in range(len(src)) if i % 4 != 3)
    dw, dh, rgba = read_rgba_bytes(encode_png(w, h, rgb, 3, 1))
    expect = bytearray()
    for i in range(w * h):
        expect.extend(rgb[i * 3 : i * 3 + 3] + b"\xff")
    check(
        rgba == bytes(expect),
        "PNG RGB expands to opaque RGBA",
        "RGB expansion mismatch",
    )

    gray = bytes((x * 9 + y * 13) & 0xFF for y in range(h) for x in range(w))
    dw, dh, rgba = read_rgba_bytes(encode_png(w, h, gray, 1, 4))
    expect = bytearray()
    for v in gray:
        expect.extend(bytes((v, v, v, 255)))
    check(rgba == bytes(expect), "PNG gray expands to RGBA", "gray expansion mismatch")

    ga = bytes(
        b
        for y in range(h)
        for x in range(w)
        for b in (((x * 5 + y) & 0xFF), (x * 19 + y * 3) & 0xFF)
    )
    dw, dh, rgba = read_rgba_bytes(encode_png(w, h, ga, 2, 3))
    expect = bytearray()
    for i in range(w * h):
        v, a = ga[i * 2], ga[i * 2 + 1]
        expect.extend(bytes((v, v, v, a)))
    check(
        rgba == bytes(expect),
        "PNG gray+alpha expands to RGBA",
        "gray+alpha expansion mismatch",
    )

    try:
        read_rgba_bytes(b"not a png")
        ok = False
    except PngError:
        ok = True
    check(ok, "PNG reader rejects a non-PNG signature", "non-PNG accepted")
    try:
        bad = bytearray(encode_png(w, h, src, 4, 0))
        bad[29] = 9  # IHDR bit depth byte
        read_rgba_bytes(bytes(bad))
        ok = False
    except PngError:
        ok = True
    check(ok, "PNG reader rejects an unsupported bit depth", "bit depth 9 accepted")


def _slice_rgba(
    size: int, angle_deg: float, radius: float, cream=(232, 222, 195), dark=(10, 9, 53)
) -> bytes:
    """A disc with a lit cap whose centre sits at `angle_deg` from +x (y down)."""
    cx = cy = (size - 1) * 0.5
    rr = size * 0.46
    cap_cx = cx + math.cos(math.radians(angle_deg)) * rr * 0.55
    cap_cy = cy + math.sin(math.radians(angle_deg)) * rr * 0.55
    cap_r = rr * radius
    out = bytearray()
    for y in range(size):
        for x in range(size):
            in_disc = (x - cx) ** 2 + (y - cy) ** 2 <= rr * rr
            if not in_disc:
                out.extend((0, 0, 0, 0))
                continue
            lit = (x - cap_cx) ** 2 + (y - cap_cy) ** 2 <= cap_r * cap_r
            r, g, b = cream if lit else dark
            out.extend((r, g, b, 255))
    return bytes(out)


def _write_tree(
    root: Path, angles: list[float], radii: list[float], size: int = 64
) -> Path:
    asset = (
        root / "assets" / "Art" / "UI" / "HUD" / "Stealth_Ball" / "T_stealthball_Array"
    )
    asset.mkdir(parents=True, exist_ok=True)
    files = []
    for i, (angle, radius) in enumerate(zip(angles, radii)):
        name = "slice_%02d.png" % i
        data = encode_png(size, size, _slice_rgba(size, angle, radius), 4, 0)
        (asset / name).write_bytes(data)
        files.append(
            {
                "index": i,
                "file": name,
                "width": size,
                "height": size,
                "bytes": len(data),
            }
        )
    manifest = {
        "schema": "tat2.texture2darray/1",
        "asset": "T_stealthball_Array",
        "source_package": "TAT/Content/Art/UI/HUD/Stealth_Ball/T_stealthball_Array.uasset",
        "export_path": "Art/UI/HUD/Stealth_Ball/T_stealthball_Array",
        "width": size,
        "height": size,
        "slices": len(files),
        "pixel_format": "PF_DXT5",
        "packed_data": len(files),
        "source_mip": {"size_x": size, "size_y": size, "size_z": len(files)},
        "decode": {"slice_files": len(files), "failures": []},
        "slice_files": files,
    }
    (asset / "manifest.json").write_text(
        json.dumps(manifest, indent=1) + "\n", encoding="utf-8"
    )
    return root


def _run(extracted: Path, out: Path, *extra: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            sys.executable,
            str(PRODUCER),
            "--extracted",
            str(extracted),
            "--out",
            str(out),
            *extra,
        ],
        capture_output=True,
        text=True,
        check=False,
    )


def test_derivation() -> None:
    n = 21
    angles = [-170.0 + i * (340.0 / (n - 1)) for i in range(n)]
    radii = [0.24 + 0.01 * (i % 3) for i in range(n)]
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        _write_tree(root, angles, radii)
        out = root / "out.json"
        res = _run(root, out)
        check(
            res.returncode == 0,
            "producer exits 0 on a complete payload",
            "exit %d: %s" % (res.returncode, res.stderr),
        )
        data = json.loads(out.read_text())
        check(
            data["status"] == "payload_present" and len(data["slices"]) == n,
            "21 authored slices measured",
            "status=%s slices=%d" % (data["status"], len(data["slices"])),
        )
        check(
            data["mapping"]["kind"] == "directional",
            "moving caps derive mapping.kind=directional",
            "kind=%s spread=%s"
            % (data["mapping"]["kind"], data["mapping"]["angle_spread_deg"]),
        )
        errs = []
        for i, entry in enumerate(data["slices"]):
            got = entry["angle_deg"]
            want = math.degrees(
                math.atan2(
                    math.sin(math.radians(angles[i])), math.cos(math.radians(angles[i]))
                )
            )
            # The centroid of a circular cap is the cap centre, so the derived
            # angle must follow the painted angle within a degree.
            d = abs((got - want + 180.0) % 360.0 - 180.0)
            if d > 1.5:
                errs.append((i, round(got, 1), round(want, 1)))
        check(
            not errs,
            "every derived cap angle matches its painted direction",
            "angle errors: %s" % errs[:4],
        )
        check(
            data["mapping"]["order"]
            == sorted(range(n), key=lambda k: (data["slices"][k]["lit_fraction"], k)),
            "mapping.order sorts by measured lit fraction",
            "order mismatch",
        )
        first = out.read_bytes()
        res2 = _run(root, out)
        check(
            res2.returncode == 0 and out.read_bytes() == first,
            "producer output is byte-deterministic",
            "second run differs",
        )

        # Payload absence must be explicit, not a silent success.
        empty = root / "empty"
        empty.mkdir()
        absent = root / "absent.json"
        res3 = _run(empty, absent)
        adata = json.loads(absent.read_text())
        check(
            res3.returncode == 0
            and adata["status"] == "payload_absent"
            and adata["slices"] == [],
            "absent payload records payload_absent",
            "status=%s rc=%d" % (adata["status"], res3.returncode),
        )
        res4 = _run(empty, root / "absent2.json", "--require-payload")
        check(
            res4.returncode == 2,
            "require-payload turns absence into exit 2",
            "exit %d" % res4.returncode,
        )

        # A manifest with a missing slice is incomplete, not absent.
        (
            root / "assets/Art/UI/HUD/Stealth_Ball/T_stealthball_Array/slice_07.png"
        ).unlink()
        res5 = _run(root, root / "partial.json")
        pdata = json.loads((root / "partial.json").read_text())
        check(
            res5.returncode == 1 and pdata["status"] == "payload_incomplete",
            "missing slice records payload_incomplete and exits 1",
            "status=%s rc=%d" % (pdata["status"], res5.returncode),
        )

    # Area ramp: centred caps that grow -> mapping.kind=area_ramp, order 0..20.
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        _write_tree(root, [0.0] * n, [0.10 + 0.035 * i for i in range(n)])
        out = root / "ramp.json"
        res = _run(root, out)
        data = json.loads(out.read_text())
        check(
            res.returncode == 0 and data["mapping"]["kind"] == "area_ramp",
            "centred growing caps derive mapping.kind=area_ramp",
            "kind=%s spread=%s"
            % (data["mapping"]["kind"], data["mapping"]["angle_spread_deg"]),
        )
        check(
            data["mapping"]["order"] == list(range(n)),
            "area ramp order is the authored index order",
            "order=%s" % data["mapping"]["order"],
        )
        check(
            data["mapping"]["lit_fraction_range"][0]
            < data["mapping"]["lit_fraction_range"][1],
            "area ramp range is increasing",
            "range=%s" % data["mapping"]["lit_fraction_range"],
        )


def main() -> int:
    test_png()
    test_derivation()
    if FAILS == 0:
        print("STEALTHBALL_ARRAY_TEST PASS checks=%d" % CHECKS)
    else:
        print("STEALTHBALL_ARRAY_TEST FAIL checks=%d fails=%d" % (CHECKS, FAILS))
    return 0 if FAILS == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
