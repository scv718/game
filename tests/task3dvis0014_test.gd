extends SceneTree

## TASK-3D-VIS-001-4 Character / Outfit / Animation Prototype 회귀 테스트.
## 기존 tests를 고치지 않는 신규 task3d* 계열 파일(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. STRUCTURE: prototype scene의 4개 리그(base 1 + worker variant 2 +
##      mercenary 1)가 전부 공용 skeleton/skinned mesh/공용 애니메이션 세트를
##      가진다(broken rig/skin 없음).
##   2. TOOL_ATTACH: tool은 hand_r BoneAttachment3D 하나로 붙고 배율은 catalog
##      hand attach hint를 따른다.
##   3. CATALOG_CONTRACT: ANIMATION_SETS의 모든 후보가 실제 UAL GLB 안에
##      존재한다(catalog 계약과 에셋 현실의 일치).
##   4. SHARED_COMPAT: 4개 리그의 본 이름 집합이 동일하고 같은 공용 action
##      매핑을 노출한다(Worker/Mercenary 공용 animation 재사용 근거).
##   5. PLAYBACK: idle/walk/work/combat/hit/death가 base 리그에서 실제로 골격을
##      움직이며 재생된다.
##   6. REUSE: 동시에 4개 리그가 같은 공용 walk를 독립적으로 재생한다.
##   7. FACING: yaw 회전만으로 방향 전환이고 visual 인스턴스 재생성이 없다
##      (sprite 개념 부재).
##   8. CLEANUP: 재생 중인 리그의 free가 안전하다(freed reference 금지).

enum Phase {
	SETUP, STRUCTURE, TOOL_ATTACH, CONTRACT, SHARED_COMPAT,
	PLAYBACK, REUSE, FACING, CLEANUP, DONE,
}

const GODOT_EPS := 0.0001

## 포즈 변화 판정 임계(지문 누적치). 미세 떨림 무시, 실질 움직임만 인정.
const POSE_DELTA_MIN := 0.05

var _frame := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _env: Node = null
var _proto: Node3D = null
var _rigs := {}

## PLAYBACK 상태.
var _pb_actions: Array = []
var _pb_index := -1
var _pb_stage := 0
var _pb_pre := 0.0

## FACING 상태.
var _facing_body: Node = null
var _facing_mesh: MeshInstance3D = null
var _facing_pos := 0.0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	if _proto != null and is_instance_valid(_proto):
		_proto.free()
	print("TASK3DVIS0014_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= GODOT_EPS


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
	var proto_scene: Node = (load("res://scenes/character_prototype_3d.tscn") as PackedScene).instantiate()
	proto_scene.name = "CharProto"
	root.add_child(proto_scene)


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_env = root.get_node_or_null("EnvRoot")
	_proto = root.get_node_or_null("CharProto") as Node3D
	_check(_world != null, "3D world root loads")
	_check(_env != null, "environment layer loads")
	_check(_proto != null, "character prototype scene loads")
	if _proto == null:
		_finish()
		return
	for rig in _proto.get_children():
		_rigs[rig.name] = rig
	_check(_rigs.size() == 4,
		"prototype holds exactly 4 character rigs (%d)" % _rigs.size())
	_check(_rigs.has("BaseMale") and _rigs.has("WorkerPeasantMale")
		and _rigs.has("WorkerPeasantFemale") and _rigs.has("MercenaryRanger"),
		"base + 2 worker variants + mercenary are all present")
	_enter(Phase.STRUCTURE)


## -- STRUCTURE --
func _structure() -> void:
	var catalog: GDScript = load("res://scripts/visual_asset_catalog_3d.gd")
	var band: Vector2 = catalog.SCALE_CONVENTION["humanoid_height_units"]
	for key in _rigs:
		var rig: Node = _rigs[key]
		var skel: Skeleton3D = rig.get_skeleton()
		_check(skel != null and skel.get_bone_count() == 65,
			"rig '%s' carries the shared 65-bone rig" % str(key))
		var meshes := _collect_body_meshes(skel)
		_check(meshes.size() > 0, "rig '%s' has visible skinned meshes" % str(key))
		var skinned := not meshes.is_empty()
		for mesh in meshes:
			if mesh.skeleton == NodePath("") or mesh.get_skin() == null:
				skinned = false
		_check(skinned, "rig '%s' has no broken rig/skin binding" % str(key))
		var player: AnimationPlayer = rig.get_animation_player()
		_check(player != null and player.get_animation_list().size() >= 6,
			"rig '%s' installs the shared action set (%d clips)"
				% [str(key), player.get_animation_list().size() if player != null else 0])
		var height := _height_of(meshes)
		_check(height >= band.x and height <= band.y,
			"rig '%s' stands in the recorded humanoid height band %.2f in [%.2f, %.2f]"
				% [str(key), height, band.x, band.y])
	_enter(Phase.TOOL_ATTACH)


## -- TOOL_ATTACH --
func _tool_attach() -> void:
	var catalog: GDScript = load("res://scripts/visual_asset_catalog_3d.gd")
	var expectations := {
		"WorkerPeasantMale": "tool/axe_bronze",
		"MercenaryRanger": "tool/sword_bronze",
	}
	for unarmed in ["BaseMale", "WorkerPeasantFemale"]:
		_check(_rigs[unarmed].get_tool_attachment() == null,
			"rig '%s' stays unarmed by default" % str(unarmed))
	for key in expectations:
		var rig: Node = _rigs[key]
		var attachment: BoneAttachment3D = rig.get_tool_attachment()
		_check(attachment != null and attachment is BoneAttachment3D,
			"rig '%s' exposes a BoneAttachment3D tool point" % str(key))
		if attachment == null:
			continue
		_check(attachment.get_parent() == rig.get_skeleton(),
			"tool attachment lives on the shared skeleton ('%s')" % str(key))
		_check(String(attachment.bone_name) == rig.HAND_BONE
			and rig.get_skeleton().find_bone(String(attachment.bone_name)) >= 0,
			"tool attachment targets a valid hand bone ('%s')" % str(key))
		_check(attachment.get_child_count() > 0
			and _collect_meshes(attachment).size() > 0,
			"attached tool model carries renderable meshes ('%s')" % str(key))
		var model := attachment.get_child(0) as Node3D
		var hint: float = catalog.attachment_scale_hint_for_key(expectations[key])
		_check(hint > 0.0 and _near(model.scale.x, hint) and _near(model.scale.y, hint)
			and _near(model.scale.z, hint),
			"tool uses the catalog hand-attach scale hint %.2f ('%s')" % [hint, str(key)])
	# 교체/해제 계약.
	var sword_rig: Node = _rigs["MercenaryRanger"]
	sword_rig.detach_tool()
	_check(sword_rig.get_tool_attachment() == null,
		"detach_tool clears the attachment reference immediately")
	sword_rig.attach_tool("tool/sword_bronze")
	_check(sword_rig.get_tool_attachment() != null,
		"re-attach after detach works")
	_enter(Phase.CONTRACT)


## -- CATALOG_CONTRACT --
func _contract() -> void:
	var catalog: GDScript = load("res://scripts/visual_asset_catalog_3d.gd")
	var instances := {}
	for action in catalog.animation_actions():
		var candidates: Array = catalog.animations_for_action(action)
		_check(not candidates.is_empty(),
			"action '%s' has at least one shared animation candidate" % action)
		for candidate in candidates:
			var lib_key: String = candidate["library"]
			_check(catalog.has_key(lib_key)
				and catalog.ENTRIES[lib_key]["category"] == catalog.CATEGORY_ANIMATION,
				"candidate %s/%s references an animation catalog entry"
					% [lib_key, candidate["name"]])
			if not instances.has(lib_key):
				var path: String = catalog.get_model_path(lib_key)
				instances[lib_key] = (load(path) as PackedScene).instantiate()
	for lib_key in instances:
		var inst: Node = instances[lib_key]
		var player := _find_player(inst)
		_check(player != null,
			"animation library '%s' exposes an AnimationPlayer" % lib_key)
		if player == null:
			continue
		for action in catalog.animation_actions():
			for candidate in catalog.animations_for_action(action):
				if candidate["library"] == lib_key:
					_check(player.has_animation(candidate["name"]),
						"UAL library '%s' really contains '%s'"
							% [lib_key, candidate["name"]])
	for value in instances.values():
		value.free()
	_enter(Phase.SHARED_COMPAT)


## -- SHARED_COMPAT --
func _shared_compat() -> void:
	var reference_bones := {}
	var reference_actions := {}
	var first := true
	for key in _rigs:
		var rig: Node = _rigs[key]
		var skel: Skeleton3D = rig.get_skeleton()
		var bones := {}
		for i in skel.get_bone_count():
			bones[skel.get_bone_name(i)] = true
		if first:
			reference_bones = bones
			first = false
		else:
			var identical := bones.size() == reference_bones.size()
			if identical:
				for b in reference_bones:
					if not bones.has(b):
						identical = false
			_check(identical,
				"rig '%s' bone set matches the base rig exactly (%d bones)"
					% [str(key), reference_bones.size()])
		var actions := {}
		for action in VisualAssetCatalog3D.animation_actions():
			actions[action] = rig.installed_animation_name(action)
		if reference_actions.is_empty():
			reference_actions = actions
		else:
			_check(actions == reference_actions,
				"rig '%s' exposes the exact same shared action mapping" % str(key))
	_enter(Phase.PLAYBACK)
	_pb_actions = ["idle", "walk", "work", "combat", "hit", "death"]
	_pb_index = -1
	_pb_stage = 0


## -- PLAYBACK --
func _playback_tick() -> bool:
	var rig: Node = _rigs["BaseMale"]
	if _pb_stage == 0:
		_pb_index += 1
		if _pb_index >= _pb_actions.size():
			return true
		var action: String = _pb_actions[_pb_index]
		rig.rotation = Vector3.ZERO
		_pb_pre = _pose_fingerprint(rig.get_skeleton())
		_check(rig.play_action(action),
			"play_action('%s') accepted on the base rig" % action)
		_check(rig.current_action() == action,
			"current_action reports '%s'" % action)
		_check(rig.get_animation_player().current_animation
			== rig.installed_animation_name(action),
			"AnimationPlayer switched to the installed '%s' clip" % action)
		_pb_stage = 1
	else:
		var action: String = _pb_actions[_pb_index]
		rig.get_animation_player().advance(0.35)
		var moved := absf(_pose_fingerprint(rig.get_skeleton()) - _pb_pre)
		_check(moved >= POSE_DELTA_MIN,
			"animation '%s' actually drives the skeleton (delta %.3f)"
				% [action, moved])
		_pb_stage = 0
	return false


## -- REUSE --
func _reuse() -> void:
	var pres := {}
	for key in _rigs:
		var rig: Node = _rigs[key]
		pres[key] = _pose_fingerprint(rig.get_skeleton())
		_check(rig.play_action("walk"),
			"worker/mercenary rig '%s' accepts the shared walk action" % str(key))
	for key in _rigs:
		var rig: Node = _rigs[key]
		rig.get_animation_player().advance(0.4)
		_check(rig.current_action() == "walk"
			and rig.get_animation_player().current_animation_position > 0.0,
			"rig '%s' is genuinely walking on the shared clip" % str(key))
		var moved := absf(_pose_fingerprint(rig.get_skeleton()) - float(pres[key]))
		_check(moved >= POSE_DELTA_MIN,
			"rig '%s' walks independently of the others (delta %.3f)"
				% [str(key), moved])
	_enter(Phase.FACING)


## -- FACING --
func _facing_prepare() -> void:
	var rig: Node = _rigs["WorkerPeasantFemale"]
	_facing_body = rig._body
	_facing_mesh = _collect_body_meshes(rig.get_skeleton())[0]
	rig.get_animation_player().advance(0.1)
	_facing_pos = rig.get_animation_player().current_animation_position
	rig.rotation.y = deg_to_rad(90.0)


func _facing_verify() -> void:
	var rig: Node = _rigs["WorkerPeasantFemale"]
	rig.get_animation_player().advance(0.1)
	_check(is_instance_valid(_facing_body) and rig._body == _facing_body,
		"yaw rotation did not recreate the visual body instance")
	_check(is_instance_valid(_facing_mesh)
		and _collect_meshes(rig.get_skeleton()).has(_facing_mesh),
		"the same skinned mesh serves every direction (no sprite regeneration)")
	_check(_collect_canvas_items(rig).is_empty(),
		"no sprite/CanvasItem exists anywhere in the 3D rig")
	_check(rig.get_animation_player().current_animation_position > _facing_pos,
		"walk playback continues through the direction change (no restart)")
	_check(_near(absf(rig.rotation.y), deg_to_rad(90.0)),
		"facing yaw is stored as a plain rotation")
	_enter(Phase.CLEANUP)


## -- CLEANUP --
func _cleanup() -> void:
	var script: GDScript = load("res://scripts/character_rig_3d.gd")
	var extra: Node = script.new()
	extra.body_key = "human/female_base"
	extra.initial_action = "walk"
	root.add_child(extra)
	_check(extra.get_skeleton() != null,
		"dynamically built rig builds its skeleton")
	_check(extra.has_action("walk"),
		"dynamically built rig installs the shared actions")
	_check(extra.play_action("walk"),
		"dynamically built rig accepts the shared walk")
	extra.get_animation_player().advance(0.3)
	extra.free()
	_check(not is_instance_valid(extra),
		"freeing a mid-play rig leaves no dangling actor")
	_finish()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.STRUCTURE:
			_structure()
		Phase.TOOL_ATTACH:
			_tool_attach()
		Phase.CONTRACT:
			_contract()
		Phase.SHARED_COMPAT:
			_shared_compat()
		Phase.PLAYBACK:
			if _playback_tick():
				_reuse()
		Phase.REUSE:
			pass
		Phase.FACING:
			if _facing_body == null:
				_facing_prepare()
			else:
				_facing_verify()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			return true
	if _frame > 3000:
		print("TASK3DVIS0014_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


## -- helpers --

## 샘플 본들의 global pose 지문(원점 내적 + 회전각 가중합). 변화량 비교 전용.
func _pose_fingerprint(skel: Skeleton3D) -> float:
	var total := 0.0
	var weight := 1.0
	for bone_name in ["pelvis", "spine_03", "Head", "upperarm_l", "upperarm_r",
			"hand_l", "hand_r", "thigh_l", "thigh_r", "foot_l"]:
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			continue
		var pose := skel.get_bone_global_pose(idx)
		total += pose.origin.dot(Vector3.ONE) * weight
		total += pose.basis.get_rotation_quaternion().get_angle() * weight * 2.0
		weight += 0.1
	return total


func _height_of(meshes: Array) -> float:
	var lo := INF
	var hi := -INF
	for mesh in meshes:
		var mesh_inst := mesh as MeshInstance3D
		var aabb: AABB = mesh_inst.global_transform * mesh_inst.get_aabb()
		lo = minf(lo, aabb.position.y)
		hi = maxf(hi, aabb.end.y)
	if lo > hi:
		return 0.0
	return hi - lo


func _collect_meshes(from: Node) -> Array:
	var out: Array = []
	var stack: Array = [from]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			out.append(node)
		stack.append_array(node.get_children())
	return out


## skeleton 직계 자식 중 tool BoneAttachment3D 하위를 제외한 body mesh들.
## tool prop은 의도적으로 unskinned rigid mesh다(broken rig/skin과 무관).
func _collect_body_meshes(skel: Skeleton3D) -> Array:
	var out: Array = []
	for child in skel.get_children():
		if child is BoneAttachment3D:
			continue
		out.append_array(_collect_meshes(child))
	return out


func _collect_canvas_items(from: Node) -> Array:
	var out: Array = []
	var stack: Array = [from]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CanvasItem:
			out.append(node)
		stack.append_array(node.get_children())
	return out


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null
