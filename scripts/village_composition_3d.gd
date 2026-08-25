extends Node3D
class_name VillageComposition3D

## TASK-3D-VIS-001-5 Visual Village Composition Prototype.
## 기능 연결 전 단계에서 Quaternius 에셋 스택(3D Asset Stack LOCK)만으로
## "게임처럼 보이는" 작은 마을 화면을 조립하는 시각 전용 프로토타입 scene이다.
##
## - 모든 모델은 VisualAssetCatalog3D 키 조회로만 생성한다(Scene -> 파일 경로
##   직접 참조 없음). 배치는 결정적 레이아웃 테이블이라 반복 실행에서 동일 화면.
## - 공간 밀도 원칙을 RECT로 코드화한다: VILLAGE(저밀도 생활) / LUMBERYARD·
##   QUARRY(작업 정체성 props) / FOREST(고밀도 수목) 4 zone이 서로 겹치지
##   않고, Main path(P_* corridor)는 어떤 solid 오브젝트도 침범하지 않는다
##   (gameplay path 가독성 원칙의 자동 검증 계약 — task3dvis0015_test).
## - 반복 모델 variation 제한: tree 4종 / rock 3종 / house palette 2종으로 고정.
## - 주민/Worker/Mercenary는 CharacterRig3D(VIS-001-4 공용 리그)를 그대로 쓴다.
##   이동/AI 없이 initial_action 재생만 한다(기능 연결은 WRK/CMB 도메인 소유).
## - 지면 톤: world3d.tscn placeholder GroundVisual에 런타임 material_override를
##   입히는 기존 캡처 도구 관례(capture_environment_3d._dress_ground)를 소유
##   API(apply_ground_tone)로 정식화했다. scene 파일은 무수정이며 실제 terrain
##   교체는 INT-001 인계(INTEGRATION_NOTE_VIS.md 참조). Main path/plaza는
##   지면 위 얇은 평면 strip(y=0.05, shadow off)으로 표현하고 충돌체를 만들지
##   않는다(순수 장식 — selection/nav 비간섭).
##
## 소유 경계: 이 scene은 screen composition 검증용이다. gameplay 건물/자원/
## Worker Actor가 아니므로 collision/selection/nav 노드를 갖지 않고, BLD/RES/
## WRK 도메인 파일을 수정하지 않는다.

## -- 공간 밀도 zone(태스크 원칙의 단일 소스). Rect2 = XZ 평면(x=min_x, y=min_z).
const ZONE_VILLAGE := Rect2(-11, -11, 22, 22)
const ZONE_FOREST := Rect2(-35, -31, 12, 22)
const ZONE_LUMBERYARD := Rect2(-30, 3, 11, 11)
const ZONE_QUARRY := Rect2(16, 10, 14, 12)

const ZONE_RECTS := {
	"village": ZONE_VILLAGE,
	"forest": ZONE_FOREST,
	"lumberyard": ZONE_LUMBERYARD,
	"quarry": ZONE_QUARRY,
}

## -- Main path corridor(XZ 평면 통행 구역). solid 배치 금지 구역이며
## PATH_MARGIN만큼 여유를 두고 검증한다(path_clearance 계약).
const PATH_SPINE := Rect2(-1, -24, 2, 42)
const PATH_EAST := Rect2(0, -1, 23, 2)
const PATH_WEST := Rect2(-21, -1, 21, 2)
const PATH_FOREST := Rect2(-21, -27, 2, 26)
const PATH_YARD := Rect2(-21, 1, 2, 4)
const PATH_QUARRY := Rect2(21, 1, 2, 13)
const PATH_PLAZA := Rect2(-3, -3, 6, 6)

const PATH_CORRIDORS := {
	"spine": PATH_SPINE,
	"east": PATH_EAST,
	"west": PATH_WEST,
	"forest_road": PATH_FOREST,
	"yard_road": PATH_YARD,
	"quarry_road": PATH_QUARRY,
	"plaza": PATH_PLAZA,
}

## solid 오브젝트가 지켜야 할 path 여유 폭(unit).
const PATH_MARGIN := 0.5

## -- 지면/path 톤. ground albedo는 task3dvis0013 가독성 밴드 검증과 같은 값.
const GROUND_TONE_ALBEDO := Color(0.42, 0.62, 0.35)
const PATH_ALBEDO := Color(0.55, 0.46, 0.34)
const PLAZA_ALBEDO := Color(0.61, 0.52, 0.38)
const PATH_STRIP_Y := 0.05

## -- 제한적 variation 팔레트(태스크 원칙). 이 범위 밖 모델을 추가하지 않는다.
## house palette: catalog house_building 조합(floor/wall/window/door 교체).
const HOUSE_PLASTER := {
	"floor": "bld/floor_wood_light",
	"wall": "bld/wall_plaster_straight",
	"window": "bld/wall_plaster_window_wide",
	"door": "bld/wall_plaster_door_flat",
}
const HOUSE_BRICK := {
	"floor": "bld/floor_brick",
	"wall": "bld/wall_brick_straight",
	"window": "bld/wall_brick_window_wide",
	"door": "bld/wall_brick_door_flat",
}

## tree variation(catalog tree role의 5개 중 4개 선택, scale_hint 준수).
const TREE_VARIANTS := [
	{"key": "tree/common_1", "scale": 0.55},
	{"key": "tree/common_3", "scale": 0.55},
	{"key": "tree/pine_1", "scale": 0.5},
	{"key": "tree/pine_2", "scale": 0.5},
]

## Medieval Village 벽 모듈 실측(2m 그리드, 높이 3.12). 지붕 roundtiles_6x6는
## capture_environment_3d에서 화면 검증된 조립식(scale = (변+0.8)/8.25)을 그대로
## 일반화해 사용한다. 상세 근거: auto_dev/VIS_VILLAGE_COMPOSITION_REPORT.md.
const WALL_HEIGHT := 3.12
const ROOF_NATIVE_SPAN := 8.25
const ROOF_NATIVE_EAVE_DROP := 0.78
const ROOF_EAVE_OVERHANG := 0.8

var _zone_roots := {}
var _solids: Array = []


func _ready() -> void:
	add_to_group("village_composition_3d")
	for zone in ZONE_RECTS:
		var root := Node3D.new()
		root.name = "Zone_%s" % zone.to_pascal_case()
		add_child(root)
		_zone_roots[zone] = root
	var paths_root := Node3D.new()
	paths_root.name = "Paths"
	add_child(paths_root)
	var chars_root := Node3D.new()
	chars_root.name = "Villagers"
	add_child(chars_root)
	_build_paths(paths_root)
	_build_village(_zone_roots["village"])
	_build_forest(_zone_roots["forest"])
	_build_lumberyard(_zone_roots["lumberyard"])
	_build_quarry(_zone_roots["quarry"])
	_build_characters(chars_root)


## world3d.tscn의 placeholder GroundVisual에 stylized 잔디 톤을 입힌다.
## GroundVisual이 없는 독립 실행이면 false(호출자가 자체 지면을 준비한다).
func apply_ground_tone(world_root: Node) -> bool:
	if world_root == null:
		return false
	var stack: Array = [world_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and node.name == "GroundVisual":
			var material := StandardMaterial3D.new()
			material.albedo_color = GROUND_TONE_ALBEDO
			material.roughness = 1.0
			(node as MeshInstance3D).material_override = material
			return true
		stack.append_array(node.get_children())
	return false


func get_zone_root(zone: String) -> Node3D:
	return _zone_roots.get(zone)


func zone_rects() -> Dictionary:
	return ZONE_RECTS.duplicate(true)


func path_corridors() -> Dictionary:
	return PATH_CORRIDORS.duplicate(true)


## 등록된 solid 배치 목록([{rect, key, zone}]). path 침범 검증 소비 전용.
func solid_footprints() -> Array:
	return _solids.duplicate(true)


## ==========================================================================
## 내부 조립. 모든 spawn은 결정적 좌표다(RNG 없음).

func _spawn(key: String, zone: String, kind: String, pos: Vector3,
		yaw_deg := 0.0, uniform_scale := 1.0, solid_half := Vector2.ZERO) -> Node3D:
	var node := VisualAssetCatalog3D.instantiate_model(key)
	if node == null:
		push_error("VillageComposition3D: model failed '%s'" % key)
		return null
	node.position = WorldCoords3D.flatten(pos)
	node.rotation.y = deg_to_rad(yaw_deg)
	node.scale = Vector3.ONE * uniform_scale
	node.set_meta("catalog_key", key)
	node.set_meta("zone", zone)
	node.set_meta("kind", kind)
	_zone_roots[zone].add_child(node)
	if solid_half != Vector2.ZERO:
		_solids.append({
			"rect": Rect2(pos.x - solid_half.x, pos.z - solid_half.y,
				solid_half.x * 2.0, solid_half.y * 2.0),
			"key": key,
			"zone": zone,
		})
	return node


func _build_paths(root: Node3D) -> void:
	for corridor_name in PATH_CORRIDORS:
		var rect: Rect2 = PATH_CORRIDORS[corridor_name]
		var mesh := PlaneMesh.new()
		mesh.size = rect.size
		var instance := MeshInstance3D.new()
		instance.name = "Path_%s" % corridor_name.to_pascal_case()
		instance.mesh = mesh
		instance.position = Vector3(rect.get_center().x, PATH_STRIP_Y,
			rect.get_center().y)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.albedo_color = PLAZA_ALBEDO if corridor_name == "plaza" \
			else PATH_ALBEDO
		material.roughness = 1.0
		instance.material_override = material
		root.add_child(instance)


## -- VILLAGE: 저밀도 생활 공간. 집 5채 + 생활 props. 수목은 포인트 2그루만.
func _build_village(root: Node3D) -> void:
	_add_house(root, 4, HOUSE_PLASTER, Vector3(-7, 0, -7), 90.0, true)
	_add_house(root, 4, HOUSE_BRICK, Vector3(-7, 0, 5), 90.0, false)
	_add_house(root, 4, HOUSE_BRICK, Vector3(7, 0, -7), -90.0, true)
	_add_house(root, 4, HOUSE_PLASTER, Vector3(8, 0, 8), -90.0, false)
	_add_house(root, 6, HOUSE_PLASTER, Vector3(-6, 0, -16), 90.0, true)

	# 광장 남서 녹지 포인트 수목(마을 내 수목 밀도 의도적 최소).
	_spawn("tree/common_3", "village", "tree", Vector3(-6, 0, 13),
		15.0, 0.5, Vector2(1.2, 1.2))
	_spawn("tree/pine_2", "village", "tree", Vector3(6, 0, -13),
		-30.0, 0.5, Vector2(1.3, 1.3))

	# 마을 남쪽 성문 느낌 울타리(spine 양측, 통행은 막지 않는 폭).
	for side in [-1.0, 1.0]:
		_spawn("bld/fence_wooden_single", "village", "prop",
			Vector3(side * 2.4, 0, 16.0), 90.0)
		_spawn("bld/fence_wooden_single", "village", "prop",
			Vector3(side * 2.4, 0, 18.0), 90.0)

	# 동쪽 잔도 시장 행(마을 기능 정체성 props).
	_spawn("prop/stall_empty", "village", "prop", Vector3(6, 0, -3.2),
		0.0, 1.0, Vector2(0.95, 0.5))
	_spawn("prop/stall_cart_empty", "village", "prop", Vector3(9.5, 0, -3.2),
		0.0, 1.0, Vector2(1.55, 0.55))
	_spawn("prop/farmcrate_apple", "village", "prop", Vector3(7.4, 0, -2.2))
	_spawn("prop/farmcrate_carrot", "village", "prop", Vector3(8.1, 0, -2.0))
	_spawn("prop/farmcrate_empty", "village", "prop", Vector3(6.2, 0, 3.2))
	_spawn("prop/coin_pile", "village", "prop", Vector3(7.8, 0, -1.6))
	_spawn("prop/bag", "village", "prop", Vector3(6.6, 0, -2.5))
	_spawn("prop/barrel", "village", "prop", Vector3(5.2, 0, -2.6))
	_spawn("prop/barrel", "village", "prop", Vector3(10.2, 0, 3.0))

	# 광장 화단 + 가옥 담장.
	_spawn("veg/flower_group_4", "village", "prop", Vector3(-2.4, 0, -2.4))
	_spawn("veg/flower_group_4", "village", "prop", Vector3(2.4, 0, 2.4))
	for i in 2:
		_spawn("bld/fence_wooden_single", "village", "prop",
			Vector3(-8.4 + i * 2.1, 0, 7.7), 0.0)


## house_size_m: 4 또는 6(m). 문은 로컬 남쪽(+Z) 벽에 있고 yaw_deg로 방향을 돌린다.
func _add_house(root: Node3D, house_size_m: int, palette: Dictionary,
		pos: Vector3, yaw_deg: float, with_chimney: bool) -> Node3D:
	var house := Node3D.new()
	house.name = "House"
	root.add_child(house)
	house.position = WorldCoords3D.flatten(pos)
	house.rotation.y = deg_to_rad(yaw_deg)
	var half := float(house_size_m) * 0.5
	var cells := int(half)

	for i in cells:
		for j in cells:
			_attach_model(house, palette["floor"],
				Vector3(-half + 1.0 + 2.0 * i, 0, -half + 1.0 + 2.0 * j))
			# 뒷줄 북벽.
			_attach_model(house, palette["wall"],
				Vector3(-half + 1.0 + 2.0 * i, 0, -half))
			# 앞줄 남벽(문 1칸 + 창).
			var front_key: String = palette["door"] if i == cells - 1 \
				else palette["window"]
			_attach_model(house, front_key,
				Vector3(-half + 1.0 + 2.0 * i, 0, half))
		# 동서 측벽.
		_attach_model(house, palette["wall"],
			Vector3(-half, 0, -half + 1.0 + 2.0 * i), 90.0)
		_attach_model(house, palette["wall"],
			Vector3(half, 0, -half + 1.0 + 2.0 * i), 90.0)

	# 지붕: capture_environment_3d에서 검증된 처마 걸침 조립식.
	var roof_scale := (float(house_size_m) + ROOF_EAVE_OVERHANG) \
		/ ROOF_NATIVE_SPAN
	_attach_model(house, "bld/roof_roundtiles_6x6",
		Vector3(0, WALL_HEIGHT + ROOF_NATIVE_EAVE_DROP * roof_scale, 0),
		0.0, roof_scale)
	if with_chimney:
		_attach_model(house, "bld/chimney",
			Vector3(float(house_size_m) * 0.22, 0.39
				+ 5.67 * roof_scale, 0))

	# 문 옆 자립 횃불(벽 부착 랜턴은 자립 시 암아트라 횃불 포스트로 대체).
	_attach_model(house, "prop/torch_metal",
		Vector3(half - 1.0 + 1.15, 0, half + 0.45))

	house.set_meta("catalog_key", "house/%s/%dm" %
		["brick" if palette == HOUSE_BRICK else "plaster", house_size_m])
	house.set_meta("kind", "house")
	var wall_pad := 0.205
	_solids.append({
		"rect": Rect2(pos.x - half - wall_pad, pos.z - half - wall_pad,
			(half + wall_pad) * 2.0, (half + wall_pad) * 2.0),
		"key": house.get_meta("catalog_key"),
		"zone": "village",
	})
	return house


## house 컨테이너(로컬 좌표)에 catalog 모델을 붙인다.
func _attach_model(house: Node3D, key: String, local_pos: Vector3,
		yaw_deg := 0.0, uniform_scale := 1.0) -> Node3D:
	var node := VisualAssetCatalog3D.instantiate_model(key)
	if node == null:
		push_error("VillageComposition3D: model failed '%s'" % key)
		return null
	node.position = local_pos
	node.rotation.y = deg_to_rad(yaw_deg)
	node.scale = Vector3.ONE * uniform_scale
	node.set_meta("catalog_key", key)
	house.add_child(node)
	return node


## -- FOREST: 고밀도 수목 클러스터 + 하층 식생. path에서 1.5 이상 띄운다.
func _build_forest(root: Node3D) -> void:
	var tree_layout := [
		[-33, -28, 0], [-31, -25, 1], [-34, -22, 2], [-30, -29, 3],
		[-28, -27, 0], [-32, -19, 1], [-29, -21, 2], [-26, -29, 0],
		[-25, -24, 3], [-33, -15, 2], [-30, -13, 0], [-27, -17, 1],
		[-24, -26, 2], [-28, -11, 3], [-25, -14, 0], [-31, -10, 1],
		[-33, -24, 3], [-26, -20, 0], [-23, -28, 1], [-24, -22, 2],
		[-29, -16, 3], [-23, -12, 0], [-27, -23, 1], [-25, -18, 2],
	]
	for item in tree_layout:
		var variant: Dictionary = TREE_VARIANTS[item[2]]
		_spawn(variant["key"], "forest", "tree",
			Vector3(item[0], 0, item[1]), fmod(item[0] * 37.0, 360.0),
			variant["scale"], Vector2(1.2, 1.2))

	var understory := [
		["veg/bush_common", -31, -27], ["veg/bush_common", -27, -25],
		["veg/bush_flowers", -32, -20], ["veg/bush_common", -28, -18],
		["veg/grass_common_tall", -33, -17], ["veg/grass_common_tall", -26, -27],
		["veg/grass_wispy_tall", -30, -23], ["veg/grass_common_short", -25, -21],
		["veg/mushroom", -31, -13], ["veg/bush_flowers", -24, -16],
		["veg/grass_common_tall", -27, -13], ["veg/grass_common_short", -29, -12],
	]
	for item in understory:
		_spawn(item[0], "forest", "vegetation", Vector3(item[1], 0, item[2]))

	# 숲 가장자리 바위 1개(전이부 읽기).
	_spawn("rock/medium_2", "forest", "rock", Vector3(-23.6, 0, -10.5),
		20.0, 0.8, Vector2(1.2, 1.0))


## -- LUMBERYARD: 벌목 작업 정체성 props(stump/log pile/wagon) + 벌목꾼 자리.
func _build_lumberyard(root: Node3D) -> void:
	# 도마(stump) 작업대 + 기대 놓은 도끼.
	_spawn("tool/chopping_log", "lumberyard", "workstation",
		Vector3(-24, 0, 8), 10.0, 1.0, Vector2(0.5, 0.45))
	_spawn("tool/axe_bronze", "lumberyard", "prop",
		Vector3(-23.1, 0, 7.4), 65.0)
	_spawn("prop/torch_metal", "lumberyard", "prop", Vector3(-24.9, 0, 8.9))

	# 원목 더미(같은 모델 4개, yaw/scale 미세 jitter만 허용).
	_spawn("tool/chopping_log", "lumberyard", "log_pile",
		Vector3(-26.4, 0, 10.2), 100.0, 1.0, Vector2(1.6, 2.2))
	_spawn("tool/chopping_log", "lumberyard", "log_pile",
		Vector3(-25.2, 0, 11.0), 82.0, 0.92)
	_spawn("tool/chopping_log", "lumberyard", "log_pile",
		Vector3(-26.9, 0, 11.6), 118.0, 0.96)
	_spawn("tool/chopping_log", "lumberyard", "log_pile",
		Vector3(-25.8, 0, 12.2), 95.0, 0.88)

	# 운반 마차 + 저장 코너.
	_spawn("bld/wagon", "lumberyard", "prop", Vector3(-24, 0, 12.5),
		90.0, 1.0, Vector2(2.1, 1.0))
	_spawn("prop/crate_wooden", "lumberyard", "prop", Vector3(-22.6, 0, 4.2),
		15.0)
	_spawn("prop/crate_wooden", "lumberyard", "prop", Vector3(-21.9, 0, 4.9),
		-10.0)
	_spawn("prop/barrel", "lumberyard", "prop", Vector3(-22.4, 0, 5.8))


## -- QUARRY: 암반 아웃크롭 + 석재 더미 + 채굴 정체성 props.
func _build_quarry(root: Node3D) -> void:
	# 본체 아웃크롭(corridor 동측, x >= 25 유지).
	_spawn("rock/medium_1", "quarry", "rock", Vector3(25.5, 0, 15),
		0.0, 1.0, Vector2(1.6, 1.5))
	_spawn("rock/medium_3", "quarry", "rock", Vector3(27.5, 0, 16.5),
		40.0, 1.0, Vector2(1.7, 1.75))
	_spawn("rock/medium_2", "quarry", "rock", Vector3(26, 0, 18.5),
		-25.0, 1.0, Vector2(1.5, 1.25))
	_spawn("rock/medium_1", "quarry", "rock", Vector3(28.2, 0, 19.5),
		70.0, 0.85, Vector2(1.4, 1.3))
	# 서측 잔반(corridor 서측, x <= 19 유지).
	_spawn("rock/medium_2", "quarry", "rock", Vector3(18.4, 0, 13),
		50.0, 0.9, Vector2(1.4, 1.1))
	_spawn("rock/medium_3", "quarry", "rock", Vector3(17.2, 0, 15.5),
		-15.0, 0.85, Vector2(1.45, 1.5))

	# 채굴 작업대: 곡괭이 + 크레이트, 석재 더미(cluster, scale 0.55 밴드).
	_spawn("tool/pickaxe_bronze", "quarry", "prop", Vector3(24.6, 0, 12.4),
		115.0)
	_spawn("prop/crate_wooden", "quarry", "prop", Vector3(25.4, 0, 11.6),
		20.0)
	_spawn("rock/medium_2", "quarry", "stone_pile", Vector3(25, 0, 13.2),
		75.0, 0.55, Vector2(0.85, 0.7))
	_spawn("rock/medium_1", "quarry", "stone_pile", Vector3(26.1, 0, 13.8),
		130.0, 0.55, Vector2(0.9, 0.85))
	_spawn("rock/medium_3", "quarry", "stone_pile", Vector3(25.5, 0, 14.4),
		-60.0, 0.5, Vector2(0.85, 0.85))
	_spawn("prop/torch_metal", "quarry", "prop", Vector3(23.9, 0, 14.8))


## -- 주민/Worker/Mercenary visual(CharacterRig3D 공용 리그, action 재생만).
func _build_characters(root: Node3D) -> void:
	_add_rig(root, "villager_male", "human/male_base", "",
		"idle", Vector3(-1.8, 0, 3.4), 160.0)
	_add_rig(root, "villager_female", "human/female_base", "",
		"idle", Vector3(-4.6, 0, 7.9), 90.0)
	_add_rig(root, "carrier_worker", "outfit/female_peasant_full", "",
		"walk", Vector3(0, 0, 8), 180.0)
	_add_rig(root, "worker_lumberjack", "outfit/male_peasant_full",
		"tool/axe_bronze", "work", Vector3(-24.8, 0, 6.9), 40.0)
	_add_rig(root, "worker_miner", "outfit/male_peasant_full",
		"tool/pickaxe_bronze", "work", Vector3(25.3, 0, 13.3), 205.0)
	_add_rig(root, "mercenary_guard", "outfit/male_ranger_full",
		"tool/sword_bronze", "idle", Vector3(0, 0, 15), 0.0)


func _add_rig(root: Node3D, role: String, body_key: String, tool_key: String,
		action: String, pos: Vector3, yaw_deg: float) -> CharacterRig3D:
	var rig := CharacterRig3D.new()
	rig.name = role.to_pascal_case()
	rig.body_key = body_key
	rig.tool_key = tool_key
	rig.initial_action = action
	rig.position = WorldCoords3D.flatten(pos)
	rig.rotation.y = deg_to_rad(yaw_deg)
	rig.set_meta("role", role)
	rig.set_meta("action", action)
	root.add_child(rig)
	return rig
