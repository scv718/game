extends SceneTree

## TASK-EXP-001-3 Exploration Foundation 통합 검증.
## Exploration loop 전체를 실제 런타임 경로(프레임 _process 누적 + GameTime phase
## 전환 + 실제 입력)로 end-to-end 검증한다:
##   1. Player Actor 없음.
##   2. World Map open(M key 입력 경로).
##   3. UNKNOWN region 확인.
##   4. Explore 시작(실제 마우스 클릭 선택 + Explore 버튼).
##   5. GameTime 진행(실제 프레임 누적 + DAY/NIGHT 전환).
##   6. progress 확인(단조 증가, 전술 Pause 동결, 2x 배율 반영).
##   7. 완료(자연 완료 - 직접 advance() 호출 없음).
##   8. DISCOVERED 확인(deterministic feature).
##   9. Map marker 갱신(열린 Map에서 실시간 패널/버튼 전환).
##   10. repeated Explore 차단.
##   11. DAY/NIGHT 반복(중복 signal / stale reference 없음).
##   12. Worker/Combat/Death Ledger 회귀.
##
## 참고: exploration_duration은 테스트 속도를 위해 시작 전 짧게 조정하는
## fixture 값이다(task0075의 resources._amounts 직접 설정과 같은 테스트 전용 조치).

enum Phase {
	SETUP,
	NO_PLAYER,
	MAP_OPEN_UNKNOWN,
	EXPLORE_START,
	PROGRESS_RUN,
	COMPLETE_WAIT,
	DISCOVERED_CHECK,
	REPEAT_BLOCK,
	DAY_NIGHT_REPEAT,
	WORKER_REGRESSION,
	COMBAT_LEDGER_REGRESSION,
	REGRESSION,
	DONE,
}

const REGION_ID := "ne_dungeon"
## fixture 탐사 소요 시간(초). 측정 창(1x/Pause/2x)과 DAY/NIGHT 전환을 모두
## 거치는 동안 완료되지 않을 만큼 충분히 길게 잡는다.
const TEST_DURATION := 6.0
const COMPLETE_BUDGET := 6000
const WORKER_BUDGET := 1500
const COMBAT_BUDGET := 3000

var _frame := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _wait := 0
var _budget := 0
var _failed := false

var _main: Node = null
var _world: Node = null
var _game_time: Node = null
var _manager: Node = null
var _region: ExplorationRegion = null
var _overlay_ctrl: Node = null
var _explore_button: Button = null
var _spawner: Node = null
var _placement: Node = null
var _resources: Node = null
var _roster: Node = null
var _ledger: Node = null
var _tactical_ui: Node = null

var _started_count := 0
var _discovered_count := 0
var _added_count := 0

var _p_base := 0.0
var _p_mark := 0.0
var _rate_1x := 0.0
var _work_base := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _enter(p: Phase) -> void:
	_phase = p
	_sub = 0
	_wait = 0
	_budget = 0


func _wait_frames(n: int) -> void:
	_wait = n
	_sub += 1


func _waited() -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	return true


func _finish() -> void:
	print("TASKEXP0013_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _m_key_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_M
	ev.physical_keycode = KEY_M
	ev.pressed = true
	return ev


func _region_click_event(world_pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = _overlay_ctrl.world_to_map(world_pos)
	ev.global_position = ev.position
	return ev


func _count_enemies() -> int:
	return get_nodes_in_group("enemies").size()


func _count_mercenaries() -> int:
	return get_nodes_in_group("mercenaries").size()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _sub == 0:
				if _frame < 8:
					return false
				# headless 기본 window(64x64)는 overlay 레이아웃을 붕괴시키므로
				# 프로젝트 해상도로 강제한다(taskexp0012 패턴).
				root.size = Vector2i(1152, 648)
				_main = root.get_node("Main")
				_world = _main.get_node("World")
				_game_time = root.get_node("GameTime")
				_game_time.set_auto_advance(false)
				_game_time.set_durations(2.0, 1.0)
				_game_time.set_time_scale(GameTime.TIME_SCALE_1X)
				# ExplorationManager 자동 진행은 끄지 않는다(실제 런타임 경로 검증).
				_manager = root.get_node_or_null("ExplorationManager")
				_check(_manager != null, "ExplorationManager autoload registered")
				_manager.exploration_started.connect(func(_id): _started_count += 1)
				_manager.region_discovered.connect(func(_id): _discovered_count += 1)
				_region = _manager.get_region(REGION_ID)
				_check(_region != null, "prototype region '%s' registered" % REGION_ID)
				_check(_region != null \
					and _region.get_discovery_state() == ExplorationRegion.DiscoveryState.UNKNOWN, \
					"region starts UNKNOWN")
				_spawner = root.get_node("FirstEncounterSpawner")
				_spawner.set_direction("west")
				_check(_spawner.get_direction() == "west", "encounter direction west (WEST = main threat)")
				_placement = _main.get_node("BuildingPlacement")
				_resources = root.get_node("VillageResources")
				_roster = root.get_node("MercenaryRoster")
				_ledger = root.get_node("DeathLedger")
				_resources._amounts["wood"] = 10000
				var overlays := get_nodes_in_group("world_map_overlay")
				_check(overlays.size() == 1, "exactly 1 WorldMapOverlay (%d)" % overlays.size())
				_overlay_ctrl = _main.get_node("WorldMapOverlay").get_node("Control")
				_explore_button = _overlay_ctrl.get_node("%ExploreButton")
				var tactical_nodes := get_nodes_in_group("tactical_command_ui")
				_tactical_ui = tactical_nodes[0] if tactical_nodes.size() > 0 else null
				_check(_tactical_ui != null, "TacticalCommandUI present")
				_check(_ledger.get_all_records().size() == 0, "DeathLedger starts empty")
				_wait_frames(10)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_enter(Phase.NO_PLAYER)
		Phase.NO_PLAYER:
			_check(get_nodes_in_group("player").size() == 0, "1. no runtime Player Actor")
			var ctrls := get_nodes_in_group("camera_controller")
			_check(ctrls.size() == 1 and ctrls[0].get_camera() != null, "camera controller intact")
			_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
			var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
			_check(floor_node != null and floor_node.get_used_cells().size() >= 128 * 128, \
				"world floor intact (>=128x128 cells)")
			_enter(Phase.MAP_OPEN_UNKNOWN)
		Phase.MAP_OPEN_UNKNOWN:
			if _sub == 0:
				_overlay_ctrl._unhandled_input(_m_key_event())
				_check(_overlay_ctrl.is_open() and _overlay_ctrl.visible, "2. World Map opens via M key")
				_sub = 1
			elif _sub == 1:
				# 실제 입력 경로로 region marker 클릭 선택(push_input → Control._gui_input).
				root.push_input(_region_click_event(_region.world_position))
				_check(_overlay_ctrl.get_selected_region_id() == REGION_ID, \
					"map click selects exploration region")
				_check("UNKNOWN" in String(_overlay_ctrl.get_node("%RegionStatusLabel").text), \
					"3. region shown UNKNOWN before explore")
				_check(not _explore_button.disabled and String(_explore_button.text) == "Explore", \
					"Explore enabled for UNKNOWN region")
				_enter(Phase.EXPLORE_START)
		Phase.EXPLORE_START:
			if _sub == 0:
				# 테스트 전용 fixture: 완료까지 실제 런타임 진행으로 도달하되 대기 시간 단축.
				_region.exploration_duration = TEST_DURATION
				_explore_button.pressed.emit()
				_check(_region.get_discovery_state() == ExplorationRegion.DiscoveryState.EXPLORING, \
					"4. UI Explore button starts exploration (EXPLORING)")
				_check(_started_count == 1, "exploration_started emitted exactly once")
				_check(_explore_button.disabled and String(_explore_button.text) == "Exploring...", \
					"button disabled while EXPLORING")
				_check("EXPLORING" in String(_overlay_ctrl.get_node("%RegionStatusLabel").text), \
					"panel shows EXPLORING right after start")
				_p_base = 0.0
				_wait_frames(12)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_p_base = _manager.get_progress(REGION_ID)
				_check(_p_base > 0.0 and _p_base < 1.0, \
					"5. progress accumulates from real frame ticks (%.4f)" % _p_base)
				_enter(Phase.PROGRESS_RUN)
		Phase.PROGRESS_RUN:
			if _sub == 0:
				_p_mark = _manager.get_progress(REGION_ID)
				_wait_frames(15)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				var p_a: float = _manager.get_progress(REGION_ID)
				_rate_1x = p_a - _p_mark
				_check(p_a > _p_mark, "6. progress monotonic increase at 1x (+%.4f)" % _rate_1x)
				_game_time.set_time_scale(GameTime.TIME_SCALE_PAUSE)
				_p_mark = p_a
				_wait_frames(15)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				var p_b: float = _manager.get_progress(REGION_ID)
				_check(_approx(p_b, _p_mark), \
					"tactical Pause freezes exploration progress (%.4f)" % p_b)
				_game_time.set_time_scale(GameTime.TIME_SCALE_1X)
				_p_mark = p_b
				_wait_frames(15)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				var p_c: float = _manager.get_progress(REGION_ID)
				_check(p_c > _p_mark, "progress resumes after Pause (+%.4f)" % (p_c - _p_mark))
				_game_time.set_time_scale(GameTime.TIME_SCALE_2X)
				_p_mark = p_c
				_wait_frames(15)
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				var p_d: float = _manager.get_progress(REGION_ID)
				var rate_2x: float = p_d - _p_mark
				_check(rate_2x >= _rate_1x * 1.5, \
					"tactical 2x scales exploration rate (%.4f vs %.4f)" % [rate_2x, _rate_1x])
				_game_time.set_time_scale(GameTime.TIME_SCALE_1X)
				# 탐사 중 DAY -> NIGHT 전환: progress 정책 일관(리셋 없음).
				_game_time.advance(2.0)
				_spawner.despawn_encounter()
				_p_mark = p_d
				_wait_frames(5)
			elif _sub == 5 and not _waited():
				return false
			elif _sub == 5:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "mid-exploration NIGHT entered")
				var p_e: float = _manager.get_progress(REGION_ID)
				_check(p_e >= _p_mark and _region.get_discovery_state() \
					== ExplorationRegion.DiscoveryState.EXPLORING, \
					"phase transition does not reset exploration (%.4f)" % p_e)
				_p_mark = p_e
				_check(_count_enemies() == 0, "auto-encounter despawned during exploration NIGHT")
				_wait_frames(15)
			elif _sub == 6 and not _waited():
				return false
			elif _sub == 6:
				var p_f: float = _manager.get_progress(REGION_ID)
				_check(p_f > _p_mark, "progress advances during NIGHT (same policy)")
				_game_time.advance(1.0)
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "back to DAY mid-exploration")
				_enter(Phase.COMPLETE_WAIT)
		Phase.COMPLETE_WAIT:
			if _sub == 0:
				if _region.get_discovery_state() == ExplorationRegion.DiscoveryState.DISCOVERED:
					_wait_frames(4)
				elif _budget >= COMPLETE_BUDGET:
					_check(false, "7. exploration never completed in budget (progress=%.4f)" \
						% _manager.get_progress(REGION_ID))
					_finish()
					return true
				else:
					_budget += 1
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(true, "7. exploration completed by real runtime progression")
				_enter(Phase.DISCOVERED_CHECK)
		Phase.DISCOVERED_CHECK:
			_check(_region.get_discovery_state() == ExplorationRegion.DiscoveryState.DISCOVERED \
				and _region.get_discovery_state_name() == "DISCOVERED", "8. region state DISCOVERED")
			_check(_discovered_count == 1 and _started_count == 1, \
				"signals exactly once each (started=%d discovered=%d)" % [_started_count, _discovered_count])
			_check(_approx(_manager.get_progress(REGION_ID), 1.0), "progress clamped to 1.0")
			_check(_region.has_discovered_feature("dungeon_entrance") \
				and _region.has_discovered_feature("safe_approach") \
				and _region.get_discovered_features().size() == 2, \
				"fixed deterministic discovery features applied")
			# 9. Map이 열려 있는 동안 marker/panel이 실시간 갱신되었는지(수동 재선택 없이).
			_check(_overlay_ctrl.is_open(), "map still open during completion (live refresh path)")
			_check(_overlay_ctrl.get_selected_region_id() == REGION_ID, "selection preserved")
			var status_text := String(_overlay_ctrl.get_node("%RegionStatusLabel").text)
			_check(_overlay_ctrl.get_node("%RegionTitleLabel").text == "NE Dungeon" \
				and "DISCOVERED" in status_text and "dungeon_entrance" in status_text, \
				"9. map panel refreshed to DISCOVERED with features (%s)" % status_text)
			_check(_explore_button.disabled and String(_explore_button.text) == "Discovered", \
				"Explore button switched to disabled 'Discovered'")
			_overlay_ctrl.close()
			_overlay_ctrl.open()
			_overlay_ctrl.select_region(REGION_ID)
			_check("DISCOVERED" in String(_overlay_ctrl.get_node("%RegionStatusLabel").text), \
				"marker state persists after map reopen")
			_enter(Phase.REPEAT_BLOCK)
		Phase.REPEAT_BLOCK:
			_explore_button.pressed.emit()
			_check(_started_count == 1 and _discovered_count == 1 \
				and _region.get_discovery_state() == ExplorationRegion.DiscoveryState.DISCOVERED, \
				"10. repeated UI press does not restart or duplicate signals")
			_check(_manager.can_start_exploration(REGION_ID) == false \
				and _manager.start_exploration(REGION_ID) == false, \
				"manager rejects repeated start after DISCOVERED")
			_overlay_ctrl.close()
			_enter(Phase.DAY_NIGHT_REPEAT)
		Phase.DAY_NIGHT_REPEAT:
			if _sub == 0:
				_check(_ledger.get_all_records().size() == 0, \
					"no deaths from exploration/cycles so far")
				_game_time.advance(2.0)
				_spawner.despawn_encounter()
				_overlay_ctrl._unhandled_input(_m_key_event())
				_check(_overlay_ctrl.is_open(), "11. map opens during repeated NIGHT")
				_overlay_ctrl._unhandled_input(_m_key_event())
				_check(_overlay_ctrl.is_open() == false, "map closes during repeated NIGHT")
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_enemies() == 0 and _spawner.get_enemy_count() == 0, \
					"encounter despawn leaves no stale enemies")
				_game_time.advance(1.0)
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "cycle 1 back to DAY")
				_check(_tactical_ui.visible == false, "tactical UI hidden in DAY")
				_check(_count_mercenaries() == 0, "no mercenary actors without hire")
				_game_time.advance(2.0)
				_spawner.despawn_encounter()
				_game_time.advance(1.0)
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "cycle 2 back to DAY")
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(get_nodes_in_group("world_map_overlay").size() == 1 \
					and get_nodes_in_group("camera_controller").size() == 1 \
					and get_nodes_in_group("tactical_command_ui").size() == 1 \
					and get_nodes_in_group("world_selection").size() == 1 \
					and get_nodes_in_group("building_placement").size() == 1, \
					"repeated cycles leave no duplicate systems")
				_check(_manager.get_regions().size() == 1, "no duplicated regions")
				_check(_region.get_discovery_state() == ExplorationRegion.DiscoveryState.DISCOVERED \
					and _approx(_manager.get_progress(REGION_ID), 1.0), \
					"DISCOVERED persists across repeated cycles")
				_check(_started_count == 1 and _discovered_count == 1, "no duplicate signals after cycles")
				_enter(Phase.WORKER_REGRESSION)
		Phase.WORKER_REGRESSION:
			if _sub == 0:
				var deposits := get_nodes_in_group("stone_deposits")
				_check(deposits.size() >= 1, "stone deposit present")
				_placement._set_building_type("quarry")
				_placement._try_place_quarry_at((deposits[0] as Node2D).global_position)
				var quarries := get_nodes_in_group("quarries")
				_check(quarries.size() == 1, "12. quarry built on deposit (worker regression)")
				var miner := (load("res://scenes/miner.tscn") as PackedScene).instantiate() as Node2D
				miner.position = (deposits[0] as Node2D).global_position + Vector2(40, 40)
				_world.add_child(miner)
				var res: Dictionary = quarries[0].handle_worker_interaction()
				_check(res.get("action") == "assign" and res.get("success") == true, \
					"quarry assigns miner (%s)" % str(res))
				_work_base = _resources.get_amount("stone")
				_sub = 1
			elif _sub == 1:
				var stone: int = _resources.get_amount("stone")
				if stone >= _work_base + 1:
					_check(true, "assigned miner produces stone (%d)" % stone)
					var quarries2 := get_nodes_in_group("quarries")
					_check(quarries2[0].unassign_worker(get_nodes_in_group("miners")[0]), \
						"miner unassigned cleanly after production check")
					_enter(Phase.COMBAT_LEDGER_REGRESSION)
				elif _budget >= WORKER_BUDGET:
					_check(false, "miner never produced stone in budget (stone=%d state=%s)" \
						% [_resources.get_amount("stone"), \
						str((get_nodes_in_group("miners")[0] as Node).get("state"))])
					_finish()
					return true
				else:
					_budget += 1
					return false
		Phase.COMBAT_LEDGER_REGRESSION:
			if _sub == 0:
				var ui: Control = get_first_node_in_group("recruitment_ui")
				_check(ui != null, "recruitment UI present")
				ui._on_mercenary_hire_pressed("mercenary_A")
				var mercenary: MercenaryData = _roster.get_mercenary("mercenary_A")
				_check(mercenary != null and mercenary.alive, "mercenary_A hired alive")
				mercenary.set_defense_zone(MercenaryData.DefenseZone.WEST)
				mercenary.max_hp = 80
				mercenary.attack_damage = 30
				mercenary.attack_interval = 0.05
				mercenary.move_speed = 120.0
				_ledger.record_added.connect(func(_record_id): _added_count += 1)
				_game_time.advance(2.0)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "NIGHT for combat regression")
				_check(_count_mercenaries() == 1, "mercenary actor spawned at NIGHT")
				var actor: Node = _roster.get_actor("mercenary_A")
				_check(actor != null, "mercenary actor retrievable")
				_check(_spawner.get_enemy_count() == 3, "west encounter spawned on NIGHT")
				_spawner.despawn_encounter()
				# 격리된 자동전투 검증: 약한 HOLD 적 1마리를 rally 근처에 배치.
				var e := (load("res://scenes/enemy.tscn") as PackedScene).instantiate() as EnemyActor
				e.max_hp = 60
				e.current_hp = 60
				e.attack_damage = 1
				e.attack_interval = 0.05
				e.setup("texp13_enemy_0", "Raider", "west")
				e.position = (actor as Node2D).global_position + Vector2(0, -70)
				_world.add_child(e)
				_wait_frames(2)
			elif _sub == 2:
				if _ledger.has_record_for_source("texp13_enemy_0") or _count_enemies() == 0:
					_wait_frames(4)
				elif _budget >= COMBAT_BUDGET:
					_check(false, "enemy never killed by auto combat in budget (enemies=%d)" \
						% _count_enemies())
					_finish()
					return true
				else:
					_budget += 1
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(_count_enemies() == 0, "dead enemy removed from combat (target/group)")
				var records: Array = _ledger.get_all_records()
				_check(records.size() == 1 and _added_count == 1, \
					"lethal death recorded exactly once (%d)" % records.size())
				if records.size() == 1:
					var rec: DeathRecord = records[0]
					_check(rec.source_kind == DeathRecord.SourceKind.ENEMY \
						and rec.display_name == "Raider", "ENEMY record identity retained")
					_check(rec.death_day == _game_time.get_day_number() \
						and rec.death_phase == DeathRecord.DeathPhase.NIGHT, \
						"death day/phase retained (NIGHT)")
					_check(rec.eligible_day == rec.death_day + 1 \
						and rec.get_status() == DeathRecord.Status.PENDING, \
						"record PENDING with eligible_day = death_day + 1")
				var actor2: Node = _roster.get_actor("mercenary_A")
				_check(actor2 != null and is_instance_valid(actor2), "mercenary survived combat")
				_game_time.advance(1.0)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "DAY return after combat")
				_check(_roster.get_actor("mercenary_A") == null and _roster.get_actor_count() == 0, \
					"DAY despawn removes mercenary actor (no stale reference)")
				var roster_merc: MercenaryData = _roster.get_mercenary("mercenary_A")
				_check(roster_merc != null and roster_merc.alive, "surviving merc returns to data")
				_check(_ledger.get_all_records().size() == 1 \
					and _ledger.get_pending_records().size() == 1 \
					and _added_count == 1, \
					"cleanup/despawn created no new death records")
				_check(_spawner.get_enemy_count() == 0 and _spawner._enemies.size() == 0, \
					"spawner holds no stale references during DAY")
				_sub = 2
			elif _sub == 2:
				_check(get_nodes_in_group("player").size() == 0, "still no Player Actor at end")
				_check(get_nodes_in_group("core_buildings").size() == 5, "core buildings intact at end")
				_check(_region.get_discovery_state() == ExplorationRegion.DiscoveryState.DISCOVERED \
					and _approx(_manager.get_progress(REGION_ID), 1.0), \
					"exploration state untouched by worker/combat regression")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASKEXP0013_RESULT=TIMEOUT phase=%s sub=%d wait=%d budget=%d" \
			% [str(_phase), _sub, _wait, _budget])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
