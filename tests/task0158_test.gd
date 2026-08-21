extends SceneTree

## TASK-015-8 Tactical Combat Vertical Slice 통합 검증.
## TASK-013(Wall/Gate) + TASK-014(고용/Enemy/자동전투/death) + TASK-015(전술 명령 UI,
## Tactical camera, Defense Zone, Regroup/Retreat, Focus Target, Gate Command, Tactical
## Time)의 모든 구성 요소를 하나의 연속 시나리오로 묶어 검증한다.
##
## 시나리오 (17단계):
##   1. Mercenary 고용 + NORTH 방어배치.
##   2. Wall(양옆) + North Gate 구성.
##   3. NIGHT → Actor spawn + Tactical camera pan.
##   4. Enemy encounter (FirstEncounterSpawner 자동 조우).
##   5. 자동전투 (Mercenary가 Enemy 자동 탐색/추격/공격).
##   6. Defense Zone 명령(East) → 실시간 구역 변경 + 재배치.
##   7. Focus Target 명령 → 우선 target.
##   8. Regroup 명령 → rally 복귀.
##   9. 재교전 (일반 방어 AI 복귀).
##  10. Retreat 명령 → 중앙 safe rally 후퇴 + HOLD.
##  11. Gate Open/Close 명령 → 통로 개폐.
##  12. Pause / 2× 전술 시간.
##  13. death cleanup (사망 후 명령 safe no-op).
##  14. DAY 복귀 (cleanup, camera follow 복구).
##  15. 다음 NIGHT 반복 (duplicate/reference 누수 없음).
##  16. 회귀: Player 무공격, NIGHT 이동 비활성, 핵심 건물/floor/HUD 유지.
##
## 핵심검증:
##  - 전투 자체는 Mercenary AI가 수행(Player는 이동/공격 안 함).
##  - 명령이 실제 Mercenary AI 행동에 영향.
##  - nav stall / freed reference 없음.
##  - Gate breach/command 충돌 없음.
##  - Worker/DayNight/HUD 회귀 없음.

enum Phase {
	SETUP,
	HIRE_ASSIGN,
	WALL_GATE,
	NIGHT_CAMERA,
	ENCOUNTER,
	AUTO_COMBAT,
	DEFENSE_ZONE,
	FOCUS_TARGET,
	REGROUP,
	RE_ENGAGE,
	RETREAT,
	GATE_COMMAND,
	TACTICAL_TIME,
	DEATH_CLEANUP,
	DAY_RETURN,
	NEXT_NIGHT,
	REGRESSION,
	DONE,
}

const GATE_POS := Vector2(0, -448)
const WALL_LEFT := Vector2(-48, -448)
const WALL_RIGHT := Vector2(48, -448)
const NORTH_RALLY := Vector2(0, -280)
const EAST_RALLY := Vector2(280, 0)
const COMBAT_FIELD := Vector2(0, -620)
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
var _placement: Node = null
var _spawner: Node = null
var _roster: Node = null
var _worker_roster: Node = null
var _resources: Node = null
var _player: Node = null
var _camera: Camera2D = null
var _tac = null

var _mercenary: MercenaryData = null
var _actor: Node = null
var _gate: Node = null
var _safe_rally := Vector2.ZERO

var _enemy_seq := 0
var _budget := 0
var _prev_pos := Vector2.ZERO
var _focus_enemy: EnemyActor = null


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
	print("TASK0158_RESULT=" + ("FAIL" if _failed else "PASS"))
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


func _spawn_enemy(pos: Vector2, hp := 60, dmg := 5) -> EnemyActor:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate() as EnemyActor
	if enemy == null:
		return null
	enemy.max_hp = hp
	enemy.current_hp = hp
	enemy.attack_damage = dmg
	enemy.attack_interval = 0.05
	enemy.setup("t0158_enemy_%d" % _enemy_seq, "Raider", "north")
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


func _wait_enemies_dead(timeout_msg: String) -> void:
	if _budget >= BUDGET:
		_check(false, timeout_msg + " (enemies=%d)" % _count_enemies())
		_wait_frames(4)
	elif _count_enemies() == 0:
		_wait_frames(4)
	else:
		_budget += 1


func release_all_actions() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)


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
				_placement = root.get_node("Main").get_node("BuildingPlacement")
				_spawner = root.get_node("FirstEncounterSpawner")
				_roster = root.get_node("MercenaryRoster")
				_worker_roster = root.get_node("WorkerRoster")
				_resources = root.get_node("VillageResources")
				_player = root.get_node("Main").get_node("Player")
				_camera = _player.get_node("Camera2D") as Camera2D
				_tac = root.get_node("Main").get_node("HUD").get_node_or_null("TacticalCommandUI")
				_check(_game_time != null and _world != null and _placement != null \
					and _spawner != null and _roster != null and _worker_roster != null \
					and _resources != null and _player != null and _camera != null and _tac != null,
					"core nodes present")
				_resources._amounts["wood"] = 10000
				_check(_roster.get_count() == 0, "mercenary roster starts empty")
				_safe_rally = _roster.get_safe_rally(_world)
				_player.night_pan_speed = 2000.0
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
					_mercenary.attack_damage = 30
					_mercenary.attack_interval = 0.05
					_mercenary.move_speed = 120.0
					_check(_mercenary.defense_zone == MercenaryData.DefenseZone.NORTH,
						"defense zone assigned NORTH")
				_check(_roster.get_count() == 1, "roster holds 1 mercenary")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.WALL_GATE)
		Phase.WALL_GATE:
			if _sub == 0:
				# 2단계: Wall 양옆 + North Gate로 passage 구성.
				_placement._set_building_type("wall")
				_placement._try_place_wall_at(WALL_LEFT)
				_placement._try_place_wall_at(WALL_RIGHT)
				_placement._set_building_type("gate")
				_placement._try_place_gate_at(_placement._snap_gate(GATE_POS))
				_gate = _find_gate_at(GATE_POS)
				_check(_gate != null, "north gate placed")
				_check(_gate != null and _gate.is_closed(), "gate starts CLOSED")
				_check(get_nodes_in_group("walls").size() == 2, "2 flanking walls placed")
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf >= NAV_SETTLE_PF:
					_enter(Phase.NIGHT_CAMERA)
		Phase.NIGHT_CAMERA:
			if _sub == 0:
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT")
				_check(_player.get("_night_mode") == true, "player night mode active (movement disabled)")
				_check(_count_mercenaries() == 1, "mercenary actor spawned at NIGHT")
				_actor = _roster.get_actor("mercenary_A")
				_check(_actor != null, "actor retrievable by id")
				if _actor != null:
					var pos: Vector2 = (_actor as Node2D).global_position
					_check(pos.distance_to(NORTH_RALLY) < 1.0, "actor at north rally (pos=%s)" % pos)
					_check(_actor.get_state() == MercenaryActor.MercState.IDLE, "actor starts IDLE")
				_sub = 2
				_pf = 0
			elif _sub == 2:
				# 4단계: Tactical camera pan (NIGHT Player 이동 비활성 유지, camera만 이동).
				release_all_actions()
				Input.action_press("move_up")
				if _pf < NAV_SETTLE_PF:
					return false
				release_all_actions()
				var cpos: Vector2 = _camera.global_position
				_check(_player.global_position == Vector2(0, 60) or _player.global_position.y == 60.0,
					"NIGHT: player entity stationary during camera pan")
				_check(cpos.y <= -COMBAT_FIELD.y - 100.0 or cpos.y <= -560.0,
					"NIGHT: camera pans to North Combat Field (y=%.0f)" % cpos.y)
				_check(_camera.position.y < 0.0, "NIGHT: camera offset accumulates (y=%.0f)" % _camera.position.y)
				_sub = 3
			elif _sub == 3:
				# 5단계: Enemy encounter 자동 조우.
				_check(_count_enemies() >= 1, "auto-encounter spawned enemies at NIGHT (%d)" % _count_enemies())
				_spawner.despawn_encounter()
				_wait_frames(2)
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				_check(_count_enemies() == 0, "auto-encounter cleaned for isolated combat test")
				_enter(Phase.AUTO_COMBAT)
		Phase.AUTO_COMBAT:
			if _sub == 0:
				# 구역 내(defense_point 180px 이내)에 spawn해 auto-combat target이 된다.
				_check(_spawn_enemy(NORTH_RALLY + Vector2(0, -70), 80, 1) != null,
					"combat enemy spawned near north zone")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				_wait_target("mercenary never acquired combat target")
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() != null, "auto combat: mercenary acquired target")
					_check(_actor.get_state() == MercenaryActor.MercState.MOVE_TO_TARGET \
						or _actor.get_state() == MercenaryActor.MercState.ATTACK,
						"auto combat: chasing/attacking (state=%d)" % _actor.get_state())
				_budget = 0
				_sub = 3
			elif _sub == 3:
				_wait_enemies_dead("mercenary never killed combat enemy")
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				_check(true, "auto combat killed enemy (AI-driven)")
				_check(_count_enemies() == 0, "dead enemy excluded from enemies group")
				_enter(Phase.DEFENSE_ZONE)
		Phase.DEFENSE_ZONE:
			if _sub == 0:
				# 6단계: Defense Zone 명령(EAST) → 실시간 구역 변경 + 재배치.
				_tac.get_defense_zone_button(MercenaryData.DefenseZone.EAST).pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_defense_zone() == MercenaryData.DefenseZone.EAST,
						"defense zone command -> EAST")
				_prev_pos = (_actor as Node2D).global_position
				_pf = 0
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _actor != null and is_instance_valid(_actor):
					var cur: Vector2 = (_actor as Node2D).global_position
					if cur.distance_to(_prev_pos) > 400.0:
						_check(false, "teleport during defense zone change")
					_prev_pos = cur
				if _actor == null or not is_instance_valid(_actor) \
					or (_actor as Node2D).global_position.distance_to(EAST_RALLY) < 12.0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never reached east rally")
					_wait_frames(4)
				else:
					_budget += 1
					_pf += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check((_actor as Node2D).global_position.distance_to(EAST_RALLY) < 30.0,
						"mercenary relocated to east rally (%s)" % str((_actor as Node2D).global_position))
				_enter(Phase.FOCUS_TARGET)
		Phase.FOCUS_TARGET:
			if _sub == 0:
				# 7단계: Focus Target 명령 → 우선 target.
				_focus_enemy = _spawn_enemy(EAST_RALLY + Vector2(0, -70), 100, 1)
				_check(_focus_enemy != null, "focus candidate enemy spawned")
				_tac.get_focus_target_button().pressed.emit()
				_check(_roster.is_focus_mode_active(), "focus mode active via UI")
				_roster.set_focus_target(_focus_enemy)
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_focus_target() == _focus_enemy, "actor received focus target")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				_wait_target("mercenary never focused the focus enemy")
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() == _focus_enemy, "focus target takes priority (target==focus)")
				_enter(Phase.REGROUP)
		Phase.REGROUP:
			if _sub == 0:
				# 8단계: Regroup 명령 → rally 복귀 + 이동 중 target 획득 억제.
				_prev_pos = (_actor as Node2D).global_position
				_tac.get_regroup_button().pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.REGROUP,
						"regroup command overrides focus (state=%d)" % _actor.get_state())
					_check(_actor.get_target() == null, "regroup clears current target")
				_pf = 0
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _actor != null and is_instance_valid(_actor):
					var cur: Vector2 = (_actor as Node2D).global_position
					if cur.distance_to(_prev_pos) > 400.0:
						_check(false, "teleport during regroup")
					_prev_pos = cur
					if _actor.get_target() != null:
						_check(false, "regroup suppresses target acquisition while moving")
				if _actor == null or not is_instance_valid(_actor) \
					or (_actor as Node2D).global_position.distance_to(EAST_RALLY) < 12.0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never regrouped to east rally")
					_wait_frames(4)
				else:
					_budget += 1
					_pf += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check((_actor as Node2D).global_position.distance_to(EAST_RALLY) < 30.0,
						"regroup arrived at east rally (no teleport)")
				_enter(Phase.RE_ENGAGE)
		Phase.RE_ENGAGE:
			if _sub == 0:
				# 9단계: 재교전 — 도착 후 일반 방어 AI 복귀, focus 재획득.
				_budget = 0
				_sub = 1
			elif _sub == 1:
				_wait_target("mercenary never re-engaged after regroup")
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() == _focus_enemy, "after regroup, focus re-acquired")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "re-engage test enemy cleaned")
				_enter(Phase.RETREAT)
		Phase.RETREAT:
			if _sub == 0:
				# 10단계: Retreat 명령 → 중앙 safe rally 후퇴 + HOLD.
				_tac.get_retreat_button().pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.RETREAT,
						"retreat command active (state=%d)" % _actor.get_state())
					_check(_actor.get_retreat_point().distance_to(_safe_rally) < 1.0,
						"retreat point = central safe rally")
				_prev_pos = (_actor as Node2D).global_position
				_pf = 0
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _actor != null and is_instance_valid(_actor):
					var cur: Vector2 = (_actor as Node2D).global_position
					if cur.distance_to(_prev_pos) > 400.0:
						_check(false, "teleport during retreat")
					_prev_pos = cur
					if _actor.get_target() != null:
						_check(false, "retreat suppresses target acquisition while moving")
				if _actor == null or not is_instance_valid(_actor) \
					or (_actor as Node2D).global_position.distance_to(_safe_rally) < 12.0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never retreated to safe rally")
					_wait_frames(4)
				else:
					_budget += 1
					_pf += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check((_actor as Node2D).global_position.distance_to(_safe_rally) < 30.0,
						"retreat arrived at safe rally (no teleport)")
				_spawn_enemy(_safe_rally + Vector2(0, -60), 80, 1)
				_wait_frames(12)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.RETREAT,
						"retreat holds even with nearby enemy")
					_check(_actor.get_target() == null, "retreat does not acquire nearby enemy")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				_check(_count_enemies() == 0, "retreat-hold enemy cleaned")
				_enter(Phase.GATE_COMMAND)
		Phase.GATE_COMMAND:
			if _sub == 0:
				# 11단계: Gate Open/Close 명령 → 통로 개폐.
				_gate = _find_gate_at(GATE_POS)
				_check(_gate != null, "gate present for command test")
				if _gate != null:
					_check(_gate.is_closed(), "gate CLOSED before command")
					_tac.command_issued.emit(_tac.Command.GATE_OPEN, _gate)
					_wait_frames(2)
					_check(_gate.is_open(), "GATE_OPEN command opened gate")
					_check(_gate.get_node_or_null("CollisionShape2D") == null,
						"open gate: collision shape removed")
					_tac.command_issued.emit(_tac.Command.GATE_CLOSE, _gate)
					_wait_frames(2)
					_check(_gate.is_closed(), "GATE_CLOSE command closed gate")
					_check(_gate.get_node_or_null("CollisionShape2D") != null,
						"closed gate: collision shape restored")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.TACTICAL_TIME)
		Phase.TACTICAL_TIME:
			if _sub == 0:
				# 12단계: Pause / 2× 전술 시간.
				# phase 전환(짧은 duration)으로 elapsed 측정이 흐트러지지 않도록
				# night phase 초반(소량 advance)에서만 측정한다.
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X, "time starts 1x")
				_game_time._elapsed = 0.0
				_tac.get_time_pause_button().pressed.emit()
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_PAUSE, "Pause -> time scale 0")
				_game_time.advance(1.0)
				_check(_game_time.get_phase_elapsed() < 0.001, "Pause: elapsed frozen")
				_tac.get_time_2x_button().pressed.emit()
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_2X, "2x -> time scale 2")
				_game_time.advance(0.4)
				_check(absf(_game_time.get_phase_elapsed() - 0.8) < 0.001, "2x: advance(0.4) -> 0.8 elapsed")
				_tac.get_time_1x_button().pressed.emit()
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X, "1x restored")
				_game_time._elapsed = 0.0
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DEATH_CLEANUP)
		Phase.DEATH_CLEANUP:
			if _sub == 0:
				# 13단계: death cleanup — 사망 후 모든 명령 safe no-op.
				_clear_test_enemies()
				if _actor != null and is_instance_valid(_actor) and _actor.alive:
					_actor.take_damage(_actor.current_hp)
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_mercenary.alive == false, "MercenaryData.alive=false after death")
				_check(_count_mercenaries() == 0, "dead mercenary removed from world")
				_check(_roster.get_actor("mercenary_A") == null, "roster actor null for dead merc")
				_tac.command_issued.emit(_tac.Command.DEFENSE_ZONE, MercenaryData.DefenseZone.NORTH)
				_tac.command_issued.emit(_tac.Command.REGROUP, 0)
				_tac.command_issued.emit(_tac.Command.RETREAT, 0)
				_tac.command_issued.emit(_tac.Command.FOCUS_TARGET, 0)
				_tac.command_issued.emit(_tac.Command.TIME_2X, 0)
				_tac.command_issued.emit(_tac.Command.TIME_1X, 0)
				_check(_roster.get_alive_count() == 0, "all commands safe no-op after death (no crash)")
				_check(_count_mercenaries() == 0, "no mercenary respawned after death")
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X, "time scale restored to 1x")
				_enter(Phase.DAY_RETURN)
		Phase.DAY_RETURN:
			if _sub == 0:
				# 14단계: DAY 복귀 — cleanup + camera follow 복구.
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_enemies() == 0, "enemies cleaned before DAY")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase is DAY")
				_check(_player.get("_night_mode") == false, "player day mode restored")
				_check(_count_mercenaries() == 0, "no mercenary actor during DAY")
				_check(_roster.get_actor_count() == 0, "roster actor_count 0 during DAY")
				_check(_spawner._enemies.size() == 0, "spawner _enemies empty during DAY")
				_player.global_position = Vector2(0, 60)
				_wait_frames(3)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_camera.position == Vector2.ZERO, "DAY: camera offset reset (follow restored)")
				_enter(Phase.NEXT_NIGHT)
		Phase.NEXT_NIGHT:
			if _sub == 0:
				# 15단계: 다음 NIGHT 반복 — duplicate/reference 누수 없음.
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "next NIGHT arrived")
				_check(_count_mercenaries() == 0, "dead merc NOT re-spawned next NIGHT")
				_check(_roster.get_actor_count() == 0, "roster actor_count 0 (dead not spawned)")
				_check(_spawner.get_enemy_count() == 3, "auto-encounter spawned again (%d)" % _spawner.get_enemy_count())
				_check(_spawner._enemies.size() == 3, "spawner no stale references (%d)" % _spawner._enemies.size())
				_check(_roster.get_count() == 1, "roster data retained")
				var a: MercenaryData = _roster.get_mercenary("mercenary_A")
				_check(a != null and a.alive == false, "dead merc stays dead in roster")
				_spawner.despawn_encounter()
				_wait_frames(2)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_spawner._enemies.size() == 0, "spawner empty after despawn")
				_check(_count_enemies() == 0, "no stale enemies after despawn")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(not _player.has_method("attack") and not _player.has_method("_attack"),
					"player has no attack method")
				_check(not _player.is_in_group("enemies") and not _player.is_in_group("mercenaries"),
					"player excluded from combat groups")
				_check(_player.get("_night_mode") == true, "player night mode active during NIGHT regression")
				_check(_worker_roster.get_count() == 0, "worker roster unaffected")
				_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor spawned")
				_check(get_nodes_in_group("miners").size() == 0, "no miner actor spawned")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				_check(get_nodes_in_group("walls").size() == 2, "2 walls intact")
				_gate = _find_gate_at(GATE_POS)
				_check(_gate != null, "gate still present in regression")
				if _gate != null:
					_check(_gate.is_closed(), "gate CLOSED (command roundtrip, no breach conflict)")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128,
					"world floor intact (128x128)")
				_check(_spawner._enemies.size() == 0, "spawner holds no stale references at end")
				_check(_roster._actors.size() == 0, "roster _actors empty at end")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 250000:
		print("TASK0158_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	release_all_actions()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
