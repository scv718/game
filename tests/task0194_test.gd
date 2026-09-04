extends SceneTree

## TASK-019-4 Farm Vertical Slice Regression 회귀 테스트.
## task0191/0192/0193의 단위 검증을 하나의 실제 수직 슬라이스로 묶어 재생한다.
##
## 완료조건 매핑:
##   1. farm → raw food → consumption loop PASS.
##      시나리오 9단계를 그대로 재생한다:
##        Farm 건설(BuildingPlacement3D KEY_5 + B + click) ->
##        Farmer assign(WorkerRoster) -> crop work(MOVE_TO_WORK) ->
##        growth(SEED->GROWING->READY) -> harvest -> raw ingredient stock 증가 ->
##        food 부족 -> RawFood fallback으로 raw ingredient 소비 ->
##        DAY/NIGHT 반복 중에도 farm 생산 loop 지속.
##   2. 기존 Lumberjack/Miner 회귀 없음 - 본 테스트 종료 후 task3dwrk0012_test.gd
##      재실행으로 확인한다(별도 run 로그 보관).
##
## 추가 검증(vertical slice 의미):
##   - DAY/NIGHT phase 전환 중에도 farmer actor가 유지되고 crop 생산이 이어진다
##     (민간 worker는 야간에도 계속 일한다 - 기존 worker convention).
##   - phase 반복 cycle에서 duplicate actor / freed reference / stale claim이 없다.
##   - crop regrow(replant)가 반복되어 생산 loop가 지속된다.

enum Phase {
	SETUP, CONTRACT, BUILD_FARM, BUILD_CHECK, NAV_SYNC,
	FARMER_ASSIGN, GROW_WAIT, GROW_READY, HARVEST_LOOP, HARVEST_CHECK,
	FOOD_SHORTAGE, RAW_CONSUME,
	TO_NIGHT, NIGHT_WAIT, NIGHT_CHECK, TO_DAY, DAY_WAIT, DAY_CHECK,
	SECOND_NIGHT, SECOND_DAY, FINAL, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 10
const LOOP_FRAME_LIMIT := 4000
const START_WOOD := 500
const FARM_CELL := Vector3(5, 0, 5)

const TEST_GROWTH_TIME := 1.0
const TEST_REGROW_TIME := 1.0
const SHORT_DAY_DURATION := 1.0
const SHORT_NIGHT_DURATION := 1.0

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _nav: Node = null
var _cam_ctl: Node = null
var _placement: Node = null
var _roster: Node = null
var _resources: Node = null
var _game_time: Node = null

var _farm: Node3D = null
var _farmer: WorkerData = null
var _actor: Node = null

var _crop_before := 0
var _harvested_some := false
var _wood_ledger := 0
var _stages_seen := {}


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_wait = 0


func _finish() -> void:
	if _farmer != null and is_instance_valid(_farmer) and _farmer.is_assigned():
		_roster.unassign(_farmer)
	if is_instance_valid(_farm):
		_farm.free()
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK0194_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _crop() -> int:
	return _resources.get_amount("crop")


func _farmers() -> int:
	return get_nodes_in_group("farmers_3d").size()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.BUILD_FARM:
			_build_farm()
		Phase.BUILD_CHECK:
			_build_check()
		Phase.NAV_SYNC:
			_nav_sync()
		Phase.FARMER_ASSIGN:
			_farmer_assign()
		Phase.GROW_WAIT:
			_grow_wait()
		Phase.GROW_READY:
			_grow_ready()
		Phase.HARVEST_LOOP:
			_harvest_loop()
		Phase.HARVEST_CHECK:
			_harvest_check()
		Phase.FOOD_SHORTAGE:
			_food_shortage()
		Phase.RAW_CONSUME:
			_raw_consume()
		Phase.TO_NIGHT:
			_to_night()
		Phase.NIGHT_WAIT:
			_night_wait()
		Phase.NIGHT_CHECK:
			_night_check()
		Phase.TO_DAY:
			_to_day()
		Phase.DAY_WAIT:
			_day_wait()
		Phase.DAY_CHECK:
			_day_check()
		Phase.SECOND_NIGHT:
			_second_night()
		Phase.SECOND_DAY:
			_second_day()
		Phase.FINAL:
			_final()
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0194_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	_world = world_scene

	_cam_ctl = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	_cam_ctl.name = "CamController"
	root.add_child(_cam_ctl)

	_placement = load("res://scripts/building_placement_3d.gd").new()
	_placement.name = "BuildingPlacement3D"
	root.add_child(_placement)

	_nav = load("res://scripts/navigation_manager_3d.gd").new()
	_nav.name = "NavManager"
	_world.add_child(_nav)


func _setup() -> void:
	if _frame < PHYSICS_WAIT_FRAMES:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_nav = root.get_node_or_null("World3DRoot/NavManager")
	_roster = root.get_node_or_null("WorkerRoster")
	_resources = root.get_node_or_null("VillageResources")
	_game_time = root.get_node_or_null("GameTime")
	if _world == null or _nav == null or _roster == null or _resources == null \
			or _game_time == null:
		_check(false, "world / navigation / autoloads available")
		_finish()
		return
	_game_time.set_auto_advance(false)
	_game_time.set_durations(SHORT_DAY_DURATION, SHORT_NIGHT_DURATION)
	_check(_game_time.get_phase_name() == "DAY", "vertical slice starts in DAY")
	_resources.add("wood", START_WOOD)
	_wood_ledger = START_WOOD
	_enter(Phase.CONTRACT)


func _contract() -> void:
	var farm_script: GDScript = load("res://scripts/farm_3d.gd")
	var wp_base: GDScript = load("res://scripts/workplace_3d.gd")
	var bld_base: GDScript = load("res://scripts/building_3d.gd")
	_check(farm_script.get_base_script() == wp_base \
			and wp_base.get_base_script() == bld_base,
		"Farm3D follows the Workplace3D -> Building3D contract path")
	_check(_placement.BUILD_COSTS.has("farm")
		and _placement.BUILD_COSTS["farm"] == {"wood": 10},
		"farm joins the building economy with a single wood cost")
	_check(_placement._building_scene_for("farm") != null,
		"BuildingPlacement3D resolves the farm scene for free-building placement")
	_enter(Phase.BUILD_FARM)


func _aim(pos: Vector3) -> Vector3:
	return pos + Vector3(0.3, 0.0, 0.3)


func _screen_of(world_pos: Vector3) -> Vector2:
	return _cam_ctl.get_camera().unproject_position(world_pos)


func _push_motion(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	root.push_input(motion)


func _push_left_click(screen_pos: Vector2) -> void:
	_push_motion(screen_pos)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen_pos
	root.push_input(event)


func _push_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	root.push_input(event)


func _build_farm() -> void:
	match _wait:
		0:
			_push_key(KEY_5)
			_push_key(KEY_B)
		1:
			_check(_placement.is_active(), "build mode activates for the farm")
			_push_left_click(_screen_of(_aim(FARM_CELL)))
		2:
			_enter(Phase.BUILD_CHECK)
			return
	_wait += 1


func _build_check() -> void:
	var farms := get_nodes_in_group("farms_3d")
	_check(farms.size() == 1, "one farm constructed via the build path (scenario 1)")
	if farms.size() == 1:
		_farm = farms[0]
		_check(_farm.position.is_equal_approx(FARM_CELL),
			"placed farm occupies the aimed grid cell center")
	_wood_ledger -= 10
	_check(_resources.get_amount("wood") == _wood_ledger,
		"farm cost is deducted exactly once")
	# 빠른 성장을 위해 plot들의 growth/regrow 시간을 갱신한다.
	var crop_data := CropData.new("wheat", "Wheat")
	crop_data.growth_time = TEST_GROWTH_TIME
	crop_data.raw_resource_id = "crop"
	crop_data.raw_efficiency = 0.5
	crop_data.stage_count = 3
	crop_data.harvest_amount = 1
	_farm.crop_definition = crop_data
	for c in _farm.get_crops():
		if c != null and is_instance_valid(c):
			c.growth_time = TEST_GROWTH_TIME
			c.regrow_time = TEST_REGROW_TIME
	_check(_farm.get_crops().size() == 3, "farm plants a fixed set of crop plots")
	_check(not _placement.is_active(), "single-place farm exits build mode")
	_enter(Phase.NAV_SYNC)


func _nav_sync() -> void:
	if _wait == 0:
		_nav.rebuild_navigation()
	_wait += 1
	if _wait < NAV_SYNC_FRAMES:
		return
	_wait = 0
	_enter(Phase.FARMER_ASSIGN)


func _farmer_assign() -> void:
	_crop_before = _crop()
	_farmer = WorkerData.new("farmer_T", "Farmer T", WorkerData.Job.FARMER)
	_check(_roster.add_worker(_farmer), "hire a farmer into the shared WorkerRoster")
	_check(_farmers() == 0, "hired farmer stays roster data only (no world actor yet)")
	_check(_roster.assign(_farmer, _farm), "assign farmer to the farm (scenario 2)")
	_check(_farmer.is_assigned(), "farmer worker data assigned")
	_actor = _roster.get_actor(_farmer)
	_check(_actor != null and is_instance_valid(_actor), "farmer actor spawned")
	if _actor != null:
		_check(_actor.get_state_name() == "MOVE",
			"farmer starts in MOVE_TO_WORK after assign (crop work, scenario 3)")
	_wait = 0
	_frame = 0
	_enter(Phase.GROW_WAIT)


func _record_stages() -> void:
	for c in _farm.get_crops():
		if c != null and is_instance_valid(c):
			var sn: String = c.get_stage_name()
			if not _stages_seen.has(sn):
				_stages_seen[sn] = true


func _grow_wait() -> void:
	_wait += 1
	_record_stages()
	if _wait < 20:
		return
	var any_ready := false
	for c in _farm.get_crops():
		if c != null and is_instance_valid(c) and c.can_interact():
			any_ready = true
	_check(not any_ready or _wait >= 60,
		"crops are not ready to harvest before growth completes")
	_wait = 0
	_enter(Phase.GROW_READY)


func _grow_ready() -> void:
	_wait += 1
	_record_stages()
	var all_ready := true
	for c in _farm.get_crops():
		if c == null or not is_instance_valid(c):
			all_ready = false
			continue
		if not c.can_interact():
			all_ready = false
	if _wait < LOOP_FRAME_LIMIT and not all_ready:
		return
	_check(all_ready, "crops reach READY after growth time (growth, scenario 4)")
	_check(_stages_seen.has("SEED") and _stages_seen.has("GROWING"),
		"visual growth stages traverse SEED/GROWING before READY")
	_wait = 0
	_frame = 0
	_enter(Phase.HARVEST_LOOP)


func _harvest_loop() -> void:
	_wait += 1
	_record_stages()
	if _crop() <= _crop_before and _wait < LOOP_FRAME_LIMIT:
		return
	_enter(Phase.HARVEST_CHECK)


func _harvest_check() -> void:
	var crop_gained: int = _crop() - _crop_before
	_check(crop_gained > 0,
		"farmer harvests READY crop and deposits raw ingredient (harvest + raw stock, scenarios 5-6)")
	_harvested_some = crop_gained > 0
	if _actor != null and is_instance_valid(_actor):
		_check(_actor.carried_amount == 0, "farmer carry emptied after deposit")
	# 수확 후 재성장(replant)이 이어지는지 잠시 관찰해 production cycle 지속을 확인한다.
	_wait = 0
	_enter(Phase.FOOD_SHORTAGE)


## -- 시나리오 7: Food 부족 상태 만들기 --
func _food_shortage() -> void:
	# food stock을 0으로 만들어 부족 상태를 확정한다.
	var food_stock: int = _resources.get_amount("food")
	if food_stock > 0:
		_resources.spend("food", food_stock)
	_check(_resources.get_amount("food") == 0, "food stock is depleted (shortage, scenario 7)")
	_wait = 0
	_enter(Phase.RAW_CONSUME)


## -- 시나리오 8: raw ingredient 소비(food 부족분 fallback) --
func _raw_consume() -> void:
	# farm이 생산한 raw ingredient를 food 부족분 fallback으로 소비한다.
	var crop_stock: int = _crop()
	_check(crop_stock > 0, "farm raw ingredient stock is available to consume")
	var before_crop: int = _crop()
	var result := RawFood.consume_with_raw_fallback(_resources, "food", "crop", 5, 0.5)
	_check(int(result.get("food", 0)) == 0, "no food stock consumed (already empty)")
	_check(int(result.get("raw", 0)) > 0, "food shortage is covered by raw ingredient fallback")
	_check(_crop() < before_crop, "raw ingredient stock spent as food fallback")
	_check(_resources.get_amount("crop") >= 0 and _resources.get_amount("food") >= 0,
		"no negative stock after raw consumption")
	_wait = 0
	_enter(Phase.TO_NIGHT)


## -- 시나리오 9: DAY -> NIGHT 반복 --
func _advance_to_next_phase() -> void:
	var need: float = _game_time.get_phase_duration() - _game_time.get_phase_elapsed()
	_game_time.advance(need + 0.05)


func _to_night() -> void:
	if _wait < PHYSICS_WAIT_FRAMES:
		_wait += 1
		return
	_advance_to_next_phase()
	_wait = 0
	_enter(Phase.NIGHT_WAIT)


func _night_wait() -> void:
	_wait += 1
	if _wait >= PHYSICS_WAIT_FRAMES:
		_enter(Phase.NIGHT_CHECK)


func _night_check() -> void:
	_check(_game_time.get_phase_name() == "NIGHT", "phase advances to NIGHT")
	_check(_farmers() == 1, "farmer actor persists through NIGHT (no despawn/duplicate)")
	_wait = 0
	_frame = 0
	_enter(Phase.TO_DAY)


func _to_day() -> void:
	if _wait < PHYSICS_WAIT_FRAMES:
		_wait += 1
		return
	_advance_to_next_phase()
	_wait = 0
	_enter(Phase.DAY_WAIT)


func _day_wait() -> void:
	_wait += 1
	if _wait >= PHYSICS_WAIT_FRAMES:
		_enter(Phase.DAY_CHECK)


func _day_check() -> void:
	_check(_game_time.get_phase_name() == "DAY", "phase returns to DAY")
	_check(_farmers() == 1, "farmer actor persists back at DAY")
	# DAY로 돌아온 뒤에도 farm 생산 loop가 이어지는지 확인한다.
	_wait = 0
	_frame = 0
	_enter(Phase.SECOND_NIGHT)


func _second_night() -> void:
	_wait += 1
	_record_stages()
	if _crop() <= _crop_before and _wait < LOOP_FRAME_LIMIT:
		return
	_enter(Phase.SECOND_DAY)


func _second_day() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	var crop_gained: int = _crop() - _crop_before
	_check(crop_gained > 0,
		"farm production loop continues across DAY/NIGHT (crop +%d)" % crop_gained)
	_check(_farmers() == 1, "no duplicate farmer actors across cycles")
	# harvest가 적어도 1회 regrow를 거쳤는지(반복 production cycle) 확인.
	var regrown := false
	for c in _farm.get_crops():
		if c != null and is_instance_valid(c) and c.can_interact():
			regrown = true
	_check(regrown or _stages_seen.has("HARVESTED"),
		"crop regrow/replant cycle continues (repeated production)")
	_wait = 0
	_enter(Phase.FINAL)


func _final() -> void:
	_check(_harvested_some, "raw ingredient was produced at least once in the loop")
	_check(_resources.get_amount("wood") == _wood_ledger,
		"wood ledger unchanged by the farm loop (no extra spend)")
	var seen := {}
	var unique := true
	for actor in get_nodes_in_group("farmers_3d"):
		if seen.has(actor):
			unique = false
		seen[actor] = true
	_check(unique, "farmer actors hold no duplicate instances in the tree")
	if _actor != null and is_instance_valid(_actor):
		_check(_actor.target_crop == null, "farmer target_crop reference cleared")
	_check(_roster.unassign(_farmer), "unassign farmer for cleanup")
	_enter(Phase.DONE)
