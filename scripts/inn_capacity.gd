extends Node

## TASK-022-2 여관(Inn) 레벨 / 보유 용량 데이터 단일 소스.
## 여관 업그레이드 레벨과 그에 따른 주민(Worker)/용병(Mercenary) 보유 한도를
## data-driven 테이블로 관리하고, 고용 Roster(WorkerRoster / MercenaryRoster /
## MercenaryRoster3D)의 add 경로가 이 용량을 cap으로 강제하도록 연결된다.
## 영구 Save/Load는 프로젝트 전역 규약대로 구현하지 않는다(인메모리 유지).

## TASK-022-2: 업그레이드 테이블.
## - level: 여관 레벨. 1이 시작 상태이고, upgrade()로 증가한다.
## - cost: 다음 업그레이드 비용(경제 시스템 부재로 spending은 구현하지 않고
##   메타데이터로만 유지). exact cost/capacity는 DESIGN_TUNING 값이다.
## - worker_capacity / mercenary_capacity: 해당 레벨에서 여관 1채당 보유 한도.
##   (GAME_DESIGN.md "여관 업그레이드는 주민/용병 보유 한도와 관리 기능을
##   확장하는 방식으로 연결" 규약의 데이터 표현)
const INN_LEVELS := [
	{ "level": 1, "cost": 0, "worker_capacity": 8, "mercenary_capacity": 4 },
	{ "level": 2, "cost": 50, "worker_capacity": 12, "mercenary_capacity": 8 },
	{ "level": 3, "cost": 100, "worker_capacity": 16, "mercenary_capacity": 12 },
]

## TASK-022-2: 여관 개수 상한. 여관은 시작부터 존재하는 핵심 건물 1채이므로
## "무한 Inn spam"을 막는 정책 상한이다(추후 배치 확장 시 can_place_inn 경로로
## 강제 연결됨).
const MAX_INN_COUNT := 1

## 현재 여관 레벨(인메모리 상태). 시작 1.
var _level := 1

signal level_changed(level: int, worker_capacity: int, mercenary_capacity: int)


func get_level() -> int:
	return _level


func get_max_level() -> int:
	return int(INN_LEVELS[INN_LEVELS.size() - 1].level)


## 지정 레벨의 테이블 행을 반환한다. 없으면 최고 레벨 행으로 fallback.
func get_level_config(level: int) -> Dictionary:
	for cfg in INN_LEVELS:
		if int(cfg.level) == level:
			return cfg
	return INN_LEVELS[INN_LEVELS.size() - 1]


func get_upgrade_cost() -> int:
	if not can_upgrade():
		return 0
	return int(get_level_config(_level + 1).cost)


func can_upgrade() -> bool:
	return _level < get_max_level()


## TASK-022-2: 업그레이드 수행. 최고 레벨이면 거부하고, 성공 시 level_changed를
## 방출한다(UI/후속 기능 연결 지점). 경제 시스템 부재로 cost spending은 없다.
func upgrade() -> bool:
	if not can_upgrade():
		return false
	_level += 1
	level_changed.emit(_level, get_worker_capacity(), get_mercenary_capacity())
	return true


## 현재 레벨의 주민 보유 한도.
## 여관 개수(2D/3D 그룹)를 곱하되, 여관은 고정 핵심 건물 1채가 항상 존재한다는
## 설계 보증에 따라 최소 1채로 계산한다. 따라서 개수 상한 정책과 연결 가능하다.
func get_worker_capacity() -> int:
	return int(get_level_config(_level).worker_capacity) * _effective_inn_count()


## 현재 레벨의 용병 보유 한도 (get_worker_capacity와 동일 규칙).
func get_mercenary_capacity() -> int:
	return int(get_level_config(_level).mercenary_capacity) * _effective_inn_count()


## 여관 개수 상한 정책 조회.
func get_inn_count_limit() -> int:
	return MAX_INN_COUNT


## 현재 월드(2D/3D 런타임)에 배치된 여관 수.
func count_inns() -> int:
	var n := 0
	for building in get_tree().get_nodes_in_group("core_buildings"):
		if is_instance_valid(building) and building.has_method("get_core_type") \
				and building.get_core_type() == "inn":
			n += 1
	for building in get_tree().get_nodes_in_group("core_buildings_3d"):
		if is_instance_valid(building) and building.has_method("get_core_type") \
				and building.get_core_type() == "inn":
			n += 1
	return n


## 개수 상한 내에서 추가 여관 배치가 허용되는지. 상한 도달 시 spam을 거부한다.
func can_place_inn() -> bool:
	return count_inns() < MAX_INN_COUNT


## 보유 한도 계산에 사용하는 유효 여관 수. 여관은 고정 핵심 건물이라 1채는
## 항상 존재한다고 간주하되(clamp 최소 1), 상한을 넘는 배치는 세지 않는다.
func _effective_inn_count() -> int:
	return clampi(count_inns(), 1, MAX_INN_COUNT)