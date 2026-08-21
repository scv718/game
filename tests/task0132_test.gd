extends SceneTree

## TASK-013-2 Wall 연결 비주얼 + 간단 철거 자동 검증.
##  - 인접 N/E/S/W Wall에 따라 straight/corner/end 시각 표현 (collision footprint 불변).
##  - Build mode에서 R Remove mode 진입 가능.
##  - Wall 철거 + Wood 전액 환불.
##  - Wall이 아닌 object(Core Building/생산시설)는 삭제 불가.
##  - 철거 후 인접 Wall 비주얼 갱신 정상.
##  - 철거 후 nav 갱신되어 통로가 열림 (stale nav 없음).

enum Phase { SETUP, VISUAL, REMOVE_NONWALL, NAVBLOCK, NAV_OPEN, DONE }

const WALL_COST := 2

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _step_done := false
var _failed := false

var _world: Node = null
var _placement: Node = null
var _resources: Node = null
var _corner_pos := Vector2(300, -300)


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
	print("TASK0132_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _wall_visual_bounds(w: Node) -> Rect2:
	var vis: Polygon2D = w.get_node("Visual") as Polygon2D
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for p in vis.polygon:
		minp = minp.min(p)
		maxp = maxp.max(p)
	return Rect2(minp, maxp - minp)


func _path_len(a: Vector2, b: Vector2) -> float:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, a, b, true)
	if path.size() < 2:
		return -1.0
	var len := 0.0
	for i in range(1, path.size()):
		len += path[i - 1].distance_to(path[i])
	return len


func _find_wall_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("walls"):
		if not is_instance_valid(node):
			continue
		var wall := node as Node2D
		if wall == null:
			continue
		if (wall.position - pos).length_squared() < 1.0:
			return node
	return null


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			_world = root.get_node("Main").get_node("World")
			_placement = root.get_node("Main").get_node("BuildingPlacement")
			_resources = root.get_node("VillageResources")
			_resources._amounts["wood"] = 10000
			_placement._set_building_type("wall")
			_placement._set_active(true)
			_enter(Phase.VISUAL)
		Phase.VISUAL:
			if not _step_done:
				_step_done = true
				var wood0: int = _resources.get_amount("wood")
				# 1) 단일 wall: 16x16 square.
				_placement._try_place_wall_at(_corner_pos)
				var single := _find_wall_at(_corner_pos)
				_check(single != null, "single wall placed")
				var sb := _wall_visual_bounds(single)
				_check(sb.size.x == 16.0 and sb.size.y == 16.0, "single wall visual is 16x16 (end) got %s" % str(sb))
				_check(_resources.get_amount("wood") == wood0 - WALL_COST, "wall cost deducted once")
				# 2) E neighbor 배치 -> straight horizontal: 폭이 24로 늘어남.
				_placement._try_place_wall_at(_corner_pos + Vector2(16, 0))
				var sb2 := _wall_visual_bounds(single)
				_check(sb2.size.x == 24.0 and sb2.size.y == 16.0, "straight horizontal visual (width 24) got %s" % str(sb2))
				# 3) N neighbor 배치 -> corner: 폭 24, 높이 24.
				_placement._try_place_wall_at(_corner_pos + Vector2(0, -16))
				var sb3 := _wall_visual_bounds(single)
				_check(sb3.size.x == 24.0 and sb3.size.y == 24.0, "corner visual (width 24, height 24) got %s" % str(sb3))
				# collision footprint는 불변(16x16) 확인.
				var col: CollisionShape2D = single.get_node("CollisionShape2D") as CollisionShape2D
				_check(col.shape.size == Vector2(16, 16), "collision footprint stays 16x16")
				# 4) N neighbor 철거 -> straight로 복귀(인접 비주얼 갱신).
				_placement._set_remove_mode(true)
				_check(_placement._remove_mode, "remove mode toggled on")
				var wood1: int = _resources.get_amount("wood")
				_placement._try_remove_wall_at(_corner_pos + Vector2(0, -16))
				_check(_find_wall_at(_corner_pos + Vector2(0, -16)) == null, "N neighbor wall removed")
				_check(_resources.get_amount("wood") == wood1 + WALL_COST, "removal refunds full Wood")
				var sb4 := _wall_visual_bounds(single)
				_check(sb4.size.x == 24.0 and sb4.size.y == 16.0, "neighbor visual updated back to straight after removal got %s" % str(sb4))
			if _elapsed() >= 4:
				_enter(Phase.REMOVE_NONWALL)
		Phase.REMOVE_NONWALL:
			if not _step_done:
				_step_done = true
				# Wall이 아닌 object(Core Building / 생산시설)는 삭제 금지.
				var before: int = get_nodes_in_group("walls").size()
				var wood0: int = _resources.get_amount("wood")
				var ly_scene: PackedScene = load("res://scenes/lumberyard.tscn")
				var ly: Node2D = ly_scene.instantiate()
				ly.position = Vector2(400, -100)
				_world.add_child(ly)
				_placement._try_remove_wall_at(Vector2(400, -100))
				_check(get_nodes_in_group("walls").size() == before, "non-wall object not removed (lumberyard kept)")
				_check(_resources.get_amount("wood") == wood0, "no refund for non-wall removal")
				_check(is_instance_valid(ly), "lumberyard still exists")
				ly.queue_free()
			if _elapsed() >= 4:
				# 시각 테스트에 남은 corner/E wall을 정리해 nav 테스트와 분리.
				_placement._set_remove_mode(true)
				_placement._try_remove_wall_at(_corner_pos)
				_placement._try_remove_wall_at(_corner_pos + Vector2(16, 0))
				_placement._set_remove_mode(false)
				_enter(Phase.NAVBLOCK)
		Phase.NAVBLOCK:
			if not _step_done:
				_step_done = true
				_placement._set_remove_mode(false)
				_pf = 0
				# (0,-200)~(112,-200) 연속 장벽 (8 segment) - task0131과 동일 범위.
				for x in range(0, 128, 16):
					_placement._try_place_wall_at(Vector2(x, -200))
				_check(get_nodes_in_group("walls").size() >= 8, "wall barrier built (8+ segments)")
			elif _pf >= 45:
				var direct := (Vector2(56, -170) - Vector2(56, -230)).length()
				var path_len := _path_len(Vector2(56, -170), Vector2(56, -230))
				_check(path_len > direct + 60.0, "wall barrier blocks nav before removal (path %.0f)" % path_len)
				# 장벽 중앙 2개(48,-200),(64,-200) 제거 -> 32px passage open.
				# (16px gap은 agent_radius=8이라 nav가 통과 불가하므로 2개 제거)
				_placement._set_remove_mode(true)
				_placement._try_remove_wall_at(Vector2(48, -200))
				_placement._try_remove_wall_at(Vector2(64, -200))
				_placement._set_remove_mode(false)
				_pf = 0
				_enter(Phase.NAV_OPEN)
		Phase.NAV_OPEN:
			if _pf >= 60:
				var direct := (Vector2(64, -170) - Vector2(64, -230)).length()
				var path_len := _path_len(Vector2(64, -170), Vector2(64, -230))
				_check(path_len < direct + 40.0, "nav passage opens after wall removal (path %.0f <= direct %.0f +40)" % [path_len, direct])
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0132_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false
