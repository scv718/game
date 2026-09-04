extends SceneTree

## TASK-021-4 Potion Combat Regression 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task02* 계열(migration map 운영 규칙 5).
##
## 큐 시나리오를 3D Runtime Actor(MercenaryActor3D) 위에서 재생한다:
##   Mercenary Potion 장착 → NIGHT combat → trigger 이전(미소비) → trigger 만족 →
##   auto consume → combat 지속 → retreat/regroup → 다음 NIGHT(fresh actor, flag 리셋).
##
## 검증 항목(완료조건 매핑):
##   1. auto potion vertical slice: 장착 -> NIGHT -> trigger 미만 미소비 -> trigger
##      만족 시 1회 자동 소비 -> HP 회복 + stock 차감 -> 전투가 계속되는 전체 경로.
##   2. Food와 역할/데이터 경로 분리: 포션 stock은 전용 "potion:" prefix로 보관되고
##      Food/raw 자원 키와 섞이지 않으며, MercenaryData의 potion slot은 Food와 별도
##      데이터 경로다(음식 경로를 만들지 않는다).
##   3. Tactical command 회귀 없음: 포션 소비 후에도 RETREAT/REGROUP/DEFENSE_ZONE
##      명령이 정상 동작한다(기존 전술 명령 회귀 없음). 죽음 경로는 task3dcmb0013이
##      별도로 커버하므로 여기서는 소비 후 생존 + 명령 응답에 집중한다.
##
## 결정성 규약: auto consume은 상태(trigger/HP)만으로 결정되므로(pause/2x 무관),
## damage 주입(take_damage)으로 trigger를 확정적으로 만족시킨 뒤 _physics_process의
## _tick_auto_potion()이 소비할 때까지 bounded 관찰한다. 전투 지속은 rally 근처
## 고정 enemy fixture의 피해로 검증한다(추격 없이 확정 교전).

enum Phase {
	SETUP, STRUCTURE, HIRE, TO_NIGHT,
	SPAWN_WAIT, TRIGGER_ABOVE_WAIT, TRIGGER_ABOVE_CHECK,
	DAMAGE_INJECT, CONSUME_WAIT, CONSUME_CHECK,
	COMBAT_ARM, COMBAT_CONTINUE_WAIT,
	RETREAT_CMD, RETREAT_OBSERVE,
	REGROUP_CMD, REGROUP_WAIT, REGROUP_CHECK,
	TO_DAY, DAY_CLEANUP,
	REPEAT_NIGHT_WAIT, REPEAT_NIGHT_CHECK,
	CLEANUP, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 12
const OBSERVE_BUDGET := 900

const HEALING_POTION := "healing_potion"
const POTION_STOCK_KEY := "potion:healing_potion"
const MERC_MAX_HP := 100
const HEAL_AMOUNT := 30
const TRIGGER_RATIO := 0.3

## west rally 중심(WorldMap.RALLY_SPACES 해석값). fixture 배치 기준.
const WEST_RALLY := Vector3(-305.0 * WorldCoords3D.PX_TO_UNIT, 0.0, 0.0)
const ENEMY_OFFSET := Vector3(2.0, 0.0, -2.0)

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _game_time: Node = null
var _ledger: Node = null
var _resources: Node = null
var _roster: Node = null
var _spawner: Node = null
var _tac: Node = null
var _cmd_ui: Script = null

var _data: MercenaryData = null
var _merc: Node = null
var _enemy: Node = null
var _player_mock: Node3D = null
var _hp_before_consume := 0
var _stock_before := 0
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


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK0214_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _group_count(group_name: String) -> int:
	return get_nodes_in_group(group_name).size()


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
		Phase.TRIGGER_ABOVE_WAIT:
			_trigger_above_wait()
		Phase.TRIGGER_ABOVE_CHECK:
			_trigger_above_check()
		Phase.DAMAGE_INJECT:
			_damage_inject()
		Phase.CONSUME_WAIT:
			_consume_wait()
		Phase.CONSUME_CHECK:
			_consume_check()
		Phase.COMBAT_ARM:
			_combat_arm()
		Phase.COMBAT_CONTINUE_WAIT:
			_combat_continue_wait()
		Phase.RETREAT_CMD:
			_retreat_cmd()
		Phase.RETREAT_OBSERVE:
			_retreat_observe()
		Phase.REGROUP_CMD:
			_regroup_cmd()
		Phase.REGROUP_WAIT:
			_regroup_wait()
		Phase.REGROUP_CHECK:
			_regroup_check()
		Phase.TO_DAY:
			_to_day()
		Phase.DAY_CLEANUP:
			_day_cleanup()
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
		print("TASK0214_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
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
	_resources = root.get_node_or_null("VillageResources")
	_check(_world != null, "3D world loads for the potion combat regression")
	_check(_game_time != null and _ledger != null and _resources != null,
		"GameTime/DeathLedger/VillageResources autoloads available")
	if _world == null or _game_time == null or _ledger == null or _resources == null:
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
	_tac = get_first_node_in_group("tactical_command_ui_3d")
	_cmd_ui = load("res://scripts/tactical_command_ui.gd")
	_enter(Phase.STRUCTURE)


## -- STRUCTURE: 시나리오 기반 연결 확인 --
func _structure() -> void:
	_check(_roster.is_in_group("mercenary_roster_3d"),
		"3D roster joins mercenary_roster_3d group")
	_check(_tac != null and _tac is Control,
		"tactical UI stays in the Control layer")
	_check(_tac.command_issued.is_connected(_roster._on_tactical_command),
		"UI command_issued is wired to the 3D roster")
	_check(_tac.visible == false, "tactical UI stays hidden during DAY")
	_ledger_baseline = _ledger.get_all_records().size()
	_enter(Phase.HIRE)


## -- HIRE: Potion을 장착한 용병 배치(시나리오 1). NIGHT 진입 전 등록. --
func _hire() -> void:
	_data = MercenaryData.new("m_potion", "Potio")
	_data.defense_zone = MercenaryData.DefenseZone.WEST
	_data.max_hp = MERC_MAX_HP
	_data.attack_damage = 10
	_data.attack_interval = 1.0
	_data.move_speed = 120.0
	_check(_data.equip_potion(HEALING_POTION, 2),
		"mercenary equips healing potion into the dedicated potion slot")
	_check(_data.has_potion_slot(), "mercenary has a potion slot after equip")
	_check(_roster.add_mercenary(_data), "potion mercenary hired")
	_check(_roster.get_count() == 1 and _roster.get_alive_count() == 1,
		"roster holds the living hire before deployment")
	_check(_resources.has(PotionCraftService.STOCK_PREFIX + HEALING_POTION, 0)
		and PotionCraftService.STOCK_PREFIX == "potion:",
		"potion stock uses the dedicated 'potion:' prefix (Food와 분리)")
	_resources.add(PotionCraftService.STOCK_PREFIX + HEALING_POTION, 3)
	_check(_resources.has(PotionCraftService.STOCK_PREFIX + HEALING_POTION, 3),
		"potion stock provisioned for the combat run")
	_spawner.set_count(1)
	_enter(Phase.TO_NIGHT)


## -- TO_NIGHT: NIGHT 진입(시나리오 2). --
func _to_night() -> void:
	_game_time.advance(_game_time.day_duration)
	_check(_game_time.get_phase() == GameTime.Phase.NIGHT,
		"phase advanced to NIGHT")
	_check(_game_time.get_day_number() == 1, "first night keeps day number 1")
	_enter(Phase.SPAWN_WAIT)


## -- SPAWN_WAIT: NIGHT spawn 수렴 + enemy fixture 배치. --
func _spawn_wait() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES + NAV_SYNC_FRAMES:
		return
	_wait = 0
	_merc = _roster.get_actor("m_potion")
	var spawned_ok: bool = _merc != null and _roster.get_actor_count() == 1 \
		and _group_count("mercenaries_3d") == 1 \
		and _spawner.is_night_active()
	_check(spawned_ok,
		"NIGHT start spawns the assigned potion mercenary")
	if not spawned_ok:
		_enter(Phase.CLEANUP)
		return
	_check((_merc as Node3D).position.distance_to(WEST_RALLY) < 0.01,
		"mercenary spawns at the defense zone rally in world XZ")
	_check((_merc as Node).get("_potion_consumed") == false,
		"fresh night actor starts with the potion unconsumed")
	# Player combat 없음 검증용 모형(자동전투 접근 축선 위).
	_player_mock = Node3D.new()
	_player_mock.name = "PlayerMock"
	_player_mock.position = Vector3(-34.0, 0.0, 0.0)
	_player_mock.add_to_group("player")
	_world.add_child(_player_mock)
	_enter(Phase.TRIGGER_ABOVE_WAIT)


func _make_stationary_enemy(id: String, pos: Vector3, hp: int) -> Node:
	var enemy: Node = (load("res://scenes/enemy_3d.tscn") as PackedScene).instantiate()
	enemy.setup(id, "Raider", "north")
	enemy.max_hp = hp
	enemy.position = pos
	_world.add_child(enemy)
	enemy.set_route([], pos)
	return enemy


## -- TRIGGER_ABOVE_WAIT: trigger 이전 상태를 결정적으로 관찰하기 위해 잠시 대기.
## spawner encounter는 마을 밖 spawn candidate에서 core로 접근하므로 rally의 용병을
## 즉시 타격하지 않는다. HP가 trigger 비율 위에 머무는 동안 미소비임을 확인한다. --
func _trigger_above_wait() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_enter(Phase.TRIGGER_ABOVE_CHECK)


## -- TRIGGER_ABOVE_CHECK: trigger 이전(HP가 trigger 비율보다 높음)에는 미소비. --
func _trigger_above_check() -> void:
	var hp_high: int = int(_merc.get("current_hp"))
	_check(hp_high == MERC_MAX_HP,
		"mercenary HP is still full (trigger not yet satisfied)")
	_check(float(hp_high) / float(MERC_MAX_HP) > TRIGGER_RATIO,
		"HP ratio above trigger threshold -> condition false")
	_check(_merc.get("_potion_consumed") == false,
		"no potion consumed while HP is above the trigger ratio")
	_check(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION) == 3,
		"potion stock untouched while trigger unmet")
	_enter(Phase.DAMAGE_INJECT)


## -- DAMAGE_INJECT: 적 피해 주입으로 trigger 만족(HP 30% 이하). --
func _damage_inject() -> void:
	_stock_before = int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION))
	# HP 100 -> 30: ratio 0.3(<= 0.3)이므로 trigger 만족(결정적, 적 간섭 없음).
	var damage: int = MERC_MAX_HP - int(TRIGGER_RATIO * MERC_MAX_HP)
	(_merc as Node).take_damage(damage)
	_hp_before_consume = int(_merc.get("current_hp"))
	_check(_hp_before_consume == int(TRIGGER_RATIO * MERC_MAX_HP),
		"enemy damage brings HP to the trigger threshold")
	_check(float(_hp_before_consume) / float(MERC_MAX_HP) <= TRIGGER_RATIO,
		"HP ratio now satisfies the trigger condition")
	_enter(Phase.CONSUME_WAIT)


## -- CONSUME_WAIT: _physics_process의 _tick_auto_potion()이 소비할 때까지 대기. --
func _consume_wait() -> void:
	_wait += 1
	if _wait > OBSERVE_BUDGET:
		_check(false, "potion was not auto-consumed within the observation budget")
		_enter(Phase.COMBAT_ARM)
		return
	if _merc.get("_potion_consumed") == false:
		return
	_wait = 0
	_check(true, "auto consume fired when the trigger condition is met")
	_enter(Phase.CONSUME_CHECK)


## -- CONSUME_CHECK: 효과 적용 + stock 반영 + multi-consume 방지. --
func _consume_check() -> void:
	var hp_now: int = int(_merc.get("current_hp"))
	var expected_hp: int = mini(MERC_MAX_HP, _hp_before_consume + HEAL_AMOUNT)
	_check(hp_now == expected_hp,
		"HEAL effect applied to current_hp (%d -> %d)" % [_hp_before_consume, hp_now])
	_check(_merc.get("_potion_consumed") == true,
		"consumed flag latched true (no multi-consume in this battle)")
	_check(_data.get_potion_slot_count() == 1,
		"potion slot count decremented after consume")
	_check(int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION))
		== _stock_before - 1,
		"potion stock reflected -1 after consume (potion: prefix path)")
	_check(int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION)) >= 0,
		"potion stock stays non-negative")
	# Food 분리: potion 소비 경로가 Food/raw 자원 키를 만들거나 소비하지 않는다.
	_check(not _resources.has("food", 1) and _resources.get_amount("food") == 0,
		"potion path does not create/touch a 'food' resource (Food 경로 분리)")
	_check(_merc.is_in_group("mercenaries_3d"),
		"surviving mercenary stays in the combat group after the potion")
	_enter(Phase.COMBAT_ARM)


## -- COMBAT_ARM: 소비 후 확정 교전용 고정 enemy fixture를 rally 근처에 배치한다.
## 소비는 상태(trigger/HP)만으로 결정되므로 enemy 없이 검증했고, 이제 전투 지속을
## 위해 근접 fixture로 확정 교전시킨다. --
func _combat_arm() -> void:
	if _enemy == null:
		_enemy = _make_stationary_enemy("enemy_potion_target", WEST_RALLY + ENEMY_OFFSET, 100000)
	_enter(Phase.COMBAT_CONTINUE_WAIT)


## -- COMBAT_CONTINUE_WAIT: 소비 후에도 자동전투가 지속되는지 관찰. --
func _combat_continue_wait() -> void:
	_wait += 1
	_poll_player_safe()
	# enemy HP가 최초 피해량보다 더 줄었으면(용병이 계속 공격) 전투 지속으로 본다.
	var enemy_hp: int = int(_enemy.get("current_hp"))
	var damaged_more: bool = enemy_hp < 100000
	if not damaged_more and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(damaged_more,
		"mercenary continues auto-combat after the potion consume")
	_check(_merc.is_in_group("mercenaries_3d"),
		"merc actor remains valid and in combat after healing")
	_enter(Phase.RETREAT_CMD)


## -- RETREAT_CMD: 전술 명령(후퇴)이 소비 후에도 정상 응답하는지 확인. --
func _retreat_cmd() -> void:
	_tac._emit_command(_cmd_ui.Command.RETREAT, 0)
	var retreat_point: Vector3 = (_merc as Node).get_retreat_point()
	_check((_merc as Node).state == MercenaryActor3D.MercState.RETREAT,
		"RETREAT command drives the potion mercenary into the RETREAT state")
	_check(retreat_point.distance_to(_roster.get_safe_rally(_world)) < 0.001,
		"RETREAT aims at the settlement safe rally in world XZ")
	_enter(Phase.RETREAT_OBSERVE)


func _retreat_observe() -> void:
	_wait += 1
	_poll_player_safe()
	var body := _merc as Node
	var settled: bool = WorldCoords3D.distance_xz(
		(body as Node3D).global_position, body.get_retreat_point()) \
		<= body.REACH_DISTANCE + 0.5
	if not settled and _wait <= OBSERVE_BUDGET * 2:
		return
	_wait = 0
	_check(settled,
		"retreating mercenary holds at the safe rally instead of resuming the hunt")
	_check(body.state == MercenaryActor3D.MercState.RETREAT,
		"mercenary remains in RETREAT (hold) after reaching the safe point")
	_enter(Phase.REGROUP_CMD)


## -- REGROUP_CMD/Wait/Check: 소비 후 REGROUP 명령으로 진지 복귀 + 재전투. --
func _regroup_cmd() -> void:
	(_merc as Node).set_defense_zone(
		MercenaryData.DefenseZone.WEST, WEST_RALLY)
	_tac._emit_command(_cmd_ui.Command.REGROUP, 0)
	_check((_merc as Node).state == MercenaryActor3D.MercState.REGROUP
		or (_merc as Node).state == MercenaryActor3D.MercState.RETURN_TO_DEFENSE_ZONE
		or (_merc as Node).state == MercenaryActor3D.MercState.ACQUIRE_TARGET,
		"REGROUP/re-defense command pulls the mercenary back toward the post")
	_enter(Phase.REGROUP_WAIT)


func _regroup_wait() -> void:
	_wait += 1
	_poll_player_safe()
	var body := _merc as Node
	var at_post: bool = WorldCoords3D.distance_xz(
		(body as Node3D).global_position, WEST_RALLY) <= body.REACH_DISTANCE + 0.5
	if not at_post and _wait <= OBSERVE_BUDGET * 2:
		return
	_wait = 0
	_check(at_post, "re-defense/regroup returns the mercenary to his west post")
	_enter(Phase.REGROUP_CHECK)


func _regroup_check() -> void:
	_check((_merc as Node).state != MercenaryActor3D.MercState.RETREAT,
		"post-return actor leaves RETREAT and resumes defense AI")
	_check(_merc.is_in_group("mercenaries_3d"),
		"merc stays in combat group after regroup (tactical command 회귀 없음)")
	_enter(Phase.TO_DAY)


## -- TO_DAY / DAY_CLEANUP: DAY 복귀 despawn. --
func _to_day() -> void:
	_game_time.advance(_game_time.night_duration)
	_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase returned to DAY")
	_enter(Phase.DAY_CLEANUP)


func _day_cleanup() -> void:
	_check(_group_count("mercenaries_3d") == 0 and _roster.get_actor_count() == 0,
		"DAY return despawns the potion mercenary actor")
	_check(not is_instance_valid(_merc),
		"despawned actor reference is freed (no stale reference)")
	_check(_resources.has(PotionCraftService.STOCK_PREFIX + HEALING_POTION, 2),
		"remaining potion stock survives across the day/night boundary")
	_check(_ledger.get_all_records().size() == _ledger_baseline,
		"day cleanup/despawn creates no death records")
	_enter(Phase.REPEAT_NIGHT_WAIT)


## -- 다음 NIGHT(시나리오 마지막): fresh actor spawn + consumed flag 리셋. --
func _repeat_night_wait() -> void:
	if _wait == 0:
		_game_time.advance(_game_time.day_duration)
		_check(_game_time.get_phase() == GameTime.Phase.NIGHT,
			"next NIGHT begins on the repeat cycle")
		_check(_game_time.get_day_number() == 2,
			"repeat night advances the day number")
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES + NAV_SYNC_FRAMES:
		return
	_wait = 0
	_enter(Phase.REPEAT_NIGHT_CHECK)


func _repeat_night_check() -> void:
	var fresh: Node = _roster.get_actor("m_potion")
	_check(fresh != null and fresh != _merc,
		"repeated NIGHT spawns a fresh actor (no duplicate id reuse)")
	_check(_data.alive and _data.get_potion_slot_count() == 1,
		"living roster data keeps the remaining potion slot across nights")
	_check(fresh.get("_potion_consumed") == false,
		"fresh night actor resets the consumed flag (battle-unit auto consume)")
	_check(_resources.has(PotionCraftService.STOCK_PREFIX + HEALING_POTION, 2),
		"potion stock persists across the repeated night")
	_enter(Phase.CLEANUP)


func _cleanup() -> void:
	# DAY로 복귀시켜 roster가 fresh actor를 despawn하도록 한 뒤 남은 fixture 정리.
	if _game_time != null and is_instance_valid(_game_time) \
			and _game_time.get_phase() == GameTime.Phase.NIGHT:
		_game_time.advance(_game_time.night_duration)
	if _roster != null and is_instance_valid(_roster):
		_roster.despawn_night_actors()
	if _spawner != null and is_instance_valid(_spawner):
		_spawner.despawn_encounter()
	for n in [_merc, _enemy, _player_mock]:
		if n != null and is_instance_valid(n):
			n.free()
	_wait += 1
	if _wait < 4:
		return
	_check(_group_count("mercenaries_3d") == 0, "no orphan mercenaries remain")
	_check(_group_count("enemies_3d") == 0, "no orphan enemies remain")
	_check(_group_count("player") == 0, "no orphan player mock remains")
	_check(_ledger.get_all_records().size() == _ledger_baseline,
		"fixture cleanup adds no death records")
	_finish()


## -- 공통: player combat 없음 순회 검증. --
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
	if _player_mock != null and is_instance_valid(_player_mock):
		if _player_mock.position != Vector3(-34.0, 0.0, 0.0):
			_check(false, "player mock was moved by combat")
			return
	elif _player_mock != null:
		_check(false, "player mock was freed during combat")
		return
