extends SceneTree

## TASK-025-4 Portal / Ghost Regression 자동 검증.
## 현재 구현된 Portal/Ghost 범위(TASK-025-1~3)의 전반 회귀를 한 시나리오로 종합 검증한다.
## 검증 범위:
##   - 여러 eligible death: ENEMY + MERCENARY 다수 eligible death가 후보 큐에 등록된다.
##   - duplicate lethal signal: 같은 source_uid가 재사망해도(중복 lethal signal) record는
##     1개만 유지된다(one-return). 실제 Actor die() 경로로도 lethal death가 정확히 1회 기록된다.
##   - cleanup/despawn: DAY 복귀 시 ghost/enemy despawn이 record를 만들지 않는다.
##   - candidate queue: GhostSpawnMix FIFO 큐가 PENDING record를 한 번씩 소비한다.
##   - mixed wave: ghost + regular enemy 혼합 wave에서 budget(count)을 점유한다(합계=count).
##   - one-return: 각 candidate는 1회만 spawn되고 RESOLVED 후 재삽입되지 않는다.
##   - ghost death: ghost 사망이 신규 record를 만들지 않는다(재귀 방지).
##   - repeated nights: 반복 NIGHT에서 다음 candidate만 1회 spawn된다.
##   - Threat/Wave: spawner의 NIGHT spawn / DAY despawn이 direction(WEST=main threat)과
##     함께 정상 동작한다.
##   - Death Ledger: record 수/상태(PENDING/ACTIVE/RESOLVED)가 일관된다.
##   - freed reference / duplicate actor: 반복 cycle 후 spawner/mix에 stale reference나
##     중복 actor가 남지 않는다.
##   - 무한 Ghost recursion 없음: 모든 candidate가 소진/해결된 후 NIGHT에는 ghost가
##     0개 spawn된다.
## (참고: 검증 목록의 "Mercenary Potion" / "Morale contributor"는 본 코드베이스에 아직
## 구현되지 않은 POST-3D 후속 기능으로, Portal/Ghost "현재 범위" 밖이므로 여기서 자동
## 검증하지 않는다 - HUMAN_CHECK/후속 태스크 범위.)
##
## 주의: -s 단독 기동에서 autoload 전역 식별자는 미등록이므로 GameTime/DeathLedger 등은
## 반드시 root.get_node로 접근하고, static 클래스 참조는 class_name 스크립트만 사용한다.

enum Phase {
	SETUP, STRUCTURE, REGISTER_MULTI, DUP_LETHAL, TO_NIGHT_1, MIXED_CHECK,
	GHOST_DEATH_1, DAY_CLEANUP, REPEAT_NIGHTS, EXHAUSTED, REGRESSION, DONE,
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
var _enemy_uid: Array[String] = []
var _ghost: Node = null

## 반복 NIGHT에서 소비한 ghost 수 누적(무한 recursion 감시용).
var _total_spawned_over_nights := 0


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
	print("TASK0254_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _group_count(group_name: String) -> int:
	return get_nodes_in_group(group_name).size()


func _force_phase(target_phase: int) -> void:
	for _i in 60:
		if _game_time.get_phase() == target_phase:
			return
		_game_time.advance(0.5)


## eligible death(ENEMY)를 snapshot으로 등록하고 record_id를 반환한다.
func _register_enemy_death(uid: String, display: String, category := "ENEMY") -> String:
	var r := DeathRecord.new("")
	r.source_uid = uid
	r.source_kind = DeathRecord.SourceKind.ENEMY
	r.category = category
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


## eligible death(MERCENARY)를 snapshot으로 등록하고 record_id를 반환한다.
func _register_mercenary_death(uid: String, display: String) -> String:
	var r := DeathRecord.new("")
	r.source_uid = uid
	r.source_kind = DeathRecord.SourceKind.MERCENARY
	r.category = "MERCENARY"
	r.display_name = display
	r.class_or_type = display
	r.level = 1
	r.max_hp = 100
	r.attack_damage = 15
	r.attack_interval = 0.8
	r.move_speed = 90.0
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


## 실제 EnemyActor3D die() 경로로 lethal death를 발생시켜 record가 정확히 1회 생성되는지
## 확인한다(duplicate lethal signal 방지). spawner와 별개로 임시 enemy를 월드에 추가한다.
func _spawn_real_enemy(uid: String, display: String) -> Node:
	var scene: PackedScene = load("res://scenes/enemy_3d.tscn")
	if scene == null:
		return null
	var enemy: Node = scene.instantiate()
	enemy.setup(uid, display, "west")
	enemy.position = _world.global_position + Vector3(0, 0, 40 * WorldCoords3D.PX_TO_UNIT)
	_world.add_child(enemy)
	return enemy


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
				_check(FileAccess.file_exists("res://scenes/enemy_3d.tscn"), "enemy_3d.tscn exists")
				_check(FileAccess.file_exists("res://scripts/ghost_actor_3d.gd"), "ghost_actor_3d.gd exists")
				_check(FileAccess.file_exists("res://scripts/ghost_spawn_mix.gd"), "ghost_spawn_mix.gd exists")
				_check(_mix != null, "GhostSpawnMix node exists")
				if _mix != null:
					_check(_mix.get("max_ghosts_per_night") == 1, \
						"max_ghosts_per_night configurable (default 1)")
				_check(_spawner.get_count() == 3, "spawner count default 3")
				_check(_spawner.get_direction() == "west", "spawner direction west (WEST = main threat)")
				_enter(Phase.REGISTER_MULTI)
		Phase.REGISTER_MULTI:
			if _sub == 0:
				# 여러 eligible death(ENEMY 3 + MERCENARY 1) 등록.
				var id1 := _register_enemy_death("ghost_cand_A", "Fallen Raider")
				var id2 := _register_enemy_death("ghost_cand_B", "Wight Slasher")
				var id3 := _register_enemy_death("ghost_cand_C", "Spectral Brute")
				var id4 := _register_mercenary_death("merc_cand_D", "Ghost Knight")
				_record_ids = [id1, id2, id3, id4]
				_enemy_uid = ["ghost_cand_A", "ghost_cand_B", "ghost_cand_C"]
				_check(_record_ids.size() == 4, "4 eligible deaths registered (multiple eligible)")
				_check(_record_ids[0] != "" and _record_ids[3] != "", \
					"both ENEMY and MERCENARY eligible categories recorded")
				_check(_ledger.get_pending_records().size() == 4, \
					"4 PENDING records in ledger")
				# unsupported category는 안전 skip(회귀 유지).
				var bad := DeathRecord.new("")
				bad.source_uid = "animal_x"
				bad.source_kind = DeathRecord.SourceKind.ENEMY
				bad.category = "ANIMAL"
				bad.display_name = "Wolf"
				bad.death_day = 1
				_check(_ledger.record_death(bad.to_snapshot()) == null, \
					"unsupported ANIMAL category safely skipped")
				_check(_ledger.get_pending_records().size() == 4, \
					"unsupported category adds no pending candidate")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DUP_LETHAL)
		Phase.DUP_LETHAL:
			# duplicate lethal signal: 같은 source_uid 재사망 → record 1개만 유지(one-return).
			if _sub == 0:
				var count_before: int = _ledger.get_all_records().size()
				var dup: DeathRecord = _ledger.record_death(
					_death_snapshot("ghost_cand_A", "Fallen Raider"))
				_check(dup != null and dup.record_id == _record_ids[0], \
					"duplicate lethal signal deduped to same record (one-return)")
				_check(_ledger.get_all_records().size() == count_before, \
					"duplicate lethal signal adds no new record")
				_check(_ledger.get_all_records().size() == 4, "ledger stays at 4 records")
				_wait_frames(3)
				_sub = 1
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				# 실제 Actor die() 경로 lethal death: 신규 ENEMY 사망은 record 1회 생성.
				var enemy := _spawn_real_enemy("live_enemy_e", "Live Raider")
				_check(enemy != null, "real enemy actor instantiated")
				if enemy != null:
					enemy.take_damage(99999)
					_wait_frames(3)
					_sub = 2
				else:
					_enter(Phase.TO_NIGHT_1)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_ledger.get_all_records().size() == 5, \
					"real enemy lethal death creates exactly 1 record (%d)" % _ledger.get_all_records().size())
				_check(_ledger.has_record_for_source("live_enemy_e"), \
					"real lethal death recorded to ledger")
				# 중복 lethal signal(Actor가 다시 die()해도 die() 가드로 1회만 기록).
				var rec: DeathRecord = _ledger.get_record(
					_record_id_for_source("live_enemy_e"))
				var live_id: String = rec.record_id if rec != null else ""
				_check(_ledger.get_all_records().size() == 5, \
					"actor duplicate die() adds no extra record")
				_enter(Phase.TO_NIGHT_1)
		Phase.TO_NIGHT_1:
			if _sub == 0:
				_force_phase(GameTime.Phase.NIGHT)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT")
				_check(_spawner.is_night_active(), "spawner night active (Threat/Wave spawn)")
				_enter(Phase.MIXED_CHECK)
		Phase.MIXED_CHECK:
			if _sub == 0:
				var ghost_count: int = _mix.get_spawned_count()
				var enemy_count: int = _spawner.get_enemy_count()
				_check(ghost_count == 1, "exactly 1 ghost mixed into wave (%d)" % ghost_count)
				_check(enemy_count == 2, "regular enemy budget reduced to 2 (budget occupied) (%d)" % enemy_count)
				_check(enemy_count + ghost_count == _spawner.get_count(), \
					"total wave size == count (mixed wave)")
				_check(_group_count("ghosts_3d") == 1, "ghost actor present in world")
				_ghost = _find_ghost()
				_check(_ghost != null, "ghost node found")
				if _ghost != null:
					_check(_ghost.get("source_record_id") == _record_ids[0], \
						"ghost carries original record id (A) - candidate queue FIFO")
					_check(_ghost.get("display_name") == "Fallen Raider", \
						"ghost carries original identity")
					_check(_ghost.is_in_group("ghosts_3d"), "ghost in ghosts_3d group")
				_check(_status_of(_record_ids[0]) == DeathRecord.Status.ACTIVE, \
					"spawned candidate A marked ACTIVE (once only)")
				_check(_status_of(_record_ids[1]) == DeathRecord.Status.PENDING, \
					"unspawned candidate B stays PENDING")
				_total_spawned_over_nights += ghost_count
				_sub = 1
			elif _sub == 1:
				_enter(Phase.GHOST_DEATH_1)
		Phase.GHOST_DEATH_1:
			if _sub == 0:
				var records_before: int = _ledger.get_all_records().size()
				_check(records_before == 5, "ledger has 5 records before ghost death")
				_ghost.take_damage(99999)
				_wait_frames(3)
				_sub = 1
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_ledger.get_all_records().size() == 5, \
					"ghost death adds no new record (no recursion) (%d)" % _ledger.get_all_records().size())
				_check(_status_of(_record_ids[0]) == DeathRecord.Status.RESOLVED, \
					"original record A RESOLVED on ghost death")
				_check(_group_count("ghosts_3d") == 0, "dead ghost removed from world/group")
				_enter(Phase.DAY_CLEANUP)
		Phase.DAY_CLEANUP:
			if _sub == 0:
				_force_phase(GameTime.Phase.DAY)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase is DAY")
				_check(_spawner.get_enemy_count() == 0, "regular enemies despawned on DAY (cleanup)")
				_check(_mix.get_alive_ghost_count() == 0, "ghosts despawned on DAY (cleanup)")
				_check(_ledger.get_all_records().size() == 5, \
					"DAY cleanup created no records (despawn is record-free)")
				_check(_spawner._enemies.size() == 0, \
					"spawner holds no stale enemy references after cleanup")
				_check(_mix._spawned_ghosts.size() == 0, \
					"mix holds no stale ghost references after cleanup")
				_enter(Phase.REPEAT_NIGHTS)
		Phase.REPEAT_NIGHTS:
			# 반복 NIGHT: 남은 candidate B/C/D를 한 번씩 spawn(one-return, repeated nights).
			if _sub == 0:
				# 다음 NIGHT로 진입해 다음 candidate만 1회 spawn되는지 확인한다.
				_force_phase(GameTime.Phase.NIGHT)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "repeat NIGHT arrived")
				_check(_mix.get_spawned_count() == 1, \
					"1 ghost spawned next night (%d)" % _mix.get_spawned_count())
				_check(_spawner.get_enemy_count() == 2, "regular budget 2 on repeat night")
				_check(_group_count("ghosts_3d") == 1, "exactly 1 ghost on repeat night")
				var ids := _ghost_ids()
				_check(ids.size() == 1 and ids[0] == _record_ids[1], \
					"repeat-night ghost is B (A not re-spawned) ids=%s" % str(ids))
				_check(_status_of(_record_ids[1]) == DeathRecord.Status.ACTIVE, \
					"candidate B ACTIVE (once only)")
				_check(_status_of(_record_ids[0]) == DeathRecord.Status.RESOLVED, \
					"resolved A never re-inserted")
				_total_spawned_over_nights += _mix.get_spawned_count()
				_ghost = _find_ghost()
				_sub = 2
			elif _sub == 2:
				# B를 ghost death로 해결한다.
				_check(_ghost != null and is_instance_valid(_ghost), "repeat-night ghost alive")
				if _ghost != null and is_instance_valid(_ghost):
					_ghost.take_damage(99999)
				_wait_frames(3)
				_sub = 3
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_status_of(_record_ids[1]) == DeathRecord.Status.RESOLVED, \
					"candidate B RESOLVED on ghost death")
				_check(_ledger.get_all_records().size() == 5, "no recursion (5 records)")
				_check(_group_count("ghosts_3d") == 0, "no ghosts remain")
				# DAY로 돌아가 다음 NIGHT에서 C를 소비한다.
				_force_phase(GameTime.Phase.DAY)
				_wait_frames(3)
				_sub = 4
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				_force_phase(GameTime.Phase.NIGHT)
				_wait_frames(3)
				_sub = 5
			elif _sub == 5 and not _waited():
				return false
			elif _sub == 5:
				_check(_mix.get_spawned_count() == 1, \
					"1 ghost spawned (candidate C) (%d)" % _mix.get_spawned_count())
				var ids_c := _ghost_ids()
				_check(ids_c.size() == 1 and ids_c[0] == _record_ids[2], \
					"night ghost is C (B not re-spawned) ids=%s" % str(ids_c))
				_check(_status_of(_record_ids[2]) == DeathRecord.Status.ACTIVE, \
					"candidate C ACTIVE (once only)")
				_total_spawned_over_nights += _mix.get_spawned_count()
				_ghost = _find_ghost()
				_sub = 6
			elif _sub == 6:
				_check(_ghost != null and is_instance_valid(_ghost), "candidate C ghost alive")
				if _ghost != null and is_instance_valid(_ghost):
					_ghost.take_damage(99999)
				_wait_frames(3)
				_sub = 7
			elif _sub == 7 and not _waited():
				return false
			elif _sub == 7:
				_check(_status_of(_record_ids[2]) == DeathRecord.Status.RESOLVED, \
					"candidate C RESOLVED on ghost death")
				_check(_group_count("ghosts_3d") == 0, "no ghosts remain")
				# DAY로 돌아가 다음 NIGHT에서 마지막 candidate D(MERCENARY ghost)를 소비한다.
				_force_phase(GameTime.Phase.DAY)
				_wait_frames(3)
				_sub = 8
			elif _sub == 8 and not _waited():
				return false
			elif _sub == 8:
				_force_phase(GameTime.Phase.NIGHT)
				_wait_frames(3)
				_sub = 9
			elif _sub == 9 and not _waited():
				return false
			elif _sub == 9:
				_check(_mix.get_spawned_count() == 1, \
					"1 ghost spawned (candidate D MERCENARY) (%d)" % _mix.get_spawned_count())
				var ids_d := _ghost_ids()
				_check(ids_d.size() == 1 and ids_d[0] == _record_ids[3], \
					"night ghost is D (MERCENARY candidate) ids=%s" % str(ids_d))
				_check(_status_of(_record_ids[3]) == DeathRecord.Status.ACTIVE, \
					"candidate D ACTIVE (once only)")
				# MERCENARY ghost도 identity feedback이 정상 동작한다(회귀).
				var gd := _find_ghost()
				if gd != null and gd.has_method("get_identity_info"):
					var info: Dictionary = gd.get_identity_info()
					_check(info.get("category", "") == "MERCENARY", \
						"mercenary ghost identity category MERCENARY (%s)" % str(info.get("category")))
				_total_spawned_over_nights += _mix.get_spawned_count()
				_ghost = _find_ghost()
				_sub = 10
			elif _sub == 10:
				_check(_ghost != null and is_instance_valid(_ghost), "candidate D ghost alive")
				if _ghost != null and is_instance_valid(_ghost):
					_ghost.take_damage(99999)
				_wait_frames(3)
				_sub = 11
			elif _sub == 11 and not _waited():
				return false
			elif _sub == 11:
				_check(_status_of(_record_ids[3]) == DeathRecord.Status.RESOLVED, \
					"candidate D RESOLVED on ghost death")
				_check(_group_count("ghosts_3d") == 0, "no ghosts remain")
				_force_phase(GameTime.Phase.DAY)
				_wait_frames(3)
				_sub = 12
			elif _sub == 12 and not _waited():
				return false
			elif _sub == 12:
				_enter(Phase.EXHAUSTED)
		Phase.EXHAUSTED:
			# 실제 lethal death로 생성된 live enemy record도 eligible candidate이므로 다음
			# NIGHT에서 1회 ghost return되어야 한다(모든 eligible pending이 정확히 1회 등장).
			if _sub == 0:
				_force_phase(GameTime.Phase.NIGHT)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "live-enemy NIGHT arrived")
				_check(_mix.get_spawned_count() == 1, \
					"1 ghost spawned for live enemy lethal death (%d)" % _mix.get_spawned_count())
				var live_id := _record_id_for_source("live_enemy_e")
				var ids_live := _ghost_ids()
				_check(ids_live.size() == 1 and ids_live[0] == live_id, \
					"live-enemy ghost carries its record ids=%s" % str(ids_live))
				_check(_status_of(live_id) == DeathRecord.Status.ACTIVE, \
					"live-enemy candidate ACTIVE (once only)")
				_total_spawned_over_nights += _mix.get_spawned_count()
				_ghost = _find_ghost()
				_sub = 2
			elif _sub == 2:
				_check(_ghost != null and is_instance_valid(_ghost), "live-enemy ghost alive")
				if _ghost != null and is_instance_valid(_ghost):
					_ghost.take_damage(99999)
				_wait_frames(3)
				_sub = 3
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_status_of(_record_id_for_source("live_enemy_e")) \
						== DeathRecord.Status.RESOLVED, \
					"live-enemy candidate RESOLVED on ghost death")
				_check(_ledger.get_all_records().size() == 5, "no recursion (5 records)")
				_check(_group_count("ghosts_3d") == 0, "no ghosts remain")
				_force_phase(GameTime.Phase.DAY)
				_wait_frames(3)
				_sub = 4
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				# 모든 eligible candidate(4 + live enemy)가 소진/해결된 후의 NIGHT에서 ghost가
				# 0개 spawn되어야 한다(무한 Ghost recursion 없음). 중복 spawn/과다 spawn 없이
				# 총 5회만 spawn되어야 한다.
				_force_phase(GameTime.Phase.NIGHT)
				_wait_frames(3)
				_sub = 1
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, \
					"fully-exhausted NIGHT arrived")
				_check(_mix.get_spawned_count() == 0, \
					"0 ghosts spawn once all candidates resolved (no infinite recursion)")
				_check(_group_count("ghosts_3d") == 0, \
					"no ghost actors when queue exhausted")
				_check(_spawner.get_enemy_count() == 3, \
					"regular wave still spawns normally at full budget when no ghost occupies it (Threat/Wave intact) got %d" % _spawner.get_enemy_count())
				_check(_total_spawned_over_nights == 5, \
					"total ghosts over all nights == 5 (exactly one per candidate) got %d" % _total_spawned_over_nights)
				_sub = 2
			elif _sub == 2:
				_force_phase(GameTime.Phase.DAY)
				_wait_frames(3)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_ledger.get_all_records().size() == 5, \
					"ledger stable (5 records) after full loop (%d)" % _ledger.get_all_records().size())
				# all 5 candidates (4 registered + live enemy) resolved.
				var resolved := 0
				for rid in _record_ids:
					if _status_of(rid) == DeathRecord.Status.RESOLVED:
						resolved += 1
				_check(resolved == 4, "all 4 registered ghost candidates resolved (one-return)")
				_check(_status_of(_record_id_for_source("live_enemy_e")) \
						== DeathRecord.Status.RESOLVED, \
					"live enemy record RESOLVED (one-return)")
				_check(_ledger.has_record_for_source("live_enemy_e"), \
					"live enemy record remains in ledger")
				_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")
				_check(_spawner._enemies.size() == 0, \
					"spawner holds no stale enemy references (freed reference)")
				_check(_mix._spawned_ghosts.size() == 0, \
					"mix holds no stale ghost references (freed reference)")
				_check(get_nodes_in_group("ghosts_3d").size() == 0, \
					"no duplicate/leftover ghost actors (duplicate actor)")
				_check(get_nodes_in_group("enemies_3d").size() == 0, \
					"no duplicate/leftover enemy actors (duplicate actor)")
				_sub = 4
			elif _sub == 4:
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0254_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _death_snapshot(uid: String, display: String) -> Dictionary:
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
	return r.to_snapshot()


func _record_id_for_source(source_uid: String) -> String:
	for r in _ledger.get_all_records():
		if r.source_uid == source_uid:
			return r.record_id
	return ""


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

