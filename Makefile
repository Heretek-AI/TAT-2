DOTNET := $(HOME)/.dotnet10/dotnet
GODOT  := flatpak run org.godotengine.Godot
EX     := tools/tat-extract/bin/Release/net10.0/tat-extract

TEXTURE_CAP ?= 1024
MOBILE_ABI  ?= arm64
QA_CONTRACT ?= 0
KEYSTORE_PROPS := $(HOME)/.config/tat2/keystore.properties

.PHONY: build-extractor extract anims normalize audit test run audio-tools linux-build linux-run android-prepare android-debug android-debug-gl android-release

build-extractor:
	DOTNET_ROOT=$(HOME)/.dotnet10 PATH=$(HOME)/.dotnet10:$(PATH) $(DOTNET) build tools/tat-extract -c Release
	cp tools/tat-extract/native/linux-x64/CUE4Parse-Natives.so tools/tat-extract/bin/Release/net10.0/

extract: build-extractor
	$(EX) list
	$(EX) raw
	$(EX) tables
	$(EX) levels
	$(EX) materials
	$(EX) audio
	$(EX) meshes
	$(EX) textures
	$(EX) anims

anims: build-extractor
	$(EX) anims
	/usr/bin/blender --background --python tools/usd_to_gltf.py -- extracted/anims/usd game/assets/ue/Anims --manifest game/data/generated/anims_manifest.json

normalize:
	python3 tools/parse_tables.py

audio-tools:
	bash tools/fetch_vgmstream.sh

audit:
	python3 tools/manifest_audit.py --min-coverage 0.90

test:
	$(GODOT) --headless --path game --script res://tests/run_tests.gd

run:
	$(GODOT) --path game

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
