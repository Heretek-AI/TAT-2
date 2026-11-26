#!/usr/bin/env python3
"""P0b Lane I audio statistics: Master-bus WAV vs the official clip's dBFS.

The capture tap (game/src/core/audio_capture.gd) writes a 16-bit stereo WAV, a
raw PCM twin, and a JSON sidecar whose `marks` carry the per-window RMS/peak the
tap measured live. This script re-measures those windows from the WAV (a
consistency check), prints the whole-capture level, and compares a mark that
names a route beat (S01..S27) with the documented level for that segment.

What the reference is — and is not
----------------------------------
* The official clip is 48 kHz AAC; its documented per-segment values are RMS and
  peak dBFS, not LUFS. The whole-clip `ebur128` figures are −43.9 LUFS
  integrated with 16.7 LU LRA and −20.2 dBFS true peak; this script does NOT
  compute LUFS (that needs the K-weighting filter) — it reports RMS/peak dBFS
  only and says so.
* Only the rows with a documented level are compared. Rows with cue-only
  evidence report the cue values as context and `ref_compare="cue-only"`; a
  fixed-pose capture mark (no beat) reports `ref_compare="none"`. Nothing is
  invented for a segment the reference does not quantify.
* Source: docs/REFERENCE_BASELINE.md §3 (clip facts), §4 (timeline) and §8.2
  (AU1–AU6); the per-cue values were re-measured in the same document's
  verification log.

Usage
-----
  build/qa/p0b_audio_stats.py --wav build/qa/p0b/captures/<run>/audio_on.wav
  build/qa/p0b_audio_stats.py --capture-dir build/qa/p0b/captures/<run>
  build/qa/p0b_audio_stats.py --route            # print the 27-beat reference
  build/qa/p0b_audio_stats.py --wav ... --json
"""

from __future__ import annotations

import argparse
import array
import json
import math
import sys
import wave
from pathlib import Path

SCHEMA = "tat2.audio_capture/1"
CLIP_INTEGRATED_LUFS = -43.9
CLIP_LRA_LU = 16.7
CLIP_TRUE_PEAK_DBFS = -20.2
CLIP_SOURCE = "docs/REFERENCE_BASELINE.md §3 / KEYFRAME_INDEX.md §1"

# S01..S27. `rms_db` is a documented (low, high) range; `peak_db` a single
# documented peak; `cues` are the documented peak cues when no bed level exists;
# `silence` marks a documented digital-zero window. `None` means the reference
# does not quantify that field for the segment.
REFERENCE_BEATS: dict[str, dict] = {
    "S01": {
        "start": 0.00,
        "end": 2.15,
        "rms_db": (-53.0, -49.0),
        "peak_db": None,
        "cues": [],
        "silence": False,
        "source": "AU1-01",
    },
    "S02": {
        "start": 2.15,
        "end": 2.60,
        "rms_db": None,
        "peak_db": None,
        "cues": ["rain fades to -82.0 then -240.0 dBFS"],
        "silence": False,
        "source": "AU1-03",
    },
    "S03": {
        "start": 2.60,
        "end": 6.57,
        "rms_db": (-76.3, -73.1),
        "peak_db": None,
        "cues": [],
        "silence": False,
        "source": "AU1-02",
    },
    "S04": {
        "start": 6.57,
        "end": 18.24,
        "rms_db": None,
        "peak_db": -23.5,
        "cues": [
            "open latch/whoosh -23.5",
            "8 hover/slot ticks -34.6..-39.4",
            "close -35.1",
        ],
        "silence": False,
        "source": "AU4-02",
    },
    "S05": {
        "start": 18.24,
        "end": 26.58,
        "rms_db": (-39.5, -39.5),
        "peak_db": -29.8,
        "cues": ["wood footstep -27.1 at 00:23.74"],
        "silence": False,
        "source": "AU1-04 + AU3-01",
    },
    "S06": {
        "start": 26.58,
        "end": 38.17,
        "rms_db": None,
        "peak_db": -30.4,
        "cues": [
            "parchment/tab -30.4 / -34.5",
            "quiet -68",
            "re-open -33.7",
            "close-prep -34.3",
        ],
        "silence": False,
        "source": "AU4-03",
    },
    "S07": {
        "start": 38.17,
        "end": 51.08,
        "rms_db": (-42.33, -42.33),
        "peak_db": -24.9,
        "cues": ["gramophone block RMS -42.33"],
        "silence": False,
        "source": "AU2-01 + astats",
    },
    "S08": {
        "start": 51.08,
        "end": 56.08,
        "rms_db": None,
        "peak_db": None,
        "cues": [],
        "silence": False,
        "source": "no documented level",
    },
    "S09": {
        "start": 56.08,
        "end": 64.80,
        "rms_db": None,
        "peak_db": -35.7,
        "cues": ["6 countdown ticks -41.3..-35.7 at 1.00 s"],
        "silence": False,
        "source": "AU4-04",
    },
    "S10": {
        "start": 64.80,
        "end": 69.44,
        "rms_db": None,
        "peak_db": None,
        "cues": [
            "true digital silence 01:04.94-01:07.78",
            "rain fade-in from 01:07.7757",
        ],
        "silence": True,
        "source": "AU1-03",
    },
    "S11": {
        "start": 69.44,
        "end": 70.81,
        "rms_db": None,
        "peak_db": None,
        "cues": [],
        "silence": False,
        "source": "no documented level",
    },
    "S12": {
        "start": 70.81,
        "end": 80.10,
        "rms_db": None,
        "peak_db": -27.3,
        "cues": ["VO -30.8", "vault thud -30.5", "metal grate steps -27.3"],
        "silence": False,
        "source": "AU3-03 + AU6-01",
    },
    "S13": {
        "start": 80.10,
        "end": 99.30,
        "rms_db": None,
        "peak_db": -20.2,
        "cues": ["wet sprint -25.2", "car double-honk -20.2"],
        "silence": False,
        "source": "AU3-02 + AU5-01",
    },
    "S14": {
        "start": 99.30,
        "end": 109.50,
        "rms_db": None,
        "peak_db": -21.5,
        "cues": ["equip clank -24.3", "launch -21.5"],
        "silence": False,
        "source": "AU5-02",
    },
    "S15": {
        "start": 109.50,
        "end": 118.50,
        "rms_db": None,
        "peak_db": -22.2,
        "cues": ["ratchet -22.2", "pneumatic -24.8"],
        "silence": False,
        "source": "AU5-02",
    },
    "S16": {
        "start": 118.50,
        "end": 131.00,
        "rms_db": None,
        "peak_db": None,
        "cues": [],
        "silence": False,
        "source": "no documented level",
    },
    "S17": {
        "start": 131.00,
        "end": 143.30,
        "rms_db": None,
        "peak_db": None,
        "cues": [],
        "silence": False,
        "source": "no documented level",
    },
    "S18": {
        "start": 143.30,
        "end": 150.70,
        "rms_db": None,
        "peak_db": -20.5,
        "cues": ["canister clink -28.0", "detonation/hiss -20.5"],
        "silence": False,
        "source": "AU5-03",
    },
    "S19": {
        "start": 150.70,
        "end": 153.00,
        "rms_db": None,
        "peak_db": -28.0,
        "cues": ["Vistara shimmer/chime -28.0"],
        "silence": False,
        "source": "AU5-04",
    },
    "S20": {
        "start": 153.00,
        "end": 174.50,
        "rms_db": None,
        "peak_db": None,
        "cues": [],
        "silence": False,
        "source": "no documented level",
    },
    "S21": {
        "start": 174.50,
        "end": 184.50,
        "rms_db": None,
        "peak_db": None,
        "cues": [],
        "silence": False,
        "source": "no documented level",
    },
    "S22": {
        "start": 184.50,
        "end": 197.10,
        "rms_db": None,
        "peak_db": -23.6,
        "cues": ["key jingle + acquisition chime -23.6"],
        "silence": False,
        "source": "AU5-07",
    },
    "S23": {
        "start": 197.10,
        "end": 202.00,
        "rms_db": None,
        "peak_db": -22.1,
        "cues": ["grunts -23.7", "impact/KO -22.1"],
        "silence": False,
        "source": "AU5-08",
    },
    "S24": {
        "start": 202.00,
        "end": 209.00,
        "rms_db": None,
        "peak_db": -28.9,
        "cues": ["hard-sole marble footfalls -28.9", "VO -32.6"],
        "silence": False,
        "source": "AU3-04 + AU6-05",
    },
    "S25": {
        "start": 209.00,
        "end": 217.40,
        "rms_db": None,
        "peak_db": -30.4,
        "cues": ["chime -30.4", "whoosh -32.3", "hum -59"],
        "silence": False,
        "source": "AU5-05",
    },
    "S26": {
        "start": 217.40,
        "end": 221.90,
        "rms_db": None,
        "peak_db": -23.5,
        "cues": ["shatter/sting -23.5", "slate steps + clack -24.5"],
        "silence": False,
        "source": "AU5-06 + AU3-05",
    },
    "S27": {
        "start": 221.90,
        "end": 225.64,
        "rms_db": None,
        "peak_db": -35.6,
        "cues": [
            "pause click -35.6",
            "ambience duck -53 -> -72.4",
            "silence 03:43.80-03:45.64",
        ],
        "silence": True,
        "source": "AU4-05",
    },
}


def db(linear: float) -> float:
    return 20.0 * math.log10(max(linear, 1.0e-9))


def read_wav(path: Path) -> tuple[array.array, int, int, int]:
    with wave.open(str(path), "rb") as w:
        channels = w.getnchannels()
        width = w.getsampwidth()
        rate = w.getframerate()
        raw = w.readframes(w.getnframes())
    if width != 2:
        raise ValueError(f"{path}: expected 16-bit PCM, got {width * 8}-bit")
    data = array.array("h")
    data.frombytes(raw)
    if sys.byteorder == "big":
        data.byteswap()
    return data, channels, rate, len(raw) // (2 * channels)


def window_stats(
    data: array.array, channels: int, rate: int, start_frame: int, frames: int
) -> dict:
    start = max(0, start_frame) * channels
    end = min(len(data), (max(0, start_frame) + max(0, frames)) * channels)
    samples = data[start:end]
    n = len(samples)
    if n <= 0:
        return {
            "frames": 0,
            "seconds": 0.0,
            "rms_dbfs": -120.0,
            "peak_dbfs": -120.0,
            "zero_fraction": 0.0,
            "dc": 0.0,
        }
    total = 0
    peak = 0
    zero = 0
    for s in samples:
        total += s * s
        a = abs(s)
        if a > peak:
            peak = a
        if s == 0:
            zero += 1
    return {
        "frames": (end - start) // channels,
        "seconds": (end - start) / channels / float(rate),
        "rms_dbfs": db(math.sqrt(total / n) / 32768.0),
        "peak_dbfs": db(peak / 32768.0),
        "zero_fraction": zero / n,
        "dc": sum(samples) / n / 32768.0,
    }


def compare_beat(beat: str, stats: dict) -> dict:
    ref = REFERENCE_BEATS.get(beat)
    if ref is None:
        return {"ref_compare": "unknown-beat"}
    out: dict = {
        "ref_compare": "none",
        "source": ref["source"],
        "ref_rms_db": list(ref["rms_db"]) if ref["rms_db"] else None,
        "ref_peak_db": ref["peak_db"],
        "cues": ref["cues"],
        "silence": ref["silence"],
    }
    if ref["rms_db"]:
        lo, hi = ref["rms_db"]
        mid = (lo + hi) / 2.0
        out["ref_compare"] = "rms-range"
        out["in_range"] = lo <= stats["rms_dbfs"] <= hi
        out["delta_mid_db"] = stats["rms_dbfs"] - mid
    elif ref["peak_db"] is not None:
        out["ref_compare"] = "peak-only"
        out["peak_delta_db"] = stats["peak_dbfs"] - ref["peak_db"]
    elif ref["silence"]:
        out["ref_compare"] = "silence"
        out["digital_zero"] = stats["zero_fraction"] >= 0.999
    elif ref["cues"]:
        out["ref_compare"] = "cue-only"
    return out


def sidecar_for(wav: Path) -> Path:
    return wav.with_suffix(".json")


def load_sidecar(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return {}


def report(wav: Path, sidecar_path: Path | None, as_json: bool) -> int:
    if not wav.is_file():
        print(f"P0B_AUDIO_FAIL missing {wav}", file=sys.stderr)
        return 2
    side_path = sidecar_path or sidecar_for(wav)
    side = load_sidecar(side_path)
    if side and side.get("schema") and side.get("schema") != SCHEMA:
        print(
            f"P0B_AUDIO_FAIL {side_path}: schema {side.get('schema')} != {SCHEMA}",
            file=sys.stderr,
        )
        return 2
    if side and side.get("enabled") is False:
        print(
            f"P0B_AUDIO_DISABLED wav={wav} reason={side.get('reason', '')} "
            f"driver={side.get('driver', '')} rate={side.get('sample_rate', 0)}"
        )
        return 0
    data, channels, rate, total_frames = read_wav(wav)
    total = window_stats(data, channels, rate, 0, total_frames)
    print(
        f"P0B_AUDIO_REF_CLIP integrated_lufs={CLIP_INTEGRATED_LUFS} lra_lu={CLIP_LRA_LU} "
        f'true_peak_dbfs={CLIP_TRUE_PEAK_DBFS} source="{CLIP_SOURCE}"'
    )
    print(
        f"P0B_AUDIO_TOTAL wav={wav} rate={rate} channels={channels} frames={total_frames} "
        f"seconds={total_frames / rate:.3f} rms={total['rms_dbfs']:.2f} peak={total['peak_dbfs']:.2f} "
        f"zero={total['zero_fraction'] * 100:.3f}% dc={total['dc']:+.5f} "
        f"sidecar={side_path if side_path.is_file() else 'missing'} "
        f'note="RMS/peak dBFS only; LUFS not computed"'
    )
    marks = side.get("marks", []) if side else []
    results = []
    if not marks:
        print(
            "P0B_AUDIO_MARKS none (no mark list in the sidecar; whole-capture level only)"
        )
    for i, m in enumerate(marks):
        label = str(m.get("label", ""))
        beat = str(m.get("beat", "")).upper()
        start = int(m.get("frame", 0))
        end = int(
            (marks[i + 1] if i + 1 < len(marks) else {}).get("frame", total_frames)
        )
        measured = window_stats(data, channels, rate, start, max(0, end - start))
        reported = m.get("window", {}) if isinstance(m.get("window"), dict) else {}
        mismatch = None
        if (
            reported
            and "frames" in reported
            and int(reported.get("frames", -1)) == measured["frames"]
        ):
            mismatch = abs(
                float(reported.get("rms_dbfs", -120.0)) - measured["rms_dbfs"]
            )
        cmp = compare_beat(beat, measured) if beat else {"ref_compare": "none"}
        row = {
            "index": i,
            "label": label,
            "beat": beat,
            "start_frame": start,
            "t_s": start / float(rate),
            "measured": measured,
            "reported": reported,
            "window_mismatch_db": mismatch,
            "reference": cmp,
        }
        results.append(row)
        ref_txt = ""
        if cmp["ref_compare"] == "rms-range":
            ref_txt = (
                f"ref_rms={cmp['ref_rms_db'][0]:.1f}..{cmp['ref_rms_db'][1]:.1f} "
                f"in_range={str(cmp['in_range']).lower()} delta_mid={cmp['delta_mid_db']:+.2f}"
            )
        elif cmp["ref_compare"] == "peak-only":
            ref_txt = f"ref_peak={cmp['ref_peak_db']:.1f} peak_delta={cmp['peak_delta_db']:+.2f}"
        elif cmp["ref_compare"] == "silence":
            ref_txt = (
                f"ref_silence=true digital_zero={str(cmp['digital_zero']).lower()}"
            )
        elif cmp["ref_compare"] == "cue-only":
            ref_txt = 'ref_cues="' + " | ".join(cmp["cues"]) + '"'
        elif cmp["ref_compare"] == "none":
            ref_txt = "ref_compare=none (mark is not a route beat)"
        else:
            ref_txt = f"ref_compare={cmp['ref_compare']}"
        print(
            f"P0B_AUDIO_MARK index={i} label={label or '-'} beat={beat or '-'} "
            f"t={row['t_s']:.3f}s frames={measured['frames']} rms={measured['rms_dbfs']:.2f} "
            f"peak={measured['peak_dbfs']:.2f} zero={measured['zero_fraction'] * 100:.3f}% "
            f"window_mismatch_db={('n/a' if mismatch is None else f'{mismatch:.3f}')} "
            f"source={cmp.get('source', '')} {ref_txt}"
        )
    if as_json:
        print(
            json.dumps(
                {
                    "wav": str(wav),
                    "sidecar": str(side_path),
                    "clip_reference": {
                        "integrated_lufs": CLIP_INTEGRATED_LUFS,
                        "lra_lu": CLIP_LRA_LU,
                        "true_peak_dbfs": CLIP_TRUE_PEAK_DBFS,
                        "source": CLIP_SOURCE,
                    },
                    "total": total,
                    "marks": results,
                },
                indent=2,
            )
        )
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--wav", type=Path, help="capture WAV (16-bit PCM)")
    ap.add_argument(
        "--sidecar", type=Path, help="capture JSON sidecar (default <wav>.json)"
    )
    ap.add_argument(
        "--capture-dir", type=Path, help="directory with audio_*.wav (and .json)"
    )
    ap.add_argument(
        "--route", action="store_true", help="print the S01..S27 reference table"
    )
    ap.add_argument("--json", action="store_true", help="print the JSON summary")
    args = ap.parse_args()
    if args.route:
        for beat, ref in REFERENCE_BEATS.items():
            rms = (
                f"{ref['rms_db'][0]:.2f}..{ref['rms_db'][1]:.2f}"
                if ref["rms_db"]
                else "-"
            )
            peak = f"{ref['peak_db']:.2f}" if ref["peak_db"] is not None else "-"
            print(
                f"P0B_ROUTE_BEAT beat={beat} start={ref['start']:.2f} end={ref['end']:.2f} "
                f"rms_db={rms} peak_db={peak} silence={str(ref['silence']).lower()} "
                f'source={ref["source"]} cues="{" | ".join(ref["cues"])}"'
            )
        print(
            f"P0B_ROUTE_CLIP integrated_lufs={CLIP_INTEGRATED_LUFS} lra_lu={CLIP_LRA_LU} "
            f'true_peak_dbfs={CLIP_TRUE_PEAK_DBFS} source="{CLIP_SOURCE}"'
        )
        return 0
    wav = args.wav
    if args.capture_dir and not wav:
        candidates = sorted(args.capture_dir.glob("audio_*.wav"))
        if not candidates:
            for s in sorted(args.capture_dir.glob("audio_*.json")):
                side = load_sidecar(s)
                if side.get("enabled") is False:
                    print(
                        f"P0B_AUDIO_DISABLED sidecar={s} reason={side.get('reason', '')} "
                        f"driver={side.get('driver', '')} rate={side.get('sample_rate', 0)}"
                    )
                    return 0
            print(
                f"P0B_AUDIO_FAIL no audio_*.wav in {args.capture_dir}", file=sys.stderr
            )
            return 2
        wav = candidates[0]
    if not wav:
        print("P0B_AUDIO_FAIL need --wav, --capture-dir or --route", file=sys.stderr)
        return 2
    return report(wav, args.sidecar, args.json)


if __name__ == "__main__":
    sys.exit(main())
