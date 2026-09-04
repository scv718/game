extends SceneTree

## TASK-037-1 Building Upgrade Audit / Contract 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열 컨벤션을 따른다.
##
## Audit 항목을 고정하면서 최소 공통 upgrade contract를 검증한다:
##   1. Building identity   - Building3D base / CoreBuilding3D(core_type 5종) /
##                            Workplace3D(Lumberyard/Quarry) identity 유지.
##   2. workplace slots     - Lumberyard/Quarry max_workers=2 baseline 보존.
##   3. production rate     - Lumberjack(gather_interval 0.6 / carry 5),
##                            Miner(production_interval 1.0 / per_cycle 1) anchor.
##   4. capacity            - 현재 runtime은 worker slot만 존재(저장 capacity 없음).
##                            contract에 임의 storage modifier를 넣지 않았는지 확인.
##   5. visual hooks        - Visual slot 존재 + work radius placeholder 유지.
## contract:
##   - level  - base 1, level별 조회/진행(1 -> 3 max)이 contract와 일치.
##   - cost   - level>=2에 양수 비용 존재, 다음 level 비용 조회 정확.
##   - modifier set - identity별 contract 단일 소스, baseline이 현재 runtime과 일치.
## 완료조건: 최소 공통 contract(BuildingUpgrade3D + Building3D API) PASS.
##
## BuildingUpgrade3D/WorldCoords3D는 class_name 정적 참조 관례(task3dbld0014 등)를
## 따른다. autoload(VillageResources/GameTime)는 계약 조회에 필요 없어 사용하지 않는다.

enum Phase {
	SETUP, CONTRACT_DATA, BASE_API, WIRING, AUDIT_ANCHOR, REGRESSION_CORE, DONE,
}

const EXPECTED_LABELS := {
	"keep": "거점",
	"tavern": "주점",
	"inn": "여관",
	"grocery": "식료품점",
	"equipment": "장비점",
}

## audit anchor: 현재 runtime baseline과 일치해야 하는 contract 값.
const AUDIT_LUMBERYARD_BASELINE := {
	"worker_slots": 2, "work_radius": 192.0, "production_rate": 1.0,
}
const AUDIT_QUARRY_BASELINE := {
	"worker_slots": 2, "production_rate": 1.0,
}
const AUDIT_LUMBERYARD_SLOTS := 2
const AUDIT_QUARRY_SLOTS := 2
const AUDIT_LUMBERYARD_RADIUS := 192.0
const AUDIT_LUMBERJACK_GATHER := 0.6
const AUDIT_LUMBERJACK_CARRY := 5
const AUDIT_MINER_INTERVAL := 1.0
const AUDIT_MINER_CYCLE := 1

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _container: Node3D = null
var _buildings := {}
var _building_script: GDScript = null


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
	print("TASK0371_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT_DATA:
			_contract_data()
		Phase.BASE_API:
			_base_api()
		Phase.WIRING:
			_wiring()
		Phase.AUDIT_ANCHOR:
			_audit_anchor()
		Phase.REGRESSION_CORE:
			_regression_core()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK0371_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	_wait += 1
	if _wait < 8:
		return
	_container = Node3D.new()
	_container.name = "BuildingUpgradeFixture"
	root.add_child(_container)

	var yard: Node3D = (load("res://scenes/lumberyard_3d.tscn") as PackedScene).instantiate()
	yard.name = "FixtureLumberyard"
	_container.add_child(yard)
	_buildings["lumberyard"] = yard

	var quarry: Node3D = (load("res://scenes/quarry_3d.tscn") as PackedScene).instantiate()
	quarry.name = "FixtureQuarry"
	_container.add_child(quarry)
	_buildings["quarry"] = quarry

	for core_type in EXPECTED_LABELS:
		var core: Node3D = (load("res://scenes/core_building_3d.tscn") as PackedScene).instantiate()
		core.name = "FixtureCore_" + core_type
		core.core_type = core_type
		_container.add_child(core)
		_buildings[core_type] = core

	_building_script = load("res://scripts/building_3d.gd")
	_check(_building_script.get_base_script() == null,
		"Building3D is the direct base (StaticBody3D) of the building lineage")
	_check(_building_script.get_instance_base_type() == "StaticBody3D",
		"Building3D base node type is StaticBody3D")
	_enter(Phase.CONTRACT_DATA)


## -- CONTRACT_DATA: BuildingUpgrade3D 단일 소스 구조/값 invariants --
func _contract_data() -> void:
	var known := BuildingUpgrade3D.KNOWN_IDENTITIES
	_check(not known.is_empty(), "known building identities are enumerated")
	var structure_ok := true
	for identity in known:
		var entries: Array = BuildingUpgrade3D.get_entries(identity)
		if entries.is_empty():
			structure_ok = false
			print("  no entries for " + identity)
			continue
		var first: Dictionary = entries[0]
		if int(first.get("level", 0)) != 1 or not first.get("cost", {}).is_empty():
			structure_ok = false
			print("  level 1 baseline not empty-cost for " + identity)
		var modifier_keys: Array = (first.get("modifiers", {}) as Dictionary).keys()
		var prev_level := 0
		for entry in entries:
			var lv := int(entry.get("level", 0))
			if lv != prev_level + 1:
				structure_ok = false
				print("  non-consecutive level in " + identity)
			prev_level = lv
			var cost: Dictionary = entry.get("cost", {})
			if lv >= 2 and cost.is_empty():
				structure_ok = false
				print("  level %d has empty cost in %s" % [lv, identity])
			for amount in cost.values():
				if not (amount is int and int(amount) > 0):
					structure_ok = false
					print("  non-positive cost in %s level %d" % [identity, lv])
			var mods: Dictionary = entry.get("modifiers", {})
			if mods.keys() != modifier_keys:
				structure_ok = false
				print("  modifier key set drifts within %s" % identity)
		if BuildingUpgrade3D.get_max_level(identity) != prev_level:
			structure_ok = false
			print("  max level mismatch in " + identity)
	_check(structure_ok,
		"all known identities expose a consistent 1-based contract (level/cost/modifier set)")

	var yard_base: Dictionary = BuildingUpgrade3D.get_base_modifiers("lumberyard")
	_check(yard_base == AUDIT_LUMBERYARD_BASELINE,
		"lumberyard level-1 modifiers match the current runtime baseline (audit anchor)")
	var quarry_base: Dictionary = BuildingUpgrade3D.get_base_modifiers("quarry")
	_check(quarry_base == AUDIT_QUARRY_BASELINE,
		"quarry level-1 modifiers match the current runtime baseline (audit anchor)")
	_check(not quarry_base.has("work_radius"),
		"quarry contract omits work_radius (miner works at fixed points - no consumer)")
	var has_storage := false
	for identity in known:
		for entry in BuildingUpgrade3D.get_entries(identity):
			if (entry.get("modifiers", {}) as Dictionary).has("storage"):
				has_storage = true
	_check(not has_storage,
		"no arbitrary storage modifier in the contract (no storage capacity in runtime)")
	_enter(Phase.BASE_API)


## -- BASE_API: contract 없는 기본 Building3D의 안전한 최소 동작 --
func _base_api() -> void:
	# scene 없이도 Building3D가 생성되고 contract 조회가 Visual/물리 의존 없이
	# 안전해야 한다(contract는 빌딩 identity/level만 사용).
	var plain: Node = _building_script.new()
	_check(plain.get_upgrade_identity() == "",
		"base building identity is empty (no contract -> not upgradable)")
	_check(plain.get_max_level() == 1,
		"contract-less building max level is 1")
	_check(plain.get_upgrade_cost().is_empty(),
		"contract-less building has no upgrade cost")
	_check(plain.get_next_level_modifiers().is_empty(),
		"contract-less building has no next modifiers")
	_check(not plain.is_upgradable(),
		"contract-less building is not upgradable")
	_check(plain.get_level() == 1, "default building level is 1")
	plain.free()

	var node: Node3D = _buildings["lumberyard"]
	_check(node.get_max_level() == BuildingUpgrade3D.get_max_level("lumberyard"),
		"max level comes from the shared contract table")
	_enter(Phase.WIRING)


## -- WIRING: 빌딩 identity -> contract 연결 + level 진행 --
func _wiring() -> void:
	var yard: Node = _buildings["lumberyard"]
	_check(yard.get_upgrade_identity() == "lumberyard",
		"lumberyard wires the shared lumberyard contract identity")
	_check(yard.get_upgrade_contract() == BuildingUpgrade3D.get_entries("lumberyard"),
		"lumberyard contract entries come from the single source table")
	_check(yard.is_upgradable(), "lumberyard at level 1 is upgradable")
	_check(yard.get_upgrade_cost() == {"wood": 40},
		"lumberyard level 1 -> 2 cost is exposed by the contract")
	_check(yard.get_next_level_modifiers() == {
		"worker_slots": 3, "work_radius": 240.0, "production_rate": 1.2,
	}, "lumberyard next modifiers match contract level 2")

	yard.level = 3
	_check(yard.get_level() == 3, "level field advances to the contract max")
	_check(not yard.is_upgradable(), "building at max level is not upgradable")
	_check(yard.get_upgrade_cost().is_empty(), "max level building has no next cost")
	_check(yard.get_next_level_modifiers().is_empty(),
		"max level building has no next modifiers")
	yard.level = 1

	var quarry: Node = _buildings["quarry"]
	_check(quarry.get_upgrade_identity() == "quarry",
		"quarry wires the shared quarry contract identity")
	_check(quarry.get_upgrade_cost() == {"wood": 40},
		"quarry level 1 -> 2 cost is exposed by the contract")
	_check(quarry.get_next_level_modifiers() == {
		"worker_slots": 3, "production_rate": 1.2,
	}, "quarry next modifiers match contract level 2 (no work_radius)")
	_enter(Phase.AUDIT_ANCHOR)


## -- AUDIT_ANCHOR: 현재 runtime baseline 값 보존(audit 고정) --
func _audit_anchor() -> void:
	var yard: Node = _buildings["lumberyard"]
	_check(yard.max_workers == AUDIT_LUMBERYARD_SLOTS,
		"lumberyard workplace slots remain 2 (baseline preserved)")
	_check(yard.get_slot_capacity() == AUDIT_LUMBERYARD_SLOTS,
		"lumberyard slot capacity API matches the audit anchor")
	_check(yard.work_radius == AUDIT_LUMBERYARD_RADIUS,
		"lumberyard work radius remains 192px (baseline preserved)")
	var quarry: Node = _buildings["quarry"]
	_check(quarry.max_workers == AUDIT_QUARRY_SLOTS,
		"quarry workplace slots remain 2 (baseline preserved)")
	_check(quarry.get_slot_capacity() == AUDIT_QUARRY_SLOTS,
		"quarry slot capacity API matches the audit anchor")

	var lumberjack_script: GDScript = load("res://scripts/lumberjack_3d.gd")
	var lumberjack: Node = lumberjack_script.new()
	_check(lumberjack.carry_capacity == AUDIT_LUMBERJACK_CARRY,
		"lumberjack carry capacity remains 5 (production baseline preserved)")
	_check(lumberjack.gather_interval == AUDIT_LUMBERJACK_GATHER,
		"lumberjack gather interval remains 0.6s (production baseline preserved)")
	lumberjack.free()
	var miner_script: GDScript = load("res://scripts/miner_3d.gd")
	var miner: Node = miner_script.new()
	_check(miner.production_interval == AUDIT_MINER_INTERVAL,
		"miner production interval remains 1.0s (production baseline preserved)")
	_check(miner.stone_per_cycle == AUDIT_MINER_CYCLE,
		"miner stone per cycle remains 1 (production baseline preserved)")
	miner.free()

	_check(yard.get_node_or_null("Visual") != null,
		"lumberyard keeps its Visual slot (visual hook audit anchor)")
	_check(yard.visual_slot != null and yard.visual_slot is Node3D,
		"Building3D visual_slot is wired after scene instantiation")
	_enter(Phase.REGRESSION_CORE)


## -- REGRESSION_CORE: 5종 핵심 건물 identity 보존(기존 TASK-3D-BLD-001-1 계약) --
func _regression_core() -> void:
	var clean := true
	for core_type in EXPECTED_LABELS:
		var building: Node = _buildings[core_type]
		var expected_label: String = EXPECTED_LABELS[core_type]
		if building.get_core_type() != core_type \
				or building.get_building_label() != expected_label \
				or building.get_level() != 1 \
				or building.get_interact_prompt() != "%s (Lv.1)" % expected_label \
				or building.get_upgrade_identity() != core_type \
				or building.get_max_level() != BuildingUpgrade3D.get_max_level(core_type):
			clean = false
			print("  identity drift in core_type=%s" % core_type)
	_check(clean,
		"all 5 core types keep legacy label/level/prompt identity and wire their upgrade contract")
	_check(_buildings["tavern"].get_upgrade_cost() == {"wood": 100},
		"core building upgrade cost is exposed by the shared contract")
	_check(_buildings["inn"].is_upgradable(),
		"inn (priority building) participates in the common upgrade contract")
	_enter(Phase.DONE)