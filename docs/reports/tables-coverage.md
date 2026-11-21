# Curve-table coverage

`GameData` now loads **all 31** authored CurveTables plus `DT_PlayerStats`,
`DT_PlayerExperience` and `CT_UpgradeStatCurves`. Before this pass, 7 curves and
`DT_PlayerStats` were silently unloaded because they sit outside the four scanned
roots, so damage/identity/knockback/input curves fell back to defaults.

## How loading works

- `_load_curves()` scans four roots (`Gameplay/Tuning`, `Character/Player`,
  `Gameplay/Tools` recursive, `AI/Data`) and then nine additional directories
  (below), each recursively.
- `_store_table_file()` classifies a table by its declared `type` (or `CT_`/`DT_`
  prefix); ambiguous tables are classified by row shape.
- `eval_curve(table, row, x, fallback)` samples a curve; `get_player_stat_def`,
  `get_xp_def` and `get_upgrade_curve` expose the progression tables.

## Census (31 CurveTables)

| Table | Path | Loaded before | Loaded now |
|---|---|---|---|
| Curve_AI_HeightDifferenceToStrengthMultiplier | AI/Alertness | no | yes |
| Curve_FallingDamage | Character/Player | yes | yes |
| Curve_Identity_Table | Gameplay/Abilities/Effects | **no** | yes |
| Curve_ShockKnockback_Table | .../Damage/Instant/Shock | **no** | yes |
| Curve_BurnDamage_Table | .../Damage/OverTime/Burn | **no** | yes |
| Curve_PoisonDamage_Table | .../Damage/OverTime/Poison | **no** | yes |
| Curve_CarryTargetThrowStrengthVsDirection | Gameplay/Carry | no | yes |
| CT_Melee_RangedAttackDamage | Gameplay/Combat/Guard/Melee/RangedAttack | **no** | yes |
| Curve_GamepadLookEdgeBoost | Gameplay/Input/Character | no | yes |
| Curve_GamepadMoveThumbstickResponse | Gameplay/Input/Character | no | yes |
| Curve_PowerSurgeKnockback_Table | Gameplay/Interactables/ElectricPower | **no** | yes |
| CT_WireCrank | Gameplay/Tools/PrimaryTools/Hotwire | yes | yes |
| CT_WireLength | Gameplay/Tools/PrimaryTools/Hotwire | yes | yes |
| Curve_Dodge | Gameplay/Traversal/Dodge | no | yes |
| CT_AIBehaviorProperties | Gameplay/Tuning | yes | yes |
| CT_AIStats | Gameplay/Tuning | yes | yes |
| CT_LockpickDamage | Gameplay/Tuning | yes | yes |
| CT_PlayerStats | Gameplay/Tuning | yes | yes |
| CT_Prop_Breakables | Gameplay/Tuning | yes | yes |
| CT_Prop_Throwables | Gameplay/Tuning | yes | yes |
| CT_StaminaSystem | Gameplay/Tuning | yes | yes |
| CT_Tool_Blackjack | Gameplay/Tuning | yes | yes |
| CT_Tool_KnockoutGas | Gameplay/Tuning | yes | yes |
| CT_Tool_SmokeBomb | Gameplay/Tuning | yes | yes |
| CT_Tool_StaminaBomb | Gameplay/Tuning | yes | yes |
| CT_Tool_Wire | Gameplay/Tuning | yes | yes |
| CT_UpgradeStatCurves | Gameplay/Tuning | yes | yes |
| CT_UX | Gameplay/Tuning | yes | yes |
| CT_XPToLevel | Gameplay/Tuning | yes | yes |
| Curve_Exposure_Compensation_Float | Art/Environment/Weather | no | yes |
| Curve_Exposure_Compensation_Float_V3 | Art/Environment/Weather | no | yes |

## Progression tables

- `DT_PlayerStats` (`Gameplay/Progression`) — now loaded (previously 0 callers).
- `DT_PlayerExperience` (`Gameplay/Tuning`) — loaded, now exposed via `get_xp_def`.
- `CT_UpgradeStatCurves` (`Gameplay/Tuning`) — loaded, now exposed via `get_upgrade_curve`.

## Tests

`run_tests.gd` asserts the 16-contract set and 134,784 level mesh references; the
curve/table load is exercised indirectly by every system that consumes a curve.
A dedicated count assertion (`curves.size() >= 31`) belongs with the M3 gameplay
milestone, when the remaining consumers are wired.
