extends Node3D
class_name NavigationManager3D

## TASK-3D-001-5 Navigation3D 런타임 소유 노드.
## 기존 world.gd(Node2D + NavigationRegion2D + rebuild API)의 3D판 최소 구조다.
## NavigationPolicy3D가 규칙 단일 소스, 이 노드가 NavigationRegion3D/bake 실행 소유.
##
## - NavigationRegion3D를 자식으로 직접 생성하므로 scene 수정 없이
##   World3D Root(또는 테스트 런타임)에 add_child만으로 연결된다.
## - bake: parse root 하위의 static collider를 PARSED_GEOMETRY_STATIC_COLLIDERS로
##   파싱해 NavigationMesh를 만들고 region에 할당한다. mask/agent 치수는
##   NavigationPolicy3D 단일 소스만 사용한다.
## - rebuild API는 world.gd와 동등한 시그니처(rebuild_navigation,
##   rebuild_navigation_debounced)로 확정했다. BLD/RES 도메인 전환 태스크는
##   기존 world.rebuild_navigation 호출부를 이 매니저(그룹 navigation_3d)로 교체한다.
## - bake는 동기(synchronous) 수행한다. 현재 Godot 버전에서 안정적인 최소 구조 우선이며
##   비동기 bake/동적 navmesh 부분 갱신은 선행 구현하지 않는다(001-5 중요 항목).
## - region 할당 후 실제 map 반영은 다음 physics sync 때 일어나므로,
##   rebuild 직후 path query는 최소 1 physics frame 대기 후 수행한다.
## - group "navigation_3d"는 NavigationPolicy3D.request_rebuild_debounced 유입구다.

signal navigation_baked

## 기존 world.gd debounce 간격과 동일값.
const DEBOUNCE_INTERVAL := 0.1

## is_target_reachable 종점 일치 허용 오차. 도달 가능 경로의 마지막 점은
## 요청 target 그 자체(거리 0)이므로 소수 오차만 흡수하면 충분하고,
## unreachable 부분 경로는 장애물 직전 최근점에서 끝나므로 이 값보다 크게 어긋난다.
const REACHABLE_END_TOLERANCE_UNITS := 0.5

var nav_rebuild_count := 0

var _region: NavigationRegion3D = null
var _parse_root_override: Node = null
var _rebuild_pending := false
var _rebuild_timer: SceneTreeTimer = null


func _ready() -> void:
	add_to_group(NavigationPolicy3D.SERVICE_GROUP)
	_region = NavigationRegion3D.new()
	_region.name = "NavigationRegion"
	add_child(_region)
	# map raster도 navmesh와 동일 해상도로 맞춘다(불일치 시 런타임 경고 + edge 오차).
	var map := _region.get_navigation_map()
	NavigationServer3D.map_set_cell_size(map, NavigationPolicy3D.NAV_CELL_SIZE_UNITS)
	NavigationServer3D.map_set_cell_height(map, NavigationPolicy3D.NAV_CELL_HEIGHT_UNITS)
	rebuild_navigation()


func set_parse_root(node: Node) -> void:
	_parse_root_override = node


func get_nav_region() -> NavigationRegion3D:
	return _region


func get_navigation_map() -> RID:
	return _region.get_navigation_map()


## from -> to 지면 경로 존재 여부.
## 주의: NavigationServer3D.map_get_path는 to가 도달 불가여도 비어 있지 않은
## "부분 경로"(to의 최근 도달점까지)를 반환한다. 따라서 path.size()만으로는
## 판정할 수 없고, 마지막 점이 요청 target과 일치할 때만 reachable로 본다.
## (영구 stall 방지 원칙상 도달 불가 판정은 이동 시작 전에도 질의 가능해야 한다.)
func is_target_reachable(from: Vector3, to: Vector3) -> bool:
	if _region == null or not _region.is_inside_tree():
		return false
	var path := NavigationServer3D.map_get_path(get_navigation_map(), from, to, true)
	if path.is_empty():
		return false
	return path[path.size() - 1].distance_to(to) <= REACHABLE_END_TOLERANCE_UNITS


## 기존 world.gd.rebuild_navigation_debounced와 동일 규약.
## 연속 요청을 DEBOUNCE_INTERVAL 안에서 1회 rebake로 coalesce한다.
func rebuild_navigation_debounced() -> void:
	if not is_inside_tree():
		return
	_rebuild_pending = true
	if _rebuild_timer != null:
		return
	_rebuild_timer = get_tree().create_timer(DEBOUNCE_INTERVAL)
	_rebuild_timer.timeout.connect(_flush_nav_rebuild)


func _flush_nav_rebuild() -> void:
	_rebuild_timer = null
	if not is_inside_tree() or not _rebuild_pending:
		return
	_rebuild_pending = false
	rebuild_navigation()


## 동기 parse + bake + region 할당. 성공 시 counter 증가 + navigation_baked emit.
func rebuild_navigation() -> void:
	var root_node := _resolve_parse_root()
	if root_node == null or not root_node.is_inside_tree():
		return
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = NavigationPolicy3D.BAKE_MASK
	nav_mesh.agent_radius = NavigationPolicy3D.ACTOR_RADIUS_UNITS
	nav_mesh.agent_height = NavigationPolicy3D.ACTOR_HEIGHT_UNITS
	nav_mesh.cell_size = NavigationPolicy3D.NAV_CELL_SIZE_UNITS
	nav_mesh.cell_height = NavigationPolicy3D.NAV_CELL_HEIGHT_UNITS
	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_geometry, root_node)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geometry)
	_region.navigation_mesh = nav_mesh
	nav_rebuild_count += 1
	navigation_baked.emit()


## bake 대상 subtree. 명시 지정 > parent(World Root에 붙였을 때 기본) > self.
func _resolve_parse_root() -> Node:
	if _parse_root_override != null and is_instance_valid(_parse_root_override):
		return _parse_root_override
	var parent := get_parent()
	return parent if parent != null else self
