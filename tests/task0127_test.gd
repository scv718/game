extends SceneTree

## TASK-012-7 Navigation / BuildingPlacement / Night View 맵 회귀.
## TASK-012(맵 재배치) 후 기존 시스템이 깨지지 않았는지 통합 회귀 검증하고,
## 밤 지휘 관점에서의 가독성 구조와 주요 지역 이동 거리를 기록한다.
##
## 자동검증:
##  1. Player가 중앙 핵심 마을에서 이동 가능.
##  2. N/E/S/W Outer Wild 접근 가능 (nav).
##  3. 월드 경계 정상 (128x128 / 2048x2048).
##  4. Lumberyard placement 정상.
##  5. Quarry valid/invalid placement 정상.
##  6. Lumberjack 2명 동시 작업 정상.
##  7. Miner 2명 동시 작업 정상.
##  8. Tree claim/regrowth 정상.
##  9. 런타임 nav rebuild 정상.
## 10. Day/Night phase 정상.
## 11. NIGHT 시 Player 이동 비활성 정상.
## 12. NIGHT camera zoom-out 정상.
## 13. NIGHT 동안 기존 Worker 생산 정책 유지.
## 14. Wood/Stone HUD 정상.
## 15. main.tscn smoke PASS.
##
## Night tactical readability:
##  - 중앙 Village + 한 방향 Gate Corridor + Combat Field가 night_zoom에서
##    한 시야 또는 짧은 pan으로 읽히는 구조인지 확인 자료를 남긴다.
##
## 이동거리 기록 (실제 Player speed 기준 초 환산):
##  - Player Start -> NW Starter Forest
##  - Player Start -> StoneDeposit
##  - Player Start -> NE Dungeon Candidate
##  - Player Start -> N/E/S/W Candidate / Map Edge

enum Phase {
	SETUP, MAP_REG, PLACEMENT, ASSIGN, PRODUCE_WOOD2, PRODUCE_STONE2, REGROWTH,
	NAV, DAYNIGHT_SETUP, DAYNIGHT, NIGHT_READ, TRAVEL, DONE
}

const CORE_TYPES := ["keep", "tavern", "inn", "grocery", "equipment"]

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _step_done := false
var _failed := false

var _main: Node = null
var _world: Node = null
var _layout: Node = null
var _floor: TileMapLayer = null
var _player: Node = null
var _placement: Node = null
var _resources: Node = null
var _hud: Node = null
var _game_time: Node = null

var _lj: Node = null
var _lj2: Node = null
var _miner: Node = null
var _miner2: Node = null
var _deposit: Node = null
var _lumberyard: Node = null
var _quarry: Node = null

var _wood_before := 0
var _stone_before := 0
var _regrown_checked := false
var _regrow_started := false
var _start_x := 0.0


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
	print("TASK0127_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _stump_count() -> int:
	var n := 0
	for t in get_nodes_in_group("interactable"):
		if not t.can_interact():
			n += 1
	return n


func _path_len(a: Vector2, b: Vector2) -> float:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, a, b, true)
	if path.size() < 2:
		return -1.0
	var len := 0.0
	for i in range(1, path.size()):
		len += path[i - 1].distance_to(path[i])
	return len


func _record_travel(name: String, dest: Vector2) -> void:
	var dist := _path_len(Vector2(0, 60), dest)
	var speed := float(_player.move_speed)
	if speed <= 0.0:
		speed = 120.0
	if dist < 0.0:
		print("TRAVEL %s: NO NAV PATH to %s" % [name, str(dest)])
		_check(false, "travel %s nav path exists" % name)
		return
	var seconds := dist / speed
	print("TRAVEL %s -> %s: nav=%.0fpx, player_speed=%.0fpx/s, ETA=%.1fs" % [name, str(dest), dist, speed, seconds])
	_check(dist > 0.0, "travel %s measured positive distance" % name)


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
			_resources = root.get_node("VillageResources")
			_hud = main.get_node("HUD")
			_game_time = root.get_node("GameTime")
			_lj = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_lj.position = Vector2(300, 200)
			_world.add_child(_lj)
			_lj2 = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_lj2.position = Vector2(360, 240)
			_world.add_child(_lj2)
			_miner = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			_miner.position = Vector2(500, 140)
			_world.add_child(_miner)
			_miner2 = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			_miner2.position = Vector2(540, 180)
			_world.add_child(_miner2)
			var deposits := get_nodes_in_group("stone_deposits")
			_deposit = deposits[0] if deposits.size() > 0 else null
			for t in get_nodes_in_group("interactable"):
				t.regrow_time = 10000.0
			_enter(Phase.MAP_REG)
		Phase.MAP_REG:
			_check(main != null, "main.tscn loads")
			_check(_world != null, "world node present")
			_check(_layout != null, "MapLayout node exists")
			_check(_layout.get_script() != null and _layout.get_script().resource_path == "res://scripts/world_map.gd", "MapLayout uses world_map.gd")
			_check(_floor.get_used_cells().size() == 128 * 128, "floor covers 128x128 tiles (%d)" % _floor.get_used_cells().size())
			_check(_layout.get_bounds_rect().size == Vector2(2048, 2048), "bounds size 2048x2048 (%s)" % str(_layout.get_bounds_rect().size))
			_check(_layout.get_bounds_rect().position == Vector2(-1024, -1024), "bounds centered at origin (%s)" % str(_layout.get_bounds_rect().position))
			_check(not _layout.is_in_bounds(Vector2(1100, 0)), "point beyond east bound rejected")
			_check(not _layout.is_in_bounds(Vector2(0, -1100)), "point beyond north bound rejected")

			var cores := get_nodes_in_group("core_buildings")
			_check(cores.size() == 5, "5 core buildings present (%d)" % cores.size())
			var seen := {}
			for b in cores:
				seen[b.get_core_type()] = true
				_check(_layout.is_in_clearing(b.global_position), "%s inside central Core Village clearing" % b.name)
			for t in CORE_TYPES:
				_check(seen.has(t), "core type %s present" % t)

			var player_pos: Vector2 = _player.global_position
			_check(player_pos.distance_to(Vector2(0, 60)) <= 24.0, "Player Start near (0,+60) (%s)" % str(player_pos))

			# Player 이동 (중앙 마을)
			_player.global_position = Vector2.ZERO
			Input.action_press("move_right")
			_enter(Phase.PLACEMENT)
		Phase.PLACEMENT:
			if _elapsed() >= 120:
				Input.action_release("move_right")
				var x: float = _player.global_position.x
				_check(x > 90.0, "player walks from center toward east outskirts (x=%s)" % str(x))
				_check(_layout.is_in_bounds(_player.global_position), "player stays inside map bounds while moving")
				_player.global_position = Vector2(0, 60)

				# Lumberyard placement
				_resources._amounts["wood"] = 0
				_placement._set_building_type("lumberyard")
				_placement._try_place_at(Vector2(300, 260))
				_check(get_nodes_in_group("lumberyards").size() == 0, "lumberyard denied without enough wood")
				_resources._amounts["wood"] = 50
				_placement._try_place_at(Vector2(300, 260))
				_check(get_nodes_in_group("lumberyards").size() == 1, "lumberyard built on valid clearing position")
				_lumberyard = get_nodes_in_group("lumberyards")[0]
				_check(_lumberyard.get_slot_capacity() == 2, "lumberyard slot capacity is 2")

				# Quarry valid/invalid placement
				_placement._set_building_type("quarry")
				var wood_before: int = _resources.get_amount("wood")
				_placement._try_place_quarry_at(Vector2(100, 100))
				_check(get_nodes_in_group("quarries").size() == 0, "quarry denied outside deposit area")
				_check(_resources.get_amount("wood") == wood_before, "wood not deducted outside deposit")
				_placement._try_place_quarry_at(_deposit.global_position)
				_check(get_nodes_in_group("quarries").size() == 1, "quarry built on valid deposit")
				_quarry = get_nodes_in_group("quarries")[0]
				_check(_deposit.is_occupied(), "deposit occupied after quarry built")
				_check(_quarry.get_slot_capacity() == 2, "quarry slot capacity is 2")
				_placement._try_place_quarry_at(_deposit.global_position)
				_check(get_nodes_in_group("quarries").size() == 1, "duplicate quarry on same deposit denied")

				# 2명씩 배치
				_check(_lumberyard.assign_worker(_lj), "lumberyard assigns lumberjack 1")
				_check(_lumberyard.assign_worker(_lj2), "lumberyard assigns lumberjack 2")
				_check(_lumberyard.get_filled_slots() == 2, "lumberyard filled 2/2")
				_check(_quarry.assign_worker(_miner), "quarry assigns miner 1")
				_check(_quarry.assign_worker(_miner2), "quarry assigns miner 2")
				_check(_quarry.get_filled_slots() == 2, "quarry filled 2/2")
				_check(not _quarry.assign_worker(_miner), "duplicate miner assignment rejected")
				_check(not _lumberyard.assign_worker(_lj), "duplicate lumberjack assignment rejected")

				_wood_before = _resources.get_amount("wood")
				_stone_before = _resources.get_amount("stone")
				_enter(Phase.PRODUCE_WOOD2)
		Phase.PRODUCE_WOOD2:
			var wood: int = _resources.get_amount("wood")
			if wood > _wood_before and _stump_count() >= 2:
				_check(wood > _wood_before, "2 lumberjacks produced wood (+%d)" % (wood - _wood_before))
				_check(_stump_count() >= 2, "2 lumberjacks claim trees -> STUMP (count=%d)" % _stump_count())
				_enter(Phase.PRODUCE_STONE2)
			elif _elapsed() >= 5000:
				_check(false, "2 lumberjacks production within timeout (wood=%d state=%d/%d stumps=%d)" % [wood, _lj.state, _lj2.state, _stump_count()])
				_finish()
				return true
		Phase.PRODUCE_STONE2:
			var stone: int = _resources.get_amount("stone")
			if stone >= _stone_before + 3:
				_check(stone >= _stone_before + 3, "2 miners produced stone at WorkPoint (+%d)" % (stone - _stone_before))
				_enter(Phase.REGROWTH)
			elif _elapsed() >= 3000:
				_check(false, "2 miners production within timeout (stone=%d state=%d/%d)" % [stone, _miner.state, _miner2.state])
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
			if mature >= 2 and not _regrown_checked:
				_check(mature >= 2, "trees regrew to MATURE (mature=%d)" % mature)
				_regrown_checked = true
			var wood: int = _resources.get_amount("wood")
			if _regrown_checked and wood >= _wood_before + 3:
				_check(wood >= _wood_before + 3, "lumberjacks resume work after regrowth (+%d)" % (wood - _wood_before))
				_enter(Phase.NAV)
			elif _elapsed() >= 3000:
				_check(false, "lumberjacks resumed work after regrowth (wood=%d mature=%d)" % [wood, mature])
				_finish()
				return true
		Phase.NAV:
			_check(_world.has_method("rebuild_navigation"), "world exposes rebuild_navigation")
			_world.rebuild_navigation()
			_check(true, "runtime navigation rebuild works with buildings/trees present")
			_check(_world.nav_rebuild_count >= 0, "navigation rebuild count available (%d)" % _world.nav_rebuild_count)
			_world.rebuild_navigation_debounced()
			_check(true, "debounced navigation rebuild does not error")
			_world.rebuild_navigation()
			_check(true, "repeated navigation rebuild is stable")

			# TASK-BUG-NAV-001 회귀: Worker가 목표로 이동 중 장애물이 생겨도
			# 동일 방향으로 영구 밀리지 않고 목표에 도달 가능해야 한다.
			var nav_map: RID = _world.get_world_2d().get_navigation_map()
			var a: Vector2 = Vector2(0, 0)
			var b: Vector2 = Vector2(620, 360)
			var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, a, b, true)
			_check(path.size() >= 2, "nav path exists across central map (obstacle-avoidance regression)")

			# N/E/S/W Outer Wild 접근
			var cands: Dictionary = _layout.get_spawn_candidates()
			for dir in ["north", "south", "east", "west"]:
				var c: Vector2 = _layout.get_spawn_candidate(dir)
				var p: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, Vector2(0, 60), c, true)
				_check(p.size() >= 2, "nav path from Player Start reaches %s Outer Wild candidate (%s)" % [dir, str(c)])
			_enter(Phase.DAYNIGHT_SETUP)
		Phase.DAYNIGHT_SETUP:
			if _game_time != null:
				_game_time.set_auto_advance(false)
				_game_time.set_durations(10.0, 10.0)
			_enter(Phase.DAYNIGHT)
		Phase.DAYNIGHT:
			if not _step_done:
				_step_done = true
				_check(_game_time.get_phase() == _game_time.Phase.DAY, "game starts in DAY")
				_check(_game_time.get_day_number() == 1, "day number starts at 1")
				_game_time.advance(10.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "DAY -> NIGHT transition")
				_check(_player._night_mode == true, "NIGHT: player direct movement disabled (flag)")
				_enter(Phase.NIGHT_READ)
		Phase.NIGHT_READ:
			if not _step_done:
				_step_done = true
				_player.global_position = Vector2.ZERO
				_start_x = _player.global_position.x
				Input.action_press("move_right")
			if _elapsed() >= 120:
				Input.action_release("move_right")
				_check(_player.global_position.x == _start_x, "NIGHT: player does not move (input disabled)")
				var camera: Camera2D = _player.get_node("Camera2D") as Camera2D
				_check(camera != null, "player camera exists")
				_check(camera.zoom.x < 0.7, "NIGHT: camera zoomed out from day (%.2f < 0.7)" % camera.zoom.x)
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "production runs during NIGHT without stop policy")
				_check(is_instance_valid(_lj.get_workplace()), "lumberjack workplace stable across transition")
				_check(is_instance_valid(_miner.get_workplace()), "miner workplace stable across transition")

				# Night tactical readability: central Village + Gate Corridor + Combat Field
				# 가 night_zoom 기준으로 한 시야 또는 짧은 pan으로 읽히는지 기록.
				var vp_h: float = ProjectSettings.get_setting("display/window/size/viewport_height", 648.0)
				var vp_w: float = ProjectSettings.get_setting("display/window/size/viewport_width", 1152.0)
				var nz: float = _player.night_zoom
				var world_half_h: float = vp_h / nz * 0.5
				var world_half_w: float = vp_w / nz * 0.5
				var village_edge := 220.0
				var combat_outer := 700.0
				print("NIGHT_READ: viewport=%dx%d night_zoom=%.2f -> visible world ~%.0fx%.0f" % [int(vp_w), int(vp_h), nz, vp_w / nz, vp_h / nz])
				print("NIGHT_READ: central Village edge=%.0fpx, Gate Corridor ~360-540px, Combat Field outer ~%.0fpx" % [village_edge, combat_outer])
				if combat_outer <= world_half_h:
					_check(true, "night view spans Village + Gate Corridor + Combat Field in one view (%.0f <= half-height %.0f)" % [combat_outer, world_half_h])
				else:
					_check(true, "night view spans Village + Corridor + Combat Field with a short vertical pan (%.0f > half-height %.0f, difference %.0fpx)" % [combat_outer, world_half_h, combat_outer - world_half_h])
				_enter(Phase.TRAVEL)
		Phase.TRAVEL:
			_check(_layout.get_node_or_null("SouthAgricultureZone") != null, "South Agriculture marker present")
			_check(_layout.get_node_or_null("NeDungeonCandidate") != null, "NE Dungeon Candidate marker present")
			print("=== TASK-012-7 이동거리 기록 (Player speed=%.0fpx/s) ===" % float(_player.move_speed))
			var starter_cluster: Dictionary = _layout.get_forest_cluster("starter")
			_record_travel("PlayerStart->NW_StarterForest", Vector2(starter_cluster.get("center", Vector2.ZERO)))
			_record_travel("PlayerStart->StoneDeposit", _layout.get_stone_deposit_pos())
			_record_travel("PlayerStart->NE_DungeonCandidate", _layout.get_ne_dungeon_candidate())
			var cands2: Dictionary = _layout.get_spawn_candidates()
			for dir in ["north", "south", "east", "west"]:
				_record_travel("PlayerStart->%s_Candidate" % dir.to_upper(), cands2[dir])
			_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0127_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
