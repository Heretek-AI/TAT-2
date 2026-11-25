# T02-STATE — remediation report (RE-N 01–18)

Team: T02-STATE (lane lead + 2 workers, disjoint files).
Worktree `/home/john/Projects/TAT-2-rem-T02-state`, branch `rem/T02-state`.
Base `38e7b03` (= the tree lane N reviewed). No push, no merge, no rebase. No
producer was run; `game/data/generated/` and `extracted/` were not written.

Commits on `rem/T02-state` (local only, in order):

| commit | subject |
|---|---|
| `d138103` | fix(state): authored cosmetic data path, co-op provenance, run reset contract |
| `760d6c9` | fix(coop,mission): host-authoritative run outcome, one guarded payout path |
| `9b6f04c` | fix(save): quarantine corrupt saves, fallible atomic writes, real outbox |
| `5990a8d` | test(state): wire T02 suites 91-93, behavioural 80.3/80.4 and 49 corrupt case |

The four commits are ordered so each one leaves a compiling tree; the gate
evidence for the merged tip is in the table below.

Ownership honoured: `game/src/core/game_state.gd`,
`game/src/core/save_system.gd`, `game/src/missions/mission_controller.gd` (only
the co-op / payout / extraction / phase functions, plus one guard at the top of
`_apply_run_clock` — called out in RE-N-15 and in Open risks),
`game/src/core/net_manager.gd` (the co-op transport; RE-N-11 is its finding and
no other team claims it), the T02 suites, `game/tests/run_tests.gd` (suite 49
corrupt case, suite 80.3/80.4, suite wiring), and one new tracked data file
`game/data/expansion/coop_provenance.json`.

| lane | files | findings |
|---|---|---|
| lead | `game_state.gd`, `coop_provenance.json`, `run_tests.gd` | RE-N-10 (GameState half), RE-N-12, RE-N-14, RE-N-16, 80.3/80.4 + 49 tautologies, suite wiring |
| worker A | `save_system.gd`, `test_w7s_loot_save.gd`, `test_t02_save_integrity.gd` | RE-N-03, RE-N-06, RE-N-04 residual, 90.1/90.2 |
| worker B | `mission_controller.gd` (payout/co-op), `net_manager.gd`, `e2e_s2_loot.gd`, `test_t02_state_lifecycle.gd` | RE-N-11, RE-N-08, RE-N-15, E2E S2-10/S2-12 |

## Gate baseline before any change (this worktree, isolated `user://`)

```
tools/godot --headless --path game --script res://tests/run_tests.gd
SUMMARY: fails=0                     # 278 PASS
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
scripts checked: 120, broken: 0
```

## Final gate set (this worktree, after every change)

| gate | command | result |
|---|---|---|
| compile | `tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"` | `scripts checked: 122, broken: 0` |
| `run_tests` | `tools/godot --headless --path game --script res://tests/run_tests.gd` | `SUMMARY: fails=0`, **297 PASS** (278 + 19) |
| M2 | `… --script res://tests/test_m2_player.gd` | `M2_SUMMARY: fails=0` |
| probe_leak | `TAT2_NO_DEN_PROBE=1 … --script res://probe_leak.gd` | exit 0, Den path clean (`TAT-2 Den reflection probe: disabled`) |
| W7E endgame | `… --script res://tests/test_w7e_endgame.gd` | `W7E_SUMMARY: fails=0` |
| E2E | `… --script res://tests/e2e/run_e2e_tests.gd` | `SUMMARY: fails=0 passed=278 total=278` (re-run on the final tree, after the `_finish_run` guard split) |
| E2E s2 | `… --script res://tests/e2e/run_e2e_tests.gd -- --tier=s2` | `fails=0 passed=12 total=12` (worker B; the full E2E above includes this tier) |
| perf guard | `build/qa/test_perf_guard.sh` | `PERF_GUARD_TEST PASS checks=78 fails=0` |
| ratchet | `make gate-ratchet` | `GATE_RATCHET: PASS` |
| audit | `make audit` | `AUDIT PASS`, coverage 12657/12703 (99.6 %), unexpected 0, exact-case unexpected 0 |
| texture cap | (inside `make audit`) | `capped: 773`, `alpha-critical 1`, `offenders: 0` |

Logs: `/tmp/opencode/t02-logs/` (`lead-run-tests-2.log`,
`lead-e2e-full.log`, `lead-audit.log`, `lead-m2.log`, `lead-probe-leak.log`,
`lead-w7e-endgame.log`, `lead-red-probe{,2}.log`, `t02b-red.log`,
`a-compile2.log`, `a-runtests.log`, `a-suite3.log`). Every Godot run used an
isolated `XDG_DATA_HOME` and a `flock` wrapper, so the developer save and the
two lanes never collided.

---

## RE-N-03 — a corrupt save is destroyed on the same boot (P1)

- severity: P1
- S1 investigate: `save_system.gd:856-889` (base). `load_save()` used
  `JSON.parse_string` and only acted on the result `if parsed is Dictionary` —
  a parse failure produced no message, no backup and no early return. `data`
  is `_defaults()` at `_ready:160` and `_defaults()` ships
  `settings.fov_migrated:false`, so `_migrate_settings_schema():699-709`
  returned true and `load_save:887-888` called `write_save()`, renaming a fresh
  profile over the player's file.
- S2 research: the shipped persistence is the `TATAtomicSave` plugin — its
  descriptor (`extracted/raw/TAT/Plugins/TATAtomicSave/TATAtomicSave.uplugin`)
  says "Save to disk atomically (write temp and rename)" and its DLL is absent
  from the dump, so the shipped **key layout/versioning is UNEXTRACTED** and
  the plugin promises nothing about corrupt input. **Quarantine-on-bad-load is
  therefore a port decision** (stated in the code comment), chosen because an
  atomic write cannot protect bytes it never wrote.
- S3 confirm (red, real run):
  ```
  REDCHECK RE-N-03 on_disk_before currency=4321
  REDCHECK RE-N-03 cold_boot_file_rewritten=true file_now_parses=true quarantine=[] (want: rewritten false, quarantine 1)
  REDCHECK RE-N-03 cold_boot_profile currency=0 contracts={  } (want: recoverable state, not a silent fresh profile)
  REDCHECK RE-N-03 cold_boot_has_load_failure=false (want true)
  ```
  Cold boot = `data = _defaults()` then `load_save()` (exactly `_ready`).
  Worker A's independent probe on the same tree:
  `after_corrupt_load save_path_present=true parses_as_object=true currency_now=0 garbage_bytes_preserved=false quarantine=[]`.
- S4 fix (`save_system.gd`):
  - `load_save` reads `save_path()`, parses with `JSON.new().parse()` (keeps the
    message and line) and treats any non-`Dictionary` root (null, array,
    string) as a failed load; `{}` stays a valid save.
  - `_report_load_failure()` **quarantines first** (`_quarantine_bad_save()` →
    `<path>.corrupt-<unix_ts>[-n]`, rename, else verified copy+remove, else keep
    the original where it is), then `push_error`s with both paths and the
    parser text, fills `load_failure {reason, path, backup_path, error}` and
    emits `load_failed(reason, backup_path)`. The boot then **returns without
    the migration write and without `_settle_pending_on_load()`**, so no fresh
    profile is minted over the player's bytes. A later explicit `write_save()`
    (a settings change) is still allowed — the original is already preserved.
  - Read API `has_load_failure()` / `get_load_failure()`; a `path_override` test
    seam so suites never touch the developer save.
- S5 test: new suite 92 `game/tests/test_t02_save_integrity.gd` blocks 1–3
  (corrupt bytes quarantined *whole*, string/array/null roots quarantined, `{}`
  accepted, a good legacy save migrates exactly once and is never quarantined);
  suite 49's vacuous `currency >= 0` check replaced by "quarantined whole + no
  live save path + reason `parse_error`" plus cleanup of the artefact.
- S6 confirm (green):
  ```
  REDCHECK RE-N-03 after_corrupt_load save_path_present=false parses_as_object=false currency_now=0 garbage_bytes_preserved=true quarantine=["tat2_save.json.corrupt-1795586435"]
  REDCHECK RE-N-03 has_load_failure_api=true value=true
  ERROR: [save_system] save at user://tat2_save.json is unusable (parse_error: Expected key (line 0)); preserved as user://tat2_save.json.corrupt-1795586584. Defaults are live for this boot and will not be written.
  PASS: T02 save integrity 1/2/3 …
  ```
- verdict: **FIXED**

## RE-N-06 — the payout outbox is test-only; `write_save` cannot fail (P1)

- severity: P1
- S1 investigate: `write_save():892-910` returned `void`, `store_string` was
  unchecked and the tmp was renamed into place even if truncated, so an ENOSPC
  write could replace a good save with invalid JSON (which then hit RE-N-03).
  `bank_payout:977-1004` ignored the write result and returned
  `{applied:true}` unconditionally. `stage_pending_payout` /
  `settle_pending_payout` had **zero production callers** (`rg` → definitions +
  `test_w7s_loot_save.gd:183`), so the documented crash recovery could not run.
- S2 research: payout bookkeeping is port-invented (the authored figures it
  mirrors are in `loot_settings.json`); the recovery requirement is the port's
  own invariant "every failure path owes a payout" (AGENTS §Known traps).
- S3 confirm (red):
  ```
  REDCHECK RE-N-06 write_save_return=<null> is_int=false (want: 0 / true)
  REDCHECK RE-N-06 write_save_missing_dir_return=<null> is_int=false tmp_left=false
  REDCHECK RE-N-06 bank_payout_keys=["applied","reason","match_id","money_taken","banked"] (want persisted/write_error/outbox_error too)
  REDCHECK RE-N-06 bank_payout applied=true persisted=<absent> currency_now=500
  ```
- S4 fix (`save_system.gd`):
  - `write_save() -> Error`: tmp open error via `get_open_error()`,
    `store_string` + `flush` + `get_error()`, **read the tmp back**, require
    byte-identical text and a JSON object (else `ERR_FILE_CORRUPT` and the tmp
    is deleted), then `rename_absolute` and return its error. Every failure path
    removes the scratch file.
  - `bank_payout`: duplicate check unchanged, then **write #1 stages** the
    record through `stage_pending_payout` (`applied:false`, `banked:0`), applies
    in memory, **write #2** persists the applied profile. Returns
    `{applied, reason, match_id, money_taken, banked, persisted, write_error,
    outbox_error}`. A crash between the writes leaves a `pending_payout` the next
    load settles exactly once; a failed #2 reports `persisted:false`; a failed
    #1 reports `outbox_error != OK`. `persisted` is never true on a failed write.
  - `_settle_pending_on_load()` calls the public `settle_pending_payout()`.
  - `mission_controller._finish_run` and the co-op client path log a
    `push_error` when `persisted == false` instead of silently claiming success.
- S5 test: suite 92 blocks 4–6: `write_save()` → `OK` on a good path (no `.tmp`
  left, file parses), non-OK `Error` on an unwritable path (no `.tmp`, no
  directory created), `stage_pending_payout` + a **fresh instance** `load_save()`
  settles once (100 → 600, second load still 600) through the override path,
  `bank_payout` returns `persisted:true` / `outbox_error:OK`, clears
  `pending_payout`, the on-disk record has `applied:true`, replay is
  `duplicate`, and a bank whose writes cannot land reports `applied:true,
  persisted:false` without lying.
- S6 confirm (green):
  ```
  REDCHECK RE-N-06 write_save_return=0 is_int=true
  REDCHECK RE-N-06 write_save_missing_dir_return=7 is_int=true tmp_left=false   # 7 = ERR_FILE_NOT_FOUND
  REDCHECK RE-N-06 bank_payout_keys=[…,"persisted","write_error","outbox_error"]
  REDCHECK RE-N-06 bank_payout applied=true persisted=true currency_now=500
  PASS: T02 save integrity 6 (bank_payout persists, clears pending, replays as duplicate, never lies about a failed write)
  ```
- verdict: **FIXED**

## RE-N-11 — a co-op client can never complete (P1)

- severity: P1
- S1 investigate: `mission_controller.gd:4341-4343` (base) returned before
  `register_extracted_player` / `resolve_phase` whenever
  `multiplayer.has_multiplayer_peer() and not multiplayer.is_server()`, so the
  client saw nothing when the host escaped; its own `_process:4260-4284` then
  reached `TIME EXPIRED` / `MAGIC DOOR COLLAPSED` and banked a stash-only
  *failure*. `net_manager.gd:12` said the same ("Loot, AI and mission
  progression are NOT replicated here").
- S2 research: the shipped build **ships multiplayer** — verbatim from
  `extracted/filelist.txt`: `TAT/Content/Core/BP_TATPvEGameMode.uasset`,
  `BP_TATPvPGameMode.uasset`, `BP_TATServerStartGameMode.uasset`,
  `TAT/Content/Core/Lobby/BP_LobbyGameMode.uasset`, `BP_LobbyGameState.uasset`,
  `TAT/Content/Character/Player/BP_MatchLobbyDummyPlayer.uasset`,
  `TAT/Content/Maps/MissionLobby/MissionLobby_P.umap`,
  `TAT/Content/UI/SessionSelect/BPUI_{SessionSearch,SessionQuery,ServerListPanel,ServerRow,SessionButton}.uasset`;
  plus `DT_PlayerExperience` row `XP.Cooperative` → "Co-op Bonus"
  (`game/data/generated/tables/Gameplay/Tuning/DT_PlayerExperience.json`). The
  BP replication graph is **UNEXTRACTED**, so the protocol below is a
  documented **port design**, not authored truth. (`MissionLobby` geometry is
  consumed only as the main-menu/prep backdrop.)
- S3 confirm (red):
  ```
  REDCHECK RE-N-11 nm_has_run_resolved=false nm_has_run_requested=false (want true/true)
  REDCHECK RE-N-11 client_extract_state=victory … (guard needs a live ENet peer, so a coop peer resolved as solo)
  FAIL: RE-N-11 transport: RUN_OUTCOMES allowlist missing or open (got <null>)
  FAIL: RE-N-11 host: run_requested/run_resolved transport signals missing
  FAIL: client extraction resolved locally (state=victory)
  ```
- S4 fix:
  - `net_manager.gd`: `RUN_OUTCOMES = ["escape","capture","timeout"]`,
    `RUN_OUTCOME_COOLDOWN_MSEC = 1000`, `MAX_PAYOUT_JSON_LEN = 8192`,
    `signal run_requested(outcome,from_peer)`,
    `signal run_resolved(outcome,payout)`. `request_run_resolved` (`any_peer`,
    reliable): local client forwards to peer 1, host validates sender +
    allowlist + 1 s/sender cooldown then emits `run_requested`;
    `broadcast_run_resolved` (host only, bounded JSON);
    `apply_run_resolved` (`authority`, reliable): real remote sender,
    allowlist, ≤ 8 KiB, JSON object, then emits `run_resolved`. Nothing
    dispatches to a network-chosen method; counters
    (`run_request_count`, `run_resolved_send_count`, `_accept/_reject`) make the
    routing assertable headless; `disconnect_net()` clears the cooldown.
  - `mission_controller.gd`: `_on_escape_gate_extracted` routes
    `NetManager.is_client()` → `request_run_resolved("escape")` (never resolves
    locally), else `_finish_run("escape")`. `_connect_coop_listener` connects
    both signals. `_on_coop_run_request` is host-only and reuses `_finish_run`.
    `_on_coop_run_resolved` (client) applies the host's **banked record
    verbatim** — `bank_payout` on the same `match_id`, never recomputes the
    numbers, never broadcasts — then mirrors `last_payout`, resolves the phase
    and shows the panel. `is_client()/is_host()` (the `set_test_peer_id` seam)
    replace the raw MultiplayerAPI read, so the path is drivable headless; solo
    is unchanged.
  - Model stated in code: each peer has its own profile; the client records the
    host's numbers, so it can neither invent nor double-bank a payout.
- S5 test: suite 91 blocks `_check_coop_host_once` (host banks once, broadcasts
  once, a client request and the host's own re-extraction bank nothing),
  `_check_coop_client_resolves` (client delta == host `banked`, same `match_id`,
  a 999999 s clock tick cannot fail the resolved run, client never broadcasts),
  `_check_client_extraction_routes` (state stays `playing`, no local peer
  registered, no currency, one request reported).
- S6 confirm: `PASS: T02-B co-op host banks and broadcasts once`,
  `PASS: T02-B co-op client resolves from the host's banked record`,
  `PASS: T02-B client extraction routes to the host`.
- verdict: **FIXED** — live two-process ENet run **not verified** (no tier-5
  gate exists); see Open risks.

## RE-N-08 — failure-path payouts guarded inconsistently (P2)

- severity: P2
- S1 investigate: `_on_extracted` guarded on `_payout_applied or state=="victory"`;
  `_on_door_collapsed` on `_payout_applied`; `_on_time_expired` on `state`
  only; `_on_player_downed` on **neither**. `GameState.last_payout` was the
  pre-bank dict (`applied:false, banked:0`) and the escape/capture paths called
  `hud.has_method` with no null check (`:4407`, `:4430`) — the lead probe hit
  `SCRIPT ERROR: Cannot call method 'has_method' on a null value.` No test drove
  `_on_player_downed` or `_on_door_collapsed`, and none asserted that a failure
  path *banked*.
- S2 research: authored payout rules — 12 slots, minor 1 / major 3 / quest 1
  (`BP_TATPlayerState`), binary `kept_on_escape = 1.0` / `kept_on_capture =
  0.0`, stashed always kept, £1,000 Guildhall reward.
- S3 confirm (red):
  ```
  SCRIPT ERROR: Cannot call method 'has_method' on a null value.  (mission_controller.gd:4430 _on_player_downed, :4407 _on_extracted)
  FAIL: capture phase=main (want resolved)
  FAIL: capture last_payout applied=false banked=0 (want true/750)
  FAIL: main timeout last_payout applied=false banked=0
  FAIL: door collapse last_payout applied=false banked=0
  FAIL: escape last_payout applied=false banked=0
  ```
- S4 fix: one `_finish_run(outcome, reason, peer_id)`; the four handlers are
  thin wrappers. Guards split deliberately: **`GameState.state` gates the run**
  (a run resolves once) and **`_payout_applied` gates the payout** (a match
  banks once) — the historical door-collapse order banked then resolved
  unconditionally, and conflating the two left a run "playing" behind a result
  it had already lost (caught by `test_w7e_endgame` S5.5c during this wave; the
  guard split is the fix, not a test edit). `last_payout` now mirrors
  `SaveSystem.get_last_match()` (real `applied`/`banked`); every panel/show path
  null-checks `hud`; a non-persisted bank logs `push_error`.
- S5 test: suite 91 `_check_failure_banking` drives capture / main timeout /
  door collapse (currency delta == the 750 stashed exactly once,
  `state=="failed"`, `phase=="resolved"`, `last_payout.applied==true &&
  banked==750`, correct reason strings, repeat call inert) and
  `_check_escape_banking` (kept+stashed+reward once, then
  `SaveSystem.bank_payout(get_last_match())` → `duplicate`).
- S6 confirm: `PASS: T02-B capture/timeout/collapse bank the stash once and
  resolve`, `PASS: T02-B escape banks once and the match_id replay is a
  duplicate`, `W7E_SUMMARY: fails=0`.
- verdict: **FIXED**

## RE-N-15 — the Thieves' Den runs a live 5400 s clock (P2)

- severity: P2
- S1 investigate: `_apply_run_clock` ran for every map; `_process` then expired
  the hub and `_on_time_expired` wrote a `timeout` `last_match` with a
  `TIME EXPIRED` panel, while the HUD hides the objective/timer row in the hub.
- S2 research: `Mission.Tutorial.ThievesDen` / `QG_ThievesDen_Intro` with
  `mission_durations.thieves_den.durations = [5400, 3600, 2700]`
  (`game/data/generated/gameplay/contracts.json`) — authored for the tutorial
  **mission**, not the hub.
- S3 confirm (red):
  ```
  REDCHECK RE-N-15 hub_main_s=5400.0 hub_endgame_s=480.0 source=map_row (want 0/0/hub)
  REDCHECK RE-N-15 hub_state_after_6000s=failed reason=TIME EXPIRED (want playing, no reason)
  ```
- S4 fix: an early `map_id == "thieves_den"` branch in `_apply_run_clock` sets
  `run_time_limit = 0`, `endgame_time_limit = 0`, phase main, clears the
  markers, logs `hub=no_mission_clock` and returns sources `"hub"`. **No new
  `GameState.state` value**: the declared `"hub"` value is never written by any
  code path and 43 files read `state`, so a zero limit is the minimal honest
  fix (recorded as a deliberate decision).
- S5 test: suite 91 `_check_hub_clock` (0/0/`hub`/`hub`, 6000 s of `_process`
  leaves `playing` with no reason) plus a control: `guildhall` with no mission
  id still gets the authored 7200 `map_row`, proving the guard is Den-only.
- S6 confirm: `PASS: T02-B hub has no mission clock (Den-only guard)`.
- verdict: **FIXED**

## RE-N-14 — `active_map_seed` is never reset (P2)

- severity: P2
- S1 investigate: `start_contract` derived the seed only when it was `0`, and
  nothing wrote it back (`rg -n 'active_map_seed\s*=' game/src` → one writer).
  A session that entered the Den first reused `thieves_den|1` for every later
  mission; the pause footer showed the stale seed.
- S2 research: authored counterpart `_mapVariationMgr` on `BP_TATGameState` plus
  `SV_*` variants; the "deterministic per-contract seed" contract is the port's.
  The defect is that the seed lived per *process* instead of per *run*.
- S3 confirm (red):
  ```
  REDCHECK RE-N-14 seed_after_reset=123456 variants=1 (want seed 0, variants 0)
  ```
- S4 fix: `GameState.reset_run()` clears `active_map_seed = 0` and
  `active_scene_variants = []`; `start_contract` already re-derives both from
  `map|order` immediately after the reset, so a retry of the same contract is
  still deterministic and a different contract on the same map gets its own
  set.
- S5 test: suite 91 `_check_reset_clears` (seed 0 after two resets, variants
  cleared, distinct `loot_run_id`, map|order hashes differ).
- S6 confirm: `PASS: T02-B reset clears the run and republishes the phase`.
- verdict: **FIXED**

## RE-N-10 — cosmetics never reach the character (P2, GameState half)

- severity: P2
- S1 investigate: `wardrobe_ui.gd:1698-1712` persisted authored tags to
  `SaveSystem.equipped_loadout` but mirrored only **short** names into
  `GameState.outfit_head/body/calling_card`; `thief_character.gd:16-18`
  hard-codes the Nisha GLBs and reads no outfit state
  (`rg -n 'outfit' game/src/player game/src/core/level_loader.gd` → no hits).
  Nothing read the three fields.
- S2 research: 54 authored `Outfit.*` rows (`unlocks.json`); the per-thief
  skeletons `SK_ThiefNisha_Dyn__Body_NoPostProcABP.glb` (Nisha, `Dyn/`) and
  `SK_ThiefCotter__Body.glb` / `SK_ThiefCotter__Head.glb` (Cotter, directly
  under `Skin/Base/` — there is no Cotter `Dyn/` folder) — all verified on
  disk. The Chameleon is ThiefCotter, so a hard-coded Nisha body is the wrong
  skeleton, not just the wrong texture.
- S3 confirm (red):
  ```
  REDCHECK RE-N-10 gs_active_outfit=false gs_thief_body_mesh=false outfit_body_field=Default (want true/true/authored tag)
  REDCHECK RE-N-10 save_loadout_head= body=
  ```
- S4 fix (`game_state.gd`, data path only): `active_outfit()` and
  `outfit_tag(slot)` return the **authored** tag from
  `SaveSystem.get_loadout(thief_id)`, falling back to the authored
  `Outfit.<Thief>.<Slot>.Default` row (a fresh save stores `""` per slot);
  `thief_base_mesh("body"|"head"|"body_1p")` returns the per-thief GLB from the
  verified `THIEF_BASE_MESHES` table; an unknown thief id (the TAT-2 `moth`, no
  authored outfit rows) resolves to the Spider skeleton instead of nothing. The
  legacy `outfit_*` fields are documented as a readerless short-name mirror.
- S5 test: suite 93 (`run_tests.gd`): for both thieves every slot tag matches
  `Outfit.<Thief>.`, the Nisha and Cotter base meshes exist and differ, and
  writing a short name into the legacy `outfit_head` does **not** change
  `active_outfit()` (the save is the source of truth).
- S6 confirm: `PASS: 93 T02 identity contracts: authored Outfit.<Thief>.* tags,
  per-thief Nisha/Cotter base meshes present, legacy mirror inert, …`.
- verdict: **FIXED (GameState data path)**. Character bind **BLOCKED-ON
  T04-ANIM**; dropping the wardrobe's short-name writes **BLOCKED-ON T05**.

### BLOCKED-ON T04-ANIM — cosmetics contract

`thief_character.gd` must replace its three hard-coded Nisha constants with:

- `GameState.thief_base_mesh("body")` → 3P body, `("head")` → head,
  `("body_1p")` → viewmodel torso (verified for both thieves);
- `GameState.active_outfit()` → `{head, body, calling_card}` **authored tags**
  (never short names) for outfit-specific meshes;
- re-bind when `GameState.thief_id` changes (the Wardrobe already persists the
  per-thief loadout via `SaveSystem.set_loadout`).

Do **not** re-derive tag→mesh inside the character: the Wardrobe's
`COTTER_HEAD_MESHES` / `_resolve_body_path` tables are the single resolution
point (W7V) and a second table will drift.

## RE-N-12 — co-op is mislabelled as TAT-2 expansion (P2)

- severity: P2
- S1 investigate: `README.md:6,116` describe co-op as an addition of the TAT-2
  expansion; `net_manager.gd` carried no provenance marker (no
  `expansion: true`, no "invented" label), unlike `prep_skyline.json` /
  `content_overrides.json`.
- S2 research: the shipped build authors the multiplayer stack and the
  `XP.Cooperative` row (see RE-N-11 S2, paths verbatim from
  `extracted/filelist.txt`). The transport (Godot ENet, 2 players, port 7742)
  is from scratch with no shipped data input → invented.
- S3 confirm: this is a labelling/provenance defect, not a runtime bug; there
  was no machine-readable label to be wrong (`GameState` had no
  `coop_provenance`, the transport no marker), so the red proof is the absence
  of the record rather than a measurement. Stated as such.
- S4 fix: new tracked record `game/data/expansion/coop_provenance.json`
  (`expansion: false`, `transport_invented: true`, the authored assets with
  their `filelist` paths, the `XP.Cooperative` row with its `ST_PostMatch` key,
  the replicated/local-only lists and the `not_modelled` list), exposed by
  `GameState.coop_provenance()` / `coop_is_expansion()` so UI copy and reports
  read one label source; `net_manager.gd`'s header states the same.
- S5 test: suite 93 verifies `expansion == false`, `transport_invented == true`,
  `coop_is_expansion() == false`, that the recorded xp row is
  `XP.Cooperative` and that `GameData.get_xp_def("XP.Cooperative")` still
  resolves "Co-op Bonus"; when `extracted/filelist.txt` exists, every recorded
  shipped `file` must appear in it (a missing dump is a loud SKIP).
- S6 confirm: same PASS line as RE-N-10's suite 93.
- verdict: **FIXED (data + runtime label)**. The contract-table copy
  ("Host Co-op" / "Join Co-op") is `contract_table_ui.gd` → **BLOCKED-ON T05**:
  it should read `GameState.coop_provenance().label`, never describe co-op as
  expansion content.

## RE-N-16 — dead state; `phase_changed` never emitted by `reset_run` (P3)

- severity: P3
- S1 investigate: `phase_changed` was emitted only by `begin_endgame` /
  `resolve_phase`; `reset_run` assigned `phase = PHASE_MAIN` silently, so a
  listener desynced at every run start and the AGENTS §7 "phase_changed (QA
  hook)" contract had no reset edge. `active_match_mode` had **zero references**
  outside its declaration and its documented domain
  (`solo|coop_host|coop_client|ftue`) contradicted the live
  `active_mission_mode` domain (`"Solo"`/`"Co-op"`, toggled at
  `mission_controller.gd:1531`). `contract_title` is written by
  `request_mission_letter` and has no reader.
- S2 research: n/a (port-invented fields); `docs/reports/w7e-endgame.md:67`
  calls `phase_changed` the QA hook.
- S3 confirm (red):
  ```
  REDCHECK RE-N-16 phase_changed_emits_from_reset=0 phase_now=main (want 1 emit)
  ```
- S4 fix: `reset_run` captures `prev_phase` and emits `phase_changed(phase)`
  only on a real change (a reset from `main` is not a transition);
  `active_match_mode` is deleted with a comment naming `active_mission_mode` as
  the live label. `contract_title` is kept (it mirrors the authored briefing row
  the letter signal carries) and its reader is handed to T05 rather than
  inventing a consumer here.
- S5 test: suite 91 `_check_reset_clears` counts exactly one emit.
- S6 confirm: `PASS: T02-B reset clears the run and republishes the phase`.
- verdict: **FIXED** (dead field + signal edge); `contract_title` reader → T05.

## RE-N-04 residual — `get_loadout()` aliases the live save (P3)

- severity: P3
- S1: `get_loadout` shallow-merged, so `out["tools"]` was the live save array;
  a caller appending to it mutated persisted state without `write_save()`.
- S2: n/a (port API). The aliasing was latent (the wardrobe copies through
  `_normalize_slots`), so it is proved by the new test rather than a live
  failure.
- S3: suite 92 block 7 fails if the deep copy is removed (it appends to the
  returned `tools` and asserts the live save is unchanged).
- S4: `get_loadout` merges `(entry).duplicate(true)`.
- S5/S6: `PASS: T02 save integrity 7 (get_loadout hands out a copy; set_loadout
  round-trips)`.
- verdict: **FIXED (P3)**

## RE-N-01 / RE-N-02 / RE-N-05 / RE-N-07 / RE-N-09 / RE-N-13 / RE-N-17

Shorter entries; each reason is the decision of record.

### RE-N-01 — port-local session model (P3) — **PARTIAL**
Dead `active_match_mode` removed and `phase_changed` given its reset edge
(RE-N-16). `contract_title` and `extracted_players` remain: the first needs a
reader in T05's ledger/result panel, the second is only the local transport's
bookkeeping (`extracted_players` has no consumer; solo now registers nothing
because `local_peer_id()` is 0 — see Open risks). Not worth minting a consumer
in this wave.

### RE-N-02 — `save_schema = 8` is a label, not a history (P3) — **DEFERRED**
A versioned migration chain needs the shipped save layout, which is
UNEXTRACTED (`TATAtomicSave` descriptor only), and no player-visible behaviour
depends on it today. What was fixable was the *test*: 90.1/90.2 now pin the
persisted literals `8`/`1` instead of comparing a constant with itself, so a
silent bump is now visible. A real per-version chain is a separate design.

### RE-N-05 — downgrade drops unknown keys (P3) — **DEFERRED**
Forward compatibility needs a design decision (keep-unknown-at-root vs strict)
and an authored schema to migrate against; only one historical key
(`equipped_cosmetics`, removed at `d589169`) is affected. Not silently
re-baselined: the behaviour is still "unknown root keys are dropped", now
documented as a known limitation.

### RE-N-07 — XP/contract recording is not idempotent (P3) — **DEFERRED**
The shipped `DT_PlayerExperience` has 11 categories (including
`XP.Cooperative`) and `DT_PlayerStats` 5 statistics; awarding them correctly
needs the post-match screen (T05) and T01's table consumer. In-process double
counting is already prevented (`_finish_run`'s state guard); the port's invented
`xp += max(100, score/2)` is unchanged and remains a KNOWN gap.

### RE-N-09 — two purchased unlock families gate nothing (P3) — **BLOCKED-ON T05**
The gate belongs in `contract_table_ui.gd` (`UnlockCatalog.conditions_met` at
the difficulty/map selectors), which is T05's file. Contract for T05: gate the
three difficulty rows and `Map.OldManor` on `is_unlocked("perks", id)` /
`UnlockCatalog.conditions_met`, or stop selling them.

### RE-N-13 — `free_play_pending` is sticky (P3) — **DEFERRED**
`free_play_pending` is the *retry* stage: clearing it in `reset_run` would drop
free play when `mission.tscn` reloads (the deploy closure re-stages it
deliberately). The correct fix is a `run_started` latch owned by T10's deploy
path, not a GameState-only clear.

### RE-N-17 — abandoning a run leaves no record; the session is never closed (P3) — **DEFERRED**
Both exits live outside this team: "Return to Thief's Den" and the result panel
are `hud.gd` (T05), and `disconnect_net()` has no caller because every
scene-change caller is a UI transition. Contract for T05/T10: call
`NetManager.disconnect_net()` when leaving a session (pause → Den and result →
startscreen) and decide whether an abandon writes a `last_match`
(`_exit_tree` is too late to distinguish a quit from a deploy reload).

## Register (all 18 findings)

| id | severity | verdict | one-line reason |
|---|---|---|---|
| RE-N-01 | P3 | PARTIAL | dead `active_match_mode` removed; `contract_title`/`extracted_players` remain (readers need T05 / have no consumer) |
| RE-N-02 | P3 | DEFERRED | shipped save layout UNEXTRACTED; 90.1/90.2 now pin literals so a bump is visible |
| RE-N-03 | P1 | **FIXED** | corrupt save quarantined whole, reported, never replaced; that boot writes nothing |
| RE-N-04 | P3 | **FIXED** | `get_loadout` returns a deep copy (test proves the alias is gone) |
| RE-N-05 | P3 | DEFERRED | forward-compat needs an authored schema; documented limitation |
| RE-N-06 | P1 | **FIXED** | `write_save -> Error` with read-back validation; outbox staged by `bank_payout`, settled once |
| RE-N-07 | P3 | DEFERRED | authored XP categories need the post-match screen (T05) + T01 tables |
| RE-N-08 | P2 | **FIXED** | one `_finish_run`; run/payout guards split; banked record mirrored; hud null-deref removed |
| RE-N-09 | P3 | BLOCKED-ON T05 | the gate is `contract_table_ui.gd` |
| RE-N-10 | P2 | **FIXED** (GameState) | authored tags + per-thief meshes exposed; bind BLOCKED-ON T04-ANIM, writes BLOCKED-ON T05 |
| RE-N-11 | P1 | **FIXED** | host-authoritative outcome replication; client resolves as victory on a host escape |
| RE-N-12 | P2 | **FIXED** (label) | `coop_provenance.json` + `GameState.coop_provenance()`; UI copy BLOCKED-ON T05 |
| RE-N-13 | P3 | DEFERRED | pending is the retry stage; needs T10's deploy latch |
| RE-N-14 | P2 | **FIXED** | `reset_run` clears the seed; `start_contract` re-derives per deploy |
| RE-N-15 | P2 | **FIXED** | the Den hub runs no mission clock (zero limit, no new state value) |
| RE-N-16 | P3 | **FIXED** | `reset_run` emits `phase_changed`; dead `active_match_mode` removed |
| RE-N-17 | P3 | DEFERRED | exits are T05 UI; `disconnect_net()` contract handed over |
| RE-N-18 | P3 | **FIXED** (coverage) | suites 91/92/93 + 80.3/80.4/90.1/90.2/49/S2-10/S2-12 replaced with behavioural assertions |

## Team summary

| verdict | count | ids |
|---|---|---|
| FIXED | 11 | 03, 04, 06, 08, 10, 11, 12, 14, 15, 16, 18 |
| PARTIAL | 1 | 01 |
| DEFERRED | 5 | 02, 05, 07, 13, 17 |
| BLOCKED-ON T05 | 1 | 09 |

Two **BLOCKED-ON** contracts also ride on FIXED findings: T04-ANIM (cosmetics
bind, RE-N-10) and T05 (wardrobe writes RE-N-10, co-op UI copy RE-N-12,
`contract_title` reader RE-N-16, `disconnect_net` RE-N-17, unlock gates
RE-N-09).

Test growth: `run_tests` 278 → **297** PASS, `fails=0` (suite 91 = 9 blocks,
suite 92 = 7 blocks, suite 93 = 1 block). E2E unchanged at 278/278 with two
tautologies replaced by behavioural assertions. No test was deleted, skipped or
weakened; the only expectation changes are the ones adjudicated in RE-N (the
intentional ones: 90.1/90.2 literals, 80.3/80.4 source text, 49's vacuous
`currency >= 0`, E2E S2-10/S2-12), each proved to be a test defect.

## Doc corrections (for the integrator; no docs were edited by this team)

1. **`AGENTS.md` §Known traps — add the corrupt-save contract.** A save that
   exists but cannot be read or whose JSON root is not an object is quarantined
   to `user://tat2_save.json.corrupt-<unix_ts>` and **that boot does not write
   defaults**. The API is `SaveSystem.has_load_failure()` /
   `get_load_failure()` and the signal `load_failed(reason, backup_path)` —
   GDScript forbids a `load_failed` variable alongside the signal.
   Quarantine is a **port decision** (the shipped `TATAtomicSave` only promises
   temp+rename).
2. **`AGENTS.md` §Commands/gates — counts.** compile is now **122** checked
   (was 120; +2 T02 suites), `run_tests` is **297** PASS (was 278). `make
   audit`, `make gate-ratchet`, E2E 278/278, m2 11, perf 78/78 are unchanged.
3. **`AGENTS.md` §7 runtime contracts — add the co-op run-outcome contract and
   the save API changes.** `NetManager.run_requested` / `run_resolved`,
   `RUN_OUTCOMES = {escape,capture,timeout}`, host-only
   `broadcast_run_resolved`, clients never broadcast; `write_save()` returns
   `Error`; `bank_payout` returns `persisted`/`write_error`/`outbox_error` and
   stages the outbox; `GameState.reset_run` clears `active_map_seed` and emits
   `phase_changed`; the Den hub has no mission clock; `active_match_mode` no
   longer exists.
4. **`README.md:6,116`** — co-op is a **shipped feature**; only the Godot ENet
   transport is TAT-2-invented. Cite `coop_provenance.json` and
   `GameState.coop_provenance().label`. Never list co-op under "the TAT-2
   expansion adds".
5. **`README.md:170` / `FIDELITY_GAPS.md`** — the KNOWN line "the two-phase
   timer banks local-only in co-op" is now wrong for **escape**: the host banks
   the run and broadcasts the banked record; clients apply it (same `match_id`,
   same numbers, own profile). A client's **failure** paths (capture, door
   collapse, its own main-clock expiry) still resolve locally; no lobby/ready
   sync; `disconnect_net()` still has no caller.
6. **`docs/reports/gameplay-truth-wave.md:30/45`** — "corrupt save is no longer
   silently overwritten" only becomes true with this wave; re-date it.
7. **`docs/reports/w7e-endgame.md`** — (a) "client-side host RPC replication is
   deferred" is superseded by RE-N-11 (keep the report historical, add a
   pointer); (b) "`phase_changed` is the QA hook" is now true from `reset_run`
   too; (c) add that the Den hub owns no mission clock.
8. **`docs/ARCHITECTURE.md:65`** — the autoload list omits `Loc` (found by
   RE-N; doc-only), and the save row should mention the `path_override` test
   seam and the quarantine files.
9. **`docs/HANDOFF_NEXT_AGENT.md:59`** — replace the co-op residual with the
   list in Open risks below; note the new suites 91–93 and the 122/297 counts.
10. **`FIDELITY_GAPS.md`** — close RE-N-03/06/08/11/14/15/16; note RE-N-15's
    `GameState.state=="hub"` is still unused by design; note the Den duration
    row remains authored for the tutorial mission.

## Open risks

1. **Co-op is not verified in a live two-process ENet run.** No tier-5 gate
   exists; the transport's `apply_run_resolved` RPC gates (remote sender,
   8 KiB, JSON object) can only be exercised with a real peer, so they are
   enforced but only inspection-tested. The *client handler* is tested through
   the signal. Treat the protocol as port design pending a live run.
2. **A client's own clock expiry / capture / door collapse stays local.** If
   the client's clock expires before the host's record arrives it banks the
   stash-only timeout and then refuses the host's record (`state != playing`).
   Documented residual; host-clock sync is out of scope.
3. **No lobby/ready/start sync and no session teardown.** Joining only sets the
   peer; each side deploys independently; `disconnect_net()` has no caller, so
   `is_coop` is process-lifetime and a host cannot stop being the host.
4. **The protocol does not carry the reason string**, so a host door-collapse
   renders as the default "TIME EXPIRED" copy on the client.
5. **Trust model:** a client applies any host `run_resolved` with an allowlisted
   outcome; there is no per-run handshake, so a stale/replayed host record could
   resolve a fresh client run. The host is authoritative by design; the replay
   window is bounded only by the client's own resolved state.
6. **The run-request cooldown uses wall-clock `Time.get_ticks_msec`**; a paused
   or blocked process could allow two requests inside one second.
7. **Solo `GameState.extracted_players` is now empty** (it used to get `[1]`
   from the hard-coded default). The field has no consumer, but it is a
   behaviour change worth knowing; if a future host-once guard needs it,
   register `local_peer_id()` even when 0.
8. **`bank_payout` now writes twice** (stage + apply) and `write_save` reads
   each payload back. Negligible for a match, but a settings-slider drag now
   costs a read-back per commit.
9. **Quarantine is port behaviour.** The shipped plugin only promises
   temp+rename; do not cite quarantine as authored.
10. **`make audit` needs `tools/bin/vgmstream`**, which is gitignored and was
    absent from this worktree; it was copied from the main checkout (a worktree
    setup gap, not a code change). A fresh remediation worktree needs the same
    copy or `make audit` fails on the audio join.
11. **T02 touched `_apply_run_clock`** (one early-return guard + log) although
    clock code belongs to T10-GAMEPLAY. It is the only way to stop the hub
    clock at the owning layer; the integrator should expect a small conflict
    with T10's wave and keep both intents.
12. **`test_w7e_endgame` reuses one mission instance across simulated runs**
    (it resets GameState, not the mission's `_payout_applied`). The guard split
    in `_finish_run` keeps it passing and matches the pre-consolidation order;
    if a future wave resets `_payout_applied` per simulated run, both behaviours
    still hold.
13. **`user://t02_save_integrity/`** is created and emptied by suite 92; the
    empty directory can remain in `user://` (cosmetic).
14. **Suite 49's `.corrupt-<ts>` artefact** is now deleted by the suite itself;
    before this wave every `make test` left one behind.
