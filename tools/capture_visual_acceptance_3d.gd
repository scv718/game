extends SceneTree

## TASK-3D-INT-002-3 Visual Acceptance 필수 스크린샷 캡처.
## 프로젝트 main scene(main_3d.tscn)을 실제 Runtime으로 부팅하고, 태스크가 요구하는
## 7장을 실제 화면에서 남긴다(capture_village_composition_3d 관례).
##
##   1. day_overview        - DAY 마을 전체 overview(핵심 건물 5종 + Lumberyard/Quarry)
##   2. day_worker_zoom     - DAY 벌목꾼 작업 zoom-in(GATHER 상태 확인 후 촬영)
##   3. forest_resource     - Starter Forest 자원 지역
##   4. lumberyard_quarry   - Lumberyard/Quarry 생산 시설 2종 한 프레임
##   5. building_placement  - 건설 mode ghost(valid 초록 + work radius 링) 프리뷰
##   6. night_tactical      - NIGHT tactical overview(접근 중인 encounter + 배치된 용병)
##   7. night_combat        - NIGHT 자동전투(용병 vs raider 교전 순간)
##
## 스테이징 원칙(과장 금지):
## - 게임 진행은 task3dint0021 회귀와 동일한 실제 입력 경로(build mode click /
##   주점·여관 UI button pressed / GameTime phase 경계 advance)만 사용한다.
## - 지면 톤은 VIS-001-5 소유 공개 API VillageComposition3D.apply_ground_tone을
##   scene 조립 없이 script 객체로 호출해 입힌다(INTEGRATION_NOTE_VIS §4가 허용한
##   캡처 경로 사용). 실제 terrain 교체는 VIS-002 소유로 아직 open 되어 있으며
##   이 점은 acceptance report에 blocker 기록으로 남긴다.
## - 액터/건물/조명/HUD는 프로덕션 그대로다. 별도 visual 주입/교체는 하지 않는다.
##
## 캡처는 실제 렌더가 필요하므로 --headless 없이 실행한다(headless는 dummy
## rasterizer라 get_texture가 null이다. 기존 캡처 도구와 동일한 실행 조건).
##
## Example:
## Godot --path . --script res://tools/capture_visual_acceptance_3d.gd

enum Phase {
	SETUP, BOOT, BUILD_YARD, BUILD_QUARRY, HIRE_WORKERS, HIRE_MERC,
	WORK_WARMUP, SHOT_DAY_OVERVIEW, WAIT_GATHER, SHOT_WORKER_ZOOM,
	SHOT_FOREST, SHOT_YARD_QUARRY, ENTER_PLACEMENT_MODE, SHOT_PLACEMENT,
	EXIT_PLACEMENT, TO_NIGHT, NIGHT_APPROACH, SHOT_NIGHT_OVERVIEW,
	ENGAGE_WAIT, SHOT_COMBAT, DONE,
}

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const GAME_TIME_SCRIPT_PATH := "res://scripts/game_time.gd"
const MERC_DATA_SCRIPT_PATH := "res://scripts/mercenary_data.gd"
const VILLAGE_COMPOSITION_SCRIPT_PATH := "res://scripts/village_composition_3d.gd"
const LUMBERJACK_SCRIPT_PATH := "res://scripts/lumberjack_3d.gd"

## 태스크 필수 screenshot 목록(단일 소스). task3dint0023 테스트가 이 계약을 감사한다.
const SHOTS := {
	"day_overview": "res://test_results/visual_acceptance_day_overview.png",
	"day_worker_zoom": "res://test_results/visual_acceptance_day_worker_zoom.png",
	"forest_resource": "res://test_results/visual_acceptance_forest_resource.png",
	"lumberyard_quarry": "res://test_results/visual_acceptance_lumberyard_quarry.png",
	"building_placement": "res://test_results/visual_acceptance_building_placement.png",
	"night_tactical": "res://test_results/visual_acceptance_night_tactical.png",
	"night_combat": "res://test_results/visual_acceptance_night_combat.png",
}

const PX := WorldCoords3D.PX_TO_UNIT
const SETTLE_FRAMES := 8
const AIM_SETTLE_FRAMES := 6

## 배치 좌표(task3dint0021 회귀와 동일한 검증된 cell).
const YARD_SPOT := Vector3(32, 0, 30)
const DEPOSIT_SPOT := Vector3(75, 0, 37.5)
## placement ghost 프레임: clearing 남쪽 빈 땅(건물/자원 overlap 없음).
const PLACEMENT_SPOT := Vector3(10, 0, 55)

## 고정 프레임(pivot, ortho size). 전체 구성이 읽히는 값으로 직접 설정한다
## (gameplay zoom clamp와 무관하게 캡처 동안만 직접 적용 - 기존 캡처 도구 관례).
const DAY_OVERVIEW_PIVOT := Vector3(10, 0, 4)
const DAY_OVERVIEW_SIZE := 56.0
const FOREST_PIVOT := Vector3(-65, 0, -52.5)
const FOREST_SIZE := 34.0
const YARD_QUARRY_PIVOT := Vector3(54, 0, 34)
const YARD_QUARRY_SIZE := 48.0
const PLACEMENT_SIZE := 28.0
## NIGHT tactical overview는 서 접근 corridor(적 spawn)와 마을 core를 한 프레임에
## 보이게 한다("방어 공간이 읽히는가" 판단 자료).
const NIGHT_OVERVIEW_PIVOT := Vector3(-82, 0, 0)
const NIGHT_OVERVIEW_SIZE := 118.0
const WORKER_ZOOM_SIZE := 10.0
const COMBAT_ZOOM_SIZE := 13.0

## 조건 폴링 예산(physics tick 기준 - WRK 노트의 headless/frame 규약).
const POLL_GATHER := 2400
const POLL_NIGHT_APPROACH := 900
const POLL_ENGAGE_HARD := 2700
const FOCUS_FALLBACK_TICK := 900
const ENGAGE_SHOT_DISTANCE := 4.5
const COMBAT_SHOT_DELAY_FRAMES := 8

var _frame := 0
var _wait := 0
var _aim_wait := -1
var _gather_state := -1
var _phase: Phase = Phase.SETUP
var _start_msec := 0
var _poll_start_pf := -1
var _combat_shot_countdown := -1
var _diag_step := -1
var _focus_issued := false

var _game_time: Node = null
var _resources: Node = null
var _main: Node = null
var _world: Node = null
var _cam_ctl: Node = null
var _camera: Camera3D = null
var _placement: Node = null
var _roster_3d: Node = null
var _tavern_ui: Node = null
var _inn_ui: Node = null
var _saved := {}


func _initialize() -> void:
	_start_msec = Time.get_ticks_msec()


func _poll_budget_exhausted(budget_ticks: int) -> bool:
	var now := Engine.get_physics_frames()
	if _poll_start_pf < 0:
		_poll_start_pf = now
	return int(now - _poll_start_pf) >= budget_ticks


func _enter(p: Phase) -> void:
	_phase = p
	_wait = 0
	_poll_start_pf = -1
	_diag_step = -1
	_focus_issued = false


func _aim(pivot: Vector3, ortho_size: float) -> void:
	# zoom lerp(_process)가 clamp 범위로 되돌리므로 캡처 내내 정지시키고
	# 원하는 size를 직접 적용한다(gameplay camera 정책 무수정).
	_cam_ctl.set_process(false)
	_cam_ctl.position = Vector3(pivot.x, WorldCoords3D.GROUND_Y, pivot.z)
	_camera.size = ortho_size


func _pan_for(world_pos: Vector3) -> void:
	# pan_camera는 상대 offset 계약(INT-001-2 노트 규약).
	_cam_ctl.pan_camera(WorldCoords3D.flatten(world_pos) - _cam_ctl.position)


func _save(key: String) -> void:
	var path: String = SHOTS[key]
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var image := root.get_texture().get_image()
	var error := image.save_png(absolute)
	if error != OK:
		push_error("screenshot save failed(%s): %d" % [key, error])
		quit(1)
		return
	_saved[key] = true
	print("CAPTURED " + absolute + " size=" + str(image.get_size()))


func _screen_pos_of(world_pos: Vector3) -> Vector2:
	return _camera.unproject_position(world_pos)


func _push_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	root.push_input(event)


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


func _advance_to_next_phase() -> void:
	# phase 경계까지 정확히(int0021 규약: carry로 다음 전환 skip 방지).
	var need: float = _game_time.get_phase_duration() \
			- _game_time.get_phase_elapsed()
	_game_time.advance(need + 0.05)


func _lumberjacks() -> Array:
	return get_nodes_in_group("lumberjacks_3d")


func _enemies() -> Array:
	return get_nodes_in_group("enemies_3d")


func _nearest_enemy_to(pos: Vector3) -> Node:
	var best: Node = null
	var best_dist := INF
	for enemy in _enemies():
		if not is_instance_valid(enemy) or enemy.get("alive") == false:
			continue
		var d: float = WorldCoords3D.distance_xz(enemy.global_position, pos)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


func _finish(complete: bool) -> void:
	print("CAPTURED_COUNT=%d/%d" % [_saved.size(), SHOTS.size()])
	print("VISUAL_ACCEPTANCE_CAPTURE=" + ("COMPLETE" if complete else "INCOMPLETE"))
	quit(0 if complete else 1)


func _process(_delta: float) -> bool:
	_frame += 1
	if Time.get_ticks_msec() - _start_msec > 300000:
		push_error("capture watchdog timeout at phase %s" % str(_phase))
		_finish(false)
		return true
	match _phase:
		Phase.SETUP:
			_phase_setup()
		Phase.BOOT:
			_phase_boot()
		Phase.BUILD_YARD:
			_phase_build_yard()
		Phase.BUILD_QUARRY:
			_phase_build_quarry()
		Phase.HIRE_WORKERS:
			_phase_hire_workers()
		Phase.HIRE_MERC:
			_phase_hire_merc()
		Phase.WORK_WARMUP:
			_phase_work_warmup()
		Phase.SHOT_DAY_OVERVIEW:
			_phase_shot_day_overview()
		Phase.WAIT_GATHER:
			_phase_wait_gather()
		Phase.SHOT_WORKER_ZOOM:
			_phase_shot_worker_zoom()
		Phase.SHOT_FOREST:
			_phase_shot_forest()
		Phase.SHOT_YARD_QUARRY:
			_phase_shot_yard_quarry()
		Phase.ENTER_PLACEMENT_MODE:
			_phase_enter_placement()
		Phase.SHOT_PLACEMENT:
			_phase_shot_placement()
		Phase.EXIT_PLACEMENT:
			_phase_exit_placement()
		Phase.TO_NIGHT:
			_phase_to_night()
		Phase.NIGHT_APPROACH:
			_phase_night_approach()
		Phase.SHOT_NIGHT_OVERVIEW:
			_phase_shot_night_overview()
		Phase.ENGAGE_WAIT:
			_phase_engage_wait()
		Phase.SHOT_COMBAT:
			_phase_shot_combat()
		Phase.DONE:
			_finish(_saved.size() == SHOTS.size())
			return true
	return false


func _phase_setup() -> void:
	if _frame < SETTLE_FRAMES:
		return
	root.size = Vector2i(1152, 648)
	_game_time = root.get_node_or_null("GameTime")
	_resources = root.get_node_or_null("VillageResources")
	if _game_time == null or _resources == null:
		push_error("shared autoloads missing")
		_finish(false)
		return
	_game_time.set_auto_advance(false)
	_enter(Phase.BOOT)


func _phase_boot() -> void:
	if _wait == 0:
		var packed: PackedScene = load(MAIN_SCENE_PATH)
		_main = packed.instantiate()
		_main.name = "Main3D"
		root.add_child(_main)
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_world = root.get_node_or_null("Main3D/World3D")
	_cam_ctl = get_first_node_in_group("camera_controller_3d")
	_camera = _cam_ctl.get_camera() if _cam_ctl != null else null
	_placement = get_first_node_in_group("building_placement_3d")
	_roster_3d = _main.get_node_or_null("MercenaryRoster3D")
	_tavern_ui = get_first_node_in_group("recruitment_ui")
	_inn_ui = get_first_node_in_group("inn_roster_ui")
	if _world == null or _cam_ctl == null or _camera == null \
			or _placement == null or _tavern_ui == null or _inn_ui == null:
		push_error("main runtime wiring incomplete")
		_finish(false)
		return
	# VIS-001-5 공개 API로 placeholder GroundVisual에 stylized 잔디 톤.
	# village_composition scene 자체는 조립하지 않는다(프로덕션 runtime 구성 유지).
	var composition: Node = (load(VILLAGE_COMPOSITION_SCRIPT_PATH) as GDScript).new()
	var toned: bool = composition.apply_ground_tone(_world)
	composition.free()
	if not toned:
		push_error("apply_ground_tone found no GroundVisual")
	print("BOOT_OK trees=%d deposit=%s" % [
		get_nodes_in_group("resource_nodes_3d").size(),
		str(get_nodes_in_group("stone_deposits_3d").size()),
	])
	_enter(Phase.BUILD_YARD)


func _phase_build_yard() -> void:
	if _wait == 0:
		_resources.add("wood", 80)
		_pan_for(YARD_SPOT)
		_push_key(KEY_1)
		_push_key(KEY_B)
		_push_left_click(_screen_pos_of(YARD_SPOT))
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	if get_nodes_in_group("lumberyards").size() != 1:
		push_error("lumberyard placement via input path failed")
		_finish(false)
		return
	print("PLACED lumberyard at %s" % str(
		get_nodes_in_group("lumberyards")[0].global_position))
	_enter(Phase.BUILD_QUARRY)


func _phase_build_quarry() -> void:
	if _wait == 0:
		_pan_for(DEPOSIT_SPOT)
		_push_key(KEY_2)
		_push_key(KEY_B)
		_push_left_click(_screen_pos_of(DEPOSIT_SPOT))
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	if get_nodes_in_group("quarries").size() != 1:
		push_error("quarry placement via input path failed")
		_finish(false)
		return
	print("PLACED quarry at %s" % str(
		get_nodes_in_group("quarries")[0].global_position))
	_enter(Phase.HIRE_WORKERS)


func _phase_hire_workers() -> void:
	if _wait == 0:
		_tavern_ui.open()
		_tavern_ui._hire_buttons["lumberjack_A"].pressed.emit()
		_tavern_ui._hire_buttons["lumberjack_B"].pressed.emit()
		_tavern_ui._hire_buttons["miner_A"].pressed.emit()
		_tavern_ui._hire_buttons["miner_B"].pressed.emit()
		_tavern_ui.close()
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_enter(Phase.HIRE_MERC)


func _phase_hire_merc() -> void:
	if _wait == 0:
		# open/close는 visible 토글 직접 호출이라 같은 프레임 순차 수행이 안전하다.
		_inn_ui.open()
		_inn_ui._assign_buttons["lumberjack_A"].pressed.emit()
		_inn_ui._assign_buttons["lumberjack_B"].pressed.emit()
		_inn_ui._assign_buttons["miner_A"].pressed.emit()
		_inn_ui._assign_buttons["miner_B"].pressed.emit()
		_inn_ui.close()
		var west_zone: int = (load(MERC_DATA_SCRIPT_PATH) as Script).DefenseZone.WEST
		_tavern_ui.open()
		_tavern_ui._mercenary_hire_buttons["mercenary_A"].pressed.emit()
		_tavern_ui.close()
		var merc = _roster_3d.get_mercenary("mercenary_A")
		if merc == null:
			push_error("mercenary hire failed")
			_finish(false)
			return
		_inn_ui.open()
		_inn_ui._on_defense_zone_pressed(merc, west_zone)
		_inn_ui.close()
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	print("HIRED workers=4 mercenary=1(zone=WEST) actors=%d" %
		get_nodes_in_group("workers_3d").size())
	_enter(Phase.WORK_WARMUP)


func _phase_work_warmup() -> void:
	# Worker들이 작업지에 도착해 생산 loop에 안정 진입할 때까지 대기.
	if _resources.get_amount("wood") >= 74 \
			or _poll_budget_exhausted(POLL_GATHER):
		_enter(Phase.SHOT_DAY_OVERVIEW)


func _phase_shot_day_overview() -> void:
	if _aim_wait < 0:
		_aim(DAY_OVERVIEW_PIVOT, DAY_OVERVIEW_SIZE)
		_aim_wait = 0
		return
	_aim_wait += 1
	if _aim_wait < AIM_SETTLE_FRAMES:
		return
	_save("day_overview")
	_aim_wait = -1
	_enter(Phase.WAIT_GATHER)


func _resolve_gather_state() -> int:
	# -s 기동 초기 autoload 미등록 컴파일 단계 규약(INT-001-2/CMB-001-2 동일):
	# Lumberjack3D 식별자를 직접 쓰면 tool 로드 시점에 의존 스크립트가 먼저
	# 컴파일되어 실패한다. enum은 runtime load로 해석한다.
	if _gather_state < 0:
		var states: Dictionary = (load(LUMBERJACK_SCRIPT_PATH) as Script).get("State")
		_gather_state = int(states.get("GATHER", -1))
	return _gather_state


func _phase_wait_gather() -> void:
	# zoom-in 컷은 벌목꾼이 실제 나무에서 GATHER 중인 순간을 잡는다.
	var gather := _resolve_gather_state()
	for jack in _lumberjacks():
		if is_instance_valid(jack) and jack.get("state") == gather:
			_enter(Phase.SHOT_WORKER_ZOOM)
			return
	if _poll_budget_exhausted(POLL_GATHER):
		print("WARN gather state not observed; shooting worker zoom anyway")
		_enter(Phase.SHOT_WORKER_ZOOM)


func _nearest_tree_to(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for tree in get_nodes_in_group("resource_nodes_3d"):
		if not is_instance_valid(tree):
			continue
		var d: float = WorldCoords3D.distance_xz(tree.global_position, pos)
		if d < best_dist:
			best_dist = d
			best = tree
	return best


func _phase_shot_worker_zoom() -> void:
	if _aim_wait < 0:
		var gather := _resolve_gather_state()
		var focus: Node3D = null
		for jack in _lumberjacks():
			if is_instance_valid(jack) and jack.get("state") == gather:
				focus = jack
				break
		if focus == null:
			focus = _lumberjacks()[0] if not _lumberjacks().is_empty() else null
		if focus == null:
			push_error("no live worker for zoom shot")
			_finish(false)
			return
		# 작업자와 대상 나무가 함께 읽히도록 중간점을 프레임한다.
		var pivot := Vector3(focus.global_position.x, 0, focus.global_position.z)
		var tree := _nearest_tree_to(focus.global_position)
		if tree != null and WorldCoords3D.distance_xz(
				tree.global_position, focus.global_position) < WORKER_ZOOM_SIZE:
			var mid: Vector3 = (focus.global_position + tree.global_position) * 0.5
			pivot = Vector3(mid.x, 0, mid.z)
		_aim(pivot, WORKER_ZOOM_SIZE)
		_aim_wait = 0
		return
	_aim_wait += 1
	if _aim_wait < AIM_SETTLE_FRAMES:
		return
	_save("day_worker_zoom")
	_aim_wait = -1
	_enter(Phase.SHOT_FOREST)


func _phase_shot_forest() -> void:
	if _aim_wait < 0:
		_aim(FOREST_PIVOT, FOREST_SIZE)
		_aim_wait = 0
		return
	_aim_wait += 1
	if _aim_wait < AIM_SETTLE_FRAMES:
		return
	_save("forest_resource")
	_aim_wait = -1
	_enter(Phase.SHOT_YARD_QUARRY)


func _phase_shot_yard_quarry() -> void:
	if _aim_wait < 0:
		_aim(YARD_QUARRY_PIVOT, YARD_QUARRY_SIZE)
		_aim_wait = 0
		return
	_aim_wait += 1
	if _aim_wait < AIM_SETTLE_FRAMES:
		return
	_save("lumberyard_quarry")
	_aim_wait = -1
	_enter(Phase.ENTER_PLACEMENT_MODE)


func _phase_enter_placement() -> void:
	if _wait == 0:
		_pan_for(PLACEMENT_SPOT)
		_push_key(KEY_1)
		_push_key(KEY_B)
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	if not _placement.is_active():
		push_error("build mode did not activate for placement shot")
		_finish(false)
		return
	# motion event로 마지막 mouse 좌표를 갱신하면 ghost _process가 해당 지면
	# 교차점을 따라온다(유효 cell = 초록 + work radius 링).
	_push_motion(_screen_pos_of(PLACEMENT_SPOT))
	_enter(Phase.SHOT_PLACEMENT)


func _phase_shot_placement() -> void:
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	if _aim_wait < 0:
		_aim(PLACEMENT_SPOT, PLACEMENT_SIZE)
		_aim_wait = 0
		return
	_aim_wait += 1
	if _aim_wait < AIM_SETTLE_FRAMES:
		return
	_save("building_placement")
	_aim_wait = -1
	_enter(Phase.EXIT_PLACEMENT)


func _phase_exit_placement() -> void:
	if _wait == 0:
		_push_key(KEY_ESCAPE)
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	if _placement.is_active():
		push_error("build mode did not exit after ESC")
		_finish(false)
		return
	_enter(Phase.TO_NIGHT)


func _phase_to_night() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_advance_to_next_phase()
	_enter(Phase.NIGHT_APPROACH)


func _phase_night_approach() -> void:
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	if _game_time.get_phase_name() != "NIGHT":
		push_error("phase did not reach NIGHT")
		_finish(false)
		return
	if _enemies().is_empty():
		if _poll_budget_exhausted(POLL_NIGHT_APPROACH):
			push_error("NIGHT encounter did not spawn")
			_finish(false)
		return
	# 서쪽 corridor 어느 정도 진입한 시점의 tactical overview.
	var min_x := INF
	for enemy in _enemies():
		min_x = minf(min_x, enemy.global_position.x)
	if min_x >= -150.0 or _poll_budget_exhausted(POLL_NIGHT_APPROACH):
		print("NIGHT enemies=%d min_x=%.1f" % [_enemies().size(), min_x])
		_enter(Phase.SHOT_NIGHT_OVERVIEW)


func _phase_shot_night_overview() -> void:
	if _aim_wait < 0:
		_aim(NIGHT_OVERVIEW_PIVOT, NIGHT_OVERVIEW_SIZE)
		_aim_wait = 0
		return
	_aim_wait += 1
	if _aim_wait < AIM_SETTLE_FRAMES:
		return
	_save("night_tactical")
	_aim_wait = -1
	_enter(Phase.ENGAGE_WAIT)


func _phase_engage_wait() -> void:
	var merc_actor: Node = _roster_3d.get_actor("mercenary_A")
	if merc_actor == null or not is_instance_valid(merc_actor):
		if _poll_budget_exhausted(POLL_ENGAGE_HARD):
			push_error("mercenary actor missing for combat shot")
			_finish(false)
		return
	var nearest := _nearest_enemy_to(merc_actor.global_position)
	if nearest == null:
		# 전투가 이미 끝났으면 현재 NIGHT 장면이라도 남긴다.
		print("WARN all enemies resolved before combat shot")
		_enter(Phase.SHOT_COMBAT)
		return
	var distance: float = WorldCoords3D.distance_xz(
		nearest.global_position, merc_actor.global_position)
	var wounded: bool = nearest.get("current_hp") != null \
		and nearest.current_hp < nearest.max_hp
	if _poll_start_pf < 0:
		_poll_start_pf = Engine.get_physics_frames()
	var polled := int(Engine.get_physics_frames() - _poll_start_pf)
	if polled / 300 > _diag_step:
		_diag_step = polled / 300
		print("DIAG t=%d dist=%.1f merc=%s/%s enemy_hp=%d/%d alive=%d" % [
			polled, distance,
			str(merc_actor.global_position), str(nearest.global_position),
			nearest.current_hp, nearest.max_hp, _enemies().size(),
		])
	if distance <= ENGAGE_SHOT_DISTANCE or wounded:
		_combat_shot_countdown = COMBAT_SHOT_DELAY_FRAMES
		_enter(Phase.SHOT_COMBAT)
		return
	if polled >= FOCUS_FALLBACK_TICK and not _focus_issued:
		# 집중 공격 명령으로 강제 교전(실제 tactical command 경로). 1회만 발행 -
		# 매 프레임 재발행은 merc 추적 상태를 계속 리셋시킨다.
		_focus_issued = true
		_roster_3d.set_focus_target(nearest)
		print("FOCUS fallback issued")
	elif _poll_budget_exhausted(POLL_ENGAGE_HARD):
		print("WARN engagement not observed within budget; shooting night scene")
		_enter(Phase.SHOT_COMBAT)


func _phase_shot_combat() -> void:
	if _combat_shot_countdown > 0:
		_combat_shot_countdown -= 1
		return
	if _combat_shot_countdown == 0:
		var merc_actor: Node = _roster_3d.get_actor("mercenary_A")
		var pivot := NIGHT_OVERVIEW_PIVOT
		if merc_actor != null and is_instance_valid(merc_actor):
			var nearest := _nearest_enemy_to(merc_actor.global_position)
			if nearest != null:
				var mid: Vector3 = (merc_actor.global_position \
					+ nearest.global_position) * 0.5
				pivot = Vector3(mid.x, 0, mid.z)
		_aim(pivot, COMBAT_ZOOM_SIZE)
		_combat_shot_countdown = -AIM_SETTLE_FRAMES
		return
	# countdown 음수 구간 = aim settle 대기.
	_combat_shot_countdown += 1
	if _combat_shot_countdown < 0:
		return
	_save("night_combat")
	_enter(Phase.DONE)
