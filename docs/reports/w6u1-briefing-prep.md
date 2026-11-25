# W6U1 — authored briefing, 1200 s endgame override, prep stage and Den poster light

Branch: `w6u1-briefing-prep` (worker worktree `/tmp/opencode/tat2-w6u1-brief`,
base `f803c3b`).

Commit: `feat(ui): authored briefing, 1200s override, prep stage and Den poster light`.

## 1. Briefing letter (KF13)

### Producer — `tools/parse_quests.py`

The shipped letters live in `extracted/json/StringTables/ST_Missions_*.json`,
not in the mission tables. The producer now reads every
`StringTables/ST_Missions_*.json` and emits a top-level `mission_briefings`
object keyed by mission id, plus `briefing_key` / `briefing_present` on each
`missions` row:

```json
"Mission.Guildhall.LootTheRoom": {
  "key": "Guildhall.LootTheRoom.Briefing",
  "text": "Esteemed Colleague - \r\n…",
  "table": "ST_Missions_Guildhall_LootTheRoom",
  "namespace": "minute",
  "placeholders": ["EndgameDurationInMinutes", "MatchDurationInMinutes"],
  "unknown_placeholders": [],
  "fact_key": "Guildhall.LootTheRoom.Fact",
  "fact": "Steal whatever you can find.",
  "source_file": "extracted/json/StringTables/ST_Missions_Guildhall_LootTheRoom.json"
}
```

Three authored letters are emitted: `Mission.Guildhall.LootTheRoom`,
`Mission.Guildhall.Set`, `Mission.Guildhall.VaultHeist`. The last one comes
from `ST_Missions_Guildhall_Procurment` (the asset's spelling); an explicit
alias maps that prefix to the `CDT_Missions` row. A new fail-closed validation
check `briefing_placeholders_known` rejects any `{Token}` the runtime cannot
substitute (3/3 checked, 0 failures).

### Tracked expansion override — `game/data/expansion/briefing_overrides.json`

The extracted `QG_Guildhall_LootTheRoom` `EndgameDuration` property node authors
**480 s**, but the shipped letter (KF13) promises a **20-minute** magic door and
mission prep shows the matching 55-minute window. The override records the
player-facing rule without touching the authored plan:

```json
"Mission.Guildhall.LootTheRoom": {
  "endgame_seconds": 1200,
  "source": "KF13",
  "evidence": "docs/reference/clip_1795033698901/clean/KF13_01m10s_briefing_letter.jpg",
  "authored_qg_endgame_seconds": 480,
  "table": "ST_Missions_Guildhall_LootTheRoom",
  "key": "Guildhall.LootTheRoom.Briefing"
}
```

### Runtime — `game/src/core/game_data.gd`

- `get_mission_briefing_record(id)` — raw authored letter (placeholders intact).
- `get_mission_endgame_seconds(id)` — override first (1200), else the plan's
  authored `endgame_duration` (480). `get_mission_endgame_source(id)` returns
  `KF13` for the override, `""` for a quest-graph value.
- `format_mission_briefing(raw, match_seconds, endgame_seconds)` — normalises
  CRLF and substitutes `{MatchDurationInMinutes}` / `{EndgameDurationInMinutes}`
  from **seconds**. No UI code types 20.
- `get_mission_briefing_text(id, …)` — convenience with mission-row defaults.

`GameData.get_mission_plan()` is untouched: suite 65 still sees
`endgame_duration == 480`, so the QG value is preserved for parity while the
runtime briefing/endgame rule is 1200 s.

### Binding — `game/src/missions/mission_controller.gd`

`_trigger_mission_start_letter()` now prefers the authored ST_Missions letter
for a free-play mission. It logs the provenance:

```text
TAT-2 briefing: mission=Mission.Guildhall.LootTheRoom table=ST_Missions_Guildhall_LootTheRoom
key=Guildhall.LootTheRoom.Briefing match_s=3300 endgame_s=1200 endgame_source=KF13 lines=11
```

The contract path is unchanged (contract intro text, placeholder fallback).

### HUD — `game/src/ui/hud.gd` (KF13)

Reference measurements (`docs/reference/clip_1795033698901/clean/KF13_01m10s_briefing_letter.jpg`,
1920x1080): paper bbox `548..1372 x 202..868` (824x666), right scrollbar at
x 1335, 11-line typewriter letter, `[SPACE] CONTINUE`.

At the 1280x720 design resolution that is a `549x444` sheet (exactly 824x666 at
1920x1080). The sheet uses the authored `T_Paper01.png`, cropped to its paper
content (`107,69 813x882`) so the transparent canvas margin does not distort the
panel. A 13-tap screen-texture blur (`hint_screen_texture`) replaces the old flat
dim; the gameplay HUD siblings are hidden while the letter is open and restored
exactly on continue. The right inner-margin scrollbar is a 3 px cream thumb over
a 5 px track at x 524 (reference 1335/1920 scaled). Text is 19 px SpecialElite in
a 412 px column — TextServer reproduces the **authored 11-line KF13 wrap word
for word** (not a hand-wrapped copy). The authored crease shadows are lifted
26 % toward the paper tone while the torn-edge alpha is preserved.

## 2. Prep stage

Baseline capture (HEAD) `prep_before.png`: from the previous mirrored authored
slot the frame was the authored `SM_Storefront_Facade_1200` (x −33.5, 36 m behind
the thief) end to end; the KF11 full moon was fully occluded.

Changes in `game/src/ui/mission_prep_ui.gd`:

- **Reframe**: stage camera moved to the authored rooftop's NE corner
  `(4.0, 1.0, 10.0)` looking at the thief + 1.2 m (measured direction
  `(-0.4583, 0.0837, -0.8848)`). The slate ridge cap now reads along the bottom,
  the thief is full-body right of the info stack, and the measured sky gap is at
  the upper right. **FOV stays the authored 20.0 with `KEEP_WIDTH`**; the preset
  stays `midnight_clear_mission_lobby` (not Guildhall `gloomy`).
- **Moon disc decoupled from the key light**: the sky disc uses
  `MOON_DISC_SCREEN (0.88, 0.12)` while the DirectionalLight key uses
  `KEY_SCREEN (0.30, 0.28)`. Previously one screen direction drove both, so
  moving the moon also moved the character light. Test W6U1.29 pins the two
  directions apart (dot −0.98).
- **Local character rig**: `MissionLobbyKey` (cool spot, 1.8, camera side),
  `MissionLobbyFill` (warm omni, 0.32), `MissionLobbyRim` (cool back spot, 1.4).
  The key aims at the thief's chest (dot > 0.9).
- **Sky regrade**: `background_energy_multiplier` 3.0 → 0.18. The pre-W6U1 3.0
  blew the authored midnight sky to daylight blue; surfaces keep their own
  exposure/ambient (unchanged) and the disc still reads at energy 2.4.

Residual (documented, not hidden): the authored Periphery facade still fills the
left/middle behind the thief; KF11's distant Kilcairn skyline is not reproduced
by the two loaded lobby sublevels. The stage sky-left vertical band is an
authored `VFX_SkySearchLight_Mesh`; the **searchlight meshes remain
`WorldGridMaterial`** here — the scoped additive material is W6L's separate
commit (`level_loader.gd` is not touched by W6U1).

## 3. Thieves' Den poster wall

`_setup_thieves_den_hub()`:

- `DenWindowBacklight` changed from a shadowless cool `OmniLight3D` 0.6 m
  outboard to a shadowless cool **`SpotLight3D` 1.1 m outboard, aimed into the
  room** (`room_facing`/`outboard` metadata). It still lights the frosted panes
  and now the room-facing reveal instead of a symmetric omni glow.
- Added `DenPosterFill`: warm `(1.0, 0.80, 0.56)` omni, energy **0.10**, range
  2.6 m, attenuation 2.0, placed 0.52 m inboard of the authored
  `SM_PosterWantedA..E` wall centroid `(-5.7777, 41.58, 269.0)`.
- Group accounting: the fill joins `den_hand_fills`. Total **1.90 → 2.00**,
  still ≤ 2.01 (suite 34b). Global exposure/glow untouched.

Capture `den_poster_after.png` shows all five authored Wanted posters legible
(at a wider survey camera than KF06); poster-wall ROI mean 0.201, max 0.909.

## 4. Evidence

Captures (native Vulkan, one Godot at a time, Xvfb 1920x1080, sidecar `.txt`
next to each PNG), in `/tmp/opencode/w6u1-captures/`:

| file | content | sidecar |
|---|---|---|
| `prep_before.png` | HEAD prep stage (baseline) | – |
| `prep_after.png` | W6U1 prep stage: moon upper-right, ridge at bottom, key/fill/rim | yes |
| `briefing_after.png` | KF13 letter over the live Guildhall safe room, HUD hidden | yes |
| `den_poster_after.png` | Den Wanted-poster wall with the 0.10 fill + spot backlight | yes |

Measured on the real captures (ImageMagick luminance):

| metric | before | after | reference |
|---|---|---|---|
| prep moon ROI mean / max (x .80–.99, y .02–.30) | 0.167 / 0.303 | **0.249 / 0.493** | KF11 moon present upper-right |
| prep thief ROI mean / SD (x .42–.62, y .30–.95) | 0.222 / 0.098 | 0.166 / **0.139** | darker sky, higher character contrast |
| prep full frame mean | 0.167 | 0.163 | no global exposure lift |
| briefing paper ROI mean / SD | – | 0.692 / 0.209 | KF13 0.544 / 0.309 (brighter, flatter folds) |
| Den poster ROI mean / max | – | 0.201 / 0.909 | KF06 posters legible |

The paper panel is exactly KF13's 824x666 at 1920x1080; the text is the
verbatim 11-line authored wrap. Residual: the authored `T_Paper01` vertical
crease shadows still cross some glyphs (reference folds are horizontal), and the
live safe-room blur is darker than KF13's brick backdrop.

## 5. Gates

| gate | result |
|---|---|
| `tools/godot … check_scripts_compile.gd` | **102 checked, 0 broken** |
| `res://tests/test_w6u1_briefing.gd` | **W6U1_SUMMARY: fails=0** (37 checks) |
| `make test` (`tests/run_tests.gd`) | **SUMMARY: fails=0** (261 PASS; suite 60 PASS) |
| `res://tests/test_m2_player.gd` | **M2_SUMMARY: fails=0** |
| `make audit` | exit 2 (6 failures); 2 are this wave's intentional quests output + producer hash, see §6 |

Focused test coverage (`game/tests/test_w6u1_briefing.gd`):

- W6U1.2–.9 override exists (1200 s, source KF13, QG 480 recorded); runtime
  accessor 1200; QG plan still 480; mission row 3300 s.
- W6U1.10–.16 authored letter emitted, raw text byte-identical to the extracted
  string table, both placeholders kept, formatted text has no `{`, states
  "55 minute window" / "20 minutes", and is seconds-derived.
- W6U1.17–.24 11-line KF13 wrap word for word; paper crop 813x882; right
  scrollbar; screen-texture blur; gameplay HUD hidden then restored;
  `[SPACE] CONTINUE`.
- W6U1.25–.32 prep FOV 20/KEEP_WIDTH, key/fill/rim, key aim, disc/key decoupled
  (dot −0.98), disc at (0.880, 0.120), sky multiplier 0.18, preset unchanged.
- W6U1.33–.37 `DenPosterFill` ≤ 0.10 at the poster wall in `den_hand_fills`;
  `DenWindowBacklight` is an outboard room-facing spot; fill total 2.00 ≤ 2.01.

## 6. Producer / audit changes

- `tools/parse_quests.py`: new `StringTables/ST_Missions_*.json` source,
  `load_mission_briefings()`, `BRIEFING_MISSION_ALIASES`,
  `validate_briefings()`; `mission_briefings=3` in `stats`; sources list gains
  `mission_strings`.
- Regenerated `game/data/generated/gameplay/quests.json` (git-ignored):
  421,806 → larger by the briefing text (~+1.5 KB) and the new validation check.
- `tools/audit_baseline.json` records the producer output sha256/bytes, so a
  normal `make audit` fails on the re-generated file until the baseline is
  re-stamped. This worker does not re-stamp the shared baseline in its commit;
  the integrating wave must run `make audit-bootstrap` (escape hatch for an
  intentional producer change) after merging.

Worker `make audit` result (exit 2, 6 failures):

```text
FAIL: baseline: producer tools/parse_tables.py output gen:gameplay content differs from the baseline
FAIL: baseline: producer tools/parse_gameplay.py output gen:gameplay content differs from the baseline
FAIL: baseline: producer tools/parse_quests.py changed since the baseline (sha256 0fb6e82efc9e -> b86003730f21)
FAIL: baseline: producer tools/parse_quests.py output gen:gameplay/quests.json content differs from the baseline
FAIL: baseline: producer tools/parse_unlocks.py output gen:gameplay/unlocks.json content differs from the baseline
FAIL: tool version drift: vgmstream: 'vgmstream CLI decoder r2168 (Oct 25 2026)' -> 'missing'
```

Only the two `parse_quests.py` lines are W6U1. The `parse_tables` / `parse_gameplay`
/ `parse_unlocks` diffs come from the worktree's copied `game/data/generated`
snapshot (the main checkout's generated tree carries other waves' uncommitted
outputs), and `vgmstream` is missing from this container. Content checks
(levels 107, contracts 16, tables 144, materials 1629, devices 4118, animations
995, audio 5018, localization 8, niagara 3695, disk-backed coverage 12657/12703
= 99.6 %) all pass.

## 7. Open residuals

- Prep stage: the authored Periphery facade still hides the KF11 city skyline;
  the visible moon depends on the W6U1 reframe. Searchlight meshes are still
  WorldGrid → **W6L dependency** (scoped additive material, separate commit).
- Briefing: `T_Paper01` vertical creases cross glyphs; the safe-room blur is
  darker than KF13's brick/grate backdrop.
- The 20-minute endgame is a briefing/plan value (`get_mission_endgame_seconds`);
  the run's escape phase still uses the authored quest-graph timers elsewhere.
  Wiring the 1200 s override into the escape-door countdown itself is out of
  W6U1's file ownership (mission flow is unchanged apart from the letter).
