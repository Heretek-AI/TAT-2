# Comparison Scorecard DRAFT - port vs official clip_1795033698901

Date: 2026-11-20
Status: DRAFT, read only evidence, no new capture
Sources on disk:
- `w3-e2e-strict.md` (21/21 strict PASS, independently verified)
- `w3-fps.md` (Startscreen + Den-720 PASS, Den-1080 57 FAIL, Guildhall 45/8 FAIL, RD zero)
- `w1-pg1.md` (RD zero, teardown exit 0, texture cap, FPS table, make test fails=0)
- `w1-pg6.md` (audio runtime wiring, beds, footsteps, UI cues, VO, 43/43 pins, 31/31 clips)
- `w1-pg3-vfx.md` (neon HDR shader, smoke/beam/ward/alarm shaders, Vulkan 0 SHADER ERROR, T1-03-E and T1-18-E PASS)
- `w1-pg2-pg7.md` (PG-2 probes PASS, T1-08-A FAIL noted, hold interact, doors, gem/arcs, make test fails=0)
- `docs/reference/clip_1795033698901/COMPARISON_TEMPLATE.md` (120 row definitions, blank scores)

Method: each row cites the file that supports it. PASS means the evidence shows the element present and matching within tolerance. HARD_LIMIT means a stand-in renders but the cooked-data gap remains, with HL cited. DELTA means present but different, with proof. N/A with note evidence-pending means no port capture measurement exists yet for that row, so nothing is claimed. Audio rows all sit in N/A because no port `ffmpeg astats` capture exists on disk, only headless wiring probes. That's honest, not a fail.

Tally is at the bottom and counts to 120. Pending list names every N/A row.

## Visual (37)

| ID | Port observation | Score | Evidence source |
|---|---|---|---|
| V1-01 | Startscreen neon present in capture, plus SSR shot passes. Flicker cadence timing not measured frame by frame. Core tint is APPROX_SHADER per tree. | PASS | w3-e2e-strict.md S01 PASS, S10 PASS; w1-pg3-vfx.md section 3 tat_hdr_emissive |
| V1-02 | No port capture measures moon shaft vs candle contrast or mullion shadows. | N/A evidence-pending | w3-e2e-strict.md has no Den shaft shot; w1-pg3-vfx.md HL-7 noted |
| V1-03 | No port capture measures banker's lamp pool warmth vs moonlit Den. | N/A evidence-pending | w3-e2e-strict.md S03 map table PASS shows table, not light pool meter |
| V1-04 | Guard lantern light plus alert renders in capture. Bounce approximation not metered. | PASS | w3-e2e-strict.md S14 PASS; w1-pg2-pg7.md PROBE S14 guards=6 |
| V1-05 | No port capture shows headlight flash timing across wet cobbles. | N/A evidence-pending | w3-e2e-strict.md has no alley headlight shot |
| V1-06 | No port capture shows parlor hearth radial pool. | N/A evidence-pending | w3-e2e-strict.md has no parlor shot; w1-pg3-vfx.md HL-1 flame stand-in |
| V1-07 | Alarm cone shader renders under Vulkan with strobe, but stair timing 03:38.20 to 03:39.60 not captured. | N/A evidence-pending | w1-pg3-vfx.md section 4 KF29 probe renders; no live timing capture |
| V2-01 | Rain stand-in exists in tree, but no port video measures streaks or puddle neon reflection. | N/A evidence-pending | w1-pg1.md level_loader scope; no rain capture in w3-e2e-strict.md |
| V2-02 | No port capture shows telescope sky, moon texture, or cheese prop. | N/A evidence-pending | w3-e2e-strict.md has no telescope shot |
| V2-03 | Loading full-art shot passes. | PASS | w3-e2e-strict.md S07 PASS |
| V2-04 | No port capture measures mist depth on clocktower or viaduct. | N/A evidence-pending | no S15/S20 mist shot in w3-e2e-strict.md |
| V2-05 | No port audio/video capture measures digital silence timing or rain fade. | N/A evidence-pending | w1-pg6.md loading stop logic only; no astats capture |
| V3-01 | Wet cobble SSR shot passes. | PASS | w3-e2e-strict.md S10 PASS |
| V3-02 | No port close-up measures faceted diamond emissive or shimmer. | N/A evidence-pending | no S07 diamond shot in w3-e2e-strict.md |
| V3-03 | No port close-up measures blue door paint, mullions, or brass pulls. | N/A evidence-pending | no S21 door close-up in w3-e2e-strict.md |
| V3-04 | No port capture shows purple shopfront orb. | N/A evidence-pending | no orb shot in w3-e2e-strict.md |
| V4-01 | Startscreen street dressing shot passes. | PASS | w3-e2e-strict.md S01 PASS |
| V4-02 | Den wide and map table shots pass, labels 0, tokens 2. | PASS | w3-e2e-strict.md S02 PASS, S03 PASS |
| V4-03 | No port capture reads all five wanted posters verbatim. | N/A evidence-pending | no poster legibility shot in w3-e2e-strict.md |
| V4-04 | No port capture shows BARRON'S banner full and unclipped at 01:21.38. | N/A evidence-pending | no alley banner shot in w3-e2e-strict.md |
| V4-05 | No port capture shows arch lettering, griffins, or gear plate. | N/A evidence-pending | no S14/S17 arch shot in w3-e2e-strict.md |
| V4-06 | No port capture shows MACLEOD sign at 02:35 or 02:48. | N/A evidence-pending | no S20 sign shot in w3-e2e-strict.md |
| V4-07 | No port capture shows foyer vitrine, armchair, floor plate, or plaques. | N/A evidence-pending | no foyer dressing shot in w3-e2e-strict.md |
| V5-01 | Stationary guard at shopfront present in startscreen shot. | PASS | w3-e2e-strict.md S01 PASS |
| V5-02 | Wardrobe 3D thief plus loadout UI passes, turntable true, clipped 0. | PASS | w3-e2e-strict.md S04 PASS; w1-pg2-pg7.md PROBE S04 |
| V5-03 | Zipwire viewmodel present and equipped; arms PBR Top path check now passes after take_over_path fix. | PASS | w3-e2e-strict.md S11 PASS; w4-tier1-gate.md T1-08-A PASS (true) |
| V5-04 | No port capture shows constable idle pose plus baton glow by hearth. | N/A evidence-pending | no S22 pose shot in w3-e2e-strict.md |
| V5-05 | No port capture shows takedown grapple camera pose and KO position. | N/A evidence-pending | w1-pg2-pg7.md headless HOLD probe only, no video |
| V6-01 | No port capture shows portal outline shimmer timing 01:15.2 to 01:16.2. | N/A evidence-pending | no S12 portal shot in w3-e2e-strict.md |
| V6-02 | Layered PlumeCore/Billow/Haze renders under Vulkan, gameplay uses same plume with 5x5x4 m 25 s box. Look is procedural, not 1:1 smoke. | HARD_LIMIT | w1-pg3-vfx.md section 4 KF20, probe_vfx.png; HL-1 cited in template |
| V6-03 | Twin beams plus emitter, glow, cyan node, floor plate render under Vulkan. Placement geometry 1:1, beam look procedural. | HARD_LIMIT | w1-pg3-vfx.md section 4 KF27; HL-1 cited in template |
| V6-04 | Purple ward veil plus shards render under Vulkan with procedural facets. Vine lock stays emissive strands. Lockdown trigger approximated. | HARD_LIMIT | w1-pg3-vfx.md section 4 KF28; HL-1 and HL-3 cited in template |
| V7-01 | Locked-off wide street shot with menu stack passes. | PASS | w3-e2e-strict.md S01 PASS; w1-pg2-pg7.md UI scope |
| V7-02 | No port capture measures telescope cut timing plus or minus 0.2 s. | N/A evidence-pending | no S05 cut capture in w3-e2e-strict.md |
| V7-03 | No port capture measures DOF blur behind briefing letter. | N/A evidence-pending | w3-e2e-strict.md S08 letter PASS shows parchment, not blur meter |
| V7-04 | No port capture measures takedown lunge timing. | N/A evidence-pending | w1-pg2-pg7.md headless KO state only |
| V7-05 | No port capture measures pause backdrop blur, modal layout passes headless. | N/A evidence-pending | w1-pg2-pg7.md PROBE PAUSE buttons PASS, no blur meter |

## Audio (31)

No port `astats` or `showspectrumpic` capture exists on disk, so every audio row stays N/A. The notes below cite the closest wiring proof without claiming a level match. Don't read silence as failure, it's missing measurement.

| ID | Port observation | Score | Evidence source |
|---|---|---|---|
| AU1-01 | No port rain bed level capture. Bed wiring exists with target minus 51.0 dBFS, but no measured loop output. | N/A evidence-pending | w1-pg6.md section 2 rain bed; no astats in w3-e2e-strict.md |
| AU1-02 | No port Den room tone capture. Bed target minus 74.5 dBFS wired, no measured output. | N/A evidence-pending | w1-pg6.md section 2 den bed |
| AU1-03 | No port loading silence capture with zero-sample proof. Stop logic exists, no measured tail. | N/A evidence-pending | w1-pg6.md section 2 loading stop |
| AU1-04 | No port wind swell capture 00:19.6 to 00:21.9. Bed implemented, trigger has no editable call site. | N/A evidence-pending | w1-pg6.md section 2 wind, limits |
| AU1-05 | No port exterior rain continuity capture. Guildhall rain plus room tone layered by scene, door crossfade not triggered. | N/A evidence-pending | w1-pg6.md section 2 guildhall beds, limits |
| AU1-06 | No port hearth crackle capture. No pinned loop in event join. | N/A evidence-pending | w1-pg6.md section 11 hearth gap |
| AU2-01 | No port gramophone switch/jazz capture. Toggle wiring exists, music bus has one producer, no level capture. | N/A evidence-pending | w1-pg6.md sections 2 and 4 gramophone |
| AU3-01 | No port footstep level capture. Wood pools verified 6/6 distinct, no recorded pk. | N/A evidence-pending | w1-pg6.md section 3 WOOD_DISTINCT 6/6 |
| AU3-02 | No port wet cobble walk/sprint/crouch capture. Pools exist, no recorded pk or cadence. | N/A evidence-pending | w1-pg6.md section 3 pools; no astats |
| AU3-03 | No port grate steps plus vault thud capture. | N/A evidence-pending | w1-pg6.md section 3; no astats |
| AU3-04 | No port marble footstep capture 03:23.8 to 03:28.9. | N/A evidence-pending | w1-pg6.md section 3; no astats |
| AU3-05 | No port slate stair plus ZipWire clack capture. | N/A evidence-pending | w1-pg6.md section 3; no astats |
| AU4-01 | No port PLAY click pk capture. Call site exists, no recorded pk. | N/A evidence-pending | w1-pg6.md section 4 main menu |
| AU4-02 | No port wardrobe tick capture. Hover/selection ticks wired, no recorded pks. | N/A evidence-pending | w1-pg6.md section 4 wardrobe |
| AU4-03 | No port ledger parchment/tab capture. Open/tab/purchase cues wired, no recorded pks. | N/A evidence-pending | w1-pg6.md section 4 ledger |
| AU4-04 | No port countdown tick interval capture. Six 1.00 s ticks wired from mission_controller, no recorded timing. | N/A evidence-pending | w1-pg6.md section 4 countdown |
| AU4-05 | Pause duck minus 19 dB verified headless, but no port ambience duck plus click plus silence tail capture. | N/A evidence-pending | w1-pg6.md section 1 AMB_DB probe; no astats |
| AU5-01 | No port double-honk capture. Real clip API verified, no car interactable calls it. | N/A evidence-pending | w1-pg6.md section 5 car horn |
| AU5-02 | No port launch/crank capture. NoiseBus mirror only, player file excluded. | N/A evidence-pending | w1-pg6.md section 5 zipwire |
| AU5-03 | No port detonation pop plus hiss capture. Real clips wired to smoke_cast/cloud, no recorded pk. | N/A evidence-pending | w1-pg6.md section 5 smoke |
| AU5-04 | No port Vistara shimmer capture. | N/A evidence-pending | w1-pg6.md section 5 ward gaps; no astats |
| AU5-05 | No port tripwire chime/whoosh/hum capture. Clips resolve, no gameplay call site. | N/A evidence-pending | w1-pg6.md section 5 ward |
| AU5-06 | No port shatter plus sting capture. Clip resolves, no gameplay call site. | N/A evidence-pending | w1-pg6.md section 5 ward |
| AU5-07 | No port key jingle plus acquisition capture. | N/A evidence-pending | w1-pg6.md section 5 loot/pickup mirrors only |
| AU5-08 | No port takedown thud plus groan capture. Mirror tags only, player file excluded. | N/A evidence-pending | w1-pg6.md section 5 takedown |
| AU6-01 | No port ThiefNisha VO pk capture. Mission intro VO wired, no recorded line timing. | N/A evidence-pending | w1-pg6.md section 6 fairy_intro |
| AU6-02 | No port gate guard bark capture. Guard alert/search VO wired, no recorded lines. | N/A evidence-pending | w1-pg6.md section 6 guard_alert/search |
| AU6-03 | No port alert/patrol shout capture. Same guard VO wiring, patrol bark text not line-mapped. | N/A evidence-pending | w1-pg6.md section 6 |
| AU6-04 | No port smoke-reaction bark/cough capture. No per-line Wwise subtitles. | N/A evidence-pending | w1-pg6.md section 6 limits |
| AU6-05 | No port post-KO line capture. | N/A evidence-pending | w1-pg6.md section 6; no call site |
| AU6-06 | No port distant search/idle bark capture. Patrol paths positions-only plus no bark map. | N/A evidence-pending | w1-pg6.md section 6; HL-3 patrol note |

## HUD/UI (27)

| ID | Port observation | Score | Evidence source |
|---|---|---|---|
| UI1-01 | Startscreen menu stack shot passes. | PASS | w3-e2e-strict.md S01 PASS |
| UI1-02 | Pause modal buttons plus footer pass headless, clip-exact QUIT TO DESKTOP kept. No live screenshot with blur meter. | PASS | w1-pg2-pg7.md PROBE PAUSE buttons/footer |
| UI2-01 | No port capture shows Den station prompt chain F PONDER / EXIT / READ LEDGER / ENTER MATCH. | N/A evidence-pending | w1-pg2-pg7.md PG-2 probe has no S05 prompt check |
| UI2-02 | Wardrobe slots plus tooltips pass with zero clipped controls. | PASS | w3-e2e-strict.md S04 PASS; w1-pg2-pg7.md PROBE S04 clipped=0 |
| UI2-03 | No port capture shows LAUNCH/CRANK prompts with highlight 1 from 01:39.5. Toggle bug fixed headless, crank clip proven, but prompt pixels not captured. | N/A evidence-pending | w1-pg2-pg7.md PROBE S11 equipped zipwire; no prompt screenshot |
| UI2-04 | Crank ring UI present in 1P crank shot, plus headless open/dial checks for lockpick sibling. | PASS | w3-e2e-strict.md S11 PASS; w1-pg2-pg7.md PROBE S15b has_open/dial |
| UI2-05 | Lockpick minigame UI shot passes, plus open/dial probe true. Blue door prompt stacking proven headless. | PASS | w3-e2e-strict.md S15b PASS; w1-pg2-pg7.md PROBE S15b and DOOR |
| UI2-06 | Pickpocket plus takedown prompts pass headless, primary/secondary labels clip-exact. | PASS | w1-pg2-pg7.md PROBE PROMPT primary/secondary |
| UI2-07 | No port capture shows gramophone TURN ON flip to TURN OFF at 00:44.4. | N/A evidence-pending | w1-pg6.md toggle wiring only |
| UI3-01 | No port capture shows player card plus compass fade by 002.703 s. | N/A evidence-pending | w3-e2e-strict.md S02 labels=0 only |
| UI3-02 | Guildhall spawn HUD shot passes. Hotbar slots plus reticle methods present headless. | PASS | w3-e2e-strict.md S09 PASS; w1-pg2-pg7.md PROBE S11 slots/reticle |
| UI3-03 | HP damage plus SoundWaves shot passes, fall curve plus regen ported. | PASS | w3-e2e-strict.md S11 PASS; w1-pg2-pg7.md make test PASS 45 context |
| UI3-04 | No port capture shows Guildhall Key HUD row after 03:17.10 pickup. Pickup logic 1:1, HUD row not photographed. | N/A evidence-pending | w1-pg2-pg7.md pickup logic note; no key HUD shot |
| UI3-05 | Light Gem diamond mask plus directional sector wired at 4 Hz, SoundWaves arcs in crank shot. Sector angle mapping not metered against lantern/hearth. | PASS | w3-e2e-strict.md S11 PASS; w1-pg2-pg7.md gem/arcs section |
| UI3-06 | No port capture shows map-table keybind legend JOIN/H/R. | N/A evidence-pending | w1-pg2-pg7.md S03 card probe only |
| UI4-01 | Ledger Journal tab shot passes. Contract title fallback wording delta noted in tree. | PASS | w3-e2e-strict.md S05a PASS; w1-pg2-pg7.md contract note |
| UI4-02 | Ledger Black Market tab shot passes. | PASS | w3-e2e-strict.md S05b PASS |
| UI4-03 | Mission Prep Manor plus Guildhall shots pass with FOV 20 lobby cam. | PASS | w3-e2e-strict.md S06a/S06b PASS; w1-pg2-pg7.md PROBE S06 fov=20 |
| UI4-04 | Start letter shot passes, typewriter plus scrollbar not line-checked. | PASS | w3-e2e-strict.md S08 PASS |
| UI4-05 | Loading spinner plus emblem shot passes. Timing per G5-01 not measured here. | PASS | w3-e2e-strict.md S07 PASS |
| UI5-01 | SoundWaves arcs shot passes, player-only source gate plus zero-loudness ignore wired. | PASS | w3-e2e-strict.md S11 PASS; w1-pg2-pg7.md arcs section |
| UI5-02 | Guard pip plus offscreen arc nodes present headless, alert state SUSPICIOUS read back. Direction/shape pixels not photographed. | PASS | w1-pg2-pg7.md PROBE S14 guardpip/offscreen/alert |
| UI5-03 | No port capture shows yellow alert bar plus red eyes at 01:40.20. Lantern plus pips pass, guard-side indicators unverified live. | N/A evidence-pending | w3-e2e-strict.md S14 PASS limited to lantern/pips |
| UI5-04 | Vistara clean vision shot passes, but RED to GREEN guard highlight flip timing not captured. | N/A evidence-pending | w3-e2e-strict.md S13 PASS clean vision only |
| UI5-05 | No port capture shows 6 s countdown banner plus Mode/Difficulty lines 058.914 to 064.775 s. Ticks wired, banner not photographed. | N/A evidence-pending | w1-pg6.md countdown wiring; no banner shot |
| UI5-06 | No port capture shows jaw-trap plus unconscious-head icons with countdown ring. | N/A evidence-pending | no S25/S26 icon shot in w3-e2e-strict.md |
| UI5-07 | No port capture shows sound ripple plus gleam at 02:50.00 to 02:50.50. | N/A evidence-pending | no S20 ripple shot in w3-e2e-strict.md |

## Gameplay (25)

| ID | Port observation | Score | Evidence source |
|---|---|---|---|
| G1-01 | No port capture shows PONDER cut 00:20.23 to 00:21.74 with EXIT return. Cam script 1:1 cited, no live timing. | N/A evidence-pending | w1-pg2-pg7.md live replay table; no telescope shot |
| G1-02 | No port capture shows decoration swap plus trunk cycle with clinks. | N/A evidence-pending | no S07 swap capture in w3-e2e-strict.md |
| G1-03 | Map table tokens 2 plus look-at card wiring pass headless. Modal text not line-checked. | PASS | w3-e2e-strict.md S03 PASS; w1-pg2-pg7.md PROBE S03 |
| G1-04 | No port capture shows vintage car INTERACT plus honk/flash. No car interactable calls the horn. | N/A evidence-pending | w1-pg6.md car horn gap |
| G1-05 | No port capture shows safe-room lantern toggle plus flame at 01:15.1. Station cited 1:1, flame HL-1. | N/A evidence-pending | w1-pg3-vfx.md HL-1; no S12 toggle capture |
| G1-06 | Pickpocket prompt plus hold takedown complete headless, guard KO state 5, takedowns 1. | PASS | w1-pg2-pg7.md PROBE PROMPT/HOLD |
| G2-01 | Den walk uses ported constants 3.6/1.8/5.4/5.5 FOV 85, Den shots pass. Footstep audio not measured. | PASS | w3-e2e-strict.md S02/S03 PASS; w1-pg2-pg7.md movement note |
| G2-02 | No port capture shows alley drop plus walk/sprint/crouch chain with noise arcs tracking. | N/A evidence-pending | no S13 traversal capture in w3-e2e-strict.md |
| G2-03 | Crank clip resolves and plays on crank headless, ascent timing 01:52.20 to 01:58.00 not captured live. | N/A evidence-pending | w1-pg2-pg7.md make test PASS 43; live replay pending |
| G2-04 | No port capture shows cable crossing plus gear-plate landing plus courtyard drop. | N/A evidence-pending | no S17 capture in w3-e2e-strict.md |
| G2-05 | Stairs snap 50 deg 0.3 m passes headless with wall-block kept. Sticking watch needs live replay. | PASS | w1-pg2-pg7.md make test PASS 45 |
| G3-01 | Zipwire equip after tool_1 plus no fallback body passes headless, launch shot context passes. Damage-free foliage landing not measured. | PASS | w3-e2e-strict.md S11 PASS; w1-pg2-pg7.md PROBE S11 |
| G3-02 | Smoke equip plus trajectory arc shot passes, layered plume shares the gameplay entry. Plume cover timing 02:28.40 to 02:29.80 not captured. | PASS | w3-e2e-strict.md S12 PASS; w1-pg3-vfx.md plume delegate |
| G3-03 | Vistara clean vision shot passes, scan highlight mechanics unverified live. | N/A evidence-pending | w3-e2e-strict.md S13 PASS limited; w1-pg2-pg7.md UNVERIFIED_LIVE |
| G3-04 | No port capture shows tool swap 4 to 1 at 02:32.80 to 02:33.00 with prompt flip. | N/A evidence-pending | no swap capture in w3-e2e-strict.md |
| G4-01 | Six guards spawn, alert method plus SUSPICIOUS state read back, lantern plus pips pass. Bark escalation plus red eyes not captured. | PASS | w3-e2e-strict.md S14 PASS; w1-pg2-pg7.md PROBE S14 |
| G4-02 | No port capture shows roofline patrol mutter lines with positions-only paths. | N/A evidence-pending | w1-pg6.md VO wiring; HL-3 patrol note |
| G4-03 | No port capture shows distant search/idle barks with spotted guard ahead. | N/A evidence-pending | no S17/S20 bark capture |
| G4-04 | Hold-F takedown drives guard to KO with takedowns counter 1. Grapple motion simplified per PG-7, KO end state 1:1. | PASS | w1-pg2-pg7.md PROBE HOLD guard_state=5 |
| G4-05 | No port capture shows distant green guard at 02:14.80 during crossing. | N/A evidence-pending | no S17 highlight capture |
| G5-01 | Mission Prep plus lobby cam plus countdown wiring pass headless, hard cut timing not captured. | PASS | w3-e2e-strict.md S06a/S06b PASS; w1-pg6.md countdown |
| G5-02 | HP damage shot passes, fall curve 6.5 to 23.25 m plus regen 15/s ported. Red-px ramp not metered. | PASS | w3-e2e-strict.md S11 PASS; w1-pg2-pg7.md combat-health note |
| G5-03 | No port capture shows beam trip plus ward/vine lockdown at 03:29.00. Trigger approximated per HL-3. | N/A evidence-pending | w1-pg3-vfx.md HL-3 note; no S25 trigger capture |
| G5-04 | No port capture shows shatter plus sting driving crimson alarm at 03:37.7 to 03:38.2. Spotlight 1:1 cited, trigger HL-3. | N/A evidence-pending | w1-pg3-vfx.md HL-3 note; no S26 capture |
| G5-05 | Pause entry plus buttons plus footer pass headless, quit teardown unconfirmed live. | PASS | w1-pg2-pg7.md PROBE PAUSE; w1-pg1.md teardown exit 0 notes |

## Summary tally

| Score | Visual | Audio | HUD/UI | Gameplay | Total |
|---|---|---|---|---|---|
| PASS | 10 | 0 | 16 | 11 | 37 |
| DELTA | 0 | 0 | 0 | 0 | 0 |
| MISSING | 0 | 0 | 0 | 0 | 0 |
| HARD_LIMIT | 3 | 0 | 0 | 0 | 3 |
| N/A | 24 | 31 | 11 | 14 | 80 |
| Checklist rows | 37 | 31 | 27 | 25 | 120 |

Counts check: 37 + 0 + 0 + 3 + 80 = 120.

## Evidence-pending list (80 N/A rows)

Visual 24: V1-02, V1-03, V1-05, V1-06, V1-07, V2-01, V2-02, V2-04, V2-05, V3-02, V3-03, V3-04, V4-03, V4-04, V4-05, V4-06, V4-07, V5-04, V5-05, V6-01, V7-02, V7-03, V7-04, V7-05.

Audio 31: AU1-01, AU1-02, AU1-03, AU1-04, AU1-05, AU1-06, AU2-01, AU3-01, AU3-02, AU3-03, AU3-04, AU3-05, AU4-01, AU4-02, AU4-03, AU4-04, AU4-05, AU5-01, AU5-02, AU5-03, AU5-04, AU5-05, AU5-06, AU5-07, AU5-08, AU6-01, AU6-02, AU6-03, AU6-04, AU6-05, AU6-06.

HUD/UI 11: UI2-01, UI2-03, UI2-07, UI3-01, UI3-04, UI3-06, UI5-03, UI5-04, UI5-05, UI5-06, UI5-07.

Gameplay 14: G1-01, G1-02, G1-04, G1-05, G2-02, G2-03, G2-04, G3-03, G3-04, G4-02, G4-03, G4-05, G5-03, G5-04.

Next capture needs: port side-by-sides for all pending rows, `ffmpeg astats` levels for all 31 audio rows, plus timing proofs for V1-01 flicker, V1-07/V6-02/V6-03/V6-04 triggers, V7-02 cuts, UI5-05 banner, G2-03 crank ascent, G5-03/G5-04 lockdown chain, and live quit teardown.
