extends SceneTree

## TASK-3D-VIS-001-5 Visual Village Composition Prototype 회귀 테스트.
## 기존 tests를 고치지 않는 신규 task3d* 계열 파일(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. STRUCTURE: village_composition_3d scene이 4개 zone + path + 캐릭터로
##      조립되고, 모든 배치물이 catalog 키 기반 실렌더 mesh를 가진다.
##   2. ZONE_DENSITY: Village/Work/Forest/Quarry zone이 서로 겹치지 않고 밀도가
##      구분된다(forest 수목 >> village 수목, quarry 암반, lumberyard 작업대).
##   3. VARIATION: 반복 모델 variation이 제한 팔레트 안에 있다(tree/house).
##   4. PATH_CLEARANCE: Main path corridor 위에 solid 장식이 없다(gameplay
##      path/selection 가독성 원칙의 코드화) + path strip은 지면 장식이다.
##   5. CHARACTERS: 주민/Worker/Mercenary 리그가 공용 action을 실제 재생한다.
##   6. CAMERA_PAN_ZOOM: Foundation Camera3D pan(clamp 포함)/zoom 수렴 smoke.
##   7. DAY_NIGHT: 마을이 살아 있는 상태에서 NIGHT/DAY 라이팅 전환 smoke.
##   8. CLEANUP: scene free 후 stale reference 없음.

enum Phase {
	SETUP, STRUCTURE, ZONES, VARIATION, PATHS, CHARACTERS,
	CAMERA_PAN, CAMERA_ZOOM, DAYNIGHT, CLEANUP, DONE,
}

const GODOT_EPS := 0.0001

## 태스크 구성 요구사항 최소치.
const MIN_HOUSE_COUNT := 4
const MIN_QUARRY_ROCK_COUNT := 5
const FOREST_TO_VILLAGE_TREE_RATIO := 3.0
const MAX_TREE_VARIANTS := 5
const MAX_HOUSE_PALETTES := 2
const TREE_SCALE_BAND := Vector2(0.45, 0.6)

var _frame := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _cam_ctl: Node = null
var _env: Node = null
var _village: Node3D = null
var _camera_size_before := 0.0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	print("TASK3DVIS0015_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= GODOT_EPS


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.STRUCTURE:
			_structure()
		Phase.ZONES:
			_zones()
		Phase.VARIATION:
			_variation()
		Phase.PATHS:
			_paths()
		Phase.CHARACTERS:
			_characters()
		Phase.CAMERA_PAN:
			_camera_pan()
		Phase.CAMERA_ZOOM:
			_camera_zoom()
		Phase.DAYNIGHT:
			_daynight()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3DVIS0015_RESULT=TIMEOUT phase=%s" % str(_phase))
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
	var env_scene: Node = (load("res://scenes/environment_3d.tscn") as PackedScene).instantiate()
	env_scene.name = "EnvRoot"
	root.add_child(env_scene)
	var village_scene: Node = (load("res://scenes/village_composition_3d.tscn") as PackedScene).instantiate()
	village_scene.name = "Village"
	root.add_child(village_scene)


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_cam_ctl = root.get_node_or_null("CamController")
	_env = root.get_node_or_null("EnvRoot")
	_village = root.get_node_or_null("Village") as Node3D
	_check(_world != null, "3D world root loads")
	_check(_cam_ctl != null, "camera controller loads")
	_check(_env != null, "environment/lighting layer loads")
	_check(_village != null, "village composition scene loads")
	if _world == null or _cam_ctl == null or _env == null or _village == null:
		_finish()
		return
	_check(_village.is_in_group("village_composition_3d"),
		"village composition joins its dedicated group")
	_check(_village.apply_ground_tone(_world),
		"ground tone override applies to the placeholder GroundVisual")
	var ground_visual: MeshInstance3D = _world.get_node_or_null("GroundVisual") as MeshInstance3D
	_check(ground_visual != null and ground_visual.material_override != null
		and ground_visual.material_override.albedo_color.is_equal_approx(
			_village.GROUND_TONE_ALBEDO),
		"GroundVisual carries the stylized grass albedo at runtime")
	_enter(Phase.STRUCTURE)


## -- STRUCTURE --
func _catalog_nodes(zone: String) -> Array:
	var out: Array = []
	var zone_root: Node3D = _village.get_zone_root(zone)
	if zone_root == null:
		return out
	var stack: Array = [zone_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta("catalog_key"):
			out.append(node)
		stack.append_array(node.get_children())
	return out


func _has_mesh_descendant(node: Node) -> bool:
	var stack: Array = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			return true
		stack.append_array(current.get_children())
	return false


func _structure() -> void:
	for zone in ["village", "forest", "lumberyard", "quarry"]:
		_check(_village.get_zone_root(zone) != null,
			"zone root '%s' exists" % zone)
	var house_count := 0
	var missing_mesh := 0
	for node in _catalog_nodes("village"):
		if node.get_meta("kind", "") == "house":
			house_count += 1
		if not _has_mesh_descendant(node):
			missing_mesh += 1
	_check(house_count >= MIN_HOUSE_COUNT,
		"village keeps multiple houses (%d >= %d)" % [house_count, MIN_HOUSE_COUNT])
	_check(missing_mesh == 0,
		"every village placement renders a real mesh (broken imports: %d)" % missing_mesh)
	var forest_missing := 0
	for node in _catalog_nodes("forest"):
		if not _has_mesh_descendant(node):
			forest_missing += 1
	_check(forest_missing == 0,
		"forest placements render real meshes (broken imports: %d)" % forest_missing)
	var paths_root := _village.get_node_or_null("Paths")
	_check(paths_root != null and paths_root.get_child_count() >= 6,
		"main path network builds enough strips (%d)"
			% (paths_root.get_child_count() if paths_root else 0))
	_check(_village.get_node_or_null("Villagers") != null,
		"character lineup container exists")
	_enter(Phase.ZONES)


func _rects_disjoint(a: Rect2, b: Rect2) -> bool:
	return not a.intersects(b)


## -- ZONE_DENSITY --
func _zones() -> void:
	var rects: Dictionary = _village.zone_rects()
	var names := rects.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			_check(_rects_disjoint(rects[names[i]], rects[names[j]]),
				"zones '%s' and '%s' do not overlap (density separation)" %
					[names[i], names[j]])
	var forest_trees := 0
	for node in _catalog_nodes("forest"):
		if node.get_meta("kind", "") == "tree":
			forest_trees += 1
	var village_trees := 0
	for node in _catalog_nodes("village"):
		if node.get_meta("kind", "") == "tree":
			village_trees += 1
	_check(village_trees > 0, "village keeps accent trees (%d)" % village_trees)
	_check(forest_trees >= int(village_trees * FOREST_TO_VILLAGE_TREE_RATIO),
		"forest density clearly exceeds village greenery (%d vs %d)" %
			[forest_trees, village_trees])
	var quarry_rocks := 0
	for node in _catalog_nodes("quarry"):
		if node.get_meta("kind", "") in ["rock", "stone_pile"]:
			quarry_rocks += 1
	_check(quarry_rocks >= MIN_QUARRY_ROCK_COUNT,
		"quarry reads as a rock cluster (%d >= %d)" %
			[quarry_rocks, MIN_QUARRY_ROCK_COUNT])
	var yard_logs := 0
	var yard_station := false
	for node in _catalog_nodes("lumberyard"):
		if node.get_meta("kind", "") == "log_pile":
			yard_logs += 1
		if node.get_meta("kind", "") == "workstation":
			yard_station = true
	_check(yard_logs >= 3 and yard_station,
		"lumberyard identity reads via stump station + log piles (%d logs)" % yard_logs)

	# 월드 경계 내 배치(Foundation bounds ±192 unit 준수).
	var out_of_bounds := 0
	for zone in ["village", "forest", "lumberyard", "quarry"]:
		for node in _catalog_nodes(zone):
			if absf(node.position.x) > 192.0 or absf(node.position.z) > 192.0:
				out_of_bounds += 1
	_check(out_of_bounds == 0,
		"all placements stay inside world bounds (%d stray)" % out_of_bounds)
	_enter(Phase.VARIATION)


## -- VARIATION --
func _variation() -> void:
	var tree_keys := {}
	var bad_scale := 0
	for zone in ["village", "forest"]:
		for node in _catalog_nodes(zone):
			if node.get_meta("kind", "") != "tree":
				continue
			tree_keys[node.get_meta("catalog_key")] = true
			var s: float = node.scale.x
			if s < TREE_SCALE_BAND.x - GODOT_EPS or s > TREE_SCALE_BAND.y + GODOT_EPS:
				bad_scale += 1
	_check(tree_keys.size() <= MAX_TREE_VARIANTS,
		"tree variation stays limited (%d variants)" % tree_keys.size())
	_check(bad_scale == 0,
		"trees use the recorded top-down scale band (violations: %d)" % bad_scale)
	var floor_keys := {}
	for node in _catalog_nodes("village"):
		if node.get_meta("kind", "") != "house":
			continue
		for part in node.get_children():
			if part.has_meta("catalog_key") \
					and str(part.get_meta("catalog_key")).begins_with("bld/floor"):
				floor_keys[part.get_meta("catalog_key")] = true
	_check(floor_keys.size() <= MAX_HOUSE_PALETTES,
		"houses repeat a limited palette (%d floors)" % floor_keys.size())
	_enter(Phase.PATHS)


## -- PATH_CLEARANCE --
func _paths() -> void:
	var corridors: Dictionary = _village.path_corridors()
	_check(corridors.size() >= 6,
		"path network defines the main corridors (%d)" % corridors.size())
	var paths_root: Node3D = _village.get_node_or_null("Paths")
	var flat_ok := true
	var shadow_ok := true
	for strip in paths_root.get_children():
		if not _near(strip.position.y, _village.PATH_STRIP_Y):
			flat_ok = false
		if strip.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_ok = false
	_check(flat_ok, "path strips stay flush with the ground (walkable read)")
	_check(shadow_ok, "path strips never cast shadows onto units")

	# solid 배치는 corridor + margin과 겹치면 안 된다(장식의 길 방해 금지).
	var blocked := []
	for solid in _village.solid_footprints():
		for corridor_name in corridors:
			if (corridors[corridor_name] as Rect2).intersects(
					(solid["rect"] as Rect2).grow(_village.PATH_MARGIN)):
				blocked.append("%s/%s" % [solid["key"], corridor_name])
	_check(blocked.is_empty(),
		"no solid decoration blocks a gameplay corridor (%s)" % str(blocked))
	_enter(Phase.CHARACTERS)


## -- CHARACTERS --
func _rigs() -> Array:
	var out: Array = []
	var chars_root: Node = _village.get_node_or_null("Villagers")
	if chars_root == null:
		return out
	for child in chars_root.get_children():
		if child.has_meta("role"):
			out.append(child)
	return out


func _characters() -> void:
	var rigs := _rigs()
	# 전원이 초기 action에 진입할 때까지 기다렸다가 1회만 판정한다.
	for rig in rigs:
		if rigs.is_empty() or rig.current_action() != String(rig.get_meta("action")):
			return
	_check(rigs.size() >= 5, "lineup covers villagers/workers/mercenary (%d)" % rigs.size())
	var roles := {}
	var working_tools := 0
	for rig in rigs:
		roles[rig.get_meta("role")] = true
		if rig.get_tool_attachment() != null \
				and rig.get_tool_attachment().get_child_count() > 0:
			working_tools += 1
	for expected in ["worker_lumberjack", "worker_miner", "mercenary_guard",
			"villager_male", "carrier_worker"]:
		_check(roles.has(expected), "role '%s' is present" % expected)
	_check(working_tools == 3,
		"axe/pickaxe/sword attach to the shared hand bone (%d)" % working_tools)
	_check(rigs[0].get_skeleton() != null,
		"character rigs carry the shared humanoid skeleton")
	_enter(Phase.CAMERA_PAN)


## -- CAMERA_PAN_ZOOM --
func _camera_pan() -> void:
	var camera: Camera3D = _cam_ctl.get_camera()
	_check(camera.current, "foundation camera stays current over the village")
	var bounds: AABB = _cam_ctl.get_world_bounds_aabb()
	_cam_ctl.pan_camera(Vector3(5000.0, 0.0, -5000.0))
	var panned: Vector3 = _cam_ctl.position
	_check(panned.x <= bounds.end.x and panned.z >= bounds.position.z
		and _near(panned.y, WorldCoords3D.GROUND_Y),
		"pan clamps at the world boundary and stays grounded (%s)" % str(panned))
	_cam_ctl.pan_camera(Vector3(5000.0, 0.0, 5000.0))
	var clamped: Vector3 = _cam_ctl.position
	_check(clamped.x <= bounds.end.x and clamped.z <= bounds.end.z,
		"opposite pan clamp holds as well (%s)" % str(clamped))
	_cam_ctl.position = Vector3.ZERO
	_camera_size_before = camera.size
	_cam_ctl.day_zoom = 2.0
	_cam_ctl._zoom_target = 2.0
	_enter(Phase.CAMERA_ZOOM)


func _camera_zoom() -> void:
	if _frame % 10 != 0:
		return
	var camera: Camera3D = _cam_ctl.get_camera()
	var target: float = _cam_ctl._ortho_size_for_zoom(2.0)
	if absf(camera.size - target) > 0.05:
		return  # zoom lerp 수렴을 기다린다.
	_check(camera.size < _camera_size_before,
		"zoom-in converges toward the target ortho size (%.2f -> %.2f, target %.2f)"
			% [_camera_size_before, camera.size, target])
	_check(absf(camera.size - target) <= 0.05,
		"ortho size settles on the zoom policy value")
	_cam_ctl.day_zoom = 1.0
	_cam_ctl._zoom_target = 1.0
	_enter(Phase.DAYNIGHT)


## -- DAY_NIGHT --
func _daynight() -> void:
	var sun: DirectionalLight3D = _env.get_sun_light()
	var day_energy: float = _env.PRESETS[_env.Phase.DAY]["sun_energy"]
	_env.apply_phase(_env.Phase.NIGHT)
	_check(sun.light_energy < day_energy * 0.5,
		"NIGHT lighting takes over the populated village")
	_env.apply_phase(_env.Phase.DAY)
	_check(_near(sun.light_energy, day_energy),
		"DAY lighting restores cleanly after the night check")
	_enter(Phase.CLEANUP)


## -- CLEANUP --
func _cleanup() -> void:
	var village_ref: Node3D = _village
	_village.free()
	_village = null
	_check(not is_instance_valid(village_ref),
		"freed village composition leaves no live instance")
	_check(root.get_node_or_null("World3DRoot") != null,
		"foundation world survives the village cleanup")
	_check(_cam_ctl.get_camera() != null
		and _cam_ctl.get_camera().is_inside_tree(),
		"camera survives the village cleanup")
	_finish()
