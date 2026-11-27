#!/usr/bin/env python3
"""Minimal stdlib PNG reader: 8-bit non-interlaced PNG -> RGBA8 rows.

Why this exists: `tools/` is stdlib-only (no Pillow, no numpy on the gate
host), and two U-4 consumers need real pixels:

* `tools/parse_stealthball_array.py` measures the authored gem slices
  (alpha coverage, lit-cap fraction/centroid) to derive the slice mapping;
* `build/qa/ui_pixel_stats.py` measures the captured UI frames.

Supported subset (everything the extractor's Skia PNG encoder emits):
colour types 0 (gray), 2 (RGB), 4 (gray+alpha) and 6 (RGBA); bit depth 8;
filter methods 0-4; no interlacing. Anything else raises `PngError` instead
of returning wrong pixels.

API::

    width, height, rgba = read_rgba(path)
    width, height, rgba = read_rgba_bytes(data)

`rgba` is a `bytes` object of `width * height * 4` bytes in row-major order.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class PngError(ValueError):
    """The file is not the PNG subset this reader can decode exactly."""


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _unfilter(raw: bytes, width: int, height: int, bpp: int, stride: int) -> bytes:
    out = bytearray(height * stride)
    pos = 0
    prev = bytearray(stride)
    for y in range(height):
        if pos >= len(raw):
            raise PngError("truncated IDAT: missing row %d" % y)
        ftype = raw[pos]
        pos += 1
        row = bytearray(raw[pos : pos + stride])
        if len(row) != stride:
            raise PngError("truncated IDAT row %d" % y)
        pos += stride
        if ftype == 0:  # None
            pass
        elif ftype == 1:  # Sub
            for i in range(bpp, stride):
                row[i] = (row[i] + row[i - bpp]) & 0xFF
        elif ftype == 2:  # Up
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 0xFF
        elif ftype == 3:  # Average
            for i in range(stride):
                left = row[i - bpp] if i >= bpp else 0
                row[i] = (row[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:  # Paeth
            for i in range(stride):
                left = row[i - bpp] if i >= bpp else 0
                upleft = prev[i - bpp] if i >= bpp else 0
                row[i] = (row[i] + _paeth(left, prev[i], upleft)) & 0xFF
        else:
            raise PngError("unknown filter type %d on row %d" % (ftype, y))
        out[y * stride : (y + 1) * stride] = row
        prev = row
    return bytes(out)


def read_rgba_bytes(data: bytes) -> tuple[int, int, bytes]:
    if not data.startswith(PNG_SIGNATURE):
        raise PngError("not a PNG (bad signature)")
    pos = len(PNG_SIGNATURE)
    width = height = 0
    bit_depth = color_type = interlace = -1
    idat = bytearray()
    seen_ihdr = False
    seen_iend = False
    while pos + 8 <= len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        ctype = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        if len(body) != length:
            raise PngError("truncated chunk %r" % ctype)
        crc = data[pos + 8 + length : pos + 12 + length]
        if len(crc) == 4:
            expect = struct.unpack(">I", crc)[0]
            if zlib.crc32(ctype + body) & 0xFFFFFFFF != expect:
                raise PngError("bad CRC on chunk %r" % ctype)
        pos += 12 + length
        if ctype == b"IHDR":
            if length != 13:
                raise PngError("bad IHDR length %d" % length)
            width, height, bit_depth, color_type, comp, filt, interlace = struct.unpack(
                ">IIBBBBB", body
            )
            if comp != 0 or filt != 0:
                raise PngError("unsupported compression/filter method")
            seen_ihdr = True
        elif ctype == b"IDAT":
            idat.extend(body)
        elif ctype == b"IEND":
            seen_iend = True
            break
        elif ctype in (
            b"PLTE",
            b"tRNS",
            b"gAMA",
            b"pHYs",
            b"sRGB",
            b"iCCP",
            b"tEXt",
            b"zTXt",
            b"iTXt",
            b"bKGD",
            b"cHRM",
            b"tIME",
        ):
            continue
        else:
            # Unknown ancillary chunks are safe to skip; unknown critical
            # chunks are not (we would be guessing at pixels).
            if ctype[:1].isupper():
                raise PngError("unknown critical chunk %r" % ctype)
    if not seen_ihdr or not seen_iend:
        raise PngError("missing IHDR or IEND")
    if width <= 0 or height <= 0:
        raise PngError("bad dimensions %dx%d" % (width, height))
    if bit_depth != 8:
        raise PngError("bit depth %d (only 8 is supported)" % bit_depth)
    if interlace != 0:
        raise PngError("interlaced PNG (only non-interlaced is supported)")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
    if channels is None:
        raise PngError("colour type %d is not supported" % color_type)
    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error as exc:
        raise PngError("IDAT decompress failed: %s" % exc) from exc
    stride = width * channels
    flat = _unfilter(raw, width, height, channels, stride)
    if color_type == 6:
        return width, height, flat
    rgba = bytearray(width * height * 4)
    if color_type == 2:
        for i in range(width * height):
            rgba[i * 4 : i * 4 + 3] = flat[i * 3 : i * 3 + 3]
            rgba[i * 4 + 3] = 255
    elif color_type == 0:
        for i in range(width * height):
            v = flat[i]
            rgba[i * 4] = rgba[i * 4 + 1] = rgba[i * 4 + 2] = v
            rgba[i * 4 + 3] = 255
    else:  # 4: gray + alpha
        for i in range(width * height):
            v = flat[i * 2]
            rgba[i * 4] = rgba[i * 4 + 1] = rgba[i * 4 + 2] = v
            rgba[i * 4 + 3] = flat[i * 2 + 1]
    return width, height, bytes(rgba)


def read_rgba(path: str | Path) -> tuple[int, int, bytes]:
    return read_rgba_bytes(Path(path).read_bytes())


def read_size(path: str | Path) -> tuple[int, int]:
    """Width/height from IHDR without decoding any pixel (fast preflight)."""
    data = Path(path).read_bytes()[:33]
    if len(data) < 24 or not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        raise PngError("not a PNG (bad signature/IHDR)")
    width, height = struct.unpack(">II", data[16:24])
    if width <= 0 or height <= 0:
        raise PngError("bad dimensions %dx%d" % (width, height))
    return width, height
