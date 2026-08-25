extends SceneTree

## TASK-3D-BLD-001-3 Wall / Gate 3D 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. Gate3D 공개 API/signal이 기존 gate.gd(TASK-013-4/014-5)와 동일 계약
##      (is_open/set_open/set_closed/toggle/take_damage + gate_state_changed/breached).
##   2. orientation이 3D world 방향과 일치: N/S Corridor gate = world X로 길게,
##      E/W = world Z로 길게(기존 4방향/Corridor 의미 유지).
##   3. Wall3D 인접 연결 비주얼: 배치 시 link 생성, 철거 시 제거, 멱등 refresh,
##      collision footprint 불변(기존 wall.gd TASK-013-2 규약).
##   4. collision state 전환: CLOSED = passage shape 존재 + probe 물리 차단,
##      OPEN/BREACHED = shape 제거 + probe 통과(Foundation policy §3).
##   5. nav 갱신: 상태 전환마다 Foundation 단일 유입구(request_rebuild_debounced)로
##      rebake가 coalesce되고, CLOSED 경로 우회 / OPEN 경로 통과가 반영된다.
##   6. BREACH: CLOSED 성문만 피해 적용, HP 0에서 영구 개방, 재닫기 no-op.
##   7. Interact toggle(prompt/interact)과 scene의 2D 의존 부재.
##
## placement 배치는 실제 진입점(_try_place_*)으로 수행해 validation/cost wiring까지
## 함께 검증한다. autoload는 --script 모드에서 컴파일 타임 식별자가 아니므로 노드
## 조회로만 사용한다(class_name 유틸은 정적 참조 가능).

enum Phase {
	SETUP, CONTRACT, ORIENTATION, WALL_LINKS, GATE_CLOSED, GATE_OPEN,
	TOGGLE_REPEAT, BREACH, NO_2D_DEP, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const START_WOOD := 1000

## fixture 좌표(cell corner grid, 서로 겹치지 않음).
const WALL_A := Vector3(20, 0, 20)
const WALL_B := Vector3(22, 0, 20)
const WALL_LONE := Vector3(40, 0, 20)
const GATE_NORTH := Vector3(0, 0, -80)
const GATE_EAST := Vector3(60, 0, 0)
## nav 통과 판정용 지점(북 corridor 안/밖).
const INSIDE := Vector3(0, 0, -70)
const OUTSIDE := Vector3(0, 0, -90)

var _frame := 0
var _pf := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _sp := 0
var _step_done := false

var _world: Node3D = null
var _placement: Node = null
var _nav_manager: Node = null
var _resources: Node = null
var _probe: CharacterBody3D = null
var _gate: Node = null

var _signal_count := 0
var _breach_count := 0
var _sig0 := 0
var _rebakes0 := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_sp = 0
	_step_done = false
	_pf = 0


func _finish() -> void:
	print("TASK3DBLD0013_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _on_gate_signal(_gate: Node, _open: bool) -> void:
	_signal_count += 1


func _on_breached(_gate: Node) -> void:
	_breach_count += 1


func _gate_shape() -> CollisionShape3D:
	return _gate.get_node_or_null("CollisionShape3D") as CollisionShape3D


func _gate_body_mesh() -> MeshInstance3D:
	return _gate.get_node("Visual/BodyMesh") as MeshInstance3D


func _probe_blocked() -> bool:
	return _probe.test_move(
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, -74.0)), Vector3(0.0, 0.0, -16.0))


func _segment_hits_gate(a: Vector3, b: Vector3, box: AABB) -> bool:
	var steps := int(ceil(a.distance_to(b) / 0.25)) + 1
	for i in steps:
		var p := a.lerp(b, float(i) / float(steps))
		if p.x >= box.position.x and p.x <= box.end.x \
				and p.z >= box.position.z and p.z <= box.end.z:
			return true
	return false


## nav 경로가 Gate footprint(XZ)를 가로지르는지. CLOSED면 우회(false),
## OPEN/BREACHED면 통과(true)되어야 한다(기존 task0134 규약의 3D판).
func _path_crosses_gate() -> bool:
	var path := NavigationServer3D.map_get_path(
		_nav_manager.get_navigation_map(), INSIDE, OUTSIDE, true)
	if path.size() < 2:
		return false
	var half: Vector2 = _gate.get_footprint_size() * 0.5 * WorldCoords3D.PX_TO_UNIT
	var center: Vector3 = _gate.global_position
	var box := AABB(
		Vector3(center.x - half.x, 0.0, center.z - half.y),
		Vector3(half.x * 2.0, 0.0, half.y * 2.0))
	for i in range(1, path.size()):
		if _segment_hits_gate(path[i - 1], path[i], box):
			return true
	return false


func _wait_frames(count: int) -> bool:
	_pf += 1
	return _pf >= count


func _process(_delta: float) -> bool:
	_frame += 1
	var phase_before: Phase = _phase
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.ORIENTATION:
			_orientation()
		Phase.WALL_LINKS:
			_wall_links()
		Phase.GATE_CLOSED:
			_gate_closed()
		Phase.GATE_OPEN:
			_gate_open()
		Phase.TOGGLE_REPEAT:
			_toggle_repeat()
		Phase.BREACH:
			_breach_phase()
		Phase.NO_2D_DEP:
			_no_2d_dep()
		Phase.DONE:
			_finish()
			return true
	if phase_before >= Phase.GATE_CLOSED and (_gate == null or not is_instance_valid(_gate)):
		print("FAIL: gate reference lost - aborting remaining phases")
		_failed = true
		_finish()
		return true
	if _frame > 4000:
		print("TASK3DBLD0013_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	_world = world_scene
	_nav_manager = load("res://scripts/navigation_manager_3d.gd").new()
	_nav_manager.name = "NavManager"
	_world.add_child(_nav_manager)
	_placement = load("res://scripts/building_placement_3d.gd").new()
	_placement.name = "BuildingPlacement3D"
	root.add_child(_placement)


func _setup() -> void:
	if _frame < 8:
		return
	_check(_world != null, "empty 3D world loads")
	_check(_placement != null, "building placement 3D loads")
	_resources = root.get_node_or_null("VillageResources")
	_check(_resources != null, "VillageResources autoload available to the 3D runtime")
	var game_time: Node = root.get_node_or_null("GameTime")
	if game_time != null and game_time.has_method("set_auto_advance"):
		game_time.set_auto_advance(false)
	# placement 진입점을 쓰기 위한 기본 자금.
	_resources.add("wood", START_WOOD)
	# 물리 통과 검증용 test fixture(기존 task0134 probe body 규약의 3D판).
	_probe = CharacterBody3D.new()
	_probe.name = "PhysicsProbe"
	_probe.collision_layer = CollisionLayers3D.WORKER
	_probe.collision_mask = CollisionLayers3D.MASK_ACTOR_SOLID
	var probe_shape := CollisionShape3D.new()
	var probe_box := BoxShape3D.new()
	probe_box.size = Vector3(1.0, 2.0, 1.0)
	probe_shape.shape = probe_box
	probe_shape.position.y = 1.0
	_probe.add_child(probe_shape)
	_world.add_child(_probe)
	_enter(Phase.CONTRACT)


## -- CONTRACT: 기존 gate.gd 공개 API/signal parity + interact 계약 --
func _contract() -> void:
	var wall_script: GDScript = load("res://scripts/wall_3d.gd")
	var gate_script: GDScript = load("res://scripts/gate_3d.gd")
	_check(wall_script.get_instance_base_type() == "StaticBody3D"
		and gate_script.get_instance_base_type() == "StaticBody3D",
		"Wall/Gate 3D remain static world colliders")

	var sample: StaticBody3D = (load("res://scenes/gate_3d.tscn") as PackedScene).instantiate()
	_check(sample.has_method("is_open") and sample.has_method("is_closed")
		and sample.has_method("is_breached") and sample.has_method("set_open")
		and sample.has_method("set_closed") and sample.has_method("toggle")
		and sample.has_method("take_damage"),
		"Gate3D keeps the legacy public state API surface")
	_check(sample.has_signal("gate_state_changed") and sample.has_signal("breached"),
		"Gate3D keeps the legacy public signals")
	_check(sample.is_closed() and not sample.is_open() and not sample.is_breached(),
		"a new gate starts CLOSED like in 2D")
	_check(sample.current_hp == sample.DEFAULT_MAX_HP
		and sample.max_hp == sample.DEFAULT_MAX_HP,
		"gate spawns with the legacy prototype max_hp (%d)" % sample.DEFAULT_MAX_HP)
	_check(sample.get_footprint_size() == Vector2(48, 16)
		and sample.get_orientation() == "horizontal",
		"gate defaults to the horizontal N/S corridor footprint")

	var interact: Area3D = sample.get_node_or_null("Interact") as Area3D
	_check(interact != null and interact.collision_layer == CollisionLayers3D.INTERACTABLE,
		"gate exposes an Interactable3D volume on the INTERACTABLE layer")
	_check(interact != null and interact.get_script() == load("res://scripts/gate_interactable_3d.gd"),
		"gate Interact uses the GateInteractable3D contract")
	sample.free()

	var wall_sample: StaticBody3D = (load("res://scenes/wall_3d.tscn") as PackedScene).instantiate()
	_check(wall_sample.has_method("refresh_visual"),
		"Wall3D exposes refresh_visual for the placement neighbor hook")
	wall_sample.free()
	_enter(Phase.ORIENTATION)


## -- ORIENTATION: 4방향 setup이 3D world 방향과 일치 --
func _orientation() -> void:
	var expected := {
		"north": {"orientation": "horizontal", "size": Vector2(48, 16), "units": Vector3(6.0, 2.0, 2.0)},
		"south": {"orientation": "horizontal", "size": Vector2(48, 16), "units": Vector3(6.0, 2.0, 2.0)},
		"east": {"orientation": "vertical", "size": Vector2(16, 48), "units": Vector3(2.0, 2.0, 6.0)},
		"west": {"orientation": "vertical", "size": Vector2(16, 48), "units": Vector3(2.0, 2.0, 6.0)},
	}
	var all_ok := true
	for dir in expected:
		var gate: StaticBody3D = (load("res://scenes/gate_3d.tscn") as PackedScene).instantiate()
		gate.setup(dir)
		var exp: Dictionary = expected[dir]
		var shape := gate.get_node("CollisionShape3D").shape as BoxShape3D
		if gate.get_direction() != dir or gate.get_orientation() != exp["orientation"] \
				or gate.get_footprint_size() != exp["size"] \
				or not shape.size.is_equal_approx(exp["units"]) \
				or gate.get_node("Visual/BodyMesh").mesh.size.x != exp["units"].x \
				or gate.get_node("Visual/BodyMesh").mesh.size.z != exp["units"].z:
			all_ok = false
			print("  mismatch on %s: size=%s units=%s" % [dir, gate.get_footprint_size(), shape.size])
		gate.free()
	_check(all_ok, "setup(dir) maps all 4 corridor directions to matching footprints")
	_check(WorldCoords3D.DIRECTION_XZ["north"] == Vector3(0, 0, -1)
		and WorldCoords3D.DIRECTION_XZ["south"] == Vector3(0, 0, 1)
		and WorldCoords3D.DIRECTION_XZ["east"] == Vector3(1, 0, 0)
		and WorldCoords3D.DIRECTION_XZ["west"] == Vector3(-1, 0, 0),
		"corridor directions keep the Foundation XZ world axes (N=-Z, E=+X)")
	_enter(Phase.WALL_LINKS)


## -- WALL_LINKS: 인접 link 비주얼 생성/제거/멱등 + collision footprint 불변 --
func _wall_links() -> void:
	match _sp:
		0:
			_placement._try_place_wall_at(WALL_A)
			_placement._try_place_wall_at(WALL_B)
			_placement._try_place_wall_at(WALL_LONE)
		1:
			var walls := get_nodes_in_group("walls_3d")
			_check(walls.size() == 3, "three wall segments placed through the legacy entry point")
			var a: StaticBody3D = null
			var b: StaticBody3D = null
			var lone: StaticBody3D = null
			for node in walls:
				var wall := node as StaticBody3D
				if wall.global_position.is_equal_approx(WALL_A):
					a = wall
				elif wall.global_position.is_equal_approx(WALL_B):
					b = wall
				elif wall.global_position.is_equal_approx(WALL_LONE):
					lone = wall
			_check(a != null and b != null and lone != null, "placed walls found at aimed cells")
			if a != null and b != null:
				var link_east := a.get_node_or_null("Visual/LinkEast") as MeshInstance3D
				var link_west := b.get_node_or_null("Visual/LinkWest") as MeshInstance3D
				_check(link_east != null, "adjacent pair gains an eastward link on the left wall")
				_check(link_west != null, "adjacent pair gains a westward link on the right wall")
				if link_east != null:
					var mesh := link_east.mesh as BoxMesh
					_check(is_equal_approx(mesh.size.x, WorldCoords3D.GRID_CELL_UNITS * 0.5)
						and is_equal_approx(mesh.size.z, 2.0),
						"link extends to the gap midpoint with the full footprint width")
					_check(not is_equal_approx(mesh.size.y, 0.0),
						"link is a real 3D visual (extruded height)")
				_check(a.get_node_or_null("Visual/LinkNorth") == null
					and a.get_node_or_null("Visual/LinkSouth") == null
					and a.get_node_or_null("Visual/LinkWest") == null,
					"unlinked directions stay bare")
			if lone != null:
				_check(lone.get_node_or_null("Visual/LinkEast") == null
					and lone.get_node_or_null("Visual/LinkNorth") == null
					and lone.get_node_or_null("Visual/LinkSouth") == null
					and lone.get_node_or_null("Visual/LinkWest") == null,
					"an isolated segment grows no links")
				var foot_shape := lone.get_node("CollisionShape3D").shape as BoxShape3D
				_check(foot_shape.size.is_equal_approx(Vector3(2, 2, 2)),
					"collision footprint stays the legacy 16x16px despite visual links")
				lone.refresh_visual()
				lone.refresh_visual()
				var vis_children := lone.get_node("Visual").get_child_count()
				lone.refresh_visual()
				_check(lone.get_node("Visual").get_child_count() == vis_children
					and lone.get_node_or_null("Visual/LinkEast") == null,
					"refresh_visual is idempotent for a lone segment")
				# 철거 후 인접 wall의 link가 정리되는지(placement remove hook).
				_placement._try_remove_wall_at(WALL_A)
		2:
			_check(get_nodes_in_group("walls_3d").size() == 2, "clicked wall segment is removed")
			var b: StaticBody3D = null
			for node in get_nodes_in_group("walls_3d"):
				var wall := node as StaticBody3D
				if wall.global_position.is_equal_approx(WALL_B):
					b = wall
			_check(b != null and b.get_node_or_null("Visual/LinkWest") == null,
				"surviving wall drops its link after the neighbor is removed")
			_enter(Phase.GATE_CLOSED)
			return
	_sp += 1


## -- GATE_CLOSED: 초기 CLOSED + collision/nav 차단 + rebake 유입구 --
func _gate_closed() -> void:
	match _sp:
		0:
			_placement._try_place_gate_at(GATE_NORTH)
			var gates := get_nodes_in_group("gates_3d")
			_check(gates.size() == 1, "north corridor gate placed through the legacy entry point")
			if gates.size() == 1:
				_gate = gates[0]
				_gate.gate_state_changed.connect(_on_gate_signal)
				_gate.breached.connect(_on_breached)
			_rebakes0 = _nav_manager.nav_rebuild_count
			_signal_count = 0
			_sp = 1
			_pf = 0
		1:
			if not _step_done:
				_step_done = true
				_check(_gate != null, "gate reference captured")
				_check(_gate.is_closed(), "freshly built gate starts CLOSED")
				_check(_gate.get_orientation() == "horizontal"
					and _gate.get_direction() == "north",
					"corridor direction resolved from world XZ (north)")
				var shape := _gate_shape()
				_check(shape != null and shape.shape.size.is_equal_approx(Vector3(6, 2, 2)),
					"CLOSED gate has its passage collision active (shape present)")
				_pf = 0
			elif _wait_frames(PHYSICS_WAIT_FRAMES):
				_check(_probe_blocked(), "CLOSED gate blocks a physics probe (test_move)")
				_check(not _path_crosses_gate(),
					"CLOSED gate: nav path detours around the footprint")
				_check(_nav_manager.nav_rebuild_count > _rebakes0,
					"placement reached the Foundation debounced nav rebake")
				_enter(Phase.GATE_OPEN)


## -- GATE_OPEN: set_open(true) -> signal 1회 + shape 제거 + probe/nav 통과 --
func _gate_open() -> void:
	match _sp:
		0:
			if not _step_done:
				_step_done = true
				_sig0 = _signal_count
				_rebakes0 = _nav_manager.nav_rebuild_count
				_gate.set_open(true)
				_check(_signal_count == _sig0 + 1,
					"set_open emits exactly one gate_state_changed")
				_check(_gate.is_open() and not _gate.is_closed(),
					"gate reports OPEN after set_open(true)")
				_check(_gate_shape() == null,
					"OPEN gate removes its passage collision shape (Foundation convention)")
				var mat := _gate_body_mesh().material_override as StandardMaterial3D
				_check(mat.albedo_color.is_equal_approx(_gate.COLOR_OPEN)
					and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
					"OPEN visual state shows the legacy translucent color")
				_pf = 0
			elif _wait_frames(PHYSICS_WAIT_FRAMES):
				_check(not _probe_blocked(), "OPEN gate lets a physics probe through")
				_check(_path_crosses_gate(), "OPEN gate: nav path crosses the footprint")
				_check(_nav_manager.nav_rebuild_count > _rebakes0,
					"state transition reached the Foundation debounced nav rebake")
				_enter(Phase.TOGGLE_REPEAT)


## -- TOGGLE_REPEAT: 반복 toggle에서 signal/collision/nav 일관 유지 --
func _toggle_repeat() -> void:
	match _sp:
		0:
			# 1회차는 Player 상호작용 경로(Interactable3D.interact)로 수행한다.
			var gi: Area3D = _gate.get_node("Interact")
			_check(gi.prompt == "Gate (OPEN) - Toggle", "prompt reflects the current state")
			_sig0 = _signal_count
			gi.interact(null)
			_check(_signal_count == _sig0 + 1 and _gate.is_closed(),
				"Interact toggle flips OPEN back to CLOSED with one signal")
			_check(gi.prompt == "Gate (CLOSED) - Toggle",
				"prompt refreshes after the state change")
			_pf = 0
			_sp += 1
		_:
			if not _step_done:
				# 동기 전환 검증(signal/collision/prompt).
				var want_open := (_sp % 2 == 1)
				_sig0 = _signal_count
				_gate.set_open(want_open)
				_step_done = true
				_check(_signal_count == _sig0 + 1,
					"toggle %d emits exactly one gate_state_changed" % _sp)
				_check(_gate.is_open() == want_open,
					"toggle %d lands in the requested state" % _sp)
				_check((_gate_shape() == null) == _gate.is_open(),
					"toggle %d keeps collision presence synced to is_open" % _sp)
				_pf = 0
			elif _wait_frames(PHYSICS_WAIT_FRAMES):
				_step_done = false
				_check(_path_crosses_gate() == _gate.is_open(),
					"toggle %d nav passage stays synced to the state" % _sp)
				if _sp >= 5:
					_enter(Phase.BREACH)
					return
				_sp += 1


## -- BREACH: CLOSED만 피해, HP 0에서 영구 개방, 재닫기 no-op --
func _breach_phase() -> void:
	match _sp:
		0:
			# OPEN 성문은 공격 대상이 아니다(no-op).
			_gate.set_open(true)
			_sig0 = _signal_count
			var hp_before: int = _gate.current_hp
			_gate.take_damage(50)
			_check(_gate.current_hp == hp_before and _signal_count == _sig0,
				"attacking an OPEN gate is a no-op (legacy rule)")
			_gate.set_closed()
			_sp = 1
			_pf = 0
		1:
			if _wait_frames(PHYSICS_WAIT_FRAMES):
				_check(_gate.is_closed(), "gate re-closed before breach checks")
				_check(_gate_shape() != null, "CLOSED again restores the passage shape")
				_sig0 = _signal_count
				_breach_count = 0
				_gate.take_damage(50)
				_check(_gate.current_hp == _gate.DEFAULT_MAX_HP - 50,
					"damage reduces hp only while CLOSED")
				_check(_signal_count == _sig0, "partial damage emits no state signal")
				_gate.take_damage(-10)
				_check(_gate.current_hp == _gate.DEFAULT_MAX_HP - 50,
					"non-positive damage is ignored (legacy guard)")
				_gate.take_damage(10000)
				_check(_gate.is_breached() and _gate.current_hp == 0,
					"hp depletion transitions to BREACHED")
				_check(_breach_count == 1, "breached signal emitted exactly once")
				_check(_signal_count == _sig0 + 1,
					"breaching emits exactly one gate_state_changed")
				_check(_gate.is_open(), "BREACHED counts as open passage")
				_check(_gate_shape() == null,
					"BREACHED removes the passage collision shape")
				var mat := _gate_body_mesh().material_override as StandardMaterial3D
				_check(mat.albedo_color.is_equal_approx(_gate.COLOR_BREACHED),
					"BREACHED visual state shows the legacy color")
				_gate.set_open(false)
				_gate.toggle()
				_gate.take_damage(50)
				_check(_gate.is_breached(),
					"BREACHED gate ignores close attempts (no auto-recovery)")
				_check(_signal_count == _sig0 + 1,
					"post-breach close attempts emit no extra signals")
				_sp = 2
				_pf = 0
		2:
			if _wait_frames(PHYSICS_WAIT_FRAMES):
				_check(_gate.is_breached() and not _gate.is_closed(),
					"BREACHED state persists across frames (no auto-recovery)")
				_check(_gate_shape() == null, "BREACHED passage stays physically open")
				_check(not _probe_blocked(), "BREACHED passage lets a physics probe through")
				_check(_path_crosses_gate(), "BREACHED passage stays nav-passable")
				_enter(Phase.NO_2D_DEP)


## -- NO_2D_DEP: wall/gate scene에 2D 노드 의존 없음 --
func _no_2d_dep() -> void:
	var allowed := {
		"Node3D": true, "Area3D": true, "StaticBody3D": true,
		"CollisionShape3D": true, "MeshInstance3D": true, "Label3D": true,
	}
	var clean := true
	for scene_path in ["res://scenes/wall_3d.tscn", "res://scenes/gate_3d.tscn"]:
		var instance: Node = (load(scene_path) as PackedScene).instantiate()
		var stack: Array[Node] = [instance]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if not allowed.has(node.get_class()):
				clean = false
				print("  offending node in %s: %s (%s)" % [scene_path, node.name, node.get_class()])
			stack.append_array(node.get_children())
		instance.free()
	_check(clean, "wall/gate scenes contain only 3D runtime nodes (no 2D dependency)")
	_finish()
