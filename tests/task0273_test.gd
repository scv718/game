extends SceneTree

## TASK-027-3 Dungeon Runtime Scene / Actor Lifecycle 검증.
## - DungeonRuntime(arena) begin_run: preparation 파티를 persistent Mercenary identity로,
##   dungeon encounter_ids를 data-driven으로 Enemy를 spawn (spawn 1회).
## - spawn 시 동일 identity 중복 spawn 차단(duplicate actor 없음).
## - end_run: 살아 있는 Party를 roster data로 복귀하고 Runtime Actor를 queue_free로
##   정리(cleanup 1회). Death Ledger death 기록 없음(cleanup/despawn record 없음).
## - roster identity 유지: end_run 후에도 /root/MercenaryRoster의 MercenaryData가
##   alive 상태로 유지된다.
## - clean하게 시작되지 않으면(IN_PROGRESS 아님/파티 없음) begin_run 실패.
## - 회귀: DungeonManager/DungeonPreparationManager state 유지 + 3D main 구조 유지.

const DUNGEON_ID := "ne_ruins"

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const ARENA_SCENE_PATH := "res://scenes/dungeon_arena_3d.tscn"

## precondition 세팅에 필요한 settle physics frame(arena nav bake 대기 포함 여유).
const SETTLE_FRAMES := 60
## queue_free가 실제로 node를 해제할 때까지의 physics frame.
const FLUSH_FRAMES := 10

var _frame := 0
var _failed := false
var _stage := 0

var _main: Node = null
var _world: Node = null
var _runtime: Node = null
var _dungeon_manager: Node = null
var _prep_manager: Node = null
var _roster: Node = null
var _ledger: Node = null
var _ledger_baseline := -1


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 800:
		print("TASK0273_RESULT=TIMEOUT")
		quit()
		return true
	match _stage:
		0:
			if _frame < SETTLE_FRAMES:
				return false
			_stage = 1
			_run_setup()
			return false
		1:
			_run_spawn_checks()
			_stage = 2
			return false
		2:
			if _frame_of_stage2 < 0:
				_frame_of_stage2 = _frame
				_removed_count = _runtime.end_run()
				return false
			if _frame < _frame_of_stage2 + FLUSH_FRAMES:
				return false
			_stage = 3
			_run_cleanup_checks()
			return false
		3:
			_run_final_checks()
			_stage = 4
			return false
		_:
			print("TASK0273_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true


var _frame_of_stage2 := -1
var _removed_count := 0


func _run_setup() -> void:
	_check(load(ARENA_SCENE_PATH) != null, "dungeon_arena_3d.tscn exists and loads")
	_main = root.get_node("Main3D")
	_check(_main != null, "main_3d.tscn loads as Main3D")
	_world = _main.get_node("World3D")
	_check(_world != null, "World3D present in main_3d")
	var runtime_nodes := get_nodes_in_group("dungeon_runtime")
	_check(runtime_nodes.size() == 1, "exactly one DungeonRuntime in the scene (no duplicate arena)")
	_runtime = runtime_nodes[0]
	_check(_runtime != null and is_instance_valid(_runtime), "DungeonRuntime wired and valid")

	_dungeon_manager = root.get_node_or_null("DungeonManager")
	_prep_manager = root.get_node_or_null("DungeonPreparationManager")
	_roster = root.get_node_or_null("MercenaryRoster")
	_ledger = root.get_node_or_null("DeathLedger")
	_check(_dungeon_manager != null and _prep_manager != null and _roster != null \
		and _ledger != null, "dungeon managers + roster + ledger autoloads present")
	_ledger_baseline = _ledger.get_all_records().size()

	# dungeon + preparation + roster(identity) 준비
	_check(_dungeon_manager.create_dungeon(DUNGEON_ID) != null, "create dungeon instance")
	_check(_prep_manager.create_preparation(DUNGEON_ID), "create dungeon preparation")
	var m_a := MercenaryData.new("merc_A", "Merc A", MercenaryData.MercClass.SWORDSMAN)
	var m_b := MercenaryData.new("merc_B", "Merc B", MercenaryData.MercClass.SWORDSMAN)
	_check(_roster.add_mercenary(m_a), "roster add merc_A")
	_check(_roster.add_mercenary(m_b), "roster add merc_B")
	_check(_prep_manager.add_member(DUNGEON_ID, "merc_A")["ok"], "prep add merc_A")
	_check(_prep_manager.add_member(DUNGEON_ID, "merc_B")["ok"], "prep add merc_B")
	# depart -> IN_PROGRESS
	var dep: Dictionary = _prep_manager.depart(DUNGEON_ID)
	_check(dep.get("ok", false), "valid party departs (dungeon IN_PROGRESS)")
	_check(_dungeon_manager.get_dungeon_state(DUNGEON_ID) \
		== DungeonDefinition.DungeonState.IN_PROGRESS, "dungeon state IN_PROGRESS")

	# invert state로 방해받지 않는 안전 시작 확인은 여기서 하지 않고,
	# begin_run이 IN_PROGRESS가 아니면 실패하는지 전용 체크는 cleanup 후 확인한다.
	# (상태를 되돌리면 spawn 검증 전 상태가 깨지므로 여기서는 시작만 준비)
	var started: bool = _runtime.begin_run(DUNGEON_ID)
	_check(started, "begin_run starts a clean encounter")
	_check(_runtime.is_run_active(), "runtime reports run active")
	_check(_runtime.get_dungeon_id() == DUNGEON_ID, "runtime dungeon_id set")
	_check(_runtime.get_arena() != null and is_instance_valid(_runtime.get_arena()), \
		"dungeon arena scene loaded on enter (scene load)")


func _run_spawn_checks() -> void:
	# spawn 1회
	_check(_runtime.get_party_count() == 2, "party spawned for 2 identities (spawn 1회)")
	_check(_runtime.get_alive_party_count() == 2, "2 party actors alive")
	_check(_runtime.get_enemy_count() == 3, "3 enemies spawned from encounter data")
	_check(_runtime.get_alive_enemy_count() == 3, "3 enemies alive")
	# roster identity 유지 (spawn된 actor의 merc_data는 roster와 동일 객체)
	var actor_a: Node = _runtime.get_party_actor("merc_A")
	var actor_b: Node = _runtime.get_party_actor("merc_B")
	_check(actor_a != null and actor_a is MercenaryActor3D, "merc_A spawned as MercenaryActor3D")
	_check(actor_b != null and actor_b.get("merc_data") == _roster.get_mercenary("merc_B"), \
		"party actor carries persistent roster identity (MercenaryData)")
	# duplicate actor 없음: 같은 identity를 재-spawn 시도해도 수가 늘지 않는다
	_runtime.spawn_party(["merc_A", "merc_B", "merc_A"])
	_check(_runtime.get_party_count() == 2, "duplicate identity spawn does not add actors")
	# 이미 진행 중이므로 이중 begin_run 차단
	_check(_runtime.begin_run(DUNGEON_ID) == false, "begin_run guarded while active (no duplicate run)")
	# enemy child 노드가 arena 아래 정확히 존재
	var enemy_leaves := _count_direct_enemy_children()
	_check(enemy_leaves == 3, "3 enemy nodes are children of the dungeon arena")


func _run_cleanup_checks() -> void:
	# cleanup 1회: end_run은 살아 있는 파티를 roster 복귀하고 actor를 정리한다
	_check(_removed_count >= 5, \
		"end_run cleaned party(2)+enemy(3) actors (cleanup 1회): %d" % _removed_count)
	_check(_runtime.is_run_active() == false, "runtime inactive after end_run")
	_check(_runtime.get_party_count() == 0 and _runtime.get_enemy_count() == 0, \
		"runtime actor tracking cleared")
	_check(_runtime.get_arena() == null, "dungeon arena scene unloaded on exit (scene unload)")
	# 살아 있는 파티 identity가 roster 복귀 목록에 기록됨
	var returned: Array = ([] + _runtime.get_returned_alive_ids())
	returned.sort()
	_check(returned == ["merc_A", "merc_B"], \
		"living party identities returned to roster")
	_check(_roster.get_mercenary("merc_A").alive and _roster.get_mercenary("merc_B").alive, \
		"roster identity remains alive (roster data 유지)")
	# queue_free flush 대기 후 orphan 없음: arena 직계에 actor node가 남지 않는다
	_check(_count_direct_enemy_children() == 0 and _count_direct_party_children() == 0, \
		"no orphan party/enemy actor under arena after flush")


func _run_final_checks() -> void:
	# cleanup은 death record를 만들지 않는다 (Death Ledger 무기록)
	_check(_ledger.get_all_records().size() == _ledger_baseline, \
		"cleanup end_run creates no Death Ledger death records")
	# 재진입: 상태를 READY로 되돌린 뒤 begin_run은 IN_PROGRESS가 아니므로 실패해야 한다
	_dungeon_manager.complete_run(DUNGEON_ID)
	_dungeon_manager.mark_ready(DUNGEON_ID)
	_check(_runtime.begin_run(DUNGEON_ID) == false, \
		"begin_run rejected when dungeon not IN_PROGRESS (no illegal run)")
	# 회귀: dungeon data/state 유지 + 3D main 구조 유지
	_check(_dungeon_manager.get_dungeon(DUNGEON_ID) != null, "dungeon instance preserved")
	_check(_dungeon_manager.get_completion_count(DUNGEON_ID) == 1, \
		"completion_count incremented by complete_run (1)")
	_check(_world.get_node_or_null("Ground") != null, "World3D ground preserved")
	_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")


func _count_direct_enemy_children() -> int:
	var arena: Node = _runtime.get_arena()
	if arena == null:
		return 0
	var n := 0
	for child in arena.get_children():
		if child is EnemyActor3D:
			n += 1
	return n


func _count_direct_party_children() -> int:
	var arena: Node = _runtime.get_arena()
	if arena == null:
		return 0
	var n := 0
	for child in arena.get_children():
		if child is MercenaryActor3D:
			n += 1
	return n


func _initialize() -> void:
	var scene: Node = load(MAIN_SCENE_PATH).instantiate()
	root.add_child(scene)

