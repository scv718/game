extends SceneTree

## TASK-021-2 Potion Data / Craft 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task02* 계열(migration map 운영 규칙 5).
##
## 완료조건 매핑:
##   1. Potion definition: PotionData가 data-driven 정의를 제공(첫 slice 회복 포션
##      1종, herb ingredient / effect / trigger / stack 규칙 필드).
##   2. ingredient validation: 재료 부족 시 can_craft=false, craft 실패 시 재료/스톡
##      불변.
##   3. potion create: 재료 충분 시 craft 성공, herb 차감 + 포션 스톡 증가.
##   4. stock negative 없음: 실패 경로에서 herb가 음수로 떨어지지 않고, 부족분
##      제작은 성공을 반환하지 않는다.

enum Phase {
	SETUP, DEFINITION, VALIDATION, CREATE, MULTI, NEGATIVE, DONE,
}

const HEALING_POTION := "healing_potion"
const HERB_REQUIRED := 2

var _frame := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _resources: Node = null
var _potion_script: GDScript = null
var _service = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	print("TASK0212_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.DEFINITION:
			_definition()
		Phase.VALIDATION:
			_validation()
		Phase.CREATE:
			_create()
		Phase.MULTI:
			_multi()
		Phase.NEGATIVE:
			_negative()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK0212_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	if _frame < 8:
		return
	_resources = root.get_node_or_null("VillageResources")
	_potion_script = load("res://scripts/potion_data.gd") as GDScript
	var service_script: GDScript = load("res://scripts/potion_craft_service.gd") as GDScript
	_check(_resources != null, "VillageResources autoload available")
	_check(_potion_script != null, "potion_data.gd loads")
	_check(service_script != null, "potion_craft_service.gd loads")
	if _resources == null or _potion_script == null or service_script == null:
		_finish()
		return
	_service = service_script.new(_resources)
	_check(_service.resources == _resources, "craft service bound to VillageResources")
	_check(_service.STOCK_PREFIX == "potion:", "potion stock uses dedicated prefix (Food와 별도 체계)")
	_enter(Phase.DEFINITION)


## -- DEFINITION: data-driven 정의 필드 검증 --
func _definition() -> void:
	var defs: Dictionary = _potion_script.DEFINITIONS
	_check(defs.size() == 1, "첫 slice Potion 1종만 정의됨 (%d)" % defs.size())
	var data = _potion_script.get_definition(HEALING_POTION)
	_check(data != null, "healing_potion definition exists (first slice Potion 1종)")
	if data == null:
		_finish()
		return
	_check(data.id == HEALING_POTION, "potion id preserved")
	var herb_req: int = int(data.ingredients.get("herb", 0))
	_check(herb_req == HERB_REQUIRED, "healing potion takes %d herb ingredient" % herb_req)
	var heal_value: int = _enum_value("EffectType", "HEAL")
	var ratio_value: int = _enum_value("TriggerType", "HP_BELOW_RATIO")
	_check(data.effect_type == heal_value, "effect type is HEAL (data-driven)")
	_check(data.effect_amount > 0, "heal amount set (%d)" % data.effect_amount)
	_check(data.trigger_type == ratio_value, "trigger type is HP_BELOW_RATIO (data-driven)")
	_check(data.trigger_value > 0.0 and data.trigger_value < 1.0,
		"trigger ratio in (0,1) -> " + str(data.trigger_value) + " (HP 30% 이하 설계 기준)")
	_check(data.max_stack >= 1, "stack rule defined (max_stack=%d)" % data.max_stack)
	_check(_potion_script.is_known(HEALING_POTION), "registry knows healing_potion")
	_check(not _potion_script.is_known("not_a_potion"), "unknown potion id rejected")
	_check(_potion_script.get_definition("not_a_potion") == null,
		"unknown potion has no definition instance")
	_check(data.get_effect_name() == "HEAL" and data.get_trigger_name() == "HP_BELOW_RATIO",
		"named effect/trigger queries work")
	_enter(Phase.VALIDATION)


func _enum_value(enum_name: String, member: String) -> int:
	var map: Dictionary = _potion_script.get_script_constant_map().get(enum_name, {})
	return int(map.get(member, -1))


## -- VALIDATION: 재료 부족 -> 실패, 재료/스톡 불변 --
func _validation() -> void:
	var herb_now := int(_resources.get_amount("herb"))
	var floor_herb := mini(herb_now, HERB_REQUIRED - 1)
	if herb_now > floor_herb:
		_resources.spend("herb", herb_now - floor_herb)
	var stock_before := int(_service.get_stock(HEALING_POTION))
	_check(int(_resources.get_amount("herb")) < HERB_REQUIRED,
		"validation starts below herb requirement")
	_check(not _service.can_craft(HEALING_POTION),
		"can_craft=false when herb insufficient")
	var result: Dictionary = _service.craft(HEALING_POTION)
	_check(result.get("ok") == false and result.get("reason") == "insufficient_ingredients",
		"craft rejected with insufficient_ingredients")
	_check(int(_resources.get_amount("herb")) == floor_herb,
		"failed craft consumes no ingredients")
	_check(int(_service.get_stock(HEALING_POTION)) == stock_before,
		"failed craft creates no potion stock")
	_check(int(_resources.get_amount("herb")) >= 0, "herb stays non-negative on failed craft")
	var unknown: Dictionary = _service.craft("not_a_potion")
	_check(not unknown.get("ok", true) and unknown.get("reason") == "unknown_potion",
		"unknown potion rejected without side effects")
	_enter(Phase.CREATE)


## -- CREATE: 재료 정확히 충족 -> 성공, herb 차감 + 스톡 증가 --
func _create() -> void:
	var herb_now := int(_resources.get_amount("herb"))
	_resources.add("herb", HERB_REQUIRED - herb_now)
	var stock_before := int(_service.get_stock(HEALING_POTION))
	_check(int(_resources.get_amount("herb")) == HERB_REQUIRED,
		"herb prepared to exact ingredient requirement")
	_check(_service.can_craft(HEALING_POTION), "can_craft=true when herb sufficient")
	var result: Dictionary = _service.craft(HEALING_POTION)
	_check(result.get("ok") == true and result.get("count") == 1,
		"craft succeeds and returns potion count")
	_check(int(_resources.get_amount("herb")) == 0,
		"craft spends exactly the herb ingredient (%d)" % HERB_REQUIRED)
	_check(int(_service.get_stock(HEALING_POTION)) == stock_before + 1,
		"craft creates 1 potion stock")
	_enter(Phase.MULTI)


## -- MULTI: 연속 제작 정상 누적 --
func _multi() -> void:
	_resources.add("herb", HERB_REQUIRED * 2)
	var stock_before := int(_service.get_stock(HEALING_POTION))
	var ok_a: Dictionary = _service.craft(HEALING_POTION)
	var ok_b: Dictionary = _service.craft(HEALING_POTION)
	_check(ok_a.get("ok") == true and ok_b.get("ok") == true,
		"repeated crafts succeed while ingredients last")
	_check(int(_resources.get_amount("herb")) == 0,
		"repeated crafts consume herb without going negative")
	_check(int(_service.get_stock(HEALING_POTION)) == stock_before + 2,
		"repeated crafts accumulate potion stock")
	_enter(Phase.NEGATIVE)


## -- NEGATIVE: 재료 0 -> 실패, herb가 음수로 내려가지 않음 --
func _negative() -> void:
	var stock_before := int(_service.get_stock(HEALING_POTION))
	var result: Dictionary = _service.craft(HEALING_POTION)
	_check(not result.get("ok", true), "craft with zero herb is rejected")
	_check(int(_resources.get_amount("herb")) == 0, "herb never goes negative")
	_check(int(_service.get_stock(HEALING_POTION)) == stock_before,
		"rejected craft leaves potion stock unchanged")
	var spend_ok: bool = _resources.spend("herb", 10)
	_check(not spend_ok, "VillageResources refuses over-spend (no negative stock)")
	_check(int(_resources.get_amount("herb")) == 0,
		"herb still non-negative after refused spend")
	_enter(Phase.DONE)
