extends Control
class_name InnRosterUI

## TASK-011-4 여관 Worker Roster / 시설 배치 관리 UI.
## 여관 상호작용 시 열리는 최소 관리 UI.
## 고용된 Worker 목록을 직업과 배치 상태(Unassigned / Lumberyard / Quarry)로 표시하고,
## 직업에 맞는 생산시설에 배치/해제한다.
## Lumberjack은 Lumberyard에만, Miner는 Quarry에만 배치할 수 있다.
## 시설 slot 상태(0/N, 1/N, ...)와 가득 참 판정, 중복 배치 거부를 함께 처리한다.
## slot capacity는 실제 시설의 get_slot_capacity()에서 동적으로 읽는다.
## 내부 assign/unassign은 WorkerRoster.assign/unassign(테스트/여관 관리 로직)을 재사용한다.

@onready var _facility_list: VBoxContainer = %FacilityList
@onready var _worker_list: VBoxContainer = %WorkerList
@onready var _close_button: Button = %CloseButton

var _facility_capacity := {}
var _assign_buttons := {}
var _unassign_buttons := {}


func _ready() -> void:
	add_to_group("inn_roster_ui")
	WorkerRoster.workers_changed.connect(_refresh)
	_close_button.pressed.connect(_close)
	_refresh_facilities()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## 직업별로 배치 가능한 시설 그룹을 모은다.
func _get_facilities_for_job(job: int) -> Array[Node]:
	var out: Array[Node] = []
	if job == WorkerData.Job.LUMBERJACK:
		for f in get_tree().get_nodes_in_group("lumberyards"):
			if is_instance_valid(f):
				out.append(f)
	elif job == WorkerData.Job.MINER:
		for f in get_tree().get_nodes_in_group("quarries"):
			if is_instance_valid(f):
				out.append(f)
	return out


## worker를 배치할 대상 시설을 고른다. 이미 배치된 worker는 배치하지 않는다.
func _pick_target(worker: WorkerData) -> Node:
	if worker == null or worker.is_assigned():
		return null
	for f in _get_facilities_for_job(worker.job):
		if _facility_capacity.get(f, 0) > _get_facility_filled(f):
			return f
	return null


func _get_facility_filled(facility: Node) -> int:
	return WorkerRoster.get_workers_for_workplace(facility).size()


func _refresh_facilities() -> void:
	_facility_capacity.clear()
	for child in _facility_list.get_children():
		child.queue_free()
	var facilities: Array[Node] = []
	facilities.append_array(get_tree().get_nodes_in_group("lumberyards"))
	facilities.append_array(get_tree().get_nodes_in_group("quarries"))
	for f in facilities:
		if not is_instance_valid(f):
			continue
		var cap: int = f.get_slot_capacity() if f.has_method("get_slot_capacity") else 0
		_facility_capacity[f] = cap
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s %d/%d" % [f.get_worker_label() if f.has_method("get_worker_label") else str(f.name), _get_facility_filled(f), cap]
		row.add_child(label)
		_facility_list.add_child(row)


func _refresh() -> void:
	_refresh_facilities()
	for child in _worker_list.get_children():
		child.queue_free()
	_assign_buttons.clear()
	_unassign_buttons.clear()
	for w in WorkerRoster.get_workers():
		var row := HBoxContainer.new()
		var info := Label.new()
		info.text = "%s (%s) - %s" % [w.display_name, w.get_job_name(), _status_text(w)]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var assign := Button.new()
		assign.text = "배치"
		assign.pressed.connect(_on_assign_pressed.bind(w))
		assign.disabled = _pick_target(w) == null
		var unassign := Button.new()
		unassign.text = "해제"
		unassign.pressed.connect(_on_unassign_pressed.bind(w))
		unassign.disabled = not w.is_assigned()
		_assign_buttons[w.id] = assign
		_unassign_buttons[w.id] = unassign
		row.add_child(info)
		row.add_child(assign)
		row.add_child(unassign)
		_worker_list.add_child(row)


func _status_text(w: WorkerData) -> String:
	if not w.is_assigned():
		return "Unassigned"
	var f := w.get_workplace()
	if not is_instance_valid(f):
		return "Unassigned"
	var label := "Lumberyard" if w.job == WorkerData.Job.LUMBERJACK else "Quarry"
	return "%s %s" % [label, f.name]


func _on_assign_pressed(w: WorkerData) -> void:
	var target := _pick_target(w)
	if target == null:
		return
	WorkerRoster.assign(w, target)
	_refresh()


func _on_unassign_pressed(w: WorkerData) -> void:
	WorkerRoster.unassign(w)
	_refresh()


func open() -> void:
	_refresh()
	visible = true


func close() -> void:
	visible = false


func _close() -> void:
	close()
