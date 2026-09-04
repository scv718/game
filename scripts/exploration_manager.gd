extends Node

## TASK-EXP-001-2 최소 Exploration Action 매니저(autoload).
## World Map에서 선택한 탐사 Region을 GameTime 기준 진행도로 관리하고
## 완료 시 DISCOVERED로 전환하는 최소 vertical slice.
##
## - Player Avatar 없음. Map/Region UI(WorldMapOverlay)에서 start_exploration() 호출.
## - 진행도는 GameTime과 동일한 클럭을 따른다: advance()에 전달된 시간에
##   GameTime.get_time_scale()(전술 Pause/1x/2x)을 곱해 누적한다.
##   DAY/NIGHT phase 자체에는 의존하지 않으므로 phase 전환과 무관하게 일관된 정책으로
##   누적되며, 전환 시 리셋되지 않는다.
## - 발견 결과는 고정 deterministic 프로토타입이다(난수/외부 시스템 없음).
## - Scout roster / mercenary escort / supply / 실제 Dungeon 생성·진입은 구현하지 않는다.
##
## 진행도(_progress)는 런타임 상태이므로 ExplorationRegion 순수 데이터에 넣지 않고
## 여기서만 보관한다. 중복 시작은 상태 가드(UNKNOWN에서만 허용)로 차단한다.

signal exploration_started(region_id: String)
signal region_discovered(region_id: String)

## 프로토타입 기본 탐사 소요 시간(초). 밸런스 확정 값이 아니다.
const DEFAULT_EXPLORATION_DURATION := 45.0

var _regions: Dictionary = {}
var _progress: Dictionary = {}
var _auto_advance := true
## TASK-026-4: Scout/Expedition이 주도하는 region(region_id → expedition_id).
## 이 region은 진행도/완료 판정을 ScoutDispatch가 담당하므로 여기서 임의로
## DISCOVERED 처리하지 않기 위해 advance()에서 제외한다. 완료 시 지워진다.
var _expedition_driven: Dictionary = {}


func _ready() -> void:
	_register_prototype_regions()


func _process(delta: float) -> void:
	if _auto_advance:
		advance(delta)


## 테스트/특수 상황에서 자동 진행을 끄고 advance()로 직접 제어할 수 있다.
func set_auto_advance(enabled: bool) -> void:
	_auto_advance = enabled


func get_regions() -> Array:
	return _regions.values()


func get_region(region_id: String) -> ExplorationRegion:
	return _regions.get(region_id)


## 월드 좌표가 속한 region을 찾는다(Map click hit-test용). 없으면 null.
func get_region_at(world_pos: Vector2) -> ExplorationRegion:
	for region in _regions.values():
		if region.contains_world_position(world_pos):
			return region
	return null


func is_exploring(region_id: String) -> bool:
	var region: ExplorationRegion = _regions.get(region_id)
	return region != null \
		and region.get_discovery_state() == ExplorationRegion.DiscoveryState.EXPLORING


## 해당 region의 탐사 진행도(0.0~1.0).
func get_progress(region_id: String) -> float:
	return clampf(float(_progress.get(region_id, 0.0)), 0.0, 1.0)


func can_start_exploration(region_id: String) -> bool:
	var region: ExplorationRegion = _regions.get(region_id)
	return region != null \
		and region.get_discovery_state() == ExplorationRegion.DiscoveryState.UNKNOWN


## 탐사 시작. UNKNOWN 상태에서만 허용되며, 이미 EXPLORING/DISCOVERED면
## 중복 시작으로 거부하고 false를 반환한다.
func start_exploration(region_id: String) -> bool:
	if not can_start_exploration(region_id):
		return false
	var region: ExplorationRegion = _regions[region_id]
	_progress[region_id] = 0.0
	region.set_discovery_state(ExplorationRegion.DiscoveryState.EXPLORING)
	exploration_started.emit(region_id)
	return true


## TASK-026-4: ScoutDispatch가 파견한 region을 expedition-driven 탐사로 등록한다.
## UNKNOWN에서만 허용하며, region을 EXPLORING으로 전환하고 exploration_started를
## 발행해 WorldMap overlay가 즉시 갱신되게 한다. 이 region의 진행도/완료 판정은
## scout expedition이 주도하므로 _expedition_driven에 기록해 본 manager의 advance()가
## 임의로 DISCOVERED 처리하지 않게 한다. UNKNOWN이 아니면 false(duplicate dispatch 차단).
func register_expedition_dispatch(region_id: String, expedition_id: String) -> bool:
	if region_id.is_empty() or expedition_id.is_empty():
		return false
	var region: ExplorationRegion = _regions.get(region_id)
	if region == null \
			or region.get_discovery_state() != ExplorationRegion.DiscoveryState.UNKNOWN:
		return false
	if _expedition_driven.has(region_id):
		return false
	_expedition_driven[region_id] = expedition_id
	_progress[region_id] = 0.0
	region.set_discovery_state(ExplorationRegion.DiscoveryState.EXPLORING)
	exploration_started.emit(region_id)
	return true


## TASK-026-4: scout expedition이 EXPLORING 구간을 완료했을 때 호출한다. region을
## DISCOVERED로 전환하고 고정 deterministic 발견 결과를 적용하며 region_discovered를
## 정확히 1회 발행한다. 이미 처리된 region(EXPLORING 아님/미등록)은 거부해
## repeated complete로 인한 duplicate 신호를 방지한다.
func complete_expedition_discovery(region_id: String) -> bool:
	if not _expedition_driven.has(region_id):
		return false
	var region: ExplorationRegion = _regions.get(region_id)
	if region == null \
			or region.get_discovery_state() != ExplorationRegion.DiscoveryState.EXPLORING:
		return false
	_expedition_driven.erase(region_id)
	_progress[region_id] = 1.0
	region.set_discovery_state(ExplorationRegion.DiscoveryState.DISCOVERED)
	_apply_prototype_discovery_result(region)
	region_discovered.emit(region_id)
	return true


## TASK-026-4: 지정 region이 scout expedition이 주도하는 탐사인지.
func is_region_expedition_driven(region_id: String) -> bool:
	return _expedition_driven.has(region_id)


## TASK-026-4: 외부(ScoutDispatchManager)에서 expedition 진행도를 region 진행도로
## 동기화한다(0.0~1.0 clamp). WorldMap overlay의 EXPLORING 진행도 arc/라벨 표시용.
func set_progress(region_id: String, value: float) -> bool:
	if region_id.is_empty() or not _regions.has(region_id):
		return false
	_progress[region_id] = clampf(value, 0.0, 1.0)
	return true


## 탐사 시간을 진행한다. GameTime.advance와 대칭 구조로, 전술 시간 배율
## (GameTime.get_time_scale())을 곱해 적용한다. Pause(0)면 진행되지 않는다.
## 완료 조건 도달 시 DISCOVERED 전환과 고정 발견 결과 적용은 1회만 수행한다.
## TASK-026-4: ScoutDispatch가 파견한 region(_expedition_driven)은 이 manager의
## 진행(임의 DISCOVERED 처리)에서 제외하고, 진행도/완료를 scout expedition이
## 주도한다(advance 대신 ScoutDispatchManager가 set_progress로 동기화).
func advance(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var scaled := seconds * GameTime.get_time_scale()
	for region_id in _regions:
		if _expedition_driven.has(region_id):
			continue
		var region: ExplorationRegion = _regions[region_id]
		if not is_exploring(region_id):
			continue
		var duration := maxf(region.exploration_duration, 0.0001)
		_progress[region_id] = get_progress(region_id) + scaled / duration
		if _progress[region_id] >= 1.0:
			_complete_exploration(region)


func _complete_exploration(region: ExplorationRegion) -> void:
	if region.get_discovery_state() == ExplorationRegion.DiscoveryState.DISCOVERED:
		return
	_progress[region.region_id] = 1.0
	region.set_discovery_state(ExplorationRegion.DiscoveryState.DISCOVERED)
	_apply_prototype_discovery_result(region)
	region_discovered.emit(region.region_id)


## 발견 결과는 고정 deterministic 프로토타입. 실제 Dungeon 생성/진입 없이
## region 데이터에 고정 feature만 기록한다.
func _apply_prototype_discovery_result(region: ExplorationRegion) -> void:
	match region.region_id:
		"ne_dungeon":
			region.add_discovered_feature("dungeon_entrance")
			region.add_discovered_feature("safe_approach")


## 프로토타입 탐사 지역 등록. NE Dungeon Candidate 1개(기존 WorldMap marker 연결).
func _register_prototype_regions() -> void:
	var dungeon := ExplorationRegion.new("ne_dungeon")
	dungeon.display_name = "NE Dungeon"
	dungeon.world_position = WorldMap.NE_DUNGEON_CANDIDATE
	dungeon.region_bounds = Rect2(
		WorldMap.NE_DUNGEON_CANDIDATE - Vector2(90, 90), Vector2(180, 180))
	dungeon.source_marker_id = "NeDungeonCandidate"
	dungeon.exploration_duration = DEFAULT_EXPLORATION_DURATION
	dungeon.base_risk = 3
	_regions[dungeon.region_id] = dungeon

