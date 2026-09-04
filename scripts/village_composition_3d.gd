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
const ZONE_FOREST := Rect2(27, -31, 12, 22)
const ZONE_LUMBERYARD := Rect2(18, 3, 11, 11)
const ZONE_QUARRY := Rect2(41, 10, 14, 12)

const ZONE_RECTS := {
	"village": ZONE_VILLAGE,
	"forest": ZONE_FOREST,
	"lumberyard": ZONE_LUMBERYARD,
	"quarry": ZONE_QUARRY,
}

## -- Main path corridor(XZ 평면 통행 구역). solid 배치 금지 구역이며
## PATH_MARGIN만큼 여유를 두고 검증한다(path_clearance 계약).
const PATH_SPINE := Rect2(-30, -5.0, 20.0, 4.0)
const PATH_EAST := Rect2(0, -4.0, 12.0, 4.0)
const PATH_WEST := Rect2(-17, -1.0, 4.0, 5.0)
const PATH_FOREST := Rect2(18, 5.0, 8.0, 2.0)
const PATH_YARD := Rect2(3.0, -17.0, 1.0, 6.0)
const PATH_QUARRY := Rect2(37, 10.0, 5.0, 2.0)
const PATH_PLAZA := Rect2(-4.0, -6.0, 8.0, 8.0)

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
const GROUND_TONE_ALBEDO := Color(0.34, 0.50, 0.29)
const PATH_ALBEDO := Color(0.40, 0.34, 0.26, 0.90)
const PLAZA_ALBEDO := Color(0.46, 0.40, 0.32, 0.94)
const PATH_STRIP_Y := 0.05
const HOUSE_VISUAL_SCALE := 0.72

const CUTESKULL_CITY := preload("res://assets/cuteskull-medieval-city/city16.fbx")

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
		# Authored visual zones are re-rooted around the settlement. Gameplay
		# resources/navigation keep their existing WorldMap coordinates.
		if zone == "forest":
			root.position.x = 62.0
		elif zone == "lumberyard":
			root.position.x = 48.0
		elif zone == "quarry":
			root.position.x = 25.0
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
	_build_landmark_dressing()
	_build_frontier_dressing()


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
			var grass_noise := FastNoiseLite.new()
			grass_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			grass_noise.frequency = 0.018
			grass_noise.fractal_octaves = 4
			var grass_texture := NoiseTexture2D.new()
			grass_texture.width = 512
			grass_texture.height = 512
			grass_texture.seamless = true
			grass_texture.noise = grass_noise
			var grass_ramp := Gradient.new()
			grass_ramp.colors = PackedColorArray([
				Color(0.62, 0.68, 0.55), Color(0.92, 0.96, 0.84),
			])
			grass_texture.color_ramp = grass_ramp
			material.albedo_texture = grass_texture
			material.uv1_scale = Vector3(4.0, 4.0, 4.0)
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
	# Paths are built from short segments, not debug rectangles. The only broad
	# open surface is the modest Keep forecourt/plaza.
	var plaza := MeshInstance3D.new()
	plaza.name = "Path_VillagePlaza"
	var plaza_mesh := CylinderMesh.new()
	plaza_mesh.top_radius = 4.7
	plaza_mesh.bottom_radius = 4.7
	plaza_mesh.height = 0.035
	plaza.mesh = plaza_mesh
	plaza.position = Vector3(2, PATH_STRIP_Y, -2.0)
	plaza.scale = Vector3(1.05, 1.0, 0.76)
	plaza.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plaza_material := StandardMaterial3D.new()
	plaza_material.albedo_color = PLAZA_ALBEDO
	plaza_material.roughness = 1.0
	plaza_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plaza.material_override = plaza_material
	root.add_child(plaza)
	_spawn_path_curve(root, "Path_Gate_Main", [Vector3(-30, 0, -3),
		Vector3(-25, 0, -2.5), Vector3(-20, 0, -1), Vector3(-15, 0, 0.5),
		Vector3(-9, 0, -1.2), Vector3(-4, 0, -3), Vector3(0, 0, -2)], 3.8)
	_spawn_path_curve(root, "Path_Plaza_Keep", [Vector3(5, 0, -2),
		Vector3(8, 0, -2.5), Vector3(11, 0, -2)], 3.2)
	_spawn_path_curve(root, "Path_Blacksmith", [Vector3(-17, 0, -0.3),
		Vector3(-15, 0, 4), Vector3(-12, 0, 9)], 1.9)
	_spawn_path_curve(root, "Path_Market", [Vector3(-4, 0, -1),
		Vector3(-4.5, 0, 3), Vector3(-5, 0, 7)], 1.8)
	_spawn_path_curve(root, "Path_Tavern", [Vector3(-1, 0, -6),
		Vector3(-2.5, 0, -10), Vector3(-1, 0, -14)], 1.8)
	_spawn_path_curve(root, "Path_Inn", [Vector3(6, 0, 1),
		Vector3(10, 0, 3), Vector3(13, 0, 6), Vector3(16, 0, 8)], 1.9)
	_spawn_path_curve(root, "Path_Residential_North", [Vector3(1, 0, -8),
		Vector3(3, 0, -13), Vector3(2, 0, -18), Vector3(4, 0, -22)], 1.7)
	_spawn_path_curve(root, "Path_Residential_East", [Vector3(9, 0, 2),
		Vector3(14, 0, 7), Vector3(20, 0, 12), Vector3(27, 0, 13)], 1.8)
	_spawn_path_curve(root, "Path_Production", [Vector3(16, 0, 8),
		Vector3(23, 0, 7), Vector3(30, 0, 10), Vector3(39, 0, 12)], 2.2)
	# Secondary lanes bend around the settlement instead of exposing a debug-like
	# rectilinear grid. They are visual-only and remain outside gameplay owners.
	_spawn_path_curve(root, "Path_Farm_West", [Vector3(23, 0, 7),
		Vector3(27, 0, 10), Vector3(30, 0, 14)], 1.7)
	_spawn_path_curve(root, "Path_Farm_East", [Vector3(30, 0, 10),
		Vector3(35, 0, 9), Vector3(40, 0, 7)], 1.7)
	_spawn_path_curve(root, "Path_Forest_East", [Vector3(23, 0, 7),
		Vector3(26, 0, 2), Vector3(30, 0, -5), Vector3(32, 0, -12)], 1.7)


func _build_village_clearing() -> void:
	# One soft, irregular clearing gives the settlement a sense of place. It is
	# deliberately not a per-district rectangle or debug overlay.
	var clearing := MeshInstance3D.new()
	clearing.name = "VillageClearing"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 22.0
	mesh.bottom_radius = 22.0
	mesh.height = 0.025
	clearing.mesh = mesh
	clearing.position = Vector3(3, 0.012, 0.0)
	clearing.scale = Vector3(1.25, 1.0, 0.86)
	clearing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.37, 0.48, 0.30)
	material.roughness = 1.0
	clearing.material_override = material
	add_child(clearing)


func _build_ground_variation() -> void:
	# Soft, overlapping terrain tones break the single green plane without
	# introducing artificial district rectangles or a new terrain subsystem.
	var patches := [
		{"name": "WornGrass_West", "pos": Vector3(-24, 0.01, 8), "radius": 13.0,
			"scale": Vector3(1.4, 1.0, 0.7), "color": Color("#5f7048")},
		{"name": "WornGrass_East", "pos": Vector3(24, 0.01, -8), "radius": 15.0,
			"scale": Vector3(0.8, 1.0, 1.35), "color": Color("#617248")},
		{"name": "FarmSoil_Edge", "pos": Vector3(22, 0.012, 14), "radius": 9.0,
			"scale": Vector3(1.4, 1.0, 0.55), "color": Color("#675642")},
		{"name": "Battlefield_Worn", "pos": Vector3(-58, 0.012, 0), "radius": 16.0,
			"scale": Vector3(1.0, 1.0, 0.72), "color": Color("#665b4b")},
	]
	for item in patches:
		var patch := MeshInstance3D.new()
		patch.name = item["name"]
		var mesh := CylinderMesh.new()
		mesh.top_radius = item["radius"]
		mesh.bottom_radius = item["radius"]
		mesh.height = 0.018
		patch.mesh = mesh
		patch.position = item["pos"]
		patch.scale = item["scale"]
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.albedo_color = item["color"]
		material.roughness = 1.0
		patch.material_override = material
		add_child(patch)


func _spawn_path_curve(root: Node3D, path_name: String, points: Array,
		width: float) -> void:
	for i in range(points.size() - 1):
		var from: Vector3 = points[i]
		var to: Vector3 = points[i + 1]
		_spawn_path_segment(root, "%s_%d" % [path_name, i], from, to, width)
	# Rounded overlaps hide the modular strip joins and read as naturally worn
	# bends rather than an editor spline made from disconnected boards.
	for i in range(1, points.size() - 1):
		_spawn_path_joint(root, "%s_Joint_%d" % [path_name, i], points[i], width)


func _spawn_path_joint(root: Node3D, joint_name: String, pos: Vector3,
		width: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = width * 0.52
	mesh.bottom_radius = width * 0.52
	mesh.height = 0.04
	var instance := MeshInstance3D.new()
	instance.name = joint_name
	instance.mesh = mesh
	instance.position = Vector3(pos.x, PATH_STRIP_Y, pos.z)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = PATH_ALBEDO
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	root.add_child(instance)


func _spawn_path_segment(root: Node3D, path_name: String, from: Vector3,
		to: Vector3, width: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.04, from.distance_to(to) + 0.85)
	var instance := MeshInstance3D.new()
	instance.name = path_name
	instance.mesh = mesh
	instance.position = (from + to) * 0.5
	instance.position.y = PATH_STRIP_Y
	instance.name = path_name
	instance.look_at_from_position(instance.position, to, Vector3.UP)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = PATH_ALBEDO
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	root.add_child(instance)


## -- VILLAGE: 저밀도 생활 공간. 집 5채 + 생활 props. 수목은 포인트 2그루만.
func _build_village(root: Node3D) -> void:
	# Houses sit beyond the widened roads, leaving a deliberate open ring around
	# the Keep and service buildings instead of a tight radial prefab cluster.
	# Two uneven residential clusters grew from side lanes rather than a ring.
	_add_cuteskull_house(root, "House_4_1", Vector3(-7, 0, -21), 18.0)
	_add_cuteskull_house(root, "House_5_1", Vector3(3, 0, -24), -12.0)
	_add_cuteskull_house(root, "House_2_1", Vector3(12, 0, -19), 31.0)
	_add_cuteskull_house(root, "House_2_2", Vector3(-13, 0, -24), 37.0)
	_add_cuteskull_house(root, "House_1_1", Vector3(-2, 0, -18), -28.0)
	_add_cuteskull_house(root, "House_4_2", Vector3(20, 0, 18), -104.0)
	_add_cuteskull_house(root, "House_5_2", Vector3(29, 0, 15), -78.0)
	_add_cuteskull_house(root, "House_2_3", Vector3(25, 0, 22), -61.0)
	_spawn_cuteskull_prop("Market/Well", "VillageWell", Vector3(1.0, 0, -2.2),
		-8.0, 0.085)
	_spawn_cuteskull_prop("Market/Market_1_2", "MarketAwningWest",
		Vector3(-3.0, 0, 3.8), 12.0, 0.10)
	_spawn_cuteskull_prop("Market/Market_1_5", "MarketAwningSouth",
		Vector3(-5.5, 0, 4.7), -21.0, 0.10)
	_spawn_cuteskull_prop("Market/Cart", "MarketHandcart",
		Vector3(-2.3, 0, 6.2), 38.0, 0.09)

	# A restrained forecourt around the Keep creates a readable focal point
	# without adding a new gameplay landmark or collision owner.
	_spawn("prop/torch_metal", "village", "keep_forecourt", Vector3(7.4, 0, -4.8))
	_spawn("prop/torch_metal", "village", "keep_forecourt", Vector3(7.2, 0, 0.6))
	_spawn("prop/chest_wood", "village", "keep_forecourt", Vector3(9.2, 0, 2.0))

	# 광장 남서 녹지 포인트 수목(마을 내 수목 밀도 의도적 최소).
	_spawn("tree/common_3", "village", "tree", Vector3(-6, 0, 13),
		15.0, 0.5, Vector2(1.2, 1.2))
	_spawn("tree/pine_2", "village", "tree", Vector3(6, 0, -13),
		-30.0, 0.5, Vector2(1.3, 1.3))
	_spawn("tree/common_1", "village", "edge_transition", Vector3(-12.5, 0, -11.5),
		-15.0, 0.48)
	_spawn("tree/common_4", "village", "edge_transition", Vector3(12.5, 0, 9.8),
		20.0, 0.48)
	_spawn("veg/bush_common", "village", "edge_transition", Vector3(-11.5, 0, 2.5))
	_spawn("veg/bush_common", "village", "edge_transition", Vector3(11.2, 0, 5.5))
	# Irregular green buffers define yard edges and soften the settlement into
	# surrounding land without outlining geometric districts.
	for item in [
		["tree/common_1", Vector3(-13, 0, -18), 0.56],
		["tree/common_3", Vector3(-2, 0, -27), 0.60],
		["tree/pine_1", Vector3(8, 0, -27), 0.55],
		["tree/common_4", Vector3(16, 0, -23), 0.58],
		["tree/common_1", Vector3(17, 0, 22), 0.56],
		["tree/pine_2", Vector3(25, 0, 21), 0.59],
		["tree/common_3", Vector3(35, 0, 17), 0.54],
	]:
		_spawn(item[0], "village", "settlement_buffer", item[1],
			float(item[1].x * 7.0), item[2])
	for pos in [
		Vector3(-10, 0, -25), Vector3(-3, 0, -20), Vector3(8, 0, -21),
		Vector3(15, 0, -16), Vector3(16, 0, 17), Vector3(24, 0, 14),
		Vector3(32, 0, 20), Vector3(35, 0, 12),
	]:
		_spawn("veg/grass_common_short", "village", "settlement_buffer", pos,
			float(pos.x * 11.0), 0.72)
	# Larger authored canopy silhouettes tie the houses to the forest edge and
	# break the empty-plane horizon at the default zoom.
	var canopy_layout := [
		["Tree_6", Vector3(-17, 0, -29), 0.095],
		["Tree_3", Vector3(-5, 0, -31), 0.10],
		["Tree_7", Vector3(9, 0, -29), 0.092],
		["Tree_2", Vector3(18, 0, -26), 0.10],
		["Tree_4", Vector3(14, 0, 24), 0.095],
		["Tree_8", Vector3(22, 0, 26), 0.09],
		["Tree_5", Vector3(32, 0, 24), 0.098],
		["Tree_1", Vector3(39, 0, 18), 0.10],
		["Tree_7", Vector3(39, 0, 8), 0.094],
		["Tree_3", Vector3(36, 0, -5), 0.10],
		["Tree_6", Vector3(34, 0, -16), 0.096],
	]
	for i in canopy_layout.size():
		var item: Array = canopy_layout[i]
		_spawn_cuteskull_prop("Environment_001/" + item[0],
			"SettlementCanopy_%02d" % i, item[1], float(i * 31 - 70), item[2])
	for pos in [Vector3(-22, 0, -5), Vector3(-18, 0, 3), Vector3(-8, 0, -5),
		Vector3(7, 0, 4), Vector3(14, 0, 12), Vector3(26, 0, 9)]:
		_spawn("rock/medium_1", "village", "roadside", pos,
			float(pos.z * 13.0), 0.28)

	# Small private yards reinforce two residential clusters without filling paths.
	for item in [
		[Vector3(-10.0, 0, -20.0), 14.0], [Vector3(0.0, 0, -20.5), -8.0],
		[Vector3(15.0, 0, -18.0), 32.0], [Vector3(18.0, 0, 15.0), -18.0],
		[Vector3(27.0, 0, 11.5), 18.0],
	]:
		_spawn("bld/fence_wooden_single", "village", "house_yard",
			item[0], item[1], 0.8)
	_spawn("prop/barrel", "village", "house_yard", Vector3(-10, 0, -23), 10.0, 0.7)
	_spawn("tool/chopping_log", "village", "house_yard", Vector3(6, 0, -22), -20.0, 0.65)
	_spawn("prop/crate_wooden", "village", "house_yard", Vector3(23, 0, 17), 12.0, 0.68)
	_spawn("veg/bush_common", "village", "house_yard", Vector3(32, 0, 12))
	_build_farm_plot(root)


func _build_landmark_dressing() -> void:
	# Functional clusters sit beside the existing gameplay-owned core buildings.
	# They are intentionally offset from corridors and carry no collision/nav data.
	# Keep forecourt: stone landmark reads first, with restrained torches already
	# placed by _build_village.
	_spawn("bld/stairs_exterior_straight", "village", "keep_forecourt",
		Vector3(7.8, 0, -2.0), 90.0, 0.72)

	# Tavern: barrels, outdoor table substitute and a warm lantern silhouette.
	_spawn("prop/barrel", "village", "tavern_cluster", Vector3(-4.2, 0, -14.2),
		18.0, 0.82)
	_spawn("prop/barrel", "village", "tavern_cluster", Vector3(-3.0, 0, -15.0),
		-12.0, 0.72)
	_spawn("prop/stall_cart_empty", "village", "tavern_cluster",
		Vector3(-4.0, 0, -11.0), 18.0, 0.72)
	_spawn("prop/lantern_wall", "village", "tavern_cluster",
		Vector3(1.6, 0, -12.8), 180.0, 0.8)

	# Inn: wagon and travel goods establish lodging/travel identity.
	_spawn("bld/wagon", "village", "inn_cluster", Vector3(19.8, 0, 6.0),
		-18.0, 0.72)
	_spawn("prop/bag", "village", "inn_cluster", Vector3(18.5, 0, 10.8),
		22.0, 0.8)
	_spawn("prop/chest_wood", "village", "inn_cluster",
		Vector3(20.5, 0, 10.0), -15.0, 0.72)

	# Blacksmith/equipment side: anvil, chopping log, fuel and forge light.
	_spawn("tool/anvil", "village", "blacksmith_cluster",
		Vector3(-9.2, 0, 9.0), 12.0, 0.72)
	_spawn("tool/chopping_log", "village", "blacksmith_cluster",
		Vector3(-9.8, 0, 11.2), -20.0, 0.7)
	_spawn("prop/crate_wooden", "village", "blacksmith_cluster",
		Vector3(-14.2, 0, 12.6), 18.0, 0.72)
	_spawn("prop/torch_metal", "village", "blacksmith_cluster",
		Vector3(-15.0, 0, 7.0), 0.0, 0.82)

	# Grocery/market: staggered stalls and food crates, kept south-west of the
	# east road so the main route remains open.
	_spawn("prop/stall_empty", "village", "market_cluster",
		Vector3(-5.5, 0, 10.8), -8.0, 0.76)
	_spawn("prop/farmcrate_carrot", "village", "market_cluster",
		Vector3(-3.8, 0, 10.4), 15.0, 0.7)
	_spawn("prop/farmcrate_apple", "village", "market_cluster",
		Vector3(-7.0, 0, 11.0), -22.0, 0.72)
	_spawn("prop/bag", "village", "market_cluster", Vector3(-7.2, 0, 8.6),
		-15.0, 0.76)

	# Small storage yard below the plaza: materials identify it without adding a
	# new storage gameplay owner.
	_spawn("prop/crate_wooden", "village", "storage_cluster",
		Vector3(-6.6, 0, 14.6), 9.0, 0.78)
	_spawn("prop/crate_wooden", "village", "storage_cluster",
		Vector3(-5.3, 0, 15.2), -18.0, 0.68)
	_spawn("prop/barrel", "village", "storage_cluster", Vector3(-7.8, 0, 15.4),
		28.0, 0.72)


func _build_farm_plot(root: Node3D) -> void:
	# A compact south-facing crop yard: visually distinct from the market and
	# connected directly to the south road, but intentionally light on props.
	var plot := Node3D.new()
	plot.name = "AgriculturePlot"
	root.add_child(plot)
	for row in range(4):
		var bed := MeshInstance3D.new()
		bed.name = "CropBed_East_%d" % row
		var mesh := BoxMesh.new()
		mesh.size = Vector3(5.2, 0.08, 0.58)
		bed.mesh = mesh
		bed.position = Vector3(32.0, 0.08, 15.0 + row * 1.05)
		bed.rotation.y = deg_to_rad(-7.0)
		var soil := StandardMaterial3D.new()
		soil.albedo_color = Color(0.32, 0.24, 0.16)
		soil.roughness = 1.0
		bed.material_override = soil
		plot.add_child(bed)
	for row in range(3):
		var bed := MeshInstance3D.new()
		bed.name = "CropBed_West_%d" % row
		var mesh := BoxMesh.new()
		mesh.size = Vector3(3.8, 0.08, 0.55)
		bed.mesh = mesh
		bed.position = Vector3(27.0, 0.08, 16.2 + row * 1.08)
		bed.rotation.y = deg_to_rad(11.0)
		var soil := StandardMaterial3D.new()
		soil.albedo_color = Color(0.29, 0.22, 0.15)
		soil.roughness = 1.0
		bed.material_override = soil
		plot.add_child(bed)
	for pos in [Vector3(27.5, 0, 14.4), Vector3(34.5, 0, 14.4),
			Vector3(27.5, 0, 19.2), Vector3(34.5, 0, 19.2)]:
		_spawn("bld/fence_wooden_single", "village", "farm_fence", pos, 90.0)
	_spawn("prop/farmcrate_carrot", "village", "farm_prop", Vector3(28.8, 0, 16.0))
	_spawn("prop/farmcrate_apple", "village", "farm_prop", Vector3(33.4, 0, 17.2))


func _build_frontier_dressing() -> void:
	# Left-side danger progression: the visual-only layer deliberately sits
	# outside gameplay gates/spawn owners and uses catalog assets only.
	_spawn_ground_patch("BattlefieldGround", Vector3(-58, 0, 0), 18.0, 0.72,
		Color(0.35, 0.31, 0.24))
	_spawn_ground_patch("CorruptedGround", Vector3(-88, 0, 0), 20.0, 0.78,
		Color(0.20, 0.18, 0.19))
	# One coherent Cuteskull family forms the portal-facing frontier defense.
	# Repeated authored modules are not stretched; the opening remains on the
	# main-road axis with a 12m+ clear troop staging approach behind it.
	for item in [
		{"node": "Castle_Wall", "x": -31.0, "z": -19.5, "yaw": 84.0,
			"name": "CuteskullWall_SouthWest"},
		{"node": "Castle_Wall", "x": -30.4, "z": -14.0, "yaw": 87.0,
			"name": "CuteskullWall_South"},
		{"node": "Castle_Wall", "x": -30.0, "z": -8.5, "yaw": 90.0,
			"name": "CuteskullWall_GateFlankSouth"},
		{"node": "Castle_Entrance", "x": -30.0, "z": -3.0, "yaw": 90.0,
			"name": "CuteskullMainGate"},
		{"node": "Castle_Wall", "x": -29.8, "z": 2.5, "yaw": 92.0,
			"name": "CuteskullWall_GateFlankNorth"},
		{"node": "Castle_Wall", "x": -29.4, "z": 8.0, "yaw": 94.0,
			"name": "CuteskullWall_North"},
		{"node": "Castle_Wall", "x": -28.8, "z": 13.5, "yaw": 96.0,
			"name": "CuteskullWall_NorthEast"},
	]:
		_spawn_cuteskull_fortification(item["node"],
			Vector3(item["x"], 0, item["z"]), item["yaw"], item["name"], 0.09)
	_spawn_cuteskull_fortification("Castle_Tower_3", Vector3(-31.6, 0, -24.0),
		84.0, "CuteskullTower_South", 0.068)
	_spawn_cuteskull_fortification("Castle_Tower_4", Vector3(-28.2, 0, 18.5),
		96.0, "CuteskullTower_North", 0.068)
	for z in [-18, -10, 10, 18]:
		_spawn_frontier_model("bld/fence_wooden_single", Vector3(-48, 0, z),
			90.0, 0.9)
	for pos in [Vector3(-55, 0, -13), Vector3(-61, 0, 12),
			Vector3(-71, 0, -15), Vector3(-79, 0, 13), Vector3(-94, 0, -12),
			Vector3(-99, 0, 14)]:
		_spawn_frontier_model("tree/dead_1", pos, 0.0, 0.55)
	for pos in [Vector3(-52, 0, 8), Vector3(-66, 0, -7), Vector3(-82, 0, 8),
			Vector3(-96, 0, -5)]:
		_spawn_frontier_model("rock/medium_2", pos, 0.0, 0.65)
	_spawn_portal(Vector3(-112, 0, 0))


func _spawn_ground_patch(node_name: String, pos: Vector3, radius: float,
		depth_scale: float, color: Color) -> void:
	var patch := MeshInstance3D.new()
	patch.name = node_name
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.UP])
	var uvs := PackedVector2Array([Vector2(0.5, 0.5)])
	var indices := PackedInt32Array()
	var edge_shape := [0.88, 1.04, 0.92, 1.10, 0.84, 1.02, 0.91,
		1.08, 0.86, 0.99, 0.90, 1.06, 0.87, 1.01]
	for i in edge_shape.size():
		var angle := TAU * float(i) / float(edge_shape.size())
		var edge_radius: float = radius * edge_shape[i]
		vertices.append(Vector3(cos(angle) * edge_radius, 0,
			sin(angle) * edge_radius * depth_scale))
		normals.append(Vector3.UP)
		uvs.append(Vector2(cos(angle), sin(angle)) * 0.5 + Vector2(0.5, 0.5))
	for i in edge_shape.size():
		indices.append(0)
		indices.append(i + 1)
		indices.append((i + 1) % edge_shape.size() + 1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	patch.mesh = mesh
	patch.position = Vector3(pos.x, 0.012, pos.z)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	patch.material_override = material
	add_child(patch)


func _spawn_frontier_model(key: String, pos: Vector3, yaw_deg: float,
		uniform_scale: float) -> void:
	var model := VisualAssetCatalog3D.instantiate_model(key)
	if model == null:
		push_error("VillageComposition3D: frontier model failed '%s'" % key)
		return
	model.position = WorldCoords3D.flatten(pos)
	model.rotation.y = deg_to_rad(yaw_deg)
	model.scale = Vector3.ONE * uniform_scale
	model.set_meta("catalog_key", key)
	model.set_meta("zone", "frontier")
	model.set_meta("kind", "visual_dressing")
	add_child(model)


func _spawn_cuteskull_fortification(source_node_name: String, pos: Vector3,
		yaw_deg: float, node_name: String, uniform_scale: float) -> Node3D:
	var source_root := CUTESKULL_CITY.instantiate()
	var source := source_root.get_node_or_null(
		"88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/" + source_node_name) as Node3D
	if source == null:
		push_error("VillageComposition3D: Cuteskull fortification node missing '%s'" % source_node_name)
		source_root.free()
		return null
	var model := source.duplicate() as Node3D
	model.name = node_name
	model.position = WorldCoords3D.flatten(pos)
	model.scale = Vector3.ONE * uniform_scale
	_normalize_cuteskull_model(model)
	_orient_cuteskull_model(model, yaw_deg)
	model.set_meta("asset_source", "Cuteskull city16.fbx")
	model.set_meta("source_node", source_node_name)
	model.set_meta("zone", "frontier")
	model.set_meta("kind", "visual_fortification")
	add_child(model)
	source_root.free()
	return model


func _make_fortification_materials_visible(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh := node.mesh.duplicate() as ArrayMesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface)
				if material is BaseMaterial3D:
					var local_material := material.duplicate() as BaseMaterial3D
					local_material.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh.surface_set_material(surface, local_material)
					node.material_override = local_material
			node.mesh = mesh
	for child in node.get_children():
		_make_fortification_materials_visible(child)


func _strip_fortification_colliders(node: Node) -> void:
	for child in node.get_children():
		if child is StaticBody3D or child is CollisionObject3D:
			child.free()
		else:
			_strip_fortification_colliders(child)


func _spawn_portal(pos: Vector3) -> void:
	var portal := MeshInstance3D.new()
	portal.name = "DistantPortal"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 3.0
	mesh.outer_radius = 4.0
	mesh.rings = 16
	mesh.ring_segments = 32
	portal.mesh = mesh
	portal.position = Vector3(pos.x, 0.35, pos.z)
	portal.rotation_degrees.x = 90.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.48, 0.08, 0.7)
	material.emission_enabled = true
	material.emission = Color(0.22, 0.02, 0.4)
	material.emission_energy_multiplier = 2.5
	portal.material_override = material
	add_child(portal)


## house_size_m: 4 또는 6(m). 문은 로컬 남쪽(+Z) 벽에 있고 yaw_deg로 방향을 돌린다.
func _add_house(root: Node3D, house_size_m: int, palette: Dictionary,
		pos: Vector3, yaw_deg: float, with_chimney: bool) -> Node3D:
	var house := Node3D.new()
	house.name = "House"
	root.add_child(house)
	house.position = WorldCoords3D.flatten(pos)
	house.rotation.y = deg_to_rad(yaw_deg)
	house.scale = Vector3.ONE * HOUSE_VISUAL_SCALE
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
	var roof := _attach_model(house, "bld/roof_roundtiles_6x6",
		Vector3(0, WALL_HEIGHT + ROOF_NATIVE_EAVE_DROP * roof_scale, 0),
		0.0, roof_scale)
	_apply_house_tone(roof, palette == HOUSE_BRICK)
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


func _add_cuteskull_house(root: Node3D, source_name: String,
		pos: Vector3, yaw_deg: float) -> Node3D:
	var source_root := CUTESKULL_CITY.instantiate()
	var source := source_root.get_node_or_null(
		"88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/" + source_name) as Node3D
	if source == null:
		source_root.free()
		push_error("VillageComposition3D: Cuteskull house missing '%s'" % source_name)
		return null
	var house := source.duplicate() as Node3D
	house.name = "Cuteskull_%s" % source_name
	house.position = WorldCoords3D.flatten(pos)
	house.scale = Vector3.ONE * 0.13
	_normalize_cuteskull_model(house)
	_orient_cuteskull_model(house, yaw_deg)
	house.set_meta("asset_source", "Cuteskull city16.fbx")
	house.set_meta("source_node", source_name)
	house.set_meta("catalog_key", "cuteskull/%s" % source_name)
	house.set_meta("kind", "house")
	_zone_roots["village"].add_child(house)
	_solids.append({
		"rect": Rect2(pos.x - 3.5, pos.z - 3.5, 7.0, 7.0),
		"key": "cuteskull/%s" % source_name,
		"zone": "village",
	})
	source_root.free()
	return house


func _spawn_cuteskull_prop(source_path: String, node_name: String,
		pos: Vector3, yaw_deg: float, uniform_scale: float) -> Node3D:
	var source_root := CUTESKULL_CITY.instantiate()
	var source := source_root.get_node_or_null(
		"88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/" + source_path) as Node3D
	if source == null:
		source_root.free()
		push_error("VillageComposition3D: Cuteskull prop missing '%s'" % source_path)
		return null
	var prop := source.duplicate() as Node3D
	prop.name = node_name
	prop.position = WorldCoords3D.flatten(pos)
	prop.scale = Vector3.ONE * uniform_scale
	_normalize_cuteskull_model(prop)
	_orient_cuteskull_model(prop, yaw_deg)
	prop.set_meta("asset_source", "Cuteskull city16.fbx")
	prop.set_meta("source_node", source_path)
	prop.set_meta("kind", "village_prop")
	_zone_roots["village"].add_child(prop)
	source_root.free()
	return prop


func _normalize_cuteskull_model(model: Node) -> void:
	for child in model.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var aabb := (child as MeshInstance3D).mesh.get_aabb()
			child.position = Vector3(-aabb.position.x - aabb.size.x * 0.5,
				-aabb.position.y - aabb.size.y * 0.5, -aabb.position.z)
			return


func _orient_cuteskull_model(model: Node3D, yaw_deg: float) -> void:
	# Cuteskull's source geometry is Z-up. Convert once at the extracted visual
	# root, then apply settlement yaw around Godot's Y-up axis.
	var authored_scale := model.scale
	model.basis = Basis(Vector3.UP, deg_to_rad(yaw_deg)) \
		* Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	model.scale = authored_scale


func _apply_house_tone(node: Node3D, brick: bool) -> void:
	if node == null:
		return
	var material := StandardMaterial3D.new()
	# Desaturated roof tones keep the settlement grounded as a frontier outpost.
	material.albedo_color = Color(0.28, 0.29, 0.29) if brick \
		else Color(0.33, 0.29, 0.25)
	material.roughness = 0.94
	_apply_house_tone_recursive(node, material)


func _apply_house_tone_recursive(node: Node, material: StandardMaterial3D) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).material_override = material
		_apply_house_tone_recursive(child, material)


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
	_spawn("veg/bush_common", "forest", "edge_transition", Vector3(-22.7, 0, -8.8))
	_spawn("veg/grass_common_short", "forest", "edge_transition", Vector3(-21.8, 0, -7.6))


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
	_spawn("veg/bush_common", "lumberyard", "edge_transition", Vector3(-19.8, 0, 5.2))
	_spawn("veg/grass_common_tall", "lumberyard", "edge_transition", Vector3(-20.2, 0, 13.4))


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
	_spawn("veg/grass_common_short", "quarry", "edge_transition", Vector3(17.0, 0, 20.8))
	_spawn("rock/medium_1", "quarry", "edge_transition", Vector3(19.0, 0, 21.0),
		-12.0, 0.55)


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
