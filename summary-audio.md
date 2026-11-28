# audio (3B.3) — worker summary

HEAD `79dc879` on `teamwork/20261127-1810-phase3-audio`. I added one documented
`WeatherProfile.rain_intensity_01()` preset→authored-0..1 converter and made all
three rain consumers (`mission_controller.gd:945`, `weather_visuals.gd`
`make_rain` and `make_lens_rain`) use it, deleting the divergent `0..1` /
`0..1.5` / `0..1` clamps; `blood_moon` 10.0 now saturates to 1.0 with one
`push_warning` per preset (every occurrence counted), 0.0→0.0, 1.0→1.0,
0.5/0.65 unchanged, missing→null. I recorded the 3 unnamed music keys and 24
unnamed buses as **not recoverable from the cook** (measured 0 of 91 `AudioBus`
objects named; no `AkTrigger` object in the extraction) in
`docs/reports/phase3-audio-20261127.md`, `HANDOFF_NEXT_AGENT.md`,
`FIDELITY_GAPS.md` and a correction banner on the W11 report. I wired the two
VO exertion beats whose owning systems already existed (`ExertionCombat/
TakingDamage` 30 and `/Attacking` 9, both Enforcer1-only; Hauntstable1 refuses),
moving the mapped census 249→288 and the remainder 396→357, with the 357
remaining lines tabulated by owning-system gap. I tested the 5 `FS_Layers`
double-ban claim against the authored switch containers and **refuted** it: a
layer selection never removes material-selected media (Stone 44→44 for
MetalPipe/MetalSheet/Metal/Slime; Glass +5, 0 lost), so the five values stay a
`PORT_DECISION` for the measured reasons now recorded. No generated audio or
weather data was regenerated and no mix default was flipped.

Verified locally: `--import`; compile 229/0; `test_audio_control` 135/0 (was
123); `test_vo_director` 60/0 (was 53); `make test` 328 PASS fails=0;
`runtime_smoke.sh 90` exit=124 errors=0 mission_ready=1; `make audit` PASS;
`make string-audit` 311/199/112; `make check-greps` PASS; `make gate-ratchet`
PASS. Not verified: any GPU/pixel or ear check (headless only), and no played
run exercises `blood_moon` (no map uses it). Integrator: the ratchet floors
`test_audio_control.checks` 123 and `test_vo_director.checks` 53 are minimums my
new counts exceed, so raise them 135/60 from the next serial gate log if desired.
