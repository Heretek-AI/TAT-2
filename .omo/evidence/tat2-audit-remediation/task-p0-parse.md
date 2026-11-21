# task-p0-parse — parse_tables.py fail-closed remediation (pipeline P0-4 + P0-5)

Date (UTC): 2026-11-20. Scope: ONLY `tools/parse_tables.py` + this file.
Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md` §1 T10 / §2 items 2,
plus `audit-pipeline.md` §2.1 (`parse_tables.py:1202-1208`) and §2.1 MID
(`parse_tables.py:763-766, 809-856`). All cited spans re-opened before editing.

## 1. What changed (and what deliberately did not)

**P0-4 — skip gate in `extract_levels` (~1202-1230).**
Every `Maps/*.json` that does not become a level payload is now counted and
listed: `BPP_*` (legitimate — re-consumed as packed-actor templates, listed
but non-fatal), corrupt JSON (fatal, reason carries the parse error), and
empty/non-list exports (fatal). Any fatal skip raises `SystemExit` after the
file loop, so the normalize step cannot go green on a partial tree.

**P0-5 — UNRESOLVED vs null MID provenance (~763-880, end of `extract_levels`).**
`_resolve_override_item` now appends a full record
`{map, mesh, ue_slot, op, on}` to `mid_stats["records"]` (uncapped) on every
unresolved MID, threaded with mesh + UE slot index from
`_component_override_paths` (new optional `slot_ctx` arg). `extract_levels`
writes the sidecar `game/data/generated/levels/_mid_unresolved.json`:
slots listed there are UNRESOLVED; `""` slots NOT listed are authored-empty
(null/NoOverride).

Deliberately unchanged: in-band `override_materials` values stay `""` for
both cases. `run_tests.gd` block 31 pins exact arrays containing `""`
(31b `ov_lsm_want = ["", ...]`, 31e `ov_bay_want`, 31d MID wants) and 31f
sweeps `*.tatlevel.json` files only — a sentinel or `null` in-band would
break those pins (`str(null)` is not `""` in GDScript). The sidecar filename
does not match `*.tatlevel.json`, so the 31f 73-file count is unaffected.

## 2. VERIFY — corrupt Maps JSON fails loudly (probe file deleted after)

Planted `extracted/json/Maps/ZZZ_CORRUPT_PROBE.json` (`{this is not valid json!!!`),
ran `python3 tools/parse_tables.py`:

- exit code: **1**
- stderr (quoted verbatim):
  `parse_tables: REFUSING to normalize with 1 skipped Maps JSONs: ZZZ_CORRUPT_PROBE.json (corrupt JSON: Expecting property name enclosed in double quotes: line 1 column 2 (char 1))`
- stdout also lists all 39 legitimate `BPP_*` skips plus the corrupt file
  (`SKIP ZZZ_CORRUPT_PROBE.json: corrupt JSON: ...`), proving count + list.
- probe file deleted after the run (confirmed absent).

## 3. VERIFY — clean run (valid inputs unchanged)

After deleting the probe, `python3 tools/parse_tables.py` exits **0**:

- `Normalized 73 level JSONs -> 134620 mesh instances, 2142 lights`
  (73 = the exact file count pinned by run_tests.gd block 31f)
- `MID overrides: mid_resolved=1090, mid_unresolved=0`
- `MID unresolved sidecar: game/data/generated/levels/_mid_unresolved.json (0 records)`
- `game/data/generated/` is gitignored, so byte-identity was checked by
  behavior instead: same 73-file set rewritten (stale_removed=73), MID
  resolution counts intact, no new `*.tatlevel.json` names, in-band `""`
  values untouched by construction (only additive record-keeping).

Targeted unit check (no full run): `_component_override_paths` with
`[None, <MID ref>]`, `exps=None` returns `[]` (trailing `""` trimmed, as
before) while `mid_stats["records"]` gains exactly one record with
`map/mesh/ue_slot/op/on` — i.e. authored-empty slot 0 gets no record (null)
and unresolved slot 1 gets one (UNRESOLVED). In-band values identical.
