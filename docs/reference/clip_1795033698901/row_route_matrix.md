# W0b — Checklist row → lane → scorable-on-this-route matrix

Source of rows: `docs/reference/clip_1795033698901/COMPARISON_TEMPLATE.md` §2, parsed in source order.
Counts are the template's own: **Visual 37, Audio 31, HUD/UI 27, Gameplay 25 = 120 rows** (37 + 31 + 27 + 25).

Lanes: **L1** = V1/V2/V7 (render, fx, camera) · **L2** = V3/V4/V5/V6 (materials, geometry, props) ·
**L3** = UI* · **L4** = G* · **L5** = AU*.

`scorable` = can a scorer reach the row's reference situation inside *this* 281 s port run and see/hear the
port's version of it?
`YES` = the reference situation occurs and a port frame/audio window shows it.
`PARTIAL` = the situation occurs but a defining element of the row is absent or different (stated inline).
`NO` = the run never reaches the reference situation; the absence proof names the official `Snn / KFnn`
required and the port time where it would have to happen, cross-referenced to `kf_presence.md`.

Port anchors are `t=mm:ss` of the port capture with the frame file (`t = NNNN-1 s`, e.g. `t=00:59 f_0060`).
Audio rows anchor the same run time; the port stem is `audio/port_48k.wav` (L5 scores it with `astats`).

## Visual (V1–V7) — 37 rows

| row id | criterion (short) | lane | scorable on this route? | port evidence anchor | absence proof (if not scorable) |
|---|---|---|---|---|---|
| V1-01 | Neon flicker + amber practicals | L1 | YES | `t=00:01 f_0002` magenta `Mac Neish/Jeweller` script neon + amber window/awning bars, `t=00:49 f_0050` same screen 48 s later (no flicker state change) | — |
| V1-02 | Volumetric moon shaft vs candle pools | L1 | YES | `t=00:19 f_0020` teal leaded window with volumetric haze; `t=00:13 f_0014` warm desk-lamp/candle pool | — |
| V1-03 | Banker's-lamp pool on the map | L1 | YES | `t=00:59 f_0060` warm pool across `KILCAIRN` parchment from the brass lamp | — |
| V1-04 | Lantern bounce & streetlamp exposure | L1 | PARTIAL | `t=01:45 f_0106` streetlamps + lit doorway on wet ground; `t=03:06 f_0187` interior wall sconce | no lantern ignite/toggle beat exists (no `[F] TURN ON`) |
| V1-05 | Flashing car-headlight glare | L1 | NO | — | needs S13–S14 / KF16: no vintage car anywhere; the street at `t=01:45–02:00` has a hand cart only — KF16 is ABSENT (`kf_presence.md` KF16) |
| V1-06 | Hearth amber radial pool | L1 | NO | — | needs S22 / KF25: no parlor, fireplace or hearth in the run — KF25 ABSENT |
| V1-07 | Crimson alarm spotlight wash | L1 | NO | — | needs S26 / KF29: no alarm state, no slate stairwell — KF29 ABSENT |
| V2-01 | Night rain streaks + puddle reflections | L1 | YES | `t=00:01 f_0002` vertical streaks + puddle reflection; exterior `t=01:45 f_0106` | — |
| V2-02 | Telescope sky, moon & cheese easter egg | L1 | YES | `t=00:22 f_0023` moon + pale-gold cheese wedge + 3 chunks over silhouettes | — |
| V2-03 | Loading illustration sky | L1 | YES | `t=01:29 f_0090` (also `t=00:08 f_0009`, `t=00:51 f_0052`) | — |
| V2-04 | Volumetric night-mist depth (clocktower, viaduct) | L1 | PARTIAL | `t=01:58 f_0119` hazy spire/half-timbered rooflines; `t=02:15 f_0136` rooflines | no clocktower silhouette with red window accents, no steel viaduct arch |
| V2-05 | Rain fade-in after digital silence | L1 | PARTIAL | cut path exists: loading `t=01:39 f_0099` → letter `t=01:40 f_0101` → rainy street `t=01:45 f_0106` | the "true digital silence" half is audio-only (L5); visually the port inserts the letter between loading and rain |
| V3-01 | Wet-cobble specular | L2 | YES | `t=01:45 f_0106`, `t=02:00 f_0121` damp cobbles + reflective patches | — |
| V3-02 | Emissive faceted diamonds | L2 | PARTIAL | `t=00:13 f_0014` / `t=00:23 f_0024` Den frames | green floor diamond and iridescent white table diamond are never in view; the S07 prop corner is not visited |
| V3-03 | Blue door paint, mullions & brass | L2 | NO | — | needs S21 / KF24: the port door at `t=02:51 f_0172` is dark timber with a brass handle — no blue paint or diamond-mullion glazing (KF24 PARTIAL) |
| V3-04 | Purple shopfront orb | L2 | YES | `t=00:01 f_0002` blue-purple orb above the neon in the upper window | — |
| V4-01 | Startscreen street dressing | L2 | YES | `t=00:01 f_0002` idle guard, car fender, crates, gold scrollwork storefront | — |
| V4-02 | Den attic dressing | L2 | YES | `t=00:13 f_0014` rolltop desk, armoire, `KILCAIRN` map table, rafters | scattered newspapers on the floorboards not visible in this framing |
| V4-03 | Wanted poster wall (five posters) | L2 | YES | `t=00:19 f_0020` `CAUTION / HIS HANDS ARE FAST`, `HE'S A THIEF`, `TELL A CONSTABLE!`, `WANTED £10000`, `REWARD £5000` | — |
| V4-04 | `BARRON'S DEMOLITION` alley dressing | L2 | PARTIAL | `t=02:00 f_0121` large blank white wall sign with a seam; crates, cart, iron fence, rain | no legible `BARRON'S DEMOLITION`, `EST. 1865` or `Out with the old…`; no oil drums, ladder or weeds |
| V4-05 | Gate arch, griffins & gear plate | L2 | NO | — | needs S14/S17 / KF16+KF18: `t=01:49 f_0110` is an unlettered stone perimeter wall + fence + pillar; no arch lettering, griffins or 10-bolt gear plate (KF16, KF18 ABSENT) |
| V4-06 | `MACLEOD` vertical sign | L2 | NO | — | needs S20 / KF23: no such facade; `t=02:41 f_0162` is an interior door — KF23 ABSENT |
| V4-07 | Foyer dressing (vitrine, armchair, floor plate, plaques) | L2 | PARTIAL | `t=02:53 f_0174` checkered marble hall + shrine + busts; `t=04:26 f_0267` backlit glass display case + plinth busts | no velvet armchair/ottoman, no flush metal floor plate, no `Basement Stairs` / `WC` plaques |
| V5-01 | Idle guard at shopfront | L2 | YES | `t=00:01 f_0002` guard silhouette in the `Mac Neish` doorway | — |
| V5-02 | 3D Spider turntable with cap sync | L2 | NO | — | needs S04 / KF03+KF04: no wardrobe overlay ever opens; `t=00:17 f_0018` is a bare dresser close-up (KF03/KF04 ABSENT) |
| V5-03 | 1P gloved hands + ZipWire viewmodel | L2 | YES | `t=01:45 f_0106` gloved forearm + launcher in hand; `t=02:15 f_0136` hand on the crank | — |
| V5-04 | Constable idle + blue hip baton | L2 | NO | — | needs S22 / KF25: no NPC of any kind in the run (KF25 ABSENT) |
| V5-05 | Takedown grapple pose | L2 | NO | — | needs S23 / KF26: no NPC, no grapple (KF26 ABSENT) |
| V6-01 | Escape portal wall outline | L2 | NO | — | needs S12 / KF14: the safe-room wall at `t=01:41 f_0102` shows a blue-white oval sconce, not the green/violet jagged portal (KF14 PARTIAL) |
| V6-02 | Smoke bomb plume | L2 | NO | — | needs S18 / KF20: no smoke throw or plume — KF20 ABSENT |
| V6-03 | Security beams, emitter & node | L2 | NO | — | needs S24 / KF27: no beam, emitter or ceiling node anywhere — KF27 PARTIAL (geometry only) |
| V6-04 | Purple ward + green vine lock | L2 | NO | — | needs S25 / KF28: no ward or vine state — KF28 ABSENT |
| V7-01 | CineCamera startscreen framing | L1 | YES | `t=00:01 f_0002` locked-off wide street, right-aligned menu stack | — |
| V7-02 | Telescope scripted hard cuts | L1 | YES | in `t=00:22 f_0023`, out `t=00:23 f_0024` (cut 00:22.1 / 00:23.2) | — |
| V7-03 | DOF blur behind briefing letter | L1 | PARTIAL | `t=01:40 f_0101` dim out-of-focus floor/crate at the sheet's lower edge | upper backdrop is pure black — no readable blurred brick safe-room |
| V7-04 | Takedown camera lunge & pull-back | L1 | NO | — | needs S23 / KF26: no takedown — KF26 ABSENT |
| V7-05 | Pause darkened blurred backdrop | L1 | PARTIAL | `t=04:38 f_0279` modal identical; `t=00:42 f_0043` second visit | backdrop is a black/ghosted game view with HUD bleed; no blurred scene to judge |

## Audio (AU1–AU6) — 31 rows

| row id | criterion (short) | lane | scorable on this route? | port evidence anchor | absence proof (if not scorable) |
|---|---|---|---|---|---|
| AU1-01 | Startscreen rain bed, zero BGM | L5 | YES | `t=00:01–00:08` (`f_0002`…`f_0008`) startscreen with rain visible | — |
| AU1-02 | Den room tone | L5 | YES | `t=00:13–00:24` Den interior (`f_0014`…`f_0024`) | — |
| AU1-03 | Loading digital silence | L5 | YES | loading windows `t=00:08–00:13`, `t=00:51–00:56`, `t=01:19–01:39` (`f_0090`) | — |
| AU1-04 | Rooftop wind swell in telescope view | L5 | YES | sky cut `t=00:22.1–00:23.2` (`f_0023`) | — |
| AU1-05 | Continuous rain bed across exteriors | L5 | YES | `t=01:43–02:00` street (`f_0106`, `f_0121`), `t=02:02–02:22` rooftops (`f_0122`…`f_0157`) | — |
| AU1-06 | Hearth crackle bed | L5 | NO | — | needs S22 / KF25: no hearth fire exists — KF25 ABSENT |
| AU2-01 | Diegetic gramophone jazz | L5 | NO | — | needs S07 / KF09: no gramophone and no music trigger — KF09 ABSENT |
| AU3-01 | Wooden-plank footsteps | L5 | YES | Den boards `t=00:13–00:24` | — |
| AU3-02 | Wet cobble walk → sprint → crouch | L5 | YES | cobble walk `t=01:45–02:00` (`f_0106`, `f_0110`, `f_0121`) | sprint/crouch phases not visually identifiable; L5 must judge the cadence from the stem |
| AU3-03 | Metal grate steps + vault thud | L5 | PARTIAL | rooftops/ledges `t=02:02–02:22` | no metal-grate catwalk and no vault/drop thud beat observed |
| AU3-04 | Hard-sole marble footsteps | L5 | YES | checkered marble hall `t=02:50–03:10` (`f_0174`, `f_0186`) | — |
| AU3-05 | Slate stair footfalls + ZipWire clack | L5 | PARTIAL | stairs traversed `t=02:30–02:36` and `t=02:51–02:53` | no slate stairwell, no zipwire clack |
| AU4-01 | `PLAY` click | L5 | YES | startscreen → loading transition `t=00:08` | — |
| AU4-02 | Wardrobe browse ticks | L5 | NO | — | needs S04 / KF03: no wardrobe screen — KF03 ABSENT |
| AU4-03 | Ledger parchment & tab clicks | L5 | NO | — | needs S06 / KF07+KF08: no ledger/black-market screen — both ABSENT |
| AU4-04 | Six countdown ticks | L5 | YES | `t=01:11–01:19` countdown 6→1 (`f_0072`, `f_0077`) | — |
| AU4-05 | Pause click, −19 dB duck, quit clicks | L5 | PARTIAL | pause opens `t=00:41–00:42` and `t=04:38` (`f_0043`, `f_0279`) | the run never selects `QUIT TO DESKTOP`, so no quit click and no silence tail |
| AU5-01 | Vintage car double-honk | L5 | NO | — | needs S13 / KF15: no car exists — KF15 PARTIAL (no vehicle) |
| AU5-02 | ZipWire launch + crank ratchet | L5 | YES | launch `t=02:01 f_0122` (airborne, launcher raised); crank `t=02:12–02:19 f_0136` | — |
| AU5-03 | Smoke detonation pop + hiss | L5 | NO | — | needs S18 / KF20: no smoke bomb use — KF20 ABSENT |
| AU5-04 | Vistara shimmer/chime | L5 | NO | — | needs S19 / KF21: the diamond is never equipped — KF21 ABSENT |
| AU5-05 | Ward tripwire chime, whoosh & hum | L5 | NO | — | needs S25 / KF28: no ward — KF28 ABSENT |
| AU5-06 | Barrier shatter + alert sting | L5 | NO | — | needs S26 / KF29: no barrier/alarm — KF29 ABSENT |
| AU5-07 | Key jingle + acquisition chime | L5 | NO | — | needs S22 (`03:17.1`) / KF25: no pickpocket, no key — KF25 ABSENT |
| AU5-08 | Takedown thud + KO groan | L5 | NO | — | needs S23 / KF26: no takedown — KF26 ABSENT |
| AU6-01 | ThiefNisha spawn VO | L5 | YES | spawn window `t=01:41–01:43` (`f_0102`, `f_0103`) | the line itself may be absent (PG-6, no VO path) — presence of the window is what is asserted |
| AU6-02 | Gate guard barks | L5 | NO | — | needs S13 / KF15: no guard exists — KF16 ABSENT |
| AU6-03 | Alert & patrol shouts | L5 | NO | — | needs S14–S16 / KF16+KF17: no guard, no alert — KF16/KF18 ABSENT |
| AU6-04 | Smoke-reaction barks | L5 | NO | — | needs S18 / KF19: no guard, no smoke — KF19 ABSENT |
| AU6-05 | Post-KO line | L5 | NO | — | needs S24 / KF27: no KO, no line — KF26 ABSENT |
| AU6-06 | Distant search & idle barks | L5 | NO | — | needs S17/S20 / KF18+KF23: no guard, no exterior side wing — both ABSENT |

## HUD/UI (UI1–UI5) — 27 rows

| row id | criterion (short) | lane | scorable on this route? | port evidence anchor | absence proof (if not scorable) |
|---|---|---|---|---|---|
| UI1-01 | Startscreen menu stack | L3 | YES | `t=00:01 f_0002` `PLAY/SETTINGS/CREDITS/QUIT`, cursor visible `t=00:49 f_0050` | — |
| UI1-02 | Pause modal + build footer | L3 | YES | `t=04:38 f_0279` four items + `1.5.148559   Novice   275275524`; `t=00:42 f_0043` footer seed `0` | — |
| UI2-01 | Den station prompt chain | L3 | PARTIAL | `t=00:19 f_0020` `[F] PONDER`; `t=00:22 f_0023` `[F] EXIT`; `t=00:59 f_0060` map-table card | `[F] READ LEDGER` never appears (no ledger station); `[F] ENTER MATCH` reticle never appears (the port opens a 2D selector at `t=01:02 f_0063`) |
| UI2-02 | Wardrobe slots, drawer & tooltips | L3 | NO | — | needs S04 / KF03+KF04: no wardrobe overlay — KF03/KF04 ABSENT |
| UI2-03 | ZipWire action prompts | L3 | YES | `t=01:45 f_0106` bottom-right `LAUNCH LMB` / `[HOLD] CRANK RMB`, `[1]` hotbar slot highlighted | — |
| UI2-04 | `CRANK [LMB]` progress ring | L3 | YES | `t=02:15 f_0136` blue/white segmented ring + `[RMB] CRANK` | label differs: centre text is `[RMB] CRANK`, not `CRANK [LMB]` |
| UI2-05 | Blue door prompts (`OPEN`/`LOCK` → `CLOSE`) | L3 | YES | `t=02:51 f_0172` `[F] OPEN` above `[F] [HOLD] LOCK`; flips to `[F] CLOSE` at `t=02:53 f_0174` | prompt set + flip present; the door art is timber, not blue mullion glass |
| UI2-06 | Pickpocket/takedown prompts | L3 | NO | — | needs S22 / KF25: no NPC to prompt against — KF25 ABSENT |
| UI2-07 | Gramophone toggle flip | L3 | NO | — | needs S07 / KF09: no gramophone — KF09 ABSENT |
| UI3-01 | Player card + compass fade-in | L3 | YES | `t=00:13 f_0014` card `The Spider` + portrait + level `1`, compass ticks; `t=01:41 f_0102` compass `S` | card shows `The Spider` level 1, not `Johnny Cipher` level 4 |
| UI3-02 | Loot tracker, hotbar & hidden health | L3 | PARTIAL | `t=01:45 f_0106` `(£) 0`, `Mission: Into the Lion's Den [0/11] (MM:SS left of the 55-minute window)`, `• Steal the Vistara Files`, `[1]`–`[4]`, `TAB MAP`/`MMB`/`[HOLD] PING MENU`, health hidden | tracker string is a different objective from `Steal 4,000 in loot value[0/4,000]`; no `[0/4,000]` counter exists |
| UI3-03 | Health Bar reveal at ~75% | L3 | PARTIAL | `t=02:45 f_0166` ornate blue-framed bar appears, 4 red segments ~1 drained + thin teal sub-bar, trailing drain | reveal is triggered by `LOCK JAMMED!` in `DOOR LOCK (LV 3)`, not by fall damage; no courtyard drop exists |
| UI3-04 | `Guildhall Key` HUD row | L3 | NO | — | needs S22 pickup / KF27: no key, no pickup — KF25 ABSENT |
| UI3-05 | Light Gem exposure states | L3 | YES | `t=01:41 f_0102` bright cream gem; `t=01:59 f_0120` lit gem + red arcs; `t=04:29 f_0270` dark gem | per-sector light tracking semantics left to L3 |
| UI3-06 | Map-table keybind legend | L3 | YES | `t=00:59 f_0060` bottom-right `DIFFICULTY: NOVICE H` / `MODE: SOLO R` / `PREPARE FOR MISSION F` | wording/order differ from `JOIN GAME [F]` / `TOGGLE MODE [R]` / `TOGGLE DIFFICULTY [H]` |
| UI4-01 | `JOURNAL` tab | L3 | NO | — | needs S06 / KF07: no journal — KF07 ABSENT |
| UI4-02 | `BLACK MARKET` tab | L3 | NO | — | needs S06 / KF08: no black market — KF08 ABSENT |
| UI4-03 | Mission prep cards + READY toggle | L3 | YES | `t=01:11 f_0072` LOCATION/MISSION/CONTRACT cards, `[F] READY`; `t=01:16 f_0077` `UNREADY` + `[F] UNREADY · [ESC] BACK` | contract card says `Into the Lion's Den / Target: Vistara Files`, not `Contract Inactive` |
| UI4-04 | Briefing letter (11 lines) | L3 | PARTIAL | `t=01:40 f_0101` parchment + `[SPACE] CONTINUE` + right scrollbar | 5-line body; no `55 minute window` / `magic door … 20 minutes` copy |
| UI4-05 | Loading spinner + gold emblem | L3 | YES | `t=01:29 f_0090` ring + `LOADING...` + gold emblem (+ progress bar text `Raising the rooftops.`) | — |
| UI5-01 | Red player-noise arcs | L3 | YES | `t=01:59 f_0120` twin red arcs flanking a lit gem; `t=04:24 f_0265` arcs present | — |
| UI5-02 | Guard-alert direction pip | L3 | NO | — | needs S15 / KF17: no guard alert, no pip — KF17 PARTIAL (ring only) |
| UI5-03 | Guard alert bar + red eyes | L3 | NO | — | needs S14 / KF16: no guard — KF16 ABSENT |
| UI5-04 | Vistara RED→GREEN guard states | L3 | NO | — | needs S19 / KF21+KF22: no NPC, no scan — both ABSENT |
| UI5-05 | 6 s countdown banner | L3 | YES | `t=01:11 f_0072` `MISSION STARTING IN 6...`, `Mode: Solo`, `Difficulty: Novice` | — |
| UI5-06 | Status icons above the Light Gem | L3 | NO | — | needs S25/S26 / KF28+KF29: no jaw-trap or unconscious icons anywhere — both ABSENT |
| UI5-07 | Sound-ripple + ZipWire gleam | L3 | NO | — | needs S20: no terrace/ripple beat, no gleam — KF23 ABSENT |

## Gameplay (G1–G5) — 25 rows

| row id | criterion (short) | lane | scorable on this route? | port evidence anchor | absence proof (if not scorable) |
|---|---|---|---|---|---|
| G1-01 | Telescope station | L4 | YES | `t=00:19 f_0020` `[F] PONDER` → `t=00:22 f_0023` sky view `[F] EXIT` → back `t=00:23 f_0024` | — |
| G1-02 | Decoration swap + trunk cycle | L4 | NO | — | needs S07 / KF09: no `[F] CHANGE DECORATION`, no trunk props — KF09 ABSENT |
| G1-03 | Mission select + confirmation modal | L4 | YES | `t=00:59 f_0060` 3D table + card; `t=01:06 f_0067` `Join Mission with these settings? / Difficulty: Novice / Mode: Solo / [SPACE] PREPARE FOR MISSION / [ESC] CANCEL` | modal reached through a 2D selector (`t=01:02 f_0063`), not the token reticle |
| G1-04 | Vintage car interact | L4 | NO | — | needs S13 / KF15: no car — KF15 PARTIAL |
| G1-05 | Safe-room lantern toggle | L4 | NO | — | needs S12 / KF14: the safe room at `t=01:41 f_0102` has no lantern station — KF14 PARTIAL |
| G1-06 | Pickpocket `Guildhall Key` | L4 | NO | — | needs S22 / KF25: no NPC — KF25 ABSENT |
| G2-01 | Den hub walk | L4 | YES | `t=00:13–00:24` free walk across floorboards (`f_0014`…`f_0024`) | — |
| G2-02 | Alley drop → sprint → crouch | L4 | PARTIAL | `t=01:43–02:00` street walk + curb step-downs (`f_0106`, `f_0110`, `f_0120`) | no drop/vault-in off a catwalk, no verifiable sprint or crouch phase, no car |
| G2-03 | ZipWire crank ascent + roofline | L4 | PARTIAL | launch `t=02:01 f_0122`; crank rings `t=02:12–02:19 f_0136`; roofline `t=02:02–02:15` | no anchored multi-strand cable, no winch/gear housing, no roof-ridge arrival beat |
| G2-04 | Cable crossing + courtyard descent | L4 | NO | — | needs S17 / KF18: no cable crossing, no gear-plate landing, no courtyard drop — KF18 ABSENT |
| G2-05 | Slate staircase ascent | L4 | PARTIAL | stair runs `t=02:30–02:36` and `t=02:51–02:53` (`f_0174`) | stairs are timber/stone interior flights, not the plain slate run to an upper gallery; no alarm context |
| G3-01 | ZipWire `[1]` equip + 1st launch | L4 | PARTIAL | `t=01:45 f_0106` equipped + `LAUNCH LMB`; `t=02:01 f_0122` airborne with the launcher raised, roofs below | no gate-arch shot, no foliage landing beside a chest, and no non-damaging-landing evidence (health bar is still hidden at 02:01) |
| G3-02 | Smoke bomb throw + plume cover | L4 | NO | — | needs S18 / KF19+KF20: slot `[2]` is never selected and no canister is thrown — KF19/KF20 ABSENT |
| G3-03 | Vistara Diamond scan pulse | L4 | NO | — | needs S19 / KF21: `[4]` is never equipped, no scan pulse — KF21 ABSENT |
| G3-04 | Tool swap back to `[1]` | L4 | NO | — | needs S19 / KF22: no `[4]→[1]` swap beat — KF22 ABSENT |
| G4-01 | Gate guard alert escalation | L4 | NO | — | needs S13–S14 / KF16: no guard — KF16 ABSENT |
| G4-02 | Roofline patrol mutter | L4 | NO | — | needs S16 (no keyframe) / KF18 context: no guard on the roofline — KF18 ABSENT |
| G4-03 | Distant search & idle barks | L4 | NO | — | needs S17/S20: no guard, no terrace — KF23 ABSENT |
| G4-04 | Guard takedown + KO | L4 | NO | — | needs S23 / KF26: no NPC — KF26 ABSENT |
| G4-05 | Distant green guard silhouette | L4 | NO | — | needs S17 / KF18: no guard highlight — KF18 ABSENT |
| G5-01 | Mission flow: select → ready → countdown → load | L4 | YES | `t=00:56–01:02` table (`f_0060`) → `t=01:06` modal (`f_0067`) → `t=01:11` prep (`f_0072`) → `t=01:21` loading (`f_0082`) | `[F] READY`→`UNREADY` reached `t=01:16 f_0077`; the port also re-enters the Den via `RETURN TO THIEF'S DEN` at 00:42 |
| G5-02 | First fall damage | L4 | PARTIAL | `t=02:45 f_0166` health bar reveal + red drain segment; `t=04:29 f_0270` bar at one segment | damage observed is the `LOCK JAMMED!` penalty in `DOOR LOCK (LV 3)`; no courtyard drop, so fall height/regen cannot be scored |
| G5-03 | Beam tripwire → ward lockdown | L4 | NO | — | needs S25 / KF28: no beams, no ward — KF28 ABSENT |
| G5-04 | Ward shatter → crimson alarm | L4 | NO | — | needs S26 / KF29: no ward, no alarm — KF29 ABSENT |
| G5-05 | Pause → quit flow | L4 | PARTIAL | `t=00:42 f_0043` and `t=04:38 f_0279` pause modal open, cursor on `RETURN TO THIEF'S DEN` (`f_0043`) / `QUIT TO DESKTOP` (`f_0279`) | the run ends on the modal at 04:41 — no selection, no teardown, no digital-silence tail |

## Tally

| Pillar | rows | YES | PARTIAL | NO |
|---|---|---|---|---|
| Visual (V1–V7) | 37 | 15 | 8 | 14 |
| Audio (AU1–AU6) | 31 | 12 | 3 | 16 |
| HUD/UI (UI1–UI5) | 27 | 12 | 4 | 11 |
| Gameplay (G1–G5) | 25 | 4 | 6 | 15 |
| **Total** | **120** | **43** | **21** | **56** |

Row-accounting check: 15+8+14 = 37; 12+3+16 = 31; 12+4+11 = 27; 4+6+15 = 25; 43+21+56 = 120.

Per-lane scorable load (what each scorer can actually spend time on):

| Lane | rows | YES | PARTIAL | NO |
|---|---|---|---|---|
| L1 (V1, V2, V7) | 17 | 8 | 5 | 4 |
| L2 (V3, V4, V5, V6) | 20 | 7 | 3 | 10 |
| L3 (UI*) | 27 | 12 | 4 | 11 |
| L4 (G*) | 25 | 4 | 6 | 15 |
| L5 (AU*) | 31 | 12 | 3 | 16 |

Notes for the final scorer (all frame-backed, see `kf_presence.md`):

1. **The route is front-end + Den-east + a Guildhall interior, with no NPCs.** The single biggest
   scoring constraint: 56 of 120 rows are unreachable because the port run never shows a guard,
   constable, car, gate arch, parlor, foyer lockdown or alarm stairwell. That removes essentially all of
   `AU5-03..AU5-08`, `AU6-02..AU6-06`, `G4-*`, `V6-02..V6-04` and `UI5-02..UI5-06`.
2. **The port inserts mechanics the official clip has no keyframe for** (a circular `DOOR LOCK (LV n)`
   tumbler minigame at LV 2/3/3/4, a `Cat Statue` loot label, a 2D `MAP TABLE — CONTRACT SELECTOR`,
   a 16-contract list, a lock-jam damage penalty). Score the official rows against the *official*
   criteria; do not credit these as the row's subject unless the row names them.
3. **The mission binding differs**: HUD tracker `Into the Lion's Den [0/11]`, objective
   `Steal the Vistara Files`, player card `The Spider` level `1`, while the prep screen still shows
   `Cleanout Heist / Time Limit: 55 minutes` for `CONSTABLES' GUILDHALL`.
4. **Two pause visits** (00:42 over the roof, 04:38 over the black hall) both show the modal 1:1; the
   footer seed differs between them (`0` vs `275275524`).
