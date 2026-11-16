#!/usr/bin/env python3
"""Extract embedded audio chunks and synthesize fallback SFX.

Inspects extracted/audio/ (including WwiseSharedAssetLibrary.ubulk, which
stores Wwise Vorbis-in-WAVE RIFF chunks) and extracts any valid
RIFF/WAVE/OGG chunks into game/assets/ue/audio/ for archival.

The embedded Wwise chunks use format tag 0xFFFF (Wwise Vorbis) which Godot
cannot decode, so this script additionally synthesizes clean fallback
.wav SFX (stdlib wave+struct+math only) guaranteeing every gameplay tag
exists as a valid PCM .wav file:

    footstep, blackjack, lockpick, grapple, smoke,
    fairy, alert, loot, door
"""

import struct
import wave
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "extracted" / "audio"
OUT_DIR = ROOT / "game" / "assets" / "ue" / "audio"

SAMPLE_RATE = 22050

FALLBACK_TAGS = [
    "footstep",
    "blackjack",
    "lockpick",
    "grapple",
    "smoke",
    "fairy",
    "alert",
    "loot",
    "door",
]

WINDOW = 4 * 1024 * 1024
OVERLAP = 32


# ---------------------------------------------------------------------------
# Chunk extraction
# ---------------------------------------------------------------------------
def _is_valid_riff_at(f, abs_off: int, file_size: int):
    """Return chunk total length if a valid RIFF/WAVE chunk starts at abs_off."""
    f.seek(abs_off)
    head = f.read(20)
    if len(head) < 20 or head[0:4] != b"RIFF" or head[8:12] != b"WAVE":
        return 0
    (size,) = struct.unpack_from("<I", head, 4)
    if size < 16 or abs_off + 8 + size > file_size or size > 300_000_000:
        return 0
    if b"fmt " not in head[12:20]:
        # fmt marker must appear right after the WAVE tag
        f.seek(abs_off + 12)
        probe = f.read(64)
        if b"fmt " not in probe:
            return 0
    total = 8 + size + (size & 1)  # RIFF chunks are word-aligned
    return total


def extract_riff_chunks(src: Path, out_dir: Path) -> int:
    file_size = src.stat().st_size
    count = 0
    cursor = 0
    with src.open("rb") as f:
        while cursor < file_size:
            f.seek(cursor)
            window = f.read(WINDOW + OVERLAP)
            if not window:
                break
            rel = window.find(b"RIFF")
            if rel < 0:
                cursor += WINDOW
                continue
            abs_off = cursor + rel
            total = _is_valid_riff_at(f, abs_off, file_size)
            if total <= 0:
                cursor = abs_off + 1
                continue
            f.seek(abs_off)
            chunk = f.read(total)
            if len(chunk) != total or chunk[8:12] != b"WAVE":
                cursor = abs_off + 1
                continue
            dest = out_dir / f"wwise_{count:04d}_{abs_off:09d}.wav"
            if not (dest.exists() and dest.stat().st_size == total):
                dest.write_bytes(chunk)
            count += 1
            cursor = abs_off + total
    return count


def extract_ogg_chains(src: Path, out_dir: Path) -> int:
    """Best-effort Ogg page-chain extraction (no OggS in current bank)."""
    file_size = src.stat().st_size
    count = 0
    cursor = 0
    with src.open("rb") as f:
        while cursor < file_size:
            f.seek(cursor)
            window = f.read(WINDOW + OVERLAP)
            if not window:
                break
            rel = window.find(b"OggS")
            if rel < 0:
                cursor += WINDOW
                continue
            abs_off = cursor + rel
            f.seek(abs_off)
            head = f.read(27)
            if len(head) < 27 or head[4] != 0:
                cursor = abs_off + 1
                continue
            segs = head[26]
            seg_table = f.read(segs)
            if len(seg_table) != segs:
                cursor = abs_off + 1
                continue
            page_len = 27 + segs + sum(seg_table)
            # Walk consecutive chained pages.
            end = abs_off + page_len
            while end + 4 <= file_size:
                f.seek(end)
                magic = f.read(4)
                if magic != b"OggS":
                    break
                f.seek(end)
                h2 = f.read(27)
                if len(h2) < 27 or h2[4] != 0:
                    break
                s2 = h2[26]
                t2 = f.read(s2)
                if len(t2) != s2:
                    break
                end += 27 + s2 + sum(t2)
                if end - abs_off > 300_000_000:
                    break
            f.seek(abs_off)
            blob = f.read(end - abs_off)
            dest = out_dir / f"ogg_{count:04d}_{abs_off:09d}.ogg"
            if not (dest.exists() and dest.stat().st_size == len(blob)):
                dest.write_bytes(blob)
            count += 1
            cursor = end if end > abs_off else abs_off + 1
    return count


def copy_loose_audio(out_dir: Path) -> int:
    count = 0
    if not SRC_DIR.is_dir():
        return 0
    for src in sorted(SRC_DIR.rglob("*")):
        if not src.is_file():
            continue
        suf = src.suffix.lower()
        if suf not in (".wav", ".ogg"):
            continue
        data = src.read_bytes()
        valid = data[:4] == b"RIFF" if suf == ".wav" else data[:4] == b"OggS"
        if not valid:
            continue
        dest = out_dir / src.name
        if dest.exists():
            stem, i = dest.stem, 1
            while dest.exists():
                dest = out_dir / f"{stem}_{i}{suf}"
                i += 1
        dest.write_bytes(data)
        count += 1
    return count


# ---------------------------------------------------------------------------
# Fallback synthesis (stdlib only)
# ---------------------------------------------------------------------------
def _noise(i: int, seed: int = 0) -> float:
    x = math.sin(float(i) * 12.9898 + float(seed) * 78.233) * 43758.5453
    return (x - math.floor(x)) * 2.0 - 1.0


def _write_wav(path: Path, samples: list, sr: int = SAMPLE_RATE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(round(s * 32767.0)))))
        for s in samples
    )
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(frames)


def _sine(phase: float) -> float:
    return math.sin(phase * math.tau)


def synth(tag: str, sr: int = SAMPLE_RATE) -> list:
    out: list = []
    if tag == "footstep":
        n = int(0.18 * sr)
        lp = 0.0
        for i in range(n):
            t = i / sr
            thud = math.sin(math.tau * 78.0 * t) * math.exp(-t * 24.0) * 0.9
            lp += 0.25 * (_noise(i, 1) - lp)
            tap = lp * math.exp(-t * 32.0) * 0.5
            out.append(thud + tap)
    elif tag == "blackjack":
        n = int(0.30 * sr)
        for i in range(n):
            t = i / sr
            body = math.sin(math.tau * 62.0 * t) * math.exp(-t * 14.0)
            knock = math.sin(math.tau * 185.0 * t) * math.exp(-t * 26.0) * 0.35
            click = _noise(i, 2) * math.exp(-t * 220.0) * 0.5 if t < 0.02 else 0.0
            out.append(body + knock + click)
    elif tag == "lockpick":
        n = int(0.50 * sr)
        clicks = [(0.05, 2750.0), (0.22, 3350.0), (0.37, 2950.0)]
        for i in range(n):
            t = i / sr
            s = math.sin(math.tau * 190.0 * t) * math.exp(-t * 8.0) * 0.08
            for ct, cf in clicks:
                dt = t - ct
                if 0.0 <= dt < 0.09:
                    s += math.sin(math.tau * cf * dt) * math.exp(-dt * 90.0) * 0.7
                    s += _noise(i, 3) * math.exp(-dt * 260.0) * 0.35
            out.append(s)
    elif tag == "grapple":
        n = int(0.60 * sr)
        lp = 0.0
        for i in range(n):
            t = i / sr
            swell = math.sin(math.pi * min(1.0, t / 0.42)) ** 1.5
            lp += (0.05 + 0.25 * (t / 0.60)) * (_noise(i, 4) - lp)
            s = lp * swell * 1.4
            dt = t - 0.42
            if dt >= 0.0:
                for cf, a in ((820.0, 0.5), (1240.0, 0.35), (2080.0, 0.2)):
                    s += math.sin(math.tau * cf * dt) * math.exp(-dt * 22.0) * a
            out.append(s)
    elif tag == "smoke":
        n = int(0.70 * sr)
        lp = 0.0
        for i in range(n):
            t = i / sr
            env = min(1.0, t / 0.15) * math.exp(-max(0.0, t - 0.15) * 3.2)
            lp += 0.08 * (_noise(i, 5) - lp)
            puff = lp * env * 1.6
            puff += math.sin(math.tau * 290.0 * t) * env * 0.05
            out.append(puff)
    elif tag == "fairy":
        notes = (1318.5, 1568.0, 1975.5, 2637.0)
        n = int(0.90 * sr)
        for i in range(n):
            t = i / sr
            s = 0.0
            for k, cf in enumerate(notes):
                dt = t - k * 0.15
                if dt >= 0.0:
                    s += (
                        (
                            math.sin(math.tau * cf * dt)
                            + 0.3 * math.sin(math.tau * cf * 2.0 * dt)
                        )
                        * math.exp(-dt * 6.0)
                        * 0.35
                    )
            out.append(s)
    elif tag == "alert":
        n = int(0.70 * sr)
        for i in range(n):
            t = i / sr
            if t < 0.30:
                cf, lt = 660.0, t
            elif t < 0.35:
                cf, lt = 0.0, 0.0
            else:
                cf, lt = 520.0, t - 0.35
            if cf == 0.0:
                out.append(0.0)
                continue
            edge = min(1.0, lt / 0.008, (0.30 - (lt if t < 0.30 else lt)) / 0.008 + 1.0)
            edge = max(0.0, min(1.0, edge))
            tone = math.sin(math.tau * cf * lt) * 0.7
            tone += (1.0 if tone >= 0.0 else -1.0) * 0.12
            out.append(tone * edge * 0.8)
    elif tag == "loot":
        n = int(0.55 * sr)
        pings = [(0.00, (2950.0, 3690.0)), (0.18, (3300.0, 4150.0))]
        for i in range(n):
            t = i / sr
            s = 0.0
            for pt, (f1, f2) in pings:
                dt = t - pt
                if dt >= 0.0:
                    s += math.sin(math.tau * f1 * dt) * math.exp(-dt * 10.0) * 0.45
                    s += math.sin(math.tau * f2 * dt) * math.exp(-dt * 12.0) * 0.30
                    s += _noise(i, 6) * math.exp(-dt * 60.0) * 0.06
            out.append(s)
    elif tag == "door":
        n = int(0.80 * sr)
        for i in range(n):
            t = i / sr
            sweep = 140.0 - 55.0 * (t / 0.80)
            vib = 8.0 * math.sin(math.tau * 6.0 * t)
            hump = math.sin(math.pi * min(1.0, t / 0.62)) ** 1.2
            creak = math.sin(math.tau * (sweep + vib) * t) * hump * 0.35
            rub = _noise(i, 7) * hump * 0.10
            dt = t - 0.60
            thud = (
                math.sin(math.tau * 65.0 * dt) * math.exp(-dt * 12.0) * 0.8
                if dt >= 0.0
                else 0.0
            )
            out.append(creak + rub + thud)
    else:
        n = int(0.30 * sr)
        out = [math.sin(math.tau * 440.0 * (i / sr)) * 0.3 for i in range(n)]
    peak = max(1e-6, max(abs(s) for s in out))
    g = 0.89 / peak
    return [s * g for s in out]


def synthesize_fallbacks(out_dir: Path) -> list:
    made = []
    for tag in FALLBACK_TAGS:
        dest = out_dir / f"{tag}.wav"
        _write_wav(dest, synth(tag))
        made.append(dest)
    return made


def verify_wav(path: Path) -> bool:
    try:
        with wave.open(str(path), "rb") as w:
            return (
                w.getnchannels() >= 1 and w.getsampwidth() == 2 and w.getnframes() > 0
            )
    except wave.Error:
        return False


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ubulks = sorted(SRC_DIR.rglob("*.ubulk")) if SRC_DIR.is_dir() else []
    riff_total, ogg_total = 0, 0
    for ub in ubulks:
        r = extract_riff_chunks(ub, OUT_DIR)
        o = extract_ogg_chains(ub, OUT_DIR)
        print(f"{ub.name}: {r} RIFF/WAVE chunks, {o} Ogg chains")
        riff_total += r
        ogg_total += o
    loose = copy_loose_audio(OUT_DIR)
    print(f"loose audio files copied: {loose}")
    made = synthesize_fallbacks(OUT_DIR)
    bad = [str(p) for p in made if not verify_wav(p)]
    for p in made:
        print(
            f"synth {p.name}: {'OK' if p not in [Path(b) for b in bad] else 'INVALID'}"
        )
    if bad:
        print(f"ERROR: invalid wav files: {bad}")
        return 1
    print(
        f"done: {riff_total} wwise chunks, {ogg_total} ogg chains, "
        f"{loose} loose, {len(made)} fallbacks -> {OUT_DIR}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
