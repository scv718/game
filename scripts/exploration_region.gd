extends RefCounted
class_name ExplorationRegion

## TASK-EXP-001-1 최소 ExplorationRegion Data Model.
## 월드 탐험 지역(NE Dungeon Candidate, resource region 등)의 발견/탐험 상태를
## Actor 생명주기와 독립된 순수 데이터로 보관하는 데이터 클래스.
## Node/Actor reference를 저장하지 않으며, WorldMap marker와의 연결은
## source_marker_id(String)로만 표현한다(예: "NeDungeonCandidate", "sparse_forest").
## 모든 필드는 기본 타입/Vector2/Rect2이므로 향후 Save/Load에 그대로 사용할 수 있다.
## 지역 간 관계/진행 규칙은 범용 QuestDatabase를 만들지 않고
## 이후 Exploration 전용 확장에서 다룬다.

enum DiscoveryState { UNKNOWN, EXPLORING, DISCOVERED }

const DISCOVERY_STATE_NAMES := {
	DiscoveryState.UNKNOWN: "UNKNOWN",
	DiscoveryState.EXPLORING: "EXPLORING",
	DiscoveryState.DISCOVERED: "DISCOVERED",
}

var region_id: String = ""
var display_name: String = ""
## WorldMap 좌표계 기준 지역 중심(예: NE_DUNGEON_CANDIDATE).
var world_position := Vector2.ZERO
## 지역 경계. 크기가 0이면 경계 없이 world_position 점만으로 식별한다.
var region_bounds := Rect2()
var discovery_state: DiscoveryState = DiscoveryState.UNKNOWN
## 완전 탐험까지 요구되는 시간(초). 진행 규칙 자체는 이후 확장.
var exploration_duration: float = 0.0
## 0~5 정수 위험도. 실제 위험 시스템 연동은 이후 태스크.
var base_risk: int = 0
## 발견된 feature id 목록(String). 내부 복사본으로만 유지한다.
var discovered_features: Array = []
var metadata: Dictionary = {}
## WorldMap marker 연결용 식별자(Node 참조 대신 String).
## 예: 마커 노드명("NeDungeonCandidate") 또는 forest cluster id("sparse_forest").
var source_marker_id: String = ""


func _init(p_region_id: String = "") -> void:
	region_id = p_region_id


func get_discovery_state_name() -> String:
	return DISCOVERY_STATE_NAMES.get(discovery_state, "?")


## 상태 변경. 존재하지 않는 enum 값은 거부하고 false를 반환한다.
func set_discovery_state(value: int) -> bool:
	if value < DiscoveryState.UNKNOWN or value > DiscoveryState.DISCOVERED:
		return false
	discovery_state = value
	return true


func get_discovery_state() -> DiscoveryState:
	return discovery_state


## 발견 feature 추가. 빈 id와 중복은 거부한다.
func add_discovered_feature(feature_id: String) -> bool:
	if feature_id.is_empty() or discovered_features.has(feature_id):
		return false
	discovered_features.append(feature_id)
	return true


func has_discovered_feature(feature_id: String) -> bool:
	return discovered_features.has(feature_id)


## 외부에서 원본 Array를 수정해도 내부 상태가 바뀌지 않게 복사본으로 저장한다.
func set_discovered_features(features: Array) -> void:
	discovered_features = features.duplicate(true)


func get_discovered_features() -> Array:
	return discovered_features.duplicate(true)


## metadata는 mutable object이므로 복사본으로 저장한다.
func set_metadata(value: Dictionary) -> void:
	metadata = value.duplicate(true)


func get_metadata() -> Dictionary:
	return metadata.duplicate(true)


## region_bounds가 유효하면 bounds 포함 여부,
## 비어 있으면 world_position 일치 여부로 판정한다.
func contains_world_position(pos: Vector2) -> bool:
	if region_bounds.size.x > 0.0 and region_bounds.size.y > 0.0:
		return region_bounds.has_point(pos)
	return pos == world_position


## 순수 snapshot(Dictionary)으로 직렬화한다. 모든 값은 기본 타입/Vector2/Rect2이며
## Node/Actor reference를 포함하지 않는다. 컨테이너는 복사본으로 포함한다.
func to_snapshot() -> Dictionary:
	return {
		"region_id": region_id,
		"display_name": display_name,
		"world_position": world_position,
		"region_bounds": region_bounds,
		"discovery_state": discovery_state,
		"exploration_duration": exploration_duration,
		"base_risk": base_risk,
		"discovered_features": discovered_features.duplicate(true),
		"metadata": metadata.duplicate(true),
		"source_marker_id": source_marker_id,
	}


## snapshot(Dictionary)으로부터 region을 복원한다. 컨테이너는 복사본으로 참조해
## 원본을 수정해도 region 내부 상태가 바뀌지 않게 한다.
static func from_snapshot(snapshot: Dictionary) -> ExplorationRegion:
	var region := ExplorationRegion.new(str(snapshot.get("region_id", "")))
	region.display_name = str(snapshot.get("display_name", ""))
	region.world_position = Vector2(snapshot.get("world_position", Vector2.ZERO))
	region.region_bounds = Rect2(snapshot.get("region_bounds", Rect2()))
	region.discovery_state = int(snapshot.get("discovery_state", DiscoveryState.UNKNOWN))
	region.exploration_duration = float(snapshot.get("exploration_duration", 0.0))
	region.base_risk = int(snapshot.get("base_risk", 0))
	var features: Variant = snapshot.get("discovered_features", [])
	if typeof(features) == TYPE_ARRAY:
		region.discovered_features = (features as Array).duplicate(true)
	var meta: Variant = snapshot.get("metadata", {})
	if typeof(meta) == TYPE_DICTIONARY:
		region.metadata = (meta as Dictionary).duplicate(true)
	region.source_marker_id = str(snapshot.get("source_marker_id", ""))
	return region
