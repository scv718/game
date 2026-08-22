extends SceneTree

## TASK-013-4 Gate OPEN/CLOSED + Collision/Navigation 자동 검증.
##  - 신규 Gate는 CLOSED로 시작.
##  - CLOSED: passage collision 활성(CollisionShape2D 존재), nav가 Gate를 통과하지 않음,
##            Player 물리 통과 불가.
##  - OPEN: passage collision 비활성(CollisionShape2D 제거), nav가 Gate를 통과 가능,
##           Player 통과 가능.
##  - 공개 API(is_open/set_open/set_closed/toggle + gate_state_changed signal) 확인.
##  - 반복 toggle에서 collision/nav 오류 누적 없음(상태/경로 일관 유지, signal 중복 없음).
##  - Worker nav가 반복 toggle 후에도 정상 동작(영구 MOVE stall 없음).
##
## nav 검증: 열린 지형에서 CLOSED Gate는 nav 경로가 Gate footprint를 가로지르지 못하게 하고
## (우회), OPEN이면 가로지를 수 있게 한다(직통). 이 엔진의 nav bake는 CollisionShape2D
## disabled/collision_layer를 무시하므로 Gate는 shape 노드 존재 여부로 open/closed를 반영한다.

enum Phase { SETUP, CLOSED_NAV, CLOSED_PHYSICS, OPEN_NAV, OPEN_PHYSICS, TOGGLE_REPEAT, WORKER, DONE }

const NORTH_GATE := Vector2(0, -448)
const INSIDE := Vector2(0, -360)
const OUTSIDE := Vector2(0, -560)
const GATE_RECT := Rect2(Vector2(-24, -456), Vector2(48, 16))
const PHYSICS_HOLD_PF := 60
const NAV_WAIT_PF := 60
const WORKER_REACH_BUDGET := 500
const WORKER_TOGGLE_BUDGET := 900

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _step_done := false
var _failed := false

var _world: Node = null
var _placement: Node = null
var _resources: Node = null
var _player: CharacterBody2D = null
var _gate: Node = null

var _signal_count := 0
var _open_sig0 := 0

var _toggle_i := 0
var _toggle_armed := false
var _toggle_sig0 := 0

var _worker: Node = null
var _worker_ly: Node = null
var _worker_tree: Node = null
var _worker_stage := -1
var _worker_toggle_i := 0
var _worker_toggle_armed := false
var _worker_toggle_sig0 := 0
var _worker_want_open := true


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_phase_start = _frame
	_step_done = false


func _elapsed() -> int:
	return _frame - _phase_start


func _finish() -> void:
	print("TASK0134_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _on_gate_signal(_gate: Node, _open: bool) -> void:
	_signal_count += 1


func _find_gate_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("gates"):
		if not is_instance_valid(node):
			continue
		var gate := node as Node2D
		if gate == null:
			continue
		if (gate.position - pos).length_squared() < 1.0:
			return node
	return null


func _collision_disabled() -> bool:
	return _gate.get_node_or_null("CollisionShape2D") == null


func _cross(p: Vector2, q: Vector2, r: Vector2) -> float:
	return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)


func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var o1 := _cross(a, b, c)
	var o2 := _cross(a, b, d)
	var o3 := _cross(c, d, a)
	var o4 := _cross(c, d, b)
	return ((o1 > 0.0 and o2 < 0.0) or (o1 < 0.0 and o2 > 0.0)) \
		and ((o3 > 0.0 and o4 < 0.0) or (o3 < 0.0 and o4 > 0.0))


func _segment_in_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var edges: Array = [
		[rect.position, rect.position + Vector2(rect.size.x, 0.0)],
		[rect.position + Vector2(rect.size.x, 0.0), rect.end],
		[rect.end, rect.position + Vector2(0.0, rect.size.y)],
		[rect.position + Vector2(0.0, rect.size.y), rect.position],
	]
	for edge in edges:
		if _segments_cross(a, b, edge[0], edge[1]):
			return true
	return false


## nav 경로가 Gate footprint(GATE_RECT)를 가로지르는지.
## CLOSED면 우회해 false, OPEN이면 통과해 true가 되어야 한다.
func _path_crosses_gate() -> bool:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, INSIDE, OUTSIDE, true)
	if path.size() < 2:
		return false
	for i in range(1, path.size()):
		if _segment_in_rect(path[i - 1], path[i], GATE_RECT):
			return true
	return false


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			var game_time: Node = root.get_node("GameTime")
			if game_time != null and game_time.has_method("set_auto_advance"):
				game_time.set_auto_advance(false)
			_world = root.get_node("Main").get_node("World")
			_placement = root.get_node("Main").get_node("BuildingPlacement")
			_resources = root.get_node("VillageResources")
			_player = root.get_node("Main").get_node("Player") as CharacterBody2D
			_check(_world != null and _placement != null and _resources != null and _player != null, "core nodes present")
			_resources._amounts["wood"] = 10000
			_placement._set_building_type("gate")
			_placement._try_place_gate_at(_placement._snap_gate(NORTH_GATE))
			_gate = _find_gate_at(NORTH_GATE)
			_check(_gate != null, "north gate placed")
			if _gate != null:
				if not _gate.gate_state_changed.is_connected(_on_gate_signal):
					_gate.gate_state_changed.connect(_on_gate_signal)
				var gi: Node = _gate.get_node_or_null("Interact")
				_check(gi != null and gi is Interactable, "gate has Interactable for player toggle")
				_check(gi != null and gi.prompt != "", "gate interact prompt set")
			_enter(Phase.CLOSED_NAV)
		Phase.CLOSED_NAV:
			if not _step_done:
				_step_done = true
				_check(_gate.is_closed(), "new gate starts CLOSED")
				_check(not _collision_disabled(), "CLOSED gate passage collision active (CollisionShape2D present)")
				_check(_gate.has_method("is_open"), "public API is_open present")
				_check(_gate.has_method("set_open"), "public API set_open present")
				_check(_gate.has_method("set_closed"), "public API set_closed present")
				_check(_gate.has_method("toggle"), "public API toggle present")
				_check(_gate.has_signal("gate_state_changed"), "public signal gate_state_changed present")
				_pf = 0
			elif _pf >= NAV_WAIT_PF:
				_check(not _path_crosses_gate(), "CLOSED gate: nav path detours (does not cross gate footprint)")
				_enter(Phase.CLOSED_PHYSICS)
		Phase.CLOSED_PHYSICS:
			if not _step_done:
				_step_done = true
				# Player는 더 이상 WASD로 이동하지 않으므로(TASK-CTRL-001-1) 물리 통과 여부를
				# CharacterBody2D.test_move로 검증한다. CLOSED면 게이트 collision에 막혀야 한다.
				_player.global_position = Vector2(0, -400)
				_pf = 0
			elif _pf >= NAV_WAIT_PF:
				var blocked: bool = _player.test_move(Transform2D(0, Vector2(0, -400)), Vector2(0, -60))
				_check(blocked, "CLOSED gate blocks player physics (test_move)")
				_check(_player.global_position.y == -400.0, "CLOSED gate: player body not teleported (y=%.0f)" % _player.global_position.y)
				_enter(Phase.OPEN_NAV)
		Phase.OPEN_NAV:
			if not _step_done:
				_step_done = true
				_open_sig0 = _signal_count
				_gate.set_open(true)
				_pf = 0
			elif _pf >= NAV_WAIT_PF:
				_check(_signal_count == _open_sig0 + 1, "set_open emits exactly one gate_state_changed")
				_check(_gate.is_open(), "gate OPEN after set_open(true)")
				_check(_collision_disabled(), "OPEN gate passage collision inactive (CollisionShape2D removed)")
				_check(_path_crosses_gate(), "OPEN gate: nav path crosses gate footprint (passage open)")
				_enter(Phase.OPEN_PHYSICS)
		Phase.OPEN_PHYSICS:
			if not _step_done:
				_step_done = true
				_player.global_position = Vector2(0, -400)
				_pf = 0
			elif _pf >= NAV_WAIT_PF:
				var blocked: bool = _player.test_move(Transform2D(0, Vector2(0, -400)), Vector2(0, -60))
				_check(not blocked, "OPEN gate allows player through (test_move)")
				_enter(Phase.TOGGLE_REPEAT)
		Phase.TOGGLE_REPEAT:
			if not _toggle_armed:
				_toggle_armed = true
				_toggle_sig0 = _signal_count
				var want_open := (_toggle_i % 2 == 1)
				# 1번째 토글은 Player 상호작용 경로(Interact.interact)로 수행해 prototype toggle 검증.
				if _toggle_i == 0:
					var gi: Node = _gate.get_node_or_null("Interact")
					_check(gi != null and gi.has_method("interact"), "gate Interact exposes interact() for player")
					if gi != null:
						gi.interact(_player)
				else:
					_gate.set_open(want_open)
				_pf = 0
			elif _pf >= NAV_WAIT_PF:
				_check(_signal_count == _toggle_sig0 + 1, "toggle %d emits exactly one gate_state_changed" % (_toggle_i + 1))
				_check(_collision_disabled() == _gate.is_open(), "toggle %d collision state matches is_open" % (_toggle_i + 1))
				if _gate.is_open():
					_check(_path_crosses_gate(), "toggle %d OPEN nav passable" % (_toggle_i + 1))
				else:
					_check(not _path_crosses_gate(), "toggle %d CLOSED nav blocked" % (_toggle_i + 1))
				_toggle_armed = false
				_toggle_i += 1
				_pf = 0
				if _toggle_i >= 6:
					_enter(Phase.WORKER)
		Phase.WORKER:
			if _worker_stage < 0:
				_worker_stage = 0
				_gate.set_open(true)
				_pf = 0
			elif _worker_stage == 0:
				if _worker == null:
					var ly_scene: PackedScene = load("res://scenes/lumberyard.tscn")
					_worker_ly = ly_scene.instantiate() as Node2D
					_worker_ly.position = Vector2(0, -300)
					_worker_ly.work_radius = 900.0
					_world.add_child(_worker_ly)
					var tree_scene: PackedScene = load("res://scenes/tree.tscn")
					_worker_tree = tree_scene.instantiate()
					_worker_tree.position = Vector2(0, -560)
					_worker_tree.max_amount = 1
					_worker_tree.current_amount = 1
					_worker_tree.regrow_time = 1.0
					_world.add_child(_worker_tree)
					var lj_scene: PackedScene = load("res://scenes/lumberjack.tscn")
					_worker = lj_scene.instantiate()
					_worker.position = Vector2(0, -360)
					_world.add_child(_worker)
					_world.rebuild_navigation()
					_check(_worker_ly.assign_worker(_worker), "worker assigned to lumberyard")
					_pf = 0
				elif _worker.state == 3:
					_check(true, "worker reaches outside tree through OPEN gate (state=%d)" % _worker.state)
					_worker_stage = 1
					_worker_toggle_i = 0
					_worker_want_open = false
					_pf = 0
				elif _pf >= WORKER_REACH_BUDGET:
					_check(false, "worker never reached tree through OPEN gate (state=%d pos=%s)" % [_worker.state, _worker.global_position])
					_worker_stage = 3
			elif _worker_stage == 1:
				if not _worker_toggle_armed:
					_worker_toggle_armed = true
					_worker_toggle_sig0 = _signal_count
					_gate.set_open(_worker_want_open)
					_pf = 0
				elif _pf >= NAV_WAIT_PF:
					_check(_signal_count == _worker_toggle_sig0 + 1, "worker-phase toggle %d emits exactly one gate_state_changed" % (_worker_toggle_i + 1))
					_check(_collision_disabled() == _gate.is_open(), "worker-phase toggle %d collision matches state" % (_worker_toggle_i + 1))
					_worker_toggle_armed = false
					_worker_toggle_i += 1
					_worker_want_open = not _worker_want_open
					_pf = 0
					if _worker_toggle_i >= 4:
						_worker_stage = 2
						_pf = 0
			elif _worker_stage == 2:
				if _worker.state == 3:
					_check(true, "worker reaches tree again after repeated gate toggles (state=3)")
					_worker_stage = 3
				elif _pf >= WORKER_TOGGLE_BUDGET:
					_check(false, "worker stalled after repeated gate toggles (state=%d pos=%s)" % [_worker.state, _worker.global_position])
					_worker_stage = 3
			elif _worker_stage == 3:
				_check(is_instance_valid(_worker), "worker node valid (no freed reference)")
				_check(_gate.is_open(), "gate OPEN at end of worker phase")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 40000:
		print("TASK0134_RESULT=TIMEOUT phase=%s worker_stage=%s" % [str(_phase), str(_worker_stage)])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)