extends RefCounted
class_name BuildingUpgrade3D

## TASK-037-1 Building Upgrade 공통 contract(data-driven).
## 기존 2D building upgrade는 존재하지 않고(level=1 고정), 3D Runtime 건물도 level만
## 1로 유지된 상태였다. 본 태스크는 BuildingUpgrade Audit 결과를 반영한 최소 공통
## upgrade contract를 정의한다. TASK-037-2가 이 contract를 소비해 실제 생산/용량에
## 반영하고, TASK-037-3 UI/visual hook이 level/cost/effect delta를 표시한다.
##
## Audit 결과(확인 항목 -> 현재 runtime 근거):
##   - Building identity: Building3D("buildings_3d"), CoreBuilding3D(core_type 5종),
##     Workplace3D(Lumberyard3D/Quarry3D). upgrade identity는 각 빌딩이 제공한다.
##   - workplace slots: Workplace3D.max_workers(Lumberyard/Quarry 모두 2).
##   - production rate: Lumberjack3D(gather_interval 0.6 / carry_capacity 5),
##     Miner3D(production_interval 1.0 / stone_per_cycle 1). worker별 export 값이다.
##   - capacity: 현재 runtime에 저장/재고 capacity 없음. worker slot만 존재.
##   - visual hooks: Visual slot placeholder(BodyMesh/RoofMesh/NameLabel + type별 색),
##     placement work-radius 링, worker carry prop/work_anim signal. upgrade가
##     직결할 최소 hook은 Visual slot + level 표시(prompt)다.
##
## Contract 구조(identity -> level 순 오름차순 배열):
##   {"level": N, "cost": {"<resource>": <amount>}, "modifiers": {"<key>": <value>}}
##   - cost: 해당 level 도달 비용. level 1은 항상 {} (건설/기본 상태).
##   - modifiers: 해당 level에서 적용되는 modifier set. level 1 = 현재 runtime
##     baseline(무변화). modifier key는 GAME_DESIGN.md "생산시설 Worker Slot" 확장
##     항목(Worker Slot / 작업 반경 / 생산 효율)을 근거로 한다.
##   - Lumberyard: worker_slots / work_radius / production_rate.
##   - Quarry: worker_slots / production_rate (Miner는 고정 WorkPoint 작업이라
##     work_radius 소비처가 없어 contract에서 제외 - audit 근거).
##   - 핵심 건물(keep/tavern/inn/grocery/equipment): 현재 runtime에 생산/슬롯
##     modifier가 없으므로 cost만 정의하고 modifiers는 {}로 둔다. 실제 효과는
##     후속 태스크(고용/로스터/식료/장비)가 DESIGN_TUNING으로 채운다.
##
## 모든 비용/수치는 DESIGN_TUNING이다(큐 공통 규칙 7).

## 최대 업그레이드 단계(공통 상한). 수치는 DESIGN_TUNING.
const MAX_LEVEL_LIMIT := 3

## identity -> level 순 배열. 계약 단일 소스다.
const UPGRADES := {
	"lumberyard": [
		{"level": 1, "cost": {}, "modifiers": {"worker_slots": 2, "work_radius": 192.0, "production_rate": 1.0}},
		{"level": 2, "cost": {"wood": 40}, "modifiers": {"worker_slots": 3, "work_radius": 240.0, "production_rate": 1.2}},
		{"level": 3, "cost": {"wood": 80}, "modifiers": {"worker_slots": 4, "work_radius": 288.0, "production_rate": 1.4}},
	],
	"quarry": [
		{"level": 1, "cost": {}, "modifiers": {"worker_slots": 2, "production_rate": 1.0}},
		{"level": 2, "cost": {"wood": 40}, "modifiers": {"worker_slots": 3, "production_rate": 1.2}},
		{"level": 3, "cost": {"wood": 80}, "modifiers": {"worker_slots": 4, "production_rate": 1.4}},
	],
	"keep": [
		{"level": 1, "cost": {}, "modifiers": {}},
		{"level": 2, "cost": {"wood": 100}, "modifiers": {}},
		{"level": 3, "cost": {"wood": 200}, "modifiers": {}},
	],
	"tavern": [
		{"level": 1, "cost": {}, "modifiers": {}},
		{"level": 2, "cost": {"wood": 100}, "modifiers": {}},
		{"level": 3, "cost": {"wood": 200}, "modifiers": {}},
	],
	"inn": [
		{"level": 1, "cost": {}, "modifiers": {}},
		{"level": 2, "cost": {"wood": 100}, "modifiers": {}},
		{"level": 3, "cost": {"wood": 200}, "modifiers": {}},
	],
	"grocery": [
		{"level": 1, "cost": {}, "modifiers": {}},
		{"level": 2, "cost": {"wood": 100}, "modifiers": {}},
		{"level": 3, "cost": {"wood": 200}, "modifiers": {}},
	],
	"equipment": [
		{"level": 1, "cost": {}, "modifiers": {}},
		{"level": 2, "cost": {"wood": 100}, "modifiers": {}},
		{"level": 3, "cost": {"wood": 200}, "modifiers": {}},
	],
}

const KNOWN_IDENTITIES := [
	"lumberyard", "quarry", "keep", "tavern", "inn", "grocery", "equipment",
]


## identity의 level 순 배열(없으면 []).
static func get_entries(identity: String) -> Array:
	return UPGRADES.get(identity, [])


## identity의 최대 upgrade level. contract 항목이 없으면 1(업그레이드 불가).
static func get_max_level(identity: String) -> int:
	var entries := get_entries(identity)
	if entries.is_empty():
		return 1
	return int(entries[entries.size() - 1].get("level", 1))


## identity/level에 해당하는 entry. 없으면 {}.
static func get_entry(identity: String, level: int) -> Dictionary:
	for entry in get_entries(identity):
		if int(entry.get("level", 0)) == level:
			return entry
	return {}


## 해당 level 도달 비용(resource_id -> amount). 없으면 {}.
static func get_cost(identity: String, level: int) -> Dictionary:
	return get_entry(identity, level).get("cost", {})


## 해당 level의 modifier set. 없으면 {}.
static func get_modifiers(identity: String, level: int) -> Dictionary:
	return get_entry(identity, level).get("modifiers", {})


## level 1 baseline modifier set(현재 runtime 값과 일치해야 하는 audit 기준).
static func get_base_modifiers(identity: String) -> Dictionary:
	return get_modifiers(identity, 1)


## from_level에서 다음 level로 가는 upgrade cost. 다음 level 없으면 {}.
static func get_next_cost(identity: String, from_level: int) -> Dictionary:
	return get_cost(identity, from_level + 1)


## from_level에서 다음 level에 적용될 modifier set. 없으면 {}.
static func get_next_modifiers(identity: String, from_level: int) -> Dictionary:
	return get_modifiers(identity, from_level + 1)


## from_level 다음 upgrade 항목이 있는지.
static func has_upgrade(identity: String, from_level: int) -> bool:
	return not get_entry(identity, from_level + 1).is_empty()