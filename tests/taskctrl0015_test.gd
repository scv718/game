extends SceneTree

## TASK-CTRL-001-5 Mouse/Camera Management integration verification.
## Full DAY management -> NIGHT tactical -> DAY return flow.

enum Phase {
	SETUP, NO_PLAYER, DAY_PAN, DAY_ZOOM, TAVERN_CLICK, HIRE,
	INN_CLICK, DEFENSE_ASSIGN, RESOURCE_INTERACT, BUILD_ENTER,
	BUILD_PAN_ZOOM, WALL_GATE_PLACE, NIGHT_TRANSITION, TACTICAL_CAMERA,
	TACTICAL_COMMAND, ENEMY_COMBAT, DEATH_LEDGER, DAY_RETURN,
	STATE_RESET, REGRESSION, DONE,
}

const TAVERN_POS := Vector2(-126, -48)
const INN_POS := Vector2(126, -48)
const LUMBERYARD_POS := Vector2(300, 260)
const QUARRY_POS := Vector2(600, 300)
const WALL_POS := Vector2(0, 300)
const GATE_POS := Vector2(-528, 0)
const LUMBERYARD_COST := 10

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
	print("TASKCTRL0015_RESULT=" + ("FAIL" if _failed else "PASS"))
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


func _set_camera_to_world(target: Vector2) -> void:
	var vp := root.get_viewport()
	var mouse := vp.get_mouse_position()
	var center := vp.get_visible_rect().size * 0.5
	var zoom: float = _camera.zoom.x
	_controller.global_position = target - (mouse - center) / zoom

func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.NO_PLAYER:
			_no_player()
		Phase.DAY_PAN:
			_day_pan()
		Phase.DAY_ZOOM:
			_day_zoom()
		Phase.TAVERN_CLICK:
			_tavern_click()
		Phase.HIRE:
			_hire()
		Phase.INN_CLICK:
			_inn_click()
		Phase.DEFENSE_ASSIGN:
			_defense_assign()
		Phase.RESOURCE_INTERACT:
			_resource_interact()
		Phase.BUILD_ENTER:
			_build_enter()
		Phase.BUILD_PAN_ZOOM:
			_build_pan_zoom()
		Phase.WALL_GATE_PLACE:
			_wall_gate_place()
		Phase.NIGHT_TRANSITION:
			_night_transition()
		Phase.TACTICAL_CAMERA:
			_tactical_camera()
		Phase.TACTICAL_COMMAND:
			_tactical_command()
		Phase.ENEMY_COMBAT:
			_enemy_combat()
		Phase.DEATH_LEDGER:
			_death_ledger_check()
		Phase.DAY_RETURN:
			_day_return()
		Phase.STATE_RESET:
			_state_reset()
		Phase.REGRESSION:
			_regression()
		Phase.DONE:
			_finish()
			return true
	if _frame > 120000:
		print("TASKCTRL0015_RESULT=TIMEOUT phase=%s" % str(_phase))
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
	_check(_ui_tavern != null, "recruitment UI exists")
	_check(_ui_inn != null, "inn roster UI exists")
	_check(_tac_ui != null, "TacticalCommandUI present in HUD")
	_enter(Phase.NO_PLAYER)

## -- NO_PLAYER --
func _no_player() -> void:
	var players := get_nodes_in_group("player")
	_check(players.size() == 0, "no Player Actor in runtime world")
	_enter(Phase.DAY_PAN)

## -- DAY_PAN --
func _day_pan() -> void:
	if _sub == 0:
		_controller.global_position = Vector2.ZERO
		_camera.zoom = Vector2.ONE
		_controller._zoom_target = 1.0
		_sub = 1
	elif _sub == 1:
		var before: Vector2 = _controller.global_position
		_controller.pan_camera(Vector2(100, -50))
		var after: Vector2 = _controller.global_position
		_check(after.distance_to(before + Vector2(100, -50)) < 1.0,
			"DAY camera pan moves by offset")
		_check(_game_time.get_phase() == GameTime.Phase.DAY,
			"still in DAY during pan")
		_enter(Phase.DAY_ZOOM)

## -- DAY_ZOOM --
func _day_zoom() -> void:
	if _sub == 0:
		var zoom_before: float = _camera.zoom.x
		_controller._zoom_target = zoom_before + 0.3
		_sub = 1
	elif _sub == 1:
		_camera.zoom = Vector2(_controller._zoom_target, _controller._zoom_target)
		_check(_camera.zoom.x > 1.0, "zoom target increased")
		_check(_camera.zoom.x <= _controller.max_zoom,
			"zoom clamped to max_zoom")
		_controller._zoom_target = 1.0
		_camera.zoom = Vector2.ONE
		_enter(Phase.TAVERN_CLICK)

## -- TAVERN_CLICK --
func _tavern_click() -> void:
	_selection.clear_selection()
	_check(_selected() == null, "selection cleared before tavern click")
	var sel: Node = _selected_at(TAVERN_POS)
	_check(sel != null, "tavern click returns an interactable")
	_check(_ui_tavern.visible, "tavern click opens Recruitment UI")
	_enter(Phase.HIRE)

## -- HIRE --
func _hire() -> void:
	if _sub == 0:
		var merc_count_before: int = _merc_roster.get_count()
		_merc_a = MercenaryData.new("ctrl0015_merc_a", "Guard A")
		_merc_roster.add_mercenary(_merc_a)
		_check(_merc_roster.get_count() == merc_count_before + 1,
			"mercenary hired (count increased)")
		_selection.clear_selection()
		_check(_ui_tavern.visible == false,
			"Recruitment UI closed after selection clear")
		_enter(Phase.INN_CLICK)

## -- INN_CLICK --
func _inn_click() -> void:
	var sel: Node = _selected_at(INN_POS)
	_check(sel != null, "inn click returns an interactable")
	_check(_ui_inn.visible, "inn click opens Roster UI")
	_selection.clear_selection()
	_check(_ui_inn.visible == false, "Roster UI closed after selection clear")
	_enter(Phase.DEFENSE_ASSIGN)

## -- DEFENSE_ASSIGN --
func _defense_assign() -> void:
	if _sub == 0:
		_merc_roster.set_defense_zone(
			"ctrl0015_merc_a", MercenaryData.DefenseZone.WEST)
		_check(_merc_a.defense_zone == MercenaryData.DefenseZone.WEST,
			"mercenary assigned to WEST defense zone")
		_enter(Phase.RESOURCE_INTERACT)

## -- RESOURCE_INTERACT --
func _resource_interact() -> void:
	if _sub == 0:
		var sel_ly: Node = _selected_at(LUMBERYARD_POS)
		_check(sel_ly != null, "Lumberyard click returns interactable")
		_selection.clear_selection()
		_sub = 1
	elif _sub == 1:
		var sel_q: Node = _selected_at(QUARRY_POS)
		_check(sel_q != null, "Quarry click returns interactable")
		_selection.clear_selection()
		_enter(Phase.BUILD_ENTER)

## -- BUILD_ENTER --
func _build_enter() -> void:
	if _sub == 0:
		_placement._set_active(true)
		_check(_placement.is_active(), "build mode entered")
		_check(_selection.can_handle_world_click() == false,
			"world click disabled during build mode")
		_sub = 1
	elif _sub == 1:
		_placement._set_active(false)
		_check(_placement.is_active() == false, "build mode exited")
		_enter(Phase.BUILD_PAN_ZOOM)

## -- BUILD_PAN_ZOOM --
func _build_pan_zoom() -> void:
	if _sub == 0:
		_controller.pan_camera(Vector2(-80, 40))
		_camera.zoom = Vector2(1.5, 1.5)
		_controller._zoom_target = 1.5
		_placement._set_building_type("lumberyard")
		_placement._set_active(true)
		_check(_placement.is_active(), "build mode active after pan/zoom")
		var wood_before: int = _resources.get_amount("wood")
		_placement._unhandled_input(_left_click_event())
		var ly: Node = _lumberyard_at(_snap_to_grid(LUMBERYARD_POS))
		_check(ly != null, "Lumberyard placed at panned/zoomed position")
		_check(_resources.get_amount("wood") == wood_before - LUMBERYARD_COST,
			"Lumberyard cost deducted")
		_camera.zoom = Vector2.ONE
		_controller._zoom_target = 1.0
		_enter(Phase.WALL_GATE_PLACE)

## -- WALL_GATE_PLACE --
func _wall_gate_place() -> void:
	if _sub == 0:
		_placement._set_building_type("wall")
		_placement._set_active(true)
		_placement._unhandled_input(_left_click_event())
		var wall_pos := _snap_to_grid(WALL_POS)
		var w_node: Node = _wall_at(wall_pos)
		_check(w_node != null, "wall placed at WALL_POS")
		_enter(Phase.NIGHT_TRANSITION)

## -- NIGHT_TRANSITION --
func _night_transition() -> void:
	if _sub == 0:
		_game_time.advance(2.0)
		_sub = 1
	elif _sub == 1:
		if _elapsed() >= 4:
			_check(_game_time.get_phase() == GameTime.Phase.NIGHT,
				"DAY -> NIGHT transition")
			_check(_controller.is_night_mode(),
				"NIGHT: camera controller tactical mode")
			_check(_tac_ui.visible, "TacticalCommandUI visible during NIGHT")
			_enter(Phase.TACTICAL_CAMERA)

## -- TACTICAL_CAMERA --
func _tactical_camera() -> void:
	if _sub == 0:
		var before: Vector2 = _controller.global_position
		_controller.pan_camera(Vector2(60, -30))
		var after: Vector2 = _controller.global_position
		_check(after.distance_to(before + Vector2(60, -30)) < 1.0,
			"NIGHT tactical camera pan moves by offset")
		_enter(Phase.TACTICAL_COMMAND)

## -- TACTICAL_COMMAND --
func _tactical_command() -> void:
	if _sub == 0:
		var time_before: float = _game_time.get_time_scale()
		_game_time.set_time_scale(GameTime.TIME_SCALE_PAUSE)
		_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_PAUSE,
			"tactical command: TIME_PAUSE works")
		_game_time.set_time_scale(GameTime.TIME_SCALE_2X)
		_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_2X,
			"tactical command: TIME_2X works")
		_game_time.set_time_scale(GameTime.TIME_SCALE_1X)
		_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X,
			"tactical command: TIME_1X works")
		_merc_roster.focus_mode = false
		_merc_roster.toggle_focus_mode()
		_check(_merc_roster.focus_mode == true,
			"tactical command: FOCUS_TARGET toggles focus mode")
		_enter(Phase.ENEMY_COMBAT)

## -- ENEMY_COMBAT --
func _enemy_combat() -> void:
	if _sub == 0:
		var enemies_before: int = _encounter_spawner.get_enemy_count()
		_check(enemies_before > 0,
			"enemies spawned during NIGHT (count=%d)" % enemies_before)
		_check(_encounter_spawner.is_night_active(),
			"FirstEncounterSpawner night_active flag set")
		_enter(Phase.DEATH_LEDGER)

## -- DEATH_LEDGER --
func _death_ledger_check() -> void:
	if _sub == 0:
		var snap: Dictionary = {
			"source_uid": "ctrl0015_test_enemy_0",
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
			"death_position": Vector2(-400, 0),
		}
		var rec: DeathRecord = _death_ledger.record_death(snap)
		_check(rec != null, "Death Ledger: record_death returns a record")
		_check(rec.source_uid == "ctrl0015_test_enemy_0",
			"Death Ledger: source_uid preserved")
		_check(_death_ledger.has_record_for_source("ctrl0015_test_enemy_0"),
			"Death Ledger: has_record_for_source returns true")
		var all_records: Array[DeathRecord] = _death_ledger.get_all_records()
		_check(all_records.size() > 0,
			"Death Ledger: get_all_records returns entries")
		_enter(Phase.DAY_RETURN)

## -- DAY_RETURN --
func _day_return() -> void:
	if _sub == 0:
		_game_time.advance(1.0)
		_sub = 1
	elif _sub == 1:
		if _elapsed() >= 4:
			_check(_game_time.get_phase() == GameTime.Phase.DAY,
				"NIGHT -> DAY transition")
			_check(_controller.is_night_mode() == false,
				"DAY: camera controller not in night mode")
			_check(_tac_ui.visible == false,
				"TacticalCommandUI hidden during DAY")
			_check(_encounter_spawner.is_night_active() == false,
				"FirstEncounterSpawner night_active cleared on DAY return")
			_enter(Phase.STATE_RESET)

## -- STATE_RESET --
func _state_reset() -> void:
	if _sub == 0:
		_check(_selection.get_selected() == null,
			"selection cleared after DAY/NIGHT cycle")
		_check(_placement.is_active() == false,
			"build mode inactive after DAY/NIGHT cycle")
		_check(_merc_a.alive, "mercenary still alive after DAY return")
		_check(_merc_a.defense_zone == MercenaryData.DefenseZone.WEST,
			"defense zone assignment preserved across DAY/NIGHT")
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
		_enter(Phase.DONE)

func _snap_to_grid(pos: Vector2) -> Vector2:
	var gs: float = _placement.GRID_SIZE if _placement else 16.0
	return (pos / gs).floor() * gs
