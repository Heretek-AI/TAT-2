# TAT-2 — *Thick As Thieves* Rebuilt in Godot 4.7

> **Private-Use Notice:** Extracted assets from `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/` are placed in `extracted/` and `game/assets/ue/`, both git-ignored. Only original code, tools, and expansion content are committed.

## What's Included
- **Extraction Pipeline (`tools/tat-extract`)**: .NET 10 + `CUE4Parse` + native Linux Oodle + UE 5.5.4 `.usmap` support (`99.4%` manifest coverage: 12,630 / 12,704 entries).
- **Normalized Data (`tools/parse_tables.py`)**: All 16 original Contracts + string tables (`ST_Contract2`–`16`), shipped `CT_*` CurveTables, 102 level/sublevel actor layouts, and 64 fonts.
- **Godot 4.7 Game (`game/`)**:
  - **Three Thieves**: **The Spider** (Grapple Wire), **The Chameleon** (Disguise Integrity), **The Moth [TAT-2 Expansion]** (Astral Scout).
  - **Gadgets**: Slithersap (short-circuits lights), Smoke Bomb (blocks AI LOS), Pickpocket Fairy (remote snatch), Blackjack takedown, Thief Vision, Lean L/R.
  - **18 Contracts** across **Old Manor**, **Guildhall**, and **Jaspering Hall (TAT-2 Expansion)**, with **Novice / Thief / Master Thief** difficulty scaling and **2-Player ENet Co-op**.

## Commands
```bash
make test    # Run headless Godot 4.7.2 verification suite
make run     # Launch Thick As Thieves 2
make audit   # Verify Steam manifest coverage
```
