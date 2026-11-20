# W0 headless baseline - make test

Date: 2026-11-19
Command: `cd /home/john/Projects/TAT-2 && timeout 1500 make test` (background bash_16)
Exit code: 0

## Tail (last 15 lines)

```
WARNING: AnimationMixer: 'AN_ThiefNisha_Zipwire_StandIdle', couldn't resolve track: 'Skeleton3D:player_view_1p'.
PASS: 43 zipwire crank AN_ThiefNisha_Zipwire__Reload_Loop resolves via ensure_fp_clip and plays on crank
PASS: 44 triage locks (outline/reticle/lockpick/arms/vm/loco/crank/toggle/lantern/steal/stealth/visreg)
PASS: 45 stairs snap (max_angle 50 deg, snap 0.3 m, wall-block/constant-speed kept, stair slope 32.7 deg walkable, 55 deg blocked, no new mantle)
PASS: 46 Den doors leaf disabled past 70 deg (layer 0 + disabled, re-enabled on close) & window wall split gap=0.95m + sill + lintel (2m marker gate kept)
SUMMARY: fails=0
WARNING: 6 ObjectDB instances were leaked at exit
ERROR: 6 RID allocations of type 'N17RendererSceneCull8InstanceE' were leaked at exit.
```

## Counts

- SUMMARY: fails=0 (exit 0, PASS)
- SCRIPT ERROR lines: 0
- Note: exit-time RID/ObjectDB leak warnings present (teardown follow-up for PG-1 lane);
  they do not fail the headless gate.

Full log: /tmp/tat2-wave0-maketest.log
