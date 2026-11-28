# producers — summary (round 2)

HEAD: the commit on `teamwork/20261127-1810-phase3-producers` created by this
round (parent `bd1e42f`). Round 1 content is in `bd1e42f`.

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
7. **FaceMeanLinear formats.** Added `PF_FloatRGB`, `PF_R32G32B32F` and
   `PF_R16F` to the raw half/float readers, so the round-1 null-for-format
   minor is fixed (unknown raw layouts still return null, never a guess).

## Checks (all green)

- `make build-extractor` → Build succeeded, 0 errors.
- `python3 -m py_compile` on the touched parsers/tests → OK.
- `make test-producers` → exit 0. New totals: `EXTRACTOR_CONFIG_TEST PASS
  checks=35`, `EXTRACT_RECIPE_TEST PASS checks=12`, `PARSE_CUBEMAP_TEST PASS
  checks=21`, `PARSE_CONTRACTS_TEST PASS checks=9`.
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
