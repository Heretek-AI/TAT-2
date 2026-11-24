DOTNET := $(HOME)/.dotnet10/dotnet
# Prefer the native 4.7.2 binary; tools/godot falls back to Flatpak.
GODOT  ?= tools/godot
EX     := tools/tat-extract/bin/Release/net10.0/tat-extract

TEXTURE_CAP ?= 1024
MOBILE_ABI  ?= arm64
QA_CONTRACT ?= 0
KEYSTORE_PROPS := $(HOME)/.config/tat2/keystore.properties

.PHONY: build-extractor extract anims normalize audit audit-bootstrap audit-refresh-stamps audit-imports test run desktop-texture-cap texture-cap-check audio-tools linux-build linux-run android-prepare android-debug android-debug-gl android-release

build-extractor:
	DOTNET_ROOT=$(HOME)/.dotnet10 PATH=$(HOME)/.dotnet10:$(PATH) $(DOTNET) build tools/tat-extract -c Release
	cp tools/tat-extract/native/linux-x64/CUE4Parse-Natives.so tools/tat-extract/bin/Release/net10.0/

extract: build-extractor
	$(EX) list
	$(EX) raw
	$(EX) tables
	$(EX) levels
	# meshes writes *.materials.json sidecars; materials consumes them to queue
	# authored materials whose names don't start MI_/M_ (CobwebFogy, T_*).
	# --overwrite keeps a changed material filter effective on an existing tree.
	$(EX) meshes
	$(EX) materials --overwrite
	$(EX) audio
	$(EX) textures
	$(EX) anims

anims: build-extractor
	$(EX) anims
	/usr/bin/blender --background --python tools/usd_to_gltf.py -- extracted/anims/usd game/assets/ue/Anims --manifest game/data/generated/anims_manifest.json

# Every generated-data producer. `normalize` fails if any is missing or errors,
# so a silently dropped parser cannot pass the gate. parse_anim_meta consumes
# the raw AnimSequence/AnimMontage dumps written by `make extract`/`make anims`;
# it runs last so a failed earlier producer cannot leave stale metadata.
NORMALIZERS := parse_tables parse_materials parse_gameplay parse_contracts \
               parse_clues parse_quests parse_devices parse_containers \
               parse_interactables parse_loot parse_spawners parse_vfx \
               parse_weather extract_audio convert_wwise parse_locres \
               convert_videos parse_anim_meta

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
audit: texture-cap-check
	python3 tools/manifest_audit.py --min-coverage 0.99 --min-exact-coverage 0.99

# Explicit first run: writes tools/audit_baseline.json after every gate passes.
audit-bootstrap:
	python3 tools/manifest_audit.py --min-coverage 0.99 --min-exact-coverage 0.99 --bootstrap-stamps

# Escape hatch after intentionally changing a producer and regenerating its
# outputs (make normalize / make anims). Missing/decreased outputs still fail.
audit-refresh-stamps:
	python3 tools/manifest_audit.py --min-coverage 0.99 --min-exact-coverage 0.99 --refresh-stamps

# Separate Godot import gate; extraction-only trees do not need it.
audit-imports:
	python3 tools/manifest_audit.py --min-coverage 0.99 --min-exact-coverage 0.99 --require-imports

test:
	$(GODOT) --headless --path game --script res://tests/run_tests.gd

run:
	$(GODOT) --path game

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
linux-build:
	$(GODOT) --headless --path game --export-release "Linux" $(CURDIR)/build/tat2-linux-x86_64

linux-run:
	$(CURDIR)/build/tat2-linux-x86_64

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
