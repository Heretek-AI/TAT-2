# producers — summary (round 4)

HEAD: the commit on `teamwork/20261127-1810-phase3-producers` created by this
round (parent `8412a13`). Round 1 content is in `bd1e42f`; round 2 in
`1e2ef16`; round 3 in `8412a13`.

## Round 2 fixes (falsifier findings)

1. **Makefile nav filter.** `make extract` died at the nav stage: `...\.umap$'`
   let GNU make consume `$'` as a one-character variable reference, leaving the
   shell an unmatched quote. The line is now `...\.umap$$'`. Proven by
   execution, not `make -n`: with the old line a scratch Makefile copy fails
   `/bin/sh: unexpected EOF while looking for matching \`''`; with the fixed
   line the stub extractor receives the exact regex as one argv and the recipe
   reaches `cubemaps --overwrite`.
2. **Executable recipe test.** New `tools/test_extract_recipe.py` runs the real
   `extract` recipe with `make -o build-extractor EX=<stub>` and pins the exact
   argv order: list, raw, tables, levels, nav (closed regex), meshes,
   materials --overwrite, audio, textures, cubemaps --overwrite, anims. It also
   executes `make json` and its failure modes. `tools/test_extractor_config.py`
   no longer accepts the standalone json target as proof that `extract`
   contains it; it now asserts `extract` has no json stage, the nav line uses
   `$$'`, and cubemaps follows nav.
3. **`make json` mapping + status.** The Makefile resolves `USMAP` from
   `USMAP`/`TAT_USMAP`, the worktree's `tools/ue4ss/output`, or the main
   checkout derived from `git rev-parse --git-common-dir`. The recipe fails
   exit 2 when the file is absent and passes `--usmap ... --fail-on-error`.
   The extractor now counts failures (`Exporter.FailCount`) and returns 1 when
   `--fail-on-error` is set and any package dump failed, so an all-
   `MappingException` run no longer exits 0.
4. **F3: Destructibles json.** Removed from `extract` (the new `tables` root
   already dumps the GC packages). `make json`/`make extract-json` stay as a
   standalone filtered dump, and the misleading "new files only / does not
   rewrite" comment is gone.
5. **Handoff/regeneration.** Targeted commands are `make build-extractor`,
   `make json` (or the raw `json --usmap ... --fail-on-error --filter
   'Destructibles/'`), `levels`, `cubemaps --overwrite`, `make normalize`.
   `make extract` is fixed and may be used, but the targeted path avoids a full
   re-extract.
6. **Cubemap hardening.** `SafeCubeId` restricts ids to `[a-z0-9_-]`; the
   resolved directory is asserted under `Cubemaps/`; all six faces are encoded
   in memory first, stale `face_*` is deleted only after success, new faces are
   written, and the manifest is moved into place last via `.tmp`.
7. **FaceMeanLinear formats (round-4 correction).** The round-3 set still
   claimed two layouts the pinned CUE4Parse 1.2.2.202611 cannot decode/encode:
   `PF_FloatRGB` is R11G11B10_FLOAT in **4 bytes** (not 3 x half; the old
   6-byte fixture was fabricated) and `PF_R32G32B32F` is `Supported=false`
   (`Decode` throws before the mean). Both are removed. The final
   `HasRawHdrMean` set is exactly `PF_FloatRGBA`, `PF_A32B32G32R32F`,
   `PF_R32_FLOAT`, `PF_R16F`. `PF_A32B32G32R32F` now reads components 3/2/1
   (bytes 12/8/4) to match the library's `ToHdrBitmap(flipOrder: true)`, so the
   mean describes the exported face. The executed `tat-extract
   selftest-face-mean` builds 4x4 fixtures from the library's
   `BlockBytes`/`NumComponents`, requires every set member to be `Supported`
   and to encode through the real `CubemapOpts` writer, and reports the two
   excluded formats with their library facts (`PF_FloatRGB` supported/4 bytes,
   `PF_R32G32B32F` unsupported/12 bytes). The three shipped cubes are
   `PF_FloatRGBA`, so no current output changes.

## Checks (all green)

- `make build-extractor` → Build succeeded, 0 errors.
- `python3 -m py_compile` on the touched parsers/tests → OK.
- `make test-producers` → exit 0. New totals: `EXTRACTOR_CONFIG_TEST PASS
  checks=47`, `FACE_MEAN_TEST PASS checks=48`, `EXTRACT_RECIPE_TEST PASS
  checks=12`, `PARSE_CUBEMAP_TEST PASS checks=21`, `PARSE_CONTRACTS_TEST PASS
  checks=9`.
- `tat-extract selftest-face-mean` (executed, no pak mount): the four set
  members print `null=false ok=true` with fixture means
  (PF_FloatRGBA/PF_A32B32G32R32F = 0.25/0.5/0.75, PF_R32_FLOAT/PF_R16F =
  0.5/0.5/0.5), `FACE_MEAN_ENCODE ... ext=hdr ok=true` for each,
  `PF_B8G8R8A8` prints `null=true`, the excluded formats print
  `in_set=false` with `PF_FloatRGB library_supported=true block_bytes=4` and
  `PF_R32G32B32F library_supported=false block_bytes=12`, and the command
  exits 0 with `FACE_MEAN_SELFTEST PASS formats=4`. A set member that is
  unsupported or fails to encode increments `fails` and exits 1.
- Stub `make extract` transcript: `list, raw, tables, levels, nav --overwrite
  --filter 'Maps/(Guildhall|OldManor|FTUE)/.*\.umap$', meshes, materials
  --overwrite, audio, textures, cubemaps --overwrite, anims`, rc 0, empty
  stderr.
- Stub `make json` without `USMAP`: auto-resolved
  `.../TAT-2/tools/ue4ss/output/TAT-5.5.4-148559+++TAT+tat_release_nosrc-30afe5ff.usmap`
  and logged `json --overwrite --usmap <path> --fail-on-error --filter
  Destructibles/`. With no mapping available it exits 2 and names the cause;
  with a failing stub it exits non-zero.
- No extraction, no `make normalize`, no audit re-stamp, no generated-data
  write, no GPU run. `git status` clean after the commit.

## Sentinel regeneration (targeted; `make extract` also works now)

```bash
make build-extractor
make json                     # resolves the usmap and fails on mapping errors
tools/tat-extract/bin/Release/net10.0/tat-extract levels
tools/tat-extract/bin/Release/net10.0/tat-extract cubemaps --overwrite
make normalize
# then audit-refresh-stamps + audit at the merged HEAD
```

Raw equivalent of `make json`:

```bash
tools/tat-extract/bin/Release/net10.0/tat-extract json \
  --overwrite --usmap /home/john/Projects/TAT-2/tools/ue4ss/output/TAT-5.5.4-148559+++TAT+tat_release_nosrc-30afe5ff.usmap \
  --fail-on-error --filter 'Destructibles/'
```
