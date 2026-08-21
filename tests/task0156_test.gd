extends SceneTree

## TASK-015-6 Gate Command + Tactical Time 검증.
##  - 설치된 N/E/S/W Gate 상태 표시 + OPEN/CLOSE 명령(Gate.set_open 경로).
##  - Gate 없음/null/destroyed(BREACHED)는 안전한 disabled 처리.
##  - 전술 시간 Pause/1x/2x (GameTime 시간 배율).
##  - Pause 상태에서도 UI input 동작.
##  - DAY 진입 시 1x 복원 + 테스트 종료 후 time state 누수 없음.
##  - 2x에서 combat/animation/GameTime/Worker timer가 비정상 중복 실행되지 않음.
##
## 자동검증 항목:
##  1. 시간 배율 API(clamp 포함)와 Pause(0)에서 GameTime 경과 고정.
##  2. Pause 중에도 UI 버튼 입력(성문 OPEN)이 동작.
##  3. 1x vs 2x GameTime 경과 비율이 ~2 (중복/4배 실행 아님).
##  4. 2x에서 전투(용병 공격) hit 수가 1x와 동일(중복 공격 아님).
##  5. 2x에서 Worker(miner) 생산량이 1x와 동일(중복 생산 아님).
##  6. 성문 OPEN/CLOSE 명령 + 상태 라벨(CLOSED/OPEN/BREACHED) 갱신.
##  7. BREACHED 성문 버튼 disabled + 명령 no-op(자동 복구 없음).
##  8. DAY 진입 시 1x 복원 + time state 누수 없음.
##  9. 회귀: Player 무공격/무타겟, 핵심 건물 5/floor, HUD 유지.

enum Phase {
	SETUP,
	PLACE_GATES,
	TO_NIGHT,
	GATE_COMMAND,
	GATE_BREACH,
	COMBAT_1X,
	COMBAT_2X,
	WORKER_1X,
	WORKER_2X,
	TIME_PAUSE,
	TIME_ELAPSED_1X,
	TIME_ELAPSED_2X,
	DAY_RESET,
	REGRESSION,
	DONE,
}

const NORTH_RALLY := Vector2(0, -280)
const NAV_SETTLE_PF := 90
const MEASURE_PF := 60
const BUDGET := 10000
## Miner.State enum 값 (SceneTree 컨텍스트에서 Miner 클래스 직접 참조 회피).
const MINER_IDLE := 0
const MINER_MINE := 2

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

var _north_gate: Node = null
var _east_gate: Node = null

var _combat_enemy: EnemyActor = null
var _hp_start_1x := 0
var _hp_start_2x := 0
var _hits_1x := 0.0
var _hits_2x := 0.0

var _miner: Node = null
var _quarry: Node = null
var _stone_before_1x := 0
var _stone_before_2x := 0
var _stone_1x := 0
var _stone_2x := 0

var _elapsed_1x := 0.0
var _elapsed_2x := 0.0
var _measure_elapsed_start := 0.0
var _pause_elapsed_before := 0.0

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
	print("TASK0156_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _count_mercenaries() -> int:
	return get_nodes_in_group("mercenaries").size()


func _clear_all_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()


func _spawn_enemy(pos: Vector2) -> EnemyActor:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate() as EnemyActor
	if enemy == null:
		return null
	enemy.max_hp = 10000
	enemy.current_hp = 10000
	enemy.attack_damage = 0
	enemy.attack_interval = 0.05
	enemy.setup("t0156_enemy_%d" % _enemy_seq, "Raider", "north")
	enemy.position = pos
	_world.add_child(enemy)
	_enemy_seq += 1
	return enemy


func _spawn_miner() -> void:
	var q_scene: PackedScene = load("res://scenes/quarry.tscn")
	_quarry = q_scene.instantiate()
	_quarry.position = Vector2(400, 400)
	_world.add_child(_quarry)
	var m_scene: PackedScene = load("res://scenes/miner.tscn")
	_miner = m_scene.instantiate()
	_miner.workplace = _quarry
	_miner.production_interval = 0.2
	_miner.state = MINER_MINE
	_miner.position = Vector2(400, 380)
	_world.add_child(_miner)


func _cleanup_miner() -> void:
	if _miner != null and is_instance_valid(_miner):
		_miner.queue_free()
	if _quarry != null and is_instance_valid(_quarry):
		_quarry.queue_free()
	_miner = null
	_quarry = null


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			if _sub == 0:
				_game_time = root.get_node("GameTime")
				_game_time.set_auto_advance(false)
				_game_time.set_durations(1000.0, 1000.0)
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
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X, "time scale defaults to 1x")
				_game_time.set_time_scale(GameTime.TIME_SCALE_2X)
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_2X, "set_time_scale 2x")
				_game_time.set_time_scale(99.0)
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_2X, "set_time_scale clamps to 2x")
				_game_time.set_time_scale(-5.0)
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_PAUSE, "set_time_scale clamps to pause")
				_game_time.set_time_scale(GameTime.TIME_SCALE_1X)
				var ui: Control = get_first_node_in_group("recruitment_ui")
				_check(ui != null, "recruitment UI present")
				ui._on_mercenary_hire_pressed("mercenary_A")
				_mercenary = _roster.get_mercenary("mercenary_A")
				_check(_mercenary != null and _mercenary.alive, "mercenary_A hired alive")
				if _mercenary != null:
					_mercenary.set_defense_zone(MercenaryData.DefenseZone.NORTH)
					_mercenary.attack_damage = 30
					_mercenary.attack_interval = 0.1
					_mercenary.move_speed = 120.0
					_check(_mercenary.defense_zone == MercenaryData.DefenseZone.NORTH, "defense zone NORTH")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.PLACE_GATES)
		Phase.PLACE_GATES:
			if _sub == 0:
				var gate_scene: PackedScene = load("res://scenes/gate.tscn")
				_check(gate_scene != null, "gate scene loads")
				_north_gate = gate_scene.instantiate()
				_north_gate.setup("north")
				_north_gate.position = Vector2(0, -560)
				_world.add_child(_north_gate)
				_check(get_nodes_in_group("gates").size() == 1, "north gate placed")
				_east_gate = gate_scene.instantiate()
				_east_gate.setup("east")
				_east_gate.position = Vector2(560, 0)
				_world.add_child(_east_gate)
				_check(get_nodes_in_group("gates").size() == 2, "east gate placed")
				_check(_north_gate.is_closed() and _east_gate.is_closed(), "new gates start CLOSED")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.TO_NIGHT)
		Phase.TO_NIGHT:
			if _sub == 0:
				_game_time.advance(1000.0)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "DAY -> NIGHT transition")
				_check(_player.get("_night_mode") == true, "player night mode active")
				_check(_tac.visible == true, "tactical command UI visible at NIGHT")
				_check(_tac.get_node("%GateList").get_child_count() == 2, "two gate rows built (N/E)")
				_enter(Phase.GATE_COMMAND)
		Phase.GATE_COMMAND:
			if _sub == 0:
				var list: Node = _tac.get_node("%GateList")
				var row0: Node = list.get_child(0)
				_check((row0.get_child(0) as Label).text == "NORTH", "gate row0 shows NORTH")
				_check((row0.get_child(1) as Label).text == "CLOSED", "north gate state label CLOSED")
				_check((row0.get_child(2) as Button).text == "OPEN", "north gate has OPEN button")
				_check((row0.get_child(3) as Button).text == "CLOSE", "north gate has CLOSE button")
				_check((row0.get_child(2) as Button).disabled == false, "north OPEN button enabled")
				var row1: Node = list.get_child(1)
				_check((row1.get_child(0) as Label).text == "EAST", "gate row1 shows EAST")
				_check((row1.get_child(1) as Label).text == "CLOSED", "east gate state label CLOSED")
				(row0.get_child(2) as Button).pressed.emit()
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_north_gate.is_open() == true, "GATE_OPEN command opens north gate")
				_check((_tac.get_node("%GateList").get_child(0).get_child(1) as Label).text == "OPEN",
					"north gate state label updated to OPEN")
				var row0b: Node = _tac.get_node("%GateList").get_child(0)
				(row0b.get_child(3) as Button).pressed.emit()
				_wait_frames(2)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_north_gate.is_open() == false and _north_gate.is_closed(), "GATE_CLOSE command closes north gate")
				_tac.command_issued.emit(_tac.Command.GATE_OPEN, _north_gate)
				_check(_north_gate.is_open() == true, "direct GATE_OPEN command works")
				_tac.command_issued.emit(_tac.Command.GATE_CLOSE, _north_gate)
				_check(_north_gate.is_closed(), "direct GATE_CLOSE command works")
				_tac.command_issued.emit(_tac.Command.GATE_OPEN, null)
				_tac.command_issued.emit(_tac.Command.GATE_CLOSE, null)
				_check(true, "gate command with null arg is safe (no crash)")
				_enter(Phase.GATE_BREACH)
		Phase.GATE_BREACH:
			if _sub == 0:
				_north_gate.take_damage(9999)
				_check(_north_gate.is_breached(), "north gate breached")
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				var row0: Node = _tac.get_node("%GateList").get_child(0)
				_check((row0.get_child(1) as Label).text == "BREACHED", "north gate state label BREACHED")
				_check((row0.get_child(2) as Button).disabled == true, "north OPEN button disabled when BREACHED")
				_check((row0.get_child(3) as Button).disabled == true, "north CLOSE button disabled when BREACHED")
				var row1: Node = _tac.get_node("%GateList").get_child(1)
				_check((row1.get_child(2) as Button).disabled == false, "intact east gate OPEN button still enabled")
				_tac.command_issued.emit(_tac.Command.GATE_CLOSE, _north_gate)
				_check(_north_gate.is_breached(), "GATE_CLOSE no-op on BREACHED (no auto-recovery)")
				_tac.command_issued.emit(_tac.Command.GATE_OPEN, _north_gate)
				_check(_north_gate.is_breached(), "GATE_OPEN keeps BREACHED open")
				_enter(Phase.COMBAT_1X)
		Phase.COMBAT_1X:
			if _sub == 0:
				_check(_count_mercenaries() == 1, "mercenary actor spawned at NIGHT")
				_actor = _roster.get_actor("mercenary_A")
				_check(_actor != null, "actor retrievable for combat measure")
				if _actor != null:
					_check((_actor as Node2D).global_position.distance_to(NORTH_RALLY) < 1.0,
						"actor at north rally")
					_check(_actor.get_state() == MercenaryActor.MercState.IDLE, "actor starts IDLE")
				_game_time.set_time_scale(GameTime.TIME_SCALE_1X)
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf < NAV_SETTLE_PF:
					return false
				_clear_all_enemies()
				_combat_enemy = _spawn_enemy(NORTH_RALLY + Vector2(0, 20))
				_check(_combat_enemy != null, "combat enemy spawned in attack range")
				_budget = 0
				_sub = 2
			elif _sub == 2:
				if _budget >= BUDGET:
					_check(false, "mercenary never engaged combat")
					_wait_frames(4)
				elif _actor != null and is_instance_valid(_actor) \
						and _actor.get_state() == MercenaryActor.MercState.ATTACK:
					_wait_frames(2)
				else:
					_budget += 1
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.ATTACK,
						"actor engaged combat at 1x")
					var visual := _actor.get_node_or_null("Visual") as AnimatedSprite2D
					_check(visual != null and visual.animation != "", "actor visual animation active")
				if _combat_enemy != null and is_instance_valid(_combat_enemy):
					_hp_start_1x = _combat_enemy.current_hp
					if _actor != null and is_instance_valid(_actor):
						_actor._attack_cd = 0.0
				_pf = 0
				_sub = 4
			elif _sub == 4:
				if _pf < MEASURE_PF:
					return false
				var hp_now := _combat_enemy.current_hp if is_instance_valid(_combat_enemy) else 0
				_hits_1x = float(_hp_start_1x - hp_now) / float(_mercenary.attack_damage)
				_check(_hits_1x > 0.0, "combat hits at 1x > 0 (%.1f)" % _hits_1x)
				_enter(Phase.COMBAT_2X)
		Phase.COMBAT_2X:
			if _sub == 0:
				_game_time.set_time_scale(GameTime.TIME_SCALE_2X)
				if _combat_enemy != null and is_instance_valid(_combat_enemy):
					_hp_start_2x = _combat_enemy.current_hp
					if _actor != null and is_instance_valid(_actor):
						_actor._attack_cd = 0.0
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf < MEASURE_PF:
					return false
				var hp_now := _combat_enemy.current_hp if is_instance_valid(_combat_enemy) else 0
				_hits_2x = float(_hp_start_2x - hp_now) / float(_mercenary.attack_damage)
				_check(absf(_hits_2x - _hits_1x) <= 2.0,
					"combat not double-run at 2x (1x=%.1f 2x=%.1f)" % [_hits_1x, _hits_2x])
				if _actor != null and is_instance_valid(_actor):
					var visual := _actor.get_node_or_null("Visual") as AnimatedSprite2D
					_check(visual != null and visual.animation != "", "actor visual animation still active at 2x")
				_game_time.set_time_scale(GameTime.TIME_SCALE_1X)
				if _combat_enemy != null and is_instance_valid(_combat_enemy):
					_combat_enemy.queue_free()
				_combat_enemy = null
				_wait_frames(2)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(get_nodes_in_group("enemies").size() == 0, "combat test enemy cleaned")
				_enter(Phase.WORKER_1X)
		Phase.WORKER_1X:
			if _sub == 0:
				_spawn_miner()
				_check(_miner != null and _quarry != null, "miner + quarry spawned")
				_game_time.set_time_scale(GameTime.TIME_SCALE_1X)
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_miner._produce_timer = 0.0
				_stone_before_1x = _resources.get_amount("stone")
				_pf = 0
				_sub = 2
			elif _sub == 2:
				if _pf < MEASURE_PF:
					return false
				_stone_1x = _resources.get_amount("stone") - _stone_before_1x
				_check(_stone_1x > 0, "miner produced stone at 1x (%d)" % _stone_1x)
				_enter(Phase.WORKER_2X)
		Phase.WORKER_2X:
			if _sub == 0:
				_game_time.set_time_scale(GameTime.TIME_SCALE_2X)
				_miner._produce_timer = 0.0
				_stone_before_2x = _resources.get_amount("stone")
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf < MEASURE_PF:
					return false
				_stone_2x = _resources.get_amount("stone") - _stone_before_2x
				_check(_stone_2x == _stone_1x or absi(_stone_2x - _stone_1x) <= 1,
					"worker timer not double-run at 2x (1x=%d 2x=%d)" % [_stone_1x, _stone_2x])
				_game_time.set_time_scale(GameTime.TIME_SCALE_1X)
				_cleanup_miner()
				_wait_frames(2)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(get_nodes_in_group("miners").size() == 0, "miner cleaned up")
				_enter(Phase.TIME_PAUSE)
		Phase.TIME_PAUSE:
			if _sub == 0:
				_game_time.set_auto_advance(true)
				_tac.get_time_pause_button().pressed.emit()
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_PAUSE, "pause button sets time scale 0")
				_pause_elapsed_before = _game_time.get_phase_elapsed()
				_wait_frames(15)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase_elapsed() == _pause_elapsed_before,
					"GameTime elapsed frozen while paused")
				_check(_tac.visible == true, "tactical UI visible during pause (NIGHT)")
				var east_row: Node = _tac.get_node("%GateList").get_child(1)
				_check((east_row.get_child(1) as Label).text == "CLOSED", "east gate CLOSED before pause open")
				(east_row.get_child(2) as Button).pressed.emit()
				_check(_east_gate.is_open() == true, "gate OPEN command works while paused (UI input active)")
				_wait_frames(2)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check((_tac.get_node("%GateList").get_child(1).get_child(1) as Label).text == "OPEN",
					"east gate state label updated to OPEN")
				_tac.get_time_1x_button().pressed.emit()
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X, "1x button resumes from pause")
				_enter(Phase.TIME_ELAPSED_1X)
		Phase.TIME_ELAPSED_1X:
			if _sub == 0:
				_tac.get_time_1x_button().pressed.emit()
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X, "1x button sets scale 1")
				_measure_elapsed_start = _game_time.get_phase_elapsed()
				_wait_frames(60)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_elapsed_1x = _game_time.get_phase_elapsed() - _measure_elapsed_start
				_check(_elapsed_1x > 0.0, "GameTime elapsed grew at 1x (%.3f)" % _elapsed_1x)
				_enter(Phase.TIME_ELAPSED_2X)
		Phase.TIME_ELAPSED_2X:
			if _sub == 0:
				_tac.get_time_2x_button().pressed.emit()
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_2X, "2x button sets scale 2")
				_measure_elapsed_start = _game_time.get_phase_elapsed()
				_wait_frames(60)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_elapsed_2x = _game_time.get_phase_elapsed() - _measure_elapsed_start
				_check(_elapsed_2x >= _elapsed_1x * 1.5 and _elapsed_2x <= _elapsed_1x * 2.6,
					"2x advances ~2x, not doubled/quadrupled (1x=%.3f 2x=%.3f)" % [_elapsed_1x, _elapsed_2x])
				_enter(Phase.DAY_RESET)
		Phase.DAY_RESET:
			if _sub == 0:
				_tac.get_time_2x_button().pressed.emit()
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_2X, "2x active before DAY entry")
				_game_time.set_auto_advance(false)
				var rem: float = _game_time.get_phase_duration() - _game_time.get_phase_elapsed()
				_game_time.advance(rem / 2.0 + 0.001)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "advanced to DAY while at 2x")
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X,
					"time scale restored to 1x on DAY entry")
				_check(_tac.visible == false, "tactical UI hidden at DAY")
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X, "time scale stays 1x after DAY (no leak)")
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
				_check(get_nodes_in_group("gates").size() == 2, "two gates still present")
				_check(_game_time.get_time_scale() == GameTime.TIME_SCALE_1X,
					"no time scale leak (1x after DAY)")
				_check(_hud.get_node("WoodLabel") != null and _hud.get_node("StoneLabel") != null \
					and _hud.get_node("DayTimeLabel") != null, "existing Wood/Stone/DayTime HUD intact")
				_check(_roster.get_mercenary("mercenary_A") != null, "mercenary data intact")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0156_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)