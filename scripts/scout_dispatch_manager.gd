extends Node
class_name ScoutDispatchManager

## TASK-026-4 Scout Dispatch / Region Discovery wiring owner.
## World Map의 UNKNOWN Region에서 Scout/Expedition을 파견하고, expedition이
## EXPLORING 구간을 완료하면 해당 Region/POI를 DISCOVERED로 처리한다.
##
## 역할 분리:
## - ExpeditionPartyData/ExpeditionManager(TASK-026-2/3): expedition 편성/시간 진행 owner.
## - ExplorationManager/ExplorationRegion(TASK-EXP-001): region 발견 상태의 authoritative
##   owner이며 discovery state/signal을 보유. WorldMap overlay가 이미 해당 signal을 구독.
## - 본 매니저: dispatch 시작(gate)과 expedition phase event → region 상태 변환 즉
##   "어느 때 파견하고, 탐사 완료 시 region을 DISCOVERED 처리할지"만 담당한다.
##
## 진행 흐름:
##   dispatch_scout() 성공 → ExplorationManager.register_expedition_dispatch()
##     → region UNKNOWN→EXPLORING → advance()로 expedition 진행
##     → expedition EXPLORING→RETURNING 전환 시 complete_expedition_discovery()
##     → region EXPLORING→DISCOVERED + 고정 발견 결과(NE Dungeon Candidate feature).
##
## 제약:
## - UNKNOWN region만 파견 가능. EXPLORING/DISCOVERED region 파견은 거부(duplicate
##   dispatch 차단).
## - Player가 파견 위치로 직접 이동하지 않는다(Runtime Actor 없음, 데이터만 처리).
## - random event framework / Dungeon instance 실행 / Scout Actor 직접 조작 없음.
## - 진행도는 ExpeditionManager에 위임하며 Progress는 region에 동기화해
##   WorldMap overlay의 EXPLORING arc/라벨이 그대로 동작하게 한다.
## autoload 등록 여부는 TASK-026-6 통합에서 결정하므로 이 파일은 project.godot을
## 건드리지 않는다(테스트/호출 측에서 트리에 넣어 사용).

signal scout_dispatched(expedition_id: String, region_id: String)
## ExplorationManager가 region DISCOVERED로 전환한 직후 동일 이벤트의 relay.
## overlay는 ExplorationManager.{exploration_started,region_discovered}를 구독하므로
## 중복 갱신이 없으며, ScoutDispatchManager 단독 구독 측용으로 제공한다.
signal region_discovered(region_id: String)

var _expeditions: ExpeditionManager = null
var _exploration: Node = null
## expedition_id → destination region_id. Node reference 대신 String 데이터로만 보관.
var _region_targets: Dictionary = {}
var _auto_advance := true
var _dispatch_seq := 0
var _last_error := ""


func _ready() -> void:
	add_to_group("scout_dispatch_manager")
	if _expeditions == null:
		_expeditions = ExpeditionManager.new()
		_expeditions.name = "ExpeditionManager"
		add_child(_expeditions)
	# 진행 gate는 본 매니저 하나로 통합한다(테스트에서 set_auto_advance(false)로
	# 결정적 제어). child ExpeditionManager는 _process로 독립 진행하지 않는다.
	_expeditions.set_auto_advance(false)
	_expeditions.expedition_phase_changed.connect(_on_expedition_phase_changed)
	_resolve_exploration()


func _process(delta: float) -> void:
	if _auto_advance:
		advance(delta)


## 테스트/특수 상황에서 자동 진행을 끄고 advance()로 직접 제어할 수 있다.
func set_auto_advance(enabled: bool) -> void:
	_auto_advance = enabled


## Expedition 진행 owner 조회(테스트/호출 측 편의).
func get_expedition_manager() -> ExpeditionManager:
	return _expeditions


## 파견 가능 여부. UNKNOWN region이고 해당 region으로 진행 중 expedition이 없어야 한다
## (active EXPLORING region의 duplicate dispatch 차단).
func can_dispatch(region_id: String) -> bool:
	if region_id.is_empty() or _expeditions == null:
		return false
	_resolve_exploration()
	if _exploration == null:
		return false
	var region: ExplorationRegion = _exploration.get_region(region_id)
	if region == null:
		return false
	if region.get_discovery_state() != ExplorationRegion.DiscoveryState.UNKNOWN:
		return false
	return not _has_active_expedition_to(region_id)


## 마지막 dispatch 실패 사유(디버깅/검증용). 성공 시 빈 문자열.
func get_dispatch_error() -> String:
	return _last_error


## 해당 region으로 파견된 진행 중 expedition을 조회한다. 없으면 null.
func find_expedition_for_region(region_id: String) -> ExpeditionPartyData:
	if _expeditions == null:
		return null
	for exp in _expeditions.get_active_expeditions():
		if exp.destination_region_id == region_id:
			return exp
	return null


## UNKNOWN Region에 Scout/Expedition을 파견한다.
## member_ids: 편성 member identity id 목록(String). 비어 있으면 roster의 살아 있는
## 용병 전체를 자동 편성한다. expedition_id가 비어 있으면 "scout_<region>_<seq>"로 생성.
## 성공 시 region이 EXPLORING으로 전환되고 true. 실패 사유는 get_dispatch_error().
func dispatch_scout(region_id: String, member_ids: Array = [],
		p_expedition_id: String = "") -> bool:
	_last_error = ""
	if not can_dispatch(region_id):
		_last_error = "region is not UNKNOWN or already being scouted"
		return false
	var ids := _resolve_member_ids(member_ids)
	if ids.is_empty():
		_last_error = "no available mercenary members to dispatch"
		return false
	var expedition_id := p_expedition_id
	if expedition_id.is_empty():
		_dispatch_seq += 1
		expedition_id = "scout_%s_%d" % [region_id, _dispatch_seq]
	if _expeditions.has_expedition(expedition_id):
		_last_error = "expedition_id already exists: " + expedition_id
		return false
	var exp := _expeditions.create_expedition(expedition_id, region_id)
	if exp == null:
		_last_error = "expedition creation failed"
		return false
	for mid in ids:
		if not _expeditions.add_member(expedition_id, mid):
			_expeditions.remove_expedition(expedition_id)
			_last_error = "member unavailable (already dispatched/dead): " + mid
			return false
	if not _expeditions.start_departure(expedition_id, _current_game_day(),
			_current_game_seconds(), _get_roster()):
		_expeditions.remove_expedition(expedition_id)
		_last_error = "departure validation failed (member dead/unavailable)"
		return false
	if _exploration == null or not _exploration.register_expedition_dispatch(
			region_id, expedition_id):
		_last_error = "region dispatch registration failed"
		return false
	_region_targets[expedition_id] = region_id
	_sync_region_progress()
	scout_dispatched.emit(expedition_id, region_id)
	return true


## Expedition 시간 진행. GameTime 배율 기반 진행은 ExpeditionManager에 위임하고,
## 완료 시 region 동기화/발견 처리는 phase signal로 처리한다.
func advance(seconds: float) -> void:
	if _expeditions == null:
		return
	_expeditions.advance(seconds)
	_sync_region_progress()


## expedition이 EXPLORING 구간을 마치고 RETURNING으로 넘어가는 시점(탐사 완료)에
## region을 DISCOVERED로 전환한다. 각 전환은 정확히 1회만 처리된다.
func _on_expedition_phase_changed(expedition_id: String, from_status: int,
		to_status: int) -> void:
	if from_status != ExpeditionPartyData.Status.EXPLORING:
		return
	if to_status != ExpeditionPartyData.Status.RETURNING:
		return
	var region_id := str(_region_targets.get(expedition_id, ""))
	if region_id.is_empty():
		return
	if _exploration != null and _exploration.has_method("complete_expedition_discovery"):
		if _exploration.complete_expedition_discovery(region_id):
			region_discovered.emit(region_id)


## dispatch 진행도를 region 진행도로 동기화해 WorldMap overlay의 EXPLORING 진행도
## 표시가 expedition과 일치하게 한다. region state 자체는 ExplorationManager가 소유한다.
func _sync_region_progress() -> void:
	if _exploration == null or not _exploration.has_method("set_progress"):
		return
	for exp in _expeditions.get_expeditions():
		var region_id := str(_region_targets.get(exp.expedition_id, ""))
		if region_id.is_empty():
			continue
		var p := 0.0
		match exp.status:
			ExpeditionPartyData.Status.EXPLORING:
				p = exp.progress
			ExpeditionPartyData.Status.RETURNING, ExpeditionPartyData.Status.COMPLETED:
				p = 1.0
		_exploration.set_progress(region_id, p)


## member_ids가 비어 있으면 roster의 살아 있는 용병 전체를 자동 편성한다.
func _resolve_member_ids(member_ids: Array) -> Array:
	if member_ids.size() > 0:
		return member_ids
	var roster := _get_roster()
	if roster == null or not roster.has_method("get_alive"):
		return []
	var out: Array = []
	for m in roster.get_alive():
		out.append(m.id)
	return out


## 해당 region으로 active(진행 중) expedition이 이미 있는지(복수 파견 방지 backup).
func _has_active_expedition_to(region_id: String) -> bool:
	for exp in _expeditions.get_active_expeditions():
		if exp.destination_region_id == region_id:
			return true
	return false


func _resolve_exploration() -> void:
	if _exploration != null and is_instance_valid(_exploration):
		return
	var tree := get_tree()
	if tree == null:
		return
	_exploration = tree.root.get_node_or_null("ExplorationManager")


func _get_roster() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("MercenaryRoster")


func _current_game_day() -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var gt := tree.root.get_node_or_null("GameTime")
	if gt == null or not gt.has_method("get_day_number"):
		return 0
	return int(gt.get_day_number())


func _current_game_seconds() -> float:
	var tree := get_tree()
	if tree == null:
		return 0.0
	var gt := tree.root.get_node_or_null("GameTime")
	if gt == null or not gt.has_method("get_phase_elapsed"):
		return 0.0
	return float(gt.get_phase_elapsed())
