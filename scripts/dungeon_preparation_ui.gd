extends Control
class_name DungeonPreparationUI

## TASK-027-2 Dungeon Preparation / Validation UI.
## Dungeon 출발 전 파티와 준비 자원을 검증하는 full-screen overlay.
## 표시:
##  - Party member 목록 (편성/해제).
##  - Food/Supply, Potion slots, Equipment summary (기존 설계에 필수 규칙이 없어 선택).
##  - Dungeon 위험도 + tier.
##  - 예상 reward 정보 중 현재 공개 가능한 값(reward table + threat reward).
## 검증:
##  - dead/unavailable/expedition member, duplicate member, party min/max 위반 사유를
##    StatusLabel에 명확히 표시하고, valid일 때만 Depart 활성화.
## 금지:
##  - Player 직접 dungeon entry. Depart는 준비 검증 통과 시 데이터 상태 전환
##    (DungeonPreparationManager.depart)만 수행하며 Runtime 진입은 TASK-027-3 hook.
##  - 신규 Food/Potion/Equipment 규칙 발명 (hook은 선택, 차단하지 않음).
## Root scene node는 CanvasLayer이며 이 스크립트는 child Control에 있다.

@onready var _dungeon_title_label: Label = %DungeonTitleLabel
@onready var _dungeon_info_label: Label = %DungeonInfoLabel
@onready var _risk_label: Label = %RiskLabel
@onready var _reward_label: Label = %RewardLabel
@onready var _party_list: VBoxContainer = %PartyList
@onready var _member_selector: OptionButton = %MemberSelector
@onready var _add_member_button: Button = %AddMemberButton
@onready var _food_line: LineEdit = %FoodLineEdit
@onready var _potion_line: LineEdit = %PotionLineEdit
@onready var _equipment_line: LineEdit = %EquipmentLineEdit
@onready var _status_label: Label = %StatusLabel
@onready var _depart_button: Button = %DepartButton
@onready var _close_button: Button = %CloseButton

var _dungeon_id := ""
var _is_open := false


func _ready() -> void:
	add_to_group("dungeon_preparation_ui")
	_close_button.pressed.connect(close)
	_add_member_button.pressed.connect(_on_add_member_pressed)
	_depart_button.pressed.connect(_on_depart_pressed)
	_food_line.text_submitted.connect(_on_food_submitted)
	_potion_line.text_submitted.connect(_on_potion_submitted)
	_equipment_line.text_submitted.connect(_on_equipment_submitted)
	_resolve_manager()
	visible = false


func _resolve_manager() -> void:
	# autoload 참조는 호출 시점에 조회해 테스트(SceneTree standalone)에서도 안전하다.
	if not _has_manager():
		return
	DungeonPreparationManager.preparation_changed.connect(_on_preparation_changed)
	DungeonPreparationManager.run_started.connect(_on_run_started)


func _has_manager() -> bool:
	var manager: Node = get_node_or_null("/root/DungeonPreparationManager")
	return manager != null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dungeon_prep"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if _dungeon_id == "":
		_dungeon_id = _pick_default_dungeon()
	if _dungeon_id == "":
		_is_open = true
		visible = true
		_dungeon_title_label.text = "Dungeon Preparation"
		_dungeon_info_label.text = "No dungeon discovered yet."
		_depart_button.disabled = true
		return
	_is_open = true
	visible = true
	_refresh()


func close() -> void:
	_is_open = false
	visible = false


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func is_open() -> bool:
	return _is_open


## 특정 dungeon으로 준비 화면을 연다. instance가 없으면 열지 않는다.
func open_dungeon(dungeon_id: String) -> void:
	if not _has_manager() or DungeonManager.get_dungeon(dungeon_id) == null:
		return
	_dungeon_id = dungeon_id
	open()


func get_dungeon_id() -> String:
	return _dungeon_id


## 비종료(DISCOVERED/READY/IN_PROGRESS) dungeon 중 첫 번째를 기본 선택한다.
func _pick_default_dungeon() -> String:
	if not _has_manager():
		return ""
	var dungeons: Array = DungeonManager.get_active_dungeons()
	if dungeons.is_empty():
		return ""
	return (dungeons[0] as DungeonDefinition).dungeon_id


## --- UI 동작 ---

func _on_add_member_pressed() -> void:
	if _dungeon_id == "" or _member_selector.get_item_count() == 0:
		return
	var member_id := _member_selector.get_item_text(_member_selector.get_selected())
	if member_id == "":
		return
	var result: Dictionary = DungeonPreparationManager.add_member(_dungeon_id, member_id)
	if not result.get("ok", false):
		_status_label.text = "Cannot add member: %s" % result.get("reason", "")
	_refresh()


func _on_depart_pressed() -> void:
	if _dungeon_id == "":
		return
	var result: Dictionary = DungeonPreparationManager.depart(_dungeon_id)
	if not result.get("ok", false):
		_refresh()
		return
	_depart_button.text = "DEPARTED"
	_depart_button.disabled = true


func _on_food_submitted(text: String) -> void:
	if _dungeon_id == "":
		return
	DungeonPreparationManager.set_food_slot(_dungeon_id, text.strip_edges())


func _on_potion_submitted(text: String) -> void:
	if _dungeon_id == "":
		return
	var ids: Array = []
	for part in text.split(","):
		var id := part.strip_edges()
		if not id.is_empty():
			ids.append(id)
	DungeonPreparationManager.set_potion_slots(_dungeon_id, ids)


func _on_equipment_submitted(text: String) -> void:
	if _dungeon_id == "":
		return
	var values: Array = []
	for part in text.split(","):
		var value := part.strip_edges()
		if not value.is_empty():
			values.append(value)
	DungeonPreparationManager.set_equipment_summary(_dungeon_id, values)


func _on_preparation_changed(dungeon_id: String) -> void:
	if _is_open and dungeon_id == _dungeon_id:
		_refresh()


func _on_run_started(dungeon_id: String) -> void:
	if _is_open and dungeon_id == _dungeon_id:
		_depart_button.text = "DEPARTED"
		_depart_button.disabled = true


## --- 화면 갱신 ---

func _refresh() -> void:
	if not _has_manager() or _dungeon_id == "":
		return
	var dungeon: DungeonDefinition = DungeonManager.get_dungeon(_dungeon_id)
	if dungeon == null:
		return
	_dungeon_title_label.text = "Dungeon Preparation - %s" % dungeon.display_name
	_dungeon_info_label.text = "Tier %d | State: %s | Encounter: %s" % [
		dungeon.tier, dungeon.get_state_name(), ", ".join(PackedStringArray(dungeon.get_encounter_ids()))]
	_risk_label.text = "Risk: %d" % DungeonPreparationManager.get_dungeon_risk(_dungeon_id)

	var reward_lines: Array = DungeonPreparationManager.get_public_reward_lines(_dungeon_id)
	_reward_label.text = "Expected reward: %s" % (
		", ".join(PackedStringArray(reward_lines)) if not reward_lines.is_empty() else "Unknown")

	var prep: DungeonPreparation = DungeonPreparationManager.get_preparation(_dungeon_id)
	if prep != null:
		_food_line.text = prep.get_food_slot()
		_potion_line.text = ", ".join(PackedStringArray(prep.get_potion_slots()))
		_equipment_line.text = ", ".join(PackedStringArray(prep.get_equipment_summary()))

	_rebuild_party_list(prep)
	_rebuild_member_selector(prep)

	var report: Dictionary = DungeonPreparationManager.validate(_dungeon_id)
	_refresh_status(report)


func _rebuild_party_list(prep: DungeonPreparation) -> void:
	for child in _party_list.get_children():
		child.queue_free()
	if prep == null or prep.get_member_count() == 0:
		var empty := Label.new()
		empty.text = "(no members)"
		empty.modulate = Color(0.5, 0.5, 0.5)
		_party_list.add_child(empty)
		return
	for member_id in prep.get_member_ids():
		var row := HBoxContainer.new()
		var name_label := Label.new()
		var roster: Node = get_node_or_null("/root/MercenaryRoster")
		var display: String = member_id
		if roster != null:
			var m: MercenaryData = roster.get_mercenary(member_id)
			if m != null:
				display = "%s (%s)" % [m.display_name, member_id]
		name_label.text = display
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var remove_button := Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(_on_remove_member_pressed.bind(member_id))
		row.add_child(name_label)
		row.add_child(remove_button)
		_party_list.add_child(row)


func _rebuild_member_selector(prep: DungeonPreparation) -> void:
	_member_selector.clear()
	var roster: Node = get_node_or_null("/root/MercenaryRoster")
	if roster == null:
		_member_selector.add_item("(no roster)")
		_add_member_button.disabled = true
		return
	var selected_index := 0
	for m in roster.get_alive():
		if prep != null and prep.has_member(m.id):
			continue
		_member_selector.add_item(m.id)
		if selected_index == 0:
			selected_index = _member_selector.item_count - 1
	if _member_selector.item_count == 0:
		_member_selector.add_item("(no available members)")
		_add_member_button.disabled = true
	else:
		_member_selector.select(selected_index)
		_add_member_button.disabled = false


func _on_remove_member_pressed(member_id: String) -> void:
	if _dungeon_id == "":
		return
	DungeonPreparationManager.remove_member(_dungeon_id, member_id)
	_refresh()


func _refresh_status(report: Dictionary) -> void:
	var issues: Array = report.get("issues", [])
	if report.get("valid", false):
		_status_label.text = "VALID - Ready to depart"
		_status_label.modulate = Color(0.4, 0.9, 0.5)
		_depart_button.disabled = false
		_depart_button.text = "Depart"
	else:
		var lines: Array = []
		for issue in issues:
			lines.append("* " + str(issue.get("message", "?")))
		_status_label.text = "NOT READY:\n" + "\n".join(lines)
		_status_label.modulate = Color(1.0, 0.6, 0.5)
		_depart_button.disabled = true
		_depart_button.text = "Depart"
