# Port Comparison Scorecard — official `clip_1,795,033,698,901` vs TAT-2 port

Blank scorecard for the comparison session (`docs/REFERENCE_BASELINE.md` §10 workflow). Section 2 is a
1:1 mirror of the `docs/REFERENCE_BASELINE.md` §8 checklist — same rows, same order (120 rows: Visual 37,
Audio 31, HUD/UI 27, Gameplay 25) with the per-row **Port observation** / **Score** columns left blank for
the scorer. Section 3 holds the 27 per-segment image slots (`KEYFRAME_INDEX.md` §2), section 4 the 27
anchor-alignment rows (`REFERENCE_BASELINE.md` §9.4 anchor events), section 5 the summary score tally.

Filling in: score every checklist row against the aligned port recording and the side-by-sides
(`REFERENCE_BASELINE.md` §10 steps 3–4; score audio rows from `ffmpeg astats` / `showspectrumpic`
evidence, not by ear), paste the port images into the section 3 slots, record the section 4 offsets into
`offsets.csv`, then tally section 5. Replace the `<date>` / `<mm_ss>` placeholders with the real port
capture values (`docs/reference/port_<date>/`, `REFERENCE_BASELINE.md` §9.3; `tools/make_side_by_side.sh`
emits the matching `ffmpeg` / `magick +append` / `-hstack` commands). Never edit `clean/*.jpg`.

## 1. Scoring rules (verbatim from `docs/REFERENCE_BASELINE.md` §8)

Scoring rules: fill **Port observation** from the aligned port recording, then set **Score** to exactly one of:

- `PASS` — port matches the official observation (within the tolerance noted in the row).
- `DELTA` — element present in both but visibly/audibly different.
- `MISSING` — element absent or non-functional in the port.
- `HARD_LIMIT` — difference caused by an unrecoverable cooked-data limit (cite the `HL-n`).
- `N/A` — not applicable or not observable on this route.

Port observation and Score are intentionally blank until the port recording exists. The **Notes** column
pre-states the expected port caveat (parity-gap / hard-limit tag with citation) so the scorer knows what
a legitimate delta looks like. `KFnn #k` refers to callout `#k` on keyframe `KFnn` in `CALLOUT_LEGENDS.md`.

## 2. 4-pillar comparison checklist (V1–V7, AU1–AU6, UI1–UI5, G1–G5) — 1:1 mirror of `docs/REFERENCE_BASELINE.md` §8

Subsections keep their §8 numbering for 1:1 diffing; checklist rows are copied verbatim in source order.

### 8.1 Visual (V1–V7)

| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score | Notes |
|---|---|---|---|---|---|---|
| V1-01 | Neon flicker + amber practicals | S01 / KF01 #1 | Magenta cursive `Mac Neish` / `Jeweller` flickers (dim `00:00.10`, full-lit `00:01.00`, left half off `00:02.05`) over warm amber window/awning bars. |  |  | Expect `APPROX_SHADER` (PG-5): authored HDR tint pass retained; core saturation/exposure residual vs UE pale gold. |
| V1-02 | Volumetric moon shaft vs candle pools | S03 / KF02 #1 | Teal-cyan moonlight shaft through arched frosted window casting mullion shadows across dark floorboards; warm candle pool at the desk contrasts. |  |  | `HARD_LIMIT (HL-7)`: Lumen bounce / auto-exposure approximated (SSIL / shadow-toe LUT). |
| V1-03 | Banker's-lamp pool on the map | S08 / KF10 #4 | Warm directional brass banker's-lamp pool across `KILCAIRN` parchment and wooden token vs cool moonlit Den. |  |  | Linear `1/15` intensity scale ported (`docs/reports/lighting-intensity.md`); check warm/cool contrast. |
| V1-04 | Lantern bounce & streetlamp exposure | S12 / KF14 #2; S13 / KF15 #2 | Caged wall lantern casts warm orange bounce on brick after ignite `01:15.1`; teal-cyan bulkhead + green streetlamp pools; gem flares pale gold under streetlamps. |  |  | Direct practicals `1:1_MATCH`; indirect bounce governed by HL-7. |
| V1-05 | Flashing car-headlight glare | S13–S14 / KF16 #3 | Dual vintage-car headlights flash across wet cobbles (`01:36.38+`) with specular streaks raking the gate. |  |  | `APPROX_SHADER` (PG-5): wet-cobble SSR tuning unchecked vs 56 Steam shots. |
| V1-06 | Hearth amber radial pool | S22 / KF25 #1 | Roaring parlor fireplace casts warm amber radial light across herringbone parquet; chandelier points overhead. |  |  | Flame VFX is a stand-in (HL-1); light pool approximation acceptable if warmth/shape read. |
| V1-07 | Crimson alarm spotlight wash | S26 / KF29 #2 | Wall security spotlight bathes slate treads + 1P arms in intense crimson (`03:38.20–03:39.60`); unlit slate stays plain outside the cone. |  |  | `1:1_MATCH` per BREAKDOWN S26 (`level_loader.gd:68-112`); check cone, colour, timing. |
| V2-01 | Night rain streaks + puddle reflections | S01 / KF01 #5; S13 / KF15 #6 | Diagonal rain streaks over rain-slick cobbles; foreground puddle reflects magenta/amber neon. |  |  | Rain is the labelled `WeatherVisuals` stand-in (100–2700 drops, 30 m/s²; HL-1 row). |
| V2-02 | Telescope sky, moon & cheese easter egg | S05 / KF05 #1–#3 | Cloudy teal-blue night sky, faint stars, crater-textured full moon; giant rotating golden cheese wedge with 3 orbiting chunks over rooftops. |  |  | Sky/moon authored (`docs/reports/sky-moon.md`); cheese prop is set dressing (#3/#4). |
| V2-03 | Loading illustration sky | S02; S10 / KF12 #1–#2 | Dark-indigo illustrated skyline, twin dirigibles with yellow searchlight cones, textured pale moon upper-right. |  |  | 2D illustration; check art fidelity and emblem placement (`UI4-05`). |
| V2-04 | Volumetric night-mist depth | S15 / KF17 #2; S20 / KF23 #4 | Clocktower silhouette with red window accents in mist; steel viaduct arch and rooflines receding into fog. |  |  | `HARD_LIMIT (HL-7)`: fog depth / exposure mapping differs. |
| V2-05 | Rain fade-in after digital silence | S10 / KF12 #5 | True digital silence `01:04.94–01:07.78`, then night rain fades in from `01:07.7757` (first non-zero sample). |  |  | Audio fade itself is PG-6 (no ambience bed); visual cut timing is G5-01. |
| V3-01 | Wet-cobble specular | S13 / KF15 #2 | Rain-wet cobbles with puddle speculars under the teal-cyan bulkhead light and streetlamps. |  |  | Puddle normal/opacity + `GroundWet` ported (`tat_landscape.gdshader`); decal graphs HL-2. |
| V3-02 | Emissive faceted diamonds | S07 / KF09 #5–#6 | Emissive green floor diamond + iridescent white-blue table diamond under the candelabra. |  |  | `APPROX_SHADER` (PG-5) emissive tuning; check facet shimmer. |
| V3-03 | Blue door paint, mullions & brass | S21 / KF24 #1 | Blue-painted wood, white/cream diamond-mullion grid over dark glass panes, twin vertical brass pull handles. |  |  | Material slots bound in GLB primitive order (#8); door leaf behaviour PG-4. |
| V3-04 | Purple shopfront orb | S01 / KF01 #2 | Glowing purple egg/orb in the upper Art Nouveau shop display beneath the warm streetlamp. |  |  | CPD emissive path ported (`tat_emissive_cpd.gdshader`). |
| V4-01 | Startscreen street dressing | S01 / KF01 #4–#5 | Stationary idle guard in uniform/helmet/brown belt; vintage car rear fender; wooden crates; Art Nouveau gold scrollwork storefront. |  |  | `1:1_MATCH` geometry (BREAKDOWN S01, `FIDELITY_GAPS.md:38`); trim specular PG-3. |
| V4-02 | Den attic dressing | S03 / KF02 #5–#6 | Candlelit rolltop desk, open armoire, `KILCAIRN` map table, scattered newspapers on floorboards, rafters. |  |  | `1:1_MATCH`; Den live capture blocked by RD cascade (PG-1). |
| V4-03 | Wanted poster wall | S05 / KF06 #5 | Five framed posters verbatim: `WANTED! / CAUTION / HIS HANDS ARE FAST`; `CHARMING MAN? / HE'S A THIEF`; `TELL A CONSTABLE!`; `WANTED £10000`; `REWARD £5000`. |  |  | World text via decals (#8); check all five legible. |
| V4-04 | `BARRON'S DEMOLITION` alley dressing | S13 / KF15 #1, #3 | Weathered brick banner + faint `EST. 1865` + `Out with the old, in with the new!`; crates, fallen steel drums, ladder, alley weeds. |  |  | `1:1_MATCH` geometry; banner full and unclipped at `01:21.38`. |
| V4-05 | Gate arch, griffins & gear plate | S14 / KF16 #1; S17 / KF18 #2, #4 | Wrought-iron `CONSTABLE'S GUILDHALL` arch with crowned star-topped pillars; twin stone griffins on brick pedestals; 10-bolt white gear plate with red downward `⚡` arrow. |  |  | `1:1_MATCH`; check gilded lettering and plate weathering. |
| V4-06 | `MACLEOD` vertical sign | S20 / KF23 #5 | Crisp illuminated vertical gold serif sign on the distant right facade (`02:35.00–02:41.50`, again `02:48.50–02:49.00`). |  |  | `APPROX_SHADER` (PG-5) emissive tint/exposure. |
| V4-07 | Foyer dressing | S24 / KF27 #2; S25 / KF28 #3 | Tall lit glass statue vitrine, velvet armchair + ottoman, flush square metallic floor plate; framed `Basement Stairs` and `WC` plaques. |  |  | `1:1_MATCH`; plaque text legibility check. |
| V5-01 | Idle guard at shopfront | S01 / KF01 #4 | Stationary guard in dark uniform, helmet, brown belt before the `Mac Neish` shopfront. |  |  | Guard mesh + retargeted idle clips (#11/#13); `1:1_MATCH` expected static pose. |
| V5-02 | 3D Spider turntable with cap sync | S04 / KF03 #4; KF04 #4 | Spider with bowler hat, yellow goggles, purple sweater on turntable before open armoire; `Cap` equipped by KF04, `Head` thumbnail synced. |  |  | PBR preview bound (visual-polish wave); wardrobe controls clipping is PG-2. |
| V5-03 | 1P gloved hands + ZipWire viewmodel | S12 / KF14 (vault); S21 / KF24 #4 | 1P gloved arms brace the railing vault (`01:19.6`); ZipWire `[1]` launcher gripped in right hand at the portico. |  |  | `1:1_MATCH` viewmodel (`player-1p.md`); idle/blendspace transitions HL-4. |
| V5-04 | Constable idle + blue hip baton | S22 / KF25 #2–#3 | Standing constable faces the fireplace, hands clasped behind back, glowing blue-tip baton on left hip; unaware of the crouched approach. |  |  | `KNOWN_GAP (PG-7)`: HA montage reuse / simplified idle; check pose + baton glow. |
| V5-05 | Takedown grapple pose | S23 / KF26 #2 | 1P camera lunges/tilts closely over the constable's helmet and corded shoulder; guard knocked onto the parquet; pull-back to eye height. |  |  | `KNOWN_GAP (PG-7)` simplified takedown motion; KO end state 1:1. |
| V6-01 | Escape portal wall outline | S12 / KF14 #1 | Jagged glowing emerald-green + violet chromatic-edge outline shimmering on the safe-room wall (`01:15.2–01:16.2`). |  |  | Emissive outline approximated (#8); shimmer/particle component HL-1. |
| V6-02 | Smoke bomb plume | S18 / KF20 #1 | Orange-white ignition flash (`02:28.20`) then opaque grey-white volumetric puffs expanding horizontally across the grand stairs (`02:28.40–02:29.80`). |  |  | `HARD_LIMIT (HL-1)` + 5×5×4 m / 25 s box stand-in (PG-7). |
| V6-03 | Security beams, emitter & node | S24 / KF27 #1, #3 | Two crisp horizontal white volumetric beams wall-to-wall from the mid-height circular white emitter (`x~17%, y~56%`); glowing cyan ceiling diamond node above the far doors. |  |  | `HARD_LIMIT (HL-1)` beam stand-in; emitter/camera geometry 1:1. |
| V6-04 | Purple ward + green vine lock | S25 / KF28 #2, #5 | Bright faceted purple crystalline ward seals the foyer archway; glowing green thorny vines erupt across the `Basement Stairs` doorway. |  |  | `HARD_LIMIT (HL-1)` VFX; lockdown trigger logic HL-3. |
| V7-01 | CineCamera startscreen framing | S01 / KF01 #3 | Locked-off wide shot of the street with right-aligned menu stack; port CineCamera at `(-12.7196, 0.4566, 14.6089)`, vFOV `48.03°`, pitch `+13.8°`, yaw `−46.335°`. |  |  | `1:1_MATCH` framing (`main_menu.gd:12-19`). |
| V7-02 | Telescope scripted hard cuts | S05 / KF05 #4 | Hard cut into the fixed sky view at `00:20.23`; centered `[F] EXIT`; hard cut back to the Den at `00:21.77`. |  |  | `_ponder_cam` scripted cut (`mission_controller.gd:57-62`); check cut timing ±0.2 s. |
| V7-03 | DOF blur behind briefing letter | S11 / KF13 #1 | Depth-of-field / Gaussian blur over the brick safe-room backdrop behind the parchment modal. |  |  | Post-process blur approximated (HL-7 mapping). |
| V7-04 | Takedown camera lunge & pull-back | S23 / KF26 | Scripted 1P lunge/tilt into the grapple (`03:17.80–03:20.60`), then pull-back to standing eye height (`03:20.80–03:22.00`). |  |  | `KNOWN_GAP (PG-7)` simplified camera motion. |
| V7-05 | Pause darkened blurred backdrop | S27 / KF30 #1 | Darkened blurred gameplay backdrop behind the teal/copper Art-Nouveau modal; frozen multi-cursor trail after `03:43.70` is a capture artifact. |  |  | Backdrop blur approximated; modal layout `1:1_MATCH` (UI1-02). |

### 8.2 Audio (AU1–AU6)

| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score | Notes |
|---|---|---|---|---|---|---|
| AU1-01 | Startscreen rain bed, zero BGM | S01 / KF01 #6 | Steady night rain hiss + distant street air `-53 to -49 dBFS` RMS; explicit zero BGM score. |  |  | `KNOWN_GAP (PG-6)`: no ambience bed in port — silence will read as `MISSING`. |
| AU1-02 | Den room tone | S03 / KF02 #7 | Indoor room tone `-76.3 to -73.1 dBFS` RMS; no BGM. |  |  | PG-6. |
| AU1-03 | Loading digital silence | S02; S10 / KF12 #5 | S02: rain fades to `-82.0` then `-240.0 dBFS`; S10: true digital silence `01:04.94–01:07.78` (100.000% zero samples), rain fade-in from `01:07.7757`. |  |  | PG-6: port has no loading music either — verify the port is silent, not playing stray audio. |
| AU1-04 | Rooftop wind swell in telescope view | S05 / KF05 #5 | Exterior wind whoosh rises to `-39.5 dBFS` RMS / `-29.8 dBFS` pk during the sky cut only (`00:19.6–00:21.9`). |  |  | PG-6. |
| AU1-05 | Continuous rain bed across exteriors | S13–S21 | Rain bed under all alley/roofline/terrace foley; outdoor→sheltered shift at the door creak (`03:01.0–03:02.2`). |  |  | PG-6. |
| AU1-06 | Hearth crackle bed | S22 / KF25 #7 | Quiet crouch approach over hearth crackle `-67.5 to -54.0 dBFS`. |  |  | PG-6 (+ flame VFX HL-1). |
| AU2-01 | Diegetic gramophone jazz (only music in clip) | S07 / KF09 #1 | Switch click `pk=-36.3`; warped wind-up + scratchy 1920s jazz/ragtime with vinyl crackle `00:45.4–00:47.8` `pk=-24.9 dBFS`, attenuating on walk-away (`00:47.9–00:49.0`). |  |  | PG-6: no music playback path in port. |
| AU3-01 | Wooden-plank footsteps | S03 / KF02 #7; S05 | Hollow wooden footfalls `pk=-27.9` (S03) / `pk=-27.1 dBFS` (S05). |  |  | PG-6: no per-surface footsteps. |
| AU3-02 | Wet cobble walk → sprint → crouch | S13 | Walk `01:20–01:24`; rapid sprint/puddle splash `pk=-25.2 dBFS` (`01:24.4–01:27.4`); crouch cadence `01:28–01:33.8`. |  |  | PG-6. |
| AU3-03 | Metal grate steps + vault thud | S12 | Hollow grate footsteps `pk=-27.3` (`01:18.6`, `01:19.0`) + vault/drop thud `pk=-30.5 dBFS` (`01:19.6`). |  |  | PG-6. |
| AU3-04 | Hard-sole marble footsteps | S24 / KF27 #8 | Crisp hard-sole footfalls on checkered marble `pk=-28.9 dBFS` (`03:23.8–03:28.9`). |  |  | PG-6. |
| AU3-05 | Slate stair footfalls + ZipWire clack | S26 / KF29 #7 | Rapid steps up the slate stairs + clack `pk=-24.5 dBFS` (`03:39.8`), quieting at the landing. |  |  | PG-6. |
| AU4-01 | `PLAY` click | S01 / KF01 #3 | Crisp UI click `pk=-33.4 dBFS` at `00:02.0`. |  |  | PG-6: no UI audio in port. |
| AU4-02 | Wardrobe browse ticks | S04 / KF03 #7 | Open latch/whoosh chime `pk=-23.5` + 8 metallic hover/slot ticks `pk=-34.6 to -39.4 dBFS` + close clack `pk=-35.1`. |  |  | PG-6. |
| AU4-03 | Ledger parchment & tab clicks | S06 / KF07 #6; KF08 #6 | Parchment rustle + open/tab clicks `pk=-30.4` / `pk=-34.5 dBFS`; quiet `-68 dBFS` reading; re-open `pk=-33.7`; close-prep `pk=-34.3`. |  |  | PG-6. |
| AU4-04 | Six countdown ticks | S09 / KF11 #6 | `6..5..4..3..2..1` percussive ticks at exact `1.00 s` intervals, `pk=-41.3 to -35.7 dBFS` (`00:59.0–01:04.0`). |  |  | PG-6. |
| AU4-05 | Pause click, −19 dB duck, quit clicks | S27 / KF30 #4 | Pause click `pk=-35.6`; ambience ducks `-53 -> -72.4 dBFS`; hover+select `pk=-34.2 dBFS`; complete digital silence `03:43.80–03:45.64`. |  |  | PG-6; silence tail expected both sides. |
| AU5-01 | Vintage car double-honk | S13 / KF15 | `HONK—HONK!` short blast + sustained two-tone `pk=-20.2 dBFS` (`01:35.68–01:36.45`; highest peak of the act) with flashing headlights. |  |  | PG-6 (horn may map to a one-shot tag; verify). |
| AU5-02 | ZipWire launch + crank ratchet | S14 / KF16 #4; S15 / KF17 #5 | Equip clank `pk=-24.3`; launch snap/twang `pk=-21.5` (`01:43.5–01:43.8`); spring/pneumatic `pk=-24.8`; ratchet hand-cranking `pk=-22.2 dBFS`. |  |  | PG-6. |
| AU5-03 | Smoke detonation pop + hiss | S18 / KF20 #2 | Throw + metallic canister clink `pk=-28.0` (`02:27.3–02:27.4`); detonation pop + sustained pressurized hiss `pk=-20.5 dBFS` (`02:28.3–02:29.8`). |  |  | PG-6. |
| AU5-04 | Vistara shimmer/chime | S19 / KF21 #8 | Crystalline equip + scan shimmer/chime pulse `pk=-28.0 dBFS` (`02:32.8–02:33.6`). |  |  | PG-6. |
| AU5-05 | Ward tripwire chime, whoosh & hum | S25 / KF28 #8 | Two-note metallic chime `pk=-30.4` (`03:29.1–03:29.6`); crystalline whoosh `pk=-32.3`; sustained low ward hum `-59 dBFS` (`03:33.5–03:35.3`). |  |  | PG-6. |
| AU5-06 | Barrier shatter + alert sting | S26 / KF29 #7 | Loud crystalline impact/shatter + sharp sting `pk=-23.5 dBFS` (`03:37.7–03:38.2`); loudest segment in range. |  |  | PG-6. |
| AU5-07 | Key jingle + acquisition chime | S22 (03:17.1) | Metallic key jingle + acquisition chime `pk=-23.6 dBFS` at `03:17.3`. |  |  | PG-6. |
| AU5-08 | Takedown thud + KO groan | S23 / KF26 #4 | Non-verbal grapple grunts `pk=-23.7` (`03:18.8–03:19.7`); heavy blunt impact + guard pain/KO groan `pk=-22.1 dBFS` (`03:20.6–03:21.5`). |  |  | PG-6. |
| AU6-01 | ThiefNisha spawn VO | S12 / KF14 #8 | *"Let the thieving begin."* `pk=-30.8 dBFS` (`01:11.6–01:13.1`). |  |  | PG-6: no VO/bark playback in port. |
| AU6-02 | Gate guard barks | S13 | Guard 1: *"What?"* (`01:34.1`); *"[Bit / You're] too loud, [thief?]."* (`01:37.2–01:38.5`); *"What?!"* + alert sting (`01:38.8–01:39.2`). |  |  | PG-6. |
| AU6-03 | Alert & patrol shouts | S14–S16 / KF16 #7; KF17 #4 | *"I know someone's here!"* `pk=-25.9`; *"Oh, I will find you, thief!"* (`~01:49.6–01:53.0`); *"Who's there?"* (`02:02.4`); *"Captain said to look around for signs of trouble. Thieves, eh?"* (`02:06.8–02:11.0`). |  |  | PG-6. |
| AU6-04 | Smoke-reaction barks | S18 / KF19 #7 | *"Hey! Show yourself!"* `pk=-33.3` (`02:24.8–02:26.0`); faint cough (`02:29.5`); *"You stop making noise, you dog!"* (`02:30.3–02:32.2`). |  |  | PG-6. |
| AU6-05 | Post-KO line | S24 | ThiefNisha *"And stay down."* `pk=-32.6 dBFS` (`03:22.4–03:23.6`). |  |  | PG-6. |
| AU6-06 | Distant search & idle barks | S17; S20 | *"Guess I'll search over here."* (`02:20.1–02:21.7`); throat-clear *"Ahem-hem"* (`02:41.5–02:42.2`); *"Hey!"* (`02:46.2`). |  |  | PG-6 + patrol paths HL-3. |

### 8.3 HUD/UI (UI1–UI5)

| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score | Notes |
|---|---|---|---|---|---|---|
| UI1-01 | Startscreen menu stack | S01 / KF01 #3 | Right-aligned `THICK AS THIEVES` logo above `PLAY` / `SETTINGS` / `CREDITS` / `QUIT`; cursor travels to `PLAY`. |  |  | `1:1_MATCH` menu stack (front-end menu, outside the PG-2 HUD fails). |
| UI1-02 | Pause modal + build footer | S27 / KF30 #2, #5 | `RESUME` / `SETTINGS` / `RETURN TO THIEF'S DEN` (straight apostrophe) / `QUIT TO DESKTOP`; footer `1.5.148559   Novice   1025051536`. |  |  | Modal `1:1_MATCH`; quit-to-desktop teardown is PG-1; port footer will show its own build string — note it. |
| UI2-01 | Den station prompt chain | S05 / KF05 #4; S08 / KF10 #3 | `[F] PONDER` → centered `[F] EXIT` in the sky view; `[F] READ LEDGER` at the desk; `[F] ENTER MATCH` reticle. |  |  | PG-2 (look-at card rendering on map table). |
| UI2-02 | Wardrobe slots, drawer & tooltips | S04 / KF03 #2, #3; KF04 #1 | `Edit Loadout` slots 1–4; `Signature Tools cannot be swapped out` notice; slot-3 expanded 4-tool row; `Vistara Diamond` tooltip card; `Zipwire` grapple-recoil description. |  |  | PG-2: `clipped_controls` live fail — check all controls visible. |
| UI2-03 | ZipWire action prompts | S14 / KF16 #6 | Bottom-right `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]` with `[1]` highlighted bottom-left from `01:39.5`. |  |  | PG-2 `equipped_tool!=zipwire` toggle bug; PG-4 crank clip playback. |
| UI2-04 | `CRANK [LMB]` progress ring | S15 / KF17 #3; S26 / KF29 #3 | Circular blue/white segmented progress ring `CRANK [LMB]` center-screen (`01:51.20`); six-tick circular reticle on the stairs (`03:39.40`). |  |  | PG-2 (port scenario `zipwire_crank` is the S15 fail id, not clip S15) + PG-4. |
| UI2-05 | Blue door prompts | S21 / KF24 #2, #3 | `[F] OPEN` stacked above `[F] [HOLD] LOCK` (`03:00.60–03:01.00`), flipping to `[F] CLOSE` (`03:01.20`) as the door swings inward. |  |  | PG-2 (`circular_lockpick_minigame_ui` fail at this door) + PG-4 door live-unconfirmed. |
| UI2-06 | Pickpocket/takedown prompts | S22 / KF25 #4, #5 | `[F] PICK POCKET` above `[F] [HOLD] TAKEDOWN` (`03:15.00–03:17.00`). |  |  | PG-2 HUD rows; pickpocket cone itself 1:1 (`guard_ai.gd`). |
| UI2-07 | Gramophone toggle flip | S07 / KF09 #2 | `[F] TURN ON` flips to `[F] TURN OFF` after the `00:44.4` click while the record plays. |  |  | Prompt flip 1:1 expected; record audio is PG-6 (AU2-01). |
| UI3-01 | Player card + compass fade-in | S03 / KF02 #2, #3 | Top-right `Johnny Cipher` Spider card level `4` + subtle top-center compass `NW` fade in by `002.703s`. |  |  | PG-2 HUD card rendering. |
| UI3-02 | Loot tracker, hotbar & hidden health | S12 / KF14 #3–#5 | `(£) 0` + `Mission: Steal 4,000 in loot value[0/4,000]` (no space before `[0/4,000]`); Health Bar hidden at 100% HP; `[1]`/`[2]`/`[4]` + `[TAB] MAP [MMB] [HOLD] PING MENU`. |  |  | PG-2; MMB binding verified in `project.godot` input map. |
| UI3-03 | Health Bar reveal at ~75% | S17 boundary / KF19 #1 | First fall damage `02:23.30` (`red_px: 0 -> 27,560`) reveals the ornate Health Bar draining to ~75% with a trailing bright-red segment. |  |  | Fall curve ported 6.5→23.25 m; reveal timing + fill level are the check. |
| UI3-04 | `Guildhall Key` HUD row | S22–S26 / KF27 #5 | Key icon + label persist bottom-left above `[1]` Zipwire after the `03:17.10` pickup (golden key shimmer, not `!`). |  |  | PG-2 HUD rows; pickup logic 1:1 (`world_pickup.gd`). |
| UI3-05 | Light Gem exposure states | S12 / KF14 #6; S15 / KF17 #6; S21 / KF24 #5; S22 / KF25 #6 | Lit sector size/position track light amount + direction: lit cream toward lantern (S12), fully dark concealed while cranking (S15), fully lit at the portico (S21), bright white-gold by the hearth (S22). |  |  | Gem semantics per §5.3; `PG-2` pips/arcs node-name fail affects rendering, not semantics. |
| UI3-06 | Map-table keybind legend | S08 / KF10 #6 | Bottom-right `JOIN GAME [F]` / `TOGGLE MODE [R]` / `TOGGLE DIFFICULTY [H]`. |  |  | PG-2 (map_table look-at card fail). |
| UI4-01 | `JOURNAL` tab | S06 / KF07 #1–#5 | `[Q] JOURNAL` + `BLACK MARKET [E]` tabs; `Level 4` XP bar `94/500`; `Contract #1/#2` `Completed`, `#3` `Active` (*Into the Lion's Den*, *In the Eye of the Beholder*) with full lore paragraphs. |  |  | PG-2; contract titles fall back to `Contract N — <quest item>` in port (#17) — expect title wording delta, note it. |
| UI4-02 | `BLACK MARKET` tab | S06 / KF08 #1–#5 | `YOUR TOTAL ASSETS: (£) 26,275`; `✓ PURCHASED` on `Zipwire`; `TOOLS` / `GUILD PERKS` / `SPIDER COSMETICS` / `CHAMELEON COSMETICS` with prices `7,500`/`5,000`/`2,500` and padlock badges. |  |  | PG-2. |
| UI4-03 | Mission prep cards + READY toggle | S09 / KF11 #2, #3, #6 | Cards: `CONSTABLES' GUILDHALL` / `Cleanout Heist` / `Time Limit: 55 minutes` / `Contract Inactive`; `[F] READY` → `READY` + `[F] UNREADY` / `[ESC] BACK` at `058.807s`; 3D Spider on the slate ridge. |  |  | PG-2 `mission_lobby_fov_20` ×2 live fails; ThiefNisha PBR preview bound. |
| UI4-04 | Briefing letter (11 lines) | S11 / KF13 #2, #3 | Typewriter letter verbatim incl. `55 minute window` and `magic door ... 20 minutes`; thin right scrollbar; `[SPACE] CONTINUE` below. |  |  | PG-2. |
| UI4-05 | Loading spinner + gold emblem | S02; S10 / KF12 #3, #4 | Centered rotating cyan/white ring over `LOADING...`; gold `THICK AS THIEVES` emblem bottom-center. |  |  | `1:1_MATCH` expected (2D screen); timing per G5-01. |
| UI5-01 | Red player-noise arcs | S13 / KF15 #4; S18 / KF20 #5; S24 / KF27 #7 | Absent when quiet (dark gem at the alley drop); wide/bright during the sprint (`pk=-25.2`) and smoke detonation; twin inner+outer arcs flare with marble footsteps. Arcs read the player's own noise level. |  |  | PG-2 `guard_pips_and_offscreen_arcs` node-name mismatch — arcs may be missing/misnamed. |
| UI5-02 | Guard-alert direction pip | S15 / KF17 #4 | Three-dash crimson directional pip mid-right (`x~1195, y~832`) during *"Oh, I will find you, thief!"*; distinct from the gem's player-noise arcs (no gem arcs present). |  |  | PG-2 pips fail; check direction + three-dash shape. |
| UI5-03 | Guard alert bar + red eyes | S14 / KF16 #2 | Alerted constable with vertical yellow overhead alert bar, glowing red eyes, hip flashlight at `01:40.20`. |  |  | `UNVERIFIED_LIVE` guard-side indicators (#13). |
| UI5-04 | Vistara RED→GREEN guard states | S19 / KF21 #3; KF22 #1 | Scan pulse highlights the patrolling constable RED (`02:31.40–02:32.60`, clearest `02:32.20`), flipping to bright GREEN at `02:33.00`. |  |  | `UNVERIFIED_LIVE` scan highlight (#12/#13). |
| UI5-05 | 6 s countdown banner | S09 / KF11 #1 | Top-center `MISSION STARTING IN 6...` → `1...` with `Mode: Solo` / `Difficulty: Novice` (`058.914–064.775s`). |  |  | PG-2; tick audio AU4-04. |
| UI5-06 | Status icons above the Light Gem | S25 / KF28 #6; S26 / KF29 #4 | White mechanical jaw/bear-trap icon with countdown ring (`03:29.00+`) + orange-arc unconscious-head icon `xx`+`zz`+`>>` (`03:31.20+`); re-triggered jaw-trap `03:38.07–03:41.87` until the Pause Menu hides the HUD. |  |  | PG-2. |
| UI5-07 | Sound-ripple + ZipWire gleam | S20 | Sound-ripple ring + red player-noise arcs as the ZipWire gleams white (`02:50.00–02:50.50`). |  |  | PG-2 arcs/pips fail. |

### 8.4 Gameplay (G1–G5)

| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score | Notes |
|---|---|---|---|---|---|---|
| G1-01 | Telescope station | S05 / KF05 #4 | `[F] PONDER` at the brass telescope cuts to the exterior sky view; `[F] EXIT` returns (`00:20.23–00:21.74`). |  |  | `_ponder_cam` 1:1 (`mission_controller.gd:57-62`). |
| G1-02 | Decoration swap + trunk cycle | S07 / KF09 #2, #4 | `[F] CHANGE DECORATION` swaps golden owl → blue/silver spider-emblem chest (`00:40.1–00:42.0`); trunk cycle egg ↔ chalice, pink gem ↔ white diamond (`00:47.6–00:50.0`); clinks `pk=-34.7`. |  |  | Station logic 1:1 (#17); prompt card PG-2. |
| G1-03 | Mission select + confirmation modal | S08 / KF10 #1–#3 | Tokens `ELWAY MANOR` → `CONSTABLES' GUILDHALL`; card `[H] Difficulty: Novice` / `[R] Mode: Solo` / `[F] Prepare for Mission`; modal `Join Mission with these settings? / Difficulty: Novice / Mode: Solo` + `[SPACE] PREPARE FOR MISSION` / `[ESC] CANCEL` at `055.339s`. |  |  | PG-2 `map_table_look_at_card` live fail. |
| G1-04 | Vintage car interact | S13 / KF15 | `[F] INTERACT` (`01:35.38`) triggers the double-honk + flashing headlights (`01:35.68–01:36.45`, `01:36.38+`). |  |  | `UNVERIFIED_LIVE` interactable (#17). |
| G1-05 | Safe-room lantern toggle | S12 / KF14 #2 | `[F] TURN ON` click `01:15.1` → flame + `[F] TURN OFF` beside the `"SPIDER"` flyer. |  |  | Station 1:1; flame VFX HL-1. |
| G1-06 | Pickpocket `Guildhall Key` | S22 / KF25 #4 | `[F] PICK POCKET` completes `03:17.10`: golden key shimmer + HUD label appear (verified not a `!` marker). |  |  | Pickpocket cone 1:1 (`guard_ai.gd:5-160`); HUD row PG-2. |
| G2-01 | Den hub walk | S03 / KF02 #7 | Free walk across floorboards during the opening pan; wooden footsteps `00:04.5–00:05.8`. |  |  | Movement constants 1:1 (3.6/1.8/5.4/5.5, FOV 85; #10). |
| G2-02 | Alley drop → sprint → crouch | S13 / KF15 #5–#6 | Drop past the banner, walk (`01:20–01:24`), sprint/puddle splash (`01:24.4–01:27.4`), crouch (`01:28–01:33.8`); noise arcs track the sprint. |  |  | Speeds 1:1; footsteps audio PG-6; arcs PG-2. |
| G2-03 | ZipWire crank ascent + roofline | S15–S16 / KF17 #1, #5 | 2nd shot anchors the roof parapet; rhythmic 1P crank hauls up the facade (`01:52.20–01:58.00`); roofline traverse + winch-housing pass (`02:01.00–02:10.40`). |  |  | PG-4: crank clip `AN_ThiefNisha_Zipwire__Reload_Loop` proven headless only. |
| G2-04 | Cable crossing + courtyard descent | S17 / KF18 #1 | Mid-cable crossing over the arch/griffins (`02:11.00–02:17.00`); face-on gear-plate landing (`02:17.60–02:18.80`); drop to flagstones beside crates (`02:19.00–02:23.20`). |  |  | PG-4 traversal chain; fall damage G5-02. |
| G2-05 | Slate staircase ascent | S26 / KF29 | Rapid ascent `03:39.60–03:41.20` up the plain dark grey/slate run to the upper landing gallery. |  |  | PG-4 stairs snap 50°/0.3 headless-only — watch for sticking. |
| G3-01 | ZipWire `[1]` equip + 1st launch | S14 / KF16 #4 | Launcher swings into the right hand (`01:39.30–01:39.50`); 1st launch `01:42.90–01:43.90`; non-damaging foliage landing beside the chest (`red_px=0` across `01:40–01:48`). |  |  | PG-2 equip-toggle bug + PG-4 crank playback; verify no damage on this landing. |
| G3-02 | Smoke bomb throw + plume cover | S18 / KF19 #4; KF20 #1 | `[2]` equip with `THROW [LMB]`; canister thrown onto the grand stairs (`02:26.80–02:27.40`); flash `02:28.20`; plume blocks stair sight lines (`02:28.40–02:29.80`). |  |  | 5×5×4 m / 25 s smoke box stand-in (PG-7); plume look HL-1. |
| G3-03 | Vistara Diamond scan pulse | S19 / KF21 #4 | `[4]` held in brass-and-leather caliper mount; scan pulse highlights the constable RED (`02:31.40–02:32.60`) with a warm golden courtyard glint (`02:32.60–02:33.00`). |  |  | `UNVERIFIED_LIVE` scan mechanics (#12). |
| G3-04 | Tool swap back to `[1]` | S19 / KF22 #3 | `[4]` → `[1]` swap (`02:32.80–02:33.00`); prompts flip to `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]`; re-equip click `02:34.0` `pk=-28.2`. |  |  | PG-2 hotbar highlight + toggle bug. |
| G4-01 | Gate guard alert escalation | S13–S14 / KF16 #2, #7 | Barks escalate *"What?"* → *"[Bit / You're] too loud, [thief?]."* → *"What?!"* + alert sting as the gate is approached; red eyes + vertical yellow alert bar at `01:40.20`. |  |  | Detection ramp/decay 1:1 (`guard_ai.gd:39-64`); barks PG-6; foot-slide PG-7. |
| G4-02 | Roofline patrol mutter | S16 | *"Who's there?"* (`02:02.4–02:03.6`) + patrol mutter *"Captain said to look around for signs of trouble. Thieves, eh?"* (`02:06.8–02:11.0`). |  |  | Patrol paths positions-only (HL-3); barks PG-6. |
| G4-03 | Distant search & idle barks | S17; S20 | *"Guess I'll search over here."* (`02:20.1–02:21.7`); throat-clear (`02:41.5–02:42.2`); *"Hey!"* (`02:46.2`); patrolling guard spotted ahead (`02:53.00–02:54.50`). |  |  | HL-3 + PG-6. |
| G4-04 | Guard takedown + KO | S23 / KF26 #2 | Hold `[F]` on `[HOLD] TAKEDOWN` as the guard turns (`03:17.40`); lunge grapple `03:17.80–03:20.60`; KO onto the parquet `03:20.6–03:21.5`. |  |  | KO state 1:1 (`guard_ai.gd`); grapple anim PG-7; grunts PG-6. |
| G4-05 | Distant green guard silhouette | S17 / KF18 #3 | Distant constable under the portico highlighted bright green at `02:14.80` during the cable crossing. |  |  | `UNVERIFIED_LIVE` highlight rendering (#13/#14). |
| G5-01 | Mission flow: select → ready → countdown → load | S08–S10 / KF10, KF11, KF12 | Confirm chime `00:55.4` → Mission Prep → `[F] READY` (`058.807s`) → countdown `058.914–064.775s` → hard cut to loading `064.803s`. |  |  | Flow cards PG-2; sublevel + difficulty timers ported (7200/2700/1800 s; #17). |
| G5-02 | First fall damage | S17 boundary `02:23.30` | Courtyard drop registers damage (`red_px: 0 -> 27,560`); Health Bar reveals and settles at ~75% fill. |  |  | Fall curve 6.5→23.25 m + regen 15/s ported (`combat-health.md`). |
| G5-03 | Beam tripwire → ward lockdown | S25 / KF28 #1–#6 | Crossing the foreground beam at `03:29.00` seals the archway (purple ward), locks `Basement Stairs` (green vines), raises the jaw-trap icon; unconscious-head icon follows `03:31.20+`. |  |  | Tripwire→lockdown trigger approximated (HL-3); ward VFX HL-1. |
| G5-04 | Ward shatter → crimson alarm | S26 / KF29 | Loud crystalline barrier impact/shatter + alert sting (`03:37.7–03:38.2`) triggers the crimson alarm spotlight for the stair ascent. |  |  | Trigger logic HL-3; spotlight light 1:1 (#6). |
| G5-05 | Pause → quit flow | S27 / KF30 #3 | Pause entry exactly `03:41.90`; cursor hovers `QUIT TO DESKTOP` cleanly (`03:43.10–03:43.30`); selection `03:43.2–03:43.6`; digital silence tail. |  |  | PG-1: quit-to-desktop teardown unconfirmed live — stop the recorder before quitting if it crashes. |

## 3. Per-segment image slots (S01–S27)

One slot per clip segment (`KEYFRAME_INDEX.md` §2; window = segment start–end). Official side = the
segment's anchor keyframe from `clean/` by exact filename; where a segment holds several keyframes the
anchor-closest one is slotted and the remaining exact filenames are listed in Notes (all 30 side-by-sides
are still built per `REFERENCE_BASELINE.md` §10 step 3). Port side placeholder follows §9.3 naming
(`port_KFnn_<mm_ss>.jpg`); replace `<date>` and `<mm_ss>` after extraction
(`tools/make_side_by_side.sh` emits the matching commands).

| Seg | Window | Official | Port | Notes |
|---|---|---|---|---|
| S01 | `00:00.00–00:02.15` | ![official](clean/KF01_00m01s_startscreen.jpg) | ![port](../port_<date>/port_KF01_<mm_ss>.jpg) |  |
| S02 | `00:02.15–00:02.60` | ![official](clean/KF12_01m06s_loading_screen.jpg) | ![port](../port_<date>/port_KF12_<mm_ss>.jpg) | No dedicated keyframe (`KEYFRAME_INDEX.md` §2: loading layout identical to `KF12_01m06s_loading_screen.jpg`) — slot reuses that shared loading-art frame (S02/S10 show the same art). |
| S03 | `00:02.60–00:06.57` | ![official](clean/KF02_00m04s_den_entry.jpg) | ![port](../port_<date>/port_KF02_<mm_ss>.jpg) |  |
| S04 | `00:06.57–00:18.24` | ![official](clean/KF03_00m07s_wardrobe_loadout.jpg) | ![port](../port_<date>/port_KF03_<mm_ss>.jpg) | Also `KF04_00m16s_wardrobe_vistara_diamond.jpg` — build its side-by-side too (`REFERENCE_BASELINE.md` §10 step 3). |
| S05 | `00:18.24–00:26.58` | ![official](clean/KF05_00m20s_telescope_cheese_moon.jpg) | ![port](../port_<date>/port_KF05_<mm_ss>.jpg) | Also `KF06_00m24s_den_wanted_window.jpg` — build its side-by-side too (`REFERENCE_BASELINE.md` §10 step 3). |
| S06 | `00:26.58–00:38.17` | ![official](clean/KF07_00m27s_ledger_journal.jpg) | ![port](../port_<date>/port_KF07_<mm_ss>.jpg) | Also `KF08_00m28s_ledger_black_market.jpg` — build its side-by-side too (`REFERENCE_BASELINE.md` §10 step 3). |
| S07 | `00:38.17–00:51.08` | ![official](clean/KF09_00m46s_den_gramophone.jpg) | ![port](../port_<date>/port_KF09_<mm_ss>.jpg) |  |
| S08 | `00:51.08–00:56.08` | ![official](clean/KF10_00m52s_den_map_table.jpg) | ![port](../port_<date>/port_KF10_<mm_ss>.jpg) |  |
| S09 | `00:56.08–01:04.80` | ![official](clean/KF11_01m00s_mission_prep_countdown.jpg) | ![port](../port_<date>/port_KF11_<mm_ss>.jpg) |  |
| S10 | `01:04.80–01:09.44` | ![official](clean/KF12_01m06s_loading_screen.jpg) | ![port](../port_<date>/port_KF12_<mm_ss>.jpg) |  |
| S11 | `01:09.44–01:10.81` | ![official](clean/KF13_01m10s_briefing_letter.jpg) | ![port](../port_<date>/port_KF13_<mm_ss>.jpg) |  |
| S12 | `01:10.81–01:20.10` | ![official](clean/KF14_01m15s_saferoom_portal_hud.jpg) | ![port](../port_<date>/port_KF14_<mm_ss>.jpg) |  |
| S13 | `01:20.10–01:39.30` | ![official](clean/KF15_01m21s_alley_barrons_demolition.jpg) | ![port](../port_<date>/port_KF15_<mm_ss>.jpg) |  |
| S14 | `01:39.30–01:49.50` | ![official](clean/KF16_01m40s_zipwire_gate_headlights.jpg) | ![port](../port_<date>/port_KF16_<mm_ss>.jpg) |  |
| S15 | `01:49.50–01:58.50` | ![official](clean/KF17_01m51s_zipwire_aim_roof.jpg) | ![port](../port_<date>/port_KF17_<mm_ss>.jpg) |  |
| S16 | `01:58.50–02:11.00` | ![official](clean/KF18_02m14s_guildhall_arch_overlook.jpg) | ![port](../port_<date>/port_KF18_<mm_ss>.jpg) | **S16 has no keyframe** (`KEYFRAME_INDEX.md` §2 `Linked Keyframes` = `—`). Slot shows `KF18_02m14s_guildhall_arch_overlook.jpg` (`02:14.80`, S17) as the nearest official anchor frame only — do NOT score S16 against it; extract official S16 frames from the clip window `01:58.50–02:11.00` (`BREAKDOWN.md` clip-frame evidence) and replace this slot. |
| S17 | `02:11.00–02:23.30` | ![official](clean/KF18_02m14s_guildhall_arch_overlook.jpg) | ![port](../port_<date>/port_KF18_<mm_ss>.jpg) |  |
| S18 | `02:23.30–02:30.70` | ![official](clean/KF19_02m25s_smoke_bomb_equip.jpg) | ![port](../port_<date>/port_KF19_<mm_ss>.jpg) | Also `KF20_02m29s_smoke_bomb_plume.jpg` — build its side-by-side too (`REFERENCE_BASELINE.md` §10 step 3). |
| S19 | `02:30.70–02:33.00` | ![official](clean/KF21_02m32s_vistara_diamond_red_guard.jpg) | ![port](../port_<date>/port_KF21_<mm_ss>.jpg) | Also `KF22_02m33s_vistara_diamond_green_guard.jpg` — build its side-by-side too (`REFERENCE_BASELINE.md` §10 step 3). |
| S20 | `02:33.00–02:54.50` | ![official](clean/KF23_02m41s_side_wing_macleod_sign.jpg) | ![port](../port_<date>/port_KF23_<mm_ss>.jpg) |  |
| S21 | `02:54.50–03:04.50` | ![official](clean/KF24_03m00s_locked_blue_double_doors.jpg) | ![port](../port_<date>/port_KF24_<mm_ss>.jpg) |  |
| S22 | `03:04.50–03:17.10` | ![official](clean/KF25_03m16s_parlor_pickpocket_takedown.jpg) | ![port](../port_<date>/port_KF25_<mm_ss>.jpg) |  |
| S23 | `03:17.10–03:22.00` | ![official](clean/KF26_03m20s_parlor_guard_takedown.jpg) | ![port](../port_<date>/port_KF26_<mm_ss>.jpg) |  |
| S24 | `03:22.00–03:29.00` | ![official](clean/KF27_03m27s_foyer_security_beam.jpg) | ![port](../port_<date>/port_KF27_<mm_ss>.jpg) |  |
| S25 | `03:29.00–03:37.40` | ![official](clean/KF28_03m35s_foyer_arcane_barriers.jpg) | ![port](../port_<date>/port_KF28_<mm_ss>.jpg) |  |
| S26 | `03:37.40–03:41.90` | ![official](clean/KF29_03m39s_stairs_crimson_alarm.jpg) | ![port](../port_<date>/port_KF29_<mm_ss>.jpg) |  |
| S27 | `03:41.90–03:45.64` | ![official](clean/KF30_03m43s_pause_menu.jpg) | ![port](../port_<date>/port_KF30_<mm_ss>.jpg) |  |

## 4. Alignment table (S01–S27)

27 anchor events (`REFERENCE_BASELINE.md` §9.4; segments per `KEYFRAME_INDEX.md` §2). Locate each
anchor event's first frame in both recordings, fill **Port ts**, compute **Offset (s)** = port ts −
official ts, and write the rows to `offsets.csv` as `Snn, official ts, port ts, offset s`
(`REFERENCE_BASELINE.md` §10 step 2; consumed by `tools/make_side_by_side.sh`). One offset per segment is
expected — drift inside a segment is itself a finding; record it in **Offset notes**.

| Seg | Anchor event | Official ts | Port ts | Offset (s) | Offset notes |
|---|---|---|---|---|---|
| S01 | First Startscreen frame (menu stack visible, cursor near `PLAY`) | `00:00.00` |  |  |  |
| S02 | Hard cut to loading art after the `PLAY` click | `00:02.15` |  |  |  |
| S03 | First Den fade-in frame (player card fading in) | `00:02.60` |  |  |  |
| S04 | Wardrobe fully faded in (`WARDROBE` header legible) | `00:06.57` |  |  |  |
| S05 | Telescope exterior cut (sky + moon visible; cut-back `00:21.77`) | `00:20.23` |  |  |  |
| S06 | `JOURNAL` panel open over the desk | `00:26.58` |  |  |  |
| S07 | Gramophone switch click (`[F] TURN ON`) | `00:44.40` |  |  |  |
| S08 | Map-table settings card visible (`[H] Difficulty: Novice`) | `00:51.50` (KF10 `00:52.35`) |  |  |  |
| S09 | `MISSION PREPARATION` cut (countdown starts `00:58.914`) | `00:56.08` |  |  |  |
| S10 | Hard cut to loading art (screen 2) | `01:04.80` |  |  |  |
| S11 | Briefing letter parchment fully visible | `01:09.44` |  |  |  |
| S12 | Safe-room spawn (HUD fade-in complete `01:11.31`) | `01:10.81` |  |  |  |
| S13 | Alley drop landing (`BARRON'S DEMOLITION` in view) | `01:20.10` |  |  |  |
| S14 | ZipWire `[1]` equip swing into the right hand | `01:39.30` |  |  |  |
| S15 | 2nd launch: `CRANK [LMB]` ring appears | `01:51.20` |  |  |  |
| S16 | Roof-ridge arrival after the crank | `01:58.50` |  |  |  |
| S17 | Cable crossing start over the arch | `02:11.00` |  |  |  |
| S18 | Courtyard flagstone landing (Health Bar appears) | `02:23.30` |  |  |  |
| S19 | Vistara `[4]` equip + scan pulse (guard turns RED) | `02:31.40` |  |  |  |
| S20 | Balcony traverse start (side wing visible) | `02:33.00` |  |  |  |
| S21 | Arched portico entry (blue doors in view) | `02:55.00` |  |  |  |
| S22 | Parlor hearth first in view (constable visible) | `03:05.80` |  |  |  |
| S23 | Guard begins turning (takedown hold starts) | `03:17.40` |  |  |  |
| S24 | Foyer marble + first beam in view | `03:24.00` |  |  |  |
| S25 | Beam-cross trigger (purple ward seals the archway) | `03:29.00` |  |  |  |
| S26 | Crimson alarm wash onset | `03:38.20` |  |  |  |
| S27 | Pause modal fully open | `03:41.90` |  |  |  |

## 5. Summary score table

Tally the section 2 scores per pillar: counts per `PASS` / `DELTA` / `MISSING` / `HARD_LIMIT` / `N/A`
(`docs/REFERENCE_BASELINE.md` §10 steps 4–6). The last row is the expected checklist row count per pillar.

| Score | Visual (V1–V7) | Audio (AU1–AU6) | HUD/UI (UI1–UI5) | Gameplay (G1–G5) | Total |
|---|---|---|---|---|---|
| `PASS` |  |  |  |  |  |
| `DELTA` |  |  |  |  |  |
| `MISSING` |  |  |  |  |  |
| `HARD_LIMIT` |  |  |  |  |  |
| `N/A` |  |  |  |  |  |
| **Checklist rows** | 37 | 31 | 27 | 25 | 120 |
