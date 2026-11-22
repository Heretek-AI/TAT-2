# E2E baseline (unmasked)

Run: `flatpak run org.godotengine.Godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd`
Log: `/tmp/opencode/e2e_unmasked2.log`

| | first unmasked run | after on-disk alignments |
|---|---:|---:|
| total | 251 | 256 |
| passed | 192 | 210 |
| failed | 59 | 46 |
| `[BOOT]` | 0 | 0 |
| `SCRIPT ERROR` | 1 (typed-array lambda) | 0 |

## What was fixed on disk (not masked)

- `e2e_tier1_features.gd:523` — the `forbid_names: Array[String]` lambda is now
  untyped; call sites pass plain arrays.
- 24 expectation alignments that previously lived in `_load_patched()` were ported
  into the tier files (outline material type, reticle/lockpick texture names,
  viewmodel isolation, disguise role, loco substring, equip_tool direct calls,
  lantern property names, guard carry seed, light-probe registration).
- Queued viewcone decay: tests now call `_tick_sustained_systems(1.0)` after
  `apply_guard_viewcone_disguise_decay` (T1-12-C expects 89/s = 10 cone + 1 timer;
  T2-12-A compares queued vs non-queued drain; T3-07/T4-04 tick before reading).
- Genuine defect: fall damage no longer consumes 40 disguise integrity
  (`take_damage(amount, source)`, `source == "fall"`).

## Remaining failures — owner milestones

| ID | Failure | Class | Owner |
|---|---|---|---|
| T1-10-C | RMB crank active/progress | tool integration | M3 |
| T1-11-D | smoke trajectory arc preview | tool integration | M3 |
| T1-11-E | Slithersap puddle (0->0, no RigidBody) | genuine | M3 |
| T1-17-C | Den active miniature highlight (seated=false) | hub token | M2/M6 |
| T2-03-B | Startscreen DirectionalLight energy floor | scene light | M2 |
| T2-05-A | Unauthored mission rows hide icon (checked=4) | stale count | M6 |
| T2-05-B | MissionPrep 720p clip + hFOV | layout | M6 |
| T2-05-E | FTUE "0 minute window" | UI copy | M6 |
| T2-08-C/D/E | 1P translation/keys/SubViewport FOV | player anim | M3 |
| T2-09-A/B/D | tool slot bounds/charges/rapid swap | tools | M3 |
| T2-10-A | zipwire 20 m boundary | tools | M3 |
| T2-10-C | mantle 4.0 m limit (y=4.55) | traversal | M3 |
| T2-11-B | smoke AABB boundary | tools | M3 |
| T2-13-B | zero-loudness SoundWaves | stealth UX | M3 |
| T2-14-C | compass texture wrap | HUD | M6 |
| T2-16-A | empty intro skips mission letter | mission flow | M6 |
| T2-16-D | five shell UIs in 1280x720 | layout | M6 |
| T2-17-A | Den map-token scale/height | hub token | M2/M6 |
| T2-18-A/B/C | Set/Cleanout objective rules | run state | M6 |
| T2-20-A | KO guard state & steal | AI | M4 |
| T3-02 | zipwire HUD ring sync | tools/HUD | M3 |
| T3-03 | smoke + NoiseBus waves + LOS | tools/stealth | M3/M4 |
| T3-06 | Vistara vision + outline | tools | M3 |
| T3-07 | lantern LightProbe + cone drain | AI/stealth | M4 |
| T3-08 | 1P zipwire GLB + isolation | player anim | M3 |
| T3-11 | Slithersap light inhibit + KO | tools | M3 |
| T3-12 | Pickpocket Fairy steals + HUD pip | tools/AI | M3 |
| T3-13 | jam shock damage + disguise + container | lockpick/combat | M3 |
| T3-14 | FOV 95 sync (main + 1P) | settings/player | M3/M6 |
| T3-17 | vault container minigame objective | doors/locks | M4 |
| T3-18 | ping PoI on compass | HUD | M6 |
| T3-19 | yellow highlight + locked prompt | VFX/UI | M2/M6 |
| T3-20 | disguise 1P anim + vignette | player anim | M3 |
| T4-02 | Den hub journey (billboards/map card) | hub | M6 |
| T4-03 | prep→loading→letter→guildhall | mission flow | M6 |
| T4-04 | rooftop sky/1P/zipwire/traverse | integration | M3 |
| T4-05 | infiltration lantern/smoke/slithersap | integration | M3/M4 |
| T4-06 | disguised vault lockpick/extract | integration | M3/M4 |
| T4-07 | set objectives + map + ping + fairy + vistara | integration | M3/M6 |
| T4-09 | combat/fall/downed/disguise journey | integration | M3 |

## Rules for closing

- A failure is fixed only when the **on-disk** assertion passes without patching the runner.
- System-dependent failures close with the milestone that owns the system; the
  issue must name the exact IDs above.
- The suite must keep `[BOOT] == 0` and `SCRIPT ERROR == 0`; a new boot/parse
  failure is a blocker, not a baseline entry.

## Next re-run

After M3 lands, re-run tiers 1–4 and drop the resolved rows. After M6, the same
for UI/layout rows. Track with the milestone issues linked from #5.
