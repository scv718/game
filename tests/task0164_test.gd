extends SceneTree

## TASK-016-4 Duplicate / Recursive Death Guard ?먮룞 寃利?
##  - DeathLedger ?덈꺼 duplicate guard: 媛숈? source_uid??record媛 ?대? 議댁옱?섎㈃
##    record_death()媛 ?좉퇋 record瑜?留뚮뱾吏 ?딄퀬 湲곗〈 record 蹂듭궗蹂몄쓣 諛섑솚?쒕떎.
##    ?숈씪 ?ㅼ젣 二쎌쓬 = ?뺥솗??1 record. record_added??理쒖큹 1?뚮쭔 諛쒗뻾.
##  - display_name???꾨땲??source_uid 湲곗? dedupe(?대쫫??媛숈? ?ㅻⅨ 媛쒖껜??媛곴컖 湲곕줉).
##  - Ghost(?ш?) guard: is_ghost=true???щ쭩 snapshot? ?좉퇋 record瑜??덈? 留뚮뱾吏
##    ?딅뒗?? 湲곗〈 record媛 ?덉쑝硫?蹂듭궗蹂몄쓣, ?놁쑝硫?null??諛섑솚.
##  - RESOLVED ?댄썑?먮룄 媛숈? source_uid ?ш린濡????좉퇋 record ?놁쓬(record???곴뎄 1媛?.
##  - ?ㅼ젣 Actor lethal death ?댄썑?먮룄 ?숈씪 source_uid ?ы샇異???record 1媛??좎?.
##  - is_ghost ?꾨뱶 snapshot round-trip 蹂댁〈.
##  - ?뚭?: main scene / 湲곗〈 autoload / Player 鍮꾩쟾??/ Ghost 誘멸뎄??ghosts 洹몃９ ?놁쓬).

enum TestPhase {
	SETUP,
	DUPLICATE_GUARD,
	SAME_NAME_DIFFERENT,
	GHOST_BLOCK_NEW,
	GHOST_BLOCK_EXISTING,
	RESOLVED_DUP,
	ACTOR_DOUBLE_DEATH,
	IS_GHOST_ROUNDTRIP,
	REGRESSION,
	DONE,
}

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _sub := 0
var _wait := 0
var _failed := false

var _ledger: Node = null
var _game_time: Node = null
var _world: Node = null

var _added_count := 0

var _dup_record_id := ""
var _enemy_seq := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: TestPhase) -> void:
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


func _on_record_added(_record_id: String) -> void:
	_added_count += 1


func _make_enemy_snapshot(source_uid: String, display_name := "Raider", hp := 60) -> Dictionary:
	var e := DeathRecord.new("")
	e.source_uid = source_uid
	e.source_kind = DeathRecord.SourceKind.ENEMY
	e.display_name = display_name
	e.class_or_type = "RAIDER"
	e.level = 1
	e.max_hp = hp
	e.attack_damage = 8
	e.attack_interval = 1.0
	e.move_speed = 90.0
	e.death_day = 3
	e.death_phase = DeathRecord.DeathPhase.NIGHT
	e.death_position = Vector2(0, -448)
	return e.to_snapshot()


func _make_ghost_snapshot(source_uid: String, display_name := "Raider Ghost") -> Dictionary:
	var snap := _make_enemy_snapshot(source_uid, display_name)
	snap["is_ghost"] = true
	return snap


func _spawn_enemy(pos: Vector2, hp := 60) -> Node:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate()
	if enemy == null:
		return null
	enemy.max_hp = hp
	enemy.setup("enemy_integration_%d" % _enemy_seq, "Raider", "north")
	enemy.position = pos
	_world.add_child(enemy)
	_enemy_seq += 1
	return enemy


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		TestPhase.SETUP:
			if _frame < 8:
				return false
			_ledger = root.get_node("DeathLedger")
			_game_time = root.get_node("GameTime")
			_world = root.get_node("Main").get_node("World")
			if _game_time != null and _game_time.has_method("set_auto_advance"):
				_game_time.set_auto_advance(false)
			if _game_time != null and _game_time.has_method("set_durations"):
				_game_time.set_durations(2.0, 1.0)
			_check(_ledger != null and _game_time != null and _world != null, \
				"DeathLedger + GameTime + World present")
			_ledger.record_added.connect(_on_record_added)
			_check(_ledger.get_all_records().size() == 0, "ledger starts empty")
			_check(_added_count == 0, "no record_added at start")
			_enter(TestPhase.DUPLICATE_GUARD)
		TestPhase.DUPLICATE_GUARD:
			if _sub == 0:
				var snap := _make_enemy_snapshot("enemy_dup_0")
				var rec1: DeathRecord = _ledger.record_death(snap)
				_check(rec1 != null, "first record_death creates record")
				_check(_added_count == 1, "record_added emitted once for first record")
				var rec2: DeathRecord = _ledger.record_death(snap)
				_check(rec2 != null, "duplicate record_death returns a record (no crash)")
				if rec1 != null and rec2 != null:
					_check(rec1.record_id == rec2.record_id, \
						"duplicate call returns same record (record_id preserved)")
				_check(_ledger.get_all_records().size() == 1, \
					"duplicate source_uid creates no new record (still 1)")
				_check(_added_count == 1, "record_added NOT emitted again for duplicate")
				_check(_ledger.has_record_for_source("enemy_dup_0"), \
					"has_record_for_source(enemy_dup_0) true")
				_dup_record_id = rec1.record_id if rec1 != null else ""
				# ?쒕줈 ?ㅻⅨ stat snapshot?대씪??媛숈? source_uid硫?泥?record ?좎?.
				var snap2 := _make_enemy_snapshot("enemy_dup_0", "Raider", 999)
				var rec3: DeathRecord = _ledger.record_death(snap2)
				_check(rec3 != null and rec3.record_id == _dup_record_id, \
					"same source_uid with different stats still deduped to first record")
				_check(_ledger.get_record(_dup_record_id).max_hp == 60, \
					"first record stats retained on duplicate")
				_check(_ledger.get_all_records().size() == 1, "still exactly 1 record")
				_enter(TestPhase.SAME_NAME_DIFFERENT)
		TestPhase.SAME_NAME_DIFFERENT:
			# 媛숈? display_name?댁?留?source_uid媛 ?ㅻⅤ硫?媛곴컖 record ?앹꽦.
			var ra1: DeathRecord = _ledger.record_death(_make_enemy_snapshot("enemy_a_0"))
			var ra2: DeathRecord = _ledger.record_death(_make_enemy_snapshot("enemy_a_1"))
			_check(ra1 != null and ra2 != null, "same-name different-source enemies both recorded")
			if ra1 != null and ra2 != null:
				_check(ra1.display_name == ra2.display_name, "same display_name 'Raider'")
				_check(ra1.source_uid != ra2.source_uid, "distinct source_uid")
				_check(ra1.record_id != ra2.record_id, "distinct record_id")
			_check(_ledger.get_all_records().size() == 3, \
				"3 records after same-name different enemies (%d)" % _ledger.get_all_records().size())
			_check(_added_count == 3, "record_added emitted for each distinct source")
			_enter(TestPhase.GHOST_BLOCK_NEW)
		TestPhase.GHOST_BLOCK_NEW:
			# Ghost source(湲곗〈 record ?녿뒗 ??source_uid) ?щ쭩 ???좉퇋 record 誘몄깮??
			var count_before: int = _ledger.get_all_records().size()
			var added_before := _added_count
			var ghost: DeathRecord = _ledger.record_death(_make_ghost_snapshot("ghost_new_0"))
			_check(ghost == null, "ghost death with no existing record returns null")
			_check(_ledger.get_all_records().size() == count_before, \
				"ghost death creates no new record (count unchanged)")
			_check(_ledger.has_record_for_source("ghost_new_0") == false, \
				"ghost_new_0 not recorded")
			_check(_added_count == added_before, "no record_added for ghost death")
			_enter(TestPhase.GHOST_BLOCK_EXISTING)
		TestPhase.GHOST_BLOCK_EXISTING:
			# Ghost source媛 湲곗〈 record??source_uid? 媛숈븘???좉퇋 record 誘몄깮??
			var count_before: int = _ledger.get_all_records().size()
			var added_before := _added_count
			var ghost: DeathRecord = _ledger.record_death(_make_ghost_snapshot("enemy_dup_0"))
			_check(ghost != null and ghost.record_id == _dup_record_id, \
				"ghost death for existing source returns existing record copy")
			_check(_ledger.get_all_records().size() == count_before, \
				"ghost death does not add a record (count unchanged)")
			_check(_added_count == added_before, "no record_added for ghost-over-existing death")
			var dup: DeathRecord = _ledger.get_record(_dup_record_id)
			_check(dup != null and dup.source_uid == "enemy_dup_0", \
				"existing record intact after ghost death attempt")
			_enter(TestPhase.RESOLVED_DUP)
		TestPhase.RESOLVED_DUP:
			# RESOLVED ?댄썑?먮룄 媛숈? source_uid ?ш린濡????좉퇋 record ?놁쓬(?곴뎄 1媛?.
			_check(_ledger.resolve(_dup_record_id, 4), "resolve enemy_dup_0 record")
			_check(_ledger.get_record(_dup_record_id).get_status() == DeathRecord.Status.RESOLVED, \
				"enemy_dup_0 record RESOLVED")
			var count_before: int = _ledger.get_all_records().size()
			var added_before := _added_count
			var retry: DeathRecord = _ledger.record_death(_make_enemy_snapshot("enemy_dup_0"))
			_check(retry != null and retry.record_id == _dup_record_id, \
				"re-record after RESOLVED returns existing RESOLVED record")
			_check(_ledger.get_all_records().size() == count_before, \
				"re-record after RESOLVED adds nothing (still %d)" % count_before)
			_check(_added_count == added_before, "no record_added after RESOLVED re-record")
			_check(_ledger.get_record(_dup_record_id).get_status() == DeathRecord.Status.RESOLVED, \
				"one record per source forever (RESOLVED preserved)")
			_enter(TestPhase.ACTOR_DOUBLE_DEATH)
		TestPhase.ACTOR_DOUBLE_DEATH:
			if _sub == 0:
				var e := _spawn_enemy(Vector2(0, -360), 60)
				_check(e != null, "test enemy spawned for double-death scenario")
				if e != null:
					e.take_damage(99999)
					_check(e.alive == false, "enemy died on lethal damage")
				_wait_frames(4)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				# ?ㅼ젣 lethal death濡??뺥솗??1 record ?앹꽦.
				var sid := "enemy_integration_0"
				_check(_ledger.has_record_for_source(sid), "actor lethal death recorded")
				var recs := _records_for_source(sid)
				_check(recs.size() == 1, "actor death creates exactly 1 record (%d)" % recs.size())
				# died signal 以묐났 ?꾨떖??媛?뺥븳 ?숈씪 source_uid ?ы샇異????좉퇋 record ?놁쓬.
				var count_before: int = _ledger.get_all_records().size()
				var added_before := _added_count
				var retry: DeathRecord = _ledger.record_death(_make_enemy_snapshot(sid))
				_check(retry != null and retry.record_id == recs[0].record_id, \
					"double delivery deduped to same record_id")
				_check(_ledger.get_all_records().size() == count_before, \
					"double delivery adds no record")
				_check(_added_count == added_before, "no record_added for double delivery")
				_check(_records_for_source(sid).size() == 1, \
					"still exactly 1 record for actor source after double delivery")
				_enter(TestPhase.IS_GHOST_ROUNDTRIP)
		TestPhase.IS_GHOST_ROUNDTRIP:
			var m := DeathRecord.new("rec_ghost_rt")
			_check(m.is_ghost == false, "DeathRecord.is_ghost defaults false (NORMAL)")
			m.is_ghost = true
			var snap := m.to_snapshot()
			_check(typeof(snap.get("is_ghost", null)) == TYPE_BOOL, \
				"is_ghost serialized as pure bool in snapshot")
			var restored := DeathRecord.from_snapshot(snap)
			_check(restored.is_ghost == true, "is_ghost preserved through snapshot round-trip")
			# snapshot??is_ghost媛 ?ы븿?섎㈃?쒕룄 ?좉퇋 ?꾨뱶???쒖닔 ????좎?.
			var valid_types := [
				TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
				TYPE_VECTOR2, TYPE_DICTIONARY, TYPE_ARRAY,
			]
			var pure := true
			for key in snap.keys():
				if typeof(snap[key]) not in valid_types:
					pure = false
					break
			_check(pure, "snapshot with is_ghost still pure data")
			_enter(TestPhase.REGRESSION)
		TestPhase.REGRESSION:
			if _sub == 0:
				var main: Node = root.get_node("Main")
				_check(main != null and main.get_node("Player") != null and main.get_node("HUD") != null, \
					"main scene intact")
				_check(root.get_node("MercenaryRoster") != null \
					and root.get_node("FirstEncounterSpawner") != null, \
					"combat autoloads intact")
				var player: Node = main.get_node("Player")
				_check(not player.has_method("attack") and not player.has_method("_attack"), \
					"player has no attack method (no direct combat)")
				_check(not player.is_in_group("enemies") and not player.is_in_group("mercenaries"), \
					"player excluded from combat groups")
				_check(get_nodes_in_group("ghosts").size() == 0, \
					"no ghost actor spawned (Ghost actual feature not implemented)")
				_check(get_nodes_in_group("enemies").size() == 0, \
					"no leftover enemies in world")
				_check(_ledger.get_all_records().size() >= 4, \
					"ledger retains records after scenario (%d)" % _ledger.get_all_records().size())
				_check(_ledger.get_pending_records().size() >= 3, \
					"pending records retained after scenario")
				_check(_ledger.get_resolved_records().size() == 1, \
					"resolved list contains enemy_dup_0 (1 resolved)")
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_enter(TestPhase.DONE)
		TestPhase.DONE:
			print("TASK0164_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 30000:
		print("TASK0164_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _records_for_source(source_uid: String) -> Array[DeathRecord]:
	var out: Array[DeathRecord] = []
	for r in _ledger.get_all_records():
		if r.source_uid == source_uid:
			out.append(r)
	return out


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var game_time: Node = root.get_node("GameTime")
	if game_time:
		game_time.set_auto_advance(false)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)