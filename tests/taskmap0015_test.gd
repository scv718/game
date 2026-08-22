extends SceneTree

## TASK-MAP-001-5 192x192 World Integration Verification.
## Full regression across Camera, Selection, Building, Worker, Combat, Death Ledger
## on the expanded 192x192 world.

enum Phase {
	SETUP, NO_PLAYER, FLOOR_BOUNDS, CAMERA_BOUNDARY, SELECTION_BASIC,
	PAN_ZOOM_COORDS, BUILD_OUTER, NAV_OUTER, WORKER_PRODUCTION,
	WEST_ENEMY, WALL_GATE, TACTICAL_COMBAT, DEATH_LEDGER,
	REPEATED_DAY_NIGHT, REGRESSION, DONE,
}

const TAVERN_POS := Vector2(-126, -48)
const INN_POS := Vector2(126, -48)
const LUMBERYARD_POS := Vector2(300, 260)
const QUARRY_POS := Vector2(600, 300)
const WALL_POS := Vector2(800, 800)
const GATE_POS := Vector2(-528, 0)
const LUMBERYARD_COST := 10

const OUTER_BUILD_POS := Vector2(1000, 1000)
const OUTER_NAV_POS := Vector2(800, 700)

const WEST_SPAWN_POS := Vector2(-1440, 200)

var _frame := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _sub := 0
var _phase_start := 0

var _main: Node = null
var _world: Node = null
var _selection: Node = null
var _placement: Node = null
var _game_time: Node = null
var _resources: Node = null
var _controller: Node = null
var _camera: Camera2D = null
var _hud: Node = null
var _merc_roster: Node = null
var _death_ledger: Node = null
var _encounter_spawner: Node = null
var _tac_ui: Node = null
var _ui_tavern: Control = null
var _ui_inn: Control = null
var _merc_a: MercenaryData = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_sub = 0
	_phase_start = _frame


func _elapsed() -> int:
	return _frame - _phase_start


func _finish() -> void:
	print("TASKMAP0015_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _selected() -> Node:
	return _selection.get_selected() as Node if _selection != null else null


func _selected_at(pos: Vector2) -> Node:
	return _selection.select_at_world_position(pos) as Node if _selection != null else null


func _left_click_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


func _right_click_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	return ev


func _esc_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	return ev


func _key_event(key: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = true
	return ev


func _wall_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("walls"):
		if not is_instance_valid(node):
			continue
		var w := node as Node2D
		if w != null and w.position.distance_to(pos) < 1.0:
			return node
	return null


func _gate_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("gates"):
		if not is_instance_valid(node):
			continue
		var g := node as Node2D
		if g != null and g.position.distance_to(pos) < 1.0:
			return node
	return null


func _lumberyard_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("lumberyards"):
		if not is_instance_valid(node):
			continue
		var ly := node as Node2D
		if ly != null and ly.position.distance_to(pos) < 1.0:
			return node
	return null


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.NO_PLAYER:
			_no_player()
		Phase.FLOOR_BOUNDS:
			_floor_bounds()
		Phase.CAMERA_BOUNDARY:
			_camera_boundary()
		Phase.SELECTION_BASIC:
			_selection_basic()
		Phase.PAN_ZOOM_COORDS:
			_pan_zoom_coords()
		Phase.BUILD_OUTER:
			_build_outer()
		Phase.NAV_OUTER:
			_nav_outer()
		Phase.WORKER_PRODUCTION:
			_worker_production()
		Phase.WEST_ENEMY:
			_west_enemy()
		Phase.WALL_GATE:
			_wall_gate()
		Phase.TACTICAL_COMBAT:
			_tactical_combat()
		Phase.DEATH_LEDGER:
			_death_ledger_check()
		Phase.REPEATED_DAY_NIGHT:
			_repeated_day_night()
		Phase.REGRESSION:
			_regression()
		Phase.DONE:
			_finish()
			return true
	if _frame > 150000:
		print("TASKMAP0015_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


## -- SETUP --
func _setup() -> void:
	if _frame < 8:
		return
	_main = root.get_node("Main")
	_world = _main.get_node("World")
	_selection = _main.get_node("WorldSelection")
	_placement = _main.get_node("BuildingPlacement")
	_game_time = root.get_node("GameTime")
	_resources = root.get_node("VillageResources")
	_merc_roster = root.get_node("MercenaryRoster")
	_death_ledger = root.get_node("DeathLedger")
	_encounter_spawner = root.get_node("FirstEncounterSpawner")
	var ctrls := get_nodes_in_group("camera_controller")
	_controller = ctrls[0] if ctrls.size() > 0 else null
	_camera = _controller.get_camera() as Camera2D if _controller else null
	_hud = _main.get_node("HUD")
	_ui_tavern = get_first_node_in_group("recruitment_ui") as Control
	_ui_inn = get_first_node_in_group("inn_roster_ui") as Control
	_tac_ui = _hud.get_node_or_null("TacticalCommandUI")

	_game_time.set_auto_advance(false)
	_game_time.set_durations(2.0, 1.0)
	_resources._amounts["wood"] = 10000
	_resources._amounts["stone"] = 10000

	_check(_main != null, "main.tscn loads")
	_check(_world != null, "World node exists")
	_check(_selection != null, "WorldSelection exists")
	_check(_placement != null, "BuildingPlacement exists")
	_check(_game_time != null, "GameTime autoload exists")
	_check(_resources != null, "VillageResources autoload exists")
	_check(_controller != null, "CameraController exists")
	_check(_camera != null, "Camera2D exists")
	_check(_hud != null, "HUD exists")
	_check(_merc_roster != null, "MercenaryRoster autoload exists")
	_check(_death_ledger != null, "DeathLedger autoload exists")
	_check(_encounter_spawner != null, "FirstEncounterSpawner autoload exists")
	_check(_game_time.get_phase() == GameTime.Phase.DAY, "starts in DAY")
	_enter(Phase.NO_PLAYER)


## -- NO_PLAYER --
func _no_player() -> void:
	var players := get_nodes_in_group("player")
	_check(players.size() == 0, "no Player Actor in runtime world")
	_enter(Phase.FLOOR_BOUNDS)


## -- FLOOR_BOUNDS --
func _floor_bounds() -> void:
	if _sub == 0:
		var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
		_check(floor_node != null, "Floor TileMapLayer exists")
		var cell_count: int = floor_node.get_used_cells().size()
		_check(cell_count >= 128 * 128,
			"floor covers at least 128x128 tiles (%d)" % cell_count)
		var layout := _world.get_node_or_null("MapLayout")
		_check(layout != null, "MapLayout exists")
		if layout != null:
			var bounds: Rect2 = layout.get_bounds_rect()
			_check(bounds.size.x == 3072 and bounds.size.y == 3072,
				"MapLayout bounds = 3072x3072 (%s)" % str(bounds))
			var nav_rect: Rect2 = layout.get_nav_rect()
			_check(nav_rect.size.x > 2900 and nav_rect.size.y > 2900,
				"nav rect covers expanded world (%s)" % str(nav_rect))
		_sub = 1
	elif _sub == 1:
		var boundaries := 0
		for child in _world.get_children():
			if child.name.begins_with("BoundaryWall_"):
				boundaries += 1
		_check(boundaries == 4, "4 boundary walls present (%d)" % boundaries)
		_enter(Phase.CAMERA_BOUNDARY)


## -- CAMERA_BOUNDARY --
func _camera_boundary() -> void:
	if _sub == 0:
		var bounds: Rect2 = _controller.get_world_bounds()
		_check(bounds.size.x == 3072 and bounds.size.y == 3072,
			"camera world bounds = 3072x3072 (%s)" % str(bounds))
		_controller.global_position = Vector2.ZERO
		_camera.zoom = Vector2.ONE
		_controller._zoom_target = 1.0
		# Pan to extreme corners and verify clamp via pan_camera
		_controller.pan_camera(Vector2(9999, 9999))
		var pos_clamped: Vector2 = _controller.global_position
		_check(pos_clamped.x <= 1536 and pos_clamped.y <= 1536,
			"camera clamped at top-right via pan_camera (%s)" % str(pos_clamped))
		_controller.pan_camera(Vector2(-19999, -19999))
		pos_clamped = _controller.global_position
		_check(pos_clamped.x >= -1536 and pos_clamped.y >= -1536,
			"camera clamped at bottom-left via pan_camera (%s)" % str(pos_clamped))
		_controller.global_position = Vector2.ZERO
		# Move to outer region and verify it works
		_controller.pan_camera(Vector2(1200, 1200))
		_check(_controller.global_position.distance_to(Vector2(1200, 1200)) < 1.0,
			"camera moves to outer region (1200,1200)")
		_controller.pan_camera(Vector2(-2400, -2400))
		_check(_controller.global_position.distance_to(Vector2(-1200, -1200)) < 1.0,
			"camera moves to outer region (-1200,-1200)")
		_controller.global_position = Vector2.ZERO
		_camera.zoom = Vector2.ONE
		_controller._zoom_target = 1.0
		_enter(Phase.SELECTION_BASIC)


## -- SELECTION_BASIC --
func _selection_basic() -> void:
	if _sub == 0:
		var sel: Node = _selected_at(TAVERN_POS)
		_check(sel != null, "tavern click returns interactable")
		_check(_ui_tavern.visible, "tavern click opens Recruitment UI")
		_selection.clear_selection()
		_ui_tavern.close()
		_sub = 1
	elif _sub == 1:
		var sel: Node = _selected_at(INN_POS)
		_check(sel != null, "inn click returns interactable")
		_check(_ui_inn.visible, "inn click opens Roster UI")
		_selection.clear_selection()
		_ui_inn.close()
		_sub = 2
	elif _sub == 2:
		_merc_a = MercenaryData.new("map0015_merc_a", "Guard A")
		_merc_roster.add_mercenary(_merc_a)
		_check(_merc_roster.get_count() >= 1, "mercenary hired")
		_merc_roster.set_defense_zone("map0015_merc_a", MercenaryData.DefenseZone.WEST)
		_check(_merc_a.defense_zone == MercenaryData.DefenseZone.WEST,
			"mercenary assigned to WEST defense zone")
		_enter(Phase.PAN_ZOOM_COORDS)


## -- PAN_ZOOM_COORDS --
func _pan_zoom_coords() -> void:
	if _sub == 0:
		_controller.global_position = Vector2.ZERO
		_camera.zoom = Vector2.ONE
		_controller._zoom_target = 1.0
		_controller.pan_camera(Vector2(800, 600))
		_check(_controller.global_position.distance_to(Vector2(800, 600)) < 1.0,
			"pan to outer coordinates (800,600)")
		_sub = 1
	elif _sub == 1:
		_controller._zoom_target = 0.5
		_camera.zoom = Vector2(0.5, 0.5)
		_controller.pan_camera(Vector2(600, 600))
		var expected := Vector2(1400, 1200)
		_check(_controller.global_position.distance_to(expected) < 2.0,
			"pan+zoom to outer (1400,1200) within tolerance (%s)" % str(_controller.global_position))
		_camera.zoom = Vector2.ONE
		_controller._zoom_target = 1.0
		_controller.global_position = Vector2.ZERO
		_enter(Phase.BUILD_OUTER)


## -- BUILD_OUTER --
func _build_outer() -> void:
	if _sub == 0:
		_placement._set_building_type("lumberyard")
		_controller.global_position = Vector2.ZERO
		_camera.zoom = Vector2.ONE
		_controller._zoom_target = 1.0
		var wood_before: int = _resources.get_amount("wood")
		# Use direct placement method (headless mouse position is 0,0)
		_placement._try_place_at(_snap_to_grid(OUTER_BUILD_POS))
		var ly: Node = _lumberyard_at(_snap_to_grid(OUTER_BUILD_POS))
		_check(ly != null, "lumberyard placed at outer position (1000,1000)")
		_check(_resources.get_amount("wood") == wood_before - LUMBERYARD_COST,
			"lumberyard cost deducted at outer position")
		_enter(Phase.NAV_OUTER)


## -- NAV_OUTER --
func _nav_outer() -> void:
	if _sub == 0:
		var nav_map: RID = _world.get_world_2d().get_navigation_map()
		var from := Vector2.ZERO
		var to := OUTER_NAV_POS
		var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, from, to, true)
		_check(path.size() >= 2, "nav path from center to outer (800,700) exists (%d points)" % path.size())
		_sub = 1
	elif _sub == 1:
		var nav_map: RID = _world.get_world_2d().get_navigation_map()
		var from := Vector2(-1200, -1200)
		var to := Vector2(1200, 1200)
		var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, from, to, true)
		_check(path.size() >= 2, "cross-world nav (-1200,-1200) to (1200,1200) exists (%d points)" % path.size())
		_enter(Phase.WORKER_PRODUCTION)


## -- WORKER_PRODUCTION --
func _worker_production() -> void:
	if _sub == 0:
		if get_nodes_in_group("lumberjacks").size() < 1:
			var lj: Node = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			lj.position = Vector2(300, 200)
			_world.add_child(lj)
		if get_nodes_in_group("miners").size() < 1:
			var mn: Node = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			mn.position = Vector2(500, 140)
			_world.add_child(mn)
		_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack present for production")
		_check(get_nodes_in_group("miners").size() >= 1, "miner present")
		_check(get_nodes_in_group("stone_deposits").size() >= 1, "stone deposit present")
		_enter(Phase.WEST_ENEMY)


## -- WEST_ENEMY --
func _west_enemy() -> void:
	if _sub == 0:
		_game_time.advance(2.0)
		_sub = 1
	elif _sub == 1:
		if _elapsed() >= 4:
			_check(_game_time.get_phase() == GameTime.Phase.NIGHT,
				"DAY -> NIGHT transition for west enemy")
			var enemy_count: int = _encounter_spawner.get_enemy_count()
			_check(enemy_count > 0,
				"enemies spawned from WEST (count=%d)" % enemy_count)
			_check(_encounter_spawner.is_night_active(),
				"FirstEncounterSpawner night_active set")
			_check(_encounter_spawner.get_direction() == "west",
				"encounter direction is west")
			_enter(Phase.WALL_GATE)


## -- WALL_GATE --
func _wall_gate() -> void:
	if _sub == 0:
		# Place wall directly via API
		_placement._set_building_type("wall")
		var wall_pos := _snap_to_grid(WALL_POS)
		_placement._try_place_wall_at(wall_pos)
		var w_node: Node = _wall_at(wall_pos)
		_check(w_node != null, "wall placed at WALL_POS during expanded world")
		_sub = 1
	elif _sub == 1:
		# Place gate directly via API
		_placement._set_building_type("gate")
		var gate_pos: Vector2 = _placement._snap_gate(GATE_POS)
		_placement._try_place_gate_at(gate_pos)
		var gate_node: Node = _gate_at(gate_pos)
		_check(gate_node != null, "gate placed at GATE_POS during expanded world")
		_enter(Phase.TACTICAL_COMBAT)


## -- TACTICAL_COMBAT --
func _tactical_combat() -> void:
	if _sub == 0:
		var before: Vector2 = _controller.global_position
		_controller.pan_camera(Vector2(60, -30))
		var after: Vector2 = _controller.global_position
		_check(after.distance_to(before + Vector2(60, -30)) < 1.0,
			"tactical camera pan works on expanded world")
		_sub = 1
	elif _sub == 1:
		_game_time.set_time_scale(GameTime.TIME_SCALE_PAUSE)
		_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_PAUSE,
			"TIME_PAUSE works")
		_game_time.set_time_scale(GameTime.TIME_SCALE_2X)
		_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_2X,
			"TIME_2X works")
		_game_time.set_time_scale(GameTime.TIME_SCALE_1X)
		_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X,
			"TIME_1X works")
		_sub = 2
	elif _sub == 2:
		var merc_actors := get_nodes_in_group("mercenaries")
		_check(merc_actors.size() >= 1,
			"mercenary actor spawned during NIGHT (%d)" % merc_actors.size())
		_enter(Phase.DEATH_LEDGER)


## -- DEATH_LEDGER --
func _death_ledger_check() -> void:
	if _sub == 0:
		var snap: Dictionary = {
			"source_uid": "map0015_test_enemy_0",
			"source_kind": DeathRecord.SourceKind.ENEMY,
			"is_ghost": false,
			"display_name": "Test Raider",
			"class_or_type": "Raider",
			"level": 1,
			"max_hp": 60,
			"attack_damage": 8,
			"attack_interval": 1.0,
			"move_speed": 90.0,
			"death_day": _game_time.get_day_number(),
			"death_phase": 1,
			"death_position": WEST_SPAWN_POS,
		}
		var rec: DeathRecord = _death_ledger.record_death(snap)
		_check(rec != null, "Death Ledger: record_death returns a record")
		_check(rec.source_uid == "map0015_test_enemy_0",
			"Death Ledger: source_uid preserved")
		_check(_death_ledger.has_record_for_source("map0015_test_enemy_0"),
			"Death Ledger: has_record_for_source true")
		var all_records: Array[DeathRecord] = _death_ledger.get_all_records()
		_check(all_records.size() > 0,
			"Death Ledger: get_all_records returns entries")
		_enter(Phase.REPEATED_DAY_NIGHT)


## -- REPEATED_DAY_NIGHT --
func _repeated_day_night() -> void:
	if _sub == 0:
		_game_time.advance(1.0)
		_sub = 1
	elif _sub == 1:
		if _elapsed() >= 4:
			_check(_game_time.get_phase() == GameTime.Phase.DAY,
				"NIGHT -> DAY return (cycle 1)")
			_check(_controller.is_night_mode() == false,
				"camera controller back to DAY mode")
			_check(_tac_ui.visible == false,
				"TacticalCommandUI hidden during DAY")
			_check(_encounter_spawner.is_night_active() == false,
				"FirstEncounterSpawner night_active cleared")
			_sub = 2
	elif _sub == 2:
		_game_time.advance(2.0)
		_sub = 3
	elif _sub == 3:
		if _elapsed() >= 4:
			_check(_game_time.get_phase() == GameTime.Phase.NIGHT,
				"DAY -> NIGHT transition (cycle 2)")
			var enemy_count2: int = _encounter_spawner.get_enemy_count()
			_check(enemy_count2 > 0,
				"enemies spawned again in cycle 2 (count=%d)" % enemy_count2)
			_sub = 4
	elif _sub == 4:
		_game_time.advance(1.0)
		_sub = 5
	elif _sub == 5:
		if _elapsed() >= 4:
			_check(_game_time.get_phase() == GameTime.Phase.DAY,
				"NIGHT -> DAY return (cycle 2)")
			_check(get_nodes_in_group("camera_controller").size() == 1,
				"exactly 1 camera controller after 2 cycles")
			_check(get_nodes_in_group("world_selection").size() == 1,
				"exactly 1 world selection after 2 cycles")
			_check(get_nodes_in_group("building_placement").size() == 1,
				"exactly 1 building placement after 2 cycles")
			_enter(Phase.REGRESSION)


## -- REGRESSION --
func _regression() -> void:
	if _sub == 0:
		_check(get_nodes_in_group("world").size() >= 1,
			"smoke: world group intact")
		_check(get_nodes_in_group("camera_controller").size() == 1,
			"smoke: exactly 1 camera controller")
		_check(get_nodes_in_group("world_selection").size() == 1,
			"smoke: exactly 1 world selection")
		_check(get_nodes_in_group("building_placement").size() == 1,
			"smoke: exactly 1 building placement")
		_check(get_nodes_in_group("player").size() == 0,
			"smoke: no player group nodes")
		_check(_death_ledger.get_all_records().size() > 0,
			"smoke: death ledger records persist")
		_check(get_nodes_in_group("core_buildings").size() == 5,
			"smoke: 5 core buildings intact")
		_check(get_nodes_in_group("walls").size() >= 1,
			"smoke: walls present")
		_check(get_nodes_in_group("gates").size() >= 1,
			"smoke: gates present")
		_check(_selection.get_selected() == null,
			"selection cleared after full cycle")
		_check(_placement.is_active() == false,
			"build mode inactive after full cycle")
		_enter(Phase.DONE)


func _snap_to_grid(pos: Vector2) -> Vector2:
	var gs: float = _placement.GRID_SIZE if _placement else 16.0
	return (pos / gs).floor() * gs


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
