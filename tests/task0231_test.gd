extends SceneTree

## TASK-023-1 Morale State / Contributor Model 테스트.
## 기존 파일은 수정하지 않는 신규 task0231* 계열 테스트(POST-3D Feature queue).
## 고용된 MercenaryRoster(autoload)의 roster data로부터 roster identity 기준 사기
## 기여자를 계산하고, contributor 변화/사망/ghost 제외/중복 방지가 동작하는지 검증한다.
##
## 완료조건 매핑:
##   - contributor 변화 -> morale 재계산.
##   - death -> 적절한 변화(사망 contributor 기여 0 반영 -> 총 사기 감소).
##   - duplicate count 없음: 같은 id contributor는 정확히 1개(roster identity 기준).

var _frame := 0
var _phase := 0
var _failed := false
var _roster: Node = null
var _state: MoraleState = null
var _changed_count := 0

var _data_a: MercenaryData = null
var _data_b: MercenaryData = null
var _data_c: MercenaryData = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _finish() -> void:
	print("TASK0231_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		0:
			_setup()
		1:
			_test_contributors()
		2:
			_test_death_recompute()
		3:
			_test_ghost_excluded()
		4:
			_test_duplicate_identity()
		5:
			_finish()
			return true
	if _frame > 2000:
		print("TASK0231_RESULT=TIMEOUT phase=%d" % _phase)
		quit()
		return true
	return false


func _setup() -> void:
	if _frame < 6:
		return
	_roster = root.get_node_or_null("MercenaryRoster")
	_check(_roster != null, "MercenaryRoster autoload is available")
	if _roster == null:
		_phase = 5
		return
	_state = MoraleState.new()
	_state.morale_changed.connect(func(): _changed_count += 1)
	_data_a = MercenaryData.new("m_a", "Alaric")
	_data_a.level = 5
	_data_b = MercenaryData.new("m_b", "Bram")
	_data_b.level = 1
	_data_c = MercenaryData.new("m_c", "Cedric")
	_data_c.level = 3
	_check(_roster.add_mercenary(_data_a), "hire mercenary A (level 5)")
	_check(_roster.add_mercenary(_data_b), "hire mercenary B (level 1)")
	_check(_roster.add_mercenary(_data_c), "hire mercenary C (level 3)")
	_phase = 1


func _test_contributors() -> void:
	# 전체 roster data 기준 계산.
	_state.refresh_from_mercenaries(_roster.get_mercenaries())
	_check(_state.get_contributor_count() == 3, "three roster identities become contributors")
	_check(_state.get_active_contributor_count() == 3, "all three contributors are active")
	# level 1 = 1.0, level 3 = 1.5, level 5 = 2.0 -> total 4.5
	_check(absf(_state.get_total_morale() - 4.5) < 0.0001,
		"total morale = sum of level-based contributions (4.5)")
	var major := _state.get_major_contributors(2)
	_check(major.size() == 2 and major[0].mercenary_id == "m_a"
		and major[1].mercenary_id == "m_c",
		"major contributors are ordered by descending contribution")
	_phase = 2


func _test_death_recompute() -> void:
	var before := _changed_count
	# contributor 변화(레벨 상승) -> 재계산.
	_data_a.level = 6
	_state.refresh_from_mercenaries(_roster.get_mercenaries())
	_check(_changed_count > before, "contributor change triggers morale recompute signal")
	_check(absf(_state.get_total_morale() - 4.75) < 0.0001,
		"level-up contributor raises total morale (4.75)")
	# 사망 -> 기여 0 반영 -> 총 사기 감소.
	var before_death := _state.get_total_morale()
	_data_a.alive = false
	_state.refresh_from_mercenaries(_roster.get_mercenaries())
	var after := _state.get_total_morale()
	_check(after < before_death, "mercenary death lowers total morale")
	_check(absf(after - 2.5) < 0.0001,
		"dead contributor contributes 0 (remaining 1.0 + 1.5 = 2.5)")
	_check(_state.get_active_contributor_count() == 2,
		"dead mercenary is no longer an active contributor")
	_phase = 3


func _test_ghost_excluded() -> void:
	# ghost(원본 생존자가 아닌 망령) contributor는 원본 생존자로 계산하지 않는다.
	# 현재 Ghost system이 없어 MercenaryData에는 is_ghost 필드가 없으므로, 모델이
	# is_ghost key를 읽는 데이터 소스(Dictionary)로 ghost contributor를 재현한다.
	var ghost := {
		"id": "m_a",
		"display_name": "Alaric",
		"level": 6,
		"alive": true,
		"is_ghost": true,
	}
	_state.refresh_from_mercenaries([ghost, _data_b, _data_c])
	_check(absf(_state.get_total_morale() - 2.5) < 0.0001,
		"ghost contributor is not counted as an original survivor (2.5)")
	_check(_state.get_active_contributor_count() == 2,
		"ghost is excluded from active contributor count")
	_check(_state.get_contributor("m_a").is_ghost == true,
		"ghost identity flag is carried on the contributor")
	_phase = 4


func _test_duplicate_identity() -> void:
	# 같은 id의 contributor가 여러 번 들어와도 roster identity 기준 1개만 유지.
	var dup := {
		"id": "m_b",
		"display_name": "Bram Clone",
		"level": 99,
		"alive": true,
		"is_ghost": false,
	}
	_state.refresh_from_mercenaries([_data_b, dup, _data_b])
	_check(_state.get_contributor_count() == 1, "same roster identity counts once (no duplicate)")
	_check(_state.get_contributor("m_b") != null, "identity is keyed by mercenary_id")
	_phase = 5
