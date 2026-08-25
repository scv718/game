extends Node
class_name MercenaryRoster3D

## TASK-3D-CMB-001-2 Tactical Command World3D Wiring - Mercenary Roster 3D.
## 기존 mercenary_roster.gd(Node autoload)의 NIGHT spawn / DAY despawn / 전술 명령
## 처리를 3D Runtime용으로 이전한 신규 파일이다. 기존 2D mercenary_roster.gd는
## LOCK 12에 따라 무수정으로 유지되며 이 파일이 대신하는 것은 3D World의
## MercenaryActor3D 라이프사이클과 전술 명령뿐이다.
##
## - 고용된 MercenaryData를 보관하고 NIGHT 시작 시 살아 있고 defense zone이 지정된
##   용병을 해당 방향 Gate 안쪽 Rally Space(RallySpace marker fallback)의 world XZ
##   좌표에 MercenaryActor3D로 spawn한다. DAY 복귀 시 spawn된 Actor를 despawn하고
##   focus mode/target 같은 tactical transient state를 함께 정리한다.
## - Defense Zone 위치/범위는 전부 XZ world 기준으로 처리한다. rally/safe 좌표는
##   WorldCoords3D 변환 단일 소스(rect_to_aabb/to_world_xz)만 사용하며
##   WorldMap logical 상수는 읽기 전용 참조다(파편적 하드코딩 금지).
## - Focus Target은 Foundation Camera3D 광선 선택이다. 카메라 컨트롤러
##   (camera_controller_3d 그룹)의 screen -> 지면 교차점으로 클릭 지점을 얻고,
##   enemies_3d 그룹 + WorldCoords3D.distance_xz 최근접 조회로 Enemy를 고른다
##   (2D _enemy_at 반경 조회 계약의 3D판, INTEGRATION_NOTE_CMB 권장 방식).
## - 명령 우선순위는 기존 규칙 그대로다: FOCUS > defense zone 자동 전투 >
##   REGROUP/RETREAT/DEAD. REGROUP/RETREAT 중에는 set_focus_target이 즉시
##   전환하지 않고 해당 상태 종료 후 재탐색 때 적용된다(actor 계약).
## - Gate world command는 gates_3d 그룹 노드에 duck-typing set_open(open)으로
##   위임한다(2D gate.gd set_open 계약과 동일, BREACHED no-op는 gate 측 책임).
##   BLD가 Gate3D 계약(is_closed/take_damage/set_open)을 갖추면 무수정 연결된다.
## - TacticalCommandUI3D와의 연결은 그룹 조회("tactical_command_ui_3d" /
##   "mercenary_roster_3d") 양방향 guarded connect다. UI는 Control 계층으로 유지되며
##   command 코드는 기존 TacticalCommandUI.Command enum을 차원 중립적으로 재사용한다.

const MERCENARY_SCENE := "res://scenes/mercenary_3d.tscn"

## Focus Target 선택 반경(world unit). 기존 2D FOCUS_PICK_RADIUS 32px를
## PX_TO_UNIT 환산한 값이라 픽 감각 비율이 동일하다.
const FOCUS_PICK_RADIUS := 32.0 * WorldCoords3D.PX_TO_UNIT

const DEFENSE_ZONE_DIRS := {
	MercenaryData.DefenseZone.NORTH: "north",
	MercenaryData.DefenseZone.EAST: "east",
	MercenaryData.DefenseZone.SOUTH: "south",
	MercenaryData.DefenseZone.WEST: "west",
}

var _mercenaries: Array[MercenaryData] = []
var _actors: Dictionary = {}
## 전술 Focus Target. 플레이어가 NIGHT에서 선택한 우선 target(살아 있는 Enemy).
## focus_mode가 true면 다음 좌클릭 광선으로 Enemy를 선택할 수 있고, 선택된 Enemy를
## 살아 있는 용병 Actor들이 우선 target으로 삼는다. target 사망/freed 시 자동 해제.
var focus_mode := false
var focus_target: Node = null

signal mercenaries_changed
signal focus_target_changed


func _ready() -> void:
	add_to_group("mercenary_roster_3d")
	GameTime.phase_changed.connect(_on_phase_changed)
	_connect_tactical_ui()


## TacticalCommandUI3D와의 command 경로를 연결한다. UI가 먼저 트리에 있으면 여기서,
## 늦게 들어오면 UI 쪽 _connect_roster에서 연결된다(중복 connect guard).
func _connect_tactical_ui() -> void:
	var ui := get_tree().get_first_node_in_group("tactical_command_ui_3d")
	if ui != null and ui.has_signal("command_issued") \
			and not ui.command_issued.is_connected(_on_tactical_command):
		ui.command_issued.connect(_on_tactical_command)


## Focus Target mode 중 플레이어가 좌클릭 광선으로 Enemy를 선택한다.
## NIGHT 전투 중에만 동작하고, focus mode가 아니면 무시한다. 빈 공간을 클릭하면
## 선택 mode만 유지하고, 우클릭/Esc로 mode를 해제할 수 있다(2D 계약 동일).
func _unhandled_input(event: InputEvent) -> void:
	if not focus_mode:
		return
	if GameTime.get_phase() != GameTime.Phase.NIGHT:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var enemy := pick_focus_target_at((event as InputEventMouse).position)
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


## NIGHT 시작 / DAY 복귀 시 spawn/despawn과 transient state 정리를 처리한다.
func _on_phase_changed(phase: int, _day_number: int) -> void:
	if phase == GameTime.Phase.NIGHT:
		spawn_night_actors()
	else:
		despawn_night_actors()
		clear_focus_target()


## NIGHT 시작 시 살아 있고 defense zone이 지정된 용병을 해당 방향 Rally Space의
## world XZ 좌표에 spawn한다. 이미 살아있는 Actor가 있으면 건드리지 않아
## 반복 NIGHT cycle에서 actor duplicate를 방지한다(2D 계약 동일).
func spawn_night_actors() -> int:
	var spawned := 0
	var world := get_tree().get_first_node_in_group("world3d")
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
	var actor := scene.instantiate() as MercenaryActor3D
	if actor == null:
		return false
	actor.merc_data = m
	var rally := get_rally_point_for_zone(m.defense_zone, world)
	actor.position = rally
	actor.defense_point = rally
	world.add_child(actor)
	# Actor가 사망하면(월드 제거 전) _actors에서 바로 제거해 freed reference가
	# roster에 남아 재조회/despawn 시 오류 나지 않게 한다(2D 계약 동일).
	actor.died.connect(_on_actor_died.bind(m.id))
	_actors[m.id] = actor
	return true


func _on_actor_died(_mercenary: Node, mercenary_id: String) -> void:
	_actors.erase(mercenary_id)


## 전술 명령(command_issued) 처리. 명령 코드는 기존 TacticalCommandUI.Command를
## 재사용하고 우선순위 규칙도 2D와 동일하다.
## DEFENSE_ZONE: 살아 있는 용병의 방어 구역을 실시간 변경(XZ rally 갱신 포함).
## REGROUP: 현재 방어 구역 rally로 복귀. RETREAT: 중앙 Village/safe rally로 후퇴.
## spawn 중(Actor 존재)인 용병만 행동이 필요하므로 Actor가 없으면 무시한다.
## FOCUS_TARGET: Focus Target mode 토글. GATE_OPEN/GATE_CLOSE: 성문 개폐 명령.
## TIME_PAUSE/1X/2X: GameTime 전술 시간 배율(DAY 복원은 GameTime 담당).
func _on_tactical_command(command: int, arg: Variant) -> void:
	match command:
		TacticalCommandUI.Command.DEFENSE_ZONE:
			var zone: int = int(arg)
			var world := get_tree().get_first_node_in_group("world3d")
			for m in get_alive():
				if m.defense_zone != zone:
					set_defense_zone(m.id, zone, world)
		TacticalCommandUI.Command.REGROUP:
			for m in get_alive():
				var actor: Node = get_actor(m.id)
				if actor is MercenaryActor3D:
					(actor as MercenaryActor3D).regroup()
		TacticalCommandUI.Command.RETREAT:
			var safe := get_safe_rally()
			for m in get_alive():
				var actor: Node = get_actor(m.id)
				if actor is MercenaryActor3D:
					(actor as MercenaryActor3D).retreat(safe)
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


## 성문(gates_3d 계약 노드)의 OPEN/CLOSED를 명령한다. 성문이 없거나 이미 freed면
## 안전하게 무시한다. BREACHED 성문의 set_open no-op(재개방 금지)는 gate 측 계약이다.
func _set_gate_open(gate: Variant, open: bool) -> void:
	if gate == null or not is_instance_valid(gate):
		return
	if gate.has_method("set_open"):
		gate.set_open(open)


## Focus Target mode를 켜고 끈다. mode가 켜지면 플레이어는 좌클릭 광선으로
## Enemy를 선택할 수 있고, 끄면 현재 focus target을 해제한다.
func toggle_focus_mode() -> bool:
	focus_mode = not focus_mode
	if not focus_mode:
		clear_focus_target()
	focus_target_changed.emit()
	return focus_mode


## 화면 좌표 광선(Foundation Camera3D)으로 focus 대상 Enemy 1개를 조회한다.
## 카메라 광선을 지면(Y=GROUND_Y)과 교차시켜 클릭 지점의 world XZ를 얻고,
## enemies_3d 그룹에서 그 지점에 가장 가까운 살아 있는 Enemy를 반경 내 반환한다.
## 광선이 지면에 닿지 않거나 대상이 없으면 null(빈 ground 클릭 안전).
func pick_focus_target_at(screen_pos: Vector2) -> Node:
	var ground_point := _ground_point_from_screen(screen_pos)
	if ground_point == Vector3.INF:
		return null
	return _enemy_at(ground_point, FOCUS_PICK_RADIUS)


## camera_controller_3d 그룹의 컨트롤러에서 screen -> 지면 교차점을 얻는다.
## 컨트롤러 부재/미준비 시 Vector3.INF(안전 no-op).
func _ground_point_from_screen(screen_pos: Vector2) -> Vector3:
	var cam_ctl := get_tree().get_first_node_in_group("camera_controller_3d")
	if cam_ctl == null or not cam_ctl.has_method("ground_point_from_screen"):
		return Vector3.INF
	return cam_ctl.ground_point_from_screen(screen_pos)


## 지정 Enemy를 focus target으로 설정한다. 모든 살아 있는 용병 Actor에 전파해
## 우선 target으로 삼게 한다. target 사망(died)/제거(tree_exiting) 시 자동으로
## focus를 해제하도록 신호를 연결한다(2D 계약 동일).
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
		if actor is MercenaryActor3D:
			(actor as MercenaryActor3D).set_focus_target(enemy)
	focus_target_changed.emit()


## focus target 해제. 모든 살아 있는 용병 Actor의 focus를 해제한다.
func clear_focus_target() -> void:
	_disconnect_focus_signals()
	focus_target = null
	focus_mode = false
	for m in get_alive():
		var actor: Node = get_actor(m.id)
		if actor is MercenaryActor3D:
			(actor as MercenaryActor3D).clear_focus_target()
	focus_target_changed.emit()


func _on_focus_target_died(_enemy: Node) -> void:
	clear_focus_target()


func _on_focus_target_tree_exiting() -> void:
	clear_focus_target()


func _disconnect_focus_signals() -> void:
	if focus_target != null and is_instance_valid(focus_target):
		if focus_target.has_signal("died") \
				and focus_target.died.is_connected(_on_focus_target_died):
			focus_target.died.disconnect(_on_focus_target_died)
		if focus_target.tree_exiting.is_connected(_on_focus_target_tree_exiting):
			focus_target.tree_exiting.disconnect(_on_focus_target_tree_exiting)


func is_focus_mode_active() -> bool:
	return focus_mode


func has_focus_target() -> bool:
	return focus_target != null and is_instance_valid(focus_target) \
		and focus_target.get("alive") != false


func get_focus_target() -> Node:
	return focus_target


## RETREAT 명령의 안전 지점(중앙 Village/safe rally)을 world XZ로 반환한다.
## 2D와 동일하게 MapLayout clearing 중심을 우선하고 Keep 위치로 대체하며,
## 3D 독립 runtime(INT wiring 전)에서는 WorldMap 상수의 clearing 중심을 쓴다.
func get_safe_rally(world: Node = null) -> Vector3:
	if world == null or not is_instance_valid(world):
		world = get_tree().get_first_node_in_group("world3d")
	if world == null:
		return WorldCoords3D.to_world_xz(WorldMap.SETTLEMENT_CENTER)
	var layout := world.get_node_or_null("MapLayout")
	if layout != null and layout.has_method("get_clearing_rect"):
		return WorldCoords3D.to_world_xz(layout.get_clearing_rect().get_center())
	var keep := world.get_node_or_null("Keep") as Node3D
	if keep != null:
		return WorldCoords3D.flatten(keep.global_position)
	return WorldCoords3D.to_world_xz(WorldMap.SETTLEMENT_CENTER)


## 지정 용병의 방어 구역을 실시간 변경한다. spawn 중(Actor 존재)이면 해당 Actor의
## defense anchor/rally도 새 구역 기준 XZ 좌표로 갱신하고, 현재 target이 새 구역과
## 무관/너무 멀면 disengage 후 새 구역으로 nav 복귀시킨다(teleport 금지, 2D 동일).
func set_defense_zone(mercenary_id: String, zone: int, world: Node = null) -> bool:
	var m := get_mercenary(mercenary_id)
	if m == null or not m.alive:
		return false
	if m.defense_zone == zone:
		return true
	m.set_defense_zone(zone)
	if world == null:
		world = get_tree().get_first_node_in_group("world3d")
	var actor: Node = get_actor(mercenary_id)
	if actor != null and is_instance_valid(actor) and actor is MercenaryActor3D:
		var rally := get_rally_point_for_zone(zone, world)
		actor.set_defense_zone(zone, rally)
	mercenaries_changed.emit()
	return true


## DAY 복귀 시 spawn된 모든 Actor를 despawn한다. 살아 있는 용병은 roster data로
## 복귀하고(roster는 이미 데이터를 보유), 죽은 용병 Actor도 월드에서 제거한다.
## queue_free 직접 호출이므로 DeathRecord를 만들지 않는다. 반복 호출은 멱등.
func despawn_night_actors() -> int:
	var removed := 0
	for id in _actors.keys():
		var actor: Variant = _actors[id]
		if actor != null and is_instance_valid(actor):
			actor.queue_free()
		_actors.erase(id)
		removed += 1
	return removed


## 해당 defense zone의 Rally Space(Gate 안쪽) 중심 world XZ 좌표.
## 설치된 Gate3d 유무와 무관하게 Rally Space 중심을 반환한다(2D와 동일 결과).
## 좌표 소스는 MapLayout(get_rally_space/marker)이 있으면 그것이 우선이고
## 없으면 WorldMap.RALLY_SPACES 상수를 WorldCoords3D.rect_to_aabb로 XZ 해석한다.
func get_rally_point_for_zone(zone: int, world: Node = null) -> Vector3:
	var dir: String = DEFENSE_ZONE_DIRS.get(zone, "")
	if dir == "":
		return Vector3.ZERO
	if world == null or not is_instance_valid(world):
		world = get_tree().get_first_node_in_group("world3d")
	var map_layout: Node = world.get_node_or_null("MapLayout") if world != null else null
	if map_layout != null and map_layout.has_method("get_rally_space"):
		return WorldCoords3D.to_world_xz(map_layout.get_rally_space(dir).get_center())
	if map_layout != null:
		var marker := map_layout.get_node_or_null(
			"RallySpace_" + dir.to_upper()) as Node3D
		if marker != null:
			return WorldCoords3D.flatten(marker.global_position)
	return WorldCoords3D.rect_to_aabb(
		WorldMap.RALLY_SPACES.get(dir, Rect2())).get_center()


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


## 현재 월드에 spawn된 용병 Actor를 조회한다. 없으면 null.
## freed reference(사망 후)가 남아 있어도 오류 없이 null을 반환한다.
func get_actor(mercenary_id: String) -> Node:
	if not _actors.has(mercenary_id):
		return null
	var actor: Variant = _actors.get(mercenary_id)
	if actor != null and is_instance_valid(actor):
		return actor
	return null


## 현재 월드에 spawn된 용병 Actor 수.
func get_actor_count() -> int:
	var n := 0
	for actor: Variant in _actors.values():
		if is_instance_valid(actor):
			n += 1
	return n


## 지정 반경(unit) 안에서 클릭 지점에 가장 가까운 살아 있는 Enemy를 찾는다.
## enemies_3d 그룹 + WorldCoords3D.distance_xz 기준(2D _enemy_at의 3D판).
## 거리 판정은 body volume이 아니라 그룹 거리 조회 기준이다(001-1 충돌 규약 동일).
func _enemy_at(world_pos: Vector3, radius: float) -> Node:
	var best: Node = null
	var best_dist := radius
	for e in get_tree().get_nodes_in_group("enemies_3d"):
		if not is_instance_valid(e):
			continue
		if e.get("alive") == false:
			continue
		var d: float = WorldCoords3D.distance_xz(e.global_position, world_pos)
		if d <= best_dist:
			best_dist = d
			best = e
	return best
