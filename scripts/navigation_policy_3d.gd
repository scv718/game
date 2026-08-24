extends RefCounted
class_name NavigationPolicy3D

## TASK-3D-001-5 Navigation3D Convention / Foundation Lock (단일 소스).
## Worker/Combat/Building 병렬 태스크가 서로 다른 Navigation 방식을 만들지 않도록
## 최소 Navigation3D 규칙을 확정한다. 기존 2D world.gd / gate.gd / actor 규약과
## 1:1 대응되는 3D 기준점이며, 복잡한 동적 NavMesh 최적화는 의도적으로 제외한다.
##
## 구조:
##   - 이 클래스 = 정책/상수 단일 소스. 런타임 소유는 navigation_manager_3d.gd가 담당한다.
##   - NavigationRegion3D는 NavigationManager3D가 생성/보유하며, NavigationMesh는
##     월드 parse root의 static collider를 PARSED_GEOMETRY_STATIC_COLLIDERS로
##     파싱해 bake한 결과를 할당한다(기존 world.gd parse/bake 동등 API).
##   - Worker/Enemy/Mercenary는 NavigationAgent3D를 만든 뒤 configure_agent()만
##     호출하면 공통 policy가 적용된다. 각 도메인이 자체 agent 튜닝을 하지 않는다.
##
## 지면 XZ 이동 기준:
##   - 목적지/path는 모두 지면 좌표(Y = WorldCoords3D.GROUND_Y)만 사용한다.
##   - Actor node origin은 지면 접지점(Y = GROUND_Y)에 두고, 시각/충돌 볼륨은
##     자식 노드에서 위로 오프셋한다(Actor Origin LOCK). NavigationAgent3D의
##     desired_distance 전진/도달 판정이 navmesh 표면 높이와 정렬되어야
##     첫 waypoint가 스폰 위치와 겹쳐도 segment가 전진한다. origin을 공중에
##     띄우면 수직 거리 때문에 전진 판정이 영원히 실패해 velocity 0 고착이 발생한다.
##   - Actor velocity는 XZ 성분만 가진다(path_follow_velocity_xz / velocity_towards_xz).
##   - gameplay 거리 판정은 항상 WorldCoords3D.distance_xz / reached_xz.
##
## Static obstacle 반영 정책:
##   - bake 파싱 mask = BAKE_MASK = CollisionLayers3D.MASK_ACTOR_SOLID
##     (= GROUND 보행면 + BUILDING/WALL/GATE/RESOURCE 장애물).
##   - GROUND layer 지면 BoxShape의 윗면(Y=0)이 walkable surface가 되고,
##     Building/Wall/Gate/Resource static collider는 navmesh에 구멍으로 반영된다.
##   - Actor body(WORKER/MERCENARY/ENEMY layer)는 mask에 없으므로 절대
##     navmesh 장애물로 파싱되지 않는다.
##
## Runtime Building placement 이후 nav update 정책(방향 확정):
##   - 배치/철거/게이트 상태 전화 후에는 증분 업데이트가 아니라 "전체 rebake" 원칙.
##   - 연속 변경은 rebuild_navigation_debounced()(0.1s debounce, world.gd와 동일)로
##     coalesce한다. 동적 NavMesh region 병합/부분 업데이트 시스템은 만들지 않는다.
##   - 도메인 호출부는 NavigationPolicy3D.request_rebuild_debounced(get_tree()) 하나만
##     사용한다(기존 gate.gd _request_nav_rebuild 그룹 조회 계약의 3D판).
##
## Gate OPEN/CLOSED/BREACHED 표현 구조:
##   - passage CollisionShape3D 노드의 존재 여부가 곧 nav 장애물이다(2D gate.gd와
##     동일 계약). OPEN/BREACHED = shape 제거 → 통과 가능, CLOSED = shape 존재 → 차단.
##   - collision_layer(GATE bit) 토글이 아니라 shape 노드 add/remove로 표현한다.
##     bake가 disabled/collision_mask를 무시하고 shape를 항상 파싱하기 때문이다.
##   - 상태 전환 후 request_rebuild_debounced()로 rebake를 요청한다.
##
## Actor radius/height 기본 convention:
##   - radius = ACTOR_RADIUS_UNITS = 1.0 unit (기존 2D PARSE_AGENT_RADIUS 8px 동일,
##     PX_TO_UNIT 0.125 환산). physics capsule/circle과 무관한 nav 기준값이다.
##   - height = ACTOR_HEIGHT_UNITS = 2.0 unit (논리 grid cell 16px = 2 unit).
##
## unreachable target 처리 원칙(기존 영구 stall 방지 유지):
##   - judge_path_status()의 3값 판정이 모든 도메인의 단일 이동 종료 규약이다.
##     - ARRIVED: 목표에 도달(target_desired_distance 이내 + reachable).
##     - BLOCKED: is_navigation_finished() == true인데 목표 미도달. 즉 부분 경로가
##       장애물 앞에서 소진된 상태다. 이동을 포기하고 bounded하게 정지/skip한다.
##       부분 경로 종점은 장애물 접촉면 위에 있으므로, 여기서 계속 밀면 접점을
##       사이에 둔 좌우 진동이 생기고 displacement가 되풀이되어 stuck guard 타이머를
##       계속 리셋한다(영구 MOVE). 반드시 BLOCKED로 먼저 종료한다.
##   - stuck guard(STUCK_TIMEOUT 초 동안 STUCK_MOVE_EPSILON_UNITS 미만 displacement)는
##     BLOCKED가 못 잡는 예외 케이스의 2차 안전망으로 유지한다.
##   - 이동 없음 판정 감각: 기존 lumberjack/enemy _check_stuck과 동일
##     (2px epsilon -> 0.25 unit 비율 보존).
##   - 도메인 FSM은 ARRIVED/BLOCKED 후 기존 규약대로 다음 목표 탐색/IDLE 복귀 등
##     bounded 동작으로 전환해야 하며, 재시도 무한루프를 만들지 않는다.

enum PathStatus {
	MOVING,
	ARRIVED,
	BLOCKED,
}


## 공통 이동 판정. Worker/Enemy/Mercenary FSM과 테스트 프로브가 모두 이 함수로
## 이동 지속/도착/포기를 결정한다(단일 종료 규약).
static func judge_path_status(agent: NavigationAgent3D, body_pos: Vector3,
		target_pos: Vector3) -> int:
	var within_reach := WorldCoords3D.distance_xz(body_pos, target_pos) \
		<= TARGET_DESIRED_DISTANCE_UNITS
	if within_reach and agent.is_target_reachable():
		return PathStatus.ARRIVED
	if agent.is_navigation_finished():
		return PathStatus.BLOCKED
	return PathStatus.MOVING

const SERVICE_GROUP := "navigation_3d"

## bake에서 장애물/보행면으로 파싱할 collision mask 단일 소스.
## MASK_ACTOR_SOLID = GROUND | BUILDING | WALL | GATE | RESOURCE.
const BAKE_MASK := CollisionLayers3D.MASK_ACTOR_SOLID

## 기존 2D world.gd PARSE_AGENT_RADIUS(8px)와 동일 값을 unit로 환산한 nav radius.
const ACTOR_RADIUS_PX := 8.0
const ACTOR_RADIUS_UNITS := ACTOR_RADIUS_PX * WorldCoords3D.PX_TO_UNIT

## 논리 grid cell 1칸(16px) = 2 unit 높이. nav clearance 기본값.
const ACTOR_HEIGHT_UNITS := 2.0

## NavMesh raster 해상도: 1 nav cell = 1 논리 px(PX_TO_UNIT).
## 기본값(cell 0.25)보다 촘촘해 2 unit 폭 Wall/Gate carve가 정확하고,
## walkable 표면이 지면(Y=GROUND_Y)에 cell 1개 이내로 붙는다. 표면이
## path_desired_distance(0.5) 이상 뜨면 agent의 waypoint 전진 판정이
## 수직 거리 때문에 실패해 이동 고착이 발생하므로 이 해상도가 요구된다.
const NAV_CELL_SIZE_UNITS := WorldCoords3D.PX_TO_UNIT
const NAV_CELL_HEIGHT_UNITS := WorldCoords3D.PX_TO_UNIT

## 기존 lumberjack.tscn/miner.tscn NavigationAgent2D 튜닝(4px)의 unit 환산값.
const PATH_DESIRED_DISTANCE_UNITS := 4.0 * WorldCoords3D.PX_TO_UNIT
const TARGET_DESIRED_DISTANCE_UNITS := 4.0 * WorldCoords3D.PX_TO_UNIT

## 기존 lumberjack STUCK_TIMEOUT(1.5s) / 2px epsilon의 비율 보존값.
const STUCK_TIMEOUT := 1.5
const STUCK_MOVE_EPSILON_PX := 2.0
const STUCK_MOVE_EPSILON_UNITS := STUCK_MOVE_EPSILON_PX * WorldCoords3D.PX_TO_UNIT


## Worker/Enemy/Mercenary가 공통으로 적용하는 NavigationAgent3D 기본 설정.
## avoidance는 기존 2D와 동일하게 끈다(actor끼리 밀어내지 않음).
static func configure_agent(agent: NavigationAgent3D) -> void:
	agent.radius = ACTOR_RADIUS_UNITS
	agent.height = ACTOR_HEIGHT_UNITS
	agent.path_desired_distance = PATH_DESIRED_DISTANCE_UNITS
	agent.target_desired_distance = TARGET_DESIRED_DISTANCE_UNITS
	agent.avoidance_enabled = false


## 지면 XZ 방향 속도. Y 성분은 항상 0(자유 높이 이동 금지).
static func velocity_towards_xz(from: Vector3, to: Vector3, max_speed: float) -> Vector3:
	var direction := to - from
	direction.y = 0.0
	if direction.length_squared() <= 0.0000001:
		return Vector3.ZERO
	return direction.normalized() * max_speed


## Worker/Enemy/Mercenary가 공통으로 사용하는 지면 path 추적 step(단일 이동 패턴).
## get_next_path_position() 결과를 반드시 지면 투영해 방향을 계산하므로,
## navmesh 표면이 ground Y보다 살짝 위에 있어도 desired_distance 전진 판정이
## Y 오프셋으로 오염되지 않는다. 첫 waypoint == 현재 위치로 direction이 0이면
## 정지 velocity를 반환하고 다음 physics frame의 agent segment 전진에 맡긴다
## (Actor Origin LOCK 하에서는 1 frame 내 전진이 보장되어 영구 고착이 없다).
static func path_follow_velocity_xz(from: Vector3, agent: NavigationAgent3D, max_speed: float) -> Vector3:
	var next := WorldCoords3D.flatten(agent.get_next_path_position())
	return velocity_towards_xz(WorldCoords3D.flatten(from), next, max_speed)


## gameplay 도달 판정은 항상 XZ 평면 거리로 한다(2D distance 의미 보존).
static func reached_xz(pos: Vector3, target: Vector3, tolerance_units: float) -> bool:
	return WorldCoords3D.distance_xz(pos, target) <= tolerance_units


## 도메인(gate/building/resource 전환 태스크)이 nav rebake를 요청하는 유입구.
## navigation_3d 그룹의 NavigationManager3D에 debounced rebuild를 위임하고,
## 매니저 부재 시 false를 반환해 안전 no-op이 된다.
static func request_rebuild_debounced(tree: SceneTree) -> bool:
	if tree == null:
		return false
	var manager := tree.get_first_node_in_group(SERVICE_GROUP)
	if manager != null and manager.has_method("rebuild_navigation_debounced"):
		manager.rebuild_navigation_debounced()
		return true
	return false
