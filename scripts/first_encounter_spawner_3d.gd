extends Node
class_name FirstEncounterSpawner3D

## TASK-3D-CMB-001-2 Tactical Command World3D Wiring - 첫 NIGHT 조우 Spawner 3D.
## 기존 first_encounter_spawner.gd(Node autoload)의 spawn/despawn 계약을 3D Runtime용으로
## 이전한 신규 파일이다. 기존 2D first_encounter_spawner.gd는 LOCK 12에 따라 무수정으로
## 유지되며 이 파일이 대신하는 것은 3D World의 EnemyActor3D spawn뿐이다.
##
## - NIGHT 시작 시 한 방향(SpawnCandidate)에서 configurable 수량의 일반 근접
##   EnemyActor3D를 world XZ 좌표에 spawn하고, DAY 복귀 시 전부 despawn한다.
## - SpawnCandidate/Approach Route/Main Road/village core는 전부 WorldMap logical
##   상수(읽기 전용 참조)를 WorldCoords3D.to_world_xz / polyline_to_world로 XZ 해석한다.
##   MapLayout/Keep이 3D 월드에 wiring되어 있으면 그것을 우선한다(INT 대비).
## - 같은 NIGHT에 중복 spawn/반복 NIGHT duplicate 없음(2D 계약 동일).
## - 사망한 Enemy는 died signal로 추적에서 즉시 제거해 freed reference가
##   반복 NIGHT cycle에 남지 않는다.

const ENEMY_SCENE := "res://scenes/enemy_3d.tscn"

const DEFAULT_DIRECTION := "west"
const DEFAULT_COUNT := 3

const DIRECTIONS := ["north", "west"]

## 마을 안쪽(중심 방향) 단위 벡터. 기존 2D DIRECTION_AXIS(logical Vector2)와 동일한
## 해석을 WorldCoords3D 관계(x, y) -> (x, z)로 옮긴 표다(spawn 지점보다 안쪽
## waypoint 선별에 사용).
const DIRECTION_AXIS_XZ := {
	"north": Vector3(0.0, 0.0, 1.0),
	"south": Vector3(0.0, 0.0, -1.0),
	"east": Vector3(-1.0, 0.0, 0.0),
	"west": Vector3(1.0, 0.0, 0.0),
}

var direction := DEFAULT_DIRECTION
var count := DEFAULT_COUNT

var _night_active := false
var _enemies: Array[Node] = []

signal encounter_changed(direction: String, count: int)


func _ready() -> void:
	GameTime.phase_changed.connect(_on_phase_changed)


## NIGHT 시작 시 spawn, DAY 복귀 시 despawn.
func _on_phase_changed(phase: int, _day_number: int) -> void:
	if phase == GameTime.Phase.NIGHT:
		spawn_encounter()
	else:
		despawn_encounter()


func set_direction(value: String) -> void:
	if value in DIRECTIONS and value != direction:
		direction = value
		encounter_changed.emit(direction, count)


func get_direction() -> String:
	return direction


func set_count(value: int) -> void:
	var v := maxi(1, value)
	if v != count:
		count = v
		encounter_changed.emit(direction, count)


func get_count() -> int:
	return count


## NIGHT spawn. 이미 이번 NIGHT에 spawn했으면(또는 DAY면) 아무것도 하지 않아
## DAY 오작동 spawn / 반복 NIGHT duplicate를 방지한다(2D 계약 동일).
func spawn_encounter() -> int:
	if GameTime.get_phase() != GameTime.Phase.NIGHT:
		return 0
	if _night_active:
		return 0
	var world := get_tree().get_first_node_in_group("world3d")
	if world == null or not is_instance_valid(world):
		return 0
	var scene: PackedScene = load(ENEMY_SCENE)
	if scene == null:
		return 0
	var spawn_world_point := get_spawn_world_point(direction, world)
	var waypoints := build_route_waypoints(direction, spawn_world_point, world)
	var core := get_village_core(world)
	var spawned := 0
	for i in count:
		var enemy := scene.instantiate() as EnemyActor3D
		if enemy == null:
			continue
		enemy.setup("enemy_%s_%d" % [direction, i], "Raider", direction)
		enemy.position = spawn_world_point + _spawn_offset(i)
		world.add_child(enemy)
		enemy.set_route(waypoints, core)
		# 전투로 사망한 Enemy를 _enemies에서 즉시 제거해 이전 Enemy reference 누수가
		# 반복 NIGHT cycle에 남지 않게 한다(2D 계약 동일).
		enemy.died.connect(_on_enemy_died)
		_enemies.append(enemy)
		spawned += 1
	_night_active = true
	return spawned


## DAY 복귀 시 spawn한 Enemy를 전부 despawn한다. queue_free 직접 호출이므로
## DeathRecord를 만들지 않는다. 반복 호출은 멱등.
func despawn_encounter() -> int:
	var removed := 0
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
			removed += 1
	_enemies.clear()
	_night_active = false
	return removed


## 전투로 사망한 Enemy를 _enemies 추적에서 제거한다(died signal 동기 호출).
func _on_enemy_died(enemy: Node) -> void:
	_enemies.erase(enemy)


## 현재 spawn된 살아 있는 Enemy 수.
func get_enemy_count() -> int:
	var n := 0
	for e in _enemies:
		var enemy := e as EnemyActor3D
		if enemy != null and is_instance_valid(enemy) and enemy.alive:
			n += 1
	return n


func get_enemies() -> Array[Node]:
	var out: Array[Node] = []
	for e in _enemies:
		if is_instance_valid(e):
			out.append(e)
	return out


func is_night_active() -> bool:
	return _night_active


## SpawnCandidate의 world XZ 좌표. 3D 월드에 MapLayout이 있으면 그 조회 결과를,
## 없으면 WorldMap.SPAWN_CANDIDATES 상수를 XZ 해석해 반환한다(읽기 전용 참조).
func get_spawn_world_point(dir: String, world: Node) -> Vector3:
	var layout := world.get_node_or_null("MapLayout")
	if layout != null and layout.has_method("get_spawn_candidate"):
		return WorldCoords3D.to_world_xz(layout.get_spawn_candidate(dir))
	return WorldCoords3D.to_world_xz(
		WorldMap.SPAWN_CANDIDATES.get(dir, WorldMap.SETTLEMENT_CENTER))


## Main Road waypoint(world XZ) 중 spawn 지점보다 마을 쪽에 있는 지점만 선택해
## road 접근 경로를 만든다. Spawn 지점보다 바깥(맵 가장자리 방향) 지점은 제외한다.
## logical 폴리라인은 WorldCoords3D.polyline_to_world 단일 소스로 변환한다.
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


## Main Road 폴리라인의 world XZ 변환값. 3D 월드에 MapLayout이 있으면 그 조회 결과를,
## 없으면 WorldMap.MAIN_ROADS 상수를 polyline_to_world로 변환한다.
func get_main_road_points(dir: String, world: Node) -> PackedVector3Array:
	var layout := world.get_node_or_null("MapLayout")
	if layout != null and layout.has_method("get_main_road"):
		return WorldCoords3D.polyline_to_world(layout.get_main_road(dir))
	if WorldMap.MAIN_ROADS.has(dir):
		return WorldCoords3D.polyline_to_world(WorldMap.MAIN_ROADS[dir])
	return PackedVector3Array()


## village core(거점/정착지 중심) 목표 world XZ 좌표. Keep이 있으면 그 위치,
## 없으면 clearing 중심(SETTLEMENT_CENTER의 XZ)이다(2D fallback 순서 동일).
func get_village_core(world: Node) -> Vector3:
	var keep := world.get_node_or_null("Keep") as Node3D
	if keep != null:
		return WorldCoords3D.flatten(keep.global_position)
	var layout := world.get_node_or_null("MapLayout")
	if layout != null and layout.has_method("get_clearing_rect"):
		return WorldCoords3D.to_world_xz(layout.get_clearing_rect().get_center())
	return WorldCoords3D.to_world_xz(WorldMap.SETTLEMENT_CENTER)


## 같은 지점에 겹쳐 spawn되지 않도록 결정적 소량 offset. 기존 16px grid 간격을
## GRID_CELL_UNITS(=2 unit)로 환산해 적용한다(XZ 평면, Y 고정).
func _spawn_offset(i: int) -> Vector3:
	var col := i % 3 - 1
	var row := i / 3
	return Vector3(
		col * WorldCoords3D.GRID_CELL_UNITS, 0.0, row * WorldCoords3D.GRID_CELL_UNITS)
