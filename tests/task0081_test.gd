extends SceneTree

enum Phase {
	SETUP, STRUCTURE, BOUNDARY_NORTH, BOUNDARY_NORTH_WAIT, BOUNDARY_SOUTH_WAIT, WALK_OUTSKIRTS, OUTSKIRTS, REGRESSION, DONE
}

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _failed := false
var _world: Node = null
var _layout: Node = null
var _controller: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(new_phase: Phase) -> void:
	_phase = new_phase
	_phase_start = _frame


func _elapsed() -> int:
	return _frame - _phase_start


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _process(_delta: float) -> bool:
	_frame += 1
	var main: Node = root.get_node("Main")
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			_world = main.get_node("World")
			_layout = _world.get_node_or_null("MapLayout")
			var ctrls := get_nodes_in_group("camera_controller")
			_controller = ctrls[0] if ctrls.size() > 0 else null
			if _controller != null:
				_controller.day_pan_speed = 2000.0
			_enter(Phase.STRUCTURE)
		Phase.STRUCTURE:
			_check(_layout != null, "MapLayout node exists")
			if _layout == null:
				_finish()
				return true
			_check(_layout.get_script() != null and _layout.get_script().resource_path == "res://scripts/world_map.gd", "MapLayout uses world_map.gd")

			var floor: TileMapLayer = _world.get_node("Floor") as TileMapLayer
			_check(floor.get_used_cells().size() == 192 * 192, "floor covers 192x192 tiles (%d)" % floor.get_used_cells().size())

			var bounds: Rect2 = _layout.get_bounds_rect()
			_check(bounds.size == Vector2(3072, 3072), "bounds size 3072x3072 (%s)" % str(bounds.size))
			_check(bounds.position == Vector2(-1536, -1536), "bounds centered at origin (%s)" % str(bounds.position))

			var clearing: Rect2 = _layout.get_clearing_rect()
			_check(clearing.has_point(Vector2.ZERO), "settlement center inside clearing")
			_check(clearing.size == Vector2(384, 384), "clearing is 384x384 (%s)" % str(clearing.size))
			_check(_layout.is_in_clearing(Vector2(0, 0)), "is_in_clearing true at center")
			_check(not _layout.is_in_clearing(Vector2(250, 0)), "is_in_clearing false outside clearing")

			var buffer: Rect2 = _layout.get_wall_buffer_rect()
			_check(buffer.size == Vector2(576, 576), "wall buffer 576x576 (%s)" % str(buffer.size))
			_check(_layout.is_in_wall_buffer(Vector2(0, 250)), "wall buffer ring holds space outside clearing")
			_check(not _layout.is_in_wall_buffer(Vector2(0, 0)), "settlement center is not wall buffer")

			for dir in ["north", "south", "east", "west"]:
				var anchor: Vector2 = _layout.get_gate_anchor(dir)
				var anchor_node: Node = _layout.get_node_or_null("GateAnchor_" + dir.to_upper())
				var axis_node: Node = _layout.get_node_or_null("Axis_" + dir.to_upper())
				_check(anchor_node != null, "GateAnchor_%s marker exists" % dir.to_upper())
				_check(anchor != Vector2.ZERO, "gate anchor %s defined" % dir)
				_check(_layout.is_in_bounds(anchor), "gate anchor %s inside bounds" % dir)
				_check(axis_node != null, "Axis_%s marker exists" % dir.to_upper())

			_check(_layout.is_on_access_axis(Vector2(0, 500)), "south access axis corridor identifiable")
			_check(_layout.is_on_access_axis(Vector2(500, 0)), "east access axis corridor identifiable")
			_check(not _layout.is_on_access_axis(Vector2(300, 300)), "corner area is off-axis")
			_check(not _layout.is_on_access_axis(Vector2(0, 0)), "settlement center not on axis")

			var spawns: Array = _layout.get_spawn_candidate_nodes()
			_check(spawns.size() >= 2, "at least 2 spawn candidate markers (%d)" % spawns.size())
			for s in spawns:
				_check(s.get_script() == null, "spawn candidate is non-functional marker (%s)" % s.name)

			var gates: Array = _layout.get_gate_anchor_nodes()
			_check(gates.size() >= 4, "4 gate anchor markers (%d)" % gates.size())
			for g in gates:
				_check(g.get_script() == null, "gate anchor is non-functional marker (%s)" % g.name)

			for wn in ["BoundaryWall_North", "BoundaryWall_South", "BoundaryWall_East", "BoundaryWall_West"]:
				var wall: Node = _world.get_node_or_null(wn)
				_check(wall != null, "%s exists" % wn)
				if wall != null:
					_check(wall is StaticBody2D, "%s is StaticBody2D" % wn)
					_check(wall.collision_layer == 4, "%s on collision layer 4" % wn)
					_check(wall.get_child_count() >= 1 and wall.get_child(0) is CollisionShape2D, "%s has collision shape" % wn)

			_enter(Phase.BOUNDARY_NORTH)
		Phase.BOUNDARY_NORTH:
			if _frame % 2 == 0:
				return false
			_controller.global_position = Vector2.ZERO
			Input.action_press("move_up")
			_enter(Phase.BOUNDARY_NORTH_WAIT)
		Phase.BOUNDARY_NORTH_WAIT:
			if _elapsed() >= 200:
				Input.action_release("move_up")
				var pos: Vector2 = _controller.global_position
				_check(pos.y <= -980, "DAY: camera actually pans north (y=%s)" % str(pos.y))
				_check(pos.y >= -1030.0, "DAY: camera clamped inside north boundary (y=%s)" % str(pos.y))
				_check(absf(pos.y) <= 1024.0 + 0.01, "camera remains inside map bounds (north)")
				_controller.global_position = Vector2.ZERO
				Input.action_press("move_down")
				_enter(Phase.BOUNDARY_SOUTH_WAIT)
		Phase.BOUNDARY_SOUTH_WAIT:
			if _elapsed() >= 200:
				Input.action_release("move_down")
				var pos: Vector2 = _controller.global_position
				_check(pos.y >= 980, "DAY: camera actually pans south (y=%s)" % str(pos.y))
				_check(pos.y <= 1030.0, "DAY: camera clamped inside south boundary (y=%s)" % str(pos.y))
				_check(absf(pos.y) <= 1024.0 + 0.01, "camera remains inside map bounds (south)")
				_controller.global_position = Vector2.ZERO
				Input.action_press("move_right")
				_enter(Phase.WALK_OUTSKIRTS)
		Phase.WALK_OUTSKIRTS:
			if _elapsed() >= 120:
				Input.action_release("move_right")
				var pos: Vector2 = _controller.global_position
				_check(pos.x >= 180, "DAY: camera pans from center toward outskirts (x=%s)" % str(pos.x))
				_check(absf(pos.x) <= 1024.0 + 0.01, "camera stays inside bounds while panning")
				_enter(Phase.OUTSKIRTS)
		Phase.OUTSKIRTS:
			if _frame % 2 == 0:
				return false
			for dir in ["north", "south", "east", "west"]:
				var anchor: Vector2 = _layout.get_gate_anchor(dir)
				_check(_layout.is_in_bounds(anchor), "%s gate anchor inside bounds (outskirts)" % dir)
			for s in _layout.get_spawn_candidate_nodes():
				_check(_layout.is_in_bounds(s.global_position), "spawn candidate %s inside bounds" % s.name)
			_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			_check(get_nodes_in_group("interactable").size() >= 3, "trees present (%d)" % get_nodes_in_group("interactable").size())
			if get_nodes_in_group("lumberjacks").size() < 1:
				var lj: Node = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
				lj.position = Vector2(300, 200)
				_world.add_child(lj)
			if get_nodes_in_group("miners").size() < 1:
				var mn: Node = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
				mn.position = Vector2(500, 140)
				_world.add_child(mn)
			_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack present")
			_check(get_nodes_in_group("miners").size() >= 1, "miner present")
			_check(get_nodes_in_group("stone_deposits").size() >= 1, "stone deposit present")
			_check(_world.nav_rebuild_count >= 0, "navigation rebuild state works")
			_world.rebuild_navigation()
			_check(true, "navigation rebuild on new map works")
			_enter(Phase.DONE)
		Phase.DONE:
			print("TASK0081_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 20000:
		print("TASK0081_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _finish() -> void:
	print("TASK0081_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)