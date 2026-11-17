# Wwise audio event → media → clip recovery (2026-11-17)

The audio pipeline decoded only 3,425 of the 5,018 Wwise media chunks in `WwiseSharedAssetLibrary.ubulk` (676,561,969 bytes) and reported `mapping_unavailable: true`, so every gameplay tag kept its synthesized fallback. Both halves of that outcome were wrong. The scanner advanced by `8 + size + (size & 1)` on the assumption that RIFF chunks are word-aligned, but the cooked ubulk is unpadded, so every odd-sized chunk drifted one byte onto garbage. The bank also carries no per-hash size or offset: `PackagedFiles[].BulkData` was serialized truncated to `{IsWemFile, IsPlugin}`. The fix walks the media region by exactly `8 + size` and joins events to clips by file order, validating that order against the bank's own `InMemoryMediaSize` values (4,155 of 4,160 exact = 99.88%; the identity order is far above every shifted, reversed or random order). The wave now decodes all 5,018 clips and wires all nine gameplay tags to a real event dump and a resolved clip.

## Root cause (R1 evidence)

### 1. The ubulk scanner assumed RIFF word alignment

`tools/extract_audio.py` walked `WwiseSharedAssetLibrary.ubulk` by advancing `8 + size + (size & 1)` bytes per chunk. That is correct for a RIFF file whose chunks are padded to even boundaries, but the cooked Wwise ubulk stores its media chunks back-to-back with **no** padding. After every odd-sized chunk the scanner skipped one byte into the next chunk's tag and then drifted through payload bytes, resynchronising only by luck.

- File size: `676,561,969` bytes.
- Chunks actually present: `5,018` RIFF media chunks (plus `32` PLUG chunks).
- Chunks the old scan recovered: `3,425` — it lost `1,593` RIFF chunks.

### 2. The bank has no per-media size or offset

The event side is intact. Each of the `1,296` `AkAudioEvent` dumps carries `EventCookedData.EventLanguageMap[].Value.Media[]`, and every media entry has:

- `MediaId`
- `DebugName` — the original `.wav` name
- `PackagedFile.Hash`

The bank side is not. `WwiseSharedAssetLibrary.CookedData.PackagedFiles` contains `5,050` entries with `IsWemFile` set (`5,018` non-plugin + `32` plugin), but their `BulkData` was serialized truncated to `{IsWemFile, IsPlugin}`. There is no size and no offset per hash, so the hash alone cannot locate a chunk. The previous pipeline therefore reported `mapping_unavailable: true` rather than guess a join.

## Fix (R2)

### 1. Strict sequential chunk walk

`scan_media_chunks()` now advances by exactly `8 + size`. It requires every tag after the bank-section run to be `RIFF` or `PLUG`, requires the walk to end exactly at EOF, and raises `ChunkScanError` on:

- an unexpected chunk tag,
- a bank section appearing after the media region has begun,
- a truncated chunk header or a chunk that ends past EOF,
- a scan that does not finish at EOF.

Result: `5,050` media chunks = `5,018` RIFF + `32` PLUG. The earlier figure of `6` PLUG chunks was wrong; `32` matches the `32` `IsPlugin` WEMs exactly.

### 2. Event → media → clip joined by order, then validated by size

The join is positional: the k-th non-plugin `IsWemFile` entry equals the k-th RIFF chunk. That ordering is not assumed. It is checked against `SoundSfxVoice.Data.Source.InMemoryMediaSize`, which records the chunk's total byte length (8-byte header + payload, not payload alone), for every distinct Data voice whose media is not plugin-processed.

Measured on the same `4,160` comparable voices:

| Chunk order | `InMemoryMediaSize` match |
|---|---:|
| identity (k-th ↔ k-th) | **99.88%** (`4,155 / 4,160`) |
| shifted +1 | `0.31%` |
| shifted −1 | `0.31%` |
| shifted +2 | `0.31%` |
| shifted −2 | `0.31%` |
| shifted +3 | `0.22%` |
| shifted −3 | `0.22%` |
| reversed | `0` |
| random (2,000 shuffles) | `~0.023%` |

The five mismatches are long (`90–211 s`) weather/ambience loops. In every case the chunk is larger than `InMemoryMediaSize`, the expected size occurs nowhere else in the ubulk, and both neighbouring indices match. That pattern is consistent with a re-cook into a larger encoding; it is recorded as a hypothesis, not an established cause.

### 3. Robustness

- **Stale-output pruning is refused on an empty or failed pass.** A missing `vgmstream`/`ffmpeg` used to delete the entire clip library; pruning now happens only after a fully successful conversion pass.
- **`ChunkScanError` yields `mapping_unavailable: true`.** A layout change no longer leaves a previous `audio_events.json` claiming a verified mapping.
- **MediaId → hash conflicts fail the join.** A MediaId that resolves to more than one hash is excluded and the join is refused; there are `0` such conflicts in this data.
- **Coverage denominators are recorded.** `4,160` of `5,018` RIFF chunks are size-checked (`82.9%`); `4,160` of `4,844` distinct Data voices (`85.9%`). `19` streaming voices are excluded because their `InMemoryMediaSize` is a prefetch size, roughly `13–470×` smaller than the full chunk (measured `13.9–473.7×`).

## Verified counts & measurements

### Decode

| Metric | Value |
|---|---:|
| Decoded clips | `5,018` |
| Total duration | `39,222.2 s` (10.9 h) |
| Ogg output | `581,494,198` bytes (~555 MiB) |
| Conversion failures | `0` |
| Godot `.import` sidecars | `5,018` |
| `ResourceLoader.exists()` | `5,018 / 5,018` |

The wave's decode pass produced `5,018` Ogg Vorbis clips via vgmstream r2168 + `ffmpeg -c:a libvorbis -q:a 5`, with `0` failures. A later no-force pass reports all `5,018` as `skipped` (present from the earlier pass), still with `0` failures. A headless Godot probe after the wave returned `TMPAUDIO SUMMARY: fails=0`, with `ResourceLoader.exists()` true for every clip.

### Events and media

| Metric | Value |
|---|---:|
| `AkAudioEvent` files | `1,298` |
| Parsed as `AkAudioEvent` | `1,296` |
| Events with media | `1,205` |
| Events with at least one resolved clip | `1,205` |
| Media entries | `5,868` |
| Media entries resolved | `5,862` |
| Media entries unresolved | `6` (convolution-reverb IRs in PLUG chunks) |
| Distinct clip paths referenced by events | `4,299` |

The `6` unresolved entries are all convolution-reverb impulse responses (for example `AK Hamburg Echo Chamber.wav` and several BOOM Library / Altiverb IRs) stored as PLUG chunks, which this vgmstream path cannot decode. No other media entry failed to resolve.

### Tag wiring

All nine gameplay tags were verified against a real event dump and a resolved clip:

| Tag | Event | EventId | Media `DebugName` |
|---|---|---:|---|
| `footstep` | `Play_FS_Player_Walk` | `803501663` | `S_BL_FS_Walk_WoodGeneric_01.wav` |
| `blackjack` | `Play_Blackjack_Impact_Generic` | `950767345` | `Equipment_Blackjack_Impact_Generic_TEMP_06.wav` |
| `lockpick` | `Play_Obj_PickableLock_Unlock` | `2607545677` | `Prop_LockPick_OpenV2_01.wav` |
| `grapple` | `Play_Ability_Hotwire_Cast` | `1673619295` | `Ability_Climbing_Rope_Launch_V2_03.wav` |
| `smoke` | `Eqp_SmokeBomb_Impact` | `1301375076` | `Eqp_KnockoutGas_Activate_OneOff_02.wav` |
| `fairy` | `Play_PickpocketingTool_Cast_Start` | `117953322` | `Ability_Tulpa_Cast_01.wav` |
| `alert` | `Play_Obj_SecurityCamera_ToAlert` | `903969937` | `Obj_SecurityCamera_MagicEye_Screech_01.wav` |
| `loot` | `Play_Loot_Pickup_Generic` | `2354702333` | `Loot_Pickup_Generic_V1_04.wav` |
| `door` | `Play_Prop_Int_Door_Wood_Open` | `2735691337` | `Props_Int_Door_Open_Wood_V1_02.wav` |

Each clip resolves to `res://assets/ue/audio/wwise/<ubulk-offset>.ogg` (the footstep tag, for example, uses `289551305.ogg`). `AudioManager.has_real_clip(tag)` returns true for all nine tags; the same headless probe reported `has_real_clip_true=9/9`.

## Evidence

- `game/data/generated/audio_events.json`: `counts.events = 1,296`, `events_with_resolved_clip = 1,205`, `media_entries = 5,868`, `media_entries_resolved = 5,862`; `evidence.order_join.order_verified = true` with `counts_match`, `type_sequence_match`, `unique_hashes`, `riff_headers_valid` and `unique_mediaid_hashes` all true; `evidence.tag_assignments` holds the nine verified rows above.
- `game/data/generated/audio_library.json`: `counts.clips = 5,018`, `counts.failed = 0`, `counts.total_duration_s = 39,222.2`, `counts.total_output_bytes = 581,494,198`.
- On-disk counts: `5,018` `.ogg` files, `5,018` `.import` sidecars and `5,018` raw `wwise_*.wav` chunks.
- Independent checks run for this report: the shift table above (2,000 random shuffles), `51` adjacent equal-size RIFF pairs, `0` CRC32/Adler32/FNV-1a/MD5 matches over all `5,018` chunks (full chunk and payload), and a headless Godot probe (`TMPAUDIO has_real_clip_true=9/9`, `resource_exists=5018/5018`, `SUMMARY: fails=0`).

## Caveats

- **The order join is proven by size statistics, not by content hashing.** The Wwise `Hash` is not a CRC32, Adler32, FNV-1a or MD5 of the full chunk or its payload (checked across all `5,018` RIFF chunks: `0` matches for each). Equal-size permutations therefore remain theoretically invisible: `51` adjacent RIFF pairs share a size. No such swap is present in this data — the identity match is `99.88%`, and every mismatch is a long loop whose neighbours match — but the check cannot mathematically exclude one.
- **`6` media entries remain unresolved**: the convolution-reverb IRs in PLUG chunks.
- **`51` WEMs are `bStreaming: true`.** Their full chunks are present and decode (`24` streaming media entries resolved), but a different cook could stream them externally.
- **The join assumes one bank and one ubulk.** The code documents that assumption; if the single ubulk's chunk layout or counts change, the count/type check fails safely instead of emitting a guessed mapping.
- `docs/reports/audio-extraction.md` documents the superseded 3,425-chunk pipeline and now carries a note pointing here; its counts are historical.

## Reproduce

```bash
python3 tools/extract_audio.py          # strict unpadded walk -> extracted/audio/wwise_raw/
python3 tools/convert_wwise.py --force  # decode all 5,018 chunks -> Ogg + manifests
make test                               # SUMMARY: fails=0
make audit                              # 99.4%
```
