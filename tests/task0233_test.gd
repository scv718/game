extends SceneTree

## TASK-023-3 Morale UI / Regression 테스트.
## 기존 파일은 수정하지 않는 신규 task0233* 계열 테스트(POST-3D Feature queue).
## main_3d.tscn의 MoraleSystem3D + MoraleUI wiring 위에서 다음을 검증한다:
##   - current morale: 총 사기가 roster identity 기준으로 정확히 계산돼 UI source에 반영.
##   - major contributor: 상위 기여자(내림차순)가 정확히 도출된다.
##   - bonus: 전역 공격 보너스 승수가 총 사기로부터 유도되고 spawn Actor에 적용된다.
##   - NIGHT lethal death 후 변화: 용병 사망(alive=false) -> 총 사기/보너스 감소.
##   - DAY 복귀 후 일관성: despawn 후 사기 상태가 유지되고 다음 cycle에서 재적용된다.
##
## 완료조건 매핑:
##   - morale vertical slice PASS.
##   - HUMAN_CHECK는 UI 수치 표시가 존재하는지(모델+배선)로 간접 검증.

enum Phase {
	SETUP, INSTANCE_WAIT, HIRE, HIRE_CHECK, TO_NIGHT, NIGHT_WAIT, NIGHT_CHECK,
	LETHAL, LETHAL_CHECK, TO_DAY, DAY_WAIT, DAY_CHECK, CLEANUP, DONE,
}

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const SHORT_DAY_DURATION := 0.8
const SHORT_NIGHT_DURATION := 0.8
const SETTLE_FRAMES := 8

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP

var _game_time: Node = null
var _roster_autoload: Node = null
var _roster_3d: Node = null
var _morale_system: Node = null
var _morale_ui: Node = null
var _main: Node = null

var _data_a: MercenaryData = null
var _data_b: MercenaryData = null
var _data_c: MercenaryData = null

## 사망 직전/직후 총 사기와 보너스 승수.
var _morale_before := 0.0
var _bonus_before := 0.0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


## UI의 세 Label(MoraleValue / BonusValue / MajorContributors)이 기대값과 일치하는지
## 검증한다. 이는 HUMAN_CHECK 항목(수치 표시 존재)을 모델+배선 수준으로 자동 확인한다.
func _check_ui_matches(expect_morale: String, expect_bonus: String,
		expect_contribs: Array[String], msg: String) -> void:
	if _morale_ui == null or not is_instance_valid(_morale_ui):
		_check(false, "%s (UI missing)" % msg)
		return
	var vlabel: Label = _morale_ui.get_node_or_null("MoralePanel/MoraleRow/MoraleValue")
	var blabel: Label = _morale_ui.get_node_or_null("MoralePanel/BonusRow/BonusValue")
	var clabel: Label = _morale_ui.get_node_or_null("MoralePanel/MajorContributors")
	if vlabel == null or blabel == null or clabel == null:
		_check(false, "%s (labels missing)" % msg)
		return
	var ok := vlabel.text == expect_morale and blabel.text == expect_bonus
	if ok:
		for e in expect_contribs:
			if not clabel.text.contains(e):
				ok = false
				break
	else:
		ok = false
	_check(ok, "%s [morale='%s' bonus='%s' contribs='%s']" %
		[msg, vlabel.text, blabel.text, clabel.text.replace("\n", " | ")])


func _enter(p: Phase) -> void:
	_phase = p
	_wait = 0


func _finish() -> void:
	print("TASK0233_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.INSTANCE_WAIT:
			_instance_wait()
		Phase.HIRE:
			_hire()
		Phase.HIRE_CHECK:
			_hire_check()
		Phase.TO_NIGHT:
			_to_night()
		Phase.NIGHT_WAIT:
			_night_wait()
		Phase.NIGHT_CHECK:
			_night_check()
		Phase.LETHAL:
			_lethal()
		Phase.LETHAL_CHECK:
			_lethal_check()
		Phase.TO_DAY:
			_to_day()
		Phase.DAY_WAIT:
			_day_wait()
		Phase.DAY_CHECK:
			_day_check()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			_finish()
			return true
	if _frame > 20000:
		print("TASK0233_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	if _frame < SETTLE_FRAMES:
		return
	_game_time = root.get_node_or_null("GameTime")
	_roster_autoload = root.get_node_or_null("MercenaryRoster")
	_check(_game_time != null and _roster_autoload != null,
		"GameTime / MercenaryRoster autoloads available")
	if _game_time == null or _roster_autoload == null:
		_enter(Phase.DONE)
		return
	_game_time.set_auto_advance(false)
	_game_time.set_durations(SHORT_DAY_DURATION, SHORT_NIGHT_DURATION)
	_enter(Phase.INSTANCE_WAIT)


func _instance_wait() -> void:
	if _wait == 0:
		var packed: PackedScene = load(MAIN_SCENE_PATH)
		_main = packed.instantiate()
		_main.name = "Main3D"
		root.add_child(_main)
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_check(_main != null, "main 3D scene instantiates")
	_roster_3d = _main.get_node_or_null("MercenaryRoster3D")
	_morale_system = _main.get_node_or_null("MoraleSystem3D")
	_morale_ui = _main.get_node_or_null("HUD/MoraleUI")
	_check(_roster_3d != null, "MercenaryRoster3D wired")
	_check(_morale_system != null and _morale_system.state != null
		and _morale_system.bonus_hook != null,
		"MoraleSystem3D wired with MoraleState + MoraleBonusHook")
	_check(_morale_ui != null, "MoraleUI wired into HUD")
	_enter(Phase.HIRE)


func _hire() -> void:
	if _wait < 2:
		_wait += 1
		return
	_data_a = MercenaryData.new("m_a", "Alaric")
	_data_a.level = 5
	_data_a.attack_damage = 100
	_data_a.set_defense_zone(MercenaryData.DefenseZone.NORTH)
	_data_b = MercenaryData.new("m_b", "Bram")
	_data_b.level = 1
	_data_b.attack_damage = 100
	_data_b.set_defense_zone(MercenaryData.DefenseZone.WEST)
	_data_c = MercenaryData.new("m_c", "Cedric")
	_data_c.level = 3
	_data_c.attack_damage = 100
	_data_c.set_defense_zone(MercenaryData.DefenseZone.SOUTH)
	_check(_roster_autoload.add_mercenary(_data_a), "hire mercenary A (level 5)")
	_check(_roster_autoload.add_mercenary(_data_b), "hire mercenary B (level 1)")
	_check(_roster_autoload.add_mercenary(_data_c), "hire mercenary C (level 3)")
	_enter(Phase.HIRE_CHECK)


## hire가 3D roster로 이월되고 morale system이 갱신됐는지 확인.
func _hire_check() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_check(_roster_3d.get_mercenary("m_a") != null
		and _roster_3d.get_mercenary("m_b") != null
		and _roster_3d.get_mercenary("m_c") != null,
		"hires bridge into MercenaryRoster3D")
	_morale_system._refresh()
	var st: MoraleState = _morale_system.state
	# level 1=1.0 + 3=1.5 + 5=2.0 = 4.5
	_check(absf(st.get_total_morale() - 4.5) < 0.0001,
		"current morale = 4.5 (roster identity)")
	_check(st.get_active_contributor_count() == 3,
		"three active contributors counted")
	var major := st.get_major_contributors(2)
	_check(major.size() == 2 and major[0].mercenary_id == "m_a"
		and major[1].mercenary_id == "m_c",
		"major contributors ordered by descending contribution")
	var mult: float = _morale_system.bonus_hook.get_attack_multiplier()
	_check(absf(mult - (1.0 + 4.5 * MoraleBonusHook.ATTACK_BONUS_PER_UNIT)) < 0.0001,
		"bonus multiplier derived from current morale")
	_check(mult > 1.0, "positive morale yields a bonus > 1.0")
	_check_ui_matches("4.5", "+23%", ["Alaric Lv.5 (+2.0)", "Cedric Lv.3 (+1.5)"],
		"UI shows current morale / major contributors / bonus after hire")
	_enter(Phase.TO_NIGHT)


func _to_night() -> void:
	_advance_to_next_phase()
	_enter(Phase.NIGHT_WAIT)


func _advance_to_next_phase() -> void:
	var current: int = _game_time.get_phase()
	var guard := 0
	while _game_time.get_phase() == current and guard < 100:
		_game_time.advance(1.0)
		guard += 1


func _night_wait() -> void:
	_wait += 1
	if _wait >= SETTLE_FRAMES:
		_enter(Phase.NIGHT_CHECK)


func _night_check() -> void:
	_check(_game_time.get_phase_name() == "NIGHT", "phase advanced to NIGHT")
	_check(_morale_system.state.get_total_morale() == 4.5,
		"morale stays 4.5 at NIGHT (deployment records no death)")
	# bonus hook가 spawn Actor에 적용됐는지 확인(멱등 중복 없음).
	var actor: Node = _roster_3d.get_actor("m_a")
	_check(actor != null and actor.has_method("get_morale_multiplier"),
		"a zone-assigned actor is spawned at NIGHT")
	if actor != null and actor.has_method("get_morale_multiplier"):
		var expected: float = _morale_system.bonus_hook.get_attack_multiplier()
		_check(absf(actor.get_morale_multiplier() - expected) < 0.0001,
			"spawned actor receives the global morale bonus multiplier")
		_check(_morale_system.bonus_hook.get_active_count() >= 1,
			"actor is subscribed to the bonus hook (idempotent)")
	_enter(Phase.LETHAL)


## NIGHT lethal death: m_a 사망 -> 총 사기/보너스 감소 확인.
func _lethal() -> void:
	if _wait < 2:
		_wait += 1
		return
	_morale_before = _morale_system.state.get_total_morale()
	_bonus_before = _morale_system.bonus_hook.get_attack_multiplier()
	var actor: Node = _roster_3d.get_actor("m_a")
	if actor != null and is_instance_valid(actor) and actor.has_method("die"):
		actor.die()
	_enter(Phase.LETHAL_CHECK)


func _lethal_check() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_check(_data_a.alive == false, "lethal death marks mercenary data dead")
	var after: float = _morale_system.state.get_total_morale()
	_check(after < _morale_before, "NIGHT lethal death lowers current morale")
	# 남은 기여: m_b(1.0) + m_c(1.5) = 2.5
	_check(absf(after - 2.5) < 0.0001,
		"dead contributor contributes 0 -> morale 2.5")
	var after_bonus: float = _morale_system.bonus_hook.get_attack_multiplier()
	_check(after_bonus < _bonus_before, "morale drop lowers the attack bonus")
	_check_ui_matches("2.5", "+13%", ["Cedric Lv.3 (+1.5)", "Bram Lv.1 (+1.0)"],
		"UI reflects morale drop after NIGHT lethal death")
	_enter(Phase.TO_DAY)


func _to_day() -> void:
	_advance_to_next_phase()
	_enter(Phase.DAY_WAIT)


func _day_wait() -> void:
	_wait += 1
	if _wait >= SETTLE_FRAMES:
		_enter(Phase.DAY_CHECK)


## DAY 복귀 후 일관성: despawn돼도 사기 상태/상수는 유지되고, 보너스는 다음 cycle 재적용.
func _day_check() -> void:
	_check(_game_time.get_phase_name() == "DAY", "phase returned to DAY")
	_check(_roster_3d.get_actor_count() == 0,
		"DAY despawns all 3D actors (no orphan)")
	_check(absf(_morale_system.state.get_total_morale() - 2.5) < 0.0001,
		"morale is consistent after DAY return (2.5)")
	# DAY 복귀 후에도 보너스 수식은 동일하게 유도된다(스냅샷/누적 없음).
	var day_bonus: float = _morale_system.bonus_hook.get_attack_multiplier()
	_check(absf(day_bonus - (1.0 + 2.5 * MoraleBonusHook.ATTACK_BONUS_PER_UNIT)) < 0.0001,
		"bonus stays derived from morale after DAY return (no drift)")
	# 다음 NIGHT에 사망자 제외, 생존자만 spawn/보너스 재적용.
	_advance_to_next_phase()
	_check(_game_time.get_phase_name() == "NIGHT", "re-enters NIGHT for the next cycle")
	_check(_roster_3d.get_actor("m_a") == null,
		"dead mercenary does not redeploy on the next NIGHT")
	var b_actor: Node = _roster_3d.get_actor("m_b")
	if b_actor != null and b_actor.has_method("get_morale_multiplier"):
		var reapply: float = _morale_system.bonus_hook.get_attack_multiplier()
		_check(absf(b_actor.get_morale_multiplier() - reapply) < 0.0001,
			"survivor actor receives re-applied bonus on the next NIGHT (idempotent)")
	_check(_morale_system.bonus_hook.get_active_count() <= 2,
		"bonus hook subscription count reflects only living contributors")
	_enter(Phase.CLEANUP)


func _cleanup() -> void:
	if _wait < 2:
		_wait += 1
		return
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	_enter(Phase.DONE)
