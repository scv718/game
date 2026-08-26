extends Node3D
class_name MapLayout3D

## TASK-3D-INT-001-2 3D Main World MapLayout.
## 기존 world.tscn의 MapLayout(world_map.gd + Marker2D 35종)을 3D Runtime용으로
## 연결하는 신규 파일이다. 기존 2D world.tscn / world_map.gd는 LOCK 12에 따라 무수정.
##
## - CMB 도메인(roster/spawner)이 이미 약속한 조회 계약을 그대로 충족한다:
##   world3d 루트의 직접 자식 "MapLayout"이 아래 메서드를 제공하면
##   FirstEncounterSpawner3D / MercenaryRoster3D가 WorldMap 상수 fallback보다
##   우선 조회한다(INTEGRATION_NOTE_CMB "MapLayout/Keep 노드를 나중에 붙여도
##   roster/spawner가 우선 조회한다" 계약).
## - 반환값은 전부 기존 logical 좌표계(Vector2/Rect2/폴리라인 Array)다. XZ 해석은
##   호출자가 WorldCoords3D 단일 소스로 수행한다(좌표 변환 책임 분리 유지).
## - 데이터는 전부 WorldMap 상수의 읽기 전용 alias다(migration map 운영 규칙 2).
##   새로운 값을 정의하지 않으므로 2D/3D layout drift가 구조적으로 없다.
## - const alias는 world_map_overlay.gd의 landmark drawing(_world_map.get("상수"))
##   소비 계약도 동시에 충족한다(Object.get()으로 script const 조회 가능 확인).
## - Marker3D 자식들은 2D world.tscn MapLayout marker와 동일 이름/논리 좌표를
##   XZ 변환해 가진 anchor다. 런타임 로직은 상수 메서드를 우선 사용하며, marker는
##   roster의 RallySpace_<DIR> marker fallback 경로(Node3D cast)와 에디터/디버그
##   식별용으로 유지한다.

const SETTLEMENT_CENTER := WorldMap.SETTLEMENT_CENTER
const CLEARING_HALF := WorldMap.CLEARING_HALF
const GATE_ANCHORS := WorldMap.GATE_ANCHORS
const SPAWN_CANDIDATES := WorldMap.SPAWN_CANDIDATES
const APPROACH_ROUTES := WorldMap.APPROACH_ROUTES
const MAIN_ROADS := WorldMap.MAIN_ROADS
const FOREST_CLUSTERS := WorldMap.FOREST_CLUSTERS
const STARTER_TREES := WorldMap.STARTER_TREES
const STONE_ZONE := WorldMap.STONE_ZONE
const SOUTH_AGRICULTURE_ZONE := WorldMap.SOUTH_AGRICULTURE_ZONE
const NE_DUNGEON_CANDIDATE := WorldMap.NE_DUNGEON_CANDIDATE


func get_spawn_candidates() -> Dictionary:
	return SPAWN_CANDIDATES


func get_spawn_candidate(direction: String) -> Vector2:
	return SPAWN_CANDIDATES.get(direction, SETTLEMENT_CENTER)


func get_main_road(direction: String) -> Array:
	return MAIN_ROADS.get(direction, [])


func get_clearing_rect() -> Rect2:
	return Rect2(SETTLEMENT_CENTER - CLEARING_HALF, CLEARING_HALF * 2.0)


func get_rally_space(direction: String) -> Rect2:
	return WorldMap.RALLY_SPACES.get(direction, Rect2())


func get_gate_anchor(direction: String) -> Vector2:
	return GATE_ANCHORS.get(direction, SETTLEMENT_CENTER)
