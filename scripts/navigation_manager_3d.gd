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
##
## TASK-3D-INT-002-2 성능 병목 최소 개선(측정 기록: tests/task3dint0022_test.gd
## 헤더와 test_results/task3dint0022_perf_report.txt):
##   - 실측 결과 이 월드(±192 unit, nav cell 0.125)의 동기 bake 1회가 약 3.9초로,
##     Tree 고갈/regrow마다 debounced rebake가 메인 스레드를 수 초간 막아
##     게임플레이가 명백히 불가능한 수준이었다. cell 해상도는 Foundation LOCK
##     (표면 정렬 요건)이라 완화할 수 없으므로, 런타임 churn 경로의 raster bake만
##     워커 스레드로 옮기는 것이 최소 개선이다.
##   - rebuild_navigation()은 동기 계약을 그대로 유지한다(테스트/초기 bake가
##     결정적 map 신선도를 요구). rebuild_navigation_async()는 parse를 동기으로
##     스냅샷한 뒤 bake만 비동기로 수행하고, 완료 콜백에서 region에 할당한다.
##   - rebuild_navigation_debounced() 유입구(트리 depletion/regrow, gate 상태,
##     placement 등 runtime churn)는 async 경로를 사용한다. 즉 debounce 경로의
##     nav 갱신은 eventually-consistent가 된다(지연 상한 = bake 소요 시간).
##     동기 경로와의 순서 보호를 위해 발행 단위 generation을 부여하고, 콜백 시점에
##     최신 발행이 아니면 폐기한다(오래된 스냅샷이 새 map을 덮어쓰지 않음).
##   - nav_rebuild_count는 "발행된 rebake 수" 의미로 두 계약 모두 발행 시 증가한다.

signal navigation_baked

## 기존 world.gd debounce 간격과 동일값.
const DEBOUNCE_INTERVAL := 0.1

## is_target_reachable 종점 일치 허용 오차. 도달 가능 경로의 마지막 점은
## 요청 target 그 자체(거리 0)이므로 소수 오차만 흡수하면 충분하고,
## unreachable 부분 경로는 장애물 직전 최근점에서 끝나므로 이 값보다 크게 어긋난다.
const REACHABLE_END_TOLERANCE_UNITS := 0.5

var nav_rebuild_count := 0

## 마지막으로 발행된 rebake 세대. 완료 순서가 뒤바킨 비동기 결과가 최신 map을
## 덮어쓰지 않도록 하는 단조 카운터다(동기/비동기 발행 모두 증가).
var _bake_generation := 0

## 비동기 bake 진행 중 플래그. bake가 워커 스레드에서 수 초~수백 ms 걸리는 동안
## 요청이 몰려도 대기 열이 쌓이지 않도록 동시 발행을 1건으로 제한한다
## (TASK-3D-INT-002-2: 완료 시 region 재할당 비용이 커서 대기열 전부가
## 프레임 히치로 연속 착지하는 것을 구조적으로 방지).
var _async_bake_active := false
## 진행 중인 bake가 있어 발행을 건너뛴 경우 완료 후 1회 재발행 플래그.
var _async_bake_respin := false

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
## flush는 비동기 bake 경로를 사용한다(위 병목 개선 참고).
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
	rebuild_navigation_async()


## 동기 parse + bake + region 할당. 성공 시 counter 증가 + navigation_baked emit.
func rebuild_navigation() -> void:
	var root_node := _resolve_parse_root()
	if root_node == null or not root_node.is_inside_tree():
		return
	var nav_mesh := _make_nav_mesh()
	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_geometry, root_node)
	_bake_generation += 1
	nav_rebuild_count += 1
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geometry)
	_region.navigation_mesh = nav_mesh
	navigation_baked.emit()


## 런타임 churn용 비동기 rebuild. parse는 동기로 최신 정적 collider 스냅샷을 만들고,
## 비용이 큰 raster bake만 워커 스레드에서 수행한다(메인 프레임 비차단).
## counter는 발행 시 증가하고, 완료 콜백에서 region 할당 + navigation_baked emit.
## 완료 시점에 세대가 최신이 아니면(그 사이 더 새로운 발행) 결과를 폐기한다.
## bake 진행 중 재요청은 큐에 쌓지 않고 완료 후 최신 상태로 1회 재발행한다
## (연속 착지 히치 방지 - eventually-consistent 유지).
func rebuild_navigation_async() -> void:
	if not is_inside_tree():
		return
	if _async_bake_active:
		_async_bake_respin = true
		return
	var root_node := _resolve_parse_root()
	if root_node == null or not root_node.is_inside_tree():
		return
	var nav_mesh := _make_nav_mesh()
	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_geometry, root_node)
	_bake_generation += 1
	nav_rebuild_count += 1
	_async_bake_active = true
	NavigationServer3D.bake_from_source_geometry_data_async(
		nav_mesh, source_geometry, _on_async_bake_finished.bind(
			nav_mesh, _bake_generation))


func _on_async_bake_finished(nav_mesh: NavigationMesh, generation: int) -> void:
	_async_bake_active = false
	if generation == _bake_generation and is_inside_tree() \
			and _region != null and is_instance_valid(_region):
		_region.navigation_mesh = nav_mesh
		navigation_baked.emit()
	if _async_bake_respin:
		_async_bake_respin = false
		rebuild_navigation_async()


## NavigationMesh 공통 설정(policy 단일 소스 소비). 동기/비동기 경로 공유.
func _make_nav_mesh() -> NavigationMesh:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = NavigationPolicy3D.BAKE_MASK
	nav_mesh.agent_radius = NavigationPolicy3D.ACTOR_RADIUS_UNITS
	nav_mesh.agent_height = NavigationPolicy3D.ACTOR_HEIGHT_UNITS
	nav_mesh.cell_size = NavigationPolicy3D.NAV_CELL_SIZE_UNITS
	nav_mesh.cell_height = NavigationPolicy3D.NAV_CELL_HEIGHT_UNITS
	return nav_mesh


## bake 대상 subtree. 명시 지정 > parent(World Root에 붙였을 때 기본) > self.
func _resolve_parse_root() -> Node:
	if _parse_root_override != null and is_instance_valid(_parse_root_override):
		return _parse_root_override
	var parent := get_parent()
	return parent if parent != null else self
