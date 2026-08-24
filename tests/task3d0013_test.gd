extends SceneTree

## TASK-3D-001-3 Camera3D Pan / Zoom / Screen-to-World 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. Orthographic Camera3D 컨트롤러 로드 및 고정 사선 Pitch/Yaw(회전 입력 경로 없음).
##   2. WASD XZ pan(action 입력 경로)과 World boundary clamp(WorldCoords3D 단일 소스).
##   3. Mouse wheel zoom(orthographic size 기반) + 최소/최대 clamp.
##   4. Screen mouse position -> 3D ground/world ray 변환 + physics raycast.
##   5. UI 위 Mouse 입력이 world 조작으로 누수되지 않음(unhandled input 계약).
##   6. 모달 overlay(world_map_overlay 그룹) 게이트.
##   7. DAY/NIGHT zoom policy 매핑(Tactical Migration 재사용 계약).
##
## 이동/수렴 검증은 컨트롤러의 process/physics 핸들러에 고정 delta를 직접 넣어
## 실행해 headless 프레임 페이싱에 의존하지 않는다.

enum Phase {
	SETUP, ORIENTATION, PAN_API, PAN_KEYS, ZOOM_WHEEL, ZOOM_MAP, ZOOM_CONVERGE,
	SCREEN_WORLD_SETUP, SCREEN_WORLD, UI_BLOCK_ON, UI_BLOCK_OFF,
	OVERLAY_GATE, POLICY, DONE,
}

const GODOT_EPS := 0.0001
const FIXED_DELTA := 1.0 / 60.0


## headless 창 크기는 프로젝트 설정과 다를 수 있으므로 화면 중앙을 동적으로 구한다.
func _view_center() -> Vector2:
	return root.get_visible_rect().size * 0.5


var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
## 컨트롤러는 전역 class_name 참조 대신 load()로 늦게 로드한다. 메인 --script는
## autoload 등록 전에 컴파일되므로 전역 클래스 정적 의존을 피하는 관례다.
var _cam_ctl: Node = null
var _probe: StaticBody3D = null
var _ui_block: Control = null
var _overlay: Node = null
var _rotation_snapshot := Vector3.ZERO
var _zoom_before := 0.0
var _pan_before := Vector3.ZERO
var _pan_stage := 0
var _key_wait := 0


class FakeOverlay extends Node:
	func is_open() -> bool:
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
	for node in [_probe, _ui_block, _overlay]:
		if node != null and is_instance_valid(node):
			node.free()
	print("TASK3D0013_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= GODOT_EPS


func _v3_near(a: Vector3, b: Vector3, eps := GODOT_EPS) -> bool:
	return absf(a.x - b.x) <= eps and absf(a.y - b.y) <= eps and absf(a.z - b.z) <= eps


func _push_wheel(up: bool) -> void:
	## 실제 마우스 휠은 항상 포인터가 화면 위에 있는 상태에서 들어오므로
	## motion 이벤트를 선행시켜 GUI hover 상태를 먼저 만든다.
	var motion := InputEventMouseMotion.new()
	motion.position = _view_center()
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.position = _view_center()
	root.push_input(event)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.ORIENTATION:
			_orientation()
		Phase.PAN_API:
			_pan_api()
		Phase.PAN_KEYS:
			_pan_keys()
		Phase.ZOOM_WHEEL:
			_zoom_wheel()
		Phase.ZOOM_MAP:
			_zoom_map()
		Phase.ZOOM_CONVERGE:
			_zoom_converge()
		Phase.SCREEN_WORLD_SETUP:
			_screen_world_setup()
		Phase.SCREEN_WORLD:
			_screen_world()
		Phase.UI_BLOCK_ON:
			_ui_block_on()
		Phase.UI_BLOCK_OFF:
			_ui_block_off()
		Phase.OVERLAY_GATE:
			_overlay_gate()
		Phase.POLICY:
			_policy()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3D0013_RESULT=TIMEOUT phase=%s" % str(_phase))
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


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_cam_ctl = root.get_node_or_null("CamController")
	_check(_world != null, "empty 3D world loads")
	_check(_cam_ctl != null, "camera controller 3D loads")
	if _cam_ctl == null:
		_finish()
		return
	_check(_cam_ctl.is_in_group("camera_controller_3d"),
		"controller joins dedicated camera_controller_3d group")
	var camera: Camera3D = _cam_ctl.get_camera()
	_check(camera != null and camera is Camera3D, "controller owns a Camera3D child")
	_check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"projection is orthographic (Top-down Direction LOCK 4)")
	_check(camera.current, "Camera3D is current in this viewport")
	_check(_near(_cam_ctl.get_zoom_target(), _cam_ctl.day_zoom),
		"initial zoom target follows DAY policy")
	_enter(Phase.ORIENTATION)


## -- ORIENTATION --
func _orientation() -> void:
	var camera: Camera3D = _cam_ctl.get_camera()
	var expected_rot := Vector3(
		deg_to_rad(_cam_ctl.pitch_degrees), deg_to_rad(_cam_ctl.yaw_degrees), 0.0)
	_rotation_snapshot = camera.global_rotation
	_check(_v3_near(camera.global_rotation, expected_rot, 0.001),
		"fixed oblique pitch/yaw applied exactly (%.0f/%.0f deg)"
		% [_cam_ctl.pitch_degrees, _cam_ctl.yaw_degrees])
	_check(camera.global_position.y > WorldCoords3D.GROUND_Y,
		"camera looks down from above the ground plane")
	_check(camera.global_position.z > 0.0,
		"oblique view keeps north(-Z) toward screen top (direction semantics)")
	_push_wheel(true)
	_check(_v3_near(camera.global_rotation, _rotation_snapshot, GODOT_EPS),
		"no input path mutates camera rotation (rotation lock)")
	_enter(Phase.PAN_API)


## -- PAN_API --
func _pan_api() -> void:
	var bounds: AABB = _cam_ctl.get_world_bounds_aabb()
	var foundation_bounds := WorldCoords3D.world_bounds_aabb()
	_check(_v3_near(bounds.position, foundation_bounds.position)
		and _v3_near(bounds.size, foundation_bounds.size),
		"bounds accessor uses WorldCoords3D single source")

	_cam_ctl.position = Vector3.ZERO
	_cam_ctl.pan_camera(Vector3(5000.0, 0.0, 5000.0))
	_check(_v3_near(_cam_ctl.position,
			Vector3(foundation_bounds.end.x, 0.0, foundation_bounds.end.z)),
		"pan_camera clamps pivot to max world corner (+192, +192)")
	_cam_ctl.pan_camera(Vector3(-10000.0, 5.0, -10000.0))
	_check(_v3_near(_cam_ctl.position,
			Vector3(foundation_bounds.position.x, 0.0, foundation_bounds.position.z)),
		"pan_camera clamps pivot to min world corner (-192, -192) and pins Y to ground")
	_cam_ctl.pan_camera(Vector3(10.0, 0.0, 20.0))
	_check(_v3_near(_cam_ctl.position, Vector3(-182.0, 0.0, -172.0)),
		"in-bounds offset moves pivot freely without extra drift")
	_enter(Phase.PAN_KEYS)


## -- PAN_KEYS (실제 action 입력으로 _physics_process 경로 검증, 고정 delta 스텝) --
func _pan_keys() -> void:
	if _pan_stage == 0:
		_cam_ctl.position = Vector3.ZERO
		Input.action_press("move_right")
		_key_wait = 0
		_pan_stage = 1
	elif _pan_stage == 1:
		_cam_ctl._physics_process(FIXED_DELTA)
		_key_wait += 1
		if _key_wait >= 30:
			Input.action_release("move_right")
			var moved_x: float = _cam_ctl.position.x
			_check(moved_x > 1.0,
				"WASD move_right pans east (+X), moved %.2f unit / %.0f ticks"
				% [moved_x, _key_wait])
			_check(_near(_cam_ctl.position.z, 0.0), "east pan does not drift on Z axis")
			_pan_before = _cam_ctl.position
			Input.action_press("move_up")
			_key_wait = 0
			_pan_stage = 2
	else:
		_cam_ctl._physics_process(FIXED_DELTA)
		_key_wait += 1
		if _key_wait >= 30:
			Input.action_release("move_up")
			var moved_z: float = _cam_ctl.position.z - _pan_before.z
			_check(moved_z < -1.0,
				"WASD move_up pans north (-Z, direction semantics preserved), %.2f unit" % moved_z)
			_cam_ctl.position = Vector3.ZERO
			_pan_stage = 0
			_enter(Phase.ZOOM_WHEEL)


## -- ZOOM_WHEEL (실제 wheel 이벤트로 _unhandled_input 경로 검증) --
func _zoom_wheel() -> void:
	if _wait == 0:
		_zoom_before = _cam_ctl.get_zoom_target()
		_wait += 1
		_push_wheel(true)
		return
	_wait += 1
	if _wait == 2:
		_check(_near(_cam_ctl.get_zoom_target(), _zoom_before + _cam_ctl.wheel_zoom_step),
			"single wheel up raises zoom target by wheel step")
		for i in 60:
			_push_wheel(true)
		return
	_check(_near(_cam_ctl.get_zoom_target(), _cam_ctl.max_zoom),
		"repeated zoom-in clamps at max_zoom (%.1f)" % _cam_ctl.max_zoom)
	for i in 120:
		_push_wheel(false)
	_check(_near(_cam_ctl.get_zoom_target(), _cam_ctl.min_zoom),
		"repeated zoom-out clamps at min_zoom (%.1f)" % _cam_ctl.min_zoom)
	_wait = 0
	_enter(Phase.ZOOM_MAP)


## -- ZOOM_MAP (zoom 배율 -> orthographic size 매핑 계약) --
func _zoom_map() -> void:
	var base_units := root.get_visible_rect().size.y * WorldCoords3D.PX_TO_UNIT
	var size_at_day: float = _cam_ctl._ortho_size_for_zoom(_cam_ctl.day_zoom)
	var size_at_night: float = _cam_ctl._ortho_size_for_zoom(_cam_ctl.night_zoom)
	_check(_near(size_at_day, base_units),
		"zoom 1.0 maps to viewport height in world units (2D zoom parity formula)")
	_check(_near(size_at_night, base_units / _cam_ctl.night_zoom),
		"NIGHT zoom 0.5 doubles visible height (overview command view)")
	var monotonic := true
	var prev := INF
	for z in [0.4, 0.5, 0.8, 1.0, 1.5, 2.0]:
		var s: float = _cam_ctl._ortho_size_for_zoom(float(z))
		if s >= prev:
			monotonic = false
		prev = s
	_check(monotonic, "higher zoom always means smaller orthographic size")
	_wait = 0
	_enter(Phase.ZOOM_CONVERGE)


## -- ZOOM_CONVERGE (고정 delta로 _process를 스텝 진행해 수렴 검증) --
func _zoom_converge() -> void:
	if _wait == 0:
		var camera: Camera3D = _cam_ctl.get_camera()
		camera.size = 10000.0
		_wait += 1
		return
	for i in 400:
		_cam_ctl._process(FIXED_DELTA)
	var target_size: float = _cam_ctl._ortho_size_for_zoom(_cam_ctl.get_zoom_target())
	var size: float = _cam_ctl.get_camera().size
	var rel_err := absf(size - target_size) / target_size
	_check(rel_err < 0.001,
		"orthographic size converges to derived target (rel err %.6f)" % rel_err)
	_wait = 0
	_enter(Phase.SCREEN_WORLD_SETUP)


## -- SCREEN_WORLD_SETUP --
func _screen_world_setup() -> void:
	var camera: Camera3D = _cam_ctl.get_camera()

	var p := Vector3(10.0, 0.0, -20.0)
	var screen := camera.unproject_position(p)
	var q: Vector3 = _cam_ctl.ground_point_from_screen(screen)
	_check(_v3_near(q, p, 0.01),
		"screen -> ground plane round trip restores world point %s" % str(p))
	_check(_near(q.y, WorldCoords3D.GROUND_Y), "ground hit lies on Y = GROUND_Y plane")

	var ray: Dictionary = _cam_ctl.screen_to_world_ray(_view_center())
	_check(not ray.is_empty() and ray.has("origin") and ray.has("direction"),
		"screen_to_world_ray provides origin/direction for selection consumers")
	var direction: Vector3 = ray["direction"]
	_check(direction.length() > 0.999 and direction.length() < 1.001,
		"ray direction is normalized")
	_check(direction.y < 0.0, "screen ray points downward into the ground")

	var corner: Vector3 = _cam_ctl.ground_point_from_screen(Vector2(5.0, 5.0))
	_check(corner.is_finite() and _near(corner.y, WorldCoords3D.GROUND_Y),
		"corner screen point resolves to a finite ground coordinate (safe empty-ground click)")

	_probe = StaticBody3D.new()
	_probe.name = "RayProbe"
	_probe.collision_layer = CollisionLayers3D.BUILDING
	_probe.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	_probe.add_child(shape)
	_probe.position = Vector3(30.0, 1.0, 30.0)
	_world.add_child(_probe)
	_wait = 0
	_enter(Phase.SCREEN_WORLD)


## -- SCREEN_WORLD (physics raycast, 등록 대기 후 검증) --
func _screen_world() -> void:
	_wait += 1
	if _wait < 30:
		return
	var probe_pos: Vector3 = _probe.global_position
	var screen: Vector2 = _cam_ctl.get_camera().unproject_position(probe_pos)
	var hit: Dictionary = _cam_ctl.raycast_from_screen(screen, CollisionLayers3D.BUILDING)
	var collider: Object = hit.get("collider") if not hit.is_empty() else null
	_check(collider == _probe, "raycast_from_screen hits probe body through screen point")

	var empty_hit: Dictionary = _cam_ctl.raycast_from_screen(
		Vector2(5.0, 5.0), CollisionLayers3D.BUILDING)
	_check(empty_hit.is_empty(), "empty area raycast returns no collider (safe miss)")

	var ground_mask_hit: Dictionary = _cam_ctl.raycast_from_screen(
		_view_center(), CollisionLayers3D.GROUND)
	_check(not ground_mask_hit.is_empty(),
		"ground layer raycast reaches world ground (mouse -> world path usable)")

	_wait = 0
	_enter(Phase.UI_BLOCK_ON)


## -- UI_BLOCK_ON: Control(STOP)이 wheel을 소비하면 zoom이 변경되지 않아야 한다 --
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
	_zoom_before = _cam_ctl.get_zoom_target()
	_push_wheel(true)
	_check(_near(_cam_ctl.get_zoom_target(), _zoom_before),
		"wheel over full-screen STOP control does not leak into zoom (UI click-through blocked)")
	_ui_block.free()
	_ui_block = null
	_wait = 0
	_enter(Phase.UI_BLOCK_OFF)


## -- UI_BLOCK_OFF: 같은 입력이 UI 없이는 정상 처리되어야 한다(대조군) --
func _ui_block_off() -> void:
	_wait += 1
	if _wait < 2:
		return
	_zoom_before = _cam_ctl.get_zoom_target()
	_push_wheel(true)
	_check(not _near(_cam_ctl.get_zoom_target(), _zoom_before),
		"same wheel input without UI still adjusts zoom (control group)")
	_wait = 0
	_enter(Phase.OVERLAY_GATE)


## -- OVERLAY_GATE: 모달 overlay(world_map_overlay) 열림 시 pan/wheel 게이트 --
func _overlay_gate() -> void:
	if _overlay == null:
		_overlay = FakeOverlay.new()
		_overlay.add_to_group("world_map_overlay")
		root.add_child(_overlay)
		_wait = 0
		return
	_wait += 1
	if _wait == 2:
		_zoom_before = _cam_ctl.get_zoom_target()
		_pan_before = _cam_ctl.position
		Input.action_press("move_right")
		for i in 10:
			_cam_ctl._physics_process(FIXED_DELTA)
		Input.action_release("move_right")
		_push_wheel(true)
		_check(_v3_near(_cam_ctl.position, _pan_before),
			"open modal overlay gates WASD pan")
		_check(_near(_cam_ctl.get_zoom_target(), _zoom_before),
			"open modal overlay gates wheel zoom")
		_overlay.free()
		_overlay = null
		_wait = 0
		_enter(Phase.POLICY)


## -- POLICY: DAY/NIGHT 매핑은 Tactical Migration이 재사용하는 계약이다.
## 전역 GameTime 상태를 오염시키지 않기 위해 signal 연결과 핸들러를 직접 검증한다.
## 메인 스크립트는 autoload 등록 전에 컴파일되므로 인스턴스 접근은
## root.get_node 패턴을 사용한다(기존 테스트 관례와 동일). --
func _policy() -> void:
	var game_time: Node = root.get_node("GameTime")
	_check(game_time.phase_changed.is_connected(_cam_ctl._on_phase_changed),
		"controller subscribes GameTime.phase_changed (policy reuse contract)")
	_cam_ctl._on_phase_changed(game_time.Phase.NIGHT, 1)
	_check(_cam_ctl.is_night_mode() and _near(_cam_ctl.get_zoom_target(), _cam_ctl.night_zoom),
		"NIGHT phase switches tactical overview zoom (night_zoom)")
	_cam_ctl._on_phase_changed(game_time.Phase.DAY, 2)
	_check(not _cam_ctl.is_night_mode() and _near(_cam_ctl.get_zoom_target(), _cam_ctl.day_zoom),
		"DAY phase restores day_zoom")
	_check(_v3_near(_cam_ctl.get_camera().global_rotation, _rotation_snapshot, 0.001),
		"camera rotation unchanged across entire run (no rotation input exists)")
	_finish()
