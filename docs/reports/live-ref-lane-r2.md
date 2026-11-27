# Live-reference lane R2 — part 1, 300–600 s

**Status:** lane report only. It records what is visible in one 300 s window of the live shipped-build
capture and nothing else. It does **not** score the port, does not touch
`docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`, `KEYFRAME_INDEX.md`,
`docs/reference/clip_1795033698901/row_route_matrix.md`, the game or any build file, and it assigns no
`PASS` / `DELTA` / `MISSING` / `HARD_LIMIT` token. No commit.

**Lane window:** part 1, proxy seconds **300–600** (the last frame is 599). Plan: `docs/reports/live-ref-review-plan.md` §2.2.
**Frame convention:** `~/Videos/tat2_ref_20261127/review/r2_<id>_<t>.png`, `t` = whole proxy seconds.

---

## 1. Method and claim boundary

### 1.1 Inputs actually read

| Input | Use |
|---|---|
| `~/Videos/tat2_ref_20261127/review/route_lossless_1fps.mp4` | the 480×270 / 1 fps proxy; **600** packets, PTS 0…599, duration 600.000 s, 11,104,587 B. Every timestamp in this report is a proxy timestamp. |
| `~/Videos/tat2_ref_20261127/route_lossless.mkv` | part 1, 2560×1440 `gbrp` 60/1, 600.000 s; decoded **only** for ≈25 candidate full-resolution frames plus two numeric checks. Never copied. |
| `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` | official S01–S27 spans, KF01–KF30 subjects and strings |
| `docs/reference/clip_1795033698901/clean/*.jpg` | KF15, KF16, KF18, KF24, KF25, KF27, KF28, KF29, KF30 opened for the comparisons below |
| `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` / `COMPARISON_TEMPLATE.md` §2 | the 120 row ids and their short criteria |
| `docs/reference/clip_1795033698901/row_route_matrix.md` | row observability language |
| `docs/reports/p0b-live-capture.md` §5 (Steps 11–12), `docs/reports/p0b-route-rescore.md` | route order, pose definitions, status vocabulary |
| `docs/reports/live-ref-review-plan.md` | segment assignment, vocabulary, row rules |

Machine: CPU only. No Godot, Vulkan, Xvfb, Steam or game build was launched; one ffmpeg at a time.

### 1.2 Proxy ↔ source mapping (measured, not assumed)

* Proxy frame *N* ≈ source **t = N + 0.4 s**. Measured by decoding 581.5–584.4 s at 10 fps and matching
  every sample to proxy frame 583: best RMSE **0.0081 at source 583.4 s** (next best 583.5 s, 0.0097).
  A 1 fps proxy cannot do better than ±0.5 s; all proxy times below carry that quantisation.
* Single-frame input seek is **coarser than the proxy**: `ffmpeg -ss 583 -i route_lossless.mkv
  -frames:v 1` returned an image that matches source **583.0 s** (RMSE 0.034 at 10 fps sampling), not
  the proxy's 583.4 s. The lossless capture has a ~250-frame GOP, so a one-frame request can stop on
  the seek point instead of the requested time. At 411 s (player on a zipwire) that 0.4 s is a
  completely different picture — this is why one early probe of mine did not match the proxy.
* Therefore: full-resolution identity/text checks used `-ss (t-2) -i SRC -t 5 -vf fps=1`, which yields
  files numbered 1…5 for *t-2 … t+2*, and **file `_3` is `t`**. Each one was re-downscaled to 480×270 and
  checked against the proxy frame with `compare -metric RMSE` (0.007–0.012 for every frame quoted below).
  A verifier who re-runs the plan's §5.3 one-frame recipe on the original should expect a ≈0.4 s
  difference and compare content, not hashes, or use the 5-frame window method.

### 1.3 What the window actually is (read this before the tables)

The window is **not** the official Cleanout Heist. The shipped HUD reads, in every frame:

```
(£) 0
Mission: Steal the components of the Staff of Edinburgh [0/3]
  Steal Gem of Arcana
  Steal Gem of Strength
  Steal Gem of Fire
Johnny Cipher  (Spider card, level 4)
[1] Zipwire   [2] Smoke Bomb   [4] Vistara Diamond      [TAB] MAP  [MMB] [HOLD] PING MENU
```

The objective counter is **0/3 for the whole 300 s** (315, 376 and 582 all read `[0/3]`). The run is a
manual free-roam-style play of the Guildhall map on a different contract, with **at least two deaths**
(`Time Until Respawn` at 376 and 592) and a respawn at 384. It does not follow the official beat order
and it never completes an objective. Consequences carried through the report:

* The mission line is a different contract string, so the HUD tracker row (`UI3-02`) and the mission
  flow rows (`UI4-03`, `G5-01`) cannot be settled from this window.
* A "beat" below means *the official beat's defining subject is on screen*, not that the beat was played
  in the official situation or order.
* `absent` in this report means **absent from this 300 s window**; it is not a route-level verdict
  (plan §2.4). S26/S27 are marked `unseen-gap?` because the capture ends mid-respawn at 600 s.

### 1.4 Evidence-frame command

```bash
PROXY="$HOME/Videos/tat2_ref_20261127/review/route_lossless_1fps.mp4"
ffmpeg -hide_banner -v error -y -ss <t> -i "$PROXY" -frames:v 1 \
  "$HOME/Videos/tat2_ref_20261127/review/r2_<id>_<t>.png"
```

The proxy is 1 fps, so `-ss <t>` returns proxy frame `t` exactly (verified: `-ss 316` reproduces the
hash of the pre-extracted frame 316, `ecc858ff…`). All 20 evidence PNGs are sha256-listed in §6.

---

## 2. Content index of 300–600 s (what is on screen, in order)

| Proxy t | Content (viewed at 1 s steps) |
|---|---|
| 300–306 | Metal grate catwalk with iron railings at roof level, a dark prone shape at the left (possibly a body), alley below. This matches the **safe-room catwalk** half of S12. |
| 307–326 | Brick alley wall: a **green line-art house/door outline** (peaked roof + door hole, green with a violet fringe) projected on the wall; to its left the white banner **`…'S DEMOLITI[ON]`**; moon upper-right. The player stands and looks at the marker for ~15 s. |
| 327–335 | Roof edge, pipes, crates and a hand cart below, grass/foliage at the parapet. |
| 336–341 | Drop to a wet cobbled street: lamp post, lit doorway, a small blue-white glint on the cobbles, iron fence. |
| 342–352 | Wall-lamp-lit wooden door/portico corner; crouch behind the corner. |
| 353–372 | A lantern/flashlight constable closes on the player; the health bar is already low; the player is cornered. |
| 373–383 | **Death** — skull icon, red damage vignette, `Time Until Respawn: 0:04 → 0:00`. |
| 384–399 | Respawn on a roof parapet above a classical facade and courtyard; moon; roofline with a green-tinted skylight and iron railings. |
| 400–439 | Rooftop/zipwire traverse: hand cart + a parked vintage car below (410), a red neon sign cut by the frame edge (411, reads *MELVIN*-like — **not** the gold `MACLEOD`), a boiler/tank with a 10-bolt pipe flange and `[F] TURN OFF` (424–439). |
| 440–470 | Stone balcony/terrace with a stone balustrade and iron fence; a lantern constable patrols; close-quarters fighting, health drops. |
| 471–481 | Parapet above a courtyard lit by a purple searchlight cone. |
| 482–501 | Drop to the courtyard (blue glass sconces, cobbles, planter); zipwire `CRANK` gauge; flight to the portico doors. |
| 502–529 | **Blue-grey diamond-mullion double doors** with brass pulls, blue sconces, arched stone portico; `[F] PICK LOCK` / `Lock Level 2`; lockpick widget; entry. |
| 530–543 | Interior hall/dining room: parquet, wall lamps, long table, chairs. |
| 544–563 | **Lounge**: constable grabbed at a window (544–548), blue-white electric arc (549), dense white smoke (550–557), constable prone on the carpet (558–563). |
| 564–573 | Colonnade/hall with lingering smoke. |
| 574–581 | **Lounge/dining room**: billiard table with green baize, chandelier, tufted armchairs, tea table; stairs up. |
| 582–585 | **Marble foyer**: checkered floor, tall glass vitrine with a constable statue, red armchair + ottoman, square floor plate, **one** horizontal white beam, wall emitter at ≈(14.7 %, 50.1 %), cyan diamond sconce above the far doors, `WC` plaque. |
| 586–591 | Beam crossed: **purple crystalline ward** and **green thorny vine** growth around the `Basement Stairs` doorway; crimson noise arcs. |
| 592–599 | Player dies next to the ward (`Time Until Respawn`), `HOLD RESPAWN` at 599. Window ends mid-respawn. |

---

## 3. Beat presence table (S01–S27)

`present` = defining subject visible and unambiguous · `partial` = subject visible but a defining
element is missing/different or the transition is unseen · `absent` = visibly not this beat anywhere
in 300–600 s (window verdict only) · `unseen-gap?` = not found and plausibly inside the 600 s → 826.5 s
unrecorded gap (not a verdict).

| Sxx | official t | proxy t | verdict | evidence frame | subject / what is actually there (and what is missing) |
|---|---|---|---|---|---|
| S01 | 00:00.00 | — | absent | — | No startscreen: the window is mid-mission with live HUD. No neon street, no menu stack, no cursor. |
| S02 | 00:02.15 | — | absent | — | No loading art. |
| S03 | 00:02.60 | — | absent | — | No Den attic, rafters, moon shaft, desk or armoire. |
| S04 | 00:06.57 | — | absent | — | No `WARDROBE` overlay anywhere in the window. |
| S05 | 00:18.24 | — | absent | — | No telescope, no sky cut, no wanted-poster wall. (The moon at 323/393 is a gameplay sky, not the telescope view.) |
| S06 | 00:26.58 | — | absent | — | No ledger, `JOURNAL` or `BLACK MARKET`. |
| S07 | 00:38.17 | — | absent | — | No gramophone corner or decoration swap. |
| S08 | 00:51.08 | — | absent | — | No map table, tokens or confirm modal. |
| S09 | 00:56.08 | — | absent | — | No `MISSION PREPARATION` card or countdown. |
| S10 | 01:04.80 | — | absent | — | No loading screen. |
| S11 | 01:09.44 | — | absent | — | No briefing letter. |
| S12 | 01:10.81 | 300–306 | **partial** | `r2_S12_catwalk_304.png` | Exterior metal-grate catwalk with iron railings (the beat's exit half). **Missing:** the safe-room interior, the jagged green/violet escape portal of KF14, the lit lantern + `[F] TURN ON`, the `SPIDER` flyer. A separate green **house/door outline** appears on the alley wall at 307–326 (`r2_S13_banner_316.png`); it is a door marker, not the jagged KF14 portal — see §5. |
| S13 | 01:20.10 | 311–322, 336–341 | **partial** | `r2_S13_banner_316.png`, `r2_S13_alley_311.png`, `r2_S13_street_340.png` | Brick alley, wet cobbles, rain, oil drums, a hand cart, the `…'S DEMOLITI[ON]` banner at the crop edge, streetlamp and lit doorway. **Missing:** the full `BARRON'S DEMOLITION` / `EST. 1865` / `Out with the old…` banner (clipped), the car `[F] INTERACT` + double-honk + flashing headlights, and the gate approach. |
| S14 | 01:39.30 | 400–423, 482–501 | **partial** | `r2_S14_zipwire_411.png` | ZipWire `[1]` in the right hand with the multi-strand cable, `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]`, rooftop launch and flight. **Missing:** the wrought-iron `CONSTABLE'S GUILDHALL` arch, the red-eyed guard with a **yellow** overhead alert bar, the car headlights, the planter landing. |
| S15 | 01:49.50 | 490–495 | **partial** | `r2_S15_crank_495.png` | `CRANK` circular gauge at centre and the cable reel in hand during a zipwire flight. **Missing:** the roof-parapet anchor, the ~7 s 1P crank ascent, the clocktower in mist. |
| S16 | 01:58.50 | 390–440 | **partial** | `r2_S16_roofline_397.png` | Slate/roof ridge walking, skylights, chimneys, parapets, a boiler/tank with `[F] TURN OFF`. **Missing:** the winch/gear housing, and the 3rd zipwire to a gate pillar (no crowned pillar is reached). |
| S17 | 02:11.00 | — | absent | — | No crowned star-topped pillars, twin stone griffins, white 10-bolt gear plate with a red `⚡`, or courtyard descent. A 10-bolt **pipe flange** on the boiler at 432 is a different object (`r2_S14_zipwire_411.png` neighbourhood). |
| S18 | 02:23.30 | 546–557 | **partial** | `r2_S18_canister_546.png`, `r2_S18_smoke_552.png` | The cylindrical `[2]` smoke canister in the 1P hand and a dense opaque grey-white plume filling a room. **Missing:** the grand-stair throw, the orange-white ignition flash, the horizontal stair-spanning plume shape. |
| S19 | 02:30.70 | — | absent | — | No Vistara Diamond in the caliper mount, no scan pulse, no RED→GREEN guard silhouette. The blue-white arc at 549 is an electric baton discharge, not a scan. |
| S20 | 02:33.00 | 440–470 | **partial** | `r2_S20_balcony_452.png` | Rain-wet stone balcony with a stone balustrade, iron fence and a patrolling lantern constable. **Missing:** the crisp vertical gold `MACLEOD` sign. The only large neon sign in the window is a red one at 411 that reads *MELVIN*-like and is cut by the frame edge — it is **not** `MACLEOD` (`r2_S14_zipwire_411.png`). |
| S21 | 02:54.50 | 495–529 | **partial** | `r2_S21_doors_506.png`, `r2_S21_lockpick_511.png` | Arched stone portico, blue-grey painted double doors with cream diamond-mullion glazing, twin brass vertical pulls, blue glass sconces, the doors opened and walked through. **Missing/different:** the door is **locked**, so the reticle is `[F] PICK LOCK` / `Lock Level 2` and a lockpick widget, not the KF24 `[F] OPEN` above `[F] [HOLD] LOCK` → `[F] CLOSE` pair; no scaffolding in frame. |
| S22 | 03:04.50 | 544–548, 558–563 | **partial** | `r2_S18_canister_546.png`, `r2_S23_guard_down_560.png` | A constable in blue with glowing red eyes, belt and baton, grabbed from behind at a window; a `Guildhall Key` row is held bottom-left from ≈582 (`r2_upper_foyer_583.png`). **Missing:** the hearth/chandelier parlor, the `[F] PICK POCKET` above `[F] [HOLD] TAKEDOWN` prompt pair, and the visible key-acquisition moment. |
| S23 | 03:17.10 | 544–563 | **partial** | `r2_S23_guard_down_560.png` | Close-quarters grapple: hands on the constable (544–548), electric arc (549), smoke (550–557), constable prone on the carpet with the 1P hands over him (558–563). **Missing:** a visible `[F] [HOLD] TAKEDOWN` progress arc and the scripted lunge/pull-back framing of KF26. |
| S24 | 03:22.00 | 582–585 | **present** | `r2_upper_foyer_583.png`, `r2_S24_beam_582.png` | Checkered marble floor, tall lit glass vitrine with a constable statue, red velvet armchair + dark ottoman, square floor plate, **one** horizontal white beam from a left-wall emitter, cyan diamond sconce above the far doors, `WC` plaque. Subject set is unambiguous. **Deltas to note, not score:** only one beam is measurable (KF27 shows two), and the emitter sits at ≈(14.7 %, 50.1 %) of the frame versus KF27's (17.7 %, 40.2 %) — see §4.2. |
| S25 | 03:29.00 | 586–591 | **present** | `r2_S25_ward_spawn_586.png`, `r2_S25_vines_587.png`, `r2_S25_ward_590.png` | The purple faceted ward crystallises across a doorway, green thorny vine growth erupts on the adjacent doorway/column, the gold framed `Basement Stairs` plaque is legible, crimson noise arcs at the gem. The ward appears **after** the beam is crossed (585 → 586), so the trigger order is visible. **Delta to note:** the ward is on the `Basement Stairs` side of the hall in this frame rather than the forward arch; both KF28 subjects are nevertheless on screen. |
| S26 | 03:37.40 | — | unseen-gap? | — | No crimson alarm, no slate-stair ascent. A staircase is visible at the right edge of 583 but unlit. The player is dying at 592 and the capture stops at 600 with `HOLD RESPAWN`, so the stair/alarm content can plausibly be in the 600 s → 826.5 s gap. |
| S27 | 03:41.90 | — | unseen-gap? | — | No pause modal, no `RESUME/SETTINGS/RETURN TO THIEF'S DEN/QUIT TO DESKTOP`, no footer. Same gap shadow. |

Count for this window: **2 present, 10 partial, 13 absent, 2 unseen-gap**.

---

## 4. Pose table

| Pose | official cue | proxy t | verdict | frame | notes |
|---|---|---|---|---|---|
| `gate` | KF16 01:40.20 | — | absent | `r2_S12_catwalk_304.png` (nearest) | No `CONSTABLE'S GUILDHALL` lettering, no arch, no yellow alert bar, no car headlights. The iron at 304 is a catwalk railing. |
| `kf18_overlook` | KF18 02:14.80 | — | absent | `r2_S16_roofline_397.png` (nearest) | No crowned star-topped pillars or twin griffins, and no cable crossing over the arch; the window has roof ridges, skylights and a boiler instead. |
| `upper_foyer` | KF27 03:27.60 | 582–584 | **partial** | `r2_upper_foyer_583.png`, `r2_S24_beam_582.png` | The framing matches (threshold → checkered marble, vitrine, armchair + ottoman, floor plate, beam, cyan node, `WC` plaque) but it is **motion, not a 3 s hold**: 582/583/584 differ by camera translation, no run of two identical samples. One beam, not two. |
| `yaw180` | KF27 +0.5 s | — | absent | — | The camera never reverses 180° at the foyer spot. 585→587 is a turn **right** toward the ward/vines, not a reverse view of the vitrine/armchair archway. |
| `lounge` | none (port-only pose) | 549, 574–577 | **partial** | `r2_lounge_577.png` | Guildhall lounge is clearly visible: billiard table with green baize, chandelier, tufted armchairs, tea table, parquet, arches. The Lounge **bouncer** is present earlier at 544–563, engaged and then prone. The specified "east doorway looking west" framing cannot be established (no reference image, compass only `NW`). |
| `lounge_beam` | none | — | absent | — | No beam or emitter is visible anywhere in the Lounge frames (549, 574–577). |
| `beam_close` | KF27 beam | — | absent | `r2_S24_beam_582.png` (nearest) | The emitter is only seen from ≈8 m across the hall; there is no 2–3 m oblique with the emitter at x≈17.8 %/y≈40 % plus two beams and the cyan ceiling diamond. |

### 4.2 Frame measurements from the foyer (CPU, no scorer, no verdict)

Measured on the 2560×1440 frames (band x 400–1500, y 300–900, smoothed row means; method noted so it can
be repeated):

| Frame | Brightest beam row | Beam count | Emitter core (threshold 55 %, trimmed bbox centre) |
|---|---|---|---|
| 582 | 49.9 % (row 718/1440) | 1 (no second band in the top-8 rows) | (14.7 %, 50.1 %) — 32×16 px bbox |
| 583 | 47.4 % (row 683) | 1 | off-frame left |
| 584 | 51.7 % (row 744) | 1 | off-frame left |

The row moves 47.4 → 51.7 % within three seconds of the same approach because the camera pitches and
steps; **camera pitch is not recorded**, so the y% is not comparable to the official keyframe or to the
port pose without that caveat. For the plan's §4 measured question the honest statement is: *the shipped
build's foyer beam in this capture is a single band at 47–52 % with a left-wall emitter at x ≈ 15 %;
the port's `upper_foyer` measurement of 49.07 % / emitter x 29.9 % falls inside the row band but frames
the emitter further right, while KF27's 40.19 % / x 17.7 % differs in y by ~8–10 points. This capture
cannot settle the KF27-vs-V6-03 discrepancy on its own.* One beam measured, not two, is the more
interesting observation and should be re-checked on the poses in part 3.

---

## 5. Row ids whose subject is visible (coverage only — no scores)

Rule applied: a row is `confirmed-subject` only when its subject is visible **and** it belongs to a
`present` beat (S24/S25 here, per plan §6.1); everything else is `partial-subject` with the reason.
Audio rows are excluded from coverage by plan §6(6) and §1.4 — nothing in this report is an audio claim.

### 5.1 `confirmed-subject` (beat present)

| Row | Subject visible | Frame | Note |
|---|---|---|---|
| V4-07 | foyer dressing: lit glass vitrine, velvet armchair + ottoman, flush square floor plate, `Basement Stairs` and `WC` plaques | `r2_upper_foyer_583.png`, `r2_S25_ward_590.png` | KF28's `Basement Stairs` plaque is legible in gold serif. |
| V6-03 | security beam, wall emitter, cyan node | `r2_S24_beam_582.png` | **One** beam measured, not two; emitter (14.7 %, 50.1 %); cyan node is a wall sconce above the far doors at ≈(54 %, 28 %). |
| V6-04 | purple crystalline ward + green thorny vine lock | `r2_S25_vines_587.png`, `r2_S25_ward_590.png` | Both subjects on screen; ward on the `Basement Stairs` side, vines adjacent. |
| UI3-04 | `Guildhall Key` HUD row above `[1]` | `r2_upper_foyer_583.png` | `0/0 Guildhall Key` bottom-left; persists 582–591. |
| UI3-05 | Light Gem present, lit sector | `r2_S24_beam_582.png` | Gem visible in every frame; no state-by-state exposure comparison made. |
| UI5-01 | red player-noise arcs | `r2_S24_beam_582.png` | Wide crimson arcs around the gem; also at 336–348. |

### 5.2 `partial-subject`

| Row | What is visible | Frame | Missing / different |
|---|---|---|---|
| V1-04 | streetlamp + warm wall-lamp pool on brick and door | `r2_S13_street_340.png` | no lantern ignite/`[F] TURN ON` beat |
| V2-01 | rain streaks, rain-slick cobbles | `r2_S13_street_340.png` | no neon puddle reflection in frame |
| V3-01 | wet-cobble specular under lamps | `r2_S13_street_340.png` | — |
| V3-03 | blue-grey painted double doors, cream diamond-mullion glazing, twin brass vertical pulls | `r2_S21_doors_506.png` | paint reads blue-grey rather than saturated blue; the KF24 open/close prompt pair is absent (door is locked) |
| V4-04 | `…'S DEMOLITI[ON]` banner at the crop edge, oil drums, cart | `r2_S13_banner_316.png`, `r2_S13_alley_311.png` | full banner, `EST. 1865`, tagline, ladder |
| V5-03 | 1P hands + ZipWire launcher + crank handle | `r2_S14_zipwire_411.png` | hands read bare/pale in bright light; no railing-vault frame |
| V5-04 | constable in blue with belt, red eyes, baton/arc | `r2_S18_canister_546.png` | he is alerted/hostile, not standing idle with hands clasped; baton glow is a discharge arc |
| V5-05 | grapple over a constable, guard prone | `r2_S23_guard_down_560.png` | no helmet/shoulder lunge framing, no prompt arc |
| V6-02 | smoke canister + dense grey-white plume | `r2_S18_smoke_552.png` | indoor throw, no stairs, no ignition flash |
| UI2-03 | `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]`, `[1]` highlighted | `r2_S14_zipwire_411.png` | — |
| UI2-04 | circular crank gauge + `CRANK` | `r2_S15_crank_495.png` | needle gauge, not the KF17 segmented progress ring |
| UI3-01 | `Johnny Cipher` Spider card level 4 + compass | `r2_S13_alley_311.png` | — |
| UI3-02 | `(£) 0`, tool hotbar, health bar, tracker | `r2_S13_alley_311.png` | tracker is `Steal the components of the Staff of Edinburgh [0/3]`, not `Steal 4,000 in loot value` |
| UI3-03 | ornate health bar, red | `r2_S18_canister_546.png` | already ~20–25 %; the reveal moment is before this window |
| UI5-02 | crimson three-dash pip at mid-right | `r2_S24_beam_582.png` | identity (guard-direction vs noise) not established |
| UI5-03 | red glowing eyes + vertical red alert bar | `r2_S18_canister_546.png` | bar is red, not the KF16 yellow bar |
| UI5-06 | white circular status icon above the gem | `r2_S25_vines_587.png` | a curved/spiral glyph, not confirmed to be the KF28 jaw-trap glyph; the `xx` unconscious-head icon is not seen |
| G5-03 | ward appears after the beam, vines on the adjacent doorway | `r2_S25_ward_spawn_586.png` | the crossing itself is between samples (585 → 586), so the tripwire is inferred, not seen |
| G1-06 | `Guildhall Key` held in HUD | `r2_upper_foyer_583.png` | the pickpocket action/prompt itself is not visible |
| G2-03 | roofline traverse | `r2_S16_roofline_397.png` | no crank ascent up a facade |
| G3-01 | ZipWire equipped, launches | `r2_S14_zipwire_411.png` | equip swing-into-hand moment not visible |

### 5.3 Not visible in this window (no row can be carried)

Visual (25): `V1-01 V1-02 V1-03 V1-05 V1-06 V1-07 V2-02 V2-03 V2-04 V2-05 V3-02 V3-04 V4-01 V4-02
V4-03 V4-05 V4-06 V5-01 V5-02 V6-01 V7-01 V7-02 V7-03 V7-04 V7-05`

HUD/UI (16): `UI1-01 UI1-02 UI2-01 UI2-02 UI2-05 UI2-06 UI2-07 UI3-06 UI4-01 UI4-02 UI4-03 UI4-04
UI4-05 UI5-04 UI5-05 UI5-07`

Gameplay (21): `G1-01 G1-02 G1-03 G1-04 G1-05 G2-01 G2-02 G2-04 G2-05 G3-02 G3-03 G3-04 G4-01 G4-02
G4-03 G4-04 G4-05 G5-01 G5-02 G5-04 G5-05`

Audio (31, **not assessed at all** — plan §1.4 / §6(6); the capture's audio is clipped and no level,
loudness, duck or silence claim may be made from it): `AU1-01 AU1-02 AU1-03 AU1-04 AU1-05 AU1-06
AU2-01 AU3-01 AU3-02 AU3-03 AU3-04 AU3-05 AU4-01 AU4-02 AU4-03 AU4-04 AU4-05 AU5-01 AU5-02 AU5-03
AU5-04 AU5-05 AU5-06 AU5-07 AU5-08 AU6-01 AU6-02 AU6-03 AU6-04 AU6-05 AU6-06`

Total accounted for: 27 visible (6 confirmed-subject + 21 partial-subject) + 62 not visible + 31 audio
= **120**.

Two near-misses worth recording so they are not mistaken for coverage:

* `V6-01` — the green **house-shaped door outline** at 307–326 (`r2_S13_banner_316.png`) is a different
  marker: clean line art of a house with a door hole, not the jagged emerald/violet portal shimmer of
  KF14, and it is on an exterior alley wall, not the safe room. Not carried.
* `V4-05` — the 10-bolt circular flange on the boiler at 424–439 is a pipe flange on industrial
  rooftop plant, not the weathered white wall plate with the red downward `⚡` of KF18. Not carried.

---

## 6. Evidence frames (exact files, sha256)

All under `~/Videos/tat2_ref_20261127/review/`. Each is a 480×270 PNG from the 1 fps proxy.

| File | t | sha256 (first 16) |
|---|---|---|
| `r2_S12_catwalk_304.png` | 304 | `0d148c69ff3ddfa4` |
| `r2_S13_alley_311.png` | 311 | `5167e46bc59be0f3` |
| `r2_S13_banner_316.png` | 316 | `ecc858ffcce71d76` |
| `r2_S13_street_340.png` | 340 | `21995da339189aba` |
| `r2_S16_roofline_397.png` | 397 | `bfa41e764a950646` |
| `r2_S14_zipwire_411.png` | 411 | `adce71c3e5919868` |
| `r2_S20_balcony_452.png` | 452 | `f3bf73805d630744` |
| `r2_S15_crank_495.png` | 495 | `1165f6f6fca91b23` |
| `r2_S21_doors_506.png` | 506 | `09793685e05a2c03` |
| `r2_S21_lockpick_511.png` | 511 | `fdbe40108a201eac` |
| `r2_S18_canister_546.png` | 546 | `f631ab4d6b5ed95e` |
| `r2_S18_smoke_552.png` | 552 | `2fd1f9ba499c9b00` |
| `r2_S23_guard_down_560.png` | 560 | `5ecc0f5b315496de` |
| `r2_lounge_577.png` | 577 | `1440a383c0fb7470` |
| `r2_S24_beam_582.png` | 582 | `a539da94369f78b6` |
| `r2_upper_foyer_583.png` | 583 | `bd7329aed69bd261` |
| `r2_S25_ward_spawn_586.png` | 586 | `4029c7d33e271214` |
| `r2_S25_vines_587.png` | 587 | `12ec45f37c87f1db` |
| `r2_S25_ward_590.png` | 590 | `4cfa183b7cebff82` |
| `r2_end_respawn_599.png` | 599 | `cac527b846c4ffb1` |

Full-resolution frames used for reading text (not saved into the review folder, decoded to
`/tmp/opencode/r2/`): 315, 316, 318, 340, 376, 380, 409, 410, 411, 412, 432, 491, 495, 506, 511, 546,
549, 552, 566, 572, 577, 582, 583, 584, 587, 590, 596, 599 (≈28). The ones quoted for text were decoded
with the 5-frame window method (§1.2) and matched to their proxy frame at RMSE 0.007–0.012 before any
string was quoted.

---

## 7. Part-2 gap risk and ambiguities

**Gap risk — high, as the plan predicted.** R2 ends exactly on the 600 s cap. The last 1 s samples are
`Time Until Respawn: 0:01` (598) and `HOLD RESPAWN` (599) — the player is dead beside the ward when the
file ends. Everything that follows in a normal run (respawn, the `Basement Stairs`/stairwell route, any
crimson alarm, the pause menu) is **after** the cut and would fall into the 226.5 s hole before part 3.
S26 and S27 are therefore `unseen-gap?`, and any `absent` verdict for them in the synthesis would be
wrong. The same applies to `G5-04`, `G5-05`, `UI5-06`'s second icon and `UI1-02`.

**Ambiguities I could not settle in this window**

1. **The contract.** Every frame carries `Steal the components of the Staff of Edinburgh [0/3]`, not the
   official Cleanout Heist tracker. The level is recognisably the Guildhall (foyer dressing, `WC` and
   `Basement Stairs` plaques, the blue portico doors, the Lounge), but the mission and the route are not
   the official ones. Any comparison that assumes the official selection fails here.
2. **The green wall marker (307–326).** A green+violet house/door outline on the alley wall. It is not
   the jagged KF14 portal; I do not know whether it is the magic-door summon marker or a waypoint. It is
   deliberately not carried as `V6-01`.
3. **The red sign at 411.** Reads *MELVIN*-like, cut by the frame edge, red neon. It is not the gold
   vertical `MACLEOD` of KF23. If a later lane sees a real `MACLEOD` elsewhere, that lane owns it.
4. **Beam count.** One band is measurable at 582, 583 and 584, and no second band appears in the row
   profile. KF27 shows two. Either the second beam is state-dependent, out of this camera's view, or the
   capture's room state differs. This is a *shipped-build* observation and should be re-measured on the
   part-3 pose frames before any conclusion about the port's beam work.
5. **Cyan node.** KF27 calls it a ceiling diamond; in this capture the cyan diamond is a wall sconce
   above the far double doors at ≈(54 %, 28 %), not on the ceiling.
6. **Ward placement.** In 587–590 the ward reads as the `Basement Stairs` doorway barrier and the vines
   as the adjacent doorway, i.e. the reverse of KF28's "ward on the forward arch / vines on Basement
   Stairs". Both subjects exist; the assignment to doorways differs. Not scored.
7. **Death at the ward (592).** The player dies touching the ward with health already ~20 %; the cause
   (ward damage vs guard damage) is not established.
8. **Motion blur is ON** and the proxy is 480p, so nothing here is an edge/sharpness/texture judgement.
   All strings quoted were read on 1440p frames.

**What this lane cannot do (repeated for the synthesizer):** it cannot confirm any front-end beat, any
Den/wardrobe/ledger/map-table/prep/loading/letter beat, the official gate, the gear plate, `MACLEOD`, the
Vistara scan, the crimson alarm, the pause menu or any audio row; and its `absent` values are window-only.

---

## 8. One-paragraph summary

In part 1, 300–600 s, the shipped build is mid-mission on a **different Guildhall contract**
(`Staff of Edinburgh`, 0/3) with two deaths. The window contains the **S12 catwalk**, the **S13 alley with
a clipped `…'S DEMOLITI[ON]` banner**, roof/zipwire traversal (**S14–S16** fragments), a **smoke-bomb
plume (S18)**, a **stone balcony with a lantern constable (S20)**, the **blue diamond-mullion portico
doors (S21, locked — `[F] PICK LOCK`)**, a **constable grapple and prone body (S22/S23)**, the **Lounge
with billiard table and bouncer**, and a **full S24 foyer** (checkered marble, vitrine, armchair +
ottoman, floor plate, one white beam, cyan node, `WC` plaque) followed by the **S25 ward + vine lockdown**
with the `Basement Stairs` plate. S26/S27 are not in the window and sit in the part-2 gap shadow. 20
evidence frames and their hashes are listed in §6; no row is scored and no file outside this report and
the evidence PNGs was written.
