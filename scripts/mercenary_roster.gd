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

## TASK-015-5: Focus Target 선택 시 마우스 클릭 지점에서 이 반경 이내의 Enemy를
## 선택한다.
const FOCUS_PICK_RADIUS := 32.0

const DEFENSE_ZONE_DIRS := {
	MercenaryData.DefenseZone.NORTH: "north",
	MercenaryData.DefenseZone.EAST: "east",
	MercenaryData.DefenseZone.SOUTH: "south",
	MercenaryData.DefenseZone.WEST: "west",
}

var _mercenaries: Array[MercenaryData] = []
var _actors: Dictionary = {}
## TASK-015-5: 전술 Focus Target. 플레이어가 NIGHT에서 선택한 우선 target(Enemy).
## focus_mode가 true면 다음 좌클릭으로 Enemy를 선택할 수 있고, 선택된 Enemy를
## 살아 있는 용병 Actor들이 우선 target으로 삼는다. target 사망/freed 시 자동 해제.
var focus_mode := false
var focus_target: Node = null

signal mercenaries_changed
## TASK-015-5: focus mode/target이 바뀌면 방출.
signal focus_target_changed


func _ready() -> void:
	GameTime.phase_changed.connect(_on_phase_changed)


## TASK-015-5: Focus Target mode 중 플레이어가 좌클릭으로 Enemy를 선택한다.
## NIGHT 전투 중에만 동작하고, focus mode가 아니면 무시한다. 빈 공간을 클릭하면
## 선택 mode만 유지하고, 우클릭/Esc로 mode를 해제할 수 있다.
func _unhandled_input(event: InputEvent) -> void:
	if not focus_mode:
		return
	if GameTime.get_phase() != GameTime.Phase.NIGHT:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var enemy := _enemy_at(_mouse_world_position(event), FOCUS_PICK_RADIUS)
			if enemy != null:
				set_focus_target(enemy)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			toggle_focus_mode()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		toggle_focus_mode()
		get_viewport().set_input_as_handled()


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


## TASK-015-3: 전술 명령(command_issued) 처리.
## DEFENSE_ZONE: 살아 있는 용병의 방어 구역을 실시간 변경한다.
## TASK-015-4: REGROUP은 살아 있는 용병 Actor를 현재 방어 구역 rally로 복귀시키고,
## RETREAT은 중앙 Village/safe rally로 후퇴시킨다. spawn 중(Actor 존재)인 용병만
## 행동이 필요하므로 Actor가 없으면 무시한다.
## TASK-015-5: FOCUS_TARGET은 Focus Target mode를 토글한다. mode 중 플레이어가
## 좌클릭으로 Enemy를 선택하면 모든 살아 있는 용병 Actor가 우선 target으로 삼는다.
## TASK-015-6: GATE_OPEN/GATE_CLOSE는 지정 성문(Gate Node)을 열고/닫고,
## TIME_PAUSE/1X/2X는 GameTime 전술 시간 배율을 설정한다(DAY 복원은 GameTime 담당).
func _on_tactical_command(command: int, arg: Variant) -> void:
	match command:
		TacticalCommandUI.Command.DEFENSE_ZONE:
			var zone: int = int(arg)
			var world := get_tree().get_first_node_in_group("world")
			for m in get_alive():
				if m.defense_zone != zone:
					set_defense_zone(m.id, zone, world)
		TacticalCommandUI.Command.REGROUP:
			for m in get_alive():
				var actor: Node = get_actor(m.id)
				if actor is MercenaryActor:
					(actor as MercenaryActor).regroup()
		TacticalCommandUI.Command.RETREAT:
			var world := get_tree().get_first_node_in_group("world")
			var safe := get_safe_rally(world)
			for m in get_alive():
				var actor: Node = get_actor(m.id)
				if actor is MercenaryActor:
					(actor as MercenaryActor).retreat(safe)
		TacticalCommandUI.Command.FOCUS_TARGET:
			toggle_focus_mode()
		TacticalCommandUI.Command.GATE_OPEN:
			_set_gate_open(arg, true)
		TacticalCommandUI.Command.GATE_CLOSE:
			_set_gate_open(arg, false)
		TacticalCommandUI.Command.TIME_PAUSE:
			GameTime.set_time_scale(GameTime.TIME_SCALE_PAUSE)
		TacticalCommandUI.Command.TIME_1X:
			GameTime.set_time_scale(GameTime.TIME_SCALE_1X)
		TacticalCommandUI.Command.TIME_2X:
			GameTime.set_time_scale(GameTime.TIME_SCALE_2X)


## TASK-015-6: 성문(Gate Node)의 OPEN/CLOSED를 명령한다. 성문이 없거나 이미
## freed면 안전하게 무시한다. BREACHED 성문은 gate.set_open이 no-op으로 처리해
## 자동 복구 없이 통로를 유지한다.
func _set_gate_open(gate: Variant, open: bool) -> void:
	if gate == null or not is_instance_valid(gate):
		return
	if gate.has_method("set_open"):
		gate.set_open(open)


## TASK-015-5: Focus Target mode를 켜고 끈다. mode가 켜지면 플레이어는 좌클릭으로
## Enemy를 선택할 수 있고, 끄면 현재 focus target을 해제한다.
func toggle_focus_mode() -> bool:
	focus_mode = not focus_mode
	if not focus_mode:
		clear_focus_target()
	focus_target_changed.emit()
	return focus_mode


## TASK-015-5: 지정 Enemy를 focus target으로 설정한다. 모든 살아 있는 용병 Actor에
## 전파해 우선 target으로 삼게 한다. target 사망(died)/제거(tree_exiting) 시 자동으로
## focus를 해제하도록 신호를 연결한다.
func set_focus_target(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.get("alive") == false:
		clear_focus_target()
		return
	_disconnect_focus_signals()
	focus_target = enemy
	focus_mode = true
	if enemy.has_signal("died") and not enemy.died.is_connected(_on_focus_target_died):
		enemy.died.connect(_on_focus_target_died)
	if not enemy.tree_exiting.is_connected(_on_focus_target_tree_exiting):
		enemy.tree_exiting.connect(_on_focus_target_tree_exiting)
	for m in get_alive():
		var actor: Node = get_actor(m.id)
		if actor is MercenaryActor:
			(actor as MercenaryActor).set_focus_target(enemy)
	focus_target_changed.emit()


## TASK-015-5: focus target 해제. 모든 살아 있는 용병 Actor의 focus를 해제한다.
func clear_focus_target() -> void:
	_disconnect_focus_signals()
	focus_target = null
	focus_mode = false
	for m in get_alive():
		var actor: Node = get_actor(m.id)
		if actor is MercenaryActor:
			(actor as MercenaryActor).clear_focus_target()
	focus_target_changed.emit()


## TASK-015-5: focus target이 사망하면 자동으로 focus를 해제한다.
func _on_focus_target_died(_enemy: Node) -> void:
	clear_focus_target()


## TASK-015-5: focus target이 freed/despawn 등으로 트리에서 제거되면 자동 해제한다.
func _on_focus_target_tree_exiting() -> void:
	clear_focus_target()


## TASK-015-5: 현재 focus target에 연결된 신호를 모두 해제한다.
func _disconnect_focus_signals() -> void:
	if focus_target != null and is_instance_valid(focus_target):
		if focus_target.has_signal("died") \
				and focus_target.died.is_connected(_on_focus_target_died):
			focus_target.died.disconnect(_on_focus_target_died)
		if focus_target.tree_exiting.is_connected(_on_focus_target_tree_exiting):
			focus_target.tree_exiting.disconnect(_on_focus_target_tree_exiting)


## TASK-015-5: focus mode가 활성 상태인지.
func is_focus_mode_active() -> bool:
	return focus_mode


## TASK-015-5: focus target이 설정되고 살아 있는지.
func has_focus_target() -> bool:
	return focus_target != null and is_instance_valid(focus_target) \
		and focus_target.get("alive") != false


## TASK-015-5: 현재 focus target 조회.
func get_focus_target() -> Node:
	return focus_target


## TASK-015-4: RETREAT 명령의 안전 지점(중앙 Village/safe rally).
## 정착지 clearing 중심을 우선하고, 없으면 Keep(거점) 위치로 대체한다.
func get_safe_rally(world: Node = null) -> Vector2:
	if world == null or not is_instance_valid(world):
		world = get_tree().get_first_node_in_group("world")
	if world == null:
		return Vector2.ZERO
	var layout := world.get_node_or_null("MapLayout")
	if layout != null and layout.has_method("get_clearing_rect"):
		return layout.get_clearing_rect().get_center()
	var keep := world.get_node_or_null("Keep") as Node2D
	if keep != null:
		return keep.global_position
	return Vector2.ZERO


## TASK-015-3: 지정 용병의 방어 구역을 실시간 변경한다. spawn 중(Actor 존재)이면
## 해당 Actor의 defense anchor/rally도 새 구역 기준으로 갱신하고, 현재 target이
## 새 구역과 무관/너무 멀면 disengage 후 새 구역으로 nav 복귀시킨다(teleport 금지).
func set_defense_zone(mercenary_id: String, zone: int, world: Node = null) -> bool:
	var m := get_mercenary(mercenary_id)
	if m == null or not m.alive:
		return false
	if m.defense_zone == zone:
		return true
	m.set_defense_zone(zone)
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	var actor: Node = get_actor(mercenary_id)
	if actor != null and is_instance_valid(actor) and actor is MercenaryActor:
		var rally := get_rally_point_for_zone(zone, world)
		actor.set_defense_zone(zone, rally)
	mercenaries_changed.emit()
	return true


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


## TASK-015-5: 마우스 클릭 이벤트의 월드 좌표. 이벤트가 있으면 이벤트 좌표(viewport)를
## 카메라 변환으로 월드 좌표로 변환하고, 없으면 현재 viewport 마우스 위치를 사용한다.
func _mouse_world_position(event: InputEvent = null) -> Vector2:
	var viewport_pos := Vector2.ZERO
	if event is InputEventMouse:
		viewport_pos = (event as InputEventMouse).position
	else:
		viewport_pos = get_viewport().get_mouse_position()
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		return cam.get_canvas_transform().affine_inverse() * viewport_pos
	return viewport_pos


## TASK-015-5: 지정 반경 안에서 가장 가까운 살아 있는 Enemy를 찾는다. 없으면 null.
func _enemy_at(world_pos: Vector2, radius: float) -> Node:
	var best: Node = null
	var best_dist := radius
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e.get("alive") == false:
			continue
		var d: float = (e.global_position as Vector2).distance_to(world_pos)
		if d <= best_dist:
			best_dist = d
			best = e
	return best