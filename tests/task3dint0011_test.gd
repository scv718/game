extends SceneTree

## TASK-3D-INT-001-1 Main Scene Wiring / Shared Config 회귀 테스트.
## 기존 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위(큐 요구사항/완료조건 대응):
##   1. project main scene 3D path 연결: application/run/main_scene가
##     res://scenes/main_3d.tscn을 가리키고, scene이 missing resource/path 없이
##     로드·인스턴스된다.
##   2. shared config: 필수 InputMap action과 기존 Autoload 7종 구성이 유지되고,
##     NavigationManager3D의 nav map cell 해상도가 NavigationPolicy3D 단일 소스와
##     일치한다.
##   3. duplicate input owner/camera/NavigationRegion 제거: Runtime 트리에 Camera3D /
##     NavigationRegion3D / WorldEnvironment / 각 controller 그룹이 정확히 1개씩만
##     있고, 2D 전용 노드(Camera2D/Node2D 계열)와 2D tactical UI/카메라 그룹은 없다.
##   4. Main 실행 성공: 인스턴스된 Main 3D 셸에서 DAY -> NIGHT -> DAY cycle을
##     진행해도 오류 없이 동작한다(NIGHT에 EnemyActor3D spawn, DAY despawn,
##     tactical UI 표시/숨김, ledger 무기록, 반복 spawn duplicate 없음).
##
## 주의: -s 기동 초기의 autoload 미등록 컴파일 단계 규약(CMB-001-2와 동일)에 따라
## 이 테스트는 autoload를 참조하는 스크립트(mercenary_roster_3d 등)를 정적으로
## 참조하지 않고, 트리 노드/런타임 load + duck-typing으로만 접근한다.

enum Phase {
	SETUP, CONFIG, INSTANCE_WAIT, STRUCTURE_AUDIT, DUPLICATE_AUDIT,
	TO_NIGHT, NIGHT_WAIT, NIGHT_CHECK, NIGHT_IDLE, NIGHT_IDLE_CHECK,
	TO_DAY, DAY_WAIT, DAY_CHECK, CLEANUP, DONE,
}

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const WORLD_SCENE_PATH := "res://scenes/world3d.tscn"
const ENV_SCENE_PATH := "res://scenes/environment_3d.tscn"
const CAMERA_SCENE_PATH := "res://scenes/camera_controller_3d.tscn"
const SELECTION_SCRIPT_PATH := "res://scripts/world_selection_3d.gd"
const PLACEMENT_SCRIPT_PATH := "res://scripts/building_placement_3d.gd"
const ROSTER_SCRIPT_PATH := "res://scripts/mercenary_roster_3d.gd"
const SPAWNER_SCRIPT_PATH := "res://scripts/first_encounter_spawner_3d.gd"
const NAV_SCRIPT_PATH := "res://scripts/navigation_manager_3d.gd"
const HUD_SCENE_PATH := "res://ui/hud_3d.tscn"
const OVERLAY_SCENE_PATH := "res://ui/world_map_overlay.tscn"

const EXPECTED_AUTOLOADS := [
	"VillageResources", "GameTime", "WorkerRoster", "MercenaryRoster",
	"FirstEncounterSpawner", "DeathLedger", "ExplorationManager",
]
const REQUIRED_ACTIONS := [
	"move_up", "move_down", "move_left", "move_right",
	"interact", "build", "death_ledger", "world_map",
]

## 테스트용 단축 phase 시간(sec). 기본 60/30 대신 짧게 진행한다.
const SHORT_DAY_DURATION := 0.6
const SHORT_NIGHT_DURATION := 0.6
const ENCOUNTER_ENEMY_COUNT := 3
const SETTLE_FRAMES := 8

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _main: Node = null
var _world: Node = null
var _game_time: Node = null
var _ledger: Node = null
var _roster_3d: Node = null
var _spawner_3d: Node = null
var _tac_3d: Node = null
var _nav_manager: Node = null
var _cam_ctl: Node = null
var _ledger_baseline := -1


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_wait = 0


func _group_count(group_name: String) -> int:
	return get_nodes_in_group(group_name).size()


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK3DINT0011_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONFIG:
			_config()
		Phase.INSTANCE_WAIT:
			_instance_wait()
		Phase.STRUCTURE_AUDIT:
			_structure_audit()
		Phase.DUPLICATE_AUDIT:
			_duplicate_audit()
		Phase.TO_NIGHT:
			_to_night()
		Phase.NIGHT_WAIT:
			_night_wait()
		Phase.NIGHT_CHECK:
			_night_check()
		Phase.NIGHT_IDLE:
			_night_idle()
		Phase.NIGHT_IDLE_CHECK:
			_night_idle_check()
		Phase.TO_DAY:
			_to_day()
		Phase.DAY_WAIT:
			_day_wait()
		Phase.DAY_CHECK:
			_day_check()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			_finish()
			return true
	if _frame > 12000:
		print("TASK3DINT0011_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	if _frame < SETTLE_FRAMES:
		return
	_game_time = root.get_node_or_null("GameTime")
	_ledger = root.get_node_or_null("DeathLedger")
	_check(_game_time != null and _ledger != null,
		"shared GameTime/DeathLedger autoloads are available to the 3D main runtime")
	if _game_time == null or _ledger == null:
		_enter(Phase.DONE)
		return
	# startup frame 오염과 무관하게 phase 경계를 통제하기 위해 auto advance off.
	_game_time.set_auto_advance(false)
	_game_time.set_durations(SHORT_DAY_DURATION, SHORT_NIGHT_DURATION)
	_enter(Phase.CONFIG)


## -- CONFIG: shared config(main scene path / InputMap / autoload / nav 해상도) --
func _config() -> void:
	var main_scene_setting: String = ProjectSettings.get_setting(
		"application/run/main_scene", "")
	_check(main_scene_setting == MAIN_SCENE_PATH,
		"project main scene points to the 3D path (%s)" % MAIN_SCENE_PATH)

	for path in [
		MAIN_SCENE_PATH, WORLD_SCENE_PATH, ENV_SCENE_PATH, CAMERA_SCENE_PATH,
		SELECTION_SCRIPT_PATH, PLACEMENT_SCRIPT_PATH, ROSTER_SCRIPT_PATH,
		SPAWNER_SCRIPT_PATH, NAV_SCRIPT_PATH, HUD_SCENE_PATH, OVERLAY_SCENE_PATH,
	]:
		_check(ResourceLoader.exists(path), "wired resource exists: %s" % path)

	var packed: PackedScene = load(MAIN_SCENE_PATH)
	_check(packed != null, "main 3D scene loads without parser/import errors")

	for action in REQUIRED_ACTIONS:
		_check(InputMap.has_action(action),
			"InputMap keeps required action '%s'" % action)

	for autoload_name in EXPECTED_AUTOLOADS:
		var setting: Variant = ProjectSettings.get_setting(
			"autoload/%s" % autoload_name, null)
		_check(setting != null and str(setting).contains("res://"),
			"autoload '%s' stays registered" % autoload_name)

	_enter(Phase.INSTANCE_WAIT)


func _instance_wait() -> void:
	if _wait == 0:
		var packed: PackedScene = load(MAIN_SCENE_PATH)
		_main = packed.instantiate()
		_main.name = "Main3D"
		root.add_child(_main)
	_world = root.get_node_or_null("Main3D/World3D")
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_check(_main != null and _world != null,
		"main 3D scene instantiates with its World3D root")
	if _main == null or _world == null:
		_enter(Phase.DONE)
		return
	_roster_3d = _main.get_node_or_null("MercenaryRoster3D")
	_spawner_3d = _main.get_node_or_null("FirstEncounterSpawner3D")
	_tac_3d = get_first_node_in_group("tactical_command_ui_3d")
	_nav_manager = _world.get_node_or_null("NavigationManager3D")
	_cam_ctl = get_first_node_in_group("camera_controller_3d")
	_ledger_baseline = (_ledger as Node).get_all_records().size()
	_enter(Phase.STRUCTURE_AUDIT)


## -- STRUCTURE_AUDIT: wiring 대상 1개씩 연결 + 명령/UI 경로 connect --
func _structure_audit() -> void:
	var spawner_script: Script = load(SPAWNER_SCRIPT_PATH)
	_check(_roster_3d != null and _roster_3d.is_in_group("mercenary_roster_3d"),
		"MercenaryRoster3D is wired into the main scene")
	_check(_spawner_3d != null and _spawner_3d.get_script() == spawner_script,
		"FirstEncounterSpawner3D is wired into the main scene")
	_check(_tac_3d != null and _tac_3d is Control,
		"TacticalCommandUI3D stays in the Control layer inside the HUD")
	_check(_nav_manager != null and _nav_manager.get_parent() == _world,
		"NavigationManager3D is wired under the World3D root")
	_check(_cam_ctl != null, "Foundation CameraController3D is wired")
	_check(_roster_3d != null and _tac_3d != null \
			and _tac_3d.command_issued.is_connected(_roster_3d._on_tactical_command),
		"tactical UI command path is connected to the 3D roster exactly once")

	var selection := get_first_node_in_group("world_selection")
	_check(selection != null and selection.has_signal("selection_changed"),
		"HUD prompt hook target (legacy world_selection group) resolves to WorldSelection3D")
	_check(get_first_node_in_group("building_placement") == get_first_node_in_group("building_placement_3d"),
		"BuildingPlacement3D serves both legacy and 3D lookup groups")

	var region: NavigationRegion3D = _nav_manager.get_nav_region()
	_check(region != null and region.is_inside_tree(),
		"exactly the manager-owned NavigationRegion3D is inside the tree")
	_check(_nav_manager.nav_rebuild_count >= 1, "navigation baked at least once on startup")
	var map_cell: float = NavigationServer3D.map_get_cell_size(
		_nav_manager.get_navigation_map())
	_check(is_equal_approx(map_cell, NavigationPolicy3D.NAV_CELL_SIZE_UNITS),
		"nav map cell resolution matches the NavigationPolicy3D single source")

	var env := get_first_node_in_group("environment_3d")
	_check(env != null and env.get_parent() == _main,
		"Environment3D layer is added on top of the 3D main world")

	_enter(Phase.DUPLICATE_AUDIT)


## -- DUPLICATE_AUDIT: camera/nav/env singleton + 2D runtime 잔존 부재 --
func _duplicate_audit() -> void:
	var nodes: Array = []
	_collect_nodes(root, nodes)

	var camera3d_count := 0
	var camera2d_count := 0
	var node2d_count := 0
	var nav_region_count := 0
	var world_env_count := 0
	var sun_count := 0
	for node in nodes:
		if node is Camera3D:
			camera3d_count += 1
		elif node is Camera2D:
			camera2d_count += 1
		elif node is Node2D:
			node2d_count += 1
		elif node is NavigationRegion3D:
			nav_region_count += 1
		elif node is WorldEnvironment:
			world_env_count += 1
		elif node is DirectionalLight3D:
			sun_count += 1

	_check(camera3d_count == 1, "exactly one Camera3D exists in the 3D runtime")
	_check(camera2d_count == 0 and node2d_count == 0,
		"no 2D camera/Node2D runtime nodes leak into the 3D main path")
	_check(nav_region_count == 1, "exactly one NavigationRegion3D exists")
	_check(world_env_count == 1, "exactly one WorldEnvironment exists")
	_check(sun_count == 1, "exactly one DirectionalLight3D exists")
	_check(root.get_camera_3d() == _cam_ctl.get_camera(),
		"the viewport current camera is the single CameraController3D camera")

	_check(_group_count("world") == 0, "no legacy 2D world group owner is active")
	_check(_group_count("camera_controller") == 0,
		"no legacy 2D camera controller group owner is active")
	_check(_group_count("tactical_command_ui") == 0,
		"no legacy 2D tactical command UI (duplicate input owner) is active")
	for group_name in ["world3d", "camera_controller_3d", "world_selection",
			"world_selection_3d", "building_placement", "building_placement_3d",
			"mercenary_roster_3d", "recruitment_ui", "inn_roster_ui",
			"death_ledger_view", "world_map_overlay"]:
		_check(_group_count(group_name) == 1,
			"group '%s' has exactly one owner" % group_name)

	_enter(Phase.TO_NIGHT)


## -- DAY -> NIGHT: 조우 spawn + tactical UI 표시 --
func _to_night() -> void:
	_game_time.advance(SHORT_DAY_DURATION * 1.1)
	_enter(Phase.NIGHT_WAIT)


func _night_wait() -> void:
	_wait += 1
	if _wait >= 4:
		_enter(Phase.NIGHT_CHECK)


func _night_check() -> void:
	_check(_game_time.get_phase_name() == "NIGHT", "phase advanced to NIGHT")
	_check(_tac_3d.visible, "tactical command UI is visible at NIGHT")
	var enemies := get_nodes_in_group("enemies_3d")
	_check(enemies.size() == ENCOUNTER_ENEMY_COUNT,
		"NIGHT encounter spawns %d EnemyActor3D" % ENCOUNTER_ENEMY_COUNT)
	var parents_ok := true
	for enemy in enemies:
		if enemy.get_parent() != _world:
			parents_ok = false
	_check(parents_ok, "spawned enemies live under the World3D root")
	_check(_group_count("mercenaries_3d") == 0,
		"no mercenaries are spawned without hires")
	_check(_group_count("enemies") == 0 and _group_count("mercenaries") == 0,
		"legacy 2D combat autoloads stay inert (no 2D actors)")
	var roster_2d := root.get_node_or_null("MercenaryRoster")
	var spawner_2d := root.get_node_or_null("FirstEncounterSpawner")
	_check(roster_2d != null and roster_2d.get_actor_count() == 0,
		"2D MercenaryRoster autoload spawned nothing in the 3D main runtime")
	_check(spawner_2d != null and spawner_2d.get_enemy_count() == 0,
		"2D FirstEncounterSpawner autoload spawned nothing in the 3D main runtime")
	_check((_ledger as Node).get_all_records().size() == _ledger_baseline,
		"encounter spawn creates no death records")
	_enter(Phase.NIGHT_IDLE)


func _night_idle() -> void:
	_game_time.advance(0.1)
	_enter(Phase.NIGHT_IDLE_CHECK)


func _night_idle_check() -> void:
	_check(_game_time.get_phase_name() == "NIGHT",
		"idle advance keeps the NIGHT phase without re-entry")
	_check(get_nodes_in_group("enemies_3d").size() == ENCOUNTER_ENEMY_COUNT,
		"idle NIGHT does not duplicate encounter spawning")
	_enter(Phase.TO_DAY)


## -- NIGHT -> DAY: despawn + UI 숨김 + transient 정리 --
func _to_day() -> void:
	_game_time.advance(SHORT_NIGHT_DURATION * 1.2)
	_enter(Phase.DAY_WAIT)


func _day_wait() -> void:
	_wait += 1
	if _wait >= 4:
		_enter(Phase.DAY_CHECK)


func _day_check() -> void:
	_check(_game_time.get_phase_name() == "DAY", "phase returned to DAY")
	_check(_game_time.get_day_number() == 2, "day number advanced exactly once")
	_check(not _tac_3d.visible, "tactical command UI hides at DAY")
	_check(get_nodes_in_group("enemies_3d").is_empty(),
		"DAY cleanup despawns every encounter enemy")
	var leftover := 0
	for child in _world.get_children():
		if child is EnemyActor3D:
			leftover += 1
	_check(leftover == 0,
		"despawned enemy nodes leave no orphan under the world root")
	_check((_ledger as Node).get_all_records().size() == _ledger_baseline,
		"DAY cleanup creates no death records (cleanup/despawn 무기록)")
	_check(is_equal_approx(_game_time.get_time_scale(), 1.0),
		"tactical time scale is restored to 1x at DAY")
	_enter(Phase.CLEANUP)


func _cleanup() -> void:
	_main.queue_free()
	_enter(Phase.DONE)


func _collect_nodes(node: Node, out: Array) -> void:
	out.append(node)
	for child in node.get_children():
		_collect_nodes(child, out)
