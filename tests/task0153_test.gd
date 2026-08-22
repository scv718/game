extends SceneTree

## TASK-015-3 Defense Zone Command 검증.
## 전술 명령 UI의 방어구역 버튼(N/E/S/W)이 내는 DEFENSE_ZONE 명령이 NIGHT 중 spawn된
## Mercenary Actor의 방어 구역/앵커(rally)를 실시간 변경하고, 현재 target이 새 구역과
## 무관/너무 멀면 disengage 후 새 구역으로 nav 이동(teleport 금지)하며,
## 이후 새 구역 기준으로 target을 탐색하는지 검증한다.
##
## 자동검증 항목:
##  1. Mercenary 고용 + NORTH 배정 + NIGHT → Actor가 North Rally(0,-280)에 spawn.
##  2. North 구역 내 Enemy → Actor가 target 획득/추격(ACQUIRE/MOVE_TO_TARGET, target set).
##  3. Tactical UI NORTH 버튼 → DEFENSE_ZONE 명령 → (구역 그대로) 동작 확인.
##  4. Tactical UI EAST 버튼 → Actor 방어 구역 EAST + defense_point East Rally(280,0) 갱신.
##  5. 이전 target이 새 구역과 멀면 disengage(target 클리어) + RETURN_TO_DEFENSE_ZONE.
##  6. teleport 금지: 새 구역 이동 중 위치가 (0,-280)에서 연속 이동(순간이동 아님).
##  7. East Rally 도착 후 새 구역 기준 target 탐색(East 구역 내 Enemy 획득).
##  8. stale target/permanent chase 없음.
##  9. 회귀: Player 무공격, NIGHT Player 이동 비활성, 핵심 건물/floor 유지.

enum Phase {
	SETUP,
	HIRE_NORTH,
	TO_NIGHT,
	SPAWN_ACTOR,
	COMBAT_NORTH,
	ISSUE_EAST,
	DISENGAGE,
	MOVE_EAST,
	COMBAT_EAST,
	REGRESSION,
	DONE,
}

const NORTH_RALLY := Vector2(0, -280)
const EAST_RALLY := Vector2(280, 0)
const NAV_SETTLE_PF := 90
const BUDGET := 3000

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
	print("TASK0153_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _count_enemies() -> int:
	return get_nodes_in_group("enemies").size()


func _count_mercenaries() -> int:
	return get_nodes_in_group("mercenaries").size()


func _spawn_enemy(pos: Vector2, hp := 80) -> EnemyActor:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate() as EnemyActor
	if enemy == null:
		return null
	enemy.max_hp = hp
	enemy.setup("test_enemy_%d" % _enemy_seq, "Raider", "north")
	enemy.position = pos
	_world.add_child(enemy)
	_enemy_seq += 1
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
				var e := _spawn_enemy(Vector2(0, -350))
				_check(e != null, "enemy spawned near north defense zone")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _budget >= BUDGET:
					_check(false, "mercenary never acquired north target in budget")
					_wait_frames(4)
				elif _actor != null and is_instance_valid(_actor) \
					and _actor.get_target() != null:
					_wait_frames(2)
				else:
					_budget += 1
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
				_enter(Phase.ISSUE_EAST)
		Phase.ISSUE_EAST:
			if _sub == 0:
				_prev_pos = (_actor as Node2D).global_position
				# 전술 명령 UI EAST 버튼으로 DEFENSE_ZONE EAST 명령 발동.
				_tac.get_defense_zone_button(MercenaryData.DefenseZone.EAST).pressed.emit()
				if _mercenary != null:
					_check(_mercenary.defense_zone == MercenaryData.DefenseZone.EAST,
						"MercenaryData defense zone -> EAST")
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_defense_zone() == MercenaryData.DefenseZone.EAST,
						"actor defense zone -> EAST")
					_check((_actor.defense_point as Vector2).distance_to(EAST_RALLY) < 1.0,
						"actor defense_point -> East Rally (%s)" % str(_actor.defense_point))
					_check(_actor.get_target() == null,
						"stale north target disengaged (target cleared)")
					_check(_actor.get_state() == MercenaryActor.MercState.RETURN_TO_DEFENSE_ZONE,
						"actor returns to defense zone (state=%d)" % _actor.get_state())
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf >= 10:
					_enter(Phase.MOVE_EAST)
		Phase.MOVE_EAST:
			if _sub == 0:
				_budget = 0
				_pf = 0
				_sub = 1
			elif _sub == 1:
				# teleport 금지: 프레임별 위치가 연속적으로 이동하는지(거대 점프 없음) 확인.
				if _actor != null and is_instance_valid(_actor):
					var cur: Vector2 = (_actor as Node2D).global_position
					var delta_pos := cur.distance_to(_prev_pos)
					if delta_pos > 400.0:
						_check(false, "teleport detected while moving to east (delta=%f)" % delta_pos)
					_prev_pos = cur
				if _actor == null or not is_instance_valid(_actor) \
					or (_actor as Node2D).global_position.distance_to(EAST_RALLY) < 12.0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never reached east rally (pos=%s)" % str((_actor as Node2D).global_position))
					_wait_frames(4)
				else:
					_budget += 1
					_pf += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(true, "mercenary moved to east rally via nav (no teleport)")
				if _actor != null and is_instance_valid(_actor):
					_check((_actor as Node2D).global_position.distance_to(EAST_RALLY) < 30.0,
						"actor reached east rally (%s)" % str((_actor as Node2D).global_position))
					_pf = 0
				_enter(Phase.COMBAT_EAST)
		Phase.COMBAT_EAST:
			if _sub == 0:
				var e := _spawn_enemy(EAST_RALLY + Vector2(0, -70))
				_check(e != null, "enemy spawned near east defense zone")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _budget >= BUDGET:
					_check(false, "mercenary never acquired east target in budget")
					_wait_frames(4)
				elif _actor != null and is_instance_valid(_actor) \
					and _actor.get_target() != null:
					_wait_frames(2)
				else:
					_budget += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() != null, "mercenary re-acquired target near east zone")
					var t: Node = _actor.get_target()
					if t != null and is_instance_valid(t):
						var td: float = (t as Node2D).global_position.distance_to(EAST_RALLY)
						_check(td <= MercenaryActor.CHASE_RETURN_DISTANCE,
							"new target is within east zone (dist=%f)" % td)
				_check(_count_enemies() == 1, "east enemy engaged (not permanent chase away)")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "east test enemy cleaned")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(not _player.has_method("attack") and not _player.has_method("_attack"), "player has no attack method")
				_check(not _player.is_in_group("enemies") and not _player.is_in_group("mercenaries"), "player excluded from combat groups")
				_check(_controller.is_night_mode() == true, "camera controller night mode active during NIGHT")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact")
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_defense_zone() == MercenaryData.DefenseZone.EAST,
						"actor still EAST after re-acquire (no stale zone)")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0153_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
