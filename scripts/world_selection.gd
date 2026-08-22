extends Node2D
class_name WorldSelection

## TASK-CTRL-001-2 Mouse World Selection / Interaction.
## 기존 Player InteractArea + E 접근 방식을 대체해 마우스 클릭으로 건물/시설/성문 등
## 주요 상호작용 오브젝트를 선택하고 기존 interact() API를 재사용해 해당 UI를 연다.
##
## - Left Click = 클릭 지점의 최상위 유효 대상 1개 선택 + interact() 실행.
## - Right Click / ESC = 선택 해제.
## - decoration / ground / 자원 노드(나무 등) 클릭 = interaction 없음(선택도 하지 않음).
## - Build mode 활성 또는 모달 UI가 열려 있으면 월드 클릭을 처리하지 않는다(UI click-through 방지).
## - Player가 근처에 없어도 interaction 가능(Player 물리 접근 전제 제거).
## - NIGHT에서는 월드 클릭 선택을 하지 않는다(전술 조작은 Tactical Command UI/버튼 담당).
##
## 대형 범용 ECS/Selection Framework는 도입하지 않고 명시적 대상 allow-list만 사용한다.

signal selection_changed(interactable)

## Interactable Area2D가 사용하는 collision layer(8 = bit 3).
const INTERACT_COLLISION_LAYER := 8

## 마우스 선택 대상 그룹. 열린 동안 월드 클릭을 차단하는 DAY 모달 UI.
const MODAL_UI_GROUPS := ["recruitment_ui", "inn_roster_ui", "world_map_overlay"]

var _selected: Interactable = null


func _ready() -> void:
	add_to_group("world_selection")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if can_handle_world_click():
				select_at_world_position(get_global_mouse_position())
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _selected != null:
				clear_selection()
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		# ESC는 기존 모달 UI 닫기(recruitment/roster)와도 공유되므로 여기서 삼키지 않는다.
		# 선택 해제만 수행하고 입력은 계속 전파시킨다.
		if _selected != null:
			clear_selection()


## DAY 관리 모드에서 월드 클릭을 처리할 수 있는지. NIGHT / Build mode / 모달 UI는 차단.
func can_handle_world_click() -> bool:
	if GameTime.get_phase() != GameTime.Phase.DAY:
		return false
	if _is_build_mode_active():
		return false
	if _has_open_modal_ui():
		return false
	return true


## 클릭 월드 좌표 기준으로 최상위 유효 대상 1개를 선택하고 interact()를 실행한다.
## 대상이 없으면(decoration/ground/자원 노드) 선택을 변경하지 않고 null을 반환한다.
## 차단 상태(guard 실패)에서는 아무것도 하지 않고 null을 반환한다.
func select_at_world_position(world_pos: Vector2) -> Interactable:
	if not can_handle_world_click():
		return null
	var target := _pick_managed_interactable_at(world_pos)
	if target == null:
		return null
	_set_selected(target)
	target.interact(self)
	return target


func clear_selection() -> void:
	if _selected != null:
		_set_selected(null)


func get_selected() -> Interactable:
	return _selected


## 클릭 지점에서 가장 가까운(최상위로 간주) 유효 관리 대상 Interactable을 찾는다.
## 자원 노드(ResourceNode/Tree)와 decoration은 물리 조회에 걸려도 대상에서 제외된다.
func _pick_managed_interactable_at(world_pos: Vector2) -> Interactable:
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collision_mask = INTERACT_COLLISION_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hits := space.intersect_point(query)
	var best: Interactable = null
	var best_dist := INF
	for hit in hits:
		var collider = hit.get("collider")
		var interactable := collider as Interactable
		if interactable == null or not is_instance_valid(interactable):
			continue
		if not _is_managed_target(interactable) or not interactable.can_interact():
			continue
		var d := world_pos.distance_squared_to(interactable.global_position)
		if d < best_dist:
			best = interactable
			best_dist = d
	return best


## 마우스 선택 대상으로 허용하는 상호작용 오브젝트. 건물/시설/성문 계열만 허용하고
## 자원 노드(나무 등)는 Worker 전용으로 남겨 Player/마우스 직접 채집을 차단한다.
func _is_managed_target(interactable: Node) -> bool:
	return interactable is CoreBuildingInteractable \
		or interactable is GateInteractable \
		or interactable is LumberyardInteractable \
		or interactable is QuarryInteractable


func _set_selected(interactable: Interactable) -> void:
	_selected = interactable
	selection_changed.emit(interactable)


func _is_build_mode_active() -> bool:
	var placement := get_tree().get_first_node_in_group("building_placement")
	return placement != null and placement.has_method("is_active") and placement.is_active()


func _has_open_modal_ui() -> bool:
	for group_name in MODAL_UI_GROUPS:
		var ui := get_tree().get_first_node_in_group(group_name) as Control
		if ui != null and ui.visible:
			return true
	return false