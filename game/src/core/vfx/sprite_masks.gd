extends RefCounted
## Measured sprite-mask table for level Niagara billboards (T12-VFX).
##
## Every entry was measured with a headless Godot run: Image.load_from_file() on the
## raw PNG, detect_alpha(), sampled alpha coverage (a > 0.1) and border coverage (the
## same test on the outer 2 sample rows). A texture is a usable soft mask when it has
## an alpha channel, border coverage <= 0.20 (an atlas page is opaque to its edges) and
## 0.005 <= coverage <= 0.85 (a fully covered or fully transparent sheet is not a
## sprite). acceptable() is the single source of truth for the shader use_sprite switch;
## probe_niagara.gd re-measures every entry and fails on drift.
##
## Result on the current extract: 6 of 29 textures across the 37 placed systems are
## usable masks. The other 23 resolve to opaque albedo/atlas pages (wrong-token material
## resolution), so those systems keep the procedural radial falloff. Do not widen the
## band to bind them: an opaque 2048 px atlas sampled as a billboard reads as a box.

## path -> [has_alpha, coverage, border_coverage]
const MEASURED: Dictionary = {
	"res://assets/ue/Raw/Art/Character/ThiefNisha/Base/Textures/T_ThiefNisha_Eyes_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Effects/LootAttract/T_LootAttract_Shine.png": [true, 0.019, 0.000],
	"res://assets/ue/Raw/Art/Effects/MagicWarp/T_MageHandGradientB.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Effects/Moths/T_Moths_N.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Effects/Puddles/T_Decal_Puddle_5_Opacity.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Effects/Smoke/Smoke32.png": [true, 0.072, 0.006],
	"res://assets/ue/Raw/Art/Environment/City/Architecture/BeautifulCorner/Materials/T_Pipes_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Environment/Nature/Trees/Willow/Materials/T_LeafWillowGlow_D.png": [true, 0.218, 0.034],
	"res://assets/ue/Raw/Art/Environment/Props/Debris/DebrisNanite/T_Newspaper_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Environment/Props/Debris/T_TrashDebris_DA.png": [true, 0.765, 0.752],
	"res://assets/ue/Raw/Art/Environment/Props/Furniture/Desk/Scrolls/T_ScrollsABC_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Environment/Props/Paintings/T_PaintingA_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Environment/Skybox/SkyboxSmokestacks/T_SkyboxSmokestacks_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Environment/Urban/Roofs/Chimneys/T_ChimneyPipesA_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Gameplay/EscapeRoutes/T_EscapeRouteTunnelA_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Gameplay/Gear/AntiStealthDevice/T_AntiStealthDevice_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Gameplay/Gear/Bomb/Liquid/T_Bomb_Liquid_DA.png": [true, 0.837, 0.861],
	"res://assets/ue/Raw/Art/Gameplay/Gear/Dart/T_Dart_Electric_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Gameplay/Gear/Faerie/Faerie_Body01.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Gameplay/Gear/LootBag/T_LootBag_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Gameplay/Gear/Slithersap/T_SlimeBomb_DA.png": [true, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Gameplay/Gear/SmokeBomb/T_SmokeBomb_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Gameplay/Gear/Zipwire/T_Zipwire_D.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/Gameplay/Loot/Stash/LootStash_Line.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/Art/VFX/Textures/Noise/_Noise_71.png": [false, 1.000, 1.000],
	"res://assets/ue/Raw/MaterialLibrary/Environment/Nature/Plants/T_BushesLeaves_DA.png": [true, 0.338, 0.016],
	"res://assets/ue/Raw/MaterialLibrary/VFX/T_LightGlowsA_D.png": [true, 0.413, 0.105],
	"res://assets/ue/Raw/ThirdParty/DEKO_VFX/VOL1_Water/Textures/TX_Splash_Big_01a_ALB.png": [true, 0.148, 0.000],
	"res://assets/ue/Raw/ThirdParty/StylizedPirateTreasures/Textures/Treasures/T_Atlas_B_01_BC.png": [false, 1.000, 1.000],
}

const BORDER_MAX: float = 0.20
const COVERAGE_MIN: float = 0.005
const COVERAGE_MAX: float = 0.85


## True when [param path] was measured and sits inside the soft-mask band.
static func acceptable(path: String) -> bool:
	var row_v: Variant = MEASURED.get(path, null)
	if not (row_v is Array) or (row_v as Array).size() < 3:
		return false
	var a: Array = row_v as Array
	return bool(a[0]) and float(a[2]) <= BORDER_MAX \
		and float(a[1]) >= COVERAGE_MIN and float(a[1]) <= COVERAGE_MAX


## The measured row, or an empty array when the texture was never measured.
static func row(path: String) -> Array:
	var v: Variant = MEASURED.get(path, [])
	return v as Array if v is Array else []
