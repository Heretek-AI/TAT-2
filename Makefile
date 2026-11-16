DOTNET := $(HOME)/.dotnet10/dotnet
GODOT  := flatpak run org.godotengine.Godot
EX     := tools/tat-extract/bin/Release/net10.0/tat-extract

.PHONY: build-extractor extract normalize audit test run

build-extractor:
	DOTNET_ROOT=$(HOME)/.dotnet10 PATH=$(HOME)/.dotnet10:$(PATH) $(DOTNET) build tools/tat-extract -c Release

extract: build-extractor
	$(EX) list
	$(EX) raw
	$(EX) tables
	$(EX) levels
	$(EX) audio
	$(EX) meshes
	$(EX) textures

normalize:
	python3 tools/parse_tables.py

audit:
	python3 tools/manifest_audit.py --min-coverage 0.90

test:
	$(GODOT) --headless --path game --script res://tests/run_tests.gd

run:
	$(GODOT) --path game
