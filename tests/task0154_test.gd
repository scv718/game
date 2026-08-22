extends SceneTree

## TASK-015-4 Regroup / Retreat 검증.
## 전술 명령 UI의 REGROUP / RETREAT 명령이 NIGHT 중 spawn된 Mercenary Actor의 행동을
## 바꾸는지 검증한다.
##
##  - REGROUP: 현재 방어 구역 rally로 nav 복귀(teleport 금지), 이동 중 새 target 획득
##    억제, 도착 후 일반 방어 AI(재탐색/재교전)로 복귀.
##  - RETREAT: 중앙 Village/safe rally로 후퇴(teleport 금지), 이동 중/도착 후 공격·target
##    획득 중지, 도착 후 HOLD, 무적 아님(적 공격으로 사망 가능).
##  - 새 DEFENSE_ZONE 명령으로 REGROUP/RETREAT 상태에서 일반 방어 AI로 정상 복귀.
##  - 회귀: Player 무공격/무타겟, NIGHT Player 이동 비활성, 핵심 건물/floor 유지.

enum Phase {
	SETUP,
	HIRE_NORTH,
	TO_NIGHT,
	SPAWN_ACTOR,
	COMBAT_NORTH,
	ISSUE_REGROUP,
	REGROUP_MOVE,
	REGROUP_RESUME,
	ISSUE_RETREAT,
	RETREAT_MOVE,
	RETREAT_HOLD,
	DEFENSE_RECOVER,
	RETREAT_NOT_INVINCIBLE,
	REGRESSION,
	DONE,
}

const NORTH_RALLY := Vector2(0, -280)
const EAST_RALLY := Vector2(280, 0)
const NAV_SETTLE_PF := 90
const BUDGET := 4000

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
var _controller: Node = null
var _hud: Node = null
var _tac = null
var _mercenary: MercenaryData = null
var _actor: Node = null

var _enemy_seq := 0
var _budget := 0
var _prev_pos := Vector2.ZERO
var _safe_rally := Vector2.ZERO
var _suppress_ok := true


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
	print("TASK0154_RESULT=" + ("FAIL" if _failed else "PASS"))
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
	enemy.setup("test_enemy_%d" % _enemy_seq, "Raider", "north")
	enemy.position = pos
	_world.add_child(enemy)
	_enemy_seq += 1
	return enemy


func _clear_test_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()


## target 획득까지 대기(예산 내). 성공 시 _wait_frames로 이동.
func _wait_target(timeout_msg: String) -> void:
	if _budget >= BUDGET:
		_check(false, timeout_msg)
		_wait_frames(4)
	elif _actor != null and is_instance_valid(_actor) and _actor.get_target() != null:
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
				var ctrls := get_nodes_in_group("camera_controller")
				_controller = ctrls[0] if ctrls.size() > 0 else null
				_hud = root.get_node("Main").get_node("HUD")
				_tac = _hud.get_node_or_null("TacticalCommandUI")
				_check(_game_time != null and _world != null and _roster != null \
					and _player != null and _hud != null and _tac != null, "core nodes present")
				_safe_rally = _roster.get_safe_rally(_world)
				_check(_safe_rally == Vector2.ZERO \
						or (_safe_rally.x > -1000.0 and _safe_rally.y > -1000.0 \
							and _safe_rally.x < 1000.0 and _safe_rally.y < 1000.0),
					"safe rally resolved in bounds (%s)" % str(_safe_rally))
				_resources._amounts["wood"] = 10000
				_check(_roster.get_count() == 0, "mercenary roster starts empty")
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
				_check(_controller.is_night_mode() == true, "camera controller night mode active")
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
					_enter(Phase.COMBAT_NORTH)
		Phase.COMBAT_NORTH:
			if _sub == 0:
				_check(_spawn_enemy(Vector2(0, -350), 80, 1) != null, "enemy spawned near north defense zone")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				_wait_target("mercenary never acquired north target in budget")
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() != null, "mercenary acquired north target")
					_check(_actor.get_state() == MercenaryActor.MercState.MOVE_TO_TARGET \
						or _actor.get_state() == MercenaryActor.MercState.ATTACK \
						or _actor.get_state() == MercenaryActor.MercState.ACQUIRE_TARGET,
						"mercenary chasing/attacking north target (state=%d)" % _actor.get_state())
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "north test enemy cleaned")
				_enter(Phase.ISSUE_REGROUP)
		Phase.ISSUE_REGROUP:
			if _sub == 0:
				_prev_pos = (_actor as Node2D).global_position
				# 전술 명령 UI REGROUP 버튼으로 명령 발동.
				_tac.get_regroup_button().pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.REGROUP,
						"actor enters REGROUP (state=%d)" % _actor.get_state())
					_check(_actor.get_target() == null, "regroup clears target")
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf >= 5:
					_enter(Phase.REGROUP_MOVE)
		Phase.REGROUP_MOVE:
			if _sub == 0:
				_budget = 0
				_pf = 0
				_suppress_ok = true
				_sub = 1
			elif _sub == 1:
				# teleport 금지 + 이동 중 새 target 획득 억제 확인(누적 플래그).
				if _actor != null and is_instance_valid(_actor):
					var cur: Vector2 = (_actor as Node2D).global_position
					var delta_pos := cur.distance_to(_prev_pos)
					if delta_pos > 400.0:
						_suppress_ok = false
						_check(false, "teleport detected during regroup (delta=%f)" % delta_pos)
					_prev_pos = cur
					if _actor.get_target() != null:
						_suppress_ok = false
				if _actor == null or not is_instance_valid(_actor) \
					or (_actor as Node2D).global_position.distance_to(NORTH_RALLY) < 12.0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never reached north rally (pos=%s)" % str((_actor as Node2D).global_position))
					_wait_frames(4)
				else:
					_budget += 1
					_pf += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_suppress_ok, "no target acquired / no teleport while regrouping")
				if _actor != null and is_instance_valid(_actor):
					_check((_actor as Node2D).global_position.distance_to(NORTH_RALLY) < 30.0,
						"actor reached north rally (%s)" % str((_actor as Node2D).global_position))
				_enter(Phase.REGROUP_RESUME)
		Phase.REGROUP_RESUME:
			if _sub == 0:
				# 도착 후 일반 방어 AI 복귀: 구역 내 적을 재탐색/재교전한다.
				_check(_spawn_enemy(Vector2(0, -350), 80, 1) != null, "enemy spawned near north zone after regroup")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				_wait_target("mercenary never resumed combat after regroup")
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() != null, "normal defense AI resumed after regroup (re-acquired)")
					_check(_actor.get_state() == MercenaryActor.MercState.MOVE_TO_TARGET \
						or _actor.get_state() == MercenaryActor.MercState.ATTACK \
						or _actor.get_state() == MercenaryActor.MercState.ACQUIRE_TARGET,
						"regrouped actor engaging target again (state=%d)" % _actor.get_state())
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "post-regroup test enemy cleaned")
				_enter(Phase.ISSUE_RETREAT)
		Phase.ISSUE_RETREAT:
			if _sub == 0:
				_prev_pos = (_actor as Node2D).global_position
				# 전술 명령 UI RETREAT 버튼으로 명령 발동.
				_tac.get_retreat_button().pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.RETREAT,
						"actor enters RETREAT (state=%d)" % _actor.get_state())
					_check(_actor.get_retreat_point().distance_to(_safe_rally) < 1.0,
						"retreat point = central safe rally (%s)" % str(_actor.get_retreat_point()))
					_check(_actor.get_target() == null, "retreat clears target")
					# Regroup/Retreat 차이: RETREAT 목표는 중앙 safe rally(북방 rally와 다름).
					_check(_actor.get_retreat_point().distance_to(NORTH_RALLY) > 50.0,
						"retreat target differs from defense rally")
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf >= 5:
					_enter(Phase.RETREAT_MOVE)
		Phase.RETREAT_MOVE:
			if _sub == 0:
				_budget = 0
				_pf = 0
				_suppress_ok = true
				_sub = 1
			elif _sub == 1:
				if _actor != null and is_instance_valid(_actor):
					var cur: Vector2 = (_actor as Node2D).global_position
					var delta_pos := cur.distance_to(_prev_pos)
					if delta_pos > 400.0:
						_suppress_ok = false
						_check(false, "teleport detected during retreat (delta=%f)" % delta_pos)
					_prev_pos = cur
					if _actor.get_target() != null:
						_suppress_ok = false
				if _actor == null or not is_instance_valid(_actor) \
					or (_actor as Node2D).global_position.distance_to(_safe_rally) < 12.0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never reached safe rally (pos=%s)" % str((_actor as Node2D).global_position))
					_wait_frames(4)
				else:
					_budget += 1
					_pf += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_suppress_ok, "no target acquired / no teleport while retreating")
				if _actor != null and is_instance_valid(_actor):
					_check((_actor as Node2D).global_position.distance_to(_safe_rally) < 30.0,
						"actor reached safe rally (%s)" % str((_actor as Node2D).global_position))
					_wait_frames(6)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.RETREAT,
						"actor holds (RETREAT) after arrival, no re-acquire")
					_check(_actor.get_target() == null, "no target after retreat arrival")
					# 근처에 적이 있어도 후퇴 상태에서는 공격/획득하지 않는다.
					_spawn_enemy(_safe_rally + Vector2(0, -60), 80, 1)
					_wait_frames(10)
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() == null, "retreat ignores nearby enemy (holds)")
					_check(_actor.get_state() == MercenaryActor.MercState.RETREAT, "retreat state held")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 5 and not _waited():
				return false
			elif _sub == 5:
				_enter(Phase.DEFENSE_RECOVER)
		Phase.DEFENSE_RECOVER:
			if _sub == 0:
				# RETREAT HOLD 상태에서 새 DEFENSE_ZONE 명령 → 일반 방어 AI로 정상 복귀.
				_tac.get_defense_zone_button(MercenaryData.DefenseZone.EAST).pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_defense_zone() == MercenaryData.DefenseZone.EAST,
						"actor defense zone -> EAST via new command")
					_check((_actor.defense_point as Vector2).distance_to(EAST_RALLY) < 1.0,
						"actor defense_point -> East Rally")
					_check(_actor.get_state() != MercenaryActor.MercState.RETREAT \
						and _actor.get_state() != MercenaryActor.MercState.REGROUP,
						"actor left retreat state (state=%d)" % _actor.get_state())
					_check(_actor.get_state() == MercenaryActor.MercState.RETURN_TO_DEFENSE_ZONE,
						"actor returns to defense zone (state=%d)" % _actor.get_state())
				_prev_pos = (_actor as Node2D).global_position
				_pf = 0
				_sub = 1
			elif _sub == 1:
				# teleport 금지 + 이동 확인.
				if _actor != null and is_instance_valid(_actor):
					var cur: Vector2 = (_actor as Node2D).global_position
					var delta_pos := cur.distance_to(_prev_pos)
					if delta_pos > 400.0:
						_check(false, "teleport detected while recovering to east (delta=%f)" % delta_pos)
					_prev_pos = cur
				if _actor == null or not is_instance_valid(_actor) \
					or (_actor as Node2D).global_position.distance_to(EAST_RALLY) < 12.0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never recovered to east rally (pos=%s)" % str((_actor as Node2D).global_position))
					_wait_frames(4)
				else:
					_budget += 1
					_pf += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(true, "new defense command recovered mercenary to east via nav (no teleport)")
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
				_wait_target("mercenary never re-engaged combat after recovery")
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
				_enter(Phase.RETREAT_NOT_INVINCIBLE)
		Phase.RETREAT_NOT_INVINCIBLE:
			if _sub == 0:
				# 무적 아님: 사망 처리가 여전히 동작한다.
				_check(_actor != null and is_instance_valid(_actor) and _actor.alive, "actor alive before damage")
				if _actor != null and is_instance_valid(_actor):
					_actor.take_damage(_actor.current_hp)
					_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_actor == null or not is_instance_valid(_actor) or not _actor.alive,
					"mercenary can die (not invincible)")
				if _mercenary != null:
					_check(_mercenary.alive == false, "MercenaryData.alive=false after death")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(not _player.has_method("attack") and not _player.has_method("_attack"), "player has no attack method")
				_check(not _player.is_in_group("enemies") and not _player.is_in_group("mercenaries"), "player excluded from combat groups")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0154_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)