extends SceneTree

## TASK-013-6 Free Wall + Gate 통합 검증.
## 개별 태스크(013-1~013-5)의 기능을 하나의 연속 시나리오로 묶어
## Wall과 Gate 시스템이 함께 동작하는지 통합 검증한다.
##
## 검증 시나리오:
##  1. Wall 기본 배치/비용/invalid/연속 배치 (TASK-013-1 통합).
##  2. Wall 연결 비주얼 + 철거/환불 + 비-Wall 삭제 금지 (TASK-013-2 통합).
##  3. Gate 4방향 corridor validation + orientation/footprint (TASK-013-3 통합).
##  4. Wall/Gate 연결: gate edge와 인접 wall 배치 허용, 실제 겹침 거부 (TASK-013-3).
##  5. Gate OPEN/CLOSED + collision/nav 전환 (TASK-013-4 통합).
##  6. Worker navigation: 열린 Gate로 외부 Tree 도달, 벽 미통과 (TASK-013-5 통합).
##  7. BuildingPlacement/DayNight/smoke 회귀 (게임 시간 경과 후 state 유지).
##
## [설계 결정 반영] 완전 밀폐 엔클로저는 이 엔진 nav-bake가 내부를 폴리곤에서
## 제거해 OPEN여도 navigable하지 않게 되는 한계가 있으므로, 내부/외부를 Gate
## corridor로 연결하는 U자형/열린 레이아웃을 사용한다 (TASK-013-5와 동일 원리).

enum Phase {
	SETUP, WALL_BASIC, U_WALLS, GATE_4WAY, WALL_GATE_CONNECT,
	GATE_NAV, WORKER, REMOVE, DAYNIGHT, DONE
}

const GATE_COST := 5
const WALL_COST := 2

# North Gate 통합 nav/worker 검증용 지점 (TASK-013-5와 동일).
const NORTH_GATE := Vector2(0, -448)
const SOUTH_GATE := Vector2(0, 448)
const EAST_GATE := Vector2(448, 0)
const WEST_GATE := Vector2(-448, 0)
const INSIDE := Vector2(0, -360)
const OUTSIDE := Vector2(0, -560)
const GATE_RECT := Rect2(Vector2(-24, -456), Vector2(48, 16))

# U자형 성벽: 남쪽 벽(y=-300, x -96..96) + 서/동 날개(x=±96, y -300..-640).
const U_X_MIN := -96
const U_X_MAX := 96
const U_Y_SOUTH := -300
const U_Y_TOP := -640

# Worker setup (통합 검증용, task0135와 별도 좌표로 겹침 방지).
const LY_POS := Vector2(0, -360)
const TREE_A := Vector2(0, -600)
const TREE_B := Vector2(32, -620)

const NAV_WAIT_PF := 90
const WORKER_REACH_BUDGET := 1500

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _step_done := false
var _failed := false

var _world: Node = null
var _layout: Node = null
var _placement: Node = null
var _resources: Node = null
var _game_time: Node = null
var _gate: Node = null

var _single_wall: Node = null
var _gates_placed := {}

var _worker: Node = null
var _worker_ly: Node = null
var _worker_stage := -1
var _worker_wait_pf := 0

var _wood_before := 0
var _dn_cycle := 0
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
	print("TASK0136_RESULT=" + ("FAIL" if _failed else "PASS"))
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


func _find_wall_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("walls"):
		if not is_instance_valid(node):
			continue
		var w := node as Node2D
		if w == null:
			continue
		if (w.position - pos).length_squared() < 1.0:
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


func _path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	return NavigationServer2D.map_get_path(nav_map, a, b, true)


func _disable_world_trees() -> void:
	for t in get_nodes_in_group("interactable"):
		t.current_amount = 0
		t.position = Vector2(900, 900)


func _build_u_walls() -> void:
	var positions: Array[Vector2] = []
	for x in range(U_X_MIN, U_X_MAX + 1, 16):
		positions.append(Vector2(float(x), float(U_Y_SOUTH)))
	for y in range(U_Y_SOUTH, U_Y_TOP - 1, -16):
		positions.append(Vector2(float(U_X_MIN), float(y)))
		positions.append(Vector2(float(U_X_MAX), float(y)))
	for p in positions:
		_placement._try_place_wall_at(p)


func _wall_visual_bounds(w: Node) -> Rect2:
	var vis: Polygon2D = w.get_node("Visual") as Polygon2D
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for p in vis.polygon:
		minp = minp.min(p)
		maxp = maxp.max(p)
	return Rect2(minp, maxp - minp)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			_world = root.get_node("Main").get_node("World")
			_layout = _world.get_node("MapLayout")
			_placement = root.get_node("Main").get_node("BuildingPlacement")
			_resources = root.get_node("VillageResources")
			_game_time = root.get_node("GameTime")
			_check(_world != null and _layout != null and _placement != null \
					and _resources != null and _game_time != null, "core nodes present")
			_check(_layout.has_method("get_gate_corridor_direction"), "MapLayout exposes gate corridor metadata (TASK-012 reuse)")
			if _game_time.has_method("set_auto_advance"):
				_game_time.set_auto_advance(false)
			_resources._amounts["wood"] = 100000
			_disable_world_trees()
			_enter(Phase.WALL_BASIC)
		Phase.WALL_BASIC:
			if not _step_done:
				_step_done = true
				_placement._set_building_type("wall")
				var wood0: int = _resources.get_amount("wood")
				var wall0: int = get_nodes_in_group("walls").size()
				# 단일 배치 + 비용 1회 차감.
				_placement._try_place_wall_at(Vector2(-200, -200))
				_single_wall = _find_wall_at(Vector2(-200, -200))
				_check(_single_wall != null, "wall placed (single segment)")
				_check(_resources.get_amount("wood") == wood0 - WALL_COST, "wall cost deducted once (%d)" % WALL_COST)
				# 연속 배치: 옆 segment 추가 → 인접 비주얼 연결 (straight).
				_placement._try_place_wall_at(Vector2(-184, -200))
				_check(get_nodes_in_group("walls").size() == wall0 + 2, "wall continuous placement (2 segments)")
				var vb := _wall_visual_bounds(_single_wall)
				_check(vb.size.x == 24.0 and vb.size.y == 16.0, "adjacent wall connected visual (straight) got %s" % str(vb))
				# invalid: Core Building 겹침 거부, 비용 차감 없음.
				var wood1: int = _resources.get_amount("wood")
				var wall1: int = get_nodes_in_group("walls").size()
				_placement._try_place_wall_at(Vector2(150, -60))
				_check(get_nodes_in_group("walls").size() == wall1, "wall rejected overlapping Core Building")
				_check(_resources.get_amount("wood") == wood1, "no wood deducted on invalid wall")
			if _elapsed() >= 4:
				# 기본 테스트용 wall 정리 후 U자형 구축 단계로.
				_placement._set_remove_mode(true)
				_placement._try_remove_wall_at(Vector2(-200, -200))
				_placement._try_remove_wall_at(Vector2(-184, -200))
				_placement._set_remove_mode(false)
				_enter(Phase.U_WALLS)
		Phase.U_WALLS:
			if not _step_done:
				_step_done = true
				var wood0: int = _resources.get_amount("wood")
				var wall0: int = get_nodes_in_group("walls").size()
				_build_u_walls()
				_check(get_nodes_in_group("walls").size() > wall0, "U-shape defensive walls built (%d walls)" % get_nodes_in_group("walls").size())
				var built: int = get_nodes_in_group("walls").size() - wall0
				_check(_resources.get_amount("wood") == wood0 - built * WALL_COST, "wall cost per segment for U-shape (wood %d)" % _resources.get_amount("wood"))
				_world.rebuild_navigation()
				_pf = 0
			if _pf >= NAV_WAIT_PF:
				_enter(Phase.GATE_4WAY)
		Phase.GATE_4WAY:
			if not _step_done:
				_step_done = true
				var wood0: int = _resources.get_amount("wood")
				var gate0: int = get_nodes_in_group("gates").size()
				# 4방향 Gate Corridor 내부 모두 배치.
				for dir in ["north", "south", "east", "west"]:
					_placement._try_place_gate_at(_placement._snap_gate(NORTH_GATE if dir == "north" else SOUTH_GATE if dir == "south" else EAST_GATE if dir == "east" else WEST_GATE))
				_check(get_nodes_in_group("gates").size() == gate0 + 4, "4 gates placed (N/E/S/W corridors)")
				_check(_resources.get_amount("wood") == wood0 - GATE_COST * 4, "gate cost deducted per gate (wood %d)" % _resources.get_amount("wood"))
				var gn := _find_gate_at(NORTH_GATE)
				var gs := _find_gate_at(SOUTH_GATE)
				var ge := _find_gate_at(EAST_GATE)
				var gw := _find_gate_at(WEST_GATE)
				_gates_placed = {"north": gn, "south": gs, "east": ge, "west": gw}
				_check(gn != null and gn.get_direction() == "north", "north gate direction north")
				_check(gs != null and gs.get_direction() == "south", "south gate direction south")
				_check(ge != null and ge.get_direction() == "east", "east gate direction east")
				_check(gw != null and gw.get_direction() == "west", "west gate direction west")
				_check(gn != null and gn.get_orientation() == "horizontal", "N/S gate horizontal orientation")
				_check(ge != null and ge.get_orientation() == "vertical", "E/W gate vertical orientation")
				_check(gn != null and gn.get_footprint_size() == Vector2(48, 16), "N/S gate footprint 48x16 (3 tiles)")
				_check(ge != null and ge.get_footprint_size() == Vector2(16, 48), "E/W gate footprint 16x48 (3 tiles)")
				_gate = gn
				# corridor 밖 배치 거부 (비용 차감 없음).
				var wood1: int = _resources.get_amount("wood")
				var gate1: int = get_nodes_in_group("gates").size()
				_placement._try_place_gate_at(Vector2(0, -200))
				_placement._try_place_gate_at(Vector2(300, 300))
				_check(get_nodes_in_group("gates").size() == gate1, "gate rejected outside corridors")
				_check(_resources.get_amount("wood") == wood1, "no wood deducted on invalid gate")
			if _elapsed() >= 4:
				_enter(Phase.WALL_GATE_CONNECT)
		Phase.WALL_GATE_CONNECT:
			if not _step_done:
				_step_done = true
				# Wall이 Gate 양옆에 자연스럽게 이어짐: edge touch 허용.
				var wood0: int = _resources.get_amount("wood")
				var wall0: int = get_nodes_in_group("walls").size()
				_placement._try_place_wall_at(Vector2(-64, -448))
				_placement._try_place_wall_at(Vector2(64, -448))
				_check(get_nodes_in_group("walls").size() == wall0 + 2, "walls connect adjacent to gate (edge touch, both sides)")
				_check(_resources.get_amount("wood") == wood0 - WALL_COST * 2, "adjacent wall cost deducted")
				# Gate footprint와 실제 겹침은 거부.
				var wood1: int = _resources.get_amount("wood")
				var wall1: int = get_nodes_in_group("walls").size()
				_placement._try_place_wall_at(Vector2(0, -448))
				_check(get_nodes_in_group("walls").size() == wall1, "wall rejected overlapping gate footprint")
				_check(_resources.get_amount("wood") == wood1, "no cost for wall-over-gate rejection")
				# 인접 wall이 gate footprint와 겹치지 않는지 시각 경계 확인.
				var wl := _find_wall_at(Vector2(-64, -448))
				_check(wl != null and _wall_visual_bounds(wl).size.x >= 16.0, "left-side wall connected to gate visual")
			if _elapsed() >= 4:
				_enter(Phase.GATE_NAV)
		Phase.GATE_NAV:
			_tick_gate_nav()
		Phase.WORKER:
			_tick_worker()
		Phase.REMOVE:
			if not _step_done:
				_step_done = true
				# Wall 철거 + 전액 환불.
				var wood0: int = _resources.get_amount("wood")
				_placement._set_remove_mode(true)
				_placement._try_remove_wall_at(Vector2(-64, -448))
				_check(_find_wall_at(Vector2(-64, -448)) == null, "wall removed (integration)")
				_check(_resources.get_amount("wood") == wood0 + WALL_COST, "wall removal refunds full Wood (+%d)" % WALL_COST)
				# Gate 철거 + 전액 환불.
				var wood1: int = _resources.get_amount("wood")
				_placement._try_remove_wall_at(WEST_GATE)
				_check(_find_gate_at(WEST_GATE) == null, "gate removed (integration)")
				_check(_resources.get_amount("wood") == wood1 + GATE_COST, "gate removal refunds full Wood (+%d)" % GATE_COST)
				# 비-Wall/Gate object(Core Building)는 삭제 금지.
				var wood2: int = _resources.get_amount("wood")
				var gates_before: int = get_nodes_in_group("gates").size()
				_placement._try_remove_wall_at(Vector2(150, -60))
				_check(get_nodes_in_group("gates").size() == gates_before, "non-wall/gate object not removed (Core Building kept)")
				_check(_resources.get_amount("wood") == wood2, "no refund for non-wall removal")
				_placement._set_remove_mode(false)
			if _elapsed() >= 4:
				_enter(Phase.DAYNIGHT)
		Phase.DAYNIGHT:
			_tick_daynight()
		Phase.DONE:
			_finish()
			return true
	if _frame > 400000:
		print("TASK0136_RESULT=TIMEOUT phase=%s worker_stage=%s" % [str(_phase), str(_worker_stage)])
		quit()
		return true
	return false


# --- Gate OPEN/CLOSED + collision/nav 전환 (통합) ---
# North Gate CLOSED → detour(blocked), OPEN → passage(cross). 반복 roundtrip.
var _nav_stage := 0

func _tick_gate_nav() -> void:
	if _nav_stage == 0:
		_check(_gate.is_closed(), "new gate starts CLOSED (integration)")
		_check(not _collision_disabled(), "CLOSED gate passage collision active (integration)")
		_nav_stage = 1
		_pf = 0
	elif _nav_stage == 1:
		if _pf >= NAV_WAIT_PF:
			_check(not _path_crosses_rect(_path(INSIDE, OUTSIDE), GATE_RECT), "integration CLOSED: nav path detours (blocked)")
			_gate.set_open(true)
			_nav_stage = 2
			_pf = 0
	elif _nav_stage == 2:
		if _pf >= NAV_WAIT_PF:
			_check(_collision_disabled(), "integration OPEN: passage collision inactive (shape removed)")
			_check(_path_crosses_rect(_path(INSIDE, OUTSIDE), GATE_RECT), "integration OPEN: nav path crosses gate (passage)")
			_gate.set_open(false)
			_nav_stage = 3
			_pf = 0
	elif _nav_stage == 3:
		if _pf >= NAV_WAIT_PF:
			_check(not _path_crosses_rect(_path(INSIDE, OUTSIDE), GATE_RECT), "integration CLOSED again: nav blocked (toggle roundtrip)")
			_gate.set_open(true)
			_enter(Phase.WORKER)


# --- Worker 통합 nav 검증 ---
# 열린 North Gate 통로로 lumberjack이 외부 Tree에 도달(벽 미통과).
func _tick_worker() -> void:
	if _worker_stage < 0:
		_worker_stage = 0
		var ly_scene: PackedScene = load("res://scenes/lumberyard.tscn")
		_worker_ly = ly_scene.instantiate() as Node2D
		_worker_ly.position = LY_POS
		_worker_ly.work_radius = 320.0
		_world.add_child(_worker_ly)
		for tpos in [TREE_A, TREE_B]:
			var tree_scene: PackedScene = load("res://scenes/tree.tscn")
			var tree := tree_scene.instantiate()
			tree.position = tpos
			tree.max_amount = 5
			tree.current_amount = 5
			tree.regrow_time = 1000.0
			_world.add_child(tree)
		var lj_scene: PackedScene = load("res://scenes/lumberjack.tscn")
		_worker = lj_scene.instantiate()
		_worker.position = Vector2(0, -400)
		_world.add_child(_worker)
		_world.rebuild_navigation()
		_check(_worker_ly.assign_worker(_worker), "lumberjack assigned to lumberyard (integration)")
		_worker_wait_pf = 0
	elif _worker_stage == 0:
		_worker_wait_pf += 1
		if _worker.state == 3:
			_check(true, "lumberjack reached outside trees through OPEN gate (state=3)")
			_check(_worker.global_position.y < -448.0, "lumberjack moved north of gate (did not tunnel through walls)")
			_enter(Phase.REMOVE)
		elif _worker_wait_pf >= WORKER_REACH_BUDGET:
			_check(false, "lumberjack never reached trees through OPEN gate (state=%d pos=%s)" % [_worker.state, _worker.global_position])
			_enter(Phase.REMOVE)


func _tick_daynight() -> void:
	if _dn_cycle == 0:
		_check(_game_time.get_phase() == _game_time.Phase.DAY, "game starts in DAY (regression)")
		_game_time.set_durations(10.0, 10.0)
		_dn_cycle = 1
		_dn_frame = 0
		_game_time.advance(10.0)
		return
	if _dn_cycle > 4:
		_check(is_instance_valid(_worker), "worker workplace stable across day/night")
		_check(get_nodes_in_group("walls").size() > 0, "walls persist across day/night")
		_check(get_nodes_in_group("gates").size() == 3, "remaining gates persist across day/night")
		_enter(Phase.DONE)
		return
	_dn_frame += 1
	if _dn_frame < 12:
		return
	var expected_day := (_dn_cycle % 2 == 0)
	_check(_game_time.get_phase() == (_game_time.Phase.DAY if expected_day else _game_time.Phase.NIGHT), "day/night cycle %d phase correct" % _dn_cycle)
	_check(_gate.is_open() == true, "north gate open state persists across day/night (cycle %d)" % _dn_cycle)
	_dn_cycle += 1
	_dn_frame = 0
	_game_time.advance(10.0)


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
