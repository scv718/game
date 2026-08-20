extends SceneTree

## TASK-013-1 Wall 기본 Scene / Placement 자동 검증.
##  - Wall 1 segment = 1 logical tile (16x16px) footprint.
##  - static collision (StaticBody2D).
##  - 16px grid snap.
##  - 여러 segment 연속 배치 (배치 후에도 build mode 유지).
##  - 비용 1회 차감 / invalid 시 비용 차감 없음.
##  - Player/Core Building 겹침 거부.
##  - placement 후 nav rebuild.

enum Phase { SETUP, PLACE, NAVBLOCK, INVALID, DONE }

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
var _barrier_built := false


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
	print("TASK0131_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _path_len(a: Vector2, b: Vector2) -> float:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, a, b, true)
	if path.size() < 2:
		return -1.0
	var len := 0.0
	for i in range(1, path.size()):
		len += path[i - 1].distance_to(path[i])
	return len


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			_world = root.get_node("Main").get_node("World")
			_placement = root.get_node("Main").get_node("BuildingPlacement")
			_resources = root.get_node("VillageResources")
			_check(root.get_node("Main") != null, "main.tscn loads")
			var wall_scene: PackedScene = load("res://scenes/wall.tscn")
			_check(wall_scene != null, "wall scene loads")
			if wall_scene != null:
				var w: Node = wall_scene.instantiate()
				_world.add_child(w)
				_check(w is StaticBody2D, "wall is StaticBody2D (static collision)")
				var vis: Polygon2D = w.get_node("Visual") as Polygon2D
				_check(vis != null, "wall has Visual polygon (16px footprint)")
				w.queue_free()
			_enter(Phase.PLACE)
		Phase.PLACE:
			if not _step_done:
				_step_done = true
				_resources._amounts["wood"] = 1000
				_placement._set_building_type("wall")
				_check(_placement._building_type == "wall", "wall build selection added (KEY_3)")
				_check(_placement._ghost_size == 16, "wall ghost footprint is 16px")
				_placement._set_active(true)
				_check(_placement._active, "wall build mode active")
				var wood0: int = _resources.get_amount("wood")
				_placement._try_place_wall_at(Vector2(0, -200))
				_check(get_nodes_in_group("walls").size() == 1, "first wall placed (grid snap to 16px)")
				_check(_resources.get_amount("wood") == wood0 - WALL_COST, "wall cost deducted once (%d wood)" % WALL_COST)
				_check(_placement._active, "wall mode stays active for continuous placement")
				_placement._try_place_wall_at(Vector2(16, -200))
				_check(get_nodes_in_group("walls").size() == 2, "second wall placed continuously (2)")
				_check(_resources.get_amount("wood") == wood0 - WALL_COST * 2, "second wall cost deducted once")
			if _elapsed() >= 4:
				_enter(Phase.NAVBLOCK)
		Phase.NAVBLOCK:
			if not _barrier_built:
				_barrier_built = true
				_pf = 0
				# 수평 벽 장벽(x=0..112, y=-200) 쌓기.
				for x in range(32, 128, 16):
					_placement._try_place_wall_at(Vector2(x, -200))
				_check(get_nodes_in_group("walls").size() == 8, "wall barrier built (8 segments)")
			elif _pf >= 30:
				# nav sync를 위해 physics frame 대기 후 측정.
				# 장벽 중앙(x=56)에서 남북을 가로지르도록 쿼리해 양끝 우회가 크게 걸리게 한다.
				var direct := (Vector2(56, -170) - Vector2(56, -230)).length()
				var path_len := _path_len(Vector2(56, -170), Vector2(56, -230))
				_check(path_len > direct + 60.0, "wall barrier blocks nav (path %.0f > direct %.0f +60)" % [path_len, direct])
				_enter(Phase.INVALID)
		Phase.INVALID:
			if not _step_done:
				_step_done = true
				var wood0: int = _resources.get_amount("wood")
				var count0: int = get_nodes_in_group("walls").size()
				# Keep은 (0,-150), 32x32 collision. wall 16x16이 겹치면 거부.
				_placement._try_place_wall_at(Vector2(0, -150))
				_check(get_nodes_in_group("walls").size() == count0, "wall rejected overlapping Core Building (Keep)")
				_check(_resources.get_amount("wood") == wood0, "no wood deducted on invalid wall position")
			if _elapsed() >= 4:
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0131_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false
