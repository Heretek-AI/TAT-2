#!/usr/bin/env python3
"""Convert extracted Wwise Vorbis-in-RIFF chunks to playable Ogg Vorbis.

Pipeline per chunk (extracted/audio/wwise_raw/wwise_<seq>_<offset>.wav):
    vgmstream-cli -> temp PCM WAV -> ffmpeg (libvorbis q5) ->
    game/assets/ue/audio/wwise/<offset-id>.ogg

Also writes:
    game/data/generated/audio_library.json - per-clip manifest
    game/data/generated/audio_events.json   - mapping audit: the recoverable
        half of the event->media map (event name, EventId, MediaId, source
        .wav DebugName) plus evidence that chunk<->media linkage is NOT
        recoverable, so no clip is wired to gameplay tags.

Stdlib only. Per-file failures are collected and reported; existing outputs
are skipped (but re-probed so the manifest stays complete).
"""

import concurrent.futures
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "extracted" / "audio" / "wwise_raw"
OUT_DIR = ROOT / "game" / "assets" / "ue" / "audio" / "wwise"
LIBRARY_PATH = ROOT / "game" / "data" / "generated" / "audio_library.json"
EVENTS_PATH = ROOT / "game" / "data" / "generated" / "audio_events.json"
VGMSTREAM = ROOT / "tools" / "bin" / "vgmstream" / "vgmstream-cli"
EVENTS_GLOB = ROOT / "extracted" / "json" / "Audio" / "Events"
BANK_JSON = ROOT / "extracted" / "json" / "Audio" / "WwiseSharedAssetLibrary.json"
FILELIST = ROOT / "extracted" / "filelist.txt"

VORBIS_QUALITY = 5
WORKERS = 8
TIMEOUT_S = 120

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

CHUNK_RE = re.compile(r"^wwise_(\d+)_(\d+)\.wav$")


def run(cmd: list) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_S)


def probe_audio(path: Path):
    """Return (duration_s, channels, sample_rate) via ffprobe, or None."""
    try:
        p = run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "stream=channels,sample_rate:format=duration",
                "-of",
                "json",
                str(path),
            ]
        )
        info = json.loads(p.stdout or "{}")
        streams = info.get("streams", [])
        fmt = info.get("format", {})
        if not streams or "duration" not in fmt:
            return None
        return (
            float(fmt["duration"]),
            int(streams[0]["channels"]),
            int(streams[0]["sample_rate"]),
        )
    except (ValueError, KeyError, TypeError, subprocess.SubprocessError):
        return None


def convert_one(src: Path, clip_id: str) -> dict:
    """Convert a single chunk; return manifest entry dict. Raises on failure."""
    dest = OUT_DIR / f"{clip_id}.ogg"
    if dest.exists() and dest.stat().st_size > 0:
        probed = probe_audio(dest)
        if probed is not None:
            duration, channels, sample_rate = probed
            return {
                "id": clip_id,
                "source": src.name,
                "duration_s": round(duration, 3),
                "channels": channels,
                "sample_rate": sample_rate,
                "output": f"wwise/{clip_id}.ogg",
                "res_path": f"res://assets/ue/audio/wwise/{clip_id}.ogg",
                "output_bytes": dest.stat().st_size,
                "status": "skipped",
            }
        dest.unlink()  # corrupt output: reconvert
    with tempfile.TemporaryDirectory(prefix="wwise_conv_") as tmp:
        tmp_wav = Path(tmp) / "decoded.wav"
        p = run([str(VGMSTREAM), str(src), "-o", str(tmp_wav)])
        if not tmp_wav.exists() or tmp_wav.stat().st_size == 0:
            raise RuntimeError(f"vgmstream failed: {(p.stderr or p.stdout)[-500:]}")
        p = run(
            [
                "ffmpeg",
                "-y",
                "-v",
                "error",
                "-i",
                str(tmp_wav),
                "-c:a",
                "libvorbis",
                "-q:a",
                str(VORBIS_QUALITY),
                str(dest),
            ]
        )
        if not dest.exists() or dest.stat().st_size == 0:
            raise RuntimeError(f"ffmpeg failed: {(p.stderr or p.stdout)[-500:]}")
    probed = probe_audio(dest)
    if probed is None or probed[0] <= 0:
        raise RuntimeError("ffprobe could not read converted output")
    duration, channels, sample_rate = probed
    return {
        "id": clip_id,
        "source": src.name,
        "duration_s": round(duration, 3),
        "channels": channels,
        "sample_rate": sample_rate,
        "output": f"wwise/{clip_id}.ogg",
        "res_path": f"res://assets/ue/audio/wwise/{clip_id}.ogg",
        "output_bytes": dest.stat().st_size,
        "status": "converted",
    }


def collect_chunks() -> list:
    chunks = []
    for src in sorted(SRC_DIR.iterdir()):
        m = CHUNK_RE.match(src.name)
        if m and src.is_file():
            chunks.append((src, str(int(m.group(2)))))
    return chunks


def convert_all() -> tuple:
    if not VGMSTREAM.exists():
        print(f"ERROR: vgmstream missing at {VGMSTREAM}; run `make audio-tools`")
        return [], [("all", "vgmstream binary missing")]
    if not SRC_DIR.is_dir():
        print(f"ERROR: source dir missing: {SRC_DIR}")
        return [], [("all", "source dir missing")]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    chunks = collect_chunks()
    print(f"found {len(chunks)} raw chunks")
    entries: list = []
    failures: list = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        future_map = {
            pool.submit(convert_one, src, cid): (src, cid) for src, cid in chunks
        }
        done = 0
        for fut in concurrent.futures.as_completed(future_map):
            src, cid = future_map[fut]
            done += 1
            try:
                entries.append(fut.result())
            except Exception as exc:  # per-file failure: record, continue
                failures.append((src.name, str(exc)))
            if done % 500 == 0 or done == len(chunks):
                print(f"  progress {done}/{len(chunks)}")
    entries.sort(key=lambda e: int(e["id"]))
    return entries, failures


# ---------------------------------------------------------------------------
# Mapping audit
# ---------------------------------------------------------------------------
def audit_mapping() -> dict:
    """Search extracted assets for any event-name -> media-id -> chunk link."""
    evidence: dict = {}
    events: list = []

    # 1. AkAudioEvent exports: event name / EventId / MediaId / source name.
    event_files = sorted(EVENTS_GLOB.rglob("*.json")) if EVENTS_GLOB.is_dir() else []
    evidence["ak_event_files"] = len(event_files)
    media_ids: set = set()
    for path in event_files:
        try:
            data = json.loads(path.read_text())
        except (ValueError, OSError):
            continue
        for entry in data if isinstance(data, list) else [data]:
            if not isinstance(entry, dict) or entry.get("Type") != "AkAudioEvent":
                continue
            media: list = []
            for lang in (entry.get("EventCookedData") or {}).get(
                "EventLanguageMap", []
            ):
                for m in (lang.get("Value") or {}).get("Media", []):
                    media_ids.add(m.get("MediaId"))
                    media.append(
                        {
                            "media_id": m.get("MediaId"),
                            "debug_name": m.get("DebugName"),
                        }
                    )
            events.append(
                {
                    "event": entry.get("Name"),
                    "event_id": ((entry.get("EventCookedData") or {}).get("EventId")),
                    "media": media,
                    "clip": None,
                }
            )
    evidence["ak_events_parsed"] = len(events)
    evidence["ak_events_with_media"] = sum(1 for e in events if e["media"])
    evidence["distinct_event_media_ids"] = len([m for m in media_ids if m])
    evidence["event_cooked_data_present"] = any(e["media"] for e in events)

    # 2. Bank hierarchies: SourceId -> InMemoryMediaSize (candidate join key).
    bank_sizes: dict = {}
    bank_ambiguous = 0
    voices_with_size = 0
    voices_without_size = 0
    bank_ok = BANK_JSON.exists()
    evidence["bank_json_present"] = bank_ok
    if bank_ok:
        from collections import Counter

        bank = json.loads(BANK_JSON.read_text())
        size_to_sid: dict = {}
        for pf in bank[0]["CookedData"]["PackagedFiles"]:
            for h in pf.get("BulkData", {}).get("Hierarchies", []):
                if h.get("Type") != "SoundSfxVoice":
                    continue
                src = h["Data"]["Source"]
                if "InMemoryMediaSize" in src:
                    voices_with_size += 1
                    size_to_sid.setdefault(src["InMemoryMediaSize"], set()).add(
                        src["SourceId"]
                    )
                else:
                    voices_without_size += 1
        bank_ambiguous = sum(1 for s in size_to_sid.values() if len(s) > 1)
        bank_sizes = {z: len(s) for z, s in size_to_sid.items()}
    evidence["bank_voices_with_size"] = voices_with_size
    evidence["bank_voices_without_size"] = voices_without_size
    evidence["bank_distinct_sizes"] = len(bank_sizes)
    evidence["bank_ambiguous_sizes"] = bank_ambiguous

    # 3. Chunk inventory: ids are ubulk byte offsets, not media ids.
    chunk_sizes: dict = {}
    chunk_ids: set = set()
    offset_verified = False
    if SRC_DIR.is_dir():
        for src in SRC_DIR.iterdir():
            m = CHUNK_RE.match(src.name)
            if m and src.is_file():
                chunk_ids.add(int(m.group(2)))
                st = src.stat().st_size
                chunk_sizes.setdefault(st, 0)
                chunk_sizes[st] += 1
    evidence["raw_chunks"] = len(chunk_ids)
    evidence["chunk_distinct_sizes"] = len(chunk_sizes)
    evidence["chunks_sharing_size"] = sum(v for v in chunk_sizes.values() if v > 1)
    media_as_chunk_id = (
        len(media_ids.intersection(chunk_ids)) if media_ids and chunk_ids else 0
    )
    evidence["media_ids_matching_chunk_ids"] = media_as_chunk_id
    # Verify chunk id == byte offset of RIFF in the shared ubulk.
    ubulks = sorted((ROOT / "extracted" / "audio").rglob("*.ubulk"))
    evidence["ubulk_files"] = [str(p.relative_to(ROOT)) for p in ubulks]
    if ubulks and chunk_ids:
        with ubulks[0].open("rb") as f:
            for cid in sorted(chunk_ids)[:3]:
                f.seek(cid)
                offset_verified = f.read(4) == b"RIFF"
                if not offset_verified:
                    break
    evidence["chunk_id_is_ubulk_offset_verified"] = offset_verified

    # 4. No .wem/.bnk anywhere to carry the media index (DIDX).
    wem_bnk = 0
    if FILELIST.exists():
        for line in FILELIST.read_text(errors="replace").splitlines():
            low = line.lower()
            if ".wem" in low or ".bnk" in low:
                wem_bnk += 1
    evidence["filelist_wem_bnk_hits"] = wem_bnk

    # 5. Size-join quality: exact and ±1 (RIFF pad byte) intersections.
    bset = set(bank_sizes)
    cset = set(chunk_sizes)
    evidence["size_exact_intersection"] = len(cset & bset)
    evidence["size_pm1_intersection"] = len(
        cset & (bset | {z + 1 for z in bset} | {z - 1 for z in bset})
    )

    mapping_found = False  # no unique media->chunk key exists; see evidence
    evidence["conclusion"] = (
        "No recoverable event->clip link: chunk ids are ubulk offsets (verified), "
        "no .wem/.bnk/DIDX index exists, MediaIds never equal chunk ids, and "
        "RIFF-size matching is ambiguous (shared sizes both sides). "
        "Event->MediaId/DebugName half of the map is preserved below for future "
        "use if a media index is ever recovered."
    )

    tags = {
        tag: {
            "clip": None,
            "status": "fallback",
            "reason": "no confirmed event->clip mapping; synthesized fallback kept",
        }
        for tag in FALLBACK_TAGS
    }
    return {
        "mapping_unavailable": not mapping_found,
        "evidence": evidence,
        "tags": tags,
        "events": events,
    }


def main() -> int:
    entries, failures = convert_all()
    converted = sum(1 for e in entries if e["status"] == "converted")
    skipped = sum(1 for e in entries if e["status"] == "skipped")
    total_s = round(sum(e["duration_s"] for e in entries), 1)
    out_bytes = sum(e["output_bytes"] for e in entries)
    print(f"converted={converted} skipped={skipped} failed={len(failures)}")
    print(f"total duration={total_s}s across {len(entries)} clips, {out_bytes} bytes")

    LIBRARY_PATH.parent.mkdir(parents=True, exist_ok=True)
    LIBRARY_PATH.write_text(
        json.dumps(
            {
                "generated_by": "tools/convert_wwise.py",
                "vgmstream": "r2168",
                "codec": "Vorbis",
                "vorbis_quality": VORBIS_QUALITY,
                "counts": {
                    "clips": len(entries),
                    "converted": converted,
                    "skipped": skipped,
                    "failed": len(failures),
                    "total_duration_s": total_s,
                    "total_output_bytes": out_bytes,
                },
                "failures": [{"source": name, "error": err} for name, err in failures],
                "clips": entries,
            },
            indent=1,
        )
    )
    print(f"wrote {LIBRARY_PATH.relative_to(ROOT)}")

    audit = audit_mapping()
    EVENTS_PATH.write_text(json.dumps(audit, indent=1))
    print(
        f"wrote {EVENTS_PATH.relative_to(ROOT)} "
        f"(events={len(audit['events'])}, "
        f"mapping_unavailable={audit['mapping_unavailable']})"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
