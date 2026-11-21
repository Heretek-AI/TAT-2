# task-p0-clipsync — Takedown clips resolve by name; victim path explicit

Date (UTC): 2026-11-20. Scope: AUDIT.md §2 item 7
(core P0-2 `animation_library.gd:~660/~700` first-clip ignore +
gameplay victim-sync `guard_ai.gd:411` `play_takedown_vic` uncalled,
attacker montage fires on whiff `thief_character.gd:1759`).
Only the two allowed span families were edited; no state-machine
transition spans were touched (`ALERTNESS_RANK`, `_set_state`,
`_enter_*`, SEARCH/SUSPICIOUS/ALERTED/COMBAT promotion logic all
untouched — verified by diff grep returning zero transition-span hunks).

## 1. Ground-truth spans reproduced before editing

- `game/src/core/animation_library.gd` `_load_source`, both load paths:
  ```gdscript
  for an in lib.get_animation_list():
      if anim == null:
          anim = lib.get_animation(an) as Animation
  ```
  (ResourceLoader path and GLTFDocument fallback path — first animation
  wins, requested `clip_name` never compared. A takedown GLB packing
  Atk+Vic takes silently plays the wrong side.)
- `game/src/ai/guard_ai.gd:411` `func play_takedown_vic() -> void:` —
  silent no-op guards (`return` with no warning) and zero callers
  (grep-verified); `knock_out()` (`:1197-1203`) duplicated the victim
  play inline instead of calling it.
- `game/src/player/thief_character.gd:1759` `_tp_takedown_atk_start()`
  fires before the hit test (`:1764-1768`) — read-only witness; NOT
  edited (out of authorized scope). Victim wiring was therefore done
  guard-side (take_knockout -> knock_out -> play_takedown_vic), which
  the authorized spans permit.

## 2. Edits

**`game/src/core/animation_library.gd` — `_load_source` only (+ one
adjacent helper, same span region):**
- New `static func _pick_named_animation(players, clip_name)`: pass 1
  exact-name match; pass 2 contains-match (importer renames) with a loud
  `push_warning` naming the substitution and flagging Atk-vs-Vic side
  risk; else first animation with a loud `push_warning` naming the
  mismatch. Null when no player carries any animation (caller keeps its
  existing `could not load clip` warning path).
- Both load paths (ResourceLoader-instantiated and GLTFDocument-
  generated) now call `_pick_named_animation(players, clip_name)`
  instead of taking the first animation. Skeleton-rest harvesting and
  caching are unchanged.

**`game/src/ai/guard_ai.gd` — victim spans only:**
- `play_takedown_vic()`: kept the no-crash contract, but both no-op
  paths now `push_warning` with the loud UE path
  (`TAT/Content/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__Vic_Montage`).
  Doc comment updated: wired via take_knockout -> knock_out.
- `knock_out()`: deleted the duplicated inline victim-play block and
  replaced it with an explicit `play_takedown_vic()` call; returns when
  `_takedown_vic_anim` is set, else loud fallback warning citing the UE
  clip and continues to the knockdown loop; added a final loud warning
  when the knockdown role is missing too (procedural tween owns KO).
- Dead-path decision: the API was wir**ed**, not deleted — the takedown
  KO path (`take_knockout` -> `knock_out`) is a real consumer, so the
  explicit-call option from the brief applies.

## 3. Resolve proof per clip (referenced -> manifest -> GLB on disk)

`ANIM_BASE` (`res://assets/ue/Anims/`) + manifest `glb`, checked with
`os.path.exists` on `game/assets/ue/Anims/<glb>`. All 8 distinct
`AN_*` takedown clips referenced by `CLUB_CLIPS`/`HA_CLIPS`
`takedown_vic` (6) and `TP_TAKEDOWN_CLIPS` (3, one overlap):

| Referenced clip | Manifest `glb` | On disk |
|---|---|---|
| AN_StealthTakedown_GuardEnforcer__Vic_Montage | TAT/Content/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__Vic_Montage.glb | OK |
| AN_StealthTakedown_GuardEnforcer__Vic | TAT/Content/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__Vic.glb | OK |
| AN_TakedownOverhead_Behind_Montage | TAT/Content/Art/Animation/Base/Anim/Synced/AN_TakedownOverhead_Behind_Montage.glb | OK |
| AN_TakedownOverhead_Behind | TAT/Content/Art/Animation/Base/Anim/Synced/AN_TakedownOverhead_Behind.glb | OK |
| AN_TakedownOverhead_Front_Montage | TAT/Content/Art/Animation/Base/Anim/Synced/AN_TakedownOverhead_Front_Montage.glb | OK |
| AN_TakedownOverhead_Front | TAT/Content/Art/Animation/Base/Anim/Synced/AN_TakedownOverhead_Front.glb | OK |
| AN_StealthTakedown_GuardEnforcer__Atk_Montage | TAT/Content/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__Atk_Montage.glb | OK |
| AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage | TAT/Content/Art/Animation/Thief/Anim/Gear/BlackJack/AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage.glb | OK |

Manifest holds 30 takedown rows total (995 entries); the 8 above are
every takedown clip the edited tables can request. Quarantine clips
(`AN_Takedown_Fall*_Vic*`, `AN_Takedown_Guard_Heavy_Front_Atk*`,
`AN_BlackJack_Takedown_In/Loop*`) remain unreferenced by design.

## 4. Verify performed (file-level + targeted, no `make test` per brief)

- Re-read both edited spans post-edit; behavior: name match wins,
  mismatch warns loudly, victim path is `take_knockout -> knock_out ->
  play_takedown_vic` with loud fallback to knockdown loop then tween.
- Grep-confirmed every referenced takedown clip resolves to a manifest
  entry whose GLB exists on disk (table above, 8/8 OK, 0 missing).
- `git diff` on the two files shows only the `_load_source`/helper and
  victim-span hunks; transition-span grep over the diff is empty.
- Full-suite `make test` NOT run (orchestrator runs it at settle).

## 5. Assumptions / follow-ups

- Manifest `animation` names equal GLB animation names (true for the
  shipped extractor output); contains-match + warning covers renames.
- Attacker-on-whiff (`thief_character.gd:1759` firing before the hit
  test) is intentionally untouched — out of scope; a follow-up task
  with thief-span authorization should move `_tp_takedown_atk_start()`
  behind the hit test / KO transition.
