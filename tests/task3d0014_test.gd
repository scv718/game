extends SceneTree

## TASK-3D-001-4 Interaction3D / Selection Contract 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. Interactable3D 공통 계약(prompt / can_interact / is_selectable / interact) 기본값.
##   2. Left Click -> 유효한 Interactable3D 1개 선택 + interact() 실행(interator 전달).
##   3. Right Click / ESC 선택 해제.
##   4. 빈 ground 클릭 안전(선택 변경 없음, 오류 없음).
##   5. decoration 비주얼 / 자원 블록(RESOURCE layer) / is_selectable=false 대상 안전.
##   6. UI open 상태 world interaction 누수 없음(STOP Control + 모달 그룹 게이트).
##   7. Build mode / NIGHT 게이트(기존 world_selection.gd 정책 동일).
##   8. 카메라 부재 시 안전 no-op.
##
## 입력 경로는 root.push_input 실제 이벤트로 검증하고, physics 등록은 프레임 대기로
## 확인한다(task3d0013 테스트와 동일 방식).

enum Phase {
	SETUP, CONTRACT, PROBE_SETUP, SELECT_LEFT, DESELECT_RIGHT, RESELECT_ESC,
	EMPTY_GROUND, NON_TARGETS, UI_BLOCK_ON, UI_BLOCK_OFF, OVERLAY_GATE,
	BUILD_GATE, NIGHT_GATE, NO_CAMERA_SAFETY, DONE,
}

const GODOT_EPS := 0.0001
const PHYSICS_WAIT_FRAMES := 30


var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
## selection 노드는 전역 class_name 참조 대신 load()로 늦게 로드한다.
## 메인 --script는 autoload/class cache 등록 전에 컴파일될 수 있으므로
## 전역 클래스 정적 의존을 피하는 관례다(task3d0013 규약).
var _sel: Node = null
var _cam_ctl: Node = null
var _game_time: Node = null
var _probe: Area3D = null
var _deco_visual: MeshInstance3D = null
var _resource_body: StaticBody3D = null
var _muted_target: Area3D = null
var _ui_block: Control = null
var _modal: Control = null
var _placement: Node = null
var _selection_events: Array = []


## 선택/interact 호출을 기록하는 test interactable.
## selectable 플래그로 is_selectable() hook 동작을 함께 검증한다.
class ProbeInteractable extends "res://scripts/interactable_3d.gd":
	var interact_count := 0
	var last_interactor: Node = null
	var selectable := true

	func is_selectable() -> bool:
		return selectable

	func interact(interactor: Node) -> Variant:
		interact_count += 1
		last_interactor = interactor
		return {}


class FakePlacement extends Node:
	func is_active() -> bool:
		return true


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	for node in [_probe, _deco_visual, _resource_body, _muted_target,
			_ui_block, _modal, _placement]:
		if node != null and is_instance_valid(node):
			node.free()
	print("TASK3D0014_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _view_center() -> Vector2:
	return root.get_visible_rect().size * 0.5


func _v3_near(a: Vector3, b: Vector3, eps := GODOT_EPS) -> bool:
	return absf(a.x - b.x) <= eps and absf(a.y - b.y) <= eps and absf(a.z - b.z) <= eps


func _screen_of(world_pos: Vector3) -> Vector2:
	return _cam_ctl.get_camera().unproject_position(world_pos)


func _push_click(button: MouseButton, screen_pos: Vector2) -> void:
	## 실제 클릭은 항상 포인터가 화면 위에 있는 상태에서 들어오므로
	## motion 이벤트를 선행시켜 GUI hover 상태를 먼저 만든다(task3d0013 규약).
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = screen_pos
	root.push_input(event)


func _push_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)


func _make_sphere_collider(radius: float) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	return shape


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.PROBE_SETUP:
			_probe_setup()
		Phase.SELECT_LEFT:
			_select_left()
		Phase.DESELECT_RIGHT:
			_deselect_right()
		Phase.RESELECT_ESC:
			_reselect_esc()
		Phase.EMPTY_GROUND:
			_empty_ground()
		Phase.NON_TARGETS:
			_non_targets()
		Phase.UI_BLOCK_ON:
			_ui_block_on()
		Phase.UI_BLOCK_OFF:
			_ui_block_off()
		Phase.OVERLAY_GATE:
			_overlay_gate()
		Phase.BUILD_GATE:
			_build_gate()
		Phase.NIGHT_GATE:
			_night_gate()
		Phase.NO_CAMERA_SAFETY:
			_no_camera_safety()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3D0014_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	var cam_scene: Node = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	cam_scene.name = "CamController"
	root.add_child(cam_scene)
	_sel = load("res://scripts/world_selection_3d.gd").new()
	_sel.name = "WorldSelection3D"
	root.add_child(_sel)


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_cam_ctl = root.get_node_or_null("CamController")
	_game_time = root.get_node_or_null("GameTime")
	_check(_world != null, "empty 3D world loads")
	_check(_cam_ctl != null, "camera controller 3D loads")
	_check(_sel != null, "world selection 3D loads")
	if _sel == null or _cam_ctl == null:
		_finish()
		return
	_check(_sel.is_in_group("world_selection_3d"),
		"selection joins dedicated world_selection_3d group")
	_check(not _sel.selection_changed.is_null(),
		"exposes selection_changed signal for parallel domain tasks")
	_check(_sel.get_selected() == null, "initial selection is empty")
	# phase gate 판정을 결정적으로 만들기 위해 자동 시간 진행을 멈춘다(종료 시 복원).
	_game_time.set_auto_advance(false)
	_enter(Phase.CONTRACT)


## -- CONTRACT: Interactable3D base 기본값 + mask 단일 소스 --
func _contract() -> void:
	var base: Area3D = (load("res://scripts/interactable_3d.gd") as GDScript).new()
	_check(base != null and base is Area3D, "Interactable3D contract extends Area3D")
	_check(base.prompt == "상호작용", "base exposes default interaction prompt export")
	_check(base.can_interact(), "base can_interact defaults to true")
	_check(base.is_selectable(), "base is_selectable defaults to true")
	_check(base.interact(null) == null, "base interact returns null by default")
	base.free()
	_check(CollisionLayers3D.MASK_SELECTION == CollisionLayers3D.INTERACTABLE,
		"selection probes the dedicated INTERACTABLE layer only")
	_check(_sel.SELECTION_RAY_LENGTH > 0.0, "selection ray length constant is positive")
	_enter(Phase.PROBE_SETUP)


## -- PROBE_SETUP: test interactable 3D object들 physics 등록 대기 --
func _probe_setup() -> void:
	if _probe == null:
		_probe = ProbeInteractable.new()
		_probe.name = "ProbeTarget"
		_probe.collision_layer = CollisionLayers3D.INTERACTABLE
		_probe.collision_mask = 0
		_probe.add_child(_make_sphere_collider(1.0))
		_probe.position = Vector3(0.0, 1.0, 0.0)
		_sel.selection_changed.connect(func(target): _selection_events.append(target))
		_world.add_child(_probe)

		_deco_visual = MeshInstance3D.new()
		_deco_visual.name = "DecorationVisual"
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 1.0, 2.0)
		_deco_visual.mesh = box
		_deco_visual.position = Vector3(-60.0, 0.5, -60.0)
		_world.add_child(_deco_visual)

		_resource_body = StaticBody3D.new()
		_resource_body.name = "ResourceBlock"
		_resource_body.collision_layer = CollisionLayers3D.RESOURCE
		_resource_body.collision_mask = 0
		_resource_body.add_child(_make_sphere_collider(1.0))
		_resource_body.position = Vector3(60.0, 1.0, 60.0)
		_world.add_child(_resource_body)

		_muted_target = ProbeInteractable.new()
		_muted_target.name = "MutedTarget"
		_muted_target.collision_layer = CollisionLayers3D.INTERACTABLE
		_muted_target.collision_mask = 0
		_muted_target.add_child(_make_sphere_collider(1.0))
		_muted_target.position = Vector3(-60.0, 1.0, 60.0)
		_world.add_child(_muted_target)
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_enter(Phase.SELECT_LEFT)


## -- SELECT_LEFT: 실제 Left click으로 유효한 대상 1개 선택 + interact 실행 --
func _select_left() -> void:
	_push_click(MOUSE_BUTTON_LEFT, _screen_of(_probe.global_position))
	var picked = _sel.get_selected()
	_check(picked == _probe,
		"left click selects exactly the ray-hit interactable (physics registered)")
	_check(_probe.interact_count == 1, "selection runs the existing interact() API once")
	_check(_probe.last_interactor == _sel,
		"interact receives the selection node as interactor")
	_check(_selection_events == [_probe],
		"selection_changed emitted once with the selected target")
	_check(_muted_target.interact_count == 0,
		"other interactables are untouched (single-target pick)")
	_enter(Phase.DESELECT_RIGHT)


## -- DESELECT_RIGHT: 우클릭 해제 --
func _deselect_right() -> void:
	_push_click(MOUSE_BUTTON_RIGHT, _view_center())
	_check(_sel.get_selected() == null, "right click clears the selection")
	_check(_selection_events == [_probe, null],
		"clearing emits selection_changed with null")
	_check(_probe.interact_count == 1, "deselect does not call interact again")
	_enter(Phase.RESELECT_ESC)


## -- RESELECT_ESC: API 재선택 + ESC 해제 --
func _reselect_esc() -> void:
	var returned = _sel.select_at_screen_position(_screen_of(_probe.global_position))
	_check(returned == _probe, "select_at_screen_position API returns the picked target")
	_push_escape()
	_check(_sel.get_selected() == null,
		"ESC clears the selection without consuming the modal close path")
	_check(_selection_events == [_probe, null, _probe, null],
		"select/deselect signal pairs stay balanced across input paths")
	_enter(Phase.EMPTY_GROUND)


## -- EMPTY_GROUND: 빈 ground 클릭 안전(선택 유지 규약 포함) --
func _empty_ground() -> void:
	_push_click(MOUSE_BUTTON_LEFT, Vector2(5.0, 5.0))
	_check(_sel.get_selected() == null, "empty ground/sky corner click selects nothing")
	_push_click(MOUSE_BUTTON_LEFT, _screen_of(_probe.global_position))
	_check(_sel.get_selected() == _probe, "probe re-selected after empty clicks")
	var center_ground: Vector3 = _cam_ctl.ground_point_from_screen(_view_center())
	_check(_v3_near(center_ground, Vector3.ZERO, 0.01),
		"screen center resolves to empty world ground (safe miss surface)")
	_push_click(MOUSE_BUTTON_LEFT, Vector2(5.0, 5.0))
	_check(_sel.get_selected() == _probe,
		"missed click keeps the current selection unchanged (2D parity rule)")
	_enter(Phase.NON_TARGETS)


## -- NON_TARGETS: decoration 비주얼 / RESOURCE layer / selectable=false 안전 --
func _non_targets() -> void:
	_push_click(MOUSE_BUTTON_LEFT, _screen_of(_deco_visual.global_position))
	_check(_sel.get_selected() == _probe,
		"clicking decoration visual never steals or clears selection")
	_push_click(MOUSE_BUTTON_LEFT, _screen_of(_resource_body.global_position))
	_check(_sel.get_selected() == _probe,
		"RESOURCE layer body is structurally excluded from the selection probe")
	_muted_target.selectable = false
	_push_click(MOUSE_BUTTON_LEFT, _screen_of(_muted_target.global_position))
	_check(_sel.get_selected() == _probe,
		"is_selectable()==false target is skipped by the selection contract")
	_check(_muted_target.interact_count == 0,
		"skipped target never receives interact()")
	_muted_target.selectable = true
	_push_click(MOUSE_BUTTON_RIGHT, _view_center())
	_enter(Phase.UI_BLOCK_ON)


## -- UI_BLOCK_ON: STOP Control이 좌클릭을 소비하면 선택되지 않아야 한다 --
func _ui_block_on() -> void:
	if _ui_block == null:
		_ui_block = ColorRect.new()
		_ui_block.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ui_block.mouse_filter = Control.MOUSE_FILTER_STOP
		root.add_child(_ui_block)
		_wait = 0
		return
	_wait += 1
	if _wait < 3:
		return
	_push_click(MOUSE_BUTTON_LEFT, _screen_of(_probe.global_position))
	_check(_sel.get_selected() == null,
		"left click over full-screen STOP control never reaches world selection (no leak)")
	_ui_block.free()
	_ui_block = null
	_wait = 0
	_enter(Phase.UI_BLOCK_OFF)


## -- UI_BLOCK_OFF: 같은 입력이 UI 없이는 정상 처리되어야 한다(대조군) --
func _ui_block_off() -> void:
	_wait += 1
	if _wait < 2:
		return
	_push_click(MOUSE_BUTTON_LEFT, _screen_of(_probe.global_position))
	_check(_sel.get_selected() == _probe,
		"same click without UI still selects (control group)")
	_push_click(MOUSE_BUTTON_RIGHT, _view_center())
	_wait = 0
	_enter(Phase.OVERLAY_GATE)


## -- OVERLAY_GATE: 모달 UI 그룹이 열려 있으면 월드 클릭 차단 --
func _overlay_gate() -> void:
	var all_gated := true
	for group_name in ["recruitment_ui", "inn_roster_ui", "world_map_overlay"]:
		_modal = Control.new()
		_modal.visible = true
		_modal.add_to_group(group_name)
		root.add_child(_modal)
		all_gated = all_gated and not _sel.can_handle_world_click()
		if group_name == "recruitment_ui":
			_push_click(MOUSE_BUTTON_LEFT, _screen_of(_probe.global_position))
			all_gated = all_gated and _sel.get_selected() == null
		_modal.free()
		_modal = null
	_check(all_gated,
		"open modal UI groups block world clicks entirely (UI leak-free contract)")
	_check(_sel.get_selected() == null, "gated clicks left no selection behind")
	_enter(Phase.BUILD_GATE)


## -- BUILD_GATE: build mode 활성 시 월드 클릭 차단 --
func _build_gate() -> void:
	_placement = FakePlacement.new()
	_placement.add_to_group("building_placement")
	root.add_child(_placement)
	_check(not _sel.can_handle_world_click(),
		"active build mode blocks world selection (placement ghost priority preserved)")
	var returned = _sel.select_at_screen_position(_screen_of(_probe.global_position))
	_check(returned == null and _sel.get_selected() == null,
		"gated select call is a safe no-op")
	_placement.free()
	_placement = null
	_check(_sel.can_handle_world_click(),
		"world selection resumes when build mode deactivates")
	_enter(Phase.NIGHT_GATE)


## -- NIGHT_GATE: NIGHT에서는 월드 클릭 선택을 하지 않는다(전술 조작 위임 규약) --
func _night_gate() -> void:
	_game_time.advance(_game_time.day_duration)
	_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "test setup reached NIGHT phase")
	_check(not _sel.can_handle_world_click(),
		"NIGHT phase blocks managed world selection (tactical UI owns night input)")
	var returned = _sel.select_at_screen_position(_screen_of(_probe.global_position))
	_check(returned == null and _sel.get_selected() == null,
		"NIGHT click is a safe no-op even over a valid target")
	_game_time.advance(_game_time.night_duration)
	_check(_game_time.get_phase() == _game_time.Phase.DAY,
		"test setup returned to DAY phase")
	_check(_sel.can_handle_world_click(), "DAY phase restores world selection")
	_enter(Phase.NO_CAMERA_SAFETY)


## -- NO_CAMERA_SAFETY: 카메라 부재 시 안전 no-op --
func _no_camera_safety() -> void:
	_cam_ctl.free()
	_cam_ctl = null
	var returned = _sel.select_at_screen_position(_view_center())
	_check(returned == null and _sel.get_selected() == null,
		"missing camera controller makes selection a safe no-op (no crash)")
	_finish()
