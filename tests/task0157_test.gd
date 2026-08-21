extends SceneTree

## TASK-015-7 Command AI Priority 검증.
## 전술 명령(DEAD/RETREAT/REGROUP/FOCUS_TARGET/DEFENSE_ZONE) 간 우선순위와
## 서로 모순되는 명령이 연속으로 내려질 때 새 명령이 이전 transient 명령을
## 명확히 덮는지, 그리고 무한 누적(contradictory state 축적)/deadlock이 없는지
## 검증한다. 범용 Command Framework는 만들지 않는다.
##
## 권장 priority (높을수록 우선):
##   1. DEAD
##   2. RETREAT
##   3. REGROUP
##   4. FOCUS TARGET
##   5. DEFENSE ZONE AUTO COMBAT
##
## 자동검증 항목:
##  1. DEFENSE ZONE AUTO COMBAT(5)이 기본: 구역 내 Enemy를 자동 target 획득/추격.
##  2. FOCUS TARGET(4) > DEFENSE ZONE(5): focus Enemy를 우선 target으로 삼음.
##  3. REGROUP(3) > FOCUS(4): focus 중 REGROUP 명령 시 target 클리어 + REGROUP 진입,
##     이동 중 target 획득 억제, 도착 후 focus 재획득.
##  4. RETREAT(2) > REGROUP(3): REGROUP 중 RETREAT 명령 시 RETREAT로 덮음,
##     이동 중/도착 후에도 공격·target 획득 중지.
##  5. DEFENSE ZONE 명령(5) > transient(RETREAT/REGROUP): RETREAT 중 새 방어 명령으로
##     일반 방어 AI 복귀 + 재교전.
##  6. RAPID OVERRIDE: 모순 명령(REGROUP→RETREAT→REGROUP→DEFENSE) 연속 발동 후에도
##     상태 누적 없이 생산적 상태로 정착(deadlock 없음).
##  7. DEAD(1): 사망 후 모든 명령이 안전한 no-op(크래시 없음, 재생성 없음).
##  8. 회귀: Player 무공격/무타겟, NIGHT 이동 비활성, 핵심 건물 5/floor 유지.

enum Phase {
	SETUP,
	HIRE_NORTH,
	TO_NIGHT,
	SPAWN_ACTOR,
	BASE_COMBAT,
	FOCUS_SET,
	REGROUP_OVERRIDE,
	REGROUP_RESUME,
	RETREAT_OVERRIDE,
	RETREAT_HOLD,
	DEFENSE_RECOVER,
	RAPID_OVERRIDE,
	DEAD_PRIORITY,
	REGRESSION,
	DONE,
}

const NORTH_RALLY := Vector2(0, -280)
const EAST_RALLY := Vector2(280, 0)
const NAV_SETTLE_PF := 90
const BUDGET := 10000

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _wait := 0
var _failed := false

var _game_time: Node = null
var _world: Node = null
var _roster: Node = null
var _resources: Node = null
var _player: Node = null
var _hud: Node = null
var _tac = null
var _mercenary: MercenaryData = null
var _actor: Node = null

var _enemy_seq := 0
var _budget := 0
var _prev_pos := Vector2.ZERO
var _suppress_ok := true
var _safe_rally := Vector2.ZERO
var _focus_enemy: EnemyActor = null
var _zone_enemy: EnemyActor = null


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
	print("TASK0157_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _count_enemies() -> int:
	return get_nodes_in_group("enemies").size()


func _count_mercenaries() -> int:
	return get_nodes_in_group("mercenaries").size()


func _spawn_enemy(pos: Vector2, hp := 80, dmg := 1) -> EnemyActor:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate() as EnemyActor
	if enemy == null:
		return null
	enemy.max_hp = hp
	enemy.current_hp = hp
	enemy.attack_damage = dmg
	enemy.attack_interval = 0.05
	enemy.setup("t0157_enemy_%d" % _enemy_seq, "Raider", "north")
	enemy.position = pos
	_world.add_child(enemy)
	_enemy_seq += 1
	return enemy


func _clear_test_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()


func _wait_target(timeout_msg: String) -> void:
	if _budget >= BUDGET:
		_check(false, timeout_msg)
		_wait_frames(4)
	elif _actor != null and is_instance_valid(_actor) and _actor.get_target() != null:
		_wait_frames(2)
	else:
		_budget += 1


func _wait_state(target_state: int, timeout_msg: String) -> void:
	if _budget >= BUDGET:
		_check(false, timeout_msg)
		_wait_frames(4)
	elif _actor != null and is_instance_valid(_actor) and _actor.get_state() == target_state:
		_wait_frames(2)
	else:
		_budget += 1


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			if _sub == 0:
				_game_time = root.get_node("GameTime")
				_game_time.set_auto_advance(false)
				_game_time.set_durations(2.0, 1.0)
				_world = root.get_node("Main").get_node("World")
				_roster = root.get_node("MercenaryRoster")
				_resources = root.get_node("VillageResources")
				_player = root.get_node("Main").get_node("Player")
				_hud = root.get_node("Main").get_node("HUD")
				_tac = _hud.get_node_or_null("TacticalCommandUI")
				_check(_game_time != null and _world != null and _roster != null \
					and _player != null and _hud != null and _tac != null, "core nodes present")
				_resources._amounts["wood"] = 10000
				_check(_roster.get_count() == 0, "mercenary roster starts empty")
				_safe_rally = _roster.get_safe_rally(_world)
				_sub = 1
			elif _sub == 1:
				_enter(Phase.HIRE_NORTH)
		Phase.HIRE_NORTH:
			if _sub == 0:
				var ui: Control = get_first_node_in_group("recruitment_ui")
				_check(ui != null, "recruitment UI present")
				ui._on_mercenary_hire_pressed("mercenary_A")
				_mercenary = _roster.get_mercenary("mercenary_A")
				_check(_mercenary != null and _mercenary.alive, "mercenary_A hired alive")
				if _mercenary != null:
					_mercenary.set_defense_zone(MercenaryData.DefenseZone.NORTH)
					_mercenary.attack_damage = 30
					_mercenary.attack_interval = 0.05
					_mercenary.move_speed = 120.0
					_check(_mercenary.defense_zone == MercenaryData.DefenseZone.NORTH, "defense zone NORTH")
				_enter(Phase.TO_NIGHT)
		Phase.TO_NIGHT:
			if _sub == 0:
				_game_time.advance(2.0)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT")
				_check(_player.get("_night_mode") == true, "player night mode active")
				_enter(Phase.SPAWN_ACTOR)
		Phase.SPAWN_ACTOR:
			if _sub == 0:
				_check(_count_mercenaries() == 1, "mercenary actor spawned at NIGHT")
				_actor = _roster.get_actor("mercenary_A")
				_check(_actor != null, "actor retrievable")
				if _actor != null:
					_check((_actor as Node2D).global_position.distance_to(NORTH_RALLY) < 1.0,
						"actor at north rally (%s)" % str((_actor as Node2D).global_position))
					_check(_actor.get_state() == MercenaryActor.MercState.IDLE, "actor starts IDLE")
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf >= NAV_SETTLE_PF:
					_enter(Phase.BASE_COMBAT)
		Phase.BASE_COMBAT:
			# priority 5: DEFENSE ZONE AUTO COMBAT 기본 동작.
			if _sub == 0:
				_check(_spawn_enemy(Vector2(0, -350), 80, 1) != null, "enemy spawned near north zone")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				_wait_target("mercenary never acquired zone target (auto combat)")
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() != null, "priority5: zone auto-combat acquired target")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "base combat enemy cleaned")
				_enter(Phase.FOCUS_SET)
		Phase.FOCUS_SET:
			# priority 4 > 5: focus target beats zone auto-combat.
			if _sub == 0:
				_zone_enemy = _spawn_enemy(Vector2(0, -350))
				_check(_zone_enemy != null, "zone enemy spawned")
				_focus_enemy = _spawn_enemy(Vector2(50, -350))
				_check(_focus_enemy != null, "focus candidate enemy spawned")
				_roster.set_focus_target(_focus_enemy)
				_check(_roster.has_focus_target() == true, "focus target set")
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_focus_target() == _focus_enemy, "actor received focus target")
				_wait_frames(8)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.is_focusing(), "priority4: actor focusing focus enemy")
					_check(_actor.get_target() == _focus_enemy,
						"priority4: focus beats zone enemy (target==focus)")
				_enter(Phase.REGROUP_OVERRIDE)
		Phase.REGROUP_OVERRIDE:
			# priority 3 > 4: REGROUP 명령이 focus/combat을 덮는다.
			if _sub == 0:
				_prev_pos = (_actor as Node2D).global_position
				_tac.get_regroup_button().pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.REGROUP,
						"priority3: REGROUP overrides focus (state=%d)" % _actor.get_state())
					_check(_actor.get_target() == null, "REGROUP clears current target")
				_budget = 0
				_pf = 0
				_sub = 1
			elif _sub == 1:
				# 이동 중 target 획득 억제 + teleport 금지.
				if _actor != null and is_instance_valid(_actor):
					var cur: Vector2 = (_actor as Node2D).global_position
					if cur.distance_to(_prev_pos) > 400.0:
						_check(false, "teleport during regroup (delta=%f)" % cur.distance_to(_prev_pos))
					_prev_pos = cur
					if _actor.get_target() != null:
						_check(false, "REGROUP should suppress target acquisition while moving")
				if _actor == null or not is_instance_valid(_actor) \
					or (_actor as Node2D).global_position.distance_to(NORTH_RALLY) < 12.0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never reached north rally during regroup")
					_wait_frames(4)
				else:
					_budget += 1
					_pf += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(true, "REGROUP moved to rally without acquiring target (suppress + no teleport)")
				if _actor != null and is_instance_valid(_actor):
					_check((_actor as Node2D).global_position.distance_to(NORTH_RALLY) < 30.0,
						"actor reached north rally (%s)" % str((_actor as Node2D).global_position))
				_enter(Phase.REGROUP_RESUME)
		Phase.REGROUP_RESUME:
			# 도착 후 일반 AI 복귀 → focus(여전히 유효) 재획득 = priority4 유지.
			if _sub == 0:
				_budget = 0
				_sub = 1
			elif _sub == 1:
				_wait_target("mercenary never re-acquired focus after regroup")
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() == _focus_enemy,
						"after REGROUP arrival, focus re-acquired (priority4)")
					_check(_actor.get_focus_target() == _focus_enemy, "focus target persisted through REGROUP")
				_enter(Phase.RETREAT_OVERRIDE)
		Phase.RETREAT_OVERRIDE:
			# priority 2 > 3: RETREAT 명령이 REGROUP/combat/focus를 덮는다.
			if _sub == 0:
				_tac.get_regroup_button().pressed.emit()
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.REGROUP,
						"actor in REGROUP before RETREAT (state=%d)" % _actor.get_state())
				_tac.get_retreat_button().pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.RETREAT,
						"priority2: RETREAT overrides REGROUP (state=%d)" % _actor.get_state())
					_check(_actor.get_target() == null, "RETREAT clears target")
					_check(_actor.get_retreat_point().distance_to(_safe_rally) < 1.0,
						"retreat point = central safe rally")
				_prev_pos = (_actor as Node2D).global_position
				_pf = 0
				_budget = 0
				_sub = 2
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					var cur: Vector2 = (_actor as Node2D).global_position
					if cur.distance_to(_prev_pos) > 400.0:
						_check(false, "teleport during retreat (delta=%f)" % cur.distance_to(_prev_pos))
					_prev_pos = cur
					if _actor.get_target() != null:
						_check(false, "RETREAT should suppress target acquisition while moving")
				if _actor == null or not is_instance_valid(_actor) \
					or (_actor as Node2D).global_position.distance_to(_safe_rally) < 12.0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never reached safe rally during retreat")
					_wait_frames(4)
				else:
					_budget += 1
					_pf += 1
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(true, "RETREAT moved to safe rally without acquiring target (no teleport)")
				if _actor != null and is_instance_valid(_actor):
					_check((_actor as Node2D).global_position.distance_to(_safe_rally) < 30.0,
						"actor reached safe rally (%s)" % str((_actor as Node2D).global_position))
				_wait_frames(6)
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				_enter(Phase.RETREAT_HOLD)
		Phase.RETREAT_HOLD:
			# 도착 후에도 공격/target 획득 중지(적 근처에서도 HOLD).
			if _sub == 0:
				_spawn_enemy(_safe_rally + Vector2(0, -60), 80, 1)
				_wait_frames(12)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.RETREAT,
						"priority2: RETREAT holds even with nearby enemy")
					_check(_actor.get_target() == null, "RETREAT does not acquire nearby enemy")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_count_enemies() == 0, "retreat-hold enemy cleaned")
				_enter(Phase.DEFENSE_RECOVER)
		Phase.DEFENSE_RECOVER:
			# 새 DEFENSE_ZONE 명령(5)이 transient RETREAT를 덮고 일반 방어 AI 복귀.
			if _sub == 0:
				_tac.get_defense_zone_button(MercenaryData.DefenseZone.EAST).pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_defense_zone() == MercenaryData.DefenseZone.EAST,
						"new defense zone command -> EAST")
					_check(_actor.get_state() != MercenaryActor.MercState.RETREAT \
						and _actor.get_state() != MercenaryActor.MercState.REGROUP,
						"priority5: defense command overrides RETREAT (state=%d)" % _actor.get_state())
				_prev_pos = (_actor as Node2D).global_position
				_pf = 0
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _actor != null and is_instance_valid(_actor):
					var cur: Vector2 = (_actor as Node2D).global_position
					if cur.distance_to(_prev_pos) > 400.0:
						_check(false, "teleport during defense recover (delta=%f)" % cur.distance_to(_prev_pos))
					_prev_pos = cur
				if _actor == null or not is_instance_valid(_actor) \
					or (_actor as Node2D).global_position.distance_to(EAST_RALLY) < 12.0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never recovered to east rally")
					_wait_frames(4)
				else:
					_budget += 1
					_pf += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check((_actor as Node2D).global_position.distance_to(EAST_RALLY) < 30.0,
						"actor reached east rally (%s)" % str((_actor as Node2D).global_position))
					_check(_actor.get_state() != MercenaryActor.MercState.RETREAT \
						and _actor.get_state() != MercenaryActor.MercState.REGROUP,
						"normal defense AI restored (state=%d)" % _actor.get_state())
					_check(_spawn_enemy(EAST_RALLY + Vector2(0, -70), 80, 1) != null,
						"enemy spawned near east zone after recover")
					_budget = 0
					_sub = 3
			elif _sub == 3:
				_wait_target("mercenary never re-engaged combat after recover")
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() != null, "recovered mercenary auto-combats at east zone")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 5 and not _waited():
				return false
			elif _sub == 5:
				_check(_count_enemies() == 0, "recover test enemy cleaned")
				_enter(Phase.RAPID_OVERRIDE)
		Phase.RAPID_OVERRIDE:
			# 모순 명령 연속 발동 후에도 상태 누적 없이 생산적 상태로 정착(deadlock 없음).
			if _sub == 0:
				_tac.get_regroup_button().pressed.emit()
				_tac.get_retreat_button().pressed.emit()
				_tac.get_regroup_button().pressed.emit()
				_tac.get_defense_zone_button(MercenaryData.DefenseZone.EAST).pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() != MercenaryActor.MercState.DEAD, "no dead state after rapid commands")
					_check(_actor.alive, "actor alive after rapid commands")
					_check(_actor.get_defense_zone() == MercenaryData.DefenseZone.EAST,
						"rapid: final defense zone command wins (EAST)")
				_prev_pos = (_actor as Node2D).global_position
				_pf = 0
				_budget = 0
				_sub = 1
			elif _sub == 1:
				# 생산적 상태로 정착: East rally 도달 + 재교전(deadlock 없음).
				if _actor != null and is_instance_valid(_actor):
					var cur: Vector2 = (_actor as Node2D).global_position
					if cur.distance_to(_prev_pos) > 400.0:
						_check(false, "teleport during rapid override (delta=%f)" % cur.distance_to(_prev_pos))
					_prev_pos = cur
				if _actor == null or not is_instance_valid(_actor) \
					or (_actor as Node2D).global_position.distance_to(EAST_RALLY) < 12.0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "rapid override never settled (deadlock?) pos=%s" % str((_actor as Node2D).global_position))
					_wait_frames(4)
				else:
					_budget += 1
					_pf += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check((_actor as Node2D).global_position.distance_to(EAST_RALLY) < 30.0,
						"rapid override settled at east rally (%s)" % str((_actor as Node2D).global_position))
					_check(_actor.get_state() == MercenaryActor.MercState.IDLE \
						or _actor.get_state() == MercenaryActor.MercState.ACQUIRE_TARGET \
						or _actor.get_state() == MercenaryActor.MercState.RETURN_TO_DEFENSE_ZONE,
						"rapid override reached a productive non-transient state (state=%d)" % _actor.get_state())
					_check(_spawn_enemy(EAST_RALLY + Vector2(0, -70), 80, 1) != null,
						"enemy spawned at east for rapid re-engage")
					_budget = 0
					_sub = 3
			elif _sub == 3:
				_wait_target("rapid override never re-engaged combat")
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() != null, "rapid override re-engaged combat (no deadlock)")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 5 and not _waited():
				return false
			elif _sub == 5:
				_check(_count_enemies() == 0, "rapid override enemy cleaned")
				_enter(Phase.DEAD_PRIORITY)
		Phase.DEAD_PRIORITY:
			# priority 1: DEAD. 사망 후 모든 명령은 안전한 no-op(크래시 없음).
			if _sub == 0:
				_check(_actor != null and is_instance_valid(_actor) and _actor.alive, "actor alive before death")
				if _actor != null and is_instance_valid(_actor):
					_actor.take_damage(_actor.current_hp)
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_actor == null or not is_instance_valid(_actor) or not _actor.alive,
					"priority1: DEAD state reached")
				if _mercenary != null:
					_check(_mercenary.alive == false, "MercenaryData.alive=false after death")
				_check(_count_mercenaries() == 0, "dead mercenary removed from world")
				# 모든 명령 발동 → get_alive()가 비어 있어 안전한 no-op.
				_tac.command_issued.emit(_tac.Command.DEFENSE_ZONE, MercenaryData.DefenseZone.NORTH)
				_tac.command_issued.emit(_tac.Command.REGROUP, 0)
				_tac.command_issued.emit(_tac.Command.RETREAT, 0)
				_tac.command_issued.emit(_tac.Command.FOCUS_TARGET, 0)
				_tac.command_issued.emit(_tac.Command.GATE_OPEN, null)
				_tac.command_issued.emit(_tac.Command.TIME_2X, 0)
				_tac.command_issued.emit(_tac.Command.TIME_1X, 0)
				_check(_roster.get_alive_count() == 0, "all commands safe no-op after death (no crash)")
				_check(_count_mercenaries() == 0, "no mercenary respawned after death")
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X, "time scale restored to 1x")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(not _player.has_method("attack") and not _player.has_method("_attack"),
					"player has no attack method")
				_check(not _player.is_in_group("enemies") and not _player.is_in_group("mercenaries"),
					"player excluded from combat groups")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128,
					"world floor intact")
				_check(_roster.get_mercenary("mercenary_A") != null, "mercenary data intact (dead)")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0157_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
