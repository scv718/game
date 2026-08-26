extends SceneTree

## TASK-3D-INT-001-3 2D Runtime Dependency Cleanup 회귀 테스트.
## 완료조건(큐) 대응:
##   1. Main Runtime 3D path self-contained: project main scene이
##      res://scenes/main_3d.tscn이고, 이 scene에서 도달 가능한 scene/script
##      closure 전체에 2D 전용 노드 타입과 2D 전용 extends가 없다.
##      UI Control/CanvasLayer는 정상 2D UI 계약이므로 허용된다(큐 요구사항).
##   2. orphan reference 없음: closure와 project.godot autoload가 참조하는 모든
##      res:// 경로가 실제로 존재한다. 또한 프로젝트 루트에 스크립트 본체가 없는
##      고아 *.uid sidecar가 없고, runtime 디렉터리(scenes/scripts/ui)와
##      project.godot의 res:// .gd/.tscn/.tres 참조 중 대상이 없는 것도 없다.
##   3. 2D Resource/Worker/Building/Combat Scene은 Runtime 미사용 확인:
##      LOCK 12에 따라 reference/test fixture로 보존되는 기존 2D scene 목록이
##      여전히 로드 가능하면서도 3D closure 어디에도 등장하지 않는다.
##   4. CharacterBody2D / NavigationAgent2D / Area2D 등 2D 물리/내비/카메라
##      노드는 실제 Runtime 트리에 0개다(Node2D 파생 전체 포함).
##
## 공유 config 결정(INT-001-1 문서 + AUDIT_2D_RUNTIME_CLEANUP.md):
##   - MercenaryRoster autoload는 주점/여관 UI의 데이터 소스이자
##     mercenary_hire_sync_3d bridge의 source라서 유지한다.
##   - FirstEncounterSpawner autoload는 "world"(2D) 그룹 lookup guard로
##     3D Runtime에서 no-op이며, 보존 중인 2D reference 회귀 스위트가 사용하므로
##     2D fixture 세션과 함께 최종 전환 완료 후 일괄 정리 대상이다.
##
## 구현 규약: INT-001-1 테스트와 동일하게 autoload를 참조하는 스크립트를 정적
## 참조하지 않고, 파일 텍스트 파싱 + duck-typing으로만 검증한다.

enum Phase {
	SETUP, SCAN, INSTANCE_WAIT, TREE_AUDIT, CLEANUP, DONE,
}

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"

## 2D 전용 표현/물리/내비/카메라 클래스. closure의 tscn node type과 gd extends
## 체인 어디에도 나오면 안 된다(Control/CanvasLayer/UI 계열은 제외).
const FORBIDDEN_2D_TYPES := [
	"Node2D", "Sprite2D", "AnimatedSprite2D",
	"CharacterBody2D", "RigidBody2D", "StaticBody2D", "Area2D",
	"CollisionShape2D", "CollisionPolygon2D",
	"NavigationAgent2D", "NavigationRegion2D", "NavigationObstacle2D",
	"TileMap", "TileMapLayer", "Camera2D", "Marker2D",
	"Line2D", "Polygon2D", "Path2D", "PathFollow2D",
	"CanvasModulate", "PointLight2D", "DirectionalLight2D",
]

## LOCK 12 보존 대상 2D reference scene 전체 목록(migration map 산출물 1.B).
const RETAINED_2D_SCENES := [
	"res://scenes/main.tscn",
	"res://scenes/world.tscn",
	"res://scenes/tree.tscn",
	"res://scenes/lumberyard.tscn",
	"res://scenes/lumberjack.tscn",
	"res://scenes/stone_deposit.tscn",
	"res://scenes/quarry.tscn",
	"res://scenes/miner.tscn",
	"res://scenes/decoration.tscn",
	"res://scenes/core_building.tscn",
	"res://scenes/wall.tscn",
	"res://scenes/gate.tscn",
	"res://scenes/mercenary.tscn",
	"res://scenes/enemy.tscn",
	"res://scenes/camera_controller.tscn",
]

## 보존 결정이 문서화된 dormant/shared autoload 계약.
const RETAINED_SHARED_AUTOLOADS := {
	"MercenaryRoster": "res://scripts/mercenary_roster.gd",
	"FirstEncounterSpawner": "res://scripts/first_encounter_spawner.gd",
}

const SETTLE_FRAMES := 8

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _main: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_wait = 0


func _finish() -> void:
	print("TASK3DINT0013_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.SCAN:
			_scan()
		Phase.INSTANCE_WAIT:
			_instance_wait()
		Phase.TREE_AUDIT:
			_tree_audit()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			_finish()
			return true
	if _frame > 4000:
		print("TASK3DINT0013_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	if _frame < SETTLE_FRAMES:
		return
	var main_scene_setting: String = ProjectSettings.get_setting(
		"application/run/main_scene", "")
	_check(main_scene_setting == MAIN_SCENE_PATH,
		"Main Runtime entry stays on the 3D path (%s)" % MAIN_SCENE_PATH)
	_enter(Phase.SCAN)


## -- SCAN: closure 수집 + 2D 타입 단정 + orphan reference 검사 --
func _scan() -> void:
	var class_base := {}
	var class_def := {}
	_build_class_maps(class_base, class_def)

	var closure := {}
	var queue: Array[String] = [MAIN_SCENE_PATH]
	closure[MAIN_SCENE_PATH] = true
	while not queue.is_empty():
		_collect_refs(queue.pop_front(), closure, queue)

	# global class_name으로 extends하는 의존도 closure에 포함(fixpoint).
	var grew := true
	while grew:
		grew = false
		for path in closure.keys():
			if not String(path).ends_with(".gd"):
				continue
			var ext := _extends_of_file(String(path))
			if ext.is_empty() or not class_def.has(ext):
				continue
			var dep: String = class_def[ext]
			if closure.has(dep):
				continue
			closure[dep] = true
			queue.push_back(dep)
			grew = true
			while not queue.is_empty():
				_collect_refs(queue.pop_front(), closure, queue)

	var errors := 0
	for path in closure.keys():
		if String(path).ends_with(".tscn"):
			errors += _audit_tscn_types(String(path))
		elif String(path).ends_with(".gd"):
			errors += _audit_gd_extends(String(path), class_base)

	# orphan reference: closure가 참조하는 모든 경로가 실재해야 한다.
	for path in closure.keys():
		_check(FileAccess.file_exists(path),
			"closure resource exists: %s" % path)

	# project.godot autoload 경로도 실재해야 한다.
	var autoload_paths := _read_autoload_paths()
	_check(not autoload_paths.is_empty(), "project.godot exposes autoload section")
	for autoload_name in autoload_paths.keys():
		var apath: String = autoload_paths[autoload_name]
		_check(FileAccess.file_exists(apath),
			"autoload '%s' points at an existing script (%s)" % [autoload_name, apath])

	# 공유 config 계약: 보존 결정된 autoload가 지정 스크립트를 계속 가리킨다.
	for autoload_name in RETAINED_SHARED_AUTOLOADS.keys():
		var expected: String = RETAINED_SHARED_AUTOLOADS[autoload_name]
		_check(autoload_paths.get(autoload_name, "") == expected,
			"shared autoload '%s' keeps its documented script (%s)" % [autoload_name, expected])

	# 2D Resource/Worker/Building/Combat Scene: 보존 + Runtime 미사용 확인.
	for two_d_path in RETAINED_2D_SCENES:
		_check(FileAccess.file_exists(two_d_path),
			"LOCK 12 reference fixture stays on disk: %s" % two_d_path)
		_check(not closure.has(two_d_path),
			"retained 2D scene is outside the Main Runtime 3D closure: %s" % two_d_path)
		_check(not _closure_references(closure, two_d_path),
			"no 3D closure file references 2D scene path: %s" % two_d_path)

	_check(errors == 0,
		"closure contains no 2D-only node type / extends (%d violations)" % errors)

	# 고아 *.uid sidecar: 스크립트 본체 없는 .uid가 프로젝트 어디에도 없어야 한다.
	_check(not _has_orphan_uid_sidecars(), "no orphan *.gd.uid sidecars remain")

	# runtime 영역(scenes/scripts/ui + project.godot)의 res:// 참조 대상 존재 검사.
	# (tests/tools는 negative assertion·capture 출력 경로 등 의도적 예외가 있어 제외)
	_check(not _has_dangling_runtime_refs(),
		"no dangling res:// .gd/.tscn/.tres references in scenes/scripts/ui/project.godot")

	_enter(Phase.INSTANCE_WAIT)


## -- INSTANCE_WAIT: 실제 Runtime 부팅 --
func _instance_wait() -> void:
	if _wait == 0:
		var packed: PackedScene = load(MAIN_SCENE_PATH)
		_main = packed.instantiate()
		_main.name = "Main3D"
		root.add_child(_main)
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_check(_main != null and root.get_node_or_null("Main3D/World3D") != null,
		"3D main runtime boots standalone from its own closure")
	_enter(Phase.TREE_AUDIT)


## -- TREE_AUDIT: 살아있는 트리에 2D 물리/내비/카메라 잔존 0 --
func _tree_audit() -> void:
	var nodes: Array = []
	_collect_nodes(root, nodes)

	var node2d_count := 0
	var character_body2d_count := 0
	var area2d_count := 0
	var nav_agent2d_count := 0
	var camera2d_count := 0
	var tile_map_layer_count := 0
	var camera3d_count := 0
	for node in nodes:
		if node is CharacterBody2D:
			character_body2d_count += 1
		if node is Area2D:
			area2d_count += 1
		if node is NavigationAgent2D:
			nav_agent2d_count += 1
		if node is Camera2D:
			camera2d_count += 1
		if node is TileMapLayer:
			tile_map_layer_count += 1
		if node is Node2D:
			node2d_count += 1
		if node is Camera3D:
			camera3d_count += 1

	_check(node2d_count == 0, "live runtime tree contains zero Node2D-derived nodes")
	_check(character_body2d_count == 0, "CharacterBody2D absent from core Runtime")
	_check(area2d_count == 0, "Area2D absent from core Runtime")
	_check(nav_agent2d_count == 0, "NavigationAgent2D absent from core Runtime")
	_check(camera2d_count == 0, "Camera2D absent from core Runtime")
	_check(tile_map_layer_count == 0, "TileMapLayer absent from core Runtime")
	_check(camera3d_count == 1, "exactly one Camera3D serves the 3D runtime")

	_enter(Phase.CLEANUP)


func _cleanup() -> void:
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	_enter(Phase.DONE)


## closure 파일 하나에서 참조하는 res:// 경로를 수집하고 새 파일을 큐에 넣는다.
## 반환값은 파싱 실패 건수다.
func _collect_refs(path: String, closure: Dictionary, queue: Array[String]) -> int:
	var text := _read_text(path)
	if text.is_empty():
		print("FAIL: cannot read closure file: %s" % path)
		return 1
	var found := 0
	if path.ends_with(".tscn"):
		var re := RegEx.create_from_string("\\[ext_resource[^\\]]*path=\"(res://[^\"]+)\"")
		for m in re.search_all(text):
			found += _enqueue_ref(m.get_string(1), closure, queue)
	else:
		var re_gd := RegEx.create_from_string("(?:load|preload)\\(\"(res://[^\"]+)\"\\)")
		for m in re_gd.search_all(text):
			found += _enqueue_ref(m.get_string(1), closure, queue)
	return 0


func _enqueue_ref(ref_path: String, closure: Dictionary, queue: Array[String]) -> int:
	if not closure.has(ref_path):
		closure[ref_path] = true
		if ref_path.ends_with(".tscn") or ref_path.ends_with(".gd"):
			queue.push_back(ref_path)
	return 0


## closure 내 tscn의 모든 [node type=...]을 2D 블랙리스트와 대조한다.
func _audit_tscn_types(path: String) -> int:
	var text := _read_text(path)
	var re := RegEx.create_from_string("\\[node[^\\]]*type=\"([A-Za-z0-9]+)\"")
	var violations := 0
	for m in re.search_all(text):
		var node_type := m.get_string(1)
		if node_type in FORBIDDEN_2D_TYPES:
			print("FAIL: 2D node type '%s' inside %s" % [node_type, path])
			violations += 1
	return violations


## closure 내 gd의 extends 체인을 builtin으로 환원해 2D 블랙리스트와 대조한다.
func _audit_gd_extends(path: String, class_bases: Dictionary) -> int:
	var text := _read_text(path)
	var re := RegEx.create_from_string("(?m)^extends\\s+([^\\s#]+)")
	var m := re.search(text)
	if m == null:
		return 0
	var current := m.get_string(1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	var visited := {}
	var depth := 0
	while depth < 16:
		depth += 1
		if visited.has(current):
			break
		visited[current] = true
		if current.begins_with("res://"):
			var next := _extends_of_file(current)
			if next.is_empty():
				break
			current = next
			continue
		if class_bases.has(current):
			current = class_bases[current]
			continue
		break
	if current in FORBIDDEN_2D_TYPES:
		print("FAIL: 2D extends chain of %s resolves to '%s'" % [path, current])
		return 1
	if current.begins_with("res://"):
		print("FAIL: unresolved extends chain in %s (ends at %s)" % [path, current])
		return 1
	return 0


func _extends_of_file(path: String) -> String:
	var re := RegEx.create_from_string("(?m)^extends\\s+([^\\s#]+)")
	var m := re.search(_read_text(path))
	if m == null:
		return ""
	return m.get_string(1).strip_edges().trim_prefix("\"").trim_suffix("\"")


## scripts/ 전체를 훑어 class_name -> extends / class_name -> 정의파일 매핑을 만든다.
func _build_class_maps(class_base: Dictionary, class_def: Dictionary) -> void:
	var dir := DirAccess.open("res://scripts")
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		var path := "res://scripts/" + file_name
		var text := _read_text(path)
		var re_class := RegEx.create_from_string("(?m)^class_name\\s+([A-Za-z0-9_]+)")
		var re_ext := RegEx.create_from_string("(?m)^extends\\s+([^\\s#]+)")
		var mc := re_class.search(text)
		var me := re_ext.search(text)
		if mc != null and me != null:
			class_base[mc.get_string(1)] = me.get_string(1).strip_edges() \
				.trim_prefix("\"").trim_suffix("\"")
			class_def[mc.get_string(1)] = path


func _read_autoload_paths() -> Dictionary:
	var out := {}
	var text := _read_text("res://project.godot")
	var in_section := false
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("["):
			in_section = trimmed == "[autoload]"
			continue
		if not in_section or trimmed.is_empty():
			continue
		var re := RegEx.create_from_string("^([A-Za-z0-9_]+)=\"\\*?(res://[^\"]+)\"")
		var m := re.search(trimmed)
		if m != null:
			out[m.get_string(1)] = m.get_string(2)
	return out


## 어떤 closure 파일이라도 지정 경로 문자열을 코드/리소스 참조로 포함하는지.
## 주석 속 언급은 무시하기 위해 tscn(ext_resource)과 gd(load/preload) 패턴만 본다.
func _closure_references(closure: Dictionary, target_path: String) -> bool:
	for path in closure.keys():
		if path == target_path:
			continue
		if not (path.ends_with(".tscn") or path.ends_with(".gd")):
			continue
		var text := _read_text(path)
		if text.contains(target_path):
			return true
	return false


## runtime 디렉터리(scenes/scripts/ui)와 project.godot의 res:// 참조 중
## 존재하지 않는 .gd/.tscn/.tres 대상이 하나라도 있으면 true.
## tests/(제거 확인용 negative assertion)와 tools/(capture 출력 경로)는 제외한다.
func _has_dangling_runtime_refs() -> bool:
	var targets := ["res://scenes", "res://scripts", "res://ui"]
	var re_ref := RegEx.create_from_string(
		"res://[A-Za-z0-9_\\-\\./]+\\.(gd|tscn|tres)")
	var checked := {}
	for dir_path in targets:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file_name in dir.get_files():
			if not (file_name.ends_with(".gd") or file_name.ends_with(".tscn")) \
					or file_name.ends_with(".uid"):
				continue
			var path: String = dir_path.path_join(file_name)
			var text := _read_text(path)
			if text.is_empty():
				continue
			for m in re_ref.search_all(text):
				var ref: String = m.get_string(0)
				if checked.has(ref):
					continue
				checked[ref] = true
				if not FileAccess.file_exists(ref):
					print("FAIL: dangling runtime reference %s in %s" % [ref, path])
					return true
	for m in re_ref.search_all(_read_text("res://project.godot")):
		var ref: String = m.get_string(0)
		if checked.has(ref):
			continue
		checked[ref] = true
		if not FileAccess.file_exists(ref):
			print("FAIL: dangling reference %s in project.godot" % ref)
			return true
	return false


## 코드 디렉터리에서 스크립트 본체 없이 남은 *.gd.uid sidecar를 찾는다.
## (에셋 import 캐시가 만드는 비-스크립트 .uid/.import는 대상 아니다.)
func _has_orphan_uid_sidecars() -> bool:
	for dir_path in ["res://", "res://scenes", "res://scripts", "res://ui",
			"res://tools", "res://tests"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for entry in dir.get_files():
			if not entry.ends_with(".gd.uid"):
				continue
			var script_path: String = dir_path.path_join(entry.trim_suffix(".uid"))
			if not FileAccess.file_exists(script_path):
				print("FAIL: orphan uid sidecar without script body: %s" % script_path)
				return true
	return false


func _collect_nodes(node: Node, out: Array) -> void:
	out.append(node)
	for child in node.get_children():
		_collect_nodes(child, out)


## res:// 텍스트 파일 전체 읽기. 실패 시 빈 문자열.
func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
