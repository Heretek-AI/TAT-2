# Audio Extraction Report — real Wwise clips + honest mapping audit

> **Superseded by the audio-wwise wave** (`docs/reports/audio-wwise.md`, 2026-11-17).
> The 3,425-chunk scan and `mapping_unavailable: true` below came from an
> unpadded-chunk alignment bug plus a truncated bank `BulkData`. The current
> pipeline extracts 5,050 media chunks (5,018 RIFF + 32 PLUG), decodes all
> 5,018 clips, resolves 5,862/5,868 event media entries and wires all nine
> gameplay tags to verified event/media pairs.

## Outcome

**Current state:** 5,018 Wwise clips are playable Ogg Vorbis files, with a
per-clip manifest; 5,862 of 5,868 event media entries resolve to a clip; all
nine gameplay tags are wired to a verified event dump + resolved clip, and
`AudioManager.has_real_clip(tag)` returns true for all nine. See
`docs/reports/audio-wwise.md` for the root cause, join validation and caveats.

The rest of this report is the historical record of the superseded 3,425-chunk
pipeline.

### Historical outcome (superseded)

All 3,425 extracted Wwise chunks were then playable Ogg Vorbis files, with a
per-clip manifest. The event-name → clip mapping audit of that pipeline found
**no link at the time**, so **nothing was wired to gameplay tags**: all 9 tags
kept their synthesized fallbacks. No event names were guessed or invented.

## Conversion stats

- Raw chunks: `extracted/audio/wwise_raw/wwise_<seq>_<offset>.wav`, 3,425 files,
  RIFF codec tag `0xFFFF` (Wwise Vorbis; FFmpeg reports "no decoder found").
- Toolchain: pinned prebuilt vgmstream **r2168** (`tools/bin/vgmstream/`,
  via `make audio-tools` / `tools/fetch_vgmstream.sh`) decodes to PCM WAV,
  then `ffmpeg -c:a libvorbis -q:a 5` encodes the final `.ogg`.
- Output: `game/assets/ue/audio/wwise/<offset-id>.ogg` — **3,425 clips**
  (3,424 converted + 1 skipped-existing and re-probed into the manifest),
  **0 failures**.
- Totals: **26,590.1 s (7.39 h)** of audio, durations 0.005 s – 541.3 s,
  390,033,540 bytes (~372 MiB). Manifest:
  `game/data/generated/audio_library.json` (id, source, duration_s,
  channels, sample_rate, output_bytes per clip + counts).
- Spot check: `ffprobe 13381358.ogg` →
  `codec_name=vorbis, sample_rate=48000, channels=2, duration=0.321938`.
- Headless Godot load test (temporary `game/tmp_ogg_check.gd`, deleted
  afterwards): `ResourceLoader.load("res://assets/ue/audio/wwise/13381358.ogg")`
  → `AudioStreamOggVorbis`, `get_length() = 0.3219 > 0`. PASS.

## Historical mapping audit (superseded)

Correction to a prior assumption: the 1,298 `AkAudioEvent` JSON exports are
**not** empty — 1,296 parse as `AkAudioEvent` with `EventCookedData`
(EventId + `Media[]` of `{MediaId, DebugName}` source .wav names); 1,205
events reference media (4,303 distinct MediaIds). The 2 remaining files are
`IsInteractablePropLocal-Local/Remote` replicated-event variants, not audio
events. The recoverable half (event → MediaId → source .wav name) is
preserved verbatim in `game/data/generated/audio_events.json`; the audio-wwise
wave now joins it to clips by ubulk order.

The 3,425-chunk pipeline did **not** recover the chunk → media half:

1. Chunk ids are **ubulk byte offsets, not media ids**: `media_ids ∩
   chunk_ids = ∅` (0 matches), and seeking to the first 3 chunk ids in
   `extracted/audio/TAT/Content/Audio/WwiseSharedAssetLibrary.ubulk` lands
   on `RIFF` each time (verified).
2. **No media index was found anywhere**: 0 `.wem`/`.bnk` hits in
   `extracted/filelist.txt` (22,005 paths); the bank dump
   (`WwiseSharedAssetLibrary.json`) contains `Hierarchies` only
   (8,707 `SoundSfxVoice`, etc.) — no DIDX/data-index section.
3. **Size matching is ambiguous both ways** (tested, rejected): 3,126
   distinct chunk sizes vs 4,529 bank `InMemoryMediaSize` values; only 1,661
   exact intersections (3,011 with ±1 RIFF-pad tolerance); 521 chunks share
   a size with another chunk and 286 bank sizes are shared by multiple
   media. Not a unique join key.
4. RIFF payloads carry no MediaId (subchunks are `fmt `/`hash`/`data`;
   `hash` is an opaque 16-byte blob).

Recorded at the time as `mapping_unavailable: true` with the full evidence
block in `game/data/generated/audio_events.json`.

## Historical wiring (superseded)

- `tags` in `audio_events.json`: all 9 gameplay tags (`footstep`,
  `blackjack`, `lockpick`, `grapple`, `smoke`, `fairy`, `alert`, `loot`,
  `door`) → `{"clip": null, "status": "fallback"}`.
- `AudioManager` (`game/src/core/audio_manager.gd`): keeps the 9 preloaded
  synthesized `.wav` fallbacks; on `_ready()` it attempts to load real clips
  from `audio_events.json` `tags` (skipped silently when absent/unmapped)
  and exposes `has_real_clip(tag)`. Headless check confirmed
  `has_real_clip("footstep") == false` and unknown tags return false.
- When the mapping was recovered, only `audio_events.json` needed confirmed
  `tag → res://…​/wwise/<id>.ogg` entries — no `AudioManager` code changes.
  That is what the audio-wwise wave did.

## Disk usage

- `game/assets/ue/audio/wwise/`: 3,425 `.ogg` + editor `.import` files,
  ~372 MiB audio (+ ~0.8 MiB `.import` sidecars).
- `game/data/generated/audio_library.json` (~0.7 MiB),
  `game/data/generated/audio_events.json` (~0.6 MiB).

## Verification commands (all exit 0)

- `make audio-tools` → vgmstream r2168 present, idempotent.
- `python3 tools/convert_wwise.py` → `converted=3424 skipped=1 failed=0`,
  exit 0.
- `jq '.counts' game/data/generated/audio_library.json` + ffprobe spot check.
- Godot editor import + headless ogg/AudioManager check → `TMPCHECK
  SUMMARY: fails=0` (temp script deleted).
- `make test` → `SUMMARY: fails=0`, zero `SCRIPT ERROR` lines (only benign
  engine-at-exit RID-leak notice).

## Files touched

`tools/fetch_vgmstream.sh` (new), `tools/convert_wwise.py` (new),
`game/src/core/audio_manager.gd`, `Makefile` (`audio-tools` target only),
`.gitignore` (`tools/bin/` line), `game/assets/ue/audio/wwise/**`,
`game/data/generated/audio_library.json`, `game/data/generated/audio_events.json`
(both gitignored generated data), this report. Nothing else modified.
