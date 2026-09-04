extends Node
class_name GhostSpawner3D

## TASK-017-2 Subsequent NIGHT Ghost Spawn.
## GhostReturn(autoload)의 eligible(미소모) GhostReturnCandidate를 NIGHT 시작에
## 기존 Portal/Spawn marker convention으로 3D GhostActor3D로 1회 spawn하고, spawn
## 성공 시 해당 candidate를 consume한다. DAY 복귀 시 spawn한 Ghost를 전부 despawn한다.
##
## - 기존 enemy spawn convention 재사용: Portal/Spawn marker(WorldMap.SPAWN_CANDIDATES /
##   MapLayout SpawnCandidate)와 village core/접근 경로 해석을 FirstEncounterSpawner3D와
##   동일하게 적용한다. 새로운 rarity/gacha/candidate 생성 알고리즘은 만들지 않는다.
## - candidate consume은 spawn 성공에만 연결한다(spawn 실패 시 candidate는 미소모로
##   유지되어 다음 유효 NIGHT에 재시도 = failed spawn recovery).
## - duplicate spawn 방지: candidate는 consume()로 정확히 1회만 spawn되며, 이미 소모된
##   candidate는 GhostReturn eligible 목록에 없다(1회 return 불변식).
## - Ghost death는 is_ghost=true record이므로 새 GhostReturnCandidate를 만들지 않아
##   무한 chain을 방지한다(DeathLedger guard).
## - Player는 절대 target이 되지 않는다(EnemyActor3D 계약 유지).

const GHOST_SCENE := "res://scenes/ghost_3d.tscn"

const DEFAULT_DIRECTION := "west"

const DIRECTIONS := ["north", "south", "east", "west"]

## 마을 안쪽(중심 방향) 단위 벡터. FirstEncounterSpawner3D와 동일한 XZ 해석
## (logical x,y) -> (world x,z)를 사용한다(spawn 지점보다 안쪽 waypoint 선별용).
const DIRECTION_AXIS_XZ := {
	"north": Vector3(0.0, 0.0, 1.0),
	"south": Vector3(0.0, 0.0, -1.0),
	"east": Vector3(-1.0, 0.0, 0.0),
	"west": Vector3(1.0, 0.0, 0.0),
}

var direction := DEFAULT_DIRECTION

var _night_active := false
var _ghosts: Array[Node] = []

signal ghost_spawned(ghost: Node, record_id: String)
signal ghost_despawned(ghost: Node)


func _ready() -> void:
	GameTime.phase_changed.connect(_on_phase_changed)


## NIGHT 시작 시 eligible candidate를 Ghost로 spawn, DAY 복귀 시 전부 despawn.
func _on_phase_changed(phase: int, _day_number: int) -> void:
	if phase == GameTime.Phase.NIGHT:
		spawn_ghosts()
	else:
		despawn_ghosts()


func set_direction(value: String) -> void:
	if value in DIRECTIONS:
		direction = value


func get_direction() -> String:
	return direction


## NIGHT에서만 동작하며 이미 이번 NIGHT에 spawn했으면(또는 DAY면) 아무것도 하지 않아
## DAY 오작동 spawn / 반복 NIGHT duplicate를 방지한다.
## 각 eligible candidate에 대해 spawn을 시도하고, 성공 시에만 consume한다.
func spawn_ghosts() -> int:
	if GameTime.get_phase() != GameTime.Phase.NIGHT:
		return 0
	if _night_active:
		return 0
	var world := get_tree().get_first_node_in_group("world3d")
	if world == null or not is_instance_valid(world):
		return 0
	var scene: PackedScene = load(GHOST_SCENE)
	if scene == null:
		return 0
	var ghost_return: Node = get_node_or_null("/root/GhostReturn")
	if ghost_return == null:
		return 0
	var spawn_world_point := get_spawn_world_point(direction, world)
	var waypoints := build_route_waypoints(direction, spawn_world_point, world)
	var core := get_village_core(world)
	var spawned := 0
	var offset_index := 0
	for cand: GhostReturnCandidate in ghost_return.get_eligible_candidates():
		var ghost := _try_spawn(scene, world, cand, spawn_world_point, waypoints, core, offset_index)
		if ghost == null:
			continue
		# spawn 성공 시에만 1회 consume(실패 시 candidate는 미소모 유지 = recovery).
		ghost_return.consume(cand.record_id)
		_ghosts.append(ghost)
		ghost.died.connect(_on_ghost_died)
		ghost_spawned.emit(ghost, cand.record_id)
		spawned += 1
		offset_index += 1
	_night_active = true
	return spawned


## 단일 candidate로 GhostActor3D 인스턴스를 구성하고 world에 배치한다. 구성/배치 중
## 어떤 단계라도 실패하면 null을 반환해 candidate가 소모되지 않게 한다(멱등 no-op).
func _try_spawn(scene: PackedScene, world: Node, cand: GhostReturnCandidate,
		spawn_point: Vector3, waypoints: Array, core: Vector3, offset_index: int) -> GhostActor3D:
	var ghost := scene.instantiate() as GhostActor3D
	if ghost == null:
		return null
	var ghost_uid := "ghost_%s" % cand.record_id
	ghost.setup_ghost(ghost_uid, "Ghost of %s" % cand.display_name, direction, cand)
	ghost.position = spawn_point + _spawn_offset(offset_index)
	world.add_child(ghost)
	if not ghost.is_in_group("enemies_3d"):
		ghost.add_to_group("enemies_3d")
	ghost.set_route(waypoints, core)
	return ghost


## DAY 복귀 시 spawn한 Ghost를 전부 despawn한다. queue_free 직접 호출이므로
## DeathRecord를 만들지 않는다(cleanup record 없음). 반복 호출은 멱등.
func despawn_ghosts() -> int:
	var removed := 0
	for g in _ghosts:
		if is_instance_valid(g):
			g.queue_free()
			ghost_despawned.emit(g)
			removed += 1
	_ghosts.clear()
	_night_active = false
	return removed


## 전투로 사망한 Ghost를 추적에서 즉시 제거한다(died signal 동기 호출).
func _on_ghost_died(ghost: Node) -> void:
	_ghosts.erase(ghost)


## 현재 살아 있는 Ghost 수.
func get_ghost_count() -> int:
	var n := 0
	for g in _ghosts:
		var ghost := g as GhostActor3D
		if ghost != null and is_instance_valid(ghost) and ghost.alive:
			n += 1
	return n


func get_ghosts() -> Array[Node]:
	var out: Array[Node] = []
	for g in _ghosts:
		if is_instance_valid(g):
			out.append(g)
	return out


func is_night_active() -> bool:
	return _night_active


## Portal/Spawn marker의 world XZ 좌표. MapLayout SpawnCandidate를 우선하고, 없으면
## WorldMap.SPAWN_CANDIDATES 상수를 XZ 해석한다(FirstEncounterSpawner3D와 동일).
func get_spawn_world_point(dir: String, world: Node) -> Vector3:
	var layout := world.get_node_or_null("MapLayout")
	if layout != null and layout.has_method("get_spawn_candidate"):
		return WorldCoords3D.to_world_xz(layout.get_spawn_candidate(dir))
	return WorldCoords3D.to_world_xz(
		WorldMap.SPAWN_CANDIDATES.get(dir, WorldMap.SETTLEMENT_CENTER))


## Main Road waypoint(world XZ) 중 spawn 지점보다 마을 쪽에 있는 지점만 선택해
## 접근 경로를 만든다(FirstEncounterSpawner3D와 동일 계약).
func build_route_waypoints(dir: String, start: Vector3, world: Node) -> Array[Vector3]:
	var waypoints: Array[Vector3] = []
	var road_points := get_main_road_points(dir, world)
	if road_points.is_empty():
		return waypoints
	road_points.reverse()
	var axis: Vector3 = DIRECTION_AXIS_XZ.get(dir, Vector3.ZERO)
	for v in road_points:
		if (v - start).dot(axis) > 0.0:
			waypoints.append(v)
	return waypoints


func get_main_road_points(dir: String, world: Node) -> PackedVector3Array:
	var layout := world.get_node_or_null("MapLayout")
	if layout != null and layout.has_method("get_main_road"):
		return WorldCoords3D.polyline_to_world(layout.get_main_road(dir))
	if WorldMap.MAIN_ROADS.has(dir):
		return WorldCoords3D.polyline_to_world(WorldMap.MAIN_ROADS[dir])
	return PackedVector3Array()


## village core(거점/정착지 중심) 목표 world XZ 좌표. Keep/clearing 중심 순으로
## 해석한다(FirstEncounterSpawner3D와 동일 fallback).
func get_village_core(world: Node) -> Vector3:
	var keep := world.get_node_or_null("Keep") as Node3D
	if keep != null:
		return WorldCoords3D.flatten(keep.global_position)
	var layout := world.get_node_or_null("MapLayout")
	if layout != null and layout.has_method("get_clearing_rect"):
		return WorldCoords3D.to_world_xz(layout.get_clearing_rect().get_center())
	return WorldCoords3D.to_world_xz(WorldMap.SETTLEMENT_CENTER)


## 같은 지점에 겹쳐 spawn되지 않도록 결정적 소량 offset(XZ 평면, Y 고정).
func _spawn_offset(i: int) -> Vector3:
	var col := i % 3 - 1
	var row := i / 3
	return Vector3(
		col * WorldCoords3D.GRID_CELL_UNITS, 0.0, row * WorldCoords3D.GRID_CELL_UNITS)
