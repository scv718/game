extends SceneTree

## TASK-3D-VIS-001-2 Visual Catalog / Scale Convention 회귀 테스트.
## 기존 tests를 고치지 않는 신규 task3d* 계열 파일(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. ROLE COVERAGE: 태스크 최소 카테고리 전부가 role로 등록되어 있고,
##      각 role이 1~5개 variation을 가진다(변형 없는 팩은 예외 기록).
##   2. KEY INTEGRITY: 모든 candidate 키/parts가 ENTRIES에 존재하고 실제
##      import된 GLTF/GLB 파일로 해석된다.
##   3. API 안전 실패: 미등록 role/variation/action은 빈 값으로 실패한다.
##   4. SCALE CONVENTION: 기록값이 WorldCoords3D 상수와 실측 AABB와 일치하고,
##      tree scale_hint 적용 결과가 마을 스케일 밴드에 들어온다.
##   5. ANIMATION MAP: idle/walk/work/combat/hit/death 후보가 지정한 라이브러리
##      GLB 안에서 실제 재생 가능한 이름이다.
##   6. CURATED SUBSET: 선택 레이어가 ENTRIES 전체를 소비하지 않는다(예비분 존재).

enum Phase { SETUP, ROLES, API_SAFE, SCALE, ANIM, DONE }

const MODELS_ROOT := "res://assets/third_party/quaternius/models/"

## 태스크 최소 카테고리 -> 등록 role 매핑(animation은 ANIMATION_SETS로 별도 검증).
const REQUIRED_ROLES := {
	"House / Village Building": ["house_building"],
	"Wall / Gate": ["wall_segment", "gate"],
	"Lumberyard visual candidates": ["workplace_lumberyard"],
	"Quarry visual candidates": ["workplace_quarry"],
	"Tavern / Inn / Keep visual candidates": ["tavern_inn_keep"],
	"Tree variants": ["tree"],
	"Rock variants": ["rock"],
	"Grass / Bush / Flower": ["vegetation"],
	"Crate / Barrel / Cart": ["container_cart"],
	"Log / Wood pile": ["log_pile"],
	"Stone pile": ["stone_pile"],
	"Axe / Pickaxe": ["tool_gather"],
	"Market / Work props": ["market_props"],
	"Base Human": ["human_base"],
	"Worker outfit": ["outfit_worker"],
	"Mercenary outfit": ["outfit_mercenary"],
	"Weapons": ["weapon"],
}

## 팩 자체에 변형이 존재하지 않아 variation 1개인 role(카탈로그에 기록된 예외).
const SINGLE_VARIATION_ROLES := ["log_pile", "weapon"]

## REQUIRED_ANIM_ACTIONS: 태스크가 요구하는 gameplay action 세트.
const REQUIRED_ANIM_ACTIONS := ["idle", "walk", "work", "combat", "hit", "death"]

## tree variation의 scale_hint 적용 후 목표 높이 밴드(world unit).
## 벽 모듈 3.12 / 집 전체 약 5.5 사이에서 top-down 실루엣이 읽히는 구간이다.
const TREE_HINTED_HEIGHT_RANGE := Vector2(3.0, 6.0)

const BATCH_PER_FRAME := 6

var _frame := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _catalog: Object = null
var _keys: Array = []
var _measure_queue: Array = []
var _queue_built := false

var _lib_players := {}


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	for library_key in _lib_players:
		var entry: Dictionary = _lib_players[library_key]
		if entry["node"] != null:
			entry["node"].free()
	print("TASK3DVIS0012_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _collect(node: Node, type_check: Callable, out: Array) -> void:
	if type_check.call(node):
		out.append(node)
	for child in node.get_children():
		_collect(child, type_check, out)


func _merged_aabb(root: Node3D) -> AABB:
	var meshes: Array = []
	_collect(root, func(n: Node) -> bool: return n is MeshInstance3D, meshes)
	var result := AABB()
	var first := true
	for mi in meshes:
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var world_box: AABB = (mi as MeshInstance3D).transform * mesh.get_aabb()
		result = world_box if first else result.merge(world_box)
		first = false
	return result


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.ROLES:
			_roles()
		Phase.API_SAFE:
			_api_safe()
		Phase.SCALE:
			_scale()
		Phase.ANIM:
			_anim()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3DVIS0012_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	_catalog = load("res://scripts/visual_asset_catalog_3d.gd")
	_keys = _catalog.all_keys()
	_enter(Phase.ROLES)


## -- ROLES: 최소 카테고리 커버 + variation 상한/키 무결성 --
func _roles() -> void:
	for required_label in REQUIRED_ROLES:
		var present := true
		for role in REQUIRED_ROLES[required_label]:
			if not _catalog.has_role(role):
				present = false
				print("  missing role: %s" % role)
		_check(present, "minimum category '%s' is cataloged" % required_label)

	for role in _catalog.roles():
		var var_ids: Array = _catalog.variation_ids_for_role(role)
		var lower_bound := 2 if not SINGLE_VARIATION_ROLES.has(role) else 1
		_check(var_ids.size() >= lower_bound and var_ids.size() <= 5,
			"role '%s' has %d~%d variations (%d)" % [role, lower_bound, 5, var_ids.size()])
		_check(_catalog.role_label(role) != "", "role '%s' carries a human label" % role)
		var seen_ids := {}
		for var_id in var_ids:
			seen_ids[var_id] = true
			for key in _catalog.candidate_parts(role, var_id):
				if not _catalog.has_key(key):
					_check(false, "candidate key '%s' exists in ENTRIES (%s/%s)" % [key, role, var_id])
					continue
				var path: String = _catalog.get_model_path(key)
				_check(FileAccess.file_exists(path),
					"candidate '%s' resolves to an imported file (%s)" % [key, path])
		_check(seen_ids.size() == var_ids.size(),
			"role '%s' variation ids are unique" % role)

	# 완료조건: Visual Agent는 role 조회만으로 골라야 하므로, 어떤 role도
	# 빈 후보를 반환하면 안 된다.
	var all_nonempty := true
	for role2 in _catalog.roles():
		if _catalog.candidate_keys_for_role(role2).is_empty():
			all_nonempty = false
			print("  empty role: %s" % role2)
	_check(all_nonempty, "every registered role exposes at least one candidate key")
	_enter(Phase.API_SAFE)


## -- API_SAFE: 미등록 식별자 안전 실패 --
func _api_safe() -> void:
	_check(not _catalog.has_role("nonexistent_role"), "unknown role reports has_role=false")
	_check(_catalog.roles().size() == _catalog.SELECTIONS.size(), "roles() mirrors SELECTIONS")
	_check(_catalog.variation_ids_for_role("nonexistent_role").is_empty(),
		"unknown role yields no variations")
	_check(_catalog.candidate_parts("tree", "nonexistent").is_empty(),
		"unknown variation yields no parts")
	_check(_catalog.candidate_keys_for_role("nonexistent_role").is_empty(),
		"unknown role yields no candidate keys")
	_check(is_equal_approx(_catalog.candidate_scale_hint("nonexistent_role", "x"), 0.0),
		"unknown variation yields scale_hint 0 sentinel")
	_check(is_equal_approx(_catalog.candidate_scale_hint("tree", "common_a"), 0.55),
		"recorded tree scale_hint is readable")
	_check(is_equal_approx(_catalog.candidate_scale_hint("rock", "medium_a"), 1.0),
		"missing scale_hint defaults to native 1.0")
	_check(_catalog.animations_for_action("nonexistent_action").is_empty(),
		"unknown animation action yields no candidates")

	# candidate_keys는 중복 없이 role 내 전 부분을 포괄한다(stone_pile cluster 등).
	var stone_keys: Array = _catalog.candidate_keys_for_role("stone_pile")
	_check(stone_keys.size() == 3 and stone_keys.has("rock/medium_1"),
		"composition variations contribute their parts to candidate keys")

	# 선택 레이어는 curated 전체를 소비하지 않는다(예비분 유지).
	var used := {}
	for role in _catalog.roles():
		for key in _catalog.candidate_keys_for_role(role):
			used[key] = true
	_check(used.size() < _keys.size(),
		"selection layer leaves reserved keys unused (%d of %d)" % [used.size(), _keys.size()])
	_enter(Phase.SCALE)


## -- SCALE: convention 수치 vs WorldCoords3D 상수 vs 실측 AABB --
func _scale() -> void:
	if _measure_queue.is_empty() and not _queue_built:
		_build_measure_queue()
		_queue_built = true

	if not _measure_queue.is_empty():
		var budget := BATCH_PER_FRAME
		while budget > 0 and not _measure_queue.is_empty():
			_run_measure_job(_measure_queue.pop_front())
			budget -= 1
		return

	# 배치 소진 후 convention 상수 자체 정합성.
	var conv: Dictionary = _catalog.SCALE_CONVENTION
	_check(is_equal_approx(conv["px_to_unit"], WorldCoords3D.PX_TO_UNIT),
		"scale convention records the foundation px_to_unit")
	_check(is_equal_approx(conv["grid_cell_units"], WorldCoords3D.GRID_CELL_UNITS),
		"scale convention records the grid cell size")
	_check(is_equal_approx(float(conv["ground_y"]), WorldCoords3D.GROUND_Y),
		"scale convention records the ground origin lock")
	_check(bool(conv["uniform_scale_only"]),
		"scale convention pins uniform-only scaling")
	_check(bool(conv["gameplay_footprint_independent_of_visual_scale"]),
		"scale convention pins visual/footprint separation")
	_enter(Phase.ANIM)


func _build_measure_queue() -> void:
	# 벽 모듈 2m 그리드(건물 조합과 grid snap 정수 호환 근거).
	for wall_key in ["bld/wall_plaster_straight", "bld/wall_brick_straight"]:
		_measure_queue.append({"key": wall_key, "kind": "wall_module"})
	# humanoid 실물 스케일 밴드(native scale LOCK).
	for human_key in ["human/male_base", "human/female_base"]:
		_measure_queue.append({"key": human_key, "kind": "humanoid"})
	# tree: 원판 높이 밴드 + hint 적용 결과가 마을 스케일에 들어오는가.
	for tree_var_id in _catalog.variation_ids_for_role("tree"):
		_measure_queue.append({
			"key": _catalog.candidate_parts("tree", tree_var_id)[0],
			"var_id": tree_var_id, "kind": "tree"})
	# 지면 origin 규약(새 반입분 chopping_log 포함).
	for grounded_key in ["tool/chopping_log", "prop/barrel", "rock/medium_1"]:
		_measure_queue.append({"key": grounded_key, "kind": "grounded"})


func _run_measure_job(job: Dictionary) -> void:
	var conv: Dictionary = _catalog.SCALE_CONVENTION
	var node: Node3D = _catalog.instantiate_model(job["key"])
	if node == null:
		_check(false, "model loads for scale check: %s" % job["key"])
		return
	var box := _merged_aabb(node)
	node.free()
	match str(job["kind"]):
		"wall_module":
			var module: Vector3 = conv["wall_module_size_units"]
			_check(absf(box.size.x - module.x) <= 0.01,
				"%s matches the recorded 2m wall module width (%.2f)" % [job["key"], box.size.x])
		"humanoid":
			var band: Vector2 = conv["humanoid_height_units"]
			_check(box.size.y >= band.x and box.size.y <= band.y,
				"%s stays inside the recorded humanoid height band (%.2f)" % [job["key"], box.size.y])
		"tree":
			var hint: float = _catalog.candidate_scale_hint("tree", job["var_id"])
			var native_band: Vector2 = conv["tree_native_height_units"]
			var slot_band: Vector2 = conv["tree_slot_scale_hint"]
			_check(box.size.y >= native_band.x - 0.01 and box.size.y <= native_band.y + 0.01,
				"%s native height fits the recorded band (%.2f)" % [job["key"], box.size.y])
			_check(hint >= slot_band.x and hint <= slot_band.y,
				"%s scale_hint sits inside the recorded slot band (%.2f)" % [job["key"], hint])
			var hinted := box.size.y * hint
			_check(hinted >= TREE_HINTED_HEIGHT_RANGE.x and hinted <= TREE_HINTED_HEIGHT_RANGE.y,
				"%s hinted height reads at village scale (%.2f)" % [job["key"], hinted])
		"grounded":
			_check(box.position.y >= -0.35 and box.position.y <= 0.06,
				"%s is authored with a ground-level origin (min y %.2f)" % [job["key"], box.position.y])


## -- ANIM: action -> 라이브러리 실제 애니메이션 이름 --
func _anim() -> void:
	for required in REQUIRED_ANIM_ACTIONS:
		_check(_catalog.animation_actions().has(required),
			"animation map covers the '%s' action" % required)

	var missing_libs := false
	for action in _catalog.animation_actions():
		var candidates: Array = _catalog.animations_for_action(action)
		if candidates.is_empty():
			missing_libs = true
			print("  empty action: %s" % action)
			continue
		var first_ok: bool = _lib_has_animation(candidates[0]["library"], candidates[0]["name"])
		_check(first_ok, "'%s' primary animation plays: %s/%s"
			% [action, candidates[0]["library"], candidates[0]["name"]])
		for candidate in candidates:
			if not _lib_has_animation(candidate["library"], candidate["name"]):
				missing_libs = true
				print("  missing anim: %s/%s (%s)" % [candidate["library"], candidate["name"], action])
	_check(not missing_libs, "every mapped animation exists inside its library GLB")

	# 작업 계열은 벌목/농사/수리 실습 이름을 제공해야 한다(VIS-001-4 재생 대상).
	var work_names := []
	for c in _catalog.animations_for_action("work"):
		work_names.append(c["name"])
	_check(work_names.has("TreeChopping") and work_names.has("Farm_Harvest"),
		"work action maps lumberjack and farm motions")
	_enter(Phase.DONE)


func _lib_has_animation(library_key: String, anim_name: String) -> bool:
	if not _lib_players.has(library_key):
		var node: Node3D = _catalog.instantiate_model(library_key)
		if node == null:
			return false
		var players: Array = []
		_collect(node, func(n: Node) -> bool: return n is AnimationPlayer, players)
		_lib_players[library_key] = {
			"node": node,
			"player": players[0] if players.size() > 0 else null,
		}
	var entry: Dictionary = _lib_players[library_key]
	if entry["player"] == null:
		return false
	return (entry["player"] as AnimationPlayer).has_animation(anim_name)
