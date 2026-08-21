extends SceneTree

## TASK-014-6 Combat Death / Cleanup 자동 검증.
##  - Enemy death: 전투(그룹)/target/월드에서 제외 후 제거. 사망 즉시 alive=false +
##    enemies 그룹 제외(combat/target 배제) + queue_free(collision 제거). 직접
##    take_damage로 사망시켜도 동일. 전투로 사망한 Enemy는 FirstEncounterSpawner의
##    _enemies 추적에서 died signal로 즉시 제거되어 반복 NIGHT cycle reference 누수가 없다.
##  - Mercenary death: MercenaryData.alive=false 반영, Actor 제거(그룹 제외 + freed),
##    roster _actors에서 즉시 제거(get_actor null), dead는 roster 조회로 확인 가능.
##    공격하던 Enemy는 target reference를 비우고 MOVE 복귀(freed reference 없음).
##  - 반복 cycle: alive Mercenary만 다음 NIGHT spawn(dead 재생성 없음), NIGHT 반복에도
##    actor duplicate 없음, 이전 Enemy reference 누수 없음.
##  - 중요: Death Ledger 기록/추가 사망 시스템은 구현하지 않음.
##  - 회귀: Player 무공격/무타겟 그룹, Worker 무spawn, 핵심 건물/floor/gate 유지.

enum Phase {
	SETUP,
	NIGHT_READY,
	ENEMY_DEATH,
	MERC_DEATH,
	NO_RESPAWN,
	REPEAT_CYCLE,
	REGRESSION,
	DONE,
}

const GATE_POS := Vector2(0, -448)
const NORTH_RALLY := Vector2(0, -280)
const BUDGET := 1500

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _wait := 0
var _failed := false

var _game_time: Node = null
var _world: Node = null
var _layout: Node = null
var _placement: Node = null
var _spawner: Node = null
var _roster: Node = null
var _worker_roster: Node = null
var _resources: Node = null
var _player: Node = null
var _mercenary: MercenaryData = null
var _mercenary_b: MercenaryData = null
var _actor: Node = null
var _ed: Node = null
var _e3: Node = null

var _enemy_seq := 0
var _budget := 0


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
	print("TASK0146_RESULT=" + ("FAIL" if _failed else "PASS"))
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
				_layout = _world.get_node("MapLayout")
				_placement = root.get_node("Main").get_node("BuildingPlacement")
				_spawner = root.get_node("FirstEncounterSpawner")
				_roster = root.get_node("MercenaryRoster")
				_worker_roster = root.get_node("WorkerRoster")
				_resources = root.get_node("VillageResources")
				_player = root.get_node("Main").get_node("Player")
				_check(_game_time != null and _world != null and _layout != null and _placement != null \
					and _spawner != null and _roster != null and _worker_roster != null \
					and _resources != null and _player != null, "core nodes present")
				_resources._amounts["wood"] = 10000
				var ui: Control = get_first_node_in_group("recruitment_ui")
				_check(ui != null, "recruitment UI present")
				ui._on_mercenary_hire_pressed("mercenary_A")
				_mercenary = _roster.get_mercenary("mercenary_A")
				_check(_mercenary != null and _mercenary.alive, "mercenary_A hired alive")
				if _mercenary != null:
					_mercenary.set_defense_zone(MercenaryData.DefenseZone.NORTH)
					_mercenary.max_hp = 80
					_mercenary.attack_damage = 30
					_mercenary.attack_interval = 0.05
					_mercenary.move_speed = 120.0
				# 두 번째 용병(B): EAST 배치로 북방 전투와 격리. dead 재생성 검증용.
				var b := MercenaryData.new("mercenary_B", "Mercenary B", MercenaryData.MercClass.SWORDSMAN)
				b.max_hp = 200
				b.attack_damage = 20
				b.attack_interval = 0.2
				b.move_speed = 120.0
				b.set_defense_zone(MercenaryData.DefenseZone.EAST)
				_mercenary_b = b
				_check(_roster.add_mercenary(b), "mercenary_B added to roster")
				_check(_roster.get_count() == 2, "roster holds 2 mercenaries (%d)" % _roster.get_count())
				_check(_roster.get_alive().size() == 2, "both mercenaries alive before combat")
				_placement._set_building_type("gate")
				_placement._try_place_gate_at(_placement._snap_gate(GATE_POS))
				_check(_find_gate_at(GATE_POS) != null, "north gate placed")
				_check(not _player.has_method("attack") and not _player.has_method("_attack"), "player has no attack method")
				_check(_roster._actors.size() == 0, "no mercenary actor during DAY (roster _actors empty)")
				_check(_spawner._enemies.size() == 0, "spawner _enemies empty during DAY")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT after advance")
				_enter(Phase.NIGHT_READY)
		Phase.NIGHT_READY:
			if _sub == 0:
				_check(_count_mercenaries() == 2, "both mercenary actors spawned at NIGHT (%d)" % _count_mercenaries())
				_actor = _roster.get_actor("mercenary_A")
				var b_actor: Node = _roster.get_actor("mercenary_B")
				_check(_actor != null and b_actor != null, "both actors retrievable by id")
				if _actor != null:
					_check(_actor.merc_data == _mercenary, "actor A references roster MercenaryData")
					_check(_actor.current_hp == 80, "actor A current_hp from max_hp (80)")
					var pos: Vector2 = (_actor as Node2D).global_position
					_check(pos.distance_to(NORTH_RALLY) < 1.0, "actor A at north rally (pos=%s)" % pos)
					_check(_actor.get_state() == MercenaryActor.MercState.IDLE, "actor A starts IDLE")
				if b_actor != null:
					_check(b_actor.merc_data.id == "mercenary_B", "actor B is mercenary_B")
				_check(_count_enemies() == 3, "spawner auto-encounter 3 enemies at NIGHT (%d)" % _count_enemies())
				_spawner.despawn_encounter()
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_enemies() == 0, "auto-encounter cleaned for isolated death test (%d)" % _count_enemies())
				_check(_spawner._enemies.size() == 0, "spawner tracking empty after despawn")
				_enter(Phase.ENEMY_DEATH)
		Phase.ENEMY_DEATH:
			if _sub == 0:
				# 북방 근처 HOLD 적 2마리 → A가 자동 추격/공격/사살.
				var e1 := _spawn_enemy(Vector2(0, -360), 60, false)
				var e2 := _spawn_enemy(Vector2(0, -400), 60, false)
				_check(e1 != null and e2 != null, "test enemies spawned for enemy-death cleanup")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _count_enemies() == 0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "test enemies never killed by mercenary in budget (enemies=%d)" % _count_enemies())
					_wait_frames(4)
				else:
					_budget += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(true, "enemies killed by mercenary auto combat")
				_check(_count_enemies() == 0, "dead enemies excluded from enemies group (combat/target)")
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() == null, "mercenary target cleared after enemy death")
				# 직접 사망 경로: take_damage → alive=false → 그룹 제외 → freed.
				var ed := _spawn_enemy(Vector2(0, -380), 60, false)
				_check(ed != null, "direct-kill enemy spawned")
				_ed = ed
				ed.take_damage(99999)
				_check(ed.alive == false, "direct-kill enemy alive=false immediately after damage")
				_check(not ed.is_in_group("enemies"), "direct-kill enemy excluded from enemies group immediately")
				_wait_frames(3)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(not is_instance_valid(_ed), "direct-kill enemy freed from world (collision removed)")
				_check(_count_enemies() == 0, "no enemies remain after direct kill (%d)" % _count_enemies())
				_enter(Phase.MERC_DEATH)
		Phase.MERC_DEATH:
			if _sub == 0:
				# 강한 적이 A를 공격해 사망시킨다(E3는 살아남음, route MOVE로 교전).
				var e3 := _spawn_enemy(Vector2(0, -330), 100000, true)
				_check(e3 != null, "strong enemy E3 spawned for merc death")
				if e3 != null:
					e3.attack_damage = 25
					e3.attack_interval = 0.05
				_e3 = e3
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _actor == null or not is_instance_valid(_actor):
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never died in budget")
					_wait_frames(4)
				else:
					_budget += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_mercenary.alive == false, "MercenaryData.alive set to false on death")
				_check(_count_mercenaries() == 1, "dead A removed from mercenaries group (B remains) (%d)" % _count_mercenaries())
				_check(_roster.get_actor("mercenary_A") == null, "roster actor lookup null for dead A")
				_check(not _roster._actors.has("mercenary_A"), "roster _actors no longer holds dead A")
				_check(_roster.get_mercenary("mercenary_A") != null, "dead A data still retrievable from roster")
				_check(_roster.get_mercenary("mercenary_A").alive == false, "roster reports dead A as dead")
				if _e3 != null and is_instance_valid(_e3):
					_check(_e3.get("_target") == null, "enemy cleared target reference after merc death")
					_check(_e3.state == EnemyActor.EnemyState.MOVE, "enemy resumed MOVE after target death")
				if _e3 != null and is_instance_valid(_e3):
					_e3.queue_free()
				_wait_frames(2)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "E3 cleaned after merc death test")
				_enter(Phase.NO_RESPAWN)
		Phase.NO_RESPAWN:
			if _sub == 0:
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase DAY after merc death")
				_check(_count_mercenaries() == 0, "no mercenary actor during DAY after death (%d)" % _count_mercenaries())
				_check(_roster.get_actor_count() == 0, "roster actor_count 0 after DAY despawn")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "next NIGHT after death")
				_check(_count_mercenaries() == 1, "only alive mercenary (B) spawned next NIGHT (%d)" % _count_mercenaries())
				_check(_roster.get_actor("mercenary_A") == null, "dead A NOT re-spawned next NIGHT")
				var b_actor: Node = _roster.get_actor("mercenary_B")
				_check(b_actor != null, "alive B actor spawned next NIGHT")
				if b_actor != null:
					_check(b_actor.merc_data.id == "mercenary_B", "spawned actor is mercenary_B")
				_check(_roster.get_actor_count() == 1, "roster actor_count 1 (no duplicate)")
				_spawner.despawn_encounter()
				_wait_frames(2)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_spawner._enemies.size() == 0, "spawner tracking empty after despawn")
				_enter(Phase.REPEAT_CYCLE)
		Phase.REPEAT_CYCLE:
			if _sub == 0:
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "repeat cycle: DAY")
				_check(_count_mercenaries() == 0, "repeat cycle: no mercenary actor during DAY")
				_check(_roster._actors.size() == 0, "repeat cycle: roster _actors empty on DAY")
				_check(_spawner._enemies.size() == 0, "repeat cycle: spawner _enemies empty on DAY")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "repeat cycle: NIGHT #1")
				_check(_count_mercenaries() == 1, "repeat cycle: exactly 1 mercenary (alive B only) (%d)" % _count_mercenaries())
				_check(_roster.get_actor_count() == 1, "repeat cycle: roster actor_count 1")
				_check(_roster.get_actor("mercenary_A") == null, "repeat cycle: dead A never re-spawned")
				_check(_spawner.get_enemy_count() == 3, "repeat cycle: encounter #1 spawned 3 enemies")
				for e in _spawner.get_enemies():
					if is_instance_valid(e):
						e.take_damage(99999)
				_wait_frames(4)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_spawner._enemies.size() == 0, "repeat cycle: dead enemies removed from spawner tracking (no leak)")
				_check(_count_enemies() == 0, "repeat cycle: dead enemies freed (%d)" % _count_enemies())
				_check(_roster._actors.size() == 1, "repeat cycle: roster _actors still 1 (no duplicate)")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "repeat cycle: DAY after cycle #1")
				_check(_roster._actors.size() == 0, "repeat cycle: roster _actors empty after DAY")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 5 and not _waited():
				return false
			elif _sub == 5:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "repeat cycle: NIGHT #2")
				_check(_count_mercenaries() == 1, "repeat cycle: exactly 1 mercenary again (no duplicate)")
				_check(_spawner.get_enemy_count() == 3, "repeat cycle: encounter #2 spawned")
				for e in _spawner.get_enemies():
					if is_instance_valid(e):
						e.take_damage(99999)
				_wait_frames(4)
			elif _sub == 6 and not _waited():
				return false
			elif _sub == 6:
				_check(_spawner._enemies.size() == 0, "repeat cycle: no accumulated dead enemy references after 2 cycles")
				_check(_count_enemies() == 0, "repeat cycle: enemies freed after cycle #2")
				_check(_roster.get_actor_count() == 1, "repeat cycle: actor_count 1 at end")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 7 and not _waited():
				return false
			elif _sub == 7:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "repeat cycle: final DAY")
				_check(_roster.get_count() == 2, "repeat cycle: both mercenary data retained (%d)" % _roster.get_count())
				var a: MercenaryData = _roster.get_mercenary("mercenary_A")
				var bb: MercenaryData = _roster.get_mercenary("mercenary_B")
				_check(a != null and a.alive == false, "repeat cycle: dead A stays dead in roster")
				_check(bb != null and bb.alive == true, "repeat cycle: alive B stays alive in roster")
				_check(_roster.get_alive().size() == 1, "repeat cycle: get_alive returns only B")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "regression at DAY")
				_check(_count_mercenaries() == 0, "no mercenary actor during final DAY (%d)" % _count_mercenaries())
				_check(_roster._actors.size() == 0, "roster _actors empty at DAY end")
				_check(_spawner._enemies.size() == 0, "spawner holds no stale enemy references at end")
				_check(not _player.has_method("attack") and not _player.has_method("_attack"), "player has no attack method")
				_check(not _player.is_in_group("enemies") and not _player.is_in_group("mercenaries"), "player excluded from enemy/mercenary target groups")
				_check(_worker_roster.get_count() == 0, "worker roster unaffected (%d)" % _worker_roster.get_count())
				_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor spawned")
				_check(get_nodes_in_group("miners").size() == 0, "no miner actor spawned")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact")
				var gate := _find_gate_at(GATE_POS)
				_check(gate != null, "north gate still present")
				if gate != null:
					gate.set_open(true)
					gate.set_open(false)
					_check(gate.is_closed(), "gate toggle still works")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0146_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)