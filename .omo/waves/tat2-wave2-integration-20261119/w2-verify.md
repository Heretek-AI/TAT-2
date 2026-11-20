# W2 verification - Wave 1 merge state + headless gates

Date: 2026-11-19
Workspace: /home/john/Projects/TAT-2
Scope: read-only verification. Only this report was written.

## 1. Merge state

- HEAD = `a13d625 chore(build): Linux x86_64 export preset plus linux-build/linux-run targets`.
- `main` is in sync with `origin/main` (`git rev-list --left-right --count origin/main...HEAD` -> `0	0`).
- Wave 1 commit `5093dc8 feat(port): Wave 1 parity fixes plus TEMP env-strip hook removal`
  is an ancestor of HEAD (`git merge-base --is-ancestor 5093dc8 HEAD` -> true), so Wave 1 is
  merged/committed, not pending.
- No merge, rebase, or cherry-pick in progress (no `.git/MERGE_HEAD`, `.git/CHERRY_PICK_HEAD`,
  `.git/rebase-merge`).
- Single worktree (`/home/john/Projects/TAT-2`); no per-lane worktrees left behind.
- Working tree is NOT clean: 18 modified sources plus 13 untracked files (wave docs/plans and
  the new `tat_*.gdshader` + `.uid` files). Those edits are uncommitted on top of HEAD; the
  gates below were run against exactly this tree.

### git status --short

```
 M game/project.godot
 M game/src/ai/guard_ai.gd
 M game/src/core/audio_manager.gd
 M game/src/core/level_loader.gd
 M game/src/core/mobile_profile.gd
 M game/src/core/vfx_manager.gd
 M game/src/interact/lockable_door.gd
 M game/src/interact/swinging_door.gd
 M game/src/player/smoke_projectile.gd
 M game/src/player/thief_character.gd
 M game/src/ui/contract_table_ui.gd
 M game/src/ui/hud.gd
 M game/src/ui/ledger_ui.gd
 M game/src/ui/loading_screen.gd
 M game/src/ui/main_menu.gd
 M game/src/ui/mission_prep_ui.gd
 M game/src/ui/settings_ui.gd
 M game/src/ui/wardrobe_ui.gd
?? .omo/drafts/tat2-godot-perf-60fps.md
?? .omo/plans/finish-port-waves-0-5.md
?? .omo/plans/tat2-godot-perf-60fps.md
?? .omo/waves/
?? docs/MASTER_PROMPT_OMO_ULW_FINISH_PORT.md
?? game/src/core/tat_alarm.gdshader
?? game/src/core/tat_alarm.gdshader.uid
?? game/src/core/tat_beam.gdshader
?? game/src/core/tat_beam.gdshader.uid
?? game/src/core/tat_smoke.gdshader
?? game/src/core/tat_smoke.gdshader.uid
?? game/src/core/tat_ward.gdshader
?? game/src/core/tat_ward.gdshader.uid
```

### git diff --stat

```
 game/project.godot                  |   4 +
 game/src/ai/guard_ai.gd             |  45 ++++-
 game/src/core/audio_manager.gd      | 362 +++++++++++++++++++++++++++++++-----
 game/src/core/level_loader.gd       | 122 +++++++++++-
 game/src/core/mobile_profile.gd     |   4 +-
 game/src/core/vfx_manager.gd        | 317 ++++++++++++++++++-------------
 game/src/interact/lockable_door.gd  |  18 ++
 game/src/interact/swinging_door.gd  |  16 ++
 game/src/player/smoke_projectile.gd |  10 +
 game/src/player/thief_character.gd  | 114 +++++++++++++-
 game/src/ui/contract_table_ui.gd    |  32 +++-
 game/src/ui/hud.gd                  | 148 ++++++++++++---
 game/src/ui/ledger_ui.gd            |   8 +-
 game/src/ui/loading_screen.gd       |   4 +
 game/src/ui/main_menu.gd            |   7 +-
 game/src/ui/mission_prep_ui.gd      |  17 ++
 game/src/ui/settings_ui.gd          |  30 +++
 game/src/ui/wardrobe_ui.gd          |  12 ++
 18 files changed, 1046 insertions(+), 224 deletions(-)
```

## 2. `make test` (unit/headless suite)

Command: `cd /home/john/Projects/TAT-2 && make test`
(= `flatpak run org.godotengine.Godot --headless --path game --script res://tests/run_tests.gd`)
Exit code: 0

Counts:
- `SUMMARY: fails=0` (line 923 of 928)
- PASS lines: 90
- FAIL lines: 0
- SCRIPT ERROR lines: 0

### Tail (last 12 lines)

```
WARNING: AnimationMixer: 'AN_ThiefNisha_Zipwire_StandIdle', couldn't resolve track:  'Skeleton3D:player_view_1p'. This warning can be disabled in Project Settings.
     at: _update_caches (scene/animation/animation_mixer.cpp:725)
PASS: 43 zipwire crank AN_ThiefNisha_Zipwire__Reload_Loop resolves via ensure_fp_clip and plays on crank
PASS: 44 triage locks (outline/reticle/lockpick/arms/vm/loco/crank/toggle/lantern/steal/stealth/visreg)
PASS: 45 stairs snap (max_angle 50 deg, snap 0.3 m, wall-block/constant-speed kept, stair slope 32.7 deg walkable, 55 deg blocked, no new mantle)
PASS: 46 Den doors leaf disabled past 70 deg (layer 0 + disabled, re-enabled on close) & window wall split gap=0.95m + sill + lintel (2m marker gate kept)
SUMMARY: fails=0
WARNING: 28 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
ERROR: 7 resources still in use at exit (run with `--verbose` for details).
   at: clear (core/io/resource.cpp:822)
ERROR: 6 RID allocations of type 'N17RendererSceneCull8InstanceE' were leaked at exit.
```

Note: the exit-time ObjectDB/resource/RID leak lines are teardown noise, present in the Wave 0
baseline too (6 ObjectDB / 6 RID there; 28 ObjectDB / 7 resources / 6 RID here). They do not
fail the headless gate. Full log: `.omo/waves/tat2-wave2-integration-20261119/unit-test.log`.

## 3. Tier-1 E2E (headless)

Command: `cd /home/john/Projects/TAT-2 && flatpak run org.godotengine.Godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=1`
Exit code: 0

Counts:
- `SUMMARY: fails=0 passed=110 total=110`
- FAIL lines: 0
- SCRIPT ERROR lines: 0 (the only match for the literal `SCRIPT ERROR` is the T1-22-D check
  name on line 152; no real engine script errors)
- SHADER ERROR lines: 0

T1-08: all of A-E PASS. `PASS: [T1-08-A] 1P arms SK_ThiefNisha__BodyUpper PBR bound (true)`,
so there is no T1-08-A Wave 4 fix item to record from this run.

### Tail (last 20 lines)

```
TAT-2 Perf: chunks=4034 collision_bodies=451 collision_shapes=18029 occluders=768
TAT-2 player spawn: source=authored pos=(5.9512, 9.5283, 126.025) yaw=1.5707963267949 headroom_clear=true forward_clear=true
TAT-2 loot containers: 110
TAT-2 spawners: throwable=385 ammo=97 health=7 civilian=2
TAT-2 swinging doors: 120
PASS: [T1-21-D] OldManor spawn headroom=true forward=true
PASS: [T1-21-B] OldManor_P player walk & collision stable (true)
PASS: [T1-21-C] OldManor_P guard collision stable (true, guards=6)
PASS: [T1-21-E] OldManor_P dual-weightmap components=7 shader=true
PASS: [T1-22-A] run_tests.gd preserves 38 suites & SUMMARY: fails= contract
PASS: [T1-22-B] manifest_audit.py & anims_manifest.json intact
PASS: [T1-22-C] Standalone E2E suite files present under res://tests/e2e/
PASS: [T1-22-D] build/qa/capture_e2e_parity.{sh,gd} with SHADER/SCRIPT ERROR=0 gate (true)
PASS: [T1-22-E] Steam refs=56 (>=56) & capture_e2e_parity.gd present=true
SUMMARY: fails=0 passed=110 total=110
WARNING: 18 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
ERROR: 5 resources still in use at exit (run with `--verbose` for details).
   at: clear (core/io/resource.cpp:822)
ERROR: 2 RID allocations of type 'N17RendererSceneCull8InstanceE' were leaked at exit.
```

Full log: `.omo/waves/tat2-wave2-integration-20261119/tier1-e2e.log`.

## Verdict

Both headless gates pass on the current tree: `make test` fails=0 (exit 0), tier-1 E2E
fails=0 passed=110 total=110 (exit 0), zero real SCRIPT/SHADER errors in either run.
Wave 1 is committed and in main's history; the only caveat for integration is that the 18
modified files and 13 untracked files are still uncommitted, so this evidence describes the
working tree, not a committed revision.
