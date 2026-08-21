extends Control
class_name DeathLedgerView

## TASK-016-5 최소 Death Ledger View.
## 실제 플레이 중 Death Ledger 기록을 확인하기 위한 최소 검증 UI. 최종
## Memorial/Archive UI가 아니며 정보 확인용이다. record 삭제/정화/망령 방지
## 기능은 없다. DeathLedger의 record_added / record_status_changed 시그널을 받아
## 신규 record/status 변경 시 목록을 refresh하고, 열 때마다 현재 Ledger 상태를
## 다시 조회해 표시한다. 좌상단 HUD(StatusPanel)와 NIGHT Tactical Command UI를
## 과도하게 가리지 않도록 좌하단에 배치한다.

@onready var _panel: Panel = %LedgerPanel
@onready var _record_list: VBoxContainer = %RecordList
@onready var _close_button: Button = %CloseButton

var _ledger: Node = null


func _ready() -> void:
	add_to_group("death_ledger_view")
	_ledger = get_node_or_null("/root/DeathLedger")
	_close_button.pressed.connect(close)
	if _ledger != null:
		if not _ledger.record_added.is_connected(_on_ledger_changed):
			_ledger.record_added.connect(_on_ledger_changed)
		if not _ledger.record_status_changed.is_connected(_on_ledger_changed):
			_ledger.record_status_changed.connect(_on_ledger_changed)
	_refresh()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("death_ledger"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## 열 때마다 현재 Ledger 상태를 다시 조회해 표시한다.
func open() -> void:
	_refresh()
	visible = true


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible


## Ledger signal(record_added / record_status_changed) 수신 시 목록을 갱신한다.
## 숨겨진 상태에서도 안전하게 동작하되, 열려 있을 때만 즉시 반영한다.
func _on_ledger_changed(_record_id: String = "", _status: int = -1) -> void:
	if visible:
		_refresh()


## DeathLedger.get_all_records()를 다시 조회해 행을 재구성한다.
func _refresh() -> void:
	for child in _record_list.get_children():
		_record_list.remove_child(child)
		child.queue_free()
	if _ledger == null:
		return
	var records: Array[DeathRecord] = _ledger.get_all_records()
	if records.is_empty():
		var empty := Label.new()
		empty.text = "기록 없음"
		_record_list.add_child(empty)
		return
	for rec in records:
		var row := Label.new()
		row.text = "%s / %s / Day %d / %s" % [
			rec.display_name,
			rec.get_source_kind_name(),
			rec.death_day,
			rec.get_status_name(),
		]
		_record_list.add_child(row)


## 테스트/검증용 접근자.
func get_record_count() -> int:
	return _record_list.get_child_count()


func get_row_text(index: int) -> String:
	if index < 0 or index >= _record_list.get_child_count():
		return ""
	var child := _record_list.get_child(index)
	return child.text if child is Label else ""