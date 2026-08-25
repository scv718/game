extends Control
class_name TacticalCommandUI3D

## TASK-3D-CMB-001-2 Tactical Command HUD 3D wiring.
## 기존 tactical_command_ui.gd(Control)의 NIGHT 지휘 UI 셸을 3D Runtime용으로
## 병행 운영하는 신규 파일이다. 기존 2D tactical_command_ui.gd / .tscn은 LOCK 12에
## 따라 무수정으로 유지되며, 이 UI는 같은 Control 계층/레이아웃을 유지한 채
## 3D World 대상으로만 연결된다(UI 자체의 3D 전환 금지 LOCK 준수).
##
## - 명령 코드는 기존 TacticalCommandUI.Command enum을 차원 중립적으로 재사용한다
##   (신규 명령/우선순위 발명 금지, command priority 기존 규칙 유지).
## - 성문 목록은 gates_3d 그룹을 조회해 상태(CLOSED/OPEN/BREACHED)와 OPEN/CLOSE
##   버튼을 만든다. gate 상태 표시/버튼 disable은 duck-typing 계약(is_open /
##   is_breached / get_direction / gate_state_changed)으로 BLD Gate3D와 연결되며
##   Gate3D 부재 시 안내 문구만 표시한다.
## - 명령 방출(command_issued)은 MercenaryRoster3D("mercenary_roster_3d" 그룹)에
##   위임한다. roster가 먼저/나중에 트리에 들어오는 양쪽 순서 모두 guarded connect로
##   중복 없이 연결되고, roster 부재 시에는 신호만 방출하는 인터페이스로 남는다.
## - DAY에서는 숨기고 NIGHT에만 표시한다(2D와 동일 phase 정책).

const ZONE_ORDER := [
	MercenaryData.DefenseZone.NORTH,
	MercenaryData.DefenseZone.EAST,
	MercenaryData.DefenseZone.SOUTH,
	MercenaryData.DefenseZone.WEST,
]

## 각 명령 버튼이 눌릴 때 방출된다. MercenaryRoster3D가 받아 실제 3D Actor AI/
## 성문/시간 동작을 수행한다. 명령 코드는 기존 TacticalCommandUI.Command다.
signal command_issued(command: int, arg: Variant)

@onready var _panel: Panel = %TacticalPanel
@onready var _regroup_button: Button = %RegroupButton
@onready var _retreat_button: Button = %RetreatButton
@onready var _focus_button: Button = %FocusTargetButton
@onready var _time_pause_button: Button = %TimePauseButton
@onready var _time_1x_button: Button = %Time1xButton
@onready var _time_2x_button: Button = %Time2xButton
@onready var _gate_list: VBoxContainer = %GateList

var _defense_buttons := {}


func _ready() -> void:
	add_to_group("tactical_command_ui_3d")
	GameTime.phase_changed.connect(_on_phase_changed)
	_connect_roster()
	_build_defense_buttons()
	_regroup_button.pressed.connect(_emit_command.bind(TacticalCommandUI.Command.REGROUP, 0))
	_retreat_button.pressed.connect(_emit_command.bind(TacticalCommandUI.Command.RETREAT, 0))
	_focus_button.pressed.connect(_emit_command.bind(TacticalCommandUI.Command.FOCUS_TARGET, 0))
	_time_pause_button.pressed.connect(_emit_command.bind(TacticalCommandUI.Command.TIME_PAUSE, 0))
	_time_1x_button.pressed.connect(_emit_command.bind(TacticalCommandUI.Command.TIME_1X, 0))
	_time_2x_button.pressed.connect(_emit_command.bind(TacticalCommandUI.Command.TIME_2X, 0))
	_apply_phase(GameTime.get_phase())


## MercenaryRoster3D를 찾아 command 경로를 연결한다. roster가 이 UI보다 늦게
## 트리에 들어오면 roster 쪽 _connect_tactical_ui가 연결을 담당하므로
## 어느 쪽 순서든 중복 connect 없이 한 번만 연결된다.
func _connect_roster() -> void:
	var roster := get_tree().get_first_node_in_group("mercenary_roster_3d")
	if roster != null and roster.has_method("_on_tactical_command") \
			and not command_issued.is_connected(roster._on_tactical_command):
		command_issued.connect(roster._on_tactical_command)


func _on_phase_changed(phase: int, _day_number: int) -> void:
	_apply_phase(phase)


## NIGHT면 명령 UI를 보여주고 설치된 성문 목록을 갱신하며, DAY면 숨긴다(2D 동일).
func _apply_phase(phase: int) -> void:
	var night := (phase == GameTime.Phase.NIGHT)
	visible = night
	if night:
		_refresh_gates()


func _build_defense_buttons() -> void:
	for zone in ZONE_ORDER:
		var btn := Button.new()
		btn.text = MercenaryData.DEFENSE_NAMES.get(zone, "?")
		btn.pressed.connect(_emit_command.bind(TacticalCommandUI.Command.DEFENSE_ZONE, zone))
		_defense_buttons[zone] = btn
		(%DefenseZoneRow as HBoxContainer).add_child(btn)


## 설치된 성문(gates_3d)을 N/E/S/W 방향별로 나열하고 상태(CLOSED/OPEN/BREACHED) +
## OPEN/CLOSE 버튼을 만든다. BREACHED(파괴) 성문은 OPEN/CLOSE 버튼을 disabled 처리해
## 조작을 막는다(gate의 set_open no-op 계약과 이중 안전). 성문 상태가 바뀌면 목록을
## 다시 그려 상태 라벨을 갱신한다. 성문이 없으면 안내 문구만 표시한다.
## gate 상태/방향 조회는 2D gate.gd와 동일 duck-typing 계약이다.
## (반복 호출은 목록을 재생성하며, gate 신호 연결은 중복 방지)
func _refresh_gates(_gate: Node = null, _open: bool = false) -> void:
	for child in _gate_list.get_children():
		child.queue_free()
	var gates := get_tree().get_nodes_in_group("gates_3d")
	if gates.is_empty():
		var empty := Label.new()
		empty.text = "설치된 성문 없음"
		_gate_list.add_child(empty)
		return
	for gate in gates:
		if not is_instance_valid(gate):
			continue
		if gate.has_signal("gate_state_changed") \
				and not gate.gate_state_changed.is_connected(_refresh_gates):
			gate.gate_state_changed.connect(_refresh_gates)
		var dir: String = "?"
		if gate.has_method("get_direction"):
			dir = gate.get_direction()
		var breached := false
		if gate.has_method("is_breached"):
			breached = gate.is_breached() == true
		var state_name := "CLOSED"
		if gate.has_method("is_open") and gate.is_open():
			state_name = "BREACHED" if breached else "OPEN"
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s" % dir.to_upper()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var state := Label.new()
		state.text = state_name
		state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var open_btn := Button.new()
		open_btn.text = "OPEN"
		open_btn.disabled = breached
		open_btn.pressed.connect(_emit_command.bind(
			TacticalCommandUI.Command.GATE_OPEN, gate))
		var close_btn := Button.new()
		close_btn.text = "CLOSE"
		close_btn.disabled = breached
		close_btn.pressed.connect(_emit_command.bind(
			TacticalCommandUI.Command.GATE_CLOSE, gate))
		row.add_child(label)
		row.add_child(state)
		row.add_child(open_btn)
		row.add_child(close_btn)
		_gate_list.add_child(row)


func _emit_command(command: int, arg: Variant) -> void:
	command_issued.emit(command, arg)


## 테스트/후속 태스크용: 버튼별 방출되는 명령 검증에 사용한다(2D와 동일 접근자).
func get_defense_zone_button(zone: int) -> Button:
	return _defense_buttons.get(zone)


func get_regroup_button() -> Button:
	return _regroup_button


func get_retreat_button() -> Button:
	return _retreat_button


func get_focus_target_button() -> Button:
	return _focus_button


func get_time_pause_button() -> Button:
	return _time_pause_button


func get_time_1x_button() -> Button:
	return _time_1x_button


func get_time_2x_button() -> Button:
	return _time_2x_button
