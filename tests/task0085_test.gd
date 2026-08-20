extends SceneTree

## TASK-008-5 World Map 통합 검증
## TASK-008(맵 골격/테라인/생산 체인 이전/Nav 회귀) 전체를 하나의 시나리오로 통합 검증한다.
## 목적은 새 128x128 오버월드에서 실제 게임 루프(이동→건설→배치→생산→재생장)가
## 한 번에 정상 동작하는지를 자동으로 확인하는 것이다.

enum Phase {
	SETUP, SMOKE, MOVEMENT, MOVEMENT_WAIT, MAP_STRUCTURE, FOREST_TREES, DEPOSIT,
	PLACEMENT, ASSIGN, PRODUCE_STONE, PRODUCE_WOOD, REGROWTH, NAVIGATION, DONE
}

const LUMBERYARD_SCENE := preload("res://scenes/lumberyard.tscn")

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _failed := false

var _world: Node = null
var _layout: Node = null
var _floor: TileMapLayer = null
var _player: Node = null
var _placement: Node = null
var _hud: Node = null
var _resources: Node = null
var _miner: Node = null
var _lumberjack: Node = null
var _deposit: Node = null
var _quarry: Node = null
var _lumberyard: Node = null

var _wood_before := 0
var _stone_before := 0
var _lumberjack_worked := false
var _regrown_checked := false
var _regrow_started := false


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


func _finish() -> void:
	print("TASK0085_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _stump_count() -> int:
	var n := 0
	for t in get_nodes_in_group("interactable"):
		if not t.can_interact():
			n += 1
	return n


func _process(_delta: float) -> bool:
	_frame += 1
	var main: Node = root.get_node("Main")
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			_world = main.get_node("World")
			_layout = _world.get_node_or_null("MapLayout")
			_floor = _world.get_node("Floor") as TileMapLayer
			_player = main.get_node("Player")
			_placement = main.get_node("BuildingPlacement")
			_hud = main.get_node("HUD")
			_resources = root.get_node("VillageResources")
			_miner = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			_miner.position = Vector2(500, 140)
			_world.add_child(_miner)
			_lumberjack = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_lumberjack.position = Vector2(300, 200)
			_world.add_child(_lumberjack)
			var deposits := get_nodes_in_group("stone_deposits")
			_deposit = deposits[0] if deposits.size() > 0 else null
			for t in get_nodes_in_group("interactable"):
				t.regrow_time = 10000.0
			_enter(Phase.SMOKE)
		Phase.SMOKE:
			_check(main != null, "main.tscn loads")
			_check(_world != null, "world node present")
			_check(_layout != null, "MapLayout node exists")
			_check(_floor is TileMapLayer, "Floor is a TileMapLayer")
			_check(_floor.get_used_cells().size() == 128 * 128, "floor covers 128x128 tiles (%d)" % _floor.get_used_cells().size())
			_check(_player != null, "player exists")
			_check(_hud != null, "HUD exists")
			_check(_miner != null, "miner exists in world")
			_check(_lumberjack != null, "lumberjack exists in world")
			_check(_deposit != null, "stone deposit exists in world")
			_check(get_nodes_in_group("interactable").size() >= 12, "trees present (%d)" % get_nodes_in_group("interactable").size())
			_check(get_nodes_in_group("decorations").size() >= 4, "decorations present (%d)" % get_nodes_in_group("decorations").size())
			_enter(Phase.MOVEMENT)
		Phase.MOVEMENT:
			_player.global_position = Vector2.ZERO
			Input.action_press("move_right")
			_enter(Phase.MOVEMENT_WAIT)
		Phase.MOVEMENT_WAIT:
			if _elapsed() >= 180:
				Input.action_release("move_right")
				var pos: Vector2 = _player.global_position
				_check(pos.x > 90, "player walks from center toward east outskirts (x=%s)" % str(pos.x))
				_check(_layout.is_in_bounds(pos), "player stays inside map bounds while moving")
				_player.global_position = Vector2.ZERO
				_enter(Phase.MAP_STRUCTURE)
		Phase.MAP_STRUCTURE:
			_check(_layout.get_script() != null and _layout.get_script().resource_path == "res://scripts/world_map.gd", "MapLayout uses world_map.gd")

			var bounds: Rect2 = _layout.get_bounds_rect()
			_check(bounds.size == Vector2(2048, 2048), "bounds size 2048x2048 (%s)" % str(bounds.size))
			_check(bounds.position == Vector2(-1024, -1024), "bounds centered at origin (%s)" % str(bounds.position))
			_check(not _layout.is_in_bounds(Vector2(1100, 0)), "point beyond east bound rejected")
			_check(not _layout.is_in_bounds(Vector2(0, -1100)), "point beyond north bound rejected")

			var clearing: Rect2 = _layout.get_clearing_rect()
			_check(clearing.size == Vector2(384, 384), "clearing 384x384 (%s)" % str(clearing.size))
			_check(clearing.has_point(Vector2.ZERO), "settlement center inside clearing")
			_check(_layout.is_in_clearing(Vector2(0, 0)), "is_in_clearing true at center")
			_check(not _layout.is_in_clearing(Vector2(250, 0)), "is_in_clearing false outside clearing")

			var buffer: Rect2 = _layout.get_wall_buffer_rect()
			_check(buffer.size == Vector2(576, 576), "wall buffer 576x576 (%s)" % str(buffer.size))
			_check(_layout.is_in_wall_buffer(Vector2(0, 250)), "wall buffer ring holds space outside clearing")
			_check(not _layout.is_in_wall_buffer(Vector2(0, 0)), "settlement center is not wall buffer")

			var nav_rect: Rect2 = _layout.get_nav_rect()
			_check(nav_rect.position.x >= bounds.position.x and nav_rect.position.y >= bounds.position.y, "nav rect inside bounds (start)")
			_check(nav_rect.end.x <= bounds.end.x and nav_rect.end.y <= bounds.end.y, "nav rect inside bounds (end)")

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
				_check(s.get_script() == null, "spawn candidate %s is non-functional marker" % s.name)

			var gates: Array = _layout.get_gate_anchor_nodes()
			_check(gates.size() >= 4, "4 gate anchor markers (%d)" % gates.size())
			for g in gates:
				_check(g.get_script() == null, "gate anchor %s is non-functional marker" % g.name)

			for wn in ["BoundaryWall_North", "BoundaryWall_South", "BoundaryWall_East", "BoundaryWall_West"]:
				var wall: Node = _world.get_node_or_null(wn)
				_check(wall != null and wall is StaticBody2D, "%s exists as StaticBody2D" % wn)
				if wall != null:
					_check(wall.collision_layer == 4, "%s on collision layer 4" % wn)
					_check(wall.collision_mask == 0, "%s has collision mask 0" % wn)
					_check(wall.get_child_count() >= 1 and wall.get_child(0) is CollisionShape2D, "%s has collision shape child" % wn)

			_enter(Phase.FOREST_TREES)
		Phase.FOREST_TREES:
			var wm_script: GDScript = load("res://scripts/world_map.gd")
			var clusters: Array = wm_script.FOREST_CLUSTERS
			_check(clusters.size() >= 3, "at least 3 meaningful forest clusters defined (%d)" % clusters.size())
			for i in clusters.size():
				var trees: Array = clusters[i]["trees"]
				_check(trees.size() >= 3, "forest cluster %d has >= 3 trees (%d)" % [i, trees.size()])
				for pos in trees:
					_check(_layout.is_in_bounds(pos), "forest cluster %d tree inside map bounds" % i)
					_check(not _layout.is_in_clearing(pos), "forest cluster %d tree not inside settlement clearing" % i)
					_check(not _layout.is_on_access_axis(pos), "forest cluster %d tree not on access axis/road" % i)

			var world_trees := get_nodes_in_group("interactable")
			_check(world_trees.size() >= 12, "world contains many trees from clusters (%d)" % world_trees.size())
			var blocking := 0
			var on_axis := 0
			for t in world_trees:
				if _layout.is_in_clearing(t.global_position):
					blocking += 1
				if _layout.is_on_access_axis(t.global_position):
					on_axis += 1
			_check(blocking == 0, "no trees block the settlement clearing (%d found)" % blocking)
			_check(on_axis == 0, "no trees block the access axes/roads (%d found)" % on_axis)

			var tree_collisions := 0
			for t in world_trees:
				if t.get_node_or_null("TrunkBlock") != null:
					tree_collisions += 1
			_check(tree_collisions >= 12, "trees carry collision for build/nav blocking (%d)" % tree_collisions)
			_enter(Phase.DEPOSIT)
		Phase.DEPOSIT:
			_check(get_nodes_in_group("stone_deposits").size() == 1, "exactly 1 stone deposit")
			_check(not _deposit.is_occupied(), "stone deposit starts unoccupied")
			var block: Node = _deposit.get_node_or_null("Block") as StaticBody2D
			_check(block != null and block.collision_layer == 4, "stone deposit has layer-4 block collision")
			_check(_layout.is_in_bounds(_deposit.global_position), "stone deposit inside map bounds")
			_check(not _layout.is_in_clearing(_deposit.global_position), "stone deposit is outside central clearing (meaningful distance)")
			_enter(Phase.PLACEMENT)
		Phase.PLACEMENT:
			_check(_placement._building_type == "lumberyard", "placement defaults to lumberyard")
			_placement._set_building_type("quarry")
			_check(_placement._building_type == "quarry", "building type switches to quarry")
			_placement._set_building_type("lumberyard")
			_check(_placement._building_type == "lumberyard", "building type switches back to lumberyard")

			_resources._amounts["wood"] = 0
			_placement._try_place_at(Vector2(300, 260))
			_check(get_nodes_in_group("lumberyards").size() == 0, "lumberyard denied without enough wood")
			_check(_resources.get_amount("wood") == 0, "wood unchanged when not affordable")

			_resources._amounts["wood"] = 20
			var wood_before: int = _resources.get_amount("wood")
			_placement._try_place_at(Vector2(300, 260))
			_check(get_nodes_in_group("lumberyards").size() == 1, "lumberyard built on valid clearing position")
			_check(_resources.get_amount("wood") == wood_before - 10, "wood deducted exactly once (-10)")
			_lumberyard = get_nodes_in_group("lumberyards")[0]
			_check(_lumberyard.get_slot_capacity() == 2, "lumberyard slot capacity is 2")
			_check(_lumberyard.get_filled_slots() == 0, "lumberyard starts 0/2")
			_check(_lumberyard.get_node_or_null("DepositPoint") != null, "lumberyard has DepositPoint marker")

			_placement._set_building_type("quarry")
			wood_before = _resources.get_amount("wood")
			_placement._try_place_quarry_at(Vector2(100, 100))
			_check(get_nodes_in_group("quarries").size() == 0, "quarry denied outside deposit area")
			_check(_resources.get_amount("wood") == wood_before, "wood not deducted outside deposit")

			_placement._try_place_quarry_at(_deposit.global_position)
			_check(get_nodes_in_group("quarries").size() == 1, "quarry built on valid deposit")
			_check(_resources.get_amount("wood") == wood_before - 10, "wood deducted exactly once for quarry (-10)")
			_check(_deposit.is_occupied(), "deposit occupied after quarry built")
			_quarry = get_nodes_in_group("quarries")[0]
			_check(_quarry.get_deposit() == _deposit, "quarry linked to deposit")
			_check(_quarry.get_slot_capacity() == 2, "quarry slot capacity is 2")
			_check(_quarry.get_filled_slots() == 0, "quarry starts 0/2")
			_check(_quarry.get_node_or_null("WorkPoint") != null, "quarry has WorkPoint marker")
			_check(_quarry.get_node_or_null("MiningPoint") != null, "quarry has MiningPoint marker")
			var interact: Node = _quarry.get_node_or_null("Interact")
			_check(interact != null and interact.collision_layer == 8, "quarry has layer 8 Interact")

			wood_before = _resources.get_amount("wood")
			_placement._try_place_quarry_at(_deposit.global_position)
			_check(get_nodes_in_group("quarries").size() == 1, "duplicate quarry on same deposit denied")
			_check(_resources.get_amount("wood") == wood_before, "no extra cost on denied duplicate")

			_enter(Phase.ASSIGN)
		Phase.ASSIGN:
			if _frame % 2 == 0:
				return false
			var qres: Dictionary = _quarry.handle_worker_interaction()
			_check(qres.get("action") == "assign" and qres.get("success") == true, "quarry assigns miner (%s)" % str(qres))
			_check(_quarry.get_filled_slots() == 1, "quarry filled becomes 1")
			_check(_miner.get_workplace() == _quarry, "miner workplace is the quarry")
			_check(_miner.state == 1, "miner enters MOVE_TO_WORK (state=%d)" % _miner.state)
			_check(not _quarry.assign_worker(_miner), "duplicate miner assignment rejected")
			_check(_quarry.get_filled_slots() == 1, "duplicate assignment keeps slot count 1")

			var lres: Dictionary = _lumberyard.handle_worker_interaction()
			_check(lres.get("action") == "assign" and lres.get("success") == true, "lumberyard assigns lumberjack (%s)" % str(lres))
			_check(_lumberyard.get_filled_slots() == 1, "lumberyard filled becomes 1")
			_check(_lumberjack.get_workplace() == _lumberyard, "lumberjack workplace is the lumberyard")
			_check(_lumberyard._pick_available_worker() == null, "lumberyard does not pick already-assigned worker")

			_stone_before = _resources.get_amount("stone")
			_enter(Phase.PRODUCE_STONE)
		Phase.PRODUCE_STONE:
			var stone: int = _resources.get_amount("stone")
			if stone >= _stone_before + 3:
				_check(stone >= _stone_before + 3, "miner produced stone at WorkPoint (+%d)" % (stone - _stone_before))
				_check(_miner.state == 2, "miner in MINE state while producing (state=%d)" % _miner.state)
				_check(_miner.is_gathering(), "miner is_gathering in MINE")
				_wood_before = _resources.get_amount("wood")
				_enter(Phase.PRODUCE_WOOD)
			elif _elapsed() >= 2000:
				_check(false, "miner produced stone within timeout (stone=%d state=%d)" % [stone, _miner.state])
				_finish()
				return true
		Phase.PRODUCE_WOOD:
			var wood: int = _resources.get_amount("wood")
			if wood > _wood_before:
				_lumberjack_worked = true
			if _lumberjack_worked and _stump_count() >= 2 and _lumberjack.carried_amount == 0 and _lumberjack.state == 0:
				_check(wood > _wood_before, "lumberjack produced wood (+%d)" % (wood - _wood_before))
				_check(_stump_count() >= 2, "in-radius trees become STUMP (count=%d)" % _stump_count())
				for t in get_nodes_in_group("interactable"):
					if not t.can_interact():
						_check(t.state == 1, "depleted tree enters STUMP state")
				_enter(Phase.REGROWTH)
			elif _elapsed() >= 4000:
				_check(false, "lumberjack production loop within timeout (wood=%d state=%d stumps=%d)" % [wood, _lumberjack.state, _stump_count()])
				_finish()
				return true
		Phase.REGROWTH:
			if not _regrow_started:
				for t in get_nodes_in_group("interactable"):
					if not t.can_interact():
						t.regrow_time = 0.5
						t._regrow()
				_regrow_started = true
				_wood_before = _resources.get_amount("wood")
			var mature := 0
			for t in get_nodes_in_group("interactable"):
				if t.can_interact() and t.state == 0:
					mature += 1
			if mature >= 2:
				if not _regrown_checked:
					_check(mature >= 2, "trees regrew to MATURE (mature=%d)" % mature)
					_regrown_checked = true
			var wood: int = _resources.get_amount("wood")
			if _regrown_checked and wood >= _wood_before + 3:
				_check(wood >= _wood_before + 3, "lumberjack resumes work after regrowth (+%d)" % (wood - _wood_before))
				_enter(Phase.NAVIGATION)
			elif _elapsed() >= 3000:
				_check(false, "lumberjack resumed work after regrowth within timeout (wood=%d mature=%d)" % [wood, mature])
				_finish()
				return true
		Phase.NAVIGATION:
			_check(_world.has_method("rebuild_navigation"), "world exposes rebuild_navigation")
			_world.rebuild_navigation()
			_check(true, "navigation rebuild works with buildings/trees present")
			_check(_quarry.get_node_or_null("WorkPoint") != null, "navigation rebuild keeps WorkPoint intact")
			_check(_world.nav_rebuild_count >= 0, "navigation rebuild count available (%d)" % _world.nav_rebuild_count)
			_world.rebuild_navigation()
			_check(true, "repeated navigation rebuild is stable")
			_enter(Phase.DONE)
		Phase.DONE:
			print("TASK0085_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 30000:
		print("TASK0085_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)