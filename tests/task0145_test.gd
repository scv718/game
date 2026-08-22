extends SceneTree

## TASK-014-5 CLOSED Gate 대응 + Gate Breach 자동 검증.
##  - Gate: prototype 내구도(max_hp/current_hp) 보유. CLOSED 성문을 Enemy가 공격 가능하고,
##    HP 0 → BREACHED(파괴/침입) → passage 영구 개방. 자동 복구 금지(set_open no-op on BREACHED).
##  - OPEN 성문은 Enemy가 공격하지 않고 통과(take_damage no-op).
##  - CLOSED→BREACHED 시 collision shape 제거 + nav 통과 가능하도록 갱신.
##  - enemy는 성문이 BREACHED(또는 OPEN)되면 MOVE 재개해 마을 방향으로 진행.
##  - 성문 공격(GATE_ATTACK) 중에도 살아 있는 대상이므로 Mercenary와 교전 가능.
##  - Wall 직접 공격 없음(이번 Enemy는 Gate 접근 선호).
##  - 회귀: Player 무공격, Worker 무spawn, 핵심 건물/floor 유지.

enum Phase {
	SETUP,
	OPEN_NO_ATTACK,
	GATE_ATTACK,
	BREACH,
	MERC_ENGAGE,
	REGRESSION,
	DONE,
}

const GATE_POS := Vector2(0, -448)
const GATE2_POS := Vector2(0, -384)
const GATE_RECT := Rect2(Vector2(-24, -456), Vector2(48, 16))
const GATE_OUTSIDE := Vector2(0, -560)
const GATE_INSIDE := Vector2(0, -360)
const NORTH_RALLY := Vector2(0, -280)
const VILLAGE_CORE := Vector2(0, -150)

const NAV_SETTLE_PF := 90
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
var _gate: Node = null
var _gate2: Node = null
var _mercenary: MercenaryData = null
var _actor: Node = null

var _enemy_seq := 0
var _budget := 0
var _breach_signal_count := 0
var _breach_y := 0.0


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
	print("TASK0145_RESULT=" + ("FAIL" if _failed else "PASS"))
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


## 테스트용 Enemy. route(final target = 마을 core)를 설정해 MOVE 상태로 만든다.
func _spawn_enemy(pos: Vector2, hp := 60) -> EnemyActor:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate() as EnemyActor
	if enemy == null:
		return null
	enemy.max_hp = hp
	enemy.setup("test_enemy_%d" % _enemy_seq, "Raider", "north")
	enemy.position = pos
	_world.add_child(enemy)
	_enemy_seq += 1
	enemy.set_route([], VILLAGE_CORE)
	return enemy


func _clear_test_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()


## nav geometry helpers (TASK-013-5/013-6/014-3와 동일).
func _cross(p: Vector2, q: Vector2, r: Vector2) -> float:
	return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)


func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var o1 := _cross(a, b, c)
	var o2 := _cross(a, b, d)
	var o3 := _cross(c, d, a)
	var o4 := _cross(c, d, b)
	return ((o1 > 0.0 and o2 < 0.0) or (o1 < 0.0 and o2 > 0.0)) \
		and ((o3 > 0.0 and o4 < 0.0) or (o3 < 0.0 and o4 > 0.0))


func _segment_in_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var edges: Array = [
		[rect.position, rect.position + Vector2(rect.size.x, 0.0)],
		[rect.position + Vector2(rect.size.x, 0.0), rect.end],
		[rect.end, rect.position + Vector2(0.0, rect.size.y)],
		[rect.position + Vector2(0.0, rect.size.y), rect.position],
	]
	for edge in edges:
		if _segments_cross(a, b, edge[0], edge[1]):
			return true
	return false


func _path_crosses_rect(path: PackedVector2Array, rect: Rect2) -> bool:
	if path.size() < 2:
		return false
	for i in range(1, path.size()):
		if _segment_in_rect(path[i - 1], path[i], rect):
			return true
	return false


func _path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	return NavigationServer2D.map_get_path(nav_map, a, b, true)


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
				_spawner.set_direction("north")
				_roster = root.get_node("MercenaryRoster")
				_worker_roster = root.get_node("WorkerRoster")
				_resources = root.get_node("VillageResources")
				_check(_game_time != null and _world != null and _layout != null and _placement != null \
					and _spawner != null and _roster != null and _worker_roster != null and _resources != null,
					"core nodes present")
				_resources._amounts["wood"] = 10000
				var ui: Control = get_first_node_in_group("recruitment_ui")
				_check(ui != null, "recruitment UI present")
				ui._on_mercenary_hire_pressed("mercenary_A")
				_mercenary = _roster.get_mercenary("mercenary_A")
				_check(_mercenary != null, "mercenary_A hired into roster")
				if _mercenary != null:
					_mercenary.set_defense_zone(MercenaryData.DefenseZone.NONE)
				_placement._set_building_type("gate")
				_placement._try_place_gate_at(_placement._snap_gate(GATE_POS))
				_gate = _find_gate_at(GATE_POS)
				_check(_gate != null, "north gate placed in corridor")
				if _gate != null:
					_check(_gate.is_closed(), "new gate starts CLOSED")
					_check(_gate.max_hp > 0 and _gate.current_hp == _gate.max_hp, "gate has prototype durability (max_hp/current_hp)")
					_check(not _gate.is_breached(), "new gate not breached")
					_gate.breached.connect(_on_gate_breached)
				_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor (Player never fights)")
				_check(EnemyActor.EnemyState.size() == 4, "EnemyState has 4 states (GATE_ATTACK added)")
				_check(Gate.GateState.size() == 3, "GateState has 3 states (BREACHED added)")
				_check(EnemyActor.EnemyState.GATE_ATTACK == 3, "GATE_ATTACK constant intact")
				_enter(Phase.OPEN_NO_ATTACK)
		Phase.OPEN_NO_ATTACK:
			if _sub == 0:
				_gate.set_open(true)
				_check(_gate.is_open(), "gate set OPEN")
				var e := _spawn_enemy(GATE_POS + Vector2(0, -22), 100000)
				_check(e != null, "enemy spawned near OPEN gate")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _budget >= 30:
					var e := _find_near_gate_enemy()
					if e != null:
						_check(e.state != EnemyActor.EnemyState.GATE_ATTACK, "enemy does NOT attack OPEN gate (stays MOVE)")
						_check(e.get_gate_target() == null, "enemy gate_target null for OPEN gate")
					# OPEN 성문은 공격 대상이 아니므로 take_damage no-op.
					var hp_before: int = _gate.current_hp
					_gate.take_damage(999)
					_check(_gate.current_hp == hp_before, "OPEN gate take_damage no-op (no damage, no breach)")
					_check(_gate.is_open() and not _gate.is_breached(), "OPEN gate unaffected by damage")
					_clear_test_enemies()
					_gate.set_open(false)
					_check(_gate.is_closed(), "gate back to CLOSED")
					_pf = 0
					_enter(Phase.GATE_ATTACK)
				else:
					_budget += 1
		Phase.GATE_ATTACK:
			if _sub == 0:
				if _gate != null:
					_gate.max_hp = 100
					_gate.current_hp = 100
				var e := _spawn_enemy(GATE_POS + Vector2(0, -22), 100000)
				_check(e != null, "enemy spawned near CLOSED gate")
				if e != null:
					e.attack_damage = 50
					e.attack_interval = 0.05
				_budget = 0
				_sub = 1
			elif _sub == 1:
				var e := _find_near_gate_enemy()
				if e != null and e.state == EnemyActor.EnemyState.GATE_ATTACK and _gate != null and _gate.current_hp < 100:
					_check(true, "enemy entered GATE_ATTACK on CLOSED gate (state=%s)" % str(e.state))
					_check(e.get_gate_target() == _gate, "enemy gate_target is the CLOSED gate")
					_check(_gate.current_hp < 100, "gate HP decreased by enemy attack (hp=%d)" % _gate.current_hp)
					_check(_gate.is_closed(), "gate still CLOSED (not yet breached)")
					_enter(Phase.BREACH)
				elif _budget >= BUDGET:
					_check(false, "enemy never attacked CLOSED gate in budget (state=%s, gatehp=%s)" \
						% [str(e.state if e != null else "?"), str(_gate.current_hp if _gate != null else "?")])
					_enter(Phase.BREACH)
				else:
					_budget += 1
		Phase.BREACH:
			if _sub == 0:
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _gate != null and _gate.is_breached():
					_wait_frames(2)
				elif _budget >= BUDGET:
					_check(false, "gate never breached in budget (state=%s hp=%d)" % [str(_gate.state if _gate != null else "?"), _gate.current_hp if _gate != null else -1])
					_enter(Phase.MERC_ENGAGE)
				else:
					_budget += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_gate.is_breached(), "gate BREACHED after HP 0")
				_check(not _gate.is_closed(), "breached gate is no longer CLOSED")
				_check(_gate.is_open(), "breached gate passage open")
				_check(_gate.get_node_or_null("CollisionShape2D") == null, "BREACHED gate collision shape removed")
				_check(_breach_signal_count == 1, "breached signal emitted exactly once")
				# 자동 복구 금지: BREACHED 성문은 set_open(false)로 다시 닫을 수 없다.
				_gate.set_open(false)
				_check(_gate.is_breached(), "BREACHED gate no auto-recovery (set_open no-op)")
				_check(_gate.is_open(), "BREACHED gate stays open")
				var e := _find_near_gate_enemy()
				_check(e != null and e.state == EnemyActor.EnemyState.MOVE, "enemy resumes MOVE after gate breached")
				_pf = 0
				_breach_y = (e as Node2D).global_position.y if e != null else 0.0
				_sub = 3
			elif _sub == 3:
				if _pf < NAV_SETTLE_PF:
					return false
				_check(_path_crosses_rect(_path(GATE_OUTSIDE, GATE_INSIDE), GATE_RECT), "BREACHED: nav path crosses gate footprint (passage open)")
				var e := _find_near_gate_enemy()
				if e != null:
					_check((e as Node2D).global_position.y > _breach_y + 8.0, "enemy proceeds toward village after breach (y %.1f -> %.1f)" % [_breach_y, (e as Node2D).global_position.y])
				_clear_test_enemies()
				_enter(Phase.MERC_ENGAGE)
		Phase.MERC_ENGAGE:
			if _sub == 0:
				# 새 CLOSED 성문(두 번째) + NORTH 방어 용병으로 Gate 앞 교전 검증.
				_placement._set_building_type("gate")
				_placement._try_place_gate_at(_placement._snap_gate(GATE2_POS))
				_gate2 = _find_gate_at(GATE2_POS)
				_check(_gate2 != null and _gate2.is_closed(), "second north gate placed CLOSED")
				if _mercenary != null:
					_mercenary.set_defense_zone(MercenaryData.DefenseZone.NORTH)
					_mercenary.max_hp = 1000
					_mercenary.attack_damage = 30
					_mercenary.attack_interval = 0.05
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT for merc engagement")
				# 자동 조우 3명은 격리하기 위해 정리.
				_spawner.despawn_encounter()
				_wait_frames(2)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_actor = _roster.get_actor("mercenary_A")
				_check(_actor != null, "mercenary actor spawned at NIGHT (north rally)")
				_check(_count_mercenaries() == 1, "one mercenary actor present (%d)" % _count_mercenaries())
				var e := _spawn_enemy(GATE2_POS + Vector2(0, -22), 100000)
				_check(e != null, "enemy spawned near CLOSED gate2")
				if e != null:
					e.attack_damage = 8
					e.attack_interval = 1.0
				var enemy_hp0: int = e.current_hp if e != null else -1
				_budget = 0
				_sub = 3
			elif _sub == 3:
				var e := _find_near_gate_enemy()
				if e != null and e.state == EnemyActor.EnemyState.GATE_ATTACK and e.get_gate_target() == _gate2:
					_check(true, "enemy in GATE_ATTACK on gate2 (front of gate)")
					_check(_actor != null and _actor.get_target() == e, "mercenary acquired the gate-front enemy as target")
					var eng_state: int = _actor.get_state() if _actor != null else -1
					_check(eng_state == MercenaryActor.MercState.MOVE_TO_TARGET or eng_state == MercenaryActor.MercState.ATTACK, "mercenary engaged enemy (state=%s)" % str(eng_state))
					_sub = 4
				elif _budget >= BUDGET:
					_check(false, "mercenary/enemy never engaged at gate front in budget")
					_sub = 4
				else:
					_budget += 1
			elif _sub == 4:
				var e := _find_near_gate_enemy()
				if e != null and e.current_hp < 100000:
					_check(true, "mercenary damaged enemy while enemy in GATE_ATTACK (enemy hp %d)" % e.current_hp)
					_clear_test_enemies()
					_mercenary.set_defense_zone(MercenaryData.DefenseZone.NONE)
					_advance_to_next_phase()
					_wait_frames(3)
				elif _budget >= BUDGET:
					_check(false, "mercenary never damaged gate-front enemy in budget")
					_clear_test_enemies()
					_mercenary.set_defense_zone(MercenaryData.DefenseZone.NONE)
					_advance_to_next_phase()
					_wait_frames(3)
				else:
					_budget += 1
			elif _sub == 5 and not _waited():
				return false
			elif _sub == 5:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase back to DAY")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(_count_mercenaries() == 0, "no mercenary actor during DAY regression")
				_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor (Player never fights)")
				_check(_worker_roster.get_count() == 0, "worker roster unaffected (%d)" % _worker_roster.get_count())
				_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor spawned")
				_check(get_nodes_in_group("miners").size() == 0, "no miner actor spawned")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact")
				_check(_gate != null and _gate.is_breached(), "gate1 remains breached at end")
				_check(_gate2 != null and _gate2.is_closed(), "gate2 remains CLOSED at end")
				_check(Gate.GateState.BREACHED == 2, "GateState.BREACHED constant intact")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0145_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _on_gate_breached(_gate: Node) -> void:
	_breach_signal_count += 1


## gate 근처(본 태스크에서 spawn한) test enemy를 그룹에서 찾아 반환.
func _find_near_gate_enemy() -> Node:
	for e in get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var eid = e.get("enemy_id")
		if eid != null and String(eid).begins_with("test_enemy_"):
			return e
	return null


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
