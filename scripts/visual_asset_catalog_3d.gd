extends RefCounted
class_name VisualAssetCatalog3D

## TASK-3D-VIS-001-1 Asset Acquire / License / Import의 runtime catalog.
## TASK-3D-VIS-001-2에서 gameplay object별 선택 레이어(SELECTIONS /
## ANIMATION_SETS)와 world scale convention(SCALE_CONVENTION)을 추가했다.
##
## 역할:
##   - Quaternius 에셋 스택(3D Asset Stack LOCK) 중 실제로 사용하는 모델만
##     gameplay 키로 노출한다. 원본 팩 전체(_source/)는 Godot import 대상이
##     아니며(.gdignore), 어떤 Scene도 파일 경로를 직접 참조하지 않고 이
##     catalog의 키 조회를 거친다.
##
## 반입 경로 / 라이선스:
##   - models/ 아래는 tools/download_quaternius_packs.ps1이 공식 itch.io
##     배포본에서 선별 복사한 GLTF/GLB다(전부 CC0).
##   - 출처/라이선스 기록: assets/third_party/quaternius/README.md 와 license/.
##   - import 검증 결과: auto_dev/VIS_ASSET_IMPORT_REPORT.md.
##
## scale/orientation 기준(통일):
##   - 모델은 원본 스케일(Y-up, glTF 미터 관례) 그대로 사용한다. 월드 배율은
##     WorldCoords3D.PX_TO_UNIT 균일 배율만 허용하는 Foundation LOCK을 따른다.
##   - glTF는 Y-up + 오른손 좌표계라 Godot 기본 규약과 일치하므로 추가 회전
##     보정 없이 인스턴스화한다(측정 근거는 import 리포트의 AABB 표).
##   - visual scale variation과 gameplay footprint의 분리 계약은 각 기능
##     Scene의 Visual slot 구조(INTEGRATION_NOTE_RES.md)를 그대로 따른다.

const MODELS_ROOT := "res://assets/third_party/quaternius/models/"

## 카테고리 상수. VIS-001-2 catalog 확장 시에도 이 값들을 사용한다.
const CATEGORY_TREES := "trees"
const CATEGORY_ROCKS := "rocks"
const CATEGORY_VEGETATION := "vegetation"
const CATEGORY_BUILDING := "building"
const CATEGORY_PROPS := "props"
const CATEGORY_TOOLS := "tools"
const CATEGORY_HUMAN := "human"
const CATEGORY_OUTFIT := "outfit"
const CATEGORY_ANIMATION := "animation"

## gameplay 키 -> { path, category }.
## path는 MODELS_ROOT 기준 상대 경로다. 키는 안정적 식별자이며 파일명 변경과
## 무관하게 유지된다(VIS-002 wiring이 이 키만 소비).
const ENTRIES := {
	# -- Stylized Nature MegaKit : Tree3D/StoneDeposit3D visual slot 후보 --
	"tree/common_1": {"path": "stylized-nature-megakit/CommonTree_1.gltf", "category": CATEGORY_TREES},
	"tree/common_2": {"path": "stylized-nature-megakit/CommonTree_2.gltf", "category": CATEGORY_TREES},
	"tree/common_3": {"path": "stylized-nature-megakit/CommonTree_3.gltf", "category": CATEGORY_TREES},
	"tree/common_4": {"path": "stylized-nature-megakit/CommonTree_4.gltf", "category": CATEGORY_TREES},
	"tree/common_5": {"path": "stylized-nature-megakit/CommonTree_5.gltf", "category": CATEGORY_TREES},
	"tree/pine_1": {"path": "stylized-nature-megakit/Pine_1.gltf", "category": CATEGORY_TREES},
	"tree/pine_2": {"path": "stylized-nature-megakit/Pine_2.gltf", "category": CATEGORY_TREES},
	"tree/dead_1": {"path": "stylized-nature-megakit/DeadTree_1.gltf", "category": CATEGORY_TREES},
	"tree/dead_2": {"path": "stylized-nature-megakit/DeadTree_2.gltf", "category": CATEGORY_TREES},
	"rock/medium_1": {"path": "stylized-nature-megakit/Rock_Medium_1.gltf", "category": CATEGORY_ROCKS},
	"rock/medium_2": {"path": "stylized-nature-megakit/Rock_Medium_2.gltf", "category": CATEGORY_ROCKS},
	"rock/medium_3": {"path": "stylized-nature-megakit/Rock_Medium_3.gltf", "category": CATEGORY_ROCKS},
	"veg/grass_common_short": {"path": "stylized-nature-megakit/Grass_Common_Short.gltf", "category": CATEGORY_VEGETATION},
	"veg/grass_common_tall": {"path": "stylized-nature-megakit/Grass_Common_Tall.gltf", "category": CATEGORY_VEGETATION},
	"veg/grass_wispy_tall": {"path": "stylized-nature-megakit/Grass_Wispy_Tall.gltf", "category": CATEGORY_VEGETATION},
	"veg/bush_common": {"path": "stylized-nature-megakit/Bush_Common.gltf", "category": CATEGORY_VEGETATION},
	"veg/bush_flowers": {"path": "stylized-nature-megakit/Bush_Common_Flowers.gltf", "category": CATEGORY_VEGETATION},
	"veg/flower_group_3": {"path": "stylized-nature-megakit/Flower_3_Group.gltf", "category": CATEGORY_VEGETATION},
	"veg/flower_group_4": {"path": "stylized-nature-megakit/Flower_4_Group.gltf", "category": CATEGORY_VEGETATION},
	"veg/mushroom": {"path": "stylized-nature-megakit/Mushroom_Common.gltf", "category": CATEGORY_VEGETATION},

	# -- Medieval Village MegaKit : 건물/Wall/Gate visual 후보 --
	"bld/wall_plaster_straight": {"path": "medieval-village-megakit/Wall_Plaster_Straight.gltf", "category": CATEGORY_BUILDING},
	"bld/wall_plaster_woodgrid": {"path": "medieval-village-megakit/Wall_Plaster_WoodGrid.gltf", "category": CATEGORY_BUILDING},
	"bld/wall_brick_straight": {"path": "medieval-village-megakit/Wall_UnevenBrick_Straight.gltf", "category": CATEGORY_BUILDING},
	"bld/wall_plaster_window_wide": {"path": "medieval-village-megakit/Wall_Plaster_Window_Wide_Flat.gltf", "category": CATEGORY_BUILDING},
	"bld/wall_brick_window_wide": {"path": "medieval-village-megakit/Wall_UnevenBrick_Window_Wide_Flat.gltf", "category": CATEGORY_BUILDING},
	"bld/wall_plaster_door_flat": {"path": "medieval-village-megakit/Wall_Plaster_Door_Flat.gltf", "category": CATEGORY_BUILDING},
	"bld/wall_brick_door_flat": {"path": "medieval-village-megakit/Wall_UnevenBrick_Door_Flat.gltf", "category": CATEGORY_BUILDING},
	"bld/door_1_flat": {"path": "medieval-village-megakit/Door_1_Flat.gltf", "category": CATEGORY_BUILDING},
	"bld/window_wide_flat": {"path": "medieval-village-megakit/Window_Wide_Flat1.gltf", "category": CATEGORY_BUILDING},
	"bld/shutters_wide_open": {"path": "medieval-village-megakit/WindowShutters_Wide_Flat_Open.gltf", "category": CATEGORY_BUILDING},
	"bld/roof_roundtiles_6x6": {"path": "medieval-village-megakit/Roof_RoundTiles_6x6.gltf", "category": CATEGORY_BUILDING},
	"bld/roof_wooden_2x1": {"path": "medieval-village-megakit/Roof_Wooden_2x1.gltf", "category": CATEGORY_BUILDING},
	"bld/overhang_roof_plaster": {"path": "medieval-village-megakit/Overhang_Roof_Plaster.gltf", "category": CATEGORY_BUILDING},
	"bld/floor_wood_light": {"path": "medieval-village-megakit/Floor_WoodLight.gltf", "category": CATEGORY_BUILDING},
	"bld/floor_brick": {"path": "medieval-village-megakit/Floor_Brick.gltf", "category": CATEGORY_BUILDING},
	"bld/stairs_exterior_straight": {"path": "medieval-village-megakit/Stairs_Exterior_Straight.gltf", "category": CATEGORY_BUILDING},
	"bld/fence_wooden_single": {"path": "medieval-village-megakit/Prop_WoodenFence_Single.gltf", "category": CATEGORY_BUILDING},
	"bld/chimney": {"path": "medieval-village-megakit/Prop_Chimney.gltf", "category": CATEGORY_BUILDING},
	"bld/vine_1": {"path": "medieval-village-megakit/Prop_Vine1.gltf", "category": CATEGORY_BUILDING},
	"bld/wagon": {"path": "medieval-village-megakit/Prop_Wagon.gltf", "category": CATEGORY_BUILDING},

	# -- Fantasy Props MegaKit : 시장/작업물/가구 props --
	"prop/barrel": {"path": "fantasy-props-megakit/Barrel.gltf", "category": CATEGORY_PROPS},
	"prop/crate_wooden": {"path": "fantasy-props-megakit/Crate_Wooden.gltf", "category": CATEGORY_PROPS},
	"prop/chest_wood": {"path": "fantasy-props-megakit/Chest_Wood.gltf", "category": CATEGORY_PROPS},
	"prop/stall_cart_empty": {"path": "fantasy-props-megakit/Stall_Cart_Empty.gltf", "category": CATEGORY_PROPS},
	"prop/stall_empty": {"path": "fantasy-props-megakit/Stall_Empty.gltf", "category": CATEGORY_PROPS},
	"prop/farmcrate_apple": {"path": "fantasy-props-megakit/FarmCrate_Apple.gltf", "category": CATEGORY_PROPS},
	"prop/farmcrate_carrot": {"path": "fantasy-props-megakit/FarmCrate_Carrot.gltf", "category": CATEGORY_PROPS},
	"prop/farmcrate_empty": {"path": "fantasy-props-megakit/FarmCrate_Empty.gltf", "category": CATEGORY_PROPS},
	"prop/coin_pile": {"path": "fantasy-props-megakit/Coin_Pile.gltf", "category": CATEGORY_PROPS},
	"prop/lantern_wall": {"path": "fantasy-props-megakit/Lantern_Wall.gltf", "category": CATEGORY_PROPS},
	"prop/torch_metal": {"path": "fantasy-props-megakit/Torch_Metal.gltf", "category": CATEGORY_PROPS},
	"prop/rope_1": {"path": "fantasy-props-megakit/Rope_1.gltf", "category": CATEGORY_PROPS},
	"prop/bag": {"path": "fantasy-props-megakit/Bag.gltf", "category": CATEGORY_PROPS},
	"prop/potion_1": {"path": "fantasy-props-megakit/Potion_1.gltf", "category": CATEGORY_PROPS},

	# -- Fantasy Props MegaKit : 도구/무기(작업/용병 prop attach 후보) --
	"tool/axe_bronze": {"path": "fantasy-props-megakit/Axe_Bronze.gltf", "category": CATEGORY_TOOLS},
	"tool/pickaxe_bronze": {"path": "fantasy-props-megakit/Pickaxe_Bronze.gltf", "category": CATEGORY_TOOLS},
	"tool/sword_bronze": {"path": "fantasy-props-megakit/Sword_Bronze.gltf", "category": CATEGORY_TOOLS},
	"tool/anvil": {"path": "fantasy-props-megakit/Anvil.gltf", "category": CATEGORY_TOOLS},
	"tool/chopping_log": {"path": "fantasy-props-megakit/Anvil_Log.gltf", "category": CATEGORY_TOOLS},
	"tool/workbench": {"path": "fantasy-props-megakit/Workbench.gltf", "category": CATEGORY_TOOLS},
	"tool/whetstone": {"path": "fantasy-props-megakit/Whetstone.gltf", "category": CATEGORY_TOOLS},

	# -- Universal Base Characters : humanoid base --
	"human/male_base": {"path": "universal-base-characters/Superhero_Male_FullBody.gltf", "category": CATEGORY_HUMAN},
	"human/female_base": {"path": "universal-base-characters/Superhero_Female_FullBody.gltf", "category": CATEGORY_HUMAN},
	"human/hair_simple_parted": {"path": "universal-base-characters/Hair_SimpleParted.gltf", "category": CATEGORY_HUMAN},

	# -- Modular Character Outfits - Fantasy : 조합형 부품 + 완성 세트 --
	"outfit/male_peasant_full": {"path": "modular-character-outfits-fantasy/Male_Peasant.gltf", "category": CATEGORY_OUTFIT},
	"outfit/female_peasant_full": {"path": "modular-character-outfits-fantasy/Female_Peasant.gltf", "category": CATEGORY_OUTFIT},
	"outfit/male_ranger_full": {"path": "modular-character-outfits-fantasy/Male_Ranger.gltf", "category": CATEGORY_OUTFIT},
	"outfit/male_peasant_arms": {"path": "modular-character-outfits-fantasy/Male_Peasant_Arms.gltf", "category": CATEGORY_OUTFIT},
	"outfit/male_peasant_body": {"path": "modular-character-outfits-fantasy/Male_Peasant_Body.gltf", "category": CATEGORY_OUTFIT},
	"outfit/male_peasant_feet": {"path": "modular-character-outfits-fantasy/Male_Peasant_Feet.gltf", "category": CATEGORY_OUTFIT},
	"outfit/male_peasant_legs": {"path": "modular-character-outfits-fantasy/Male_Peasant_Legs.gltf", "category": CATEGORY_OUTFIT},
	"outfit/male_ranger_arms": {"path": "modular-character-outfits-fantasy/Male_Ranger_Arms.gltf", "category": CATEGORY_OUTFIT},
	"outfit/male_ranger_body": {"path": "modular-character-outfits-fantasy/Male_Ranger_Body.gltf", "category": CATEGORY_OUTFIT},
	"outfit/male_ranger_feet_boots": {"path": "modular-character-outfits-fantasy/Male_Ranger_Feet_Boots.gltf", "category": CATEGORY_OUTFIT},
	"outfit/male_ranger_legs": {"path": "modular-character-outfits-fantasy/Male_Ranger_Legs.gltf", "category": CATEGORY_OUTFIT},
	"outfit/male_ranger_head_hood": {"path": "modular-character-outfits-fantasy/Male_Ranger_Head_Hood.gltf", "category": CATEGORY_OUTFIT},
	"outfit/male_ranger_acc_pauldron": {"path": "modular-character-outfits-fantasy/Male_Ranger_Acc_Pauldron.gltf", "category": CATEGORY_OUTFIT},
	"outfit/female_peasant_arms": {"path": "modular-character-outfits-fantasy/Female_Peasant_Arms.gltf", "category": CATEGORY_OUTFIT},
	"outfit/female_peasant_body": {"path": "modular-character-outfits-fantasy/Female_Peasant_Body.gltf", "category": CATEGORY_OUTFIT},
	"outfit/female_peasant_feet": {"path": "modular-character-outfits-fantasy/Female_Peasant_Feet.gltf", "category": CATEGORY_OUTFIT},
	"outfit/female_peasant_legs": {"path": "modular-character-outfits-fantasy/Female_Peasant_Legs.gltf", "category": CATEGORY_OUTFIT},

	# -- Universal Animation Library 1/2 : 공용 humanoid 애니메이션(GLB) --
	"anim/ual1_standard": {"path": "universal-animation-library/UAL1_Standard.glb", "category": CATEGORY_ANIMATION},
	"anim/ual2_standard": {"path": "universal-animation-library-2/UAL2_Standard.glb", "category": CATEGORY_ANIMATION},
	"anim/mannequin_female": {"path": "universal-animation-library-2/Mannequin_F.glb", "category": CATEGORY_ANIMATION},
}

## ==========================================================================
## TASK-3D-VIS-001-2 Visual Catalog / Scale Convention 선택 레이어.
##
## 역할:
##   - Visual Agent가 gameplay object별 후보를 ENTRIES 키 조회만으로 고르게
##     한다(랜덤 검색/파일 탐색 금지). role -> variation 목록 1단계 조회다.
##   - variation은 단일 모델("key") 또는 조립 팔레트("parts", 모듈러 건물/
##     문/gate처럼 단일 메시가 없는 조합)이다. parts 배치/조립은 wiring
##     태스크(VIS-002) 소유이고, catalog는 palette만 확정한다.
##   - 일부러 ENTRIES 전체를 소비하지 않는다. 미선택 키는 예비분이며,
##     카테고리당 variation 상한 5개(태스크 요구)를 넘지 않는다.
##
## scale_hint 규약:
##   - 값은 wiring 시 적용할 권장 uniform scale 배수다(생략 시 1.0 원판).
##   - 근거: WorldCoords3D 균일 배율 LOCK + import 리포트 AABB 측정
##     (auto_dev/VIS_VISUAL_CATALOG_REPORT.md). gameplay footprint(collision/
##     nav)와 visual scale은 분리 계약(INTEGRATION_NOTE_RES.md)을 유지하므로
##     hint는 Visual slot에만 적용한다.
const SELECTIONS := {
	"tree": {
		"label": "Tree variants",
		"use": "WorldTree3D visual slot / forest cluster",
		"variations": [
			{"id": "common_a", "key": "tree/common_1", "scale_hint": 0.55},
			{"id": "common_b", "key": "tree/common_3", "scale_hint": 0.55},
			{"id": "pine_a", "key": "tree/pine_1", "scale_hint": 0.5},
			{"id": "pine_b", "key": "tree/pine_2", "scale_hint": 0.5},
			{"id": "dead", "key": "tree/dead_1", "scale_hint": 0.45},
		],
	},
	"rock": {
		"label": "Rock variants",
		"use": "StoneDeposit3D block / decoration",
		"variations": [
			{"id": "medium_a", "key": "rock/medium_1"},
			{"id": "medium_b", "key": "rock/medium_2"},
			{"id": "medium_c", "key": "rock/medium_3"},
		],
	},
	"vegetation": {
		"label": "Grass / Bush / Flower",
		"use": "world dressing / clearing decoration",
		"variations": [
			{"id": "grass_short", "key": "veg/grass_common_short"},
			{"id": "grass_tall", "key": "veg/grass_common_tall"},
			{"id": "bush_plain", "key": "veg/bush_common"},
			{"id": "bush_flowers", "key": "veg/bush_flowers"},
			{"id": "flower_group", "key": "veg/flower_group_4", "scale_hint": 0.7},
		],
	},
	"house_building": {
		"label": "House / Village Building",
		"use": "village house composition (walls stack on the 2m module grid)",
		"variations": [
			{"id": "plaster_gable", "parts": ["bld/floor_wood_light",
				"bld/wall_plaster_straight", "bld/wall_plaster_window_wide",
				"bld/wall_plaster_door_flat", "bld/roof_wooden_2x1"]},
			{"id": "brick_gable", "parts": ["bld/floor_brick",
				"bld/wall_brick_straight", "bld/wall_brick_window_wide",
				"bld/wall_brick_door_flat", "bld/roof_wooden_2x1"]},
		],
	},
	"wall_segment": {
		"label": "Wall / palisade segment",
		"use": "Wall3D visual slot (1 segment = 1 grid cell)",
		"variations": [
			{"id": "plaster", "key": "bld/wall_plaster_straight"},
			{"id": "brick", "key": "bld/wall_brick_straight"},
			{"id": "fence_interior", "key": "bld/fence_wooden_single"},
		],
	},
	"gate": {
		"label": "Gate",
		"use": "Gate3D visual slot (door wall + door leaf)",
		"variations": [
			{"id": "plaster", "parts": ["bld/wall_plaster_door_flat", "bld/door_1_flat"]},
			{"id": "brick", "parts": ["bld/wall_brick_door_flat", "bld/door_1_flat"]},
		],
	},
	"workplace_lumberyard": {
		"label": "Lumberyard visual candidates",
		"use": "lumberyard site dressing motifs",
		"variations": [
			{"id": "stump_station", "parts": ["tool/chopping_log", "tool/axe_bronze"]},
			{"id": "storage_corner", "parts": ["prop/crate_wooden", "prop/barrel"]},
			{"id": "cart_loading", "parts": ["bld/wagon", "prop/crate_wooden"]},
		],
	},
	"workplace_quarry": {
		"label": "Quarry visual candidates",
		"use": "quarry site dressing motifs",
		"variations": [
			{"id": "deposit_outcrop", "parts": ["rock/medium_1", "rock/medium_3"]},
			{"id": "miner_station", "parts": ["tool/pickaxe_bronze", "prop/crate_wooden"]},
		],
	},
	"tavern_inn_keep": {
		"label": "Tavern / Inn / Keep",
		"use": "CoreBuilding core_type별 composition palette",
		"variations": [
			{"id": "tavern", "parts": ["bld/floor_wood_light",
				"bld/wall_plaster_woodgrid", "bld/wall_plaster_window_wide",
				"bld/wall_plaster_door_flat", "bld/roof_roundtiles_6x6",
				"bld/chimney", "prop/lantern_wall"]},
			{"id": "inn", "parts": ["bld/floor_brick",
				"bld/wall_brick_window_wide", "bld/wall_brick_door_flat",
				"bld/roof_roundtiles_6x6", "bld/chimney",
				"bld/shutters_wide_open", "bld/wagon"]},
			{"id": "keep", "parts": ["bld/floor_brick",
				"bld/wall_brick_straight", "bld/wall_brick_window_wide",
				"bld/stairs_exterior_straight", "bld/roof_roundtiles_6x6",
				"prop/torch_metal"]},
		],
	},
	"container_cart": {
		"label": "Crate / Barrel / Cart",
		"use": "market & workplace prop dressing",
		"variations": [
			{"id": "barrel", "key": "prop/barrel"},
			{"id": "crate", "key": "prop/crate_wooden"},
			{"id": "cart", "key": "bld/wagon"},
		],
	},
	"log_pile": {
		"label": "Log / Wood pile",
		"use": "lumberyard wood stock (pile = 인스턴스 반복 + yaw jitter 적층)",
		"variations": [
			{"id": "chopping_log", "key": "tool/chopping_log"},
		],
	},
	"stone_pile": {
		"label": "Stone pile",
		"use": "quarry stone stock (cluster 배치 전용)",
		"variations": [
			{"id": "pile_single", "parts": ["rock/medium_2"], "scale_hint": 0.55},
			{"id": "pile_cluster", "parts": ["rock/medium_2", "rock/medium_1",
				"rock/medium_3"], "note": "tight cluster, per-part scale 0.65/0.5/0.45"},
		],
	},
	"tool_gather": {
		"label": "Axe / Pickaxe",
		"use": "worker hand attach / workplace lean props",
		"variations": [
			{"id": "axe", "key": "tool/axe_bronze", "scale_hint": 0.85,
				"note": "hand attach 시 0.85, 바닥 설치 시 native"},
			{"id": "pickaxe", "key": "tool/pickaxe_bronze", "scale_hint": 0.85,
				"note": "hand attach 시 0.85, 바닥 설치 시 native"},
		],
	},
	"market_props": {
		"label": "Market / Work props",
		"use": "market row & grocery dressing",
		"variations": [
			{"id": "stall", "key": "prop/stall_empty"},
			{"id": "stall_cart", "key": "prop/stall_cart_empty"},
			{"id": "crate_apple", "key": "prop/farmcrate_apple"},
			{"id": "crate_carrot", "key": "prop/farmcrate_carrot"},
			{"id": "coin_pile", "key": "prop/coin_pile"},
		],
	},
	"human_base": {
		"label": "Base Human",
		"use": "Worker/Mercenary/Enemy actor base body (native scale LOCK)",
		"variations": [
			{"id": "male", "key": "human/male_base"},
			{"id": "female", "key": "human/female_base"},
		],
	},
	"outfit_worker": {
		"label": "Worker outfit",
		"use": "worker visual variant (base human에 parent)",
		"variations": [
			{"id": "peasant_male", "key": "outfit/male_peasant_full"},
			{"id": "peasant_female", "key": "outfit/female_peasant_full"},
			{"id": "peasant_male_modular", "parts": ["outfit/male_peasant_body",
				"outfit/male_peasant_arms", "outfit/male_peasant_legs",
				"outfit/male_peasant_feet"],
				"note": "같은 Skeleton3D에 parent하는 파츠 조합"},
		],
	},
	"outfit_mercenary": {
		"label": "Mercenary outfit",
		"use": "mercenary visual variant (base human에 parent)",
		"variations": [
			{"id": "ranger_male", "key": "outfit/male_ranger_full"},
			{"id": "ranger_male_modular", "parts": ["outfit/male_ranger_body",
				"outfit/male_ranger_arms", "outfit/male_ranger_legs",
				"outfit/male_ranger_feet_boots", "outfit/male_ranger_head_hood",
				"outfit/male_ranger_acc_pauldron"],
				"note": "같은 Skeleton3D에 parent하는 파츠 조합"},
		],
	},
	"weapon": {
		"label": "Weapons",
		"use": "mercenary hand attach (bronze tier 통일)",
		"variations": [
			{"id": "sword", "key": "tool/sword_bronze", "scale_hint": 0.85},
		],
	},
}

## gameplay action -> 공용 애니메이션 후보(first = primary).
## library는 ENTRIES의 CATEGORY_ANIMATION 키, name은 그 GLB 내부
## AnimationPlayer의 실제 애니메이션 이름이다(VIS-001-4가 이 이름으로 재생).
const ANIMATION_SETS := {
	"idle": [
		{"library": "anim/ual1_standard", "name": "Idle"},
		{"library": "anim/ual1_standard", "name": "Idle_Torch"},
	],
	"walk": [
		{"library": "anim/ual1_standard", "name": "Walk"},
		{"library": "anim/ual2_standard", "name": "Walk_Carry"},
		{"library": "anim/ual1_standard", "name": "Jog_Fwd"},
	],
	"work": [
		{"library": "anim/ual2_standard", "name": "TreeChopping"},
		{"library": "anim/ual2_standard", "name": "Farm_Harvest"},
		{"library": "anim/ual2_standard", "name": "Farm_Watering"},
		{"library": "anim/ual1_standard", "name": "Fixing_Kneeling"},
	],
	"combat": [
		{"library": "anim/ual1_standard", "name": "Sword_Attack"},
		{"library": "anim/ual2_standard", "name": "Melee_Hook"},
		{"library": "anim/ual2_standard", "name": "Sword_Regular_A"},
	],
	"hit": [
		{"library": "anim/ual1_standard", "name": "Hit_Chest"},
		{"library": "anim/ual1_standard", "name": "Hit_Head"},
		{"library": "anim/ual2_standard", "name": "Hit_Knockback"},
	],
	"death": [
		{"library": "anim/ual1_standard", "name": "Death01"},
	],
}

## world scale convention 단일 기록(태스크 요구사항).
## 수치 출처: WorldCoords3D 상수 + task3dvis0011_probe.txt AABB 측정.
const SCALE_CONVENTION := {
	"px_to_unit": WorldCoords3D.PX_TO_UNIT,
	"grid_cell_units": WorldCoords3D.GRID_CELL_UNITS,
	"ground_y": WorldCoords3D.GROUND_Y,
	"uniform_scale_only": true,
	"yaw_free_for_organic_props": true,
	"gameplay_footprint_independent_of_visual_scale": true,
	"humanoid_height_units": Vector2(1.5, 2.1),
	"wall_module_size_units": Vector3(2.0, 3.12, 0.41),
	"tree_native_height_units": Vector2(7.0, 11.5),
	"tree_slot_scale_hint": Vector2(0.45, 0.65),
}


static func has_key(key: String) -> bool:
	return ENTRIES.has(key)


## 등록되지 않은 키면 빈 문자열. 존재하지 않는 res 경로를 만들지 않는다.
static func get_model_path(key: String) -> String:
	if not ENTRIES.has(key):
		return ""
	return MODELS_ROOT + ENTRIES[key]["path"]


## 카테고리에 속한 키 목록(등록 순서 보존).
static func keys_in_category(category: String) -> Array:
	var out: Array = []
	for key in ENTRIES:
		if ENTRIES[key]["category"] == category:
			out.append(key)
	return out


static func all_keys() -> Array:
	return ENTRIES.keys()


## PackedScene 로드. 실패 시 null(호출 측에서 fallback placeholder를 쓴다).
## import error를 숨기지 않기 위해 push_error로 남긴다(큐 운영 규칙 27).
static func load_model(key: String) -> PackedScene:
	var path := get_model_path(key)
	if path.is_empty():
		push_error("VisualAssetCatalog3D: unknown key '%s'" % key)
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("VisualAssetCatalog3D: failed to load '%s' (%s)" % [key, path])
	return scene


## 인스턴스 생성 실패 시 null 반환. 생성물은 호출자가 소유한다.
static func instantiate_model(key: String) -> Node3D:
	var scene := load_model(key)
	if scene == null:
		return null
	var node: Node = scene.instantiate()
	return node as Node3D


## ==========================================================================
## VIS-001-2 선택 레이어 조회 API. Visual Agent는 이 함수들만 소비한다.

static func has_role(role: String) -> bool:
	return SELECTIONS.has(role)


static func roles() -> Array:
	return SELECTIONS.keys()


static func role_label(role: String) -> String:
	if not SELECTIONS.has(role):
		return ""
	return SELECTIONS[role]["label"]


static func variation_ids_for_role(role: String) -> Array:
	if not SELECTIONS.has(role):
		return []
	var out: Array = []
	for variation in SELECTIONS[role]["variations"]:
		out.append(variation["id"])
	return out


static func _variation(role: String, variation_id: String) -> Dictionary:
	if not SELECTIONS.has(role):
		return {}
	for variation in SELECTIONS[role]["variations"]:
		if variation["id"] == variation_id:
			return variation
	return {}


## role이 참조하는 ENTRIES 키 전체(model은 key 1개, composition은 parts).
## 중복 없이 등록 순서대로. 알 수 없는 role이면 빈 배열.
static func candidate_keys_for_role(role: String) -> Array:
	if not SELECTIONS.has(role):
		return []
	var seen := {}
	var out: Array = []
	for variation in SELECTIONS[role]["variations"]:
		var keys: Array = variation["parts"] if variation.has("parts") \
			else [variation["key"]]
		for key in keys:
			if not seen.has(key):
				seen[key] = true
				out.append(key)
	return out


## variation 하나를 구성하는 model 키 목록. model kind는 1개짜리 배열이고,
## 알 수 없는 조합이면 빈 배열.
static func candidate_parts(role: String, variation_id: String) -> Array:
	var variation := _variation(role, variation_id)
	if variation.is_empty():
		return []
	return variation["parts"] if variation.has("parts") else [variation["key"]]


## 권장 uniform scale 배수(생략 시 native 1.0). 알 수 없는 조합이면 0.0.
static func candidate_scale_hint(role: String, variation_id: String) -> float:
	var variation := _variation(role, variation_id)
	if variation.is_empty():
		return 0.0
	return variation.get("scale_hint", 1.0)


static func animation_actions() -> Array:
	return ANIMATION_SETS.keys()


## gameplay action의 애니메이션 후보 목록({library, name}, first = primary).
## 알 수 없는 action이면 빈 배열.
static func animations_for_action(action: String) -> Array:
	return ANIMATION_SETS.get(action, [])


## hand attach처럼 "들고 쓰는" 용도의 권장 uniform scale 배수를 key 역방향으로
## 조회한다(VIS-001-4 tool attach가 사용). SELECTIONS 어디에도 scale_hint 없이
## 등장하지 않는 key면 native 1.0.
static func attachment_scale_hint_for_key(key: String) -> float:
	for role in SELECTIONS:
		for variation in SELECTIONS[role]["variations"]:
			if variation.get("key", "") == key and variation.has("scale_hint"):
				return variation["scale_hint"]
	return 1.0
