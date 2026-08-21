extends Node

## TASK-014-1 최소 Mercenary Roster 기반.
## TASK-014-2 NIGHT Actor spawn / DAY despawn 라이프사이클.
## 고용된 MercenaryData를 월드와 독립적으로 보관하고,
## NIGHT 시작 시 살아 있고 defense zone이 지정된 용병을 해당 방향 Gate 안쪽
## Rally Space(RallySpace marker fallback)에 전투 Actor로 spawn하고,
## DAY 복귀 시 spawn된 Actor를 despawn해 roster data 상태로 복귀시킨다.
## 같은 id의 용병 중복 고용을 거부하고, id 조회/생존 상태 조회를 제공한다.
## 영구 Save/Load는 구현하지 않는다.

const MERCENARY_SCENE := "res://scenes/mercenary.tscn"

const DEFENSE_ZONE_DIRS := {
	MercenaryData.DefenseZone.NORTH: "north",
	MercenaryData.DefenseZone.EAST: "east",
	MercenaryData.DefenseZone.SOUTH: "south",
	MercenaryData.DefenseZone.WEST: "west",
}

var _mercenaries: Array[MercenaryData] = []
var _actors: Dictionary = {}

signal mercenaries_changed


func _ready() -> void:
	GameTime.phase_changed.connect(_on_phase_changed)


## NIGHT 시작 / DAY 복귀 시 spawn/despawn을 처리한다.
func _on_phase_changed(phase: int, _day_number: int) -> void:
	if phase == GameTime.Phase.NIGHT:
		spawn_night_actors()
	else:
		despawn_night_actors()


## TASK-014-2: NIGHT 시작 시 살아 있고 defense zone이 지정된 용병을 해당 방향
## Rally Space에 spawn한다. 이미 살아있는 Actor가 있으면 건드리지 않아
## 반복 NIGHT cycle에서 actor duplicate를 방지한다.
func spawn_night_actors() -> int:
	var spawned := 0
	var world := get_tree().get_first_node_in_group("world")
	for m in get_alive():
		if m.defense_zone == MercenaryData.DefenseZone.NONE:
			continue
		if _actors.has(m.id) and is_instance_valid(_actors[m.id]):
			continue
		if _spawn_actor(m, world):
			spawned += 1
	return spawned


func _spawn_actor(m: MercenaryData, world: Node) -> bool:
	if world == null or not is_instance_valid(world):
		return false
	var scene: PackedScene = load(MERCENARY_SCENE)
	if scene == null:
		return false
	var actor := scene.instantiate() as MercenaryActor
	if actor == null:
		return false
	actor.merc_data = m
	var rally := get_rally_point_for_zone(m.defense_zone, world)
	actor.position = rally
	actor.defense_point = rally
	world.add_child(actor)
	# TASK-014-4: Actor가 사망하면(월드 제거 전) _actors에서 바로 제거해
	# freed reference가 roster에 남아 재조회/despawn 시 오류 나지 않게 한다.
	actor.died.connect(_on_actor_died.bind(m.id))
	_actors[m.id] = actor
	return true


## TASK-014-4: 사망한 용병 Actor를 _actors에서 제거. get_alive()는 이미 alive=false를
## 제외하므로 다음 NIGHT에 재생성되지 않는다.
func _on_actor_died(_mercenary: Node, mercenary_id: String) -> void:
	_actors.erase(mercenary_id)


## TASK-014-2: DAY 복귀 시 spawn된 모든 Actor를 despawn한다. 살아 있는 용병은
## roster data로 복귀하고(roster는 이미 데이터를 보유), 죽은 용병 Actor도 월드에서
## 제거한다. 반복 호출은 멱등하다.
func despawn_night_actors() -> int:
	var removed := 0
	for id in _actors.keys():
		var actor: Variant = _actors[id]
		if actor != null and is_instance_valid(actor):
			actor.queue_free()
		_actors.erase(id)
		removed += 1
	return removed


## 해당 defense zone의 Rally Space(Gate 안쪽) 중심 좌표.
## 해당 방향에 Gate가 설치되어 있으면 Rally Space 중심을 반환하고,
## 없으면 기존 RallySpace marker 기준 fallback RallyPoint를 반환한다.
func get_rally_point_for_zone(zone: int, world: Node) -> Vector2:
	var dir: String = DEFENSE_ZONE_DIRS.get(zone, "")
	if dir == "":
		return Vector2.ZERO
	var map_layout: Node = world.get_node_or_null("MapLayout") if world != null else null
	var rally_space_center := Vector2.ZERO
	var fallback := Vector2.ZERO
	if map_layout != null:
		if map_layout.has_method("get_rally_space"):
			rally_space_center = map_layout.get_rally_space(dir).get_center()
		var marker := map_layout.get_node_or_null("RallySpace_" + dir.to_upper()) as Node2D
		fallback = marker.position if marker != null else rally_space_center
	if _find_gate_for_direction(world, dir) != null:
		if rally_space_center != Vector2.ZERO:
			return rally_space_center
		return fallback
	return fallback


func _find_gate_for_direction(world: Node, dir: String) -> Node:
	for gate in get_tree().get_nodes_in_group("gates"):
		if not is_instance_valid(gate):
			continue
		if gate.has_method("get_direction") and gate.get_direction() == dir:
			return gate
	return null


func add_mercenary(mercenary: MercenaryData) -> bool:
	if mercenary == null or not mercenary is MercenaryData:
		return false
	if get_mercenary(mercenary.id) != null:
		return false
	_mercenaries.append(mercenary)
	mercenaries_changed.emit()
	return true


func remove_mercenary(mercenary: MercenaryData) -> bool:
	if mercenary == null or not _mercenaries.has(mercenary):
		return false
	_mercenaries.erase(mercenary)
	var actor: Node = _actors.get(mercenary.id)
	if actor != null and is_instance_valid(actor):
		actor.queue_free()
	_actors.erase(mercenary.id)
	mercenaries_changed.emit()
	return true


func get_mercenary(mercenary_id: String) -> MercenaryData:
	for m in _mercenaries:
		if m.id == mercenary_id:
			return m
	return null


func get_mercenaries() -> Array[MercenaryData]:
	return _mercenaries.duplicate()


func get_alive() -> Array[MercenaryData]:
	var out: Array[MercenaryData] = []
	for m in _mercenaries:
		if m.alive:
			out.append(m)
	return out


func get_count() -> int:
	return _mercenaries.size()


func get_alive_count() -> int:
	return get_alive().size()


## TASK-014-2: 현재 월드에 spawn된 용병 Actor를 조회한다. 없으면 null.
## freed reference(사망 후)가 남아 있어도 오류 없이 null을 반환한다.
func get_actor(mercenary_id: String) -> Node:
	if not _actors.has(mercenary_id):
		return null
	var actor: Variant = _actors.get(mercenary_id)
	if actor != null and is_instance_valid(actor):
		return actor
	return null


## TASK-014-2: 현재 월드에 spawn된 용병 Actor 수.
func get_actor_count() -> int:
	var n := 0
	for actor: Variant in _actors.values():
		if is_instance_valid(actor):
			n += 1
	return n