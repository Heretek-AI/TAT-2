DOTNET := $(HOME)/.dotnet10/dotnet
# Prefer the native 4.7.2 binary; tools/godot falls back to Flatpak.
GODOT  ?= tools/godot
EX     := tools/tat-extract/bin/Release/net10.0/tat-extract

TEXTURE_CAP ?= 1024
MOBILE_ABI  ?= arm64
QA_CONTRACT ?= 0
KEYSTORE_PROPS := $(HOME)/.config/tat2/keystore.properties

# Mapping file for unversioned packages. `tools/ue4ss/output` is gitignored and
# a git worktree usually does not have it, so fall back to the main checkout
# derived from the shared git dir. An explicit `USMAP=` / `TAT_USMAP=` wins.
GIT_COMMON := $(shell git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
MAIN_CHECKOUT := $(if $(GIT_COMMON),$(abspath $(GIT_COMMON)/..),)
USMAP ?= $(TAT_USMAP)
ifeq ($(USMAP),)
USMAP := $(firstword $(wildcard tools/ue4ss/output/*.usmap) $(wildcard $(MAIN_CHECKOUT)/tools/ue4ss/output/*.usmap))
endif

.PHONY: build-extractor extract json extract-json anims normalize audit audit-bootstrap audit-refresh-stamps audit-imports content-overrides check-logic check-consumers string-audit check-greps gate-ratchet test test-producers run editor review review-capture bake-review bake-review-core desktop-texture-cap texture-cap-check audio-tools linux-build linux-stamp-verify linux-run android-prepare android-debug android-debug-gl android-release

build-extractor:
	DOTNET_ROOT=$(HOME)/.dotnet10 PATH=$(HOME)/.dotnet10:$(PATH) $(DOTNET) build tools/tat-extract -c Release
	cp tools/tat-extract/native/linux-x64/CUE4Parse-Natives.so tools/tat-extract/bin/Release/net10.0/

# P3-3B.4 / round-2 F3: standalone filtered package dump for Destructibles.
# This is NOT part of `extract`: the new `TAT/Content/Destructibles/` tables
# root already dumps GC_ChestTrunkALid and friends in the `tables` stage.
# `--usmap` is resolved above (env USMAP/TAT_USMAP, the worktree's
# tools/ue4ss/output, or the main checkout's copy) and `--fail-on-error` makes
# a package that fails to map exit non-zero instead of a silent ok=0/fail=N.
json: build-extractor
	@if [ ! -f "$(USMAP)" ]; then \
		echo "ERROR: no .usmap found at '$(USMAP)'; set USMAP=/path/to/TAT-*.usmap (worktrees lack tools/ue4ss/output)" >&2; \
		exit 2; \
	fi
	$(EX) json --overwrite --usmap '$(USMAP)' --fail-on-error --filter 'Destructibles/'

extract-json: json

extract: build-extractor
	$(EX) list
	$(EX) raw
	$(EX) tables
	$(EX) levels
	# N-P0: decoded ARecastNavMesh tiles for the three navmesh maps only. The
	# generated runtime asset is produced by tools/parse_nav.py in `normalize`.
	# `$$` before the closing quote keeps that quote out of make's variable
	# expansion (a single dollar plus quote is a one-character variable
	# reference and leaves the shell with an unmatched quote).
	$(EX) nav --overwrite --filter 'Maps/(Guildhall|OldManor|FTUE)/.*\.umap$$'
	# meshes writes *.materials.json sidecars; materials consumes them to queue
	# authored materials whose names don't start MI_/M_ (CobwebFogy, T_*).
	# --overwrite keeps a changed material filter effective on an existing tree.
	$(EX) meshes
	$(EX) materials --overwrite
	$(EX) audio
	$(EX) textures
	# 3A.4: faces are HDR for HDR cubes; --overwrite re-encodes an existing
	# PNG tree so a stale 8-bit face cannot survive a code change.
	$(EX) cubemaps --overwrite
	$(EX) anims

anims: build-extractor
	$(EX) anims
	/usr/bin/blender --background --python tools/usd_to_gltf.py -- extracted/anims/usd game/assets/ue/Anims --manifest game/data/generated/anims_manifest.json

# Every generated-data producer. `normalize` fails if any is missing or errors,
# so a silently dropped parser cannot pass the gate. parse_anim_meta consumes
# the raw AnimSequence/AnimMontage dumps written by `make extract`/`make anims`;
# it runs last so a failed earlier producer cannot leave stale metadata.
NORMALIZERS := parse_tables parse_curves parse_materials parse_gameplay \
               parse_contracts parse_settings parse_clues parse_quests \
               parse_devices parse_containers parse_interactables parse_loot \
               parse_spawners parse_vfx parse_unlocks parse_hearing \
               parse_state_tree parse_weather parse_cubemap parse_project_ini parse_input \
               parse_nav parse_collision parse_wwise extract_audio convert_wwise \
               parse_audio_control parse_locres convert_videos parse_anim_meta \
               parse_stealthball_array

normalize:
	@for t in $(NORMALIZERS); do \
		if [ ! -f tools/$$t.py ]; then echo "ERROR: missing tools/$$t.py" >&2; exit 1; fi; \
		echo "== $$t"; \
		python3 tools/$$t.py || exit 1; \
	done

audio-tools:
	bash tools/fetch_vgmstream.sh

# The texture cap is derived from the extracted `.import` sidecars, so a stale
# cap must fail the content gate (see the check target below).
# check-logic validates the W5E payloads (unlocks/hearing/perception/StateTrees)
# with expectations kept outside the producers; check-consumers fails when a
# generated file has no game/src reader and no allowlisted reason; string-audit
# and check-greps are the W10-A fail-closed UI-string and literal-formula gates.
audit: content-overrides texture-cap-check check-logic check-consumers string-audit check-greps
	python3 tools/manifest_audit.py --min-coverage 0.99 --min-exact-coverage 0.99

# Fail-closed validator for the logic-data payloads (was wired to no target).
check-logic:
	python3 tools/check_logic_data.py

# Every normalised output needs a reader or an allowlisted reason.
check-consumers:
	python3 tools/check_consumers.py

# W10-A: the UI string audit becomes a gate. Floors are the measured W10-A
# baseline (306 visible rows routed, 195 with an authored counterpart, 111
# invented); raise them, never lower them. P5-UI raises only the invented
# ceiling to 112: the contract list's standalone hub map label "Thieves' Den"
# has no authored map-name row (authored rows only carry "Quit to Thieves Den" /
# "Return to Thief's Den" / "Learn About the Thieves' Den"), and it is the
# correct reference copy. Documented at contract_table_ui.gd:362.
string-audit:
	python3 build/qa/w9/p3_string_audit.py --min-routed 306 --min-authored 195 --max-invented 112

# W10-A: no live port-invented formula in code and no invented post-match
# rating label in a UI string literal (comments documenting the removals are
# legal; a live occurrence is not).
check-greps:
	python3 tools/check_literal_greps.py

# Boot a real free-play mission headless and fail on any SCRIPT/SHADER ERROR.
# The unit suites and E2E cannot see this class: the 2026-11-25 footstep
# occlusion bug threw on every step while E2E still reported 278/278.
runtime-smoke:
	build/qa/runtime_smoke.sh 90

# W6T graybox P0/3rd-floor gate: validates the tracked override table against
# the applied .tatlevel.json output (counts, overlap, coverage regions,
# graybox-only, authored materials). `--table-only` needs no private data.
content-overrides:
	python3 tools/check_content_overrides.py

# Non-Sonar GDScript ratchet: the hosted part validates the tracked baseline,
# the content table and Python sources. The Godot gates themselves need the
# private extract and run locally (see docs/reports/w6t-graybox-sonar.md).
gate-ratchet:
	python3 -m py_compile tools/*.py
	python3 tools/check_content_overrides.py --table-only
	python3 tools/check_gate_ratchet.py

# Explicit first run: writes tools/audit_baseline.json after every gate passes.
audit-bootstrap:
	python3 tools/manifest_audit.py --min-coverage 0.99 --min-exact-coverage 0.99 --bootstrap-stamps

# Escape hatch after intentionally changing a producer and regenerating its
# outputs (make normalize / make anims). Missing/decreased outputs still fail,
# and REASON is mandatory: the baseline records why the drift was accepted.
audit-refresh-stamps:
	@if [ -z "$(REASON)" ]; then \
		echo "ERROR: audit-refresh-stamps needs REASON='why this drift is accepted'" >&2; \
		echo "  e.g. make audit-refresh-stamps REASON='parse_curves added; regenerated after make normalize'" >&2; \
		exit 1; \
	fi
	python3 tools/manifest_audit.py --min-coverage 0.99 --min-exact-coverage 0.99 --refresh-stamps --refresh-reason "$(REASON)"

# Producer + audit unit tests (stdlib only, no Godot, no GPU). Every tools/test_*.py
# is run so a new suite is picked up automatically.
test-producers:
	@for t in tools/test_*.py; do echo "== $$t"; python3 "$$t" || exit 1; done

# Separate Godot import gate; extraction-only trees do not need it.
audit-imports:
	python3 tools/manifest_audit.py --min-coverage 0.99 --min-exact-coverage 0.99 --require-imports

test:
	$(GODOT) --headless --path game --script res://tests/run_tests.gd

run:
	$(GODOT) --path game

# --- World review (editor-openable baked scenes + in-game free camera) ------
MAP ?= guildhall
OUT ?= res://scenes/review/$(MAP)

# Bake one binary scene per sublevel through the real LevelLoader and write
# world.scn + review.tscn + review_manifest.json. Output is gitignored.
bake-review:
	$(GODOT) --headless --path game --script $(CURDIR)/tools/bake_review_map.gd -- --map=$(MAP) --out=$(OUT)

# Core-min single-call bake: POI + 3rd floor + Gameplay + Lighting in one
# load_sublevels_async() call with a 160-light budget. Writes <map>_core.scn +
# review_core.tscn + review_manifest.json under res://scenes/review/<map>_core.
# This is the scene a low-memory desktop can open; the full assembly is not.
bake-review-core:
	$(GODOT) --headless --path game --script $(CURDIR)/tools/bake_review_map.gd -- --map=$(MAP) --mode=single --sublevels=core --out=res://scenes/review/$(MAP)_core

# In-game free-camera review of the same static world (no mission/player).
review:
	$(GODOT) --path game res://scenes/review_mode.tscn -- --map=$(MAP)

# Offscreen six-bookmark capture sweep (writes build/qa/review/<map>/*.png).
review-capture:
	$(GODOT) --path game --resolution 1280x720 res://scenes/review_mode.tscn -- --map=$(MAP) --capture-dir=$(CURDIR)/build/qa/review/$(MAP) --capture-quit

# Editor with the TAT-2 Review dock (Project > Plugins if it is not visible).
editor:
	$(GODOT) --editor --path game

# Desktop texture pre-bake: writes the 1024 px long-edge cap + mipmaps into the
# loader-managed PNG .import sidecars, deletes their .ctex/.md5 dest files, then
# reimports. Preview with `python3 tools/prebake_texture_cap.py --dry-run`.
# Required again after any clean extraction (which wipes extracted/).
desktop-texture-cap:
	python3 tools/prebake_texture_cap.py --cap 1024
	tools/reimport_assets.sh

# Read-only cap gate (part of `make audit`): fails when an over-cap loader
# texture lacks process/size_limit<=1024 + mipmaps, with the fix command.
# The alpha-critical storefront decal is exempt by design.
texture-cap-check:
	python3 tools/prebake_texture_cap.py --check --cap 1024

# --- Linux x86_64 export (Tier-1 gate) ----------------------------------------
# Requires the 4.7.2 Linux export templates (linux_debug.x86_64 /
# linux_release.x86_64) in the flatpak template dir; see game/export_presets.cfg.
# Output lands under gitignored build/.
#
# W7G provenance: after a successful export, write build/tat2-linux-x86_64
# .stamp.json with HEAD (short + full), the UTC build time, the Godot version,
# a tracked-tree dirty flag and the SHA-256 + size of the binary and PCK. The
# perf wrapper refuses to measure an export whose stamp is missing, stale or
# does not match the artifacts, and marks a dirty build non-publishable.
LINUX_OUT ?= $(CURDIR)/build/tat2-linux-x86_64
linux-build:
	@mkdir -p $(CURDIR)/build
	$(GODOT) --headless --path game --export-release "Linux" $(LINUX_OUT)
	bash $(CURDIR)/build/qa/export_stamp.sh write --root $(CURDIR) --binary $(LINUX_OUT) --preset Linux

# Re-check the stamp without exporting (exit 0 ok, 3 stale, 4 mismatch, 5 missing).
linux-stamp-verify:
	bash $(CURDIR)/build/qa/export_stamp.sh verify --root $(CURDIR) --binary $(LINUX_OUT)

linux-run:
	$(LINUX_OUT)

# --- Android (internal sideload build) --------------------------------------
# Generates build/mobile_game/ (gitignored) with ETC2 textures, Mobile renderer
# and landscape orientation, then exports a signed APK.
android-prepare:
	python3 tools/prepare_mobile_project.py --texture-cap $(TEXTURE_CAP) --abi $(MOBILE_ABI) --autostart-contract $(QA_CONTRACT) --renderer mobile

android-debug:
	$(MAKE) android-prepare MOBILE_ABI=both
	$(GODOT) --headless --path build/mobile_game --export-debug "Android" $(CURDIR)/build/tat2-mobile-debug.apk

# Emulator-only build: the Android emulator cannot present Vulkan surfaces, so
# QA builds for it use the Compatibility (GLES) renderer.
android-debug-gl:
	python3 tools/prepare_mobile_project.py --texture-cap $(TEXTURE_CAP) --abi both --autostart-contract $(QA_CONTRACT) --renderer gl_compatibility
	$(GODOT) --headless --path build/mobile_game --export-debug "Android" $(CURDIR)/build/tat2-mobile-gl-debug.apk

android-release:
	$(MAKE) android-prepare
	. $(KEYSTORE_PROPS) && \
	GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$$storeFile" \
	GODOT_ANDROID_KEYSTORE_RELEASE_USER="$$keyAlias" \
	GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$$storePassword" \
	$(GODOT) --headless --path build/mobile_game --export-release "Android" $(CURDIR)/build/tat2-mobile-release.apk
