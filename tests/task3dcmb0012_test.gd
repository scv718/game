extends SceneTree

## TASK-3D-CMB-001-2 Tactical Command World3D Wiring 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위(큐 요구사항/완료조건 대응):
##   1. 구조: MercenaryRoster3D / FirstEncounterSpawner3D / TacticalCommandUI3D가
##     3D Runtime 전용 신규 파일로 존재하고, UI는 Control 계층 유지 + 명령 코드는
##     기존 TacticalCommandUI.Command 재사용(차원 중립).
##   2. Tactical Camera: Foundation CameraController3D를 그대로 소비하며 NIGHT에
##     night_zoom policy로 확장되고 DAY에 복귀한다. phase 전환과 무관하게 고정
##     사선 basis가 불변이다(Camera rotation 입력 경로 없음).
##   3. Defense Zone 위치/범위 XZ 처리: rally/safe/spawn 좌표가 전부 WorldMap logical
##     상수의 WorldCoords3D XZ 해석과 일치(Y = GROUND_Y 고정).
##   4. NIGHT tactical selection: focus mode에서 화면 광선 지면 교차점 기준으로
##     가장 가까운 살아 있는 Enemy 선택, 빈 ground 클릭 안전, mode 해제 시 focus 해제.
##   5. 명령 -> AI 행동: REGROUP/RETREAT/DEFENSE_ZONE 명령이 실제 MercenaryActor3D
##     FSM/이동에 반영된다(teleport 없음).
##   6. command priority 기존 규칙: FOCUS > 방어 구역 자동 전투(근접 zone enemy 무시),
##     REGROUP/RETREAT 중 set_focus_target은 즉시 전환하지 않음.
##   7. Gate world command: gates_3d duck-typing set_open 계약 동작 + BREACHED 보호,
##     UI 성문 목록이 gates_3d를 조회해 갱신된다.
##   8. TIME 명령: Pause/1x/2x 배율 설정, DAY 복귀 시 1x 복원.
##   9. DAY 복귀 transient 정리: spawn Actor despawn(무기록), focus mode/target 해제,
##     UI 숨김, 반복 NIGHT에서 duplicate 없음.
##
## 주의: 이 테스트가 정적으로 참조하는 클래스는 autoload를 참조하지 않는 스크립트뿐이다
## (WorldCoords3D/MercenaryData/MercenaryActor3D/EnemyActor3D/WorldMap 등).
## mercenary_roster_3d.gd와 tactical_command_ui 계열은 bare autoload(GameTime 등)를
## 참조하므로 -s 기동 초기의 autoload 미등록 컴파일 단계에서 정적 참조하면 컴파일이
## 파괴된다(리뷰 프로브로 확정). 해당 스크립트/명령 코드는 반드시 런타임 load() +
## duck-typing으로만 접근한다.

enum Phase {
	SETUP, STRUCTURE, CAMERA_DAY, HIRE, TO_NIGHT, CAMERA_NIGHT, SPAWN_WAIT,
	ZONE_XZ_CHECK, FOCUS_ARM, FOCUS_PICK, FOCUS_PRIORITY, FOCUS_CANCEL,
	REGROUP_CMD, REGROUP_OBSERVE, RETREAT_CMD, RETREAT_PRIORITY, RETREAT_OBSERVE,
	ZONE_CHANGE_CMD, ZONE_CHANGE_OBSERVE, GATE_ARM, GATE_CMD, TIME_CMD,
	TO_DAY, DAY_CLEANUP, FREE_MANUALS, REPEAT_NIGHT_WAIT, REPEAT_NIGHT_CHECK,
	CLEANUP, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 12
const OBSERVE_BUDGET := 900

## WorldMap.RALLY_SPACES의 XZ 해석값(테스트 기준값). rect 중심 * PX_TO_UNIT.
const NORTH_RALLY := Vector3(0.0, 0.0, -305.0 * WorldCoords3D.PX_TO_UNIT)
const EAST_RALLY := Vector3(305.0 * WorldCoords3D.PX_TO_UNIT, 0.0, 0.0)
const SOUTH_RALLY := Vector3(0.0, 0.0, 305.0 * WorldCoords3D.PX_TO_UNIT)
const WEST_RALLY := Vector3(-305.0 * WorldCoords3D.PX_TO_UNIT, 0.0, 0.0)

const FOCUS_ENEMY_POS := Vector3(12, 0, -24)
const ZONE_ENEMY_POS := Vector3(-3, 0, -34)
## ZONE_CHANGE 이후 저장된 focus가 방어 AI 재개와 함께 적용되는지 보는 미끼.
const LURE_ENEMY_OFFSET := Vector3(5, 0, 5)

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _nav_manager: Node = null
var _game_time: Node = null
var _ledger: Node = null
var _cam_ctl: Node = null
var _camera_basis := Transform3D()
var _roster: Node = null
var _spawner: Node = null
var _tac: Node = null
## 명령 코드/상수 참조는 전부 런타임 load()로 한다(상단 "주의" 참고).
var _roster_script: Script = null
var _cmd_ui: Script = null

var _merc_north: Node = null
var _merc_west: Node = null
var _data_north: MercenaryData = null
var _data_west: MercenaryData = null
var _focus_enemy: Node = null
var _zone_enemy: Node = null
var _lure_enemy: Node = null
var _ledger_before_day := -1


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
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK3DCMB0012_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _group_count(group_name: String) -> int:
	return get_nodes_in_group(group_name).size()


func _dist_xz(a: Vector3, b: Vector3) -> float:
	return WorldCoords3D.distance_xz(a, b)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.STRUCTURE:
			_structure()
		Phase.CAMERA_DAY:
			_camera_day()
		Phase.HIRE:
			_hire()
		Phase.TO_NIGHT:
			_to_night()
		Phase.CAMERA_NIGHT:
			_camera_night()
		Phase.SPAWN_WAIT:
			_spawn_wait()
		Phase.ZONE_XZ_CHECK:
			_zone_xz_check()
		Phase.FOCUS_ARM:
			_focus_arm()
		Phase.FOCUS_PICK:
			_focus_pick()
		Phase.FOCUS_PRIORITY:
			_focus_priority()
		Phase.FOCUS_CANCEL:
			_focus_cancel()
		Phase.REGROUP_CMD:
			_regroup_cmd()
		Phase.REGROUP_OBSERVE:
			_observe_move_toward(_defense_goal_of, Phase.RETREAT_CMD, "REGROUP")
		Phase.RETREAT_CMD:
			_retreat_cmd()
		Phase.RETREAT_PRIORITY:
			_retreat_priority()
		Phase.RETREAT_OBSERVE:
			_retreat_observe()
		Phase.ZONE_CHANGE_CMD:
			_zone_change_cmd()
		Phase.ZONE_CHANGE_OBSERVE:
			_zone_change_observe()
		Phase.GATE_ARM:
			_gate_arm()
		Phase.GATE_CMD:
			_gate_cmd()
		Phase.TIME_CMD:
			_time_cmd()
		Phase.TO_DAY:
			_to_day()
		Phase.DAY_CLEANUP:
			_day_cleanup()
		Phase.FREE_MANUALS:
			_free_manuals()
		Phase.REPEAT_NIGHT_WAIT:
			_repeat_night_wait()
		Phase.REPEAT_NIGHT_CHECK:
			_repeat_night_check()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			_finish()
			return true
	if _frame > 20000:
		print("TASK3DCMB0012_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_game_time = root.get_node_or_null("GameTime")
	_ledger = root.get_node_or_null("DeathLedger")
	_check(_world != null, "3D world loads")
	_check(_game_time != null and _ledger != null,
		"GameTime/DeathLedger autoloads available to the 3D tactical runtime")
	if _world == null or _game_time == null or _ledger == null:
		_finish()
		return
	_game_time.set_auto_advance(false)
	_game_time.set_durations(2.0, 1.0)
	_nav_manager = load("res://scripts/navigation_manager_3d.gd").new()
	_nav_manager.name = "NavManager"
	_world.add_child(_nav_manager)
	var cam_scene: Node = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	cam_scene.name = "CameraController"
	root.add_child(cam_scene)
	_roster = load("res://scripts/mercenary_roster_3d.gd").new()
	_roster.name = "MercenaryRoster3D"
	root.add_child(_roster)
	_spawner = load("res://scripts/first_encounter_spawner_3d.gd").new()
	_spawner.name = "FirstEncounterSpawner3D"
	root.add_child(_spawner)
	var tac_scene: Node = (load("res://ui/tactical_command_ui_3d.tscn") as PackedScene).instantiate()
	tac_scene.name = "TacticalCommandUI3D"
	root.add_child(tac_scene)
	_cam_ctl = get_first_node_in_group("camera_controller_3d")
	_tac = get_first_node_in_group("tactical_command_ui_3d")
	# autoload 등록이 끝난 뒤 런타임 로드한다(정적 참조 금지, 상단 "주의" 참고).
	# 명령 코드 단일 소스는 기존 2D TacticalCommandUI.Command다.
	_roster_script = load("res://scripts/mercenary_roster_3d.gd")
	_cmd_ui = load("res://scripts/tactical_command_ui.gd")
	_enter(Phase.STRUCTURE)


## -- STRUCTURE: 신규 wiring 파일 구조 / UI Control 계층 / 명령 코드 계약 --
func _structure() -> void:
	_check(_cam_ctl != null, "Foundation CameraController3D is part of the tactical runtime")
	_check(_tac != null, "TacticalCommandUI3D scene instantiates")
	if _tac != null:
		_check(_tac is Control, "tactical UI stays in the Control layer (never a 3D node)")
		_check(_tac.name == StringName("TacticalCommandUI3D"),
			"3D tactical UI keeps its own scene identity")
	var roster_ok: bool = _roster_script != null \
		and _roster.is_in_group("mercenary_roster_3d") \
		and _roster.get_script() == _roster_script
	_check(roster_ok, "3D roster script attaches and joins mercenary_roster_3d group")
	var legacy_radius: float = _roster_script.FOCUS_PICK_RADIUS
	_check(_near(legacy_radius, 32.0 * WorldCoords3D.PX_TO_UNIT),
		"focus pick radius preserves legacy 32px scaled by PX_TO_UNIT")
	var commands := [
		_cmd_ui.Command.DEFENSE_ZONE, _cmd_ui.Command.REGROUP,
		_cmd_ui.Command.RETREAT, _cmd_ui.Command.FOCUS_TARGET,
		_cmd_ui.Command.GATE_OPEN, _cmd_ui.Command.GATE_CLOSE,
		_cmd_ui.Command.TIME_PAUSE, _cmd_ui.Command.TIME_1X,
		_cmd_ui.Command.TIME_2X,
	]
	var ordered := true
	for i in commands.size():
		if commands[i] != i:
			ordered = false
	_check(ordered,
		"3D wiring reuses the legacy TacticalCommandUI.Command codes unchanged")
	_check(_tac.command_issued.is_connected(_roster._on_tactical_command),
		"UI command_issued is wired to the 3D roster (guarded single connect)")
	_check(_tac.visible == false, "tactical UI stays hidden during DAY")
	_enter(Phase.CAMERA_DAY)


## -- CAMERA_DAY: Foundation 카메라의 DAY policy 스냅샷 --
func _camera_day() -> void:
	_check(_cam_ctl.is_night_mode() == false, "camera starts in DAY management mode")
	_check(_near(_cam_ctl.get_zoom_target(), _cam_ctl.day_zoom),
		"DAY zoom target follows the foundation day policy")
	_camera_basis = (_cam_ctl.get_camera() as Camera3D).global_transform
	_enter(Phase.HIRE)


## -- HIRE: 용병 데이터 등록(전투 관찰 내내 생존하도록 prototype보다 큰 HP).
## NIGHT 진입 전에 등록해야 phase_changed 핸들러가 이들을 spawn 대상으로 본다.
func _hire() -> void:
	_data_north = MercenaryData.new("m_north", "Garrick")
	_data_north.defense_zone = MercenaryData.DefenseZone.NORTH
	_data_north.max_hp = 100000
	_data_north.attack_damage = 10
	_data_north.attack_interval = 1.0
	_data_north.move_speed = 120.0
	_data_west = MercenaryData.new("m_west", "Bram")
	_data_west.defense_zone = MercenaryData.DefenseZone.WEST
	_data_west.max_hp = 100000
	_data_west.attack_damage = 10
	_data_west.attack_interval = 1.0
	_data_west.move_speed = 120.0
	_check(_roster.add_mercenary(_data_north), "north zone mercenary hired")
	_check(_roster.add_mercenary(_data_west), "west zone mercenary hired")
	_check(_roster.get_count() == 2 and _roster.get_alive_count() == 2,
		"roster holds both living hires")
	_spawner.set_count(1)
	_enter(Phase.TO_NIGHT)


func _to_night() -> void:
	_game_time.advance(_game_time.day_duration)
	_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase advanced to NIGHT")
	_enter(Phase.CAMERA_NIGHT)


## -- CAMERA_NIGHT: DAY/NIGHT policy 확장 + rotation 없음 --
func _camera_night() -> void:
	_check(_cam_ctl.is_night_mode(), "camera switches to the NIGHT tactical policy")
	_check(_near(_cam_ctl.get_zoom_target(), _cam_ctl.night_zoom),
		"NIGHT zoom target applies the tactical overview policy")
	_check((_cam_ctl.get_camera() as Camera3D).global_transform.basis \
			== _camera_basis.basis,
		"phase switch applies no camera rotation (fixed oblique basis)")
	_check(_near((_cam_ctl as Node3D).position.y, WorldCoords3D.GROUND_Y),
		"camera pivot stays height-locked on the ground plane")
	_check(_tac.visible, "tactical command UI becomes visible on NIGHT")
	_enter(Phase.SPAWN_WAIT)


## -- SPAWN_WAIT: NIGHT spawn 수렴(용병 rally 배치 + spawner encounter).
## spawn은 advance() 안에서 동기 실행되므로 settle 후 1회만 판정한다.
func _spawn_wait() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES + NAV_SYNC_FRAMES:
		return
	_wait = 0
	_merc_north = _roster.get_actor("m_north")
	_merc_west = _roster.get_actor("m_west")
	var spawned_ok: bool = _merc_north != null and _merc_west != null \
		and _roster.get_actor_count() == 2 and _group_count("mercenaries_3d") == 2 \
		and _spawner.is_night_active() and _spawner.get_enemy_count() == 1 \
		and _group_count("enemies_3d") >= 1
	_check(spawned_ok,
		"NIGHT start spawns both assigned mercenaries and the encounter")
	if not spawned_ok:
		_enter(Phase.ZONE_XZ_CHECK)
		return
	_check((_merc_north as Node3D).position.distance_to(NORTH_RALLY) < 0.01
		and (_merc_north as MercenaryActor3D).defense_point.distance_to(NORTH_RALLY) < 0.01,
		"north mercenary spawns at the defense zone rally in world XZ")
	_check((_merc_west as Node3D).position.distance_to(WEST_RALLY) < 0.01
		and (_merc_west as MercenaryActor3D).defense_point.distance_to(WEST_RALLY) < 0.01,
		"west mercenary spawns at the defense zone rally in world XZ")
	_ledger_before_day = _ledger.get_all_records().size()
	_enter(Phase.ZONE_XZ_CHECK)


## -- ZONE_XZ_CHECK: Defense Zone 위치/범위의 XZ 단일 해석 --
func _zone_xz_check() -> void:
	var expected := {
		MercenaryData.DefenseZone.NORTH: NORTH_RALLY,
		MercenaryData.DefenseZone.EAST: EAST_RALLY,
		MercenaryData.DefenseZone.SOUTH: SOUTH_RALLY,
		MercenaryData.DefenseZone.WEST: WEST_RALLY,
	}
	var all_match := true
	for zone in expected:
		var rally: Vector3 = _roster.get_rally_point_for_zone(zone, _world)
		if rally.distance_to(expected[zone]) > 0.001 or rally.y != WorldCoords3D.GROUND_Y:
			all_match = false
	_check(all_match,
		"every defense zone rally resolves to the WorldMap rally space center in XZ")
	var safe: Vector3 = _roster.get_safe_rally(_world)
	_check(safe.distance_to(Vector3.ZERO) < 0.001 and safe.y == WorldCoords3D.GROUND_Y,
		"retreat safe rally is the settlement clearing center on the ground plane")
	var spawn_point: Vector3 = _spawner.get_spawn_world_point(
		_spawner.get_direction(), _world)
	var expected_spawn := WorldCoords3D.to_world_xz(
		WorldMap.SPAWN_CANDIDATES[_spawner.get_direction()])
	_check(spawn_point == expected_spawn,
		"encounter spawn point preserves the logical spawn candidate in world XZ")
	var route: Array[Vector3] = _spawner.build_route_waypoints(
		_spawner.get_direction(), spawn_point, _world)
	var axis: Vector3 = _spawner.DIRECTION_AXIS_XZ[_spawner.get_direction()]
	var inward: bool = not route.is_empty()
	for p in route:
		if (p - spawn_point).dot(axis) <= 0.0:
			inward = false
	_check(inward,
		"encounter route keeps only inward main-road waypoints in world XZ")
	_enter(Phase.FOCUS_ARM)


## -- FOCUS_ARM: 테스트 제어용 Enemy 배치 + UI 명령으로 focus mode 진입 --
func _make_stationary_enemy(id: String, pos: Vector3) -> Node:
	var enemy := (load("res://scenes/enemy_3d.tscn") as PackedScene).instantiate() as EnemyActor3D
	enemy.setup(id, "Raider", "north")
	enemy.max_hp = 100000
	enemy.position = pos
	_world.add_child(enemy)
	enemy.set_route([], pos)
	return enemy


func _focus_arm() -> void:
	_focus_enemy = _make_stationary_enemy("enemy_focus_pick", FOCUS_ENEMY_POS)
	_zone_enemy = _make_stationary_enemy("enemy_zone_guard", ZONE_ENEMY_POS)
	_tac._emit_command(_cmd_ui.Command.FOCUS_TARGET, 0)
	_check(_roster.focus_mode, "FOCUS_TARGET command toggles focus mode on")
	_enter(Phase.FOCUS_PICK)


## -- FOCUS_PICK: Foundation 카메라 광선 지면 교차점 기반 선택.
## 같은 프레임에 focus를 지정한다. 대기 사이클을 사이에 두면 북쪽 용병이 그 사이
## 근접 zone enemy를 자동 교전해 우선순위 판정이 오염된다.
func _focus_pick() -> void:
	var camera := _cam_ctl.get_camera() as Camera3D
	var screen_pos := camera.unproject_position(
		(_focus_enemy as Node3D).global_position)
	var picked: Node = _roster.pick_focus_target_at(screen_pos)
	_check(picked == _focus_enemy,
		"ray-based ground point picks the nearest living enemy under the click")
	_roster.set_focus_target(picked)
	_check(_roster.has_focus_target() and _roster.get_focus_target() == _focus_enemy,
		"selected enemy becomes the roster focus target")
	_check((_merc_north as MercenaryActor3D).get_focus_target() == _focus_enemy
		and (_merc_west as MercenaryActor3D).get_focus_target() == _focus_enemy,
		"focus target propagates to every spawned mercenary actor")
	var empty_ground := camera.unproject_position(Vector3(120, 0, 150))
	_check(_roster.pick_focus_target_at(empty_ground) == null,
		"clicking empty ground picks nothing and keeps the mode armed")
	_check(_roster.has_focus_target(),
		"empty pick leaves an existing focus target untouched")
	_enter(Phase.FOCUS_PRIORITY)


## -- FOCUS_PRIORITY: FOCUS > 근접 zone enemy 우선순위 --
func _focus_priority() -> void:
	_wait += 1
	var chasing: bool = (_merc_north as MercenaryActor3D).is_focusing()
	if not chasing and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(chasing,
		"focused mercenary prioritizes the focus target over closer zone combat")
	_check((_zone_enemy as EnemyActor3D).current_hp == (_zone_enemy as EnemyActor3D).max_hp,
		"closer zone enemy stays ignored while the focus target lives")
	_enter(Phase.FOCUS_CANCEL)


func _focus_cancel() -> void:
	_roster.toggle_focus_mode()
	_check(_roster.focus_mode == false and _roster.focus_target == null,
		"cancelling focus mode releases the focus target")
	_check((_merc_north as MercenaryActor3D).get_focus_target() == null,
		"actors drop the focus target when the mode is cancelled")
	_enter(Phase.REGROUP_CMD)


## -- REGROUP: 명령이 실제 FSM/이동에 반영 --
func _regroup_cmd() -> void:
	(_merc_north as MercenaryActor3D).regroup()
	(_merc_west as MercenaryActor3D).regroup()
	_check((_merc_north as MercenaryActor3D).state
		== MercenaryActor3D.MercState.REGROUP
		and (_merc_west as MercenaryActor3D).state
		== MercenaryActor3D.MercState.REGROUP,
		"REGROUP command drives both actors into the REGROUP state")
	_enter(Phase.REGROUP_OBSERVE)


## REGROUP 관찰기용 목적지: 각 actor의 현재 방어 구역 rally.
func _defense_goal_of(actor: Node) -> Vector3:
	return (actor as MercenaryActor3D).defense_point


## 공통 관찰기: 두 actor가 goal_of(actor) 지점에 도달할 때까지 bounded 대기한다.
## label은 성공/실패 메시지 구분용이다.
func _observe_move_toward(goal_of: Callable, next_phase: int, label: String) -> void:
	_wait += 1
	var progressed := true
	for actor in [_merc_north, _merc_west]:
		if actor == null or not is_instance_valid(actor):
			progressed = false
			continue
		var goal: Vector3 = goal_of.call(actor)
		var remaining := _dist_xz((actor as Node3D).global_position, goal)
		if remaining > (actor as MercenaryActor3D).REACH_DISTANCE:
			progressed = false
	if progressed:
		_wait = 0
		_check(true, "%s observation: actors reach their commanded goal without teleporting"
			% label)
		_enter(next_phase)
		return
	if _wait > OBSERVE_BUDGET * 3:
		_check(false, "%s observation: actors failed to reach the commanded goal in time"
			% label)
		_enter(next_phase)


func _retreat_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.RETREAT, 0)
	var retreat_point: Vector3 = (_merc_north as MercenaryActor3D).get_retreat_point()
	_check((_merc_north as MercenaryActor3D).state == MercenaryActor3D.MercState.RETREAT
		and (_merc_west as MercenaryActor3D).state == MercenaryActor3D.MercState.RETREAT,
		"RETREAT command drives both actors into the RETREAT state")
	_check(retreat_point.distance_to(_roster.get_safe_rally(_world)) < 0.001,
		"RETREAT aims at the settlement safe rally in world XZ")
	_enter(Phase.RETREAT_PRIORITY)


## -- RETREAT 중 focus 지정: 즉시 전환 금지(command priority 기존 규칙) --
func _retreat_priority() -> void:
	_lure_enemy = _make_stationary_enemy("enemy_east_lure",
		EAST_RALLY + LURE_ENEMY_OFFSET)
	_roster.set_focus_target(_lure_enemy)
	_check((_merc_north as MercenaryActor3D).state == MercenaryActor3D.MercState.RETREAT
		and (_merc_west as MercenaryActor3D).state == MercenaryActor3D.MercState.RETREAT,
		"arming focus during RETREAT never interrupts the retreat")
	_check((_lure_enemy as EnemyActor3D).current_hp == (_lure_enemy as EnemyActor3D).max_hp,
		"retreating mercenaries do not attack the newly armed focus target")
	_enter(Phase.RETREAT_OBSERVE)


func _retreat_observe() -> void:
	_wait += 1
	var settled := true
	for actor in [_merc_north, _merc_west]:
		var body := actor as MercenaryActor3D
		if _dist_xz(body.global_position, body.get_retreat_point()) \
				> body.REACH_DISTANCE + 0.5:
			settled = false
	if settled:
		_wait = 0
		_check(true, "mercenaries complete the retreat at the safe rally and hold")
		_check((_merc_north as MercenaryActor3D).state
				== MercenaryActor3D.MercState.RETREAT,
			"retreated mercenaries hold position instead of resuming the hunt")
		_enter(Phase.ZONE_CHANGE_CMD)
		return
	if _wait > OBSERVE_BUDGET * 3:
		_check(false, "retreat did not converge at the safe rally in time")
		_enter(Phase.ZONE_CHANGE_CMD)


## -- DEFENSE_ZONE 명령: 데이터/rally 갱신 + 일반 방어 AI 복귀 --
func _zone_change_cmd() -> void:
	var pos_before := (_merc_north as Node3D).global_position
	_tac._emit_command(_cmd_ui.Command.DEFENSE_ZONE,
		MercenaryData.DefenseZone.EAST)
	_check(_data_north.defense_zone == MercenaryData.DefenseZone.EAST
		and _data_west.defense_zone == MercenaryData.DefenseZone.EAST,
		"DEFENSE_ZONE command updates every living mercenary's zone data")
	_check((_merc_north as MercenaryActor3D).defense_point.distance_to(EAST_RALLY) < 0.001
		and (_merc_west as MercenaryActor3D).defense_point.distance_to(EAST_RALLY) < 0.001,
		"zone command re-anchors both actors to the new XZ rally")
	_check((_merc_north as Node3D).global_position == pos_before,
		"zone change never teleports actors")
	var leaving: bool = (_merc_north as MercenaryActor3D).state \
		!= MercenaryActor3D.MercState.RETREAT
	_check(leaving, "zone command pulls retreated mercenaries back into defense AI")
	_enter(Phase.ZONE_CHANGE_OBSERVE)


func _zone_change_observe() -> void:
	_wait += 1
	var engaging: bool = (_merc_north as MercenaryActor3D).is_focusing() \
		or (_merc_west as MercenaryActor3D).is_focusing()
	if not engaging and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(engaging,
		"after the zone command the armed focus target is engaged by defense AI")
	_enter(Phase.GATE_ARM)


## -- GATE_ARM/GATE_CMD: gates_3d duck-typing 명령 계약 --
class MockGate3D extends Node3D:
	signal gate_state_changed(gate: Node, open: bool)

	var closed := true
	var breached := false

	func is_closed() -> bool:
		return closed and not breached

	func is_open() -> bool:
		return (not closed) or breached

	func is_breached() -> bool:
		return breached

	func get_direction() -> String:
		return "east"

	func set_open(open: bool) -> void:
		if breached:
			return
		if closed == (not open):
			return
		closed = not open
		gate_state_changed.emit(self, is_open())


var _gate: MockGate3D = null


func _gate_arm() -> void:
	# 반복 진입 시 mock 중복 생성 금지(001-1 테스트와 동일한 null guard 규약).
	# 목록 재생성(_refresh_gates)도 생성 프레임에 1회만 호출한다. 반복 호출하면
	# queue_free된 이전 행이 프레임 끝까지 남아 child_count 판정이 오염된다.
	if _gate == null:
		_gate = MockGate3D.new()
		_gate.name = "GateMockEast"
		_gate.position = Vector3(46, 0, 0)
		_world.add_child(_gate)
		_gate.add_to_group("gates_3d")
		_tac._refresh_gates()
	_wait += 1
	if _wait < 6:
		return
	_wait = 0
	var rows := (_tac.get_node("%GateList") as VBoxContainer).get_child_count()
	_check(rows == 1, "tactical UI lists installed gates_3d entries")
	_enter(Phase.GATE_CMD)


func _gate_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.GATE_OPEN, _gate)
	_check(_gate.is_open() and not _gate.is_closed(),
		"GATE_OPEN command opens the world gate through the 3D contract")
	_tac._emit_command(_cmd_ui.Command.GATE_CLOSE, _gate)
	_check(_gate.is_closed(), "GATE_CLOSE command closes the world gate again")
	_gate.closed = false
	_gate.breached = true
	_tac._emit_command(_cmd_ui.Command.GATE_CLOSE, _gate)
	_check(_gate.is_breached() and _gate.is_open(),
		"BREACHED gate ignores close commands (no auto recovery)")
	_enter(Phase.TIME_CMD)


## -- TIME 명령: 전술 시간 배율 --
func _time_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.TIME_PAUSE, 0)
	var paused: bool = _game_time.get_time_scale() == GameTime.TIME_SCALE_PAUSE
	_tac._emit_command(_cmd_ui.Command.TIME_2X, 0)
	var doubled: bool = _game_time.get_time_scale() == GameTime.TIME_SCALE_2X
	_tac._emit_command(_cmd_ui.Command.TIME_1X, 0)
	var normal: bool = _game_time.get_time_scale() == GameTime.TIME_SCALE_1X
	_check(paused, "TIME_PAUSE command sets the tactical pause scale")
	_check(doubled, "TIME_2X command doubles the tactical time scale")
	_check(normal, "TIME_1X command restores the tactical time scale")
	_enter(Phase.TO_DAY)


func _to_day() -> void:
	_ledger_before_day = _ledger.get_all_records().size()
	_game_time.advance(_game_time.night_duration)
	_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase returned to DAY")
	_enter(Phase.DAY_CLEANUP)


## -- DAY_CLEANUP: tactical transient state 정리 --
func _day_cleanup() -> void:
	_check(_group_count("mercenaries_3d") == 0 and _roster.get_actor_count() == 0,
		"DAY return despawns every spawned mercenary actor")
	_check(_spawner.get_enemy_count() == 0 and not _spawner.is_night_active(),
		"DAY return despawns the whole encounter")
	_check(not is_instance_valid(_merc_north) and not is_instance_valid(_merc_west),
		"despawned actor references are freed (no stale roster references)")
	_check(_roster.focus_mode == false and _roster.focus_target == null,
		"DAY return clears the focus mode/target transient state")
	_check(_tac.visible == false, "tactical UI hides again on DAY return")
	_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X,
		"DAY return restores the 1x time scale")
	_check(_cam_ctl.is_night_mode() == false
		and _near(_cam_ctl.get_zoom_target(), _cam_ctl.day_zoom),
		"camera policy returns to the DAY zoom target")
	_check((_cam_ctl.get_camera() as Camera3D).global_transform.basis
			== _camera_basis.basis,
		"full cycle applied no camera rotation")
	_check(_ledger.get_all_records().size() == _ledger_before_day,
		"cleanup/despawn around DAY return creates no death records")
	_enter(Phase.FREE_MANUALS)


func _free_manuals() -> void:
	for enemy in [_focus_enemy, _zone_enemy, _lure_enemy]:
		if enemy != null and is_instance_valid(enemy):
			enemy.queue_free()
	_wait += 1
	if _wait < 4:
		return
	_wait = 0
	_check(_group_count("enemies_3d") == 0,
		"test-controlled enemies leave no residue in enemies_3d")
	_enter(Phase.REPEAT_NIGHT_WAIT)


func _repeat_night_wait() -> void:
	if _wait == 0:
		_game_time.advance(_game_time.day_duration)
		_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "next NIGHT begins")
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_enter(Phase.REPEAT_NIGHT_CHECK)


func _repeat_night_check() -> void:
	var north_again: Node = _roster.get_actor("m_north")
	var west_again: Node = _roster.get_actor("m_west")
	_check(north_again != null and west_again != null
		and north_again != _merc_north and west_again != _merc_west,
		"repeated NIGHT spawns fresh actors (no duplicate id reuse)")
	_check(_roster.get_actor_count() == _roster.get_alive_count(),
		"repeated NIGHT spawns exactly the living roster")
	_check(_spawner.get_enemy_count() == 1,
		"repeated NIGHT spawns a fresh encounter after DAY despawn")
	_enter(Phase.CLEANUP)


## -- CLEANUP: 잔여 reference/orphan 정리 검증 --
func _cleanup() -> void:
	for actor in [_roster.get_actor("m_north"), _roster.get_actor("m_west")]:
		if actor != null and is_instance_valid(actor):
			actor.free()
	for enemy in _spawner.get_enemies():
		if is_instance_valid(enemy):
			enemy.free()
	if is_instance_valid(_gate):
		_gate.free()
	_wait += 1
	if _wait < 4:
		return
	_check(_group_count("mercenaries_3d") == 0, "no orphan mercenaries remain")
	_check(_group_count("enemies_3d") == 0, "no orphan enemies remain")
	_check(_group_count("gates_3d") == 0, "mock gate leaves no residue")
	_finish()
