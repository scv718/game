extends SceneTree

## TASK-3D-VIS-001-1 Asset Acquire / License / Import 회귀 테스트.
## 신규 task3d* 계열 파일로만 추가(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. license/source 기록 존재(README + 팩 동봉 라이선스 원문 7종).
##   2. runtime catalog 계약: 필요한 에셋만 키로 노출, 미등록 키 안전 실패,
##      GLTF/GLB 우선 반입 규칙 준수.
##   3. catalog 전 모델 Godot import 성공(PackedScene 로드 + Node3D 생성).
##   4. broken material/texture 없음(모든 서피스에 재질 존재, 텍스처 또는
##      의도적 단색 유리/마네킹 재질로 해석 가능).
##   5. 공용 skeleton/애니메이션 호환 자산(UAL 43 anim, humanoid bone 보유).
##   6. scale/orientation 기준(모듈 벽 2m 그리드, 인간 신장 ~1.8, 지면 origin).
##   7. 원본 팩 전체는 runtime에 노출되지 않음(_source/ .gdignore 격리).

enum Phase { SETUP, DOCS, CATALOG, IMPORT, MATERIALS, RIG, SCALE, ISOLATION,
	DONE }

const MODELS_ROOT := "res://assets/third_party/quaternius/models/"
const DOC_ROOT := "res://assets/third_party/quaternius/"

## VIS-001-2가 반입 절차(tools/download_quaternius_packs.ps1)로 추가한
## tool/chopping_log(Anvil_Log) 1키를 반영한 카운트다.
const EXPECTED_KEY_COUNT := 84
const EXPECTED_LICENSE_PACKS := 7
## UAL1/UAL2 Standard 라이브러리의 공용 애니메이션 수(원본 팩 값).
const EXPECTED_UAL_ANIM_COUNT := 43
## 라이브러리별 시그니처 애니메이션(UAL1 로코모션/전투, UAL2 농사/상호작용).
const UAL_SIGNATURE_ANIMS := {
	"anim/ual1_standard": ["Idle", "Death01", "Hit_Chest", "Fixing_Kneeling"],
	"anim/ual2_standard": ["Farm_Harvest", "Farm_PlantSeed", "Chest_Open",
		"Hit_Knockback"],
}

var _frame := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _catalog: Object = null
var _keys: Array = []
var _key_index := 0
var _instances: Array = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	print("TASK3DVIS0011_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _collect(node: Node, type_check: Callable, out: Array) -> void:
	if type_check.call(node):
		out.append(node)
	for child in node.get_children():
		_collect(child, type_check, out)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.DOCS:
			_docs()
		Phase.CATALOG:
			_catalog_phase()
		Phase.IMPORT:
			_import_phase()
		Phase.MATERIALS:
			_materials()
		Phase.RIG:
			_rig()
		Phase.SCALE:
			_scale()
		Phase.ISOLATION:
			_isolation()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3DVIS0011_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	_catalog = load("res://scripts/visual_asset_catalog_3d.gd")
	_keys = _catalog.all_keys()
	_enter(Phase.DOCS)


## -- DOCS: license/source 기록 존재 --
func _docs() -> void:
	_check(FileAccess.file_exists(DOC_ROOT + "README.md"),
		"master source/license record exists")
	var lic_dir := DirAccess.open(DOC_ROOT + "license")
	var license_files: Array = []
	if lic_dir != null:
		for fname in lic_dir.get_files():
			if fname.ends_with(".txt"):
				license_files.append(fname)
	_check(license_files.size() == EXPECTED_LICENSE_PACKS,
		"all %d packs preserve their own license text (%d found)"
			% [EXPECTED_LICENSE_PACKS, license_files.size()])
	var cc0_count := 0
	for fname in license_files:
		var txt := FileAccess.get_file_as_string(DOC_ROOT + "license/" + fname)
		if txt.contains("CC0"):
			cc0_count += 1
	_check(cc0_count == EXPECTED_LICENSE_PACKS,
		"every preserved pack license declares CC0")

	var readme := FileAccess.get_file_as_string(DOC_ROOT + "README.md")
	for pack_name in ["Medieval Village MegaKit", "Stylized Nature MegaKit",
			"Fantasy Props MegaKit", "Universal Base Characters",
			"Modular Character Outfits", "Universal Animation Library"]:
		_check(readme.contains(pack_name),
			"availability table covers '%s'" % pack_name)
	_enter(Phase.CATALOG)


## -- CATALOG: 필요한 asset만 runtime catalog에 노출 --
func _catalog_phase() -> void:
	_check(_keys.size() == EXPECTED_KEY_COUNT,
		"catalog exposes exactly the curated subset (%d keys)" % EXPECTED_KEY_COUNT)

	var categories: Array = [
		_catalog.CATEGORY_TREES, _catalog.CATEGORY_ROCKS,
		_catalog.CATEGORY_VEGETATION, _catalog.CATEGORY_BUILDING,
		_catalog.CATEGORY_PROPS, _catalog.CATEGORY_TOOLS,
		_catalog.CATEGORY_HUMAN, _catalog.CATEGORY_OUTFIT,
		_catalog.CATEGORY_ANIMATION]
	for category in categories:
		_check(_catalog.keys_in_category(category).size() > 0,
			"category '%s' has at least one candidate" % category)

	# GLTF/GLB 우선: catalog가 가리키는 반입물은 전부 glTF 계열이다.
	var gltf_only := true
	for key in _keys:
		var path: String = _catalog.get_model_path(key)
		if not (path.ends_with(".gltf") or path.ends_with(".glb")) \
				or not FileAccess.file_exists(path):
			gltf_only = false
			print("  offending key: %s -> %s" % [key, path])
	_check(gltf_only, "every catalog entry resolves to an imported GLTF/GLB file")

	# 미등록 키는 안전하게 실패한다(빈 경로 / null / error log).
	_check(not _catalog.has_key("nonexistent/key"),
		"unknown keys report has_key=false")
	_check(_catalog.get_model_path("nonexistent/key").is_empty(),
		"unknown keys resolve to an empty path instead of a bogus res:// url")
	_check(_catalog.load_model("nonexistent/key") == null,
		"unknown keys fail load without crashing")
	_enter(Phase.IMPORT)


## -- IMPORT: catalog 전 모델 Godot import 성공(missing dependency 없음) --
func _import_phase() -> void:
	if _key_index == 0:
		_instances.clear()
	var batch_end := mini(_key_index + 16, _keys.size())
	while _key_index < batch_end:
		var key: String = _keys[_key_index]
		var scene: PackedScene = _catalog.load_model(key)
		var ok := scene != null
		var node: Node3D = null
		if ok:
			node = scene.instantiate()
			ok = node != null
		var meshes: Array = []
		if ok:
			_collect(node, func(n: Node) -> bool: return n is MeshInstance3D, meshes)
			ok = meshes.size() > 0
			_instances.append({"key": key, "node": node})
		_check(ok, "model imports and instantiates with mesh geometry: %s" % key)
		_key_index += 1
	if _key_index >= _keys.size():
		_enter(Phase.MATERIALS)


## -- MATERIALS: broken material/texture 없음 --
func _materials() -> void:
	var broken_mat := 0
	var broken_surface := 0
	var suspicious_white := 0
	for entry in _instances:
		var meshes: Array = []
		_collect(entry["node"], func(n: Node) -> bool: return n is MeshInstance3D, meshes)
		for mi in meshes:
			var mesh: Mesh = mi.mesh
			if mesh == null:
				broken_meshes_guard(entry["key"])
				continue
			for s in mesh.get_surface_count():
				var mat: Material = mesh.surface_get_material(s)
				if mat == null:
					broken_surface += 1
					print("  missing material: %s surf%d" % [entry["key"], s])
				elif mat is BaseMaterial3D:
					var bm: BaseMaterial3D = mat
					var textured: bool = bm.albedo_texture != null
					var colored: bool = bm.albedo_color != Color.WHITE
					if not textured and not colored:
						suspicious_white += 1
						print("  untextured default-white surface: %s surf%d" % [entry["key"], s])
				elif not mat is BaseMaterial3D:
					broken_mat += 1
	_check(broken_surface == 0, "no surface is missing its material")
	_check(broken_mat == 0, "all materials are engine materials (no foreign types)")
	_check(suspicious_white == 0,
		"untextured surfaces carry intentional colors (glass/mannequin), none are blank white")
	_free_instances()
	_enter(Phase.RIG)


func broken_meshes_guard(_key: String) -> void:
	pass


func _free_instances() -> void:
	for entry in _instances:
		entry["node"].free()
	_instances.clear()


## -- RIG: 공용 skeleton / 애니메이션 호환 --
func _rig() -> void:
	for anim_key in UAL_SIGNATURE_ANIMS:
		var node: Node3D = _catalog.instantiate_model(anim_key)
		var players: Array = []
		_collect(node, func(n: Node) -> bool: return n is AnimationPlayer, players)
		var anim_count := 0
		var missing: Array = []
		if players.size() > 0:
			var player: AnimationPlayer = players[0]
			anim_count = player.get_animation_list().size()
			for required: String in UAL_SIGNATURE_ANIMS[anim_key]:
				if not player.has_animation(required):
					missing.append(required)
		_check(players.size() == 1 and anim_count == EXPECTED_UAL_ANIM_COUNT,
			"%s ships the full shared library (%d animations)" % [anim_key, anim_count])
		_check(missing.is_empty(),
			"%s exposes its signature animations %s" % [anim_key, str(UAL_SIGNATURE_ANIMS[anim_key])])
		node.free()

	for skel_key in ["human/male_base", "human/female_base",
			"outfit/male_peasant_body", "anim/mannequin_female"]:
		var node2: Node3D = _catalog.instantiate_model(skel_key)
		var skeletons: Array = []
		_collect(node2, func(n: Node) -> bool: return n is Skeleton3D, skeletons)
		var bone_total := 0
		for skel in skeletons:
			bone_total += (skel as Skeleton3D).get_bone_count()
		_check(skeletons.size() > 0 and bone_total > 0,
			"%s carries a rigged skeleton (%d bones)" % [skel_key, bone_total])
		node2.free()
	_enter(Phase.SCALE)


## -- SCALE/ORIENTATION: 모델 scale/orientation 기준 통일 근거 --
func _scale() -> void:
	# 모듈러 건물 부품은 MegaKit의 2m 그리드를 유지한다(벽 폭 2.0).
	for wall_key in ["bld/wall_plaster_straight", "bld/wall_brick_straight",
			"bld/wall_plaster_door_flat"]:
		var node: Node3D = _catalog.instantiate_model(wall_key)
		var box := _merged_aabb(node)
		_check(absf(box.size.x - 2.0) <= 0.01,
			"%s keeps the kit's 2m modular width (%.2f)" % [wall_key, box.size.x])
		node.free()

	# 바닥 모듈은 2x2 XZ 평면이다(orientation: Y-up 지면 평면).
	for floor_key in ["bld/floor_wood_light", "bld/floor_brick"]:
		var node2: Node3D = _catalog.instantiate_model(floor_key)
		var box2 := _merged_aabb(node2)
		_check(absf(box2.size.x - 2.0) <= 0.01 and absf(box2.size.z - 2.0) <= 0.01,
			"%s lies flat on the XZ plane at 2x2 units" % floor_key)
		_check(absf(box2.position.y) <= 0.05,
			"%s origin sits on the ground plane (Y-up export)" % floor_key)
		node2.free()

	# humanoid base 신장은 실물 스케일(~1.8m)이다.
	for human_key in ["human/male_base", "human/female_base",
			"anim/mannequin_female"]:
		var node3: Node3D = _catalog.instantiate_model(human_key)
		var box3 := _merged_aabb(node3)
		_check(box3.size.y > 1.5 and box3.size.y < 2.1,
			"%s keeps realistic human height (%.2f)" % [human_key, box3.size.y])
		node3.free()

	# 지면 오브젝트(tree/rock/prop/tool)는 origin이 지면 근처다.
	var grounded_keys := ["tree/common_1", "rock/medium_1", "veg/bush_common",
		"prop/barrel", "tool/anvil", "bld/chimney"]
	for gkey in grounded_keys:
		var node4: Node3D = _catalog.instantiate_model(gkey)
		var box4 := _merged_aabb(node4)
		_check(box4.position.y >= -0.6 and box4.position.y <= 0.05,
			"%s is authored with a ground-level origin (min y %.2f)" % [gkey, box4.position.y])
		node4.free()

	# 예외 문서화: vine은 처마 아래 매달리는 용도라 origin 위로 생성된다.
	var vine: Node3D = _catalog.instantiate_model("bld/vine_1")
	_check(_merged_aabb(vine).position.y < -1.0,
		"bld/vine_1 hangs below its origin by design (eaves decoration)")
	vine.free()

	# 전 모델 AABB 유한성(깨진 transform 방지).
	var all_finite := true
	for key in _keys:
		var node5: Node3D = _catalog.instantiate_model(key)
		var box5 := _merged_aabb(node5)
		if not (box5.size.is_finite() and box5.size.x > 0.0
				and box5.size.y > 0.0 and box5.size.z > 0.0):
			all_finite = false
			print("  degenerate aabb: %s" % key)
		node5.free()
	_check(all_finite, "every catalog model has a finite non-degenerate volume")
	_enter(Phase.ISOLATION)


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


## -- ISOLATION: 원본 전체를 Scene에서 직접 참조하지 않음(.gdignore 격리) --
func _isolation() -> void:
	_check(not ResourceLoader.exists(
			DOC_ROOT + "_source/extracted/stylized-nature-megakit/glTF/CommonTree_1.gltf"),
		"original pack sources under _source/ stay invisible to the runtime")
	_check(ResourceLoader.exists(_catalog.get_model_path("tree/common_1")),
		"only the curated models/ copy is runtime-visible")
	_finish()
