extends SceneTree

## TASK-014-2 Defense Assignment + Mercenary NIGHT Spawn 자동 검증.
##  - 여관에서 Mercenary defense zone(N/E/S/W) 변경 UI와 데이터 반영.
##  - NIGHT 시작 시 살아 있고 defense zone이 지정된 용병을 해당 방향
##    Gate 안쪽 Rally Space(Gate 없으면 RallySpace marker fallback)에 Actor spawn.
##  - DAY 복귀 시 spawn된 Actor는 roster data로 복귀(despawn).
##  - 반복 DAY/NIGHT cycle에서 actor duplicate 없음.
##  - alive=false / zone NONE 용병은 spawn 안 됨.
##  - Worker 시스템/Player 무공격/건물/nav 회귀 유지.

enum Phase {
	SETUP,
	ASSIGN_UI,
	NIGHT_FALLBACK,
	DAY_DESPAWN_FALLBACK,
	NIGHT_GATE,
	DAY_DESPAWN_GATE,
	REPEAT_CYCLE,
	ALIVE_ONLY,
	NONE_ZONE,
	REGRESSION,
	DONE,
}

const NORTH_GATE := Vector2(0, -448)
const NORTH_RALLY := Vector2(0, -280)
const EAST_RALLY := Vector2(280, 0)

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _wait := 0
var _failed := false

var _game_time: Node = null
var _world: Node = null
var _placement: Node = null
var _resources: Node = null
var _roster: Node = null
var _worker_roster: Node = null
var _mercenary: MercenaryData = null

var _cycle_i := 0


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
	print("TASK0142_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _advance_to_next_phase() -> void:
	if _game_time.get_phase() == GameTime.Phase.DAY:
		_game_time.advance(2.0)
	else:
		_game_time.advance(1.0)


func _count_actors() -> int:
	return get_nodes_in_group("mercenaries").size()


func _defense_buttons(roster_ui: Node) -> Array:
	var out: Array = []
	for block in roster_ui._mercenary_list.get_children():
		if not block is VBoxContainer:
			continue
		for child in block.get_children():
			if child is HBoxContainer:
				for sub in child.get_children():
					if sub is Button:
						out.append(sub)
	return out


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
				_placement = root.get_node("Main").get_node("BuildingPlacement")
				_resources = root.get_node("VillageResources")
				_roster = root.get_node("MercenaryRoster")
				_worker_roster = root.get_node("WorkerRoster")
				_check(_game_time != null and _world != null and _placement != null and _resources != null \
					and _roster != null and _worker_roster != null, "core nodes present")
				_resources._amounts["wood"] = 10000
				var ui: Control = get_first_node_in_group("recruitment_ui")
				_check(ui != null, "recruitment UI present")
				ui._on_mercenary_hire_pressed("mercenary_A")
				_mercenary = _roster.get_mercenary("mercenary_A")
				_check(_mercenary != null, "mercenary_A hired into roster")
				_check(_mercenary.alive, "mercenary_A alive")
				_check(_mercenary.get_defense_zone() == MercenaryData.DefenseZone.NONE, "mercenary_A zone NONE initially")
				_check(_count_actors() == 0, "no mercenary actor during DAY on hire (%d)" % _count_actors())
				_check(_roster.get_actor_count() == 0, "roster actor_count 0 during DAY")
				_enter(Phase.ASSIGN_UI)
		Phase.ASSIGN_UI:
			if _sub == 0:
				var inn: Node = _world.get_node("Inn")
				var inn_interact: Node = inn.get_node("Interact")
				inn_interact.interact(null)
				var roster_ui: Control = get_first_node_in_group("inn_roster_ui")
				_check(roster_ui != null and roster_ui.visible, "inn roster UI opens")
				var buttons := _defense_buttons(roster_ui)
				_check(buttons.size() >= 5, "mercenary defense zone buttons present (%d)" % buttons.size())
				var texts := []
				for b in buttons:
					texts.append(str(b.text))
				_check("NONE" in texts and "NORTH" in texts and "EAST" in texts and "SOUTH" in texts and "WEST" in texts, "defense zone button labels N/E/S/W")
				roster_ui._on_defense_zone_pressed(_mercenary, MercenaryData.DefenseZone.EAST)
				_check(_mercenary.get_defense_zone() == MercenaryData.DefenseZone.EAST, "defense assignment EAST via inn UI")
				_check(_mercenary.get_defense_name() == "EAST", "defense name EAST")
				roster_ui.close()
				_check(not roster_ui.visible, "roster UI closes")
				_advance_to_next_phase()
				_enter(Phase.NIGHT_FALLBACK)
		Phase.NIGHT_FALLBACK:
			if _sub == 0:
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT after advance")
				_check(_count_actors() == 1, "1 mercenary actor spawned at NIGHT (%d)" % _count_actors())
				_check(_roster.get_actor_count() == 1, "roster actor_count 1 at NIGHT")
				var actor: MercenaryActor = _roster.get_actor("mercenary_A") as MercenaryActor
				_check(actor != null, "actor retrievable by id")
				_check(actor != null and actor.is_in_group("mercenaries"), "actor in mercenaries group")
				_check(actor != null and actor.merc_data == _mercenary, "actor references roster MercenaryData")
				_check(actor != null and actor.current_hp == _mercenary.max_hp, "actor current_hp initialized from max_hp")
				_check(actor != null and actor.get_defense_zone() == MercenaryData.DefenseZone.EAST, "actor defense zone EAST")
				var pos: Vector2 = (actor as Node2D).global_position
				_check(pos.distance_to(EAST_RALLY) < 1.0, "east fallback spawn at RallyPoint (pos=%s)" % pos)
				_advance_to_next_phase()
				_enter(Phase.DAY_DESPAWN_FALLBACK)
		Phase.DAY_DESPAWN_FALLBACK:
			if _sub == 0:
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase back to DAY")
				_check(_count_actors() == 0, "actor despawned on DAY return (group=%d)" % _count_actors())
				_check(_roster.get_actor_count() == 0, "roster actor_count 0 on DAY")
				_check(_roster.get_mercenary("mercenary_A") == _mercenary, "roster data retained after despawn")
				_check(_mercenary.alive, "mercenary still alive in roster")
				_check(_mercenary.get_defense_zone() == MercenaryData.DefenseZone.EAST, "defense zone retained EAST")
				_enter(Phase.NIGHT_GATE)
		Phase.NIGHT_GATE:
			if _sub == 0:
				_placement._set_building_type("gate")
				_placement._try_place_gate_at(_placement._snap_gate(NORTH_GATE))
				_check(_find_gate_at(NORTH_GATE) != null, "north gate placed")
				var roster_ui: Control = get_first_node_in_group("inn_roster_ui")
				roster_ui._on_defense_zone_pressed(_mercenary, MercenaryData.DefenseZone.NORTH)
				_check(_mercenary.get_defense_zone() == MercenaryData.DefenseZone.NORTH, "defense assignment NORTH via inn UI")
				_advance_to_next_phase()
				_enter(Phase.DAY_DESPAWN_GATE)
		Phase.DAY_DESPAWN_GATE:
			if _sub == 0:
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_actors() == 1, "1 actor spawned with gate present (%d)" % _count_actors())
				var actor: MercenaryActor = _roster.get_actor("mercenary_A") as MercenaryActor
				_check(actor != null, "gate-path actor present")
				var pos: Vector2 = (actor as Node2D).global_position
				_check(pos.distance_to(NORTH_RALLY) < 1.0, "north gate-inside Rally Space spawn (pos=%s)" % pos)
				_check(_roster.spawn_night_actors() == 0, "spawn_night_actors idempotent (0 new during same NIGHT)")
				_check(_count_actors() == 1, "no duplicate actor after redundant spawn call")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "gate-path phase back to DAY")
				_check(_count_actors() == 0, "gate-path actor despawned on DAY (%d)" % _count_actors())
				_enter(Phase.REPEAT_CYCLE)
		Phase.REPEAT_CYCLE:
			if _sub == 0:
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "repeat cycle %d phase NIGHT" % _cycle_i)
				_check(_count_actors() == 1, "repeat cycle %d exactly 1 actor (no duplicate) (%d)" % [_cycle_i, _count_actors()])
				_check(_roster.get_actor_count() == 1, "repeat cycle %d roster actor_count 1" % _cycle_i)
				var actor: Node = _roster.get_actor("mercenary_A")
				_check(actor != null and actor.is_in_group("mercenaries"), "repeat cycle %d actor valid" % _cycle_i)
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "repeat cycle %d phase DAY" % _cycle_i)
				_check(_count_actors() == 0, "repeat cycle %d actor despawned" % _cycle_i)
				_cycle_i += 1
				if _cycle_i >= 3:
					_enter(Phase.ALIVE_ONLY)
				else:
					_sub = 0
		Phase.ALIVE_ONLY:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "ALIVE_ONLY starts in DAY")
				_mercenary.alive = false
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "ALIVE_ONLY phase NIGHT")
				_check(_count_actors() == 0, "dead mercenary NOT spawned (%d)" % _count_actors())
				_mercenary.alive = true
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "ALIVE_ONLY returns to DAY")
				_check(_count_actors() == 0, "no actor after restoring alive on DAY")
				_enter(Phase.NONE_ZONE)
		Phase.NONE_ZONE:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "NONE_ZONE starts in DAY")
				_mercenary.set_defense_zone(MercenaryData.DefenseZone.NONE)
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "NONE_ZONE phase NIGHT")
				_check(_count_actors() == 0, "NONE-zone mercenary NOT spawned (%d)" % _count_actors())
				_mercenary.set_defense_zone(MercenaryData.DefenseZone.NORTH)
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "NONE_ZONE returns to DAY")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "REGRESSION starts in DAY")
				_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor (Player never fights)")
				_check(_worker_roster.get_count() == 0, "worker roster unaffected by mercenary (%d)" % _worker_roster.get_count())
				_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor spawned")
				_check(get_nodes_in_group("miners").size() == 0, "no miner actor spawned")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_actors() == 1, "final NIGHT spawn works after zone restore (%d)" % _count_actors())
				var actor: Node = _roster.get_actor("mercenary_A")
				var pos: Vector2 = (actor as Node2D).global_position if actor != null else Vector2(99999, 99999)
				_check(actor != null and pos.distance_to(NORTH_RALLY) < 1.0, "final actor at north rally (pos=%s)" % pos)
				var nav_map: RID = _world.get_world_2d().get_navigation_map()
				var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, NORTH_RALLY, Vector2(0, -150), true)
				_check(path.size() >= 2, "nav path from rally to keep exists (%d pts)" % path.size())
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_count_actors() == 0, "final DAY cleanup despawns actor")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 60000:
		print("TASK0142_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)