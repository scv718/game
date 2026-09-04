extends SceneTree

## TASK-025-2 Ghost Spawn Mix Integration 자동 검증.
##  - existing Wave/Threat spawn(FirstEncounterSpawner3D)과 충돌 없이 Ghost return mix.
##  - Ghost는 일반 enemy spawn budget(count)을 점유(regular count 차감, 합계 = count).
##  - configurable queue insertion policy(max_ghosts_per_night) - hardcoded random 없음.
##  - same candidate once only: candidate 1회만 spawn, 이후 재삽입 없음.
##  - spawn failure recovery: 실패 시 candidate 유실 없이 큐 복원.
##  - Ghost death가 신규 DeathRecord를 만들지 않고(재귀 방지) 원본 record를 RESOLVED 처리.
##  - DAY 복귀 시 Ghost despawn(무기록)으로 wave 완료 deadlock 없음.
## 회귀: main scene 유지, autoload 유지, regular enemy spawn 무영향.
##
## 주의: -s 단독 기동에서 autoload 전역 식별자는 미등록이므로 GameTime/DeathLedger/
## FirstEncounterSpawner3D 등은 반드시 root.get_node로 접근하고, static 클래스 참조는
## class_name 스크립트(WorldCoords3D/EnemyActor3D/GhostActor3D 등)만 사용한다.

enum Phase {
	SETUP, STRUCTURE, REGISTER_CANDIDATES, TO_NIGHT, MIXED_CHECK, GHOST_DEATH,
	FAILURE_RECOVERY, DAY_CLEANUP, REPEAT_NIGHT, KILL_B, FINAL_CLEANUP,
	REGRESSION, DONE,
}

var _frame := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _wait := 0
var _failed := false

var _world: Node = null
var _nav_manager: Node = null
var _game_time: Node = null
var _ledger: Node = null
var _spawner: Node = null
var _mix: Node = null

var _record_ids: Array[String] = []
var _ghost: Node = null


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
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK0252_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _group_count(group_name: String) -> int:
	return get_nodes_in_group(group_name).size()


## 각 phase duration이 1.0 이상이므로 0.5 step으로 한 번에 한 경계만 넘으며,
## 목표 phase에 도달하면 즉시 멈춰 over-shoot(이중 전환)를 방지한다.
func _force_phase(target_phase: int) -> void:
	for _i in 60:
		if _game_time.get_phase() == target_phase:
			return
		_game_time.advance(0.5)


func _register_enemy_death(uid: String, display: String) -> String:
	var r := DeathRecord.new("")
	r.source_uid = uid
	r.source_kind = DeathRecord.SourceKind.ENEMY
	r.category = "ENEMY"
	r.display_name = display
	r.class_or_type = display
	r.level = 1
	r.max_hp = 80
	r.attack_damage = 12
	r.attack_interval = 1.0
	r.move_speed = 120.0
	r.death_day = _game_time.get_day_number()
	r.death_phase = DeathRecord.DeathPhase.NIGHT
	var rec: DeathRecord = _ledger.record_death(r.to_snapshot())
	return rec.record_id if rec != null else ""


func _find_ghost() -> Node:
	for g in get_nodes_in_group("ghosts_3d"):
		if is_instance_valid(g):
			return g
	return null


func _ghost_ids() -> Array:
	var out: Array = []
	for g in get_nodes_in_group("ghosts_3d"):
		if is_instance_valid(g):
			out.append(g.get("source_record_id"))
	return out


func _status_of(record_id: String) -> int:
	var rec: DeathRecord = _ledger.get_record(record_id)
	return rec.get_status() if rec != null else -1


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
					_game_time.set_durations(3.0, 1.0)
				_ledger = root.get_node("DeathLedger")
				_check(_game_time != null and _ledger != null, "core autoloads present")
				_force_phase(GameTime.Phase.DAY)
				_sub = 1
			elif _sub == 1:
				_enter(Phase.STRUCTURE)
		Phase.STRUCTURE:
			if _sub == 0:
				_check(_ledger.get_all_records().size() == 0, "ledger starts empty")
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase is DAY before spawn")
				_check(FileAccess.file_exists("res://scenes/ghost_3d.tscn"), "ghost_3d.tscn exists")
				_check(FileAccess.file_exists("res://scripts/ghost_actor_3d.gd"), "ghost_actor_3d.gd exists")
				_check(FileAccess.file_exists("res://scripts/ghost_spawn_mix.gd"), "ghost_spawn_mix.gd exists")
				_check(_mix != null, "GhostSpawnMix node exists")
				if _mix != null:
					_check(_mix.get("max_ghosts_per_night") == 1, "max_ghosts_per_night configurable (default 1)")
				_check(_spawner.get_count() == 3, "spawner count default 3")
				_enter(Phase.REGISTER_CANDIDATES)
		Phase.REGISTER_CANDIDATES:
			if _sub == 0:
				var id1 := _register_enemy_death("ghost_cand_A", "Fallen Raider")
				var id2 := _register_enemy_death("ghost_cand_B", "Wight Slasher")
				var id3 := _register_enemy_death("ghost_cand_C", "Spectral Brute")
				_record_ids = [id1, id2, id3]
				_check(_record_ids.size() == 3 and _record_ids[0] != "", "3 eligible ghost candidates registered")
				_check(_ledger.get_pending_records().size() == 3, "3 PENDING records in ledger")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.TO_NIGHT)
		Phase.TO_NIGHT:
			if _sub == 0:
				_force_phase(GameTime.Phase.NIGHT)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT")
				_check(_spawner.is_night_active(), "spawner night active")
				_enter(Phase.MIXED_CHECK)
		Phase.MIXED_CHECK:
			if _sub == 0:
				var ghost_count: int = _mix.get_spawned_count()
				var enemy_count: int = _spawner.get_enemy_count()
				_check(ghost_count == 1, "exactly 1 ghost mixed into wave (%d)" % ghost_count)
				_check(enemy_count == 2, "regular enemy budget reduced to 2 (budget occupied) (%d)" % enemy_count)
				_check(enemy_count + ghost_count == _spawner.get_count(), "total wave size == count")
				_check(_group_count("ghosts_3d") == 1, "ghost actor present in world")
				_ghost = _find_ghost()
				_check(_ghost != null, "ghost node found")
				if _ghost != null:
					_check(_ghost.get("source_record_id") == _record_ids[0], "ghost carries original record id (A)")
					_check(_ghost.get("display_name") == "Fallen Raider", "ghost carries original identity")
					_check(_ghost.is_in_group("ghosts_3d"), "ghost in ghosts_3d group")
				_check(_status_of(_record_ids[0]) == DeathRecord.Status.ACTIVE, \
					"spawned candidate A marked ACTIVE (once only)")
				_check(_status_of(_record_ids[1]) == DeathRecord.Status.PENDING, \
					"unspawned candidate B stays PENDING")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.GHOST_DEATH)
		Phase.GHOST_DEATH:
			if _sub == 0:
				var records_before: int = _ledger.get_all_records().size()
				_check(records_before == 3, "ledger has 3 records before ghost death")
				_ghost.take_damage(99999)
				_wait_frames(3)
				_sub = 1
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_ledger.get_all_records().size() == 3, \
					"ghost death adds no new record (no recursion) (%d)" % _ledger.get_all_records().size())
				_check(_status_of(_record_ids[0]) == DeathRecord.Status.RESOLVED, \
					"original record A RESOLVED on ghost death")
				_check(_group_count("ghosts_3d") == 0, "dead ghost removed from world/group")
				_enter(Phase.FAILURE_RECOVERY)
		Phase.FAILURE_RECOVERY:
			# spawn failure recovery: scene을 무효화해 spawn 실패를 유도하고, candidate가
			# 유실되지 않고 PENDING으로 복원되는지 확인한다. 이후 유효 scene 복원 재시도.
			if _sub == 0:
				_mix.set("ghost_scene", "res://scenes/nonexistent_ghost.tscn")
				_wait_frames(2)
				_sub = 1
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				var spawned: int = _mix.spawn_ghost_mix(
					_world,
					_spawner.get_spawn_world_point("west", _world),
					_spawner.build_route_waypoints("west", _spawner.get_spawn_world_point("west", _world), _world),
					_spawner.get_village_core(_world), "west")
				_check(spawned == 0, "spawn failure yields 0 spawned (%d)" % spawned)
				_check(_status_of(_record_ids[1]) == DeathRecord.Status.PENDING, \
					"candidate B not lost (stays PENDING after failure)")
				# 유효 scene 복원: 이번 NIGHT 재호출 시 B가 성공적으로 spawn되는지 확인.
				_mix.set("ghost_scene", "res://scenes/ghost_3d.tscn")
				var spawned2: int = _mix.spawn_ghost_mix(
					_world,
					_spawner.get_spawn_world_point("west", _world),
					_spawner.build_route_waypoints("west", _spawner.get_spawn_world_point("west", _world), _world),
					_spawner.get_village_core(_world), "west")
				_check(spawned2 == 1, "recovered candidate B spawns on retry (%d)" % spawned2)
				_check(_group_count("ghosts_3d") == 1, "recovered ghost present")
				_check(_status_of(_record_ids[1]) == DeathRecord.Status.ACTIVE, \
					"candidate B ACTIVE after successful recovery retry")
				_enter(Phase.DAY_CLEANUP)
		Phase.DAY_CLEANUP:
			if _sub == 0:
				_force_phase(GameTime.Phase.DAY)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase is DAY")
				_check(_spawner.get_enemy_count() == 0, "regular enemies despawned on DAY")
				_check(_mix.get_alive_ghost_count() == 0, "ghosts despawned on DAY (no record change)")
				_check(_ledger.get_all_records().size() == 3, "DAY cleanup created no records")
				_enter(Phase.REPEAT_NIGHT)
		Phase.REPEAT_NIGHT:
			# 다음 NIGHT: 소비/해결된 A·B는 재등장하지 않고, 남은 PENDING candidate C가
			# 1회 spawn된다(same candidate once only).
			if _sub == 0:
				_force_phase(GameTime.Phase.NIGHT)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "repeat NIGHT arrived")
				_check(_mix.get_spawned_count() == 1, "1 ghost spawned next night (%d)" % _mix.get_spawned_count())
				_check(_spawner.get_enemy_count() == 2, "regular budget 2 on repeat night")
				_check(_group_count("ghosts_3d") == 1, "exactly 1 ghost on repeat night")
				var ids := _ghost_ids()
				_check(ids.size() == 1 and ids[0] == _record_ids[2], \
					"repeat-night ghost is C (A/B not re-spawned) ids=%s" % str(ids))
				_check(_status_of(_record_ids[2]) == DeathRecord.Status.ACTIVE, \
					"candidate C ACTIVE (once only)")
				_check(_status_of(_record_ids[0]) == DeathRecord.Status.RESOLVED, \
					"resolved A never re-inserted")
				_ghost = _find_ghost()
				_sub = 2
			elif _sub == 2:
				_enter(Phase.KILL_B)
		Phase.KILL_B:
			if _sub == 0:
				_check(_ghost != null and is_instance_valid(_ghost), "repeat-night ghost alive")
				if _ghost != null and is_instance_valid(_ghost):
					_ghost.take_damage(99999)
				_wait_frames(3)
				_sub = 1
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_status_of(_record_ids[2]) == DeathRecord.Status.RESOLVED, \
					"candidate C RESOLVED on ghost death")
				_check(_ledger.get_all_records().size() == 3, "no recursion (3 records)")
				_check(_group_count("ghosts_3d") == 0, "no ghosts remain")
				_enter(Phase.FINAL_CLEANUP)
		Phase.FINAL_CLEANUP:
			if _sub == 0:
				_force_phase(GameTime.Phase.DAY)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "final DAY restored")
				_check(_spawner.get_enemy_count() == 0 and _mix.get_alive_ghost_count() == 0, \
					"wave completes without deadlock (no leftover actors)")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(_ledger.get_all_records().size() == 3, "ledger stable (3 records)")
				_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")
				_check(_spawner._enemies.size() == 0, "spawner holds no stale enemy references")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0252_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	root.add_child(world_scene)
	_world = root.get_child(root.get_child_count() - 1)
	_nav_manager = load("res://scripts/navigation_manager_3d.gd").new()
	_world.add_child(_nav_manager)
	var cam_scene: Node = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	root.add_child(cam_scene)
	_spawner = load("res://scripts/first_encounter_spawner_3d.gd").new()
	_spawner.direction = "west"
	root.add_child(_spawner)
	_mix = load("res://scripts/ghost_spawn_mix.gd").new()
	root.add_child(_mix)

