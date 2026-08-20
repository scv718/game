extends Control
class_name TavernRecruitmentUI

## TASK-011-3 주점 Worker 고용 프로토타입 UI.
## 고정된 프로토타입 후보 목록(Lumberjack A/B, Miner A/B)을 표시하고,
## 고용 시 WorkerData를 WorkerRoster에 정확히 1회 추가한다.
## 경제/Gold 시스템이 없으므로 고용 비용은 임시로 0이며 비용 시스템은 만들지 않는다.
## 고용 직후 월드 Worker Actor는 생성하지 않는다. Mercenary 고용은 아직 구현하지 않는다.

const CANDIDATES := [
	{ "id": "lumberjack_A", "name": "Lumberjack A", "job": WorkerData.Job.LUMBERJACK },
	{ "id": "lumberjack_B", "name": "Lumberjack B", "job": WorkerData.Job.LUMBERJACK },
	{ "id": "miner_A", "name": "Miner A", "job": WorkerData.Job.MINER },
	{ "id": "miner_B", "name": "Miner B", "job": WorkerData.Job.MINER },
]

@onready var _candidate_list: VBoxContainer = %CandidateList
@onready var _close_button: Button = %CloseButton

var _hire_buttons := {}


func _ready() -> void:
	add_to_group("recruitment_ui")
	WorkerRoster.workers_changed.connect(_refresh_candidate_states)
	_close_button.pressed.connect(_close)
	_build_candidate_list()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build_candidate_list() -> void:
	for c in CANDIDATES:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = c.name
		var hire_button := Button.new()
		hire_button.text = "고용 (0)"
		hire_button.pressed.connect(_on_hire_pressed.bind(c.id))
		_hire_buttons[c.id] = hire_button
		row.add_child(name_label)
		row.add_child(hire_button)
		_candidate_list.add_child(row)
	_refresh_candidate_states()


func _refresh_candidate_states() -> void:
	for c in CANDIDATES:
		var btn: Button = _hire_buttons.get(c.id)
		if btn == null:
			continue
		if WorkerRoster.get_worker(c.id) != null:
			btn.disabled = true
			btn.text = "고용됨"
		else:
			btn.disabled = false
			btn.text = "고용 (0)"


func _on_hire_pressed(candidate_id: String) -> void:
	if WorkerRoster.get_worker(candidate_id) != null:
		return
	for c in CANDIDATES:
		if c.id != candidate_id:
			continue
		var worker := WorkerData.new(c.id, c.name, c.job)
		WorkerRoster.add_worker(worker)
		break
	_refresh_candidate_states()


func open() -> void:
	_refresh_candidate_states()
	visible = true


func close() -> void:
	visible = false


func _close() -> void:
	close()