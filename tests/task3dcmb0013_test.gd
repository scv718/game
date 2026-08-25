extends SceneTree

## TASK-3D-CMB-001-3 Combat / Death Ledger Regression 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 큐 시나리오 전체를 3D Runtime Actor 위에서 순서대로 재생한다:
##   용병 배치 → NIGHT → Enemy 조우 → 자동전투 → Focus Target → Regroup →
##   Retreat → Gate Open/Close → Pause → 2x → lethal death → Death Ledger 확인 →
##   DAY → 다음 NIGHT 반복.
##
## 검증 항목(큐 "검증" 대응):
##   1. Player combat 없음: enemies_3d는 mercenaries_3d만 target으로 삼고,
##     월드에 배치한 player 모형 노드는 끝까지 무대상/무피격/무변경이다.
##   2. duplicate death record 없음: 같은 실제 죽음의 source_uid record는 정확히 1개.
##   3. cleanup record 없음: DAY despawn/수동 queue_free/free 정리 경로는
##     DeathLedger에 record를 만들지 않는다.
##   4. freed reference 없음: 사망/despawn 직후 roster/spawner/focus 참조가 즉시
##     정리되어 stale reference가 남지 않는다.
##   5. Gate/nav stale state 없음: CLOSED 성문 교전(GATE_ATTACK) 중 GATE_OPEN 명령으로
##     bounded 시간 안에 상태를 벗어나 경로를 재개한다(영구 gate lock 금지).
##   6. command deadlock 없음: Pause 중에도 명령이 먹고, 반복 NIGHT 이후 명령이
##     다시 응답하며, 모든 관찰 루프는 budget으로 bounded다.
##
## 전투 결정성 규약(001-2 관례 계승): 이동하는 encounter는 chase leash 밖
## village core에서 HOLD로 종료할 수 있으므로(기존 설계 동작, 회귀 대상 아님),
## 확정 kill 검증은 rally 근처 고정 fixture(decoy/bait)로 수행하고 ledger 일관성은
## "관측된 died signal 총횟수 == ledger 증가량" 대응으로 닫는다. 이 규약 아래
## fixture 생존/사망이 어느 쪽이든 ledger 정합성 검증은 성립한다.
##
## 주의: 이 테스트가 정적으로 참조하는 클래스는 autoload를 참조하지 않는 스크립트뿐이다
## (WorldCoords3D/MercenaryData/MercenaryActor3D/EnemyActor3D/DeathRecord/GameTime 등).
## mercenary_roster_3d.gd와 tactical_command_ui 계열은 bare autoload를 참조하므로
## -s 기동 초기 컴파일 단계에서 정적 참조하면 컴파일이 파괴된다. 해당 스크립트와
## 명령 코드는 반드시 런타임 load() + duck-typing으로만 접근한다(001-2 규약).

enum Phase {
	SETUP, STRUCTURE, HIRE, TO_NIGHT,
	SPAWN_WAIT, AUTO_COMBAT_WAIT,
	FOCUS_CMD, FOCUS_OBSERVE,
	REGROUP_CMD, REGROUP_KILL_WAIT,
	RETREAT_CMD, RETREAT_OBSERVE, SOUTH_RETURN_WAIT,
	GATE_ARM, GATE_ENGAGE_WAIT, GATE_OPEN_CMD, GATE_CROSS_WAIT, GATE_PROBE_FREE,
	GATE_CLOSE_CMD,
	TIME_PAUSE_CMD, TIME_PAUSE_HOLD, TIME_2X_CMD, TIME_1X_CMD,
	LETHAL_ARM, LETHAL_WAIT, LEDGER_CHECK,
	TO_DAY, DAY_CLEANUP, FREE_FIXTURES,
	REPEAT_NIGHT_WAIT, REPEAT_NIGHT_CHECK, REPEAT_CMD_CHECK,
	CLEANUP, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 12
const OBSERVE_BUDGET := 900

## WorldMap.RALLY_SPACES의 XZ 해석값(테스트 기준값). rect 중심 * PX_TO_UNIT.
const NORTH_RALLY := Vector3(0.0, 0.0, -305.0 * WorldCoords3D.PX_TO_UNIT)
const WEST_RALLY := Vector3(-305.0 * WorldCoords3D.PX_TO_UNIT, 0.0, 0.0)
const SOUTH_RALLY := Vector3(0.0, 0.0, 305.0 * WorldCoords3D.PX_TO_UNIT)

## 자동전투 결정화 fixture 배치(west rally 기준).
## decoy가 더 가까워 자동전투 1차 target이 되고, bait는 focus 전환 대상이다.
const DECOY_OFFSET := Vector3(2.0, 0.0, -2.0)
const BAIT_OFFSET := Vector3(6.0, 0.0, 3.0)
## player combat 없음 검증용 모형 배치(자동전투 접근 축선 위).
const PLAYER_POS := Vector3(-34.0, 0.0, 0.0)
## south 치명타 fixture(south rally 기준). m_south와 즉시 교전한다.
const KILLER_OFFSET := Vector3(2.0, 0.0, 1.0)
## gate stale 검증용 mock 성문과 probe enemy(probe는 성문 서쪽에서 동쪽 경로).
const GATE_POS := Vector3(-50.0, 0.0, 0.0)
const PROBE_POS := Vector3(-54.0, 0.0, 0.0)
const PROBE_ROUTE_POINT := Vector3(-30.0, 0.0, 0.0)
const GATE_CROSS_MARGIN := 1.0

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _game_time: Node = null
var _ledger: Node = null
var _cam_ctl: Node = null
var _camera_basis := Transform3D()
var _roster: Node = null
var _spawner: Node = null
var _tac: Node = null
## 명령 코드/상수 참조는 전부 런타임 load()로 한다(상단 "주의" 참고).
var _cmd_ui: Script = null

var _data_north: MercenaryData = null
var _data_west: MercenaryData = null
var _data_south: MercenaryData = null
var _merc_north: Node = null
var _merc_west: Node = null
var _merc_south: Node = null
var _decoy: Node = null
var _bait: Node = null
var _killer: Node = null
var _probe: Node = null
var _gate: MockGate3D = null
var _player_mock: Node3D = null
var _encounter: Node = null

## 관측된 실제 죽음(died signal) 총횟수. ledger 증가량과 정확히 대응해야 한다.
var _deaths_total := 0
var _ledger_baseline := -1
var _decoy_hp_at_focus := -1


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
	print("TASK3DCMB0013_RESULT=" + ("FAIL" if _failed else "PASS"))
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
		Phase.HIRE:
			_hire()
		Phase.TO_NIGHT:
			_to_night()
		Phase.SPAWN_WAIT:
			_spawn_wait()
		Phase.AUTO_COMBAT_WAIT:
			_auto_combat_wait()
		Phase.FOCUS_CMD:
			_focus_cmd()
		Phase.FOCUS_OBSERVE:
			_focus_observe()
		Phase.REGROUP_CMD:
			_regroup_cmd()
		Phase.REGROUP_KILL_WAIT:
			_regroup_kill_wait()
		Phase.RETREAT_CMD:
			_retreat_cmd()
		Phase.RETREAT_OBSERVE:
			_retreat_observe()
		Phase.SOUTH_RETURN_WAIT:
			_south_return_wait()
		Phase.GATE_ARM:
			_gate_arm()
		Phase.GATE_ENGAGE_WAIT:
			_gate_engage_wait()
		Phase.GATE_OPEN_CMD:
			_gate_open_cmd()
		Phase.GATE_CROSS_WAIT:
			_gate_cross_wait()
		Phase.GATE_PROBE_FREE:
			_gate_probe_free()
		Phase.GATE_CLOSE_CMD:
			_gate_close_cmd()
		Phase.TIME_PAUSE_CMD:
			_time_pause_cmd()
		Phase.TIME_PAUSE_HOLD:
			_time_pause_hold()
		Phase.TIME_2X_CMD:
			_time_2x_cmd()
		Phase.TIME_1X_CMD:
			_time_1x_cmd()
		Phase.LETHAL_ARM:
			_lethal_arm()
		Phase.LETHAL_WAIT:
			_lethal_wait()
		Phase.LEDGER_CHECK:
			_ledger_check()
		Phase.TO_DAY:
			_to_day()
		Phase.DAY_CLEANUP:
			_day_cleanup()
		Phase.FREE_FIXTURES:
			_free_fixtures()
		Phase.REPEAT_NIGHT_WAIT:
			_repeat_night_wait()
		Phase.REPEAT_NIGHT_CHECK:
			_repeat_night_check()
		Phase.REPEAT_CMD_CHECK:
			_repeat_cmd_check()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			_finish()
			return true
	if _frame > 20000:
		print("TASK3DCMB0013_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	# 기동 직후 첫 frame부터 autoload의 자동 진행을 꺼서 테스트 주입 시간 외의
	# _elapsed 오염(기동 frame 누적)을 차단한다. 아직 미등록이면 SETUP에서 다시 끈다.
	var gt := root.get_node_or_null("GameTime")
	if gt != null:
		gt.set_auto_advance(false)
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
		"GameTime/DeathLedger autoloads available to the regression run")
	if _world == null or _game_time == null or _ledger == null:
		_finish()
		return
	_game_time.set_auto_advance(false)
	_game_time.set_durations(2.0, 1.0)
	var nav_manager: Node = load("res://scripts/navigation_manager_3d.gd").new()
	nav_manager.name = "NavManager"
	_world.add_child(nav_manager)
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
	_cmd_ui = load("res://scripts/tactical_command_ui.gd")
	_enter(Phase.STRUCTURE)


## -- STRUCTURE: 시나리오 기반 구조/연결 확인 --
func _structure() -> void:
	_check(_cam_ctl != null, "Foundation CameraController3D is part of the runtime")
	_check(_tac != null and _tac is Control, "tactical UI stays in the Control layer")
	_check(_roster.is_in_group("mercenary_roster_3d"),
		"3D roster joins mercenary_roster_3d group")
	_check(_tac.command_issued.is_connected(_roster._on_tactical_command),
		"UI command_issued is wired to the 3D roster")
	_check(_tac.visible == false, "tactical UI stays hidden during DAY")
	_camera_basis = (_cam_ctl.get_camera() as Camera3D).global_transform
	_ledger_baseline = _ledger.get_all_records().size()
	_enter(Phase.HIRE)


## -- HIRE: 용병 배치(시나리오 1). north/west는 관찰 내내 생존, south는 치명타 검증용
## 가변 HP. NIGHT 진입 전 등록해야 phase_changed 핸들러의 spawn 대상이 된다.
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
	_data_south = MercenaryData.new("m_south", "Hale")
	_data_south.defense_zone = MercenaryData.DefenseZone.SOUTH
	_data_south.max_hp = 24
	_data_south.attack_damage = 10
	_data_south.attack_interval = 1.0
	_data_south.move_speed = 120.0
	_check(_roster.add_mercenary(_data_north), "north zone mercenary hired")
	_check(_roster.add_mercenary(_data_west), "west zone mercenary hired")
	_check(_roster.add_mercenary(_data_south), "south zone mercenary hired")
	_check(_roster.get_count() == 3 and _roster.get_alive_count() == 3,
		"roster holds all living hires before deployment")
	_spawner.set_count(1)
	_enter(Phase.TO_NIGHT)


func _to_night() -> void:
	_game_time.advance(_game_time.day_duration)
	_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase advanced to NIGHT")
	_check(_game_time.get_day_number() == 1, "first night keeps day number 1")
	_enter(Phase.SPAWN_WAIT)


## -- SPAWN_WAIT: NIGHT spawn 수렴(시나리오 2~3). spawn은 advance() 안에서 동기 실행. --
func _spawn_wait() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES + NAV_SYNC_FRAMES:
		return
	_wait = 0
	_merc_north = _roster.get_actor("m_north")
	_merc_west = _roster.get_actor("m_west")
	_merc_south = _roster.get_actor("m_south")
	var spawned_ok: bool = _merc_north != null and _merc_west != null \
		and _merc_south != null and _roster.get_actor_count() == 3 \
		and _group_count("mercenaries_3d") == 3 \
		and _spawner.is_night_active() and _spawner.get_enemy_count() == 1 \
		and _group_count("enemies_3d") >= 1
	_check(spawned_ok,
		"NIGHT start spawns all assigned mercenaries and the encounter")
	if not spawned_ok:
		_enter(Phase.LEDGER_CHECK)
		return
	for actor in [_merc_north, _merc_west, _merc_south]:
		(actor as Node).died.connect(_on_tracked_died)
	var enemies: Array[Node] = _spawner.get_enemies()
	if not enemies.is_empty():
		_encounter = enemies[0]
		(_encounter as Node).died.connect(_on_tracked_died)
	_check((_merc_north as Node3D).position.distance_to(NORTH_RALLY) < 0.01,
		"north mercenary spawns at the defense zone rally in world XZ")
	_check((_merc_west as Node3D).position.distance_to(WEST_RALLY) < 0.01,
		"west mercenary spawns at the defense zone rally in world XZ")
	_check((_merc_south as Node3D).position.distance_to(SOUTH_RALLY) < 0.01,
		"south mercenary spawns at the defense zone rally in world XZ")
	_player_mock = Node3D.new()
	_player_mock.name = "PlayerMock"
	_player_mock.position = PLAYER_POS
	_player_mock.add_to_group("player")
	_world.add_child(_player_mock)
	_decoy = _make_stationary_enemy("enemy_zone_decoy",
		WEST_RALLY + DECOY_OFFSET, 100000)
	_bait = _make_stationary_enemy("enemy_zone_bait",
		WEST_RALLY + BAIT_OFFSET, 60)
	_decoy.died.connect(_on_tracked_died)
	_bait.died.connect(_on_tracked_died)
	_enter(Phase.AUTO_COMBAT_WAIT)


func _make_stationary_enemy(id: String, pos: Vector3, hp: int) -> EnemyActor3D:
	var enemy := (load("res://scenes/enemy_3d.tscn") as PackedScene).instantiate() as EnemyActor3D
	enemy.setup(id, "Raider", "north")
	enemy.max_hp = hp
	enemy.position = pos
	_world.add_child(enemy)
	enemy.set_route([], pos)
	return enemy


## -- AUTO_COMBAT_WAIT: 자동전투 개시(시나리오 4). focus 명령 없이 defense zone
## 자동 AI가 최근접 decoy를 물어뜯기 시작하는지 관찰한다. --
func _auto_combat_wait() -> void:
	_wait += 1
	_poll_player_safe()
	var engaged: bool = (_decoy as EnemyActor3D).current_hp \
		< (_decoy as EnemyActor3D).max_hp
	if not engaged and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(engaged,
		"defense zone auto-combat engages the nearest zone enemy without commands")
	_check((_decoy as EnemyActor3D).current_hp == (_decoy as EnemyActor3D).max_hp \
			or (_bait as EnemyActor3D).current_hp == (_bait as EnemyActor3D).max_hp,
		"auto-combat picks exactly one target while unfocused")
	_check(_player_mock.is_in_group("player")
		and not _player_mock.is_in_group("mercenaries_3d")
		and not _player_mock.is_in_group("enemies_3d"),
		"player mock never joins a combat group")
	_enter(Phase.FOCUS_CMD)


## -- FOCUS_CMD: Focus Target 명령(시나리오 5). UI 토글 + 더 먼 bait 지정. --
func _focus_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.FOCUS_TARGET, 0)
	_check(_roster.focus_mode, "FOCUS_TARGET command toggles focus mode on")
	_roster.set_focus_target(_bait)
	_check(_roster.has_focus_target() and _roster.get_focus_target() == _bait,
		"the farther enemy becomes the roster focus target on demand")
	_decoy_hp_at_focus = (_decoy as EnemyActor3D).current_hp
	_enter(Phase.FOCUS_OBSERVE)


## -- FOCUS_OBSERVE: FOCUS > 근접 자동전투 우선순위 유지 확인. --
func _focus_observe() -> void:
	_wait += 1
	_poll_player_safe()
	var switched: bool = (_merc_west as MercenaryActor3D).is_focusing() \
		and (_merc_north as MercenaryActor3D).is_focusing()
	if not switched and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(switched, "both mercenaries switch to the focused enemy over zone combat")
	_check((_decoy as EnemyActor3D).current_hp == _decoy_hp_at_focus,
		"closer zone enemy stays ignored while the focus target lives")
	_enter(Phase.REGROUP_CMD)


## -- REGROUP_CMD / REGROUP_KILL_WAIT: Regroup(시나리오 6)과 이후 확정 kill. --
func _regroup_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.REGROUP, 0)
	_check((_merc_north as MercenaryActor3D).state
		== MercenaryActor3D.MercState.REGROUP
		and (_merc_west as MercenaryActor3D).state
		== MercenaryActor3D.MercState.REGROUP,
		"REGROUP command drives both actors into the REGROUP state")
	_enter(Phase.REGROUP_KILL_WAIT)


func _regroup_kill_wait() -> void:
	_wait += 1
	_poll_player_safe()
	if _deaths_total < 1 and _wait <= OBSERVE_BUDGET * 3:
		return
	_wait = 0
	if _deaths_total < 1:
		_check(false, "focused enemy did not die within the regroup observation budget")
		_enter(Phase.RETREAT_CMD)
		return
	_check(true, "regrouped mercenaries resume defense AI and kill the focus target")
	_check(_count_records_for("enemy_zone_bait") == 1,
		"lethal focus kill produces exactly one ENEMY ledger record (no duplicates)")
	var record := _record_for("enemy_zone_bait")
	if record != null:
		_check(record.source_kind == DeathRecord.SourceKind.ENEMY,
			"bait record kind is ENEMY")
		_check(record.death_phase == DeathRecord.DeathPhase.NIGHT,
			"bait death phase is NIGHT")
		_check(record.death_position is Vector2 and record.death_position != Vector2.ZERO,
			"bait record stores a nonzero logical death position")
	_check(_roster.focus_mode == false and _roster.focus_target == null,
		"roster auto-releases the focus transient state when the target dies")
	_check((_merc_west as MercenaryActor3D).get_focus_target() == null,
		"actors drop the cleared focus reference (no stale focus)")
	_enter(Phase.RETREAT_CMD)


## -- RETREAT(시나리오 7): safe rally 후퇴 + 도착 HOLD. --
func _retreat_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.RETREAT, 0)
	var retreat_point: Vector3 = (_merc_north as MercenaryActor3D).get_retreat_point()
	_check((_merc_north as MercenaryActor3D).state == MercenaryActor3D.MercState.RETREAT
		and (_merc_west as MercenaryActor3D).state == MercenaryActor3D.MercState.RETREAT,
		"RETREAT command drives both actors into the RETREAT state")
	_check(retreat_point.distance_to(_roster.get_safe_rally(_world)) < 0.001,
		"RETREAT aims at the settlement safe rally in world XZ")
	_enter(Phase.RETREAT_OBSERVE)


func _retreat_observe() -> void:
	_wait += 1
	_poll_player_safe()
	var settled := true
	for actor in [_merc_north, _merc_west]:
		var body := actor as MercenaryActor3D
		if _dist_xz(body.global_position, body.get_retreat_point()) \
				> body.REACH_DISTANCE + 0.5:
			settled = false
	if settled:
		_wait = 0
		_check((_merc_north as MercenaryActor3D).state
				== MercenaryActor3D.MercState.RETREAT,
			"retreated mercenaries hold at the safe rally instead of resuming the hunt")
		# 치명타 결정화: RETREAT 전역 명령도 따라간 south 용병을 actor 공개 계약
		# (set_defense_zone)으로 자기 진지로 복귀시킨다. core에 머무는 encounter는
		# 근접 대상에게만 정지 교전하므로(추격 없음) 복귀 동선이 오염되지 않는다.
		(_merc_south as MercenaryActor3D).set_defense_zone(
			MercenaryData.DefenseZone.SOUTH, SOUTH_RALLY)
		_enter(Phase.SOUTH_RETURN_WAIT)
		return
	if _wait > OBSERVE_BUDGET * 2:
		_check(false, "retreat did not converge at the safe rally in time")
		_enter(Phase.GATE_ARM)


## south 용병이 자기 방어 구역 rally로 복귀해 방어 AI로 돌아올 때까지 bounded 대기.
func _south_return_wait() -> void:
	_wait += 1
	_poll_player_safe()
	var body := _merc_south as MercenaryActor3D
	var returned: bool = body != null and is_instance_valid(body) \
		and body.state != MercenaryActor3D.MercState.RETREAT \
		and _dist_xz(body.global_position, SOUTH_RALLY) <= body.REACH_DISTANCE
	if not returned and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(returned,
		"zone re-defense command pulls the retreated mercenary back to his post")
	_enter(Phase.GATE_ARM)


## -- GATE(시나리오 8): CLOSED 성문 교전 → OPEN 명령 회복 → CLOSE 복원. --
class MockGate3D extends Node3D:
	signal gate_state_changed(gate: Node, open: bool)

	var closed := true
	var breached := false
	var hp := 500

	func is_closed() -> bool:
		return closed and not breached

	func is_open() -> bool:
		return (not closed) or breached

	func is_breached() -> bool:
		return breached

	func get_direction() -> String:
		return "west"

	func set_open(open: bool) -> void:
		if breached:
			return
		if closed == (not open):
			return
		closed = not open
		gate_state_changed.emit(self, is_open())

	func take_damage(amount: int) -> void:
		hp -= amount


func _gate_arm() -> void:
	if _gate == null:
		_gate = MockGate3D.new()
		_gate.name = "GateMockWest"
		_gate.position = GATE_POS
		_world.add_child(_gate)
		_gate.add_to_group("gates_3d")
		_probe = _make_stationary_enemy("enemy_gate_probe", PROBE_POS, 100000)
		_probe.set_route([PROBE_ROUTE_POINT], Vector3.ZERO)
		_probe.died.connect(_on_tracked_died)
	_enter(Phase.GATE_ENGAGE_WAIT)


func _gate_engage_wait() -> void:
	_wait += 1
	_poll_player_safe()
	var attacking: bool = (_probe as EnemyActor3D).state \
		== EnemyActor3D.EnemyState.GATE_ATTACK and (_gate as MockGate3D).hp < 500
	if not attacking and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(attacking,
		"closed gate inside detection range draws GATE_ATTACK from the route runner")
	_check((_probe as EnemyActor3D).get_gate_target() == _gate,
		"gate attack state references the live gate (no stale gate target)")
	_enter(Phase.GATE_OPEN_CMD)


func _gate_open_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.GATE_OPEN, _gate)
	_check(_gate.is_open() and not _gate.is_closed(),
		"GATE_OPEN command opens the world gate through the 3D contract")
	_enter(Phase.GATE_CROSS_WAIT)


## gate/nav stale 방지: 개방 후 bounded 시간 안에 GATE_ATTACK을 벗어나 성문 선을
## 통과해 경로를 재개해야 한다(영구 gate lock 금지).
func _gate_cross_wait() -> void:
	_wait += 1
	_poll_player_safe()
	var crossed: bool = is_instance_valid(_probe) \
		and (_probe as EnemyActor3D).state != EnemyActor3D.EnemyState.GATE_ATTACK \
		and (_probe as Node3D).global_position.x >= GATE_POS.x + GATE_CROSS_MARGIN
	if not crossed and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(crossed,
		"opening the gate releases the enemy from GATE_ATTACK and resumes its nav route")
	_enter(Phase.GATE_PROBE_FREE)


func _gate_probe_free() -> void:
	if is_instance_valid(_probe):
		_probe.queue_free()
	_wait += 1
	if _wait < 4:
		return
	_wait = 0
	_check(not is_instance_valid(_probe),
		"manual probe cleanup leaves no enemy residue")
	_check(_ledger.get_all_records().size() == _ledger_baseline + _deaths_total,
		"manual queue_free cleanup created no death records")
	_enter(Phase.GATE_CLOSE_CMD)


func _gate_close_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.GATE_CLOSE, _gate)
	_check(_gate.is_closed(),
		"GATE_CLOSE command closes the world gate again after recovery")
	_enter(Phase.TIME_PAUSE_CMD)


## -- TIME(시나리오 9~10): Pause → 2x. Pause 중에도 명령 경로가 산다(deadlock 없음). --
func _time_pause_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.TIME_PAUSE, 0)
	var paused: bool = _game_time.get_time_scale() == GameTime.TIME_SCALE_PAUSE
	_tac._emit_command(_cmd_ui.Command.FOCUS_TARGET, 0)
	var cmd_alive: bool = _roster.focus_mode
	_tac._emit_command(_cmd_ui.Command.FOCUS_TARGET, 0)
	var cmd_toggled_back: bool = _roster.focus_mode == false
	_check(paused, "TIME_PAUSE command sets the tactical pause scale")
	_check(cmd_alive and cmd_toggled_back,
		"tactical commands still respond while paused (no command deadlock)")
	_enter(Phase.TIME_PAUSE_HOLD)


func _time_pause_hold() -> void:
	var elapsed_before: float = _game_time.get_phase_elapsed()
	_game_time.advance(5.0)
	_check(_game_time.get_phase() == GameTime.Phase.NIGHT
		and _near(_game_time.get_phase_elapsed(), elapsed_before),
		"paused clock freezes the night phase")
	_enter(Phase.TIME_2X_CMD)


func _time_2x_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.TIME_2X, 0)
	_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_2X,
		"TIME_2X command doubles the tactical time scale")
	# 절대 elapsed가 아니라 상대 증분으로 판정한다(기동 frame 등 외부 오염 무시).
	var elapsed_before: float = _game_time.get_phase_elapsed()
	_game_time.advance(0.25)
	_check(_game_time.get_phase() == GameTime.Phase.NIGHT
		and _near(_game_time.get_phase_elapsed() - elapsed_before, 0.5),
		"2x scale advances night elapsed time at double rate")
	_enter(Phase.TIME_1X_CMD)


func _time_1x_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.TIME_1X, 0)
	var elapsed_before: float = _game_time.get_phase_elapsed()
	_game_time.advance(0.25)
	_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X
		and _near(_game_time.get_phase_elapsed() - elapsed_before, 0.25),
		"TIME_1X command restores the tactical time scale")
	_enter(Phase.LETHAL_ARM)


## -- LETHAL(시나리오 11): 가변 HP 용병이 살아 있는 적의 실제 타격으로 사망한다. --
func _lethal_arm() -> void:
	if _killer == null:
		_killer = _make_stationary_enemy("enemy_south_killer",
			SOUTH_RALLY + KILLER_OFFSET, 100000)
		_killer.died.connect(_on_tracked_died)
	_enter(Phase.LETHAL_WAIT)


func _lethal_wait() -> void:
	_wait += 1
	_poll_player_safe()
	var fell: bool = _data_south.alive == false and not is_instance_valid(_merc_south)
	if not fell and _wait <= OBSERVE_BUDGET * 2:
		return
	_wait = 0
	if not fell:
		_check(false, "mortal mercenary did not fall to lethal damage in time")
		_enter(Phase.LEDGER_CHECK)
		return
	_check(true, "lethal enemy damage kills the mortal mercenary")
	_check(_data_south.alive == false,
		"fallen mercenary data flips alive off")
	_check(_roster.get_actor("m_south") == null,
		"fallen mercenary actor reference is erased from the roster immediately")
	_check(is_instance_valid(_killer),
		"surviving killer keeps a valid reference (no freed residue)")
	_enter(Phase.LEDGER_CHECK)


## -- LEDGER_CHECK(시나리오 12): duplicate/cleanup/freed-free ledger 정합성. --
func _count_records_for(uid: String) -> int:
	var n := 0
	for record in _ledger.get_all_records():
		if record.source_uid == uid:
			n += 1
	return n


func _record_for(uid: String) -> DeathRecord:
	for record in _ledger.get_all_records():
		if record.source_uid == uid:
			return record
	return null


func _ledger_check() -> void:
	var records: Array[DeathRecord] = _ledger.get_all_records()
	_check(records.size() == _ledger_baseline + _deaths_total,
		"ledger growth equals observed lethal deaths exactly (%d)" % _deaths_total)
	_check(_count_records_for("m_south") == 1,
		"mercenary lethal death is recorded exactly once")
	var record := _record_for("m_south")
	if record != null:
		_check(record.source_kind == DeathRecord.SourceKind.MERCENARY,
			"fallen mercenary record kind is MERCENARY")
		_check(record.display_name == "Hale",
			"ledger snapshot keeps the fallen identity")
		_check(record.death_phase == DeathRecord.DeathPhase.NIGHT,
			"mercenary death phase is NIGHT")
		_check(record.death_position is Vector2 and record.death_position != Vector2.ZERO,
			"mercenary record stores a nonzero logical death position")
	var duplicated := false
	var sources := {}
	for entry in records:
		if sources.has(entry.source_uid):
			duplicated = true
		sources[entry.source_uid] = true
	_check(not duplicated, "ledger holds no duplicate source_uid across the battle")
	_check(_ledger.has_record_for_source("enemy_zone_bait"),
		"has_record_for_source finds the recorded kill")
	_enter(Phase.TO_DAY)


func _to_day() -> void:
	_game_time.advance(_game_time.night_duration)
	_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase returned to DAY")
	_enter(Phase.DAY_CLEANUP)


## -- DAY_CLEANUP(시나리오 13): despawn 무기록 + freed reference 없음 + transient 정리. --
func _day_cleanup() -> void:
	_check(_group_count("mercenaries_3d") == 0 and _roster.get_actor_count() == 0,
		"DAY return despawns every spawned mercenary actor")
	_check(_spawner.get_enemy_count() == 0 and not _spawner.is_night_active(),
		"DAY return despawns the whole encounter")
	_check(not is_instance_valid(_merc_north) and not is_instance_valid(_merc_west)
		and not is_instance_valid(_encounter),
		"despawned references are freed (no stale runtime references)")
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
	_check(_ledger.get_all_records().size() == _ledger_baseline + _deaths_total,
		"cleanup/despawn around DAY return creates no death records")
	_enter(Phase.FREE_FIXTURES)


func _free_fixtures() -> void:
	for node in [_killer, _decoy, _bait, _player_mock]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_wait += 1
	if _wait < 4:
		return
	_wait = 0
	_check(_group_count("enemies_3d") == 0,
		"fixture cleanup leaves no residue in enemies_3d")
	_check(_ledger.get_all_records().size() == _ledger_baseline + _deaths_total,
		"manual fixture cleanup creates no death records either")
	_enter(Phase.REPEAT_NIGHT_WAIT)


## -- 다음 NIGHT 반복(시나리오 14): fresh spawn, 사망자 미재spawn, 명령 재응답. --
func _repeat_night_wait() -> void:
	if _wait == 0:
		_spawner.set_direction("north")
		_game_time.advance(_game_time.day_duration)
		_check(_game_time.get_phase() == GameTime.Phase.NIGHT,
			"next NIGHT begins on repeat cycle")
		_check(_game_time.get_day_number() == 2,
			"repeat night advances the day number")
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
	_check(_roster.get_actor("m_south") == null,
		"fallen mercenary is not respawned on the next night")
	_check(_spawner.get_enemy_count() == 1,
		"repeated NIGHT spawns a fresh encounter after DAY despawn")
	_check(_tac.visible, "tactical UI reappears on the repeat night")
	for actor in [north_again, west_again]:
		(actor as Node).died.connect(_on_tracked_died)
	for enemy in _spawner.get_enemies():
		if is_instance_valid(enemy):
			(enemy as Node).died.connect(_on_tracked_died)
	_enter(Phase.REPEAT_CMD_CHECK)


func _repeat_cmd_check() -> void:
	_tac._emit_command(_cmd_ui.Command.REGROUP, 0)
	var responding: bool = (_roster.get_actor("m_north") as MercenaryActor3D).state \
		== MercenaryActor3D.MercState.REGROUP \
		and (_roster.get_actor("m_west") as MercenaryActor3D).state \
		== MercenaryActor3D.MercState.REGROUP
	_check(responding,
		"commands still drive fresh actors after the full cycle (no deadlock)")
	_enter(Phase.CLEANUP)


## -- CLEANUP: 잔여 reference/orphan 정리 검증 --
func _cleanup() -> void:
	for id in ["m_north", "m_west"]:
		var actor: Node = _roster.get_actor(id)
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
	_check(_ledger.get_all_records().size() == _ledger_baseline + _deaths_total,
		"final cleanup still adds no death records")
	_finish()


## -- 공통: player combat 없음 순회 검증. 모든 살아 있는 enemy의 target/gate target은
## null 또는 mercenaries_3d 소속이어야 하고, player 모형은 무변경이다. --
func _poll_player_safe() -> void:
	for e in get_nodes_in_group("enemies_3d"):
		if not is_instance_valid(e):
			continue
		var target: Variant = e.get("_target")
		if target != null:
			if not is_instance_valid(target) \
					or not (target as Node).is_in_group("mercenaries_3d"):
				_check(false, "an enemy targeted something outside mercenaries_3d")
				return
		var gate_target: Variant = e.get("_gate_target")
		if gate_target != null and not is_instance_valid(gate_target):
			_check(false, "an enemy holds a freed gate reference")
			return
	if _player_mock != null and is_instance_valid(_player_mock):
		if _player_mock.position != PLAYER_POS:
			_check(false, "player mock was moved by combat")
			return
	elif _player_mock != null:
		_check(false, "player mock was freed during combat")
		return


func _on_tracked_died(_actor: Node) -> void:
	_deaths_total += 1
