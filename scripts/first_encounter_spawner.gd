extends Node

## TASK-014-3 첫 NIGHT 조우 Spawner (FirstEncounterSpawner).
## 범용 WaveManager를 만들지 않고, NIGHT 시작 시 한 방향(SpawnCandidate)에서
## configurable 수량의 일반 근접 Enemy를 spawn한다. DAY 복귀 시 spawn한 Enemy를
## 전부 despawn한다. 실제 Portal 시스템은 구현하지 않으며, 기존 Spawn Candidate를
## spawn 위치로 재사용한다. 같은 NIGHT에 중복 spawn/반복 NIGHT duplicate 없음.
## 이동은 Enemy가 Main Road/Approach Route waypoint를 따라 마을 쪽으로 접근하도록
## 경로를 계산해 전달한다(road 접근 선호).

const ENEMY_SCENE := "res://scenes/enemy.tscn"

const DEFAULT_DIRECTION := "north"
const DEFAULT_COUNT := 3

const DIRECTIONS := ["north", "south", "east", "west"]
const DIRECTION_AXIS := {
	"north": Vector2(0, 1),
	"south": Vector2(0, -1),
	"east": Vector2(1, 0),
	"west": Vector2(-1, 0),
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


## TASK-014-3: NIGHT spawn. 이미 이번 NIGHT에 spawn했으면(또는 DAY면) 아무것도 하지
## 않아 DAY 오작동 spawn / 반복 NIGHT duplicate를 방지한다.
func spawn_encounter() -> int:
	if GameTime.get_phase() != GameTime.Phase.NIGHT:
		return 0
	if _night_active:
		return 0
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not is_instance_valid(world):
		return 0
	var scene: PackedScene = load(ENEMY_SCENE)
	if scene == null:
		return 0
	var layout := world.get_node_or_null("MapLayout")
	var spawn_point := Vector2.ZERO
	if layout != null and layout.has_method("get_spawn_candidate"):
		spawn_point = layout.get_spawn_candidate(direction)
	var waypoints := _build_waypoints(world, direction, spawn_point)
	var core := _get_village_core(world)
	var spawned := 0
	for i in count:
		var enemy := scene.instantiate() as EnemyActor
		if enemy == null:
			continue
		enemy.setup("enemy_%s_%d" % [direction, i], "Raider", direction)
		enemy.position = spawn_point + _spawn_offset(i)
		world.add_child(enemy)
		enemy.set_route(waypoints, core)
		_enemies.append(enemy)
		spawned += 1
	_night_active = true
	return spawned


## TASK-014-3: DAY 복귀 시 spawn한 Enemy를 전부 despawn한다. 반복 호출은 멱등.
func despawn_encounter() -> int:
	var removed := 0
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
			removed += 1
	_enemies.clear()
	_night_active = false
	return removed


## 현재 spawn된 살아 있는 Enemy 수.
func get_enemy_count() -> int:
	var n := 0
	for e in _enemies:
		var enemy := e as EnemyActor
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


## Main Road waypoint(외곽→내부) 중 Spawn 지점보다 마을 쪽에 있는 지점만 선택해
## road 접근 경로를 만든다. Spawn 지점보다 바깥(맵 가장자리 방향) 지점은 제외한다.
func _build_waypoints(world: Node, dir: String, start: Vector2) -> Array[Vector2]:
	var layout := world.get_node_or_null("MapLayout")
	var waypoints: Array[Vector2] = []
	if layout == null or not layout.has_method("get_main_road"):
		return waypoints
	var road: Array = layout.get_main_road(dir).duplicate()
	road.reverse()
	var axis: Vector2 = DIRECTION_AXIS.get(dir, Vector2.ZERO)
	for p in road:
		var v := Vector2(p)
		if (v - start).dot(axis) > 0.0:
			waypoints.append(v)
	return waypoints


## village core(거점/정착지 중심) 목표 좌표. Keep이 없으면 clearing 중심.
func _get_village_core(world: Node) -> Vector2:
	var keep := world.get_node_or_null("Keep")
	if keep != null and keep is Node2D:
		return (keep as Node2D).global_position
	var layout := world.get_node_or_null("MapLayout")
	if layout != null and layout.has_method("get_clearing_rect"):
		return layout.get_clearing_rect().get_center()
	return Vector2.ZERO


## 같은 지점에 겹쳐 spawn되지 않도록 결정적 소량 offset.
func _spawn_offset(i: int) -> Vector2:
	var col := i % 3 - 1
	var row := i / 3
	return Vector2(col * 16.0, row * 16.0)