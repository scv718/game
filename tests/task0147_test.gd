extends SceneTree

## TASK-014-7 First Auto Combat 통합 검증.
## TASK-014-1~014-6의 개별 기능을 하나의 연속 시나리오로 묶어 검증한다.
##
## 시나리오:
##  1. 주점에서 Mercenary 고용 (TASK-014-1).
##  2. 여관에서 NORTH defense assignment (TASK-014-2).
##  3. North Gate 준비 (TASK-013).
##  4. NIGHT → Mercenary Actor spawn (TASK-014-2).
##  5. Enemy spawn (TASK-014-3).
##  6. Enemy approach (road waypoint를 따라 마을 쪽 접근).
##  7. Mercenary auto target/chase/attack (TASK-014-4).
##  8. 양측 HP 변화 (merc↔enemy 상호 공격).
##  9. Enemy death (TASK-014-4/6).
## 10. Mercenary 사망 별도 검증 (TASK-014-4/6).
## 11. CLOSED Gate attack/breach (TASK-014-5).
## 12. DAY cleanup (TASK-014-6).
## 13. 다음 NIGHT duplicate/reference 오류 없음 (TASK-014-6).
## 회귀: Player attack 없음, NIGHT Player 이동 비활성, Worker 무spawn,
##       핵심 건물/floor/gate/Wall nav 유지.

enum Phase {
	SETUP,
	HIRE_ASSIGN,
	GATE_WALL,
	NIGHT_READY,
	COMBAT_KILL,
	MERC_DEATH,
	GATE_BREACH,
	DAY_CLEANUP,
	NEXT_NIGHT,
	REGRESSION,
	DONE,
}

const GATE_POS := Vector2(0, -448)
const NORTH_RALLY := Vector2(0, -280)
const BUDGET := 2000
const NAV_SETTLE_PF := 90

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
var _player: Node = null
var _mercenary: MercenaryData = null
var _actor: Node = null
var _gate: Node = null

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


func _wait_frames(n: int) -> void:
	_wait = n
	_sub += 1


func _waited() -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	return true


func _finish() -> void:
	print("TASK0147_RESULT=" + ("FAIL" if _failed else "PASS"))
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
		var g := node as Node2D
		if g == null:
			continue
		if (g.position - pos).length_squared() < 1.0:
			return node
	return null


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


func _clear_test_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()


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
				_player = root.get_node("Main").get_node("Player")
				_check(_game_time != null and _world != null and _placement != null \
					and _spawner != null and _roster != null and _worker_roster != null \
					and _resources != null and _player != null, "core nodes present")
				_resources._amounts["wood"] = 10000
				_check(_roster.get_count() == 0, "mercenary roster starts empty")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.HIRE_ASSIGN)
		Phase.HIRE_ASSIGN:
			if _sub == 0:
				var ui: Control = get_first_node_in_group("recruitment_ui")
				_check(ui != null, "recruitment UI present")
				ui._on_mercenary_hire_pressed("mercenary_A")
				_mercenary = _roster.get_mercenary("mercenary_A")
				_check(_mercenary != null and _mercenary.alive, "mercenary_A hired alive")
				if _mercenary != null:
					_mercenary.set_defense_zone(MercenaryData.DefenseZone.NORTH)
					_mercenary.max_hp = 80
					_mercenary.attack_damage = 25
					_mercenary.attack_interval = 0.05
					_mercenary.move_speed = 120.0
					_check(_mercenary.defense_zone == MercenaryData.DefenseZone.NORTH, "defense zone set NORTH")
				_check(_roster.get_count() == 1, "roster holds 1 mercenary")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.GATE_WALL)
		Phase.GATE_WALL:
			if _sub == 0:
				_placement._set_building_type("gate")
				_placement._try_place_gate_at(_placement._snap_gate(GATE_POS))
				_gate = _find_gate_at(GATE_POS)
				_check(_gate != null, "north gate placed")
				_check(_gate != null and _gate.is_closed(), "gate starts CLOSED")
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf >= NAV_SETTLE_PF:
					_enter(Phase.NIGHT_READY)
		Phase.NIGHT_READY:
			if _sub == 0:
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT")
				_check(_player.get("_night_mode") == true, "player night mode active (movement disabled)")
				_check(_count_mercenaries() == 1, "mercenary actor spawned at NIGHT (%d)" % _count_mercenaries())
				_actor = _roster.get_actor("mercenary_A")
				_check(_actor != null, "actor retrievable by id")
				if _actor != null:
					_check(_actor.merc_data == _mercenary, "actor references roster MercenaryData")
					_check(_actor.current_hp == 80, "actor current_hp from max_hp (80)")
					var pos: Vector2 = (_actor as Node2D).global_position
					_check(pos.distance_to(NORTH_RALLY) < 1.0, "actor at north rally (pos=%s)" % pos)
					_check(_actor.get_state() == MercenaryActor.MercState.IDLE, "actor starts IDLE")
				_check(_count_enemies() >= 1, "auto-encounter spawned enemies at NIGHT (%d)" % _count_enemies())
				_sub = 2
				_pf = 0
			elif _sub == 2:
				if _pf >= 30:
					var approaching := false
					for e in get_nodes_in_group("enemies"):
						if not is_instance_valid(e):
							continue
						if e.get("state") == EnemyActor.EnemyState.MOVE:
							approaching = true
					_check(approaching, "enemies approach village via road (MOVE)")
					_spawner.despawn_encounter()
					_wait_frames(2)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "auto-encounter cleaned (%d)" % _count_enemies())
				_enter(Phase.COMBAT_KILL)
		Phase.COMBAT_KILL:
			if _sub == 0:
				var e1 := _spawn_enemy(Vector2(0, -360), 80, true)
				var e2 := _spawn_enemy(Vector2(16, -370), 80, true)
				_check(e1 != null and e2 != null, "2 test enemies spawned near defense zone (approach MOVE)")
				if e1 != null:
					e1.attack_damage = 5
					e1.attack_interval = 0.1
				if e2 != null:
					e2.attack_damage = 5
					e2.attack_interval = 0.1
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _count_enemies() == 0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "enemies never killed by mercenary in budget (enemies=%d)" % _count_enemies())
					_wait_frames(4)
				else:
					_budget += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(true, "enemies killed by mercenary auto combat")
				_check(_count_enemies() == 0, "dead enemies excluded from enemies group")
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() == null, "mercenary target cleared after kill")
					_check(_actor.get_state() == MercenaryActor.MercState.IDLE \
						or _actor.get_state() == MercenaryActor.MercState.ACQUIRE_TARGET,
						"mercenary returned to idle/acquire after kill")
					_check(_actor.current_hp < 80, "mercenary HP decreased during combat (%d < 80)" % _actor.current_hp)
				_enter(Phase.MERC_DEATH)
		Phase.MERC_DEATH:
			if _sub == 0:
				var strong := _spawn_enemy(Vector2(0, -340), 100000, true)
				_check(strong != null, "strong enemy spawned for merc death test")
				if strong != null:
					strong.attack_damage = 30
					strong.attack_interval = 0.05
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
				_check(_mercenary.alive == false, "MercenaryData.alive=false on death")
				_check(_count_mercenaries() == 0, "dead merc removed from mercenaries group (%d)" % _count_mercenaries())
				_check(_roster.get_actor("mercenary_A") == null, "roster actor null for dead merc")
				_check(not _roster._actors.has("mercenary_A"), "roster _actors no longer holds dead merc")
				_check(_roster.get_mercenary("mercenary_A") != null, "dead merc data still retrievable")
				_check(_roster.get_mercenary("mercenary_A").alive == false, "roster reports dead merc as dead")
				_clear_test_enemies()
				_wait_frames(3)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "enemies cleaned after merc death test")
				_enter(Phase.GATE_BREACH)
		Phase.GATE_BREACH:
			if _sub == 0:
				_gate = _find_gate_at(GATE_POS)
				_check(_gate != null, "gate present for breach test")
				_check(_gate != null and _gate.is_closed(), "gate is CLOSED before breach test")
				if _gate != null:
					_gate.max_hp = 80
					_gate.current_hp = 80
				var breacher := _spawn_enemy(Vector2(0, -460), 100000, true)
				_check(breacher != null, "breach enemy spawned near gate")
				if breacher != null:
					breacher.attack_damage = 50
					breacher.attack_interval = 0.03
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _gate == null or not is_instance_valid(_gate):
					_wait_frames(4)
				elif _gate.is_breached():
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "gate never breached in budget (hp=%d)" % (_gate.current_hp if _gate != null else -1))
					_wait_frames(4)
				else:
					_budget += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_gate.is_breached(), "gate BREACHED after enemy attack")
				_check(_gate.is_open(), "breached gate is open (passage open)")
				_check(_gate.get_node_or_null("CollisionShape2D") == null, "breached gate: collision shape removed")
				_enter(Phase.DAY_CLEANUP)
		Phase.DAY_CLEANUP:
			if _sub == 0:
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_enemies() == 0, "enemies cleaned before DAY (%d)" % _count_enemies())
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase is DAY after cleanup")
				_check(_count_mercenaries() == 0, "no mercenary actor during DAY (%d)" % _count_mercenaries())
				_check(_roster.get_actor_count() == 0, "roster actor_count 0 during DAY")
				_check(_spawner._enemies.size() == 0, "spawner _enemies empty during DAY")
				_check(_player.get("_night_mode") == false, "player night mode off at DAY")
				_enter(Phase.NEXT_NIGHT)
		Phase.NEXT_NIGHT:
			if _sub == 0:
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "next NIGHT arrived")
				_check(_count_mercenaries() == 0, "dead merc NOT re-spawned next NIGHT (%d)" % _count_mercenaries())
				_check(_roster.get_actor_count() == 0, "roster actor_count 0 (dead not spawned)")
				_check(_spawner.get_enemy_count() == 3, "auto-encounter spawned (%d)" % _spawner.get_enemy_count())
				_check(_spawner._enemies.size() == 3, "spawner tracking has no stale references (%d)" % _spawner._enemies.size())
				_check(_roster.get_count() == 1, "roster data retained (%d)" % _roster.get_count())
				var a: MercenaryData = _roster.get_mercenary("mercenary_A")
				_check(a != null and a.alive == false, "dead merc stays dead in roster")
				_spawner.despawn_encounter()
				_wait_frames(2)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_spawner._enemies.size() == 0, "spawner tracking empty after despawn")
				_check(_count_enemies() == 0, "no stale enemies after despawn (%d)" % _count_enemies())
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(not _player.has_method("attack") and not _player.has_method("_attack"), "player has no attack method")
				_check(not _player.is_in_group("enemies") and not _player.is_in_group("mercenaries"), "player excluded from combat groups")
				_check(_player.get("_night_mode") == true, "player night mode active during NIGHT regression")
				_check(_worker_roster.get_count() == 0, "worker roster unaffected (%d)" % _worker_roster.get_count())
				_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor spawned")
				_check(get_nodes_in_group("miners").size() == 0, "no miner actor spawned")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact")
				_gate = _find_gate_at(GATE_POS)
				_check(_gate != null, "gate still present in regression")
				if _gate != null:
					_check(_gate.is_breached(), "gate remains breached (no auto-recovery)")
				_check(_spawner._enemies.size() == 0, "spawner holds no stale references at end")
				_check(_roster._actors.size() == 0, "roster _actors empty at end")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0147_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
