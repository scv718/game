extends SceneTree

## TASK-015-2 Tactical Command HUD 검증.## NIGHT 지휘 모드에서 표시되는 전술 명령 UI 셸이 DAY 숨김 / NIGHT 표시를 정상 처리하고,
## 각 명령 버튼(방어구역/집결/후퇴/집중공격/성문 개폐/시간 조작)이 command_issued 신호로
## 올바른 명령을 방출하는지, 성문 목록을 반영하는지 검증한다.
## 실제 명령 동작(AI/시간)은 TASK-015-3 ~ 015-6에서 구현하므로 이 태스크는 UI 셸만 검증한다.
##
## 자동검증 항목:
##  1. TacticalCommandUI가 HUD에 존재하고 DAY에서 숨김.
##  2. 방어구역 N/E/S/W 버튼이 DEFENSE_ZONE + 올바른 zone을 방출.
##  3. 집결/후퇴/집중공격 버튼이 각각 REGROUP/RETREAT/FOCUS_TARGET을 방출.
##  4. 성문 없음 시 "설치된 성문 없음" 표시.
##  5. 성문 배치 후 NIGHT 진입 → UI 표시 + 성문 행 생성 + OPEN/CLOSE가 GATE_OPEN/GATE_CLOSE 방출.
##  6. 전술 시간 Pause/1x/2x 버튼이 TIME_PAUSE/TIME_1X/TIME_2X 방출.
##  7. DAY 복귀 → UI 숨김(DAY reset).
##  8. 회귀: Player 무공격, 핵심 건물 5/floor/gate/기존 HUD 유지.

enum Phase {
	SETUP,
	DAY_HIDDEN,
	DEFENSE_ZONE,
	GROUP_COMMANDS,
	TIME_COMMANDS,
	PLACE_GATE,
	TO_NIGHT,
	NIGHT_VISIBLE,
	GATE_COMMANDS,
	DAY_RETURN,
	REGRESSION,
	DONE,
}

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _wait := 0
var _failed := false

var _game_time: Node = null
var _world: Node = null
var _player: Node = null
var _hud: Node = null
var _tac = null
var _resources: Node = null

var _last_command := -1
var _last_arg: Variant = null
var _command_count := 0
var _placed_gate: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_sub = 0
	_wait = 0


func _wait_frames(n: int) -> void:
	_wait = n
	_sub += 1


func _waited() -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	return true


func _finish() -> void:
	print("TASK0152_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _on_command(command: int, arg: Variant) -> void:
	_last_command = command
	_last_arg = arg
	_command_count += 1


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _sub == 0:
				if _frame < 8:
					return false
				_game_time = root.get_node("GameTime")
				_world = root.get_node("Main").get_node("World")
				_player = root.get_node("Main").get_node("Player")
				_hud = root.get_node("Main").get_node("HUD")
				_resources = root.get_node("VillageResources")
				_tac = _hud.get_node_or_null("TacticalCommandUI")
				_check(_tac != null, "TacticalCommandUI present in HUD")
				_check(_game_time != null and _world != null and _player != null, "core nodes present")
				_game_time.set_auto_advance(false)
				_game_time.set_durations(2.0, 1.0)
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DAY_HIDDEN)
		Phase.DAY_HIDDEN:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "starts in DAY")
				_check(_tac.visible == false, "tactical command UI hidden at DAY")
				_check(_tac.get_defense_zone_button(MercenaryData.DefenseZone.NORTH) != null, "defense zone N button exists")
				_check(_tac.get_defense_zone_button(MercenaryData.DefenseZone.EAST) != null, "defense zone E button exists")
				_check(_tac.get_defense_zone_button(MercenaryData.DefenseZone.SOUTH) != null, "defense zone S button exists")
				_check(_tac.get_defense_zone_button(MercenaryData.DefenseZone.WEST) != null, "defense zone W button exists")
				_check(_tac.get_regroup_button() != null and _tac.get_retreat_button() != null, "regroup/retreat buttons exist")
				_check(_tac.get_focus_target_button() != null, "focus target button exists")
				_check(_tac.get_time_pause_button() != null and _tac.get_time_1x_button() != null and _tac.get_time_2x_button() != null, "time control buttons exist")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DEFENSE_ZONE)
		Phase.DEFENSE_ZONE:
			if _sub == 0:
				_tac.command_issued.connect(_on_command)
				_tac.get_defense_zone_button(MercenaryData.DefenseZone.NORTH).pressed.emit()
				_check(_last_command == _tac.Command.DEFENSE_ZONE and _last_arg == MercenaryData.DefenseZone.NORTH, "N button emits DEFENSE_ZONE north")
				_tac.get_defense_zone_button(MercenaryData.DefenseZone.EAST).pressed.emit()
				_check(_last_command == _tac.Command.DEFENSE_ZONE and _last_arg == MercenaryData.DefenseZone.EAST, "E button emits DEFENSE_ZONE east")
				_tac.get_defense_zone_button(MercenaryData.DefenseZone.SOUTH).pressed.emit()
				_check(_last_command == _tac.Command.DEFENSE_ZONE and _last_arg == MercenaryData.DefenseZone.SOUTH, "S button emits DEFENSE_ZONE south")
				_tac.get_defense_zone_button(MercenaryData.DefenseZone.WEST).pressed.emit()
				_check(_last_command == _tac.Command.DEFENSE_ZONE and _last_arg == MercenaryData.DefenseZone.WEST, "W button emits DEFENSE_ZONE west")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.GROUP_COMMANDS)
		Phase.GROUP_COMMANDS:
			if _sub == 0:
				_tac.get_regroup_button().pressed.emit()
				_check(_last_command == _tac.Command.REGROUP, "regroup button emits REGROUP")
				_tac.get_retreat_button().pressed.emit()
				_check(_last_command == _tac.Command.RETREAT, "retreat button emits RETREAT")
				_tac.get_focus_target_button().pressed.emit()
				_check(_last_command == _tac.Command.FOCUS_TARGET, "focus target button emits FOCUS_TARGET")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.TIME_COMMANDS)
		Phase.TIME_COMMANDS:
			if _sub == 0:
				_tac.get_time_pause_button().pressed.emit()
				_check(_last_command == _tac.Command.TIME_PAUSE, "pause button emits TIME_PAUSE")
				_tac.get_time_1x_button().pressed.emit()
				_check(_last_command == _tac.Command.TIME_1X, "1x button emits TIME_1X")
				_tac.get_time_2x_button().pressed.emit()
				_check(_last_command == _tac.Command.TIME_2X, "2x button emits TIME_2X")
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_2X, "2x button actually applies 2x speed")
				# TASK-015-6: TIME_2X 버튼은 실제 시간 배율을 2x로 바꾸므로, 이후 phase 전환에
				# 영향을 주지 않도록 1x로 복원한다(시간 버튼 동작 자체는 TASK-015-6에서 검증).
				_game_time.set_time_scale(GameTime.TIME_SCALE_1X)
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X, "time scale restored to 1x")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.PLACE_GATE)
		Phase.PLACE_GATE:
			if _sub == 0:
				_resources._amounts["wood"] = 10000
				var gate_scene: PackedScene = load("res://scenes/gate.tscn")
				_check(gate_scene != null, "gate scene loads")
				var g: Node = gate_scene.instantiate()
				g.setup("north")
				g.position = Vector2(0, -560)
				_world.add_child(g)
				_placed_gate = g
				_check(_world.has_node(str(g.name)), "gate placed in world")
				_check(_tac.get_node("%GateList").get_child_count() == 0, "gate list empty at DAY (refresh only on NIGHT)")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.TO_NIGHT)
		Phase.TO_NIGHT:
			if _sub == 0:
				_game_time.advance(2.0)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "DAY -> NIGHT transition")
				_check(_tac.visible == true, "tactical command UI visible at NIGHT")
				_check(_tac.get_node("%GateList").get_child_count() == 1, "gate row built at NIGHT (1 gate)")
				_sub = 2
			elif _sub == 2:
				_enter(Phase.NIGHT_VISIBLE)
		Phase.NIGHT_VISIBLE:
			if _sub == 0:
				var gate_list: Node = _tac.get_node("%GateList")
				var first_row: Node = gate_list.get_child(0)
				_check(first_row is HBoxContainer, "gate row is an HBoxContainer")
				_check((first_row.get_child(0) as Label).text == "NORTH", "gate row shows NORTH direction")
				_check((first_row.get_child(1) as Label).text == "CLOSED", "gate row shows state label CLOSED")
				_check((first_row.get_child(2) as Button).text == "OPEN", "gate row has OPEN button")
				_check((first_row.get_child(3) as Button).text == "CLOSE", "gate row has CLOSE button")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.GATE_COMMANDS)
		Phase.GATE_COMMANDS:
			if _sub == 0:
				var first_row: Node = _tac.get_node("%GateList").get_child(0)
				(first_row.get_child(2) as Button).pressed.emit()
				_check(_last_command == _tac.Command.GATE_OPEN and _last_arg == _placed_gate, "gate OPEN button emits GATE_OPEN with gate")
				(first_row.get_child(3) as Button).pressed.emit()
				_check(_last_command == _tac.Command.GATE_CLOSE and _last_arg == _placed_gate, "gate CLOSE button emits GATE_CLOSE with gate")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DAY_RETURN)
		Phase.DAY_RETURN:
			if _sub == 0:
				_game_time.advance(1.0)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "NIGHT -> DAY transition")
				_check(_tac.visible == false, "tactical command UI hidden after DAY reset")
				_sub = 2
			elif _sub == 2:
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(not _player.has_method("attack") and not _player.has_method("_attack"), "player has no attack method")
				_check(not _player.is_in_group("enemies") and not _player.is_in_group("mercenaries"), "player excluded from combat groups")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact (128x128)")
				_check(get_nodes_in_group("gates").size() == 1, "placed gate intact")
				_check(_hud.get_node("WoodLabel") != null and _hud.get_node("StoneLabel") != null and _hud.get_node("DayTimeLabel") != null, "existing Wood/Stone/DayTime HUD intact")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0152_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
