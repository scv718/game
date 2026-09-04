extends SceneTree

## TASK-023-2 Global Morale Bonus Hook 테스트.
## 신규 morale_bonus_hook.gd(MoraleBonusHook)와 mercenary_actor_3d.gd의
## _get_attack_damage() 승수 적용을 검증한다. 기존 파일은 수정하지 않는
## 신규 task0232* 계열 테스트(POST-3D Feature queue).
##
## 완료조건 매핑:
##   - morale increase/decrease가 modifier에 반영:
##     총 사기 증가 -> attack multiplier/공격 데미지 증가,
##     총 사기 감소(사망) -> multiplier/공격 데미지 감소.
##   - actor spawn/despawn 반복 시 누적 중복 없음:
##     승수는 총 사기로만 유도되므로 spawn/despawn을 반복해도 multiplier와
##     공격 데미지가 누적되지 않고, 구독 registry는 멱등(같은 id 1회)이며
##     freed Actor는 자동 정리되어 stale reference가 남지 않는다.
##
## 금지 규칙:
##   - base stat(merc_data.attack_damage)은 절대 변조하지 않는다(영구 변조 금지).

var _frame := 0
var _phase := 0
var _failed := false
var _roster: Node = null
var _state: MoraleState = null
var _hook: MoraleBonusHook = null
var _world: Node = null

var _data: MercenaryData = null
var _attacker: Node = null
var _cleanup_wait := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _finish() -> void:
	print("TASK0232_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		0:
			_setup()
		1:
			_test_multiplier_derived()
		2:
			_test_increase_decrease()
		3:
			_test_base_stat_preserved()
		4:
			_test_apply_remove_idempotent()
		5:
			_test_spawn_despawn_no_accumulation()
		6:
			_test_freed_auto_cleanup()
		7:
			_finish()
			return true
	if _frame > 2000:
		print("TASK0232_RESULT=TIMEOUT phase=%d" % _phase)
		quit()
		return true
	return false


func _setup() -> void:
	if _frame < 6:
		return
	# 3D world root (Actor _ready가 참조하는 그룹/노드 안전 로드용).
	var world_scene: PackedScene = load("res://scenes/world3d.tscn") as PackedScene
	if world_scene != null:
		_world = world_scene.instantiate()
		_world.name = "World3DRoot"
		root.add_child(_world)
	_roster = root.get_node_or_null("MercenaryRoster")
	_check(_roster != null, "MercenaryRoster autoload is available")
	# MoraleState + MoraleBonusHook 구성.
	_state = MoraleState.new()
	_hook = MoraleBonusHook.new()
	_hook.set_state(_state)
	# 용병 3명(roster identity) 고용.
	_data = MercenaryData.new("m_a", "Alaric")
	_data.level = 5
	_data.attack_damage = 100
	var b := MercenaryData.new("m_b", "Bram")
	b.level = 1
	b.attack_damage = 100
	var c := MercenaryData.new("m_c", "Cedric")
	c.level = 3
	c.attack_damage = 100
	_check(_roster.add_mercenary(_data), "hire mercenary A (level 5)")
	_check(_roster.add_mercenary(b), "hire mercenary B (level 1)")
	_check(_roster.add_mercenary(c), "hire mercenary C (level 3)")
	_state.refresh_from_mercenaries(_roster.get_mercenaries())
	_phase = 1


func _spawn_attacker() -> Node:
	var scene: PackedScene = load("res://scenes/mercenary_3d.tscn") as PackedScene
	var actor: Node = scene.instantiate()
	actor.merc_data = _data
	actor.position = Vector3(0, 0, 0)
	actor.defense_point = Vector3(0, 0, 0)
	if _world != null:
		_world.add_child(actor)
	else:
		root.add_child(actor)
	return actor


func _test_multiplier_derived() -> void:
	# 총 사기: level 1=1.0 + level 3=1.5 + level 5=2.0 = 4.5
	var morale: float = _state.get_total_morale()
	_check(absf(morale - 4.5) < 0.0001, "total morale = 4.5 (three contributors)")
	var mult: float = _hook.get_attack_multiplier()
	_check(absf(mult - (1.0 + 4.5 * MoraleBonusHook.ATTACK_BONUS_PER_UNIT)) < 0.0001,
		"attack multiplier is derived from total morale (pure function)")
	_check(mult > 1.0, "positive morale yields a bonus multiplier > 1.0")
	# Actor 적용: base 100 * mult 반영.
	_attacker = _spawn_attacker()
	_check(_hook.apply_to(_attacker), "apply morale bonus to a spawned actor")
	var dmg: int = _attacker._get_attack_damage()
	var expect: int = roundi(100.0 * mult)
	_check(dmg == expect, "actor attack damage reflects morale multiplier (%d)" % dmg)
	_check(_hook.get_active_count() == 1, "one actor subscribed to the hook")
	_phase = 2


func _test_increase_decrease() -> void:
	# 증가: 기여자 레벨 상승 -> 총 사기 증가 -> multiplier/데미지 증가.
	var before_mult: float = _hook.get_attack_multiplier()
	var before_dmg: int = _attacker._get_attack_damage()
	_data.level = 6
	_state.refresh_from_mercenaries(_roster.get_mercenaries())
	var after_mult: float = _hook.get_attack_multiplier()
	var after_dmg: int = _attacker._get_attack_damage()
	_check(after_mult > before_mult, "morale increase raises attack multiplier")
	_check(after_dmg > before_dmg, "morale increase raises actor attack damage")
	_check(absf(_attacker.get_morale_multiplier() - after_mult) < 0.0001,
		"actor multiplier refreshed on morale change (signal-driven)")
	# 감소: 한 명 사망 -> 총 사기 감소 -> multiplier/데미지 감소.
	var before_mult2: float = _hook.get_attack_multiplier()
	var before_dmg2: int = _attacker._get_attack_damage()
	_data.alive = false
	_state.refresh_from_mercenaries(_roster.get_mercenaries())
	var after_mult2: float = _hook.get_attack_multiplier()
	var after_dmg2: int = _attacker._get_attack_damage()
	_check(after_mult2 < before_mult2, "morale decrease lowers attack multiplier")
	_check(after_dmg2 < before_dmg2, "morale decrease lowers actor attack damage")
	_phase = 3


func _test_base_stat_preserved() -> void:
	# base stat(merc_data.attack_damage)은 변조되지 않아야 한다(영구 변조 금지).
	_check(_data.attack_damage == 100, "base attack_damage is never mutated")
	var actor_base: int = _attacker.merc_data.attack_damage
	_check(actor_base == 100, "actor base stat unchanged after morale bonus applied")
	_phase = 4


func _test_apply_remove_idempotent() -> void:
	# apply 중복 -> 멱등(같은 id 1회만, 데미지 중첩 없음).
	var dmg: int = _attacker._get_attack_damage()
	var before_count: int = _hook.get_active_count()
	_check(not _hook.apply_to(_attacker), "duplicate apply_to is idempotent (no-op)")
	_check(_hook.get_active_count() == before_count, "active count unchanged on duplicate apply")
	_check(_attacker._get_attack_damage() == dmg, "no damage stacking on duplicate apply")
	# remove -> 멱등.
	_check(_hook.remove_from(_attacker), "remove_from removes the actor")
	_check(not _hook.remove_from(_attacker), "duplicate remove_from is idempotent (no-op)")
	_check(_hook.get_active_count() == 0, "active count is zero after removal")
	_check(absf(_attacker.get_morale_multiplier() - 1.0) < 0.0001,
		"removed actor resets to neutral multiplier (1.0)")
	_phase = 5


func _test_spawn_despawn_no_accumulation() -> void:
	# spawn/despawn 반복: 승수는 총 사기로만 유도되므로 누적이 없어야 한다.
	var expect_mult: float = _hook.get_attack_multiplier()
	var expected_dmg: int = roundi(100.0 * expect_mult)
	var mult_after := 0.0
	for i in range(5):
		var a := _spawn_attacker()
		_hook.apply_to(a)
		mult_after = a.get_morale_multiplier()
		_check(a._get_attack_damage() == expected_dmg,
			"repeated spawn keeps damage non-accumulating (iter %d)" % i)
		_hook.remove_from(a)
		a.queue_free()
	_check(absf(mult_after - expect_mult) < 0.0001,
		"multiplier never accumulates across spawn/despawn")
	_check(_hook.get_active_count() == 0,
		"all actors cleaned up -> no active subscription left (no accumulation)")
	# remove 없이 despawn(freed)만 반복 -> freed Actor가 registry에 남는다.
	for i in range(5):
		var a := _spawn_attacker()
		_hook.apply_to(a)
		a.queue_free()
	_cleanup_wait = 0
	_phase = 6


func _test_freed_auto_cleanup() -> void:
	# queue_free가 실제 처리될 프레임을 대기한 뒤 _refresh가 freed Actor를 자동 정리하는지 확인.
	_cleanup_wait += 1
	if _cleanup_wait < 15:
		return
	# freed Actor가 정리되려면 _refresh가 호출돼야 한다. morale_changed로 refresh를 트리거.
	_hook._refresh()
	var count: int = _hook.get_active_count()
	_check(count == 0,
		"freed actors auto-cleaned by refresh -> no stale subscription (%d)" % count)
	# 승수는 여전히 유효(누적/오염 없음).
	_check(absf(_hook.get_attack_multiplier()
		- (1.0 + _state.get_total_morale() * MoraleBonusHook.ATTACK_BONUS_PER_UNIT)) < 0.0001,
		"multiplier stays derived from morale after cleanup (no drift)")
	_phase = 7
