extends SceneTree

## TASK-025-3 Ghost Identity Feedback 자동 검증.
##  - 최소한 이름/category/origin을 확인 가능(원본 identity feedback).
##  - 과도한 lore UI 없음: 원본 identity는 전투 중 Ghost nameplate(Label3D) 한 줄로만
##    표시하고, category/origin은 debug/inspection API(get_source_record/get_identity_info)
##    로만 노출한다(신규 lore UI 생성 없음).
##  - Death Ledger와의 연결을 debug/inspection 가능: get_source_record()가 원본
##    DeathRecord를 조회하고, ghost 사망 시 원본 record RESOLVED 후에도 조회 가능.
## 회귀: ghost spawn 흐름(task0252) 무영향, regular enemy spawn 무영향.
##
## 주의: -s 단독 기동에서 autoload 전역 식별자는 미등록이므로 GameTime/DeathLedger/
## FirstEncounterSpawner3D 등은 반드시 root.get_node로 접근한다.

enum Phase {
	SETUP, STRUCTURE, REGISTER_CANDIDATES, TO_NIGHT, IDENTITY_CHECK,
	LEDGER_LINK_CHECK, GHOST_DEATH, DAY_CLEANUP, REGRESSION, DONE,
}

var _frame := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _wait := 0
var _failed := false

var _world: Node = null
var _game_time: Node = null
var _ledger: Node = null
var _spawner: Node = null
var _mix: Node = null

var _record_id := ""
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
	print("TASK0253_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _group_count(group_name: String) -> int:
	return get_nodes_in_group(group_name).size()


func _force_phase(target_phase: int) -> void:
	for _i in 60:
		if _game_time.get_phase() == target_phase:
			return
		_game_time.advance(0.5)


func _register_enemy_death(uid: String, display: String, category: String, day: int) -> String:
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
	r.death_day = day
	r.death_phase = DeathRecord.DeathPhase.NIGHT
	var rec: DeathRecord = _ledger.record_death(r.to_snapshot())
	return rec.record_id if rec != null else ""


func _find_ghost() -> Node:
	for g in get_nodes_in_group("ghosts_3d"):
		if is_instance_valid(g):
			return g
	return null


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
				_check(FileAccess.file_exists("res://scenes/ghost_3d.tscn"), "ghost_3d.tscn exists")
				var ghost_scene: PackedScene = load("res://scenes/ghost_3d.tscn")
				_check(ghost_scene != null, "ghost_3d.tscn loads")
				if ghost_scene != null:
					var probe := ghost_scene.instantiate()
					var label := probe.get_node_or_null("Visual/IdentityLabel")
					_check(label != null and label is Label3D, \
						"ghost scene has IdentityLabel (Label3D) for combat identity feedback")
					probe.free()
				_check(_ghost_has_identity_api(), "GhostActor3D has identity feedback API")
				_check(_ledger.get_all_records().size() == 0, "ledger starts empty")
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase is DAY before spawn")
				_check(_spawner.get_count() == 3, "spawner count default 3")
				_enter(Phase.REGISTER_CANDIDATES)
		Phase.REGISTER_CANDIDATES:
			if _sub == 0:
				_record_id = _register_enemy_death(
					"fallen_wolf_1", "Fallen Wolf", "ENEMY", _game_time.get_day_number())
				_check(_record_id != "", "eligible ghost candidate registered")
				_check(_ledger.get_pending_records().size() == 1, "1 PENDING record in ledger")
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
				_check(_mix.get_spawned_count() == 1, "1 ghost mixed into wave")
				_check(_group_count("ghosts_3d") == 1, "ghost actor present in world")
				_ghost = _find_ghost()
				_check(_ghost != null, "ghost node found")
				_enter(Phase.IDENTITY_CHECK)
		Phase.IDENTITY_CHECK:
			if _sub == 0:
				if _ghost == null:
					_enter(Phase.DONE)
					return false
				_check(_ghost.get("source_record_id") == _record_id, \
					"ghost carries source record id")
				var info: Dictionary = _ghost.get_identity_info()
				_check(info.get("name", "") == "Fallen Wolf", \
					"identity name == original name (%s)" % str(info.get("name")))
				_check(info.get("category", "") == "ENEMY", \
					"identity category == ENEMY (%s)" % str(info.get("category")))
				_check(info.get("source_uid", "") == "fallen_wolf_1", \
					"identity source_uid == original uid (%s)" % str(info.get("source_uid")))
				_check(str(info.get("origin", "")).begins_with("Day "), \
					"identity origin carries death day (%s)" % str(info.get("origin")))
				_check(str(info.get("origin", "")).contains("fallen_wolf_1"), \
					"identity origin carries source uid")
				var label := _ghost.get_node_or_null("Visual/IdentityLabel") as Label3D
				_check(label != null, "ghost IdentityLabel node exists")
				if label != null:
					_check(label.visible, "IdentityLabel visible during combat")
					_check(label.text == "Fallen Wolf", \
						"IdentityLabel shows original name (%s)" % label.text)
				_sub = 1
			elif _sub == 1:
				_enter(Phase.LEDGER_LINK_CHECK)
		Phase.LEDGER_LINK_CHECK:
			if _sub == 0:
				if _ghost == null:
					_enter(Phase.DONE)
					return false
				var record: DeathRecord = _ghost.get_source_record()
				_check(record != null, "get_source_record resolves original record")
				if record != null:
					_check(record.record_id == _record_id, "resolved record id matches")
					_check(record.display_name == "Fallen Wolf", "resolved record name matches")
					_check(record.get_category() == "ENEMY", "resolved record category matches")
					_check(record.get_status() == DeathRecord.Status.ACTIVE, \
						"resolved record is ACTIVE while ghost alive")
				# 원본 record 삭제 없음 / ghost가 신규 record를 만들지 않음.
				_check(_ledger.get_all_records().size() == 1, "ledger has exactly 1 record (no dup)")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.GHOST_DEATH)
		Phase.GHOST_DEATH:
			if _sub == 0:
				var records_before: int = _ledger.get_all_records().size()
				_check(records_before == 1, "ledger count 1 before ghost death")
				_ghost.take_damage(99999)
				_wait_frames(3)
				_sub = 1
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_ledger.get_all_records().size() == 1, \
					"ghost death adds no new record (no recursion)")
				_check(_status_of(_record_id) == DeathRecord.Status.RESOLVED, \
					"original record RESOLVED on ghost death")
				_check(_group_count("ghosts_3d") == 0, "dead ghost removed from world/group")
				# debug/inspection: ghost death로 원본 record가 RESOLVED되어도 record 자체는
				# 유지되므로 Death Ledger 연결 조회가 계속 가능하다.
				_check(_ledger.get_record(_record_id) != null, \
					"ledger record inspectable after ghost death (RESOLVED kept)")
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
				_check(_mix.get_alive_ghost_count() == 0, "ghosts despawned on DAY")
				_check(_ledger.get_all_records().size() == 1, "DAY cleanup created no records")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")
				_check(_spawner._enemies.size() == 0, "spawner holds no stale enemy references")
				_check(_ledger.get_record(_record_id).get_status() == DeathRecord.Status.RESOLVED, \
					"ledger stable after full loop")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0253_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _ghost_has_identity_api() -> bool:
	var script_text := FileAccess.get_file_as_string("res://scripts/ghost_actor_3d.gd")
	if script_text == "":
		return false
	return script_text.contains("func get_identity_info") \
		and script_text.contains("func get_source_record")


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	root.add_child(world_scene)
	_world = root.get_child(root.get_child_count() - 1)
	var nav_manager: Node = load("res://scripts/navigation_manager_3d.gd").new()
	_world.add_child(nav_manager)
	var cam_scene: Node = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	root.add_child(cam_scene)
	_spawner = load("res://scripts/first_encounter_spawner_3d.gd").new()
	_spawner.direction = "west"
	root.add_child(_spawner)
	_mix = load("res://scripts/ghost_spawn_mix.gd").new()
	root.add_child(_mix)
