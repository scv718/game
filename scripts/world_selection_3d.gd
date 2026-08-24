extends Node3D
class_name WorldSelection3D

## TASK-3D-001-4 Mouse Selection / Interaction 3D contract.
## 기존 world_selection.gd(Node2D point query)의 선택 의미를 Camera3D raycast로
## 이전한 최소 공통 계약이다. 거대 Selection Framework를 만들지 않고 단일 대상
## 선택만 제공한다(001-4 금지 항목 준수).
##
## - Left Click = 클릭 광선과 교차하는 유효한 Interactable3D 1개 선택 + interact() 실행.
##   광선은 최근접 hit 1개만 반환하므로 2D의 "최상위 유효 대상" 의미가 그대로 보존된다.
## - 빈 ground / decoration 클릭 = interaction/선택 변경 없음(안전 no-op).
##   INTERACTABLE layer만 조회하므로 지면/비주얼 decoration/자원 블록은
##   구조적으로 조회되지 않는다(CollisionLayers3D.MASK_SELECTION).
## - Right Click / ESC = 선택 해제. ESC는 기존 모달 UI 닫기와 공유되므로 입력을
##   삼키지 않고 선택 해제만 수행한다(기존 2D 규약 동일).
## - NIGHT / Build mode / 모달 UI가 열려 있으면 월드 클릭을 처리하지 않는다
##   (기존 world_selection.gd 게이트 정책과 동일, UI click-through 방지).
## - Player가 근처에 없어도 interaction 가능(Player 물리 접근 전제 제거 유지).
## - 카메라 광선은 camera_controller_3d 그룹의 screen_to_world_ray를 소비하고
##   physics query는 이 노드가 직접 수행한다(Area3D 조회를 위해 areas-only query).
## - game data 소유를 강제하지 않는다. 선택 결과는 Interactable3D 계약 참조뿐이며
##   실제 기능은 각 도메인이 interact() 위임으로 연결한다.

signal selection_changed(interactable)

## selection probe 길이(unit). orthographic 사선 시점에서 전체 월드(+경계)를
## 커버하기에 충분하며 camera_controller_3d.raycast_from_screen 내부 길이와 동일값.
const SELECTION_RAY_LENGTH := 2000.0

## 열린 동안 월드 클릭을 차단하는 DAY 모달 UI 그룹.
## 기존 world_selection.MODAL_UI_GROUPS와 동일 목록(차원별 자기 파일 유지 원칙).
const MODAL_UI_GROUPS := ["recruitment_ui", "inn_roster_ui", "world_map_overlay"]

var _selected: Interactable3D = null


func _ready() -> void:
	add_to_group("world_selection_3d")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if can_handle_world_click():
				select_at_screen_position(event.position)
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


## 클릭 화면 좌표 광선 기준으로 유효한 Interactable3D 1개를 선택하고 interact()를 실행한다.
## 대상이 없으면(decoration/ground/자원) 선택을 변경하지 않고 null을 반환한다.
## 차단 상태(guard 실패)나 카메라 미준비 상태에서도 아무것도 하지 않고 null을 반환한다.
func select_at_screen_position(screen_pos: Vector2) -> Interactable3D:
	if not can_handle_world_click():
		return null
	var target := _pick_interactable_at(screen_pos)
	if target == null:
		return null
	_set_selected(target)
	target.interact(self)
	return target


func clear_selection() -> void:
	if _selected != null:
		_set_selected(null)


func get_selected() -> Interactable3D:
	return _selected


## 클릭 광선의 최근접 hit이 유효한 관리 대상인지 판정해 반환한다.
## 조회 mask는 CollisionLayers3D.MASK_SELECTION(INTERACTABLE Area3D 전용)이므로
## 지면/건물 본체/decoration 비주얼/자원 블록은 애초에 hit되지 않는다.
## Area3D 선택을 위해 bodies는 끄고 areas만 조회한다(기존 2D areas-only query 규약).
func _pick_interactable_at(screen_pos: Vector2) -> Interactable3D:
	var ray := _selection_ray(screen_pos)
	if ray.is_empty():
		return null
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		ray["origin"], ray["origin"] + ray["direction"] * SELECTION_RAY_LENGTH,
		CollisionLayers3D.MASK_SELECTION)
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	var interactable := collider as Interactable3D
	if interactable == null or not is_instance_valid(interactable):
		return null
	if not interactable.is_selectable() or not interactable.can_interact():
		return null
	return interactable


## camera_controller_3d 그룹의 컨트롤러에서 screen -> world ray를 얻는다.
## 컨트롤러 부재/미준비 시 빈 Dictionary(안전 no-op).
func _selection_ray(screen_pos: Vector2) -> Dictionary:
	var cam_ctl := get_tree().get_first_node_in_group("camera_controller_3d")
	if cam_ctl == null or not cam_ctl.has_method("screen_to_world_ray"):
		return {}
	return cam_ctl.screen_to_world_ray(screen_pos)


func _set_selected(interactable: Interactable3D) -> void:
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
