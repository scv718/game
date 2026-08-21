extends Control
class_name TacticalCommandUI

## TASK-015-2 Tactical Command HUD.
## NIGHT 지휘 모드에서 표시되는 전술 명령 UI 셸. DAY에서는 숨긴다.
## 실제 명령 동작(방어구역 변경/집결/후퇴/집중공격/성문 개폐/시간 조작)은
## TASK-015-3 ~ 015-6에서 구현하고, 이 UI는 각 명령 버튼이 command_issued 신호로
## 명령을 방출하는 인터페이스만 제공한다.
## 전투 중앙을 과도하게 가리지 않도록 화면 오른쪽 가장자리에 배치한다.

enum Command {
	DEFENSE_ZONE,   # arg = MercenaryData.DefenseZone
	REGROUP,        # arg = 0
	RETREAT,        # arg = 0
	FOCUS_TARGET,   # arg = 0 (mode toggle)
	GATE_OPEN,      # arg = Gate Node
	GATE_CLOSE,     # arg = Gate Node
	TIME_PAUSE,     # arg = 0
	TIME_1X,        # arg = 0
	TIME_2X,        # arg = 0
}

## 각 명령 버튼이 눌릴 때 방출된다. 후속 태스크(TASK-015-3 ~ 015-6)가 이 신호를
## 받아 실제 AI/시간 동작을 구현한다.
signal command_issued(command: int, arg: Variant)

const ZONE_ORDER := [
	MercenaryData.DefenseZone.NORTH,
	MercenaryData.DefenseZone.EAST,
	MercenaryData.DefenseZone.SOUTH,
	MercenaryData.DefenseZone.WEST,
]

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
	add_to_group("tactical_command_ui")
	GameTime.phase_changed.connect(_on_phase_changed)
	_build_defense_buttons()
	_regroup_button.pressed.connect(_emit_command.bind(Command.REGROUP, 0))
	_retreat_button.pressed.connect(_emit_command.bind(Command.RETREAT, 0))
	_focus_button.pressed.connect(_emit_command.bind(Command.FOCUS_TARGET, 0))
	_time_pause_button.pressed.connect(_emit_command.bind(Command.TIME_PAUSE, 0))
	_time_1x_button.pressed.connect(_emit_command.bind(Command.TIME_1X, 0))
	_time_2x_button.pressed.connect(_emit_command.bind(Command.TIME_2X, 0))
	_apply_phase(GameTime.get_phase())


func _on_phase_changed(phase: int, _day_number: int) -> void:
	_apply_phase(phase)


## NIGHT면 명령 UI를 보여주고 설치된 성문 목록을 갱신하며, DAY면 숨긴다.
func _apply_phase(phase: int) -> void:
	var night := (phase == GameTime.Phase.NIGHT)
	visible = night
	if night:
		_refresh_gates()


func _build_defense_buttons() -> void:
	for zone in ZONE_ORDER:
		var btn := Button.new()
		btn.text = MercenaryData.DEFENSE_NAMES.get(zone, "?")
		btn.pressed.connect(_emit_command.bind(Command.DEFENSE_ZONE, zone))
		_defense_buttons[zone] = btn
		(%DefenseZoneRow as HBoxContainer).add_child(btn)


## 설치된 성문을 N/E/S/W 방향별로 나열하고 OPEN/CLOSE 버튼을 만든다.
## 성문이 없으면 안내 문구만 표시한다. (반복 호출은 목록을 재생성)
func _refresh_gates() -> void:
	for child in _gate_list.get_children():
		child.queue_free()
	var gates := get_tree().get_nodes_in_group("gates")
	if gates.is_empty():
		var empty := Label.new()
		empty.text = "설치된 성문 없음"
		_gate_list.add_child(empty)
		return
	for gate in gates:
		if not is_instance_valid(gate):
			continue
		var dir: String = "?"
		if gate.has_method("get_direction"):
			dir = gate.get_direction()
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s" % dir.to_upper()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var open_btn := Button.new()
		open_btn.text = "OPEN"
		open_btn.pressed.connect(_emit_command.bind(Command.GATE_OPEN, gate))
		var close_btn := Button.new()
		close_btn.text = "CLOSE"
		close_btn.pressed.connect(_emit_command.bind(Command.GATE_CLOSE, gate))
		row.add_child(label)
		row.add_child(open_btn)
		row.add_child(close_btn)
		_gate_list.add_child(row)


func _emit_command(command: int, arg: Variant) -> void:
	command_issued.emit(command, arg)


## 테스트/후속 태스크용: 버튼별 방출되는 명령 검증에 사용한다.
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
