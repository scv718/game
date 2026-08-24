extends SceneTree

## OVERNIGHT-STOP-7 Control / Map / Exploration Foundation 종료 경계 검증.
## TASK-CTRL-001 / TASK-MAP-001 / TASK-MAP-002 / TASK-EXP-001 완료 상태에서
## 큐를 종료하기 전 아래 경계를 자동 검증한다:
##   A. 종료 전제: runtime Player Actor 없음(player.gd/player.tscn 제거 확인 포함).
##   B. DAY/NIGHT Camera + Mouse 관리 조작 구조 유지.
##   C. 192x192 World scale 유지.
##   D. WEST/NORTH/EAST/SOUTH 방향별 역할 유지.
##   E. World Map View 유지.
##   F. 최소 Exploration state(UNKNOWN/EXPLORING/DISCOVERED) 유지.
##   G. TASK-016 Death Ledger autoload 유지.
##   H. 금지 시스템(Ghost/Wave/Boss/Food/Potion/Morale/Dungeon) 미시작.
##   I. 임시 파일(_diag*/_probe*/_debug*/_temp*) 없음.
##
 ## 종료 회귀(smoke/taskctrl0015/taskmap0015/taskmap0023/taskexp0013/
 ## task0158/task0166)는 본 테스트와 별도로 개별 실행한다.

const EXPECTED_AUTOLOADS := [
	"VillageResources",
	"GameTime",
	"WorkerRoster",
	"MercenaryRoster",
	"FirstEncounterSpawner",
	"DeathLedger",
	"ExplorationManager",
]

var _failed := false
var _frame := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 8:
		var main: Node = root.get_node("Main")
		_check(main != null, "main.tscn loads")
		if main == null:
			print("OVERNIGHTSTOP7_RESULT=FAIL")
			quit()
			return true

		_verify_no_player_actor(main)
		_verify_camera_mouse_management(main)
		_verify_world_scale(main)
		_verify_direction_roles(main)
		_verify_world_map_view(main)
		_verify_exploration_state()
		_verify_death_ledger()
		_verify_forbidden_systems_not_started()
		_verify_no_temp_files()

		print("OVERNIGHTSTOP7_RESULT=" + ("FAIL" if _failed else "PASS"))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)


# --- A. 종료 전제: Player Actor 없음 ---

func _verify_no_player_actor(main: Node) -> void:
	_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")
	_check(main.find_child("Player", true, false) == null, "no Player node in runtime tree")
	_check(FileAccess.file_exists("res://scripts/player.gd") == false,
		"scripts/player.gd removed")
	_check(FileAccess.file_exists("res://scenes/player.tscn") == false,
		"scenes/player.tscn removed")


# --- B. Camera + Mouse 관리 조작 ---

func _verify_camera_mouse_management(main: Node) -> void:
	var cams := get_nodes_in_group("camera_controller")
	_check(cams.size() == 1, "exactly 1 camera controller")
	if cams.size() == 1:
		var owned := cams[0].find_children("*", "Camera2D", true, false)
		_check(owned.size() >= 1 and (owned[0] as Camera2D).enabled,
			"camera controller owns enabled Camera2D")
	_check(get_nodes_in_group("world_selection").size() == 1, "WorldSelection present")
	_check(get_nodes_in_group("building_placement").size() == 1, "BuildingPlacement present")
	_check(get_nodes_in_group("tactical_command_ui").size() == 1,
		"TacticalCommandUI present (NIGHT input policy)")


# --- C. 192x192 World scale ---

func _verify_world_scale(main: Node) -> void:
	var world: Node = main.get_node("World")
	var floor_node: TileMapLayer = world.get_node("Floor") as TileMapLayer
	_check(floor_node.get_used_cells().size() >= 128 * 128,
		"world floor intact (%d cells)" % floor_node.get_used_cells().size())
	_check(WorldMap.MAP_TILES == 192, "MAP_TILES == 192")
	_check(WorldMap.WORLD_SIZE == 3072, "WORLD_SIZE == 3072px")
	_check(WorldMap.BOUNDS_RECT == Rect2(-1536, -1536, 3072, 3072),
		"BOUNDS_RECT is +/-1536")


# --- D. 방향별 역할 유지 ---

func _verify_direction_roles(main: Node) -> void:
	var map_layout: Node2D = main.get_node_or_null("World/MapLayout")
	_check(map_layout != null, "MapLayout markers node exists")
	if map_layout == null:
		return
	var expected_roles := {
		"west": "main_threat_portal",
		"north": "secondary_threat_rift",
		"east": "royal_road_exit",
		"south": "future_event_threat",
	}
	for dir in expected_roles:
		_check(map_layout.call("get_direction_role", dir) == expected_roles[dir],
			"%s = %s" % [dir.to_upper(), expected_roles[dir]])
	for dir in WorldMap.GATE_ANCHORS:
		var anchor_name: String = "GateAnchor_" + String(dir).to_upper()
		var marker: Node2D = map_layout.get_node_or_null(anchor_name)
		_check(marker != null \
			and marker.position == WorldMap.GATE_ANCHORS[dir],
			"%s matches GATE_ANCHORS constant" % anchor_name)


# --- E. World Map View ---

func _verify_world_map_view(main: Node) -> void:
	var overlays := get_nodes_in_group("world_map_overlay")
	_check(overlays.size() == 1, "exactly 1 WorldMapOverlay")
	if overlays.size() == 1:
		_check(overlays[0].has_method("is_open"), "overlay has open/close API")
		_check(overlays[0].has_method("world_to_map"), "overlay has world->map mapping")
	_check(main.find_child("HUD", true, false) != null, "HUD intact beside overlay")


# --- F. 최소 Exploration state ---

func _verify_exploration_state() -> void:
	var manager: Node = root.get_node_or_null("ExplorationManager")
	_check(manager != null, "ExplorationManager autoload registered")
	if manager == null:
		return
	var region: ExplorationRegion = manager.get_region("ne_dungeon")
	_check(region != null, "prototype region 'ne_dungeon' registered")
	if region == null:
		return
	_check(region.get_discovery_state() == ExplorationRegion.DiscoveryState.UNKNOWN,
		"region starts UNKNOWN")
	_check(ExplorationRegion.DiscoveryState.UNKNOWN == 0 \
		and ExplorationRegion.DiscoveryState.EXPLORING == 1 \
		and ExplorationRegion.DiscoveryState.DISCOVERED == 2,
		"minimal discovery states UNKNOWN/EXPLORING/DISCOVERED")
	_check(region.get_class() == "RefCounted", "region is pure data (no Actor reference)")
	var map_layout: Node2D = root.get_node("Main").get_node_or_null("World/MapLayout")
	_check(map_layout != null and map_layout.get_node_or_null(region.source_marker_id) != null,
		"region links to existing WorldMap marker '%s'" % region.source_marker_id)


# --- G. Death Ledger ---

func _verify_death_ledger() -> void:
	var ledger: Node = root.get_node_or_null("DeathLedger")
	_check(ledger != null, "DeathLedger autoload registered")
	if ledger != null:
		_check(ledger.get_all_records().size() == 0, "DeathLedger starts empty")


# --- H. 금지 시스템 미시작 ---

func _verify_forbidden_systems_not_started() -> void:
	var forbidden_prefixes := [
		"ghost", "wave", "boss", "food", "potion", "morale", "dungeon",
	]
	var file_offenders: Array[String] = []
	for dir_path in ["res://scripts", "res://ui", "res://scenes", "res://data"]:
		for file in _list_script_and_scene_files(dir_path):
			var base := file.to_lower().get_file().get_basename()
			for prefix in forbidden_prefixes:
				if base.begins_with(prefix):
					file_offenders.append("%s/%s" % [dir_path, file])
	_check(file_offenders.is_empty(),
		"no forbidden system files in scripts/ui/scenes/data")
	for offender in file_offenders:
		print("FAIL: forbidden system file -> " + offender)
		_failed = true
	var forbidden_class_names := [
		"class_name GhostActor", "class_name GhostFactory",
		"class_name GhostReturnSpawner", "class_name WaveManager",
		"class_name Boss", "class_name Food", "class_name Potion",
		"class_name Morale", "class_name Dungeon",
	]
	var offenders: Array[String] = []
	for file in _list_script_and_scene_files("res://scripts"):
		if not file.ends_with(".gd"):
			continue
		var content := FileAccess.get_file_as_string("res://scripts".path_join(file))
		for decl in forbidden_class_names:
			if content.contains(decl):
				offenders.append("scripts/%s declares %s" % [file, decl])
	_check(offenders.is_empty(), "no forbidden class declarations in scripts/")
	for offender in offenders:
		print("FAIL: forbidden declaration -> " + offender)
		_failed = true
	for autoload in EXPECTED_AUTOLOADS:
		_check(ProjectSettings.has_setting("autoload/" + autoload),
			"expected autoload intact: " + autoload)
	var cfg := ConfigFile.new()
	_check(cfg.load("res://project.godot") == OK, "project.godot readable")
	if cfg.has_section("autoload"):
		for key in cfg.get_section_keys("autoload"):
			_check(EXPECTED_AUTOLOADS.has(key), "no unexpected autoload: " + key)


# --- I. 임시 파일 없음 ---

func _verify_no_temp_files() -> void:
	var temp_prefixes := ["_diag", "_probe", "_debug", "_temp"]
	var found: Array[String] = []
	_scan_temp_files("res://", temp_prefixes, found)
	_check(found.is_empty(), "no _diag*/_probe*/_debug*/_temp* files in project")
	for path in found:
		print("FAIL: temp file left behind -> " + path)
		_failed = true


func _scan_temp_files(dir_path: String, prefixes: Array, found: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if entry != ".git" and entry != ".godot":
				_scan_temp_files(dir_path.path_join(entry), prefixes, found)
		else:
			for prefix in prefixes:
				if entry.begins_with(prefix):
					found.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


func _list_script_and_scene_files(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() \
				and (entry.ends_with(".gd") or entry.ends_with(".tscn")):
			result.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return result
