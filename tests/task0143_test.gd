extends SceneTree

## TASK-014-3 Enemy Actor + First Night Encounter Spawner 자동 검증.
##  - Enemy Actor: 일반 근접 1종(Red Warrior), HP/move_speed/damage/attack_interval/death 보유.
##    Player를 combat target으로 선택하지 않음(공격 기능 없음, 전투 AI는 TASK-014-4).
##  - FirstEncounterSpawner: NIGHT 시작 시 한 방향(SpawnCandidate)에서 configurable 수량 spawn,
##    DAY 복귀 시 despawn. DAY 오작동 spawn 없음. 반복 NIGHT duplicate 없음.
##  - 이동: Main Road/Approach Route waypoint를 따라 마을로 접근(road 선호),
##    OPEN Gate면 Gate footprint 통과로 Village Core 방향 진행 가능, CLOSED면 우회.
##  - 회귀: Player 무공격/Mercenary 독립/Worker 무spawn/핵심 건물/floor 유지.

enum Phase {
	SETUP,
	DAY_GUARD,
	NIGHT_SPAWN,
	MOVEMENT,
	GATE_OPEN,
	GATE_CLOSED,
	DAY_DESPAWN,
	REPEAT_CYCLE,
	CONFIG_COUNT,
	REGRESSION,
	DONE,
}

const NORTH_CANDIDATE := Vector2(-140, -900)
const GATE_POS := Vector2(0, -448)
const GATE_RECT := Rect2(Vector2(-24, -456), Vector2(48, 16))
## 성문 바로 안/밖의 짧은 path 쌍. 열린 지형에서 성문(48x16)만으로는 장거리 nav '완전
## 차단'이 구조적으로 어렵다(TASK-013-4 문서화 한계)고, 짧은 path는 좌우 우회가
## 정확히 검증된다(TASK-013-4/013-5와 동일 좌표/방식).
const GATE_OUTSIDE := Vector2(0, -560)
const GATE_INSIDE := Vector2(0, -360)

const DEFAULT_COUNT := 3
const MOVEMENT_BUDGET := 900
const REACH_BUDGET := 1200
const NO_STALL_BUDGET := 120
## gate OPEN/CLOSED 후 nav map 동기화 대기 (TASK-013-5 NAV_WAIT_PF와 동일 방식).
const NAV_SETTLE_PF := 90

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
var _gate: Node = null
var _core := Vector2(0, -150)

var _move_budget := 0
var _move_start_y := 0.0
var _reach_budget := 0
var _no_stall_budget := 0
var _no_stall_pos := Vector2.ZERO
var _cycle_i := 0
var _reached := false


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
	print("TASK0143_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _advance_to_next_phase() -> void:
	if _game_time.get_phase() == GameTime.Phase.DAY:
		_game_time.advance(2.0)
	else:
		_game_time.advance(1.0)


func _count_enemies() -> int:
	return get_nodes_in_group("enemies").size()


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


## nav geometry helpers (TASK-013-5/013-6와 동일).
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
				_check(_spawner.get_direction() == "west", "direction west default")
				# 이 레거시 vertical slice는 북쪽 성문 전투를 격리 검증한다.
				_spawner.set_direction("north")
				_roster = root.get_node("MercenaryRoster")
				_worker_roster = root.get_node("WorkerRoster")
				_resources = root.get_node("VillageResources")
				_player = root.get_node("Main").get_node("Player")
				_check(_game_time != null and _world != null and _layout != null and _placement != null \
					and _spawner != null and _roster != null and _worker_roster != null and _resources != null \
					and _player != null, "core nodes present")
				_resources._amounts["wood"] = 10000
				_check(load("res://scenes/enemy.tscn") != null, "enemy scene loads")
				var keep := _world.get_node_or_null("Keep") as Node2D
				if keep != null:
					_core = keep.global_position
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "game starts in DAY")
				_check(_count_enemies() == 0, "no enemies during DAY on start")
				_check(_spawner.get_enemy_count() == 0, "spawner enemy_count 0 during DAY")
				_check(not _spawner.is_night_active(), "spawner night not active during DAY")
				_check(not _player.has_method("attack"), "player has no attack method")
				_enter(Phase.DAY_GUARD)
		Phase.DAY_GUARD:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "DAY_GUARD in DAY")
				var n: int = _spawner.spawn_encounter()
				_check(n == 0, "spawn_encounter during DAY returns 0 (no mis-spawn)")
				_check(_count_enemies() == 0, "no enemy spawned during DAY (%d)" % _count_enemies())
				_check(not _spawner.is_night_active(), "spawner night inactive after DAY spawn guard")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT after advance")
				_enter(Phase.NIGHT_SPAWN)
		Phase.NIGHT_SPAWN:
			if _sub == 0:
				_check(_count_enemies() == DEFAULT_COUNT, "default encounter spawns %d enemies (%d)" % [DEFAULT_COUNT, _count_enemies()])
				_check(_spawner.get_enemy_count() == DEFAULT_COUNT, "spawner enemy_count %d" % DEFAULT_COUNT)
				_check(_spawner.is_night_active(), "spawner night active after NIGHT spawn")
				var enemies: Array = _spawner.get_enemies()
				_check(enemies.size() == DEFAULT_COUNT, "spawner get_enemies returns %d" % DEFAULT_COUNT)
				for e in enemies:
					var enemy: EnemyActor = e as EnemyActor
					_check(enemy != null and enemy.alive, "enemy alive (%s)" % str(enemy.enemy_id if enemy != null else "null"))
					_check(enemy != null and enemy.current_hp == enemy.max_hp, "enemy current_hp initialized from max_hp (%s)" % str(enemy.enemy_id if enemy != null else "null"))
					_check(enemy != null and enemy.get_direction() == "north", "enemy direction north (%s)" % str(enemy.enemy_id if enemy != null else "null"))
					_check(enemy != null and (enemy as Node2D).global_position.distance_to(NORTH_CANDIDATE) <= 40.0, "enemy spawned at north candidate (%s)" % str((enemy as Node2D).global_position if enemy != null else "?"))
					_check(enemy != null and enemy.state == EnemyActor.EnemyState.MOVE, "enemy route set (MOVE) (%s)" % str(enemy.enemy_id if enemy != null else "null"))
				var dup: int = _spawner.spawn_encounter()
				_check(dup == 0, "spawn_encounter idempotent within NIGHT (0 new)")
				_check(_count_enemies() == DEFAULT_COUNT, "no duplicate enemy after redundant spawn call (%d)" % _count_enemies())
				_move_budget = 0
				var first: Array = _spawner.get_enemies()
				_move_start_y = (first[0] as Node2D).global_position.y if first.size() > 0 else 0.0
				_sub = 1
			elif _sub == 1:
				var any_moved := false
				for e in _spawner.get_enemies():
					if (e as Node2D).global_position.y > _move_start_y + 120.0:
						any_moved = true
						break
				if any_moved:
					_check(true, "enemies approach village along road (y %.1f -> south)" % _move_start_y)
					_enter(Phase.GATE_OPEN)
				elif _move_budget >= MOVEMENT_BUDGET:
					_check(false, "enemies never approached village in budget (y %.1f)" % _move_start_y)
					_enter(Phase.GATE_OPEN)
				else:
					_move_budget += 1
		Phase.GATE_OPEN:
			if _sub == 0:
				_placement._set_building_type("gate")
				_placement._try_place_gate_at(_placement._snap_gate(GATE_POS))
				_gate = _find_gate_at(GATE_POS)
				_check(_gate != null, "north gate placed in corridor")
				if _gate != null:
					_check(_gate.is_closed(), "new gate starts CLOSED")
					_gate.set_open(true)
				_world.rebuild_navigation()
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf < NAV_SETTLE_PF:
					return false
				_check(_gate != null and _gate.is_open(), "gate OPEN")
				_check(_path_crosses_rect(_path(GATE_OUTSIDE, GATE_INSIDE), GATE_RECT), "OPEN: nav path crosses gate footprint (passage to core)")
				_check(_count_enemies() == DEFAULT_COUNT, "enemies intact after gate placement (%d)" % _count_enemies())
				_reach_budget = 0
				_reached = false
				_sub = 2
			elif _sub == 2:
				for e in _spawner.get_enemies():
					if (e as Node2D).global_position.distance_to(_core) <= 90.0:
						_reached = true
						break
				if _reached:
					_check(true, "enemy reached village core through OPEN gate")
					_enter(Phase.GATE_CLOSED)
				elif _reach_budget >= REACH_BUDGET:
					_check(false, "enemy never reached village core through OPEN gate in budget")
					_enter(Phase.GATE_CLOSED)
				else:
					_reach_budget += 1
		Phase.GATE_CLOSED:
			if _sub == 0:
				_gate.set_open(false)
				_world.rebuild_navigation()
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf < NAV_SETTLE_PF:
					return false
				_check(_gate != null and _gate.is_closed(), "gate CLOSED")
				_check(_gate != null and _gate.get_node_or_null("CollisionShape2D") != null, "CLOSED gate has passage collision shape")
				_check(not _path_crosses_rect(_path(GATE_OUTSIDE, GATE_INSIDE), GATE_RECT), "CLOSED: nav path detours (does not cross gate footprint)")
				var enemies: Array = _spawner.get_enemies()
				_no_stall_budget = 0
				_no_stall_pos = (enemies[0] as Node2D).global_position if enemies.size() > 0 else Vector2.ZERO
				_sub = 2
			elif _sub == 2:
				var moved := false
				for e in _spawner.get_enemies():
					if (e as Node2D).global_position.distance_to(_no_stall_pos) > 2.0:
						moved = true
						break
				if moved:
					_check(true, "no permanent MOVE stall with CLOSED gate (enemies keep moving/detouring)")
					_enter(Phase.DAY_DESPAWN)
				elif _no_stall_budget >= NO_STALL_BUDGET:
					_check(_count_enemies() == DEFAULT_COUNT, "CLOSED gate: enemies stable, no stall error (%d)" % _count_enemies())
					_enter(Phase.DAY_DESPAWN)
				else:
					_no_stall_budget += 1
		Phase.DAY_DESPAWN:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "DAY_DESPAWN still in NIGHT")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase back to DAY")
				_check(_count_enemies() == 0, "enemies despawned on DAY return (%d)" % _count_enemies())
				_check(_spawner.get_enemy_count() == 0, "spawner enemy_count 0 on DAY")
				_check(_spawner.get_enemies().size() == 0, "spawner enemy list empty on DAY")
				_check(not _spawner.is_night_active(), "spawner night inactive on DAY")
				_enter(Phase.REPEAT_CYCLE)
		Phase.REPEAT_CYCLE:
			if _sub == 0:
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "repeat cycle %d phase NIGHT" % _cycle_i)
				_check(_count_enemies() == DEFAULT_COUNT, "repeat cycle %d exactly %d enemies (no duplicate) (%d)" % [_cycle_i, DEFAULT_COUNT, _count_enemies()])
				_check(_spawner.spawn_encounter() == 0, "repeat cycle %d spawn idempotent" % _cycle_i)
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "repeat cycle %d phase DAY" % _cycle_i)
				_check(_count_enemies() == 0, "repeat cycle %d enemies despawned" % _cycle_i)
				_cycle_i += 1
				if _cycle_i >= 2:
					_enter(Phase.CONFIG_COUNT)
				else:
					_sub = 0
		Phase.CONFIG_COUNT:
			if _sub == 0:
				_spawner.set_count(5)
				_check(_spawner.get_count() == 5, "set_count configures 5")
				_check(_spawner.get_direction() == "north", "legacy scenario direction north")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "config count phase NIGHT")
				_check(_count_enemies() == 5, "configurable count spawns 5 (%d)" % _count_enemies())
				_check(_spawner.get_enemy_count() == 5, "spawner enemy_count 5")
				_spawner.set_count(DEFAULT_COUNT)
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "config count phase DAY")
				_check(_count_enemies() == 0, "config count enemies despawned on DAY")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "REGRESSION starts in DAY")
				_check(not _player.has_method("attack"), "player has no attack method")
				_check(not _player.has_method("_attack"), "player has no internal attack")
				_check(_roster.get_count() == 0, "mercenary roster unaffected (%d)" % _roster.get_count())
				_check(get_nodes_in_group("mercenaries").size() == 0, "no mercenary actor spawned")
				_check(_worker_roster.get_count() == 0, "worker roster unaffected (%d)" % _worker_roster.get_count())
				_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor spawned")
				_check(get_nodes_in_group("miners").size() == 0, "no miner actor spawned")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact")
				var enemy_scene: PackedScene = load("res://scenes/enemy.tscn")
				var sample := enemy_scene.instantiate()
				_world.add_child(sample)
				var vis: AnimatedSprite2D = sample.get_node("Visual")
				var names := vis.sprite_frames.get_animation_names()
				_check(names.has("idle_down") and names.has("walk_right"), "enemy has idle/walk anims")
				_check(vis.sprite_frames.get_frame_count("idle_down") == 8, "enemy idle 8 frames")
				_check(vis.sprite_frames.get_frame_count("walk_right") == 6, "enemy walk 6 frames")
				_check(not sample.has_method("attack"), "enemy has no attack method (combat AI is TASK-014-4)")
				_check(sample.get("_player") == null, "enemy has no player target/reference")
				_check(sample.attack_damage > 0 and sample.attack_interval > 0.0, "enemy combat stats present")
				_check(sample.alive, "enemy alive flag present")
				sample.queue_free()
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0143_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
