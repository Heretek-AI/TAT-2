# Wave 0 preflight - Wave 3 live-GPU verification route map

Read-only surface map, captured 2026-11-19. No captures were run.

## 1. `build/qa/capture_e2e_parity.sh` flags

- Only CLI flag handled: `--strict` (`build/qa/capture_e2e_parity.sh:10-15`). Default `STRICT=0` (`:10`).
- Behavior of `--strict`: with 1, a nonzero `PARITY_FAILS` count exits 1 with `STRICT_GATE_FAILED` (`:87-90`); without it, parity image failures do not fail the script.
- Always-on gate (regardless of flags): fails when the Godot exit status is nonzero, when the log contains `SHADER ERROR` or `SCRIPT ERROR`, or when any of the 21 expected PNGs is missing/empty (`:40-41`, `:43-73`, `:83-85`).
- Fixed runtime parameters, not flags: Xvfb `:99` at `1280x720x24` (`:23`), Godot under flatpak with `--rendering-driver vulkan` (`:35-37`), output dir `build/qa/e2e_parity/` (`:6`).
- Exit contract: prints `EXIT=... SHADER_ERRORS=... SCRIPT_ERRORS=... MISSING_OR_EMPTY=...` (`:80`) and `PARITY_SUMMARY: shots=21 parity_passes=... parity_fails=...` (`:77`, `:81`).

## 2. Export preset name

- `game/export_presets.cfg:3` -> `name="Linux"` (preset `[preset.0]`, `platform="Linux"`, export path `../build/tat2-linux-x86_64` at `:10`).
- Templates referenced: `4.7.2.stable/linux_debug.x86_64` / `linux_release.x86_64` (`game/export_presets.cfg:18-19`).

## 3. Makefile `linux-build` target

- Listed in `.PHONY` at `Makefile:10`.
- Recipe at `Makefile:50-51`:
  - `50: linux-build:`
  - `51: \t$(GODOT) --headless --path game --export-release "Linux" $(CURDIR)/build/tat2-linux-x86_64`
- Companion `linux-run` at `Makefile:53-54` executes `$(CURDIR)/build/tat2-linux-x86_64`.
- Preceding comment `Makefile:46-49` states the target is the Tier-1 gate and needs the 4.7.2 Linux templates; output lands in gitignored `build/`.

## 4. `COMPARISON_TEMPLATE.md` row count = 120

- File: `docs/reference/clip_1795033698901/COMPARISON_TEMPLATE.md` (263 lines).
- Section 2 heading at `:30`; checklist spans `:30-173`.
- Data-row count by ID prefix: V = 37 (`grep -c '^| V[0-9]'`), AU = 31, UI = 27, G = 25 -> **37 + 31 + 27 + 25 = 120**.
- Pipe-row total for section 2 is 128 = 120 data rows + 8 table header/separator rows (4 subsections x 2).
- The template's own header states 120 rows (`:4-6`) and its tally row reads `| **Checklist rows** | 37 | 31 | 27 | 25 | 120 |` at `:263`.

## 5. `build/tat2-linux-x86_64` existence

- Exists: `ls -la build/tat2-linux-x86_64` -> `-rwxr-xr-x 73519416 Nov 19 13:58 build/tat2-linux-x86_64`.
- `file`: ELF 64-bit LSB executable, x86-64, dynamically linked, interpreter `/lib64/ld-linux-x86-64.so.2`, for GNU/Linux 5.15.0, stripped.
- Sidecar `build/tat2-linux-x86_64.pck` present (2,886,810,288 bytes, Nov 19 14:00).
- Gitignored by `.gitignore:18` (`build/`); `git status --porcelain` reports nothing for it.

## Wave 3 route notes

- Capture entry point: `bash build/qa/capture_e2e_parity.sh` (add `--strict` to make parity image FAILs gating). It starts its own Xvfb; do not pre-start one.
- Build/refresh command if the binary is stale: `make linux-build` (export-release preset `"Linux"`).
- Verification readout to quote in Wave 3 evidence: the `EXIT=` line and `PARITY_SUMMARY:` line, plus the 21 PNGs in `build/qa/e2e_parity/`.
