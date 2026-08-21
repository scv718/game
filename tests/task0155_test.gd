extends SceneTree

## TASK-015-5 Focus Target 검증.
## 전술 명령 UI의 FOCUS_TARGET 명령이 Focus Target mode를 토글하고,
## 플레이어가 선택한 Enemy를 모든 용병 Actor의 우선 target으로 삼는지 검증한다.
##
## 자동검증 항목:
##  1. FOCUS_TARGET 명령으로 focus mode 토글 활성화.
##  2. focus_mode / has_focus_target / get_focus_target API 확인.
##  3. set_focus_target으로 Enemy 지정 → MercenaryActor가 해당 target을 우선 추격.
##  4. focus target이 다른 Enemy보다 우선순위 높음 (zone enemy도 무시).
##  5. focus target 사망(died) → 자동 focus 해제 (clear_focus_target).
##  6. focus target freed(queue_free) → 자동 focus 해제.
##  7. toggle_focus_mode() off → focus 해제 + focus_mode=false.
##  8. REGROUP/RETREAT 중 set_focus_target → 즉시 전환 안 함, 도착 후 우선 target.
##  9. 회귀: Player 무공격/무타겟, NIGHT Player 이동 비활성, 핵심 건물/floor 유지.

enum Phase {
	SETUP,
	HIRE_NORTH,
	TO_NIGHT,
	SPAWN_ACTOR,
	TOGGLE_FOCUS_ON,
	FOCUS_ACTIVE,
	SELECT_FOCUS_TARGET,
	FOCUS_PRIORITY,
	FOCUS_TARGET_KILLED,
	AUTO_RELEASE,
	FOCUS_CLEARED,
	TOGGLE_FOCUS_OFF,
	FOCUS_DURING_RETREAT,
	FOCUS_RESUME_AFTER_COMMAND,
	REGRESSION,
	DONE,
}

const NORTH_RALLY := Vector2(0, -280)
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
var _focus_enemy: EnemyActor = null
var _zone_enemy: EnemyActor = null
var _safe_rally := Vector2.ZERO


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
	print("TASK0155_RESULT=" + ("FAIL" if _failed else "PASS"))
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
	enemy.setup("test_enemy_%d" % _enemy_seq, "Raider", "north")
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
				_check(_roster.is_focus_mode_active() == false, "focus mode starts inactive")
				_check(_roster.has_focus_target() == false, "no focus target initially")
				_check(_roster.get_focus_target() == null, "get_focus_target returns null initially")
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
					_check(_actor.get_focus_target() == null, "actor focus target initially null")
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf >= NAV_SETTLE_PF:
					_enter(Phase.TOGGLE_FOCUS_ON)
		Phase.TOGGLE_FOCUS_ON:
			if _sub == 0:
				_tac.get_focus_target_button().pressed.emit()
				_check(_roster.is_focus_mode_active() == true, "focus mode activated via UI button")
				_check(_roster.has_focus_target() == false, "no target yet after toggle on")
				_enter(Phase.FOCUS_ACTIVE)
		Phase.FOCUS_ACTIVE:
			if _sub == 0:
				_zone_enemy = _spawn_enemy(Vector2(0, -350))
				_check(_zone_enemy != null, "zone enemy spawned near north defense")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				_wait_target("mercenary never acquired zone target")
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() != null, "mercenary acquired zone target before focus")
				_enter(Phase.SELECT_FOCUS_TARGET)
		Phase.SELECT_FOCUS_TARGET:
			if _sub == 0:
				_focus_enemy = _spawn_enemy(Vector2(50, -350))
				_check(_focus_enemy != null, "focus candidate enemy spawned")
				_roster.set_focus_target(_focus_enemy)
				_check(_roster.is_focus_mode_active() == true, "focus mode remains active after set")
				_check(_roster.has_focus_target() == true, "has_focus_target true after set")
				_check(_roster.get_focus_target() == _focus_enemy, "get_focus_target returns selected enemy")
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_focus_target() == _focus_enemy, "actor received focus target")
				_wait_frames(10)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_enter(Phase.FOCUS_PRIORITY)
		Phase.FOCUS_PRIORITY:
			if _sub == 0:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.is_focusing(), "actor is focusing on focus target")
					_check(_actor.get_target() == _focus_enemy,
						"actor target IS the focus enemy (priority over zone enemy)")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_enemies() == 0, "focus priority test enemies cleaned")
				_enter(Phase.FOCUS_TARGET_KILLED)
		Phase.FOCUS_TARGET_KILLED:
			if _sub == 0:
				_focus_enemy = _spawn_enemy(Vector2(0, -360))
				_check(_focus_enemy != null, "new focus enemy spawned for kill test")
				_roster.set_focus_target(_focus_enemy)
				_wait_frames(4)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_roster.has_focus_target() == true, "focus target set before kill")
				if _focus_enemy != null and is_instance_valid(_focus_enemy):
					_focus_enemy.take_damage(_focus_enemy.current_hp + 100)
				_wait_frames(4)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_roster.has_focus_target() == false,
					"focus auto-released after target killed (died signal)")
				_check(_roster.get_focus_target() == null,
					"get_focus_target null after kill")
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_focus_target() == null,
						"actor focus target cleared after enemy death")
				_enter(Phase.AUTO_RELEASE)
		Phase.AUTO_RELEASE:
			if _sub == 0:
				_focus_enemy = _spawn_enemy(Vector2(20, -360))
				_check(_focus_enemy != null, "focus enemy spawned for freed test")
				_roster.set_focus_target(_focus_enemy)
				_check(_roster.has_focus_target() == true, "focus target set before freed")
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				if _focus_enemy != null and is_instance_valid(_focus_enemy):
					_focus_enemy.queue_free()
				_wait_frames(4)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_roster.has_focus_target() == false,
					"focus auto-released after target freed (tree_exiting signal)")
				_enter(Phase.FOCUS_CLEARED)
		Phase.FOCUS_CLEARED:
			if _sub == 0:
				_focus_enemy = _spawn_enemy(Vector2(10, -360))
				_check(_focus_enemy != null, "focus enemy spawned for toggle-off test")
				_roster.set_focus_target(_focus_enemy)
				_check(_roster.has_focus_target() == true, "focus target set")
				_roster.toggle_focus_mode()
				_check(_roster.is_focus_mode_active() == false,
					"focus mode deactivated via toggle")
				_check(_roster.has_focus_target() == false,
					"focus target cleared on toggle off")
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_focus_target() == null,
						"actor focus target cleared on toggle off")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_enemies() == 0, "toggle-off test enemies cleaned")
				_enter(Phase.TOGGLE_FOCUS_OFF)
		Phase.TOGGLE_FOCUS_OFF:
			if _sub == 0:
				_check(_roster.is_focus_mode_active() == false, "focus mode still off")
				_check(_roster.has_focus_target() == false, "no focus target while off")
				_focus_enemy = _spawn_enemy(Vector2(30, -360))
				_check(_focus_enemy != null, "focus candidate enemy spawned for double-toggle")
				_roster.set_focus_target(_focus_enemy)
				_check(_roster.is_focus_mode_active() == true,
					"set_focus_target re-enables focus mode")
				_roster.toggle_focus_mode()
				_check(_roster.is_focus_mode_active() == false,
					"toggle off again deactivates focus")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_enter(Phase.FOCUS_DURING_RETREAT)
		Phase.FOCUS_DURING_RETREAT:
			if _sub == 0:
				_zone_enemy = _spawn_enemy(Vector2(0, -350))
				_check(_zone_enemy != null, "zone enemy for retreat-focus test")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				_wait_target("mercenary never engaged before retreat")
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_tac.get_retreat_button().pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.RETREAT,
						"actor entered RETREAT (state=%d)" % _actor.get_state())
				_focus_enemy = _spawn_enemy(Vector2(100, -200))
				_check(_focus_enemy != null, "focus enemy spawned during retreat")
				_roster.set_focus_target(_focus_enemy)
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() == MercenaryActor.MercState.RETREAT,
						"actor stays RETREAT despite focus set (state=%d)" % _actor.get_state())
					_check(_actor.get_focus_target() == _focus_enemy,
						"actor stores focus target even during retreat")
					_check(_actor.get_target() == null,
						"retreat clears current target")
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "retreat-focus test enemies cleaned")
				_enter(Phase.FOCUS_RESUME_AFTER_COMMAND)
		Phase.FOCUS_RESUME_AFTER_COMMAND:
			if _sub == 0:
				_focus_enemy = _spawn_enemy(Vector2(280, -340))
				_check(_focus_enemy != null, "focus enemy for resume test")
				_roster.set_focus_target(_focus_enemy)
				_tac.get_defense_zone_button(MercenaryData.DefenseZone.EAST).pressed.emit()
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_state() != MercenaryActor.MercState.RETREAT,
						"actor left RETREAT after defense zone command (state=%d)" % _actor.get_state())
					_check(_actor.get_focus_target() == _focus_enemy,
						"actor retains focus target after command")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				_wait_target("mercenary never resumed with focus target")
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_focus_target() == _focus_enemy,
						"focus target persists after resume")
					_check(_actor.is_focusing() or _actor.get_target() == _focus_enemy,
						"actor resumed and acquired focus target (state=%d)" % _actor.get_state())
				_clear_test_enemies()
				_wait_frames(2)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "resume test enemies cleaned")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(not _player.has_method("attack") and not _player.has_method("_attack"),
					"player has no attack method")
				_check(not _player.is_in_group("enemies") and not _player.is_in_group("mercenaries"),
					"player excluded from combat groups")
				_check(_player.get("_night_mode") == true, "player night mode active during NIGHT")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128,
					"world floor intact")
				_roster.toggle_focus_mode()
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0155_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
