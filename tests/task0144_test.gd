extends SceneTree

## TASK-014-4 Mercenary Auto Combat FSM 자동 검증.
##  - MercenaryActor FSM: IDLE/ACQUIRE_TARGET/MOVE_TO_TARGET/ATTACK/RETURN_TO_DEFENSE_ZONE/DEAD.
##    지정 defense zone 근처(CHASE_RETURN_DISTANCE 이내) 살아 있는 Enemy를 deterministic
##    priority로 자동 탐색/추격/공격하고, 과도하게 멀리 추격하면 defense_point로 복귀하며,
##    target death/invalid 시 새 target을 탐색한다.
##  - EnemyActor 전투: 공격 range 안의 살아 있는 Mercenary를 target으로 interval 공격하고,
##    target이 죽거나 멀어지면 기존 접근(route)을 재개한다. Player는 절대 target이 되지 않는다.
##  - Mercenary는 Enemy 공격으로 HP가 감소하고, HP 0이 되면 사망한다(MercenaryData.alive=false,
##    그룹 제외, 월드 제거). 사망한 용병은 다음 NIGHT에 재생성되지 않는다.
##  - 회귀: Player 무공격/무타겟, Worker 무spawn, 핵심 건물/floor/nav/gate 유지.

enum Phase {
	SETUP,
	NIGHT_READY,
	IDLE_NO_TARGET,
	ACQUIRE_CHASE,
	ATTACK_KILL,
	RETARGET,
	ENEMY_ATTACKS_MERC,
	CHASE_RETURN,
	MERC_DEATH,
	NO_RESPAWN,
	REGRESSION,
	DONE,
}

const GATE_POS := Vector2(0, -448)
const NORTH_RALLY := Vector2(0, -280)
const MERC_MAX_HP := 100
const MERC_ATTACK_DAMAGE := 30
const MERC_ATTACK_INTERVAL := 0.05
const ENEMY_FAST_INTERVAL := 0.05
const BUDGET := 1500

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _wait := 0
var _failed := false

var _game_time: Node = null
var _world: Node = null
var _placement: Node = null
var _spawner: Node = null
var _roster: Node = null
var _worker_roster: Node = null
var _resources: Node = null
var _mercenary: MercenaryData = null
var _actor: Node = null

var _enemy_seq := 0
var _budget := 0
var _observed_return := false


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_sub = 0
	_wait = 0


## 현재 sub-step을 마치고 n 프레임 대기하는 다음 sub-step으로 진행한다.
func _wait_frames(n: int) -> void:
	_wait = n
	_sub += 1


func _waited() -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	return true


func _finish() -> void:
	print("TASK0144_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _advance_to_next_phase() -> void:
	if _game_time.get_phase() == GameTime.Phase.DAY:
		_game_time.advance(2.0)
	else:
		_game_time.advance(1.0)


func _count_enemies() -> int:
	return get_nodes_in_group("enemies").size()


func _count_mercenaries() -> int:
	return get_nodes_in_group("mercenaries").size()


func _find_gate_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("gates"):
		if not is_instance_valid(node):
			continue
		var gate := node as Node2D
		if gate == null:
			continue
		if (gate.position - pos).length_squared() < 1.0:
			return node
	return null


## 직접 배치하는 테스트용 Enemy. HOLD(정지) 또는 route(MOVE) 선택.
func _spawn_enemy(pos: Vector2, hp := 60, with_route := false) -> EnemyActor:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate() as EnemyActor
	if enemy == null:
		return null
	enemy.max_hp = hp
	enemy.setup("test_enemy_%d" % _enemy_seq, "Raider", "north")
	enemy.position = pos
	_world.add_child(enemy)
	_enemy_seq += 1
	if with_route:
		enemy.set_route([], Vector2(0, -150))
	return enemy


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			if _sub == 0:
				_game_time = root.get_node("GameTime")
				if _game_time != null and _game_time.has_method("set_auto_advance"):
					_game_time.set_auto_advance(false)
				if _game_time != null and _game_time.has_method("set_durations"):
					_game_time.set_durations(2.0, 1.0)
				_world = root.get_node("Main").get_node("World")
				_placement = root.get_node("Main").get_node("BuildingPlacement")
				_spawner = root.get_node("FirstEncounterSpawner")
				_spawner.set_direction("north")
				_roster = root.get_node("MercenaryRoster")
				_worker_roster = root.get_node("WorkerRoster")
				_resources = root.get_node("VillageResources")
				_check(_game_time != null and _world != null and _placement != null \
					and _spawner != null and _roster != null and _worker_roster != null \
					and _resources != null, "core nodes present")
				_resources._amounts["wood"] = 10000
				var ui: Control = get_first_node_in_group("recruitment_ui")
				_check(ui != null, "recruitment UI present")
				ui._on_mercenary_hire_pressed("mercenary_A")
				_mercenary = _roster.get_mercenary("mercenary_A")
				_check(_mercenary != null, "mercenary_A hired into roster")
				_check(_mercenary != null and _mercenary.alive, "mercenary_A alive")
				if _mercenary != null:
					_mercenary.set_defense_zone(MercenaryData.DefenseZone.NORTH)
					_mercenary.max_hp = MERC_MAX_HP
					_mercenary.attack_damage = MERC_ATTACK_DAMAGE
					_mercenary.attack_interval = MERC_ATTACK_INTERVAL
					_mercenary.move_speed = 120.0
				_check(_mercenary != null and _mercenary.get_defense_zone() == MercenaryData.DefenseZone.NORTH, "defense NORTH")
				_check(_count_mercenaries() == 0, "no mercenary actor during DAY (%d)" % _count_mercenaries())
				_placement._set_building_type("gate")
				_placement._try_place_gate_at(_placement._snap_gate(GATE_POS))
				_check(_find_gate_at(GATE_POS) != null, "north gate placed")
				_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor (Player never fights)")
				_check(MercenaryActor.MercState.size() == 8, "MercState has 8 states (FSM)")
				_check(EnemyActor.EnemyState.size() == 4, "EnemyState has 4 states (ATTACK, GATE_ATTACK)")
				_check(MercenaryActor.MercState.keys().has("RETURN_TO_DEFENSE_ZONE") \
					and MercenaryActor.MercState.keys().has("ACQUIRE_TARGET") \
					and MercenaryActor.MercState.keys().has("REGROUP") \
					and MercenaryActor.MercState.keys().has("RETREAT"), "FSM states ACQUIRE_TARGET/RETURN/REGROUP/RETREAT exist")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT after advance")
				_enter(Phase.NIGHT_READY)
		Phase.NIGHT_READY:
			if _sub == 0:
				_check(_count_mercenaries() == 1, "mercenary actor spawned at NIGHT (%d)" % _count_mercenaries())
				_actor = _roster.get_actor("mercenary_A")
				_check(_actor != null, "actor retrievable by id")
				if _actor != null:
					_check(_actor.merc_data == _mercenary, "actor references roster MercenaryData")
					_check(_actor.current_hp == MERC_MAX_HP, "actor current_hp from max_hp")
					_check(_actor.alive, "actor alive")
					var pos: Vector2 = (_actor as Node2D).global_position
					_check(pos.distance_to(NORTH_RALLY) < 1.0, "actor at north rally (pos=%s)" % pos)
					_check(_actor.get_state() == MercenaryActor.MercState.IDLE, "actor starts IDLE")
				_check(_count_enemies() == 3, "spawner auto-encounter 3 enemies at NIGHT (%d)" % _count_enemies())
				_spawner.despawn_encounter()
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_enemies() == 0, "auto-encounter cleaned for isolated FSM test (%d)" % _count_enemies())
				_enter(Phase.IDLE_NO_TARGET)
		Phase.IDLE_NO_TARGET:
			if _sub == 0:
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _budget >= 30:
					_check(_count_enemies() == 0, "no enemies present")
					if _actor != null:
						_check(_actor.get_state() == MercenaryActor.MercState.IDLE, "actor stays IDLE with no target")
						_check((_actor as Node2D).global_position.distance_to(NORTH_RALLY) < 1.0, "actor holds at defense point")
					_enter(Phase.ACQUIRE_CHASE)
				else:
					_budget += 1
		Phase.ACQUIRE_CHASE:
			if _sub == 0:
				_spawn_enemy(Vector2(0, -380), 60, false)
				_check(_count_enemies() == 1, "test enemy E1 spawned near zone (%d)" % _count_enemies())
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _actor != null and _actor.get_state() == MercenaryActor.MercState.MOVE_TO_TARGET:
					_check(true, "mercenary ACQUIRE_TARGET -> MOVE_TO_TARGET (state=%s)" % str(_actor.get_state()))
					var target: Node = _actor.get_target()
					_check(target != null and is_instance_valid(target) and (target as Node2D).global_position.distance_to(Vector2(0, -380)) < 1.0, "mercenary target is E1")
					var dist: float = (_actor as Node2D).global_position.distance_to(Vector2(0, -380))
					_check(dist <= 101.0, "mercenary started chasing E1 (dist=%.1f)" % dist)
					_enter(Phase.ATTACK_KILL)
				elif _budget >= BUDGET:
					_check(false, "mercenary never acquired/chased enemy in budget (state=%s)" % str(_actor.get_state() if _actor != null else "?"))
					_enter(Phase.ATTACK_KILL)
				else:
					_budget += 1
		Phase.ATTACK_KILL:
			if _sub == 0:
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _count_enemies() == 0:
					_wait_frames(5)
				elif _budget >= BUDGET:
					_check(false, "E1 never killed by mercenary in budget (enemies=%d)" % _count_enemies())
					_enter(Phase.RETARGET)
				else:
					_budget += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(true, "E1 killed by mercenary attack (enemy count=0)")
				_check(_actor.alive, "mercenary alive after killing E1")
				_check(_actor.get_state() == MercenaryActor.MercState.IDLE, "mercenary returns to IDLE after target death")
				_enter(Phase.RETARGET)
		Phase.RETARGET:
			if _sub == 0:
				var e2 := _spawn_enemy(Vector2(0, -330), 60, false)
				_check(e2 != null, "test enemy E2 spawned")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _actor != null and _count_enemies() == 1 and _actor.get_target() != null:
					var t: Node = _actor.get_target()
					if t != null and is_instance_valid(t) and t.enemy_id == "test_enemy_1":
						var e2hp: int = t.current_hp
						if e2hp < 60:
							_check(true, "mercenary re-acquired E2 and attacked (hp=%d)" % e2hp)
							_check(_actor.get_state() == MercenaryActor.MercState.ATTACK, "mercenary in ATTACK")
							if is_instance_valid(t):
								t.take_damage(100000)
							_enter(Phase.ENEMY_ATTACKS_MERC)
						elif _budget >= BUDGET:
							_check(false, "E2 never damaged in budget")
							_enter(Phase.ENEMY_ATTACKS_MERC)
						else:
							_budget += 1
					elif _budget >= BUDGET:
						_check(false, "mercenary never re-targeted E2")
						_enter(Phase.ENEMY_ATTACKS_MERC)
					else:
						_budget += 1
				elif _budget >= BUDGET:
					_check(false, "mercenary no target E2 in budget (state=%s)" % str(_actor.get_state() if _actor != null else "?"))
					_enter(Phase.ENEMY_ATTACKS_MERC)
				else:
					_budget += 1
		Phase.ENEMY_ATTACKS_MERC:
			if _sub == 0:
				var e3 := _spawn_enemy(Vector2(0, -340), 100000, true)
				_check(e3 != null, "test enemy E3 (high hp, route) spawned")
				if e3 != null:
					e3.attack_damage = 8
					e3.attack_interval = ENEMY_FAST_INTERVAL
				var hp0: int = (_actor as Node2D).current_hp if _actor != null else MERC_MAX_HP
				_check(hp0 == MERC_MAX_HP, "mercenary full hp before enemy engagement")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _actor != null and _actor.current_hp < MERC_MAX_HP:
					_check(true, "enemy attacked mercenary (mercenary hp %d < %d)" % [_actor.current_hp, MERC_MAX_HP])
					_check(_actor.alive, "mercenary still alive")
					if _count_enemies() > 0:
						for e in get_nodes_in_group("enemies"):
							if is_instance_valid(e):
								e.queue_free()
					_enter(Phase.CHASE_RETURN)
				elif _budget >= BUDGET:
					_check(false, "mercenary hp never dropped by enemy in budget (%d)" % (_actor.current_hp if _actor != null else -1))
					for e in get_nodes_in_group("enemies"):
						if is_instance_valid(e):
							e.queue_free()
					_enter(Phase.CHASE_RETURN)
				else:
					_budget += 1
		Phase.CHASE_RETURN:
			if _sub == 0:
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_enemies() == 0, "enemies cleared for chase-return test (%d)" % _count_enemies())
				var e4 := _spawn_enemy(Vector2(0, -380), 60, false)
				_check(e4 != null, "test enemy E4 spawned")
				_budget = 0
				_sub = 2
			elif _sub == 2:
				# mercenary가 E4를 향해 추격을 시작하면 E4를 멀리(260, -280)로 이동시킨다.
				if _actor != null and _actor.get_state() == MercenaryActor.MercState.MOVE_TO_TARGET:
					var e4: Node = _actor.get_target()
					if e4 != null and is_instance_valid(e4):
						(e4 as Node2D).global_position = Vector2(260, -280)
						_check(true, "E4 moved far east (%s) -> mercenary should return" % Vector2(260, -280))
						_observed_return = false
						_budget = 0
						_sub = 3
					elif _budget >= BUDGET:
						_check(false, "mercenary chasing but target invalid")
						_enter(Phase.MERC_DEATH)
					else:
						_budget += 1
				elif _budget >= BUDGET:
					_check(false, "mercenary never chased E4 in budget")
					_enter(Phase.MERC_DEATH)
				else:
					_budget += 1
			elif _sub == 3:
				if _actor != null and _actor.get_state() == MercenaryActor.MercState.RETURN_TO_DEFENSE_ZONE:
					_observed_return = true
				if _observed_return and _actor != null and _actor.get_state() == MercenaryActor.MercState.IDLE \
					and (_actor as Node2D).global_position.distance_to(NORTH_RALLY) <= 30.0:
					_check(true, "mercenary returned to defense point (RETURN_TO_DEFENSE_ZONE -> IDLE near rally)")
					_check((_actor as Node2D).global_position.distance_to(NORTH_RALLY) <= 30.0, "returned position near rally")
					_budget = 0
					_sub = 4
				elif _budget >= BUDGET:
					_check(false, "mercenary never returned to defense point in budget (observed_return=%s, state=%s, dist=%.1f)" \
						% [str(_observed_return), str(_actor.get_state() if _actor != null else "?"), (_actor as Node2D).global_position.distance_to(NORTH_RALLY) if _actor != null else -1.0])
					_enter(Phase.MERC_DEATH)
				else:
					_budget += 1
			elif _sub == 4:
				# 복귀 후에도 E4(멀리 있음)를 다시 추격하지 않는지(영구 chase 없음) 확인.
				if _budget >= 30:
					var e4: Node = _actor.get_target() if _actor != null else null
					_check(e4 == null, "no re-acquisition of far enemy after return (no permanent chase)")
					if _count_enemies() > 0:
						for e in get_nodes_in_group("enemies"):
							if is_instance_valid(e):
								e.queue_free()
					_enter(Phase.MERC_DEATH)
				else:
					_budget += 1
		Phase.MERC_DEATH:
			if _sub == 0:
				_check(_actor != null, "actor present for death test")
				if _actor != null:
					var hp: int = _actor.current_hp
					_actor.take_damage(hp + 999)
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_actor == null or not is_instance_valid(_actor), "mercenary actor freed after death")
				_check(_count_mercenaries() == 0, "mercenary removed from group (%d)" % _count_mercenaries())
				_check(_mercenary.alive == false, "MercenaryData.alive set to false on death")
				_check(_roster.get_actor("mercenary_A") == null, "roster actor lookup null after death")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase back to DAY after death")
				_enter(Phase.NO_RESPAWN)
		Phase.NO_RESPAWN:
			if _sub == 0:
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "next NIGHT after death")
				_check(_count_mercenaries() == 0, "dead mercenary NOT re-spawned next NIGHT (%d)" % _count_mercenaries())
				_check(_roster.get_actor_count() == 0, "roster actor_count 0 (no respawn)")
				_mercenary.alive = true
				_mercenary.set_defense_zone(MercenaryData.DefenseZone.NONE)
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase DAY for regression")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(_count_mercenaries() == 0, "no mercenary actor during DAY regression")
				_check(_roster.get_count() == 1, "mercenary roster data retained (%d)" % _roster.get_count())
				_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor (Player never fights)")
				_check(_worker_roster.get_count() == 0, "worker roster unaffected (%d)" % _worker_roster.get_count())
				_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor spawned")
				_check(get_nodes_in_group("miners").size() == 0, "no miner actor spawned")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact")
				# Enemy는 비전투(non-mercenary) 액터를 target으로 삼지 않음:
				# 정착지 중심(전 플레이어 시작 지점)에 배치해도 ATTACK 진입 금지.
				var eprobe := _spawn_enemy(Vector2(0, 90), 60, true)
				_check(eprobe != null, "enemy probe near settlement center spawned")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _budget >= 60:
					_check(eprobe_state() == EnemyActor.EnemyState.MOVE, "enemy near non-mercenary stays MOVE (no target)")
					for e in get_nodes_in_group("enemies"):
						if is_instance_valid(e):
							e.queue_free()
					var gate := _find_gate_at(GATE_POS)
					_check(gate != null, "gate still present")
					if gate != null:
						gate.set_open(true)
						gate.set_open(false)
						_check(gate.is_closed(), "gate toggle still works")
					var nav_map: RID = _world.get_world_2d().get_navigation_map()
					var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, NORTH_RALLY, Vector2(0, -150), true)
					_check(path.size() >= 2, "nav path from rally to keep exists (%d pts)" % path.size())
					_check(EnemyActor.EnemyState.ATTACK == 2, "EnemyState.ATTACK constant intact")
					_enter(Phase.DONE)
				else:
					_budget += 1
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0144_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


## regression에서 사용: 정착지 중심 근처에 배치한 test enemy의 state를 그룹에서 찾아 반환.
func eprobe_state() -> int:
	for e in get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var eid = e.get("enemy_id")
		if eid != null and String(eid).begins_with("test_enemy_"):
			return e.state
	return -1


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
