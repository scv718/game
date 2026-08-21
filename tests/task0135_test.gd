extends SceneTree

## TASK-013-5 Wall/Gate Navigation Stress Regression.
## [설계 결정 반영] 밀폐 사각 엔클로저(160x160)는 이 엔진의 nav-bake가 내부를 폴리곤에서
## 제거해 OPEN여도 내부가 navigable하지 않게 되는 한계가 있다. 따라서 테스트 레이아웃을
## **두 개의 열린 영역(내부=성 안 / 외부=성 밖)을 North Gate corridor로 연결하는
## U자형/열린 레이아웃**으로 재설계했다. 성벽을 완전히 밀폐하지 않으므로 nav-bake가
## 두 영역을 모두 유지한다.
##
## 검증 시나리오 (큐 규칙 유지):
##  1. U자형 성벽 구축 (남쪽 벽 + 서/동 날개).
##  2. North Gate 설치.
##  3. OPEN에서 내부↔외부 nav path (Gate footprint 통과).
##  4. CLOSED에서 passage 차단 (Gate footprint 미통과, 우회).
##  5. Wall 추가/철거 (runtime nav 갱신, stale collision 없음).
##  6. runtime nav rebuild 반복 (Gate toggle, 상태/경로 일관 유지).
##  7. Lumberjack이 Wall을 뚫지 않고 열린 Gate 통로로 외부 Tree 도달 (Worker 2명).
##  8. unreachable Tree는 영구 MOVE stall 없이 안전 처리 (TASK-BUG-NAV-001).
##  9. Miner/Quarry 정상 생산.
## 10. DAY/NIGHT 반복 후 Gate/Worker/Resource state 유지.

enum Phase {
	SETUP, BUILD, NAV_OPEN, NAV_CLOSED, WALL_ADD, WALL_REMOVE, REBUILD_REPEAT,
	WORKER_OPEN, WORKER_CLOSED, POCKET, MINER, DAYNIGHT, DONE
}

const GATE_POS := Vector2(0, -448)
const INSIDE := Vector2(0, -360)
const OUTSIDE := Vector2(0, -560)
const GATE_RECT := Rect2(Vector2(-24, -456), Vector2(48, 16))

# U자형 성벽: 남쪽 벽(y=-300, x -96..96) + 서/동 날개(x=±96, y -300..-640).
const U_X_MIN := -96
const U_X_MAX := 96
const U_Y_SOUTH := -300
const U_Y_TOP := -640

# Wall 추가/철거 barrier (Gate 북쪽, combat field 방향)
const BARRIER := [Vector2(-16, -520), Vector2(0, -520), Vector2(16, -520)]
const BARRIER_RECT := Rect2(Vector2(-24, -528), Vector2(48, 16))

# Worker setup
const LY_POS := Vector2(0, -360)
const TREE_A := Vector2(0, -600)
const TREE_B := Vector2(32, -620)

const NAV_WAIT_PF := 90
const WORKER_REACH_BUDGET := 1500
const WORKER_CLOSED_BUDGET := 2000
const STALL_BUDGET := 1200

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _step_done := false
var _failed := false

var _main: Node = null
var _world: Node = null
var _layout: Node = null
var _placement: Node = null
var _resources: Node = null
var _game_time: Node = null
var _gate: Node = null

var _lj1: Node = null
var _lj2: Node = null
var _ly: Node = null
var _miner: Node = null
var _quarry: Node = null
var _deposit: Node = null
var _barrier_placed := false

var _rebuild_i := 0
var _rebuild_want_open := false
var _rebuild_armed := false

var _worker_stage := -1
var _worker_wait_pf := 0

var _wood_before := 0
var _worker_closed_done := false

var _pocket_tree: Node = null
var _pocket_ly: Node = null
var _pocket_lj: Node = null
var _pocket_wall_removed := false
var _pocket_stage := -1

var _miner_wait_pf := 0
var _stone_before := 0

var _dn_cycle := 0
var _dn_open_at_start := false
var _dn_frame := 0


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
	print("TASK0135_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _find_gate_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("gates"):
		if not is_instance_valid(node):
			continue
		var g := node as Node2D
		if g == null:
			continue
		if (g.position - pos).length_squared() < 1.0:
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


func _path_crosses_rect(path: PackedVector2Array, rect: Rect2) -> bool:
	if path.size() < 2:
		return false
	for i in range(1, path.size()):
		if _segment_in_rect(path[i - 1], path[i], rect):
			return true
	return false


func _path_reaches(a: Vector2, b: Vector2) -> bool:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, a, b, true)
	if path.size() < 2:
		return false
	return path[path.size() - 1].distance_to(b) <= 80.0


func _path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	return NavigationServer2D.map_get_path(nav_map, a, b, true)


## 전체 월드의 기존 Tree를 비활성화해 테스트 커스텀 Tree만 대상이 되게 한다.
func _disable_world_trees() -> void:
	for t in get_nodes_in_group("interactable"):
		t.current_amount = 0
		t.position = Vector2(900, 900)


## U자형 성벽 배치. 남쪽 벽을 밀폐하지 않고(열린 레이아웃), 서/동 날개가
## 북쪽으로 길게 뻗어 내부/외부를 Gate corridor로만 통과하게 하는 형태.
func _build_u_walls() -> void:
	var positions: Array[Vector2] = []
	for x in range(U_X_MIN, U_X_MAX + 1, 16):
		positions.append(Vector2(float(x), float(U_Y_SOUTH)))
	for y in range(U_Y_SOUTH, U_Y_TOP - 1, -16):
		positions.append(Vector2(float(U_X_MIN), float(y)))
		positions.append(Vector2(float(U_X_MAX), float(y)))
	for p in positions:
		_placement._try_place_wall_at(p)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			_main = root.get_node("Main")
			_world = _main.get_node("World")
			_layout = _world.get_node("MapLayout")
			_placement = _main.get_node("BuildingPlacement")
			_resources = root.get_node("VillageResources")
			_game_time = root.get_node("GameTime")
			_check(_world != null and _layout != null and _placement != null \
					and _resources != null and _game_time != null, "core nodes present")
			if _game_time.has_method("set_auto_advance"):
				_game_time.set_auto_advance(false)
			_resources._amounts["wood"] = 100000
			_disable_world_trees()
			_enter(Phase.BUILD)
		Phase.BUILD:
			if not _step_done:
				_step_done = true
				var wall0 := get_nodes_in_group("walls").size()
				_build_u_walls()
				_check(get_nodes_in_group("walls").size() > wall0, "U-shape walls built (%d walls)" % get_nodes_in_group("walls").size())
				_placement._try_place_gate_at(_placement._snap_gate(GATE_POS))
				_gate = _find_gate_at(GATE_POS)
				_check(_gate != null, "north gate installed in corridor")
				if _gate != null:
					_check(_gate.is_closed(), "new gate starts CLOSED")
				_world.rebuild_navigation()
				_pf = 0
			if _pf >= NAV_WAIT_PF:
				_enter(Phase.NAV_OPEN)
		Phase.NAV_OPEN:
			if not _step_done:
				_step_done = true
				_gate.set_open(true)
				_pf = 0
			if _pf >= NAV_WAIT_PF:
				_check(_path_reaches(INSIDE, OUTSIDE), "OPEN: inside->outside nav reachable")
				_check(_path_crosses_rect(_path(INSIDE, OUTSIDE), GATE_RECT), "OPEN: path crosses gate footprint (passage)")
				_enter(Phase.NAV_CLOSED)
		Phase.NAV_CLOSED:
			if not _step_done:
				_step_done = true
				_gate.set_open(false)
				_pf = 0
			if _pf >= NAV_WAIT_PF:
				_check(not _path_crosses_rect(_path(INSIDE, OUTSIDE), GATE_RECT), "CLOSED: path detours (does not cross gate footprint)")
				_enter(Phase.WALL_ADD)
		Phase.WALL_ADD:
			if not _step_done:
				_step_done = true
				_gate.set_open(true)
				_pf = 0
			elif _pf >= NAV_WAIT_PF and not _barrier_placed:
				_barrier_placed = true
				for p in BARRIER:
					_placement._try_place_wall_at(p)
				_world.rebuild_navigation()
				_pf = 0
			elif _pf >= NAV_WAIT_PF and _barrier_placed:
				_check(not _path_crosses_rect(_path(INSIDE, OUTSIDE), BARRIER_RECT), "wall added: path detours (nav updated, no stale)")
				_enter(Phase.WALL_REMOVE)
		Phase.WALL_REMOVE:
			if not _step_done:
				_step_done = true
				_placement._set_remove_mode(true)
				for p in BARRIER:
					_placement._try_remove_wall_at(p)
				_placement._set_remove_mode(false)
				_pf = 0
			if _pf >= NAV_WAIT_PF:
				_check(_path_crosses_rect(_path(INSIDE, OUTSIDE), BARRIER_RECT), "wall removed: path straight again (no stale collision)")
				_enter(Phase.REBUILD_REPEAT)
		Phase.REBUILD_REPEAT:
			if not _rebuild_armed:
				_rebuild_armed = true
				_rebuild_want_open = (_rebuild_i % 2 == 1)
				_gate.set_open(_rebuild_want_open)
				_world.rebuild_navigation()
				_pf = 0
			elif _pf >= NAV_WAIT_PF:
				_check(_collision_disabled() == _gate.is_open(), "rebuild %d: collision state matches is_open" % (_rebuild_i + 1))
				if _gate.is_open():
					_check(_path_reaches(INSIDE, OUTSIDE), "rebuild %d OPEN: passage reachable" % (_rebuild_i + 1))
				else:
					_check(not _path_crosses_rect(_path(INSIDE, OUTSIDE), GATE_RECT), "rebuild %d CLOSED: passage blocked" % (_rebuild_i + 1))
				_rebuild_armed = false
				_rebuild_i += 1
				_pf = 0
				if _rebuild_i >= 6:
					_enter(Phase.WORKER_OPEN)
		Phase.WORKER_OPEN:
			_tick_worker_open()
		Phase.WORKER_CLOSED:
			_tick_worker_closed()
		Phase.POCKET:
			_tick_pocket()
		Phase.MINER:
			_tick_miner()
		Phase.DAYNIGHT:
			_tick_daynight()
		Phase.DONE:
			_finish()
			return true
	if _frame > 400000:
		print("TASK0135_RESULT=TIMEOUT phase=%s worker_stage=%s pocket_stage=%s" % [str(_phase), str(_worker_stage), str(_pocket_stage)])
		quit()
		return true
	return false


# --- Worker phases ---

func _spawn_worker_setup() -> void:
	_gate.set_open(true)
	var ly_scene: PackedScene = load("res://scenes/lumberyard.tscn")
	_ly = ly_scene.instantiate() as Node2D
	_ly.position = LY_POS
	_ly.work_radius = 320.0
	_world.add_child(_ly)
	for tpos in [TREE_A, TREE_B]:
		var tree_scene: PackedScene = load("res://scenes/tree.tscn")
		var tree := tree_scene.instantiate()
		tree.position = tpos
		tree.max_amount = 5
		tree.current_amount = 5
		tree.regrow_time = 1000.0
		_world.add_child(tree)
	var lj_scene: PackedScene = load("res://scenes/lumberjack.tscn")
	_lj1 = lj_scene.instantiate()
	_lj1.position = Vector2(0, -400)
	_world.add_child(_lj1)
	_lj2 = lj_scene.instantiate()
	_lj2.position = Vector2(16, -408)
	_world.add_child(_lj2)
	_world.rebuild_navigation()
	_check(_ly.assign_worker(_lj1), "lumberjack 1 assigned")
	_check(_ly.assign_worker(_lj2), "lumberjack 2 assigned")


func _tick_worker_open() -> void:
	if _worker_stage < 0:
		_worker_stage = 0
		_spawn_worker_setup()
		_worker_wait_pf = 0
	elif _worker_stage == 0:
		# Gate OPEN: 두 lumberjack이 벽을 뚫지 않고 열린 Gate 통로로 외부 Tree 도달.
		_worker_wait_pf += 1
		if _lj1.state == 3 and _lj2.state == 3:
			_check(true, "both lumberjacks reached outside trees through OPEN gate (states %d/%d)" % [_lj1.state, _lj2.state])
			_check(_lj1.global_position.y < -448.0 and _lj2.global_position.y < -448.0, "lumberjacks moved north of gate (did not tunnel through walls)")
			_enter(Phase.WORKER_CLOSED)
		elif _worker_wait_pf >= WORKER_REACH_BUDGET:
			_check(false, "lumberjacks never reached trees through OPEN gate (states %d/%d pos %s/%s)" % [_lj1.state, _lj2.state, _lj1.global_position, _lj2.global_position])
			_enter(Phase.WORKER_CLOSED)


## Gate CLOSED에서도 Worker가 영구 MOVE stall 없이 (우회 경로로) 작업을 계속한다.
func _tick_worker_closed() -> void:
	if _worker_stage == 0:
		_worker_stage = 1
		_check(is_instance_valid(_lj1) and is_instance_valid(_lj2), "worker nodes valid (no freed reference)")
		_gate.set_open(false)
		_world.rebuild_navigation()
		_wood_before = _resources.get_amount("wood")
		_worker_wait_pf = 0
	elif _worker_stage == 1:
		_worker_wait_pf += 1
		var wood: int = _resources.get_amount("wood")
		if wood > _wood_before:
			_check(true, "no permanent MOVE stall with CLOSED gate: worker deposited wood (%d -> %d) states %d/%d" % [_wood_before, wood, _lj1.state, _lj2.state])
			_worker_closed_done = true
			_enter(Phase.POCKET)
		elif _worker_wait_pf >= WORKER_CLOSED_BUDGET:
			_check(false, "worker never deposited with CLOSED gate (states %d/%d pos %s/%s)" % [_lj1.state, _lj2.state, _lj1.global_position, _lj2.global_position])
			_enter(Phase.POCKET)


func _tick_pocket() -> void:
	if _pocket_stage < 0:
		_pocket_stage = 0
		# 별도 밀폐 포켓: 트리를 4벽으로 막아 unreachable (TASK-BUG-NAV-001).
		# 포켓 중심(520,-160), 트리(520,-144), 벽 N(520,-176)/S(520,-112)/W(504,-144)/E(536,-144).
		# 주 Worker(_ly @ (0,-360), radius 320)의 탐색 범위 밖에 두어 포켓 트리를 빼앗지 않게 한다.
		var base := Vector2(520, -160)
		_pocket_tree = (load("res://scenes/tree.tscn") as PackedScene).instantiate()
		_pocket_tree.position = base + Vector2(0, 16)
		_pocket_tree.max_amount = 5
		_pocket_tree.current_amount = 5
		_pocket_tree.regrow_time = 1000.0
		_world.add_child(_pocket_tree)
		for offset in [Vector2(0, -16), Vector2(0, 48), Vector2(-16, 16), Vector2(16, 16)]:
			_placement._try_place_wall_at(base + offset)
		_pocket_ly = (load("res://scenes/lumberyard.tscn") as PackedScene).instantiate() as Node2D
		_pocket_ly.position = base + Vector2(0, -64)
		_pocket_ly.work_radius = 200.0
		_world.add_child(_pocket_ly)
		_pocket_lj = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
		_pocket_lj.position = base + Vector2(0, -96)
		_world.add_child(_pocket_lj)
		_world.rebuild_navigation()
		_check(_pocket_ly.assign_worker(_pocket_lj), "pocket lumberjack assigned")
		_worker_wait_pf = 0
	elif _pocket_stage == 0:
		_worker_wait_pf += 1
		if _worker_wait_pf >= 300:
			# 밀폐 포켓의 트리는 unreachable → Worker는 영구 MOVE stall 없이 안전 처리해야 한다.
			# (find_tree가 nav path 없는 Tree를 skip하므로 IDLE/FIND를 오가며 stall 없음)
			var stalled: bool = (_pocket_lj.state == 2)
			_check(not stalled, "pocket: unreachable sealed tree -> no permanent MOVE stall (state=%d pos=%s)" % [_pocket_lj.state, _pocket_lj.global_position])
			_pocket_stage = 1
			_pf = 0
	elif _pocket_stage == 1:
		if not _pocket_wall_removed:
			_pocket_wall_removed = true
			# 북쪽 벽(520,-176) 제거 → 포켓이 열려 트리 reachable.
			_placement._set_remove_mode(true)
			_placement._try_remove_wall_at(Vector2(520, -176))
			_placement._set_remove_mode(false)
			_world.rebuild_navigation()
			_worker_wait_pf = 0
		else:
			_worker_wait_pf += 1
			if _worker_wait_pf >= 100:
				_check(_path_reaches(_pocket_lj.global_position, _pocket_tree.global_position), "pocket: after wall removed, tree reachable (no stale collision)")
				_pocket_stage = 2
				_pf = 0
	elif _pocket_stage == 2:
		# 이제 트리가 열려 reachable -> lumberjack이 도달해 채집/반납 (regrow/claim도 함께 확인).
		if _pocket_lj.state == 3:
			_check(true, "pocket: lumberjack reached opened tree (state=3, no stale collision)")
			_pocket_stage = 3
		elif _worker_wait_pf >= 1200:
			_check(_pocket_lj.state == 3, "pocket: lumberjack should reach opened tree (state=%d)" % _pocket_lj.state)
			_pocket_stage = 3
		else:
			_worker_wait_pf += 1
	elif _pocket_stage == 3:
		_enter(Phase.MINER)


func _tick_miner() -> void:
	if _miner_wait_pf < 0:
		return
	if _miner == null:
		_deposit = get_nodes_in_group("stone_deposits")[0] if get_nodes_in_group("stone_deposits").size() > 0 else null
		_check(_deposit != null, "stone deposit present")
		if _deposit == null:
			_enter(Phase.DAYNIGHT)
			return
		_placement._try_place_quarry_at(_deposit.global_position)
		_quarry = get_nodes_in_group("quarries")[0] if get_nodes_in_group("quarries").size() > 0 else null
		_check(_quarry != null, "quarry built on deposit")
		_miner = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
		_miner.position = _deposit.global_position + Vector2(0, 80)
		_world.add_child(_miner)
		_world.rebuild_navigation()
		_check(_quarry != null and _quarry.assign_worker(_miner), "miner assigned to quarry")
		_stone_before = _resources.get_amount("stone")
		_miner_wait_pf = 0
	else:
		_miner_wait_pf += 1
		if _resources.get_amount("stone") > _stone_before:
			_check(true, "miner/ quarry production normal (stone %d -> %d)" % [_stone_before, _resources.get_amount("stone")])
			_miner_wait_pf = -1
			_enter(Phase.DAYNIGHT)
		elif _miner_wait_pf >= 2000:
			_check(false, "miner/ quarry production within timeout (stone=%d)" % _resources.get_amount("stone"))
			_miner_wait_pf = -1
			_enter(Phase.DAYNIGHT)


func _tick_daynight() -> void:
	if _dn_cycle == 0:
		_dn_open_at_start = _gate.is_open()
		_check(_game_time.get_phase() == _game_time.Phase.DAY, "game starts in DAY")
		_game_time.set_durations(10.0, 10.0)
		_dn_cycle = 1
		_dn_frame = 0
		_game_time.advance(10.0)
		return
	if _dn_cycle > 4:
		_enter(Phase.DONE)
		return
	_dn_frame += 1
	if _dn_frame < 12:
		return
	var expected_day := (_dn_cycle % 2 == 0)
	_check(_game_time.get_phase() == (_game_time.Phase.DAY if expected_day else _game_time.Phase.NIGHT), "day/night cycle %d phase correct (expect %s, got %s)" % [_dn_cycle, "DAY" if expected_day else "NIGHT", _game_time.get_phase_name()])
	_check(_gate.is_open() == _dn_open_at_start, "gate state persists across day/night (cycle %d)" % _dn_cycle)
	if _ly != null:
		_check(is_instance_valid(_ly), "worker workplace stable across day/night (cycle %d)" % _dn_cycle)
	if _quarry != null:
		_check(is_instance_valid(_quarry), "quarry stable across day/night (cycle %d)" % _dn_cycle)
	_dn_cycle += 1
	_dn_frame = 0
	_game_time.advance(10.0)


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)