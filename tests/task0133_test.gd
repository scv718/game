extends SceneTree

## TASK-013-3 Gate Corridor 판정 + Gate Placement 자동 검증.
##  - Gate는 Wall보다 넓은 footprint (prototype 3 logical tiles = 48px).
##  - N/S Gate = 도로를 가로지르는 수평(48x16), E/W Gate = 수직(16x48) orientation.
##  - 4방향(N/E/S/W) Gate Corridor 내부에서만 배치 허용.
##  - corridor 밖 / 다른 object와 겹침 거부.
##  - Main Road 중심선 근처 snap (N/S는 x=0, E/W는 y=0).
##  - Wall이 성문 양옆에 자연스럽게 이어질 수 있음 (인접 허용 / 실제 겹침 거부).
##  - 비용/철거/환불 정상.

enum Phase { SETUP, SELECT, PLACE_4WAY, SNAP, OUTSIDE, OVERLAP, ADJACENT, REMOVE, DONE }

const GATE_COST := 5
const WALL_COST := 2

var _frame := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _step_done := false
var _failed := false

var _world: Node = null
var _placement: Node = null
var _resources: Node = null
var _layout: Node = null

const NORTH_GATE := Vector2(0, -448)
const SOUTH_GATE := Vector2(0, 448)
const EAST_GATE := Vector2(448, 0)
const WEST_GATE := Vector2(-448, 0)


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
	print("TASK0133_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _gate_count() -> int:
	return get_nodes_in_group("gates").size()


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


func _gate_footprint(g: Node) -> Vector2:
	var col: CollisionShape2D = g.get_node("CollisionShape2D") as CollisionShape2D
	return (col.shape as RectangleShape2D).size


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			_world = root.get_node("Main").get_node("World")
			_placement = root.get_node("Main").get_node("BuildingPlacement")
			_resources = root.get_node("VillageResources")
			_layout = _world.get_node("MapLayout")
			_check(_layout != null, "MapLayout present (TASK-012 metadata reused)")
			_resources._amounts["wood"] = 10000
			var gate_scene: PackedScene = load("res://scenes/gate.tscn")
			_check(gate_scene != null, "gate scene loads")
			if gate_scene != null:
				var g: Node = gate_scene.instantiate()
				_world.add_child(g)
				_check(g is StaticBody2D, "gate is StaticBody2D (static collision)")
				g.queue_free()
			_enter(Phase.SELECT)
		Phase.SELECT:
			if not _step_done:
				_step_done = true
				_placement._set_building_type("gate")
				_check(_placement._building_type == "gate", "gate build selection added (KEY_4)")
				_check(_placement._extents_for_gate(NORTH_GATE) == Vector2(24, 8), "N/S gate ghost extents 48x16")
				_check(_placement._extents_for_gate(EAST_GATE) == Vector2(8, 24), "E/W gate ghost extents 16x48")
			if _elapsed() >= 4:
				_enter(Phase.PLACE_4WAY)
		Phase.PLACE_4WAY:
			if not _step_done:
				_step_done = true
				var wood0: int = _resources.get_amount("wood")
				# 4방향 모두 corridor 내부 valid 배치.
				_placement._try_place_gate_at(_placement._snap_gate(NORTH_GATE))
				_placement._try_place_gate_at(_placement._snap_gate(SOUTH_GATE))
				_placement._try_place_gate_at(_placement._snap_gate(EAST_GATE))
				_placement._try_place_gate_at(_placement._snap_gate(WEST_GATE))
				_check(_gate_count() == 4, "4 gates placed (N/E/S/W)")
				_check(_resources.get_amount("wood") == wood0 - GATE_COST * 4, "gate cost deducted per gate (wood %d)" % _resources.get_amount("wood"))
				var gn := _find_gate_at(NORTH_GATE)
				var gs := _find_gate_at(SOUTH_GATE)
				var ge := _find_gate_at(EAST_GATE)
				var gw := _find_gate_at(WEST_GATE)
				_check(gn != null and gn.get_direction() == "north", "north gate direction north")
				_check(gs != null and gs.get_direction() == "south", "south gate direction south")
				_check(ge != null and ge.get_direction() == "east", "east gate direction east")
				_check(gw != null and gw.get_direction() == "west", "west gate direction west")
				_check(gn != null and gn.get_orientation() == "horizontal" and _gate_footprint(gn) == Vector2(48, 16), "N/S gate horizontal 48x16 orientation")
				_check(gs.get_orientation() == "horizontal", "south gate horizontal orientation")
				_check(ge.get_orientation() == "vertical" and _gate_footprint(ge) == Vector2(16, 48), "E/W gate vertical 16x48 orientation")
				_check(gw.get_orientation() == "vertical", "west gate vertical orientation")
			if _elapsed() >= 4:
				_enter(Phase.SNAP)
		Phase.SNAP:
			if not _step_done:
				_step_done = true
				# Main Road 중심선 snap: N/S는 x=0, E/W는 y=0.
				_check(_placement._snap_gate(Vector2(32, -464)) == Vector2(0, -464), "north mouse off-center snaps to centerline x=0")
				_check(_placement._snap_gate(Vector2(480, 16)) == Vector2(480, 0), "east mouse off-center snaps to centerline y=0")
				_check(_placement._snap_gate(Vector2(-16, 400)) == Vector2(0, 400), "south mouse off-center snaps to centerline x=0")
			if _elapsed() >= 4:
				_enter(Phase.OUTSIDE)
		Phase.OUTSIDE:
			if not _step_done:
				_step_done = true
				var wood0: int = _resources.get_amount("wood")
				var count0 := _gate_count()
				# corridor 밖 (정착지 내부/outer wild) → invalid, 비용 차감 없음.
				_placement._try_place_gate_at(Vector2(0, -200))
				_placement._try_place_gate_at(Vector2(0, -600))
				_placement._try_place_gate_at(Vector2(300, 300))
				_check(_gate_count() == count0, "gate rejected outside corridors (count stays %d)" % count0)
				_check(_resources.get_amount("wood") == wood0, "no wood deducted on invalid gate positions")
			if _elapsed() >= 4:
				_enter(Phase.OVERLAP)
		Phase.OVERLAP:
			if not _step_done:
				_step_done = true
				var wood0: int = _resources.get_amount("wood")
				var count0 := _gate_count()
				# 겹침 거부: 먼저 north corridor에 wall 배치 후, 같은 위치 gate 배치 시도 → 거부.
				_placement._try_place_wall_at(Vector2(0, -512))
				_check(get_nodes_in_group("walls").size() >= 1, "wall placed for overlap test")
				var wood_after_wall: int = _resources.get_amount("wood")
				_placement._try_place_gate_at(Vector2(0, -512))
				_check(_gate_count() == count0, "gate rejected overlapping existing wall")
				_check(_resources.get_amount("wood") == wood_after_wall, "no wood deducted on gate-over-wall")
				# wall도 gate footprint와 실제 겹치면 거부 (north gate (0,-448) 기준).
				var wood1: int = _resources.get_amount("wood")
				_placement._try_place_wall_at(Vector2(-16, -448))
				_check(_resources.get_amount("wood") == wood1, "wall rejected overlapping gate footprint (no cost)")
			if _elapsed() >= 4:
				_enter(Phase.ADJACENT)
		Phase.ADJACENT:
			if not _step_done:
				_step_done = true
				var wood0: int = _resources.get_amount("wood")
				var wall0: int = get_nodes_in_group("walls").size()
				# Wall이 성문 양옆에 자연스럽게 이어짐: gate footprint edge와 touch만 허용.
				_placement._try_place_wall_at(Vector2(-32, -448))
				_check(get_nodes_in_group("walls").size() == wall0 + 1, "wall placed adjacent to gate (edge touch allowed)")
				_check(_resources.get_amount("wood") == wood0 - WALL_COST, "adjacent wall cost deducted once")
			if _elapsed() >= 4:
				_enter(Phase.REMOVE)
		Phase.REMOVE:
			if not _step_done:
				_step_done = true
				var wood0: int = _resources.get_amount("wood")
				_placement._set_remove_mode(true)
				# 성문 철거 + 환불.
				_placement._try_remove_wall_at(NORTH_GATE)
				_check(_find_gate_at(NORTH_GATE) == null, "north gate removed")
				_check(_resources.get_amount("wood") == wood0 + GATE_COST, "gate removal refunds full Wood (+%d)" % GATE_COST)
				# 벽 철거 + 환불.
				var wood1: int = _resources.get_amount("wood")
				_placement._try_remove_wall_at(Vector2(-32, -448))
				_check(_resources.get_amount("wood") == wood1 + WALL_COST, "wall removal refunds full Wood (+%d)" % WALL_COST)
				# 성문이 아닌 object(Core Building) 삭제 금지/환불 없음.
				var wood2: int = _resources.get_amount("wood")
				var before: int = _gate_count()
				_placement._try_remove_wall_at(Vector2(150, -60))
				_check(_gate_count() == before, "non-gate/non-wall object not removed (Inn kept)")
				_check(_resources.get_amount("wood") == wood2, "no refund for non-gate removal")
				_placement._set_remove_mode(false)
			if _elapsed() >= 4:
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0133_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)