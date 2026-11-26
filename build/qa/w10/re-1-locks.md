# RE-1 (W10-A) — is the Guildhall prison door pickable, or key-only?

Wave: W10-A defect 8. Worker: RE-1. Worktree: `/home/john/Projects/TAT-2-rem-w10-a`.
Read-only investigation against the shipped UE5.5 dump (`extracted/`, symlink, not modified).
No Godot run. No game source touched. This is the only file created.

**VERDICT: pickable as authored.** A `KeyTag` without `CanBeLockpicked` is *not* a
key-only declaration. `CanBeLockpicked` is the lockpick gate and its un-authored value
resolves to **`true`** for `TATSwingingDoor` — so `StaticMeshActor_528` is authored as
*pickable* (with a key tag that, for this actor, binds no key item), exactly what the port
does today (`game/src/interact/swinging_door.gd:128-137`).

Secondary finding, same actor, different question: the port locks it at **level 1**, but
the *authored* `MaxLockLevel` resolves to **4** (inherited from `BP_SwingingDoor_C`). The
producer only emits the instance delta, so the cap never reaches the record. That is a
completeness bug in the generated data, not a pickability bug — see §7.2.

---

## 0. Answer in one line each

| Question | Answer |
|---|---|
| Is the pickable treatment authored? | **Yes** — absence of `CanBeLockpicked` means "inherit", and the inherited value is `true`. |
| Should `KeyTag`-only mean key-only? | **No.** 26 of the 33 placed `CanBeLockpicked:false` authors have **no** `KeyTag`; the flag means "cannot be picked", not "needs a key". |
| Is `StaticMeshActor_528` locked? | **Yes** — `_locked: true` authored on the instance (`Building_Guildhall_POI.json:101439`, object #1417). The port's `locked == true` gate therefore fires. |
| Does it have a key that opens it? | **No binding.** It is the only one of 23 key-tagged POI actors with no `KeyItemInfo`; the other 22 bind `BP_Key_POI_Guildhall_ItemInfo_C`. Key-only would be unopenable. |
| Can the dump prove the C++ default? | Not directly (0 `/Script` packages are dumped). It proves the *resolved value* mechanically via delta serialization: **`true`**. §3. |

---

## 1. Inheritance chain and every CDO's `_lockConfig`

The dump records the BP parent two ways: `Super` (parent is a Blueprint) and
`SuperStruct` (parent is native). `BP_SwingingDoor_C` is the deepest BP in this chain and
its parent is the native `TATSwingingDoor`; no native class JSON exists in the dump
(§3.4), so the chain terminates there.

| # | Class | File / object index | Parent (as dumped) | CDO `_lockConfig` (verbatim) |
|---|---|---|---|---|
| 0 | `StaticMeshActor_528` (placed) | `Maps/Buildings/Guildhall/Building_Guildhall_POI.json` **#1417**, name line 101352 | `Template` → `Default__BP_Prison_WallA_DoorwayB2_6x6_C` | `{"KeyTag": {"TagName": "Item.Key.Buildings.Guildhall"}}` + `_locked: true` |
| 1 | `BP_Prison_WallA_DoorwayB2_6x6_C` | `Art/Environment/Prison/BP_Prison_WallA_DoorwayB2_6x6.json` **#6** `Default__…`, line 211 | `Super` → `BP_SwingingDoor_DoubleBase_C`; `Template` → `Default__BP_SwingingDoor_DoubleBase_C` | **absent** |
| 2 | `BP_SwingingDoor_DoubleBase_C` | `Gameplay/Interactables/Doors/BP_SwingingDoor_DoubleBase.json` **#6** | `Super` → `BP_SwingingDoor_C`; `Template` → `Default__BP_SwingingDoor_C` | **absent** |
| 3 | `BP_SwingingDoor_C` | `Gameplay/Interactables/Doors/BP_SwingingDoor.json` **#7**, `_lockConfig` at line 591 | `SuperStruct` → `Class'TATSwingingDoor'` (`/Script/TAT`); `Template: null` | `{"MaxLockLevel": 4, "LockedInteractStatusTag": {"TagName": "Interaction.Status.Locked"}, "UnlockedInteractStatusTag": {"TagName": "Interaction.Status.Unlocked"}}` |
| 4 | `TATSwingingDoor` (native C++) | not in the dump | — | not observable |

Consequences of the chain, once §2 is accepted:

* `CanBeLockpicked` is authored **nowhere** in the chain ⇒ it equals the native value.
* `MaxLockLevel` is authored **once**, at `#3`, as `4` ⇒ the resolved cap for the prison
  door is **4**, not "none". `MinLockLevel` is authored nowhere ⇒ native value (unreadable).
* The `Interaction.Status.Locked` / `Unlocked` status tags are also inherited from `#3`.
  The port has no tag model; that is pre-existing and out of scope.

---

## 2. The dump serializes a **delta against the archetype** — proved from the data

This is the crux. If absence meant "the value is false/default-in-this-class", the port's
rule would be right by accident; if absence means "inherit", the port's rule is right by
design. The dump settles it, three independent ways.

### 2.1 Every object names its archetype in `Template`

```
Default__BP_SwingingDoor_C            Template: null                       (root BP; archetype is the native CDO)
Default__BP_SwingingDoor_DoubleBase_C Template: Default__BP_SwingingDoor_C
Default__BP_Prison_WallA_DoorwayB2_6x6_C Template: Default__BP_SwingingDoor_DoubleBase_C
StaticMeshActor_528                   Template: Default__BP_Prison_WallA_DoorwayB2_6x6_C
```

A full dump would repeat `_lockConfig` on `DoubleBase` and on the prison CDO. Both are
empty, while `#3` authors `MaxLockLevel: 4`. The only reading that fits is
**Properties = the delta vs. the named `Template`**.

### 2.2 The `_locked` corpus is a closed, self-consistent delta system (6/6, no exceptions)

Every CDO in all 12,541 JSONs that authors `_locked`, with its parent's resolved value:

| CDO | authored `_locked` | parent | parent's value | consistent with delta? |
|---|---|---|---|---|
| `BP_SlidingWindow_Base_C` (#4) | `true` | `BP_OSESimpleWindow_C` → native `TATOpenableWindow` | not authored | yes (`true` ≠ inherited) |
| `BP_Dumbwaiter_C` (#4) | `false` | `BP_SlidingWindow_Base_C` | **`true`** | yes (`false` is a change) |
| `BP_Urban_Window_4x6_C` (#4) | `false` | `BP_SlidingWindow_Base_C` | **`true`** | yes |
| `BP_LargeFancySafe_C` (#2) | `true` | native `TATLockableToggle` | not authored | yes |
| `BP_SmallSafe_C` (#2) | `true` | native `TATLockableToggle` | not authored | yes |
| `BP_SmallSafe_MajorLoot_C` (#2) | `false` | `BP_SmallSafe_C` | **`true`** | yes |

Every explicit `false` sits on a `true` parent; every explicit `true` sits on a
non-`true` parent. If the dump were a full dump there would be thousands of
`_locked: false`; there are three, and each is a genuine change. If the dump were a
diff-against-*native* dump, `BP_Dumbwaiter_C`'s `false` would be a no-op and would not
be written. Both alternatives are excluded.

The same is visible at placement level: the two FTUE bay windows
(`Maps/FTUE/FTUE_Building_SpawnArea.json` **#58/#59**, `StaticMeshActor_82/87`) author
`_locked: false`; their class `BP_Urban_Ext_BayWindow_C` authors no `_locked` and inherits
`true` from `BP_SlidingWindow_Base_C`. The `false` is written because it is a change.

### 2.3 No field is being *dropped* by the deserializer

Absence could otherwise mean "the dumper could not map this property". Each field inside
`_lockConfig` appears on some object in the corpus — `MaxLockLevel` (31 CDOs),
`MinLockLevel`, `KeyTag`, `KeyItemInfo`, `CanBeLockpicked`, `IncorrectKeyTags`,
`IncorrectKeyMessage`, `LockedInteractStatusTag` — so the struct is mapped field-by-field
and a missing field is a real "equal to archetype", not a parse failure.

The dump is produced by CUE4Parse 1.2.2 (`tools/tat-extract/tat-extract.csproj`), which
serialises the *raw tagged properties* (`tools/tat-extract/Exporter.cs:110,163`). Raw
tagged properties are exactly the delta set.

---

## 3. What `CanBeLockpicked` resolves to

### 3.1 Census of every explicit author in the dump (4 CDOs, 33 placements)

| Object | Explicit value | Its parent's value | Meaning |
|---|---|---|---|
| `BP_SlidingWindow_Base_C` CDO (#4, line 231) | **`false`** | *not authored anywhere in the chain* | inherited value must be `true` |
| `BP_Dumbwaiter_C` CDO (#4) | `true` | `false` (from the line above) | consistent |
| `BP_Urban_Window_4x6_C` CDO (#4) | `true` | `false` | consistent |
| `BP_Urban_Ext_BayWindow_C` CDO (#4) | `true` | `false` | consistent |
| 33 placed actors (10 classes) | **all `false`, zero `true`** | class value `true` in every case | consistent |

There is **not one** placed actor anywhere in the dump that authors `CanBeLockpicked: true`.
Under the "default false" hypothesis, every pickable locked thing in the shipped game would
have to be pickable by accident, and the three `true` authors would be no-ops that the
serializer would have discarded.

### 3.2 The decisive same-chain case: a *door* under `TATSwingingDoor` that authors `false`

`Maps/FTUE/FTUE_Building_SpawnArea.json` **#53**, actor `BP_Manor_Doorway_4x6_C_2`
(class `BP_Res_Int_Doorway_C`, line 2154), lines 2261-2263:

```json
"_locked": true,
"_lockConfig": { "CanBeLockpicked": false, "KeyTag": {"TagName": "Item.Key.Buildings.Apartment"}, ... }
```

Its chain is `BP_Res_Int_Doorway_C` (`_lockConfig: {MaxLockLevel: 2}`, line 315 — **no**
`CanBeLockpicked`) → `BP_SwingingDoor_DoubleBase_C` (none) → `BP_SwingingDoor_C` (none) →
`TATSwingingDoor`. That is the prison door's chain minus one level. Because the `false` is
written on the instance, the inherited value for `TATSwingingDoor` **must be `true`**.

So: the designers make a door key-only by writing `CanBeLockpicked: false` explicitly.
They did **not** write it on `StaticMeshActor_528`. Under the delta rule, the prison door
resolves `CanBeLockpicked = true`.

Independent confirmation from a second family (`TATLockableToggle`): `BP_ChestTrunk_C`'s CDO
carries `{MaxLockLevel: 4, status tags}` and no `CanBeLockpicked`; the placed
`BP_ChestTrunk_C_1` (`Maps/Guildhall/Guildhall_Gameplay.json` #1819) authors
`CanBeLockpicked: false`. Same conclusion, different native root ⇒ it is the struct default,
not a per-class fluke.

### 3.3 The flag does not mean "key"

Only 7 of the 33 placed `false` authors carry a `KeyTag`; **26 carry none** (e.g.
`BP_VaultDoor_Sliding_StartsOpen_C`, `BP_LargeFancySafe_CombinationLock_C`,
`BP_SmallSafe_C_1`). `CanBeLockpicked: false` = "no picking", full stop. A key is a separate
axis, and the game supports both at once — `ST_Lockpicking` has distinct prompts for
`LockPicking.Lock.KeyUnlock` ("Unlock with Key"), `LockPicking.Lock.KeyRequired`
("Requires {Key} to Unlock"), `LockPicking.Lock.NoPicking` ("LOCKED") and
`Lockpicking.Pompt.Start` ("Pick Lock"). `BP_SwingingDoor_C` even carries separate
`KeyDirection` and `LockpickableDirection` entries in `_lockdownAllowedDirections`.
(String table = vocabulary evidence, not control flow — labelled as such.)

### 3.4 No native declaration is in the dump

* `grep -rl '"Package": "/Script' extracted/json | wc -l` → **0**. Native `/Script/TAT`
  packages are not exported, so there is no `TATSwingingDoor`/`TATLockableToggle` CDO and no
  UPROPERTY initialiser to read.
* `TATDoor` → **0** occurrences anywhere. `TATLockable*` → `TATLockableToggle` (9),
  `TATLockableToggleDirection` (18), `TATLockableInterface` (2). `TATSwingingDoor` → 14.
* `Interaction.Status.Locked` → 12 files (BP CDOs + maps).

So the C++ initialiser is **not observable**. What is observable is the value it must hold:
`true`. That is an inference about a binary we cannot read, but it is forced by the
delta semantics proven in §2 and corroborated by two independent native families and by a
door on the same native class.

---

## 4. What the level actually places

### 4.1 `Building_Guildhall_POI` — every actor with `_lockConfig` (37)

`Source`: `extracted/json/Maps/Buildings/Guildhall/Building_Guildhall_POI.json`.
`<ABS>` = not authored on the instance ⇒ inherited (see §2).

| # | Actor | Class | `_locked` | `CanBeLockpicked` | `KeyTag.TagName` | Min | Max |
|---|---|---|---:|---|---|---:|---:|
| 889 | `BP_Manor_Porch_Door_8x8_C_0` | `BP_Civic_Doorway_6x8_C` | `<ABS>` | `<ABS>` | `Item.Key.Buildings.Guildhall` | 2 | 3 |
| 890 | `BP_Manor_Porch_Door_8x8_C_1` | `BP_Civic_Doorway_6x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | 2 | 3 |
| 891 | `BP_Manor_WindowB_4x8_Reinforced_C_14` | `BP_Civic_Doorway_6x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | 2 | 3 |
| 892 | `BP_Manor_WindowB_4x8_Reinforced_C_328` | `BP_Civic_Doorway_6x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 2 |
| 893 | `…_333` | `BP_Civic_Doorway_6x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 2 |
| 894 | `…_70` | `BP_Civic_Doorway_6x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 2 |
| 895 | `…_9` | `BP_Civic_Doorway_6x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | 2 | 3 |
| 896 | `StaticMeshActor_1570` | `BP_Civic_Doorway_6x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 2 |
| 897 | `StaticMeshActor_1302` | `BP_Civic_Int_DoorwayD_6x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 2 |
| 898 | `StaticMeshActor_1550` | `BP_Civic_Int_DoorwayD_6x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 2 |
| 899 | `StaticMeshActor_1602` | `BP_Civic_Int_DoorwayD_6x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | 3 | 3 |
| 900 | `StaticMeshActor_848` | `BP_Civic_Int_DoorwayD_6x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 2 |
| 917-934 (14) | `BP_Manor_WindowB_4x8_Reinforced_C_{0,1,11,2,20,21,22,23}` + `StaticMeshActor_{183,289,3055,3056,3058,3059}` | `BP_Civic_WindowC_6x8_Closed_C` | `<ABS>` | **`false`** | `<none>` | `<ABS>` | `<ABS>` |
| 1239 | `StaticMeshActor_1599` | `BP_Manor_Doorway_4x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 1 |
| 1240 | `StaticMeshActor_1601` | `BP_Manor_Doorway_4x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 1 |
| 1241 | `StaticMeshActor_3519` | `BP_Manor_Doorway_4x8_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 1 |
| 1242 | `StaticMeshActor_1606` | `BP_Manor_Doorway_4x8_Shutterdoors_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 1 |
| 1243 | `StaticMeshActor_1607` | `BP_Manor_Doorway_4x8_Shutterdoors_C` | `<ABS>` | `<ABS>` | `…Guildhall` | `<ABS>` | 1 |
| 1415 | `BP_Prison_WallA_DoorwayA_6x6_C_0` | `BP_Prison_WallA_DoorwayA_6x6_C` | `<ABS>` | `<ABS>` | `…Guildhall` | 2 | 2 |
| 1416 | `StaticMeshActor_4949` | `BP_Prison_WallA_DoorwayB2_6x6_C` | `<ABS>` | `<ABS>` | `…Guildhall` | 2 | 3 |
| **1417** | **`StaticMeshActor_528`** | `BP_Prison_WallA_DoorwayB2_6x6_C` | **`true`** | **`<ABS>` ⇒ `true`** | `…Guildhall` | `<ABS>` | **`<ABS>` ⇒ 4** |
| 1418 | `StaticMeshActor_571` | `BP_Prison_WallA_DoorwayB2_6x6_C` | `<ABS>` | `<ABS>` | `…Guildhall` | 3 | 3 |
| 1419 | `BP_Doorless_Civic_DoorA_Wall_Int_6x6_C_281` | `BP_Prison_WallA_DoorwayB_6x6_C` | `<ABS>` | `<ABS>` | `…Guildhall` | 2 | 3 |
| 1420 | `BP_Prison_WallA_DoorwayB_6x6_C_0` | `BP_Prison_WallA_DoorwayB_6x6_C` | `<ABS>` | `<ABS>` | `…Guildhall` | 3 | `<ABS>` |

Counts: **37** actors with `_lockConfig`; **1** authors `_locked` (`StaticMeshActor_528`);
**14** author `CanBeLockpicked` (all `false`, all the `Civic_WindowC_6x8_Closed` windows);
the remaining **23** are doors with a `KeyTag` and no lockpick flag ⇒ pickable if locked.

`StaticMeshActor_528` verbatim (`Building_Guildhall_POI.json:101439-101444`):

```json
"_locked": true,
"_lockConfig": { "KeyTag": { "TagName": "Item.Key.Buildings.Guildhall" } }
```

It is the **only locked actor in the POI**, and its siblings (`_4949`, `_571`) are unlocked
despite carrying explicit Min/Max caps. The prisoner's cell door is a deliberate singleton.

It is also the **only one of the 23 key-tagged actors in the POI with no `KeyItemInfo`**:
the other 22 bind `KeyItemInfo: BlueprintGeneratedClass'BP_Key_POI_Guildhall_ItemInfo_C'`,
`StaticMeshActor_528` binds nothing. So its key path is not wired to a concrete key item at
all, while its lock is on. A "key-only" reading of this actor would therefore leave *no key
in the game that opens it* — the cell would only be enterable by picking, which is what the
`CanBeLockpicked` default already permits.

### 4.2 OldManor and FTUE — do they carry prison / key-only doors?

| Map | Actor | Class | `_locked` | `CanBeLockpicked` | Key | Max | Reading |
|---|---|---|---|---|---|---|---|
| `OldManor_Geo` #2063/2064/2066 | `BP_Prison_WallA_DoorwayB2_6x6_C_*`, `StaticMeshActor_1983` | `BP_Prison_WallA_DoorwayB2_6x6_C` | `<ABS>` | `<ABS>` | `…OldManor` | 2 | **unlocked** in the OldManor, the same class as the Guildhall prison door |
| `OldManor_Geo` #2067/2068 | `…DoorwayA_6x6_C_1`, `StaticMeshActor_765` | `BP_Prison_WallA_DoorwayB_6x6_C` | `<ABS>` | `<ABS>` | `…OldManor` | 2 | unlocked |
| `OldManor_Geo` #1999, #2007 | `BP_LineMesh_OldManor_Wall_4x850_C_1059`, `StaticMeshActor_2390` | `BP_OldManor_Doorway_4x650_C` | **`true`** | `<ABS>` ⇒ pickable | `…OldManor` | 2 | pickable |
| `OldManor_Gameplay` #4387-4389 | `BP_VaultDoor_Sliding_C_2/3/5` | `BP_VaultDoor_Sliding_C` | `true` | **`false`** | `VaultA/B/C` | `<ABS>` | **key-only**, with `IncorrectKeyMessage` |
| `OldManor_Gameplay` #4390-4392 | `BP_VaultDoor_Sliding_C_0/1/4` | `BP_VaultDoor_Sliding_StartsOpen_C` | `<ABS>` | **`false`** | none | `<ABS>` | not pickable, not locked |
| `FTUE_Building_SpawnArea` #53 | `BP_Manor_Doorway_4x6_C_2` | `BP_Res_Int_Doorway_C` | `true` | **`false`** | `…Apartment` | `<ABS>` | **key-only** (the decisive §3.2 case) |
| `FTUE_Building_JewelryStore` #102 | `BP_GB_Door3x5_C_1` | `BP_GB_DoorSolo_C` | `true` | `<ABS>` ⇒ pickable | `…Jeweller` | 2 | pickable |
| `FTUE_Building_SpawnArea` #58/59 | `StaticMeshActor_82/87` | `BP_Urban_Ext_BayWindow_C` | `false` | **`false`** | none | `<ABS>` | unlocked |

No prison-class door outside `Building_Guildhall_POI` is locked at all. Every *locked* door in
the shipped maps is either explicitly `CanBeLockpicked: false` with a bound key (the three
OldManor vaults and three Guildhall vaults, each with `Item.Key.Vault.*`) or pickable. The
only `false` doors without a key are the `BP_VaultDoor_Sliding_StartsOpen_C` /
`..._AlwaysOpen_C` instances, and none of those is locked.
**`StaticMeshActor_528` is in neither key-only set.**

---

## 5. What the port consumes today

Generated record: `game/data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json`
(`source: "Buildings/Guildhall/Building_Guildhall_POI.json"`, 730 actors).

Actor (`actors[]`, `"name": "StaticMeshActor_528"`):

```json
{"name": "StaticMeshActor_528", "class": "BP_Prison_WallA_DoorwayB2_6x6_C",
 "pos": [-3.0, 11.5, -9.0], "basis": [...], "scale": [1.0,1.0,1.0],
 "locked": true, "key_tag": "Item.Key.Buildings.Guildhall", "tags": ["WithSmartObject"]}
```

Door node (`swinging_doors[]`, `name: "StaticMeshActor_528.Pivot"` and `.SecondPivot`):

```json
{"name": "StaticMeshActor_528.Pivot", "actor": "StaticMeshActor_528",
 "class": "BP_Prison_WallA_DoorwayB2_6x6_C", ..., "locked": true,
 "key_tag": "Item.Key.Buildings.Guildhall", "source": "...::StaticMeshActor_528"}
```

So today the record carries `locked: true` + `key_tag`, and **no** `can_lockpick`, **no**
`max_lock_level`, **no** `min_lock_level`. The producer copies only the instance's own
authored keys (`tools/parse_tables.py:1132-1158`, `_authored_lock_fields`), so the inherited
cap `4` cannot reach the record.

Runtime branch (`game/src/interact/swinging_door.gd:128-137`):
`locked == true` → class does not contain "window" → `can_lockpick` is `null` (not `bool`)
→ `set_locked(true, clampi(1, 1, 4))` = **level 1, pickable**. The W9 test pins this:
`game/tests/test_w9p2_locks.gd:122-127`
(`"door locked with a KeyTag but no CanBeLockpicked locks at the 1 fallback"`).

---

## 6. The prior W9 claim — is it supported?

| Claim | Location | Verdict |
|---|---|---|
| "by the authored flag it is pickable and locks at the 1 fallback" | `build/qa/w9/b2-impl.md:159-166`; `build/qa/w9/p2-report.md:483-485` and `:673` | **Supported on pickability.** The W9 lane reached the right answer with the right caveat (it refused to invent a "KeyTag ⇒ key-only" rule) but did not prove *why* absence means pickable, so it left it flagged as an inference. §2-§3 supply the missing proof. |
| "all 33 placed values are `false`, all 3 `true` values are class defaults" | `build/qa/w9/facts-b2.md:166`, CDO table `:1238-1270`, `_locked` table `:1272-1281` | **Correct data, inference not drawn.** The dataset in that table is exactly the delta proof of §2; W9 recorded it without reading it as "so the default is `true`". |
| "locks at the 1 fallback" | same | **Correct as a statement of the port's behaviour, incomplete as a statement about the data.** The record has no cap, but the authored cap is 4 (§1, §7.2). |

The earlier "key-only door count = 4" (`3 BP_VaultDoor_Sliding_C + 1 BP_Res_Int_Doorway_C`)
is right, and those four are exactly the actors that explicitly author
`CanBeLockpicked: false`. The prison door is not among them.

---

## 7. Conclusion

### 7.1 Which branch is authored

**Pickable.** `StaticMeshActor_528` is authored as a locked door that can be picked. The
Guildhall key *tag* is present but no `KeyItemInfo` is bound for this actor, so the key side
of the lock is not wired; the lockpick side is. The port's current behaviour (lock it, allow
the lockpick minigame) is faithful.

Do **not** "fix" defect 8 by switching this actor to key-only. That would invent a rule
("KeyTag without `CanBeLockpicked` is key-only") that the shipped data contradicts in 7
other locked doors, that the game's own UI vocabulary contradicts (`KeyUnlock` and
`Pick Lock` coexist), and that would make this particular door **unopenable in practice**:
it is the only key-tagged actor in the POI with no `KeyItemInfo`, so there is no key item
bound that could satisfy a key-only gate (§4.1).

Confidence: **high** for the resolved value `true`. Residual uncertainty is confined to
"we cannot read the C++ initialiser"; the value is forced by the delta rule (§2) and by a
same-class door that must have changed it (§3.2). If someone later finds the C++ default is
`false`, then `BP_SlidingWindow_Base_C`'s explicit `false` and 33 placed `false`s become
unexplainable no-ops — i.e. the dump would have to be lossy, which §2.3 excludes.

### 7.2 The real defect in this area (separate from pickability)

The port's *input* is incomplete for exactly this actor. Authored `MaxLockLevel` resolves to
**4** (inherited from `BP_SwingingDoor_C`, never overridden on the prison class), but
`_authored_lock_fields` emits only instance-authored keys, so the port invents the level
`1`. Under the port's own documented policy ("level = the authored cap, clamped; a locked
record with no cap locks at 1") this actor should be **4**, not 1.

Two honest options for the lead, both labelled port decisions because **no per-instance
`LockLevel` exists anywhere** (W9 checked: 0 occurrences in 12,541 JSONs):

1. **Leave the runtime at 1**, correct only the wording: "the record carries no cap because
   the producer emits instance deltas; the authored cap is 4 and is not consumed." Cheapest,
   no behaviour change, but keeps an untrue-looking record.
2. **Resolve the chain in the producer** (integrator-only, `game/data` regeneration) and emit
   `max_lock_level: 4`; the runtime then locks at 4 per the existing rule. This is a
   difficulty change (LV4 pick on the cell door) and should be a deliberate call, not a
   side effect of fixing pickability.

This investigator does not recommend changing the lock level as part of defect 8, because
the brief's question is pickability and the level change is player-visible.

### 7.3 What a port-side gate can assert without inventing a rule

Everything below is a *fact* about the shipped data, re-derivable with §8:

1. **Resolved-value census.** Walk `Super`/`SuperStruct` from every class that owns a
   `_lockConfig` and record the nearest explicit `CanBeLockpicked`; the unresolved tail is
   `true` (proven here). Assert the result set: exactly one class resolves `false`
   (`BP_SlidingWindow_Base_C`) and it has **zero placements** in `Maps/**`. This is the
   regression trap the current rule is missing.
2. **"Key-only is always explicit" invariant.** For every *placed* lock actor, assert
   `can_lockpick == false` in the record **iff** the dump authors `CanBeLockpicked: false`
   on that instance. The shipped data obeys it 33/33, and it fails loudly if a future
   placement relies on an inherited `false` that the producer cannot see.
3. **Pin `StaticMeshActor_528` explicitly**: `locked == true`, `key_tag ==
   "Item.Key.Buildings.Guildhall"`, `can_lockpick` **absent**, and the resulting runtime
   state `locked && lock_level == 1` (today) — with a comment citing this file. If option 2
   in §7.2 is taken later, this is the one assertion to update, deliberately.
4. **Label correction (no data needed).** `swinging_door.gd` and the test call the
   exclusion "key_only"; 26 of the 33 `false` authors have no `KeyTag`. Rename to
   `no_pick` / `unpickable` in the counter keys and the new comments; keep
   `key_only_exclusions()` as a deprecated alias if other code reads it.

A gate should **not** assert "KeyTag ⇒ key-only" or "no `CanBeLockpicked` ⇒ key-only":
either would invert the shipped data.

---

## 8. Re-derivation

All commands run from the worktree root (or `TAT-2`, the dump is shared). No Godot needed.

```bash
# 1. chain + CDO _lockConfig + Template (prints the whole walk)
python3 - <<'EOF'
import json,os,re
root='extracted/json'; pkg={}
for dp,_,fns in os.walk(root):
    for fn in fns:
        if not fn.endswith('.json'): continue
        p=os.path.join(dp,fn)
        try: d=json.load(open(p))
        except Exception: continue
        if not isinstance(d,list): continue
        b=[o for o in d if o.get('Type')=='BlueprintGeneratedClass']
        if not b: continue
        b=b[0]; sup=b.get('Super'); ss=b.get('SuperStruct')
        rec={'name':b.get('Name'),'super':re.sub(r'\.\d+$','',(sup or {}).get('ObjectPath','')) or None,
             'native':(ss or {}).get('ObjectName'),'lc':None,'locked':None}
        for o in d:
            if o.get('Name','').startswith('Default__'):
                pr=o.get('Properties') or {}
                if '_lockConfig' in pr: rec['lc']=pr['_lockConfig']
                if '_locked' in pr: rec['locked']=pr['_locked']
        pkg[b.get('Package')]=rec
p='/Game/Art/Environment/Prison/BP_Prison_WallA_DoorwayB2_6x6'
for _ in range(6):
    r=pkg.get(p)
    if not r: print('NATIVE/missing:',p); break
    print(r['name'], '| _lockConfig=',json.dumps(r['lc'],sort_keys=True),'| _locked=',r['locked'])
    p=r['super']
    if not p: print('  SuperStruct:',r['native']); break
EOF

# 2. the census: explicit CanBeLockpicked anywhere
grep -rl "CanBeLockpicked" extracted/json --include=*.json      # 9 files
grep -o '"CanBeLockpicked": *[a-z]*' -r extracted/json | sed 's/.*: //' | sort | uniq -c
#   34 false (33 placed actors + the BP_SlidingWindow_Base CDO), 3 true (3 CDOs), 37 total

# 3. the prison actor in the level (object #1417)
python3 -c "import json;d=json.load(open('extracted/json/Maps/Buildings/Guildhall/Building_Guildhall_POI.json'));o=d[1417];print(o['Name'],o['Properties'].get('_locked'),json.dumps(o['Properties'].get('_lockConfig')))"

# 4. the decisive FTUE door (object #53)
python3 -c "import json;d=json.load(open('extracted/json/Maps/FTUE/FTUE_Building_SpawnArea.json'));o=d[53];print(o['Name'],o['Properties'].get('_locked'),json.dumps(o['Properties'].get('_lockConfig')))"

# 5. no native declarations are dumped
grep -rl '"Package": "/Script' extracted/json --include=*.json | wc -l   # 0
grep -ro "TATDoor[A-Za-z_]*" extracted/json | wc -l                     # 0

# 6. what the port consumes
python3 -c "
import json;d=json.load(open('game/data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json'))
print([a for a in d['actors'] if a['name']=='StaticMeshActor_528'])
print([s for s in d['swinging_doors'] if s.get('actor')=='StaticMeshActor_528'])"

# 7. no key item bound on the prison door (only key-tagged POI actor without one)
python3 -c "
import json;d=json.load(open('extracted/json/Maps/Buildings/Guildhall/Building_Guildhall_POI.json'))
kt=[(i,o['Name']) for i,o in enumerate(d) if isinstance(o.get('Properties'),dict)
    and isinstance(o['Properties'].get('_lockConfig'),dict)
    and (o['Properties']['_lockConfig'].get('KeyTag') or {}).get('TagName')]
noinfo=[x for x in kt if 'KeyItemInfo' not in d[x[0]]['Properties']['_lockConfig']]
print(len(kt),'key-tagged;',noinfo)"
```

Exact JSON paths used above:

```
extracted/json/Art/Environment/Prison/BP_Prison_WallA_DoorwayB2_6x6.json      #6  Default__BP_Prison_WallA_DoorwayB2_6x6_C   (line 211)
extracted/json/Gameplay/Interactables/Doors/BP_SwingingDoor_DoubleBase.json   #6  Default__BP_SwingingDoor_DoubleBase_C
extracted/json/Gameplay/Interactables/Doors/BP_SwingingDoor.json              #7  Default__BP_SwingingDoor_C   (_lockConfig line 591)
extracted/json/Gameplay/Interactables/Windows/BP_SlidingWindow_Base.json      #4  (_lockConfig line 231, _locked line 234)
extracted/json/Core/Gameplay/Interactables/Windows/BP_OSESimpleWindow.json    #4
extracted/json/Art/Environment/Props/Kitchen/BP_Dumbwaiter.json               #4
extracted/json/Art/Environment/Urban/Walls/BP_Urban_Window_4x6.json           #4
extracted/json/Art/Environment/Urban/Walls/BP_Urban_Ext_BayWindow.json        #4
extracted/json/Art/Environment/Civic/Exterior/BP_Civic_WindowC_6x8_Closed.json #5  (_lockConfig line 326)
extracted/json/Art/Environment/Residence/Walls/BP_Res_Int_Doorway.json        #6  (_lockConfig line 315)
extracted/json/Maps/Buildings/Guildhall/Building_Guildhall_POI.json          #1417 StaticMeshActor_528 (line 101352, _locked 101439)
extracted/json/Maps/FTUE/FTUE_Building_SpawnArea.json                        #53  BP_Manor_Doorway_4x6_C_2 (line 2154, _locked 2261)
extracted/json/StringTables/ST_Lockpicking.json                              LockPicking.Lock.{KeyUnlock,KeyRequired,NoPicking}
game/data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json   actors[] + swinging_doors[]
tools/parse_tables.py:1132-1158     _authored_lock_fields  (instance delta only)
game/src/interact/swinging_door.gd:128-137, 82-84
game/tests/test_w9p2_locks.gd:122-127
```

---

## 9. Files touched

* Created: `build/qa/w10/re-1-locks.md` (this file).
* Modified: none. `extracted/`, `game/data/generated/` and `game/src/` untouched.
  No Godot process was started.
* Commit note for the lead: `build/qa/*` is git-ignored (`.gitignore:25`) and only
  `**/*.gd|sh|py` are re-included, so this file needs `git add -f` — the same way the
  tracked `build/qa/w9/*.md` reports were added.
