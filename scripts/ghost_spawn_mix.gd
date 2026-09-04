extends Node
class_name GhostSpawnMix

## TASK-025-2 Ghost Spawn Mix Integration.
## DeathLedger의 PENDING eligible record를 Ghost 후보 FIFO 큐로 관리하고, NIGHT spawn
## 시 기존 Wave/Threat spawn(FirstEncounterSpawner3D)에 Ghost를 섞어 넣는다.
##
## - configurable insertion policy: max_ghosts_per_night(기본 1)로 조정 가능한 삽입
##   정책을 사용한다. exact ratio가 없으므로 hardcoded random system을 만들지 않는다.
## - Ghost는 일반 enemy spawn budget(count)을 점유한다(기존 설계 우선): spawner가
##   regular count에서 mix가 소비한 수만큼 차감한다.
## - same candidate once only: candidate는 1회만 spawn되고, 성공 spawn 후에는 소비되어
##   다음 NIGHT에 재삽입되지 않는다(원본 record RESOLVED 처리와 함께).
## - spawn failure recovery: spawn 실패 시 candidate를 잃지 않고 큐 앞으로 복원한다.
##
## main_3d.tscn의 scene node로 배치되며 "ghost_spawn_mix" 그룹으로 spawner가 조회한다.
## 별도 거대 WaveManager를 만들지 않고 기존 spawn 경로를 최소 확장한다.

signal ghost_spawned(record_id: String)
signal ghost_spawn_failed(record_id: String)

@export var max_ghosts_per_night := 1
## Ghost Actor scene 경로. 테스트에서 spawn failure recovery를 유도하기 위해 조정 가능.
@export var ghost_scene := "res://scenes/ghost_3d.tscn"

var _queue: Array[String] = []
var _spawned_ghosts: Array[Node] = []
var _ghosts_this_night := 0


func _ready() -> void:
	add_to_group("ghost_spawn_mix")
	var gt := get_node_or_null("/root/GameTime")
	if gt != null and not gt.phase_changed.is_connected(_on_phase_changed):
		gt.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(phase: int, _day_number: int) -> void:
	if phase != GameTime.Phase.NIGHT:
		_despawn_ghosts()


## DAY 복귀 시 spawn한 Ghost를 전부 despawn한다. queue_free 직접 호출이므로 record
## 상태를 바꾸지 않는다(cleanup은 RESOLVED 처리되지 않음). 반복 호출은 멱등.
func _despawn_ghosts() -> void:
	for g in _spawned_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_spawned_ghosts.clear()


## NIGHT spawn 시 spawner가 호출한다. eligible candidate를 Ghost Actor로 spawn하고,
## 소비한 budget 수(ghost 수)를 반환해 spawner가 regular count에서 차감하게 한다.
func spawn_ghost_mix(world: Node, spawn_point: Vector3, waypoints: Array, core: Vector3, direction: String) -> int:
	if GameTime.get_phase() != GameTime.Phase.NIGHT:
		return 0
	_refresh_queue()
	_ghosts_this_night = 0
	var spawned := 0
	var attempts := mini(max_ghosts_per_night, _queue.size())
	while attempts > 0 and _queue.size() > 0:
		attempts -= 1
		var record_id := _queue[0]
		_queue.pop_front()
		var record := _get_record(record_id)
		if record == null:
			continue
		if not _mark_active(record_id):
			continue
		var ghost := _try_spawn(record, world, spawn_point, waypoints, core, direction, spawned)
		if ghost == null:
			# spawn failure recovery: candidate를 잃지 않고 큐 앞으로 복원한다.
			_mark_pending(record_id)
			_queue.push_front(record_id)
			ghost_spawn_failed.emit(record_id)
			continue
		_spawned_ghosts.append(ghost)
		_ghosts_this_night += 1
		spawned += 1
		ghost_spawned.emit(record_id)
	return spawned


## 이번 NIGHT에 mix가 spawn한 ghost 수(남은 사망 여부와 무관).
func get_spawned_count() -> int:
	return _ghosts_this_night


## 현재 살아 있는 spawn된 Ghost 수.
func get_alive_ghost_count() -> int:
	var n := 0
	for g in _spawned_ghosts:
		if is_instance_valid(g) and g.get("alive") != false:
			n += 1
	return n


## PENDING eligible record를 FIFO 큐로 보강한다. 이미 큐에 있는 id / ghost record는
## 추가하지 않는다. DeathLedger가 duplicate/ghost/cleanup을 원천 차단하므로 candidate
## 중복이 생기지 않는다.
func _refresh_queue() -> void:
	var ledger := _ledger()
	if ledger == null:
		return
	for record in ledger.get_pending_records():
		if record.is_ghost:
			continue
		if record.record_id in _queue:
			continue
		_queue.append(record.record_id)


func _get_record(record_id: String) -> DeathRecord:
	var ledger := _ledger()
	if ledger == null:
		return null
	return ledger.get_record(record_id)


func _mark_active(record_id: String) -> bool:
	var ledger := _ledger()
	return ledger != null and ledger.mark_active(record_id)


func _mark_pending(record_id: String) -> bool:
	var ledger := _ledger()
	return ledger != null and ledger.mark_pending(record_id)


func _try_spawn(record: DeathRecord, world: Node, spawn_point: Vector3, waypoints: Array, core: Vector3, direction: String, index: int) -> Node:
	var scene: PackedScene = load(ghost_scene)
	if scene == null:
		return null
	var ghost := scene.instantiate() as GhostActor3D
	if ghost == null:
		return null
	ghost.setup_ghost(
		"ghost_" + record.record_id, record.display_name, direction,
		record.record_id, record.source_uid)
	ghost.max_hp = maxi(1, record.max_hp)
	ghost.current_hp = ghost.max_hp
	ghost.attack_damage = record.attack_damage
	ghost.attack_interval = record.attack_interval
	ghost.move_speed = _resolve_move_speed(record.move_speed)
	ghost.position = spawn_point + _spawn_offset(index)
	world.add_child(ghost)
	ghost.set_route(waypoints, core)
	return ghost


## 원본 move_speed가 0(미기록)이면 기본 Enemy 속도로 대체한다.
func _resolve_move_speed(move_speed: float) -> float:
	if move_speed > 0.0:
		return move_speed
	return 90.0 * WorldCoords3D.PX_TO_UNIT


## 같은 지점에 겹쳐 spawn되지 않도록 결정적 소량 offset(XZ, Y 고정).
func _spawn_offset(index: int) -> Vector3:
	var col := index % 3 - 1
	var row := index / 3
	return Vector3(col * WorldCoords3D.GRID_CELL_UNITS, 0.0, row * WorldCoords3D.GRID_CELL_UNITS)


func _ledger() -> Node:
	return get_node_or_null("/root/DeathLedger")
