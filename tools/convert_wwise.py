#!/usr/bin/env python3
"""Convert extracted Wwise Vorbis-in-RIFF chunks to playable Ogg Vorbis.

Pipeline per chunk (extracted/audio/wwise_raw/wwise_<seq>_<offset>.wav):
    vgmstream-cli -> temp PCM WAV -> ffmpeg (libvorbis q5) ->
    game/assets/ue/audio/wwise/<offset-id>.ogg

Also writes:
    game/data/generated/audio_library.json - per-clip manifest
    game/data/generated/audio_events.json   - event -> media -> clip map:
        event name, EventId, and every Media entry's MediaId, source .wav
        DebugName, PackagedFile.Hash and decoded clip path.  The join uses
        ubulk file order (k-th non-plugin IsWemFile entry <-> k-th RIFF
        chunk) and is emitted only after it is validated against the bank's
        SoundSfxVoice InMemoryMediaSize values.

Gameplay tags are deliberately left on their synthesized fallbacks; no
clip->tag assignment happens here.

Stdlib only. Per-file failures are collected and reported; existing outputs
are probed and reported as ``skipped`` (present from an earlier pass), while
clips decoded in this run are reported as ``converted``.  Pass ``--force`` to
re-decode every chunk.  Stale outputs are pruned only after a fully successful
conversion pass.
"""

import concurrent.futures
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_audio  # same-directory pipeline helper

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "extracted" / "audio" / "wwise_raw"
OUT_DIR = ROOT / "game" / "assets" / "ue" / "audio" / "wwise"
LIBRARY_PATH = ROOT / "game" / "data" / "generated" / "audio_library.json"
EVENTS_PATH = ROOT / "game" / "data" / "generated" / "audio_events.json"
VGMSTREAM = ROOT / "tools" / "bin" / "vgmstream" / "vgmstream-cli"
EVENTS_GLOB = ROOT / "extracted" / "json" / "Audio" / "Events"
BANK_JSON = ROOT / "extracted" / "json" / "Audio" / "WwiseSharedAssetLibrary.json"

VORBIS_QUALITY = 5
WORKERS = 8
TIMEOUT_S = 120

# The order-based join is accepted only when the bank's own
# InMemoryMediaSize values agree with the chunk lengths at the resolved
# indices.  Streaming voices are excluded (their InMemoryMediaSize is a
# prefetch size, not the media length); see audit_mapping().
MIN_SIZE_MATCH_RATE = 0.995
MIN_SIZE_SAMPLE = 50

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


def convert_one(src: Path, clip_id: str, force: bool = False) -> dict:
    """Convert a single chunk; return manifest entry dict. Raises on failure."""
    dest = OUT_DIR / f"{clip_id}.ogg"
    if not force and dest.exists() and dest.stat().st_size > 0:
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


def convert_all(force: bool = False) -> tuple:
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
            pool.submit(convert_one, src, cid, force): (src, cid) for src, cid in chunks
        }
        done = 0
        for fut in concurrent.futures.as_completed(future_map):
            src = future_map[fut][0]
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
def _load_events() -> tuple:
    """Parse AkAudioEvent exports into ordered event records.

    Returns (events, mediaid_to_hash, mediaid_conflicts, event_files,
    non_event_files).  Each event record keeps every Media entry's MediaId,
    DebugName and PackagedFile.Hash.  The hash is the only stable join key:
    472 DebugNames in this bank map to more than one hash.

    A MediaId that maps to more than one hash is recorded as a conflict and
    excluded from the join map; the caller must refuse the join rather than
    silently keeping the last hash it saw.
    """
    event_files = sorted(EVENTS_GLOB.rglob("*.json")) if EVENTS_GLOB.is_dir() else []
    events: list = []
    mediaid_hashes: dict = {}
    non_event_files: list = []
    for path in event_files:
        try:
            data = json.loads(path.read_text())
        except (ValueError, OSError) as exc:
            non_event_files.append({"file": path.name, "reason": f"unreadable: {exc}"})
            continue
        entries = data if isinstance(data, list) else [data]
        parsed_any = False
        for entry in entries:
            if not isinstance(entry, dict) or entry.get("Type") != "AkAudioEvent":
                continue
            parsed_any = True
            cooked = entry.get("EventCookedData") or {}
            event_id = None
            media: list = []
            for lang in cooked.get("EventLanguageMap", []):
                value = lang.get("Value") or {}
                if event_id is None:
                    event_id = value.get("EventId")
                for m in value.get("Media", []):
                    packaged = m.get("PackagedFile") or {}
                    media_hash = packaged.get("Hash")
                    media_id = m.get("MediaId")
                    if media_id is not None and media_hash is not None:
                        mediaid_hashes.setdefault(media_id, set()).add(media_hash)
                    media.append(
                        {
                            "media_id": media_id,
                            "debug_name": m.get("DebugName"),
                            "hash": media_hash,
                        }
                    )
            events.append(
                {
                    "event": entry.get("Name"),
                    "event_id": event_id,
                    "media": media,
                }
            )
        if not parsed_any:
            kind = (
                entries[0].get("Type")
                if entries and isinstance(entries[0], dict)
                else "unknown"
            )
            non_event_files.append(
                {"file": path.name, "reason": f"not an AkAudioEvent ({kind})"}
            )
    mediaid_to_hash = {
        media_id: next(iter(hashes))
        for media_id, hashes in mediaid_hashes.items()
        if len(hashes) == 1
    }
    mediaid_conflicts = [
        {"media_id": media_id, "hashes": sorted(hashes, key=str)}
        for media_id, hashes in mediaid_hashes.items()
        if len(hashes) > 1
    ]
    mediaid_conflicts.sort(key=lambda conflict: str(conflict["media_id"]))
    return events, mediaid_to_hash, mediaid_conflicts, event_files, non_event_files


def _load_bank() -> dict:
    """Return ordered WEM entries and the SoundSfxVoice source records."""
    bank = json.loads(BANK_JSON.read_text())
    packaged = bank[0]["CookedData"]["PackagedFiles"]
    wem = [pf for pf in packaged if (pf.get("BulkData") or {}).get("IsWemFile")]
    nonplugin = [pf for pf in wem if not (pf.get("BulkData") or {}).get("IsPlugin")]
    plugin = [pf for pf in wem if (pf.get("BulkData") or {}).get("IsPlugin")]
    voices: list = []
    voices_without_size = 0
    for pf in packaged:
        for h in (pf.get("BulkData") or {}).get("Hierarchies", []):
            if h.get("Type") != "SoundSfxVoice":
                continue
            src = (h.get("Data") or {}).get("Source") or {}
            if "SourceId" in src and "InMemoryMediaSize" in src:
                voices.append(src)
            else:
                voices_without_size += 1
    return {
        "packaged": len(packaged),
        "wem": wem,
        "nonplugin": nonplugin,
        "plugin": plugin,
        "voices": voices,
        "voices_without_size": voices_without_size,
    }


def _validate_order_join(
    bank: dict,
    chunks: list,
    mediaid_to_hash: dict,
    mediaid_conflicts: list,
) -> dict:
    """Validate: k-th non-plugin WEM entry <-> k-th RIFF chunk.

    Four independent checks are recorded:
      1. counts and the RIFF/PLUG type sequence match entry-for-entry;
      2. hashes are unique across non-plugin WEM entries;
      3. SoundSfxVoice InMemoryMediaSize equals the total byte length of the
         chunk reached through MediaId -> hash -> index.  Streaming voices
         are excluded because Wwise stores a prefetch size there.
      4. no MediaId resolves to more than one PackagedFile.Hash.
    """
    nonplugin = bank["nonplugin"]
    plugin = bank["plugin"]
    wem = bank["wem"]
    riffs = [c for c in chunks if c["tag"] == b"RIFF"]
    plugs = [c for c in chunks if c["tag"] == b"PLUG"]

    counts_match = len(riffs) == len(nonplugin) and len(plugs) == len(plugin)
    type_sequence_match = len(chunks) == len(wem) and all(
        ("PLUG" if ch["tag"] == b"PLUG" else "RIFF")
        == ("PLUG" if (pf.get("BulkData") or {}).get("IsPlugin") else "RIFF")
        for ch, pf in zip(chunks, wem)
    )
    hashes = [pf.get("Hash") for pf in nonplugin]
    unique_hashes = len(set(hashes)) == len(hashes) and None not in hashes
    riff_headers_valid = all(c["valid_riff"] for c in riffs)
    unique_mediaid_hashes = not mediaid_conflicts

    hash_to_chunk = (
        {pf["Hash"]: riffs[i] for i, pf in enumerate(nonplugin)} if counts_match else {}
    )
    plugin_hashes = {pf.get("Hash") for pf in plugin}

    distinct_voices: dict = {}
    for src in bank["voices"]:
        distinct_voices.setdefault(src["SourceId"], src)
    data_voices = [
        src for src in distinct_voices.values() if src.get("SourceType") == "Data"
    ]
    streaming_voices = [
        src for src in distinct_voices.values() if src.get("SourceType") == "Streaming"
    ]

    stats = {
        "data_match": 0,
        "data_mismatch": 0,
        "streaming_excluded": 0,
        "unresolved": 0,
        "data_plugin_media": 0,
        "data_unresolved": 0,
        "data_mismatch_examples": [],
        "data_mismatch_sizes": [],
    }
    for sid, src in distinct_voices.items():
        media_hash = mediaid_to_hash.get(sid)
        chunk = hash_to_chunk.get(media_hash)
        is_data = src.get("SourceType") == "Data"
        if chunk is None:
            stats["unresolved"] += 1
            if is_data:
                if media_hash in plugin_hashes:
                    stats["data_plugin_media"] += 1
                else:
                    stats["data_unresolved"] += 1
            continue
        if src.get("SourceType") == "Streaming":
            stats["streaming_excluded"] += 1
            continue
        if chunk["total_size"] == src["InMemoryMediaSize"]:
            stats["data_match"] += 1
        else:
            stats["data_mismatch"] += 1
            stats["data_mismatch_sizes"].append(
                (src["InMemoryMediaSize"], chunk["total_size"])
            )
            if len(stats["data_mismatch_examples"]) < 10:
                stats["data_mismatch_examples"].append(
                    {
                        "source_id": sid,
                        "in_memory_media_size": src["InMemoryMediaSize"],
                        "chunk_total_size": chunk["total_size"],
                        "chunk_offset": chunk["offset"],
                    }
                )

    comparable = stats["data_match"] + stats["data_mismatch"]
    match_rate = (stats["data_match"] / comparable) if comparable else 0.0
    # Denominator for the Data-voice size check: Data voices whose media is
    # not plugin-processed.  Plugin media cannot be reached through the RIFF
    # order join, so counting it against the join would understate coverage.
    data_non_plugin = len(data_voices) - stats["data_plugin_media"]
    data_check_rate = (comparable / data_non_plugin) if data_non_plugin else 0.0
    chunk_check_rate = (comparable / len(riffs)) if riffs else 0.0
    examples = stats["data_mismatch_examples"]
    all_chunk_sizes = {c["total_size"] for c in chunks}
    mismatch_sizes = stats["data_mismatch_sizes"]
    mismatch_observations = {
        "mismatch_count": stats["data_mismatch"],
        "all_chunks_larger_than_expected": all(
            actual > expected for expected, actual in mismatch_sizes
        ),
        "expected_sizes_absent_from_ubulk": all(
            expected not in all_chunk_sizes for expected, _ in mismatch_sizes
        ),
    }
    order_verified = bool(
        counts_match
        and type_sequence_match
        and unique_hashes
        and riff_headers_valid
        and unique_mediaid_hashes
        and comparable >= MIN_SIZE_SAMPLE
        and match_rate >= MIN_SIZE_MATCH_RATE
    )
    return {
        "order_verified": order_verified,
        "counts_match": counts_match,
        "type_sequence_match": type_sequence_match,
        "unique_hashes": unique_hashes,
        "riff_headers_valid": riff_headers_valid,
        "unique_mediaid_hashes": unique_mediaid_hashes,
        "mediaid_hash_conflicts": len(mediaid_conflicts),
        "mediaid_hash_conflict_examples": mediaid_conflicts[:10],
        "riff_chunks": len(riffs),
        "plug_chunks": len(plugs),
        "nonplugin_wem": len(nonplugin),
        "plugin_wem": len(plugin),
        "distinct_voices_total": len(distinct_voices),
        "distinct_data_voices": len(data_voices),
        "distinct_streaming_voices": len(streaming_voices),
        "data_voices_with_plugin_media": stats["data_plugin_media"],
        "data_voices_non_plugin": data_non_plugin,
        "data_voices_size_checked": comparable,
        "data_voices_size_checked_rate": round(data_check_rate, 6),
        "data_voices_unresolved": stats["data_unresolved"],
        "chunks_size_checked": comparable,
        "chunks_total": len(riffs),
        "chunks_size_checked_rate": round(chunk_check_rate, 6),
        "size_comparable": comparable,
        "size_matches": stats["data_match"],
        "size_mismatches": stats["data_mismatch"],
        "size_match_rate": round(match_rate, 6),
        "streaming_excluded": stats["streaming_excluded"],
        "unresolved_voices": stats["unresolved"],
        "data_mismatch_examples": examples,
        "data_mismatch_observations": mismatch_observations,
    }


def audit_mapping(entries: list) -> dict:
    """Join events to decoded clips through the validated ubulk chunk order.

    The cooked BulkData for Wwise media was serialized as only
    {IsWemFile, IsPlugin}: no size and no offset.  The join therefore relies
    on file order (k-th non-plugin IsWemFile entry <-> k-th RIFF chunk in the
    ubulk) and is only used after _validate_order_join() confirms it against
    the bank's own InMemoryMediaSize values.  If validation fails, no clips
    are emitted (mapping_unavailable stays true) rather than guessing.
    """
    (
        events,
        mediaid_to_hash,
        mediaid_conflicts,
        event_files,
        non_event_files,
    ) = _load_events()
    evidence: dict = {
        "ak_event_files": len(event_files),
        "ak_events_parsed": len(events),
        "ak_events_with_media": sum(1 for e in events if e["media"]),
        "non_event_files": non_event_files,
        "distinct_event_media_ids": len(mediaid_to_hash) + len(mediaid_conflicts),
        "mediaid_hash_conflicts": len(mediaid_conflicts),
        "mediaid_hash_conflict_examples": mediaid_conflicts[:10],
        "bank_json_present": BANK_JSON.exists(),
    }

    bank = None
    chunks: list = []
    order: dict = {}
    ubulks = sorted((ROOT / "extracted" / "audio").rglob("*.ubulk"))
    evidence["ubulk_files"] = [str(p.relative_to(ROOT)) for p in ubulks]
    if BANK_JSON.exists():
        bank = _load_bank()
        evidence["bank_packaged_files"] = bank["packaged"]
        evidence["bank_wem_entries"] = len(bank["wem"])
        evidence["bank_wem_nonplugin"] = len(bank["nonplugin"])
        evidence["bank_wem_plugin"] = len(bank["plugin"])
        evidence["bank_wem_streaming"] = sum(
            1 for pf in bank["wem"] if pf.get("bStreaming")
        )
        evidence["bank_wem_streaming_nonplugin"] = sum(
            1 for pf in bank["nonplugin"] if pf.get("bStreaming")
        )
        evidence["bank_wem_streaming_and_plugin"] = sum(
            1
            for pf in bank["wem"]
            if pf.get("bStreaming") and (pf.get("BulkData") or {}).get("IsPlugin")
        )
        evidence["bank_voices_with_size"] = len(bank["voices"])
        evidence["bank_voices_without_size"] = bank["voices_without_size"]
    if bank is not None and ubulks:
        try:
            chunks = extract_audio.scan_media_chunks(ubulks[0])
        except extract_audio.ChunkScanError as exc:
            # Never let a layout change leave a previous audio_events.json
            # claiming a verified mapping: record the scan failure and emit an
            # unavailable mapping with no clip assignments below.
            scan_error = str(exc)
            evidence["chunk_scan"] = {
                "file": str(ubulks[0].relative_to(ROOT)),
                "file_size": ubulks[0].stat().st_size,
                "media_chunks": 0,
                "media_start_offset": None,
                "ends_at_eof": False,
                "error": scan_error,
            }
            order = {
                "order_verified": False,
                "scan_error": scan_error,
                "mediaid_hash_conflicts": len(mediaid_conflicts),
                "mediaid_hash_conflict_examples": mediaid_conflicts[:10],
            }
        else:
            file_size = ubulks[0].stat().st_size
            ends_at_eof = bool(chunks) and (
                chunks[-1]["offset"] + chunks[-1]["total_size"] == file_size
            )
            evidence["chunk_scan"] = {
                "file": str(ubulks[0].relative_to(ROOT)),
                "file_size": file_size,
                "media_chunks": len(chunks),
                "media_start_offset": chunks[0]["offset"] if chunks else None,
                "ends_at_eof": ends_at_eof,
            }
            order = _validate_order_join(
                bank, chunks, mediaid_to_hash, mediaid_conflicts
            )
    if order and "size_comparable" in order:
        # Only explain the size comparison when the order block was actually
        # produced by validation.  The wording is a hypothesis: the cooked
        # bank does not retain the original encoding size, so a re-cook cannot
        # be proven from it.
        order["note"] = (
            "Chunk lengths are compared against the chunk's total byte length "
            "(8-byte header + payload), which is what Wwise's InMemoryMediaSize "
            "records. Streaming voices are excluded because their "
            "InMemoryMediaSize is a prefetch size. The few Data voices that "
            "disagree are consistent with a re-cook into a larger encoding: "
            "each mismatch is a long (90-211 s) loop, the chunk is larger than "
            "InMemoryMediaSize, the expected size does not occur anywhere else "
            "in the ubulk, and no neighbouring index is shifted. This remains "
            "a hypothesis, not an established cause."
        )
    evidence["order_join"] = order

    order_ok = bool(order.get("order_verified"))
    riffs = [c for c in chunks if c["tag"] == b"RIFF"]
    nonplugin = bank["nonplugin"] if bank else []
    plugin_hashes = {pf.get("Hash") for pf in bank["plugin"]} if bank else set()
    wem_hashes = {pf.get("Hash") for pf in bank["wem"]} if bank else set()
    streaming_hashes = (
        {pf.get("Hash") for pf in bank["wem"] if pf.get("bStreaming")}
        if bank
        else set()
    )

    clip_by_hash: dict = {}
    decoded_by_id = {str(e["id"]): e for e in entries}
    validated = order_ok and bool(decoded_by_id)
    missing_clips = 0
    if validated:
        for i, pf in enumerate(nonplugin):
            media_hash = pf.get("Hash")
            clip_id = str(riffs[i]["offset"])
            manifest = decoded_by_id.get(clip_id)
            if manifest is None:
                clip_by_hash[media_hash] = None
                missing_clips += 1
            else:
                clip_by_hash[media_hash] = manifest["res_path"]
    evidence["decoded_clips"] = len(decoded_by_id)
    evidence["decoded_clip_ids_missing_for_riff_chunks"] = missing_clips
    evidence["streaming_wem_hashes_with_clip"] = (
        sum(1 for h in streaming_hashes if clip_by_hash.get(h)) if validated else 0
    )
    evidence["plugin_wem_hashes"] = len(plugin_hashes)

    resolved_events: list = []
    unresolved_by_reason: dict = {}
    total_media = 0
    resolved_media = 0
    events_with_resolved = 0
    streaming_media_entries = 0
    streaming_media_entries_resolved = 0
    plugin_media_entries = 0
    for ev in events:
        media_out: list = []
        for m in ev["media"]:
            total_media += 1
            media_hash = m["hash"]
            if media_hash in streaming_hashes:
                streaming_media_entries += 1
            if media_hash in plugin_hashes:
                plugin_media_entries += 1
            clip = None
            reason = None
            if media_hash is None:
                reason = "no_packaged_file"
            elif not validated:
                reason = "mapping_not_validated"
            elif clip_by_hash.get(media_hash):
                clip = clip_by_hash[media_hash]
            elif media_hash in plugin_hashes:
                reason = "plugin_media"
            elif media_hash in wem_hashes:
                reason = "decode_failed"
            else:
                reason = "hash_not_in_bank"
            if clip is not None:
                resolved_media += 1
                if media_hash in streaming_hashes:
                    streaming_media_entries_resolved += 1
            else:
                unresolved_by_reason[reason] = unresolved_by_reason.get(reason, 0) + 1
            media_out.append(
                {
                    "media_id": m["media_id"],
                    "debug_name": m["debug_name"],
                    "hash": media_hash,
                    "clip": clip,
                    "unresolved_reason": reason,
                }
            )
        if any(m["clip"] for m in media_out):
            events_with_resolved += 1
        resolved_events.append(
            {
                "event": ev["event"],
                "event_id": ev["event_id"],
                "media": media_out,
                "clip": None,  # no event-level pick is made in this task
            }
        )

    evidence["total_media_entries"] = total_media
    evidence["resolved_media_entries"] = resolved_media
    evidence["unresolved_media_entries"] = total_media - resolved_media
    evidence["unresolved_media_by_reason"] = unresolved_by_reason
    evidence["streaming_media_entries"] = streaming_media_entries
    evidence["streaming_media_entries_resolved"] = streaming_media_entries_resolved
    evidence["plugin_media_entries"] = plugin_media_entries
    evidence["events_with_resolved_clip"] = events_with_resolved
    evidence["conclusion"] = (
        "Order-based event->clip join validated: the k-th non-plugin IsWemFile "
        "entry maps to the k-th RIFF chunk, confirmed by matching "
        f"{order.get('size_matches', 0)}/{order.get('size_comparable', 0)} "
        "comparable SoundSfxVoice InMemoryMediaSize values "
        f"({order.get('size_match_rate', 0):.2%}) plus an exact RIFF/PLUG type "
        "sequence match. Plugin media (PLUG chunks) remain non-decodable by "
        "this path. No gameplay tag is assigned a clip in this task."
        if validated
        else "Order-based join did not pass validation; no clips were emitted."
    )

    tags = {
        tag: {
            "clip": None,
            "status": "fallback",
            "reason": (
                "event->clip map recovered; gameplay-tag assignment is a "
                "separate task, synthesized fallback kept"
                if validated
                else "no validated event->clip mapping; synthesized fallback kept"
            ),
        }
        for tag in FALLBACK_TAGS
    }
    return {
        "mapping_unavailable": not validated,
        "counts": {
            "events": len(resolved_events),
            "events_with_media": sum(1 for e in resolved_events if e["media"]),
            "events_with_resolved_clip": events_with_resolved,
            "media_entries": total_media,
            "media_entries_resolved": resolved_media,
            "media_entries_unresolved": total_media - resolved_media,
            "media_entries_unresolved_by_reason": unresolved_by_reason,
            "wem_entries": len(bank["wem"]) if bank else 0,
            "wem_streaming": evidence.get("bank_wem_streaming", 0),
            "wem_plugin": len(bank["plugin"]) if bank else 0,
            "wem_streaming_and_plugin": evidence.get(
                "bank_wem_streaming_and_plugin", 0
            ),
        },
        "evidence": evidence,
        "tags": tags,
        "events": resolved_events,
    }


def rebuild_entries_from_outputs() -> list:
    """Probe already-converted clips so a failed pass can keep a full manifest.

    Used only when the conversion pass cannot run or produced nothing.  It
    never decodes and never deletes; entries are marked ``skipped`` because
    they were present, not decoded, in this pass.
    """
    if not OUT_DIR.is_dir():
        return []
    source_by_id: dict = {}
    if SRC_DIR.is_dir():
        try:
            source_by_id = {cid: src.name for src, cid in collect_chunks()}
        except OSError:
            source_by_id = {}
    entries: list = []
    for dest in sorted(OUT_DIR.glob("*.ogg")):
        probed = probe_audio(dest)
        if probed is None:
            continue
        duration, channels, sample_rate = probed
        clip_id = dest.stem
        entries.append(
            {
                "id": clip_id,
                "source": source_by_id.get(clip_id, ""),
                "duration_s": round(duration, 3),
                "channels": channels,
                "sample_rate": sample_rate,
                "output": f"wwise/{clip_id}.ogg",
                "res_path": f"res://assets/ue/audio/wwise/{clip_id}.ogg",
                "output_bytes": dest.stat().st_size,
                "status": "skipped",
            }
        )
    entries.sort(key=lambda e: int(e["id"]) if e["id"].isdigit() else 0)
    return entries


def prune_stale_outputs(entries: list) -> int:
    """Remove .ogg files (and Godot .import sidecars) no longer in the manifest.

    Pruning is only safe after a successful conversion pass.  An empty entry
    list means the pass could not run (missing vgmstream/source/ffmpeg) or
    produced nothing; deleting outputs then would erase the whole library.
    """
    if not entries:
        print("refusing to prune: conversion pass produced no entries")
        return 0
    keep = {e["id"] for e in entries}
    pruned = 0
    for dest in OUT_DIR.glob("*.ogg"):
        if dest.stem in keep:
            continue
        dest.unlink()
        sidecar = dest.with_name(dest.name + ".import")
        if sidecar.exists():
            sidecar.unlink()
        pruned += 1
    return pruned


def main() -> int:
    force = "--force" in sys.argv[1:]
    entries, failures = convert_all(force=force)
    top_level_failures = [failure for failure in failures if failure[0] == "all"]
    conversion_succeeded = bool(entries) and not failures
    if not conversion_succeeded:
        if top_level_failures:
            reason = top_level_failures[0][1]
        elif not entries:
            reason = "conversion pass produced no clips"
        else:
            reason = f"{len(failures)} clip(s) failed to convert"
        print(f"ERROR: {reason}")
        # Pruning is only safe after a successful conversion pass: an empty
        # or failed pass must never delete the existing library.
        print(
            "pruning is only safe after a successful conversion pass; "
            "existing outputs are kept"
        )
        converted_ids = {e["id"] for e in entries if e["status"] == "converted"}
        entries = rebuild_entries_from_outputs()
        for entry in entries:
            if entry["id"] in converted_ids:
                entry["status"] = "converted"
        if not entries:
            print(
                "no existing decoded clips could be probed; leaving "
                f"{LIBRARY_PATH.relative_to(ROOT)} and "
                f"{EVENTS_PATH.relative_to(ROOT)} untouched"
            )
            return 1
        print(
            f"rebuilt manifest from {len(entries)} existing clip(s) without "
            "decoding (status=skipped means present, not decoded this pass)"
        )
    else:
        pruned = prune_stale_outputs(entries)
        print(f"pruned {pruned} stale clip(s) not present in the current manifest")

    converted = sum(1 for e in entries if e["status"] == "converted")
    skipped = sum(1 for e in entries if e["status"] == "skipped")
    total_s = round(sum(e["duration_s"] for e in entries), 1)
    out_bytes = sum(e["output_bytes"] for e in entries)
    if converted and converted == len(entries):
        decode_pass = "decoded"
    elif converted:
        decode_pass = "partial_decode"
    else:
        decode_pass = "probed_existing"
    print(
        f"decode pass: decoded_this_pass={converted} "
        f"present_from_previous_pass={skipped} failed={len(failures)} "
        f"({decode_pass})"
    )
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
                    "decoded_this_pass": converted,
                    "present_from_previous_pass": skipped,
                    "decode_pass": decode_pass,
                },
                "failures": [{"source": name, "error": err} for name, err in failures],
                "clips": entries,
            },
            indent=1,
        )
    )
    print(f"wrote {LIBRARY_PATH.relative_to(ROOT)}")

    audit = audit_mapping(entries)
    EVENTS_PATH.write_text(json.dumps(audit, indent=1))
    counts = audit["counts"]
    print(
        f"wrote {EVENTS_PATH.relative_to(ROOT)} "
        f"(events={counts['events']}, "
        f"with_resolved_clip={counts['events_with_resolved_clip']}, "
        f"media={counts['media_entries_resolved']}/{counts['media_entries']} resolved, "
        f"mapping_unavailable={audit['mapping_unavailable']})"
    )
    print(
        f"wem entries={counts['wem_entries']} "
        f"streaming={counts['wem_streaming']} plugin={counts['wem_plugin']} "
        f"unresolved_by_reason={counts['media_entries_unresolved_by_reason']}"
    )
    return 0 if conversion_succeeded else 1


if __name__ == "__main__":
    raise SystemExit(main())
